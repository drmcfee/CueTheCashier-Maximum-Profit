-- CueTheCashier: item page of the Buy tab (what Blizzard shows after you
-- click an item): Back, "N Available" with refresh, the item header with
-- its favorite star, the list of auctions (Current Bid / Buyout Price /
-- time left), and at the bottom gold/silver/copper inputs with Bid and
-- Buyout buttons. Every bid and buyout asks for confirmation first, and
-- only happens from your click (Blizzard rule).
--
-- Positions are in UI units, measured from a screenshot of Blizzard's page.
-- Copyright (C) 2026 Kim. Licensed under the GNU GPL v3 or later; see LICENSE.
local _, ns = ...
local CM = CueTheCashier
local API = CM.API

local ItemPage = {}
ns.ItemPage = ItemPage

local ROW_HEIGHT = 20
local LEFT = 174
local TIME_LEFT = { [0] = "Short", [1] = "Medium", [2] = "Long", [3] = "Very Long" }

local page, buyTab
local current = { itemKey = nil, isCommodity = false, rows = {}, selected = nil }

local function Money(c) return (c and c > 0) and CM.FormatMoney(c) or "" end

-- Yes/no popup for Bid and Buyout (shared with the whole suite).
local Confirm = CM.Confirm

-- ------------------------------------------------------------------
-- Auction list
-- ------------------------------------------------------------------
-- Estimated total for qty: cheapest listings first (not your own).
local function Estimate(qty)
  local left, total = qty, 0
  for _, row in ipairs(current.rows) do
    if left <= 0 then break end
    if not row.containsOwnerItem and row.unitPrice then
      local take = math.min(left, row.quantity or 0)
      total, left = total + take * row.unitPrice, left - take
    end
  end
  return total, left <= 0
end

local function UpdateButtons()
  local r = current.selected
  local own = r and r.containsOwnerItem
  -- Stackables: Quantity + Buy Now. Single items: money boxes + Bid/Buyout.
  page.commodityRow:SetShown(current.isCommodity)
  page.moneyInput:SetShown(not current.isCommodity)
  page.bidButton:SetShown(not current.isCommodity)
  page.buyoutButton:SetShown(not current.isCommodity)
  local qty = tonumber(page.qty:GetText()) or 0
  page.buyNow:SetEnabled(current.isCommodity and qty > 0 and not current.buying)
  local total = Estimate(qty)
  page.estimate:SetText(qty > 0 and ("Total about " .. CM.FormatMoney(total)) or "")
  if current.quote then
    -- The server quoted the exact price: Buy Now became Confirm.
    page.estimate:SetText(("Server price %s (%s each)"):format(
      CM.FormatMoney(current.quote.total), CM.FormatMoney(current.quote.unit)))
    page.buyNow:SetText("Confirm")
    page.buyNow:SetEnabled(true)
  else
    page.buyNow:SetText("Buy Now")
  end
  page.bidButton:SetEnabled(r and not current.isCommodity and not own and r.minBid and r.minBid > 0 or false)
  page.buyoutButton:SetEnabled(r and not current.isCommodity and not own
    and r.buyoutAmount and r.buyoutAmount > 0 or false)
end

local function InitRow(row, r)
  if not row.bid then
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.sel = row:CreateTexture(nil, "ARTWORK")
    row.sel:SetAllPoints()
    CM.Skins:Paint(row.sel, "selected")
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    CM.Skins:Paint(hl, "highlight")
    row.bid = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.bid:SetPoint("LEFT", 4, 0)
    row.bid:SetWidth(110)
    row.bid:SetJustifyH("RIGHT")
    row.buyout = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.buyout:SetPoint("LEFT", 120, 0)
    row.buyout:SetWidth(90)
    row.buyout:SetJustifyH("RIGHT")
    row.time = row:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    row.time:SetPoint("RIGHT", -8, 0)
    row:SetScript("OnEnter", function(rw)
      CM.ShowItemTooltip(rw, rw.data.itemLink or current.itemKey)
    end)
    row:SetScript("OnLeave", GameTooltip_Hide)
    row:SetScript("OnClick", function(rw)
      current.selected = rw.data
      if current.isCommodity then
        -- Like Blizzard: buy everything from the cheapest row down to this one.
        local qty = 0
        for _, other in ipairs(current.rows) do
          if not other.containsOwnerItem then qty = qty + (other.quantity or 0) end
          if other == rw.data then break end
        end
        page.qty:SetText(qty)
      end
      -- Prefill the money boxes with the lowest allowed bid.
      if rw.data.minBid and MoneyInputFrame_SetCopper then
        MoneyInputFrame_SetCopper(page.moneyInput, rw.data.minBid)
      end
      ItemPage:RefreshList()
    end)
  end
  row.data = r
  CM.Skins:Stripe(row.bg, r.index)
  row.sel:SetShown(current.selected == r)
  if current.isCommodity then
    row.bid:SetText(r.quantity or "")             -- "Available" for stackables
    row.buyout:SetText(Money(r.unitPrice))
    row.time:SetText("")
  else
    row.bid:SetText(Money(r.bidAmount))
    row.buyout:SetText(Money(r.buyoutAmount))
    row.time:SetText(r.containsOwnerItem and "Yours" or TIME_LEFT[r.timeLeft] or "")
  end
