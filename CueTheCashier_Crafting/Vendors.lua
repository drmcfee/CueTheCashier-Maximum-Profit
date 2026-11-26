-- CueTheCashier Crafting: vendors you have visited, and map pins to them.
--
-- Every time a merchant window opens, the vendor is remembered: its name,
-- NPC ID, where you stood (map and position, close enough for a pin) and
-- what it sells. Shared by all your characters (CueTheCashierCraftingDB.vendors).
-- The Shopping List then pins the nearest known vendor that sells a reagent,
-- with Blizzard's own map pin (C_Map.SetUserWaypoint + super tracking).
-- GUESS: Forever has retail's map pin API (Kim sees map pins in game).
-- Until an outside vendor list is added, only vendors you have visited
-- are known.
-- Copyright (C) 2026 Kim. Licensed under the GNU GPL v3 or later; see LICENSE.
local _, ns = ...
local CM = CueTheCashier

local V = {}
ns.Vendors = V

local function DB()
  ns.db.vendors = ns.db.vendors or {}
  return ns.db.vendors
end

local function NpcID(guid)
  if type(guid) ~= "string" then return nil end
  local kind, _, _, _, _, id = strsplit("-", guid)
  if kind == "Creature" or kind == "Vehicle" then return tonumber(id) end
end

-- Where the player stands: map, x, y (0-1), continent and world position.
local function Here()
  if not (C_Map and C_Map.GetBestMapForUnit) then return nil end
  local map = C_Map.GetBestMapForUnit("player")
  if not map then return nil end
  local pos = C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(map, "player")
  if not pos then return { map = map } end
  local x, y = pos:GetXY()
  local here = { map = map, x = x, y = y }
  if C_Map.GetWorldPosFromMapPos and CreateVector2D then
    local ok, cont, world = pcall(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(x, y))
    if ok and cont and world then here.cont, here.wx, here.wy = cont, world:GetXY() end
  end
  return here
end

local function MapName(map)
  local info = map and C_Map.GetMapInfo and C_Map.GetMapInfo(map)
  return info and info.name or ("map " .. tostring(map))
end

-- MERCHANT_SHOW: remember this vendor and what it sells.
function V.Record()
  local id = NpcID(UnitGUID and UnitGUID("npc"))
  if not id then return end
  local here = Here()
  if not (here and here.x) then return end -- instances: no position
  local v = DB()[id] or {}
  v.name = UnitName("npc") or v.name
  v.map, v.x, v.y, v.cont, v.wx, v.wy = here.map, here.x, here.y, here.cont, here.wx, here.wy
  v.factions = v.factions or {}
  v.factions[UnitFactionGroup("player") or "?"] = true
  v.seen = time()
  v.items = {}
  local n = 0
  for i = 1, GetMerchantNumItems() or 0 do
    local item = GetMerchantItemID and GetMerchantItemID(i)
    if item then v.items[item] = true; n = n + 1 end
  end
  DB()[id] = v
  CM.Debug(("Vendor %s (%d) at %s %.1f, %.1f: %d items."):format(tostring(v.name), id, MapName(v.map),
    v.x * 100, v.y * 100, n))
end

-- The nearest known vendor selling itemID: same continent first (by
-- distance), then any. Your faction's vendors are preferred.
function V.Nearest(itemID)
  local here = Here() or {}
  local faction = UnitFactionGroup("player")
  local best, bestScore
  for id, v in pairs(DB()) do
    if v.items and v.items[itemID] then
      local score = 1e12
      if here.cont and v.cont == here.cont and here.wx and v.wx then
        score = math.sqrt((here.wx - v.wx) ^ 2 + (here.wy - v.wy) ^ 2)
      elseif here.map and v.map == here.map then
        score = 0
      end
      if not (v.factions and v.factions[faction]) then score = score + 1e13 end
      if not bestScore or score < bestScore then best, bestScore = v, score; best.npc = id end
    end
  end
  return best
end

function V.Describe(v)
  return ("%s, %s (%.0f, %.0f)"):format(tostring(v.name), MapName(v.map), (v.x or 0) * 100, (v.y or 0) * 100)
end

-- Puts Blizzard's map pin on the nearest vendor selling itemID.
function V.Pin(itemID)
  local name = ns.Costs.ItemName(itemID)
  local v = V.Nearest(itemID)
  if not v then
    CM.Print(("No vendor selling %s is known yet. Open a merchant that sells it once and CueTheCashier remembers it."):format(name))
    return
  end
  if not (C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates) then
    CM.Print(("%s: %s. (This client has no map pins.)"):format(name, V.Describe(v)))
    return
  end
  local ok, err = pcall(function()
    C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(v.map, v.x, v.y))
    if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
  end)
  if ok then
    CM.Print(("Map pin set: %s sells %s."):format(V.Describe(v), name))
  else
    CM.Print(("%s: %s. (The map pin failed, see /cmp log.)"):format(name, V.Describe(v)))
    CM.Log("SetUserWaypoint ERROR: " .. tostring(err))
  end
end

-- /cmp prof vendors: every known vendor into the log.
function V.Report()
  local n = 0
  for id, v in pairs(DB()) do
    local count = 0
    for _ in pairs(v.items or {}) do count = count + 1 end
    CM.Log(("Vendor %d: %s, %d items."):format(id, V.Describe(v), count))
    n = n + 1
  end
  CM.Log(("%d vendors known."):format(n))
end
