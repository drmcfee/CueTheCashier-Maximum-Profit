-- CueTheCashier: the Prices tab of the main window.
--   Top:   try a formula on an item.
--   Left:  custom prices (a formula saved under a name, usable in other
--          formulas and operations). Click one to edit; New / Save / Delete.
--   Right: every price source, with its short name and its value for the
--          item in the Item box.
-- Formulas are explained in Formulas.lua.
-- Copyright (C) 2026 Kim. Licensed under the GNU GPL v3 or later; see LICENSE.
local _, CM = ...
local API = CM.API
local F = CM.Formula

local ROW = 20
local TOP = -64
local LEFT_W = 340

local page
local state = { item = nil, picked = nil }

local function Skin() return CM.Skins:Get() end
local function Label(parent, text, font)
  local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontNormal")
  fs:SetText(text or "")
  fs:SetJustifyH("LEFT")
  return fs
end
local function Button(parent, text, width)
  local b = CreateFrame("Button", nil, parent, Skin().buttonTemplate)
  b:SetSize(width or 80, 22)
  b:SetText(text)
  return b
end
local function Input(parent, width)
  local e = CreateFrame("EditBox", nil, parent, Skin().inputTemplate)
  e:SetSize(width, 22)
  e:SetAutoFocus(false)
  CM.Skins:StyleInput(e)
  e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  return e
end
local function Money(v) return v and CM.FormatMoney(v) or "|cffaaaaaa-|r" end

local function List(parent, x, y, width, bottom, init)
  local inset = CreateFrame("Frame", nil, parent, Skin().insetTemplate)
  inset:SetPoint("TOPLEFT", x, y)
  inset:SetPoint("BOTTOMLEFT", x, bottom)
  inset:SetWidth(width)
  local box = CreateFrame("Frame", nil, parent, "WowScrollBoxList")
  local bar = CreateFrame("EventFrame", nil, parent, "MinimalScrollBar")
  local view = CreateScrollBoxListLinearView()
  view:SetElementInitializer("CueTheCashierResultRowTemplate", init)
  if view.SetElementExtent then view:SetElementExtent(ROW) end
  ScrollUtil.InitScrollBoxListWithScrollBar(box, bar, view)
  box:SetPoint("TOPLEFT", inset, "TOPLEFT", 4, -4)
  box:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -4, 4)
  bar:SetPoint("TOPLEFT", inset, "TOPRIGHT", 6, 0)
  bar:SetPoint("BOTTOMLEFT", inset, "BOTTOMRIGHT", 6, 0)
  return box
end

-- Three text cells across a row.
local function Cells(row, widths, fonts)
  if row.cells then return end
  row.cells = {}
  local x = 4
  for i, w in ipairs(widths) do
    local fs = Label(row, "", fonts[i] or "GameFontHighlight")
    fs:SetPoint("LEFT", x, 0)
    fs:SetWidth(w - 6)
    fs:SetWordWrap(false)
    if i == #widths then fs:SetJustifyH("RIGHT") end
    row.cells[i] = fs
    x = x + w
  end
  row.bg = row:CreateTexture(nil, "BACKGROUND")
  row.bg:SetAllPoints()
  local hl = row:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  CM.Skins:Paint(hl, "highlight")
end

local Refresh

-- ------------------------------------------------------------------
-- Rows
-- ------------------------------------------------------------------
local function InitCustomRow(row, d)
  if not row.cells then
    Cells(row, { 100, 150, 70 }, { "GameFontNormal", "GameFontHighlightSmall", "GameFontHighlightSmall" })
    row:SetScript("OnClick", function(r)
      state.picked = r.data.name
      page.nameBox:SetText(r.data.name)
      page.formulaBox:SetText(r.data.formula)
      Refresh()
    end)
  end
  row.data = d
  row.cells[1]:SetText(d.name)
  row.cells[2]:SetText(d.formula)
  row.cells[3]:SetText(state.item and Money(F.Custom(d.name, state.item)) or "")
  if d.name == state.picked then CM.Skins:Paint(row.bg, "selected")
  else CM.Skins:Stripe(row.bg, d.index) end
end

