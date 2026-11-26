-- CueTheCashier Crafting: what a craft costs and what it earns.
--
-- Craft cost = every required reagent, each at its cheapest way to get it:
--   * the auction house (market value, else lowest buyout),
--   * a vendor (base vendor price, only for reagents vendors sell), or
--   * crafting it yourself, when one of your characters knows a recipe
--     for it (up to two steps down, e.g. bars for a bolt for a shirt).
-- Craft value = what the result sells for on the auction house (market
-- value, else lowest buyout). Profit = value after the auction house cut
-- minus the craft cost. All per craft; a recipe that makes 2-4 counts 3.
--
-- Price sources (CueTheCashier.API, per single item, for items one of your
-- characters can craft):
--   craft.cost    cheapest craft cost of one
--   craft.value   auction house value of one
--   craft.profit  value after the cut minus craft cost
-- Copyright (C) 2026 Kim. Licensed under the GNU GPL v3 or later; see LICENSE.
local _, ns = ...
local CM = CueTheCashier
local API = CM.API

local C = {}
ns.Costs = C

-- The auction house cut: 5% at a faction auction house (seen on Forever),
-- more at a neutral one. Comes from the core (API minor 8).
function C.Cut() return API.GetAuctionCutRate and API.GetAuctionCutRate() or 0.05 end
local MAX_DEPTH = 2

local recipeCache, itemCache = {}, {}

function C.Changed()
  recipeCache, itemCache = {}, {}
  ns.Debounce("Profession window refresh", 0.2, ns.UI.Refresh)
end

local function AuctionValue(itemID)
  local v = API.GetPrice(itemID, "auction.market")
  if v then return v, "auction" end
  v = API.GetPrice(itemID, "auction.min")
  if v then return v, "auction (lowest buyout)" end
end
C.AuctionValue = AuctionValue

local ItemCraftCost

-- Cheapest price of one reagent: copper, how ("auction", "vendor", "craft").
function C.ReagentPrice(itemID, depth, visiting)
  local best, how = AuctionValue(itemID)
  local vendor = API.GetPrice(itemID, "vendor.buy")
  if vendor and (not best or vendor < best) then best, how = vendor, "vendor" end
  if (depth or 0) < MAX_DEPTH and not (visiting and visiting[itemID]) then
    local craft = ItemCraftCost(itemID, (depth or 0) + 1, visiting)
    if craft and (not best or craft < best) then best, how = craft, "craft" end
  end
  return best, how
end

