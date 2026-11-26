-- CueTheCashier: small UI pieces shared by the core and every module.
-- (Fonts, templates and colours come from the skin, see Skins.lua.)
-- Copyright (C) 2026 Kim. Licensed under the GNU GPL v3 or later; see LICENSE.
local _, CM = ...

-- Yes/no popup in Blizzard's style. Purchases must be made from its
-- Accept (Forever blocks them from addon buttons, confirmed in 0.10.8).
-- Never assign the StaticPopupDialogs global itself (not even "X = X or {}"):
-- that taints it, and Blizzard's own popups and Escape handling read it.
StaticPopupDialogs.CRAFTMARKET_CONFIRM = {
  text = "%s",
  button1 = ACCEPT or "Accept",
  button2 = CANCEL or "Cancel",
  OnAccept = function(_, data) data.accept() end,
  OnCancel = function(_, data) if data.cancel then data.cancel() end end,
  timeout = 0, whileDead = true, hideOnEscape = true,
}

-- Asks a yes/no question. onAccept runs on Accept, onCancel (optional) on
-- Cancel or Escape.
function CM.Confirm(text, onAccept, onCancel)
  StaticPopup_Show("CRAFTMARKET_CONFIRM", text, nil, { accept = onAccept, cancel = onCancel })
end

-- Shows the normal item tooltip (with comparison when Blizzard shows one).
-- what = an item link, or an itemKey from the auction house.
function CM.ShowItemTooltip(owner, what)
  if not what then return end
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  if type(what) == "string" then
    GameTooltip:SetHyperlink(what)
  elseif GameTooltip.SetItemKey and type(what.itemLevel) == "number"
      and type(what.itemSuffix) == "number" then
    -- SetItemKey needs a full itemKey. Blizzard reports a usage error even
    -- inside pcall, so only call it when every field is there.
    GameTooltip:SetItemKey(what.itemID, what.itemLevel, what.itemSuffix)
  elseif what.itemID then
    GameTooltip:SetItemByID(what.itemID)
  end
  GameTooltip:Show()
end

-- A question with up to three answers, in a small window of our own (no
-- new StaticPopupDialogs entry; Kim's rule). Not for purchases: those need
-- Blizzard's popup (CM.Confirm).
--   CM.Choose("Text", { { "None", fn }, { "10", fn }, { "All 20", fn } })
-- Escape or the X picks nothing.
local chooser
function CM.Choose(text, answers)
  local skin = CM.Skins:Get()
  if not chooser then
    local f = CreateFrame("Frame", "CueTheCashierChooseFrame", UIParent, skin.windowTemplate)
    CM.Skins:ApplyWindow(f)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetPoint("TOP", 0, -160)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    local top = CM.Skins:SetupWindow(f, "CueTheCashier")
    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.text:SetPoint("TOPLEFT", 16, -(top + 4))
    f.text:SetPoint("TOPRIGHT", -16, -(top + 4))
    f.text:SetJustifyH("LEFT")
    f.text:SetSpacing(2)
    f.buttons = {}
    for i = 1, 3 do
      local b = CreateFrame("Button", nil, f, skin.buttonTemplate)
      b:SetSize(120, 22)
      f.buttons[i] = b
    end
    CM.CloseOnEscape(f)
    chooser = f
  end
  local f = chooser
  f:SetWidth(420)
  f.text:SetText(text)
  local n = math.min(#answers, 3)
  for i, b in ipairs(f.buttons) do
    local a = answers[i]
    b:ClearAllPoints()
    if a and i <= n then
      b:SetText(a[1])
      b:SetWidth(math.max(90, (b:GetFontString() and b:GetFontString():GetStringWidth() or 60) + 30))
      b:SetScript("OnClick", function() f:Hide(); a[2]() end)
      b:Show()
    else
      b:Hide()
    end
  end
  -- Buttons in a row, centred, under the text.
  local width = 0
  for i = 1, n do width = width + f.buttons[i]:GetWidth() + (i > 1 and 8 or 0) end
  local x = -width / 2
  for i = 1, n do
    local b = f.buttons[i]
    b:SetPoint("BOTTOMLEFT", f, "BOTTOM", x, 14)
    x = x + b:GetWidth() + 8
  end
  f:SetHeight((f.contentTop or 30) + 4 + (f.text:GetStringHeight() or 40) + 52)
  f:Show()
  f:Raise()
end

-- New rows for a list (a Blizzard ScrollBox) without jumping back to the
-- top (Kim, 0.42.4: no list should jump when you click in it). Every list
-- in the addon goes through here. keepScroll = false starts at the top
-- (e.g. another group picked).
function CM.SetRows(box, rows, keepScroll)
  local dp = CreateDataProvider(rows)
  local retain = keepScroll ~= false and ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition
  if retain then box:SetDataProvider(dp, retain) else box:SetDataProvider(dp) end
end
