-- CueTheCashier: the main window.
--
-- One window in Blizzard's style with tabs along the bottom. The core
-- makes the window and its Overview, Groups, Operations, Prices and
-- Settings tabs (MainTabs.lua); modules add their own tabs, Overview
-- boxes and Settings through the API (API minor 2):
--
--   API.RegisterMainTab(key, { title = "Ledger", order = 20,
--     build = function(page) end,  -- once, the first time the tab is shown
--     show = function(page) end,   -- every time it is shown or refreshed
--     hide = function(page) end })
--   API.RegisterOverviewSection(key, { title, order, wide = bool,
--     lines = function() return { { left = text, right = text, itemID = id }, ... } end })
--   API.RegisterSettings(groupKey, { title, order, settings = {
--     { type = "toggle", label, tooltip, get = fn, set = fn(value) },
--     { type = "number", label, tooltip, min, max, get = fn, set = fn(value) } } })
--     (a group key that already exists gets the settings added to it)
--   API.ShowMainWindow(key), API.ToggleMainWindow(key), API.RefreshMainWindow()
--
-- A page is a frame covering the whole window; pages place their own
-- things below the title bar (the portrait takes the top left corner).
-- Opening the window sends CM_MAIN_WINDOW_SHOW, so load-on-demand modules
-- that list it in their .toc load first and add their tabs.
-- Copyright (C) 2026 Kim. Licensed under the GNU GPL v3 or later; see LICENSE.
local _, CM = ...
local API = CM.API

local MW = { tabs = {}, sections = {}, settingGroups = {} }
CM.MainWindow = MW

local WIDTH, HEIGHT = 820, 520
MW.WIDTH, MW.HEIGHT = WIDTH, HEIGHT

local frame, current