-- Everything about one craft of a recipe, or nil when its facts are unknown:
-- { recipe, cost, complete, parts = { { id, qty, each, how }, ... },
--   made, value (each), net (all made, after the cut), profit, perItem }
function C.Recipe(recipeID, depth, visiting)
  depth = depth or 0
  if depth == 0 and recipeCache[recipeID] ~= nil then return recipeCache[recipeID] or nil end
  local r = ns.Recipes.Get(recipeID)
  if not r then
    if depth == 0 then recipeCache[recipeID] = false end
    return nil
  end
  visiting = visiting or {}
  if r.out then visiting[r.out] = true end
  local total, complete, parts = 0, true, {}
  for _, e in ipairs(r.reagents) do
    local each, how, id = C.ReagentPrice(e.id, depth, visiting)
    id = e.id
    for _, alt in ipairs(e.alt or {}) do
      local p, h = C.ReagentPrice(alt, depth, visiting)
      if p and (not each or p < each) then each, how, id = p, h, alt end
    end
    if each then total = total + each * e.qty else complete = false end
    parts[#parts + 1] = { id = id, qty = e.qty, each = each, how = how }
  end
  if r.out then visiting[r.out] = nil end
  local made = ((r.q1 or 1) + (r.q2 or r.q1 or 1)) / 2
  local value = r.out and AuctionValue(r.out)
  local net = value and math.floor(value * made * (1 - C.Cut()))
  local res = {
    recipe = r, cost = math.floor(total + 0.5), complete = complete, parts = parts, made = made,
    value = value, net = net, perItem = complete and total / made or nil,
    profit = (net and complete) and (net - math.floor(total + 0.5)) or nil,
  }
  if depth == 0 then recipeCache[recipeID] = res end
  return res
end

-- Cheapest complete craft cost of one item from recipes you know.
ItemCraftCost = function(itemID, depth, visiting)
  depth = depth or 0
  if depth == 0 and itemCache[itemID] ~= nil then return itemCache[itemID] or nil end
  local best
  for _, id in ipairs(ns.Recipes.ForOutput(itemID, true)) do
    local res = C.Recipe(id, depth, visiting)
    if res and res.perItem and (not best or res.perItem < best) then best = res.perItem end
  end
  if depth == 0 then itemCache[itemID] = best or false end
  return best
end
C.ItemCraftCost = ItemCraftCost

-- The known recipe that makes an item cheapest, and its result.
function C.BestRecipeFor(itemID)
  local bestID, best
  for _, id in ipairs(ns.Recipes.ForOutput(itemID, true)) do
    local res = C.Recipe(id)
    if res and res.perItem and (not best or res.perItem < best.perItem) then bestID, best = id, res end
  end
  return bestID, best
end

local function CanCraft(itemID) return #ns.Recipes.ForOutput(itemID, true) > 0 end

API.RegisterPriceSource("craft.cost", { label = "Craft cost",
  get = function(id) local v = ItemCraftCost(id); return v and math.floor(v + 0.5) end,
  description = "Cheapest cost to craft one with a recipe one of your characters knows (reagents at auction, vendor or own craft price)." })
API.RegisterPriceSource("craft.value", { label = "Craft value",
  get = function(id) if CanCraft(id) then return (AuctionValue(id)) end end,
  description = "Auction house value of one item you can craft." })
API.RegisterPriceSource("craft.profit", { label = "Craft profit",
  get = function(id)
    local cost, value = ItemCraftCost(id), AuctionValue(id)
    if cost and value then return math.floor(value * (1 - C.Cut()) - cost + 0.5) end
  end,
  description = "Profit on one item you craft: auction value after the 5% cut minus craft cost." })

-- Plain money text for the log (no coin icons): 1g 05s 00c, 5s 03c, 7c.
function ns.MoneyText(copper)
  if not copper then return "?" end
  local neg = copper < 0
  copper = math.floor(math.abs(copper) + 0.5)
  local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
  local text
  if g > 0 then text = ("%dg %02ds %02dc"):format(g, s, c)
  elseif s > 0 then text = ("%ds %02dc"):format(s, c)
  else text = ("%dc"):format(c) end
  return (neg and "-" or "") .. text
end

-- Not loaded yet (Shopping List showed numbers, 0.41): the game is asked
-- for it and the lists redraw when it arrives (Module.lua).
local function ItemName(id)
  local name = (C_Item.GetItemInfo(id)) or (API.GetItemName and API.GetItemName(id))
  if name then return name end
  ns.namesWanted = true
  return "item " .. id
end
C.ItemName = ItemName

-- /cmp prof top: your known recipes, most profitable first, into the log.
function C.ReportTop(n)
  local char, key = ns.Char()
  local rows, missing, noValue = {}, 0, 0
  for id in pairs(char.known) do
    local res = C.Recipe(id)
    if res then
      if res.profit then rows[#rows + 1] = res; res.id = id
      elseif not res.complete then missing = missing + 1
      else noValue = noValue + 1 end
    end
  end
  table.sort(rows, function(a, b) return a.profit > b.profit end)
  CM.Log(("=== Most profitable crafts for %s (after %d%% auction cut) ==="):format(key, C.Cut() * 100))
  for i = 1, math.min(n, #rows) do
    local res = rows[i]
    local parts = {}
    for _, p in ipairs(res.parts) do
      parts[#parts + 1] = ("%d %s %s (%s)"):format(p.qty, ItemName(p.id), ns.MoneyText(p.each), tostring(p.how))
    end
    CM.Log(("%d. %s: profit %s, cost %s, sells %s x%s. Reagents: %s."):format(i, tostring(res.recipe.name),
      ns.MoneyText(res.profit), ns.MoneyText(res.cost), ns.MoneyText(res.value), tostring(res.made),
      table.concat(parts, ", ")))
  end
  if #rows == 0 then CM.Log("No known recipe has prices for all its reagents and its result yet.") end
  CM.Log(("%d recipes with a profit, %d missing a reagent price, %d without an auction value (e.g. enchants)."):format(
    #rows, missing, noValue))
end

-- Item tooltips: craft cost for items you can craft.
if TooltipDataProcessor and Enum and Enum.TooltipDataType then
  TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
    if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
    if not (ns.db and data and data.id) or ns.db.settings.tooltipCraftCost == false then return end
    if not CanCraft(data.id) then return end
    local cost = ItemCraftCost(data.id)
    if cost then
      tooltip:AddDoubleLine("Craft cost", CM.API.FormatMoney(math.floor(cost + 0.5)), 1, 1, 1, 1, 1, 1)
    end
  end)
end
