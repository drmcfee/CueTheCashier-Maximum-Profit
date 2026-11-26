import sys, os, glob
from lupa.lua51 import LuaRuntime

ROOT = sys.argv[1]
HERE = os.path.dirname(os.path.abspath(__file__))

def parse_toc(path):
    meta, files = {}, []
    for line in open(path, encoding="utf-8"):
        line = line.strip()
        if line.startswith("## "):
            k, _, v = line[3:].partition(":")
            meta[k.strip()] = v.strip()
        elif line and not line.startswith("#"):
            files.append(line)
    return meta, files

def new_runtime(disabled=(), legacy=None):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(open(os.path.join(HERE, "mock.lua")).read())
    M = lua.globals()._MOCK
    lua.execute("_BASE = {} for k in pairs(_G) do _BASE[k] = true end")
    names = ["CueTheCashier"] + sorted(os.path.basename(d) for d in glob.glob(os.path.join(ROOT, "CueTheCashier_*")))
    for n in names:
        meta, files = parse_toc(os.path.join(ROOT, n, n + ".toc"))
        lod = meta.get("LoadOnDemand") == "1"
        M.RegisterAddon(n, os.path.join(ROOT, n), lua.table_from(files), lua.table_from(meta), lod)
        if n in disabled:
            M.addons[n].disabled = True
    if legacy:
        lua.execute(legacy)
    return lua, M

def startup(lua, M):
    # WoW loads non-LoD addons in order, each fires ADDON_LOADED, then PLAYER_LOGIN.
    for n in list(M.addonOrder.values()):
        a = M.addons[n]
        if not a.lod and not a.disabled:
            M.LoadFiles(n)
    M.loggedIn = True
    M.FireEvent("PLAYER_LOGIN")
    M.RunTimers(2)

def slash(lua, text):
    lua.globals().SlashCmdList.CRAFTMARKET(text)

def show(lua, label):
    M = lua.globals()._MOCK
    print("=====", label)
    for i in range(1, len(M.printed) + 1):
        print("  print:", M.printed[i])
    errs = len(M.errors)
    for i in range(1, errs + 1):
        print("  ERROR:", M.errors[i])
    lua.execute("_MOCK.printed = {} _MOCK.errors = {}")
    return errs

def leaked(lua):
    return sorted(lua.eval("(function() local t = {} for k in pairs(_G) do if not _BASE[k] then t[#t+1] = k end end table.sort(t) return table.concat(t, ' ') end)()").split())

TOTAL_ERR = 0
def check(lua, label):
    global TOTAL_ERR
    TOTAL_ERR += show(lua, label)

# ---------- Scenario 1: full install, upgrade from 0.13.0 data ----------
LEGACY = """
CueTheCashierDB = { dbVersion = 3, realms = { ["EU Normal - Alliance"] = { lastScan = 1699990000, items = {
  [2318] = { minBuyout = 37, marketValue = 40, median = 41, mean = 42, maxBuyout = 60, quantity = 100, auctions = 5,
             seenInLastScan = true, week = { market = 39, min = 35, n = 3 }, month = { market = 38, min = 34, n = 9 },
             all = { min = 36, market = 41, nMin = 10, nMarket = 10, since = 1 } },
  [10940] = { minBuyout = 5000, marketValue = 5200, seenInLastScan = true } } } },
  settings = { skin = "Blizzard" }, itemInfo = {},
  ledger = { ["EU Normal - Alliance"] = { bought = { { t = 1699990000, id = 2318, name = "Light Leather", qty = 5, money = 200, source = "AH", char = "X" } }, sold = {}, mails = {} } },
  disenchants = { { 1699990000, 1234, 2, 20, 4, { [10940] = 2 } } } }
"""
lua, M = new_runtime(legacy=LEGACY)
startup(lua, M)
check(lua, "login (only core + Destroying loaded)")
print("loaded:", M.loadLog, "| Auctioning", lua.eval("C_AddOns.IsAddOnLoaded('CueTheCashier_Auctioning')"),
      "| Accounting", lua.eval("C_AddOns.IsAddOnLoaded('CueTheCashier_Accounting')"),
      "| Destroying", lua.eval("C_AddOns.IsAddOnLoaded('CueTheCashier_Destroying')"))
print("disenchants moved:", lua.eval("CueTheCashierDB.disenchants == nil and #CueTheCashierDestroyingDB.disenchants"))

slash(lua, "status"); check(lua, "/cm status")
slash(lua, "help"); check(lua, "/cm help")
slash(lua, "sources 2318"); check(lua, "/cm sources 2318")
slash(lua, "dis"); check(lua, "/cm dis")
slash(lua, "price 2318"); check(lua, "/cm price 2318")

# Minimap hover loads Accounting and adds its lines
lua.execute("CueTheCashierMinimapButton.__scripts.OnEnter(CueTheCashierMinimapButton)")
print("tooltip:", list(lua.eval("GameTooltip.lines").values()))
print("ledger moved:", lua.eval("CueTheCashierDB.ledger == nil and #CueTheCashierAccountingDB.ledger['EU Normal - Alliance'].bought"))
check(lua, "minimap hover")

# Auction house opens: Auctioning loads, gets the same AUCTION_HOUSE_SHOW, builds the window.
lua.execute("AuctionHouseFrame = _MOCK.NewWidget('Frame', 'AuctionHouseFrame'); AuctionHouseFrame.CloseButton = _MOCK.NewWidget('Button')")
M.FireEvent("AUCTION_HOUSE_SHOW")
M.RunTimers(3)
print("loaded:", M.loadLog, "| switch button:", lua.eval("CueTheCashierShowCraftTradeButton ~= nil"),
      "| Craft Trade window:", lua.eval("CueTheCashierCraftTradeFrame ~= nil and CueTheCashierCraftTradeFrame:IsShown()"))
check(lua, "AUCTION_HOUSE_SHOW")

# A buyout through the purchase flow: popup -> Accept -> PlaceBid -> message -> ledger
lua.execute("""
  local ns = _MOCK.addons.CueTheCashier_Auctioning.ns
  ns.BuyAuction({ auctionID = 77, amount = 500, itemID = 2318, name = 'Light Leather', ask = 'Buy?', buyout = true })
  local p = _MOCK.popups[#_MOCK.popups]; p.data.accept()
""")
M.FireEvent("AUCTION_HOUSE_PURCHASE_COMPLETED", 77)
print("ledger lines:", lua.eval("#CueTheCashierAccountingDB.ledger['EU Normal - Alliance'].bought"))
check(lua, "buyout recorded in ledger")

# Stack: auto-confirm sends the message before ConfirmCommoditiesPurchase
lua.execute("_MOCK.addons.CueTheCashier_Auctioning.ns.AutoConfirmStack(2318, 10, 'Light Leather', 400, 500)")
M.FireEvent("COMMODITY_PURCHASE_SUCCEEDED")
print("ledger lines:", lua.eval("#CueTheCashierAccountingDB.ledger['EU Normal - Alliance'].bought"))
check(lua, "stack recorded in ledger")

# Each tab selects without errors
for i in range(1, 9):
    lua.execute("_MOCK.addons.CueTheCashier_Auctioning.ns.CraftTrade:SelectTab(%d)" % i)
M.RunTimers(2)
check(lua, "select every tab")

slash(lua, "debug"); M.RunTimers(1); check(lua, "/cm debug (message to Auctioning)")
print("test button gone (0.42):", lua.eval("CueTheCashierTestScanButton == nil"))
slash(lua, "debug"); check(lua, "/cm debug off")
slash(lua, "fullscan"); check(lua, "/cm fullscan")
slash(lua, "button width 140"); check(lua, "/cm button")
slash(lua, "ledger"); check(lua, "/cm ledger")
print("main window shown on ledger:", lua.eval("CueTheCashierMainFrame:IsShown()"), lua.eval("CueTheCashier.MainWindow:Current()"))
slash(lua, "ledger"); print("/cm ledger again closes:", lua.eval("CueTheCashierMainFrame:IsShown()"))

# Scan results go through the API and fire CM_PRICES_UPDATED
lua.execute("""
  _GOT = nil
  CueTheCashier.API.RegisterCallback('test', 'CM_PRICES_UPDATED', function(msg, kind, n) _GOT = kind .. ':' .. n end)
  CueTheCashier.API.RecordScan({ [2318] = { prices = { 30, 10, 35, 5 }, sellers = 2 } }, 'test', 2)
""")
print("message:", lua.eval("_GOT"), "| new min:", lua.eval("CueTheCashier.API.GetPrice(2318, 'auction.min')"))
check(lua, "API.RecordScan")

M.FireEvent("AUCTION_HOUSE_CLOSED"); M.RunTimers(1)
check(lua, "AUCTION_HOUSE_CLOSED")
print("globals added:", leaked(lua))

# ---------- Scenario 2: fresh install, Accounting folder turned off ----------
lua, M = new_runtime(disabled=("CueTheCashier_Accounting",))
startup(lua, M)
check(lua, "fresh login, Accounting off")
lua.execute("CueTheCashierMinimapButton.__scripts.OnEnter(CueTheCashierMinimapButton)")
print("tooltip:", list(lua.eval("GameTooltip.lines").values()))
slash(lua, "ledger")
check(lua, "ledger with Accounting off")
slash(lua, "")
print("main window without Accounting, tabs:", lua.eval("(function() local t = {} for _, b in ipairs(CueTheCashierMainFrame.Tabs) do t[#t+1] = b:GetText() end return table.concat(t, ',') end)()"))
check(lua, "main window with Accounting off")
M.FireEvent("MERCHANT_SHOW"); M.FireEvent("MAIL_SHOW")
check(lua, "merchant + mail with Accounting off")

# ---------- Scenario 3: first event to load Accounting is MERCHANT_SHOW ----------
lua, M = new_runtime()
startup(lua, M)
lua.execute("_MOCK.money = 100000")
M.FireEvent("MERCHANT_SHOW")
print("loaded:", M.loadLog)
lua.execute("_MOCK.money = 90000")
M.FireEvent("PLAYER_MONEY"); M.RunTimers(2)
check(lua, "merchant opened first")

print("TOTAL ERRORS:", TOTAL_ERR)

# ---------- Scenario 4: professions (CueTheCashier_Crafting) ----------
PRICES = """
CueTheCashierDB = { dbVersion = 3, settings = { skin = "Blizzard" }, itemInfo = {}, realms = { ["EU Normal - Alliance"] = {
  lastScan = 1699990000, items = {
  [2318] = { minBuyout = 37, marketValue = 40, seenInLastScan = true },   -- Light Leather
  [2320] = { minBuyout = 30, marketValue = 30, seenInLastScan = true },   -- Coarse Thread: vendor 10c is cheaper
  [2304] = { minBuyout = 180, marketValue = 200, seenInLastScan = true }, -- Light Armor Kit
  [2302] = { minBuyout = 450, marketValue = 500, seenInLastScan = true }, -- Handstitched Boots
  [783]  = { minBuyout = 90, marketValue = 100, seenInLastScan = true },  -- Light Hide
  [5000] = { minBuyout = 1900, marketValue = 2000, seenInLastScan = true },
  [4444] = { minBuyout = 10, marketValue = 10, seenInLastScan = true },
} } } }
"""
PROF_MOCK = """
for id, n in pairs({ [2320] = 'Coarse Thread', [2304] = 'Light Armor Kit', [2302] = 'Handstitched Leather Boots',
  [783] = 'Light Hide', [4231] = 'Cured Light Hide', [4289] = 'Salt', [5000] = 'Test Bag' }) do
  _MOCK.items[id] = { n, 1, 10, 1 }
end
Enum.SpellBookSpellBank = { Player = 0 }
Enum.CraftingReagentType = { Modifying = 0, Finishing = 1, Basic = 2 }
local PROFS = { { 'Leatherworking', 165, 120, 150, 1, 10 }, { 'Skinning', 393, 100, 150, 2, 20 }, nil, nil, nil, { 'First Aid', 129, 50, 75, 1, 30 } }
function GetProfessions() return 1, 2, nil, nil, nil, 6 end
function GetProfessionInfo(i) local p = PROFS[i]; return p[1], 0, p[3], p[4], p[5], p[6], p[2] end
local BOOK = { [11] = { spellID = 3104, name = 'Leatherworking' }, [21] = { spellID = 1278068, name = 'Tanning' },
  [22] = { spellID = 8617, name = 'Skinning', isPassive = true }, [31] = { spellID = 3274, name = 'First Aid' } }
C_SpellBook = { GetSpellBookItemInfo = function(i) return BOOK[i] end }
C_Spell = { GetSpellName = function(id) return 'Spell' .. id end }
local function Slot(id, qty) return { reagents = { { itemID = id } }, quantityRequired = qty, required = true, reagentType = 2 } end
local R = {
  [100] = { name = 'Light Armor Kit', out = 2304, slots = { Slot(2318, 1) }, learned = true },
  [101] = { name = 'Handstitched Leather Boots', out = 2302, slots = { Slot(2318, 2), Slot(2320, 1),
            { reagents = { { itemID = 9999 } }, quantityRequired = 1, required = false, reagentType = 0 } }, learned = true },
  [102] = { name = 'Enchant Something', slots = { Slot(2318, 1) }, learned = true },
  [103] = { name = 'Cured Light Hide', out = 4231, slots = { Slot(783, 1), Slot(4289, 1) }, learned = true },
  [104] = { name = 'Test Bag', out = 5000, slots = { Slot(4231, 2), Slot(4444, 1) }, learned = true },
  [105] = { name = 'Unlearned Thing', out = 2304, slots = { Slot(2318, 9) }, learned = false },
}
_MOCK.profLine = 165
C_TradeSkillUI = {
  IsTradeSkillReady = function() return true end,
  IsTradeSkillLinked = function() return false end,
  GetBaseProfessionInfo = function() return { professionID = _MOCK.profLine, professionName = 'Leatherworking', skillLevel = 120, maxSkillLevel = 150 } end,
  GetAllRecipeIDs = function() return { 100, 101, 102, 103, 104, 105 } end,
  GetRecipeInfo = function(id) local r = R[id]; return r and { recipeID = id, name = r.name, learned = r.learned } end,
  GetRecipeSchematic = function(id) local r = R[id]; return r and { recipeID = id, outputItemID = r.out, quantityMin = 1,
    quantityMax = 1, reagentSlotSchematics = r.slots, name = r.name } end,
}
-- Blizzard's retail-style profession window
local function Row(id)
  local row = _MOCK.NewWidget('Button'); row.Label = _MOCK.NewWidget('FontString'); row.SkillUps = _MOCK.NewWidget('Frame')
  row.GetElementData = function() return { GetData = function() return { recipeInfo = R[id] and { recipeID = id } } end } end
  return row
end
local rows = { Row(100), Row(101), Row(102), Row(104) }
local sb = _MOCK.NewWidget('Frame')
sb.Update = function() end
sb.ForEachFrame = function(self, fn) for _, r in ipairs(rows) do fn(r) end end
local form = _MOCK.NewWidget('Frame'); form.Reagents = _MOCK.NewWidget('Frame')
form.Init = function(self, info) self.info = info end
form.GetRecipeInfo = function(self) return self.info end
_MOCK.rows = rows
_MOCK.LoadBlizzardProfessions = function()
  ProfessionsFrame = _MOCK.NewWidget('Frame', 'ProfessionsFrame')
  ProfessionsFrame.CraftingPage = { RecipeList = { ScrollBox = sb }, SchematicForm = form }
  _MOCK.FireEvent('ADDON_LOADED', 'Blizzard_Professions')
end
"""
lua, M = new_runtime(legacy=PRICES)
lua.execute(PROF_MOCK)
startup(lua, M)
check(lua, "login with Crafting")
print("profs:", lua.eval("(function() local t = {} for k, p in pairs(select(1, _MOCK.addons.CueTheCashier_Crafting.ns.Char()).profs) do t[#t+1] = k .. '=' .. p.name .. '/' .. #p.spells end table.sort(t) return table.concat(t, ' ') end)()"))
lua.execute("_MOCK.LoadBlizzardProfessions()")
M.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 3104)
M.FireEvent("TRADE_SKILL_SHOW"); M.RunTimers(3)
check(lua, "open Leatherworking")
print("known:", lua.eval("(function() local t = {} for k in pairs(select(1, _MOCK.addons.CueTheCashier_Crafting.ns.Char()).known) do t[#t+1] = k end table.sort(t) return table.concat(t, ',') end)()"),
      "| opener 165:", lua.eval("CueTheCashierCraftingDB.openers[165]"),
      "| boots reagents:", lua.eval("#CueTheCashierCraftingDB.recipes[101].reagents"))
