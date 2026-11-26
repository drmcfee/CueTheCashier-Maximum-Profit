-- CueTheCashier: the Ledger tab of the CueTheCashier main window (since 0.23.0;
-- before that its own window). Opened with /cmp ledger or the Ledger tab.
-- Right-click a Bought or Sold line to delete it.
-- Three views, picked with the buttons at the top left:
--   Bought  - every purchase, newest first
--   Sold    - every sale (auction house and vendor), newest first
--   Profit  - one line per item: average buy and sell price, resale
--             profit per item, and profit, for today, 7 days or all time
--   Other   - repairs, postage, AH cut, lost deposits and trades (0.36)
-- Copyright (C) 2026 Kim. Licensed under the GNU GPL v3 or later; see LICENSE.
local _, ns = ...
local CM = CueTheCashier
local API = CM.API

local LedgerUI = {}
ns.LedgerUI = LedgerUI

local ROW_HEIGHT = 20
local LIST_TOP = -90

local function Money(c) return c and CM.FormatMoney(c) or "" end

local function ItemText(id, name)
  local quality = id and select(3, C_Item.GetItemInfo(id))
  local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality or 1]
  local text = name or (id and ("item " .. id)) or "?"
  if color and color.hex then return color.hex .. text .. "|r" end
  return text
end

local function ProfitText(c)
  if not c then return "" end
  if c < 0 then return "|cffff2020-" .. Money(-c) .. "|r" end
  return "|cff00ff00" .. Money(c) .. "|r"
end

-- Column sets. get(line) returns the cell text.
local LINE_COLUMNS = function(moneyTitle)
  return {
    { title = "Time", width = 100, get = function(l) return date("%d %b %H:%M", l.t) end },
    { title = "Item", width = 230, left = true, get = function(l) return ItemText(l.id, l.name) end },
    { title = "Qty", width = 50, get = function(l) return l.qty end },
    { title = moneyTitle, width = 110, get = function(l) return Money(l.money) end },
    { title = "Each", width = 100, get = function(l) return Money(math.floor(l.money / math.max(l.qty, 1))) end },
    { title = "Where", width = 60, get = function(l) return l.source == "Vendor" and "Vendor" or "AH" end },
    { title = "Character", width = 86, left = true, get = function(l) return l.char or "" end },
  }
end

local PAGES = {
  { name = "Bought", columns = LINE_COLUMNS("Paid") },
  { name = "Sold", columns = LINE_COLUMNS("Received") },
  { name = "Profit", columns = {
    { title = "Item", width = 196, left = true, get = function(it) return ItemText(it.id, it.name) end },
    { title = "Bought", width = 56, get = function(it) return it.boughtQty end },
    { title = "Avg Buy", width = 96, get = function(it) return Money(it.avgBuy) end },
    { title = "Sold", width = 50, get = function(it) return it.soldQty end },
    { title = "Avg Sell", width = 96, get = function(it) return Money(it.avgSell) end },
    { title = "Resale", width = 96, get = function(it) return ProfitText(it.resale) end },
    { title = "Profit", width = 106, get = function(it) return ProfitText(it.profit) end },
  } },
  { name = "Other", columns = {
    { title = "Time", width = 100, get = function(l) return date("%d %b %H:%M", l.t) end },
    { title = "Kind", width = 100, left = true, get = function(l) return l.kind end },
    { title = "What", width = 270, left = true, get = function(l) return l.note or "" end },
    { title = "Money", width = 120, get = function(l) return ProfitText(l.money) end },
    { title = "Character", width = 100, left = true, get = function(l) return l.char or "" end },
  } },
}

local PERIODS = {
  { label = "Today", since = function() return ns.Ledger:Today() end },
  { label = "7 Days", since = function() return ns.Ledger:Today() - 6 * 86400 end },
  { label = "All Time", since = function() return nil end },
}

local frame -- the Ledger page inside the main window
local current = { page = 1, period = 1 }

