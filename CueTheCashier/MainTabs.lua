-- CueTheCashier: the core's tabs in the main window (MainWindow.lua):
--   Overview    boxes with the numbers that matter now. The core adds
--               Gold and Auction data, modules add their own boxes.
--   Groups      in GroupsTab.lua, Operations in OperationsTab.lua,
--   Prices      in PricesTab.lua
--   Settings    every setting of the core and the modules on one page
-- The Ledger tab comes from CueTheCashier_Accounting.
-- Copyright (C) 2026 Kim. Licensed under the GNU GPL v3 or later; see LICENSE.
local _, CM = ...
local API = CM.API
local MW = CM.MainWindow

local ROW = 18
local TOP = -64 -- below the title bar and the portrait

local function Money(c) return CM.FormatMoney(c or 0) end
local function Skin() return CM.Skins:Get() end

local function Header(page, text)
  local fs = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  fs:SetPoint("TOPLEFT", 70, -36)
  fs:SetPoint("RIGHT", page, "RIGHT", -20, 0)
  fs:SetJustifyH("LEFT")
  fs:SetText(text or "")
  return fs
end

-- ------------------------------------------------------------------
-- Gold on every character (account-wide, per server and faction).
-- CueTheCashierDB.gold["EU Normal - Alliance"]["Malaeiel"] = copper
-- ------------------------------------------------------------------
local function SaveGold()
  if not (CueTheCashierDB and GetMoney) then return end
  CueTheCashierDB.gold = CueTheCashierDB.gold or {}
  local key = CM:GetAuctionKey()
  CueTheCashierDB.gold[key] = CueTheCashierDB.gold[key] or {}
  local name = UnitName("player")
  if name then
    CueTheCashierDB.gold[key][name] = GetMoney()
    if CM.GoldHistory then CM.GoldHistory.Record(key, name, GetMoney()) end
  end
end
CM.RegisterEvent("Gold", "PLAYER_LOGIN", function() CM.Try("Save gold", SaveGold) end)
CM.RegisterEvent("Gold", "PLAYER_MONEY", function()
  CM.Try("Save gold", SaveGold)
  MW:Refresh()
end)

