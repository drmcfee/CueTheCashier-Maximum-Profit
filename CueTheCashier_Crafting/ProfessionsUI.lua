-- CueTheCashier Crafting: profit in Blizzard's own profession window.
--
-- Blizzard's window stays as it is. CueTheCashier only adds:
--   * in the recipe list, the profit (green) or loss (red) of one craft at
--     the right of each recipe you can price;
--   * under the reagents of the selected recipe, three lines in
--     Blizzard's font: Craft cost, Sells for (after the auction house cut)
--     and Profit. Hover them for every reagent's price and where it comes
--     from (auction, vendor or your own craft);
--   * Keep in stock / Min profit: the item's restock rule (Restock.lua);
--   * a Craft List button (CraftList.lua).
-- /cmp prof move x y moves the three lines if they sit badly on Forever's
-- window.
--
-- GUESS (not seen in game yet): Forever uses the retail-style window
-- (Blizzard_Professions: ProfessionsFrame.CraftingPage with RecipeList and
-- SchematicForm), since its addon API is the retail one. If it isn't
-- there, /cmp prof says so in the log.
-- Copyright (C) 2026 Kim. Licensed under the GNU GPL v3 or later; see LICENSE.
local _, ns = ...
local CM = CueTheCashier
local API = CM.API

local UI = {}
ns.UI = UI

local hooked = { list = false, form = false }
local box -- the three lines under the reagents
local missingLogged = false

local GREEN, RED, GRAY = "|cff20ff20", "|cffff2020", "|cff808080"

local function Money(c) return API.FormatMoney(c) end

-- Short money for the recipe list: 1g 05s, 5s 03c, 7c (with coin icons).
local GOLD = "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t"
local SILVER = "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t"
local COPPER = "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t"
local function Short(copper)
  copper = math.floor(math.abs(copper) + 0.5)
  local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
  if g > 0 then return ("%d%s %02d%s"):format(g, GOLD, s, SILVER) end
  if s > 0 then return ("%d%s %02d%s"):format(s, SILVER, c, COPPER) end
  return ("%d%s"):format(c, COPPER)
end

-- The whole number is coloured: green profit, red loss, white for none.
-- The coin icons keep their own colours.
local WHITE = "|cffffffff"
local function ProfitText(profit, short)
  if not profit then return "" end
  local f = short and Short or Money
  local amount = math.floor(math.abs(profit) + 0.5)
  if amount == 0 then return WHITE .. f(0) .. "|r" end
  local color, sign = profit > 0 and GREEN or RED, profit > 0 and "+" or "-"
  -- Re-apply the colour after each coin icon, so the digits stay coloured.
  local text = f(amount):gsub("|t", "|t" .. color)
  return color .. sign .. text .. "|r"
end
ns.ProfitText = ProfitText

local function Page()
  local pf = _G.ProfessionsFrame
  return pf and pf.CraftingPage, pf
end

-- ------------------------------------------------------------------
-- Recipe list
-- ------------------------------------------------------------------
local function RowRecipe(row)
  local data = row.GetElementData and row:GetElementData()
  if type(data) ~= "table" then return nil end
  local node = data.GetData and data:GetData() or data
  return type(node) == "table" and node.recipeInfo or nil
end

function UI.DecorateRow(row)
  if type(row) ~= "table" or not row.CreateFontString then return end
  local info = RowRecipe(row)
  local fs = row.cmProfit
  local res = info and info.recipeID and ns.Costs.Recipe(info.recipeID)
  if not (res and res.profit) then
    if fs then fs:Hide() end
    return
  end
  if not fs then
    fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetJustifyH("RIGHT")
    row.cmProfit = fs
  end
  fs:ClearAllPoints()
  -- Always at the row's right edge. (0.15-0.17 anchored it left of the
  -- skill-up arrow, but on this window the arrow sits left of the name,
  -- which pushed the number out of sight on every orange/yellow/green
  -- recipe; seen in game 25 Nov.)
  fs:SetPoint("RIGHT", row, "RIGHT", -6, 0)
  fs:SetText(ProfitText(res.profit, true))
  fs:Show()
  -- Make room: Blizzard sizes the name before we add our text.
  local label = row.Label
  local left, ours = label and label.GetLeft and label:GetLeft(), fs.GetLeft and fs:GetLeft()
  if left and ours then
    local room = ours - left - 4
    if room > 30 and (label:GetWidth() or 0) > room then label:SetWidth(room) end
  end
end

local function OnRowInit(...)
  for i = 1, select("#", ...) do
    local a = select(i, ...)
    if type(a) == "table" and a ~= UI and a.GetElementData then
      UI.DecorateRow(a)
      return
    end
  end
end

function UI.RefreshList()
  local page = Page()
  local sb = page and page.RecipeList and page.RecipeList.ScrollBox
  if sb and sb.ForEachFrame then pcall(sb.ForEachFrame, sb, UI.DecorateRow) end
end

