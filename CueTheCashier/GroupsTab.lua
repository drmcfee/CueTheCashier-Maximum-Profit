-- CueTheCashier: the Groups tab of the main window (data in Groups.lua).
--
-- Left: the group tree, with the Base Group (every item) on top. Click a group to pick it, click +/- to fold its
-- sub-groups, right-click for a menu (new sub-group, move, export,
-- delete). Buttons under it: New Group, New Sub-group, Delete.
-- Right: the picked group's name, Items / Operations
-- buttons, and for Items two lists: the
-- parent group's items (your bags for a top-level group) and this
-- group's items, with Add / Remove between them. Add items also by typing
-- an ID or a name in the Add item box, by shift-clicking an item anywhere
-- while this tab is open, or by dropping an item on a list. Pick items on
-- the right to change this group's rank for them (bottom left: box, Up, Down, Make 1st).
-- Copyright (C) 2026 Kim. Licensed under the GNU GPL v3 or later; see LICENSE.
local _, CM = ...
local API = CM.API
local G = CM.Groups

local ROW = 20
local TOP = -64
local TREE_WIDTH = 250
local RIGHT_X = 12 + TREE_WIDTH + 14

local page -- the tab's frame once built
local state = { selected = nil, picked = { left = {}, right = {} }, anchor = {}, tab = "items" }

local function Skin() return CM.Skins:Get() end
local function Collapsed()
  local s = CM.ProfileSettings()
  s.groupsCollapsed = s.groupsCollapsed or {}
  return s.groupsCollapsed
end

local function ItemName(itemID)
  local name, _, quality = C_Item.GetItemInfo(itemID)
  if not name then
    if C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(itemID) end
    state.waitingNames = true
    return "item " .. itemID
  end
  local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality or 1]
  if color and color.hex then return color.hex .. name .. "|r" end
  return name
end

local function ItemIcon(itemID)
  local icon = C_Item.GetItemInfoInstant and select(5, C_Item.GetItemInfoInstant(itemID))
  return icon or "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function Button(parent, text, width)
  local b = CreateFrame("Button", nil, parent, Skin().buttonTemplate)
  b:SetSize(width or 90, 22)
  b:SetText(text)
  return b
end

local function Input(parent, width, numeric)
  local e = CreateFrame("EditBox", nil, parent, Skin().inputTemplate)
  e:SetSize(width, 22)
  e:SetAutoFocus(false)
  if numeric then e:SetNumeric(true); e:SetMaxLetters(3) end
  CM.Skins:StyleInput(e)
  e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  return e
end

local function Label(parent, text, font)
  local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontNormal")
  fs:SetText(text or "")
  fs:SetJustifyH("LEFT")
  return fs
end

local function ScrollList(parent, inset, template, init)
  local box = CreateFrame("Frame", nil, parent, "WowScrollBoxList")
  local bar = CreateFrame("EventFrame", nil, parent, "MinimalScrollBar")
  local view = CreateScrollBoxListLinearView()
  view:SetElementInitializer(template, init)
  if view.SetElementExtent then view:SetElementExtent(ROW) end
  ScrollUtil.InitScrollBoxListWithScrollBar(box, bar, view)
  box:SetPoint("TOPLEFT", inset, "TOPLEFT", 4, -4)
  box:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -4, 4)
  bar:SetPoint("TOPLEFT", inset, "TOPRIGHT", 6, 0)
  bar:SetPoint("BOTTOMLEFT", inset, "BOTTOMRIGHT", 6, 0)
  return box
end

local Refresh, Select, BuildOps

-- New rows without jumping back to the top (0.42.0, Kim): a click on an
-- item redraws the lists, and they should stay where they were.
local function SetRows(box, rows, keep) CM.SetRows(box, rows, keep and true or false) end

-- Adds an item to the picked group (from the box, a shift-click or a drop).
local function AddItem(itemID)
  if G.IsBase(state.selected) then
    CM.Print("The Base Group already holds every item. Pick or make another group to add items to.")
    return false
  end
  if not (state.selected and G.Get(state.selected)) then
    CM.Print("Pick a group first (or make one with New Group).")
    return false
  end
  itemID = tonumber(itemID)
  if not itemID then return false end
  if G.AddItem(state.selected, itemID) then
    CM.Print(("Added %s to %s."):format(ItemName(itemID), G.Path(state.selected)))
  end
  return true
end

local function TakeCursorItem()
  local kind, itemID = GetCursorInfo()
  if kind == "item" and itemID then
    ClearCursor()
    AddItem(itemID)
    return true
  end
end