API.RegisterOverviewSection("gold", { title = "Gold", order = 10, lines = function()
  local all = (CueTheCashierDB.gold or {})[CM:GetAuctionKey()] or {}
  local me = UnitName("player")
  local list, total = {}, 0
  for name, copper in pairs(all) do
    total = total + copper
    if name ~= me then list[#list + 1] = { name = name, copper = copper } end
  end
  table.sort(list, function(a, b) return a.copper > b.copper end)
  local lines = {
    { left = "This character", right = Money(GetMoney()) },
    { left = ("All characters (%d)"):format(#list + 1), right = Money(total) },
  }
  for i = 1, math.min(#list, 4) do
    lines[#lines + 1] = { left = "|cffaaaaaa" .. list[i].name .. "|r", right = Money(list[i].copper) }
  end
  return lines
end })

API.RegisterOverviewSection("auction", { title = "Auction data", order = 20, lines = function()
  local data = CM:GetRealmData()
  local count = 0
  for _ in pairs(data.items) do count = count + 1 end
  return {
    { left = "Server", right = CM:GetAuctionKey() },
    { left = "Prices saved", right = tostring(count) },
    { left = "Last scan", right = (data.lastScan or 0) > 0 and date("%d %b %H:%M", data.lastScan) or "never" },
    { left = "Full scan ready", right = CM.FullScanCooldownText() },
  }
end })

-- ------------------------------------------------------------------
-- Overview tab
-- ------------------------------------------------------------------
local SMALL_HEIGHT, GAP, SIDE = 146, 8, 12

local function Box(page, i)
  local b = page.boxes[i]
  if b then return b end
  b = CreateFrame("Frame", nil, page, Skin().insetTemplate)
  b.title = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  b.title:SetPoint("TOPLEFT", 10, -8)
  b.empty = b:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  b.empty:SetPoint("TOPLEFT", 10, -10 - ROW)
  b.empty:SetText("Nothing yet.")
  b.rows = {}
  page.boxes[i] = b
  return b
end

local function Row(box, i)
  local r = box.rows[i]
  if r then return r end
  r = CreateFrame("Button", nil, box)
  r:SetHeight(ROW)
  local y = -8 - ROW * i
  r:SetPoint("TOPLEFT", 10, y)
  r:SetPoint("TOPRIGHT", -10, y)
  r.right = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  r.right:SetPoint("RIGHT")
  r.right:SetJustifyH("RIGHT")
  r.left = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  r.left:SetPoint("LEFT")
  r.left:SetPoint("RIGHT", r.right, "LEFT", -6, 0)
  r.left:SetJustifyH("LEFT")
  r.left:SetWordWrap(false)
  r:SetScript("OnEnter", function(self)
    if self.itemID then CM.ShowItemTooltip(self, { itemID = self.itemID }) end
  end)
  r:SetScript("OnLeave", GameTooltip_Hide)
  box.rows[i] = r
  return r
end

local function FillBox(box, section, height)
  box.title:SetText(section.title)
  local ok, lines = pcall(section.lines)
  if not ok then
    CM.Debug("Overview " .. section.key .. " ERROR: " .. tostring(lines))
    lines = { { left = "|cffff2020Error, see /cmp log|r" } }
  end
  lines = type(lines) == "table" and lines or {}
  local fits = math.max(1, math.floor((height - 14) / ROW) - 1)
  for _, r in ipairs(box.rows) do r:Hide() end
  for i = 1, math.min(#lines, fits) do
    local r, l = Row(box, i), lines[i]
    r.left:SetText(l.left or "")
    r.right:SetText(l.right or "")
    r.itemID = l.itemID
    r:Show()
  end
  box.empty:SetShown(#lines == 0)
end

local function ShowOverview(page)
  local name = UnitName("player")
  page.header:SetText(("%s, %s"):format(name or "?", CM:GetAuctionKey()))
  local small, wide = {}, {}
  for _, s in ipairs(MW.Sorted(MW.sections)) do
    if s.wide then wide[#wide + 1] = s else small[#small + 1] = s end
  end
  for _, b in ipairs(page.boxes) do b:Hide() end
  local width = MW.WIDTH - 2 * SIDE
  local n, y = 0, TOP
  -- Small boxes three to a row, then wide boxes two to a row in what is left.
  local function Place(list, perRow, height)
    local w = (width - GAP * (perRow - 1)) / perRow
    for i, s in ipairs(list) do
      local col = (i - 1) % perRow
      if col == 0 and i > 1 then y = y - height - GAP end
      n = n + 1
      local b = Box(page, n)
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", SIDE + col * (w + GAP), y)
      b:SetSize(w, height)
      FillBox(b, s, height)
      b:Show()
    end
    if #list > 0 then y = y - height - GAP end
  end
  Place(small, 3, SMALL_HEIGHT)
  local wideRows = math.ceil(#wide / 2)
  if wideRows > 0 then
    local left = MW.HEIGHT + y - SIDE -- y is negative
    Place(wide, 2, math.max(ROW * 3, (left - GAP * (wideRows - 1)) / wideRows))
  end
end

API.RegisterMainTab("overview", { title = "Overview", order = 10,
  build = function(page)
    page.boxes = {}
    page.header = Header(page)
  end,
  show = ShowOverview,
})

-- ------------------------------------------------------------------
-- Settings tab
-- ------------------------------------------------------------------
local SETTING_ROW = 28
local COLUMN_X = { 20, 420 }

local function SettingTooltip(owner, s)
  if not s.tooltip then return end
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  GameTooltip:AddLine(s.label, 1, 1, 1)
  GameTooltip:AddLine(s.tooltip, nil, nil, nil, true)
  GameTooltip:Show()
end

local function Get(s)
  local ok, v = pcall(s.get)
  if ok then return v end
  CM.Debug("Setting " .. tostring(s.label) .. " ERROR: " .. tostring(v))
end

local function Set(s, v)
  local ok, err = pcall(s.set, v)
  if not ok then CM.Debug("Setting " .. tostring(s.label) .. " ERROR: " .. tostring(err)) end
end

local function MakeToggle(page, s)
  local skin = Skin()
  local w = CreateFrame("CheckButton", nil, page, skin.checkTemplate)
  w:SetSize(26, 26)
  w.label = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  w.label:SetPoint("LEFT", w, "RIGHT", 4, 1)
  w.label:SetWidth(340)
  w.label:SetJustifyH("LEFT")
  w.label:SetWordWrap(false)
  w.label:SetText(s.label)
  w:SetScript("OnClick", function(b) Set(s, b:GetChecked() and true or false); MW:Refresh() end)
  w:SetScript("OnEnter", function(b) SettingTooltip(b, s) end)
  w:SetScript("OnLeave", GameTooltip_Hide)
  w.Update = function(self) self:SetChecked(Get(s) and true or false) end
  w.Place = function(self, x, y) self:ClearAllPoints(); self:SetPoint("TOPLEFT", x, y) end
  return w
end

-- A button showing the chosen option; click for a menu of s.options
-- ({ { value, text }, ... }).
local function MakeChoice(page, s)
  local skin = Skin()
  local w = CreateFrame("Button", nil, page, skin.buttonTemplate)
  w:SetSize(90, 22)
  w.label = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  w.label:SetPoint("LEFT", w, "RIGHT", 8, 0)
  w.label:SetWidth(280)
  w.label:SetJustifyH("LEFT")
  w.label:SetWordWrap(false)
  w.label:SetText(s.label)
  local function Options() return type(s.options) == "function" and s.options() or s.options end
  local function Text(v)
    for _, o in ipairs(Options()) do if o[1] == v then return o[2] end end
    return Options()[1][2]
  end
  w.Update = function(self) self:SetText(Text(Get(s))) end
  w:SetScript("OnClick", function(self)
    if MenuUtil and MenuUtil.CreateContextMenu then
      MenuUtil.CreateContextMenu(self, function(_, root)
        for _, o in ipairs(Options()) do
          root:CreateRadio(o[2], function() return Get(s) == o[1] end,
            function() Set(s, o[1]); self:Update() end)
        end
      end)
    else
      -- No menu API: step to the next option.
      local opts, cur, nextIndex = Options(), Get(s), 1
      for i, o in ipairs(opts) do if o[1] == cur then nextIndex = i % #opts + 1 end end
      Set(s, opts[nextIndex][1]); self:Update()
    end
  end)
  w:SetScript("OnEnter", function(b) SettingTooltip(b, s) end)
  w:SetScript("OnLeave", GameTooltip_Hide)
  w.Place = function(self, x, y) self:ClearAllPoints(); self:SetPoint("TOPLEFT", x + 2, y - 2) end
  return w
end

local function MakeNumber(page, s)
  local skin = Skin()
  local w = CreateFrame("EditBox", nil, page, skin.inputTemplate)
  w:SetSize(44, 22)
  w:SetAutoFocus(false)
  w:SetNumeric(true)
  w:SetMaxLetters(#tostring(s.max or 9999))
  CM.Skins:StyleInput(w)
  w.label = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  w.label:SetPoint("LEFT", w, "RIGHT", 8, 0)
  w.label:SetWidth(320)
  w.label:SetJustifyH("LEFT")
  w.label:SetWordWrap(false)
  w.label:SetText(s.label)
  w.Update = function(self) self:SetText(tostring(Get(s) or "")) end
  local function Save(self)
    local v = tonumber(self:GetText())
    if v and (not s.min or v >= s.min) and (not s.max or v <= s.max) then Set(s, v) end
    self:Update() -- a number out of range goes back to the saved one
  end
  w:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  w:SetScript("OnEditFocusLost", Save)
  w:SetScript("OnEscapePressed", function(self) self:Update(); self:ClearFocus() end)
  w:SetScript("OnEnter", function(b) SettingTooltip(b, s) end)
  w:SetScript("OnLeave", GameTooltip_Hide)
  -- The input box's border sticks out a little to the left.
  w.Place = function(self, x, y) self:ClearAllPoints(); self:SetPoint("TOPLEFT", x + 8, y - 2) end
  return w
end

-- Profile row: which profile this character uses, and what to do with it.
local function ProfileMenu(owner)
  local P = CM.Profiles
  if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
  MenuUtil.CreateContextMenu(owner, function(_, root)
    root:CreateTitle("Use profile")
    for _, name in ipairs(P.Names()) do
      root:CreateRadio(name, function() return P.Current() == name end, function() P.Use(name); MW:Refresh() end)
    end
    local others = {}
    for _, name in ipairs(P.Names()) do if name ~= P.Current() then others[#others + 1] = name end end
    if #others > 0 then
      local copy = root:CreateButton("Copy from")
      for _, name in ipairs(others) do
        copy:CreateButton(name, function()
          CM.Confirm(("Replace everything in profile \"%s\" with a copy of \"%s\"?"):format(P.Current(), name),
            function() P.CopyFrom(name); MW:Refresh() end)
        end)
      end
    end
    root:CreateButton("Reset this profile", function()
      CM.Confirm(("Empty profile \"%s\"? Its groups, operations, custom prices and settings are removed."):format(P.Current()),
        function() P.Reset(); MW:Refresh() end)
    end)
    if P.Current() ~= P.Default() then
      root:CreateButton("Delete this profile", function()
        CM.Confirm(("Delete profile \"%s\"? Characters using it go back to their server's own profile."):format(P.Current()),
          function() P.Delete(P.Current()); MW:Refresh() end)
      end)
    end
  end)
end

local function BuildProfileRow(page)
  local skin = Skin()
  local row = CreateFrame("Frame", nil, page)
  row:SetPoint("TOPLEFT", 20, TOP - 4)
  row:SetSize(760, 26)
  local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  label:SetPoint("LEFT", 0, 0)
  label:SetText("Profile")
  local choose = CreateFrame("Button", nil, row, skin.buttonTemplate)
  choose:SetSize(170, 22)
  choose:SetPoint("LEFT", label, "RIGHT", 12, 0)
  choose:SetScript("OnClick", function(b) ProfileMenu(b) end)
  choose:SetScript("OnEnter", function(b)
    GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Profile", 1, 1, 1)
    GameTooltip:AddLine("Groups, operations, custom prices and the settings below are saved in a profile. Pick which one this character uses, copy another into it, reset or delete it.", nil, nil, nil, true)
    local users = CM.Profiles.UsedBy(CM.Profiles.Current())
    if #users > 0 then GameTooltip:AddLine("Used by: " .. table.concat(users, ", "), 0.7, 0.7, 0.7, true) end
    GameTooltip:Show()
  end)
  choose:SetScript("OnLeave", GameTooltip_Hide)
  local box = CreateFrame("EditBox", nil, row, skin.inputTemplate)
  box:SetSize(150, 22)
  box:SetAutoFocus(false)
  box:SetMaxLetters(40)
  CM.Skins:StyleInput(box)
  box:SetPoint("LEFT", choose, "RIGHT", 30, 0)
  local new = CreateFrame("Button", nil, row, skin.buttonTemplate)
  new:SetSize(150, 22)
  new:SetPoint("LEFT", box, "RIGHT", 8, 0)
  new:SetText("New Profile")
  local err = row:CreateFontString(nil, "OVERLAY", "GameFontRedSmall")
  err:SetPoint("LEFT", new, "RIGHT", 10, 0)
  local function Make()
    local ok, msg = CM.Profiles.New(box:GetText())
    err:SetText(ok and "" or (msg or ""))
    if ok then box:SetText(""); box:ClearFocus(); MW:Refresh() end
  end
  new:SetScript("OnClick", Make)
  new:SetScript("OnEnter", function(b)
    GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
    GameTooltip:AddLine("New Profile", 1, 1, 1)
    GameTooltip:AddLine("Makes an empty profile with the name in the box and uses it for this character. Use Copy from (in the profile menu) to start from another one.", nil, nil, nil, true)
    GameTooltip:Show()
  end)
  new:SetScript("OnLeave", GameTooltip_Hide)
  box:SetScript("OnEnterPressed", Make)
  box:SetScript("OnEscapePressed", function(b) b:ClearFocus() end)
  row.Update = function()
    choose:SetText(CM.Profiles.Current() .. " |cff808080(change)|r")
  end
  page.profileRow, page.profileChoose, page.profileBox, page.profileNew = row, choose, box, new
  return row
end

local function ShowSettings(page)
  page.widgets = page.widgets or {}
  page.headers = page.headers or {}
  for _, h in ipairs(page.headers) do h:Hide() end
  if not page.profileRow then BuildProfileRow(page) end
  page.profileRow.Update()
  local y = { TOP - 46, TOP - 46 }
  for gi, g in ipairs(MW.Sorted(MW.settingGroups)) do
    if #g.settings > 0 then
      local col = (y[2] > y[1]) and 2 or 1
      local x = COLUMN_X[col]
      local h = page.headers[gi]
      if not h then
        h = page:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        page.headers[gi] = h
      end
      h:ClearAllPoints()
      h:SetPoint("TOPLEFT", x, y[col])
      h:SetText(g.title)
      h:Show()
      y[col] = y[col] - 24
      for _, s in ipairs(g.settings) do
        local w = page.widgets[s]
        if not w then
          local make = (s.type == "number" and MakeNumber) or (s.type == "choice" and MakeChoice) or MakeToggle
          w = make(page, s)
          page.widgets[s] = w
        end
        w:Place(x, y[col])
        w:Update()
        y[col] = y[col] - SETTING_ROW
      end
      y[col] = y[col] - 10
    end
  end
end

API.RegisterMainTab("settings", { title = "Settings", order = 90,
  build = function(page)
    Header(page, "General settings are for your whole account; the rest is saved in the profile. Hover a setting for more.")
  end,
  show = ShowSettings,
})

-- ------------------------------------------------------------------
-- The core's own settings
-- ------------------------------------------------------------------
local function S() return CM.Settings() end

API.RegisterSettings("general", { title = "General", order = 10, settings = {
  { type = "toggle", label = "Minimap button",
    tooltip = "The cash register button on the minimap edge. /cmp opens this window too.",
    get = function() return not S().hideMinimapButton end,
    set = function(v) CM.SetMinimapButtonShown(v) end },
  { type = "choice", label = "Skin (after /reload)",
    tooltip = "How CueTheCashier's windows and lists look. Blizzard is the game's own look. Make your own: see SKINS.md in the CueTheCashier folder.",
    options = function()
      local list = {}
      for _, name in ipairs(CM.Skins:List()) do list[#list + 1] = { name, name } end
      return list
    end,
    get = function() return S().skin or "Blizzard" end,
    set = function(v)
      if CM.Skins:Set(v) then CM.Print("Skin set to " .. v .. ". Type /reload to see it everywhere.") end
    end },
  { type = "toggle", label = "Debug mode",
    tooltip = "Writes a fuller debug log you can copy (/cmp log).",
    get = function() return S().debug end,
    set = function(v) CM.SetDebugMode(v) end },
  { type = "toggle", label = "Verbose debug log",
    tooltip = "Also logs every auction house search event and call. Makes very long logs.",
    get = function() return S().debugVerbose end,
    set = function(v) S().debugVerbose = v end },
} })

-- Tooltip lines (Tooltip.lua asks CM.TooltipLineShown).
local TOOLTIP_LINES = {
  { "min", "Min buyout", "Lowest buyout in the last scan." },
  { "market", "Market value", "Average of the cheapest part of the auctions in the last scan." },
  { "avg7", "7-day average", "Market value averaged over 7 days (needs 2 days of scans)." },
  { "avg30", "30-day average", "Market value averaged over 30 days." },
  { "saleRate", "Sale rate", "Share of your auctions of the item that sold on this server (needs 2)." },
  { "soldPerDay", "Sold per day", "How many you sold per day on this server, over the last 30 days." },
  { "region", "Region", "Market value, sale rate and sold per day over every server type and faction in your region, when your characters on another one saw the item." },
  { "disenchant", "Disenchant value", "What disenchanting the item is worth (estimate). Shown on items that bind when equipped, or on every item when this character knows Enchanting." },
  { "deMats", "Disenchant materials", "What the item disenchants into, with the chance of each." },
  { "groups", "Groups", "The groups the item is in. With several, they are listed by rank, the winner (rank 1) first, in green." },
}

function CM.TooltipLineShown(key)
  local hide = CueTheCashierDB and CueTheCashierDB.profiles and CM.ProfileSettings().tooltipHide
  return not (hide and hide[key])
end

local tooltipSettings = {}
for _, l in ipairs(TOOLTIP_LINES) do
  tooltipSettings[#tooltipSettings + 1] = { type = "toggle", label = l[2], tooltip = l[3],
    get = function() return CM.TooltipLineShown(l[1]) end,
    set = function(v)
      local ps = CM.ProfileSettings()
      ps.tooltipHide = ps.tooltipHide or {}
      ps.tooltipHide[l[1]] = (not v) or nil
    end }
end
API.RegisterSettings("tooltip", { title = "Item tooltips", order = 20, settings = tooltipSettings })

-- Auction house settings are kept in the core's saved settings, so they
-- show here before the Auctioning module has loaded.
API.RegisterSettings("auction", { title = "Auction house", order = 30, settings = {
  { type = "toggle", label = "Open Craft Trade at the auction house",
    tooltip = "Off: Blizzard's auction house window opens instead. The button next to the X switches too, and is remembered.",
    get = function() return CM.ProfileSettings().openCraftTrade ~= false end,
    set = function(v) CM.ProfileSettings().openCraftTrade = v end },
  { type = "toggle", label = "Share commodity prices across server types",
    tooltip = "Stackable items (commodities) seem to share one auction house across Normal, PvP, Roleplay and the other server types of your region. On: a scan on any character counts for all of them. Off: each server type uses only its own scans. Scans keep both, so switching loses nothing.",
    get = function() return CueTheCashierDB.settings.sharedCommodities ~= false end,
    set = function(v) CueTheCashierDB.settings.sharedCommodities = v end },
  { type = "number", label = "Snipe: % of market value", min = 1, max = 100,
    tooltip = "The Snipe tab reports new auctions at or under this share of the market value.",
    get = function() return tonumber(CM.ProfileSettings().snipePercent) or 60 end,
    set = function(v) CM.ProfileSettings().snipePercent = v end },
  { type = "choice", label = "One-key scroll wheel",
    tooltip = "Hold this key and scroll the mouse wheel to do the next step, one per scroll: accept a CueTheCashier confirm box, post or cancel the Post tab's next line, buy the selected deal, disenchant the Destroy list's top item. /cmp macro also makes a macro you can put on any key.",
    options = { { "off", "Off" }, { "CTRL", "Ctrl" }, { "ALT", "Alt" }, { "SHIFT", "Shift" } },
    get = function() return CM.OneKey and CM.OneKey.WheelModifier() or "off" end,
    set = function(v) if CM.OneKey then CM.OneKey.SetWheelModifier(v) end end },
} })
