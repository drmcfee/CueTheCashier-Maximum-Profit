-- CueTheCashier Crafting: the craft list.
--
-- A **Craft List** button in Blizzard's profession window (left of Create
-- All) offers two lists:
--   * All profitable recipes: every recipe this character knows, in every
--     profession, that makes a profit at today's prices;
--   * Only <open profession>: the same for the window that is open;
--   * Restock items: what your restock rules ask for (Restock.lua).
-- The Crafting List window (docked to the profession window, shown with
-- it) lists what to craft: one of each; left-click a row for one more,
-- right-click for one less. A reagent that is cheapest to craft yourself
-- becomes a craft of its own ("for reagents", made first). **Craft**
-- crafts the next recipe on the list that the open window can make now;
-- each finished craft is taken off the list. The list is saved per
-- character. Where to get the reagents is the Task List's job
-- (TaskList.lua).
--
-- GUESS: C_TradeSkillUI.CraftRecipe works from an addon button click on
-- Forever (Blizzard blocked auction purchases that way; crafting is not
-- known yet). If it is blocked, the log says so.
-- Copyright (C) 2026 Kim. Licensed under the GNU GPL v3 or later; see LICENSE.
local _, ns = ...
local CM = CueTheCashier
local API = CM.API

local L = {}
ns.CraftList = L

local window, listButton

local function Queue()
  local c = ns.Char()
  c.queue = c.queue or {}
  return c.queue
end

local function Money(c) return API.FormatMoney(math.floor((c or 0) + 0.5)) end

local probing -- true while the supply check tries counts (Summary leaves the row spots alone)

-- Where each recipe sits on the Crafting List: { next = n, spot = { [recipeID] = n } }.
local function OrderTable()
  local c = ns.Char()
  if type(c.queueOrder) ~= "table" then c.queueOrder = {} end
  local o = c.queueOrder
  o.next = tonumber(o.next) or 0
  o.spot = o.spot or {}
  return o
end

