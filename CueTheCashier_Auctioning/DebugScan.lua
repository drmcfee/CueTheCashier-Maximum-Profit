-- CueTheCashier: debug test scan.
-- Looks up ONE item (Light Leather by default) with normal searches instead
-- of the full snapshot. Normal searches have no 15 minute cooldown, so this
-- is for quick testing while developing. The price is saved like a full-scan
-- price. Every step is written to the debug log (/cmp log).
--
-- Steps:
--   1. Make sure the client has the item's auction house info loaded
--      (GetItemKeyInfo). If not, wait for ITEM_KEY_ITEM_INFO_RECEIVED.
--   2. Exact item search (SendSearchQuery), like clicking an item row.
--   3. If that gives nothing, a name search (SendBrowseQuery), like typing
--      the name into the auction house search box.
-- Copyright (C) 2026 Kim. Licensed under the GNU GPL v3 or later; see LICENSE.
local _, ns = ...
local CM = CueTheCashier
local API = CM.API

local DebugScan = { busy = false }
ns.DebugScan = DebugScan

DebugScan.DEFAULT_ITEM = 2318 -- Light Leather
local KEYINFO_WAIT = 5
local SEARCH_WAIT = 6
local BROWSE_WAIT = 8
-- Used for the name search when the client has not cached the name yet.
local KNOWN_NAMES = { [2318] = "Light Leather" }

local frame = CreateFrame("Frame")

local function ItemName(itemID)
  local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)
  return name or KNOWN_NAMES[itemID] or ("item " .. itemID)
end

local function PriceSorts()
  local order = Enum and Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price
  return order and { { sortOrder = order, reverseSort = false } } or {}
end

-- Runs fn after delay seconds, but only if this scan is still the active one.
local function After(self, delay, fn)
  local token = self.token
  C_Timer.After(delay, function()
    if self.busy and self.token == token then fn() end
  end)
end

local function Stop(self)
  frame:UnregisterAllEvents()
  frame:SetScript("OnEvent", nil)
  self.busy = false
  self.step = nil
end

local function Finish(self, best, quantity, auctions, how)
  local itemID = self.itemID
  -- Listings read by ReadCommodity/ReadItems (a name search only has the min).
  local prices = DebugScan.prices
  DebugScan.prices = nil
  Stop(self)
  API.RecordScan({ [itemID] = { prices = prices, minOnly = best, quantity = quantity } },
    "test", auctions)
  local e = API.GetItemSummary(itemID) or {}
  CM.Print(("Test scan (%s): %s lowest buyout %s, market value %s (%d for sale)."):format(
    how, ItemName(itemID), CM.FormatMoney(best),
    e.marketValue and CM.FormatMoney(e.marketValue) or "?", quantity))
end

local function Fail(self, msg)
  Stop(self)
  CM.Print("Test scan: " .. msg .. " See /cmp log for details.")
end

