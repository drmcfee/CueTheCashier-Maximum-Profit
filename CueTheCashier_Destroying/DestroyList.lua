-- CueTheCashier Destroying: the Destroy list (/cmp destroy).
--
-- Lists the items in your bags you can disenchant (uncommon and rare
-- armor and weapons; epics are left out so nothing valuable goes by
-- mistake), with what disenchanting and the auction house would give.
-- One button disenchants the top item: every click is one hardware press
-- and one item, as Blizzard requires. The button is a secure action button
-- running "/cast Disenchant" + "/use <bag> <slot>", so it can't change in
-- combat; the window closes when combat starts.
-- Right-click a row to ignore that item (Shift+right-click on the list
-- title brings ignored items back).
-- Forever has no Prospecting or Milling (classic era professions), so
-- disenchanting is the only kind of destroying for now.
-- Saved: CueTheCashierDestroyingDB.ignore = { [itemID] = true }
-- Copyright (C) 2026 Kim. Licensed under the GNU GPL v3 or later; see LICENSE.
local _, ns = ...
local CM = CueTheCashier
local API = CM.API

local D = {}
ns.DestroyList = D

local ROWS = 12
local ROW_HEIGHT = 20
local QUALITIES = { [2] = true, [3] = true } -- uncommon, rare

local function Ignored()
  ns.db.ignore = ns.db.ignore or {}
  return ns.db.ignore
end

local function SpellName()
  local id = API.DISENCHANT_SPELL
  if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
  if GetSpellInfo then return (GetSpellInfo(id)) end
end

local function LastBag() return NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4 end

-- { { bag, slot, itemID, link, name, quality, value, market }, ... } best value first.
function D.Scan()
  local list, ignore = {}, Ignored()
  for bag = 0, LastBag() do
    for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      local id = info and info.itemID
      if id and not ignore[id] and not info.isLocked then
        local quality = API.GetDisenchantInfo(id)
        if QUALITIES[quality] then
          local value = API.GetDisenchantValue(id)
          list[#list + 1] = {
            bag = bag, slot = slot, itemID = id, link = info.hyperlink, quality = quality,
            name = C_Item.GetItemInfo(id) or ("Item " .. id),
            value = type(value) == "number" and value or nil,
            market = API.GetPrice(id, "auction.market"),
          }
        end
      end
    end
  end
  table.sort(list, function(a, b)
    if (a.value or 0) ~= (b.value or 0) then return (a.value or 0) > (b.value or 0) end
    return a.name < b.name
  end)
  return list
end

