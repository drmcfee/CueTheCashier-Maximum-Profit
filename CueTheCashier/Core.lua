-- CueTheCashier: core namespace, saved variables, server key and startup.
--
-- CueTheCashier is a suite: this core addon holds the price data, price
-- sources, saved data, debug log, shared UI pieces, skins and the public
-- API (API.lua). Features live in module addons (CueTheCashier_Auctioning,
-- CueTheCashier_Accounting, ...) that talk to the core only through the
-- module system (Modules.lua), the event bus (Events.lua) and the API.
-- The global `CueTheCashier` is the only name the suite puts in _G (apart
-- from saved variables, the slash command and named frames).
-- Copyright (C) 2026 Kim. Licensed under the GNU GPL v3 or later; see LICENSE.
local ADDON_NAME, CM = ...
_G.CueTheCashier = CM

CM.ADDON_NAME = ADDON_NAME
CM.version = "0.45.0"
CM.NAME = "CueTheCashier: Maximum Profit"
-- Icons (TGA, power of two). Folder names stay CueTheCashier* so saved data keeps working.
CM.ICON = "Interface\\AddOns\\CueTheCashier\\Media\\icon128"
CM.ICON_ROUND = "Interface\\AddOns\\CueTheCashier\\Media\\icon_round"

-- Bump when the saved data layout changes.
local DB_VERSION = 3

local function Print(msg)
  print("|cff33ff99CueTheCashier|r: " .. tostring(msg))
  if CM.Debug then CM.Debug(msg) end
end
CM.Print = Print

-- Money text used everywhere in CueTheCashier. Smaller coins are always
-- shown with two digits once a bigger coin is shown, so prices line up:
-- 5c, 1s 05c, 1g 00s 00c (with the coin icons instead of letters).
local GOLD_ICON = "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t"
local SILVER_ICON = "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t"
local COPPER_ICON = "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t"
function CM.FormatMoney(copper)
  copper = math.floor(tonumber(copper) or 0)
  local gold = math.floor(copper / 10000)
  local silver = math.floor(copper / 100) % 100
  local cop = copper % 100
  if gold > 0 then
    local g = BreakUpLargeNumbers and BreakUpLargeNumbers(gold) or tostring(gold)
    return ("%s%s %02d%s %02d%s"):format(g, GOLD_ICON, silver, SILVER_ICON, cop, COPPER_ICON)
  elseif silver > 0 then
    return ("%d%s %02d%s"):format(silver, SILVER_ICON, cop, COPPER_ICON)
  end
  return ("%d%s"):format(cop, COPPER_ICON)
end

-- Item ID from a number, an item link or an item string.
function CM.ParseItemID(text)
  if not text then return nil end
  return tonumber(text) or tonumber(tostring(text):match("item:(%d+)"))
end

-- Settings shared by the core and the modules (CueTheCashierDB.settings).
function CM.Settings()
  return CueTheCashierDB.settings
end

