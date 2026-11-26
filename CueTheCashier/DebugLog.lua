-- CueTheCashier: debug log and debug window.
-- When debug mode is on (/cmp debug), every CueTheCashier chat message plus
-- detailed diagnostics go into a log. /cmp log opens a window where the text
-- can be selected and copied (click in the text, Ctrl+A, Ctrl+C).
-- Copyright (C) 2026 Kim. Licensed under the GNU GPL v3 or later; see LICENSE.
local _, CM = ...

local MAX_LINES = 1000
local lines = {}
local window
local paused = false -- while paused the window keeps its text, so it can be copied

local function IsDebug()
  return CueTheCashierDB and CueTheCashierDB.settings and CueTheCashierDB.settings.debug
end
CM.IsDebug = IsDebug

-- Searches (browse pages, item lookups) make hundreds of log lines; they
-- are only logged with /cmp debug verbose. Buying, posting and errors are
-- always logged in debug mode.
local function IsVerbose()
  return CueTheCashierDB and CueTheCashierDB.settings and CueTheCashierDB.settings.debugVerbose
end
local NOISY = {
  AUCTION_HOUSE_BROWSE_RESULTS_UPDATED = true, AUCTION_HOUSE_BROWSE_RESULTS_ADDED = true,
  COMMODITY_SEARCH_RESULTS_UPDATED = true, COMMODITY_SEARCH_RESULTS_ADDED = true,
  ITEM_SEARCH_RESULTS_UPDATED = true, ITEM_SEARCH_RESULTS_ADDED = true,
  ITEM_KEY_ITEM_INFO_RECEIVED = true, REPLICATE_ITEM_LIST_UPDATE = true, AUCTION_HOUSE_THROTTLED_SYSTEM_READY = true,
  AUCTION_HOUSE_THROTTLED_MESSAGE_SENT = true, AUCTION_HOUSE_THROTTLED_MESSAGE_RESPONSE_RECEIVED = true,
}
local function IsNoisyLabel(label)
  return label:find("Search") or label:find("Browse") or label:find("RequestMore")
end