end

function ItemPage:RefreshList()
  for i, r in ipairs(current.rows) do r.index = i end
  CM.SetRows(page.list, current.rows)
  local total = 0
  for _, r in ipairs(current.rows) do total = total + (r.quantity or 1) end
  page.available:SetText(total .. " Available")
  UpdateButtons()
end

local function ReadResults()
  local rows, key = {}, current.itemKey
  if current.isCommodity then
    local n = C_AuctionHouse.GetNumCommoditySearchResults(key.itemID) or 0
    for i = 1, n do rows[#rows + 1] = C_AuctionHouse.GetCommoditySearchResultInfo(key.itemID, i) end
  else
    local n = C_AuctionHouse.GetNumItemSearchResults(key) or 0
    for i = 1, n do rows[#rows + 1] = C_AuctionHouse.GetItemSearchResultInfo(key, i) end
  end
  -- Keep the selection if that auction is still there.
  local selID = current.selected and current.selected.auctionID
  current.selected = nil
  for _, r in ipairs(rows) do
    if selID and r.auctionID == selID then current.selected = r end
  end
  current.rows = rows
  CM.Debug("Item page: " .. #rows .. " rows.")
  ItemPage:RefreshList()
end

local function SendSearch()
  local order = Enum.AuctionHouseSortOrder
  local sorts = order and { { sortOrder = order.Buyout or order.Price, reverseSort = false } } or {}
  CM.Try("Item page SendSearchQuery", C_AuctionHouse.SendSearchQuery, current.itemKey, sorts, true)
end

-- ------------------------------------------------------------------
-- Buying stackables. Blizzard's flow: ask the server for the exact price
-- (StartCommoditiesPurchase), it answers with COMMODITY_PRICE_UPDATED, we
-- show that price and only buy (ConfirmCommoditiesPurchase) on your OK.
-- ------------------------------------------------------------------
function ItemPage:StartCommodityPurchase()
  if current.quote then
    -- Second click: buy at the quoted price.
    local qty = current.buying
    current.quote = nil
    UpdateButtons()
    CM.Try("ConfirmCommoditiesPurchase", C_AuctionHouse.ConfirmCommoditiesPurchase, current.itemKey.itemID, qty)
    return
  end
  local qty = tonumber(page.qty:GetText()) or 0
  if qty <= 0 or not current.itemKey then return end
  current.buying = qty
  UpdateButtons()
  -- If Blizzard blocks it, the purchase moves to Blizzard's window.
  local function Reset()
    current.buying = false
    UpdateButtons()
  end
  local total, enough = Estimate(qty)
  current.approved = enough and total or nil
  ns.StartStackPurchase(current.itemKey.itemID, qty, current.name, nil, Reset, nil,
    enough and ("Buy %d %s for %s?"):format(qty, current.name or "", CM.FormatMoney(total)) or nil)
end

function ItemPage:ConfirmCommodityPurchase(unitPrice, totalPrice)
  local qty = current.buying
  if not qty then return end
  local itemID = current.itemKey.itemID
  -- You accepted this price (or less) in the first popup: buy now.
  if ns.AutoConfirmStack(itemID, qty, current.name, totalPrice, current.approved) then return end
  Confirm(("Buy %d %s for %s (%s each)?"):format(qty, current.name or "",
      CM.FormatMoney(totalPrice), CM.FormatMoney(unitPrice)),
    function()
      ns.ConfirmStackPurchase(itemID, qty, current.name, nil, function()
        current.buying = false
        UpdateButtons()
      end, totalPrice)
    end,
    function()
      current.buying = false
      if C_AuctionHouse.CancelCommoditiesPurchase then C_AuctionHouse.CancelCommoditiesPurchase() end
      UpdateButtons()
    end)
end

-- ------------------------------------------------------------------
-- Show / hide
-- ------------------------------------------------------------------
-- opts.quantity: prefill the Quantity box for stackables (Vendor tab).
function ItemPage:Show(result, opts)
  if not page then return end
  local key = result.itemKey
  local info = C_AuctionHouse.GetItemKeyInfo(key)
  if not info and not (opts and opts.noWait) then
    -- The game drops searches for items it hasn't loaded yet, so wait for
    -- the item's info first (at most 5 seconds).
    current.pending = { result = result, opts = opts }
    C_Timer.After(5, function()
      if current.pending and current.pending.result == result then
        current.pending = nil
        ItemPage:Show(result, { quantity = opts and opts.quantity, noWait = true })
      end
    end)
    return
  end
  info = info or {}
  current.pending = nil
  current.itemKey = key
  current.rows, current.selected = {}, nil
  if current.quote and C_AuctionHouse.CancelCommoditiesPurchase then C_AuctionHouse.CancelCommoditiesPurchase() end
  current.buying, current.quote = false, nil
  page.qty:SetText(opts and opts.quantity or "")
  current.isCommodity = info.isCommodity and true or false

  -- Header: icon, name (with item level for gear), favorite star.
  local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[info.quality or 1]
  local name = info.itemName or result.name or "?"
  -- Gear shows its required level in brackets, like Blizzard's page.
  if info.isEquipment and C_Item.GetItemInfo then
    local reqLevel = select(5, C_Item.GetItemInfo(key.itemID))
    if reqLevel and reqLevel > 0 then name = name .. " (" .. reqLevel .. ")" end
  end
  page.name:SetText(name)
  current.name = info.itemName or result.name
  if color then page.name:SetTextColor(color.r, color.g, color.b) end
  page.icon:SetTexture(info.iconFileID or result.icon)
  buyTab:UpdateStar(page.star, key)

  page.colBid:SetText(current.isCommodity and "Available" or "Current Bid")
  page.colBuyout:SetText(current.isCommodity and "Unit Price" or "Buyout Price")
  if MoneyInputFrame_SetCopper then MoneyInputFrame_SetCopper(page.moneyInput, 0) end

  buyTab.browseView:Hide()
  if CueTheCashierAuctionBar then CueTheCashierAuctionBar:Hide() end
  page:Show()
  self:RefreshList()
  SendSearch()
end

function ItemPage:Hide()
  if not (page and page:IsShown()) then return end
  page:Hide()
  buyTab.browseView:Show()
  if CueTheCashierAuctionBar then CueTheCashierAuctionBar:Show() end
end

-- ------------------------------------------------------------------
-- Building
-- ------------------------------------------------------------------
function ItemPage:Build(parent, tab)
  buyTab = tab
  local skin = CM.Skins:Get()
  page = CreateFrame("Frame", "CueTheCashierItemPage", parent)
  page:SetAllPoints()
  page:Hide()

  local back = CreateFrame("Button", nil, page, skin.buttonTemplate)
  back:SetSize(105, 22)
  back:SetPoint("TOPLEFT", LEFT + 10, -84)
  back:SetText(BACK or "Back")
  back:SetScript("OnClick", function() ItemPage:Hide() end)

  local refresh = CreateFrame("Button", nil, page, "UIPanelSquareButton")
  refresh:SetSize(24, 24)
  refresh:SetPoint("TOPRIGHT", -12, -83)
  local rt = refresh:CreateTexture(nil, "OVERLAY")
  rt:SetPoint("CENTER")
  rt:SetSize(16, 16)
  if not pcall(rt.SetAtlas, rt, "UI-RefreshButton") then
    rt:SetTexture("Interface\\Buttons\\UI-RefreshButton")
  end
  refresh:SetScript("OnClick", function()
    if current.isCommodity then
      CM.Try("RefreshCommoditySearchResults", C_AuctionHouse.RefreshCommoditySearchResults, current.itemKey.itemID)
    else
      CM.Try("RefreshItemSearchResults", C_AuctionHouse.RefreshItemSearchResults, current.itemKey)
    end
  end)
  page.available = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  page.available:SetPoint("RIGHT", refresh, "LEFT", -8, 0)

  -- Item header box.
  local header = CreateFrame("Frame", nil, page, "InsetFrameTemplate")
  header:SetPoint("TOPLEFT", LEFT - 4, -118)
  header:SetPoint("TOPRIGHT", -8, -118)
  header:SetHeight(84)
  page.icon = header:CreateTexture(nil, "ARTWORK")
  page.icon:SetSize(50, 50)
  page.icon:SetPoint("LEFT", 22, 0)
  if page.icon.SetMask then pcall(page.icon.SetMask, page.icon, "Interface\\CharacterFrame\\TempPortraitAlphaMask") end
  page.name = header:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
  page.name:SetPoint("LEFT", page.icon, "RIGHT", 12, 0)
  -- Hovering the icon or name shows the item tooltip.
  local hover = CreateFrame("Frame", nil, header)
  hover:SetPoint("TOPLEFT", page.icon, "TOPLEFT")
  hover:SetPoint("BOTTOMRIGHT", page.name, "BOTTOMRIGHT")
  hover:EnableMouse(true)
  hover:SetScript("OnEnter", function(h)
    local first = current.rows[1]
    CM.ShowItemTooltip(h, first and first.itemLink or current.itemKey)
  end)
  hover:SetScript("OnLeave", GameTooltip_Hide)
  local star = CreateFrame("Button", nil, header)
  star:SetSize(18, 18)
  star:SetPoint("TOPRIGHT", -12, -10)
  star.tex = star:CreateTexture(nil, "ARTWORK")
  star.tex:SetAllPoints()
  star:SetScript("OnClick", function(b)
    local fav = C_AuctionHouse.IsFavoriteItem(current.itemKey)
    CM.Try("SetFavoriteItem", C_AuctionHouse.SetFavoriteItem, current.itemKey, not fav)
    buyTab:UpdateStar(b, current.itemKey)
  end)
  page.star = star

  -- Column headers.
  local function Header(text, x, width)
    local h = CreateFrame("Frame", nil, page)
    h:SetSize(width, ROW_HEIGHT)
    h:SetPoint("TOPLEFT", x, -219)
    local bg = h:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    if not pcall(bg.SetAtlas, bg, "auctionhouse-tableheader") then bg:SetColorTexture(0.15, 0.15, 0.15, 0.9) end
    local fs = h:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("LEFT", 8, 0)
    fs:SetText(text)
    return fs
  end
  page.colBid = Header("Current Bid", LEFT + 4, 116)
  page.colBuyout = Header("Buyout Price", LEFT + 122, 472)

  -- Auction list.
  local inset = CreateFrame("Frame", nil, page, "InsetFrameTemplate")
  inset:SetPoint("TOPLEFT", LEFT, -239)
  inset:SetPoint("BOTTOMRIGHT", -28, 30)
  local box = CreateFrame("Frame", nil, page, "WowScrollBoxList")
  local bar = CreateFrame("EventFrame", nil, page, "MinimalScrollBar")
  local view = CreateScrollBoxListLinearView()
  view:SetElementInitializer("CueTheCashierResultRowTemplate", InitRow)
  if view.SetElementExtent then view:SetElementExtent(ROW_HEIGHT) end
  ScrollUtil.InitScrollBoxListWithScrollBar(box, bar, view)
  box:SetPoint("TOPLEFT", inset, "TOPLEFT", 4, -4)
  box:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -4, 4)
  bar:SetPoint("TOPLEFT", inset, "TOPRIGHT", 6, 0)
  bar:SetPoint("BOTTOMLEFT", inset, "BOTTOMRIGHT", 6, 0)
  page.list = box

  -- Stackables: Quantity + Buy Now, bottom right.
  local cRow = CreateFrame("Frame", nil, page)
  cRow:SetAllPoints()
  local buyNow = CreateFrame("Button", "CueTheCashierBuyNowButton", cRow, skin.buttonTemplate)
  buyNow:SetSize(120, 22)
  buyNow:SetPoint("BOTTOMRIGHT", -2, 5)
  buyNow:SetText("Buy Now")
  buyNow:SetScript("OnClick", function() ItemPage:StartCommodityPurchase() end)
  page.buyNow = buyNow
  local qty = CreateFrame("EditBox", "CueTheCashierBuyQuantity", cRow, "InputBoxTemplate")
  qty:SetSize(80, 22)
  qty:SetPoint("RIGHT", buyNow, "LEFT", -12, 0)
  qty:SetNumeric(true)
  qty:SetAutoFocus(false)
  CM.Skins:StyleInput(qty)
  qty:SetScript("OnTextChanged", function() UpdateButtons() end)
  qty:SetScript("OnEnterPressed", qty.ClearFocus)
  page.qty = qty
  local qtyLabel = cRow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  qtyLabel:SetPoint("RIGHT", qty, "LEFT", -10, 0)
  qtyLabel:SetText("Quantity")
  page.estimate = cRow:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  page.estimate:SetPoint("RIGHT", qtyLabel, "LEFT", -20, 0)
  page.commodityRow = cRow

  -- Bottom row: money inputs, Bid, Buyout.
  local buyout = CreateFrame("Button", "CueTheCashierBuyoutButton", page, skin.buttonTemplate)
  buyout:SetSize(100, 22)
  buyout:SetPoint("BOTTOMRIGHT", -2, 5)
  buyout:SetText(BUYOUT or "Buyout")
  buyout:SetScript("OnClick", function()
    local r = current.selected
    if not r then return end
    -- Forever only allows buys from a popup's Accept.
    ns.BuyAuction({ auctionID = r.auctionID, amount = r.buyoutAmount, buyout = true,
      itemID = current.itemKey and current.itemKey.itemID, name = current.name,
      ask = ("Buy %s for %s?"):format(current.name or "this item", Money(r.buyoutAmount)) })
  end)
  page.buyoutButton = buyout

  local bid = CreateFrame("Button", "CueTheCashierBidButton", page, skin.buttonTemplate)
  bid:SetSize(97, 22)
  bid:SetPoint("RIGHT", buyout, "LEFT", -20, 0)
  bid:SetText(BID or "Bid")
  bid:SetScript("OnClick", function()
    local r = current.selected
    if not r then return end
    local amount = MoneyInputFrame_GetCopper and MoneyInputFrame_GetCopper(page.moneyInput) or 0
    if amount < (r.minBid or 0) then
      CM.Print("Your bid must be at least " .. Money(r.minBid) .. ".")
      return
    end
    Confirm(("Bid %s on %s?"):format(Money(amount), page.name:GetText() or "this item"),
      function() ns.BuyAuction({ auctionID = r.auctionID, amount = amount, name = current.name }) end)
  end)
  page.bidButton = bid

  local ok, money = pcall(CreateFrame, "Frame", "CueTheCashierBidMoneyInput", page, "MoneyInputFrameTemplate")
  if not ok then
    CM.Debug("Item page: MoneyInputFrameTemplate missing: " .. tostring(money))
    money = CreateFrame("Frame", nil, page)
  end
  money:SetPoint("RIGHT", bid, "LEFT", -12, 0)
  money:SetSize(176, 22)
  page.moneyInput = money

  -- Server answers and changes.
  page:RegisterEvent("ITEM_SEARCH_RESULTS_UPDATED")
  page:RegisterEvent("ITEM_SEARCH_RESULTS_ADDED")
  page:RegisterEvent("COMMODITY_SEARCH_RESULTS_UPDATED")
  page:RegisterEvent("AUCTION_HOUSE_FAVORITES_UPDATED")
  page:RegisterEvent("ITEM_KEY_ITEM_INFO_RECEIVED")
  page:RegisterEvent("COMMODITY_PRICE_UPDATED")
  page:RegisterEvent("COMMODITY_PRICE_UNAVAILABLE")
  page:RegisterEvent("COMMODITY_PURCHASE_SUCCEEDED")
  page:RegisterEvent("COMMODITY_PURCHASE_FAILED")
  page:SetScript("OnEvent", function(_, event, arg, arg2)
    if event == "ITEM_KEY_ITEM_INFO_RECEIVED" then
      local p = current.pending
      if p and p.result.itemKey.itemID == arg then
        current.pending = nil
        ItemPage:Show(p.result, p.opts)
      end
      return
    end
    if not current.itemKey then return end
    local purchaseEvent = event:find("^COMMODITY_P") ~= nil
    if purchaseEvent and not current.buying then
      return -- a purchase from another tab (Vendor)
    elseif event == "COMMODITY_PRICE_UPDATED" then
      ItemPage:ConfirmCommodityPurchase(arg, arg2)
    elseif event == "COMMODITY_PRICE_UNAVAILABLE" then
      current.buying, current.quote = false, nil
      CM.Print("Those items are no longer available at that price.")
      UpdateButtons()
    elseif event == "COMMODITY_PURCHASE_SUCCEEDED" then
      current.buying, current.quote = false, nil
      CM.Print("Purchase complete.")
      SendSearch()
    elseif event == "COMMODITY_PURCHASE_FAILED" then
      current.buying, current.quote = false, nil
      CM.Print("Purchase failed.")
      UpdateButtons()
    elseif event == "AUCTION_HOUSE_FAVORITES_UPDATED" then
      buyTab:UpdateStar(page.star, current.itemKey)
    elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
      if current.isCommodity and arg == current.itemKey.itemID then ReadResults() end
    elseif not current.isCommodity and type(arg) == "table" and arg.itemID == current.itemKey.itemID then
      ReadResults()
    end
  end)
  UpdateButtons()
  return page
end