lua.execute("ProfessionsFrame.CraftingPage.SchematicForm:Init({ recipeID = 101 })")
M.RunTimers(1)
print("details box:", lua.eval("(function() local ns = _MOCK.addons.CueTheCashier_Crafting.ns; local f = ProfessionsFrame.CraftingPage.SchematicForm; for _, w in ipairs(_MOCK.allFrames) do if w.rows and w.__parent == f then return w.rows[1]:GetText() .. ' || ' .. w.rows[2]:GetText() .. ' || ' .. w.rows[3]:GetText() end end return 'none' end)()"))
lua.execute("ProfessionsFrame.CraftingPage.RecipeList.ScrollBox:Update()")
for i in range(1, 5):
    print("row", i, lua.eval("_MOCK.rows[%d].cmProfit and _MOCK.rows[%d].cmProfit:IsShown() and _MOCK.rows[%d].cmProfit:GetText() or '-'" % (i, i, i)))
check(lua, "window decorated")
for src in ["craft.cost", "craft.value", "craft.profit"]:
    print(src, "boots", lua.eval("CueTheCashier.API.GetPrice(2302, '%s')" % src), "bag", lua.eval("CueTheCashier.API.GetPrice(5000, '%s')" % src),
          "leather", lua.eval("CueTheCashier.API.GetPrice(2318, '%s')" % src))
# Tanning window opened by its spell: the opener is learned for Skinning.
lua.execute("_MOCK.profLine = 393")
M.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 1278068)
M.FireEvent("TRADE_SKILL_SHOW"); M.RunTimers(3)
print("opener 393:", lua.eval("CueTheCashierCraftingDB.openers[393]"))
lua.execute("_MOCK.profLine = 165")
slash(lua, "prof"); slash(lua, "prof top"); slash(lua, "prof move 5 -10"); slash(lua, "prof move")
check(lua, "/cm prof commands")
print("LOG:\n  " + "\n  ".join(lua.eval("CueTheCashierDebugFrame and CueTheCashierDebugFrame.edit and CueTheCashierDebugFrame.edit:GetText() or 'no window'").split("\n")[-22:]))
# Tooltip line
lua.execute("GameTooltip.lines = {}; _MOCK.tooltipPost(GameTooltip, { id = 5000 })")
print("tooltip:", list(lua.eval("GameTooltip.lines").values()))
# Merchant with a reagent missing from the table
lua.execute("""
  _MOCK.items[7777] = { 'New Reagent', 1, 10, 1 }
  local gi = C_Item.GetItemInfo
  C_Item.GetItemInfo = function(id) if id == 7777 then return 'New Reagent', nil, 1, 10, 1, 'Trade', 'x', 20, '', 1, 1, 7, 0, 0, 0, 0, true end return gi(id) end
  function GetMerchantNumItems() return 1 end
  function GetMerchantItemID() return 7777 end
  function GetMerchantItemInfo() return 'New Reagent', 0, 25, 1, 5, true, false, false end
""")
M.FireEvent("MERCHANT_SHOW"); M.RunTimers(2)
print("learned vendor reagent 7777:", lua.eval("CueTheCashier.API.GetPrice(7777, 'vendor.buy')"))
check(lua, "merchant reagent")
slash(lua, "debug"); M.FireEvent("TRADE_SKILL_SHOW"); M.RunTimers(3)
lua.execute("ProfessionsFrame.CraftingPage.SchematicForm:Init({ recipeID = 104 })")
print("debug log tail:\n  " + "\n  ".join(lua.eval("CueTheCashierDebugFrame.edit:GetText()").split("\n")[-8:]))
check(lua, "debug-mode prof logging")
# Craft list
lua.execute("ProfessionsFrame.CraftingPage.CreateAllButton = _MOCK.NewWidget('Button')")
lua.execute("_MOCK.counts = { [2318] = 1 }; C_Item.GetItemCount = function(id) return _MOCK.counts[id] or 0 end")
slash(lua, "prof list open"); check(lua, "prof list open")
lua.execute("""
  local f = CueTheCashierCraftListFrame; _OUT = {}
  for _, r in ipairs(f.rows) do if r:IsShown() then _OUT[#_OUT+1] = r.left:GetText() .. ' | ' .. r.right:GetText() end end
  _OUT[#_OUT+1] = f.totals:GetText()
""")
print("craft list:\n  " + "\n  ".join(lua.eval("table.concat(_OUT, '\\n')").split("\n")))
lua.execute("for _, r in ipairs(CueTheCashierCraftListFrame.rows) do if r.line and r.line.left and r.line.left:find('Test Bag') then r.__scripts.OnClick(r, 'LeftButton') end end")
lua.execute("for _, r in ipairs(CueTheCashierCraftListFrame.rows) do if r.line and r.line.left and r.line.left:find('Light Armor') then r.__scripts.OnClick(r, 'RightButton') end end")
print("queue after click:", lua.eval("(function() local t = {} for k, v in pairs(select(1, _MOCK.addons.CueTheCashier_Crafting.ns.Char()).queue) do t[#t+1] = k .. '=' .. v end table.sort(t) return table.concat(t, ' ') end)()"))
lua.execute("C_TradeSkillUI.CraftRecipe = function(id, n) _CRAFTED = id .. 'x' .. n end; local gi = C_TradeSkillUI.GetRecipeInfo; C_TradeSkillUI.GetRecipeInfo = function(id) local i = gi(id); if i then i.numAvailable = 3 end return i end")
lua.execute("CueTheCashierCraftListFrame.craftButton.__scripts.OnClick()")
print("crafted:", lua.eval("_CRAFTED"))
lua.execute("C_TradeSkillUI.GetRecipeInfo = gi_orig or C_TradeSkillUI.GetRecipeInfo; _CRAFTED = nil")
lua.execute("local gi = C_TradeSkillUI.GetRecipeInfo; C_TradeSkillUI.GetRecipeInfo = function(id) local i = gi(id); if i then i.numAvailable = nil end return i end")
lua.execute("_MOCK.counts = { [2318] = 40, [4444] = 5, [2320] = 5, [783] = 9 }")
lua.execute("CueTheCashierCraftListFrame.craftButton.__scripts.OnClick()")
print("crafted without numAvailable (bags):", lua.eval("_CRAFTED"))
lua.execute("_MOCK.counts = {}; _CRAFTED = nil")
lua.execute("CueTheCashierCraftListFrame.craftButton.__scripts.OnClick()")
print("empty bags, log:", [l[:140] for l in lua.eval("CueTheCashierDebugFrame.edit:GetText()").split("\n")[-3:]])
M.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 104)
print("queue after craft:", lua.eval("(function() local t = {} for k, v in pairs(select(1, _MOCK.addons.CueTheCashier_Crafting.ns.Char()).queue) do t[#t+1] = k .. '=' .. v end table.sort(t) return table.concat(t, ' ') end)()"))
slash(lua, "prof list all"); slash(lua, "prof button 3 4")
lua.execute("""
  local API = CueTheCashier.API
  API.CreateOperation('craft', 'Twenty')
  API.SetOperationValue('craft', 'Twenty', 'maxCraft', 20)
  API.SetOperationValue('craft', 'Twenty', 'minProfit', '1c')
  API.SetGroupOperation(0, 'craft', 'Twenty')
  local ns = _MOCK.addons.CueTheCashier_Crafting.ns
  ns.CraftList.Build(nil)
  local t = {} for k, v in pairs(ns.Char().queue) do t[#t+1] = k .. '=' .. v end table.sort(t)
  _Q1 = table.concat(t, ' ')
  API.SetOperationValue('craft', 'Twenty', 'keepInStock', 3)
  ns.CraftList.Build(nil)
  t = {} for k, v in pairs(ns.Char().queue) do t[#t+1] = k .. '=' .. v end table.sort(t)
  _Q2 = table.concat(t, ' ')
  wipe(ns.Char().queue); ns.Restock.Fill(ns.Char().queue)
  t = {} for k, v in pairs(ns.Char().queue) do t[#t+1] = k .. '=' .. v end table.sort(t)
  _Q3 = table.concat(t, ' ')
  API.SetGroupOperation(0, 'craft', nil)
""")
print("craft op max 20:", lua.eval("_Q1"), "| keep 3:", lua.eval("_Q2"), "| restock:", lua.eval("_Q3"))
check(lua, "crafting operation counts")
print("list button:", lua.eval("(function() for _, w in ipairs(_MOCK.allFrames) do if w.__text == 'Craft List' then return 'found' end end return 'none' end)()"))
lua.execute("ProfessionsFrame.CraftingPage.SchematicForm:Init({ recipeID = 101 })")
check(lua, "craft list")
# 0.42: rows keep their place, AH supply question, queue timer, saved dock spot
lua.execute("""
  local ns = _MOCK.addons.CueTheCashier_Crafting.ns
  local q = ns.Char().queue
  wipe(q)
  local ids = {}
  for id in pairs(ns.Char().known) do ids[#ids+1] = id end
  table.sort(ids)
  for i, id in ipairs(ids) do q[id] = 3 end
  local function Order() local t = {} for _, c in ipairs(ns.CraftList.Summary().crafts) do if not c.forReagent then t[#t+1] = c.id end end return table.concat(t, ',') end
  _O1 = Order()
  local first = ns.CraftList.Summary().crafts[#ns.CraftList.Summary().crafts].id
  q[first] = 1
  _O2 = Order()
  q[first] = 9
  _O3 = Order()
  -- supply: only 1 of each auction reagent for sale
  local API = CueTheCashier.API
  local real = API.GetAuctionSupply
  API.GetAuctionSupply = function() return 1, true end
  wipe(q)
  ns.Char().known[ids[1]] = true
  ns.CraftList.Add(ids[1], 5)
  local f = CueTheCashierChooseFrame
  _CH = tostring(f and f:IsShown())
  _CHB = {}
  if f then for _, b in ipairs(f.buttons) do if b:IsShown() then _CHB[#_CHB+1] = b:GetText() end end end
  _CHT = f and f.text:GetText() or ''
  if f then f.buttons[2].__scripts.OnClick(f.buttons[2]) end
  _QA = tostring(q[ids[1]])
  API.GetAuctionSupply = real
  -- timer
  UnitCastingInfo = function() return 'x', nil, nil, _MOCK.now * 1000, _MOCK.now * 1000 + 3000, nil, nil, nil, 77 end
  ns.CraftTimer.Start(77, 4)
""")
M.RunTimers(1)
lua.execute("""
  local ns = _MOCK.addons.CueTheCashier_Crafting.ns
  _T1 = tostring(CueTheCashierCraftTimer:IsShown()) .. ' ' .. tostring(ns.CraftTimer.label:GetText())
  for i = 1, 4 do ns.CraftTimer.SpellDone(77) end
  _T2 = tostring(CueTheCashierCraftTimer:IsShown())
  UnitCastingInfo = nil
""")
lua.execute("""
  local ns = _MOCK.addons.CueTheCashier_Crafting.ns
  local pf = ProfessionsFrame
  pf:Show()
  pf.GetRight = function() return 500 end; pf.GetTop = function() return 700 end; pf.GetBottom = function() return 100 end
  local tab = _MOCK.NewWidget('Frame', 'ProfTabs'); tab:Show()
  tab.GetLeft = function() return 497 end; tab.GetRight = function() return 560 end
  tab.GetTop = function() return 650 end; tab.GetBottom = function() return 300 end
  pf.GetChildren = function() return tab end
  ns.db.settings.listDock = nil
  ns.CraftList.Dock()
  _DX = tostring(ns.CraftList.dockX)
  local w = CueTheCashierCraftListFrame
  w.GetLeft = function() return 600 end; w.GetTop = function() return 690 end
  w.__scripts.OnDragStop(w)
  local ld = ns.db.settings.listDock; _DS = ld and (ld.x .. ',' .. ld.y) or ('nil: ' .. (CueTheCashierDebugFrame and CueTheCashierDebugFrame.edit:GetText():sub(-300) or ''))
  pf.GetChildren = function() return end
""")
_MOCK_RUN = M.RunTimers(2)
print("0.42.1 dock x past the tab bar (want 62):", lua.eval("_DX"), "| saved after drag (want 100,-10):", lua.eval("_DS"))
lua.execute("""
  local ns = _MOCK.addons.CueTheCashier_Crafting.ns
  local API = CueTheCashier.API
  local g = API.CreateGroup('Kits')
  local sub = API.CreateGroup('Light', g)
  local any
  for id in pairs(ns.Char().known) do local r = ns.db.recipes[id]; if r and r.out then any = r.out; API.AddItemToGroup(sub, r.out) break end end
  wipe(ns.Char().queue)
  ns.GroupPicker.Show()
  local f = CueTheCashierQueueFrame
  _GP1 = tostring(f.go:IsEnabled()) .. ' rows ' .. #f.rows .. ' keys ' .. (function() local t = {} for _, r in ipairs(f.rows) do t[#t+1] = tostring(r.key) end return table.concat(t, ',') end)() .. ' g=' .. tostring(g)
  for _, row in ipairs(f.rows) do if row.key == g then row.check.GetChecked = function() return true end; row.check.__scripts.OnClick(row.check) end end
  _GP2 = tostring(f.go:IsEnabled()) .. ' ' .. f.info:GetText()
  f.go.__scripts.OnClick(f.go)
  local t = {} for k, v in pairs(ns.Char().queue) do local r = ns.db.recipes[k]; t[#t+1] = tostring(r and r.out == any) end
  _GP3 = table.concat(t, ',')
  wipe(ns.Char().queue)
""")
print("0.42.2 queue window: enabled before", lua.eval("_GP1"), "| after tick", lua.eval("_GP2"), "| queued only group items:", lua.eval("_GP3"))
print("0.42 order:", lua.eval("_O1"), "| after one less:", lua.eval("_O2"), "| after more:", lua.eval("_O3"))
print("0.42 supply ask:", lua.eval("_CH"), lua.eval("table.concat(_CHB, ' / ')"), "| queued after 'Only':", lua.eval("_QA"))
print("  text:", lua.eval("_CHT").replace("\n", " // "))
print("0.42 timer label:", lua.eval("_T1"), "| shown after done:", lua.eval("_T2"))
check(lua, "0.42 crafting list order, supply, timer")
# Restock + where to get materials (alt and mail)
lua.execute("""
  local ns = _MOCK.addons.CueTheCashier_Crafting.ns
  ns.db.chars['Altie - EU Normal - Alliance'] = { profs = {}, known = {}, inv = { bags = { [783] = 1 }, bank = {}, mail = { [2304] = 1 } } }
  ns.db.chars['Other - EU PvP - Horde'] = { profs = {}, known = {}, inv = { bags = { [783] = 50 }, bank = {}, mail = {} } }
  function GetInboxNumItems() return 1 end
  function GetInboxItem(i, a) if a == 1 then return 'Salt', 4289, 0, 2 end end
""")
M.FireEvent("MAIL_INBOX_UPDATE"); M.RunTimers(2)
lua.execute("ProfessionsFrame.CraftingPage.SchematicForm:Init({ recipeID = 100 })")
lua.execute("""
  local ns = _MOCK.addons.CueTheCashier_Crafting.ns
  local f = ProfessionsFrame.CraftingPage.SchematicForm
  for _, w in ipairs(_MOCK.allFrames) do if w.keep and w.__parent == f then _BOX = w end end
  _BOX.keep:SetText('5'); _BOX.keep.__scripts.OnEditFocusLost(_BOX.keep)
  ns.Restock.Set(5000, 2, 100000) -- bag: min profit 10g, too high
""")
print("rule 2304:", lua.eval("CueTheCashierCraftingDB.restock[2304].keep"), lua.eval("CueTheCashierCraftingDB.restock[2304].minProfit"))
lua.execute("_MOCK.counts = { [2304] = 1 }")
slash(lua, "prof list restock")
lua.execute("""
  local f = CueTheCashierCraftListFrame; _OUT = {}
  for _, r in ipairs(f.rows) do if r:IsShown() then _OUT[#_OUT+1] = r.left:GetText() .. ' | ' .. r.right:GetText() end end
""")
print("restock list:\n  " + "\n  ".join(lua.eval("table.concat(_OUT, '\\n')").split("\n")))
slash(lua, "prof list open"); slash(lua, "prof shop")
lua.execute("""
  local f = CueTheCashierShoppingListFrame; _OUT = {}
  for _, r in ipairs(f.rows) do if r:IsShown() then _OUT[#_OUT+1] = r.left:GetText() .. ' | ' .. r.right:GetText() end end
  _OUT[#_OUT+1] = f.totals:GetText()
  local row; for _, r in ipairs(f.rows) do if r:IsShown() and r.line and r.line.itemID == 783 then row = r end end
  GameTooltip.lines = {}
  if row then row.__scripts.OnEnter(row) end
""")
print("shopping list:\n  " + "\n  ".join(lua.eval("table.concat(_OUT, '\\n')").split("\n")))
print("hover Light Hide:", list(lua.eval("GameTooltip.lines").values()))
slash(lua, "prof restock"); slash(lua, "prof button top"); slash(lua, "prof button reset")
print("LOG tail:\n  " + "\n  ".join(lua.eval("CueTheCashierDebugFrame.edit:GetText()").split("\n")[-6:]))
check(lua, "restock and sources")
# Shopping: list published to the core, Shopping tab, merchant
slash(lua, "prof list open"); M.RunTimers(2)
print("shopping auction:", lua.eval("(function() local t = {} for id, e in pairs(CueTheCashier.API.GetShoppingList('auction')) do t[#t+1] = id .. 'x' .. e.quantity .. '<=' .. e.maxPrice end table.sort(t) return table.concat(t, ' ') end)()"))
print("shopping vendor:", lua.eval("(function() local t = {} for id, e in pairs(CueTheCashier.API.GetShoppingList('vendor')) do t[#t+1] = id .. 'x' .. e.quantity end table.sort(t) return table.concat(t, ' ') end)()"))
lua.execute("""
  AuctionHouseFrame = AuctionHouseFrame or _MOCK.NewWidget('Frame', 'AuctionHouseFrame'); AuctionHouseFrame.CloseButton = _MOCK.NewWidget('Button')
  C_AuctionHouse.GetItemKeyInfo = function(k) return { isCommodity = true, itemName = 'Item' .. k.itemID } end
""")
M.FireEvent("AUCTION_HOUSE_SHOW"); M.RunTimers(3)
lua.execute("_MOCK.addons.CueTheCashier_Auctioning.ns.CraftTrade:SelectTab(7)")
lua.execute("_MOCK.addons.CueTheCashier_Auctioning.ns.ShoppingTab:Toggle('shop')")
lua.execute("""
  local tab = _MOCK.addons.CueTheCashier_Auctioning.ns.ShoppingTab
  _SROWS = {} for _, r in ipairs(tab.state.rows) do _SROWS[#_SROWS+1] = r.itemID .. ' need ' .. r.need .. ' max ' .. r.maxPrice end
  table.sort(_SROWS)
  -- Light Leather listings: 5 at 45c, 10 at 60c (max is 48c)
  local leather; for _, r in ipairs(tab.state.rows) do if r.itemID == 2318 then leather = r end end
  C_AuctionHouse.GetNumCommoditySearchResults = function() return 2 end
  C_AuctionHouse.GetCommoditySearchResultInfo = function(id, i) return ({ { unitPrice = 45, quantity = 5 }, { unitPrice = 60, quantity = 10 } })[i] end
  tab:Select(leather)
  _MOCK.FireEvent('COMMODITY_SEARCH_RESULTS_UPDATED', 2318)
  _LEATHER = leather
""")
print("shopping rows:", list(lua.eval("_SROWS").values()))
print("leather under max:", lua.eval("_LEATHER.qty"), "| qty box:", lua.eval("CueTheCashierShoppingQuantity:GetText()"),
      "| detail:", lua.eval("_MOCK.addons.CueTheCashier_Auctioning.ns.ShoppingTab.tab.detail:GetText()"))
