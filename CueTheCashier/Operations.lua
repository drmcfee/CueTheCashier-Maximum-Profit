-- CueTheCashier: operations (data and rules; the tab is OperationsTab.lua).
--
-- An operation is a named set of rules of one kind (Posting, Shopping,
-- Crafting and restock, Mailing, Vendoring). Groups pick one operation of
-- each kind (Groups.lua); an item uses the operation of the winning group
-- that has one of that kind, else the Base Group's.
--
-- Every kind has a list of fields (FIELDS below). Field types:
--   price   a price formula (Formulas.lua), e.g. "market * 90%"
--   number  a whole number
--   choice  one of a few options
--   toggle  on / off
--   text    free text (a character name)
--
-- Saved in the profile (Profiles.lua): CM.Profile().operations[kind][name] = { field = value, ... }
-- Missing fields use the default.
-- Copyright (C) 2026 Kim. Licensed under the GNU GPL v3 or later; see LICENSE.
local _, CM = ...
local API = CM.API
local G = CM.Groups

local O = {}
CM.Operations = O

O.FIELDS = {
  post = {
    { key = "minPrice", type = "price", label = "Lowest price", default = "max(market * 60%, vendor * 120%)",
      tooltip = "Never post below this." },
    { key = "normalPrice", type = "price", label = "Normal price", default = "first(7d, market)",
      tooltip = "Used when nobody else is selling, or as set below." },
    { key = "maxPrice", type = "price", label = "Highest price", default = "first(7d, market) * 200%",
      tooltip = "Never post above this. When the cheapest auction is higher, post at this price." },
    { key = "undercut", type = "price", label = "Undercut by", default = "0c",
      tooltip = "How far under the cheapest other auction to post. Forever sells the same price in the order posted, newest first, so 0c is enough." },
    { key = "belowMin", type = "choice", label = "When others are under lowest", default = "skip",
      options = { { "skip", "Don't post" }, { "min", "Post at lowest price" }, { "normal", "Post at normal price" },
        { "max", "Post at highest price" } },
      tooltip = "What to do when the cheapest other auction is below your lowest price." },
    { key = "alone", type = "choice", label = "When nobody else sells", default = "normal",
      options = { { "normal", "Post at normal price" }, { "max", "Post at highest price" } } },
    { key = "postCap", type = "number", label = "Most to have posted", default = 10, min = 1, max = 5000,
      tooltip = "How many of the item you want up on the auction house at once." },
    { key = "keep", type = "number", label = "Keep in bags", default = 0, min = 0, max = 5000,
      tooltip = "Never post these last ones." },
    -- Forever's auction durations are 2, 8 and 24 hours (Kim, 25 Nov).
    { key = "duration", type = "choice", label = "Duration", default = "medium",
      options = { { "short", "2 hours" }, { "medium", "8 hours" }, { "long", "24 hours" } } },
    { key = "cancelUndercut", type = "toggle", label = "Cancel when undercut", default = true,
      tooltip = "A cancel scan takes back your auctions that someone posted under, to post them again." },
  },
  shop = {
    { key = "maxPrice", type = "price", label = "Highest price to pay", default = "first(7d, market)",
      tooltip = "Shopping buys auctions at or under this price." },
    { key = "buyUpTo", type = "number", label = "Buy up to (0 = no limit)", default = 0, min = 0, max = 100000,
      tooltip = "Stop when you have this many (bags, bank, mail)." },
  },
  craft = {
    { key = "minProfit", type = "price", label = "Lowest profit", default = "crafting * 30%",
      tooltip = "Only craft (and restock) when each item made earns at least this much, e.g. crafting * 30%." },
    { key = "keepInStock", type = "number", label = "Keep in stock", default = 0, min = 0, max = 100000,
      tooltip = "Craft until you have this many (bags, bank, mail, auctions). 0 = don't restock." },
    { key = "maxCraft", type = "number", label = "Most to craft at once", default = 5, min = 1, max = 1000,
      tooltip = "How many crafts the Crafting List queues for this item." },
  },
  mail = {
    { key = "target", type = "text", label = "Send to character", default = "",
      tooltip = "The name of the character that gets these items." },
    { key = "send", type = "number", label = "Send at most (0 = all)", default = 0, min = 0, max = 100000 },
    { key = "keep", type = "number", label = "Keep in bags", default = 0, min = 0, max = 100000 },
  },
  vendor = {
    { key = "sell", type = "toggle", label = "Sell to vendors", default = true },
    { key = "sellBelow", type = "price", label = "When auction value is under", default = "vendor * 120%",
      tooltip = "Sell to a vendor when the item is worth less than this on the auction house." },
    { key = "keep", type = "number", label = "Keep in bags", default = 0, min = 0, max = 100000 },
  },
  bank = {
    { key = "keepInBags", type = "number", label = "Keep in bags", default = 0, min = 0, max = 100000,
      tooltip = "To Bank leaves this many in your bags." },
    { key = "takeToBags", type = "number", label = "Take to bags (0 = all)", default = 0, min = 0, max = 100000,
      tooltip = "To Bags takes from the bank until your bags have this many." },
  },
}

