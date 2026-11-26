-- CueTheCashier: the Operations tab of the main window (data in Operations.lua).
--
-- Left: every operation, under its kind (Posting, Shopping, ...). Click
-- one to edit it; New makes one of the picked kind, Copy copies the picked
-- one, Delete deletes it (groups using it then use none).
-- Right: its name and settings. Price fields take a formula (see the
-- Prices tab); with an item in Test item, each price shows its value for
-- that item. Changes are saved when you press Enter or leave the box.
-- Groups pick operations in the Groups tab, Operations view.
-- Copyright (C) 2026 Kim. Licensed under the GNU GPL v3 or later; see LICENSE.
local _, CM = ...
local API = CM.API
local G = CM.Groups
local O = CM.Operations

local ROW = 20
local TOP = -64
local TREE_WIDTH = 250
local RIGHT_X = 12 + TREE_WIDTH + 14
local FIELD_ROW = 28
local CONTROL_X = 190

local page
local state = { kind = "post", name = nil, testItem = nil }

local function Skin() return CM.Skins:Get() end
local function Label(parent, text, font)
  local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontNormal")
  fs:SetText(text or "")
  fs:SetJustifyH("LEFT")
  return fs
end
local function Button(parent, text, width)
  local b = CreateFrame("Button", nil, parent, Skin().buttonTemplate)
  b:SetSize(width or 90, 22)
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
local function Tip(frame, title, text)
  if not text then return end
  frame:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(title, 1, 1, 1)
    GameTooltip:AddLine(text, nil, nil, nil, true)
    GameTooltip:Show()
  end)
  frame:SetScript("OnLeave", GameTooltip_Hide)
end
local function KindLabel(kind)
  for _, k in ipairs(G.OPERATION_KINDS) do if k.key == kind then return k.label end end
  return kind
end

local Refresh

local function ShowError(msg)
  if page then page.err:SetText(msg and ("|cffff4040" .. msg .. "|r") or "") end
end