lua.execute("_MOCK.addons.CueTheCashier_Auctioning.ns.ShoppingTab:Buy()")
print("popup:", lua.eval("_MOCK.popups[#_MOCK.popups].text"))
check(lua, "shopping tab")
# Merchant sells Coarse Thread (needed 1) and Salt
lua.execute("""
  MerchantFrame = _MOCK.NewWidget('Frame', 'MerchantFrame')
  local items = { { 2320, 10, 1 }, { 4289, 50, 1 }, { 159, 5, 1 } }
  function GetMerchantNumItems() return #items end
  function GetMerchantItemID(i) return items[i][1] end
  function GetMerchantItemInfo(i) return 'x', 0, items[i][2], items[i][3], -1, true, false, false end
  function GetMerchantItemMaxStack() return 20 end
  _BOUGHT = {}
  function BuyMerchantItem(i, n) _BOUGHT[#_BOUGHT+1] = items[i][1] .. 'x' .. tostring(n) end
""")
lua.execute("""
  function UnitGUID(u) if u == 'npc' then return 'Creature-0-1-2-3-3366-0000' end end
  local UnitName0 = UnitName
  function UnitName(u) if u == 'npc' then return 'Tamar' end return UnitName0(u) end
  _MOCK.map = 1453
  C_Map = { GetBestMapForUnit = function() return _MOCK.map end,
    GetPlayerMapPosition = function() return { GetXY = function() return 0.62, 0.71 end } end,
    GetWorldPosFromMapPos = function(m, v) return 0, { GetXY = function() return v.x * 1000 + m, v.y * 1000 end } end,
    GetMapInfo = function(m) return { name = 'Stormwind' } end,
    SetUserWaypoint = function(p) _PIN = p.uiMapID .. ' ' .. p.position.x .. ' ' .. p.position.y end }
  CreateVector2D = function(x, y) return { x = x, y = y } end
  UiMapPoint = { CreateFromCoordinates = function(m, x, y) return { uiMapID = m, position = { x = x, y = y } } end }
  C_SuperTrack = { SetSuperTrackedUserWaypoint = function(v) _SUPER = v end }
""")
M.FireEvent("MERCHANT_SHOW"); M.RunTimers(2)
print("vendor saved:", lua.eval("(function() local v = CueTheCashierCraftingDB.vendors[3366]; return v and (v.name .. ' map ' .. v.map .. ' sells thread ' .. tostring(v.items[2320])) end)()"))
slash(lua, "prof buy")
print("merchant popup:", lua.eval("_MOCK.popups[#_MOCK.popups].text"))
lua.execute("_MOCK.popups[#_MOCK.popups].data.accept()")
print("bought:", list(lua.eval("_BOUGHT").values()))
check(lua, "merchant buy")
# Click a reagent in the craft list with the AH open: Shopping tab buys it
lua.execute("MerchantFrame:Hide(); AuctionHouseFrame:Show(); _MOCK.popups = {}")
lua.execute("""
  local tab = _MOCK.addons.CueTheCashier_Auctioning.ns.ShoppingTab
  tab.state.rows = {}; tab.state.finishedAt = nil; tab.state.buying = false
  local row; for _, r in ipairs(CueTheCashierShoppingListFrame.rows) do if r:IsShown() and r.line and r.line.itemID == 2318 and r.line.onClick then row = r end end
  row.__scripts.OnClick(row, 'LeftButton')
""")
M.RunTimers(3)
lua.execute("_MOCK.FireEvent('COMMODITY_SEARCH_RESULTS_UPDATED', 2318)")
print("dbg:", lua.eval("(function() local t = _MOCK.addons.CueTheCashier_Auctioning.ns.ShoppingTab; return tostring(#t.state.rows) .. ' sel ' .. tostring(t.state.selected and t.state.selected.itemID) .. ' auto ' .. tostring(t.autoBuy) .. ' qty ' .. tostring(t.state.selected and t.state.selected.qty) .. ' buying ' .. tostring(t.state.buying) end)()"), list(lua.eval("_MOCK.printed").values()))
print("auto popup:", lua.eval("_MOCK.popups[#_MOCK.popups] and _MOCK.popups[#_MOCK.popups].text"))
check(lua, "reagent click buys")
# A CueTheCashier AH buy counts as in the mailbox until the mailbox is opened
lua.execute("_MOCK.addons.CueTheCashier_Crafting.ns.Inventory.Bought(2318, 5)")
print("leather where after buy:", lua.eval("(function() local w = _MOCK.addons.CueTheCashier_Crafting.ns.Inventory.Where(2318) return 'mail ' .. w.mail .. ' total ' .. w.total end)()"))
lua.execute("_MOCK.addons.CueTheCashier_Crafting.ns.ShoppingList.Hide(); AuctionHouseFrame:Hide()")
M.FireEvent("AUCTION_HOUSE_CLOSED"); M.FireEvent("MAIL_SHOW"); M.RunTimers(2)
print("shopping list auto-open at mailbox:", lua.eval("CueTheCashierShoppingListFrame:IsShown()"))
M.FireEvent("MAIL_CLOSED")
print("still open after mailbox closed:", lua.eval("CueTheCashierShoppingListFrame:IsShown()"))
lua.execute("function ToggleGameMenu() _MENU = true end")
M.FireEvent("ADDON_LOADED", "Blizzard_GameMenuEsc")
lua.execute("ToggleGameMenu()")
print("escape opens game menu:", lua.eval("_MENU"))
print("escape closes it:", lua.eval("not CueTheCashierShoppingListFrame:IsShown()"))
lua.execute("CueTheCashierShoppingListFrame:Hide(); CueTheCashierMinimapButton.__scripts.OnClick(CueTheCashierMinimapButton, 'RightButton')")
print("minimap right-click opens it:", lua.eval("CueTheCashierShoppingListFrame:IsShown()"))
print("not in UISpecialFrames:", lua.eval("(function() for _, n in ipairs(UISpecialFrames) do if n:find('List') or n:find('CraftTrade') then return false end end return true end)()"))
M.FireEvent("TRADE_SKILL_CLOSE")
print("craft list hidden with prof window:", lua.eval("not CueTheCashierCraftListFrame:IsShown()"))
M.FireEvent("TRADE_SKILL_SHOW"); M.RunTimers(3)
print("craft list shown with prof window:", lua.eval("CueTheCashierCraftListFrame:IsShown()"))
lua.execute("""
  _OUT = {}
  for _, r in ipairs(CueTheCashierCraftListFrame.rows) do if r:IsShown() and r.line.header then _OUT[#_OUT+1] = r.line.header .. ' skill ' .. tostring(r.line.skill) end end
""")
print("profession titles:", lua.eval("table.concat(_OUT, ', ')"))
lua.execute("_CRAFTED = nil; _MOCK.counts = { [2318] = 40, [4444] = 5, [2320] = 5, [783] = 9 }")
lua.execute("""
  for _, r in ipairs(CueTheCashierCraftListFrame.rows) do if r:IsShown() and r.line.skill == 165 then r.__scripts.OnClick(r, 'LeftButton') end end
""")
print("title click crafts:", lua.eval("_CRAFTED"))
lua.execute("""
  local ns = _MOCK.addons.CueTheCashier_Crafting.ns
  CueTheCashierCraftingDB.recipes[900] = { name = 'Spiced Wolf Meat', skill = 185, out = 2680, q1 = 1, q2 = 1, reagents = { { id = 2672, qty = 1 } } }
  ns.Char().profs[185] = { name = 'Cooking', spells = { { id = 2550 } } }
  ns.Char().queue[900] = 2
  ns.CraftList.Refresh()
  _OUT = {}
  for _, r in ipairs(CueTheCashierCraftListFrame.rows) do if r:IsShown() and r.line.header then _OUT[#_OUT+1] = r.line.header end end
  C_TradeSkillUI.OpenTradeSkill = function(s) _OPENED = s end
  for _, r in ipairs(CueTheCashierCraftListFrame.rows) do if r:IsShown() and r.line.skill == 185 then r.__scripts.OnClick(r, 'LeftButton') end end
  -- bad saved openers get cleaned
  CueTheCashierCraftingDB.openers = { [165] = 104, [356] = 1278068, [393] = 1278068, [185] = 2550 }
  ns.Professions.CleanOpeners()
  _OP = {} for k, v in pairs(CueTheCashierCraftingDB.openers) do _OP[#_OP+1] = k .. '=' .. v end table.sort(_OP)
""")
print("titles with cooking:", lua.eval("table.concat(_OUT, ', ')"), "| cooking title opens:", lua.eval("_OPENED"))
print("openers after clean:", lua.eval("table.concat(_OP, ' ')"))
lua.execute("MerchantFrame:Hide(); _PIN = nil")
slash(lua, "prof shop")
lua.execute("""
  for _, r in ipairs(CueTheCashierShoppingListFrame.rows) do if r:IsShown() and r.line and r.line.itemID == 2320 then _VR = r end end
  if _VR then _VR.__scripts.OnClick(_VR, 'LeftButton') else _MOCK.addons.CueTheCashier_Crafting.ns.Vendors.Pin(2320) end
""")
print("vendor row pin:", lua.eval("_PIN"), "| super:", lua.eval("_SUPER"), "| row found:", lua.eval("_VR ~= nil"))
lua.execute("_MOCK.addons.CueTheCashier_Crafting.ns.Vendors.Pin(9998)")
slash(lua, "prof vendors")
print("vendors log:", lua.eval("CueTheCashierDebugFrame.edit:GetText()").split("\n")[-3:])
lua.execute("""
  local ns = _MOCK.addons.CueTheCashier_Crafting.ns
  ns.Char().known[102] = true
  ProfessionsFrame.CraftingPage.SchematicForm:Init({ recipeID = 102 })
  local f = ProfessionsFrame.CraftingPage.SchematicForm
  for _, w in ipairs(_MOCK.allFrames) do if w.add and w.__parent == f then _ADD = w.add end end
  _ADD.__scripts.OnClick(_ADD, 'LeftButton')
  _MOCK.shift = true; _ADD.__scripts.OnClick(_ADD, 'LeftButton'); _MOCK.shift = false
  _ADD.__scripts.OnClick(_ADD, 'RightButton')
""")
print("manual add 102:", lua.eval("_MOCK.addons.CueTheCashier_Crafting.ns.CraftList.Count(102)"), "| button:", lua.eval("_ADD:GetText()"))
check(lua, "split lists")
lua.execute("_MOCK.profLine = 165")
slash(lua, "prof group"); slash(lua, "prof group")
print("prof groups:", lua.eval("(function() local t = {} for _, g in ipairs(CueTheCashier.API.GetGroups()) do t[#t+1] = g.path .. ':' .. g.itemCount end return table.concat(t, ', ') end)()"))
print("make group button:", lua.eval("_MOCK.addons.CueTheCashier_Crafting.ns.CraftList.groupButton ~= nil"))
check(lua, "prof make group")
print("globals added:", leaked(lua))

