-- CueTheCashier: auction house categories, read live from the game.
--
-- Blizzard's AH window builds its category list (Weapons > One-Handed
-- Axes, ...) from a global table called AuctionCategories. We read that
-- same table every time, so new categories or subcategories that Blizzard
-- adds show up without changing CueTheCashier.
-- If that table is missing, we build the list from the game's item
-- classes instead (also live data).
-- Copyright (C) 2026 Kim. Licensed under the GNU GPL v3 or later; see LICENSE.
local _, ns = ...
local CM = CueTheCashier
local API = CM.API

local Categories = {}
ns.Categories = Categories

-- Turns one Blizzard category into our simple form:
-- { name, filters = { {classID, subClassID, inventoryType}, ... }, children = {...} }
local function Convert(cat, depth)
  if type(cat) ~= "table" or not cat.name then return nil end
  -- Skip special entries the normal search cannot handle (WoW Token).
  if cat.flags and (cat.flags.WOW_TOKEN_FLAG or cat.flags.WoWToken) then return nil end
  local node = { name = cat.name, filters = cat.filters or {}, depth = depth, children = {} }
  for _, sub in ipairs(cat.subCategories or {}) do
    local child = Convert(sub, depth + 1)
    if child then node.children[#node.children + 1] = child end
  end
  return node
end

local function FromItemClasses()
  local list = {}
  if not (C_Item and C_Item.GetItemClassInfo) then return list end
  for classID = 0, 20 do
    local name = C_Item.GetItemClassInfo(classID)
    if name and name ~= "" then
      local node = { name = name, filters = { { classID = classID } }, depth = 1, children = {} }
      local subs = C_AuctionHouse.GetAuctionItemSubClasses
        and C_AuctionHouse.GetAuctionItemSubClasses(classID) or {}
      for _, subClassID in ipairs(subs) do
        local subName = C_Item.GetItemSubClassInfo(classID, subClassID)
        if subName then
          node.children[#node.children + 1] = { name = subName, depth = 2, children = {},
            filters = { { classID = classID, subClassID = subClassID } } }
        end
      end
      list[#list + 1] = node
    end
  end
  return list
end

-- Returns the category tree. Source is logged in the debug log.
function Categories:Get()
  local list = {}
  if type(AuctionCategories) == "table" then
    for _, cat in ipairs(AuctionCategories) do
      local node = Convert(cat, 1)
      if node then list[#list + 1] = node end
    end
  end
  if #list > 0 then
    CM.Debug("Categories: " .. #list .. " read from Blizzard's AuctionCategories.")
    return list
  end
  list = FromItemClasses()
  CM.Debug("Categories: AuctionCategories missing, built " .. #list .. " from item classes.")
  return list
end
