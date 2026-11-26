-- CueTheCashier: event bus.
--
-- One frame listens to game events for the whole suite and hands them to
-- whoever registered (the core or a module). CueTheCashier's own messages
-- (names start with "CM_", listed in API.lua) go through the same bus, so
-- modules never call each other: one sends a message, the others listen.
--
-- Load-on-demand modules name the events/messages that should load them
-- (## X-CueTheCashier-LoadOn in their .toc). When one of those happens the
-- module is loaded first and then gets the same event, so it never misses
-- the event that woke it up (e.g. AUCTION_HOUSE_SHOW, MAIL_SHOW).
-- Copyright (C) 2026 Kim. Licensed under the GNU GPL v3 or later; see LICENSE.
local _, CM = ...

local frame = CreateFrame("Frame")
local gameSubs = {}  -- [event]   = { { owner, fn }, ... } in registration order
local msgSubs = {}   -- [message] = same
local loadOn = {}    -- [event or message] = { addonName = true }

local function IsMessage(name) return type(name) == "string" and name:find("^CM_") ~= nil end

local function Add(subs, name, owner, fn)
  local list = subs[name]
  if not list then
    list = {}
    subs[name] = list
  end
  for _, s in ipairs(list) do
    if s.owner == owner then s.fn = fn; return end
  end
  list[#list + 1] = { owner = owner, fn = fn }
end

local function Remove(subs, name, owner)
  local list = subs[name]
  if not list then return end
  for i = #list, 1, -1 do
    if list[i].owner == owner then
      list[i].removed = true
      table.remove(list, i)
    end
  end
  if #list == 0 then subs[name] = nil end
end

local function NeedFrameEvent(event)
  return gameSubs[event] ~= nil or (loadOn[event] ~= nil and next(loadOn[event]) ~= nil)
end

local function SyncFrameEvent(event)
  if NeedFrameEvent(event) then
    if not frame:IsEventRegistered(event) then
      local ok = pcall(frame.RegisterEvent, frame, event)
      if not ok and CM.Debug then CM.Debug("Event not known by this client: " .. tostring(event)) end
      return ok
    end
  elseif frame:IsEventRegistered(event) then
    frame:UnregisterEvent(event)
  end
  return true
end

-- An error in one listener must not stop the others. It is logged and
-- handed to the game's error handler (the usual Lua error box).
local function Report(label, err)
  if CM.Debug then CM.Debug(label .. " ERROR: " .. tostring(err)) end
  local handler = geterrorhandler and geterrorhandler()
  if handler then pcall(handler, err) end
end

local function Dispatch(list, name, ...)
  if not list then return end
  -- A copy, so listeners may register or unregister while we loop.
  local copy = {}
  for i, s in ipairs(list) do copy[i] = s end
  for _, s in ipairs(copy) do
    if not s.removed then
      local ok, err = pcall(s.fn, name, ...)
      if not ok then Report(name, err) end
    end
  end
end

-- Loads every module addon that asked to be loaded by `name`.
local function LoadTriggered(name)
  local wanted = loadOn[name]
  if not wanted then return end
  for addon in pairs(wanted) do
    if CM.LoadModuleAddon then CM.LoadModuleAddon(addon, name) end
  end
end

-- ------------------------------------------------------------------
-- Game events. fn(event, ...) gets the event name and its arguments.
-- owner is any table or string; one handler per owner and event.
-- ------------------------------------------------------------------
function CM.RegisterEvent(owner, event, fn)
  assert(type(fn) == "function", "CueTheCashier.RegisterEvent: handler must be a function")
  Add(gameSubs, event, owner, fn)
  return SyncFrameEvent(event)
end

function CM.UnregisterEvent(owner, event)
  Remove(gameSubs, event, owner)
  SyncFrameEvent(event)
end

function CM.UnregisterAllEvents(owner)
  local names = {}
  for event in pairs(gameSubs) do names[#names + 1] = event end
  for _, event in ipairs(names) do CM.UnregisterEvent(owner, event) end
end

frame:SetScript("OnEvent", function(_, event, ...)
  LoadTriggered(event)
  Dispatch(gameSubs[event], event, ...)
end)

-- ------------------------------------------------------------------
-- CueTheCashier messages ("CM_..."). fn(message, ...).
-- ------------------------------------------------------------------
function CM.RegisterMessage(owner, message, fn)
  assert(IsMessage(message), "CueTheCashier messages start with CM_")
  assert(type(fn) == "function", "CueTheCashier.RegisterMessage: handler must be a function")
  Add(msgSubs, message, owner, fn)
end

function CM.UnregisterMessage(owner, message)
  Remove(msgSubs, message, owner)
end

function CM.UnregisterAllMessages(owner)
  local names = {}
  for message in pairs(msgSubs) do names[#names + 1] = message end
  for _, message in ipairs(names) do Remove(msgSubs, message, owner) end
end

function CM.SendMessage(message, ...)
  assert(IsMessage(message), "CueTheCashier messages start with CM_")
  LoadTriggered(message)
  Dispatch(msgSubs[message], message, ...)
end

-- ------------------------------------------------------------------
-- Load triggers (used by Modules.lua).
-- ------------------------------------------------------------------
function CM.AddLoadTrigger(name, addon)
  loadOn[name] = loadOn[name] or {}
  loadOn[name][addon] = true
  if not IsMessage(name) then SyncFrameEvent(name) end
end

-- Called once an addon is loaded (or can't be): it needs no triggers now.
function CM.RemoveLoadTriggers(addon)
  for name, wanted in pairs(loadOn) do
    if wanted[addon] then
      wanted[addon] = nil
      if not next(wanted) then loadOn[name] = nil end
      if not IsMessage(name) then SyncFrameEvent(name) end
    end
  end
end

CM.ReportError = Report