-- ------------------------------------------------------------------
-- Tree (left)
-- ------------------------------------------------------------------
local function GroupMenu(owner, id)
  if G.IsBase(id) or not (MenuUtil and MenuUtil.CreateContextMenu) then return end
  MenuUtil.CreateContextMenu(owner, function(_, root)
    root:CreateTitle(G.Get(id).name)
    root:CreateButton("New sub-group", function()
      Select(G.Create("New Group", id), true)
    end)
    local move = root:CreateButton("Move into")
    move:CreateButton("Top level", function() G.Move(id, nil) end)
    local blocked = {}
    for _, d in ipairs(G.Descendants(id)) do blocked[d] = true end
    for _, e in ipairs(G.Tree(nil, true)) do
      if not blocked[e.id] then
        move:CreateButton(("  "):rep(e.depth) .. G.Get(e.id).name, function() G.Move(id, e.id) end)
      end
    end
    root:CreateButton("Export", function() page.ShowText("export", id) end)
    root:CreateButton("Delete", function() page.AskDelete(id) end)
  end)
end

local function InitTreeRow(row, e)
  if not row.name then
    row.toggle = CreateFrame("Button", nil, row)
    row.toggle:SetSize(14, 14)
    row.toggle:SetScript("OnClick", function(b)
      local c = Collapsed()
      c[b.groupID] = not c[b.groupID] or nil
      Refresh()
    end)
    row.toggleTex = row.toggle:CreateTexture(nil, "ARTWORK")
    row.toggleTex:SetAllPoints()
    row.name = Label(row, "", "GameFontHighlight")
    row.name:SetWordWrap(false)
    row.count = Label(row, "", "GameFontDisableSmall")
    row.count:SetPoint("RIGHT", -4, 0)
    row.count:SetJustifyH("RIGHT")
    row.sel = row:CreateTexture(nil, "BACKGROUND")
    row.sel:SetAllPoints()
    CM.Skins:Paint(row.sel, "selected")
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    CM.Skins:Paint(hl, "highlight")
    if row.RegisterForClicks then row:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    row:SetScript("OnClick", function(r, button)
      Select(r.groupID)
      if button == "RightButton" then GroupMenu(r, r.groupID) end
    end)
    row:SetScript("OnReceiveDrag", function(r)
      Select(r.groupID)
      TakeCursorItem()
    end)
  end
  row.groupID = e.id
  row.toggle.groupID = e.id
  local x = 4 + e.depth * 14
  row.toggle:ClearAllPoints()
  row.toggle:SetPoint("LEFT", x, 0)
  row.toggle:SetShown(e.hasChildren)
  row.toggleTex:SetTexture(Collapsed()[e.id] and "Interface\\Buttons\\UI-PlusButton-Up"
    or "Interface\\Buttons\\UI-MinusButton-Up")
  row.name:ClearAllPoints()
  row.name:SetPoint("LEFT", x + 18, 0)
  row.name:SetPoint("RIGHT", row.count, "LEFT", -4, 0)
  row.name:SetText(e.base and ("|cffffd100" .. G.BASE_NAME .. "|r") or G.Name(e.id))
  row.count:SetText(e.base and "all" or G.ItemCount(e.id))
  row.sel:SetShown(e.id == state.selected)
end

-- ------------------------------------------------------------------
-- Item lists (right side). Left: the parent group's items that aren't in
-- this group (your bags for a top-level group, whose parent is the Base
-- Group). Right: this group's items. Click picks an item (click again to
-- unpick), shift-click picks a range, Select All picks the whole list.
-- Add / Remove move the picked items; double-click or right-click moves
-- one at once.
-- ------------------------------------------------------------------
local SIDES = { "left", "right" }
local function Picked(side) return state.picked[side] end

local function MoveItems(side, ids)
  if not (state.selected and G.Get(state.selected)) or #ids == 0 then return end
  if side == "left" then
    G.AddItems(state.selected, ids)
  else
    G.RemoveItems(state.selected, ids)
  end
  wipe(state.picked[side])
  state.anchor[side] = nil
end

