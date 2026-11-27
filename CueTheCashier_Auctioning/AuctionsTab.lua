-- CueTheCashier: the Auctions tab of the Craft Trade window.
-- A copy of Blizzard's "Auctions" page with its two inner tabs:
--   Auctions: your own auctions and their status, with Cancel Auction.
--   Bids:     auctions you have bid on, with Bid and Buyout.
-- The left list has "All ..." plus each item, to filter the right list.
-- Positions are in UI units, measured from screenshots of Blizzard's page.
-- Copyright (C) 2026 Kim. Licensed under the GNU GPL v3 or later; see LICENSE.
local _, ns = ...
local CM = CueTheCashier
local API = CM.API

local AuctionsTab = {}
ns.AuctionsTab = AuctionsTab

local ROW_HEIGHT = 20
local LIST_TOP = -80
local RIGHT_LEFT = 178
local TIME_LEFT = { [0] = "Short", [1] = "Medium", [2] = "Long", [3] = "Very Long" }

local tab
local state = {
  mode = "auctions",     -- "auctions" or "bids"
  rows = {},             -- everything from the server
  filter = nil,          -- itemID chosen in the left list, nil = all
  selected = nil,        -- selected row
}

local function Money(c) return (c and c > 0) and CM.FormatMoney(c) or "" end

local function Sorts()
  local o = Enum.AuctionHouseSortOrder
  return o and { { sortOrder = o.Name, reverseSort = false } } or {}
end

-- "4h", "35m" for your own auctions (Blizzard shows hours).
local function ShortTime(seconds)
  if not seconds then return "" end
  if seconds >= 3600 then return math.floor(seconds / 3600) .. "h" end
  return math.max(1, math.floor(seconds / 60)) .. "m"
end

-- Item name for a row: "Camp Tent x20" for auctions, "Cracked Shortbow (3)"
-- (required level) for gear in bids, like Blizzard.
local function ItemText(r)
  local info = C_AuctionHouse.GetItemKeyInfo(r.itemKey) or {}
  local name = info.itemName or (r.itemLink and r.itemLink:match("%[(.-)%]")) or "..."
  if state.mode == "auctions" then
    if (r.quantity or 1) > 1 then name = name .. " |cff808080x" .. r.quantity .. "|r" end
  elseif info.isEquipment and C_Item.GetItemInfo then
    local req = select(5, C_Item.GetItemInfo(r.itemKey.itemID))
    if req and req > 0 then name = name .. " (" .. req .. ")" end
  end
  return name, info.iconFileID, info.quality
end

-- ------------------------------------------------------------------
-- Lists
-- ------------------------------------------------------------------
local function MakeList(parent, initializer)
  local box = CreateFrame("Frame", nil, parent, "WowScrollBoxList")
  local bar = CreateFrame("EventFrame", nil, parent, "MinimalScrollBar")
  local view = CreateScrollBoxListLinearView()
  view:SetElementInitializer("CueTheCashierResultRowTemplate", initializer)
  if view.SetElementExtent then view:SetElementExtent(ROW_HEIGHT) end
  ScrollUtil.InitScrollBoxListWithScrollBar(box, bar, view)
  return box, bar
end

