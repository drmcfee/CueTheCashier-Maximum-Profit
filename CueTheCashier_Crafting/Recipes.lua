-- CueTheCashier Crafting: reading recipes from the open profession window.
--
-- Every time a profession window opens or its list changes, all its
-- recipes are read again (cheap, and it picks up patches): which ones you
-- know, and for each recipe what it makes and what it needs
-- (C_TradeSkillUI.GetRecipeSchematic). Recipe facts are the same for every
-- character, so they are saved once; which recipes you know is saved per
-- character. Windows of other players (links, guild) and NPC crafting
-- show prices but don't change what you know.
--
-- Recipe facts: db.recipes[recipeID] = {
--   name, skill = skill line, out = itemID made (nil for enchants),
--   q1, q2 = how many one craft makes (min, max),
--   reagents = { { id = itemID, qty = n, alt = { other itemIDs that fit } }, ... },
--   t = time read }
-- Only required reagents are kept; optional/finishing ones are skipped.
-- Copyright (C) 2026 Kim. Licensed under the GNU GPL v3 or later; see LICENSE.
local _, ns = ...
local CM = CueTheCashier

local R = {}
ns.Recipes = R

local byOutput = {}  -- [itemID] = { recipeID, ... }
local knownAny = {}  -- [recipeID] = true when any of your characters knows it
local loggedLine = {} -- skill lines whose raw data was logged this session

function R.BuildIndex()
  byOutput, knownAny = {}, {}
  for id, r in pairs(ns.db.recipes) do
    if r.out then
      byOutput[r.out] = byOutput[r.out] or {}
      table.insert(byOutput[r.out], id)
    end
  end
  for _, c in pairs(ns.db.chars) do
    for id in pairs(c.known or {}) do knownAny[id] = true end
  end
end

-- Recipes that make an item. knownOnly: only ones one of your characters knows.
function R.ForOutput(itemID, knownOnly)
  local list = byOutput[itemID]
  if not list or not knownOnly then return list or {} end
  local out = {}
  for _, id in ipairs(list) do
    if knownAny[id] then out[#out + 1] = id end
  end
  return out
end

function R.IsKnown(recipeID) return knownAny[recipeID] == true end

local function IsRequired(slot)
  if slot.required ~= nil then return slot.required and true or false end
  local types = Enum and Enum.CraftingReagentType
  if types and types.Basic and slot.reagentType ~= nil then return slot.reagentType == types.Basic end
  return true
end

-- Reads one recipe's facts from the game and saves them. Returns them,
-- or the saved ones when the game gives nothing.
function R.Read(recipeID, info, skillLine)
  local T = C_TradeSkillUI
  local old = ns.db.recipes[recipeID]
  local ok, s = pcall(T.GetRecipeSchematic, recipeID, false)
  if not ok or type(s) ~= "table" then return old end
  local r = {
    name = (info and info.name) or s.name or (old and old.name),
    skill = skillLine or (old and old.skill),
    out = s.outputItemID,
    q1 = s.quantityMin or 1, q2 = s.quantityMax or s.quantityMin or 1,
    reagents = {}, t = time(),
  }
  for _, slot in ipairs(s.reagentSlotSchematics or {}) do
    if IsRequired(slot) and (slot.quantityRequired or 0) > 0 then
      local ids = {}
      for _, reagent in ipairs(slot.reagents or {}) do
        if reagent.itemID then ids[#ids + 1] = reagent.itemID end
      end
      if #ids > 0 then
        local e = { id = ids[1], qty = slot.quantityRequired }
        if #ids > 1 then e.alt = { select(2, unpack(ids)) } end
        r.reagents[#r.reagents + 1] = e
      end
    end
  end
  ns.db.recipes[recipeID] = r
  return r
end

-- Saved facts, or read now if the window that has it is open.
function R.Get(recipeID)
  local r = ns.db.recipes[recipeID]
  if r then return r end
  if C_TradeSkillUI and C_TradeSkillUI.GetRecipeSchematic then
    r = R.Read(recipeID, C_TradeSkillUI.GetRecipeInfo and C_TradeSkillUI.GetRecipeInfo(recipeID))
    if r and r.out then
      byOutput[r.out] = byOutput[r.out] or {}
      table.insert(byOutput[r.out], recipeID)
    end
  end
  return r
end

-- Is the open window someone else's (a link, the guild) or an NPC's?
local function IsOtherWindow()
  local T = C_TradeSkillUI
  local function Check(name)
    local f = T[name]
    if type(f) ~= "function" then return false end
    local ok, v = pcall(f)
    return ok and v and true or false
  end
  return Check("IsTradeSkillLinked") or Check("IsTradeSkillGuild") or Check("IsNPCCrafting")
end

-- Reads the whole open window.
function R.Scan()
  local T = C_TradeSkillUI
  if not (T and T.GetAllRecipeIDs and T.GetRecipeInfo) then
    CM.Debug("Recipes: C_TradeSkillUI.GetAllRecipeIDs/GetRecipeInfo don't exist on this client.")
    return
  end
  if T.IsTradeSkillReady and not T.IsTradeSkillReady() then return end
  local line, name = ns.Professions.OpenProfession()
  local other = IsOtherWindow()
  local ids = T.GetAllRecipeIDs() or {}
  if #ids == 0 then return end
  local char = ns.Char()
  local known, noFacts, first = 0, 0, nil
  for _, id in ipairs(ids) do
    local info = T.GetRecipeInfo(id)
    if info then
      local r = R.Read(id, info, line)
      if not r then noFacts = noFacts + 1 end
      if not other then
        char.known[id] = info.learned and true or nil
        if info.learned then known = known + 1 end
      end
      first = first or (info.learned and { info = info, id = id })
    end
  end
  if not other and line then
    char.scanned = char.scanned or {}
    char.scanned[line] = { t = time(), total = #ids, known = known }
  end
  R.BuildIndex()
  CM.Debug(("Recipes read: %s (%s), %d recipes, %d known%s%s."):format(tostring(name), tostring(line), #ids,
    known, noFacts > 0 and (", " .. noFacts .. " without a schematic") or "",
    other and ", someone else's window (not saved as yours)" or ""))
  -- Once per session and profession: one recipe raw, to see what Forever gives.
  if first and line and not loggedLine[line] and CM.IsDebug() then
    loggedLine[line] = true
    CM.Debug("Recipe info example: " .. CM.Dump(first.info, 2))
    local ok, s = pcall(T.GetRecipeSchematic, first.id, false)
    CM.Debug("Recipe schematic example: " .. (ok and CM.Dump(s, 5) or "error"))
  end
  ns.Costs.Changed()
end

function R.Learned(recipeID)
  if not recipeID then return end
  ns.Char().known[recipeID] = true
  knownAny[recipeID] = true
  ns.Costs.Changed()
end

-- { [skillLine] = { total, known, last } } from this character's reads.
function R.CountBySkillLine(char)
  local out = {}
  for line, s in pairs(char.scanned or {}) do
    out[line] = { total = s.total, known = s.known, last = s.t }
  end
  return out
end