# ---------- Scenario 5: main window (0.23.0) ----------
lua, M = new_runtime()
startup(lua, M)
lua.execute("""
  local d = { bought = { { t = _MOCK.now - 3600, id = 2318, name = 'Light Leather', qty = 10, money = 500, source = 'AH', char = 'Malaeiel' } },
    sold = { { t = _MOCK.now - 60, id = 2318, name = 'Light Leather', qty = 4, money = 800, source = 'AH', char = 'Malaeiel' } }, mails = {} }
  CueTheCashierAccountingDB = { ledger = { ['EU Normal - Alliance'] = d } }
  CueTheCashierDB.gold = { ['EU Normal - Alliance'] = { Altie = 50000 } }
""")
M.RunTimers(1)
slash(lua, "")  # /cm alone opens the main window
check(lua, "/cm opens main window")
print("loaded:", M.loadLog)
print("shown:", lua.eval("CueTheCashierMainFrame:IsShown()"), "| tab:", lua.eval("CueTheCashier.MainWindow:Current()"))
print("tabs:", lua.eval("(function() local t = {} for _, b in ipairs(CueTheCashierMainFrame.Tabs) do t[#t+1] = b:GetText() end return table.concat(t, ',') end)()"))
lua.execute("""
  _BOXES = {}
  local page = CueTheCashier.MainWindow.tabs.overview.page
  for _, b in ipairs(page.boxes) do
    if b:IsShown() then
      local t = { b.title:GetText() }
      for _, r in ipairs(b.rows) do if r:IsShown() then t[#t+1] = r.left:GetText() .. '=' .. r.right:GetText() end end
      _BOXES[#_BOXES+1] = table.concat(t, ' | ')
    end
  end
""")
for i in range(1, len(lua.eval("_BOXES")) + 1):
    print("  box:", lua.eval("_BOXES")[i])
for key in ["ledger", "groups", "operations", "prices", "settings", "overview"]:
    lua.execute("CueTheCashier.MainWindow:Select('%s')" % key)
check(lua, "every main tab")
print("ledger rows built:", lua.eval("CueTheCashier.MainWindow.tabs.ledger.page.summary:GetText()"))
# Settings: click toggles and type numbers
lua.execute("""
  CueTheCashier.MainWindow:Select('settings')
  local page = CueTheCashier.MainWindow.tabs.settings.page
  _LABELS = {}
  for s, w in pairs(page.widgets) do
    _LABELS[#_LABELS+1] = s.label
    if s.label == 'Minimap button' then w.GetChecked = function() return false end; w.__scripts.OnClick(w) end
    if s.label == 'Market value' then w.GetChecked = function() return false end; w.__scripts.OnClick(w) end
    if s.label == 'Craft cost' then w.GetChecked = function() return false end; w.__scripts.OnClick(w) end
    if s.label == 'Snipe: % of market value' then w:SetText('45'); w.__scripts.OnEditFocusLost(w) end
    if s.label == 'Shopping: % of the list price' then w:SetText('9'); w.__scripts.OnEditFocusLost(w) end
  end
  table.sort(_LABELS)
""")
print("settings:", lua.eval("table.concat(_LABELS, '; ')"))
print("minimap hidden:", lua.eval("CueTheCashierDB.settings.hideMinimapButton"), lua.eval("CueTheCashierMinimapButton:IsShown()"),
      "| market line shown:", lua.eval("CueTheCashier.TooltipLineShown('market')"),
      "| snipe:", lua.eval("CueTheCashierDB.settings.snipePercent"),
      "| shop max (9 refused):", lua.eval("CueTheCashierCraftingDB.settings.shopMaxPercent"),
      "| craft cost off:", lua.eval("CueTheCashierCraftingDB.settings.tooltipCraftCost"))
check(lua, "settings changes")
slash(lua, "settings"); print("/cm settings while on settings closes:", lua.eval("CueTheCashierMainFrame:IsShown()"))
lua.execute("CueTheCashierMinimapButton.__scripts.OnClick(CueTheCashierMinimapButton, 'LeftButton')")
print("minimap click opens on last tab:", lua.eval("CueTheCashierMainFrame:IsShown()"), lua.eval("CueTheCashier.MainWindow:Current()"))
lua.execute("ToggleGameMenu = ToggleGameMenu or function() end")
M.FireEvent("ADDON_LOADED", "Blizzard_GameMenu")
lua.execute("ToggleGameMenu()")
print("Escape closes:", not lua.eval("CueTheCashierMainFrame:IsShown()"))
check(lua, "minimap + escape")
print("globals added:", leaked(lua))

# ---------- Scenario 6: groups (0.24.0) ----------
lua, M = new_runtime()
startup(lua, M)
lua.execute("""
  local API = CueTheCashier.API
  _LW = API.CreateGroup('Leatherworking')
  _KITS = API.CreateGroup('Armor Kits', _LW)
  _MATS = API.CreateGroup('Mats')
  API.AddItemToGroup(_LW, 2318)
  API.AddItemToGroup(_MATS, 2318)
  API.AddItemToGroup(_KITS, 10940)
  API.SetItemRank(_MATS, 2318, 1)
""")
print("item groups 2318:", lua.eval("(function() local t = {} for _, e in ipairs(CueTheCashier.API.GetItemGroups(2318)) do t[#t+1] = e.path .. '=' .. e.rank end return table.concat(t, ', ') end)()"))
lua.execute("""
  local API = CueTheCashier.API
  _C = API.CreateGroup('Third')
  API.AddItemToGroup(_C, 2318)
  _R1 = select(1, API.GetItemRank(_C, 2318))
  API.SetItemRank(_C, 2318, 1)
  local t = {} for _, e in ipairs(API.GetItemGroups(2318)) do t[#t+1] = e.name .. e.rank end
  _ORDER = table.concat(t, ',')
  API.MoveItemRank(_C, 2318, 1)
  t = {} for _, e in ipairs(API.GetItemGroups(2318)) do t[#t+1] = e.name .. e.rank end
  _ORDER2 = table.concat(t, ',')
  API.DeleteGroup(_C)
  t = {} for _, e in ipairs(API.GetItemGroups(2318)) do t[#t+1] = e.name .. e.rank end
  _ORDER3 = table.concat(t, ',')
""")
print("new group starts last:", lua.eval("_R1"), "| set 1:", lua.eval("_ORDER"), "| down:", lua.eval("_ORDER2"), "| deleted:", lua.eval("_ORDER3"))
lua.execute("CueTheCashier.API.SetGroupOperation(CueTheCashier.API.BASE_GROUP, 'shop', 'Base default')")
print("base winner for shop (no real group has one):", lua.eval("(CueTheCashier.API.GetWinningGroup(2318, 'shop')) == 0"),
      "| item 999 in base only:", lua.eval("(CueTheCashier.API.GetWinningGroup(999)) == 0"),
      "| base delete refused:", lua.eval("CueTheCashier.API.DeleteGroup(0)"),
      "| base add refused:", lua.eval("CueTheCashier.API.AddItemToGroup(0, 5)"))
print("winner any is Mats:", lua.eval("(CueTheCashier.API.GetWinningGroup(2318)) == _MATS"))
lua.execute("CueTheCashier.API.SetGroupOperation(_LW, 'post', 'Default')")
print("winner post is LW (only one with post):", lua.eval("(CueTheCashier.API.GetWinningGroup(2318, 'post')) == _LW"),
      "| kits inherits post:", lua.eval("CueTheCashier.API.GetGroupOperation(_KITS, 'post')"))
print("move LW into own child refused:", lua.eval("CueTheCashier.API.MoveGroup(_LW, _KITS)"))
text = lua.eval("CueTheCashier.API.ExportGroups(nil)")
print("export:\n" + text)
lua.execute("CueTheCashier.API.DeleteGroup(_LW)")
print("after delete LW, groups:", lua.eval("#CueTheCashier.API.GetGroups()"))
lua.globals()._TXT = text
print("import:", lua.eval("table.concat({CueTheCashier.API.ImportGroups(_TXT)}, ',')"))
print("re-import merges:", lua.eval("table.concat({CueTheCashier.API.ImportGroups(_TXT)}, ',')"),
      "| groups:", lua.eval("#CueTheCashier.API.GetGroups()"))
print("bad import:", lua.eval("select(2, CueTheCashier.API.ImportGroups('hello'))"))
# tooltip
lua.execute("GameTooltip.lines = {} CueTheCashier.AddGroupLines(GameTooltip, 2318)")
print("tooltip:", list(lua.eval("GameTooltip.lines").values()))
# Groups tab
slash(lua, "")
lua.execute("CueTheCashier.MainWindow:Select('groups')")
lua.execute("""
  local MW = CueTheCashier.MainWindow
  local page = MW.tabs.groups.page
  page.addBox:SetText('10940'); page.addBox.__scripts.OnEnterPressed(page.addBox)
  page.nameBox:SetText('Renamed'); page.nameBox.__scripts.OnEditFocusLost(page.nameBox)
  page.ShowText('export', nil)
  _EXP = page.textBox.edit:GetText()
  page.ShowText('import')
  page.textBox.edit:SetText(_EXP)
  page.textBox.go.__scripts.OnClick(page.textBox.go)
  page.AskDelete(CueTheCashier.API.GetGroups()[2].id)
  CueTheCashier.MainWindow.tabs.groups.page.tree:SetDataProvider({}) -- (mock)

  local pop = _MOCK.popups[#_MOCK.popups]
  pop.data.accept()
""")
# Two lists: make a sub-group of the first real group and move items
lua.execute("""
  local API = CueTheCashier.API
  local top = API.GetGroups()[2].id
  _SUB = API.CreateGroup('Sub', top)
  local page = CueTheCashier.MainWindow.tabs.groups.page
  local function Row(list, data)
    local row = CreateFrame('Button')
    list.__view.__init(row, data)
    return row
  end
  _ROW = Row
  -- pick the sub-group with a tree row click
  for _, e in ipairs(page.tree.__dp.t) do
    if e.id == _SUB then local r = Row(page.tree, e); r.__scripts.OnClick(r, 'LeftButton') end
  end
  _L1 = page.leftTitle:GetText()
  -- pick every parent item on the left, Add
  page.addButton:GetParent()
  for _, d in ipairs(page.leftList.__dp.t) do local r = Row(page.leftList, d); r.__scripts.OnClick(r, 'LeftButton') end
  _ADDTXT = page.addButton:GetText()
  page.addButton.__scripts.OnClick(page.addButton)
  _R1 = page.rightTitle:GetText() .. ' / ' .. page.leftTitle:GetText()
  -- pick one on the right (it is in the parent too, so rank 2/2), make it 1st, then remove by double-click
  local d = page.rightList.__dp.t[1]
  local r = Row(page.rightList, d); r.__scripts.OnClick(r, 'LeftButton')
  _EXTRA = d.extra
  page.itemTop.__scripts.OnClick(page.itemTop)
  page.itemRank.__scripts.OnEnter(page.itemRank)
  page.itemDown.__scripts.OnClick(page.itemDown)
  page.itemUp.__scripts.OnClick(page.itemUp)
  page.itemRank:SetText('2'); page.itemRank.__scripts.OnEditFocusLost(page.itemRank)
  page.itemRank:SetText('1'); page.itemRank.__scripts.OnEditFocusLost(page.itemRank)
  _PRIO = _EXTRA .. ' -> ' .. tostring(API.GetItemGroups(d.itemID)[1].id == _SUB)
  r.__scripts.OnDoubleClick(r)
  _R2 = page.rightTitle:GetText()
  -- Operations view of the sub-group: inherits post from its parent
  API.SetGroupOperation(API.GetGroups()[2].id, 'post', 'Fast sell')
  API.SetGroupOperation(0, 'mail', 'Send to alt')
  page.opsTab.__scripts.OnClick(page.opsTab)
  _OPS = page.opsView.values.post:GetText() .. ' || ' .. page.opsView.values.mail:GetText() .. ' || ' .. page.opsView.values.shop:GetText()
  _SHOWN = tostring(page.opsView:IsShown()) .. '/' .. tostring(page.itemsView:IsShown())
  for _, e in ipairs(page.tree.__dp.t) do
    if e.base then local r = Row(page.tree, e); r.__scripts.OnClick(r, 'LeftButton') end
  end
  _BASEOPS = page.opsView.values.mail:GetText()
  page.itemsTab.__scripts.OnClick(page.itemsTab)
  _BASESHOWN = tostring(page.baseInfo:IsShown()) .. '/' .. tostring(page.itemsView:IsShown())
""")
print("ops view:", lua.eval("_OPS"), "| ops/items shown:", lua.eval("_SHOWN"), "| base ops:", lua.eval("_BASEOPS"), "| base items: info/lists", lua.eval("_BASESHOWN"))
print("left before:", lua.eval("_L1"), "| add button:", lua.eval("_ADDTXT"), "| after add:", lua.eval("_R1"),
      "| rank 1 here:", lua.eval("_PRIO"), "| after double-click:", lua.eval("_R2"))
print("groups after tab actions:", lua.eval("(function() local t = {} for _, g in ipairs(CueTheCashier.API.GetGroups()) do t[#t+1] = g.path .. ':' .. g.itemCount end return table.concat(t, ', ') end)()"))
check(lua, "groups tab")

