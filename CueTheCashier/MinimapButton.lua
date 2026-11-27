-- CueTheCashier: round minimap button in the default WoW style, with
-- the CueTheCashier cash register icon. Left-click opens the CueTheCashier main
-- window (MainWindow.lua), right-click the Task List. Modules add lines
-- to its tooltip through the CM_MINIMAP_TOOLTIP message. Drag it around
-- the edge of the minimap; the spot is saved.
-- /cmp minimap hides or shows it.
-- Copyright (C) 2026 Kim. Licensed under the GNU GPL v3 or later; see LICENSE.
local _, CM = ...

local ICON = CM.ICON_ROUND
local DEFAULT_ANGLE = 200 -- degrees, counter-clockwise from the right

local button

local function Place()
  local angle = math.rad(CueTheCashierDB.settings.minimapAngle or DEFAULT_ANGLE)
  local radius = (Minimap:GetWidth() / 2) + 5
  button:ClearAllPoints()
  button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function OnDragUpdate()
  local mx, my = Minimap:GetCenter()
  local scale = Minimap:GetEffectiveScale()
  local cx, cy = GetCursorPosition()
  cx, cy = cx / scale, cy / scale
  CueTheCashierDB.settings.minimapAngle = math.deg(math.atan2(cy - my, cx - mx)) % 360
  Place()
end

local function ShowTooltip(self)
  GameTooltip:SetOwner(self, "ANCHOR_LEFT")
  GameTooltip:AddLine("CueTheCashier")
  -- The Accounting module adds today's spent / received / profit here.
  CM.SendMessage("CM_MINIMAP_TOOLTIP", GameTooltip)
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine("Click: CueTheCashier window. Right-click: Task List. Drag to move.", 0.6, 0.6, 0.6)
  GameTooltip:Show()
end

local function Build()
  button = CreateFrame("Button", "CueTheCashierMinimapButton", Minimap)
  button:SetSize(31, 31)
  button:SetFrameStrata("MEDIUM")
  button:SetFrameLevel(8)
  button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  button:RegisterForDrag("LeftButton")
  button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

  local bg = button:CreateTexture(nil, "BACKGROUND")
  bg:SetSize(20, 20)
  bg:SetPoint("TOPLEFT", 7, -5)
  bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
  local icon = button:CreateTexture(nil, "ARTWORK")
  icon:SetSize(20, 20)
  icon:SetPoint("TOPLEFT", 7, -5)
  icon:SetTexture(ICON)
  button.icon = icon
  local border = button:CreateTexture(nil, "OVERLAY")
  border:SetSize(53, 53)
  border:SetPoint("TOPLEFT")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

  button:SetScript("OnClick", function(_, b)
    if b == "RightButton" then
      CM.RunCommand("prof", "tasks")
    else
      CM.Try("Main window", CM.MainWindow.Toggle, CM.MainWindow)
    end
  end)
  button:SetScript("OnDragStart", function(b) b:SetScript("OnUpdate", OnDragUpdate) end)
  button:SetScript("OnDragStop", function(b) b:SetScript("OnUpdate", nil) end)
  button:SetScript("OnEnter", ShowTooltip)
  button:SetScript("OnLeave", GameTooltip_Hide)
  -- Pressed look like Blizzard's minimap buttons.
  button:SetScript("OnMouseDown", function() icon:SetPoint("TOPLEFT", 8, -7) end)
  button:SetScript("OnMouseUp", function() icon:SetPoint("TOPLEFT", 7, -6) end)

  Place()
  button:SetShown(not CueTheCashierDB.settings.hideMinimapButton)
end

function CM.SetMinimapButtonShown(show)
  CueTheCashierDB.settings.hideMinimapButton = not show
  if button then button:SetShown(show and true or false) end
  CM.Print(show and "Minimap button shown." or "Minimap button hidden (/cmp minimap or /cmp settings shows it).")
end

function CM.ToggleMinimapButton()
  CM.SetMinimapButtonShown(CueTheCashierDB.settings.hideMinimapButton)
end

CM.RegisterEvent("MinimapButton", "PLAYER_LOGIN", function()
  if Minimap then CM.Try("Minimap button", Build) end
end)
