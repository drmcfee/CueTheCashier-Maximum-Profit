-- CueTheCashier Crafting: craft cooldowns across your characters (0.36).
-- When a profession window shows its recipes, every recipe with a cooldown
-- (transmutes, Mooncloth and the like) is saved with the time it is ready
-- again; crafting one reads it again. The Overview shows them for every
-- character on this server, and at login a chat line lists the ready ones.
-- Saved per character: chars[key].cooldowns = { [recipeID] = { name, readyAt } }
-- Kim has no cooldown recipe yet: untested in game.
-- Copyright (C) 2026 Kim. Licensed under the GNU GPL v3 or later; see LICENSE.
local _, ns = ...
local CM = CueTheCashier
local API = CM.API

local C = {}
ns.Cooldowns = C

local function Mine()
  local c = ns.Char()
  c.cooldowns = c.cooldowns or {}
  return c.cooldowns
end

-- Reads every recipe's cooldown from the open profession window.
function C.Scan()
  local T = C_TradeSkillUI
  if not (T and T.GetAllRecipeIDs and T.GetRecipeCooldown) then return end
  local mine = Mine()
  for _, id in ipairs(T.GetAllRecipeIDs() or {}) do
    local ok, cd, isDay, charges, maxCharges = pcall(T.GetRecipeCooldown, id)
    if ok and ((cd and cd > 0) or (maxCharges and maxCharges > 0) or mine[id]) then
      local info = T.GetRecipeInfo and T.GetRecipeInfo(id)
      local name = info and info.name or mine[id] and mine[id].name or ("Recipe " .. id)
      local e = mine[id] or {}
      e.name = name
      e.readyAt = (cd and cd > 0) and math.floor(time() + cd) or (e.readyAt and math.min(e.readyAt, time())) or time()
      mine[id] = e
    end
  end
end

-- A craft finished: if it has a cooldown, read it again shortly.
function C.SpellDone(spellID)
  if Mine()[spellID] then ns.Debounce("Read cooldowns", 1, C.Scan) end
end

-- { { char, name, readyAt }, ... } for this server, soonest first.
function C.All()
  local server = API.GetServerKey()
  local out = {}
  for key, c in pairs(ns.db.chars or {}) do
    if c.cooldowns and key:sub(-#server - 3) == " - " .. server then
      local char = key:sub(1, #key - #server - 3)
      for _, e in pairs(c.cooldowns) do out[#out + 1] = { char = char, name = e.name, readyAt = e.readyAt or 0 } end
    end
  end
  table.sort(out, function(a, b) return a.readyAt < b.readyAt end)
  return out
end

local function Left(t)
  local s = t - time()
  if s <= 0 then return "|cff00ff00Ready|r" end
  if s >= 86400 then return ("%dd %dh"):format(s / 86400, (s % 86400) / 3600) end
  if s >= 3600 then return ("%dh %dm"):format(s / 3600, (s % 3600) / 60) end
  return ("%dm"):format(math.max(1, s / 60))
end

function C.ReportReady()
  local ready = {}
  for _, e in ipairs(C.All()) do
    if e.readyAt <= time() then ready[#ready + 1] = ("%s (%s)"):format(e.name, e.char) end
  end
  if #ready > 0 then CM.Print("Cooldowns ready: " .. table.concat(ready, ", ") .. ".") end
end

function C.Register(module)
  if API.RegisterOverviewSection then
    API.RegisterOverviewSection("cooldowns", { title = "Craft cooldowns", order = 60, lines = function()
      local lines = {}
      for _, e in ipairs(C.All()) do
        lines[#lines + 1] = { left = e.name .. " |cffaaaaaa" .. e.char .. "|r", right = Left(e.readyAt) }
      end
      if #lines == 0 then lines[1] = { left = "|cffaaaaaaNone seen yet (open a profession with one)|r", right = "" } end
      return lines
    end })
  end
  C_Timer.After(5, function() ns.Safe("Cooldown report", C.ReportReady) end)
end
