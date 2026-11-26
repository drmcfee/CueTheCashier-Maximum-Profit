-- CueTheCashier: profiles.
--
-- A profile holds your groups, operations, custom prices and the settings
-- that shape how CueTheCashier works (tooltip lines, auction house choices).
-- Every character uses one profile: its server's own (named after the
-- server and faction, e.g. "EU Normal - Alliance") unless you pick another
-- in Settings. So characters on the same server share one by default, and
-- other servers start apart. Any character can pick any profile. Account things stay outside profiles: price data, the ledger, the
-- debug log, the minimap button and the skin.
--
-- Saved: CueTheCashierDB.profiles[name] = { groups, operations, customPrices, settings }
--        CueTheCashierDB.profileOf["Name - <server key>"] = profile name
-- Message: CM_PROFILE_CHANGED (also sends CM_GROUPS_CHANGED,
-- CM_OPERATIONS_CHANGED and CM_PRICES_CHANGED so every view refreshes).
-- Copyright (C) 2026 Kim. Licensed under the GNU GPL v3 or later; see LICENSE.
local _, CM = ...

local P = {}
CM.Profiles = P

P.DEFAULT = "Default" -- only for data from before 0.31 / before login
-- Keys of the old account settings that belong to a profile now.
local PROFILE_SETTINGS = { "tooltipHide", "openCraftTrade", "snipePercent" }

local charKey, serverKey -- known after PLAYER_LOGIN (faction is needed)

-- The profile a character on this server uses unless it picked another.
function P.Default() return serverKey or P.DEFAULT end

local function DB() return CueTheCashierDB end

-- Moves pre-0.31 data (groups, operations, custom prices at the top of
-- CueTheCashierDB) into the Default profile. Safe to call any time.
function P.Migrate()
  local db = DB()
  if not db then return end
  db.profiles = db.profiles or {}
  db.profileOf = db.profileOf or {}
  local old = db.settings or {}
  local hasOld = db.groups ~= nil or db.operations ~= nil or db.customPrices ~= nil
  for _, k in ipairs(PROFILE_SETTINGS) do if old[k] ~= nil then hasOld = true end end
  if not hasOld then return end
  local d = db.profiles[P.DEFAULT]
  if not d then
    d = { settings = {} }
    db.profiles[P.DEFAULT] = d
  end
  d.settings = d.settings or {}
  for _, k in ipairs({ "groups", "operations", "customPrices" }) do
    if db[k] ~= nil then
      if d[k] == nil then
        d[k] = db[k]
      elseif k == "groups" then
        -- Never let a new, empty groups table win over old groups (0.42.0).
        if type(db[k]) == "table" and next(db[k].list or {}) and not next(d[k].list or {}) then
          local base = d[k].baseOperations
          d[k] = db[k]
          d[k].baseOperations = d[k].baseOperations or base
        end
      elseif type(d[k]) == "table" and type(db[k]) == "table" then
        -- Operations / custom prices: add the old ones that aren't there.
        for name, v in pairs(db[k]) do
          if d[k][name] == nil then
            d[k][name] = v
          elseif k == "operations" and type(v) == "table" and type(d[k][name]) == "table" then
            for opName, op in pairs(v) do
              if d[k][name][opName] == nil or opName == "Base" then d[k][name][opName] = op end
            end
          end
        end
      end
      db[k] = nil
    end
  end
  for _, k in ipairs(PROFILE_SETTINGS) do
    if old[k] ~= nil then
      if d.settings[k] == nil then d.settings[k] = old[k] end
      old[k] = nil
    end
  end
end

function P.Current()
  local db = DB()
  local name = charKey and db.profileOf and db.profileOf[charKey]
  if not (name and db.profiles and db.profiles[name]) then name = P.Default() end
  return name
end

-- The profile table in use (groups, operations, customPrices, settings).
function CM.Profile()
  local db = DB()
  if not db.profiles then P.Migrate() end
  local name = P.Current()
  local p = db.profiles[name]
  if not p and not serverKey then
    -- Before login: a scratch profile that is not saved.
    P.scratch = P.scratch or { settings = {} }
    return P.scratch
  end
  if not p then
    p = { settings = {} }
    db.profiles[name] = p
  end
  p.settings = p.settings or {}
  return p
end

-- Settings saved in the profile (CM.Settings() is account-wide).
function CM.ProfileSettings() return CM.Profile().settings end

