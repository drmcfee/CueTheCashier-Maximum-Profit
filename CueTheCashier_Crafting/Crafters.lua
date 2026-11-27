-- CueTheCashier Crafting: which character crafts, and who should learn a
-- recipe (0.46.0, Kim).
--
-- Crafter per Crafting operation: a Crafting operation can name a
-- character ("Crafter"). The Task List then queues that operation's crafts
-- on that character only; your other characters list them under "Crafted
-- by other characters" so you know where to log in. If the crafter doesn't
-- know a recipe for the item, the next character that does is used (you
-- first, then by name) and the row says so. Defaults chosen for the open
-- questions: one crafter per operation (no backup list); Mailing
-- operations don't follow it by themselves (set "Send to character" to the
-- crafter if you want the reagents mailed there).
--
-- Recipe tracking and routing: which recipes each character knows is
-- saved when its profession windows open (Recipes.lua). A recipe item
-- (Pattern:, Recipe:, Plans:, Formula:, Schematic:, Design:, Manual: ...)
-- is matched to the recipe it teaches by name: the text after the colon
-- against the recipe names read from your profession windows. Its tooltip
-- then says who should learn it: the main crafter of that profession (the
-- character with the highest skill in it), or, when the main already knows
-- it, another character with the profession that doesn't. When nobody can
-- use it, the tooltip says so (sell it). Defaults for the open questions:
-- skill level isn't checked (the recipe data has no required skill), and
-- the mailing list isn't fed yet.
-- GUESS: name matching needs testing on Forever (Kim's 0.46.0 test list).
-- Copyright (C) 2026 Kim. Licensed under the GNU GPL v3 or later; see LICENSE.
local _, ns = ...
local CM = CueTheCashier

local C = {}
ns.Crafters = C

local function Server() return CM.API.GetServerKey() end

-- Your characters on this server and faction: { { key, name, char }, ... },
-- you first, then by name.
function C.Here()
  local server = Server()
  local _, myKey = ns.Char()
  local out = {}
  for key, c in pairs(ns.db.chars) do
    if key:sub(-#server - 3) == " - " .. server then
      out[#out + 1] = { key = key, name = key:sub(1, #key - #server - 3), char = c, me = key == myKey }
    end
  end
  table.sort(out, function(a, b)
    if a.me ~= b.me then return a.me end
    return a.name < b.name
  end)
  return out
end

-- A character by the name typed in an operation (first name is enough,
-- any case: Forever names have a surname part).
function C.Find(typed)
  typed = tostring(typed or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if typed == "" then return nil end
  local first = typed:match("^(%S+)"):lower()
  for _, c in ipairs(C.Here()) do
    if c.name:lower() == typed:lower() or c.name:lower():match("^(%S+)") == first then return c end
  end
end

-- Does this character know a recipe that makes the item?
local function Knows(char, itemID)
  for _, id in ipairs(ns.Recipes.ForOutput(itemID, false)) do
    if char.known and char.known[id] then return true end
  end
  return false
end

-- Who crafts an item under its Crafting operation's "Crafter":
-- returns entry (from C.Here) or nil (no crafter set: whoever builds the
-- list), and a note when another character stands in.
function C.WhoCrafts(itemID, settings)
  local typed = settings and settings.crafter
  if not typed or tostring(typed):match("^%s*$") then return nil end
  local named = C.Find(typed)
  if named and Knows(named.char, itemID) then return named end
  for _, c in ipairs(C.Here()) do
    if Knows(c.char, itemID) then
      local why = named and ("%s doesn't know it, %s crafts it"):format(named.name, c.name)
        or ("no character called %s here, %s crafts it"):format(tostring(typed), c.name)
      return c, why
    end
  end
  return named, named and (named.name .. " doesn't know it yet") or nil
end

-- ------------------------------------------------------------------
-- Recipe items
-- ------------------------------------------------------------------
local RECIPE_CLASS = (Enum and Enum.ItemClass and Enum.ItemClass.Recipe) or 9
local cache = {}

local function Clean(s) return (tostring(s or ""):lower():gsub("[%s%p]+", " "):gsub("^ ", ""):gsub(" $", "")) end

-- The recipe an item teaches: recipeID or nil, and "unread" when it is a
-- recipe item whose recipe no profession window has shown yet.
function C.RecipeForItem(itemID)
  if cache[itemID] ~= nil then return cache[itemID] or nil end
  local name, _, _, _, _, _, _, _, _, _, _, classID = C_Item.GetItemInfo(itemID)
  if not name then return nil end -- not loaded yet: ask again later
  if classID ~= RECIPE_CLASS then cache[itemID] = false; return nil end
  local taught = Clean(name:match(":%s*(.+)$") or name)
  for id, r in pairs(ns.db.recipes) do
    local rn = Clean(r.name)
    local out = r.out and C_Item.GetItemInfo(r.out)
    if rn == taught or (out and Clean(out) == taught) then
      cache[itemID] = id
      return id
    end
  end
  return nil, "unread"
end

-- Who should learn a recipe item: { recipeID, skill, profName, knownBy = { names },
-- learnOn = name or nil, why }.
function C.Route(itemID)
  local recipeID, unread = C.RecipeForItem(itemID)
  if not recipeID then return unread and { unread = true } or nil end
  local r = ns.db.recipes[recipeID]
  local skill = r and r.skill
  local out = { recipeID = recipeID, skill = skill, knownBy = {} }
  local withProf = {}
  for _, c in ipairs(C.Here()) do
    local p = c.char.profs and c.char.profs[skill]
    if c.char.known and c.char.known[recipeID] then out.knownBy[#out.knownBy + 1] = c.name end
    if p then
      out.profName = out.profName or p.name
      withProf[#withProf + 1] = { c = c, rank = p.rank or 0 }
    end
  end
  table.sort(withProf, function(a, b)
    if a.rank ~= b.rank then return a.rank > b.rank end
    return a.c.name < b.c.name
  end)
  if #withProf == 0 then
    out.why = "none of your characters has this profession: sell it"
    return out
  end
  local main = withProf[1].c
  for i, w in ipairs(withProf) do
    if not (w.c.char.known and w.c.char.known[recipeID]) then
      out.learnOn = w.c.name
      out.why = i == 1 and "your main " .. tostring(out.profName or "crafter")
        or ("%s already knows it"):format(main.name)
      return out
    end
  end
  out.why = "every character with " .. tostring(out.profName or "the profession") .. " knows it: sell it"
  return out
end

if TooltipDataProcessor and Enum and Enum.TooltipDataType then
  TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
    if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
    if not (ns.db and data and data.id) or ns.db.settings.tooltipRecipeRoute == false then return end
    local ok, route = pcall(C.Route, data.id)
    if not ok or not route then return end
    if route.unread then
      tooltip:AddLine("CueTheCashier: open the profession window once to see who should learn this.", 0.5, 0.5, 0.5, true)
      return
    end
    if route.learnOn then
      tooltip:AddDoubleLine("Learn on", route.learnOn .. " |cff808080(" .. route.why .. ")|r", 1, 1, 1, 0, 1, 0)
    else
      tooltip:AddLine((route.why:gsub("^%l", string.upper)), 1, 0.6, 0.2, true)
    end
    if #route.knownBy > 0 then
      tooltip:AddDoubleLine("Known by", table.concat(route.knownBy, ", "), 1, 1, 1, 1, 1, 1)
    end
  end)
end
