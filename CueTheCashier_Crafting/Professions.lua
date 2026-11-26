-- CueTheCashier Crafting: finding your professions.
--
-- At login (and when your skills change) every profession slot the game
-- has is read: GetProfessions() gives the slots, GetProfessionInfo() the
-- name, skill line and level, and the spellbook the profession's spells.
-- Confirmed in game on Forever (25 Nov 2026): Skinning 393 with Tanning,
-- Fishing 356 with Bait and Tackle, First Aid 129.
--
-- No skill is assumed to have no recipes: on Forever gathering skills
-- have recipe windows too, opened by another spell (Tanning, Gardening,
-- Bait and Tackle, Smelting). Which spell opened a window is learned when
-- you open it (the spell you cast just before TRADE_SKILL_SHOW). The spell
-- IDs below are only a fallback for windows you haven't opened yet.
-- Copyright (C) 2026 Kim. Licensed under the GNU GPL v3 or later; see LICENSE.
local _, ns = ...
local CM = CueTheCashier

local P = {}
ns.Professions = P

-- Fallback: skill line -> spell that opens its recipe window on Forever.
-- Tanning, Bait and Tackle and Gardening seen in game (Kim); Smelting 2656
-- is on Mining's skill line in Forever's game data (wago.tools).
local KNOWN_OPENERS = { [393] = 1278068, [356] = 1278067, [182] = 1278062, [186] = 2656 }
P.KNOWN_OPENERS = KNOWN_OPENERS

local lastCast -- { id, t }

local function SpellName(id)
  if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
  if C_Spell and C_Spell.GetSpellInfo then
    local info = C_Spell.GetSpellInfo(id)
    return info and info.name
  end
end

local function BookSpell(index)
  if not (C_SpellBook and C_SpellBook.GetSpellBookItemInfo) then return nil end
  local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
  local ok, info = pcall(C_SpellBook.GetSpellBookItemInfo, index, bank)
  if ok and type(info) == "table" and info.spellID then return info.spellID, info.name, info.isPassive end
end

