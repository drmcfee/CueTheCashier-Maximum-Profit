-- CueTheCashier: scan buttons and status line, shown inside the Craft Trade
-- window (CraftTradeUI.lua calls ns.BuildScanBar when it builds the window).
-- Copyright (C) 2026 Kim. Licensed under the GNU GPL v3 or later; see LICENSE.
local _, ns = ...
local CM = CueTheCashier
local API = CM.API

local ui

function ns.BuildScanBar(parent)
  if ui then return ui end
  local skin = CM.Skins:Get()

  ui = CreateFrame("Frame", "CueTheCashierAuctionBar", parent)
  ui:SetSize(360, 24)
  -- Top right, just under the title bar.
  ui:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -12, -30)

  local button = CreateFrame("Button", "CueTheCashierScanButton", ui, skin.buttonTemplate)
  button:SetSize(110, 22)
  button:SetPoint("RIGHT")
  button:SetText("Full Scan")
  button:SetScript("OnClick", function() ns.Scanner:Start() end)
  button:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:SetText("CueTheCashier Full Scan")
    GameTooltip:AddLine("Reads every auction and saves the lowest buyout per item.", 1, 1, 1, true)
    GameTooltip:AddLine("Blizzard allows one full scan every 15 minutes.", nil, nil, nil, true)
    GameTooltip:Show()
  end)
  button:SetScript("OnLeave", GameTooltip_Hide)
  ui.button = button

  -- The Test Scan button (debug, one item) is gone since 0.42.0: full
  -- scans work. /cmp test [item] still runs it from chat.
  local function LeftAnchor() return button end

  local bar = CreateFrame("StatusBar", nil, ui)
  bar:SetSize(120, 12)
  bar:SetStatusBarTexture(skin.progressBar.texture)
  bar:SetStatusBarColor(unpack(skin.progressBar.color))
  bar:SetMinMaxValues(0, 1)
  local bg = bar:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(unpack(skin.progressBar.background))
  bar:Hide()
  ui.bar = bar

  local status = ui:CreateFontString(nil, "OVERLAY", skin.fontStatus)
  status:SetJustifyH("RIGHT")
  ui.status = status

  function ns.UpdateDebugButton()
    bar:ClearAllPoints(); bar:SetPoint("RIGHT", LeftAnchor(), "LEFT", -8, 0)
    status:ClearAllPoints(); status:SetPoint("RIGHT", LeftAnchor(), "LEFT", -8, 0)
  end
  ns.UpdateDebugButton()

  local function Refresh(state, progress)
    if state == "waiting" then
      button:Disable(); bar:Hide(); status:Show()
      status:SetText("Waiting for server...")
    elseif state == "processing" then
      button:Disable(); status:Hide(); bar:Show(); bar:SetValue(progress)
    else
      bar:Hide(); status:Show()
      local cd = API.GetFullScanCooldown()
      button:SetEnabled(cd <= 0)
      local last = API.GetLastScanTime()
      local lastText = last > 0 and date("%H:%M", last) or "never"
      if cd > 0 then
        status:SetText(("Last scan %s, next in %s"):format(lastText, CM.FullScanCooldownText()))
      else
        status:SetText("Last scan " .. lastText)
      end
    end
  end
  ns.Scanner:OnChange(Refresh)

  -- Tick the cooldown text once a second while the window is open.
  local elapsed = 0
  ui:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + dt
    if elapsed >= 1 then
      elapsed = 0
      if ns.Scanner.state == "idle" then Refresh("idle", 0) end
    end
  end)
  Refresh("idle", 0)
  return ui
end
