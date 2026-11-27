-- CueTheCashier Crafting: a simple list window in Blizzard's style, used by
-- the Crafting List and the Task List. Rows are text left and right;
-- headers are gold. Each row can have an item tooltip, extra tooltip
-- lines and a click action.
--   local w = ns.ListWindow.New("CueTheCashierTaskListFrame", "Task List", 380, 440)
--   w:SetLines({ { header = "Auction House", right = "1g" },
--                { left = "3 x Light Leather", right = "1s 20c", itemID = 2318,
--                  tip = { "Click to buy it" }, onClick = function(button) end } })
-- Copyright (C) 2026 Kim. Licensed under the GNU GPL v3 or later; see LICENSE.
local _, ns = ...
local CM = CueTheCashier

local W = {}
ns.ListWindow = W

local ROW_HEIGHT = 16

local function NewRow(parent)
  local row = CreateFrame("Button", nil, parent)
  row:SetHeight(ROW_HEIGHT)
  -- Same row look as the auction house lists: stripes and the skin's highlight.
  row.bg = row:CreateTexture(nil, "BACKGROUND")
  row.bg:SetAllPoints()
  local hl = row:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  CM.Skins:Paint(hl, "highlight")
  row.left = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.left:SetPoint("LEFT", 4, 0)
  row.left:SetJustifyH("LEFT")
  row.right = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.right:SetPoint("RIGHT", -4, 0)
  row.right:SetJustifyH("RIGHT")
  row.left:SetPoint("RIGHT", row.right, "LEFT", -6, 0)
  row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  row:SetScript("OnEnter", function(self)
    local line = self.line
    if not line or not (line.itemID or line.tip) then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if line.itemID then
      GameTooltip:SetItemByID(line.itemID)
      if line.tip then GameTooltip:AddLine(" ") end
    end
    for i, t in ipairs(line.tip or {}) do
      if type(t) == "table" then
        GameTooltip:AddDoubleLine(t[1], t[2], 1, 0.82, 0, 1, 1, 1)
      elseif i == 1 and not line.itemID then
        GameTooltip:AddLine(t, 1, 1, 1)
      else
        GameTooltip:AddLine(t, 0.5, 0.5, 0.5, true)
      end
    end
    GameTooltip:Show()
  end)
  row:SetScript("OnLeave", function() GameTooltip:Hide() end)
  row:SetScript("OnClick", function(self, button)
    if self.line and self.line.onClick then self.line.onClick(button) end
  end)
  return row
end

-- bottom: room below the list for buttons and a totals line.
-- Not in Blizzard's Escape list (UISpecialFrames): that gave "blocked"
-- warnings in game (0.19.0) and took an extra press. The Crafting List hides
-- with the profession window; the Task List watches Escape itself.
function W.New(name, title, width, height, bottom)
  local skin = CM.Skins:Get()
  local f = CreateFrame("Frame", name, UIParent, skin.windowTemplate)
  CM.Skins:ApplyWindow(f)
  f:SetSize(width, height)
  f:SetPoint("CENTER", 300, 0)
  -- Comes to the front when clicked (0.45.0, Widgets.lua).
  if CM.Raisable then CM.Raisable(f) else f:SetFrameStrata("HIGH") end
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  -- f.OnMoved(f), when set, saves where you dragged it (0.42.0).
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    if self.OnMoved then self:OnMoved() end
  end)
  local top = CM.Skins:SetupWindow(f, title)
  f:SetHeight(height + top - 30)
  -- The list sits on an inset, like the auction house's lists.
  CM.Skins:AddInset(f, 6, top - 2, 6, (bottom or 40) - 4)
  local scroll = CreateFrame("ScrollFrame", name .. "Scroll", f, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 10, -(top + 2))
  scroll:SetPoint("BOTTOMRIGHT", -30, bottom or 40)
  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(width - 40, 10)
  scroll:SetScrollChild(content)
  f.content, f.rows = content, {}
  f.totals = f:CreateFontString(nil, "OVERLAY", skin.fontSmall)
  f.totals:SetPoint("BOTTOMLEFT", 14, 38)
  f.totals:SetJustifyH("LEFT")
  f.AddButton, f.SetLines = W.AddButton, W.SetLines
  f.SavePosition, f.LoadPosition = W.SavePosition, W.LoadPosition
  f:Hide()
  return f
end

function W.AddButton(f, text, width, onClick, tip)
  local skin = CM.Skins:Get()
  local b = CreateFrame("Button", nil, f, skin.buttonTemplate)
  b:SetSize(width, 22)
  if f.lastButton then b:SetPoint("RIGHT", f.lastButton, "LEFT", -6, 0)
  else b:SetPoint("BOTTOMRIGHT", -10, 10) end
  f.lastButton = b
  b:SetText(text)
  b:SetScript("OnClick", onClick)
  if tip then
    b:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:AddLine(tip, 1, 1, 1, true)
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end
  return b
end

function W.SetLines(f, lines)
  local y = 0
  for i, line in ipairs(lines) do
    local row = f.rows[i] or NewRow(f.content)
    f.rows[i] = row
    row.line = line
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", f.content, "TOPLEFT", 0, -y)
    row:SetPoint("RIGHT", f.content, "RIGHT", 0, 0)
    CM.Skins:Stripe(row.bg, (not line.header and line.left ~= " ") and i or nil)
    if line.header then
      row.left:SetFontObject("GameFontNormal")
      row.left:SetText(line.header)
    else
      row.left:SetFontObject("GameFontHighlightSmall")
      row.left:SetText(line.left or "")
    end
    row.right:SetText(line.right or "")
    row:Show()
    y = y + ROW_HEIGHT + (line.header and 4 or 0)
  end
  for i = #lines + 1, #f.rows do
    f.rows[i]:Hide()
    f.rows[i].line = nil
  end
  f.content:SetHeight(math.max(y, 10))
end

-- Remembering a free-standing window's spot (Task List): saved as
-- { point, x, y } against the screen in t[key].
function W.SavePosition(f, t, key)
  local point, _, rel, x, y = f:GetPoint(1)
  if point then t[key] = { point = point, rel = rel or point, x = x, y = y } end
end

function W.LoadPosition(f, t, key)
  local p = t[key]
  if type(p) ~= "table" or not p.point then return false end
  f:ClearAllPoints()
  f:SetPoint(p.point, UIParent, p.rel or p.point, tonumber(p.x) or 0, tonumber(p.y) or 0)
  return true
end