-- Points the secure button at the top item (out of combat only).
function D.Aim()
  local b = D.button
  if not b or InCombatLockdown() then return end
  local top = D.list and D.list[1]
  local spell = SpellName()
  if top and spell and API.IsEnchanter() then
    b:SetAttribute("type", "macro")
    b:SetAttribute("macrotext", ("/cast %s\n/use %d %d"):format(spell, top.bag, top.slot))
    b:SetText(("Disenchant (%d)"):format(#D.list))
    b:Enable()
  else
    b:SetAttribute("type", nil)
    b:SetAttribute("macrotext", nil)
    b:SetText("Disenchant (0)")
    b:Disable()
  end
end

function D.Refresh()
  local f = D.frame
  if not (f and f:IsShown()) then return end
  D.list = D.Scan()
  for i = 1, ROWS do
    local row, e = f.rows[i], D.list[i]
    row.entry = e
    if e then
      local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[e.quality]
      row.name:SetText(e.name)
      if c then row.name:SetTextColor(c.r, c.g, c.b) end
      row.value:SetText(e.value and CM.FormatMoney(e.value) or "?")
      row.market:SetText(e.market and CM.FormatMoney(e.market) or "")
      row:Show()
    else
      row:Hide()
    end
  end
  local more = #D.list - ROWS
  if not API.IsEnchanter() then
    f.info:SetText("This character doesn't know Enchanting.")
  elseif #D.list == 0 then
    f.info:SetText("Nothing to disenchant in your bags.")
  else
    f.info:SetText(more > 0 and ("and %d more"):format(more) or "")
  end
  D.Aim()
end

local function MakeRow(f, i)
  local row = CreateFrame("Button", nil, f)
  row:SetSize(360, ROW_HEIGHT)
  row:SetPoint("TOPLEFT", 14, -52 - (f.dy or 0) - (i - 1) * ROW_HEIGHT)
  row.bg = row:CreateTexture(nil, "BACKGROUND")
  row.bg:SetAllPoints()
  CM.Skins:Stripe(row.bg, i)
  row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  local hl = row:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  CM.Skins:Paint(hl, "highlight")
  row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  row.name:SetPoint("LEFT", 4, 0)
  row.name:SetWidth(170)
  row.name:SetJustifyH("LEFT")
  row.name:SetWordWrap(false)
  row.value = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  row.value:SetPoint("LEFT", 176, 0)
  row.value:SetWidth(90)
  row.value:SetJustifyH("RIGHT")
  row.market = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  row.market:SetPoint("LEFT", 268, 0)
  row.market:SetWidth(90)
  row.market:SetJustifyH("RIGHT")
  row:SetScript("OnEnter", function(r)
    if r.entry then CM.ShowItemTooltip(r, r.entry.link or ("item:" .. r.entry.itemID)) end
  end)
  row:SetScript("OnLeave", GameTooltip_Hide)
  row:SetScript("OnClick", function(r, button)
    if button == "RightButton" and r.entry then
      Ignored()[r.entry.itemID] = true
      CM.Print(r.entry.name .. " won't be listed for disenchanting any more.")
      D.Refresh()
    end
  end)
  return row
end

function D.Build()
  local skin = CM.Skins:Get()
  local f = CreateFrame("Frame", "CueTheCashierDestroyFrame", UIParent, skin.windowTemplate)
  CM.Skins:ApplyWindow(f)
  f:SetSize(390, 52 + ROWS * ROW_HEIGHT + 64)
  f:SetPoint("CENTER", 200, 0)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:SetFrameStrata("DIALOG")
  f:Hide()
  f:SetClampedToScreen(true)
  CM.CloseOnEscape(f)
  f.dy = CM.Skins:SetupWindow(f, "CueTheCashier Destroy") - 30
  f:SetHeight(f:GetHeight() + f.dy)
  CM.Skins:AddInset(f, 8, 48 + f.dy, 8, 62)
  local function Header(text, x, w, justify)
    local h = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    h:SetPoint("TOPLEFT", x, -34 - f.dy)
    h:SetWidth(w)
    h:SetJustifyH(justify)
    h:SetText(text)
    return h
  end
  local title = Header("Item", 18, 170, "LEFT")
  Header("Disenchant", 190, 90, "RIGHT")
  Header("Market value", 282, 90, "RIGHT")
  -- Shift+right-click the Item header: list ignored items again.
  local reset = CreateFrame("Button", nil, f)
  reset:SetAllPoints(title)
  reset:RegisterForClicks("RightButtonUp")
  reset:SetScript("OnClick", function()
    if IsShiftKeyDown() then wipe(Ignored()); CM.Print("Ignored items are listed again."); D.Refresh() end
  end)
  f.rows = {}
  for i = 1, ROWS do f.rows[i] = MakeRow(f, i) end
  f.info = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  f.info:SetPoint("TOPLEFT", 18, -56 - f.dy - ROWS * ROW_HEIGHT)
  f.info:SetWidth(350)
  f.info:SetJustifyH("LEFT")

  local b = CreateFrame("Button", "CueTheCashierDestroyButton", f, "SecureActionButtonTemplate," .. skin.buttonTemplate)
  b:SetSize(180, 24)
  b:SetPoint("BOTTOM", 0, 12)
  b:RegisterForClicks("AnyUp", "AnyDown")
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Disenchant the top item")
    GameTooltip:AddLine("One click, one item. You can bind a key to it: /click CueTheCashierDestroyButton", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", GameTooltip_Hide)
  D.button = b

  f:RegisterEvent("BAG_UPDATE_DELAYED")
  f:RegisterEvent("PLAYER_REGEN_DISABLED")
  f:RegisterEvent("GET_ITEM_INFO_RECEIVED")
  f:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then f:Hide() else D.Refresh() end
  end)
  f:SetScript("OnShow", D.Refresh)
  D.frame = f
  return f
end

function D.Toggle()
  if InCombatLockdown() then CM.Print("The Destroy list can't open in combat.") return end
  local f = D.frame or D.Build()
  f:SetShown(not f:IsShown())
end

-- Chat report for /cmp destroy list.
function D.Report()
  local list = D.Scan()
  CM.Print(("%d items to disenchant in your bags."):format(#list))
  for i, e in ipairs(list) do
    if i > 10 then break end
    CM.Print(("  %s: disenchant %s, market %s"):format(e.name, e.value and CM.FormatMoney(e.value) or "?",
      e.market and CM.FormatMoney(e.market) or "-"))
  end
end

-- The one-key macro (CueTheCashier\OneKey.lua): while the Destroy list is
-- open, a press disenchants its top item.
if CM.OneKey then
  CM.OneKey.AddStep(D, function()
    if not (D.frame and D.frame:IsShown() and D.button and D.button:IsEnabled()) then return end
    local macro = D.button:GetAttribute("macrotext")
    local top = D.list and D.list[1]
    if macro and top then return "Disenchant " .. top.name, { macro = macro } end
  end)
end
