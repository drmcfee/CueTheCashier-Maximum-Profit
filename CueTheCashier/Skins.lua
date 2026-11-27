-- CueTheCashier: skin registry.
-- Every frame CueTheCashier builds asks this file for its look, so a skin
-- can restyle the whole addon without touching the logic files.
-- To make a skin: in your own small addon (or any file loaded after
-- CueTheCashier), call CueTheCashier.Skins:Register("Name", { ... }) with only
-- the fields you want to change; everything else comes from the Blizzard
-- skin below. SkinDark.lua is a complete example, and SKINS.md explains
-- every field. Pick a skin in Settings > General > Skin (or /cmp skin).
-- Copyright (C) 2026 Kim. Licensed under the GNU GPL v3 or later; see LICENSE.
local _, CM = ...

local Skins = { registry = {} }
CM.Skins = Skins

-- Default: the stock WoW look, built only from Blizzard templates and fonts.
Skins.registry.Blizzard = {
  buttonTemplate = "UIPanelButtonTemplate",
  -- Small windows (Crafting List, Task List, debug log, Destroy, questions).
  -- Since 0.42.1 the same frame as the auction house and main window, without
  -- the portrait, so the whole addon has one look (Kim). Their lists sit on
  -- an inset like the auction house's.
  windowTemplate = "PortraitFrameTemplate",
  -- GUESS: Blizzard's auction house window is built on PortraitFrameTemplate.
  craftTradeTemplate = "PortraitFrameTemplate",
  -- The CueTheCashier main window (/cmp, minimap button).
  mainWindowTemplate = "PortraitFrameTemplate",
  insetTemplate = "InsetFrameTemplate",
  checkTemplate = "UICheckButtonTemplate",
  inputTemplate = "InputBoxTemplate",
  fontLog = "ChatFontNormal",
  -- Text inputs: text starts this far in from the box edge, left aligned.
  inputMargin = 2,
  fontNormal = "GameFontNormal",
  fontSmall = "GameFontHighlightSmall",
  fontStatus = "GameFontNormalSmall",
  -- Buttons that sit in a window's title bar next to the X (the Craft
  -- Trade switch). Same red button as Blizzard's, but its silver border is
  -- tinted gold to match the X. The tint multiplies the button's colours:
  -- grey turns gold while the red fill stays red. Lower numbers = darker.
  -- Sizes are in UI units; at your screen scale 1 unit is about 1.8 pixels.
  titleButton = {
    tint = { 1.0, 0.86, 0.35 },
    gap = 2,          -- space between it and the X
    -- Tune these live in game with /cmp button (see /cmp for help).
    extraHeight = 1,  -- this much taller than the X
    raise = 3,        -- moved this much up compared to the X
  },
  progressBar = {
    texture = "Interface\\TargetingFrame\\UI-StatusBar",
    color = { 0.0, 0.65, 0.0 },
    background = { 0, 0, 0, 0.5 },
  },
  -- Colours (r, g, b, a from 0 to 1) used by every list and chart.
  colors = {
    stripe = { 1, 1, 1, 0.03 },     -- every second row of a list
    highlight = { 1, 1, 1, 0.06 },  -- the row under the mouse
    selected = { 1, 0.82, 0, 0.15 },-- the row you clicked
    chartBar = { 1, 0.82, 0, 0.8 }, -- bars on the Gold tab
  },
  -- Extra look for CueTheCashier's own windows (main window, Craft Trade,
  -- lists, debug log). background = a colour laid over the window's own
  -- background; nil keeps Blizzard's.
  window = { background = nil },
}

-- Builds a title-bar button: Blizzard's standard red button with its
-- border tinted (see titleButton above).
function Skins:CreateTitleButton(parent, name)
  local skin = self:Get()
  local b = CreateFrame("Button", name, parent, skin.buttonTemplate)
  local tint = skin.titleButton.tint
  local highlight = b:GetHighlightTexture()
  local function Tint()
    for _, region in ipairs({ b:GetRegions() }) do
      if region ~= highlight and region.SetVertexColor and region:GetObjectType() == "Texture" then
        region:SetVertexColor(tint[1], tint[2], tint[3])
      end
    end
  end
  Tint()
  -- Blizzard swaps the button art when pressed/released; re-apply the tint.
  b:HookScript("OnMouseDown", Tint)
  b:HookScript("OnMouseUp", Tint)
  b:HookScript("OnEnable", Tint)
  b:HookScript("OnDisable", Tint)
  return b