local function VisibleRows()
  local out = {}
  for _, r in ipairs(state.rows) do
    if not state.filter or r.itemKey.itemID == state.filter then out[#out + 1] = r end
  end
  return out
end

local function UpdateButtons()
  local r = state.selected
  if state.mode == "auctions" then
    -- Only active (not sold) auctions can be cancelled.
    local active = r and (not Enum.AuctionStatus or r.status ~= Enum.AuctionStatus.Sold)
    tab.cancel:SetEnabled(active and true or false)
  else
    tab.bid:SetEnabled(r and r.minBid and r.minBid > 0 and true or false)
    tab.buyout:SetEnabled(r and r.buyoutAmount and r.buyoutAmount > 0 and true or false)
  end
end

local function InitRow(row, r)
  if not row.name then
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.sel = row:CreateTexture(nil, "ARTWORK")
    row.sel:SetAllPoints()
    row.sel:SetColorTexture(1, 0.82, 0, 0.35)
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    CM.Skins:Paint(hl, "highlight")
    row.icon = row:CreateTexture(nil, "OVERLAY")
    row.icon:SetSize(16, 16)
    row.icon:SetPoint("LEFT", 8, 0)
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
    row.name:SetWidth(270)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.bidText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.bidText:SetPoint("RIGHT", row, "LEFT", 412, 0)
    row.bidText:SetJustifyH("RIGHT")
    row.buyoutText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.buyoutText:SetPoint("RIGHT", row, "LEFT", 530, 0)
    row.buyoutText:SetJustifyH("RIGHT")
    row.time = row:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    row.time:SetPoint("RIGHT", -8, 0)
    row:SetScript("OnClick", function(rw)
      state.selected = rw.data
      if state.mode == "bids" and MoneyInputFrame_SetCopper then
        MoneyInputFrame_SetCopper(tab.moneyInput, rw.data.minBid or 0)
      end
      AuctionsTab:Refresh()
    end)
    row:SetScript("OnEnter", function(rw) CM.ShowItemTooltip(rw, rw.data.itemLink or rw.data.itemKey) end)
    row:SetScript("OnLeave", GameTooltip_Hide)
  end
  row.data = r
  CM.Skins:Stripe(row.bg, r.index)
  row.sel:SetShown(state.selected == r)
  local name, icon, quality = ItemText(r)
  local sold = state.mode == "auctions" and Enum.AuctionStatus and r.status == Enum.AuctionStatus.Sold
  -- Sold auctions read like Blizzard's: a green "Sold:" in front of the name.
  row.name:SetText(sold and ("|cff00ff00Sold:|r " .. (name or "")) or name)
  local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality or 1]
  if color and state.mode == "bids" then row.name:SetTextColor(color.r, color.g, color.b)
  else row.name:SetTextColor(1, 1, 1) end
  row.icon:SetTexture(icon)
  row.buyoutText:SetText(Money(r.buyoutAmount))
  if state.mode == "auctions" then
    row.bidText:SetText(Money(r.bidAmount))
    row.bidText:SetTextColor(1, 1, 1)
    if sold then
      -- What the mail will bring (Forever puts it in bid or buyout),
      -- and the time until the mail comes.
      row.bidText:SetText("")
      local amount = ((r.bidAmount or 0) > 0 and r.bidAmount) or r.buyoutAmount
      row.buyoutText:SetText(Money(amount))
      row.time:SetText(ShortTime(r.timeLeftSeconds) or "")
    else
      row.time:SetText(ShortTime(r.timeLeftSeconds))
    end
  else
    -- Your bid in green while you are the highest bidder (like Blizzard).
    local mine = r.bidder and UnitGUID and r.bidder == UnitGUID("player")
    row.bidText:SetText(Money(r.bidAmount or r.minBid))
    if mine then row.bidText:SetTextColor(0, 1, 0) else row.bidText:SetTextColor(1, 1, 1) end
    row.time:SetText(TIME_LEFT[r.timeLeft] or "")
  end
end

local function InitItemRow(row, node)
  if not row.label then
    row.sel = row:CreateTexture(nil, "BACKGROUND")
    row.sel:SetAllPoints()
    row.sel:SetColorTexture(1, 0.82, 0, 0.35)
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    CM.Skins:Paint(hl, "highlight")
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(16, 16)
    row.icon:SetPoint("LEFT", 4, 0)
    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.label:SetJustifyH("LEFT")
    row.label:SetWordWrap(false)
    row:SetScript("OnClick", function(rw)
      state.filter = rw.node.itemID
      state.selected = nil
      AuctionsTab:Refresh()
    end)
  end
  row.node = node
  local selected = state.filter == node.itemID
  row.sel:SetShown(selected)
  row.icon:SetTexture(node.icon)
  row.icon:SetShown(node.icon ~= nil)
  row.label:ClearAllPoints()
  row.label:SetPoint("LEFT", node.icon and 24 or 4, 0)
  row.label:SetPoint("RIGHT", -4, 0)
  row.label:SetFontObject(node.itemID and "GameFontHighlight" or "GameFontNormalLarge")
  row.label:SetText(node.name)
end