# ---------- Scenario 7: price formulas and operations (0.28.0) ----------
lua, M = new_runtime()
startup(lua, M)
lua.execute("""
  local d = CueTheCashier:GetRealmData()
  d.items[2318] = { minBuyout = 30, marketValue = 40, median = 45, seenInLastScan = true }
  CueTheCashierDB.vendorPrices = CueTheCashierDB.vendorPrices or {}
""")
lua.execute("function _R(...) local a, b = ... return tostring(a) .. ' | ' .. tostring(b) end")
tests = [
  "market", "market * 90%", "min(market, 100g)", "max(1g50s, market)", "first(7d, market)",
  "avg(min, market)", "(market + min) / 2", "market * 2 - 10c", "7d", "auction.market",
  "market / 0", "unknownthing", "min(", "market * ", "1g 50s", "-market + 1g", "nonsense(1)", "30d * 3",
]
for t in tests:
    lua.globals()._T = t
    print("formula %-22s ->" % t, lua.eval("_R(CueTheCashier.API.EvaluatePrice(_T, 2318))"))
lua.execute("""
  local API = CueTheCashier.API
  _C1 = table.concat({tostring(API.SetCustomPrice('mybase', 'max(market, 35c)'))}, ',')
  _C2 = _R(API.SetCustomPrice('market', '1g'))
  _C3 = tostring(API.EvaluatePrice('mybase * 2', 2318))
  _C4 = tostring(API.GetPrice(2318, 'mybase'))
  API.SetCustomPrice('loopa', 'mybase')
  _C5 = _R(API.SetCustomPrice('selfref', 'selfref * 2'))
""")
print("custom:", lua.eval("_C1"), "|", lua.eval("_C2"), "| mybase*2:", lua.eval("_C3"), "| GetPrice custom:", lua.eval("_C4"), "| self ref:", lua.eval("_C5"))
# Operations
lua.execute("""
  local API = CueTheCashier.API
  _OP = API.CreateOperation('post', 'Cheap')
  _E1 = _R(API.SetOperationValue('post', 'Cheap', 'minPrice', 'market *'))
  API.SetOperationValue('post', 'Cheap', 'minPrice', 'mybase * 50%')
  _E2 = _R(API.SetOperationValue('post', 'Cheap', 'postCap', 0))
  API.SetOperationValue('post', 'Cheap', 'duration', 'long')
  local g = API.CreateGroup('Leather')
  API.AddItemToGroup(g, 2318)
  API.SetGroupOperation(g, 'post', 'Cheap')
  local name, settings, gid = API.GetItemOperation(2318, 'post')
  _IO = tostring(name) .. ' ' .. tostring(settings and settings.duration) .. ' ' .. tostring(gid == g)
  _IP = tostring(API.GetOperationPrice('post', 'Cheap', 'minPrice', 2318))
  API.RenameOperation('post', 'Cheap', 'Cheaper')
  _RN = tostring((API.GetGroupOperation(g, 'post')))
  API.CopyOperation('post', 'Cheaper')
  _NAMES = table.concat(API.GetOperations('post'), ',')
  API.DeleteOperation('post', 'Cheaper')
  _DEL = tostring((API.GetGroupOperation(g, 'post')))
  API.SetGroupOperation(0, 'shop', API.CreateOperation('shop', 'Default'))
  -- 0.42: Base Group shop/post/... ops only cover grouped items; craft covers all.
  _BASE = tostring((API.GetItemOperation(999, 'shop'))) .. ' / craft ' .. tostring((API.GetItemOperation(999, 'craft')))
    .. ' / grouped 2318 shop ' .. tostring((API.GetItemOperation(2318, 'shop')))
""")
for k in ["_OP","_E1","_E2","_IO","_IP","_RN","_NAMES","_DEL","_BASE"]:
    print("ops", k, lua.eval(k))
check(lua, "formulas and operations")
# UI
slash(lua, "")
lua.execute("""
  local MW = CueTheCashier.MainWindow
  MW:Select('operations')
  local page = MW.tabs.operations.page
  page.newButton.__scripts.OnClick(page.newButton)
  local form = page.forms.post
  for _, c in ipairs(form.controls) do
    if c.field.key == 'undercut' then c.control:SetText('5c'); c.control.__scripts.OnEditFocusLost(c.control) end
    if c.field.key == 'normalPrice' then c.control:SetText('bad(('); c.control.__scripts.OnEditFocusLost(c.control) end
  end
  _ERR = page.err:GetText()
  page.testBox:SetText('2318'); page.testBox.__scripts.OnEditFocusLost(page.testBox)
  _VALS = {}
  for _, c in ipairs(form.controls) do _VALS[#_VALS+1] = c.field.key .. '=' .. c.value:GetText() end
  page.nameBox:SetText('My Post'); page.nameBox.__scripts.OnEditFocusLost(page.nameBox)
  _USED = page.used:GetText()
  MW:Select('prices')
  local pp = MW.tabs.prices.page
  pp.itemBox:SetText('2318'); pp.itemBox.__scripts.OnEditFocusLost(pp.itemBox)
  pp.tryBox:SetText('market * 2'); pp.tryBox.__scripts.OnTextChanged(pp.tryBox)
  _TRY = pp.tryResult:GetText()
  pp.nameBox:SetText('double'); pp.formulaBox:SetText('market * 2')
  MW:Select('groups')
  MW:Select('prices')
""")
print("ops ui err:", lua.eval("_ERR"))
print("ops ui values:", lua.eval("table.concat(_VALS, ' ; ')"))
print("ops ui renamed:", lua.eval("table.concat(CueTheCashier.API.GetOperations('post'), ',')"), "|", lua.eval("_USED"))
print("try:", lua.eval("_TRY"))
check(lua, "operations and prices tabs")

# ---------- Scenario 8: Post / Cancel scan (0.29.0) ----------
lua, M = new_runtime()
startup(lua, M)
lua.execute("""
  local d = CueTheCashier:GetRealmData()
  d.items[2318] = { minBuyout = 30, marketValue = 100, seenInLastScan = true }
  d.items[10940] = { minBuyout = 30, marketValue = 200, seenInLastScan = true }
  Enum.ItemCommodityStatus = { Item = 1, Commodity = 2 }
  Enum.AuctionStatus = { Active = 0, Sold = 1 }
  ItemLocation = { CreateFromBagAndSlot = function(_, b, s) return { bag = b, slot = s } end }
  local bags = { [0] = { { itemID = 2318, stackCount = 15 }, { itemID = 10940, stackCount = 3 } } }
  C_Container.GetContainerNumSlots = function(b) return bags[b] and #bags[b] or 0 end
  C_Container.GetContainerItemInfo = function(b, s) return bags[b] and bags[b][s] end
  local AH = C_AuctionHouse
  AH.GetItemCommodityStatus = function(loc) return loc.slot == 1 and 2 or 1 end
  AH.GetItemKeyInfo = function(k) return { itemName = 'x', isCommodity = k.itemID == 2318 } end
  AH.GetNumCommoditySearchResults = function() return 2 end
  AH.GetCommoditySearchResultInfo = function(_, i)
    return ({ { unitPrice = 80, quantity = 5, numOwnerItems = 5 }, { unitPrice = 90, quantity = 20, numOwnerItems = 0 } })[i]
  end
  AH.GetNumItemSearchResults = function() return 1 end
  AH.GetItemSearchResultInfo = function() return { buyoutAmount = 50, containsOwnerItem = false } end
  _OWNED = { { auctionID = 5, itemKey = { itemID = 2318 }, quantity = 4, buyoutAmount = 95, status = 0 },
             { auctionID = 6, itemKey = { itemID = 2318 }, quantity = 9, buyoutAmount = 70, status = 1 } }
  AH.GetNumOwnedAuctions = function() return #_OWNED end
  AH.GetOwnedAuctionInfo = function(i) return _OWNED[i] end
  _POSTS = {}
  AH.PostCommodity = function(loc, dur, q, p) _POSTS[#_POSTS+1] = 'C ' .. dur .. ' ' .. q .. 'x' .. p end
  AH.PostItem = function(loc, dur, q, bid, p) _POSTS[#_POSTS+1] = 'I ' .. dur .. ' ' .. q .. 'x' .. p end
  AH.CancelAuction = function(id) _POSTS[#_POSTS+1] = 'cancel ' .. id end
  local API = CueTheCashier.API
  API.CreateOperation('post', 'P')
  API.SetOperationValue('post', 'P', 'minPrice', 'market * 50%')
  API.SetOperationValue('post', 'P', 'postCap', 10)
  API.SetOperationValue('post', 'P', 'keep', 1)
  API.SetOperationValue('post', 'P', 'duration', 'long')
  API.SetGroupOperation(0, 'post', 'P')
  -- 0.42: the Base Group's post op only covers items in a group.
  local g = API.CreateGroup('Sell')
  API.AddItemToGroup(g, 2318); API.AddItemToGroup(g, 10940)
""")
lua.execute("AuctionHouseFrame = _MOCK.NewWidget('Frame', 'AuctionHouseFrame'); AuctionHouseFrame.CloseButton = _MOCK.NewWidget('Button')")
M.FireEvent("AUCTION_HOUSE_SHOW")
M.RunTimers(3)
lua.execute("""
  local ns = _MOCK.addons.CueTheCashier_Auctioning.ns
  ns.CraftTrade:SelectTab(4)
  ns.PostTab:Start('post')
""")
M.FireEvent("OWNED_AUCTIONS_UPDATED")
def answer_all(lua, M):
    for _ in range(4):
        cur = lua.eval("(function() local ns = _MOCK.addons.CueTheCashier_Auctioning.ns return nil end)()")
        M.FireEvent("COMMODITY_SEARCH_RESULTS_UPDATED", 2318)
        M.FireEvent("ITEM_SEARCH_RESULTS_UPDATED", lua.eval("C_AuctionHouse.MakeItemKey(10940)"))
        M.RunTimers(1)
answer_all(lua, M)
lua.execute("""
  local tab = CueTheCashierPostTab
  _PI = tab.info:GetText()
  local ns = _MOCK.addons.CueTheCashier_Auctioning.ns
  ns.PostTab:DoNext(); _MOCK.FireEvent('AUCTION_HOUSE_AUCTION_CREATED', 1)
  ns.PostTab:DoNext(); _MOCK.FireEvent('AUCTION_HOUSE_AUCTION_CREATED', 2)
  ns.PostTab:DoNext()
""")
print("post scan:", lua.eval("_PI"), "| posts:", lua.eval("table.concat(_POSTS, ', ')"))
check(lua, "post scan")
lua.execute("""
  _POSTS = {}
  _MOCK.addons.CueTheCashier_Auctioning.ns.PostTab:Start('cancel')
""")
M.FireEvent("OWNED_AUCTIONS_UPDATED")
answer_all(lua, M)
lua.execute("""
  local ns = _MOCK.addons.CueTheCashier_Auctioning.ns
  _CI = CueTheCashierPostTab.info:GetText()
  ns.PostTab:DoNext(); _MOCK.FireEvent('AUCTION_CANCELED', 5)
""")
print("cancel scan:", lua.eval("_CI"), "| calls:", lua.eval("table.concat(_POSTS, ', ')"))
check(lua, "cancel scan")
# Sold rows in the Auctions tab
lua.execute("""
  local ns = _MOCK.addons.CueTheCashier_Auctioning.ns
  ns.CraftTrade:SelectTab(3)
""")
M.FireEvent("OWNED_AUCTIONS_UPDATED")
M.RunTimers(2)
check(lua, "auctions tab with a sold row")
# ---------- Scenario 9: vendor buys and the Sell to Vendor button (0.30.0) ----------
lua, M = new_runtime()
startup(lua, M)
lua.execute("""
  local d = CueTheCashier:GetRealmData()
  d.items[2318] = { minBuyout = 5, marketValue = 6, seenInLastScan = true }
  d.items[10940] = { minBuyout = 500, marketValue = 500, seenInLastScan = true }
  CueTheCashier.Data.GetVendorPrice = function(_, id) return ({ [2318] = 10, [10940] = 7, [4444] = 50 })[id] end
  _BAGS = { [0] = { { itemID = 2318, stackCount = 4 }, { itemID = 2318, stackCount = 10 }, { itemID = 10940, stackCount = 3 },
                    { itemID = 4444, stackCount = 2 } } }
  C_Container.GetContainerNumSlots = function(b) return _BAGS[b] and #_BAGS[b] or 0 end
  C_Container.GetContainerItemInfo = function(b, s) return _BAGS[b] and _BAGS[b][s] end
  C_Container.UseContainerItem = function(b, s) _SOLD = (_SOLD or '') .. _BAGS[b][s].itemID .. 'x' .. _BAGS[b][s].stackCount .. ' '; _BAGS[b][s] = { } end
  C_Item.GetItemCount = function(id)
    local n = 0 for _, bag in pairs(_BAGS) do for _, x in pairs(bag) do if x.itemID == id then n = n + x.stackCount end end end return n end
  MerchantFrame = _MOCK.NewWidget('Frame', 'MerchantFrame'); MerchantFrame:Show()
  local API = CueTheCashier.API
  API.AddVendorBuy(2318, 10)   -- 4 of my own + 10 bought
  API.CreateOperation('vendor', 'Junk')
  API.SetGroupOperation(0, 'vendor', 'Junk')  -- 4444 has no AH value: kept; 10940 worth 500 > 7*120%: kept
  local g = API.CreateGroup('Junk')
  for _, id in ipairs({ 2318, 10940, 4444 }) do API.AddItemToGroup(g, id) end
""")
M.FireEvent("MERCHANT_SHOW"); M.RunTimers(1)
lua.execute("""
  _PL = #CueTheCashier.API.GetVendorSellPlan()
  local p, t = CueTheCashier.API.GetVendorSellPlan(true)
  _P = {} for _, x in ipairs(p) do _P[#_P+1] = x.itemID .. 'x' .. x.count .. ' ' .. x.why end
  _BT = CueTheCashierVendorSellButton:GetText()
  CueTheCashierVendorSellButton.__scripts.OnEnter(CueTheCashierVendorSellButton)
  _MOCK.shift = true
  CueTheCashierVendorSellButton.__scripts.OnClick(CueTheCashierVendorSellButton)
  _MOCK.shift = false
""")
M.RunTimers(5)
M.FireEvent("BAG_UPDATE_DELAYED"); M.RunTimers(1)
print("vendor plan (click / shift):", lua.eval("_PL"), lua.eval("table.concat(_P, ', ')"), "| button:", lua.eval("_BT"), "| sold:", lua.eval("_SOLD"),
      "| left on list:", lua.eval("#CueTheCashier.API.GetVendorBuys()"))
