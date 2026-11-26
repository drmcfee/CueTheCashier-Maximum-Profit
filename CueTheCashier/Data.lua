-- CueTheCashier: price data, statistics and history.
--
-- Saved data is split in two so the game doesn't load everything at once:
--
-- CueTheCashierDB (this addon, loaded at login): small, one summary per item.
--   itemInfo[itemID] = { name, quality, level, classID, subclassID, vendorPrice }
--   realms["<server> - <faction>"] = {
--     lastScan, scans = { { time, kind, auctions, items }, ... } (last 100)
--     items[itemID] = {
--       -- Latest scan (copper per single item):
--       minBuyout, marketValue, median, mean, maxBuyout,
--       quantity, auctions, sellers, lastSeen, seenInLastScan, belowVendor,
--       -- Averages, updated after every scan:
--       week  = { min, market, median, quantity, auctions, n = days },
--       month = { same, 30 days },
--       all   = { min, market, nMin, nMarket, since }  -- every scan ever
--       -- Sale rate (0-1): not visible in game; filled from outside data
--       -- later (Data:SetSaleRate).
--       saleRate, saleRateFrom,
--     }
--   }
--
-- CueTheCashierHistoryDB (the CueTheCashier_History addon, load on demand:
-- loaded when you scan or ask for a span other than 7/30 days):
--   ["<server> - <faction>"][itemID] = { point, point, ... } oldest first,
--   one point per day for the last 30 days:
--   { dayStart, min, market, median, quantity, auctions, scans }
--   min is the day's lowest; the others are the day's average.
--   0 means "not known" (a name search only gives min).
--   Without the CueTheCashier_History folder, history is kept in
--   CueTheCashierDB.history instead and moved over once it is installed.
-- Copyright (C) 2026 Kim. Licensed under the GNU GPL v3 or later; see LICENSE.
local _, CM = ...

local Data = {}
CM.Data = Data

local DAY = 86400
local KEEP_DAYS = 30
local MAX_SCAN_LOG = 100
local HISTORY_ADDON = "CueTheCashier_History"

-- History point positions, so the arrays stay readable in code.
local H = { time = 1, min = 2, market = 3, median = 4, quantity = 5, auctions = 6, scans = 7 }
Data.H = H
local FIELDS = { "min", "market", "median", "quantity", "auctions" }

