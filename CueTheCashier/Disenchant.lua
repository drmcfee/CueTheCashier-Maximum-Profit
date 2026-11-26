-- CueTheCashier: disenchant table and values (a price source).
--
-- Blizzard doesn't say what an item disenchants into, but in the 2004-era
-- game it follows fixed rules: item quality, item level, and armor or
-- weapon. The table below is the classic one (the same idea TSM uses).
-- WoW Forever may have changed it, so the CueTheCashier_Destroying module
-- records every disenchant you do and /cmp dis compares what you got with
-- the table. The numbers need real testing before you trust them.
--
-- Value of an item = sum over materials of chance x average count x the
-- material's price (7-day market average, else the last scan).
-- Copyright (C) 2026 Kim. Licensed under the GNU GPL v3 or later; see LICENSE.
local _, CM = ...

local DE = {}
CM.Disenchant = DE

DE.SPELL = 13262 -- Disenchant

-- Materials
local M = {
  STRANGE_DUST = 10940, SOUL_DUST = 11083, VISION_DUST = 11137, DREAM_DUST = 11176, ILLUSION_DUST = 16204,
  LESSER_MAGIC = 10938, GREATER_MAGIC = 10939, LESSER_ASTRAL = 10998, GREATER_ASTRAL = 11082,
  LESSER_MYSTIC = 11134, GREATER_MYSTIC = 11135, LESSER_NETHER = 11174, GREATER_NETHER = 11175,
  LESSER_ETERNAL = 16202, GREATER_ETERNAL = 16203,
  SMALL_GLIMMERING = 10978, LARGE_GLIMMERING = 11084, SMALL_GLOWING = 11138, LARGE_GLOWING = 11139,
  SMALL_RADIANT = 11177, LARGE_RADIANT = 11178, SMALL_BRILLIANT = 14343, LARGE_BRILLIANT = 14344,
  NEXUS = 20725,
}
DE.Materials = M

-- Uncommon (green): { maxLevel, dust, dustMin, dustMax, essence, essMin, essMax, shard }
-- Armor: 75% dust / 20% essence / 5% shard (first tier: 80/20, no shard).
-- Weapons: 20% dust / 75% essence / 5% shard.
local UNCOMMON = {
  { 15, M.STRANGE_DUST, 1, 2, M.LESSER_MAGIC, 1, 2, nil },
  { 20, M.STRANGE_DUST, 2, 3, M.GREATER_MAGIC, 1, 2, M.SMALL_GLIMMERING },
  { 25, M.STRANGE_DUST, 4, 6, M.LESSER_ASTRAL, 1, 2, M.SMALL_GLIMMERING },
  { 30, M.SOUL_DUST, 1, 2, M.GREATER_ASTRAL, 1, 2, M.LARGE_GLIMMERING },
  { 35, M.SOUL_DUST, 2, 5, M.LESSER_MYSTIC, 1, 2, M.SMALL_GLOWING },
  { 40, M.VISION_DUST, 1, 2, M.GREATER_MYSTIC, 1, 2, M.LARGE_GLOWING },
  { 45, M.VISION_DUST, 2, 5, M.LESSER_NETHER, 1, 2, M.SMALL_RADIANT },
  { 50, M.DREAM_DUST, 1, 2, M.GREATER_NETHER, 1, 2, M.LARGE_RADIANT },
  { 55, M.DREAM_DUST, 2, 5, M.LESSER_ETERNAL, 1, 2, M.SMALL_BRILLIANT },
  { 60, M.ILLUSION_DUST, 1, 2, M.GREATER_ETERNAL, 1, 2, M.LARGE_BRILLIANT },
  { 65, M.ILLUSION_DUST, 2, 5, M.GREATER_ETERNAL, 2, 3, M.LARGE_BRILLIANT },
}
-- Rare (blue): one shard; the top tier has a small Nexus Crystal chance.
local RARE = {
  { 25, M.SMALL_GLIMMERING }, { 30, M.LARGE_GLIMMERING }, { 35, M.SMALL_GLOWING },
  { 40, M.LARGE_GLOWING }, { 45, M.SMALL_RADIANT }, { 50, M.LARGE_RADIANT },
  { 55, M.SMALL_BRILLIANT }, { 65, M.LARGE_BRILLIANT },
}
-- Epic (purple): { maxLevel, material, min, max }
local EPIC = {
  { 45, M.SMALL_RADIANT, 2, 4 }, { 50, M.LARGE_RADIANT, 2, 4 }, { 55, M.SMALL_BRILLIANT, 2, 4 },
  { 60, M.NEXUS, 1, 1 }, { 80, M.NEXUS, 1, 2 },
}