local function InitRow(row, data)
  local cols = PAGES[current.page].columns
  row.cells = row.cells or {}
  if not row.bg then
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    CM.Skins:Paint(hl, "highlight")
    row:SetScript("OnEnter", function(rw)
      if rw.data and rw.data.id then CM.ShowItemTooltip(rw, { itemID = rw.data.id }) end
    end)
    row:SetScript("OnLeave", GameTooltip_Hide)
    -- Right-click a Bought or Sold line to delete it (for lines recorded
    -- wrong, like the double-counted mails in 0.10.10).
    if row.RegisterForClicks then row:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    row:SetScript("OnClick", function(rw, button)
      if button == "RightButton" then LedgerUI:AskDelete(rw.data) end
    end)
  end
  for _, fs in pairs(row.cells) do fs:Hide() end
  local x = 4
  for i, col in ipairs(cols) do
    local fs = row.cells[i]
    if not fs then
      fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      fs:SetWordWrap(false)
      row.cells[i] = fs
    end
    fs:ClearAllPoints()
    fs:SetPoint("LEFT", x, 0)
    fs:SetWidth(col.width - 10)
    fs:SetJustifyH(col.left and "LEFT" or "RIGHT")
    fs:SetText(col.get(data))
    fs:Show()
    x = x + col.width
  end
  row.data = data
  CM.Skins:Stripe(row.bg, data.index)
end

local function BuildHeaders()
  for _, h in ipairs(frame.headers) do h:Hide() end
  local x = 16
  for i, col in ipairs(PAGES[current.page].columns) do
    local h = frame.headers[i]
    if not h then
      h = CreateFrame("Frame", nil, frame)
      h:SetHeight(ROW_HEIGHT)
      local bg = h:CreateTexture(nil, "BACKGROUND")
      bg:SetAllPoints()
      if not pcall(bg.SetAtlas, bg, "auctionhouse-tableheader") then bg:SetColorTexture(0.15, 0.15, 0.15, 0.9) end
      h.label = h:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      h.label:SetPoint("LEFT", 8, 0)
      frame.headers[i] = h
    end
    h:ClearAllPoints()
    h:SetPoint("TOPLEFT", x, LIST_TOP)
    h:SetWidth(col.width - 2)
    h.label:SetText(col.title)
    h:Show()
    x = x + col.width
  end
end