-- Reads every profession slot. why: what asked, for the log.
function P.Discover(why)
  if not (GetProfessions and GetProfessionInfo) then
    CM.Debug("Professions: GetProfessions/GetProfessionInfo don't exist on this client.")
    return
  end
  local slots = { GetProfessions() }
  local char = ns.Char()
  local found = {}
  -- GetProfessions returns nil for empty slots, so walk a fixed range.
  for slot = 1, math.max(#slots, 6) do
    local index = slots[slot]
    if index then
      local name, _, rank, maxRank, numSpells, offset, skillLine = GetProfessionInfo(index)
      if skillLine then
        local p = char.profs[skillLine] or {}
        p.name, p.rank, p.max, p.slot = name, rank, maxRank, slot
        p.spells = {}
        for i = 1, numSpells or 0 do
          local id, sname, passive = BookSpell((offset or 0) + i)
          if id then p.spells[#p.spells + 1] = { id = id, name = sname, passive = passive or nil } end
        end
        char.profs[skillLine] = p
        found[skillLine] = true
      end
    end
  end
  -- Forget professions you dropped.
  for skillLine in pairs(char.profs) do
    if not found[skillLine] then char.profs[skillLine] = nil end
  end
  local parts = {}
  for skillLine, p in pairs(char.profs) do
    parts[#parts + 1] = ("%s %d (%d/%d)"):format(tostring(p.name), skillLine, p.rank or 0, p.max or 0)
  end
  table.sort(parts)
  CM.Debug(("Professions (%s): %s"):format(why, #parts > 0 and table.concat(parts, ", ") or "none"))
end

function P.SpellCast(spellID)
  lastCast = { id = spellID, t = GetTime() }
end

-- The profession whose window is open: skill line, name, rank, max, raw info.
function P.OpenProfession()
  local T = C_TradeSkillUI
  if not T then return nil end
  local info = T.GetBaseProfessionInfo and T.GetBaseProfessionInfo()
  if type(info) ~= "table" or not info.professionID then
    info = T.GetChildProfessionInfo and T.GetChildProfessionInfo()
  end
  if type(info) ~= "table" then return nil end
  -- Retail-style clients may give an expansion "child" line with a parent.
  local line = info.parentProfessionID or info.professionID
  return line, info.parentProfessionName or info.professionName, info.skillLevel, info.maxSkillLevel, info
end

-- TRADE_SKILL_SHOW: remember which spell opened this window.
function P.WindowOpened()
  local line, name, _, _, info = P.OpenProfession()
  CM.Debug("Profession window opened:", info or "no profession info yet")
  if not line then return end
  if lastCast and GetTime() - lastCast.t < 3 and P.IsOpenerFor(line, lastCast.id) then
    local old = ns.db.openers[line]
    ns.db.openers[line] = lastCast.id
    if old ~= lastCast.id then
      CM.Debug(("Profession window %s (%d) is opened by spell %s (%d)."):format(
        tostring(name), line, tostring(SpellName(lastCast.id)), lastCast.id))
    end
  end
  lastCast = nil
end

-- Only a spell from the profession's own spellbook entries can open it.
-- A craft cast just before (recipes are spells too) or another
-- profession's spell is not (seen in game, 0.20.0: Leatherworking was
-- "opened by" Camp Chair, Fishing by Tanning).
function P.IsOpenerFor(skillLine, spellID)
  if ns.db.recipes[spellID] then return false end
  local known = KNOWN_OPENERS[skillLine]
  if known then return known == spellID end
  for other, id in pairs(KNOWN_OPENERS) do
    if id == spellID and other ~= skillLine then return false end
  end
  local p = ns.Char().profs[skillLine]
  for _, s in ipairs(p and p.spells or {}) do
    if s.id == spellID then return true end
  end
  return false
end

-- Drops wrong openers saved by 0.15.0-0.20.0.
function P.CleanOpeners()
  for line, id in pairs(ns.db.openers) do
    if ns.db.recipes[id] or (KNOWN_OPENERS[line] and KNOWN_OPENERS[line] ~= id) then
      ns.db.openers[line] = nil
    else
      for other, kid in pairs(KNOWN_OPENERS) do
        if kid == id and other ~= line then ns.db.openers[line] = nil end
      end
    end
  end
end

-- Spell that opens a skill line's recipe window: learned, else the
-- fallback list, else the profession's first active spell.
function P.Opener(skillLine)
  local learned = ns.db.openers[skillLine]
  if learned then return learned, "seen" end
  if KNOWN_OPENERS[skillLine] then return KNOWN_OPENERS[skillLine], "list" end
  local p = ns.Char().profs[skillLine]
  for _, s in ipairs(p and p.spells or {}) do
    if not s.passive then return s.id, "guess" end
  end
end

-- /cmp prof: everything we know, into the copyable log.
function P.Report()
  P.Discover("/cmp prof")
  local Log = CM.Log
  local char, key = ns.Char()
  Log(("=== CueTheCashier %s professions report for %s ==="):format(tostring(select(3, CM.API.GetVersion())), key))
  local lines = {}
  for skillLine in pairs(char.profs) do lines[#lines + 1] = skillLine end
  table.sort(lines, function(a, b) return (char.profs[a].slot or 9) < (char.profs[b].slot or 9) end)
  if #lines == 0 then Log("No professions found (GetProfessions returned nothing).") end
  local counts = ns.Recipes.CountBySkillLine(char)
  for _, skillLine in ipairs(lines) do
    local p = char.profs[skillLine]
    local spells = {}
    for _, s in ipairs(p.spells or {}) do
      spells[#spells + 1] = ("%s %d%s"):format(tostring(s.name), s.id, s.passive and " passive" or "")
    end
    local opener, how = P.Opener(skillLine)
    local c = counts[skillLine]
    Log(("Slot %d: %s, skill line %d, level %d/%d. Spells: %s."):format(p.slot or 0, tostring(p.name),
      skillLine, p.rank or 0, p.max or 0, #spells > 0 and table.concat(spells, ", ") or "none"))
    Log(("  Recipe window: %s (%s). Recipes read: %s."):format(
      opener and ("%s %d"):format(tostring(SpellName(opener)), opener) or "unknown",
      how == "seen" and "seen opening it" or how == "list" and "from CueTheCashier's list, not seen yet"
        or how == "guess" and "guess: first spell" or "-",
      c and ("%d known of %d, last read %s"):format(c.known, c.total, c.last and date("%Y-%m-%d %H:%M", c.last) or "?")
        or "none yet, open the window once"))
  end
  -- Recipe windows opened for a skill line not in your profession list.
  for skillLine, c in pairs(counts) do
    if not char.profs[skillLine] then
      Log(("Skill line %d (not in the profession list): %d known of %d recipes."):format(skillLine, c.known, c.total))
    end
  end
  local T = C_TradeSkillUI
  Log(("API: C_TradeSkillUI %s, GetRecipeSchematic %s, ProfessionsFrame %s, TradeSkillFrame %s."):format(
    tostring(T ~= nil), tostring(T and T.GetRecipeSchematic ~= nil), tostring(_G.ProfessionsFrame ~= nil),
    tostring(_G.TradeSkillFrame ~= nil)))
  ns.UI.LogStatus()
end
