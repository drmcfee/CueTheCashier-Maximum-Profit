-- CueTheCashier: public API.
--
-- CueTheCashier.API is the stable way for CueTheCashier's own modules and for
-- other addons to read prices and listen to CueTheCashier. Everything here
-- keeps working the same way while API.VERSION stays the same; anything
-- not in this file may change between CueTheCashier versions.
--
--   local API = CueTheCashier and CueTheCashier.API
--   if API and API.VERSION == 1 then
--     local copper = API.GetPrice(itemID, "auction.market")
--   end
--
-- Prices are copper per single item, or nil when unknown.
--
-- Price sources (API.GetPriceSources() lists them, /cmp sources too):
--   auction.min, auction.market, auction.median, auction.mean, auction.max
--                       last scan: lowest buyout, market value (weighted
--                       average of the cheapest part), median, mean, highest
--   auction.min.7d, auction.market.7d     7-day averages
--   auction.min.30d, auction.market.30d   30-day averages
--   auction.min.all, auction.market.all   average of every scan ever
--   vendor.sell         what a vendor pays you
--   vendor.buy          base price a vendor sells it for (reagents only)
--   disenchant          expected value of disenchanting it (estimate)
--   sale.rate, sale.perday, sale.avg     your own sales on this server
--                       (share of your auctions that sold, items sold per
--                       day, average copper you got each, after the cut)
--   region.market, region.min           averages over every server type
--                       in your region your characters scanned
--   region.salerate, region.perday, region.saleavg
--                       your own sales on all of them added up
--   craft.cost, craft.value, craft.profit   added by CueTheCashier_Crafting
-- Modules can add their own with API.RegisterPriceSource.
--
-- Messages (API.RegisterCallback(owner, message, fn); fn(message, ...)):
--   CM_PRICES_UPDATED (kind, itemCount)    after a scan was saved
--                                           kind = "full", "test" or another
--                                           scanner's name
--   CM_BUYOUT_PLACED (auctionID, itemID, name, copper)
--                                           a buyout was sent to the server
--   CM_STACK_PURCHASE_CONFIRMING (itemID, name, quantity, copper)
--                                           a stack purchase is being confirmed
--   CM_DEBUG_MODE_CHANGED (on)             /cmp debug turned on or off
--   CM_MINIMAP_TOOLTIP (tooltip)           the minimap button tooltip is
--                                           being built: add lines to it
--   CM_MODULE_ENABLED (name), CM_MODULE_DISABLED (name)
--   CM_SHOPPING_LIST_CHANGED ()             the shopping list changed (minor 1)
--   CM_SHOP_ITEM (itemID)                   buy this shopping-list item at
--                                           the open auction house (minor 1)
--   CM_MAIN_WINDOW_SHOW ()                  the main window is opening (minor 2)
--
-- Main window (minor 2, see MainWindow.lua): API.RegisterMainTab,
-- API.RegisterOverviewSection, API.RegisterSettings, API.ShowMainWindow,
-- API.ToggleMainWindow, API.RefreshMainWindow.
--
-- Groups (minor 3, see Groups.lua): API.GetGroups, API.GetItemGroups,
-- API.GetGroupItems, API.GetWinningGroup, API.CreateGroup and friends,
-- API.ExportGroups / API.ImportGroups. Message CM_GROUPS_CHANGED ().
-- Minor 4: the Base Group (API.BASE_GROUP = 0, every item, priority 0),
-- API.AddItemsToGroup, API.FindGroup.
-- Minor 5: price formulas and custom prices (Formulas.lua): API.ParsePrice,
-- API.EvaluatePrice, API.GetCustomPrices, API.SetCustomPrice,
-- API.DeleteCustomPrice, API.GetPriceAliases; operations (Operations.lua):
-- API.GetOperationKinds, API.GetOperationFields, API.GetOperations,
-- API.GetOperation, API.CreateOperation, API.CopyOperation,
-- API.RenameOperation, API.DeleteOperation, API.SetOperationValue,
-- API.GetItemOperation, API.GetOperationPrice. Message CM_OPERATIONS_CHANGED.
-- Minor 6: selling to vendors (VendorSell.lua): API.AddVendorBuy,
-- API.GetVendorBuys, API.GetVendorSellPlan. Message CM_VENDOR_LIST_CHANGED.
-- Minor 7: profiles (Profiles.lua): API.GetProfile, API.GetProfiles,
-- API.UseProfile, API.NewProfile, API.CopyProfile, API.ResetProfile,
-- API.DeleteProfile. Message CM_PROFILE_CHANGED. Mailing (Mailing.lua):
-- API.GetMailPlan.
-- Minor 11 (0.39.0): group priorities (1-100) became unique ranks per item
-- (1 wins). API.GetItemRank, API.SetItemRank, API.MoveItemRank; entries
-- carry .rank instead of .priority; SetGroupPriority and SetItemPriority are gone.
-- Minor 12 (0.42.0): API.GetItemName (asks the game to load names it
-- doesn't have yet), API.GetAuctionSupply (how many were for sale up to a
-- price in the last full scan).
-- Minor 13 (0.43.0): sale and region price sources, API.GetSaleStats,
-- API.SetSaleStats, API.GetRegionStats, API.FormatSourceValue; a price
-- source can say format = "percent" or "number" (not copper).
-- Copyright (C) 2026 Kim. Licensed under the GNU GPL v3 or later; see LICENSE.
local _, CM = ...