-- Turns a flat list { unitPrice, count, unitPrice, count, ... } into stats.
-- Market value works like TSM's: a quantity-weighted average of the
-- cheapest part of the market, ignoring a few extreme cheap/expensive
-- outliers, so one silly listing does not swing the price.
function Data.Summarize(flat)
  local rows = {}
  for i = 1, #flat, 2 do
    rows[#rows + 1] = { flat[i], flat[i + 1] }
  end
  if #rows == 0 then return nil end
  table.sort(rows, function(a, b) return a[1] < b[1] end)

  local total, sum = 0, 0
  for _, r in ipairs(rows) do
    total = total + r[2]
    sum = sum + r[1] * r[2]
  end

  -- Median: the price of the item in the middle of the quantity.
  local median, seen = rows[#rows][1], 0
  for _, r in ipairs(rows) do
    seen = seen + r[2]
    if seen >= total / 2 then median = r[1]; break end
  end

  -- Market value: always take the cheapest 15% of the quantity, then keep
  -- going up to 30% while each price is at most 20% above the one before.
  local mvQty, mvSum, prev = 0, 0, nil
  for _, r in ipairs(rows) do
    local u, c = r[1], r[2]
    local inFirst = mvQty < total * 0.15
    local inSecond = mvQty < total * 0.30 and prev and u <= prev * 1.2
    if mvQty > 0 and not inFirst and not inSecond then break end
    mvQty = mvQty + c
    mvSum = mvSum + u * c
    prev = u
  end

  return {
    minBuyout = rows[1][1],
    maxBuyout = rows[#rows][1],
    mean = math.floor(sum / total),
    median = median,
    marketValue = math.floor(mvSum / mvQty),
    quantity = total,
    auctions = #rows,
  }
end

-- ------------------------------------------------------------------
-- History (separate load-on-demand addon)
-- ------------------------------------------------------------------
local fallbackWarned = false

-- The whole history table, loading CueTheCashier_History if needed.
function Data:History()
  if type(CueTheCashierHistoryDB) ~= "table" then
    local load = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
    if load then pcall(load, HISTORY_ADDON) end
  end
  CM.AdoptOldSaved("CueTheCashierHistoryDB")
  if type(CueTheCashierHistoryDB) == "table" then
    -- History kept in the main file while the folder was missing: move it.
    local old = CueTheCashierDB.history
    if old then
      for key, items in pairs(old) do
        local dest = CueTheCashierHistoryDB[key] or {}
        for id, points in pairs(items) do dest[id] = dest[id] or points end
        CueTheCashierHistoryDB[key] = dest
      end
      CueTheCashierDB.history = nil
    end
    return CueTheCashierHistoryDB
  end
  if not fallbackWarned and CM.Print then
    fallbackWarned = true
    CM.Print("The CueTheCashier_History folder is missing, so price history is kept in the main file. "
      .. "Copy both folders from the zip to your AddOns folder.")
  end
  CueTheCashierDB.history = CueTheCashierDB.history or {}
  return CueTheCashierDB.history
end

function Data:IsHistoryLoaded() return type(CueTheCashierHistoryDB) == "table" end

local function RealmHistory(key)
  local h = Data:History()
  h[key] = h[key] or {}
  return h[key]
end

-- Start of the local day.
local function DayStart(t)
  local d = date("*t", t)
  return time({ year = d.year, month = d.month, day = d.day, hour = 0 })
end
Data.DayStart = DayStart

-- Adds one scan to the day's point (min = lowest, others = average) and
-- drops days older than KEEP_DAYS.
local function AddPoint(points, t, values)
  local day = DayStart(t)
  local last = points[#points]
  if last and last[H.time] == day then
    local n = last[H.scans] or 1
    local v = values[H.min]
    if v > 0 and (last[H.min] == 0 or v < last[H.min]) then last[H.min] = v end
    for f = H.market, H.auctions do
      v = values[f]
      if v > 0 then
        last[f] = last[f] == 0 and v or math.floor((last[f] * n + v) / (n + 1) + 0.5)
      end
    end
    last[H.scans] = n + 1
  else
    points[#points + 1] = { day, values[H.min], values[H.market], values[H.median],
      values[H.quantity], values[H.auctions], 1 }
  end
  local oldest = day - (KEEP_DAYS - 1) * DAY
  while points[1] and points[1][H.time] < oldest - 3600 do table.remove(points, 1) end
end

-- Average of every field over the last `days` days of points.
-- Returns { min, market, median, quantity, auctions, n = days with data }.
local function Averages(points, days, now)
  local from = DayStart(now) - (days - 1) * DAY - 3600 -- an hour of slack for summer time
  local out, n = { n = 0 }, 0
  for _, name in ipairs(FIELDS) do
    local f, sum, cnt = H[name], 0, 0
    for _, p in ipairs(points) do
      if p[H.time] >= from and p[f] > 0 then sum, cnt = sum + p[f], cnt + 1 end
    end
    if cnt > 0 then out[name] = math.floor(sum / cnt + 0.5) end
    if cnt > n then n = cnt end
  end
  out.n = n
  if n == 0 then return nil end
  return out
end

-- Running all-time average, one count per scan.
local function AddToAll(all, minV, marketV, t)
  all = all or { nMin = 0, nMarket = 0, since = t }
  if minV and minV > 0 then
    all.min = math.floor(((all.min or 0) * all.nMin + minV) / (all.nMin + 1) + 0.5)
    all.nMin = all.nMin + 1
  end
  if marketV and marketV > 0 then
    all.market = math.floor(((all.market or 0) * all.nMarket + marketV) / (all.nMarket + 1) + 0.5)
    all.nMarket = all.nMarket + 1
  end
  return all
end

local function UpdateAverages(entry, points, now)
  entry.week = Averages(points, 7, now)
  entry.month = Averages(points, KEEP_DAYS, now)
end

-- Vendor sell price (copper) for one item. Read from the same data the
-- item tooltip uses for its "Sell Price" line, because that is the number
-- a vendor really pays. C_Item.GetItemInfo's sellPrice is only a fallback
-- (it gave wrong numbers for some patterns in game).
-- Saved in itemInfo so we only need to look it up once per item.
local function TooltipSellPrice(itemID)
  if not (C_TooltipInfo and C_TooltipInfo.GetItemByID) then return nil end
  local ok, data = pcall(C_TooltipInfo.GetItemByID, itemID)
  if not (ok and data and data.lines) then return nil end
  local sellType = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.SellPrice
  local found = false
  for _, line in ipairs(data.lines) do
    if (sellType and line.type == sellType) or (line.price and not sellType) then
      return line.price or 0
    end
    if line.leftText then found = true end
  end
  -- A loaded tooltip without a Sell Price line: vendors don't buy it.
  if found and C_Item.GetItemInfo(itemID) then return 0 end
  return nil
end

function Data:GetVendorPrice(itemID)
  local entry = CueTheCashierDB.itemInfo[itemID]
  if entry and entry.vendorPrice and entry.vendorFrom == "tooltip" then return entry.vendorPrice end
  if not (C_Item and C_Item.GetItemInfo) then return nil end
  local name, _, _, _, _, _, _, _, _, _, sellPrice = C_Item.GetItemInfo(itemID)
  if not name then return nil end -- not loaded yet; GET_ITEM_INFO_RECEIVED follows
  local tip = TooltipSellPrice(itemID)
  if tip and sellPrice and tip ~= sellPrice and CM.Debug then
    CM.Debug(("Vendor price %s (%d): tooltip %d, GetItemInfo %d."):format(name, itemID, tip, sellPrice))
  end
  entry = entry or {}
  entry.vendorPrice = tip or sellPrice or 0
  entry.vendorFrom = tip and "tooltip" or nil -- GetItemInfo values are looked up again next time
  CueTheCashierDB.itemInfo[itemID] = entry
  return entry.vendorPrice
end

-- Item ID from an item name (mails only give names). Looks through the
-- items we have seen; nil when unknown.
local nameCache = {}
function Data:FindItemID(name)
  if not name then return nil end
  if nameCache[name] then return nameCache[name] end
  for id, info in pairs(CueTheCashierDB.itemInfo) do
    if info.name == name then nameCache[name] = id; return id end
  end
  if C_Item and C_Item.GetItemInfoInstant then
    local ok, id = pcall(C_Item.GetItemInfoInstant, name)
    if ok and type(id) == "number" then nameCache[name] = id; return id end
  end
end

-- For /cmp vendor: every source we know, to compare with the tooltip.
function Data:VendorPriceReport(itemID)
  local name, _, _, _, _, _, _, stack, _, _, sellPrice = C_Item.GetItemInfo(itemID)
  local saved = CueTheCashierDB.itemInfo[itemID]
  return name, TooltipSellPrice(itemID), sellPrice, stack, saved and saved.vendorPrice
end

local function SaveItemInfo(itemID, info)
  local db = CueTheCashierDB.itemInfo
  Data:GetVendorPrice(itemID)
  if db[itemID] and db[itemID].name then return end
  local entry = db[itemID] or {}
  if info then
    entry.name = entry.name or info.name
    entry.quality = entry.quality or info.quality
    entry.level = entry.level or info.level
  end
  if not entry.classID and C_Item and C_Item.GetItemInfoInstant then
    local ok, _, _, _, _, _, classID, subclassID = pcall(C_Item.GetItemInfoInstant, itemID)
    if ok then entry.classID, entry.subclassID = classID, subclassID end
  end
  db[itemID] = entry
end

Data.DEPTH_STEPS = { 1, 1.1, 1.2, 1.35, 1.5, 2, 3 }

-- How many of an item were for sale at or under a price in the last scan:
-- count, exact. Counted from the steps above, so "at or under" rounds
-- down to the nearest step (never more than were there). nil when the
-- item has no scan data or was scanned before 0.42.0.
function Data:GetSupply(itemID, maxPrice)
  local entry = CM:GetItemEntry(itemID)
  if not (entry and maxPrice) then return nil end
  if not entry.seenInLastScan then return 0, true end
  local min, depth = entry.minBuyout, entry.depth
  if not (min and min > 0) then return nil end
  if maxPrice < min then return 0, true end
  if entry.maxBuyout and maxPrice >= entry.maxBuyout and entry.quantity then return entry.quantity, true end
  if type(depth) ~= "table" then return nil end
  local n = 0
  for i, step in ipairs(Data.DEPTH_STEPS) do
    if min * step <= maxPrice and depth[i] then n = depth[i] end
  end
  return n, false
end

-- Saves one scan.
--   collected[itemID] = { prices = { unit, count, ... }, sellers = n,
--                         info = { name, quality, level }, minOnly = copper }
--   kind = "full" or "test". A full scan marks items it did not see as not
--   seen; a test scan only touches its own item.
function Data:Record(collected, kind, totalAuctions)
  local realm = CM:GetRealmData()
  local now = time()
  local items = realm.items
  local hist = RealmHistory(CM:GetAuctionKey())
  if kind == "full" then
    for _, entry in pairs(items) do entry.seenInLastScan = false end
  end
  -- Commodities are saved a second time under the region's shared key (0.44.0).
  local shared = CM:GetSharedData()
  local sharedHist = shared and RealmHistory(CM.SharedKey())
  if shared and kind == "full" then
    for _, entry in pairs(shared.items) do entry.seenInLastScan = false end
  end
  local count = 0
  for itemID, c in pairs(collected) do
    local stats = c.prices and #c.prices > 0 and Data.Summarize(c.prices)
    if not stats and c.minOnly then
      stats = { minBuyout = c.minOnly, quantity = c.quantity or 0, auctions = 0 }
    end
    if stats then
      SaveItemInfo(itemID, c.info)
      local targets = { { items, hist } }
      if shared and CM.IsCommodity(itemID) then targets[2] = { shared.items, sharedHist } end
      for _, target in ipairs(targets) do
        Data.SaveScanEntry(target[1], target[2], itemID, c, stats, now)
      end
      count = count + 1
    end
  end
  if kind == "full" then
    realm.lastScan = now
    if shared then shared.lastScan = now end
  end
  realm.scans = realm.scans or {}
  table.insert(realm.scans, { now, kind, totalAuctions or 0, count })
  while #realm.scans > MAX_SCAN_LOG do table.remove(realm.scans, 1) end
  return count
end

-- One item's scan into one store (items + its history).
function Data.SaveScanEntry(items, hist, itemID, c, stats, now)
  do
    do
      local entry = items[itemID] or {}
      for k, v in pairs(stats) do entry[k] = v end
      if not stats.marketValue then
        -- Partial data: keep old detail fields rather than mixing scans.
        entry.marketValue, entry.median, entry.mean, entry.maxBuyout = nil, nil, nil, nil
      end
      entry.sellers = c.sellers
      entry.lastSeen = now
      entry.seenInLastScan = true
      local points = hist[itemID] or {}
      AddPoint(points, now, { now, stats.minBuyout or 0, stats.marketValue or 0,
        stats.median or 0, stats.quantity or 0, stats.auctions or 0 })
      hist[itemID] = points
      UpdateAverages(entry, points, now)
      entry.all = AddToAll(entry.all, stats.minBuyout, stats.marketValue, now)
      items[itemID] = entry
      -- Listings below the vendor sell price: how many, and the profit if
      -- you buy them all and sell them to a vendor.
      -- How many are for sale up to a few steps over the cheapest (0.42.0):
      -- depth[i] = count at or under minBuyout * DEPTH_STEPS[i]. Full
      -- scans only (a test scan sees one page).
      if c.prices and stats.minBuyout and stats.minBuyout > 0 then
        local depth = {}
        for i, step in ipairs(Data.DEPTH_STEPS) do
          local limit, n = stats.minBuyout * step, 0
          for j = 1, #c.prices, 2 do
            if c.prices[j] <= limit then n = n + c.prices[j + 1] end
          end
          depth[i] = n
        end
        entry.depth = depth
      end
      entry.belowVendor = nil
      local vendor = Data:GetVendorPrice(itemID)
      if vendor and vendor > 0 and c.prices then
        local qty, profit = 0, 0
        for i = 1, #c.prices, 2 do
          local unit, n = c.prices[i], c.prices[i + 1]
          if unit < vendor then qty = qty + n; profit = profit + (vendor - unit) * n end
        end
        if qty > 0 then entry.belowVendor = { qty, profit } end
      end
    end
  end
end

-- Average of one field over the last `days` days.
-- field: "min", "market", "median", "quantity" or "auctions".
-- 7 and 30 days come from the item's summary (no history load); other
-- spans load the history. Returns average, days with data (or nil).
function Data:GetAverage(itemID, field, days)
  local entry = CM:GetItemEntry(itemID)
  if not (entry and H[field]) then return nil end
  local a
  if days == 7 then
    a = entry.week
  elseif days == KEEP_DAYS then
    a = entry.month
  else
    local _, key = CM:GetItemEntryAndKey(itemID)
    local points = RealmHistory(key or CM:GetAuctionKey())[itemID]
    a = points and Averages(points, days, time())
  end
  if a and a[field] then return a[field], a.n end
  return nil
end

-- All-time average of "min" or "market" (every scan ever), and the number
-- of scans it covers.
function Data:GetAllTimeAverage(itemID, field)
  local entry = CM:GetItemEntry(itemID)
  local all = entry and entry.all
  if not all then return nil end
  if field == "min" and all.min then return all.min, all.nMin end
  if field == "market" and all.market then return all.market, all.nMarket end
end

-- Daily history points for one item (loads the history).
function Data:GetHistory(itemID)
  local _, key = CM:GetItemEntryAndKey(itemID)
  return RealmHistory(key or CM:GetAuctionKey())[itemID] or {}
end

-- Sale rate set from outside (API.SetSaleRate), shown when your own
-- auctions don't give one (see Data:GetSaleRate).
function Data:SetSaleRate(itemID, rate, source)
  local entry = CM:GetRealmData().items[itemID]
  if not entry then
    entry = {}
    CM:GetRealmData().items[itemID] = entry
  end
  entry.saleRate, entry.saleRateFrom = rate, source
end

function Data:GetSaleRate(itemID)
  local st = Data:GetSaleStats(itemID)
  if st and st.rate then
    return st.rate, ("%d of your %d auctions sold"):format(st.sold, st.sold + st.expired)
  end
  local entry = CM:GetRealmData().items[itemID]
  return entry and entry.saleRate, entry and entry.saleRateFrom
end

-- ------------------------------------------------------------------
-- Your own sales (0.43.0)
--
-- Worked out by the Accounting module from its ledger, for every server
-- and faction you have a ledger on, and saved here so tooltips and price
-- sources have them without loading Accounting:
--   CueTheCashierDB.sales["<server> - <faction>"] = {
--     t = when worked out, days = days of ledger it covers (1-30),
--     items = { [itemID] = { sold, expired, sold30, itemsSold, money } } }
--   sold / expired  your auctions that sold / ran out (all you have)
--   sold30          items sold on the AH in the last 30 days
--   itemsSold/money items sold on the AH and the money you got (after the cut)
-- It is rebuilt from the ledger each time, so nothing is lost if it goes.
-- ------------------------------------------------------------------
Data.MIN_AUCTIONS = 2 -- auctions needed before a sale rate is shown

local function SaleTables()
  local s = CueTheCashierDB.sales
  if type(s) ~= "table" then s = {}; CueTheCashierDB.sales = s end
  return s
end

-- Called by Accounting with one server key's numbers.
function Data:SetSaleStats(key, stats)
  if type(key) ~= "string" or type(stats) ~= "table" or type(stats.items) ~= "table" then return end
  SaleTables()[key] = stats
end

-- Turns the saved numbers for one or more keys into rates. nil if none.
local function SaleSummary(rows)
  local sold, expired, perDay, items, money, any = 0, 0, 0, 0, 0, false
  for _, r in ipairs(rows) do
    local c, days = r[1], r[2]
    any = true
    sold, expired = sold + (c[1] or 0), expired + (c[2] or 0)
    perDay = perDay + (c[3] or 0) / math.max(1, days or 30)
    items, money = items + (c[4] or 0), money + (c[5] or 0)
  end
  if not any then return nil end
  local out = { sold = sold, expired = expired, perDay = perDay, itemsSold = items, money = money }
  if sold + expired >= Data.MIN_AUCTIONS then out.rate = sold / (sold + expired) end
  if items > 0 then out.average = math.floor(money / items + 0.5) end
  return out
end

-- Your own sales of an item on one server key (default: this one):
-- { sold, expired, rate (0-1 or nil), perDay, itemsSold, money, average }.
function Data:GetSaleStats(itemID, key)
  local t = SaleTables()[key or CM:GetAuctionKey()]
  local c = t and t.items and t.items[itemID]
  if not c then return nil end
  return SaleSummary({ { c, t.days } })
end

-- ------------------------------------------------------------------
-- Region (0.43.0)
--
-- Forever puts every server type of a region (EU, US) on mega servers.
-- Region numbers merge what your characters saw on all of them: every
-- "<region> <type> - <faction>" key in CueTheCashierDB.realms and .sales.
-- Nothing extra is saved: it is worked out when asked.
--   market / min   average over the servers of each one's 30-day market
--                  value / lowest buyout (its last scan when no average)
--   servers        how many servers gave a price, and keys = their names
--   sale numbers   your auctions on all of them added up
-- Servers not scanned for 30 days are left out of the prices.
--
-- Outside data: when an addon file sets the global CueTheCashierAppData
-- (the planned desktop app will write one), its numbers win:
--   CueTheCashierAppData = { time = <unix time>, region = { ["EU"] = {
--     [itemID] = { market =, min =, saleRate =, perDay =, saleAvg = } } } }
-- ------------------------------------------------------------------
local REGION_MAX_AGE = 30 * DAY

function Data.RegionName()
  local r = GetCurrentRegionName and GetCurrentRegionName()
  if type(r) == "string" and r ~= "" then return r end
  local key = CM:GetAuctionKey()
  return key:match("^(%S+) ") or ""
end

-- The keys of this region, e.g. "EU Normal - Alliance", "EU PvP - Horde".
function Data:RegionKeys(store)
  local region, out = Data.RegionName(), {}
  if region == "" then return out end
  local prefix, shared = region .. " ", CM.SharedKey()
  for key in pairs(store or {}) do
    if type(key) == "string" and key ~= shared and key:sub(1, #prefix) == prefix then out[#out + 1] = key end
  end
  table.sort(out)
  return out
end

local function AppRegion(itemID)
  local app = CueTheCashierAppData
  local r = type(app) == "table" and type(app.region) == "table" and app.region[Data.RegionName()]
  local e = type(r) == "table" and r[itemID]
  if type(e) == "table" then return e end
end

-- One server's price for the region average: 30-day average, else last scan.
local function ServerPrice(entry, field)
  if field == "market" then
    return (entry.month and entry.month.market) or entry.marketValue
  end
  return (entry.month and entry.month.min) or entry.minBuyout
end

-- Every server's numbers for one item, for /cmp region:
-- { { key, min, market, lastSeen }, ... }
function Data:RegionRows(itemID)
  local rows = {}
  for _, key in ipairs(self:RegionKeys(CueTheCashierDB.realms)) do
    local e = CueTheCashierDB.realms[key].items and CueTheCashierDB.realms[key].items[itemID]
    if e then rows[#rows + 1] = { key, e.minBuyout, e.marketValue, e.lastSeen, ServerPrice(e, "min"), ServerPrice(e, "market") } end
  end
  local shared = CM.SharedKey()
  local s = shared and CueTheCashierDB.realms[shared]
  local e = s and s.items and s.items[itemID]
  if e then rows[#rows + 1] = { shared, e.minBuyout, e.marketValue, e.lastSeen, ServerPrice(e, "min"), ServerPrice(e, "market") } end
  return rows
end

-- { market, min, servers, keys, otherServers, sold, expired, rate, perDay,
--   average, fromApp } for one item, or nil when nothing is known.
-- otherServers: true when a server other than this one added something.
function Data:GetRegion(itemID)
  if not itemID then return nil end
  local here, now = CM:GetAuctionKey(), time()
  local out, sums = { keys = {}, servers = 0 }, { market = { 0, 0 }, min = { 0, 0 } }
  for _, key in ipairs(self:RegionKeys(CueTheCashierDB.realms)) do
    local e = CueTheCashierDB.realms[key].items and CueTheCashierDB.realms[key].items[itemID]
    if e and (e.lastSeen or 0) >= now - REGION_MAX_AGE then
      local got = false
      for field, sum in pairs(sums) do
        local v = ServerPrice(e, field)
        if v and v > 0 then sum[1], sum[2], got = sum[1] + v, sum[2] + 1, true end
      end
      if got then
        out.servers = out.servers + 1
        out.keys[#out.keys + 1] = key
        if key ~= here then out.otherServers = true end
      end
    end
  end
  for field, sum in pairs(sums) do
    if sum[2] > 0 then out[field] = math.floor(sum[1] / sum[2] + 0.5) end
  end
  local sales, rows = SaleTables(), {}
  for _, key in ipairs(self:RegionKeys(sales)) do
    local c = sales[key].items and sales[key].items[itemID]
    if c then
      rows[#rows + 1] = { c, sales[key].days }
      if key ~= here then out.otherServers = true end
    end
  end
  local s = SaleSummary(rows)
  if s then
    out.sold, out.expired, out.rate, out.perDay, out.average = s.sold, s.expired, s.rate, s.perDay, s.average
  end
  local app = AppRegion(itemID)
  if app then
    out.fromApp = true
    out.market = tonumber(app.market) or out.market
    out.min = tonumber(app.min) or out.min
    out.rate = tonumber(app.saleRate) or out.rate
    out.perDay = tonumber(app.perDay) or out.perDay
    out.average = tonumber(app.saleAvg) or out.average
  end
  if not (out.market or out.min or out.rate or out.perDay or out.average) then return nil end
  return out
end

function Data:GetItemInfo(itemID)
  return CueTheCashierDB.itemInfo[itemID]
end

-- Upgrades data saved by older versions instead of throwing it away.
function Data.Migrate(db)
  db.itemInfo = db.itemInfo or {}
  if (db.dbVersion or 1) < 2 then
    for _, realm in pairs(db.realms or {}) do
      realm.scans = realm.scans or {}
      for _, entry in pairs(realm.items or {}) do
        if not entry.history and entry.minBuyout then
          entry.history = { { entry.lastSeen or realm.lastScan or time(), entry.minBuyout,
            0, 0, entry.quantity or 0, entry.auctions or 0 } }
        end
      end
    end
    db.dbVersion = 2
  end
  if db.dbVersion < 3 then
    -- 0.11.0: per-item history moves to CueTheCashier_History as one point
    -- per day (last 30 days); the item keeps week/month/all-time averages.
    local now = time()
    for key, realm in pairs(db.realms or {}) do
      local hist
      for id, entry in pairs(realm.items or {}) do
        if entry.history then
          hist = hist or RealmHistory(key)
          local points = {}
          for _, e in ipairs(entry.history) do
            if e[H.time] >= now - KEEP_DAYS * DAY then AddPoint(points, e[H.time], e) end
            entry.all = AddToAll(entry.all, e[H.min], e[H.market], e[H.time])
          end
          if #points > 0 then hist[id] = points end
          UpdateAverages(entry, points, now)
          entry.history = nil
        end
      end
    end
    db.dbVersion = 3
  end
end