local ARMOR, WEAPON = 4, 2
DE.ARMOR, DE.WEAPON = ARMOR, WEAPON
-- Equipped items that can't be disenchanted.
local NOT_DISENCHANTABLE_SLOT = { INVTYPE_BODY = true, INVTYPE_TABARD = true, INVTYPE_AMMO = true }

local function Tier(list, level)
  for _, t in ipairs(list) do
    if level <= t[1] then return t end
  end
end

-- What one disenchant gives: { { itemID, chance, min, max }, ... }, or nil.
function DE.Outcomes(quality, level, classID)
  if not (quality and level and level > 0) then return nil end
  if classID ~= ARMOR and classID ~= WEAPON then return nil end
  if quality == 2 then
    local t = Tier(UNCOMMON, level)
    if not t then return nil end
    local weapon = classID == WEAPON
    local out = {}
    local dust, ess, shard
    if not t[8] then
      dust, ess, shard = weapon and 0.2 or 0.8, weapon and 0.8 or 0.2, 0
    else
      dust, ess, shard = weapon and 0.2 or 0.75, weapon and 0.75 or 0.2, 0.05
    end
    out[#out + 1] = { t[2], dust, t[3], t[4] }
    out[#out + 1] = { t[5], ess, t[6], t[7] }
    if t[8] then out[#out + 1] = { t[8], shard, 1, 1 } end
    return out
  elseif quality == 3 then
    if level < 11 then return nil end
    local t = Tier(RARE, level)
    if not t then return nil end
    if t[2] == M.LARGE_BRILLIANT then
      return { { t[2], 0.995, 1, 1 }, { M.NEXUS, 0.005, 1, 1 } }
    end
    return { { t[2], 1, 1, 1 } }
  elseif quality == 4 then
    if level < 40 then return nil end
    local t = Tier(EPIC, level)
    if not t then return nil end
    return { { t[2], 1, t[3], t[4] } }
  end
end

-- Item facts. Returns quality, level, classID, or "wait" when the game
-- hasn't loaded the item yet (GET_ITEM_INFO_RECEIVED follows).
-- level: pass the auction's itemKey.itemLevel when you have it.
function DE.ItemFacts(itemID, level)
  if not (itemID and C_Item.GetItemInfoInstant and C_Item.GetItemInfo) then return nil end
  local _, _, _, equipLoc, _, classID = C_Item.GetItemInfoInstant(itemID)
  if classID ~= ARMOR and classID ~= WEAPON then return nil end
  if NOT_DISENCHANTABLE_SLOT[equipLoc] or equipLoc == "" then return nil end
  local name, _, quality, itemLevel = C_Item.GetItemInfo(itemID)
  if not name then return "wait" end
  if not level or level <= 0 then level = itemLevel end
  return quality, level, classID
end

function DE.MaterialPrice(itemID)
  local avg = CM.Data:GetAverage(itemID, "market", 7)
  if avg then return avg end
  local e = CM:GetItemEntry(itemID)
  return e and (e.marketValue or e.minBuyout)
end

-- Expected copper from disenchanting one item. Returns value, complete
-- (false when a material has no saved price; it then counts as 0), or
-- "wait", or nil when the item can't be disenchanted.
function DE.Value(itemID, level)
  local quality, lvl, classID = DE.ItemFacts(itemID, level)
  if quality == "wait" then return "wait" end
  local outcomes = DE.Outcomes(quality, lvl, classID)
  if not outcomes then return nil end
  local value, complete = 0, true
  for _, o in ipairs(outcomes) do
    local price = DE.MaterialPrice(o[1])
    if price then
      value = value + o[2] * (o[3] + o[4]) / 2 * price
    else
      complete = false
    end
  end
  return math.floor(value + 0.5), complete
end

-- true when this character can disenchant (knows Enchanting).
function DE.IsEnchanter()
  local spell = DE.SPELL
  if spell and IsPlayerSpell and IsPlayerSpell(spell) then return true end
  if GetProfessions and GetProfessionInfo then
    local p1, p2 = GetProfessions()
    for _, i in ipairs({ p1, p2 }) do
      local skillLine = select(7, GetProfessionInfo(i))
      if skillLine == 333 then return true end
    end
  end
  return false
end

-- true when the item binds when equipped (so it can be sold before you
-- disenchant it). bindType 2 = on equip.
function DE.IsBoE(itemID)
  local bindType = select(14, C_Item.GetItemInfo(itemID))
  return bindType == 2
end
