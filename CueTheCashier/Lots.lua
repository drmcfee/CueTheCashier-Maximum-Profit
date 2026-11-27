-- CueTheCashier: posted lots and failed attempts per unit (0.46.1, Kim).
--
-- 0.46.0 counted "failed posts" per item: every expired auction since the
-- last sale. Freshly crafted items then inherited old expirations, and a
-- sale read from the same mailbox visit didn't reset it (Kim's Kaldorei
-- Spider Kabobs: "3 failed, vendor it" although some sold).
--
-- Now each post is a lot: when it was posted and how many. Mail tells what
-- came back expired (or cancelled) and what sold. Units that come back
-- expired carry one more failed try; when posted again they take that
-- count with them. Fresh units (crafted, bought, looted) start at 0 tries.
-- So "Vendor it" only ever means the very units that failed that often.
--
-- Items are alike, so which units go into a post is a choice. Like a
-- player reposting the stack that came back: units that came back go out
-- again first (most tries first), then fresh ones, and last the ones
-- already marked "Vendor it" (the Post scan leaves those out). Sales take
-- the most-tried units of the oldest open lot first.
--
-- Saved: CueTheCashierDB.lots["<server key>"][itemID] = {
--   open = { { t = posted, n = units still out, tries = { [failedBefore] = units } }, ... },
--   back = { [failed] = units back in your bags that failed that many times } }
-- Lots older than 3 days with nothing heard back are dropped.
-- Copyright (C) 2026 Kim. Licensed under the GNU GPL v3 or later; see LICENSE.
local _, CM = ...
local API = CM.API

local Lots = {}
CM.Lots = Lots

local MAX_AGE = 3 * 86400

local function Item(id, make)
  CueTheCashierDB.lots = type(CueTheCashierDB.lots) == "table" and CueTheCashierDB.lots or {}
  local key = CM:GetAuctionKey()
  local s = CueTheCashierDB.lots[key]
  if not s then
    if not make then return nil end
    s = {}
    CueTheCashierDB.lots[key] = s
  end
  local e = s[id]
  if not e and make then
    e = { open = {}, back = {} }
    s[id] = e
  end
  return e
end

local function Sum(t)
  local n = 0
  for _, v in pairs(t) do n = n + v end
  return n
end

-- Takes n units out of a { [tries] = units } table, fewest tries first
-- (most first when mostFirst); only tries below `below` when given.
-- Returns the taken { [tries] = units } and how many were missing.
local function Take(t, n, mostFirst, below)
  local keys = {}
  for k in pairs(t) do if not below or k < below then keys[#keys + 1] = k end end
  table.sort(keys, function(a, b) if mostFirst then return a > b end return a < b end)
  local out = {}
  for _, k in ipairs(keys) do
    if n <= 0 then break end
    local x = math.min(n, t[k])
    t[k] = t[k] - x
    if t[k] <= 0 then t[k] = nil end
    out[k] = (out[k] or 0) + x
    n = n - x
  end
  return out, n
end

local function Tidy(e)
  local now = time()
  for i = #e.open, 1, -1 do
    local lot = e.open[i]
    if lot.n <= 0 or (lot.t or 0) < now - MAX_AGE then table.remove(e.open, i) end
  end
end

-- Units you have of the item (bags and bank). Returned units that are gone
-- (vendored, used, mailed) leave "back", most tries first.
local function Clamp(e, id)
  local ok, have = pcall(C_Item.GetItemCount, id, true)
  if not ok or type(have) ~= "number" then return end
  local over = Sum(e.back) - have
  if over > 0 then Take(e.back, over, true) end
end

-- A post of qty units (from the post hooks below).
function Lots.Posted(id, qty)
  if not (id and qty and qty > 0) then return end
  local e = Item(id, true)
  Tidy(e)
  local ok, have = pcall(C_Item.GetItemCount, id, true)
  have = ok and type(have) == "number" and have or qty
  local fresh = math.max(0, have - Sum(e.back))
  local lot = { t = time(), n = qty, tries = {} }
  local function Add(taken) for k, v in pairs(taken) do lot.tries[k] = (lot.tries[k] or 0) + v end end
  local need = CM.VendorSell and CM.VendorSell.RepostNeed and CM.VendorSell.RepostNeed(id) or math.huge
  -- 1. units that came back but aren't "Vendor it" yet, most tries first
  local taken, rest = Take(e.back, qty, true, need)
  Add(taken)
  -- 2. fresh units
  local fromFresh = math.min(rest, fresh)
  if fromFresh > 0 then lot.tries[0] = (lot.tries[0] or 0) + fromFresh end
  rest = rest - fromFresh
  -- 3. the "Vendor it" ones (posted anyway)
  if rest > 0 then
    taken, rest = Take(e.back, rest, true)
    Add(taken)
    if rest > 0 then lot.tries[0] = (lot.tries[0] or 0) + rest end
  end
  e.open[#e.open + 1] = lot
end

-- Mail: qty units came back. failed = true for expired (one more try),
-- false for cancelled (same tries).
function Lots.Returned(id, qty, failed)
  local e = id and Item(id, false)
  if not e then return end
  for _, lot in ipairs(e.open) do
    if qty <= 0 then break end
    local taken = Take(lot.tries, math.min(qty, lot.n), true)
    local n = Sum(taken)
    lot.n, qty = lot.n - n, qty - n
    for k, v in pairs(taken) do
      local k2 = failed and k + 1 or k
      e.back[k2] = (e.back[k2] or 0) + v
    end
  end
  Tidy(e)
end

-- Mail: qty units sold.
function Lots.Sold(id, qty)
  local e = id and Item(id, false)
  if not e then return end
  for _, lot in ipairs(e.open) do
    if qty <= 0 then break end
    local n = Sum((Take(lot.tries, math.min(qty, lot.n), true)))
    lot.n, qty = lot.n - n, qty - n
  end
  Tidy(e)
end

-- Units in your bags and bank that failed at least `need` times.
function Lots.Tired(id, need)
  local e = Item(id, false)
  if not e then return 0, 0 end
  Clamp(e, id)
  local n, most = 0, 0
  for k, v in pairs(e.back) do
    if k >= need then n = n + v end
    if k > most then most = k end
  end
  return n, most
end

-- The posts themselves: Blizzard's window and ours both end in these calls.
if C_AuctionHouse and hooksecurefunc then
  local function ItemOf(loc)
    local ok, id = pcall(C_Item.GetItemID, loc)
    return ok and id or nil
  end
  if C_AuctionHouse.PostItem then
    hooksecurefunc(C_AuctionHouse, "PostItem", function(loc, _, qty)
      CM.Try("Lot posted", Lots.Posted, ItemOf(loc), tonumber(qty) or 1)
    end)
  end
  if C_AuctionHouse.PostCommodity then
    hooksecurefunc(C_AuctionHouse, "PostCommodity", function(loc, _, qty)
      CM.Try("Lot posted", Lots.Posted, ItemOf(loc), tonumber(qty) or 1)
    end)
  end
end

API.LotReturned = Lots.Returned -- (itemID, qty, expired) (API minor 15)
API.LotSold = Lots.Sold         -- (itemID, qty) (API minor 15)