end

-- Gives a text input the skin's standard look: left aligned text with a
-- small margin inside the box.
function Skins:StyleInput(editBox)
  local m = self:Get().inputMargin
  editBox:SetJustifyH("LEFT")
  editBox:SetTextInsets(m, m, 0, 0)
end

function Skins:Register(name, skin)
  assert(type(name) == "string" and type(skin) == "table", "Skins:Register(name, table)")
  -- Missing fields fall back to the Blizzard skin, also inside the tables.
  local base = self.registry.Blizzard
  for key, value in pairs(base) do
    if type(value) == "table" and type(skin[key]) == "table" then
      setmetatable(skin[key], { __index = value })
    end
  end
  setmetatable(skin, { __index = base })
  self.registry[name] = skin
end

-- A colour from the skin on a texture: Skins:Paint(texture, "highlight").
function Skins:Paint(texture, key)
  local c = self:Get().colors[key] or self.registry.Blizzard.colors[key]
  if c then texture:SetColorTexture(c[1], c[2], c[3], c[4] or 1) end
end

-- Row backgrounds: the stripe colour on every second row, clear otherwise.
function Skins:Stripe(texture, index)
  local c = self:Get().colors.stripe
  texture:SetColorTexture(c[1], c[2], c[3], (index and index % 2 == 0) and (c[4] or 1) or 0)
end

-- Title (and portrait) of one of our small windows. The portrait is hidden
-- when the game can do that; if not, it shows our icon and the content
-- starts lower. Returns how far down the content starts.
function Skins:SetupWindow(frame, title)
  if frame.SetTitle then
    frame:SetTitle(title)
  else
    local t = frame:CreateFontString(nil, "OVERLAY", self:Get().fontNormal)
    t:SetPoint("TOP", 0, -5)
    t:SetText(title)
    frame.cmTitle = t
  end
  local top = 30
  if frame.PortraitContainer or frame.portrait or frame.SetPortraitToAsset then
    local hidden = ButtonFrameTemplate_HidePortrait and pcall(ButtonFrameTemplate_HidePortrait, frame)
    if not hidden then
      if frame.SetPortraitToAsset then pcall(frame.SetPortraitToAsset, frame, CM.ICON) end
      top = 62
    end
  end
  frame.contentTop = top
  return top
end

-- A dark inset behind a list, like the auction house's (skin.insetTemplate).
function Skins:AddInset(parent, left, top, right, bottom)
  local tpl = self:Get().insetTemplate
  local ok, inset = pcall(CreateFrame, "Frame", nil, parent, tpl)
  if not ok then return nil end
  inset:SetPoint("TOPLEFT", left, -top)
  inset:SetPoint("BOTTOMRIGHT", -right, bottom)
  inset:SetFrameLevel(math.max(0, parent:GetFrameLevel() + 1))
  return inset
end

-- Gives one of CueTheCashier's windows the skin's window look.
function Skins:ApplyWindow(frame)
  local bg = self:Get().window and self:Get().window.background
  if not bg then return end
  if not frame.cmSkinBackground then
    local t = frame:CreateTexture(nil, "BACKGROUND", nil, 7)
    t:SetPoint("TOPLEFT", 3, -22)
    t:SetPoint("BOTTOMRIGHT", -3, 3)
    frame.cmSkinBackground = t
  end
  frame.cmSkinBackground:SetColorTexture(bg[1], bg[2], bg[3], bg[4] or 1)
end

function Skins:List()
  local names = {}
  for name in pairs(self.registry) do names[#names + 1] = name end
  table.sort(names)
  return names
end

function Skins:Set(name)
  if not self.registry[name] then return false end
  CueTheCashierDB.settings.skin = name
  return true
end

function Skins:Get()
  local name = CueTheCashierDB and CueTheCashierDB.settings and CueTheCashierDB.settings.skin
  return self.registry[name] or self.registry.Blizzard
end
