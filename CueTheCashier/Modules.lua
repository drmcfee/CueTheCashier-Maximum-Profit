-- CueTheCashier: module system.
--
-- Every feature addon of the suite (CueTheCashier_Auctioning, _Accounting,
-- _Destroying, _Crafting) makes one module object:
--
--   local CM = CueTheCashier
--   local Module = CM:NewModule("Accounting", { addon = ADDON_NAME, api = 1 })
--   function Module:OnInitialize() end -- its saved variables are loaded
--   function Module:OnEnable() end     -- the player is in the world
--   function Module:OnDisable() end
--
-- A module gets its events and messages through the core
-- (Module:RegisterEvent / RegisterMessage / SendMessage), its slash
-- commands through Module:RegisterCommand, and data through
-- CueTheCashier.API. Modules never call each other.
--
-- Load on demand: a module addon's .toc can say when to load it:
--   ## LoadOnDemand: 1
--   ## X-CueTheCashier-LoadOn: AUCTION_HOUSE_SHOW, CM_MINIMAP_TOOLTIP
--   ## X-CueTheCashier-Commands: ledger
-- The core reads that at startup, loads the module when one of those events
-- or messages happens (it then gets that same event), or when you type one
-- of its /cmp commands.
-- Copyright (C) 2026 Kim. Licensed under the GNU GPL v3 or later; see LICENSE.
local _, CM = ...

local Module = {}
Module.__index = Module

local modules, order = {}, {}
CM.modules = modules
CM.moduleAddons = {} -- [addonName] = { title, loadOn = {...}, commands = {...}, lod = bool }

-- Turns a method name or function into fn(...) that calls it with self
-- first: handler(self, ...).
local function Bind(self, handler, default)
  handler = handler or default
  if type(handler) == "string" then
    local name = handler
    return function(...) return self[name](self, ...) end
  end
  assert(type(handler) == "function", "handler must be a function or a method name")
  return function(...) return handler(self, ...) end
end

-- ------------------------------------------------------------------
-- Module object
-- ------------------------------------------------------------------

-- handler: a method name (string) or function(self, event, ...); default
-- is the method named like the event.
function Module:RegisterEvent(event, handler)
  return CM.RegisterEvent(self, event, Bind(self, handler, event))
end

function Module:UnregisterEvent(event) CM.UnregisterEvent(self, event) end

function Module:RegisterMessage(message, handler)
  CM.RegisterMessage(self, message, Bind(self, handler, message))
end

function Module:UnregisterMessage(message) CM.UnregisterMessage(self, message) end

function Module:SendMessage(message, ...) CM.SendMessage(message, ...) end

-- /cmp <name>: fn(self, rest of the line). usage is shown in /cmp help.
function Module:RegisterCommand(name, fn, usage)
  CM.RegisterCommand(name, self, Bind(self, fn), usage)
end

function Module:Print(msg) CM.Print(msg) end
function Module:Debug(msg, ...) CM.Debug(msg, ...) end
function Module:IsEnabled() return self.state == "enabled" end

function Module:Enable()
  if self.state == "enabled" then return end
  if self.state ~= "initialized" and self.state ~= "disabled" then return end
  self.state = "enabled"
  if self.OnEnable then
    local ok, err = pcall(self.OnEnable, self)
    if not ok then CM.ReportError(self.name .. " OnEnable", err) end
  end
  CM.SendMessage("CM_MODULE_ENABLED", self.name)
end

function Module:Disable()
  if self.state ~= "enabled" then return end
  self.state = "disabled"
  if self.OnDisable then
    local ok, err = pcall(self.OnDisable, self)
    if not ok then CM.ReportError(self.name .. " OnDisable", err) end
  end
  CM.UnregisterAllEvents(self)
  CM.UnregisterAllMessages(self)
  CM.SendMessage("CM_MODULE_DISABLED", self.name)
end

-- ------------------------------------------------------------------
-- Creating and starting modules
-- ------------------------------------------------------------------