-- Pooled stacks with one price per unit ("commodities" on retail).
local function ReadCommodity(itemID)
  local _, n = CM.Try("GetNumCommoditySearchResults(" .. itemID .. ")",
    C_AuctionHouse.GetNumCommoditySearchResults, itemID)
  local best, quantity, auctions = nil, 0, 0
  local prices = {}
  DebugScan.prices = prices
  for i = 1, tonumber(n) or 0 do
    local r = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, i)
    if i <= 3 then CM.Debug("  commodity row " .. i .. ":", r) end
    if r and r.unitPrice and r.unitPrice > 0 then
      if not best or r.unitPrice < best then best = r.unitPrice end
      prices[#prices + 1] = r.unitPrice
      prices[#prices + 1] = r.quantity or 1
      quantity = quantity + (r.quantity or 0)
      auctions = auctions + 1
    end
  end
  return best, quantity, auctions
end

-- Separate auctions, each with its own buyout for the whole stack.
local function ReadItems(itemKey)
  local _, n = CM.Try("GetNumItemSearchResults(itemKey)",
    C_AuctionHouse.GetNumItemSearchResults, itemKey)
  local best, quantity, auctions = nil, 0, 0
  local prices = {}
  DebugScan.prices = prices
  for i = 1, tonumber(n) or 0 do
    local r = C_AuctionHouse.GetItemSearchResultInfo(itemKey, i)
    if i <= 3 then CM.Debug("  item row " .. i .. ":", r) end
    if r and r.buyoutAmount and r.buyoutAmount > 0 then
      local count = (r.quantity and r.quantity > 0) and r.quantity or 1
      local unit = math.floor(r.buyoutAmount / count)
      if not best or unit < best then best = unit end
      prices[#prices + 1] = unit
      prices[#prices + 1] = count
      quantity = quantity + count
      auctions = auctions + 1
    end
  end
  return best, quantity, auctions
end

-- Name search results: one row per item, already holding the lowest price.
local function ReadBrowse(itemID)
  DebugScan.prices = nil
  local ok, results = CM.Try("GetBrowseResults() count", function()
    local r = C_AuctionHouse.GetBrowseResults()
    return r and #r or 0
  end)
  results = ok and C_AuctionHouse.GetBrowseResults() or {}
  for i, r in ipairs(results) do
    if i <= 5 then CM.Debug("  browse row " .. i .. ":", r) end
    if r.itemKey and r.itemKey.itemID == itemID and r.minPrice and r.minPrice > 0 then
      return r.minPrice, r.totalQuantity or 0, 0
    end
  end
end

-- Step 3: name search.
local function Browse(self)
  self.step = "browse"
  local name = ItemName(self.itemID)
  if name:match("^item %d+$") then
    return Fail(self, "exact search found nothing and the item name is unknown, so no name search.")
  end
  frame:UnregisterAllEvents()
  frame:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
  frame:SetScript("OnEvent", function()
    local best, q, a = ReadBrowse(self.itemID)
    if best then Finish(self, best, q, a, "name search") end
    -- Otherwise keep waiting: more result pages may arrive before the timeout.
  end)
  local query = { searchString = name, sorts = PriceSorts(), filters = {}, itemClassFilters = {} }
  CM.Debug("Step 3: name search for " .. ("%q"):format(name))
  if not CM.Try("SendBrowseQuery", C_AuctionHouse.SendBrowseQuery, query) then
    return Fail(self, "SendBrowseQuery failed.")
  end
  After(self, BROWSE_WAIT, function()
    CM.Debug(("No matching name search result after %d seconds. Reading list directly:"):format(BROWSE_WAIT))
    local best, q, a = ReadBrowse(self.itemID)
    if best then Finish(self, best, q, a, "name search")
    else Fail(self, "no data from either search.") end
  end)
end

-- Step 2: exact item search.
local function Search(self)
  self.step = "search"
  local itemID, itemKey = self.itemID, self.itemKey
  frame:UnregisterAllEvents()
  frame:RegisterEvent("COMMODITY_SEARCH_RESULTS_UPDATED")
  frame:RegisterEvent("ITEM_SEARCH_RESULTS_UPDATED")
  frame:SetScript("OnEvent", function(_, event, arg)
    if event == "COMMODITY_SEARCH_RESULTS_UPDATED" and arg == itemID then
      local best, q, a = ReadCommodity(itemID)
      if best then return Finish(self, best, q, a, "exact search") end
    elseif event == "ITEM_SEARCH_RESULTS_UPDATED" and type(arg) == "table" and arg.itemID == itemID then
      local best, q, a = ReadItems(itemKey)
      if best then return Finish(self, best, q, a, "exact search") end
    else
      return CM.Debug("Results for another item, ignored:", arg)
    end
    CM.Debug("Exact search answered but had no buyout auctions.")
    Browse(self)
  end)
  CM.Debug("Step 2: exact search")
  if not CM.Try("SendSearchQuery", C_AuctionHouse.SendSearchQuery, itemKey, PriceSorts(), false) then
    return Browse(self)
  end
  CM.Print(("Test scan: searching for %s..."):format(ItemName(itemID)))
  After(self, SEARCH_WAIT, function()
    CM.Debug(("No exact search result after %d seconds. Reading lists directly:"):format(SEARCH_WAIT))
    local best, q, a = ReadCommodity(itemID)
    if not best then best, q, a = ReadItems(itemKey) end
    if best then Finish(self, best, q, a, "exact search") else Browse(self) end
  end)
end

-- Step 1: make sure the item's auction house info is loaded.
local function EnsureKeyInfo(self)
  self.step = "keyinfo"
  local ok, info = CM.Try("GetItemKeyInfo(itemKey)", C_AuctionHouse.GetItemKeyInfo, self.itemKey)
  if ok and type(info) == "table" then return Search(self) end
  CM.Debug("Step 1: item info not loaded yet, waiting for ITEM_KEY_ITEM_INFO_RECEIVED")
  frame:RegisterEvent("ITEM_KEY_ITEM_INFO_RECEIVED")
  frame:SetScript("OnEvent", function(_, _, id)
    if id == self.itemID then
      CM.Try("GetItemKeyInfo(itemKey)", C_AuctionHouse.GetItemKeyInfo, self.itemKey)
      Search(self)
    end
  end)
  After(self, KEYINFO_WAIT, function()
    if self.step == "keyinfo" then
      CM.Debug("Item info never arrived, searching anyway.")
      Search(self)
    end
  end)
end

local function StartUnsafe(self, itemID)
  itemID = itemID or self.DEFAULT_ITEM
  if CM.IsDebug() then CM.ShowDebugWindow() end
  CM.Debug(("--- Test scan for %s (itemID %d) ---"):format(ItemName(itemID), itemID))
  if self.busy then CM.Print("Test scan already running."); return end
  if ns.Scanner.state ~= "idle" then CM.Print("Wait for the full scan to finish."); return end
  if not (AuctionHouseFrame and AuctionHouseFrame:IsShown()) then
    CM.Print("Open the auction house first."); return
  end
  if C_AuctionHouse.IsThrottledMessageSystemReady then
    local ready = C_AuctionHouse.IsThrottledMessageSystemReady()
    CM.Debug("IsThrottledMessageSystemReady() = " .. tostring(ready))
    if not ready then CM.Print("The auction house is busy, try again in a second."); return end
  end
  if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(itemID) end
  -- The game rejects a plain number here, so try an item string.
  CM.Try('GetItemCommodityStatus("item:' .. itemID .. '")',
    C_AuctionHouse.GetItemCommodityStatus, "item:" .. itemID)

  local ok, itemKey = CM.Try("MakeItemKey(" .. itemID .. ")", C_AuctionHouse.MakeItemKey, itemID)
  if not ok or type(itemKey) ~= "table" then
    itemKey = { itemID = itemID, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 }
    CM.Debug("Using hand-made itemKey:", itemKey)
  end
  self.busy = true
  self.itemID = itemID
  self.itemKey = itemKey
  self.token = (self.token or 0) + 1
  EnsureKeyInfo(self)
end

function DebugScan:Start(itemID)
  local ok, err = pcall(StartUnsafe, self, itemID)
  if not ok then
    Stop(self)
    CM.Print("Test scan crashed: " .. tostring(err))
  end
end
