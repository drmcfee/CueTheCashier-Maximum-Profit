-- CueTheCashier Crafting: the Queue window (0.42.2, Kim).
--
-- Opened by the Queue... button on the Crafting List. It lists your
-- groups with a tick box each; Queue fills the Crafting List with the
-- profitable recipes (by each item's Crafting operation, as the Craft List
-- button does) whose result is in a ticked group or one of its
-- sub-groups. "Everything" ignores groups. Your ticks are remembered
-- (ns.db.settings.queueGroups). The list is replaced, like the Craft
-- List button's choices; then the auction house check asks if reagents
-- are short.
-- Copyright (C) 2026 Kim. Licensed under the GNU GPL v3 or later; see LICENSE.
local _, ns = ...
local CM = CueTheCashier
local API = CM.API

local GP = {}
ns.GroupPicker = GP

local ROW = 22
local window

local function Picked()
  local s = ns.db.settings
  if type(s.queueGroups) ~= "table" then s.queueGroups = {} end
  return s.queueGroups
end

local function CountPicked()
  local n = 0
  for id, on in pairs(Picked()) do if on then n = n + 1 end end
  return n
end

local function UpdateButton()
  if not window then return end
  local n, all = CountPicked(), Picked().all
  window.go:SetEnabled(all or n > 0)
  window.info:SetText(all and "Every recipe you know." or
    (n == 0 and "Tick one or more groups." or ("%d group%s (with their sub-groups)."):format(n, n == 1 and "" or "s")))
end

local function MakeRow(parent)
  local skin = CM.Skins:Get()
  local row = CreateFrame("Frame", nil, parent)
  row:SetHeight(ROW)
  row.bg = row:CreateTexture(nil, "BACKGROUND")
  row.bg:SetAllPoints()
  row.check = CreateFrame("CheckButton", nil, row, skin.checkTemplate)
  row.check:SetSize(22, 22)
  row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  row.label:SetPoint("LEFT", row.check, "RIGHT", 2, 0)
  row.label:SetPoint("RIGHT", -4, 0)
  row.label:SetJustifyH("LEFT")
  row.label:SetWordWrap(false)
  row.check:SetScript("OnClick", function(self)
    local key = row.key
    Picked()[key] = self:GetChecked() and true or nil
    if key == "all" then GP.Refresh() else UpdateButton() end
  end)
  return row
end

function GP.Refresh()
  if not (window and window:IsShown()) then return end
  local picked = Picked()
  local lines = { { key = "all", text = "|cffffd100Everything|r (all recipes you know, no groups)", depth = 0 } }
  for _, g in ipairs(API.GetGroups and API.GetGroups() or {}) do
    if not g.base then
      lines[#lines + 1] = { key = g.id, text = ("%s |cff808080(%d)|r"):format(g.name, g.itemCount or 0), depth = g.depth or 0 }
    end
  end
  if #lines == 1 then
    lines[2] = { text = "|cff808080No groups yet. Make Group in the profession window, or /cmp > Groups.|r", depth = 0 }
  end
  local y = 0
  for i, line in ipairs(lines) do
    local row = window.rows[i] or MakeRow(window.content)
    window.rows[i] = row
    row.key = line.key
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", window.content, "TOPLEFT", 0, -y)
    row:SetPoint("RIGHT", window.content, "RIGHT", 0, 0)
    row.check:ClearAllPoints()
    row.check:SetPoint("LEFT", 2 + line.depth * 16, 0)
    row.check:SetShown(line.key ~= nil)
    row.check:SetChecked(line.key ~= nil and picked[line.key] and true or false)
    -- With Everything ticked the groups don't matter: greyed.
    local off = picked.all and line.key ~= "all"
    row.check:SetEnabled(not off)
    row.label:SetText(line.text)
    row.label:SetAlpha(off and 0.5 or 1)
    CM.Skins:Stripe(row.bg, i)
    row:Show()
    y = y + ROW
  end
  for i = #lines + 1, #window.rows do window.rows[i]:Hide() end
  window.content:SetHeight(math.max(y, 10))
  UpdateButton()
end

local function Queue()
  local picked = Picked()
  local items
  if not picked.all then
    items = {}
    -- Groups deleted since you ticked them are dropped.
    local exists = {}
    for _, g in ipairs(API.GetGroups()) do exists[g.id] = true end
    for id, on in pairs(picked) do
      if on and id ~= "all" then
        if exists[id] then
          for itemID in pairs(API.GetGroupItems(id, true)) do items[itemID] = true end
        else
          picked[id] = nil
        end
      end
    end
  end
  local n = ns.CraftList.Build(nil, items)
  CM.Print(("Crafting List: %d profitable recipes from %s."):format(n,
    picked.all and "everything you know" or ("%d group(s)"):format(CountPicked())))
  window:Hide()
  ns.CraftList.Show()
  ns.Safe("Supply check", ns.CraftList.CheckSupplyAll)
end

local function Build()
  local skin = CM.Skins:Get()
  local f = CreateFrame("Frame", "CueTheCashierQueueFrame", UIParent, skin.windowTemplate)
  CM.Skins:ApplyWindow(f)
  f:SetFrameStrata("DIALOG")
  f:SetToplevel(true)
  f:SetSize(300, 380)
  f:SetPoint("CENTER", 0, 40)
  f:EnableMouse(true)
  f:SetMovable(true)
  f:SetClampedToScreen(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    ns.ListWindow.SavePosition(self, ns.db.settings, "queuePos")
  end)
  ns.ListWindow.LoadPosition(f, ns.db.settings, "queuePos")
  CM.CloseOnEscape(f)
  local top = CM.Skins:SetupWindow(f, "Queue from groups")
  f:SetHeight(380 + top - 30)
  local intro = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  intro:SetPoint("TOPLEFT", 14, -(top + 2))
  intro:SetPoint("RIGHT", -14, 0)
  intro:SetJustifyH("LEFT")
  intro:SetText("Queue the profitable recipes that make items in these groups:")
  CM.Skins:AddInset(f, 6, top + 18, 6, 58)
  local scroll = CreateFrame("ScrollFrame", "CueTheCashierQueueScroll", f, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 10, -(top + 22))
  scroll:SetPoint("BOTTOMRIGHT", -30, 62)
  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(260, 10)
  scroll:SetScrollChild(content)
  f.content, f.rows = content, {}
  f.info = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  f.info:SetPoint("BOTTOMLEFT", 14, 40)
  f.info:SetPoint("RIGHT", -14, 0)
  f.info:SetJustifyH("LEFT")
  f.go = CreateFrame("Button", nil, f, skin.buttonTemplate)
  f.go:SetSize(90, 22)
  f.go:SetPoint("BOTTOMRIGHT", -10, 10)
  f.go:SetText("Queue")
  f.go:SetScript("OnClick", Queue)
  local cancel = CreateFrame("Button", nil, f, skin.buttonTemplate)
  cancel:SetSize(80, 22)
  cancel:SetPoint("RIGHT", f.go, "LEFT", -6, 0)
  cancel:SetText(CANCEL or "Cancel")
  cancel:SetScript("OnClick", function() f:Hide() end)
  f:SetScript("OnShow", GP.Refresh)
  f:Hide()
  return f
end

function GP.Show()
  window = window or Build()
  if window:IsShown() then window:Hide() return end
  window:Show()
  GP.Refresh()
end