-- ------------------------------------------------------------------
-- Selected recipe: Craft cost / Sells for / Profit
-- ------------------------------------------------------------------
local function ShowBreakdown(self)
  local res = self.result
  if not res then return end
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  GameTooltip:AddLine(tostring(res.recipe.name), 1, 1, 1)
  for _, p in ipairs(res.parts) do
    local how = p.how and (GRAY .. " (" .. p.how .. ")|r") or ""
    GameTooltip:AddDoubleLine(("%d x %s"):format(p.qty, ns.Costs.ItemName(p.id)),
      p.each and (Money(math.floor(p.each * p.qty + 0.5)) .. how) or (RED .. "no price|r"),
      1, 1, 1, 1, 1, 1)
  end
  GameTooltip:AddDoubleLine("Craft cost", Money(res.cost), 1, 0.82, 0, 1, 1, 1)
  if res.value then
    GameTooltip:AddDoubleLine(("Makes %s, auction value each"):format(tostring(res.made)), Money(res.value),
      1, 0.82, 0, 1, 1, 1)
    GameTooltip:AddDoubleLine(("After the %d%% auction cut"):format(ns.Costs.Cut() * 100), Money(res.net),
      1, 0.82, 0, 1, 1, 1)
  end
  GameTooltip:AddLine("CueTheCashier: reagents at their cheapest of auction, vendor or your own craft.",
    0.5, 0.5, 0.5, true)
  GameTooltip:Show()
end

function UI.UpdateAddButton()
  if not (box and box.add and box.recipeID) then return end
  local n = ns.CraftList.Count(box.recipeID)
  box.add:SetText(n > 0 and ("On list: %d  +"):format(n) or "Add to list")
end

local function BuildBox(form)
  box = CreateFrame("Frame", nil, form)
  box:SetSize(250, 92)
  box.rows = {}
  for i, label in ipairs({ "Craft cost:", "Sells for:", "Profit:" }) do
    local l = box:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    l:SetPoint("TOPLEFT", 0, -(i - 1) * 14)
    l:SetText(label)
    local v = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    v:SetPoint("TOPLEFT", 80, -(i - 1) * 14)
    v:SetJustifyH("LEFT")
    box.rows[i] = v
  end
  box:EnableMouse(true)
  box:SetScript("OnEnter", ShowBreakdown)
  box:SetScript("OnLeave", function() GameTooltip:Hide() end)
  UI.BuildRestock(box)
  -- Add the shown recipe to the Crafting List by hand, profitable or not.
  local skin = CM.Skins:Get()
  -- On the Keep in stock line, right of its box (the price lines above can be long).
  local add = CreateFrame("Button", nil, box, skin.buttonTemplate)
  add:SetSize(110, 20)
  add:SetPoint("TOPLEFT", box, "TOPLEFT", 140, -48)
  add:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  add:SetScript("OnClick", function(_, button)
    local id = box.recipeID
    if not id then return end
    local n = IsShiftKeyDown() and 5 or 1
    ns.CraftList.Add(id, button == "RightButton" and -n or n)
    UI.UpdateAddButton()
  end)
  add:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Add to Crafting List", 1, 1, 1)
    GameTooltip:AddLine("Click: one more. Shift-click: five more. Right-click: one less (Shift: five less). Works for any recipe you know, profitable or not.", nil, nil, nil, true)
    GameTooltip:Show()
  end)
  add:SetScript("OnLeave", function() GameTooltip:Hide() end)
  box.add = add
  return box
end

-- Restock rule of the shown item: Keep in stock [n], Min profit [money].
local function SaveRule()
  local r = box and box.result and box.result.recipe
  if not (r and r.out) or box.loading then return end
  local keep = tonumber(box.keep:GetText() or "") or 0
  local minProfit = MoneyInputFrame_GetCopper and MoneyInputFrame_GetCopper(box.minProfit) or 0
  ns.Restock.Set(r.out, keep, minProfit)
end

function UI.BuildRestock(b)
  local r = CreateFrame("Frame", nil, b)
  r:SetSize(250, 46)
  r:SetPoint("TOPLEFT", 0, -46)
  b.restock = r
  local l1 = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  l1:SetPoint("TOPLEFT", 0, -4)
  l1:SetText("Keep in stock:")
  local keep = CreateFrame("EditBox", nil, r, "InputBoxTemplate")
  keep:SetSize(40, 18)
  keep:SetPoint("LEFT", l1, "LEFT", 86, 0)
  keep:SetAutoFocus(false)
  keep:SetNumeric(true)
  keep:SetMaxLetters(4)
  CM.Skins:StyleInput(keep)
  keep:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  keep:SetScript("OnEditFocusLost", SaveRule)
  keep:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Restock", 1, 1, 1)
    GameTooltip:AddLine("How many of this item to keep, counting all your characters' bags, bank and mail. Craft List > Restock items crafts the rest when the profit is at least Min profit. Empty or 0 = no rule.", nil, nil, nil, true)
    GameTooltip:Show()
  end)
  keep:SetScript("OnLeave", function() GameTooltip:Hide() end)
  b.keep = keep
  local l2 = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  l2:SetPoint("TOPLEFT", 0, -26)
  l2:SetText("Min profit:")
  local ok, money = pcall(CreateFrame, "Frame", "CueTheCashierRestockMinProfit", r, "MoneyInputFrameTemplate")
  if ok and money then
    money:SetPoint("LEFT", l2, "LEFT", 86, 0)
    if MoneyInputFrame_SetOnValueChangedFunc then MoneyInputFrame_SetOnValueChangedFunc(money, SaveRule) end
    b.minProfit = money
  else
    l2:Hide()
  end