local function InitSourceRow(row, d)
  if not row.cells then
    Cells(row, { 150, 200, 76 }, { "GameFontNormal", "GameFontHighlight", "GameFontHighlightSmall" })
    row:SetScript("OnEnter", function(r)
      GameTooltip:SetOwner(r, "ANCHOR_RIGHT")
      GameTooltip:AddLine(r.data.key, 1, 1, 1)
      GameTooltip:AddLine(r.data.label, nil, nil, nil, true)
      if r.data.alias then GameTooltip:AddLine("Short name: " .. r.data.alias, 0.6, 0.6, 0.6) end
      if r.data.description then GameTooltip:AddLine(r.data.description, nil, nil, nil, true) end
      GameTooltip:Show()
    end)
    row:SetScript("OnLeave", GameTooltip_Hide)
  end
  row.data = d
  row.cells[1]:SetText(d.alias or d.key)
  row.cells[2]:SetText(d.label .. (d.alias and (" |cffaaaaaa(" .. d.key .. ")|r") or ""))
  local v = state.item and API.GetPrice(state.item, d.key)
  row.cells[3]:SetText(state.item and (API.FormatSourceValue(d.key, v) or Money(nil)) or "")
  CM.Skins:Stripe(row.bg, d.index)
end

-- ------------------------------------------------------------------
-- Refresh
-- ------------------------------------------------------------------
local function TryFormula()
  local text = page.tryBox:GetText()
  if text == "" then page.tryResult:SetText(""); return end
  local v, err = F.Evaluate(text, state.item or 0)
  if err then
    page.tryResult:SetText("|cffff4040" .. err .. "|r")
  elseif not state.item then
    page.tryResult:SetText("|cff00ff00OK.|r Put an item in the Item box to see its value.")
  else
    page.tryResult:SetText(v and ("= " .. CM.FormatMoney(v)) or "|cffaaaaaaNo value for this item.|r")
  end
end

