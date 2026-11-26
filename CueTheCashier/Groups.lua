-- CueTheCashier: item groups (data and rules; the Groups tab is GroupsTab.lua).
--
-- Groups form a tree (groups and sub-groups). Unlike other auction addons,
-- one item can be in several groups. Each item ranks its groups 1, 2, 3...
-- with no two groups on the same rank (0.39.0, Kim's design): rank 1 wins.
-- A group that newly gets the item goes to the bottom. Moving a group to
-- rank N pushes the ones from N down one step, so ranks stay unique.
-- (Before 0.39 groups had a priority 1-100; the first load turns those
-- into ranks, highest priority first, ties to the group made first.)
--
-- Operations (rule sets for posting, shopping, crafting, mailing,
-- vendoring) come next. A group keeps them by kind in g.operations[kind];
-- a sub-group without one uses its parent's. G.Winner(itemID, kind) then
-- picks, among the groups an item is in that have an operation of that
-- kind, the one with the best (lowest) rank.
--
-- The Base Group (id 0) holds every item in the game without listing
-- them. It is not saved as a group: it can't be renamed, moved, deleted
-- or get sub-groups, and it always ranks last, so any other group an
-- item is in wins. Its operations (DB().baseOperations)
-- are the defaults for items no other group covers. Real groups don't
-- inherit from it.
--
-- Saved in the profile (Profiles.lua), CM.Profile().groups:
--   { nextID = n, list = { [id] = { id, name, parent = id|nil, created,
--       items = { [itemID] = true }, operations = { [kind] = name } } },
--     ranks = { [itemID] = { groupID, ... } } -- rank 1 first; only items in 2+ groups need one
--     rankVersion = 1 }
-- Copyright (C) 2026 Kim. Licensed under the GNU GPL v3 or later; see LICENSE.
local _, CM = ...

local G = {}
CM.Groups = G

G.OLD_DEFAULT_PRIORITY = 50 -- only to read data from before 0.39
G.BASE_ID, G.BASE_NAME = 0, "Base Group"
-- The kinds of operations a group can have (Operations come next).
G.OPERATION_KINDS = {
  { key = "post", label = "Posting" },
  { key = "shop", label = "Shopping" },
  { key = "craft", label = "Crafting" },
  { key = "mail", label = "Mailing" },
  { key = "vendor", label = "Vendoring" },
  { key = "bank", label = "Warehousing" },
}
G.SEPARATOR = " > " -- between group names in a path, e.g. "Leatherworking > Armor Kits"

local function DB()
  local d = CM.Profile().groups
  if type(d) ~= "table" then
    d = {}
    CM.Profile().groups = d
  end
  d.list = d.list or {}
  d.nextID = d.nextID or 1
  d.baseOperations = d.baseOperations or {}
  d.ranks = d.ranks or {}
  if CM.Operations and CM.Operations.EnsureBase and not CM.Profile().baseOpsMade then
    CM.Operations.EnsureBase() -- the Base operations (0.42.0), once
  end
  if d.rankVersion ~= 1 then
    -- 0.39: priorities (1-100, higher wins, item's own over the group's)
    -- become ranks. Ties go to the group made first, as before.
    local byItem = {}
    for id, g in pairs(d.list) do
      for itemID, own in pairs(g.items or {}) do
        local p = type(own) == "number" and own or tonumber(g.priority) or G.OLD_DEFAULT_PRIORITY
        local t = byItem[itemID] or {}
        byItem[itemID] = t
        t[#t + 1] = { id = id, p = p }
        g.items[itemID] = true
      end
      g.priority = nil
    end
    for itemID, t in pairs(byItem) do
      if #t > 1 then
        table.sort(t, function(a, b)
          if a.p ~= b.p then return a.p > b.p end
          return a.id < b.id
        end)
        local r = {}
        for i, e in ipairs(t) do r[i] = e.id end
        d.ranks[itemID] = r
      end
    end
    d.rankVersion = 1
  end
  return d
end

local index -- [itemID] = { groupID, ... }, rebuilt after every change

local function Changed()
  index = nil
  CM.SendMessage("CM_GROUPS_CHANGED")
end

local function Index()
  if index then return index end
  index = {}
  for id, g in pairs(DB().list) do
    for itemID in pairs(g.items) do
      local t = index[itemID] or {}
      index[itemID] = t
      t[#t + 1] = id
    end
  end
  return index
end

-- The groups holding an item, rank 1 first. Keeps d.ranks in step: groups
-- deleted or without the item drop out, groups missing from it go to the
-- bottom (in the order they were made).
local function Ranks(itemID)
  local d = DB()
  local holders = Index()[itemID]
  if not holders or #holders == 0 then
    d.ranks[itemID] = nil
    return {}
  end
  local out, seen = {}, {}
  for _, id in ipairs(d.ranks[itemID] or {}) do
    local g = d.list[id]
    if g and g.items[itemID] and not seen[id] then
      out[#out + 1] = id
      seen[id] = true
    end
  end
  local missing = {}
  for _, id in ipairs(holders) do
    if not seen[id] then missing[#missing + 1] = id end
  end
  table.sort(missing)
  for _, id in ipairs(missing) do out[#out + 1] = id end
  d.ranks[itemID] = #out > 1 and out or nil
  return out
end

-- Puts a group last in an item's ranking (when it newly gets the item).
local function RankLast(id, itemID)
  local list = Ranks(itemID)
  for i = #list, 1, -1 do
    if list[i] == id then table.remove(list, i) end
  end
  list[#list + 1] = id
  DB().ranks[itemID] = #list > 1 and list or nil
end

-- Names can't hold the characters the export text uses.
local function CleanName(name)
  name = tostring(name or ""):gsub("[\r\n;>|]", " "):gsub("^%s+", ""):gsub("%s+$", "")
  if name == "" then name = "New Group" end
  return name:sub(1, 48)
end

function G.Get(id) return id and DB().list[id] or nil end
function G.Exists(id) return id == G.BASE_ID or G.Get(id) ~= nil end
function G.IsBase(id) return id == G.BASE_ID end
function G.Name(id)
  if id == G.BASE_ID then return G.BASE_NAME end
  local g = G.Get(id)
  return g and g.name
end

-- Sorted child groups of parent (nil = top level).
function G.Children(parent)
  local list = {}
  for _, g in pairs(DB().list) do
    if g.parent == parent then list[#list + 1] = g end
  end
  table.sort(list, function(a, b)
    local x, y = a.name:lower(), b.name:lower()
    if x ~= y then return x < y end
    return a.id < b.id
  end)
  return list
end

function G.FindChild(parent, name)
  for _, g in ipairs(G.Children(parent)) do
    if g.name:lower() == name:lower() then return g end
  end
end

function G.Path(id)
  if id == G.BASE_ID then return G.BASE_NAME end
  local names, g = {}, G.Get(id)
  while g do
    table.insert(names, 1, g.name)
    g = G.Get(g.parent)
  end
  return table.concat(names, G.SEPARATOR)
end

-- id and every group below it.
function G.Descendants(id)
  local out = { id }
  local i = 1
  while out[i] do
    for _, c in ipairs(G.Children(out[i])) do out[#out + 1] = c.id end
    i = i + 1
  end
  return out
end

-- The whole tree in display order: { { id, depth, hasChildren }, ... }.
-- collapsed[id] = true hides that group's sub-groups. The Base Group
-- comes first unless noBase.
function G.Tree(collapsed, noBase)
  local out = {}
  if not noBase then out[1] = { id = G.BASE_ID, depth = 0, hasChildren = false, base = true } end
  local function Walk(parent, depth)
    for _, g in ipairs(G.Children(parent)) do
      local kids = #G.Children(g.id) > 0
      out[#out + 1] = { id = g.id, depth = depth, hasChildren = kids }
      if kids and not (collapsed and collapsed[g.id]) then Walk(g.id, depth + 1) end
    end
  end
  Walk(nil, 0)
  return out
end

function G.Count() local n = 0 for _ in pairs(DB().list) do n = n + 1 end return n end

function G.ItemCount(id)
  local n, g = 0, G.Get(id)
  for _ in pairs(g and g.items or {}) do n = n + 1 end
  return n
end

-- ------------------------------------------------------------------
-- Changing groups
-- ------------------------------------------------------------------
function G.Create(name, parent)
  local d = DB()
  if parent and not d.list[parent] then parent = nil end
  local id = d.nextID
  d.nextID = id + 1
  d.list[id] = { id = id, name = CleanName(name), parent = parent,
    created = time(), items = {}, operations = {} }
  Changed()
  return id
end

function G.Rename(id, name)
  local g = G.Get(id)
  if not g then return false end
  g.name = CleanName(name)
  Changed()
  return true
end

-- Deletes the group and every sub-group under it.
function G.Delete(id)
  if not G.Get(id) then return false end
  local list = DB().list
  for _, gid in ipairs(G.Descendants(id)) do list[gid] = nil end
  Changed()
  return true
end

-- Moves a group under another one (nil = top level). Not into itself or
-- one of its own sub-groups.
function G.Move(id, parent)
  if parent == G.BASE_ID then parent = nil end
  local g = G.Get(id)
  if not g or (parent and not G.Get(parent)) then return false end
  for _, d in ipairs(G.Descendants(id)) do
    if d == parent then return false end
  end
  g.parent = parent
  Changed()
  return true
end

-- rank = nil: a new item goes to the bottom of its ranking.
function G.AddItem(id, itemID, rank)
  local g = G.Get(id)
  itemID = tonumber(itemID)
  if not (g and itemID and itemID > 0) then return false end
  if g.items[itemID] and rank == nil then return false end -- already in it
  if not g.items[itemID] then
    g.items[itemID] = true
    index = nil
    RankLast(id, itemID)
  end
  if rank then return G.SetItemRank(id, itemID, rank) end
  Changed()
  return true
end

-- Adds many items with one change message. Returns how many were new.
function G.AddItems(id, itemIDs)
  local g = G.Get(id)
  if not g then return 0 end
  local n = 0
  for _, itemID in ipairs(itemIDs) do
    itemID = tonumber(itemID)
    if itemID and itemID > 0 and not g.items[itemID] then
      g.items[itemID] = true
      index = nil
      RankLast(id, itemID)
      n = n + 1
    end
  end
  if n > 0 then Changed() end
  return n
end

-- Takes many items out with one change message. Returns how many.
function G.RemoveItems(id, itemIDs)
  local g = G.Get(id)
  if not g then return 0 end
  local n = 0
  for _, itemID in ipairs(itemIDs) do
    if g.items[itemID] then g.items[itemID] = nil; n = n + 1 end
  end
  if n > 0 then Changed() end
  return n
end

function G.RemoveItem(id, itemID)
  local g = G.Get(id)
  if not (g and g.items[itemID]) then return false end
  g.items[itemID] = nil
  Changed()
  return true
end

-- The group's rank for the item (1 = wins) and how many groups hold it.
function G.ItemRank(id, itemID)
  local g = G.Get(id)
  if not (g and g.items[itemID]) then return nil end
  local list = Ranks(itemID)
  for i, gid in ipairs(list) do
    if gid == id then return i, #list end
  end
end

-- Moves the group to rank n for the item. The groups from n on move down
-- one step, so every rank stays unique. n past the end = last.
function G.SetItemRank(id, itemID, n)
  local g = G.Get(id)
  n = math.floor(tonumber(n) or 0)
  if not (g and g.items[itemID]) or n < 1 then return false end
  local list = Ranks(itemID)
  for i = #list, 1, -1 do
    if list[i] == id then table.remove(list, i) end
  end
  table.insert(list, math.min(n, #list + 1), id)
  DB().ranks[itemID] = #list > 1 and list or nil
  Changed()
  return true
end

-- delta -1 = one step up (towards rank 1), +1 = one step down.
function G.MoveItemRank(id, itemID, delta)
  local r, count = G.ItemRank(id, itemID)
  if not r then return false end
  local n = math.max(1, math.min(count, r + delta))
  if n == r then return false end
  return G.SetItemRank(id, itemID, n)
end

-- ------------------------------------------------------------------
-- Which groups an item is in, and which one wins
-- ------------------------------------------------------------------

-- { { id, rank, path, name }, ... } in rank order, rank 1 (the winner) first.
function G.ItemGroups(itemID)
  local out = {}
  for i, id in ipairs(Ranks(itemID)) do
    out[#out + 1] = { id = id, rank = i, path = G.Path(id), name = G.Get(id).name }
  end
  -- Every item is in the Base Group, last.
  out[#out + 1] = { id = G.BASE_ID, rank = #out + 1, path = G.BASE_NAME, name = G.BASE_NAME, base = true }
  return out
end

-- The operation of a kind a group uses: its own, else its parent's (and
-- so on up). Returns the operation name and the group it comes from.
function G.Operation(id, kind)
  if id == G.BASE_ID then
    local op = DB().baseOperations[kind]
    if op then return op, G.BASE_ID end
    return nil
  end
  local g = G.Get(id)
  while g do
    local op = g.operations and g.operations[kind]
    if op then return op, g.id end
    -- false = "None, not even the Base Group's" (0.42.0): stops here.
    if op == false then return nil, g.id, true end
    g = G.Get(g.parent)
  end
end

function G.SetOperation(id, kind, name)
  if id == G.BASE_ID then
    DB().baseOperations[kind] = name
    Changed()
    return true
  end
  local g = G.Get(id)
  if not g then return false end
  g.operations = g.operations or {}
  g.operations[kind] = name
  Changed()
  return true
end

-- The group whose rules apply to an item. kind = nil: of all its groups;
-- with a kind ("post", "shop", ...): of the groups that have an operation
-- of that kind. Returns the group ID, its entry from ItemGroups, and the
-- full list (so callers can tell about the others).
function G.Winner(itemID, kind)
  local list = G.ItemGroups(itemID)
  local blocked = false
  for _, e in ipairs(list) do
    if not kind then return e.id, e, list end
    local op, _, none = G.Operation(e.id, kind)
    if op and not (e.base and blocked) then return e.id, e, list end
    -- A group set to "None" keeps the Base Group's operation off its items.
    if none then blocked = true end
  end
  return nil, nil, list
end

-- ------------------------------------------------------------------
-- Export and import as text, to keep or share groups.
--   CueTheCashier groups 2
--   group: Leatherworking
--   items: 2318, 2319, 4234@2        (@ = the group's rank for that item, when it is in 2+ groups)
--   group: Leatherworking > Armor Kits
-- Paths start at the exported group, so an import can go anywhere.
-- Text from before 0.39 ("groups 1", with priorities) still imports;
-- its priorities are skipped and items go to the bottom of their ranking.
-- ------------------------------------------------------------------
local HEADER = "CueTheCashier groups 2"
local HEADER_ANY = "groups (%d+)" -- also text from before the rename ("CraftMarket groups 1")
local ITEMS_PER_LINE = 15

-- id = nil exports every group.
function G.Export(id)
  local lines = { HEADER }
  local base = id and G.Get(id) and G.Get(id).parent
  local basePath = base and (G.Path(base) .. G.SEPARATOR) or ""
  local ids = {}
  if id == G.BASE_ID then id = nil end -- the Base Group itself has nothing to export
  if id then
    ids = G.Descendants(id)
  else
    for _, e in ipairs(G.Tree(nil, true)) do ids[#ids + 1] = e.id end
  end
  for _, gid in ipairs(ids) do
    local g = G.Get(gid)
    local path = G.Path(gid)
    if basePath ~= "" and path:sub(1, #basePath) == basePath then path = path:sub(#basePath + 1) end
    lines[#lines + 1] = "group: " .. path
    local items = {}
    for itemID in pairs(g.items) do
      local r, count = G.ItemRank(gid, itemID)
      items[#items + 1] = { itemID, (count or 0) > 1 and r or nil }
    end
    table.sort(items, function(a, b) return a[1] < b[1] end)
    for i = 1, #items, ITEMS_PER_LINE do
      local parts = {}
      for j = i, math.min(i + ITEMS_PER_LINE - 1, #items) do
        local e = items[j]
        parts[#parts + 1] = e[2] and (e[1] .. "@" .. e[2]) or tostring(e[1])
      end
      lines[#lines + 1] = "items: " .. table.concat(parts, ", ")
    end
  end
  return table.concat(lines, "\n")
end

-- Adds the groups in text under parent (nil = top level). Groups with the
-- same name and place are merged, not doubled. Returns groups, items made,
-- or nil and what is wrong.
function G.Import(text, parent)
  text = tostring(text or "")
  local version = (text:find("CueTheCashier groups", 1, true) or text:find("CraftMarket groups", 1, true))
    and tonumber(text:match(HEADER_ANY))
  if not version then
    return nil, "That isn't CueTheCashier group text (it starts with \"" .. HEADER .. "\")."
  end
  if parent and not G.Get(parent) then parent = nil end -- also the Base Group
  local groups, items, current = 0, 0, nil
  local oldChanged = Changed
  Changed = function() index = nil end -- one message at the end
  for line in text:gmatch("[^\r\n]+") do
    line = line:gsub("^%s+", ""):gsub("%s+$", "")
    local path = line:match("^group:%s*(.-)%s*;%s*priority%s*%d+$") -- old text
    if not path then path = line:match("^group:%s*(.-)%s*$") end
    if path and path ~= "" then
      local at = parent
      for name in (path .. G.SEPARATOR):gmatch("(.-)%s*>%s*") do
        name = CleanName(name)
        local g = G.FindChild(at, name)
        if not g then
          g = G.Get(G.Create(name, at))
          groups = groups + 1
        end
        at = g.id
      end
      current = at
    elseif current and line:find("^items:") then
      for entry in line:sub(7):gmatch("[^,]+") do
        local itemID, p = entry:match("^%s*(%d+)%s*@?%s*(%d*)%s*$")
        itemID = tonumber(itemID)
        if itemID then
          local g = G.Get(current)
          if not g.items[itemID] then
            items = items + 1
            g.items[itemID] = true
            index = nil
            RankLast(current, itemID)
          end
          if version >= 2 and p ~= "" then G.SetItemRank(current, itemID, p) end
        end
      end
    end
  end
  Changed = oldChanged
  Changed()
  return groups, items
end

-- ------------------------------------------------------------------
-- Public API (minor 3). Lists are copies; change groups only through
-- these functions, which send CM_GROUPS_CHANGED.
-- ------------------------------------------------------------------
local API = CM.API

-- Every group in tree order: { { id, name, path, parent, depth, itemCount, base }, ... }
-- The Base Group (id 0, base = true, every item, always ranked last) is first.
function API.GetGroups()
  local out = {}
  for _, e in ipairs(G.Tree()) do
    local g = G.Get(e.id)
    if e.base then
      out[#out + 1] = { id = G.BASE_ID, name = G.BASE_NAME, path = G.BASE_NAME, depth = 0,
        itemCount = 0, base = true }
    else
      out[#out + 1] = { id = g.id, name = g.name, path = G.Path(g.id), parent = g.parent,
        depth = e.depth, itemCount = G.ItemCount(g.id) }
    end
  end
  return out
end

-- The groups an item is in, rank 1 (the winner) first: { { id, name, path, rank, base }, ... }
-- The Base Group is always last.
function API.GetItemGroups(itemID) return G.ItemGroups(itemID) end

-- { [itemID] = best rank } of a group (and its sub-groups when asked).
function API.GetGroupItems(id, withSubgroups)
  local out = {}
  for _, gid in ipairs(withSubgroups and G.Descendants(id) or { id }) do
    local g = G.Get(gid)
    for itemID in pairs(g and g.items or {}) do
      local r = G.ItemRank(gid, itemID) or 1
      if not out[itemID] or r < out[itemID] then out[itemID] = r end
    end
  end
  return out
end

-- The group whose rules apply to the item (kind = an operation kind, or
-- nil for any group). Returns groupID, rank, path, or nil.
function API.GetWinningGroup(itemID, kind)
  local id, e = G.Winner(itemID, kind)
  if id then return id, e.rank, e.path end
end

API.CreateGroup = G.Create             -- (name, parentID) -> id
API.RenameGroup = G.Rename             -- (id, name)
API.DeleteGroup = G.Delete             -- (id), sub-groups too
API.MoveGroup = G.Move                 -- (id, parentID or nil)
API.AddItemToGroup = G.AddItem         -- (id, itemID, [rank])
API.AddItemsToGroup = G.AddItems       -- (id, { itemID, ... }) -> how many were new
API.RemoveItemsFromGroup = G.RemoveItems -- (id, { itemID, ... }) -> how many
API.FindGroup = function(name, parentID) -- a group by name under parentID (nil = top level)
  local g = G.FindChild(parentID, name)
  return g and g.id
end
API.BASE_GROUP = G.BASE_ID
API.RemoveItemFromGroup = G.RemoveItem -- (id, itemID)
API.GetItemRank = G.ItemRank           -- (id, itemID) -> rank, groups holding the item
API.SetItemRank = G.SetItemRank        -- (id, itemID, rank), others shift down (minor 11)
API.MoveItemRank = G.MoveItemRank      -- (id, itemID, -1 up / +1 down)
API.GetGroupOperation = G.Operation    -- (id, kind) -> name, fromGroupID
API.SetGroupOperation = G.SetOperation -- (id, kind, name or nil)
API.ExportGroups = G.Export            -- (id or nil) -> text
API.ImportGroups = G.Import            -- (text, parentID) -> groups, items | nil, error