lua.execute("""
  _BAGS[0] = { { itemID = 2318, stackCount = 4 }, { itemID = 2318, stackCount = 10 } }
  _SOLD = nil
  CueTheCashier.API.SetGroupOperation(0, 'vendor', nil)
  CueTheCashier.API.AddVendorBuy(2318, 10)
""")
M.FireEvent("MERCHANT_SHOW"); M.RunTimers(1)
lua.execute("CueTheCashierVendorSellButton.__scripts.OnClick(CueTheCashierVendorSellButton)")
M.RunTimers(5); M.FireEvent("BAG_UPDATE_DELAYED"); M.RunTimers(1)
print("list only: sold", lua.eval("_SOLD"), "| own left:", lua.eval("C_Item.GetItemCount(2318)"), "| list left:", lua.eval("#CueTheCashier.API.GetVendorBuys()"))
# Blizzard's window opens after our MERCHANT_SHOW handler (seen in game, 0.30.0)
lua.execute("""
  _BAGS[0] = { { itemID = 2318, stackCount = 3 } }
  MerchantFrame:Hide(); CueTheCashierVendorSellButton:Hide()
  SlashCmdList.CRAFTMARKET('tovendor add |cffffffff|Hitem:2318::::|h[Light Leather]|h|r 3')
""")
M.FireEvent("MERCHANT_SHOW")
lua.execute("MerchantFrame:Show()")
M.RunTimers(1)
slash(lua, "tovendor")
print("late merchant window: button", lua.eval("CueTheCashierVendorSellButton:IsShown()"), lua.eval("CueTheCashierVendorSellButton:GetText()"))
check(lua, "sell to vendor")
# ---------- Scenario 10: profiles and mailing (0.31.0) ----------
lua, M = new_runtime(legacy="""
CueTheCashierDB = { dbVersion = 3, realms = {}, itemInfo = {}, settings = { snipePercent = 42, debug = false },
  groups = { nextID = 4, list = { [1] = { id = 1, name = 'Old Group', priority = 50, created = 1, items = { [2318] = true, [2319] = true }, operations = {} },
    [2] = { id = 2, name = 'Old High', priority = 70, created = 2, items = { [2318] = true, [2319] = 30 }, operations = {} },
    [3] = { id = 3, name = 'Old Tie', priority = 50, created = 3, items = { [2318] = true }, operations = {} } } },
  operations = { mail = { ['To Alt'] = { target = 'Altie' } } }, customPrices = { mybase = 'market * 2' } }
""")
startup(lua, M)
lua.execute("""
  local API = CueTheCashier.API
  local function Order(item) local t = {} for _, e in ipairs(API.GetItemGroups(item)) do t[#t+1] = e.name end return table.concat(t, ',') end
  _MIG = Order(2318) .. ' / ' .. Order(2319)
  _P1 = API.GetProfile() .. ' groups=' .. #API.GetGroups() .. ' snipe=' .. tostring(CueTheCashier.ProfileSettings().snipePercent)
    .. ' custom=' .. #API.GetCustomPrices() .. ' oldkeys=' .. tostring(CueTheCashierDB.groups) .. tostring(CueTheCashierDB.settings.snipePercent)
  API.NewProfile('Alt setup')
  _P2 = API.GetProfile() .. ' groups=' .. #API.GetGroups() .. ' custom=' .. #API.GetCustomPrices()
  API.CopyProfile('EU Normal - Alliance')
  _P3 = 'after copy groups=' .. #API.GetGroups()
  API.CreateGroup('Only here')
  API.UseProfile('EU Normal - Alliance')
  _P4 = API.GetProfile() .. ' groups=' .. #API.GetGroups()
  API.UseProfile('Alt setup'); API.DeleteProfile('Alt setup')
  _P5 = API.GetProfile() .. ' ' .. table.concat(API.GetProfiles(), ',')
""")
print("priority -> rank migration (want Old High,Old Group,Old Tie / Old Group,Old High):", lua.eval("_MIG"))

for k in ["_P1","_P2","_P3","_P4","_P5"]:
    print("profile", k, lua.eval(k))