-- opts.addon: the module's addon folder name (the first value of `...`).
-- opts.api: the API version the module was written for.
function CM:NewModule(name, opts)
  opts = opts or {}
  assert(type(name) == "string", "CueTheCashier:NewModule needs a name")
  assert(not modules[name], "CueTheCashier module already exists: " .. name)
  if opts.api and opts.api ~= CM.API_VERSION then
    error(("%s was made for CueTheCashier API %s, this core has API %s. Update both folders."):format(
      name, tostring(opts.api), tostring(CM.API_VERSION)), 2)
  end
  local m = setmetatable({ name = name, addon = opts.addon, state = "new" }, Module)
  modules[name] = m
  order[#order + 1] = m
  return m
end

function CM:GetModule(name) return modules[name] end

local function Initialize(m)
  if m.state ~= "new" then return end
  m.state = "initialized"
  if m.OnInitialize then
    local ok, err = pcall(m.OnInitialize, m)
    if not ok then CM.ReportError(m.name .. " OnInitialize", err) end
  end
end

-- Starts the modules of one addon once its files and saved variables are
-- loaded. Before login they are enabled at PLAYER_LOGIN.
local function StartAddon(addon)
  for _, m in ipairs(order) do
    if m.addon == addon then
      Initialize(m)
      if CM.loggedIn then m:Enable() end
    end
  end
end

CM.RegisterEvent("Modules", "ADDON_LOADED", function(_, addon)
  if addon == CM.ADDON_NAME or not CM.dbReady then return end
  StartAddon(addon)
end)

-- Called by Core.lua at PLAYER_LOGIN.
function CM.EnableModules()
  CM.loggedIn = true
  for _, m in ipairs(order) do
    if m.state == "new" and m.addon and C_AddOns and C_AddOns.IsAddOnLoaded
        and C_AddOns.IsAddOnLoaded(m.addon) then
      Initialize(m)
    end
    if m.state == "initialized" then m:Enable() end
  end
end

-- ------------------------------------------------------------------
-- Finding module addons and loading them on demand
-- ------------------------------------------------------------------
local function SplitList(text)
  local list = {}
  for item in tostring(text or ""):gmatch("[^,%s]+") do list[#list + 1] = item end
  return list
end

local function Meta(addon, field)
  local get = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
  if not get then return nil end
  local ok, v = pcall(get, addon, field)
  return ok and v or nil
end

local function IsLoaded(addon)
  local f = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
  return f and f(addon) and true or false
end
CM.IsAddOnLoaded = IsLoaded

-- Reads every installed CueTheCashier_* addon's .toc fields.
function CM.FindModuleAddons()
  local api = C_AddOns or {}
  local count = (api.GetNumAddOns or GetNumAddOns or function() return 0 end)()
  local getInfo = api.GetAddOnInfo or GetAddOnInfo
  local isLoD = api.IsAddOnLoadOnDemand or IsAddOnLoadOnDemand
  for i = 1, count do
    local name, title = getInfo(i)
    if type(name) == "string" and name:find("^CueTheCashier_") then
      local info = {
        title = title, loadOn = SplitList(Meta(name, "X-CueTheCashier-LoadOn")),
        commands = SplitList(Meta(name, "X-CueTheCashier-Commands")),
        lod = isLoD and isLoD(name) and true or false,
      }
      CM.moduleAddons[name] = info
      if info.lod and not IsLoaded(name) then
        for _, trigger in ipairs(info.loadOn) do CM.AddLoadTrigger(trigger, name) end
      end
    end
  end
end

-- Loads a module addon (if needed). why: what asked for it, for the log.
-- Returns true when it is loaded.
local failed = {}
function CM.LoadModuleAddon(addon, why)
  if IsLoaded(addon) then
    CM.RemoveLoadTriggers(addon)
    return true
  end
  local load = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
  if not load then return false end
  local ok, loaded, reason = pcall(load, addon)
  CM.RemoveLoadTriggers(addon)
  if ok and loaded then
    if CM.Debug then CM.Debug(("Loaded %s (%s)."):format(addon, tostring(why))) end
    StartAddon(addon) -- in case ADDON_LOADED came before the core was ready
    return true
  end
  reason = ok and reason or loaded
  if not failed[addon] then
    failed[addon] = true
    if reason == "DISABLED" then
      if CM.Debug then CM.Debug(addon .. " is turned off in the AddOns list, not loaded.") end
    else
      CM.Print(("Could not load %s (%s)."):format(addon, tostring(reason)))
    end
  end
  return false
end
