-- Minimal fake WoW client for load/event tests (Lua 5.1).
local M = {}
_MOCK = M
M.printed, M.errors, M.timers, M.now = {}, {}, {}, 1700000000
M.allFrames = {}
M.addons = {}       -- name -> { files = {...}, lod = bool, meta = {}, loaded = bool, dir = path, deps }
M.addonOrder = {}

local function noop() end

-- Generic widget ------------------------------------------------------
local Widget = {}
local function NewWidget(kind, name)
  local w = setmetatable({ __kind = kind, __shown = true, __events = {}, __scripts = {}, __points = {},
    __text = "" }, Widget)
  if name then _G[name] = w end
  M.allFrames[#M.allFrames + 1] = w
  return w
end
M.NewWidget = NewWidget
local methods = {
  RegisterEvent = function(self, e)
    if type(e) ~= "string" or e:find("^CM_") then error("bad event " .. tostring(e)) end
    self.__events[e] = true
  end,
  UnregisterEvent = function(self, e) self.__events[e] = nil end,
  UnregisterAllEvents = function(self) self.__events = {} end,
  IsEventRegistered = function(self, e) return self.__events[e] or false end,
  SetScript = function(self, k, f) self.__scripts[k] = f end,
  GetScript = function(self, k) return self.__scripts[k] end,
  HookScript = function(self, k, f)
    local old = self.__scripts[k]
    self.__scripts[k] = function(...) if old then old(...) end f(...) end
  end,
  Show = function(self)
    local was = self.__shown; self.__shown = true
    if not was and self.__scripts.OnShow then self.__scripts.OnShow(self) end
  end,
  Hide = function(self)
    local was = self.__shown; self.__shown = false
    if was and self.__scripts.OnHide then self.__scripts.OnHide(self) end
  end,
  SetShown = function(self, v) if v then self:Show() else self:Hide() end end,
  IsShown = function(self) return self.__shown end,
  IsVisible = function(self) return self.__shown end,
  SetText = function(self, t) self.__text = t end,
  GetText = function(self) return self.__text end,
  GetNumPoints = function() return 0 end,
  GetWidth = function() return 800 end, GetHeight = function() return 500 end,
  GetLeft = function() return 10 end, GetTop = function() return 700 end,
  GetFrameLevel = function() return 1 end, GetFrameStrata = function() return "MEDIUM" end,
  GetRegions = function() return end, GetChildren = function() return end,
  GetObjectType = function(self) return self.__kind end,
  GetParent = function(self) return self.__parent end,
  SetParent = function(self, p) self.__parent = p end,
  SetAttribute = function(self, k, v) self.__attrs = self.__attrs or {}; self.__attrs[k] = v end,
  GetAttribute = function(self, k) return self.__attrs and self.__attrs[k] end,
  GetEffectiveScale = function() return 1 end, GetCenter = function() return 0, 0 end,
  GetNumber = function() return 0 end, HasFocus = function() return false end,
  GetVerticalScrollRange = function() return 0 end, GetChecked = function() return false end,
  IsEnabled = function() return true end, GetID = function(self) return self.__id or 0 end,
  SetID = function(self, id) self.__id = id end,
  GetStringWidth = function() return 50 end,
  SetElementInitializer = function(self, _, fn) self.__init = fn end,
  SetDataProvider = function(self, dp) self.__dp = dp end,
}
Widget.__index = function(self, k)
  if methods[k] then return methods[k] end
  if type(k) ~= "string" or not k:find("^%u") then return nil end -- fields are nil
  if type(k) == "string" and (k:find("^Create") or k:find("Texture$") or k:find("^Get.*Frame$")) then
    return function(self2, ...) local w = NewWidget("Region"); w.__parent = self2; return w end
  end
  if type(k) == "string" and k:find("^Get") then return function() return nil end end
  if type(k) == "string" and k:find("^Is") then return function() return false end end
  return noop
end

function CreateFrame(kind, name, parent, template)
  local f = NewWidget(kind, name)
  f.__parent = parent
  if template and template:find("PortraitFrame") then f.CloseButton = NewWidget("Button") end
  if template and template:find("SearchBox") then f.Instructions = NewWidget("FontString") end
  return f
end

function M.FireEvent(event, ...)
  local list = {}
  for _, f in ipairs(M.allFrames) do
    if f.__events[event] and f.__scripts.OnEvent then list[#list + 1] = f end
  end
  for _, f in ipairs(list) do
    local ok, err = pcall(f.__scripts.OnEvent, f, event, ...)
    if not ok then M.errors[#M.errors + 1] = event .. ": " .. tostring(err) end
  end
end

-- Globals --------------------------------------------------------------
UIParent = NewWidget("Frame", "UIParent")
Minimap = NewWidget("Frame", "Minimap")
GameTooltip = NewWidget("GameTooltip", "GameTooltip")
GameTooltip.lines = {}
GameTooltip.AddLine = function(self, t) self.lines[#self.lines + 1] = tostring(t) end
GameTooltip.AddDoubleLine = function(self, a, b) self.lines[#self.lines + 1] = tostring(a) .. " | " .. tostring(b) end
GameTooltip.SetOwner = function(self) self.lines = {} end
ItemRefTooltip = NewWidget("GameTooltip", "ItemRefTooltip")
UISpecialFrames = {}
StaticPopupDialogs = {}
M.popups = {}
function StaticPopup_Show(which, text, _, data)
  M.popups[#M.popups + 1] = { which = which, text = text, data = data }
end
SlashCmdList = {}
function print(...) local t = {} for i = 1, select("#", ...) do t[#t + 1] = tostring((select(i, ...))) end
  M.printed[#M.printed + 1] = table.concat(t, " ") end
function geterrorhandler() return function(e) M.errors[#M.errors + 1] = "handler: " .. tostring(e) end end
function hooksecurefunc(a, b, c)
  if type(a) == "string" then a, b, c = _G, a, b end
  local old = a[b]
  if type(old) ~= "function" then return end
  a[b] = function(...) local r = { old(...) } c(...) return unpack(r) end
end
function time(t) if t then return os.time(t) end return M.now end
function GetTime() return M.now end
local realdate = os.date
function date(fmt, t) return realdate(fmt, t or M.now) end
function debugstack() return "" end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function BreakUpLargeNumbers(n) return tostring(n) end
function GetBuildInfo() return "1.60.1", "71037", "", 16001 end
function GetRealmName() return "" end
function GetCurrentRegionName() return "EU" end
function UnitFactionGroup() return "Alliance" end
function UnitName() return "Malaeiel" end
function UnitFullName() return "Malaeiel", "Nightwalker" end
function UnitReaction() return 4 end
function GetMoney() return M.money or 100000 end
function IsLoggedIn() return M.loggedIn end
function GetCursorPosition() return 0, 0 end
C_GameRules = { GetForeverExperiencePreset = function() return 1 end, IsHardcoreActive = function() return false end,
  IsSelfFoundAllowed = function() return false end }
Enum = { TooltipDataType = { Item = 0 }, TooltipDataLineType = { SellPrice = 11 },
  AuctionHouseSortOrder = { Price = 0, Name = 1 }, ItemQuality = {} }
M.tooltipPosts = {}
M.tooltipPost = function(tt, data) for _, fn in ipairs(M.tooltipPosts) do fn(tt, data) end end
TooltipDataProcessor = { AddTooltipPostCall = function(_, fn) M.tooltipPosts[#M.tooltipPosts + 1] = fn end }
C_Timer = { After = function(d, f) M.timers[#M.timers + 1] = { d = d, f = f } end,
  NewTicker = function(d, f) return { Cancel = noop } end, NewTimer = function(d, f) return { Cancel = noop } end }
function M.RunTimers(rounds)
  for _ = 1, rounds or 3 do
    local list = M.timers; M.timers = {}
    for _, t in ipairs(list) do
      local ok, err = pcall(t.f)
      if not ok then M.errors[#M.errors + 1] = "timer: " .. tostring(err) end
    end
  end
end
M.items = { [2318] = { "Light Leather", 1, 15, 10 }, [10940] = { "Strange Dust", 1, 10, 7 } }
C_Item = {
  GetItemInfo = function(id)
    local i = M.items[id]; if not i then return nil end
    return i[1], "|Hitem:" .. id .. "|h[" .. i[1] .. "]|h", i[2], i[3], 1, "Trade", "Leather", 20, "", 1, i[4], 7, 0
  end,
  GetItemInfoInstant = function(id) return id, "Trade", "Leather", "", 1, 7, 0 end,
  GetItemNameByID = function(id) local i = M.items[id]; return i and i[1] end,
  RequestLoadItemDataByID = noop, GetItemClassInfo = function(c) return "Class" .. c end,
  GetItemSubClassInfo = function() return "Sub" end,
}
C_TooltipInfo = { GetItemByID = function(id) return { lines = { { leftText = "x" }, { type = 11, price = 10 } } } end }
C_Container = { GetContainerNumSlots = function() return 0 end, GetContainerItemInfo = function() return nil end }
C_AuctionHouse = setmetatable({
  MakeItemKey = function(id) return { itemID = id, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 } end,
  GetBrowseResults = function() return {} end, IsThrottledMessageSystemReady = function() return true end,
  GetNumReplicateItems = function() return 0 end, GetAuctionItemSubClasses = function() return {} end,
  GetNumCommoditySearchResults = function() return 0 end, GetNumItemSearchResults = function() return 0 end,
  GetOwnedAuctions = function() return {} end, GetBids = function() return {} end,
  GetNumOwnedAuctions = function() return 0 end, GetNumBids = function() return 0 end,
}, { __index = function() return noop end })
NUM_BAG_SLOTS = 4
function GetInboxNumItems() return 0 end
function GetInboxInvoiceInfo() return nil end
function CreateDataProvider(t) return { t = t } end
function CreateScrollBoxListLinearView() return NewWidget("View") end
ScrollUtil = { InitScrollBoxListWithScrollBar = function(box, bar, view) box.__view = view end }
function PanelTemplates_SetNumTabs() end
function PanelTemplates_SetTab() end
function GameTooltip_Hide() end
function GetCursorInfo() return nil end
function ClearCursor() end
function MoneyFrame_Update() end
function MoneyInputFrame_SetCopper() end
function MoneyInputFrame_GetCopper() return 0 end
ITEM_QUALITY_COLORS = {}
SEARCH = "Search"
AuctionCategories = {}

-- Addon loading ----------------------------------------------------------
function M.RegisterAddon(name, dir, files, meta, lod)
  M.addons[name] = { name = name, dir = dir, files = files, meta = meta, lod = lod, loaded = false, ns = {} }
  M.addonOrder[#M.addonOrder + 1] = name
end
function M.LoadFiles(name)
  local a = M.addons[name]
  for _, f in ipairs(a.files) do
    if f:find("%.lua$") then
      local chunk, err = loadfile(a.dir .. "/" .. f)
      if not chunk then error(err) end
      chunk(name, a.ns)
    end
  end
  a.loaded = true
  M.FireEvent("ADDON_LOADED", name)
end
C_AddOns = {
  GetNumAddOns = function() return #M.addonOrder end,
  GetAddOnInfo = function(i) local n = M.addonOrder[i]; return n, "Title " .. n end,
  GetAddOnMetadata = function(n, field) return M.addons[n] and M.addons[n].meta[field] end,
  IsAddOnLoadOnDemand = function(n) return M.addons[n] and M.addons[n].lod end,
  IsAddOnLoaded = function(n) return M.addons[n] and M.addons[n].loaded or false end,
  LoadAddOn = function(n)
    local a = M.addons[n]
    if not a then return false, "MISSING" end
    if a.disabled then return false, "DISABLED" end
    if not a.loaded then
      M.loadLog = (M.loadLog or "") .. n .. ";"
      M.LoadFiles(n)
    end
    return true
  end,
}
function IsShiftKeyDown() return _MOCK and _MOCK.shift end
function strsplit(sep, s)
  local out = {}
  for part in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do out[#out + 1] = part end
  return unpack(out)
end


function InCombatLockdown() return false end
function ClearOverrideBindings() end
function SetOverrideBindingClick() end
function GetMacroIndexByName() return 0 end
function CreateMacro() return 1 end
function EditMacro() end
return M
