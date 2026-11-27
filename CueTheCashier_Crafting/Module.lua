-- CueTheCashier Crafting: the module object.
--
-- "Prof" in CueTheCashier means every trade skill: crafting professions,
-- gathering skills (on Forever, Skinning, Herbalism, Mining and Fishing
-- have recipe windows too) and secondary skills (First Aid, Cooking,
-- Fishing). This module
--   * finds your professions at login (Professions.lua),
--   * reads the recipes of a profession window when you open it
--     (Recipes.lua),
--   * works out what a craft costs and earns (Costs.lua, also the price
--     sources craft.cost, craft.value and craft.profit), and
--   * adds that to Blizzard's own profession window (ProfessionsUI.lua).
-- It talks to the core only through CueTheCashier.API, the event bus and
-- the debug log.
--
-- Saved: CueTheCashierCraftingDB = {
--   recipes = { [recipeID] = recipe facts, shared by all characters },
--   chars = { ["Name - EU Normal - Alliance"] = { profs = {...}, known = {...} } },
--   openers = { [skillLine] = spellID that opened its recipe window },
--   settings = { detailsX, detailsY },
-- }
-- Copyright (C) 2026 Kim. Licensed under the GNU GPL v3 or later; see LICENSE.
local ADDON_NAME, ns = ...
local CM = CueTheCashier
-- 0.42.5: lists keep their scroll spot through CM.SetRows (core Widgets.lua,
-- 0.42.4). If the core folder is older than this module (not every folder
-- copied), stand in for it so lists still work, and say so once.
if not CM.SetRows then
  CM.SetRows = function(box, rows)
    local retain = ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition
    if retain then box:SetDataProvider(CreateDataProvider(rows), retain)
    else box:SetDataProvider(CreateDataProvider(rows)) end
  end
  if not CM.warnedOldCore then
    CM.warnedOldCore = true
    print("|cffff4444CueTheCashier: the CueTheCashier (core) folder is older than CueTheCashier_Crafting. Copy all six folders from the zip.|r")
  end
end

local Module = CM:NewModule("Crafting", { addon = ADDON_NAME, api = 1 })
ns.module = Module

local DB_VERSION = 1

function Module:OnInitialize()
  CueTheCashier.AdoptOldSaved("CueTheCashierCraftingDB")
  if type(CueTheCashierCraftingDB) ~= "table" or (CueTheCashierCraftingDB.dbVersion or 1) > DB_VERSION then
    CueTheCashierCraftingDB = {}
  end
  local db = CueTheCashierCraftingDB
  db.dbVersion = DB_VERSION
  db.recipes = db.recipes or {}
  db.chars = db.chars or {}
  db.openers = db.openers or {}
  db.settings = db.settings or {}
  ns.db = db
  ns.Recipes.BuildIndex()
end

-- This character's saved table (made at login, when the server key is known).
function ns.Char()
  local key = (UnitName("player") or "?") .. " - " .. CM.API.GetServerKey()
  local c = ns.db.chars[key]
  if not c then
    c = { profs = {}, known = {} }
    ns.db.chars[key] = c
  end
  return c, key
end