function AuctionsTab:Refresh()
  -- Left: "All ..." then one line per item.
  local items, seen = { { name = state.mode == "auctions" and "All Auctions" or "All Bids" } }, {}
  for _, r in ipairs(state.rows) do
    local id = r.itemKey.itemID
    if not seen[id] then
      seen[id] = true
      local info = C_AuctionHouse.GetItemKeyInfo(r.itemKey) or {}
      items[#items + 1] = { itemID = id, name = info.itemName or "...", icon = info.iconFileID }
    end
  end
  if state.filter and not seen[state.filter] then state.filter = nil end
  CM.SetRows(tab.itemList, items)
  -- Right: the auctions.
  local rows = VisibleRows()
  for i, r in ipairs(rows) do r.index = i end
  CM.SetRows(tab.list, rows)
  local sum, n = 0, 0
  for _, r in ipairs(state.rows) do
    if state.mode == "auctions" and Enum.AuctionStatus and r.status == Enum.AuctionStatus.Sold then
      sum, n = sum + (((r.bidAmount or 0) > 0 and r.bidAmount) or r.buyoutAmount or 0), n + 1
    end
  end
  tab.soldSum:SetText(n > 0 and ("|cff00ff00Sold:|r %s"):format(CM.FormatMoney(sum)) or "")
  tab.soldSum:SetShown(state.mode == "auctions")
  UpdateButtons()
end

local loggedSold = {} -- auctionID -> true once its "Sold auction" line is in the log

local function ReadRows()
  local rows = {}
  local selID = state.selected and state.selected.auctionID
  state.selected = nil
  if state.mode == "auctions" then
    for i = 1, C_AuctionHouse.GetNumOwnedAuctions() or 0 do
      rows[#rows + 1] = C_AuctionHouse.GetOwnedAuctionInfo(i)
    end
  else
    for i = 1, C_AuctionHouse.GetNumBids() or 0 do
      rows[#rows + 1] = C_AuctionHouse.GetBidInfo(i)
    end
  end
  for _, r in ipairs(rows) do
    if selID and r.auctionID == selID then state.selected = r end
  end
  state.rows = rows
  CM.Debug(("Auctions tab: %d %s."):format(#rows, state.mode))
  -- Each sold auction is logged once per session (0.45.0): the game sends
  -- OWNED_AUCTIONS_UPDATED several times per refresh, which logged every
  -- sold auction 2 to 4 times. "Time left" on a sold auction is the wait
  -- until the gold arrives by mail (up to 1 hour).
  for _, r in ipairs(rows) do
    if Enum.AuctionStatus and r.status == Enum.AuctionStatus.Sold and r.auctionID
      and not loggedSold[r.auctionID] then
      loggedSold[r.auctionID] = true
      CM.Debug(("Sold auction %s: bid %s, buyout %s, qty %s, time left %s s."):format(tostring(r.auctionID),
        tostring(r.bidAmount), tostring(r.buyoutAmount), tostring(r.quantity), tostring(r.timeLeftSeconds)))
    end
  end
  AuctionsTab:Refresh()
end

function AuctionsTab:Query()
  if state.mode == "auctions" then
    CM.Try("QueryOwnedAuctions", C_AuctionHouse.QueryOwnedAuctions, Sorts())
  else
    CM.Try("QueryBids", C_AuctionHouse.QueryBids, Sorts(), {})
  end
end

function AuctionsTab:SetMode(mode)
  state.mode, state.filter, state.selected, state.rows = mode, nil, nil, {}
  local isAuctions = mode == "auctions"
  if PanelTemplates_SelectTab then
    pcall(isAuctions and PanelTemplates_SelectTab or PanelTemplates_DeselectTab, tab.auctionsTab)
    pcall(isAuctions and PanelTemplates_DeselectTab or PanelTemplates_SelectTab, tab.bidsTab)
  end
  tab.clockHeader:SetShown(isAuctions)
  tab.cancel:SetShown(isAuctions)
  tab.bidRow:SetShown(not isAuctions)
  self:Refresh()
  self:Query()
end

-- ------------------------------------------------------------------
-- Building
-- ------------------------------------------------------------------
function AuctionsTab:Build(parent)
  local skin = CM.Skins:Get()
  tab = CreateFrame("Frame", "CueTheCashierAuctionsTab", parent)
  tab:SetAllPoints()
  tab:Hide()

  -- Inner tabs: Auctions | Bids.
  local function InnerTab(name, text, x, mode)
    local t = CreateFrame("Button", name, tab, "PanelTopTabButtonTemplate")
    t:SetPoint("BOTTOMLEFT", tab, "TOPLEFT", x, LIST_TOP + 2)
    t:SetText(text)
    if PanelTemplates_TabResize then pcall(PanelTemplates_TabResize, t, 20) end
    t:SetScript("OnClick", function() AuctionsTab:SetMode(mode) end)
    return t
  end
  tab.auctionsTab = InnerTab("CueTheCashierAuctionsInnerTab1", "Auctions", 52, "auctions")
  tab.bidsTab = InnerTab("CueTheCashierAuctionsInnerTab2", "Bids", 140, "bids")

  local refresh = CreateFrame("Button", nil, tab, "UIPanelSquareButton")
  refresh:SetSize(24, 24)
  refresh:SetPoint("TOPRIGHT", -12, -40)
  local rt = refresh:CreateTexture(nil, "OVERLAY")
  rt:SetPoint("CENTER")
  rt:SetSize(16, 16)
  if not pcall(rt.SetAtlas, rt, "UI-RefreshButton") then rt:SetTexture("Interface\\Buttons\\UI-RefreshButton") end
  refresh:SetScript("OnClick", function() AuctionsTab:Query() end)

  -- Left item list.
  local leftInset = CreateFrame("Frame", nil, tab, "InsetFrameTemplate")
  leftInset:SetPoint("TOPLEFT", 8, LIST_TOP)
  leftInset:SetPoint("BOTTOMLEFT", 8, 30)
  leftInset:SetWidth(156)
  local itemList, itemBar = MakeList(tab, InitItemRow)
  itemList:SetPoint("TOPLEFT", leftInset, "TOPLEFT", 4, -4)
  itemList:SetPoint("BOTTOMRIGHT", leftInset, "BOTTOMRIGHT", -16, 4)
  itemBar:SetPoint("TOPLEFT", itemList, "TOPRIGHT", 2, 0)
  itemBar:SetPoint("BOTTOMLEFT", itemList, "BOTTOMRIGHT", 2, 0)
  tab.itemList = itemList

  -- Column headers.
  local function Header(text, x, width)
    local h = CreateFrame("Frame", nil, tab)
    h:SetSize(width, ROW_HEIGHT)
    h:SetPoint("TOPLEFT", x, LIST_TOP)
    local bg = h:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    if not pcall(bg.SetAtlas, bg, "auctionhouse-tableheader") then bg:SetColorTexture(0.15, 0.15, 0.15, 0.9) end
    local fs = h:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("LEFT", 8, 0)
    fs:SetText(text)
    return h, fs
  end
  Header("Item", RIGHT_LEFT, 300)
  Header("Bid Price", RIGHT_LEFT + 302, 117)
  Header("Buyout Price", RIGHT_LEFT + 421, 119)
  local clock, clockText = Header("", RIGHT_LEFT + 542, 49)
  local clockIcon = clock:CreateTexture(nil, "OVERLAY")
  clockIcon:SetSize(12, 12)
  clockIcon:SetPoint("LEFT", 8, 0)
  if not pcall(clockIcon.SetAtlas, clockIcon, "auctionhouse-icon-clock") then
    clockIcon:SetTexture("Interface\\Icons\\INV_Misc_PocketWatch_01")
  end
  tab.clockHeader = clock

  local inset = CreateFrame("Frame", nil, tab, "InsetFrameTemplate")
  inset:SetPoint("TOPLEFT", RIGHT_LEFT - 4, LIST_TOP - ROW_HEIGHT)
  inset:SetPoint("BOTTOMRIGHT", -28, 30)
  local list, bar = MakeList(tab, InitRow)
  list:SetPoint("TOPLEFT", inset, "TOPLEFT", 4, -4)
  list:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -4, 4)
  bar:SetPoint("TOPLEFT", inset, "TOPRIGHT", 6, 0)
  bar:SetPoint("BOTTOMLEFT", inset, "BOTTOMRIGHT", 6, 0)
  tab.list = list

  -- Auctions mode: Cancel Auction, bottom right (asks first, shows the cost).
  local cancel = CreateFrame("Button", "CueTheCashierCancelAuctionButton", tab, skin.buttonTemplate)
  cancel:SetSize(152, 22)
  cancel:SetPoint("BOTTOMRIGHT", -2, 5)
  cancel:SetText("Cancel Auction")
  cancel:SetScript("OnClick", function()
    local r = state.selected
    if not r then return end
    local cost = C_AuctionHouse.GetCancelCost and C_AuctionHouse.GetCancelCost(r.auctionID) or 0
    local text = "Cancel this auction?"
    if cost and cost > 0 then text = text .. " It costs " .. CM.FormatMoney(cost) .. "." end
    CM.Confirm(text, function() CM.Try("CancelAuction", C_AuctionHouse.CancelAuction, r.auctionID) end)
  end)
  tab.cancel = cancel
  -- Sum of the sold auctions (money on its way in the mail).
  local soldSum = tab:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  soldSum:SetPoint("RIGHT", cancel, "LEFT", -12, 0)
  tab.soldSum = soldSum

  -- Bids mode: money inputs, Bid, Buyout (like the Buy tab's item page).
  local bidRow = CreateFrame("Frame", nil, tab)
  bidRow:SetAllPoints()
  local buyout = CreateFrame("Button", "CueTheCashierBidsBuyoutButton", bidRow, skin.buttonTemplate)
  buyout:SetSize(100, 22)
  buyout:SetPoint("BOTTOMRIGHT", -2, 5)
  buyout:SetText(BUYOUT or "Buyout")
  buyout:SetScript("OnClick", function()
    local r = state.selected
    if not r then return end
    CM.Confirm(("Buy %s for %s?"):format(ItemText(r), CM.FormatMoney(r.buyoutAmount)),
      function() CM.Try("PlaceBid (buyout)", C_AuctionHouse.PlaceBid, r.auctionID, r.buyoutAmount) end)
  end)
  tab.buyout = buyout
  local bid = CreateFrame("Button", "CueTheCashierBidsBidButton", bidRow, skin.buttonTemplate)
  bid:SetSize(97, 22)
  bid:SetPoint("RIGHT", buyout, "LEFT", -20, 0)
  bid:SetText(BID or "Bid")
  bid:SetScript("OnClick", function()
    local r = state.selected
    if not r then return end
    local amount = MoneyInputFrame_GetCopper and MoneyInputFrame_GetCopper(tab.moneyInput) or 0
    if amount < (r.minBid or 0) then
      CM.Print("Your bid must be at least " .. CM.FormatMoney(r.minBid) .. ".")
      return
    end
    CM.Confirm(("Bid %s on %s?"):format(CM.FormatMoney(amount), ItemText(r)),
      function() CM.Try("PlaceBid", C_AuctionHouse.PlaceBid, r.auctionID, amount) end)
  end)
  tab.bid = bid
  local ok, money = pcall(CreateFrame, "Frame", "CueTheCashierBidsMoneyInput", bidRow, "MoneyInputFrameTemplate")
  if not ok then money = CreateFrame("Frame", nil, bidRow) end
  money:SetPoint("RIGHT", bid, "LEFT", -12, 0)
  money:SetSize(176, 22)
  tab.moneyInput = money
  tab.bidRow = bidRow

  -- Your gold, bottom left.
  local moneyInset = CreateFrame("Frame", nil, tab, "InsetFrameTemplate")
  moneyInset:SetPoint("BOTTOMLEFT", 8, 5)
  moneyInset:SetSize(156, 20)
  local gold = CreateFrame("Frame", "CueTheCashierAuctionsMoneyFrame", moneyInset, "SmallMoneyFrameTemplate")
  gold:SetPoint("RIGHT", moneyInset, "RIGHT", 6, 0)
  local function UpdateMoney() MoneyFrame_Update(gold, GetMoney()) end
  UpdateMoney()

  tab:RegisterEvent("OWNED_AUCTIONS_UPDATED")
  tab:RegisterEvent("BIDS_UPDATED")
  tab:RegisterEvent("AUCTION_CANCELED")
  tab:RegisterEvent("BID_ADDED")
  tab:RegisterEvent("ITEM_KEY_ITEM_INFO_RECEIVED")
  tab:RegisterEvent("PLAYER_MONEY")
  tab:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_MONEY" then UpdateMoney()
    elseif event == "OWNED_AUCTIONS_UPDATED" then
      if state.mode == "auctions" then ReadRows() end
    elseif event == "BIDS_UPDATED" then
      if state.mode == "bids" then ReadRows() end
    elseif event == "ITEM_KEY_ITEM_INFO_RECEIVED" then
      if tab:IsVisible() then AuctionsTab:Refresh() end
    elseif tab:IsVisible() then
      AuctionsTab:Query() -- something changed: ask again
    end
  end)
  -- Ask the server each time the tab is opened.
  tab:SetScript("OnShow", function() AuctionsTab:SetMode(state.mode) end)
  return tab
end