-- Forever has mega servers: GetRealmName() is "" and GetRealmID() 0 (seen
-- in game). The server is named by region and server type, e.g.
-- "EU Normal". Since 0.37 the type comes from the server's rule flags
-- (C_GameRules.IsGameRuleActive with the Hardcore, RP and PvP rulesets):
-- Hardcore, Roleplay PvP, Roleplay, PvP or Normal. The server's number
-- (C_GameRules.GetForeverExperiencePreset, 1 = Normal on Kim's server) is
-- saved with the name it had, in CueTheCashierDB.servers, so the number can
-- name the server later without asking for the rules.
local PRESET_NAMES = { [1] = "Normal" }

local function Call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, v = pcall(fn, ...)
  if ok then return v end
end

-- true/false for one rule flag, or nil when this client can't tell.
local function RuleActive(name)
  local rules = C_GameRules
  local enum = Enum and Enum.GameRule
  if not (rules and rules.IsGameRuleActive and enum and enum[name] ~= nil) then return nil end
  local ok, v = pcall(rules.IsGameRuleActive, enum[name])
  if ok then return v and true or false end
end

-- "Hardcore", "Roleplay PvP", "Roleplay", "PvP", "Normal", or nil when the
-- rule flags can't be read.
function CM.ServerType()
  local hc, rp, pvp = RuleActive("HardcoreRuleset"), RuleActive("RPRuleset"), RuleActive("PvPRuleset")
  if hc == nil and rp == nil and pvp == nil then return nil end
  if hc or Call((C_GameRules or {}).IsHardcoreActive) then return "Hardcore" end
  if rp and pvp then return "Roleplay PvP" end
  if rp then return "Roleplay" end
  if pvp then return "PvP" end
  return "Normal"
end

function CM.ServerID()
  return Call((C_GameRules or {}).GetForeverExperiencePreset)
end

-- The name a server number was saved with (on any earlier login).
local function LearnedName(region, id)
  local servers = CueTheCashierDB and CueTheCashierDB.servers
  local e = servers and id and servers[(region or "") .. "-" .. tostring(id)]
  return e and e.type
end

function CM.ServerName()
  local region = Call(GetCurrentRegionName)
  local rules = C_GameRules or {}
  local id = CM.ServerID()
  local mode = CM.ServerType() or LearnedName(region, id)
  if not mode then
    if Call(rules.IsHardcoreActive) then
      mode = "Hardcore"
    else
      mode = id and (PRESET_NAMES[id] or ("Preset " .. tostring(id))) or nil
    end
  end
  if Call(rules.IsSelfFoundAllowed) then mode = (mode or "") .. " Self-Found" end
  local name = table.concat({ region ~= "" and region or nil, mode }, " ")
  if name == "" then return nil end
  return name
end

-- How 0.10.15-0.36 named the server (by number only), to move data saved
-- under that name when the new name differs.
function CM.OldServerName()
  local region = Call(GetCurrentRegionName)
  local rules = C_GameRules or {}
  local mode
  if Call(rules.IsHardcoreActive) then
    mode = "Hardcore"
  else
    local id = CM.ServerID()
    mode = id and (PRESET_NAMES[id] or ("Preset " .. tostring(id))) or nil
  end
  if Call(rules.IsSelfFoundAllowed) then mode = (mode or "") .. " Self-Found" end
  local name = table.concat({ region ~= "" and region or nil, mode }, " ")
  if name == "" then return nil end
  return name
end

-- Saves this server's number with its type (at login).
function CM.RecordServer()
  local region, id, kind = Call(GetCurrentRegionName), CM.ServerID(), CM.ServerType()
  if not (id and kind) then return end
  CueTheCashierDB.servers = CueTheCashierDB.servers or {}
  local key = (region or "") .. "-" .. tostring(id)
  local e = CueTheCashierDB.servers[key] or {}
  if e.type and e.type ~= kind then
    CM.Debug(("Server %s was %s, now %s."):format(key, e.type, kind))
  end
  e.id, e.region, e.type, e.seen = id, region, kind, time()
  CueTheCashierDB.servers[key] = e
end

-- Data saved under the old name moves to the new one (prices, gold,
-- profiles) unless the new name already has some.
function CM.MoveRenamedServerData()
  local old, new = CM.OldServerName(), CM.ServerName()
  if not (old and new) or old == new or GetRealmName() ~= "" then return end
  local faction = UnitFactionGroup("player") or "Neutral"
  local oldKey, newKey = old .. " - " .. faction, new .. " - " .. faction
  local moved = false
  for _, store in ipairs({ CueTheCashierDB.realms, CueTheCashierDB.gold, CueTheCashierDB.goldHistory, CueTheCashierDB.profiles }) do
    if type(store) == "table" and store[oldKey] and not store[newKey] then
      store[newKey], store[oldKey] = store[oldKey], nil
      moved = true
    end
  end
  if type(CueTheCashierDB.profileOf) == "table" then
    for k, v in pairs(CueTheCashierDB.profileOf) do
      if v == oldKey then CueTheCashierDB.profileOf[k] = newKey end
    end
  end
  if CueTheCashierDB.defaultClaimed == oldKey then CueTheCashierDB.defaultClaimed = newKey end
  if moved then CM.Print(("Saved data moved from \"%s\" to \"%s\" (server type now read from its rules)."):format(oldKey, newKey)) end
end

-- GUESS: Forever may share one auction house across factions like retail,
-- or keep one per faction like 2004. We key by server AND faction to be safe.
function CM:GetAuctionKey()
  local realm = GetRealmName()
  if not realm or realm == "" then realm = CM.ServerName() or "UnknownRealm" end
  local faction = UnitFactionGroup("player") or "Neutral"
  return realm .. " - " .. faction
end

-- Data saved before 0.13.0 under " - <faction>" (empty realm name) moves
-- to the new key, prices and ledger both, unless the new key has data.
function CM.MoveEmptyRealmData()
  local faction = UnitFactionGroup("player")
  if not faction then return end
  local old, new = " - " .. faction, CM:GetAuctionKey()
  if old == new then return end
  for _, store in ipairs({ CueTheCashierDB.realms, CueTheCashierDB.ledger }) do
    if type(store) == "table" and store[old] and not store[new] then
      store[new], store[old] = store[old], nil
      CM.Print(("Saved data moved from \"%s\" to \"%s\"."):format(old, new))
    end
  end
end

-- Modules that got their own saved file in 0.14.0 take their old data out
-- of CueTheCashierDB with this (once). Returns the old table, or nil.
function CM.TakeLegacyData(key)
  local old = CueTheCashierDB and CueTheCashierDB[key]
  if old ~= nil then CueTheCashierDB[key] = nil end
  return old
end

function CM:GetRealmData()
  local key = self:GetAuctionKey()
  local realms = CueTheCashierDB.realms
  if not realms[key] then
    realms[key] = { lastScan = 0, items = {} }
  end
  return realms[key]
end

-- Copper per single item from the last scan, or nil if never seen.
-- (Modules use CueTheCashier.API.GetPrice instead.)
function CM:GetMinBuyout(itemID)
  local entry = self:GetItemEntry(itemID)
  return entry and entry.minBuyout or nil
end

-- ------------------------------------------------------------------
-- Shared commodity prices (0.44.0)
--
-- Stackable items (commodities) look like they share one auction house
-- over every server type of a region (TSM keys them per region too). So
-- scans also save commodities under one region key, e.g.
-- "EU Commodities (all server types)", next to the server's own key as
-- before: two copies, nothing is moved or removed. Prices for a commodity
-- come from the newest of the shared copy and every server type's own
-- copy, so a scan on any character counts everywhere. Turning the
-- setting off (Settings > Auction house) goes back to only this server's
-- own copy; scans keep filling both, so switching either way loses nothing.
-- ------------------------------------------------------------------
function CM.SharedKey()
  local region = Call(GetCurrentRegionName)
  if type(region) ~= "string" or region == "" then return nil end
  return region .. " Commodities (all server types)"
end

function CM.SharedCommoditiesOn()
  local s = CueTheCashierDB and CueTheCashierDB.settings
  return not (s and s.sharedCommodities == false) and CM.SharedKey() ~= nil
end

-- true when the item stacks (a commodity), false when not, nil when the
-- game hasn't loaded it yet. Saved in itemInfo once known.
function CM.IsCommodity(itemID)
  if not itemID then return nil end
  local info = CueTheCashierDB.itemInfo and CueTheCashierDB.itemInfo[itemID]
  if info and info.stack then return info.stack > 1 end
  if not (C_Item and C_Item.GetItemInfo) then return nil end
  local ok, name, _, _, _, _, _, _, stack = pcall(C_Item.GetItemInfo, itemID)
  if not (ok and name and type(stack) == "number") then return nil end
  if CueTheCashierDB.itemInfo then
    info = CueTheCashierDB.itemInfo[itemID] or {}
    info.stack = stack
    CueTheCashierDB.itemInfo[itemID] = info
  end
  return stack > 1
end

function CM:GetSharedData()
  local key = CM.SharedKey()
  if not key then return nil end
  local realms = CueTheCashierDB.realms
  if not realms[key] then realms[key] = { lastScan = 0, items = {}, shared = true } end
  return realms[key]
end

-- The saved entry for an item and the key it is saved under.
function CM:GetItemEntryAndKey(itemID)
  if not itemID then return nil end
  local key = self:GetAuctionKey()
  local entry = self:GetRealmData().items[itemID]
  if not (CM.SharedCommoditiesOn() and CM.IsCommodity(itemID)) then return entry, key end
  -- Newest copy: the shared one, or any server type of the region
  -- (scans from before 0.44.0 only have those).
  local best, bestKey, bestT = entry, key, entry and entry.lastSeen or -1
  local region = Call(GetCurrentRegionName) or ""
  local shared = CM.SharedKey()
  for k, realm in pairs(CueTheCashierDB.realms) do
    if k ~= key and (k == shared or k:sub(1, #region + 1) == region .. " ") then
      local e = type(realm) == "table" and realm.items and realm.items[itemID]
      -- The shared copy wins a tie: it holds every server type's scans.
      if e and ((e.lastSeen or 0) > bestT or (k == shared and (e.lastSeen or 0) == bestT)) then
        best, bestKey, bestT = e, k, e.lastSeen or 0
      end
    end
  end
  return best, bestKey
end

function CM:GetItemEntry(itemID)
  return (self:GetItemEntryAndKey(itemID))
end

-- ------------------------------------------------------------------
-- Full scan cooldown. Kept in the core because it is account-wide saved
-- data that both the scanner and /cmp status need.
-- GUESS: 15 minutes, taken from retail. Blizzard has no API that reports
-- the remaining cooldown, so this is our own timer.
-- ------------------------------------------------------------------
CM.FULL_SCAN_COOLDOWN = 15 * 60

function CM.FullScanCooldown()
  local last = CueTheCashierDB.lastFullScan or 0
  return math.max(0, last + CM.FULL_SCAN_COOLDOWN - time())
end

function CM.FullScanCooldownText()
  local s = CM.FullScanCooldown()
  if s <= 0 then return "now" end
  return ("%d:%02d"):format(math.floor(s / 60), s % 60)
end

function CM.MarkFullScan()
  CueTheCashierDB.lastFullScan = time()
end

-- ------------------------------------------------------------------
-- Startup
-- ------------------------------------------------------------------
-- 0.41.0 renamed the saved variables (CraftMarketDB -> CueTheCashierDB,
-- ...). Each .toc lists the old name too, so data saved under it still
-- loads; here it moves to the new name once and the old one is dropped
-- (the game then stops saving it).
local OLD_SAVED = {
  CueTheCashierDB = "CraftMarketDB",
  CueTheCashierAccountingDB = "CraftMarketAccountingDB",
  CueTheCashierCraftingDB = "CraftMarketCraftingDB",
  CueTheCashierDestroyingDB = "CraftMarketDestroyingDB",
  CueTheCashierHistoryDB = "CraftMarketHistoryDB",
}
function CM.AdoptOldSaved(newName)
  local oldName = OLD_SAVED[newName]
  local old = oldName and _G[oldName]
  if type(old) ~= "table" then return false end
  local cur = _G[newName]
  local moved = false
  if type(cur) ~= "table" or next(cur) == nil then
    _G[newName] = old
    moved = true
  end
  _G[oldName] = nil
  if moved then CM.Debug(("Saved data moved from %s to %s."):format(oldName, newName)) end
  return moved
end

local function InitDB()
  CM.AdoptOldSaved("CueTheCashierDB")
  if type(CueTheCashierDB) ~= "table" or type(CueTheCashierDB.realms) ~= "table"
     or (CueTheCashierDB.dbVersion or 1) > DB_VERSION then
    -- Missing, broken, or saved by a newer CueTheCashier: start fresh.
    CueTheCashierDB = { dbVersion = DB_VERSION, realms = {}, settings = {}, itemInfo = {} }
    CM.freshDB = true
  end
  CM.Data.Migrate(CueTheCashierDB)
  CueTheCashierDB.settings = CueTheCashierDB.settings or {}
  CueTheCashierDB.settings.skin = CueTheCashierDB.settings.skin or "Blizzard"
  CueTheCashierDB.settings.debug = CueTheCashierDB.settings.debug or false
  CM.Profiles.Migrate()
  -- Account-wide, because Blizzard's full-scan cooldown is account-wide.
  CueTheCashierDB.lastFullScan = CueTheCashierDB.lastFullScan or 0
end

CM.RegisterEvent(CM, "ADDON_LOADED", function(_, addon)
  if addon ~= ADDON_NAME then return end
  CM.UnregisterEvent(CM, "ADDON_LOADED")
  InitDB()
  CM.dbReady = true
  CM.UpdateEventSpy()
  -- Learn which module addons are installed and when to load them.
  CM.Try("Find modules", CM.FindModuleAddons)
end)

-- 0.40.0 renamed the folders from CueTheCashier* to CueTheCashier*. The
-- saved data files follow the folder names, so the old files must be
-- renamed once by hand (README). Old folders left in AddOns would load a
-- second copy: say so.
function CM.CheckOldFolders()
  local api = C_AddOns or {}
  local getInfo = api.GetAddOnInfo or GetAddOnInfo
  local num = (api.GetNumAddOns or GetNumAddOns or function() return 0 end)()
  local old = {}
  for i = 1, num do
    local name = getInfo and getInfo(i)
    if type(name) == "string" and (name == "CraftMarket" or name:find("^CraftMarket_")) then old[#old + 1] = name end
  end
  if #old > 0 then
    Print("|cffff2020Old CraftMarket folders are still in your AddOns folder (" .. table.concat(old, ", ") ..
      "). Delete them; CueTheCashier replaces them.|r")
  end
  if CM.freshDB then
    Print("No saved data found. Coming from CraftMarket? See README: rename the saved files in WTF once.")
  end
end

CM.RegisterEvent(CM, "PLAYER_LOGIN", function()
  CM.LogEnvironment()
  CM.Try("Old folders", CM.CheckOldFolders)
  CM.Try("Move saved data", CM.MoveEmptyRealmData)
  CM.Try("Server rules", CM.RecordServer)
  CM.Try("Move renamed server data", CM.MoveRenamedServerData)
  local data = CM:GetRealmData()
  local count = 0
  for _ in pairs(data.items) do count = count + 1 end
  -- Shown on every login so we can tell if SavedVariables persisted
  -- (they reportedly did not in the Forever beta).
  if data.lastScan > 0 then
    Print(("%d prices loaded for %s, last scan %s."):format(
      count, CM:GetAuctionKey(), date("%Y-%m-%d %H:%M", data.lastScan)))
  else
    Print("No saved prices yet. Open the auction house and click Scan.")
  end
  CM.EnableModules()
end)

-- ------------------------------------------------------------------
-- Escape. Seen in game (0.19.0-0.22.0): our frames in Blizzard's Escape
-- list (UISpecialFrames), or catching keys with OnKeyDown, tainted
-- Blizzard's game menu, and it then blocked SpellStopCasting() /
-- SpellStopTargeting() (ADDON_ACTION_FORBIDDEN from ToggleGameMenu).
-- So our windows close AFTER Blizzard has handled Escape, from a
-- hooksecurefunc post-hook, which never taints Blizzard's own code. One
-- press closes Blizzard's windows and ours together.
-- ------------------------------------------------------------------
local escapeFrames = {}
function CM.CloseOnEscape(frame)
  escapeFrames[#escapeFrames + 1] = frame
end

local function HookEscape()
  if CM.escapeHooked or type(_G.ToggleGameMenu) ~= "function" then return end
  CM.escapeHooked = true
  hooksecurefunc("ToggleGameMenu", function()
    for _, f in ipairs(escapeFrames) do
      if f:IsShown() then f:Hide() end
    end
  end)
end
CM.RegisterEvent("Escape", "PLAYER_LOGIN", HookEscape)
-- Blizzard's game menu code can load later on Forever.
CM.RegisterEvent("Escape", "ADDON_LOADED", HookEscape)