-- Runs fn; an error goes to the debug log instead of stopping CueTheCashier.
function ns.Safe(label, fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok then CM.Debug(label .. " ERROR: " .. tostring(err)) end
end

-- Runs fn a moment later, once, however often it is asked for meanwhile.
function ns.Debounce(key, delay, fn)
  ns.pending = ns.pending or {}
  if ns.pending[key] then return end
  ns.pending[key] = true
  C_Timer.After(delay, function()
    ns.pending[key] = nil
    ns.Safe(key, fn)
  end)
end

function Module:OnEnable()
  local P, R, UI = ns.Professions, ns.Recipes, ns.UI
  ns.Char()
  P.Discover("login")
  P.CleanOpeners()
  ns.Inventory.Register(self)

  self:RegisterEvent("SKILL_LINES_CHANGED", function() ns.Debounce("Find professions", 1, function() P.Discover("skills changed") end) end)
  self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", function(_, _, unit, _, spellID)
    if unit == "player" then
      P.SpellCast(spellID)
      ns.CraftList.SpellDone(spellID)
      ns.Cooldowns.SpellDone(spellID)
      ns.CraftTimer.SpellDone(spellID)
    end
  end)
  for _, ev in ipairs({ "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_FAILED" }) do
    self:RegisterEvent(ev, function(_, _, unit, _, spellID)
      if unit == "player" then ns.CraftTimer.SpellStopped(spellID) end
    end)
  end
  ns.CraftTimer.Hook()
  self:RegisterEvent("UNIT_SPELLCAST_SENT", function(_, _, unit, _, _, spellID)
    if unit == "player" then P.SpellCast(spellID) end
  end)

  self:RegisterEvent("TRADE_SKILL_SHOW", function()
    P.WindowOpened()
    UI.Hook()
    ns.CraftList.WindowOpened()
    ns.CraftList.PendingCraft() -- a craft clicked on the Task List (0.45.0)
    -- Blizzard may load its profession window on this same event.
    ns.Debounce("Hook profession window", 0.1, UI.Hook)
    ns.Debounce("Read recipes", 0.5, R.Scan)
  end)
  self:RegisterEvent("TRADE_SKILL_CLOSE", function() ns.CraftList.WindowClosed() end)
  -- Names the lists showed as "item 1234" have arrived: draw them again.
  self:RegisterEvent("GET_ITEM_INFO_RECEIVED", function()
    if not ns.namesWanted then return end
    ns.Debounce("Item names", 0.5, function()
      ns.namesWanted = false
      ns.CraftList.Refresh()
      if ns.TaskList then ns.TaskList.Refresh() end
    end)
  end)
  self:RegisterEvent("TRADE_SKILL_LIST_UPDATE", function()
    ns.CraftList.PendingCraft()
    ns.Debounce("Read recipes", 0.5, R.Scan)
    ns.Debounce("Read cooldowns", 0.6, ns.Cooldowns.Scan)
  end)
  self:RegisterEvent("TRADE_SKILL_DATA_SOURCE_CHANGED", function() ns.Debounce("Read recipes", 0.5, R.Scan) end)
  self:RegisterEvent("NEW_RECIPE_LEARNED", function(_, _, recipeID) R.Learned(recipeID) end)
  self:RegisterEvent("ADDON_LOADED", function(_, _, addon)
    if addon == "Blizzard_Professions" then UI.Hook() end
  end)
  UI.Hook() -- in case Blizzard's profession window is already loaded
  ns.Merchant.Register(self)
  ns.TaskList.Register()
  -- The saved craft list's shopping list, once bags are read.
  ns.Debounce("Craft list refresh", 2, ns.CraftList.Refresh)

  -- New prices (a scan, or vendor prices learned at a merchant).
  self:RegisterMessage("CM_PRICES_UPDATED", function() ns.Costs.Changed() end)

  self:RegisterCommand("prof", function(_, rest) ns.Command(rest) end, "/cmp prof [list|queue|tasks [auto]|restock|top|max %|buy|group|vendors|dock|move x y|button x y|top|reset]")
  ns.AddSettings()
  ns.InventoryTab.Register()
  ns.Cooldowns.Register(self)
end

-- Crafting settings on the main window's Settings tab (API minor 2).
function ns.AddSettings()
  local API = CM.API
  if not API.RegisterSettings then return end -- core older than 0.23.0
  local function S() return ns.db.settings end
  API.RegisterSettings("crafting", { title = "Crafting", order = 40, settings = {
    { type = "number", label = "Shopping: % of the list price", min = 50, max = 500,
      tooltip = "The Shopping tab buys auction reagents up to this share of the price the Crafting List counted with (/cmp prof max).",
      get = function() return ns.CraftList.MaxPercent() end,
      set = function(v) S().shopMaxPercent = v; ns.CraftList.Refresh() end },
    { type = "toggle", label = "Open the Task List by itself",
      tooltip = "At the auction house, a mailbox, the bank or a merchant, when there is something to get there (/cmp prof tasks auto).",
      get = function() return S().shopAuto ~= false end,
      set = function(v) S().shopAuto = v end },
  } })
  -- Added to the core's Item tooltips group.
  API.RegisterSettings("tooltip", { settings = {
    { type = "toggle", label = "Craft cost",
      tooltip = "What making the item costs, for items one of your characters can craft.",
      get = function() return S().tooltipCraftCost ~= false end,
      set = function(v) S().tooltipCraftCost = v end },
  } })
end