slash(lua, "")
lua.execute("CueTheCashier.MainWindow:Select('settings')")
lua.execute("""
  local page = CueTheCashier.MainWindow.tabs.settings.page
  page.profileBox:SetText('Second'); page.profileNew.__scripts.OnClick(page.profileNew)
  _P6 = CueTheCashier.API.GetProfile() .. ' / ' .. page.profileChoose:GetText()
  CueTheCashier.API.UseProfile('EU Normal - Alliance')
""")
print("profile ui:", lua.eval("_P6"))
check(lua, "profiles")
# Mailing
lua.execute("""
  local API = CueTheCashier.API
  local g = API.GetGroups()[1].id
  API.SetGroupOperation(g, 'mail', 'To Alt')
  API.SetOperationValue('mail', 'To Alt', 'keep', 2)
  _BAGS = { [0] = { { itemID = 2318, stackCount = 5 }, { itemID = 2318, stackCount = 20 }, { itemID = 2318, stackCount = 1 } } }
  C_Container.GetContainerNumSlots = function(b) return _BAGS[b] and #_BAGS[b] or 0 end
  C_Container.GetContainerItemInfo = function(b, s) return _BAGS[b] and _BAGS[b][s] end
  _ATT = {}
  C_Container.PickupContainerItem = function(b, s) _CUR = _BAGS[b][s] end
  function ClickSendMailItemButton(i) _ATT[#_ATT+1] = _CUR.itemID .. 'x' .. _CUR.stackCount; _CUR = nil end
  function GetSendMailPrice() return 30 * #_ATT end
  function ClearSendMail() _ATT = {} end
  function SendMail(to, subj) _SENT = (_SENT or '') .. to .. ':' .. table.concat(_ATT, '+') .. ' ' end
  MailFrame = _MOCK.NewWidget('Frame', 'MailFrame'); MailFrame:Show()
  SendMailFrame = _MOCK.NewWidget('Frame', 'SendMailFrame'); SendMailFrame:Show()
""")
M.FireEvent("MAIL_SHOW"); M.RunTimers(1)
lua.execute("_BT = CueTheCashierMailButton:GetText(); CueTheCashierMailButton.__scripts.OnEnter(CueTheCashierMailButton); CueTheCashierMailButton.__scripts.OnClick(CueTheCashierMailButton, 'LeftButton')")
M.FireEvent("MAIL_SEND_SUCCESS"); M.RunTimers(2)
print("mail button:", lua.eval("_BT"), "| sent:", lua.eval("_SENT"))
lua.execute("""
  _INBOX = {
    { subject = 'Auction successful: Light Leather', money = 500, items = 0, inv = 'seller' },
    { subject = 'Auction expired: Camp Tent', money = 0, items = 1 },
    { subject = 'Hello', money = 0, items = 1, cod = 100 },
    { subject = 'Auction won: Strange Dust', money = 0, items = 1, inv = 'buyer' },
  }
  AUCTION_EXPIRED_MAIL_SUBJECT = 'Auction expired: %s'; AUCTION_REMOVED_MAIL_SUBJECT = 'Auction cancelled: %s'
  function GetInboxNumItems() return #_INBOX end
  function GetInboxHeaderInfo(i) local m = _INBOX[i]; return nil, nil, 'x', m.subject, m.money, m.cod or 0, 30, m.items, false, false, false, false, false end
  function GetInboxInvoiceInfo(i) return _INBOX[i].inv end
  C_Container.GetContainerNumFreeSlots = function() return 10 end
  function AutoLootMailItem(i) _OPENED = (_OPENED or '') .. _INBOX[i].subject .. '; '; table.remove(_INBOX, i) end
  _MOCK.FireEvent('MAIL_SHOW')
""")
M.RunTimers(1)
lua.execute("_SB = 'send tab: ' .. CueTheCashierMailButton:GetText()")
lua.execute("SendMailFrame:Hide(); InboxFrame = _MOCK.NewWidget('Frame', 'InboxFrame'); InboxFrame:Show(); CueTheCashier.Mailing.Refresh()")
lua.execute("_OB = CueTheCashierMailButton:GetText(); _SB = _SB .. ' | inbox tab: ' .. _OB; CueTheCashierMailButton.__scripts.OnEnter(CueTheCashierMailButton)")
lua.execute("CueTheCashierMailButton.__scripts.OnClick(CueTheCashierMailButton, 'LeftButton')")
M.RunTimers(5)
lua.execute("_OB2 = CueTheCashierMailButton:GetText(); function TakeInboxMoney(i) _OPENED = _OPENED .. 'money:' .. _INBOX[i].subject .. '; '; table.remove(_INBOX, i) end")
lua.execute("CueTheCashierMailButton.__scripts.OnClick(CueTheCashierMailButton, 'RightButton')")
M.RunTimers(5)
lua.execute("_OB = _OB .. ' -> ' .. _OB2 .. ' -> ' .. CueTheCashierMailButton:GetText()")
slash(lua, "mail")
print("open button:", lua.eval("_OB"), "|", lua.eval("_SB"), "| opened:", lua.eval("_OPENED"), "| left:", lua.eval("#_INBOX"))
print("mail log:", [l[:120] for l in lua.eval("CueTheCashierDebugFrame and CueTheCashierDebugFrame.edit:GetText() or ''").split("\n")[-4:]])
check(lua, "mailing")
# 0.34: AH fees, Group Scan, saved searches, advanced filters
lua.execute("AuctionHouseFrame = _MOCK.NewWidget('Frame', 'AuctionHouseFrame'); AuctionHouseFrame.CloseButton = _MOCK.NewWidget('Button'); C_AuctionHouse.GetItemKeyInfo = function(k) return { isCommodity = true, itemName = 'Item' .. k.itemID } end")
lua.execute("_REALENTRY = CueTheCashier.GetItemEntry; CueTheCashier.GetItemEntry = function(self, id) return ({ [2318] = { marketValue = 40 }, [10940] = { marketValue = 5200 } })[id] end")
lua.execute("_ok, _err = pcall(CueTheCashier.API.SetCustomPrice, 'mycut', 'cut + deposit')")
lua.execute("""
  local API = CueTheCashier.API
  _F1 = API.GetAuctionCutRate() .. ' ' .. API.GetAuctionDepositRate() .. ' cut=' .. tostring(API.GetPrice(2318, 'auction.cut'))
    .. ' dep=' .. tostring(API.GetPrice(2318, 'auction.deposit')) .. ' formula=' .. tostring(API.GetPrice(2318, 'mycut'))
  UnitFactionGroup = function(u) if u == 'npc' then return nil end return 'Alliance' end
  GetSubZoneText = function() return 'Booty Bay' end
""")
M.FireEvent("AUCTION_HOUSE_SHOW"); M.RunTimers(3)
lua.execute("""
  local API = CueTheCashier.API
  _F2 = API.GetAuctionCutRate() .. ' neutral=' .. tostring(API.IsNeutralAuctionHouse()) .. ' cut=' .. tostring(API.GetPrice(2318, 'auction.cut'))
  UnitFactionGroup = function() return 'Alliance' end
  GetSubZoneText = function() return 'Trade District' end
""")
M.FireEvent("AUCTION_HOUSE_SHOW"); M.RunTimers(3)
print("fees:", lua.eval("_F1"), "|", lua.eval("_F2"), "| back:", lua.eval("CueTheCashier.API.GetAuctionCutRate()"))
lua.execute("""
  local API = CueTheCashier.API
  local g = API.CreateGroup('Shop mats')
  API.AddItemToGroup(g, 2318); API.AddItemToGroup(g, 10940)
  API.CreateOperation('shop', 'Cheap mats')
  API.SetOperationValue('shop', 'Cheap mats', 'maxPrice', 'market * 120%')
  API.SetOperationValue('shop', 'Cheap mats', 'buyUpTo', 20)
  API.SetGroupOperation(g, 'shop', 'Cheap mats')
  C_Item.GetItemCount = function(id) return id == 2318 and 5 or 0 end
  local ns = _MOCK.addons.CueTheCashier_Auctioning.ns
  AuctionHouseFrame:Show(); if not ns.CraftTrade.showingOurs then ns.CraftTrade:ShowOurs() end
  ns.CraftTrade:SelectTab(8)
  local tab = ns.ShoppingTab
  tab:Toggle('groups')
  _GS = {} for _, r in ipairs(tab.state.rows) do _GS[#_GS+1] = r.itemID .. ' need ' .. tostring(r.need) .. ' max ' .. r.maxPrice end
  table.sort(_GS); _GS = table.concat(_GS, '; ')
  _GI = tab.tab.info and tab.tab.info:GetText() or ''
""")
print("group scan:", lua.eval("_GS"), "| info:", lua.eval("_GI"))
lua.execute("""
  local ns = _MOCK.addons.CueTheCashier_Auctioning.ns
  ns.CraftTrade:SelectTab(1)
  local B = ns.BuyTab
  B.searchBox:SetText('leather'); B.minLevel:SetText('10'); B.maxLevel:SetText('20')
  _Q = nil
  C_AuctionHouse.SendBrowseQuery = function(q) _Q = q end
  C_AuctionHouse.GetBrowseResults = function() return {
    { itemKey = C_AuctionHouse.MakeItemKey(2318), minPrice = 30, totalQuantity = 5 },
    { itemKey = C_AuctionHouse.MakeItemKey(10940), minPrice = 9000, totalQuantity = 1 } } end
  B:Search()
  _BQ = 'query lvl ' .. tostring(_Q and _Q.minLevel) .. '-' .. tostring(_Q and _Q.maxLevel)
  B.SetPct = function(p) end
""")
lua.execute("""
  local B = _MOCK.addons.CueTheCashier_Auctioning.ns.BuyTab
  -- choose 100% of value: 2318 (30 <= 40) stays, 10940 (9000 > 5200) hidden
  B:Load({ text = 'leather', minLevel = 10, maxLevel = 20, maxPct = 100, filters = {} })
  _MOCK.FireEvent('AUCTION_HOUSE_BROWSE_RESULTS_UPDATED')
  _BR = #B.Searches().recent .. ' recent, shown=' .. #B.resultsBox.__dp.t
""")
lua.execute("""
  local B = _MOCK.addons.CueTheCashier_Auctioning.ns.BuyTab
  B:SaveSearch('Cheap leather')
  B:SaveSearch('Cheap leather')
  local s = B.Searches()
  _SV = #s.saved .. ' saved: ' .. s.saved[1].name .. ' = ' .. B.Describe(s.saved[1])
  B:ShowSavedMenu(CueTheCashierBuySavedButton)
  B:AskName(CueTheCashierBuySavedButton)
  _SV = _SV .. ' | name box: ' .. B.namePanel.editBox:GetText()
  B:DeleteSearch('Cheap leather')
  _SV = _SV .. ' | after delete ' .. #s.saved
""")
print("buy:", lua.eval("_BQ"), "|", lua.eval("_BR"), "|", lua.eval("_SV"))
check(lua, "0.34 fees, group scan, saved searches")
# 0.35: disenchant materials on tooltips, Destroy list, bank moves
lua.execute("""
  local gi, gii = C_Item.GetItemInfo, C_Item.GetItemInfoInstant
  _BIND = 2
  C_Item.GetItemInfo = function(id)
    if id == 9001 then return 'Green Boots', '|Hitem:9001|h[Green Boots]|h', 2, 20, 15, 'Armor', 'Leather', 1, 'INVTYPE_FEET', 1, 50, 4, 2, _BIND end
    return gi(id)
  end
  C_Item.GetItemInfoInstant = function(id)
    if id == 9001 then return id, 'Armor', 'Leather', 'INVTYPE_FEET', 1, 4, 2 end
    return gii(id)
  end
  IsPlayerSpell = function() return _ENCH end
  _ENCH = false
  GameTooltip.lines = {}; local ok, e = pcall(_MOCK.tooltipPost, GameTooltip, { id = 9001 }); _ERR = tostring(e)
  _T1 = table.concat(GameTooltip.lines, ' / ')
  _BIND = 1
  GameTooltip.lines = {}; _MOCK.tooltipPost(GameTooltip, { id = 9001 })
  _T2 = table.concat(GameTooltip.lines, ' / ')
  _ENCH = true
  GameTooltip.lines = {}; _MOCK.tooltipPost(GameTooltip, { id = 9001 })
  _T3 = table.concat(GameTooltip.lines, ' / ')
""")
print("de tooltip BoE:", lua.eval("_T1"), lua.eval("_ERR"), lua.eval("(function() local DE=CueTheCashier.Disenchant; local q,l,c = DE.ItemFacts(9001); local o = DE.Outcomes(q,l,c); return tostring(q)..','..tostring(l)..','..tostring(c)..' out '..tostring(o and #o)..' lines '..#GameTooltip.lines end)()"))
print("de tooltip soulbound, not enchanter:", lua.eval("_T2"))
print("de tooltip enchanter:", lua.eval("_T3"))
lua.execute("""
  _BAGS = { [0] = { { itemID = 9001, stackCount = 1, hyperlink = 'x' }, { itemID = 2318, stackCount = 20 } } }
  C_Container.GetContainerNumSlots = function(b) return _BAGS[b] and #_BAGS[b] or 0 end
  C_Container.GetContainerItemInfo = function(b, s) return _BAGS[b] and _BAGS[b][s] end
  C_Spell = C_Spell or {}; C_Spell.GetSpellName = function() return 'Disenchant' end
  InCombatLockdown = function() return false end
""")
slash(lua, "destroy")
print("after destroy:", list(lua.eval("_MOCK.printed").values()), list(lua.eval("_MOCK.errors").values()))
lua.execute("local b = _MOCK.addons.CueTheCashier_Destroying.ns.DestroyList.button; _D = tostring(b.__attrs and b.__attrs.macrotext) .. ' | ' .. b:GetText()")
slash(lua, "destroy list")
lua.execute("""
  local K = CueTheCashier.OneKey
  local b = K.Button()
  b.__scripts.PreClick(b)
  _OK1 = tostring(b:GetAttribute('type')) .. ' ' .. tostring(b:GetAttribute('macrotext'))
  StaticPopup_FindVisible = function(w) if _POP then return _POP end end
  StaticPopup_OnClick = function(d, i) _ACCEPTED = d.data.accept() or 'yes' end
  _POP = { data = { accept = function() _ACC = true end } }
  b.__scripts.PreClick(b)
  _OK2 = tostring(b:GetAttribute('type')) .. ' accepted=' .. tostring(_ACC)
  _POP = nil
""")
slash(lua, "macro next")
lua.execute("""
  local K = CueTheCashier.OneKey
  _BINDS = {}
  SetOverrideBindingClick = function(_, _, key, name) _BINDS[#_BINDS+1] = key end
  K.SetWheelModifier('CTRL')
  _WH = K.WheelModifier() .. ' ' .. table.concat(_BINDS, ',')
  CueTheCashierDB.settings.oneKeyWheel = true
  _WH = _WH .. ' | old true -> ' .. K.WheelModifier()
  K.SetWheelModifier('off')
  _WH = _WH .. ' | ' .. K.WheelModifier()
""")
print("wheel:", lua.eval("_WH"))
print("one key:", lua.eval("_OK1"), "|", lua.eval("_OK2"))
print("destroy:", lua.eval("_D"))
lua.execute("""
  local API = CueTheCashier.API
  local g = API.CreateGroup('Bank stuff')
  API.AddItemToGroup(g, 2318); API.AddItemToGroup(g, 10940)
  API.CreateOperation('bank', 'Keep 5')
  API.SetOperationValue('bank', 'Keep 5', 'keepInBags', 5)
  API.SetOperationValue('bank', 'Keep 5', 'takeToBags', 12)
  API.SetGroupOperation(g, 'bank', 'Keep 5')
  _BANKG = g
  NUM_BAG_SLOTS = 4; NUM_TOTAL_EQUIPPED_BAG_SLOTS = 5; NUM_BANKBAGSLOTS = 7; BANK_CONTAINER = -1
  _BAGS = { [0] = { { itemID = 2318, stackCount = 20 }, false, false },
            [-1] = { { itemID = 10940, stackCount = 8 }, false, false, false } }
  C_Container.GetContainerNumSlots = function(b) return _BAGS[b] and #_BAGS[b] or 0 end
  C_Container.GetContainerItemInfo = function(b, s) return _BAGS[b] and _BAGS[b][s] or nil end
  function C_Container.PickupContainerItem(b, s)
    if _CUR then _BAGS[b][s] = _CUR; _CUR = nil else _CUR = _BAGS[b][s]; _BAGS[b][s] = false end
  end
  function C_Container.SplitContainerItem(b, s, n)
    local it = _BAGS[b][s]; it.stackCount = it.stackCount - n; _CUR = { itemID = it.itemID, stackCount = n }
  end
  function ClearCursor() _CUR = nil end
  BankFrame = _MOCK.NewWidget('Frame', 'BankFrame')
  _MOCK.FireEvent('BANKFRAME_OPENED')
  CueTheCashier.BankMoves.Start('bank', 'ops')
""")
M.RunTimers(10)
lua.execute("""
  local function Dump()
    local t = {}
    for _, b in ipairs({ 0, -1 }) do for s, it in ipairs(_BAGS[b]) do if it then t[#t+1] = b .. ':' .. it.itemID .. 'x' .. it.stackCount end end end
    return table.concat(t, ' ')
  end
  _BM1 = Dump()
  CueTheCashier.BankMoves.Start('bags', 'ops')
  _DUMP = Dump
""")
M.RunTimers(10)
lua.execute("_BM2 = _DUMP(); local b = CueTheCashier.BankMoves.button; b.__scripts.OnClick(b)")
print("bank to bank:", lua.eval("_BM1"), "| to bags:", lua.eval("_BM2"))
check(lua, "0.35 disenchant tooltip, destroy, bank")
# 0.36: accounting extras, gold history, inventory tab, cooldowns
lua.execute("_MOCK.FireEvent('MAIL_SHOW')")
M.RunTimers(2)
lua.execute("""
  local ns = _MOCK.addons.CueTheCashier_Accounting.ns
  local L = ns.Ledger
  -- repairs: at a merchant, gold goes down and no item changes
  _MONEY = 100000
  GetMoney = function() return _MONEY end
  L.StartMerchant()
  _MONEY = 99000
  L:MerchantChanged()
  -- postage
  GetSendMailPrice = function() return 60 end
  L.MailSending('Altie'); L.MailSent()
  -- trade
  GetPlayerTradeMoney = function() return 0 end
  GetTargetTradeMoney = function() return 5000 end
  ERR_TRADE_COMPLETE = 'Trade complete.'
  L.TradeShown(); L.TradeChanged(); L.InfoMessage('Trade complete.')
  -- sale mail with cut, and an expired auction
  _INBOX = {
    { subject = 'Auction successful: Light Leather', inv = { 'seller', 'Light Leather', 'Bob', 1000, 0, 0, 50, 0, 0, 5 } },
    { subject = 'Auction expired: Light Leather', item = { 'Light Leather', 2318, nil, 10 } },
  }
  AUCTION_EXPIRED_MAIL_SUBJECT = 'Auction expired: %s'; AUCTION_REMOVED_MAIL_SUBJECT = 'Auction cancelled: %s'
  function GetInboxNumItems() return #_INBOX end
  function GetInboxHeaderInfo(i) return nil, nil, 'x', _INBOX[i].subject, 0, 0, 20, 1 end
  function GetInboxInvoiceInfo(i) if _INBOX[i].inv then return unpack(_INBOX[i].inv) end end
  function GetInboxItem(i, a) if a == 1 and _INBOX[i].item then return unpack(_INBOX[i].item) end end
  L:ScanMail(); L:ScanMail()
  local byKind, income, costs = L:OtherTotals()
  local t = {}
  for k, v in pairs(byKind) do t[#t+1] = k .. '=' .. v end
  table.sort(t)
  _OT = table.concat(t, ' ') .. ' | in ' .. income .. ' out ' .. costs
  -- profit per item
  L:AddBought(2318, 'Light Leather', 10, 300, 'AH')
  local list = L:Summary()
  for _, it in ipairs(list) do if it.id == 2318 then _PI = 'avgBuy ' .. tostring(it.avgBuy) .. ' avgSell ' .. tostring(it.avgSell) .. ' resale ' .. tostring(it.resale) end end
""")
print("other:", lua.eval("_OT"))
print("profit per item:", lua.eval("_PI"))
lua.execute("CueTheCashier.MainWindow:Select('ledger')")
lua.execute("""
  local page = CueTheCashier.MainWindow.tabs.ledger.page
  for i = 3, 4 do page.viewButtons[i].__scripts.OnClick(page.viewButtons[i]) end
  _LS = page.summary:GetText()
""")
print("ledger other summary:", lua.eval("_LS"))
lua.execute("""
  local H = CueTheCashier.GoldHistory
  local key = CueTheCashier:GetAuctionKey()
  local today = H.DayStart()
  H.Record(key, 'Malaeiel', 100000)
  CueTheCashierDB.goldHistory[key]['Malaeiel'][today - 2 * 86400] = 50000
  CueTheCashierDB.goldHistory[key]['Altie'] = { [today - 1 * 86400] = 20000 }
  local s = H.Series(4)
  local t = {} for _, p in ipairs(s) do t[#t+1] = tostring(p.copper) end
  _GS = table.concat(t, ',')
  s = H.Series(4, 'Altie')
  t = {} for _, p in ipairs(s) do t[#t+1] = tostring(p.copper) end
  _GS = _GS .. ' | Altie ' .. table.concat(t, ',')
""")
lua.execute("CueTheCashier.MainWindow:Select('gold')")
print("gold series:", lua.eval("_GS"))
lua.execute("""
  local ns = _MOCK.addons.CueTheCashier_Crafting.ns
  local server = CueTheCashier.API.GetServerKey()
  ns.db.chars['Altie - ' .. server] = { profs = {}, known = {}, inv = { bags = { [2318] = 3 }, bank = { [10940] = 7 }, mail = {}, auctions = { [2318] = 2 } },
    cooldowns = { [999] = { name = 'Transmute: Arcanite', readyAt = time() - 10 } } }
  local rows, sum = ns.InventoryTab.Rows('Altie')
  local t = {} for _, r in ipairs(rows) do t[#t+1] = r.id .. ' bags ' .. r.bags .. ' bank ' .. r.bank .. ' auc ' .. r.auctions .. ' total ' .. r.total end
  table.sort(t)
  _IV = table.concat(t, '; ') .. ' | chars ' .. #ns.InventoryTab.Characters()
  C_TradeSkillUI = C_TradeSkillUI or {}
  C_TradeSkillUI.GetAllRecipeIDs = function() return { 555 } end
  C_TradeSkillUI.GetRecipeCooldown = function(id) return 3600 * 20, true, 0, 0 end
  C_TradeSkillUI.GetRecipeInfo = function(id) return { name = 'Mooncloth' } end
  ns.Cooldowns.Scan()
  local t2 = {} for _, e in ipairs(ns.Cooldowns.All()) do t2[#t2+1] = e.name .. '@' .. e.char .. (e.readyAt <= time() and ' ready' or ' later') end
  _CD = table.concat(t2, ', ')
  ns.Cooldowns.ReportReady()
""")
lua.execute("CueTheCashier.MainWindow:Select('inventory')")
lua.execute("CueTheCashier.MainWindow:Select('overview')")
print("inventory:", lua.eval("_IV"), "| cooldowns:", lua.eval("_CD"))
check(lua, "0.36 accounting, gold, inventory, cooldowns")
# 0.37: server rules, sale rate, skins
lua.execute("""
  local CM = CueTheCashier
  Enum.GameRule = { HardcoreRuleset = 1, RPRuleset = 2, PvPRuleset = 3 }
  _RULES = {}
  C_GameRules.IsGameRuleActive = function(r) return _RULES[r] or false end
  local t = {}
  t[#t+1] = CM.ServerType()
  _RULES = { [3] = true }; t[#t+1] = CM.ServerType()
  _RULES = { [2] = true, [3] = true }; t[#t+1] = CM.ServerType()
  _RULES = { [1] = true }; t[#t+1] = CM.ServerType()
  _RULES = {}
  CM.RecordServer()
  _SR = table.concat(t, ',') .. ' | name ' .. CM.ServerName() .. ' | old ' .. CM.OldServerName()
  -- a PvP server with number 4: old name "EU Preset 4", new "EU PvP"
  C_GameRules.GetForeverExperiencePreset = function() return 4 end
  _RULES = { [3] = true }
  CueTheCashierDB.realms['EU Preset 4 - Alliance'] = { lastScan = 5, items = {} }
  CM.MoveRenamedServerData()
  CM.RecordServer()
  _SR = _SR .. ' | pvp key ' .. CM:GetAuctionKey() .. ' moved ' .. tostring(CueTheCashierDB.realms['EU PvP - Alliance'] and CueTheCashierDB.realms['EU PvP - Alliance'].lastScan)
  -- without the rule API the saved number still names it
  local f = C_GameRules.IsGameRuleActive; C_GameRules.IsGameRuleActive = nil
  _SR = _SR .. ' | learned ' .. CM.ServerName()
  C_GameRules.IsGameRuleActive = f
  C_GameRules.GetForeverExperiencePreset = function() return 1 end
  _RULES = {}
  local i = CM.API.GetServerInfo()
  _SR = _SR .. ' | info ' .. tostring(i.id) .. ' ' .. tostring(i.type)
""")
print("server rules:", lua.eval("_SR"))
lua.execute("""
  CueTheCashier.GetItemEntry = _REALENTRY
  local L = _MOCK.addons.CueTheCashier_Accounting.ns.Ledger
  L:AddSold(2318, 'Light Leather', 5, 900, 'AH')
  L:AddSold(2318, 'Light Leather', 5, 900, 'AH')
  local n = L:SaleRates()
  local rate, from = CueTheCashier.API.GetSaleRate(2318)
  _RATE = n .. ' items, 2318 = ' .. tostring(rate) .. ' (' .. tostring(from) .. ')'
  GameTooltip.lines = {}; _MOCK.tooltipPost(GameTooltip, { id = 2318 })
  for _, l in ipairs(GameTooltip.lines) do if l:find('Sale rate') then _RATE = _RATE .. ' | ' .. l end end
""")
print("sale rate:", lua.eval("_RATE"))
lua.execute("""
  local S = CueTheCashier.Skins
  S:Set('Dark')
  local tex = { SetColorTexture = function(self, r, g, b, a) self.c = r .. ',' .. g .. ',' .. b .. ',' .. a end }
  S:Paint(tex, 'highlight'); local h = tex.c
  S:Stripe(tex, 2); local st = tex.c
  S:Register('Half', { colors = { highlight = { 0, 1, 0, 0.2 } } })
  S:Set('Half'); S:Paint(tex, 'selected')
  _SK = 'dark hl ' .. h .. ' stripe ' .. st .. ' | partial skin selected ' .. tex.c .. ' button ' .. S:Get().buttonTemplate
  S:Set('Blizzard')
""")
lua.execute("CueTheCashier.MainWindow:Select('settings')")
print("skins:", lua.eval("_SK"))
slash(lua, "realm")
check(lua, "0.37 server rules, sale rate, skins")
# ---------- 0.40: placement (fake frames with rects) ----------
lua.execute("""
  local function F(name, l, b, w, h, parent, opts)
    opts = opts or {}
    local f = { name = name, l = l, b = b, w = w, h = h, parent = parent, kids = {}, shown = true, points = {} }
    function f:GetRect() return self.l, self.b, self.w, self.h end
    function f:GetEffectiveScale() return 1 end
    function f:GetEffectiveAlpha() return 1 end
    function f:IsVisible() return self.shown end
    function f:IsShown() return self.shown end
    function f:IsMouseEnabled() return opts.mouse ~= false end
    function f:IsObjectType() return false end
    function f:GetParent() return self.parent end
    function f:GetName() return self.name end
    function f:GetChildren() return unpack(self.kids) end
    function f:GetNumPoints() return #self.points end
    function f:GetPoint(i) local p = self.points[i]; return p[1], p[2] end
    function f:ClearAllPoints() self.points = {} end
    function f:SetPoint(p, rel, rp, x, y)
      self.points[#self.points + 1] = { p, rel }
      -- tiny layout: TOPRIGHT of host inside, or under it
      if rp == 'TOPRIGHT' then self.l, self.b = rel.l + rel.w + x - self.w, rel.b + rel.h + y - self.h
      elseif rp == 'BOTTOMRIGHT' then self.l, self.b = rel.l + rel.w + x - self.w, rel.b + y - self.h end
    end
    if parent then table.insert(parent.kids, f) end
    return f
  end
  local oldUI = UIParent
  local ui = F('UIParent', 0, 0, 2000, 1200)
  UIParent = ui
  local host = F('MerchantFrame', 100, 300, 400, 500, ui)
  local theirs = F('OtherAddonButton', 360, 750, 120, 22, host) -- top right, where ours wants to go
  local ours = F(nil, 0, 0, 130, 22, host)
  local i, free = CueTheCashier.Place.Check(ours, host, {
    { 'TOPRIGHT', host, 'TOPRIGHT', -12, -30 },
    { 'TOPRIGHT', host, 'BOTTOMRIGHT', -12, -2 } }, { name = 'test' })
  _PL = 'spot ' .. tostring(i) .. ' free ' .. tostring(free)
  theirs.shown = false
  i, free = CueTheCashier.Place.Check(ours, host, {
    { 'TOPRIGHT', host, 'TOPRIGHT', -12, -30 },
    { 'TOPRIGHT', host, 'BOTTOMRIGHT', -12, -2 } }, { name = 'test' })
  _PL = _PL .. ' | their button hidden: spot ' .. tostring(i) .. ' free ' .. tostring(free)
  -- a docked panel of another addon, anchored to the window (not inside it)
  theirs.shown = true; theirs.l = 0; theirs.b = 0
  local dock = F('OtherDock', 100, 180, 400, 120, ui)
  dock.points = { { 'TOP', host } }
  i, free = CueTheCashier.Place.Check(ours, host, {
    { 'TOPRIGHT', host, 'BOTTOMRIGHT', -12, -2 },
    { 'TOPRIGHT', host, 'TOPRIGHT', -12, -30 } }, { name = 'test' })
  _PL = _PL .. ' | docked panel below: spot ' .. tostring(i) .. ' free ' .. tostring(free)
  UIParent = oldUI
""")
print("placement (want spot 2 free true | spot 1 free true | spot 2 free true):", lua.eval("_PL"))
check(lua, "0.40 placement")
# ---------- 0.41: old saved variable names are adopted ----------
lua, M = new_runtime(legacy="""
CraftMarketDB = { dbVersion = 3, realms = { ["EU Normal - Alliance"] = { lastScan = 1699990000, items = {
  [2318] = { minBuyout = 37, marketValue = 40, seenInLastScan = true } } } }, settings = { skin = "Blizzard" }, itemInfo = {} }
CraftMarketAccountingDB = { ledger = { x = 1 } }
""")
startup(lua, M)
lua.execute("""
  _AD = 'old core nil: ' .. tostring(CraftMarketDB == nil) .. ', price 2318: ' .. tostring(CueTheCashier:GetMinBuyout(2318))
  CueTheCashier.AdoptOldSaved('CueTheCashierAccountingDB')
  _AD = _AD .. ', ledger moved: ' .. tostring(CueTheCashierAccountingDB and CueTheCashierAccountingDB.ledger.x) .. ', old ledger nil: ' .. tostring(CraftMarketAccountingDB == nil)
  _AD = _AD .. ', fresh hint: ' .. tostring(CueTheCashier.freshDB)
  _AD = _AD .. ', old export imports: ' .. tostring((CueTheCashier.API.ImportGroups('CraftMarket groups 1\\ngroup: Old; priority 60\\nitems: 2318@70')))
""")
print("adopt old saved:", lua.eval("_AD"))
check(lua, "0.41 old saved variables")
print("TOTAL ERRORS:", TOTAL_ERR)