function LedgerUI:Refresh()
  if not frame then return end
  local page = PAGES[current.page]
  local data = {}
  local d = ns.Ledger:Data()
  local since = PERIODS[current.period].since()
  if page.name == "Profit" then
    local list, total = ns.Ledger:Summary(since)
    table.sort(list, function(a, b)
      if a.profit ~= b.profit then return a.profit > b.profit end
      return (a.name or "") < (b.name or "")
    end)
    data = list
    frame.summary:SetText(("%s: spent %s, received %s, profit %s"):format(
      PERIODS[current.period].label, Money(total.spent), Money(total.received), ProfitText(total.profit)))
  elseif page.name == "Other" then
    local byKind, income, costs = ns.Ledger:OtherTotals(since)
    for i = #d.other, 1, -1 do
      local l = d.other[i]
      if not since or l.t >= since then data[#data + 1] = l end
    end
    local parts = {}
    for kind, money in pairs(byKind) do parts[#parts + 1] = kind .. " " .. ProfitText(money) end
    table.sort(parts)
    frame.summary:SetText(("%s: income %s, costs %s.  %s"):format(PERIODS[current.period].label,
      Money(income), Money(costs), table.concat(parts, ", ")))
  else
    local list = page.name == "Bought" and d.bought or d.sold
    local sum = 0
    for i = #list, 1, -1 do
      local l = list[i]
      if not since or l.t >= since then
        data[#data + 1] = l
        sum = sum + l.money
      end
    end
    frame.summary:SetText(("%s: %d lines, %s %s"):format(PERIODS[current.period].label, #data,
      page.name == "Bought" and "spent" or "received", Money(sum)))
  end
  for i, row in ipairs(data) do row.index = i end
  BuildHeaders()
  CM.SetRows(frame.list, data)
  frame.empty:SetShown(#data == 0)
  for i, b in ipairs(frame.periodButtons) do
    if i == current.period then b:LockHighlight() else b:UnlockHighlight() end
  end
  for i, b in ipairs(frame.viewButtons) do
    if i == current.page then b:LockHighlight() else b:UnlockHighlight() end
  end
end

-- Builds the Ledger page (called by the main window the first time the
-- Ledger tab is shown). page covers the whole window.
function LedgerUI.Build(page)
  local skin = CM.Skins:Get()
  frame = page
  local f = frame

  -- Bought / Sold / Profit, top left (right of the portrait).
  f.viewButtons = {}
  for i, p in ipairs(PAGES) do
    local b = CreateFrame("Button", "CueTheCashierLedgerView" .. i, f, skin.buttonTemplate)
    b:SetSize(80, 22)
    if i == 1 then b:SetPoint("TOPLEFT", 70, -34) else b:SetPoint("LEFT", f.viewButtons[i - 1], "RIGHT", 4, 0) end
    b:SetText(p.name)
    b:SetScript("OnClick", function() current.page = i; LedgerUI:Refresh() end)
    f.viewButtons[i] = b
  end

  f.summary = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  f.summary:SetPoint("TOPLEFT", 70, -66)
  f.summary:SetPoint("RIGHT", f, "RIGHT", -20, 0)
  f.summary:SetJustifyH("LEFT")
  f.summary:SetWordWrap(false)

  -- Period buttons, top right.
  f.periodButtons = {}
  local anchor
  for i = #PERIODS, 1, -1 do
    local b = CreateFrame("Button", "CueTheCashierLedgerPeriod" .. i, f, skin.buttonTemplate)
    b:SetSize(80, 22)
    if anchor then b:SetPoint("RIGHT", anchor, "LEFT", -4, 0) else b:SetPoint("TOPRIGHT", -12, -34) end
    b:SetText(PERIODS[i].label)
    b:SetScript("OnClick", function() current.period = i; LedgerUI:Refresh() end)
    f.periodButtons[i] = b
    anchor = b
  end

  f.headers = {}
  local inset = CreateFrame("Frame", nil, f, "InsetFrameTemplate")
  inset:SetPoint("TOPLEFT", 12, LIST_TOP - ROW_HEIGHT)
  inset:SetPoint("BOTTOMRIGHT", -30, 12)
  local box = CreateFrame("Frame", nil, f, "WowScrollBoxList")
  local bar = CreateFrame("EventFrame", nil, f, "MinimalScrollBar")
  local view = CreateScrollBoxListLinearView()
  view:SetElementInitializer("CueTheCashierResultRowTemplate", InitRow)
  if view.SetElementExtent then view:SetElementExtent(ROW_HEIGHT) end
  ScrollUtil.InitScrollBoxListWithScrollBar(box, bar, view)
  box:SetPoint("TOPLEFT", inset, "TOPLEFT", 4, -4)
  box:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -4, 4)
  bar:SetPoint("TOPLEFT", inset, "TOPRIGHT", 6, 0)
  bar:SetPoint("BOTTOMLEFT", inset, "BOTTOMRIGHT", 6, 0)
  f.list = box

  f.empty = f:CreateFontString(nil, "OVERLAY", "GameFontNormalMed1")
  f.empty:SetPoint("TOP", inset, "TOP", 0, -100)
  f.empty:SetText("Nothing recorded for this period yet.")

  ns.Ledger:OnChange(function() if f:IsVisible() then LedgerUI:Refresh() end end)
end

function LedgerUI:AskDelete(line)
  local page = PAGES[current.page].name
  if not line or page == "Profit" then return end
  local d = ns.Ledger:Data()
  local list = (page == "Bought" and d.bought) or (page == "Sold" and d.sold) or d.other
  local text = page == "Other" and ("%s: %s"):format(line.kind or "", line.note or "")
    or ("%s: %d %s for %s"):format(page, line.qty or 0, line.name or "?", Money(line.money))
  CM.Confirm("Delete this line from the ledger?\n" .. text,
    function()
      for i, l in ipairs(list) do
        if l == line then table.remove(list, i); break end
      end
      LedgerUI:Refresh()
    end)
end

-- /cmp ledger: the main window on the Ledger tab (or closes it).
function LedgerUI:Toggle()
  API.ToggleMainWindow("ledger")
end