-- /cmp prof            what CueTheCashier knows about your professions (log)
-- /cmp prof top        the most profitable recipes you know (log)
-- /cmp prof move x y   moves the craft cost box in the profession window
-- /cmp prof list [all|open|restock]   the craft list (rebuilt with all/open/restock)
-- /cmp prof restock    every restock rule and what it would do (log)
-- /cmp prof max <percent>  highest auction price the Shopping tab pays (% of list price)
-- /cmp prof buy        at a merchant: buy the vendor reagents the craft list needs
-- /cmp prof tasks [auto] the Task List (auto: turn opening by itself on/off); "shop" still works
-- /cmp prof group     group for the open profession (Items, Materials)
-- /cmp prof button x y  moves the Craft List button (top / reset: other spot / default)
function ns.Command(rest)
  local cmd, a, b = (rest or ""):lower():match("^(%S*)%s*(%S*)%s*(%S*)")
  if cmd == "max" then
    local pct = tonumber(a)
    if pct and pct >= 50 and pct <= 500 then
      ns.db.settings.shopMaxPercent = pct
      ns.CraftList.Refresh()
    end
    CM.Print(("Shopping buys auction reagents up to %d%% of the price the craft list used. /cmp prof max <percent> changes it."):format(ns.CraftList.MaxPercent()))
    return
  elseif cmd == "tasks" or cmd == "task" or cmd == "shop" then
    if a == "auto" then
      ns.db.settings.shopAuto = ns.db.settings.shopAuto == false
      CM.Print("Task List opens by itself at the auction house, mailbox, bank and merchants: "
        .. (ns.db.settings.shopAuto and "on" or "off") .. ".")
    else
      ns.TaskList.Show()
    end
    return
  elseif cmd == "group" then
    ns.CraftList.MakeGroup() -- same as the Make Group button
    return
  elseif cmd == "queue" then
    ns.GroupPicker.Show()
  elseif cmd == "dock" then
    ns.CraftList.ForgetDock()
  elseif cmd == "vendors" then
    ns.Vendors.Report()
    CM.ShowDebugWindow()
    CM.Print("Known vendors written to the log (/cmp log).")
    return
  elseif cmd == "buy" then
    ns.Merchant.BuyAll()
    return
  elseif cmd == "restock" then
    ns.Restock.Report()
    CM.ShowDebugWindow()
    CM.Print("Restock rules written to the log (/cmp log).")
    return
  elseif cmd == "list" then
    if a == "all" or a == "open" or a == "restock" then ns.CraftList.Open(a) else ns.CraftList.Show() end
    return
  elseif cmd == "button" then
    if a == "top" or a == "bottom" or a == "reset" then
      ns.db.settings.listAnchor = a == "top" and "top" or nil
      if a == "reset" then ns.db.settings.listX, ns.db.settings.listY = 0, 0 end
      local pf = _G.ProfessionsFrame
      ns.CraftList.PlaceButton(pf and pf.CraftingPage)
      CM.Print("Craft List button: " .. ns.CraftList.ButtonStatus())
      return
    end
    local x, y = tonumber(a), tonumber(b)
    if not (x and y) then CM.Print("Usage: /cmp prof button <x> <y> moves the Craft List button (0 0 = default)."); return end
    ns.db.settings.listX, ns.db.settings.listY = x, y
    local pf = _G.ProfessionsFrame
    ns.CraftList.PlaceButton(pf and pf.CraftingPage)
    CM.Print(("Craft List button moved by %d, %d."):format(x, y))
    return
  elseif cmd == "move" then
    local x, y = tonumber(a), tonumber(b)
    if not (x and y) then
      CM.Print(("The craft cost box is moved by %d, %d. Usage: /cmp prof move <x> <y> (0 0 = default)."):format(
        ns.db.settings.detailsX or 0, ns.db.settings.detailsY or 0))
      return
    end
    ns.db.settings.detailsX, ns.db.settings.detailsY = x, y
    ns.UI.Refresh()
    CM.Print(("Craft cost box moved by %d, %d."):format(x, y))
  elseif cmd == "top" then
    ns.Costs.ReportTop(tonumber(a) or 20)
    CM.ShowDebugWindow()
    CM.Print("Most profitable recipes written to the log (/cmp log).")
  else
    ns.Professions.Report()
    CM.ShowDebugWindow()
    CM.Print("Profession report written to the log (/cmp log). /cmp prof top lists your best crafts.")
  end
end
