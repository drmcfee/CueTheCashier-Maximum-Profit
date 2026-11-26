-- CueTheCashier: the Sell tab of the Craft Trade window.
-- A copy of Blizzard's "Post Auctions" page. Left: the Create Auction
-- panel (item slot, Quantity + Max, Buyout Price per item, Duration,
-- Deposit, Total Price, Create Auction, Buyout Mode). Right: what the
-- item is listed for right now (Bid Price / Buyout Price).
--
-- Put an item in by dragging it onto the slot, or by right-clicking it in
-- your bags (we pick up what Blizzard's own sell page would get).
-- Positions are in UI units, measured from a screenshot of Blizzard's page.
-- Copyright (C) 2026 Kim. Licensed under the GNU GPL v3 or later; see LICENSE.
local _, ns = ...
local CM = CueTheCashier
local API = CM.API

local SellTab = {}
ns.SellTab = SellTab

local ROW_HEIGHT = 20
local LABEL_X = 106          -- right edge of the labels
local INPUT_X = 127          -- left edge of the inputs
local ROWS_Y = { quantity = -193, buyout = -237, bid = -282 }
local SHIFT_FOR_BID = 45     -- how far rows move down when Starting Bid shows

local tab                    -- the tab frame
local state = {
  location = nil,            -- ItemLocation of the item to sell
  isCommodity = false,
  duration = 2,              -- 1, 2 or 3 (Blizzard's three durations)
  buyoutMode = true,         -- true = buyout only, false = starting bid too
  rows = {},
}

local function Money(c) return CM.FormatMoney(c or 0) end

local function DurationLabel(i)
  -- Blizzard's own texts, so they match this game version ("8 Hours" ...).
  local g = ({ AUCTION_DURATION_ONE, AUCTION_DURATION_TWO, AUCTION_DURATION_THREE })[i]
  return g or ({ "Short", "Medium", "Long" })[i]
end

local function GetQuantity()
  return tonumber(tab.quantity:GetText()) or 0
end

local function GetCopper(input)
  return MoneyInputFrame_GetCopper and MoneyInputFrame_GetCopper(input) or 0
end

local function SetCopper(input, c)
  if MoneyInputFrame_SetCopper then MoneyInputFrame_SetCopper(input, c or 0) end
end

-- ------------------------------------------------------------------
-- Deposit, total and the Create Auction button
-- ------------------------------------------------------------------
function SellTab:Update()
  local loc, qty = state.location, GetQuantity()
  local price = GetCopper(tab.buyoutInput)
  local deposit = 0
  if loc and qty > 0 then
    local ok, d
    if state.isCommodity then
      ok, d = pcall(C_AuctionHouse.CalculateCommodityDeposit,
        C_Item.GetItemID(loc), state.duration, qty)
    else
      ok, d = pcall(C_AuctionHouse.CalculateItemDeposit, loc, state.duration, qty)
    end
    deposit = ok and d or 0
  end
  tab.deposit:SetText(Money(deposit))
  tab.total:SetText(Money(price * qty))
  local bidOK = state.buyoutMode or GetCopper(tab.bidInput) > 0
  tab.create:SetEnabled(loc ~= nil and qty > 0 and price > 0 and bidOK)
end

-- Moves the rows down when the Starting Bid row is shown (Buyout Mode off).
local function Layout()
  -- Stackables are priced per unit and have no bidding (like Blizzard).
  tab.buyoutLabel:SetText(state.isCommodity and "Unit Price" or "Buyout Price")
  tab.modeButton:SetShown(not state.isCommodity)
  tab.modeText:SetShown(not state.isCommodity)
  tab.itemHeaders:SetShown(not state.isCommodity)
  tab.commodityHeaders:SetShown(state.isCommodity)
  local showBid = not state.buyoutMode and not state.isCommodity
  tab.bidRow:SetShown(showBid)
  local shift = showBid and SHIFT_FOR_BID or 0
  for _, r in ipairs(tab.movingRows) do
    r.frame:ClearAllPoints()
    r.frame:SetPoint("TOPLEFT", tab, "TOPLEFT", 0, r.y - shift)
  end
end

-- ------------------------------------------------------------------
-- The item to sell
-- ------------------------------------------------------------------
local function ReadList()
  local rows = {}
  if not state.location then state.rows = rows; return end
  local itemID = C_Item.GetItemID(state.location)
  if state.isCommodity then
    for i = 1, C_AuctionHouse.GetNumCommoditySearchResults(itemID) or 0 do
      local r = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, i)
      if r then
        rows[#rows + 1] = { buyout = r.unitPrice, quantity = r.quantity, own = r.containsOwnerItem,
          sellers = r.totalNumberOfOwners, owner = r.owners and r.owners[1] }
      end
    end
  else
    local key = state.itemKey
    for i = 1, C_AuctionHouse.GetNumItemSearchResults(key) or 0 do
      local r = C_AuctionHouse.GetItemSearchResultInfo(key, i)
      if r then
        rows[#rows + 1] = { bid = r.minBid, buyout = r.buyoutAmount, quantity = r.quantity,
          own = r.containsOwnerItem, link = r.itemLink }
      end
    end
  end
  state.rows = rows
  local total = 0
  for i, r in ipairs(rows) do r.index = i; total = total + (r.quantity or 1) end
  tab.available:SetText(#rows > 0 and (total .. " Available") or "")
  CM.SetRows(tab.list, rows)
end

-- In game (2026-11-21) SendSellSearchQuery got no answer at all on
-- Forever, while SendSearchQuery with a plain item key works (Test Scan,
-- Buy tab). So we use that, and keep the sell query only as a fallback.
local function SendQuery()
  if not state.itemKey then return end
  state.waitingForKeyInfo = false
  state.answered = false
  local order = Enum.AuctionHouseSortOrder
  local sorts = order and { { sortOrder = order.Price, reverseSort = false } } or {}
  local plainKey = C_AuctionHouse.MakeItemKey(state.itemKey.itemID)
  -- Stackables are listed under the plain key; gear under its full key.
  local key = state.isCommodity and plainKey or state.itemKey
  CM.Try("Sell SendSearchQuery", C_AuctionHouse.SendSearchQuery, key, sorts, true)
  local asked = state.itemKey
  C_Timer.After(4, function()
    if state.itemKey ~= asked or state.answered then return end
    CM.Debug("Sell: no answer after 4 seconds, trying the other search kinds.")
    CM.Try("Sell SendSearchQuery (plain key)", C_AuctionHouse.SendSearchQuery, plainKey, sorts, true)
    if C_AuctionHouse.SendSellSearchQuery then
      CM.Try("SendSellSearchQuery", C_AuctionHouse.SendSellSearchQuery, state.itemKey, sorts, true)
    end
  end)
end

-- The game silently drops a search for an item whose auction house info
-- is not loaded yet (we found this with Test Scan). So: check, and if it
-- is missing, wait for ITEM_KEY_ITEM_INFO_RECEIVED before searching.
local function SearchCurrent()
  if not state.itemKey then return end
  local ok, info = CM.Try("Sell GetItemKeyInfo", C_AuctionHouse.GetItemKeyInfo, state.itemKey)
  if ok and info then return SendQuery() end
  state.waitingForKeyInfo = true
  local key = state.itemKey
  C_Timer.After(5, function()
    if state.waitingForKeyInfo and state.itemKey == key then
      CM.Debug("Sell: item info never arrived, searching anyway.")
      SendQuery()
    end
  end)
end

function SellTab:SetItem(location)
  if not (location and C_Item.DoesItemExist(location)) then return end
  if C_AuctionHouse.IsSellItemValid and not C_AuctionHouse.IsSellItemValid(location, false) then
    CM.Print("That item can't be sold on the auction house.")
    return
  end
  state.location = location
  local ok, status = pcall(C_AuctionHouse.GetItemCommodityStatus, location)
  CM.Debug("Sell tab: commodity status " .. tostring(ok and status))
  state.isCommodity = ok and Enum.ItemCommodityStatus and status == Enum.ItemCommodityStatus.Commodity
  local itemID = C_Item.GetItemID(location)
  state.itemKey = C_AuctionHouse.GetItemKeyFromItem and C_AuctionHouse.GetItemKeyFromItem(location)
    or C_AuctionHouse.MakeItemKey(itemID)

  tab.icon:SetTexture(C_Item.GetItemIcon(location))
  local quality = C_Item.GetItemQuality(location)
  local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality or 1]
  tab.itemName:SetText(C_Item.GetItemName(location) or "")
  if color then tab.itemName:SetTextColor(color.r, color.g, color.b) end

  -- Start at 1 for gear, the whole stack for stackables (like Blizzard).
  local max = C_AuctionHouse.GetAvailablePostCount(location) or 1
  tab.quantity:SetText(state.isCommodity and max or 1)
  -- Suggest our saved lowest buyout as the price, if we have one.
  SetCopper(tab.buyoutInput, API.GetPrice(itemID, "auction.min") or 0)
  SetCopper(tab.bidInput, 0)
  Layout()
  self:Update()
  ReadList()
  SearchCurrent()
end

function SellTab:ClearItem()
  state.location, state.itemKey, state.rows = nil, nil, {}
  tab.icon:SetTexture(nil)
  tab.itemName:SetText("")
  tab.quantity:SetText("")
  SetCopper(tab.buyoutInput, 0)
  SetCopper(tab.bidInput, 0)
  CM.SetRows(tab.list, {})
  tab.available:SetText("")
  self:Update()
end

-- ------------------------------------------------------------------
-- Posting
-- ------------------------------------------------------------------
function SellTab:Post()
  local loc, qty = state.location, GetQuantity()
  if not loc then return end
  local price = GetCopper(tab.buyoutInput)
  local ok
  if state.isCommodity then
    ok = CM.Try("PostCommodity", C_AuctionHouse.PostCommodity, loc, state.duration, qty, price)
  else
    local bid = (not state.buyoutMode) and GetCopper(tab.bidInput) or nil
    ok = CM.Try("PostItem", C_AuctionHouse.PostItem, loc, state.duration, qty, bid, price)
  end
  if not ok then CM.Print("Posting failed, see /cmp log.") end
end

-- ------------------------------------------------------------------
-- Building
-- ------------------------------------------------------------------
local function Label(parent, text, y, sub)
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  fs:SetPoint("RIGHT", parent, "TOPLEFT", LABEL_X, y)
  fs:SetJustifyH("RIGHT")
  fs:SetText(text)
  if sub then
    local s = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    s:SetPoint("TOPRIGHT", fs, "BOTTOMRIGHT", 0, -1)
    s:SetText(sub)
  end
  return fs
end

local function MoneyInput(parent, name, y)
  local ok, m = pcall(CreateFrame, "Frame", name, parent, "MoneyInputFrameTemplate")
  if not ok then
    CM.Debug("Sell tab: MoneyInputFrameTemplate missing: " .. tostring(m))
    m = CreateFrame("Frame", name, parent)
  end
  m:SetPoint("LEFT", parent, "TOPLEFT", INPUT_X + 6, y)
  m:SetSize(176, 22)
  if MoneyInputFrame_SetOnValueChangedFunc then
    MoneyInputFrame_SetOnValueChangedFunc(m, function() SellTab:Update() end)
  end
  return m
end

-- A row that moves down when the Starting Bid row appears.
local function MovingRow(y)
  local f = CreateFrame("Frame", nil, tab)
  f:SetSize(360, 1)
  tab.movingRows[#tab.movingRows + 1] = { frame = f, y = y }
  return f
end

local function InitListRow(row, r)
  if not row.bid then
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    CM.Skins:Paint(hl, "highlight")
    row.bid = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.bid:SetPoint("LEFT", 4, 0)
    row.bid:SetWidth(108)
    row.bid:SetJustifyH("RIGHT")
    row.buyout = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.buyout:SetPoint("LEFT", 120, 0)
    row.buyout:SetWidth(100)
    row.buyout:SetJustifyH("RIGHT")
    row.extra = row:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    row.extra:SetPoint("RIGHT", -8, 0)
    -- Clicking a listing copies its price into your Buyout Price.
    row:SetScript("OnClick", function(rw)
      SetCopper(tab.buyoutInput, rw.data.buyout or 0)
      SellTab:Update()
    end)
    row:SetScript("OnEnter", function(rw)
      if rw.data.link then CM.ShowItemTooltip(rw, rw.data.link) end
    end)
    row:SetScript("OnLeave", GameTooltip_Hide)
  end
  row.data = r
  CM.Skins:Stripe(row.bg, r.index)
  row.bid:ClearAllPoints()
  row.buyout:ClearAllPoints()
  row.extra:ClearAllPoints()
  if state.isCommodity then
    -- Stackables, like Blizzard: Unit Price | quantity | Seller.
    row.buyout:SetPoint("LEFT", 4, 0)              -- unit price
    row.buyout:SetWidth(72)
    row.bid:SetPoint("LEFT", 100, 0)               -- quantity
    row.bid:SetWidth(98)
    row.extra:SetPoint("LEFT", 284, 0)             -- seller
    row.buyout:SetText(Money(r.buyout))
    row.bid:SetText(r.quantity or "")
    local seller = ""
    if r.own then seller = "Yours"
    elseif r.sellers and r.sellers > 1 then seller = r.sellers .. " Sellers"
    elseif r.owner then seller = r.owner end
    row.extra:SetText(seller)
  else
    -- Gear and other single items: Bid Price | Buyout Price.
    row.bid:SetPoint("LEFT", 4, 0)
    row.bid:SetWidth(108)
    row.buyout:SetPoint("LEFT", 120, 0)
    row.buyout:SetWidth(100)
    row.extra:SetPoint("RIGHT", -8, 0)
    row.bid:SetText(r.bid and r.bid > 0 and Money(r.bid) or "")
    row.buyout:SetText(r.buyout and r.buyout > 0 and Money(r.buyout) or "")
    row.extra:SetText(r.own and "Yours" or "")
  end
end

function SellTab:Build(parent)
  local skin = CM.Skins:Get()
  tab = CreateFrame("Frame", "CueTheCashierSellTab", parent)
  tab:SetAllPoints()
  tab:Hide()
  tab.movingRows = {}

  -- Left panel with its little "Create Auction" tab on top.
  local panel = CreateFrame("Frame", nil, tab, "InsetFrameTemplate")
  panel:SetPoint("TOPLEFT", 7, -73)
  panel:SetPoint("BOTTOMLEFT", 7, 30)
  panel:SetWidth(358)
  local panelTab = CreateFrame("Button", nil, tab, "PanelTopTabButtonTemplate")
  panelTab:SetPoint("BOTTOMLEFT", panel, "TOPLEFT", 40, -2)
  panelTab:SetText("Create Auction")
  if PanelTemplates_TabResize then pcall(PanelTemplates_TabResize, panelTab, 20) end
  if PanelTemplates_SelectTab then pcall(PanelTemplates_SelectTab, panelTab) end

  -- Item box: slot + name. Drop an item here or right-click it in bags.
  local itemBox = CreateFrame("Frame", nil, tab, "InsetFrameTemplate")
  itemBox:SetPoint("TOPLEFT", 16, -83)
  itemBox:SetSize(340, 72)
  local slot = CreateFrame("Button", "CueTheCashierSellItemSlot", itemBox)
  slot:SetSize(52, 52)
  slot:SetPoint("LEFT", 10, 0)
  local slotBg = slot:CreateTexture(nil, "BACKGROUND")
  slotBg:SetAllPoints()
  if not pcall(slotBg.SetAtlas, slotBg, "auctionhouse-itemicon-empty") then
    slotBg:SetTexture("Interface\\Buttons\\UI-EmptySlot")
  end
  tab.icon = slot:CreateTexture(nil, "ARTWORK")
  tab.icon:SetPoint("TOPLEFT", 4, -4)
  tab.icon:SetPoint("BOTTOMRIGHT", -4, 4)
  local function TakeCursorItem()
    local loc = C_Cursor and C_Cursor.GetCursorItem and C_Cursor.GetCursorItem()
    if loc then ClearCursor(); SellTab:SetItem(loc); return true end
  end
  slot:RegisterForDrag("LeftButton")
  slot:SetScript("OnReceiveDrag", TakeCursorItem)
  slot:SetScript("OnClick", function()
    if not TakeCursorItem() and state.location then SellTab:ClearItem() end
  end)
  slot:SetScript("OnEnter", function(s)
    GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
    if state.location then
      local bag, slotIndex = state.location:GetBagAndSlot()
      if bag then GameTooltip:SetBagItem(bag, slotIndex) end
    else
      GameTooltip:SetText("Drag an item here, or right-click it in your bags.")
    end
    GameTooltip:Show()
  end)
  slot:SetScript("OnLeave", GameTooltip_Hide)
  tab.itemName = itemBox:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  tab.itemName:SetPoint("LEFT", slot, "RIGHT", 12, 0)
  tab.itemName:SetWidth(250)
  tab.itemName:SetJustifyH("LEFT")

  -- Quantity + Max.
  Label(tab, "Quantity", ROWS_Y.quantity)
  local qty = CreateFrame("EditBox", "CueTheCashierSellQuantity", tab, "InputBoxTemplate")
  qty:SetSize(124, 26)
  qty:SetPoint("LEFT", tab, "TOPLEFT", INPUT_X + 6, ROWS_Y.quantity)
  qty:SetNumeric(true)
  qty:SetAutoFocus(false)
  CM.Skins:StyleInput(qty)
  qty:SetScript("OnTextChanged", function() SellTab:Update() end)
  qty:SetScript("OnEnterPressed", qty.ClearFocus)
  tab.quantity = qty
  local max = CreateFrame("Button", nil, tab, skin.buttonTemplate)
  max:SetSize(70, 22)
  max:SetPoint("LEFT", qty, "RIGHT", 10, 0)
  max:SetText("Max")
  max:SetScript("OnClick", function()
    if state.location then
      qty:SetText(C_AuctionHouse.GetAvailablePostCount(state.location) or 1)
    end
  end)

  -- Buyout Price per item.
  tab.buyoutLabel = Label(tab, "Buyout Price", ROWS_Y.buyout, "per item")
  tab.buyoutInput = MoneyInput(tab, "CueTheCashierSellBuyout", ROWS_Y.buyout)

  -- Starting Bid (only with Buyout Mode off).
  local bidRow = CreateFrame("Frame", nil, tab)
  bidRow:SetAllPoints()
  Label(bidRow, "Starting Bid", ROWS_Y.bid, "per item")
  tab.bidInput = MoneyInput(bidRow, "CueTheCashierSellBid", ROWS_Y.bid)
  tab.bidRow = bidRow

  -- Rows below move down when Starting Bid shows.
  local durRow = MovingRow(0)
  Label(durRow, "Duration", -284)
  local ok, dd = pcall(CreateFrame, "DropdownButton", "CueTheCashierSellDuration", durRow,
    "WowStyle1DropdownTemplate")
  if ok and dd.SetupMenu then
    dd:SetupMenu(function(_, root)
      for i = 1, 3 do
        root:CreateRadio(DurationLabel(i), function() return state.duration == i end,
          function() state.duration = i; SellTab:Update() end)
      end
    end)
  else
    -- Fallback: a button that cycles through the three durations.
    dd = CreateFrame("Button", "CueTheCashierSellDuration", durRow, skin.buttonTemplate)
    dd:SetScript("OnClick", function(b)
      state.duration = state.duration % 3 + 1
      b:SetText(DurationLabel(state.duration))
      SellTab:Update()
    end)
    dd:SetText(DurationLabel(state.duration))
  end
  dd:SetSize(112, 24)
  dd:SetPoint("LEFT", durRow, "TOPLEFT", INPUT_X, -284)
  tab.durationButton = dd

  local depRow = MovingRow(0)
  Label(depRow, "Deposit", -327)
  tab.deposit = depRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
  tab.deposit:SetPoint("LEFT", depRow, "TOPLEFT", INPUT_X, -327)

  local totRow = MovingRow(0)
  Label(totRow, "Total Price", -372)
  tab.total = totRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
  tab.total:SetPoint("LEFT", totRow, "TOPLEFT", INPUT_X, -372)

  local createRow = MovingRow(0)
  local create = CreateFrame("Button", "CueTheCashierCreateAuctionButton", createRow, skin.buttonTemplate)
  create:SetSize(189, 22)
  create:SetPoint("CENTER", createRow, "TOPLEFT", 185, -413)
  create:SetText("Create Auction")
  create:SetScript("OnClick", function() SellTab:Post() end)
  tab.create = create

  -- Buyout Mode, bottom left of the panel.
  local mode = CreateFrame("CheckButton", "CueTheCashierSellBuyoutMode", tab, "UICheckButtonTemplate")
  mode:SetSize(26, 26)
  mode:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 10, 10)
  mode:SetChecked(true)
  tab.modeButton = mode
  local modeText = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  modeText:SetPoint("LEFT", mode, "RIGHT", 4, 0)
  modeText:SetText("Buyout Mode")
  tab.modeText = modeText
  mode:SetScript("OnClick", function(b)
    state.buyoutMode = b:GetChecked() and true or false
    Layout()
    SellTab:Update()
  end)

  -- Right side: current listings for this item.
  local refresh = CreateFrame("Button", nil, tab, "UIPanelSquareButton")
  refresh:SetSize(24, 24)
  refresh:SetPoint("TOPRIGHT", -12, -40)
  local rt = refresh:CreateTexture(nil, "OVERLAY")
  rt:SetPoint("CENTER")
  rt:SetSize(16, 16)
  if not pcall(rt.SetAtlas, rt, "UI-RefreshButton") then rt:SetTexture("Interface\\Buttons\\UI-RefreshButton") end
  refresh:SetScript("OnClick", SearchCurrent)

  tab.available = tab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  tab.available:SetPoint("RIGHT", refresh, "LEFT", -8, 0)

  local function Header(text, x, width, parent)
    local h = CreateFrame("Frame", nil, parent)
    h:SetSize(width, ROW_HEIGHT)
    h:SetPoint("TOPLEFT", x, -72)
    local bg = h:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    if not pcall(bg.SetAtlas, bg, "auctionhouse-tableheader") then bg:SetColorTexture(0.15, 0.15, 0.15, 0.9) end
    local fs = h:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("LEFT", 8, 0)
    fs:SetText(text)
    return fs
  end
  -- Two header sets: single items, and stackables (like Blizzard).
  tab.itemHeaders = CreateFrame("Frame", nil, tab)
  tab.itemHeaders:SetAllPoints()
  Header("Bid Price", 373, 116, tab.itemHeaders)
  Header("Buyout Price", 491, 276, tab.itemHeaders)
  tab.commodityHeaders = CreateFrame("Frame", nil, tab)
  tab.commodityHeaders:SetAllPoints()
  Header("Unit Price", 373, 274, tab.commodityHeaders)
  Header("Seller", 649, 117, tab.commodityHeaders)
  tab.commodityHeaders:Hide()
  local inset = CreateFrame("Frame", nil, tab, "InsetFrameTemplate")
  inset:SetPoint("TOPLEFT", 369, -92)
  inset:SetPoint("BOTTOMRIGHT", -28, 30)
  local box = CreateFrame("Frame", nil, tab, "WowScrollBoxList")
  local bar = CreateFrame("EventFrame", nil, tab, "MinimalScrollBar")
  local view = CreateScrollBoxListLinearView()
  view:SetElementInitializer("CueTheCashierResultRowTemplate", InitListRow)
  if view.SetElementExtent then view:SetElementExtent(ROW_HEIGHT) end
  ScrollUtil.InitScrollBoxListWithScrollBar(box, bar, view)
  box:SetPoint("TOPLEFT", inset, "TOPLEFT", 4, -4)
  box:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -4, 4)
  bar:SetPoint("TOPLEFT", inset, "TOPRIGHT", 6, 0)
  bar:SetPoint("BOTTOMLEFT", inset, "BOTTOMRIGHT", 6, 0)
  tab.list = box

  -- Your gold, bottom left.
  local moneyInset = CreateFrame("Frame", nil, tab, "InsetFrameTemplate")
  moneyInset:SetPoint("BOTTOMLEFT", 8, 5)
  moneyInset:SetSize(156, 20)
  local money = CreateFrame("Frame", "CueTheCashierSellMoneyFrame", moneyInset, "SmallMoneyFrameTemplate")
  money:SetPoint("RIGHT", moneyInset, "RIGHT", 6, 0)
  local function UpdateMoney() MoneyFrame_Update(money, GetMoney()) end
  UpdateMoney()

  -- Ctrl- or Shift-click an item in your bags while the Sell tab is open
  -- puts it in the slot.
  local function FindInBags(link)
    local itemID = tonumber(link:match("item:(%d+)"))
    for bag = 0, (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) do
      for slotIndex = 1, C_Container.GetContainerNumSlots(bag) or 0 do
        local l = C_Container.GetContainerItemLink(bag, slotIndex)
        if l == link or (l and itemID and tonumber(l:match("item:(%d+)")) == itemID) then
          return ItemLocation:CreateFromBagAndSlot(bag, slotIndex)
        end
      end
    end
  end
  if HandleModifiedItemClick then
    hooksecurefunc("HandleModifiedItemClick", function(link, location)
      if not (tab:IsVisible() and type(link) == "string") then return end
      if not (IsShiftKeyDown() or IsControlKeyDown()) then return end
      -- Newer clients pass where the item is; otherwise find it in the bags.
      if not (type(location) == "table" and location.IsBagAndSlot and location:IsBagAndSlot()) then
        location = FindInBags(link)
      end
      if location then SellTab:SetItem(location) end
    end)
  end

  -- Right-click in bags: Blizzard hands the item to its own (hidden) sell
  -- page; we pick it up when our Sell tab is open.
  -- GUESS: AuctionHouseFrame:SetPostItem exists as on retail.
  if AuctionHouseFrame and AuctionHouseFrame.SetPostItem then
    hooksecurefunc(AuctionHouseFrame, "SetPostItem", function(_, location)
      if tab:IsVisible() then SellTab:SetItem(location) end
    end)
  else
    CM.Debug("Sell tab: AuctionHouseFrame.SetPostItem not found, right-click from bags won't work.")
  end

  tab:RegisterEvent("ITEM_SEARCH_RESULTS_UPDATED")
  tab:RegisterEvent("COMMODITY_SEARCH_RESULTS_UPDATED")
  tab:RegisterEvent("AUCTION_HOUSE_AUCTION_CREATED")
  tab:RegisterEvent("ITEM_KEY_ITEM_INFO_RECEIVED")
  tab:RegisterEvent("AUCTION_HOUSE_POST_WARNING")
  tab:RegisterEvent("PLAYER_MONEY")
  tab:SetScript("OnEvent", function(_, event, arg)
    if event == "PLAYER_MONEY" then UpdateMoney()
    elseif event == "AUCTION_HOUSE_AUCTION_CREATED" then
      CM.Print("Auction created.")
      SellTab:ClearItem()
    elseif event == "AUCTION_HOUSE_POST_WARNING" then
      -- Blizzard wants a second OK (for example a price far below normal).
      CM.Confirm("Blizzard warns about this auction. Post it anyway?", function()
        if state.isCommodity then
          CM.Try("ConfirmPostCommodity", C_AuctionHouse.ConfirmPostCommodity,
            state.location, state.duration, GetQuantity(), GetCopper(tab.buyoutInput))
        else
          CM.Try("ConfirmPostItem", C_AuctionHouse.ConfirmPostItem, state.location, state.duration,
            GetQuantity(), (not state.buyoutMode) and GetCopper(tab.bidInput) or nil,
            GetCopper(tab.buyoutInput))
        end
      end)
    elseif event == "ITEM_KEY_ITEM_INFO_RECEIVED" then
      if state.waitingForKeyInfo and state.itemKey and arg == state.itemKey.itemID then SendQuery() end
    elseif state.location and tab:IsVisible() and state.itemKey
        and (arg == state.itemKey.itemID or (type(arg) == "table" and arg.itemID == state.itemKey.itemID)) then
      state.answered = true
      -- Trust the kind of answer over our guess: the commodity check can say
      -- "unknown" before the item is loaded.
      local isCommodity = event == "COMMODITY_SEARCH_RESULTS_UPDATED"
      if isCommodity ~= state.isCommodity then
        CM.Debug("Sell: switching to " .. (isCommodity and "stackable" or "single item") .. " view.")
        state.isCommodity = isCommodity
        if isCommodity then SetCopper(tab.bidInput, 0) end
        Layout()
        SellTab:Update()
      end
      ReadList()
    end
  end)

  tab:SetScript("OnShow", function() SellTab:Update() end)
  Layout()
  self:Update()
  return tab
end
