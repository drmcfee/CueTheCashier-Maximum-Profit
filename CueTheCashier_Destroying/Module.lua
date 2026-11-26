-- CueTheCashier Destroying: the module object. Records every disenchant you
-- do and compares it with CueTheCashier's disenchant table (/cmp dis), so the
-- table can be checked on WoW Forever. Room for milling and prospecting
-- later. The table and the disenchant values live in the core (a price
-- source); this module only reads them through CueTheCashier.API.
-- Copyright (C) 2026 Kim. Licensed under the GNU GPL v3 or later; see LICENSE.
local ADDON_NAME, ns = ...
local CM = CueTheCashier

local Module = CM:NewModule("Destroying", { addon = ADDON_NAME, api = 1 })
ns.module = Module

-- Saved: CueTheCashierDestroyingDB = { disenchants = { record, ... } }
function Module:OnInitialize()
  CueTheCashier.AdoptOldSaved("CueTheCashierDestroyingDB")
  if type(CueTheCashierDestroyingDB) ~= "table" then CueTheCashierDestroyingDB = {} end
  local db = CueTheCashierDestroyingDB
  db.disenchants = db.disenchants or {}
  -- Up to 0.13.0 the records were kept in CueTheCashierDB: move them here once.
  local old = CM.TakeLegacyData("disenchants")
  if type(old) == "table" then
    local list = {}
    for _, r in ipairs(old) do list[#list + 1] = r end
    for _, r in ipairs(db.disenchants) do list[#list + 1] = r end
    table.sort(list, function(a, b) return (a[1] or 0) < (b[1] or 0) end)
    db.disenchants = list
  end
  ns.db = db
end

function Module:OnEnable()
  local Recorder = ns.Recorder
  self:RegisterEvent("UNIT_SPELLCAST_START", function(_, _, unit, _, spellID)
    -- unit, castGUID, spellID
    if unit == "player" then Recorder.SpellStarted(spellID) end
  end)
  self:RegisterEvent("UNIT_SPELLCAST_SENT", function(_, _, unit, _, _, spellID)
    -- unit, target, castGUID, spellID
    if unit == "player" then Recorder.SpellStarted(spellID) end
  end)
  self:RegisterEvent("LOOT_OPENED", Recorder.LootShown)
  self:RegisterEvent("LOOT_READY", Recorder.LootShown)
  self:RegisterCommand("dis", function() ns.Recorder.Report() end, "/cmp dis")
  self:RegisterCommand("destroy", function(_, rest)
    if rest == "list" then ns.DestroyList.Report() else ns.DestroyList.Toggle() end
  end, "/cmp destroy [list]")
end