local API = { VERSION = 1, MINOR = 14 }
CM.API = API
CM.API_VERSION = API.VERSION

-- Major API version, minor version, CueTheCashier version text.
function API.GetVersion()
  return API.VERSION, API.MINOR, CM.version
end

-- ------------------------------------------------------------------
-- Price sources
-- ------------------------------------------------------------------
local sources, sourceOrder = {}, {}

-- key: unique text like "auction.market". info = { label, description,
-- get = function(itemID) return copper or nil end, format = nil (copper),
-- "percent" (0-1) or "number" }.
function API.RegisterPriceSource(key, info)
  assert(type(key) == "string" and key ~= "", "price source needs a key")
  assert(type(info) == "table" and type(info.get) == "function", "price source needs a get function")
  if not sources[key] then sourceOrder[#sourceOrder + 1] = key end
  sources[key] = { key = key, label = info.label or key, description = info.description, get = info.get,
    format = info.format }
end

-- { { key, label, description }, ... } in the order they were added.
function API.GetPriceSources()
  local list = {}
  for _, key in ipairs(sourceOrder) do
    local s = sources[key]
    list[#list + 1] = { key = s.key, label = s.label, description = s.description, format = s.format }
  end
  return list
end

function API.HasPriceSource(key) return sources[key] ~= nil end

-- A source's value as text: money, "60%" or "1.5" (minor 13).
function API.FormatSourceValue(key, v)
  if type(v) ~= "number" then return nil end
  local f = sources[key] and sources[key].format
  if f == "percent" then return ("%d%%"):format(math.floor(v * 100 + 0.5)) end
  if f == "number" then return v >= 10 and tostring(math.floor(v + 0.5)) or ("%.1f"):format(v) end
  return CM.FormatMoney(math.floor(v + 0.5))
end

-- source: a price source key, or the name of a custom price (minor 5).
function API.GetPrice(itemID, source)
  local s = sources[source]
  if not s and itemID and CM.Formula then return CM.Formula.Custom(source, itemID) end
  if not (s and itemID) then return nil end
  local ok, v = pcall(s.get, itemID)
  if ok and type(v) == "number" then return v end
  return nil
end

-- Every source's value for one item: { [key] = copper }.
function API.GetPrices(itemID)
  local out = {}
  for _, key in ipairs(sourceOrder) do out[key] = API.GetPrice(itemID, key) end
  return out
end

local function Entry(itemID) return CM:GetItemEntry(itemID) end
local function Field(name) return function(id) local e = Entry(id); return e and e[name] end end
local function Avg(field, days) return function(id) return (CM.Data:GetAverage(id, field, days)) end end
local function AllTime(field) return function(id) return (CM.Data:GetAllTimeAverage(id, field)) end end

API.RegisterPriceSource("auction.min", { label = "Lowest buyout", get = Field("minBuyout"),
  description = "Lowest buyout per item in your last scan." })
API.RegisterPriceSource("auction.market", { label = "Market value", get = Field("marketValue"),
  description = "Weighted average of the cheapest part of the market in your last scan." })
API.RegisterPriceSource("auction.median", { label = "Median", get = Field("median"),
  description = "Median buyout per item in your last scan." })
API.RegisterPriceSource("auction.mean", { label = "Mean", get = Field("mean"),
  description = "Average buyout per item in your last scan." })
API.RegisterPriceSource("auction.max", { label = "Highest buyout", get = Field("maxBuyout"),
  description = "Highest buyout per item in your last scan." })
API.RegisterPriceSource("auction.min.7d", { label = "Lowest buyout, 7-day average", get = Avg("min", 7) })
API.RegisterPriceSource("auction.market.7d", { label = "Market value, 7-day average", get = Avg("market", 7) })
API.RegisterPriceSource("auction.min.30d", { label = "Lowest buyout, 30-day average", get = Avg("min", 30) })
API.RegisterPriceSource("auction.market.30d", { label = "Market value, 30-day average", get = Avg("market", 30) })
API.RegisterPriceSource("auction.min.all", { label = "Lowest buyout, all-time average", get = AllTime("min") })
API.RegisterPriceSource("auction.market.all", { label = "Market value, all-time average", get = AllTime("market") })
API.RegisterPriceSource("vendor.sell", { label = "Vendor sell price",
  get = function(id) return CM.Data:GetVendorPrice(id) end,
  description = "What a vendor pays you for one." })
API.RegisterPriceSource("vendor.buy", { label = "Vendor buy price",
  get = function(id) return CM.Data:GetVendorBuyPrice(id) end,
  description = "Base price a vendor sells it for, before reputation discounts (reagents only)." })
API.RegisterPriceSource("disenchant", { label = "Disenchant value",
  get = function(id)
    local v = CM.Disenchant.Value(id)
    return type(v) == "number" and v or nil
  end,
  description = "Expected value of the materials from disenchanting it (classic table, estimate)." })

local function Sale(field) return function(id) local s = CM.Data:GetSaleStats(id); return s and s[field] end end
local function Region(field) return function(id) local r = CM.Data:GetRegion(id); return r and r[field] end end
API.RegisterPriceSource("sale.rate", { label = "Your sale rate", get = Sale("rate"), format = "percent",
  description = "Share of your auctions of it on this server that sold, from your auction mails (needs 2). 0-1 in formulas: 60% is 0.6." })
API.RegisterPriceSource("sale.perday", { label = "Your sold per day", get = Sale("perDay"), format = "number",
  description = "How many you sold on the auction house per day on this server, over the last 30 days." })
API.RegisterPriceSource("sale.avg", { label = "Your average sale price", get = Sale("average"),
  description = "What you got for each one you sold on this server, after the auction house cut." })
API.RegisterPriceSource("region.market", { label = "Region market value", get = Region("market"),
  description = "Market value averaged over every server type in your region that your characters scanned (each server's 30-day average)." })
API.RegisterPriceSource("region.min", { label = "Region lowest buyout", get = Region("min"),
  description = "Lowest buyout averaged over every server type in your region that your characters scanned (each server's 30-day average)." })
API.RegisterPriceSource("region.salerate", { label = "Region sale rate", get = Region("rate"), format = "percent",
  description = "Share of your auctions of it that sold, on all server types and factions in your region." })
API.RegisterPriceSource("region.perday", { label = "Region sold per day", get = Region("perDay"), format = "number",
  description = "How many you sold per day on all server types and factions in your region." })
API.RegisterPriceSource("region.saleavg", { label = "Region average sale price", get = Region("average"),
  description = "What you got for each one you sold in your region, after the auction house cut." })

-- ------------------------------------------------------------------
-- Item data
-- ------------------------------------------------------------------
local function Copy(t, depth)
  if type(t) ~= "table" or depth <= 0 then return t end
  local out = {}
  for k, v in pairs(t) do out[k] = Copy(v, depth - 1) end
  return out
end

-- A copy of everything the last scans saved for an item, or nil:
-- { minBuyout, marketValue, median, mean, maxBuyout, quantity, auctions,
--   sellers, lastSeen, seenInLastScan, week = {...}, month = {...},
--   all = {...}, saleRate, saleRateFrom }
function API.GetItemSummary(itemID)
  return Copy(Entry(itemID), 3)
end

-- Average of "min", "market", "median", "quantity" or "auctions" over the
-- last `days` days. Returns average, days with data.
function API.GetAverage(itemID, field, days)
  return CM.Data:GetAverage(itemID, field, days)
end

-- All-time average of "min" or "market", and the number of scans.
function API.GetAllTimeAverage(itemID, field)
  return CM.Data:GetAllTimeAverage(itemID, field)
end

-- Daily points for the last 30 days (a copy; loads CueTheCashier_History):
-- { { dayStart, min, market, median, quantity, auctions, scans }, ... }
function API.GetHistory(itemID)
  return Copy(CM.Data:GetHistory(itemID), 2)
end

function API.GetSaleRate(itemID) return CM.Data:GetSaleRate(itemID) end
-- Your own sales of an item on a server key (default this one), minor 13:
-- { sold, expired, rate, perDay, itemsSold, money, average } or nil.
function API.GetSaleStats(itemID, key) return CM.Data:GetSaleStats(itemID, key) end
-- Saves one server key's sale numbers (the Accounting module does this).
function API.SetSaleStats(key, stats) CM.Data:SetSaleStats(key, stats) end
-- Region numbers for an item (see Data.lua), minor 13, or nil.
function API.GetRegionStats(itemID) return CM.Data:GetRegion(itemID) end
function API.SetSaleRate(itemID, rate, source) CM.Data:SetSaleRate(itemID, rate, source) end

function API.GetVendorSellPrice(itemID) return CM.Data:GetVendorPrice(itemID) end
function API.GetVendorBuyPrice(itemID) return CM.Data:GetVendorBuyPrice(itemID) end

-- Expected copper from disenchanting one item: value, complete (false when
-- a material has no price yet), or "wait" while the game loads the item,
-- or nil when it can't be disenchanted. itemLevel: the auction's, if known.
function API.GetDisenchantValue(itemID, itemLevel)
  return CM.Disenchant.Value(itemID, itemLevel)
end

-- quality, itemLevel, classID of a disenchantable item, or "wait", or nil.
function API.GetDisenchantInfo(itemID, itemLevel)
  return CM.Disenchant.ItemFacts(itemID, itemLevel)
end

-- What one disenchant gives by the table: { { itemID, chance, min, max }, ... }
function API.GetDisenchantOutcomes(quality, itemLevel, classID)
  return CM.Disenchant.Outcomes(quality, itemLevel, classID)
end

API.DISENCHANT_SPELL = CM.Disenchant.SPELL
API.IsEnchanter = CM.Disenchant.IsEnchanter     -- () -> bool (minor 9)
API.IsBindOnEquip = CM.Disenchant.IsBoE         -- (itemID) -> bool (minor 9)

-- An item's name: the game's, else the one saved from a scan, else nil.
-- When the game hasn't loaded the item yet, it is asked to, and
-- GET_ITEM_INFO_RECEIVED follows (minor 12).
function API.GetItemName(itemID)
  if not itemID then return nil end
  local name = C_Item.GetItemInfo(itemID)
  if name then return name end
  if C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, itemID) end
  local saved = CM.Data:GetItemInfo(itemID)
  if saved and saved.name then return saved.name end
  return C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID) or nil
