-- CueTheCashier Destroying: recording your disenchants. When the Disenchant
-- spell starts, the bags are noted; when its loot window opens, the item
-- that left your bags is the one disenchanted and the loot is what it gave.
-- CueTheCashierDestroyingDB.disenchants =
--   { { t, itemID, quality, level, classID, { [matID] = count } }, ... }
-- Copyright (C) 2026 Kim. Licensed under the GNU GPL v3 or later; see LICENSE.
local _, ns = ...
local CM = CueTheCashier
local API = CM.API

local Recorder = {}
ns.Recorder = Recorder

local MAX_RECORDS = 2000
local WEAPON = 2 -- item class
local pending -- { bags = counts, t = time }

local function BagCounts()
  local counts = {}
  for bag = 0, (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) do
    for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      if info and info.itemID then
        counts[info.itemID] = (counts[info.itemID] or 0) + (info.stackCount or 1)
      end
    end
  end
  return counts
end

function Recorder.SpellStarted(spellID)
  if spellID == API.DISENCHANT_SPELL then
    pending = { bags = BagCounts(), t = GetTime() }
  end
end

-- The loot is read right away (the window may close quickly with auto
-- loot); the bags are compared a moment later, once the item is gone.
function Recorder.OnLoot()
  if not pending or GetTime() - pending.t > 10 then pending = nil; return end
  local before = pending.bags
  pending = nil
  local got = {}
  for slot = 1, (GetNumLootItems and GetNumLootItems() or 0) do
    local link = GetLootSlotLink and GetLootSlotLink(slot)
    local id = link and tonumber(link:match("item:(%d+)"))
    local _, _, count = GetLootSlotInfo(slot)
    if id then got[id] = (got[id] or 0) + (count or 1) end
  end
  if not next(got) then return end
  C_Timer.After(0.5, function() CM.Try("Disenchant record", Recorder.Record, before, got) end)
end

function Recorder.LootShown()
  if pending then CM.Try("Disenchant record", Recorder.OnLoot) end
end

function Recorder.Record(before, got)
  local now = BagCounts()
  local source
  for id, n in pairs(before) do
    if (now[id] or 0) < n and not got[id] then
      local q, lvl, classID = API.GetDisenchantInfo(id)
      if q and q ~= "wait" then source = { id = id, quality = q, level = lvl, classID = classID } end
    end
  end
  if not source then
    CM.Debug("Disenchant: couldn't tell which item was disenchanted.")
    return
  end
  local list = ns.db.disenchants
  list[#list + 1] = { time(), source.id, source.quality, source.level, source.classID, got }
  while #list > MAX_RECORDS do table.remove(list, 1) end
  CM.Debug(("Disenchant recorded: item %d (quality %d, level %d)."):format(source.id, source.quality, source.level))
end

-- /cmp dis: what your disenchants gave, next to what the table expects.
function Recorder.Report()
  local list = ns.db.disenchants
  if #list == 0 then
    CM.Print("No disenchants recorded yet. Disenchant items and they are recorded automatically.")
    return
  end
  local groups, order = {}, {}
  for _, r in ipairs(list) do
    local outcomes = API.GetDisenchantOutcomes(r[3], r[4], r[5])
    local tier = outcomes and outcomes[1][1]
    local qualityName = ({ [2] = "green", [3] = "blue", [4] = "purple" })[r[3]] or ("quality " .. r[3])
    local key = ("%s %s, %s tier"):format(qualityName, r[5] == WEAPON and "weapon" or "armor",
      tier and (C_Item.GetItemInfo(tier) or ("item " .. tier)) or "unknown")
    local g = groups[key]
    if not g then
      g = { n = 0, got = {}, outcomes = outcomes, key = key }
      groups[key] = g
      order[#order + 1] = g
    end
    g.n = g.n + 1
    for id, c in pairs(r[6]) do
      g.got[id] = g.got[id] or { times = 0, count = 0 }
      g.got[id].times, g.got[id].count = g.got[id].times + 1, g.got[id].count + c
    end
  end
  CM.Print(("%d disenchants recorded."):format(#list))
  for _, g in ipairs(order) do
    local parts = {}
    for id, x in pairs(g.got) do
      local expect = "not expected"
      for _, o in ipairs(g.outcomes or {}) do
        if o[1] == id then expect = ("table %d%%, %d-%d"):format(o[2] * 100, o[3], o[4]) end
      end
      parts[#parts + 1] = ("%s %d%% avg %.1f (%s)"):format(C_Item.GetItemInfo(id) or ("item " .. id),
        x.times / g.n * 100, x.count / x.times, expect)
    end
    CM.Print(("%s: %d times. %s"):format(g.key, g.n, table.concat(parts, "; ")))
  end
end