-- Turns any value into readable text, including tables (one level of nesting
-- per depth step), so raw API replies can be logged.
local function Dump(v, depth)
  depth = depth or 2
  if type(v) == "string" then return ("%q"):format(v) end
  if type(v) ~= "table" then return tostring(v) end
  if depth <= 0 then return "{...}" end
  local parts = {}
  for k, val in pairs(v) do
    parts[#parts + 1] = tostring(k) .. "=" .. Dump(val, depth - 1)
  end
  table.sort(parts)
  return "{" .. table.concat(parts, ", ") .. "}"
end
CM.Dump = Dump

local function Refresh()
  if window and window:IsShown() and not paused then
    window.edit:SetText(table.concat(lines, "\n"))
    -- Jump to the newest line.
    C_Timer.After(0, function()
      window.scroll:SetVerticalScroll(window.scroll:GetVerticalScrollRange())
    end)
  end
end

-- Adds a line to the log. Extra arguments are dumped, so
-- CM.Debug("result", tbl) shows the table.
local function Append(msg, ...)
  local text = tostring(msg)
  for i = 1, select("#", ...) do
    text = text .. " " .. Dump((select(i, ...)))
  end
  lines[#lines + 1] = date("%H:%M:%S") .. "  " .. text
  if #lines > MAX_LINES then table.remove(lines, 1) end
  Refresh()
end

-- Logs only while debug mode is on.
function CM.Debug(msg, ...)
  if IsDebug() then Append(msg, ...) end
end

-- Like CM.Debug, but written even when debug mode is off. For reports a
-- command was asked to make (e.g. /cmp prof), so they can be copied from
-- /cmp log.
function CM.Log(msg, ...) Append(msg, ...) end

local function Build()
  local skin = CM.Skins:Get()
  -- GUESS: BasicFrameTemplateWithInset exists in the 12.x client, as on retail.
  local f = CreateFrame("Frame", "CueTheCashierDebugFrame", UIParent, skin.windowTemplate)
  CM.Skins:ApplyWindow(f)
  f:SetSize(620, 380)
  f:SetPoint("CENTER")
  f:SetFrameStrata("DIALOG")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:SetClampedToScreen(true)
  CM.CloseOnEscape(f) -- Escape closes it (see Core.lua)

  local top = CM.Skins:SetupWindow(f, "CueTheCashier Debug Log")
  f:SetHeight(380 + top - 30)
  CM.Skins:AddInset(f, 6, top - 2, 6, 36)

  local scroll = CreateFrame("ScrollFrame", "CueTheCashierDebugScroll", f, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 12, -(top + 2))
  scroll:SetPoint("BOTTOMRIGHT", -32, 40)
  f.scroll = scroll

  local edit = CreateFrame("EditBox", nil, scroll)
  edit:SetMultiLine(true)
  edit:SetAutoFocus(false)
  edit:SetFontObject(skin.fontLog)
  edit:SetWidth(570)
  edit:SetScript("OnEscapePressed", function(self) self:ClearFocus(); f:Hide() end)
  -- Read only: typing puts the log text back.
  edit:SetScript("OnTextChanged", function(self, userInput)
    if userInput then self:SetText(table.concat(lines, "\n")) end
  end)
  scroll:SetScrollChild(edit)
  f.edit = edit

  local selectAll = CreateFrame("Button", nil, f, skin.buttonTemplate)
  selectAll:SetSize(110, 22)
  selectAll:SetPoint("BOTTOMLEFT", 12, 10)
  selectAll:SetText("Select All")
  selectAll:SetScript("OnClick", function()
    edit:SetFocus()
    edit:HighlightText()
  end)

  local clear = CreateFrame("Button", nil, f, skin.buttonTemplate)
  clear:SetSize(80, 22)
  clear:SetPoint("LEFT", selectAll, "RIGHT", 6, 0)
  clear:SetText("Clear")
  clear:SetScript("OnClick", function() wipe(lines); edit:SetText("") end)

  -- Pause: stop the window from updating (the log keeps recording), so a
  -- busy search can't scroll the text away while you copy it.
  local pause = CreateFrame("Button", nil, f, skin.buttonTemplate)
  pause:SetSize(80, 22)
  pause:SetPoint("LEFT", clear, "RIGHT", 6, 0)
  pause:SetText("Pause")
  pause:SetScript("OnClick", function(b)
    paused = not paused
    b:SetText(paused and "Resume" or "Pause")
    if not paused then Refresh() end
  end)

  local hint = f:CreateFontString(nil, "OVERLAY", skin.fontSmall)
  hint:SetPoint("LEFT", pause, "RIGHT", 10, 0)
  hint:SetText("Pause, Select All, then Ctrl+C to copy.")

  f:SetScript("OnShow", Refresh)
  f:Hide()
  return f
end

function CM.ShowDebugWindow()
  window = window or Build()
  window:Show()
  Refresh()
end

function CM.ToggleDebugWindow()
  if window and window:IsShown() then window:Hide() else CM.ShowDebugWindow() end
end

-- Event spy: while debug mode is on, log every auction house event the
-- client sends, with its arguments. Unknown event names are logged too,
-- which tells us what this client does not have.
local SPY_EVENTS = {
  "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "AUCTION_HOUSE_SHOW_ERROR",
  "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", "AUCTION_HOUSE_BROWSE_RESULTS_ADDED",
  "COMMODITY_SEARCH_RESULTS_UPDATED", "COMMODITY_SEARCH_RESULTS_ADDED",
  "ITEM_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_ADDED",
  "ITEM_KEY_ITEM_INFO_RECEIVED", "REPLICATE_ITEM_LIST_UPDATE",
  "AUCTION_HOUSE_THROTTLED_SYSTEM_READY", "AUCTION_HOUSE_THROTTLED_MESSAGE_SENT",
  "AUCTION_HOUSE_THROTTLED_MESSAGE_RESPONSE_RECEIVED",
  "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED", "AUCTION_HOUSE_THROTTLED_MESSAGE_QUEUED",
  "UI_ERROR_MESSAGE",
  -- Buying: always logged.
  "COMMODITY_PRICE_UPDATED", "COMMODITY_PRICE_UNAVAILABLE", "COMMODITY_PURCHASE_SUCCEEDED",
  "COMMODITY_PURCHASE_FAILED", "AUCTION_HOUSE_PURCHASE_COMPLETED",
  "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN",
}
local spy = CreateFrame("Frame")
spy:SetScript("OnEvent", function(_, event, ...)
  if NOISY[event] and not IsVerbose() then return end
  local args = {}
  for i = 1, select("#", ...) do args[#args + 1] = Dump((select(i, ...))) end
  CM.Debug("EVENT " .. event .. "(" .. table.concat(args, ", ") .. ")")
end)

function CM.UpdateEventSpy()
  if IsDebug() then
    for _, e in ipairs(SPY_EVENTS) do
      if not pcall(spy.RegisterEvent, spy, e) then
        CM.Debug("Event not known by this client: " .. e)
      end
    end
  else
    spy:UnregisterAllEvents()
  end
end

-- Calls a game function, logs what it returned or the error it threw, and
-- returns ok plus the results. Used for every API call in the debug scan so
-- a crash shows up in the log instead of being hidden by WoW.
local function TryResult(label, ok, ...)
  if not ok then
    CM.Debug(label .. " ERROR: " .. tostring((...)))
    return false
  end
  if IsNoisyLabel(label) and not IsVerbose() then return true, ... end
  local out = {}
  for i = 1, select("#", ...) do out[#out + 1] = Dump((select(i, ...))) end
  CM.Debug(label .. " -> " .. (#out > 0 and table.concat(out, ", ") or "nothing"))
  return true, ...
end

function CM.Try(label, fn, ...)
  if type(fn) ~= "function" then
    CM.Debug(label .. " ERROR: function does not exist")
    return false
  end
  return TryResult(label, pcall(fn, ...))
end

-- Logs the client build and which auction house functions exist.
function CM.LogEnvironment()
  local version, build, _, toc = GetBuildInfo()
  CM.Debug(("Client %s build %s, interface %s. CueTheCashier %s."):format(
    tostring(version), tostring(build), tostring(toc), CM.version))
  local missing = {}
  for _, fn in ipairs({ "ReplicateItems", "GetNumReplicateItems", "GetReplicateItemInfo",
      "MakeItemKey", "SendSearchQuery", "IsThrottledMessageSystemReady",
      "GetNumCommoditySearchResults", "GetCommoditySearchResultInfo",
      "GetNumItemSearchResults", "GetItemSearchResultInfo", "GetItemCommodityStatus" }) do
    if not (C_AuctionHouse and C_AuctionHouse[fn]) then missing[#missing + 1] = fn end
  end
  CM.Debug(#missing == 0 and "All C_AuctionHouse functions found."
    or ("MISSING C_AuctionHouse functions: " .. table.concat(missing, ", ")))
  -- Old 2004-style auction functions, in case Forever kept them.
  CM.Debug(("Old-style API: QueryAuctionItems=%s, GetNumAuctionItems=%s"):format(
    tostring(type(QueryAuctionItems) == "function"), tostring(type(GetNumAuctionItems) == "function")))
end

-- Logs every auction house request, including the ones Blizzard's own AH
-- window sends. Search for something by hand with debug on, and the log
-- shows exactly what a working request looks like on this client.
local HOOKED = { "SendBrowseQuery", "SendSearchQuery", "SendSellSearchQuery",
  "ReplicateItems", "RefreshCommoditySearchResults", "RefreshItemSearchResults",
  "SearchForFavorites", "RequestMoreBrowseResults", "RequestMoreCommoditySearchResults",
  "RequestMoreItemSearchResults" }
if C_AuctionHouse and hooksecurefunc then
  for _, name in ipairs(HOOKED) do
    if type(C_AuctionHouse[name]) == "function" then
      hooksecurefunc(C_AuctionHouse, name, function(...)
        if not (IsDebug() and IsVerbose()) then return end
        local args = {}
        for i = 1, select("#", ...) do args[#args + 1] = Dump((select(i, ...)), 3) end
        CM.Debug("CALL C_AuctionHouse." .. name .. "(" .. table.concat(args, ", ") .. ")")
      end)
    end
  end
end

-- When Blizzard blocks something CueTheCashier called ("Interface action
-- failed because of an AddOn"), say which function it was, always (not
-- only in debug mode), so it can be reported and fixed.
local blocked = CreateFrame("Frame")
for _, e in ipairs({ "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN" }) do
  pcall(blocked.RegisterEvent, blocked, e)
end
CM.blockedLines = {}
blocked:SetScript("OnEvent", function(_, event, addon, func)
  -- Any addon of the suite (CueTheCashier, CueTheCashier_Auctioning, ...).
  if type(addon) ~= "string" or not addon:find("^CueTheCashier") then return end
  CM.blockedCount = (CM.blockedCount or 0) + 1
  local msg = ("Blizzard blocked %s (%s, %s). Please send this line."):format(tostring(func), event, addon)
  table.insert(CM.blockedLines, date("%H:%M:%S") .. " " .. tostring(func) .. " (" .. event .. ", " .. addon .. ")")
  if #CM.blockedLines > 10 then table.remove(CM.blockedLines, 1) end
  -- This runs inside the blocked Blizzard call; printing to chat from here
  -- spreads the taint into the chat window. Log now, print a moment later.
  CM.Log(msg)
  if debugstack then CM.Log(debugstack(2, 12, 0)) end
  C_Timer.After(0, function() print("|cff33ff99CueTheCashier|r: " .. msg) end)
end)
