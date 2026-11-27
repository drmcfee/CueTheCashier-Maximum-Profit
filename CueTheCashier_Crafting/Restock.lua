-- CueTheCashier Crafting: restock rules.
--
-- A rule says "keep N of this item, but only craft it when one makes at
-- least this much profit". Set it under the craft cost lines of a recipe
-- in the profession window (Keep in stock / Min profit). The craft list's
-- **Restock** choice then queues, for every rule, enough crafts to get
-- back up to N, counting what all your characters on this server and
-- faction have in bags, bank and mail. Items on the auction house are not
-- counted yet. Rules are per item and shared by your characters.
--
-- Saved: db.restock[itemID] = { keep = n, minProfit = copper (nil = no minimum) }
-- Copyright (C) 2026 Kim. Licensed under the GNU GPL v3 or later; see LICENSE.
local _, ns = ...
local CM = CueTheCashier

local R = {}
ns.Restock = R

local function Rules()
  ns.db.restock = ns.db.restock or {}
  return ns.db.restock
end

function R.Get(itemID) return itemID and Rules()[itemID] end

-- keep 0 or nil removes the rule.
function R.Set(itemID, keep, minProfit)
  if not itemID then return end
  if not keep or keep <= 0 then
    Rules()[itemID] = nil
  else
    Rules()[itemID] = { keep = math.floor(keep), minProfit = minProfit }
  end
end

-- The recipe this character should use for an item: the cheapest one it
-- knows (one only an alt knows can't be crafted here).
function R.MyRecipe(itemID)
  local known = ns.Char().known
  local bestID, best
  for _, id in ipairs(ns.Recipes.ForOutput(itemID, true)) do
    if known[id] then
      local res = ns.Costs.Recipe(id)
      if res and res.perItem and (not best or res.perItem < best.perItem) then bestID, best = id, res end
    end
  end
  return bestID, best
end

-- The Crafting operation of an item (from its groups), or nil.
function R.Operation(itemID)
  local API = CM.API
  if not (API.GetItemOperation and itemID) then return nil end
  local name, settings = API.GetItemOperation(itemID, "craft")
  if not name then return nil end
  return name, settings
end

-- What a Crafting operation says about one recipe: crafts (0 = none) and
-- why. res = ns.Costs.Recipe(recipeID).
function R.FromOperation(itemID, res, opName, s)
  local made = (res and res.made) or 1
  local each = res and res.profit and res.profit / made
  if not each then return 0, "no auction price for it" end
  local minP = CM.API.GetOperationPrice("craft", opName, "minProfit", itemID)
  if not minP then return 0, ("Lowest profit in \"%s\" has no value for it"):format(opName) end
  if each < minP then
    return 0, ("profit %s each is below %s (\"%s\")"):format(ns.MoneyText(each), ns.MoneyText(minP), opName)
  end
  local count = tonumber(s.maxCraft) or 1
  -- What you already have counts (bags, bank, mail, own auctions, alts),
  -- so a list made again after crafting doesn't queue the same crafts.
  -- Without Keep in stock the target is one batch (Most to craft at once).
  local keep = tonumber(s.keepInStock) or 0
  if keep <= 0 then keep = count * made end
  local short = keep - ns.Inventory.Where(itemID).total
  if short <= 0 then return 0, "enough in stock" end
  count = math.min(count, math.ceil(short / made))
  return count, "ok"
end

-- Checks every rule. Returns { { itemID, recipeID, crafts, have, keep,
-- profitEach, ok, why }, ... }.
function R.Check()
  local out = {}
  for itemID, rule in pairs(Rules()) do
    local where = ns.Inventory.Where(itemID)
    local e = { itemID = itemID, keep = rule.keep, have = where.total, minProfit = rule.minProfit }
    local short = rule.keep - where.total
    local rid, res = R.MyRecipe(itemID)
    if short <= 0 then
      e.why = "enough in stock"
    elseif not rid then
      e.why = "this character knows no recipe for it (or a reagent has no price)"
    else
      e.recipeID = rid
      e.profitEach = res.profit and res.profit / res.made
      if not e.profitEach then
        e.why = "no auction price for it"
      elseif rule.minProfit and e.profitEach < rule.minProfit then
        e.why = ("profit %s each is below the minimum %s"):format(ns.MoneyText(e.profitEach), ns.MoneyText(rule.minProfit))
      else
        e.crafts = math.ceil(short / (res.made or 1))
        e.ok = true
      end
    end
    out[#out + 1] = e
  end
  -- Crafting operations with Keep in stock (Groups / Operations tabs).
  -- An old rule set in the profession window wins for its item.
  local seen = {}
  for id in pairs(ns.Char().known) do
    local r = ns.db.recipes[id]
    local itemID = r and r.out
    if itemID and not seen[itemID] and not Rules()[itemID] then
      seen[itemID] = true
      local opName, s = R.Operation(itemID)
      if opName and (tonumber(s.keepInStock) or 0) > 0 then
        local rid, res = R.MyRecipe(itemID)
        local e = { itemID = itemID, keep = s.keepInStock, have = ns.Inventory.Where(itemID).total, op = opName }
        local who = ns.Crafters.WhoCrafts(itemID, s)
        if who and not who.me then
          e.why = "crafted by " .. who.name .. " (Crafting operation)"
          if rid then
            local n = R.FromOperation(itemID, res, opName, s)
            if n > 0 then ns.CraftList.Elsewhere()[itemID] = { who = who.name, count = n, op = opName } end
          end
        elseif not rid then
          e.why = "this character knows no recipe for it (or a reagent has no price)"
        else
          local n, why = R.FromOperation(itemID, res, opName, s)
          e.recipeID, e.profitEach = rid, res.profit and res.profit / res.made
          if n > 0 then e.crafts, e.ok = n, true else e.why = why end
        end
        out[#out + 1] = e
      end
    end
  end
  return out
end

-- Fills a craft queue from the rules. Returns crafts queued, rules skipped.
function R.Fill(queue)
  local n, skipped = 0, 0
  for _, e in ipairs(R.Check()) do
    if e.ok then
      queue[e.recipeID] = (queue[e.recipeID] or 0) + e.crafts
      n = n + 1
    elseif e.why ~= "enough in stock" and not e.why:find("^crafted by") then
      skipped = skipped + 1
    end
    CM.Debug(("Restock %s: keep %d, have %d: %s."):format(ns.Costs.ItemName(e.itemID), e.keep, e.have,
      e.ok and ("craft " .. e.crafts) or e.why))
  end
  return n, skipped
end

-- /cmp prof restock: every rule and what it would do now, into the log.
function R.Report()
  local list = R.Check()
  CM.Log(("=== Restock rules (%d) ==="):format(#list))
  for _, e in ipairs(list) do
    CM.Log(("%s: keep %d, min profit %s. Have %d (all characters). %s."):format(ns.Costs.ItemName(e.itemID),
      e.keep, e.minProfit and ns.MoneyText(e.minProfit) or "none", e.have,
      e.ok and ("Would craft " .. e.crafts .. " times") or ("Nothing to do: " .. e.why)))
  end
  if #list == 0 then CM.Log("No rules yet. Set Keep in stock under a recipe's craft cost in the profession window.") end
end
