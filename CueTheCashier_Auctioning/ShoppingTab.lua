-- CueTheCashier: Shopping tab.
-- Buys what CueTheCashier's shopping list says to get on the auction house.
-- The list comes from the craft list (CueTheCashier_Crafting): only reagents
-- whose cheapest source is the auction house, only the missing amount, and
-- only up to a max price per item (by default 120% of the price the craft
-- list used; /cmp prof max <percent>). Search looks up every item's
-- listings; click one and Buy, like the Vendor tab. Every purchase asks
-- first (Forever only allows buys from a confirm box).
-- Group Scan (0.34): looks up every item in your groups that has a
-- Shopping operation and lists only the ones on sale at or under the
-- operation's highest price, up to its "buy up to" amount.
-- Uses the shared code in DealPage.lua.
-- Copyright (C) 2026 Kim. Licensed under the GNU GPL v3 or later; see LICENSE.
local _, ns = ...
local CM = CueTheCashier
local API = CM.API

local function AddRow(s, page, r)
  r.name, r.quality = C_Item.GetItemInfo(r.itemID)
  r.loaded = false
  s.rows[#s.rows + 1] = r
  s.byKey[page.KeyString(r.itemKey)] = r
end

-- Every grouped item with a Shopping operation: { [itemID] = { maxPrice, need, op, path } }.
-- need is nil when the operation has no limit.
function ns.ShoppingGroupItems()
  local out = {}
  for _, g in ipairs(API.GetGroups()) do
    if not g.base then
      for itemID in pairs(API.GetGroupItems(g.id)) do
        if out[itemID] == nil then
          out[itemID] = false
          local op, settings, groupID = API.GetItemOperation(itemID, "shop")
          local maxPrice = op and API.GetOperationPrice("shop", op, "maxPrice", itemID)
          if maxPrice and maxPrice > 0 then
            local need
            local upTo = tonumber(settings and settings.buyUpTo) or 0
            if upTo > 0 then need = upTo - (C_Item.GetItemCount(itemID, true) or 0) end
            if not need or need > 0 then
              local path
              for _, gg in ipairs(API.GetGroups()) do if gg.id == groupID then path = gg.path end end
              out[itemID] = { maxPrice = maxPrice, need = need, op = op, path = path or g.path }
            end
          end
        end
      end
    end
  end
  for id, e in pairs(out) do if not e then out[id] = nil end end
  return out
end

local function FillRows(page)
  local s = page.state
  s.rows, s.byKey, s.selected = {}, {}, nil
  if s.mode == "groups" then
    for itemID, e in pairs(ns.ShoppingGroupItems()) do
      AddRow(s, page, {
        itemKey = C_AuctionHouse.MakeItemKey(itemID), itemID = itemID, need = e.need,
        maxPrice = e.maxPrice, limit = e.maxPrice, ref = e.maxPrice + 1, why = "Group", group = e.path,
      })
    end
    return
  end
  for itemID, e in pairs(API.GetShoppingList("auction")) do
    AddRow(s, page, {
      itemKey = C_AuctionHouse.MakeItemKey(itemID), itemID = itemID, need = e.quantity, price = e.price,
      maxPrice = e.maxPrice, limit = e.maxPrice, ref = e.maxPrice + 1, why = "Shopping",
    })
  end
end

ns.ShoppingTab = ns.DealPage.New({
  name = "Shopping",
  owner = "shopping",
  loop = false,
  -- The craft list keeps items with nothing cheap enough; a group scan
  -- shows only deals.
  keepEmpty = function(s) return s.mode ~= "groups" end,
  sortKey = "need",
  FillRows = FillRows,
  -- Quantity box: what you still need, if your gold pays for it.
  WantQty = function(r, affordable) return math.min(r.need or math.huge, affordable, r.qty or 0) end,
  modes = {
    { mode = "shop", label = SEARCH or "Search", buttonName = "SearchButton" },
    { mode = "groups", label = "Group Scan", buttonName = "GroupScanButton", width = 110 },
  },
  columns = {
    { key = "name", title = "Item", width = 206, kind = "text" },
    { key = "need", title = "Need", width = 60, kind = "count" },
    { key = "price", title = "List Price", width = 96, kind = "money" },
    { key = "maxPrice", title = "Max Price", width = 96, kind = "money" },
    { key = "minBuyout", title = "Lowest Buyout", width = 104, kind = "money" },
    { key = "qty", title = "Under Max", width = 80, kind = "count" },
    { key = "available", title = "Available", width = 72, kind = "count" },
  },
  emptyText = "The shopping list is empty. Make a Craft List in a profession window first.",
  EmptyText = function(s)
    if s.mode == "groups" then
      return "Nothing to buy: no grouped item with a Shopping operation is under its max price."
    end
    return "The shopping list is empty. Make a Craft List in a profession window first."
  end,
  boughtText = "Bought for the craft list.",
  Evaluate = function() return nil end, -- no browse search on this tab
  InfoText = function(s)
    if s.mode == "groups" then
      if s.finishedAt then
        local deals = 0
        for _, r in ipairs(s.rows) do if r.loaded and (r.qty or 0) > 0 then deals = deals + 1 end end
        return ("Group Scan: %d items at or under their Shopping operation max price so far."):format(deals)
      end
    end
    local n = 0
    for _ in pairs(API.GetShoppingList("auction")) do n = n + 1 end
    if s.finishedAt then
      return ("%d items from your craft list to buy here. Click one, then Buy."):format(#s.rows)
    end
    return ("%d craft list reagents are cheapest on the auction house. Click Search to look them up, or Group Scan for your groups' Shopping operations."):format(n)
  end,
})
ns.ShoppingTab.KeyString = ns.DealPage.KeyString

-- The craft list changed (you bought or crafted something): update what
-- each row still needs; drop rows you no longer need.
function ns.ShoppingTab:ListChanged()
  local s = self.state
  if not s.finishedAt or not self.tab or s.mode == "groups" then return end
  local list = API.GetShoppingList("auction")
  for i = #s.rows, 1, -1 do
    local r = s.rows[i]
    local e = list[r.itemID]
    if e then
      r.need = e.quantity
    else
      table.remove(s.rows, i)
      s.byKey[self.KeyString(r.itemKey)] = nil
      if s.selected == r then s.selected = nil end
    end
  end
  if self.tab:IsVisible() then self:Refresh() end
end

-- A click on a reagent in the craft list: open this tab, look the item up
-- and start buying it (the confirm box asks first).
function ns.ShoppingTab:BuyItem(itemID)
  local CraftTrade = ns.CraftTrade
  if not (AuctionHouseFrame and AuctionHouseFrame:IsShown()) then return end
  if not CraftTrade.showingOurs then CraftTrade:ShowOurs() end
  for i, page in ipairs(CueTheCashierCraftTradeFrame.pages) do
    if page.name == "Shopping" then CraftTrade:SelectTab(i) end
  end
  local s = self.state
  local function Find()
    for _, r in ipairs(s.rows) do if r.itemID == itemID then return r end end
  end
  local r = s.mode == "shop" and Find()
  if not r then
    -- Not looked up yet (or the list changed): fill the tab first.
    self:StopLoading()
    s.mode = "shop"
    self.cfg.FillRows(self)
    s.finishedAt = time()
    self:QueueLoads()
    r = Find()
  end
  if not r then
    CM.Print("That item isn't on the shopping list for the auction house.")
    return
  end
  self.autoBuy = r
  self:Select(r)
end