local function Sorted(registry)
  local list = {}
  for _, v in pairs(registry) do list[#list + 1] = v end
  table.sort(list, function(a, b)
    if (a.order or 100) ~= (b.order or 100) then return (a.order or 100) < (b.order or 100) end
    return (a.title or a.key) < (b.title or b.key)
  end)
  return list
end
MW.Sorted = Sorted

-- ------------------------------------------------------------------
-- Registries (API)
-- ------------------------------------------------------------------
function API.RegisterMainTab(key, info)
  assert(type(key) == "string" and type(info) == "table", "RegisterMainTab(key, info)")
  local old = MW.tabs[key]
  local tab = { key = key, title = info.title or key, order = info.order, build = info.build,
    show = info.show, hide = info.hide }
  if old then tab.page = old.page end -- keep a page already built
  MW.tabs[key] = tab
  if frame then MW:BuildTabs() end
end

function API.RegisterOverviewSection(key, info)
  assert(type(key) == "string" and type(info) == "table" and type(info.lines) == "function",
    "RegisterOverviewSection(key, { lines = function })")
  MW.sections[key] = { key = key, title = info.title or key, order = info.order, wide = info.wide,
    lines = info.lines }
end

function API.RegisterSettings(key, info)
  assert(type(key) == "string" and type(info) == "table", "RegisterSettings(key, info)")
  local g = MW.settingGroups[key]
  if not g then
    g = { key = key, title = info.title or key, order = info.order, settings = {} }
    MW.settingGroups[key] = g
  end
  if info.title then g.title = info.title end
  if info.order then g.order = info.order end
  for _, s in ipairs(info.settings or {}) do g.settings[#g.settings + 1] = s end
  if frame and frame:IsShown() then MW:Refresh() end
end

function API.ShowMainWindow(key) MW:Show(key) end
function API.ToggleMainWindow(key) MW:Toggle(key) end
function API.RefreshMainWindow() MW:Refresh() end

-- ------------------------------------------------------------------
-- Window
-- ------------------------------------------------------------------
local function Build()
  local skin = CM.Skins:Get()
  frame = CreateFrame("Frame", "CueTheCashierMainFrame", UIParent, skin.mainWindowTemplate)
  CM.Skins:ApplyWindow(frame)
  local f = frame
  f:SetSize(WIDTH, HEIGHT)
  f:SetPoint("CENTER")
  CM.Raisable(f) -- comes to the front when clicked (Widgets.lua)
  f:EnableMouse(true)
  f:SetMovable(true)
  f:SetClampedToScreen(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  if f.SetTitle then f:SetTitle("CueTheCashier") end
  if f.SetPortraitToAsset then f:SetPortraitToAsset(CM.ICON) end
  CM.CloseOnEscape(f) -- Escape closes it (see Core.lua; never UISpecialFrames)
  f.Tabs, f.tabPool = {}, {}
  f:SetScript("OnHide", function()
    local t = current and MW.tabs[current]
    if t and t.hide and t.page then CM.Try("Main window " .. t.key, t.hide, t.page) end
  end)
  f:Hide()
end

-- (Re)makes the bottom tabs from the registry. Tab buttons are reused.
function MW:BuildTabs()
  local list = Sorted(self.tabs)
  local pool = frame.tabPool
  for _, b in ipairs(pool) do b:Hide() end
  wipe(frame.Tabs)
  for i, t in ipairs(list) do
    local b = pool[i]
    if not b then
      b = CreateFrame("Button", "CueTheCashierMainFrameTab" .. i, frame, "PanelTabButtonTemplate")
      b:SetID(i)
      if i == 1 then b:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 19, 2)
      else b:SetPoint("LEFT", pool[i - 1], "RIGHT", 3, 0) end
      pool[i] = b
    end
    frame.Tabs[i] = b
    b:SetText(t.title)
    b.key = t.key
    b:SetScript("OnClick", function(btn) MW:Select(btn.key) end)
    b:Show()
  end
  -- frame.Tabs holds only the tabs in use: Blizzard's PanelTemplates count it.
  if PanelTemplates_SetNumTabs then PanelTemplates_SetNumTabs(frame, #list) end
  self:MarkTab()
end

function MW:MarkTab()
  for i, b in ipairs(frame.Tabs) do
    if b.key == current and PanelTemplates_SetTab then PanelTemplates_SetTab(frame, i) end
  end
end

function MW:Select(key)
  local t = key and self.tabs[key]
  if not t then t = Sorted(self.tabs)[1] end
  if not t then return end
  local old = current and self.tabs[current]
  if old and old ~= t and old.page then
    if old.hide then CM.Try("Main window " .. old.key, old.hide, old.page) end
    old.page:Hide()
  end
  current = t.key
  CM.Settings().mainTab = t.key
  if not t.page then
    t.page = CreateFrame("Frame", nil, frame)
    t.page:SetAllPoints(frame)
    if t.build then CM.Try("Main window " .. t.key, t.build, t.page) end
  end
  t.page:Show()
  if t.show then CM.Try("Main window " .. t.key, t.show, t.page) end
  self:MarkTab()
end

-- Shows the window, on tab `key` (or the tab used last).
function MW:Show(key)
  if not frame then Build() end
  -- Load-on-demand modules with CM_MAIN_WINDOW_SHOW in their .toc load
  -- now and add their tabs before the tab row is made.
  CM.SendMessage("CM_MAIN_WINDOW_SHOW")
  self:BuildTabs()
  frame:Show()
  self:Select(key or current or CM.Settings().mainTab or "overview")
end

-- Closes the window, or opens it. With a key: closes it only when that tab
-- is the one showing, otherwise switches to it.
function MW:Toggle(key)
  if frame and frame:IsShown() and (not key or key == current) then
    frame:Hide()
  else
    self:Show(key)
  end
end

-- Redraws the tab showing (after data changed).
function MW:Refresh()
  if not (frame and frame:IsShown() and current) then return end
  local t = self.tabs[current]
  if t and t.page and t.show then CM.Try("Main window " .. t.key, t.show, t.page) end
end

function MW:IsShown() return frame and frame:IsShown() or false end
function MW:Current() return current end

-- Another profile: everything on screen may differ.
CM.RegisterMessage(MW, "CM_PROFILE_CHANGED", function()
  if frame and frame:IsShown() then MW:Refresh() end
end)