# ---------- Scenario 0.42: defaults, base operations, None, list order, supply, timer ----------
lua, M = new_runtime()
startup(lua, M)
lua.execute("""
  local API = CueTheCashier.API
  _B = {}
  for _, k in ipairs({ 'post', 'shop', 'craft', 'mail', 'vendor', 'bank' }) do
    _B[#_B+1] = k .. '=' .. tostring((API.GetGroupOperation(0, k)))
  end
  _UC = API.GetOperation('post', 'Base').undercut
  _MP = API.GetOperation('craft', 'Base').minProfit .. ' max ' .. API.GetOperation('craft', 'Base').maxCraft
  _VS = tostring(API.GetOperation('vendor', 'Base').sell)
  local g = API.CreateGroup('Mats')
  API.AddItemToGroup(g, 2318)
  _G0 = tostring((API.GetItemOperation(4444, 'post'))) .. '/' .. tostring((API.GetItemOperation(4444, 'mail')))
  _G1 = tostring((API.GetItemOperation(2318, 'post')))
  API.SetGroupOperation(g, 'post', false)
  _G2 = tostring((API.GetItemOperation(2318, 'post')))
  local sub = API.CreateGroup('Sub', g)
  API.AddItemToGroup(sub, 2318)
  _G3 = tostring((API.GetItemOperation(2318, 'post')))
  -- deleting Base stays deleted after a reload of the profile table
  API.DeleteOperation('mail', 'Base')
  _G4 = tostring(API.GetOperation('mail', 'Base'))
  -- supply from a scan
  CueTheCashier.Data:Record({ [2318] = { prices = { 10, 5, 11, 5, 15, 10, 40, 100 }, sellers = 1 } }, 'full', 4)
  local a, b = API.GetAuctionSupply(2318, 12)
  local c = API.GetAuctionSupply(2318, 15)
  local d = API.GetAuctionSupply(2318, 9)
  local e = API.GetAuctionSupply(2318, 1000)
  _SUP = table.concat({ tostring(a), tostring(b), tostring(c), tostring(d), tostring(e) }, ' ')
  _NAME = tostring(API.GetItemName(2318))
""")
lua.execute("""
  SendMailFrame = _MOCK.NewWidget('Frame', 'SendMailFrame'); SendMailFrame:Show()
  SendMailNameEditBox = _MOCK.NewWidget('EditBox', 'SendMailNameEditBox')
  CueTheCashierDB.gold = { [CueTheCashier:GetAuctionKey()] = { Altie = 5, Malaeiel = 9 } }
  SendMail = SendMail or function() end
  CueTheCashier.MailTo.Update()
  _MT1 = tostring(CueTheCashierMailToButton ~= nil)
""")
lua.execute("if SendMail then SendMail('Bob Smith', 'hi', '') end")
M.FireEvent("MAIL_SEND_SUCCESS")
print("0.42.3 mail arrow made:", lua.eval("_MT1"), "| recent:", lua.eval("table.concat(CueTheCashierDB.recentMail and CueTheCashierDB.recentMail[CueTheCashier:GetAuctionKey()] or {}, ',')"))
print("0.42 base ops:", lua.eval("table.concat(_B, ' ')"), "| undercut", lua.eval("_UC"), "| craft", lua.eval("_MP"), "| vendor sell", lua.eval("_VS"))
print("0.42.1 ungrouped post/mail (want Base/nil):", lua.eval("_G0"))
print("0.42 none:", lua.eval("_G1"), lua.eval("_G2"), lua.eval("_G3"), "| deleted mail Base:", lua.eval("_G4"))
print("0.42 supply (<=12, exact, <=15, <=9, all):", lua.eval("_SUP"), "| name:", lua.eval("_NAME"))
check(lua, "0.42 defaults and base operations")
print("TOTAL ERRORS (all):", TOTAL_ERR)

# ---------- Scenario 0.43: own sale numbers on all servers, region prices ----------
lua, M = new_runtime()
startup(lua, M)
lua.execute("""
  local now = time()
  CueTheCashierDB.realms['EU PvP - Horde'] = { lastScan = now, items = {
    [2318] = { minBuyout = 50, marketValue = 60, lastSeen = now - 3600, month = { market = 58, min = 48, n = 5 } } } }
  CueTheCashierDB.realms['US Normal - Alliance'] = { lastScan = now, items = {
    [2318] = { minBuyout = 9999, marketValue = 9999, lastSeen = now } } }
  CueTheCashierDB.realms['EU Roleplay - Alliance'] = { lastScan = now, items = {
    [2318] = { minBuyout = 1, marketValue = 1, lastSeen = now - 40 * 86400 } } }
  CueTheCashier.Data:Record({ [2318] = { prices = { 40, 10, 44, 10 }, sellers = 2 } }, 'full', 2)
  C_AddOns.LoadAddOn('CueTheCashier_Accounting')
  local ns = _MOCK.addons.CueTheCashier_Accounting.ns
  local L = ns.Ledger
  L:AddSold(2318, 'Light Leather', 10, 380, 'AH')
  L:AddSold(2318, 'Light Leather', 10, 420, 'AH')
  L:AddOther('Expired', -2, '5 x Light Leather (deposit, estimate)')
  ns.db.ledger['EU PvP - Horde'] = { bought = {}, mails = {}, other = {
      { t = now - 86400 * 9, kind = 'Expired', money = 0, note = '5 x Light Leather (deposit, estimate)' } },
    sold = { { t = now - 86400 * 9, id = 2318, name = 'Light Leather', qty = 20, money = 1000, source = 'AH', char = 'Z' } } }
  ns.db.ledger['US Normal - Alliance'] = { bought = {}, mails = {}, other = {},
    sold = { { t = now, id = 2318, name = 'Light Leather', qty = 99, money = 99999, source = 'AH', char = 'Q' } } }
  _N = L:SaleRates()
  local API = CueTheCashier.API
  local out = {}
  for _, k in ipairs({ 'sale.rate', 'sale.perday', 'sale.avg', 'region.market', 'region.min', 'region.salerate', 'region.perday', 'region.saleavg' }) do
    out[#out+1] = k .. '=' .. tostring(API.GetPrice(2318, k)) .. ' [' .. tostring(API.FormatSourceValue(k, API.GetPrice(2318, k))) .. ']'
  end
  _SRC = table.concat(out, ' ')
  _F = tostring(API.EvaluatePrice('regionmarket * salerate', 2318)) .. ' / ' .. tostring(API.EvaluatePrice('first(regionsaleavg, 1g)', 2318))
  local r = API.GetRegionStats(2318)
  _R = 'servers ' .. r.servers .. ' (' .. table.concat(r.keys, ', ') .. ') other ' .. tostring(r.otherServers)
  GameTooltip.lines = {}; _MOCK.tooltipPost(GameTooltip, { id = 2318 })
  _TT = table.concat(GameTooltip.lines, ' || ')
  CueTheCashierAppData = { time = now, region = { EU = { [2318] = { market = 77, saleRate = 0.9 } } } }
  local a = API.GetRegionStats(2318)
  _APP = tostring(a.market) .. ' ' .. tostring(a.rate) .. ' ' .. tostring(a.fromApp) .. ' min ' .. tostring(a.min)
  CueTheCashierAppData = nil
  -- No sale data and no prices: nothing
  _NONE = tostring(API.GetRegionStats(123456)) .. ' ' .. tostring(API.GetPrice(123456, 'sale.rate'))
""")
print("0.43 rated items here:", lua.eval("_N"))
print("0.43 sources:", lua.eval("_SRC"))
print("0.43 formulas (regionmarket*salerate, regionsaleavg):", lua.eval("_F"))
print("0.43 region:", lua.eval("_R"))
print("0.43 tooltip:", lua.eval("_TT"))
print("0.43 app data:", lua.eval("_APP"), "| unknown item:", lua.eval("_NONE"))
slash(lua, "region 2318"); slash(lua, "price 2318"); slash(lua, "sources 2318")
check(lua, "0.43 sale and region")
print("TOTAL ERRORS (all):", TOTAL_ERR)

# ---------- Scenario 0.44: shared commodity prices across server types ----------
lua, M = new_runtime()
startup(lua, M)
lua.execute("""
  local CM, API = CueTheCashier, CueTheCashier.API
  local out = {}
  local function P(s) out[#out+1] = s end
  CueTheCashierDB.itemInfo[9999] = { name = 'Sword', stack = 1 }
  CM.Data:Record({ [2318] = { prices = { 40, 10 }, sellers = 1 }, [9999] = { prices = { 5000, 1 }, sellers = 1 } }, 'full', 2)
  local sk = CM.SharedKey()
  P('key ' .. sk)
  P('shared has 2318 ' .. tostring(CueTheCashierDB.realms[sk].items[2318] ~= nil) .. ', 9999 ' .. tostring(CueTheCashierDB.realms[sk].items[9999] ~= nil))
  P('own has both ' .. tostring(CM:GetRealmData().items[2318] ~= nil and CM:GetRealmData().items[9999] ~= nil))
  P('shared history ' .. tostring(#CM.Data:History()[sk][2318]))
  -- another server type
  local real = CM.GetAuctionKey
  CM.GetAuctionKey = function() return 'EU PvP - Horde' end
  P('PvP sees 2318 ' .. tostring(API.GetPrice(2318, 'auction.min')) .. ', sword ' .. tostring(API.GetPrice(9999, 'auction.min')))
  -- older data from before 0.44 on Roleplay, newer than the shared copy
  _MOCK.now = _MOCK.now + 100
  CueTheCashierDB.realms['EU Roleplay - Alliance'] = { lastScan = _MOCK.now, items = { [2318] = { minBuyout = 33, lastSeen = _MOCK.now } } }
  P('newest wins ' .. tostring(API.GetPrice(2318, 'auction.min')))
  _MOCK.now = _MOCK.now + 100
  CM.Data:Record({ [2318] = { prices = { 55, 10 }, sellers = 1 } }, 'test', 1)
  P('after PvP scan ' .. tostring(API.GetPrice(2318, 'auction.min')))
  CueTheCashierDB.settings.sharedCommodities = false
  P('off: PvP own ' .. tostring(API.GetPrice(2318, 'auction.min')))
  CM.GetAuctionKey = real
  P('off: Normal own ' .. tostring(API.GetPrice(2318, 'auction.min')))
  CueTheCashierDB.settings.sharedCommodities = nil
  P('on: Normal ' .. tostring(API.GetPrice(2318, 'auction.min')) .. ' 7d ' .. tostring(API.GetPrice(2318, 'auction.min.7d')))
  P('region servers ' .. tostring(API.GetRegionStats(2318).servers))
  _OUT44 = table.concat(out, ' | ')
""")
print("0.44:", lua.eval("_OUT44"))
slash(lua, "region 2318")
check(lua, "0.44 shared commodities")
print("TOTAL ERRORS (all):", TOTAL_ERR)