end

local function ShowRule(res)
  local r = box.restock
  if not r then return end
  local out = res.recipe.out
  if not out then r:Hide(); return end
  local rule = ns.Restock.Get(out)
  box.loading = true -- filling the boxes must not save
  box.keep:SetText(rule and tostring(rule.keep) or "")
  if box.minProfit and MoneyInputFrame_SetCopper then MoneyInputFrame_SetCopper(box.minProfit, rule and rule.minProfit or 0) end
  box.loading = false
  r:Show()
end

local function Place(form)
  local s = ns.db.settings
  local x, y = s.detailsX or 0, s.detailsY or 0
  box:ClearAllPoints()
  local optional, reagents = form.OptionalReagents, form.Reagents
  local anchor = (type(optional) == "table" and optional:IsShown() and optional)
    or (type(reagents) == "table" and reagents) or nil
  if anchor then
    box:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", x, -12 + y)
  else
    box:SetPoint("BOTTOMLEFT", form, "BOTTOMLEFT", 30 + x, 40 + y)
  end
end

function UI.ShowDetails(form, recipeInfo)
  local id = type(recipeInfo) == "table" and recipeInfo.recipeID
  local res = id and ns.Costs.Recipe(id)
  if not res then
    if box then box:Hide() end
    return
  end
  box = box or BuildBox(form)
  -- Save a rule being typed for the previous recipe before switching.
  if box.keep and box.keep:HasFocus() then box.keep:ClearFocus() end
  Place(form)
  box.result = res
  box.recipeID = id
  UI.UpdateAddButton()
  box.rows[1]:SetText(Money(res.cost) .. (res.complete and "" or (GRAY .. "  (some prices missing)|r")))
  box.rows[2]:SetText(res.value and Money(res.net) or (GRAY .. "no auction price|r"))
  box.rows[3]:SetText(res.profit and ProfitText(res.profit) or (GRAY .. "?|r"))
  ShowRule(res)
  box:Show()
  CM.Debug(("Recipe %s (%d): cost %s%s, sells %s, profit %s."):format(tostring(res.recipe.name), id,
    ns.MoneyText(res.cost), res.complete and "" or " (incomplete)", ns.MoneyText(res.net), ns.MoneyText(res.profit)))
end

-- ------------------------------------------------------------------
-- Hooks
-- ------------------------------------------------------------------
function UI.Hook()
  local page, pf = Page()
  if not page then
    if pf == nil and _G.TradeSkillFrame and not missingLogged then
      missingLogged = true
      CM.Debug("No ProfessionsFrame, but TradeSkillFrame exists: this client has the old profession window.")
    end
    return
  end
  ns.CraftList.HookButton(page)
  local before = tostring(hooked.list) .. tostring(hooked.form)
  local sb = page.RecipeList and page.RecipeList.ScrollBox
  if sb and not hooked.list then
    hooked.list = true
    if ScrollUtil and ScrollUtil.AddInitializedFrameCallback then
      pcall(ScrollUtil.AddInitializedFrameCallback, sb, OnRowInit, UI, true)
    end
    -- Also after every list update (scrolling, filters), in case the
    -- callback above isn't there.
    if sb.Update then hooksecurefunc(sb, "Update", UI.RefreshList) end
  end
  local form = page.SchematicForm
  if form and form.Init and not hooked.form then
    hooked.form = true
    hooksecurefunc(form, "Init", function(f, recipeInfo)
      ns.Safe("Show craft cost", UI.ShowDetails, f, recipeInfo)
    end)
  end
  if before ~= tostring(hooked.list) .. tostring(hooked.form) or not (hooked.list and hooked.form) then
    CM.Debug(("Profession window hooks: recipe list %s, recipe details %s."):format(
      tostring(hooked.list), tostring(hooked.form)))
  end
end

-- New prices or recipes: redraw what is shown.
function UI.Refresh()
  ns.CraftList.Refresh()
  local page, pf = Page()
  if not (pf and pf:IsShown() and page) then return end
  UI.RefreshList()
  local form = page.SchematicForm
  if form and form.GetRecipeInfo then
    local ok, info = pcall(form.GetRecipeInfo, form)
    if ok then UI.ShowDetails(form, info) end
  end
end

function UI.LogStatus()
  local page, pf = Page()
  CM.Log(("Profession window: ProfessionsFrame %s, CraftingPage %s, RecipeList %s, SchematicForm %s. Hooked: list %s, details %s."):format(
    tostring(pf ~= nil), tostring(page ~= nil), tostring(page and page.RecipeList ~= nil),
    tostring(page and page.SchematicForm ~= nil), tostring(hooked.list), tostring(hooked.form)))
  CM.Log("Craft List button: " .. ns.CraftList.ButtonStatus())
end