local function MovePicked(side)
  local ids = {}
  for id in pairs(state.picked[side]) do ids[#ids + 1] = id end
  MoveItems(side, ids)
end

local function InitItemRow(row, d)
  if not row.name then
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(16, 16)
    row.icon:SetPoint("LEFT", 4, 0)
    row.extra = Label(row, "", "GameFontHighlightSmall")
    row.extra:SetPoint("RIGHT", -4, 0)
    row.extra:SetWidth(40)
    row.extra:SetWordWrap(false)
    row.extra:SetJustifyH("RIGHT")
    row.name = Label(row, "", "GameFontHighlight")
    row.name:SetPoint("LEFT", 26, 0)
    row.name:SetPoint("RIGHT", row.extra, "LEFT", -4, 0)
    row.name:SetWordWrap(false)
    row.sel = row:CreateTexture(nil, "BACKGROUND")
    row.sel:SetAllPoints()
    row.sel:SetColorTexture(1, 0.82, 0, 0.18)
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    CM.Skins:Paint(hl, "highlight")
    if row.RegisterForClicks then row:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    row:SetScript("OnClick", function(r, button)
      if TakeCursorItem() then return end
      local d2 = r.data
      if button == "RightButton" then MoveItems(d2.side, { d2.itemID }); return end
      local picked = Picked(d2.side)
      local from = state.anchor[d2.side]
      if IsShiftKeyDown() and from then
        local list = page.rows[d2.side]
        for i = math.min(from, d2.index), math.max(from, d2.index) do
          if list[i] then picked[list[i].itemID] = true end
        end
      else
        picked[d2.itemID] = not picked[d2.itemID] or nil
        state.anchor[d2.side] = d2.index
      end
      Refresh()
    end)
    row:SetScript("OnDoubleClick", function(r) MoveItems(r.data.side, { r.data.itemID }) end)
    row:SetScript("OnReceiveDrag", TakeCursorItem)
    row:SetScript("OnEnter", function(r) CM.ShowItemTooltip(r, { itemID = r.data.itemID }) end)
    row:SetScript("OnLeave", GameTooltip_Hide)
  end
  row.data = d
  row.icon:SetTexture(ItemIcon(d.itemID))
  row.name:SetText(ItemName(d.itemID))
  row.extra:SetText(d.extra or "")
  -- Room for "in <sub-group>" when there is one.
  row.extra:SetWidth(d.inSub and 130 or 40)
  if d.inSub then row.name:SetTextColor(0.6, 0.6, 0.6) else row.name:SetTextColor(1, 1, 1) end
  row.icon:SetDesaturated(d.inSub and true or false)
  row.sel:SetShown(Picked(d.side)[d.itemID] and true or false)
end

local function SortRows(rows)
  table.sort(rows, function(a, b) return a.sortName < b.sortName end)
  for i, d in ipairs(rows) do d.index = i end
  return rows
end

local function SortName(itemID) return (C_Item.GetItemInfo(itemID)) or ("~" .. itemID) end

-- Items that sit in a sub-group: { [itemID] = sub-group name } for the
-- groups below `id` (not `id` itself, and not `skip`). Shown greyed with
-- "in <name>" so they don't look forgotten (0.42.1, Kim).
local function InSubGroups(id, skip)
  local out = {}
  for _, sid in ipairs(G.Descendants(id)) do
    local sg = sid ~= id and sid ~= skip and G.Get(sid)
    if sg then
      for itemID in pairs(sg.items) do
        if not out[itemID] then out[itemID] = sg.name end
      end
    end
  end
  return out
end

local function SubText(name)
  if #name > 14 then name = name:sub(1, 13) .. "..." end
  return "|cff808080in " .. name .. "|r"
end

-- Right list: this group's items. For an item in other groups too, this
-- group's rank for it: green "1/3" when this group wins, orange "2/3"
-- when another one does. Nothing when this is the item's only group.
local function GroupRows(g)
  local rows = {}
  local inSub = InSubGroups(g.id)
  for itemID in pairs(g.items) do
    local r, count = G.ItemRank(g.id, itemID)
    local extra = ""
    if r and count > 1 then
      extra = (r == 1 and "|cff00ff00" or "|cffff9900") .. r .. "/" .. count .. "|r"
    end
    if inSub[itemID] then extra = SubText(inSub[itemID]) .. (extra ~= "" and (" " .. extra) or "") end
    rows[#rows + 1] = { side = "right", itemID = itemID, sortName = SortName(itemID), extra = extra,
      inSub = inSub[itemID] }
  end
  return SortRows(rows)
end

local function BagCounts()
  local counts = {}
  local last = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
  for bag = 0, last do
    for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      if info and info.itemID then
        counts[info.itemID] = (counts[info.itemID] or 0) + (info.stackCount or 1)
      end
    end
  end
  return counts
end

-- Left list: the parent's items not in this group; for a top-level group
-- (parent = the Base Group) the items in your bags.
local function SourceRows(g)
  local rows = {}
  local parent = G.Get(g.parent)
  if parent then
    local inSub = InSubGroups(parent.id, g.id) -- in a sister group
    for itemID in pairs(parent.items) do
      if not g.items[itemID] then
        rows[#rows + 1] = { side = "left", itemID = itemID, sortName = SortName(itemID),
          extra = inSub[itemID] and SubText(inSub[itemID]) or nil, inSub = inSub[itemID] }
      end
    end
  else
    for itemID, n in pairs(BagCounts()) do
      if not g.items[itemID] then
        rows[#rows + 1] = { side = "left", itemID = itemID, sortName = SortName(itemID), extra = "x" .. n }
      end
    end
  end
  return SortRows(rows), parent
end

-- ------------------------------------------------------------------
-- Refresh
-- ------------------------------------------------------------------
Refresh = function()
  if not (page and page:IsVisible()) then return end
  state.waitingNames = false
  if state.selected and not G.Exists(state.selected) then state.selected = nil end
  local tree = G.Tree(Collapsed())
  -- Pick the first real group, or the Base Group when there is none.
  if not state.selected then state.selected = (tree[2] or tree[1]).id end
  SetRows(page.tree, tree, true)
  page.noGroups:SetShown(#tree <= 1)

  local g = G.Get(state.selected)
  local isBase = G.IsBase(state.selected)
  page.right:SetShown(g ~= nil or isBase)
  page.subButton:SetEnabled(g ~= nil)
  page.deleteButton:SetEnabled(g ~= nil)
  -- The Base Group can't be renamed.
  page.nameBox:SetEnabled(not isBase)
  if not page.nameBox:HasFocus() then page.nameBox:SetText(G.Name(state.selected) or "") end
  page.path:SetText(g and g.parent and G.Path(g.id) or "")
  local ops = state.tab == "ops"
  page.SetTab(state.tab)
  page.opsView:SetShown(ops)
  page.itemsView:SetShown(not ops and g ~= nil)
  page.baseInfo:SetShown(not ops and isBase)
  if ops then page.opsView:Fill(state.selected) return end
  if not g then return end

  local left, parent = SourceRows(g)
  local right = GroupRows(g)
  page.rows = { left = left, right = right }
  -- Picks of items no longer in a list go.
  for _, side in ipairs(SIDES) do
    local present = {}
    for _, d in ipairs(page.rows[side]) do present[d.itemID] = true end
    for id in pairs(state.picked[side]) do if not present[id] then state.picked[side][id] = nil end end
  end
  -- Same group as last time: keep the scroll spot; another group starts at the top.
  local same = state.listsFor == g.id
  state.listsFor = g.id
  SetRows(page.leftList, left, same)
  SetRows(page.rightList, right, same)
  page.leftTitle:SetText(parent and ("In %s, not here (%d)"):format(parent.name, #left)
    or ("In your bags, not here (%d)"):format(#left))
  page.rightTitle:SetText(("In this group (%d)"):format(#right))
  page.leftEmpty:SetText(parent and ("Everything in %s is in this group too."):format(parent.name)
    or "Nothing in your bags that isn't in this group.")
  page.leftEmpty:SetShown(#left == 0)
  page.rightEmpty:SetShown(#right == 0)
  local nl, nr = 0, 0
  for _ in pairs(state.picked.left) do nl = nl + 1 end
  for _ in pairs(state.picked.right) do nr = nr + 1 end
  page.addButton:SetText(nl > 0 and ("Add %d"):format(nl) or "Add")
  page.addButton:SetEnabled(nl > 0)
  page.removeButton:SetText(nr > 0 and ("Remove %d"):format(nr) or "Remove")
  page.removeButton:SetEnabled(nr > 0)

  -- Rank bar: for the items picked on the right.
  page.itemBar:SetShown(nr > 0)
  page.hint:SetShown(nr == 0)
  if nr > 0 then
    local first = next(state.picked.right)
    local r, count = G.ItemRank(g.id, first)
    local anyUp, anyDown = false, false
    for id in pairs(state.picked.right) do
      local ri, ci = G.ItemRank(g.id, id)
      if ri and ri > 1 then anyUp = true end
      if ri and ci and ri < ci then anyDown = true end
    end
    page.itemLabel:SetText(nr == 1 and ("%s, rank here (of %d):"):format(ItemName(first), count or 1)
      or ("%d picked items, rank here:"):format(nr))
    if not page.itemRank:HasFocus() then page.itemRank:SetText(nr == 1 and (r or "") or "") end
    page.itemUp:SetEnabled(anyUp)
    page.itemDown:SetEnabled(anyDown)
    page.itemTop:SetEnabled(anyUp)
  end
end


Select = function(id, rename)
  if id ~= state.selected then
    wipe(state.picked.left); wipe(state.picked.right)
    state.anchor = {}
  end
  state.selected = id
  Refresh()
  if rename and page then
    page.nameBox:SetFocus()
    page.nameBox:HighlightText()
  end
end

-- ------------------------------------------------------------------
-- Operations view: which operation of each kind the group uses (its own,
-- its parent's, or the Base Group's default). Choosing them comes with
-- the Operations tab.
-- ------------------------------------------------------------------
function BuildOps(parent)
  local v = CreateFrame("Frame", nil, parent)
  v:SetAllPoints(parent)
  local intro = Label(v, "The rules this group's items follow. A sub-group without its own uses its parent's; " ..
    "without one anywhere, the Base Group's is used (pick \"None, not even the Base Group's\" to stop that). " ..
    "Items in no group only get the Base Group's Crafting operation. Make operations on the Operations tab.",
    "GameFontHighlightSmall")
  intro:SetPoint("TOPLEFT", 0, -66)
  intro:SetPoint("RIGHT", v, "RIGHT", -8, 0)
  intro:SetJustifyH("LEFT")
  intro:SetSpacing(2)
  v.values = {}
  for i, kind in ipairs(G.OPERATION_KINDS) do
    local y = -122 - (i - 1) * 30
    local l = Label(v, kind.label)
    l:SetPoint("TOPLEFT", 0, y)
    local choose = Button(v, "Choose", 80)
    choose:SetPoint("TOPRIGHT", -8, y + 4)
    choose:SetScript("OnClick", function(self) v:Menu(self, kind) end)
    local val = Label(v, "", "GameFontHighlight")
    val:SetPoint("TOPLEFT", 190, y)
    val:SetPoint("RIGHT", choose, "LEFT", -8, 0)
    val:SetWordWrap(false)
    v.values[kind.key] = val
  end
  -- Pick this group's operation of one kind.
  function v:Menu(owner, kind)
    local id = state.selected
    local O = CM.Operations
    if not (MenuUtil and MenuUtil.CreateContextMenu) then
      CM.ShowOperation(kind.key, nil) -- no menu API: open the Operations tab
      return
    end
    MenuUtil.CreateContextMenu(owner, function(_, root)
      root:CreateTitle(kind.label)
      local own = G.Get(id) and G.Get(id).operations and G.Get(id).operations[kind.key]
      if G.IsBase(id) then own = G.Operation(id, kind.key) end
      root:CreateRadio(G.IsBase(id) and "None" or "None (use the parent's)", function() return own == nil end,
        function() G.SetOperation(id, kind.key, nil) end)
      if not G.IsBase(id) then
        -- false: these items get no operation of this kind, not even the Base Group's.
        root:CreateRadio("None, not even the Base Group's", function() return own == false end,
          function() G.SetOperation(id, kind.key, false) end)
      end
      for _, name in ipairs(O.Names(kind.key)) do
        root:CreateRadio(name, function() return own == name end,
          function() G.SetOperation(id, kind.key, name) end)
      end
      root:CreateButton("New " .. kind.label:lower() .. " operation", function()
        local name = O.Create(kind.key, O.FreeName(kind.key, kind.label))
        G.SetOperation(id, kind.key, name)
        CM.ShowOperation(kind.key, name)
      end)
      if own then root:CreateButton("Edit \"" .. own .. "\"", function() CM.ShowOperation(kind.key, own) end) end
    end)
  end
  function v:Fill(id)
    for _, kind in ipairs(G.OPERATION_KINDS) do
      local op, from, none = G.Operation(id, kind.key)
      local text
      if none then
        text = "|cffaaaaaanone, not even the Base Group's" ..
          (from ~= id and (" (from " .. (G.Name(from) or "?") .. ")") or "") .. "|r"
      elseif op and from == id then
        text = op
      elseif op then
        text = op .. " |cffaaaaaa(from " .. (G.Name(from) or "?") .. ")|r"
      else
        local def = not G.IsBase(id) and G.Operation(G.BASE_ID, kind.key)
        text = def and ("|cffaaaaaanone here; Base Group default: " .. def .. "|r") or "|cffaaaaaanone|r"
      end
      self.values[kind.key]:SetText(text)
    end
  end
  v:Hide()
  return v
end

-- ------------------------------------------------------------------
-- Build
-- ------------------------------------------------------------------
local function Build(p)
  page = p
  local h = Label(p, "An item can be in several groups. Each item ranks its groups 1, 2, 3...; rank 1 wins.")
  h:SetPoint("TOPLEFT", 70, -36)

  -- Tree
  local treeInset = CreateFrame("Frame", nil, p, Skin().insetTemplate)
  treeInset:SetPoint("TOPLEFT", 12, TOP)
  treeInset:SetPoint("BOTTOMLEFT", 12, 44)
  treeInset:SetWidth(TREE_WIDTH)
  p.tree = ScrollList(p, treeInset, "CueTheCashierResultRowTemplate", InitTreeRow)
  p.noGroups = Label(p, "No groups of your own yet.\nClick New Group to make one.", "GameFontDisable")
  p.noGroups:SetPoint("TOP", treeInset, "TOP", 0, -60)
  p.noGroups:SetJustifyH("CENTER")

  local new = Button(p, "New Group", 84)
  new:SetPoint("BOTTOMLEFT", 12, 14)
  new:SetScript("OnClick", function() Select(G.Create("New Group", nil), true) end)
  p.subButton = Button(p, "Sub-group", 84)
  p.subButton:SetPoint("LEFT", new, "RIGHT", 4, 0)
  p.subButton:SetScript("OnClick", function()
    if state.selected and not G.IsBase(state.selected) then
      Collapsed()[state.selected] = nil
      Select(G.Create("New Group", state.selected), true)
    end
  end)
  p.deleteButton = Button(p, "Delete", 74)
  p.deleteButton:SetPoint("LEFT", p.subButton, "RIGHT", 4, 0)
  p.deleteButton:SetScript("OnClick", function()
    if state.selected and not G.IsBase(state.selected) then p.AskDelete(state.selected) end
  end)

  -- Right side (hidden while no group is picked)
  local r = CreateFrame("Frame", nil, p)
  r:SetPoint("TOPLEFT", RIGHT_X, TOP)
  r:SetPoint("BOTTOMRIGHT", -12, 12)
  p.right = r

  -- Shown instead of the right side when the Base Group is picked.
  local baseInfo = CreateFrame("Frame", nil, p)
  baseInfo:SetPoint("TOPLEFT", RIGHT_X, TOP - 66)
  baseInfo:SetPoint("BOTTOMRIGHT", -12, 40)
  local bb = Label(baseInfo, "Every item in the game is in the Base Group, without being listed. It has the " ..
    "last rank, so any other group an item is in wins over it.\n\n" ..
    "It can't be renamed, moved or deleted, and has no sub-groups. Its operations (Operations tab above, " ..
    "\"Base\" of each kind to start with) are the defaults for the items in your groups that have no " ..
    "operation of that kind. Items in no group at all are never posted, mailed, sold or moved by them; " ..
    "only its Crafting operation covers every recipe.", "GameFontHighlight")
  bb:SetPoint("TOPLEFT", 0, -4)
  bb:SetWidth(500)
  bb:SetSpacing(4)
  baseInfo:Hide()
  p.baseInfo = baseInfo

  local nameLabel = Label(r, "Name")
  nameLabel:SetPoint("TOPLEFT", 0, -4)
  p.nameBox = Input(r, 200)
  p.nameBox:SetPoint("LEFT", nameLabel, "RIGHT", 12, 0)
  local function SaveName(self)
    local g = G.Get(state.selected)
    if g and self:GetText() ~= g.name then G.Rename(g.id, self:GetText()) end
  end
  p.nameBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  p.nameBox:SetScript("OnEditFocusLost", SaveName)

  p.path = Label(r, "", "GameFontDisableSmall")
  p.path:SetPoint("LEFT", p.nameBox, "RIGHT", 16, 0)
  p.path:SetPoint("RIGHT", r, "RIGHT", -4, 0)
  p.path:SetWordWrap(false)

  -- Two views of the picked group, picked with the buttons under its name:
  -- Items (the two lists) and Operations (its rule sets).
  -- Blizzard's top tabs (as on retail windows); plain buttons if this
  -- client has no such template.
  local function Tab(text, key)
    local ok, t = pcall(CreateFrame, "Button", nil, r, "PanelTopTabButtonTemplate")
    if not ok or not t then
      t = Button(r, text, 100)
      t.plain = true
    else
      t:SetText(text)
      if PanelTemplates_TabResize then pcall(PanelTemplates_TabResize, t, 0) end
    end
    t:SetScript("OnClick", function() state.tab = key; Refresh() end)
    return t
  end
  p.itemsTab = Tab("Items", "items")
  p.itemsTab:SetPoint("BOTTOMLEFT", r, "TOPLEFT", 4, -54)
  p.opsTab = Tab("Operations", "ops")
  p.opsTab:SetPoint("LEFT", p.itemsTab, "RIGHT", 2, 0)
  -- Line under the tabs, across the whole right side.
  local line = r:CreateTexture(nil, "ARTWORK")
  line:SetHeight(2)
  line:SetPoint("TOPLEFT", 0, -54)
  line:SetPoint("TOPRIGHT", 0, -54)
  line:SetColorTexture(0.6, 0.5, 0.25, 0.8)
  p.SetTab = function(key)
    for _, t in ipairs({ { p.itemsTab, "items" }, { p.opsTab, "ops" } }) do
      local tab, on = t[1], t[2] == key
      if tab.plain then
        if on then tab:LockHighlight() else tab:UnlockHighlight() end
      elseif on and PanelTemplates_SelectTab then
        PanelTemplates_SelectTab(tab)
      elseif PanelTemplates_DeselectTab then
        PanelTemplates_DeselectTab(tab)
      end
    end
  end
  p.opsView = BuildOps(r)
  local top = r
  r = CreateFrame("Frame", nil, top)
  r:SetAllPoints(top)
  p.itemsView = r
  p.addBox = Input(r, 130)
  p.addBox:SetPoint("TOPRIGHT", -8, -24)
  local addLabel = Label(r, "Add item")
  addLabel:SetPoint("RIGHT", p.addBox, "LEFT", -10, 0)
  p.addBox:SetScript("OnEnterPressed", function(self)
    local text = self:GetText()
    local itemID = CM.ParseItemID(text) or API.FindItemID(text)
    if itemID then
      AddItem(itemID)
      self:SetText("")
    elseif text ~= "" then
      CM.Print(("No item called \"%s\" is known yet. Try its item ID, or shift-click it."):format(text))
    end
  end)
  p.addBox:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Add item", 1, 1, 1)
    GameTooltip:AddLine("Type an item ID or name and press Enter. You can also shift-click an item " ..
      "anywhere, or drop one on a list.", nil, nil, nil, true)
    GameTooltip:Show()
  end)
  p.addBox:SetScript("OnLeave", GameTooltip_Hide)

  -- Two lists side by side: left the parent's items (or your bags),
  -- right this group's.
  local LIST_TOP, LIST_BOTTOM, LIST_W = -80, 60, 236
  local function List(side, x)
    local title = Label(r, "", "GameFontNormalSmall")
    title:SetPoint("TOPLEFT", x + 2, LIST_TOP + 14)
    title:SetWidth(LIST_W)
    title:SetWordWrap(false)
    local inset = CreateFrame("Frame", nil, r, Skin().insetTemplate)
    inset:SetPoint("TOPLEFT", x, LIST_TOP)
    inset:SetPoint("BOTTOM", r, "BOTTOM", 0, LIST_BOTTOM)
    inset:SetWidth(LIST_W)
    inset:EnableMouse(true)
    inset:SetScript("OnReceiveDrag", TakeCursorItem)
    inset:SetScript("OnMouseUp", TakeCursorItem)
    local list = ScrollList(r, inset, "CueTheCashierResultRowTemplate", InitItemRow)
    local empty = Label(r, "", "GameFontDisable")
    empty:SetPoint("TOP", inset, "TOP", 0, -40)
    empty:SetWidth(LIST_W - 30)
    empty:SetJustifyH("CENTER")
    local all = Button(r, "Select All", 84)
    all:SetPoint("TOPLEFT", inset, "BOTTOMLEFT", 0, -4)
    all:SetScript("OnClick", function()
      local picked = state.picked[side]
      local allPicked = true
      for _, d in ipairs(p.rows and p.rows[side] or {}) do
        if not picked[d.itemID] then allPicked = false end
      end
      wipe(picked) -- a second click unpicks them all
      if not allPicked then
        for _, d in ipairs(p.rows[side]) do picked[d.itemID] = true end
      end
      Refresh()
    end)
    local move = Button(r, side == "left" and "Add" or "Remove", 110)
    move:SetPoint("LEFT", all, "RIGHT", 4, 0)
    move:SetScript("OnClick", function() MovePicked(side) end)
    return title, list, empty, move
  end
  p.leftTitle, p.leftList, p.leftEmpty, p.addButton = List("left", 0)
  p.rightTitle, p.rightList, p.rightEmpty, p.removeButton = List("right", LIST_W + 28)
  p.rightEmpty:SetText("No items yet. Add them from the left, type one in Add item, or shift-click one.")

  -- Bottom: rank of the items picked on the right, or a hint.
  p.hint = Label(r, "Click to pick, shift-click for a range, double-click to move one. " ..
    "Rank: green 1/3 = this group wins, orange = another group wins.", "GameFontDisableSmall")
  p.hint:SetPoint("BOTTOMLEFT", 0, 8)
  p.hint:SetPoint("RIGHT", r, "RIGHT", -170, 0)
  p.hint:SetJustifyH("LEFT")
  p.itemBar = CreateFrame("Frame", nil, r)
  p.itemBar:SetPoint("BOTTOMLEFT", 0, 0)
  p.itemBar:SetSize(420, 26)
  p.itemLabel = Label(p.itemBar, "", "GameFontHighlightSmall")
  p.itemLabel:SetPoint("LEFT", 0, 0)
  p.itemLabel:SetWidth(190)
  p.itemLabel:SetWordWrap(false)
  local function Picked() return state.selected, state.picked.right end
  p.itemRank = Input(p.itemBar, 36, true)
  p.itemRank:SetPoint("LEFT", p.itemLabel, "RIGHT", 10, 0)
  p.itemRank:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  p.itemRank:SetScript("OnEditFocusLost", function(self)
    local v = tonumber(self:GetText())
    local gid, picked = Picked()
    if gid and v and v >= 1 then
      for id in pairs(picked) do
        if G.ItemRank(gid, id) ~= v then G.SetItemRank(gid, id, v) end
      end
    end
    Refresh()
  end)
  -- Hover: the picked item's groups in rank order.
  p.itemRank:SetScript("OnEnter", function(self)
    local gid, picked = Picked()
    local first = next(picked)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Rank", 1, 1, 1)
    GameTooltip:AddLine("Rank 1 wins when an item is in several groups. No two groups share a rank: " ..
      "moving a group to rank 2 pushes the old 2 to 3, and so on. A group that gets the item later starts last.",
      nil, nil, nil, true)
    if first then
      GameTooltip:AddLine(" ")
      for _, e in ipairs(G.ItemGroups(first)) do
        local here = e.id == gid
        GameTooltip:AddDoubleLine(e.rank .. ". " .. e.path, here and "this group" or "",
          here and 0 or 1, here and 1 or 0.82, here and 0 or 0, 0.6, 0.6, 0.6)
      end
    end
    GameTooltip:Show()
  end)
  p.itemRank:SetScript("OnLeave", GameTooltip_Hide)
  local function MoveAll(delta)
    local gid, picked = Picked()
    if not gid then return end
    for id in pairs(picked) do
      if delta == "top" then G.SetItemRank(gid, id, 1) else G.MoveItemRank(gid, id, delta) end
    end
  end
  p.itemUp = Button(p.itemBar, "Up", 44)
  p.itemUp:SetPoint("LEFT", p.itemRank, "RIGHT", 6, 0)
  p.itemUp:SetScript("OnClick", function() MoveAll(-1) end)
  p.itemDown = Button(p.itemBar, "Down", 50)
  p.itemDown:SetPoint("LEFT", p.itemUp, "RIGHT", 2, 0)
  p.itemDown:SetScript("OnClick", function() MoveAll(1) end)
  p.itemTop = Button(p.itemBar, "Make 1st", 70)
  p.itemTop:SetPoint("LEFT", p.itemDown, "RIGHT", 2, 0)
  p.itemTop:SetScript("OnClick", function() MoveAll("top") end)

  local import = Button(top, "Import", 70)
  import:SetPoint("BOTTOMRIGHT", -18, 2)
  import:SetScript("OnClick", function() p.ShowText("import") end)
  local export = Button(top, "Export", 70)
  export:SetPoint("RIGHT", import, "LEFT", -4, 0)
  export:SetScript("OnClick", function() p.ShowText("export", state.selected) end)

  -- Export / import text box, over the right side.
  local box = CreateFrame("Frame", nil, p, Skin().insetTemplate)
  box:SetPoint("TOPLEFT", RIGHT_X, TOP)
  box:SetPoint("BOTTOMRIGHT", -12, 12)
  box:SetFrameLevel(r:GetFrameLevel() + 20)
  box:EnableMouse(true)
  box.title = Label(box, "")
  box.title:SetPoint("TOPLEFT", 10, -8)
  box.title:SetPoint("RIGHT", box, "RIGHT", -10, 0)
  box.title:SetWordWrap(true)
  local scroll = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 10, -44)
  scroll:SetPoint("BOTTOMRIGHT", -30, 40)
  local edit = CreateFrame("EditBox", nil, scroll)
  edit:SetMultiLine(true)
  edit:SetAutoFocus(false)
  edit:SetFontObject(Skin().fontLog)
  edit:SetWidth(470)
  edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  scroll:SetScrollChild(edit)
  box.edit = edit
  box.close = Button(box, "Close", 80)
  box.close:SetPoint("BOTTOMRIGHT", -10, 10)
  box.close:SetScript("OnClick", function() box:Hide() end)
  box.go = Button(box, "Import", 80)
  box.go:SetPoint("RIGHT", box.close, "LEFT", -4, 0)
  box.go:SetScript("OnClick", function()
    local groups, items = G.Import(edit:GetText(), nil)
    if not groups then CM.Print(items); return end
    CM.Print(("Imported: %d new groups, %d new items in groups."):format(groups, items))
    box:Hide()
  end)
  box:Hide()
  p.textBox = box

  p.ShowText = function(mode, id)
    box:Show()
    if mode == "export" then
      box.title:SetText(id and ("Group \"%s\" and its sub-groups. Ctrl+C to copy."):format(G.Path(id))
        or "Every group. Ctrl+C to copy.")
      edit:SetText(G.Export(id))
      box.go:Hide()
      edit:SetFocus()
      edit:HighlightText()
    else
      box.title:SetText("Paste group text (Ctrl+V) and click Import. It is added at the top level; " ..
        "groups with the same name are merged.")
      edit:SetText("")
      box.go:Show()
      edit:SetFocus()
    end
  end

  p.AskDelete = function(id)
    local subs = #G.Descendants(id) - 1
    CM.Confirm(("Delete the group %s%s?\nThe items stay in any other groups they are in."):format(
      G.Path(id), subs > 0 and (" and its %d sub-groups"):format(subs) or ""),
      function()
        local parent = G.Get(id) and G.Get(id).parent
        G.Delete(id)
        Select(parent)
      end)
  end

  -- Shift-click an item anywhere while this tab is open: add it.
  if HandleModifiedItemClick then
    hooksecurefunc("HandleModifiedItemClick", function(link)
      if not (p:IsVisible() and type(link) == "string" and IsShiftKeyDown()) then return end
      if p.textBox:IsShown() then return end
      local itemID = CM.ParseItemID(link)
      if itemID then AddItem(itemID) end
    end)
  end
end

CM.RegisterMessage("GroupsTab", "CM_GROUPS_CHANGED", function() Refresh() end)
CM.RegisterEvent("GroupsTab", "BAG_UPDATE_DELAYED", function()
  Refresh() -- the left list may show your bags
end)
-- Item names that weren't loaded yet: redraw once they arrive.
CM.RegisterEvent("GroupsTab", "GET_ITEM_INFO_RECEIVED", function()
  if not (state.waitingNames and page and page:IsVisible()) or state.namesTimer then return end
  state.namesTimer = true
  C_Timer.After(0.3, function() state.namesTimer = nil; Refresh() end)
end)

API.RegisterMainTab("groups", { title = "Groups", order = 30,
  build = Build,
  show = function() Refresh() end,
  hide = function() if page then page.textBox:Hide() end end,
})

-- ------------------------------------------------------------------
-- Tooltip: which groups an item is in, in rank order; the winner in green.
-- ------------------------------------------------------------------
function CM.AddGroupLines(tooltip, itemID)
  if not CM.TooltipLineShown("groups") then return end
  local list = {}
  for _, e in ipairs(G.ItemGroups(itemID)) do
    if not e.base then list[#list + 1] = e end -- every item is in the Base Group
  end
  if #list == 0 then return end
  for i = 1, math.min(#list, 4) do
    local e = list[i]
    local text = (#list > 1 and ("%d. %s"):format(e.rank, e.name)) or e.name
    if i == 1 and #list > 1 then text = "|cff00ff00" .. text .. "|r" end
    tooltip:AddDoubleLine(i == 1 and (#list > 1 and "Groups" or "Group") or " ", text, 1, 1, 1, 1, 1, 1)
  end
  if #list > 4 then tooltip:AddDoubleLine(" ", ("and %d more"):format(#list - 4), 1, 1, 1, 0.6, 0.6, 0.6) end
end