-- Base operations (0.42.0, Kim): every kind gets one called "Base", set on
-- the Base Group, once per profile. Only adds: an operation or a Base Group
-- choice you already have is never changed, and one you delete later
-- doesn't come back (p.baseOpsMade).
O.BASE_NAME = "Base"
-- Settings that differ from the field defaults, for the Base ones only.
-- Vendoring starts off so nothing is sold until you say so; Crafting
-- queues one at a time like the list did for items without an operation.
O.BASE_PRESET = { vendor = { sell = false }, craft = { maxCraft = 1 } }

local function MakeBase(p)
  if p.baseOpsMade then return end
  p.baseOpsMade = 1
  p.groups = type(p.groups) == "table" and p.groups or {}
  p.groups.baseOperations = p.groups.baseOperations or {}
  local base = p.groups.baseOperations
  local made = {}
  for kind in pairs(O.FIELDS) do
    p.operations[kind] = p.operations[kind] or {}
    local list = p.operations[kind]
    if not list[O.BASE_NAME] then
      local op = {}
      for k, v in pairs(O.BASE_PRESET[kind] or {}) do op[k] = v end
      list[O.BASE_NAME] = op
      made[#made + 1] = kind
    end
    if base[kind] == nil then base[kind] = O.BASE_NAME end
  end
  if #made > 0 and CM.Debug then
    table.sort(made)
    CM.Debug("Base operations made: " .. table.concat(made, ", "))
  end
end

local function DB()
  local p = CM.Profile()
  p.operations = p.operations or {}
  MakeBase(p)
  return p.operations
end
function O.EnsureBase() DB() end

local function Kind(kind)
  assert(O.FIELDS[kind], "unknown operation kind " .. tostring(kind))
  DB()[kind] = DB()[kind] or {}
  return DB()[kind]
end

local function Changed() CM.SendMessage("CM_OPERATIONS_CHANGED") end

local function CleanName(name)
  name = tostring(name or ""):gsub("[\r\n;|]", " "):gsub("^%s+", ""):gsub("%s+$", "")
  return name:sub(1, 40)
end

function O.Field(kind, key)
  for _, f in ipairs(O.FIELDS[kind] or {}) do
    if f.key == key then return f end
  end
end

function O.Names(kind)
  local list = {}
  for name in pairs(Kind(kind)) do list[#list + 1] = name end
  table.sort(list, function(a, b) return a:lower() < b:lower() end)
  return list
end

function O.Exists(kind, name) return name ~= nil and Kind(kind)[name] ~= nil end

-- A field's value (saved or default).
-- Durations saved before 0.34.1 ("12"/"24"/"48") mean the same game
-- choice (short/medium/long).
local OLD_DURATION = { ["12"] = "short", ["24"] = "medium", ["48"] = "long" }

function O.Value(kind, name, key)
  local op = Kind(kind)[name]
  local v = op and op[key]
  if key == "duration" and OLD_DURATION[tostring(v)] then
    v = OLD_DURATION[tostring(v)]
    op[key] = v
  end
  if v == nil then
    local f = O.Field(kind, key)
    v = f and f.default
  end
  return v
end

-- Every field's value: { [key] = value }.
function O.Settings(kind, name)
  if not O.Exists(kind, name) then return nil end
  local out = {}
  for _, f in ipairs(O.FIELDS[kind]) do out[f.key] = O.Value(kind, name, f.key) end
  return out
end

-- A free name like "Posting 2".
function O.FreeName(kind, base)
  base = base or "New"
  if not O.Exists(kind, base) then return base end
  local i = 2
  while O.Exists(kind, base .. " " .. i) do i = i + 1 end
  return base .. " " .. i
end

function O.Create(kind, name)
  name = CleanName(name)
  if name == "" then name = O.FreeName(kind) end
  if O.Exists(kind, name) then return nil, "There is already an operation called " .. name .. "." end
  Kind(kind)[name] = {}
  Changed()
  return name
end

function O.Copy(kind, name, newName)
  if not O.Exists(kind, name) then return nil end
  newName = CleanName(newName or O.FreeName(kind, name))
  if newName == "" or O.Exists(kind, newName) then newName = O.FreeName(kind, name) end
  local copy = {}
  for k, v in pairs(Kind(kind)[name]) do copy[k] = v end
  Kind(kind)[newName] = copy
  Changed()
  return newName
end

-- Groups that use an operation (by name) are updated too.
local function ForGroupsUsing(kind, name, fn)
  local groups = CM.Profile().groups
  for _, g in pairs(groups and groups.list or {}) do
    if g.operations and g.operations[kind] == name then fn(g.operations) end
  end
  local base = groups and groups.baseOperations
  if base and base[kind] == name then fn(base) end
end

function O.Rename(kind, name, newName)
  newName = CleanName(newName)
  if not O.Exists(kind, name) then return nil, "No such operation." end
  if newName == "" then return nil, "The name is empty." end
  if newName == name then return name end
  if O.Exists(kind, newName) then return nil, "There is already an operation called " .. newName .. "." end
  Kind(kind)[newName], Kind(kind)[name] = Kind(kind)[name], nil
  ForGroupsUsing(kind, name, function(ops) ops[kind] = newName end)
  Changed()
  CM.SendMessage("CM_GROUPS_CHANGED")
  return newName
end

function O.Delete(kind, name)
  if not O.Exists(kind, name) then return false end
  Kind(kind)[name] = nil
  ForGroupsUsing(kind, name, function(ops) ops[kind] = nil end)
  Changed()
  CM.SendMessage("CM_GROUPS_CHANGED")
  return true
end

-- Groups (paths) using an operation, the Base Group first.
function O.UsedBy(kind, name)
  local list = {}
  local groups = CM.Profile().groups
  if groups and groups.baseOperations and groups.baseOperations[kind] == name then list[1] = G.BASE_NAME end
  local rest = {}
  for id, g in pairs(groups and groups.list or {}) do
    if g.operations and g.operations[kind] == name then rest[#rest + 1] = G.Path(id) end
  end
  table.sort(rest)
  for _, p in ipairs(rest) do list[#list + 1] = p end
  return list
end

-- Checks and saves one field. Returns true or nil, what is wrong.
function O.Set(kind, name, key, value)
  local f = O.Field(kind, key)
  if not (f and O.Exists(kind, name)) then return nil, "No such operation or field." end
  if f.type == "price" then
    value = tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local ok, err = API.ParsePrice(value)
    if not ok then return nil, err end
  elseif f.type == "number" then
    value = tonumber(value)
    if not value then return nil, "Not a number." end
    value = math.floor(value)
    if (f.min and value < f.min) or (f.max and value > f.max) then
      return nil, ("Between %d and %d."):format(f.min or 0, f.max or 0)
    end
  elseif f.type == "choice" then
    local found = false
    for _, o in ipairs(f.options) do if o[1] == value then found = true end end
    if not found then return nil, "Not one of the choices." end
  elseif f.type == "toggle" then
    value = value and true or false
  else
    value = CleanName(value)
  end
  if value == f.default then value = nil end -- keep the saved table small
  Kind(kind)[name][key] = value
  Changed()
  return true
end

-- The operation of a kind that applies to an item: name, settings,
-- groupID (0 = the Base Group). nil when none does.
-- Kinds that move, sell or mail items: the Base Group's operation only
-- covers items that are in at least one group of yours (your groups
-- without their own operation of that kind). Items in no group are left
-- alone. Posting and Crafting cover every item (0.42.1, Kim: Post Scan
-- lists everything sellable in your bags unless a group says "None").
O.GROUPED_ONLY = { shop = true, mail = true, vendor = true, bank = true }

function O.ForItem(itemID, kind)
  DB() -- makes the Base operations on first use
  local gid, _, list = G.Winner(itemID, kind)
  if gid == nil then return nil end
  if gid == G.BASE_ID and O.GROUPED_ONLY[kind] and list and #list <= 1 then return nil end
  local name = G.Operation(gid, kind)
  if not O.Exists(kind, name) then return nil end
  return name, O.Settings(kind, name), gid
end

-- A price field of an operation, worked out for an item.
function O.Price(kind, name, key, itemID)
  local v = O.Value(kind, name, key)
  if type(v) ~= "string" then return nil end
  return API.EvaluatePrice(v, itemID)
end

-- ------------------------------------------------------------------
-- API (minor 5)
-- ------------------------------------------------------------------
function API.GetOperationKinds()
  local out = {}
  for _, k in ipairs(G.OPERATION_KINDS) do out[#out + 1] = { key = k.key, label = k.label } end
  return out
end

-- { { key, type, label, default, options, min, max, tooltip }, ... } (copies)
function API.GetOperationFields(kind)
  local out = {}
  for _, f in ipairs(O.FIELDS[kind] or {}) do
    local c = {}
    for k, v in pairs(f) do c[k] = v end
    out[#out + 1] = c
  end
  return out
end

API.GetOperations = O.Names               -- (kind) -> { name, ... }
API.GetOperation = O.Settings             -- (kind, name) -> { field = value } (copy)
API.CreateOperation = O.Create            -- (kind, name) -> name | nil, error
API.CopyOperation = O.Copy                -- (kind, name, [newName]) -> newName
API.RenameOperation = O.Rename            -- (kind, name, newName) -> newName | nil, error
API.DeleteOperation = O.Delete            -- (kind, name)
API.SetOperationValue = O.Set             -- (kind, name, field, value) -> true | nil, error
API.GetItemOperation = O.ForItem          -- (itemID, kind) -> name, settings, groupID
API.GetOperationPrice = O.Price           -- (kind, name, field, itemID) -> copper