end

-- How many of an item were for sale at or under maxPrice (copper each) in
-- the last full scan: count, exact (false: rounded down from price steps).
-- nil without scan data (minor 12).
function API.GetAuctionSupply(itemID, maxPrice)
  return CM.Data:GetSupply(itemID, maxPrice)
end

-- Item ID for an item name CueTheCashier has seen (mails only give names).
function API.FindItemID(name) return CM.Data:FindItemID(name) end

-- ------------------------------------------------------------------
-- Scans
-- ------------------------------------------------------------------

-- The key prices are saved under, e.g. "EU Normal - Alliance".
function API.GetServerKey() return CM:GetAuctionKey() end
-- { id, type, region, name } of this server (minor 10): id = the game's
-- server number, type = Normal / PvP / Roleplay / Roleplay PvP / Hardcore.
function API.GetServerInfo()
  return { id = CM.ServerID(), type = CM.ServerType(), region = GetCurrentRegionName and GetCurrentRegionName(),
    name = CM.ServerName() }
end

-- Time of the last full scan on this server (0 = never).
function API.GetLastScanTime() return CM:GetRealmData().lastScan or 0 end

-- Seconds until the account-wide full scan cooldown is over (our timer).
function API.GetFullScanCooldown() return CM.FullScanCooldown() end