-- Where a reagent comes from, in this order: your bags, the mailbox, the
-- bank, your other characters; what is still missing after that (and
-- after what you craft yourself) is bought.
-- alloc = { bags, mail, bank, alts = { { name, count }, ... } }
local function Allocate(e)
  local w, left = e.where, e.need
  local function Take(n)
    local t = math.min(left, n or 0)
    left = left - t
    return t
  end
  local a = { bags = Take(w.bags), mail = Take(w.mail), bank = Take(w.bank), alts = {} }
  for _, alt in ipairs(w.alts) do
    local t = Take(alt.count)
    if t > 0 then a.alts[#a.alts + 1] = { name = alt.name, count = t } end
  end
  e.alloc = a
  e.buy = math.max(0, left - e.crafted)
end

-- ------------------------------------------------------------------
-- Building the list
-- ------------------------------------------------------------------

-- skillLine: only that profession; nil = all of this character's.
-- onlyItems: { [itemID] = true } to queue only recipes that make one of
-- these (the groups picked in the Queue window); nil = any.
function L.Build(skillLine, onlyItems)
  local q = Queue()
  wipe(q)
  local n = 0
  local done = {} -- output items already queued (one recipe each)
  for id in pairs(ns.Char().known) do
    local r = ns.db.recipes[id]
    if r and (not skillLine or r.skill == skillLine) and (not onlyItems or (r.out and onlyItems[r.out])) then
      local res = ns.Costs.Recipe(id)
      local opName, settings = ns.Restock.Operation(r.out)
      if opName then
        -- The item's Crafting operation decides: Lowest profit, Keep in
        -- stock and Most to craft at once. Use the cheapest recipe.
        if not done[r.out] and ns.Restock.MyRecipe(r.out) == id then
          done[r.out] = true
          local count, why = ns.Restock.FromOperation(r.out, res, opName, settings)
          if count > 0 then
            q[id] = count
            n = n + 1
          else
            CM.Debug(("Craft list: %s skipped: %s."):format(tostring(r.name), why))
          end
        end
      elseif res and res.profit and res.profit > 0 and not done[r.out] then
        -- No Crafting operation: one craft, unless you already have the
        -- item (bags, bank, mail, auctions or an alt), e.g. just made it.
        done[r.out] = true
        local have = r.out and ns.Inventory.Where(r.out).total or 0
        if have > 0 then
          CM.Debug(("Craft list: %s skipped: you have %d."):format(tostring(r.name), have))
        else
          q[id] = 1
          n = n + 1
        end
      end
    end
  end
  CM.Debug(("Craft list built (%s): %d profitable recipes."):format(
    skillLine and ("skill line " .. skillLine) or "all professions", n))
  return n
end

-- { crafts = { { id, name, count, profit (all), each, forReagent }, ... },
--   reagents = { { id, need, have, where, alloc, crafted, buy, each, how, cost }, ... },
-- have counts every place you have it: bags and bank, the mailbox, and
-- your other characters on this server (see Inventory.lua).
--   cost, profit }
-- A reagent that is cheapest to craft yourself is added as a craft of its
-- own ("for reagents", made first), and its reagents join the list.
function L.Summary()
  local crafts, byID, need = {}, {}, {}
  local totalProfit, totalCost = 0, 0

  local function AddCraft(id, count, forReagent)
    local res = ns.Costs.Recipe(id)
    if not (res and count > 0) then return end
    local c = byID[id]
    if not c then
      c = { id = id, name = res.recipe.name or ("recipe " .. id), count = 0, each = res.profit,
        skill = res.recipe.skill, forReagent = forReagent }
      byID[id] = c
      crafts[#crafts + 1] = c
    end
    c.count = c.count + count
    if not forReagent then totalProfit = totalProfit + (res.profit or 0) * count end
    for _, p in ipairs(res.parts) do
      local e = need[p.id]
      if not e then
        local where = ns.Inventory.Where(p.id)
        e = { id = p.id, need = 0, crafted = 0, each = p.each, how = p.how, have = where.total, where = where }
        need[p.id] = e
      end
      e.need = e.need + p.qty * count
    end
  end

  for id, count in pairs(Queue()) do AddCraft(id, count, false) end
  -- Reagents to craft yourself (a few rounds: a crafted reagent can need one too).
  for _ = 1, 4 do
    local changed = false
    for itemID, e in pairs(need) do
      local short = e.need - e.have - e.crafted
      if e.how == "craft" and short > 0 then
        local rid, res = ns.Costs.BestRecipeFor(itemID)
        if rid and not (byID[rid] and not byID[rid].forReagent) then
          local n = math.ceil(short / (res.made or 1))
          e.crafted = e.crafted + n * (res.made or 1)
          AddCraft(rid, n, true)
          changed = true
        end
      end
    end
    if not changed then break end
  end
  for _, c in ipairs(crafts) do c.profit = (not c.forReagent and c.each) and c.each * c.count or nil end
  -- Reagent crafts first (they are made first), then each keeps the spot
  -- it got when it came on the list (0.42.0, Kim): one more or one less
  -- doesn't move rows around. New ones go last, most profitable first.
  local order = probing and { next = 0, spot = {} } or OrderTable() -- trial counts don't touch the spots
  local fresh = {}
  for _, c in ipairs(crafts) do if not order.spot[c.id] then fresh[#fresh + 1] = c end end
  table.sort(fresh, function(a, b)
    if (a.profit or 0) ~= (b.profit or 0) then return (a.profit or 0) > (b.profit or 0) end
    return a.name < b.name
  end)
  for _, c in ipairs(fresh) do
    order.next = order.next + 1
    order.spot[c.id] = order.next
  end
  -- Spots of recipes no longer on the list go.
  for id in pairs(order.spot) do if not byID[id] then order.spot[id] = nil end end
  if not next(order.spot) then order.next = 0 end
  table.sort(crafts, function(a, b)
    if (a.forReagent or false) ~= (b.forReagent or false) then return a.forReagent and true or false end
    return order.spot[a.id] < order.spot[b.id]
  end)

  local reagents = {}
  for _, e in pairs(need) do
    Allocate(e)
    e.cost = e.each and e.each * e.buy
    totalCost = totalCost + (e.cost or 0)
    reagents[#reagents + 1] = e
  end
  table.sort(reagents, function(a, b)
    if (a.buy > 0) ~= (b.buy > 0) then return a.buy > 0 end
    return (a.cost or 0) > (b.cost or 0)
  end)
  return { crafts = crafts, reagents = reagents, cost = totalCost, profit = totalProfit }
end

-- ------------------------------------------------------------------
-- Crafting
-- ------------------------------------------------------------------

-- The first recipe on the list the open window can make now.
-- How many of a recipe your bags can make now. In game (0.19.4) Forever's
-- recipe info has no numAvailable, so: C_TradeSkillUI.GetCraftableCount if
-- the client has it, else count the saved reagents in your bags.
local function CanMake(id, info)
  local T = C_TradeSkillUI
  if info and info.numAvailable then return info.numAvailable, "numAvailable" end
  if T.GetCraftableCount then
    local ok, n = pcall(T.GetCraftableCount, id)
    if ok and type(n) == "number" then return n, "GetCraftableCount" end
  end
  local r = ns.db.recipes[id]
  if not (r and r.reagents and #r.reagents > 0) then return 0, "no reagents saved" end
  local n = math.huge
  for _, g in ipairs(r.reagents) do
    local have = C_Item.GetItemCount(g.id, false) or 0
    n = math.min(n, math.floor(have / math.max(1, g.qty or 1)))
  end
  return n, "bags"
end

local function NextCraftable()
  local T = C_TradeSkillUI
  if not (T and T.GetRecipeInfo) then return nil end
  local line = ns.Professions.OpenProfession()
  local why = {}
  for _, c in ipairs(L.Summary().crafts) do
    if not line or c.skill == line then
      local info = T.GetRecipeInfo(c.id)
      local n, how = CanMake(c.id, info)
      why[#why + 1] = ("%s: learned %s, can make %s (%s)"):format(c.name, tostring(info and info.learned), tostring(n), how)
      if info and info.learned and n > 0 then
        return c.id, math.min(c.count, n), c.name
      end
    else
      why[#why + 1] = ("%s: skill line %s, open window is %s"):format(c.name, tostring(c.skill), tostring(line))
    end
  end
  CM.Log("Craft: nothing to make. " .. (#why > 0 and table.concat(why, "; ") or "the list is empty"))
end

function L.CraftNext()
  local id, count, name = NextCraftable()
  if not id then
    CM.Print("Nothing on the craft list can be made in this window right now (missing reagents, or another profession).")
    return
  end
  if not (C_TradeSkillUI and C_TradeSkillUI.CraftRecipe) then
    CM.Print("This client has no C_TradeSkillUI.CraftRecipe; craft it from Blizzard's window.")
    return
  end
  CM.Debug(("Craft list: crafting %s x%d (recipe %d)."):format(tostring(name), count, id))
  local ok, err = pcall(C_TradeSkillUI.CraftRecipe, id, count)
  if not ok then CM.Debug("CraftRecipe ERROR: " .. tostring(err)) end
end

-- ------------------------------------------------------------------
-- Crafting from the Task List (0.45.0, Kim)
-- A craft row on the Task List: one click opens the right profession and
-- starts the craft, but only when every reagent is in your bags; otherwise
-- nothing opens and the missing reagents are listed.
-- ------------------------------------------------------------------

-- Reagents your bags lack for `count` crafts of a recipe, from the saved
-- recipe: { { id, need, have }, ... } (empty = all there), and how many
-- crafts your bags can make. nil when the recipe's reagents aren't known yet.
function L.BagCheck(id, count)
  local r = ns.db.recipes[id]
  if not (r and r.reagents and #r.reagents > 0) then return nil end
  count = math.max(1, count or 1)
  local missing, can = {}, math.huge
  for _, g in ipairs(r.reagents) do
    local qty = math.max(1, g.qty or 1)
    local have = C_Item.GetItemCount(g.id, false) or 0
    can = math.min(can, math.floor(have / qty))
    if have < qty * count then missing[#missing + 1] = { id = g.id, need = qty * count, have = have } end
  end
  return missing, can
end

local pendingCraft -- { id, count, name, skill, t }: waits for its profession window

local function StartCraft(id, count, name)
  if not (C_TradeSkillUI and C_TradeSkillUI.CraftRecipe) then
    CM.Print("This client has no C_TradeSkillUI.CraftRecipe; craft it from Blizzard's window.")
    return
  end
  local before = CM.blockedCount or 0
  CM.Debug(("Task List: crafting %s x%d (recipe %d)."):format(tostring(name), count, id))
  local ok, err = pcall(C_TradeSkillUI.CraftRecipe, id, count)
  if not ok then CM.Debug("CraftRecipe ERROR: " .. tostring(err)) end
  if (CM.blockedCount or 0) ~= before then
    -- GUESS: a craft started by the window opening (not by your click)
    -- may be blocked. Then the window is open and a second click crafts.
    CM.Print(("The game didn't let CueTheCashier start %s by itself. Click it on the Task List again."):format(tostring(name)))
  end
end

-- c = a craft from L.Summary().crafts.
function L.CraftFromTask(c)
  if not (c and c.id) then return end
  local missing, can = L.BagCheck(c.id, 1)
  if not missing then
    CM.Print(("CueTheCashier doesn't know the reagents for %s yet. Open its profession window once."):format(tostring(c.name)))
    return
  end
  if #missing > 0 then
    local parts = {}
    for _, m in ipairs(missing) do
      parts[#parts + 1] = ("%d x %s"):format(m.need - m.have, ns.Costs.ItemName(m.id))
    end
    CM.Print(("Not crafting %s: missing in your bags: %s."):format(tostring(c.name), table.concat(parts, ", ")))
    return
  end
  local count = math.min(c.count or 1, can)
  if count < (c.count or 1) then
    CM.Print(("Your bags have reagents for %d of %d %s; crafting %d."):format(can, c.count, tostring(c.name), count))
  end
  if c.skill and c.skill == ns.Professions.OpenProfession() then
    pendingCraft = nil
    StartCraft(c.id, count, c.name)
    return
  end
  local T = C_TradeSkillUI
  if not (c.skill and T and T.OpenTradeSkill) then
    CM.Print("This client can't open a profession from an addon; open it from your spellbook.")
    return
  end
  pendingCraft = { id = c.id, count = count, name = c.name, skill = c.skill, t = GetTime() }
  local ok, err = pcall(T.OpenTradeSkill, c.skill)
  local prof = ns.Char().profs[c.skill]
  CM.Log(("Task List: open %s (%s) to craft %s: %s"):format(prof and prof.name or "profession", tostring(c.skill), tostring(c.name),
    ok and "asked" or tostring(err)))
  if not ok then pendingCraft = nil end
end

-- The profession window opened (or its recipes arrived): start a craft the
-- Task List asked for, if it is for this window and still fresh (5 s).
function L.PendingCraft()
  local p = pendingCraft
  if not p then return end
  if GetTime() - p.t > 5 then pendingCraft = nil return end
  if ns.Professions.OpenProfession() ~= p.skill then return end
  pendingCraft = nil
  StartCraft(p.id, p.count, p.name)
end

-- A craft finished: one off the list. Retail recipe IDs are spell IDs.
function L.SpellDone(spellID)
  local q = Queue()
  if q[spellID] then
    q[spellID] = q[spellID] - 1
    if q[spellID] <= 0 then q[spellID] = nil end
    L.Refresh()
  end
end

-- ------------------------------------------------------------------
-- Shopping: the reagents to get go on CueTheCashier's shopping list, where
-- the Shopping tab at the auction house and the merchant button find them.
-- ------------------------------------------------------------------
local lastPublished
function L.MaxPercent() return tonumber(ns.db.settings.shopMaxPercent) or 120 end

function L.Publish(summary)
  local items, parts = {}, {}
  for _, e in ipairs(summary.reagents) do
    local from = e.how == "vendor" and "vendor" or (e.how and e.how:find("^auction") and "auction") or nil
    if e.buy > 0 and from and e.each then
      items[e.id] = { quantity = e.buy, from = from, price = math.floor(e.each + 0.5),
        maxPrice = from == "auction" and math.floor(e.each * L.MaxPercent() / 100 + 0.5) or nil }
      parts[#parts + 1] = e.id .. ":" .. e.buy .. ":" .. from .. ":" .. tostring(items[e.id].maxPrice)
    end
  end
  table.sort(parts)
  local key = table.concat(parts, ",")
  if key == lastPublished then return end
  lastPublished = key
  CM.API.SetShoppingList("CueTheCashier_Crafting", items)
end

-- Clicking a reagent to buy it: auction items go to the Shopping tab
-- (message to the Auctioning module), vendor items to the open merchant.
function L.BuyReagent(e)
  if not e or e.buy <= 0 then return end
  local fromAH = e.how and e.how:find("^auction")
  if fromAH and AuctionHouseFrame and AuctionHouseFrame:IsShown() then
    CM.SendMessage("CM_SHOP_ITEM", e.id)
  elseif e.how == "vendor" and MerchantFrame and MerchantFrame:IsShown() then
    ns.Merchant.BuyItem(e.id)
  elseif fromAH then
    CM.Print("Open the auction house to buy " .. ns.Costs.ItemName(e.id) .. ".")
  elseif e.how == "vendor" then
    CM.Print("Open a merchant that sells " .. ns.Costs.ItemName(e.id) .. " to buy it.")
  end
end

-- ------------------------------------------------------------------
-- Enough on the auction house? (0.42.0, Kim) When a recipe goes on the
-- list N times but the reagents to buy aren't all for sale at or under the
-- Shopping tab's top price (list price x /cmp prof max), ask: none, what is
-- for sale, or all N. Counts come from the last full scan (0.42.0 or newer
-- saves how many are for sale per price step); without them nobody asks.
-- ------------------------------------------------------------------

-- Reagents short on the auction house: total missing, { { id, buy, forSale } }.
local function Shortage(summary)
  local total, list = 0, {}
  if not API.GetAuctionSupply then return 0, list end
  for _, e in ipairs(summary.reagents) do
    if e.buy > 0 and e.each and e.how and e.how:find("^auction") then
      local forSale = API.GetAuctionSupply(e.id, math.floor(e.each * L.MaxPercent() / 100 + 0.5))
      if forSale and forSale < e.buy then
        total = total + (e.buy - forSale)
        list[#list + 1] = { id = e.id, buy = e.buy, forSale = forSale }
      end
    end
  end
  return total, list
end

-- Most crafts of one recipe (up to want) that add no shortage, the rest of
-- the list as it is.
local function Affordable(id, want)
  local q = Queue()
  local keep = q[id]
  local was = probing
  probing = true
  q[id] = nil
  local ok, lo = pcall(function()
    local base = Shortage(L.Summary())
    local lo, hi = 0, want
    while lo < hi do
      local mid = math.ceil((lo + hi) / 2)
      q[id] = mid
      if Shortage(L.Summary()) <= base then lo = mid else hi = mid - 1 end
    end
    return lo
  end)
  q[id] = keep
  probing = was
  if not ok then error(lo) end
  return lo
end

local function RecipeName(id)
  local r = ns.db.recipes[id]
  return r and r.name or ("recipe " .. id)
end

local function ShortText(list)
  local parts = {}
  for i, x in ipairs(list) do
    if i > 4 then parts[#parts + 1] = "..." break end
    parts[#parts + 1] = ("%s: %d for sale, %d needed"):format(ns.Costs.ItemName(x.id), x.forSale, x.buy)
  end
  return table.concat(parts, "\n")
end

local function Set(id, n)
  Queue()[id] = n > 0 and n or nil
end

-- One recipe went from `before` to its count now (Add to list, +1 clicks).
local accepted = {} -- [recipeID] = count you said "All" to (no asking again up to it)
function L.CheckSupply(id, before)
  local want = Queue()[id] or 0
  if want <= (before or 0) or (accepted[id] and want <= accepted[id]) then return end
  local can = Affordable(id, want)
  if can >= want then return end
  local _, list = Shortage(L.Summary())
  before = before or 0
  local answers = {}
  answers[#answers + 1] = { before == 0 and "None" or ("Keep " .. before), function() Set(id, before); L.Refresh() end }
  if can ~= before then answers[#answers + 1] = { "Only " .. can, function() Set(id, can); L.Refresh() end } end
  answers[#answers + 1] = { "All " .. want, function() accepted[id] = want; L.Refresh() end }
  CM.Choose(("%d x %s: the auction house only has reagents for %d under your top price (%d%% of the list price).\n\n%s\n\nHow many to queue?")
    :format(want, RecipeName(id), can, L.MaxPercent(), ShortText(list)), answers)
end

-- A whole list was made (Craft List button): one question for all the
-- recipes that are short, most profitable first.
function L.CheckSupplyAll()
  local q = Queue()
  if Shortage(L.Summary()) <= 0 then return end
  local full = {}
  for id, n in pairs(q) do full[id] = n end
  local ids = {}
  for _, c in ipairs(L.Summary().crafts) do if not c.forReagent then ids[#ids + 1] = c end end
  table.sort(ids, function(a, b) return (a.each or 0) > (b.each or 0) end)
  -- Plan: each recipe in turn takes what is left on the auction house.
  probing = true
  wipe(q)
  local plan, short = {}, {}
  local ok, err = pcall(function()
    for _, c in ipairs(ids) do
      local can = Affordable(c.id, full[c.id])
      q[c.id] = can > 0 and can or nil
      plan[c.id] = can
      if can < full[c.id] then short[#short + 1] = c.id end
    end
  end)
  wipe(q)
  for id, n in pairs(full) do q[id] = n end
  probing = false
  if not ok then error(err) end
  if #short == 0 then return end
  local _, list = Shortage(L.Summary())
  local lines = {}
  for i, id in ipairs(short) do
    if i > 6 then lines[#lines + 1] = "..." break end
    lines[#lines + 1] = ("%s: %d of %d"):format(RecipeName(id), plan[id], full[id])
  end
  CM.Choose(("%d recipes on the list need more reagents than the auction house has under your top price (%d%% of the list price):\n\n%s\n\n%s\n\nQueue them?")
    :format(#short, L.MaxPercent(), table.concat(lines, "\n"), ShortText(list)), {
      { "None of them", function() for _, id in ipairs(short) do Set(id, 0) end L.Refresh() end },
      { "What's for sale", function() for _, id in ipairs(short) do Set(id, plan[id]) end L.Refresh() end },
      { "All", function() for _, id in ipairs(short) do accepted[id] = full[id] end end },
    })
end

-- ------------------------------------------------------------------
-- Crafting List window: what to craft. Docked to the right of Blizzard's
-- profession window and shown with it.
-- ------------------------------------------------------------------
local function Change(recipeID, delta)
  local q = Queue()
  q[recipeID] = math.max(0, (q[recipeID] or 0) + delta)
  if q[recipeID] == 0 then q[recipeID] = nil end
  L.Refresh()
end

-- Adds n of a recipe to the list by hand (any recipe you know, profitable
-- or not); a negative n takes some off. Returns the new count.
function L.Add(recipeID, n)
  if not ns.Char().known[recipeID] then
    CM.Print("You don't know that recipe on this character.")
    return 0
  end
  local before = Queue()[recipeID] or 0
  Change(recipeID, n)
  if n > 0 then ns.Safe("Supply check", function() L.CheckSupply(recipeID, before) end) end
  local q = Queue()[recipeID] or 0
  local r = ns.db.recipes[recipeID]
  CM.Print(("Crafting List: %d x %s."):format(q, r and r.name or ("recipe " .. recipeID)))
  return q
end

function L.Count(recipeID) return Queue()[recipeID] or 0 end

local function Build()
  local f = ns.ListWindow.New("CueTheCashierCraftListFrame", "Crafting List", 320, 420, 64)
  -- 0.42.0 bug: this pointed at Moved before Moved existed (a later local),
  -- so dragging saved nothing. Look it up when the drag ends instead.
  f.OnMoved = function(self) L.Moved(self) end
  f:HookScript("OnDragStart", function() L.dockToken = (L.dockToken or 0) + 1 end)
  f:SetClampedToScreen(true)
  f.craftButton = f:AddButton("Craft", 80, function() L.CraftNext() end,
    "Crafts the next recipe on the list that the open profession window can make now.")
  f:AddButton("Clear", 60, function() wipe(Queue()); wipe(accepted); L.Refresh() end)
  -- Queue button (0.42.2, Kim): another addon can hide our Craft List
  -- button in the profession window, so the list can fill itself too.
  -- Right-click opens the Task List (its old place here).
  local queue = f:AddButton("Queue...", 90, function(_, button)
    if button == "RightButton" then ns.TaskList.Show() else ns.GroupPicker.Show() end
  end, "Click: pick groups and queue their profitable recipes.\nRight-click: Task List (crafts to make, what to buy and where to fetch the reagents).")
  queue:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  -- Closing it by hand keeps it closed until the next profession window.
  -- (Hiding with the profession window doesn't count.)
  f:SetScript("OnHide", function()
    local pf = _G.ProfessionsFrame
    if not L.autoHiding and pf and pf:IsShown() then L.closedByHand = true end
  end)
  return f
end

-- Where you dragged it, kept against the profession window's top right
-- corner (0.42.0, Kim): { x, y } in ns.db.settings.listDock. /cmp prof dock
-- forgets it.
local function SavedDock()
  local d = ns.db.settings.listDock
  if type(d) == "table" and tonumber(d.x) and tonumber(d.y) then return d end
end

-- How far right of the profession window the list must start to clear
-- what sits on its right edge: Forever's profession tab buttons (0.42 still
-- covered them, Kim), or another addon's panel. Looks at every shown frame
-- inside the window (they may stick out of it) and every free-standing
-- one, whose left edge is near the window's right edge and that sits at
-- its height. Returns x in the window's units, and what it found.
local function RightEdgeClear(pf)
  local ps = pf:GetEffectiveScale()
  local pr, pt, pb = pf:GetRight(), pf:GetTop(), pf:GetBottom()
  if not (pr and pt and pb) then return 2, 0 end
  pr, pt, pb = pr * ps, pt * ps, pb * ps
  local maxRight, found = pr, 0
  local seen = {}
  local function Look(f)
    if seen[f] or f == window or (window and f:GetParent() == window) then return end
    seen[f] = true
    if f.IsForbidden and f:IsForbidden() then return end
    if not (f.IsVisible and f:IsVisible()) then return end
    local l, r, t, b = f:GetLeft(), f:GetRight(), f:GetTop(), f:GetBottom()
    if not (l and r and t and b) then return end
    local s = f:GetEffectiveScale()
    l, r, t, b = l * s, r * s, t * s, b * s
    local w = r - l
    if w > 1 and w < 600 * ps and l >= pr - 8 * ps and l <= pr + 80 * ps and t > pb and b < pt then
      if r > maxRight then maxRight = r end
      found = found + 1
    end
  end
  local function Walk(f, depth)
    for _, c in ipairs({ f:GetChildren() }) do
      if type(c) == "table" and c.GetLeft then
        pcall(Look, c)
        if depth < 4 then Walk(c, depth + 1) end
      end
    end
  end
  Walk(pf, 1)
  for _, c in ipairs({ UIParent:GetChildren() }) do
    if type(c) == "table" and c ~= pf and c.GetLeft then
      local name = c.GetName and c:GetName()
      if not (name and name:find("^CueTheCashier")) then pcall(Look, c) end
    end
  end
  return math.floor((maxRight - pr) / ps + 0.5) + 2, found
end

function L.Dock()
  if not window then return end
  L.dockToken = (L.dockToken or 0) + 1
  local token = L.dockToken
  local pf = _G.ProfessionsFrame
  window:ClearAllPoints()
  -- Only anchored next to Blizzard's window, never its child: it hides on
  -- TRADE_SKILL_CLOSE (also when Escape closes the window), so none of our
  -- code runs inside Blizzard's Escape handling.
  if not (pf and pf:IsShown()) then
    window:SetPoint("CENTER", 300, 0)
    return
  end
  local d = SavedDock()
  if d then
    window:SetPoint("TOPLEFT", pf, "TOPRIGHT", d.x, d.y)
    CM.Debug(("Crafting List: at your spot %d, %d."):format(d.x, d.y))
    return
  end
  local function Fit(when)
    if token ~= L.dockToken or SavedDock() or not pf:IsShown() then return end
    local ok, x, found = pcall(RightEdgeClear, pf)
    if not ok then CM.Debug("Crafting List dock: " .. tostring(x)); x, found = 2, 0 end
    window:ClearAllPoints()
    window:SetPoint("TOPLEFT", pf, "TOPRIGHT", x, 0)
    L.dockX = x
    if x ~= L.loggedX then
      L.loggedX = x
      CM.Debug(("Crafting List docked %d right of the profession window (%s: %d things on its right edge)."):format(
        x, when, found))
    end
  end
  Fit("now")
  -- Tabs and other addons' panels can show a moment later.
  C_Timer.After(0.3, function() Fit("0.3 s") end)
  C_Timer.After(1.5, function() Fit("1.5 s") end)
end

-- Dragged by hand: remember the spot next to the profession window.
function L.Moved(f)
  L.dockToken = (L.dockToken or 0) + 1 -- no late re-dock over your spot
  local pf = _G.ProfessionsFrame
  if not (pf and pf:IsShown() and pf:GetRight() and f:GetLeft()) then
    CM.Log("Crafting List moved, but the profession window isn't open: spot not saved.")
    return
  end
  local s1, s2 = f:GetEffectiveScale(), pf:GetEffectiveScale()
  local x = (f:GetLeft() * s1 - pf:GetRight() * s2) / s1
  local y = (f:GetTop() * s1 - pf:GetTop() * s2) / s1
  ns.db.settings.listDock = { x = math.floor(x + 0.5), y = math.floor(y + 0.5) }
  CM.Log(("Crafting List spot saved: %d, %d from the profession window's top right (/cmp prof dock forgets it)."):format(
    ns.db.settings.listDock.x, ns.db.settings.listDock.y))
  L.Dock()
end

function L.ForgetDock()
  ns.db.settings.listDock = nil
  L.Dock()
  CM.Print("Crafting List: back to its normal spot next to the profession window.")
end

-- Profession titles. Clicking a title opens that profession's window with
-- C_TradeSkillUI.OpenTradeSkill(skill line) (worked in game for Skinning
-- 393), or, when that window is already open, crafts the first thing in the
-- group you can make (like the Craft button). 0.20.0 cast the opener spell
-- from secure buttons instead; those went stale when the window changed and
-- cast the wrong spell (seen in game), so the choice is now made on click.
local function ProfName(skill)
  local p = ns.Char().profs[skill]
  return p and p.name or ("Profession " .. tostring(skill))
end

local function TitleClicked(skill)
  if skill == ns.Professions.OpenProfession() then
    L.CraftNext()
    return
  end
  local T = C_TradeSkillUI
  if not (T and T.OpenTradeSkill) then
    CM.Print("This client can't open a profession from an addon; open it from your spellbook.")
    return
  end
  local ok, err = pcall(T.OpenTradeSkill, skill)
  CM.Log(("Open %s (%s): %s"):format(ProfName(skill), tostring(skill), ok and "asked" or tostring(err)))
end

function L.Refresh()
  if ns.UI and ns.UI.UpdateAddButton then ns.UI.UpdateAddButton() end
  local s = L.Summary()
  L.Publish(s)
  if ns.TaskList then ns.TaskList.Refresh(s) end
  if not (window and window:IsShown()) then return end
  -- Group by profession: the open one first, then by name.
  local open = ns.Professions.OpenProfession()
  local groups, order = {}, {}
  for _, c in ipairs(s.crafts) do
    local k = c.skill or 0
    if not groups[k] then groups[k] = { profit = 0 }; order[#order + 1] = k end
    table.insert(groups[k], c)
    if not c.forReagent then groups[k].profit = groups[k].profit + (c.profit or 0) end
  end
  table.sort(order, function(x, y)
    if (x == open) ~= (y == open) then return x == open end
    return ProfName(x) < ProfName(y)
  end)
  local lines = {}
  for _, k in ipairs(order) do
    if #lines > 0 then lines[#lines + 1] = { left = " " } end
    local name = ProfName(k)
    local skill = k
    lines[#lines + 1] = { header = name, right = ns.ProfitText(groups[k].profit), skill = k,
      onClick = function(button) if button == "LeftButton" then TitleClicked(skill) end end,
      tip = { name, k == open and "Click: craft the first recipe here that you have reagents for."
        or ("Click: open %s. Click again to craft."):format(name) } }
    for _, c in ipairs(groups[k]) do
      if c.forReagent then
        lines[#lines + 1] = { left = ("%d x %s"):format(c.count, c.name), right = "|cff808080for reagents|r",
          tip = { c.name, "Made first: a reagent for the crafts below is cheaper to make yourself." } }
      else
        local id = c.id
        lines[#lines + 1] = { left = ("%d x %s"):format(c.count, c.name),
          right = c.profit and ns.ProfitText(c.profit) or "?",
          tip = { c.name, "Left-click: one more. Right-click: one less." },
          onClick = function(button)
            local before = Queue()[id] or 0
            Change(id, button == "RightButton" and -1 or 1)
            if button ~= "RightButton" then ns.Safe("Supply check", function() L.CheckSupply(id, before) end) end
          end }
      end
    end
  end
  if #s.crafts == 0 then
    lines[#lines + 1] = { left = "|cff808080Nothing to craft. Use the Craft List button to fill it.|r" }
  end
  window:SetLines(lines)
  local toGet = 0
  for _, e in ipairs(s.reagents) do
    if e.need - e.alloc.bags - e.crafted > 0 then toGet = toGet + 1 end
  end
  window.totals:SetText(("Profit: %s     %s"):format(ns.ProfitText(s.profit),
    toGet > 0 and ("|cffffd100%d reagents to get|r"):format(toGet) or "All reagents in your bags"))
end

function L.Show()
  window = window or Build()
  L.autoHiding = false
  L.closedByHand = false
  L.Dock()
  window:Show()
  L.Refresh()
end

-- Profession window opened or closed.
function L.WindowOpened()
  if L.closedByHand then return end
  window = window or Build()
  L.Dock()
  window:Show()
  L.Refresh()
end

function L.WindowClosed()
  L.closedByHand = false
  if window and window:IsShown() then
    L.autoHiding = true
    window:Hide()
    L.autoHiding = false
  end
end

function L.Open(which)
  local line, name = ns.Professions.OpenProfession()
  local n
  if which == "restock" then
    wipe(Queue())
    local skipped
    n, skipped = ns.Restock.Fill(Queue())
    CM.Print(("Craft list: %d items to restock%s."):format(n,
      skipped > 0 and (", %d rules skipped (see /cmp prof restock)"):format(skipped) or ""))
  elseif which == "open" then
    if not line then CM.Print("Open a profession window first."); return end
    n = L.Build(line)
    CM.Print(("Craft list: %d profitable recipes in %s."):format(n, tostring(name)))
  else
    n = L.Build(nil)
    CM.Print(("Craft list: %d profitable recipes in all your professions."):format(n))
  end
  L.Show()
  ns.Safe("Supply check", L.CheckSupplyAll)
end

-- ------------------------------------------------------------------
-- The button in Blizzard's profession window
-- ------------------------------------------------------------------
local function ShowChoices(owner)
  local _, name = ns.Professions.OpenProfession()
  local onlyText = "Only " .. tostring(name or "this profession")
  if MenuUtil and MenuUtil.CreateContextMenu then
    MenuUtil.CreateContextMenu(owner, function(_, root)
      root:CreateTitle("Craft List")
      root:CreateButton("All profitable recipes", function() L.Open("all") end)
      root:CreateButton(onlyText, function() L.Open("open") end)
      root:CreateButton("Restock items", function() L.Open("restock") end)
      root:CreateButton("From groups...", function() ns.GroupPicker.Show() end)
      root:CreateButton("Show the current list", function() L.Show() end)
      root:CreateButton("Task List", function() ns.TaskList.Show() end)
    end)
  else
    -- No menu API: left-click = only this profession, right-click = all.
    L.Open(owner.lastButton == "RightButton" and "all" or "open")
  end
end

-- Makes (or fills up) a group for the open profession, with two
-- sub-groups: Items (what its known recipes make) and Materials (their
-- reagents). Running it again only adds what is new.
function L.MakeGroup()
  local API = CM.API
  if not API.AddItemsToGroup then return end -- core older than 0.25.0
  local line, name = ns.Professions.OpenProfession()
  if not (line and name) then
    CM.Print("Open a profession window first.")
    return
  end
  local items, mats, seenI, seenM = {}, {}, {}, {}
  local recipes = 0
  for recipeID in pairs(ns.Char().known or {}) do
    local r = ns.db.recipes[recipeID]
    if r and r.skill == line then
      recipes = recipes + 1
      if r.out and not seenI[r.out] then seenI[r.out] = true; items[#items + 1] = r.out end
      for _, e in ipairs(r.reagents or {}) do
        for _, id in ipairs({ e.id, unpack(e.alt or {}) }) do
          if not seenM[id] then seenM[id] = true; mats[#mats + 1] = id end
        end
      end
    end
  end
  if recipes == 0 then
    CM.Print(("No %s recipes read yet. Wait a moment for the list to load, then click again."):format(name))
    return
  end
  local function Find(n, parent) return API.FindGroup(n, parent) or API.CreateGroup(n, parent) end
  local top = Find(name, nil)
  local newI = API.AddItemsToGroup(Find("Items", top), items)
  local newM = API.AddItemsToGroup(Find("Materials", top), mats)
  CM.Print(("Group %s: %d new items (of %d), %d new materials (of %d), from %d recipes. See /cmp > Groups."):format(
    name, newI, #items, newM, #mats, recipes))
end

function L.HookButton(page)
  if listButton or not page then return end
  local skin = CM.Skins:Get()
  listButton = CreateFrame("Button", nil, page, skin.buttonTemplate)
  listButton:SetSize(100, 22)
  listButton:SetText("Craft List")
  listButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  L.PlaceButton(page)
  listButton:SetScript("OnClick", function(self, button)
    self.lastButton = button
    ShowChoices(self)
  end)
  listButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Craft List", 1, 1, 1)
    GameTooltip:AddLine("Lists the profitable recipes you know and the reagents to get for them.", nil, nil, nil, true)
    GameTooltip:Show()
  end)
  listButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

  -- "Make Group": a group for this profession (Items and Materials).
  if CM.API.AddItemsToGroup then
    local gb = CreateFrame("Button", nil, page, skin.buttonTemplate)
    gb:SetSize(100, 22)
    gb:SetText("Make Group")
    gb:SetPoint("RIGHT", listButton, "LEFT", -4, 0)
    gb:SetScript("OnClick", function() ns.Safe("Make group", L.MakeGroup) end)
    gb:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:AddLine("Make Group", 1, 1, 1)
      GameTooltip:AddLine("Makes a group named after this profession with two sub-groups: Items (what your " ..
        "recipes make) and Materials (their reagents). Click again after learning recipes to add the new ones.",
        nil, nil, nil, true)
      GameTooltip:Show()
    end)
    gb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    if page.GetFrameLevel then
      gb:SetFrameStrata(page:GetFrameStrata() or "MEDIUM")
      gb:SetFrameLevel((page:GetFrameLevel() or 1) + 20)
    end
    L.groupButton = gb
  end
  -- Above the page's own art, so it can't hide behind it.
  if page.GetFrameLevel then
    listButton:SetFrameStrata(page:GetFrameStrata() or "MEDIUM")
    listButton:SetFrameLevel((page:GetFrameLevel() or 1) + 20)
  end
  listButton:Show()
end

-- For /cmp prof: where the button is, so a missing button can be found.
function L.ButtonStatus()
  if not listButton then return "not made (no ProfessionsFrame.CraftingPage yet)" end
  local p, rel, rp, x, y = listButton:GetPoint(1)
  return ("shown %s, visible %s, level %s, anchored %s to %s %s (%s, %s), left %s bottom %s"):format(
    tostring(listButton:IsShown()), tostring(listButton:IsVisible()), tostring(listButton:GetFrameLevel()),
    tostring(p), rel and (rel.GetName and rel:GetName() or "a frame without a name") or "?",
    tostring(rp), tostring(x), tostring(y), tostring(listButton:GetLeft()), tostring(listButton:GetBottom()))
end

function L.PlaceButton(page)
  if not (listButton and page) then return end
  local s = ns.db.settings
  local x, y = s.listX or 0, s.listY or 0
  listButton:ClearAllPoints()
  local createAll = type(page.CreateAllButton) == "table" and page.CreateAllButton or nil
  local host = _G.ProfessionsFrame or page
  if not s.listAnchor and x == 0 and y == 0 and CM.Place then
    -- No spot set by hand (/cmp prof button): the first free one of these.
    local spots = {}
    if createAll then spots[#spots + 1] = { "RIGHT", createAll, "LEFT", -8, 0 } end
    spots[#spots + 1] = { "BOTTOMLEFT", page, "BOTTOMLEFT", 10, 8 }
    spots[#spots + 1] = { "TOPRIGHT", page, "TOPRIGHT", -40, -30 }
    spots[#spots + 1] = { "TOPRIGHT", host, "BOTTOMRIGHT", -12, -2 }
    CM.Place.Fit(listButton, host, spots, { name = "Craft List button", also = { L.groupButton } })
  elseif s.listAnchor == "top" then
    -- Fallback spot (/cmp prof button top): top right of the window.
    listButton:SetPoint("TOPRIGHT", page, "TOPRIGHT", -40 + x, -30 + y)
  elseif createAll then
    listButton:SetPoint("RIGHT", createAll, "LEFT", -8 + x, y)
  else
    listButton:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 10 + x, 8 + y)
  end
end