Refresh = function()
  if not (page and page:IsVisible()) then return end
  local customs = F.Customs()
  for i, d in ipairs(customs) do d.index = i end
  CM.SetRows(page.customs, customs)
  page.noCustoms:SetShown(#customs == 0)

  local aliasOf = {}
  for alias, key in pairs(API.GetPriceAliases()) do aliasOf[key] = alias end
  local sources = API.GetPriceSources()
  for i, s in ipairs(sources) do s.index = i; s.alias = aliasOf[s.key] end
  CM.SetRows(page.sources, sources)
  page.deleteButton:SetEnabled(state.picked ~= nil)
  TryFormula()
end

-- ------------------------------------------------------------------
-- Build
-- ------------------------------------------------------------------
local function Build(p)
  page = p
  local h = Label(p, "Formulas: sources, 100g / 5s / 20c, 90%, + - * / ( ), min() max() avg() first().  " ..
    "Example: min(market, 7d) * 90%", "GameFontNormalSmall")
  h:SetPoint("TOPLEFT", 70, -38)
  h:SetPoint("RIGHT", p, "RIGHT", -20, 0)
  h:SetWordWrap(true)

  -- Try a formula on an item.
  local tryLabel = Label(p, "Try")
  tryLabel:SetPoint("TOPLEFT", 16, TOP - 4)
  p.tryBox = Input(p, 300)
  p.tryBox:SetPoint("LEFT", tryLabel, "RIGHT", 12, 0)
  p.tryBox:SetScript("OnTextChanged", function() if page then TryFormula() end end)
  local itemLabel = Label(p, "Item")
  itemLabel:SetPoint("LEFT", p.tryBox, "RIGHT", 16, 0)
  p.itemBox = Input(p, 130)
  p.itemBox:SetPoint("LEFT", itemLabel, "RIGHT", 12, 0)
  p.itemBox:SetScript("OnEditFocusLost", function(self)
    local text = self:GetText()
    state.item = text ~= "" and (CM.ParseItemID(text) or API.FindItemID(text)) or nil
    Refresh()
  end)
  p.itemBox:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Item", 1, 1, 1)
    GameTooltip:AddLine("An item ID or name, or shift-click an item. The lists then show its prices.",
      nil, nil, nil, true)
    GameTooltip:Show()
  end)
  p.itemBox:SetScript("OnLeave", GameTooltip_Hide)
  if HandleModifiedItemClick then
    hooksecurefunc("HandleModifiedItemClick", function(link)
      if not (p:IsVisible() and type(link) == "string" and IsShiftKeyDown()) then return end
      local id = CM.ParseItemID(link)
      if id then
        state.item = id
        p.itemBox:SetText((C_Item.GetItemInfo(id)) or tostring(id))
        Refresh()
      end
    end)
  end
  p.tryResult = Label(p, "", "GameFontHighlightSmall")
  p.tryResult:SetPoint("TOPLEFT", 16, TOP - 30)
  p.tryResult:SetPoint("RIGHT", p, "RIGHT", -20, 0)
  p.tryResult:SetWordWrap(false)

  -- Custom prices (left)
  local listTop = TOP - 66
  local ct = Label(p, "Custom prices", "GameFontNormalSmall")
  ct:SetPoint("TOPLEFT", 16, listTop + 14)
  p.customs = List(p, 12, listTop, LEFT_W, 104, InitCustomRow)
  p.noCustoms = Label(p, "None yet. Give a formula a name below\nto use it by that name.", "GameFontDisable")
  p.noCustoms:SetPoint("TOPLEFT", 30, listTop - 40)

  local nameLabel = Label(p, "Name")
  nameLabel:SetPoint("BOTTOMLEFT", 16, 78)
  p.nameBox = Input(p, 150)
  p.nameBox:SetPoint("LEFT", nameLabel, "RIGHT", 22, 0)
  local formulaLabel = Label(p, "Formula")
  formulaLabel:SetPoint("BOTTOMLEFT", 16, 50)
  p.formulaBox = Input(p, LEFT_W - 70)
  p.formulaBox:SetPoint("LEFT", formulaLabel, "RIGHT", 8, 0)

  local new = Button(p, "New", 70)
  new:SetPoint("BOTTOMLEFT", 12, 14)
  new:SetScript("OnClick", function()
    state.picked = nil
    p.nameBox:SetText("")
    p.formulaBox:SetText("")
    p.nameBox:SetFocus()
    Refresh()
  end)
  local save = Button(p, "Save", 70)
  save:SetPoint("LEFT", new, "RIGHT", 4, 0)
  save:SetScript("OnClick", function()
    local name, formula = p.nameBox:GetText(), p.formulaBox:GetText()
    local ok, err = F.SetCustom(name, formula)
    if not ok then
      p.tryResult:SetText("|cffff4040" .. tostring(err) .. "|r")
      return
    end
    local clean = F.CheckName(name)
    -- Saved under a new name: the old one goes (a rename).
    if state.picked and clean and state.picked ~= clean then F.DeleteCustom(state.picked) end
    state.picked = clean
    CM.Print(("Custom price \"%s\" saved."):format(clean or name))
    Refresh()
  end)
  p.deleteButton = Button(p, "Delete", 70)
  p.deleteButton:SetPoint("LEFT", save, "RIGHT", 4, 0)
  p.deleteButton:SetScript("OnClick", function()
    if not state.picked then return end
    local name = state.picked
    CM.Confirm(("Delete the custom price \"%s\"?\nFormulas and operations using it will show an error."):format(name),
      function()
        F.DeleteCustom(name)
        state.picked = nil
        p.nameBox:SetText("")
        p.formulaBox:SetText("")
        Refresh()
      end)
  end)

  -- Price sources (right)
  local sx = 12 + LEFT_W + 30
  local st = Label(p, "Price sources (use the gold name in formulas)", "GameFontNormalSmall")
  st:SetPoint("TOPLEFT", sx + 4, listTop + 14)
  local sources = List(p, sx, listTop, 820 - sx - 32, 14, InitSourceRow)
  p.sources = sources
end

CM.RegisterMessage("PricesTab", "CM_PRICES_CHANGED", function() Refresh() end)
CM.RegisterMessage("PricesTab", "CM_PRICES_UPDATED", function() Refresh() end)

API.RegisterMainTab("prices", { title = "Prices", order = 50,
  build = Build,
  show = function() Refresh() end,
})
