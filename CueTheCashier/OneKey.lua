-- CueTheCashier: the one-key macro.
--
-- One key does the next step each time you press it, so you can post,
-- cancel, buy and disenchant by pressing (or scrolling) the same key over
-- and over. Every press is a real key press, which Blizzard needs for each
-- post, cancel, buy and spell.
--
-- Make the macro with /cmp macro (a character macro "CueTheCashier" with
-- "/click CueTheCashierOneKeyButton") and put it on your bars or a key.
-- Settings > Auction house > One-key scroll wheel: hold Ctrl, Alt or Shift
-- and scroll to press it (account wide; /cmp macro wheel toggles Alt).
--
-- What a press does, first match wins:
--   1. A CueTheCashier confirm box is open (buy, post, cancel): Accept it.
--   2. Steps added by modules (CM.OneKey.AddStep): the Post tab posts or
--      cancels its next line; a deal tab buys the selected item; the
--      Destroy list disenchants its top item.
-- In combat the key does nothing (Blizzard locks the button then).
-- Copyright (C) 2026 Kim. Licensed under the GNU GPL v3 or later; see LICENSE.
local _, CM = ...
local API = CM.API

local K = {}
CM.OneKey = K

K.BUTTON = "CueTheCashierOneKeyButton"
K.MACRO = "CueTheCashier"
K.OLD_MACRO = "CraftMarket" -- name before 0.38; renamed on the next /cmp macro
local steps = {} -- { { owner, fn }, ... }

-- fn() returns nil (nothing to do) or label, action. action is a function
-- (run right away during the key press) or { macro = "/cast ..." } for
-- spells, which the secure button runs.
function K.AddStep(owner, fn)
  steps[#steps + 1] = { owner = owner, fn = fn }
end

local function VisiblePopup()
  if not StaticPopup_FindVisible then return nil end
  return StaticPopup_FindVisible("CRAFTMARKET_CONFIRM")
end

local function AcceptPopup(dialog)
  if StaticPopup_OnClick then
    StaticPopup_OnClick(dialog, 1)
    return
  end
  local b = (dialog.GetButton1 and dialog:GetButton1()) or dialog.button1
  if b then b:Click() end
end

-- label, action of the next step, or nil.
function K.Next()
  local dialog = VisiblePopup()
  if dialog then return "Accept", function() AcceptPopup(dialog) end end
  for _, s in ipairs(steps) do
    local ok, label, action = pcall(s.fn)
    if ok and label then return label, action end
    if not ok then CM.Debug("One key step error: " .. tostring(label)) end
  end
end

local function PreClick(self)
  if InCombatLockdown() then return end
  local label, action = K.Next()
  self:SetAttribute("type", nil)
  self:SetAttribute("macrotext", nil)
  if not label then
    CM.Debug("One key: nothing to do.")
    return
  end
  CM.Debug("One key: " .. label)
  if type(action) == "table" and action.macro then
    self:SetAttribute("type", "macro")
    self:SetAttribute("macrotext", action.macro)
  elseif type(action) == "function" then
    action()
  end
end

function K.Button()
  if K.button then return K.button end
  local b = CreateFrame("Button", K.BUTTON, UIParent, "SecureActionButtonTemplate")
  b:SetSize(1, 1)
  b:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10, 10) -- off screen; used through /click
  b:RegisterForClicks("AnyUp", "AnyDown")
  b:SetScript("PreClick", PreClick)
  K.button = b
  return b
end

-- Makes (or refreshes) the character macro.
function K.MakeMacro()
  if InCombatLockdown() then CM.Print("Not in combat.") return end
  local body = "/click " .. K.BUTTON
  local index = GetMacroIndexByName and GetMacroIndexByName(K.MACRO) or 0
  if (not index or index == 0) and GetMacroIndexByName then
    index = GetMacroIndexByName(K.OLD_MACRO) or 0
  end
  if index and index > 0 then
    EditMacro(index, K.MACRO, nil, body)
    CM.Print("The CueTheCashier macro is up to date. Put it on a bar or bind a key to it.")
    return
  end
  local ok, err = pcall(CreateMacro, K.MACRO, "INV_MISC_QUESTIONMARK", body, true)
  if ok then
    CM.Print("Made the character macro \"CueTheCashier\" (Escape > Macros). Put it on a bar or bind a key to it; each press does the next step.")
  else
    CM.Print("Couldn't make the macro (" .. tostring(err) .. "). Make one yourself with: " .. body)
  end
end

-- Modifier + mouse wheel presses the button: "CTRL", "ALT", "SHIFT" or "off".
local MODIFIERS = { CTRL = true, ALT = true, SHIFT = true }

function K.WheelModifier()
  local v = CM.Settings().oneKeyWheel
  if v == true then return "ALT" end -- 0.35.0 saved true for Alt
  return MODIFIERS[v] and v or "off"
end

function K.ApplyWheel()
  if not SetOverrideBindingClick then return end
  if InCombatLockdown() then K.wheelPending = true return end
  local b = K.Button()
  ClearOverrideBindings(b)
  local mod = K.WheelModifier()
  if mod ~= "off" then
    SetOverrideBindingClick(b, true, mod .. "-MOUSEWHEELUP", K.BUTTON)
    SetOverrideBindingClick(b, true, mod .. "-MOUSEWHEELDOWN", K.BUTTON)
  end
end

function K.SetWheelModifier(v)
  CM.Settings().oneKeyWheel = MODIFIERS[v] and v or nil
  K.ApplyWheel()
end

CM.RegisterEvent(K, "PLAYER_REGEN_ENABLED", function()
  if K.wheelPending then K.wheelPending = nil; K.ApplyWheel() end
end)

-- 0.41.0 renamed our buttons from CraftMarket... to CueTheCashier...
-- Macros that click the old names (the one-key macro, a Destroy macro)
-- are updated once, out of combat.
function K.FixOldMacros()
  if InCombatLockdown() or not (GetNumMacros and GetMacroInfo and EditMacro) then return 0 end
  local account, char = GetNumMacros()
  local slots = {}
  for i = 1, account or 0 do slots[#slots + 1] = i end
  for i = 1, char or 0 do slots[#slots + 1] = (MAX_ACCOUNT_MACROS or 120) + i end
  local fixed = 0
  for _, i in ipairs(slots) do
    local name, _, body = GetMacroInfo(i)
    if body and body:find("/click CraftMarket", 1, true) then
      local newBody = body:gsub("/click CraftMarket", "/click CueTheCashier")
      local newName = name == K.OLD_MACRO and K.MACRO or name
      if pcall(EditMacro, i, newName, nil, newBody) then fixed = fixed + 1 end
    end
  end
  if fixed > 0 then CM.Print(("Updated %d macro(s) to the new button names."):format(fixed)) end
  return fixed
end

CM.RegisterEvent(K, "PLAYER_LOGIN", function()
  K.Button()
  K.ApplyWheel()
  CM.Try("Old macros", K.FixOldMacros)
end)

API.AddOneKeyStep = K.AddStep -- (owner, fn) fn() -> label, function | { macro = text } (minor 9)
API.GetOneKeyNext = function() return (K.Next()) end -- () -> label | nil (minor 9)