function P.Names()
  local list = {}
  for name in pairs(DB().profiles or {}) do list[#list + 1] = name end
  table.sort(list, function(a, b)
    local d = P.Default()
    if a == d or b == d then return a == d end
    return a:lower() < b:lower()
  end)
  return list
end

-- Characters using a profile.
function P.UsedBy(name)
  local list = {}
  for key, n in pairs(DB().profileOf or {}) do
    if n == name then list[#list + 1] = key end
  end
  table.sort(list)
  return list
end

local function Changed()
  CM.SendMessage("CM_PROFILE_CHANGED", P.Current())
  CM.SendMessage("CM_GROUPS_CHANGED")
  CM.SendMessage("CM_OPERATIONS_CHANGED")
  CM.SendMessage("CM_PRICES_CHANGED")
end

local function CleanName(name)
  name = tostring(name or ""):gsub("[\r\n|]", " "):gsub("^%s+", ""):gsub("%s+$", "")
  return name:sub(1, 40)
end

local function DeepCopy(t)
  if type(t) ~= "table" then return t end
  local c = {}
  for k, v in pairs(t) do c[k] = DeepCopy(v) end
  return c
end

-- This character uses the profile (made empty when it doesn't exist).
function P.Use(name)
  name = CleanName(name)
  if name == "" then return nil, "The name is empty." end
  if not charKey then return nil, "Not logged in yet." end
  local db = DB()
  P.Migrate()
  if not db.profiles[name] then db.profiles[name] = { settings = {} } end
  db.profileOf[charKey] = (name ~= P.Default()) and name or nil
  Changed()
  return name
end

-- A new profile for this character, empty or a copy of another.
function P.New(name, copyFrom)
  name = CleanName(name)
  if name == "" then return nil, "Type a name for the new profile." end
  if DB().profiles[name] then return nil, "There is already a profile called " .. name .. "." end
  DB().profiles[name] = copyFrom and DeepCopy(DB().profiles[copyFrom]) or { settings = {} }
  return P.Use(name)
end

-- Replaces the current profile's contents with a copy of another's.
function P.CopyFrom(from)
  local src = DB().profiles[from]
  if not src or from == P.Current() then return nil end
  DB().profiles[P.Current()] = DeepCopy(src)
  Changed()
  return true
end

-- Empties the current profile (no groups, operations, custom prices; default settings).
function P.Reset()
  DB().profiles[P.Current()] = { settings = {} }
  Changed()
  return true
end

-- Deletes a profile (not this server's own). Its characters go back to
-- their server's profile.
function P.Delete(name)
  if name == P.Default() or not DB().profiles[name] then return nil end
  DB().profiles[name] = nil
  for key, n in pairs(DB().profileOf) do
    if n == name then DB().profileOf[key] = nil end
  end
  Changed()
  return true
end

CM.RegisterEvent(P, "PLAYER_LOGIN", function()
  P.Migrate()
  serverKey = CM:GetAuctionKey()
  charKey = (UnitName("player") or "?") .. " - " .. serverKey
  local db = DB()
  if not db.profiles[serverKey] then
    -- The first server seen takes over "Default" (everything made before
    -- 0.33); other servers start with an empty profile of their own.
    if db.profiles[P.DEFAULT] and not db.defaultClaimed then
      db.profiles[serverKey] = db.profiles[P.DEFAULT]
      db.profiles[P.DEFAULT] = nil
      for key, n in pairs(db.profileOf) do if n == P.DEFAULT then db.profileOf[key] = nil end end
    else
      db.profiles[serverKey] = { settings = {} }
    end
  end
  db.defaultClaimed = db.defaultClaimed or serverKey
  if P.Current() ~= P.DEFAULT then
    CM.Debug("Profile: " .. P.Current())
    Changed()
  end
end)

-- ------------------------------------------------------------------
-- API (minor 7)
-- ------------------------------------------------------------------
local API = CM.API
API.GetProfile = P.Current            -- () -> name used by this character
API.GetProfiles = P.Names             -- () -> { name, ... } (this server's first)
API.UseProfile = P.Use                -- (name) -> name | nil, error
API.NewProfile = P.New                -- (name, [copyFrom]) -> name | nil, error
API.CopyProfile = P.CopyFrom          -- (from): into the current profile
API.ResetProfile = P.Reset            -- (): empties the current profile
API.DeleteProfile = P.Delete          -- (name)