-- Saves scan results (for scanner modules, and outside data later).
--   collected[itemID] = { prices = { unitPrice, count, unitPrice, count, ... },
--                         sellers = n, info = { name, quality, level },
--                         minOnly = copper, quantity = n }
--   kind: "full" marks items it didn't see as gone; anything else only
--   touches its own items.
-- Returns the number of items saved and sends CM_PRICES_UPDATED.
function API.RecordScan(collected, kind, totalAuctions)
  local count = CM.Data:Record(collected, kind, totalAuctions)
  CM.SendMessage("CM_PRICES_UPDATED", kind, count)
  return count
end

-- ------------------------------------------------------------------
-- Messages and helpers
-- ------------------------------------------------------------------

-- owner: your addon's name or table (one callback per owner and message).
function API.RegisterCallback(owner, message, fn) CM.RegisterMessage(owner, message, fn) end
function API.UnregisterCallback(owner, message) CM.UnregisterMessage(owner, message) end
function API.UnregisterAllCallbacks(owner) CM.UnregisterAllMessages(owner) end

-- Money text in CueTheCashier's style (1g 05s 00c with coin icons).
function API.FormatMoney(copper) return CM.FormatMoney(copper) end

-- ------------------------------------------------------------------
-- Shopping list (API minor 1)
-- ------------------------------------------------------------------
-- What the player wants to buy, shared between modules: the Crafting
-- module puts the reagents its craft list needs here, the Auctioning
-- module buys the auction ones and Crafting buys the vendor ones at a
-- merchant. Each owner (a module or addon name) sets its own list; the
-- lists are added together. Kept for this session only.
--   items[itemID] = { quantity = n, from = "auction" | "vendor",
--                     maxPrice = copper per item (auction), price = copper
--                     per item the list expects }
local shopping = {}

function API.SetShoppingList(owner, items)
  assert(owner ~= nil, "SetShoppingList needs an owner")
  shopping[owner] = items and next(items) and items or nil
  CM.SendMessage("CM_SHOPPING_LIST_CHANGED")
end

-- Every owner's list added together (a copy). from: only "auction" or
-- "vendor" items, or nil for all.
function API.GetShoppingList(from)
  local out = {}
  for _, items in pairs(shopping) do
    for id, e in pairs(items) do
      if (e.quantity or 0) > 0 and (not from or e.from == from) then
        local o = out[id]
        if o then
          o.quantity = o.quantity + e.quantity
          o.maxPrice = math.max(o.maxPrice or 0, e.maxPrice or 0)
        else
          out[id] = { quantity = e.quantity, from = e.from, maxPrice = e.maxPrice, price = e.price }
        end
      end
    end
  end
  return out
end