-- ------------------------------------------------------------------
-- Left: kinds and their operations
-- ------------------------------------------------------------------
local function TreeData()
  local rows = {}
  for _, k in ipairs(G.OPERATION_KINDS) do
    rows[#rows + 1] = { kind = k.key, header = true }
    for _, name in ipairs(O.Names(k.key)) do rows[#rows + 1] = { kind = k.key, name = name } end
  end
  return rows
end

local function InitTreeRow(row, d)
  if not row.text then
    row.text = Label(row, "", "GameFontHighlight")
    row.text:SetPoint("RIGHT", -4, 0)
    row.text:SetWordWrap(false)
    row.sel = row:CreateTexture(nil, "BACKGROUND")
    row.sel:SetAllPoints()
    CM.Skins:Paint(row.sel, "selected")
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    CM.Skins:Paint(hl, "highlight")
    row:SetScript("OnClick", function(r)
      state.kind, state.name = r.data.kind, r.data.name
      ShowError(nil)
      Refresh()
    end)
  end
  row.data = d
  row.text:ClearAllPoints()
  row.text:SetPoint("RIGHT", -4, 0)
  if d.header then
    row.text:SetPoint("LEFT", 6, 0)
    row.text:SetText("|cffffd100" .. KindLabel(d.kind) .. "|r")
  else
    row.text:SetPoint("LEFT", 22, 0)
    row.text:SetText(d.name)
  end
  row.sel:SetShown(d.kind == state.kind and d.name == state.name)
end

-- ------------------------------------------------------------------
-- Right: one form per kind
-- ------------------------------------------------------------------
local function SaveField(f, value)
  if not state.name then return end
  local ok, err = O.Set(state.kind, state.name, f.key, value)
  ShowError(not ok and (f.label .. ": " .. tostring(err)) or nil)
  Refresh()
end

local function ValueText(f)
  if f.type ~= "price" or not state.name then return "" end
  local _, err = API.ParsePrice(O.Value(state.kind, state.name, f.key))
  if err then return "|cffff4040error|r" end
  if not state.testItem then return "" end
  local v = O.Price(state.kind, state.name, f.key, state.testItem)
  return v and CM.FormatMoney(v) or "|cffaaaaaano value|r"
end

local function MakeControl(form, f, y)
  local label = Label(form, f.label)
  label:SetPoint("TOPLEFT", 0, y - 4)
  label:SetWidth(CONTROL_X - 8)
  label:SetWordWrap(false)
  local c
  if f.type == "price" or f.type == "text" or f.type == "number" then
    c = Input(form, f.type == "price" and 240 or (f.type == "number" and 60 or 160))
    if f.type == "number" then c:SetNumeric(true) end
    c:SetPoint("TOPLEFT", CONTROL_X + 6, y)
    c:SetScript("OnEditFocusLost", function(self)
      local cur = O.Value(state.kind, state.name, f.key)
      if self:GetText() ~= tostring(cur) then SaveField(f, self:GetText()) end
    end)
    c.Update = function(self)
      if not self:HasFocus() then self:SetText(tostring(O.Value(state.kind, state.name, f.key) or "")) end
    end
    if f.type == "text" then
      -- A character name: one click puts in the character you play now.
      local me = Button(form, "This character", 110)
      me:SetPoint("LEFT", c, "RIGHT", 8, 0)
      me:SetScript("OnClick", function()
        c:ClearFocus()
        -- Forever names can have two parts (seen in game: UnitFullName gives
        -- the first name and the surname); some have only one.
        local first, second = UnitFullName("player")
        first = first or UnitName("player") or ""
        SaveField(f, (second and second ~= "") and (first .. " " .. second) or first)
      end)
      Tip(me, "This character", "Fills in the name of the character you are playing now.")
    end
  elseif f.type == "toggle" then
    c = CreateFrame("CheckButton", nil, form, Skin().checkTemplate)
    c:SetSize(26, 26)
    c:SetPoint("TOPLEFT", CONTROL_X, y + 2)
    c:SetScript("OnClick", function(self) SaveField(f, self:GetChecked() and true or false) end)
    c.Update = function(self) self:SetChecked(O.Value(state.kind, state.name, f.key) and true or false) end
  else -- choice
    c = Button(form, "", 200)
    c:SetPoint("TOPLEFT", CONTROL_X, y)
    local function OptionText(v)
      for _, o in ipairs(f.options) do if o[1] == v then return o[2] end end
      return tostring(v)
    end
    c:SetScript("OnClick", function(self)
      local cur = O.Value(state.kind, state.name, f.key)
      if MenuUtil and MenuUtil.CreateContextMenu then
        MenuUtil.CreateContextMenu(self, function(_, root)
          for _, o in ipairs(f.options) do
            root:CreateRadio(o[2], function() return O.Value(state.kind, state.name, f.key) == o[1] end,
              function() SaveField(f, o[1]) end)
          end
        end)
      else
        -- No menu API: step to the next choice.
        for i, o in ipairs(f.options) do
          if o[1] == cur then SaveField(f, f.options[i % #f.options + 1][1]); break end
        end
      end
    end)
    c.Update = function(self) self:SetText(OptionText(O.Value(state.kind, state.name, f.key))) end
  end
  Tip(label, f.label, f.tooltip)
  local value = Label(form, "", "GameFontHighlightSmall")
  value:SetPoint("TOPLEFT", CONTROL_X + 256, y - 5)
  value:SetPoint("RIGHT", form, "RIGHT", -4, 0)
  value:SetJustifyH("RIGHT")
  return { control = c, value = value, field = f }
end

local function BuildForm(parent, kind)
  local form = CreateFrame("Frame", nil, parent)
  form:SetPoint("TOPLEFT", 0, -60)
  form:SetPoint("BOTTOMRIGHT", 0, 60)
  form.controls = {}
  for i, f in ipairs(O.FIELDS[kind]) do
    form.controls[#form.controls + 1] = MakeControl(form, f, -(i - 1) * FIELD_ROW)
  end
  form:Hide()
  return form
end

-- ------------------------------------------------------------------
-- Refresh
-- ------------------------------------------------------------------
Refresh = function()
  if not (page and page:IsVisible()) then return end
  if state.name and not O.Exists(state.kind, state.name) then state.name = nil end
  local tree = TreeData()
  CM.SetRows(page.tree, tree)
  page.newButton:SetText("New " .. KindLabel(state.kind))
  local has = state.name ~= nil
  page.copyButton:SetEnabled(has)
  page.deleteButton:SetEnabled(has)
  page.right:SetShown(has)
  page.none:SetShown(not has)
  for kind, form in pairs(page.forms) do form:SetShown(has and kind == state.kind) end
  if not has then return end
  if not page.nameBox:HasFocus() then page.nameBox:SetText(state.name) end
  page.kindText:SetText(KindLabel(state.kind) .. " operation")
  for _, c in ipairs(page.forms[state.kind].controls) do
    c.control:Update()
    c.value:SetText(ValueText(c.field))
  end
  local used = O.UsedBy(state.kind, state.name)
  page.used:SetText(#used > 0 and ("Used by: " .. table.concat(used, ", "))
    or "Not used by any group yet. Pick it in Groups > Operations.")
end

-- Opens the tab on one operation (from the group view).
function CM.ShowOperation(kind, name)
  state.kind, state.name = kind, name
  API.ShowMainWindow("operations")
  Refresh()
end

-- ------------------------------------------------------------------
-- Build
-- ------------------------------------------------------------------
local function Build(p)
  page = p
  local h = Label(p, "Rules for your groups. Price fields take a formula, see the Prices tab.")
  h:SetPoint("TOPLEFT", 70, -36)

  local treeInset = CreateFrame("Frame", nil, p, Skin().insetTemplate)
  treeInset:SetPoint("TOPLEFT", 12, TOP)
  treeInset:SetPoint("BOTTOMLEFT", 12, 44)
  treeInset:SetWidth(TREE_WIDTH)
  local box = CreateFrame("Frame", nil, p, "WowScrollBoxList")
  local bar = CreateFrame("EventFrame", nil, p, "MinimalScrollBar")
  local view = CreateScrollBoxListLinearView()
  view:SetElementInitializer("CueTheCashierResultRowTemplate", InitTreeRow)
  if view.SetElementExtent then view:SetElementExtent(ROW) end
  ScrollUtil.InitScrollBoxListWithScrollBar(box, bar, view)
  box:SetPoint("TOPLEFT", treeInset, "TOPLEFT", 4, -4)
  box:SetPoint("BOTTOMRIGHT", treeInset, "BOTTOMRIGHT", -4, 4)
  bar:SetPoint("TOPLEFT", treeInset, "TOPRIGHT", 6, 0)
  bar:SetPoint("BOTTOMLEFT", treeInset, "BOTTOMRIGHT", 6, 0)
  p.tree = box

  p.newButton = Button(p, "New", 140)
  p.newButton:SetPoint("BOTTOMLEFT", 12, 14)
  p.newButton:SetScript("OnClick", function()
    local name = O.Create(state.kind, O.FreeName(state.kind, KindLabel(state.kind)))
    state.name = name
    ShowError(nil)
    Refresh()
    if page.nameBox then page.nameBox:SetFocus(); page.nameBox:HighlightText() end
  end)
  p.copyButton = Button(p, "Copy", 60)
  p.copyButton:SetPoint("LEFT", p.newButton, "RIGHT", 4, 0)
  p.copyButton:SetScript("OnClick", function()
    if state.name then state.name = O.Copy(state.kind, state.name); Refresh() end
  end)
  p.deleteButton = Button(p, "Delete", 62)
  p.deleteButton:SetPoint("LEFT", p.copyButton, "RIGHT", 4, 0)
  p.deleteButton:SetScript("OnClick", function()
    if not state.name then return end
    local kind, name = state.kind, state.name
    local used = O.UsedBy(kind, name)
    CM.Confirm(("Delete the %s operation \"%s\"?%s"):format(KindLabel(kind):lower(), name,
      #used > 0 and ("\nUsed by %d groups; they will have none."):format(#used) or ""),
      function() O.Delete(kind, name) end)
  end)

  p.none = Label(p, "Pick an operation on the left, or click New.", "GameFontDisable")
  p.none:SetPoint("TOPLEFT", RIGHT_X + 10, TOP - 40)

  local r = CreateFrame("Frame", nil, p)
  r:SetPoint("TOPLEFT", RIGHT_X, TOP)
  r:SetPoint("BOTTOMRIGHT", -12, 12)
  p.right = r

  local nameLabel = Label(r, "Name")
  nameLabel:SetPoint("TOPLEFT", 0, -4)
  p.nameBox = Input(r, 200)
  p.nameBox:SetPoint("LEFT", nameLabel, "RIGHT", 12, 0)
  p.nameBox:SetScript("OnEditFocusLost", function(self)
    if not state.name or self:GetText() == state.name then return end
    local newName, err = O.Rename(state.kind, state.name, self:GetText())
    if newName then state.name = newName; ShowError(nil) else ShowError(err) end
    Refresh()
  end)
  p.kindText = Label(r, "", "GameFontDisableSmall")
  p.kindText:SetPoint("LEFT", p.nameBox, "RIGHT", 10, 0)

  -- Test item: show what each price works out to for one item.
  p.testBox = Input(r, 120)
  p.testBox:SetPoint("TOPRIGHT", -8, -30)
  local testLabel = Label(r, "Test item", "GameFontNormalSmall")
  testLabel:SetPoint("RIGHT", p.testBox, "LEFT", -10, 0)
  Tip(p.testBox, "Test item", "Type an item ID or name (or shift-click an item) to see what each price " ..
    "field works out to for it.")
  p.testBox:SetScript("OnEditFocusLost", function(self)
    local text = self:GetText()
    state.testItem = text ~= "" and (CM.ParseItemID(text) or API.FindItemID(text)) or nil
    Refresh()
  end)
  if HandleModifiedItemClick then
    hooksecurefunc("HandleModifiedItemClick", function(link)
      if not (p:IsVisible() and type(link) == "string" and IsShiftKeyDown()) then return end
      local id = CM.ParseItemID(link)
      if id then
        state.testItem = id
        p.testBox:SetText((C_Item.GetItemInfo(id)) or tostring(id))
        Refresh()
      end
    end)
  end

  p.forms = {}
  for _, k in ipairs(G.OPERATION_KINDS) do p.forms[k.key] = BuildForm(r, k.key) end

  p.used = Label(r, "", "GameFontHighlightSmall")
  p.used:SetPoint("BOTTOMLEFT", 0, 30)
  p.used:SetPoint("RIGHT", r, "RIGHT", -8, 0)
  p.used:SetWordWrap(false)
  p.err = Label(r, "", "GameFontHighlightSmall")
  p.err:SetPoint("BOTTOMLEFT", 0, 8)
  p.err:SetPoint("RIGHT", r, "RIGHT", -8, 0)
  p.err:SetWordWrap(false)
end

CM.RegisterMessage("OperationsTab", "CM_OPERATIONS_CHANGED", function() Refresh() end)
CM.RegisterMessage("OperationsTab", "CM_GROUPS_CHANGED", function() Refresh() end)
CM.RegisterMessage("OperationsTab", "CM_PRICES_CHANGED", function() Refresh() end)

API.RegisterMainTab("operations", { title = "Operations", order = 40,
  build = Build,
  show = function() Refresh() end,
})
