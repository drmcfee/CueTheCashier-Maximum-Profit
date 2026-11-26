-- CueTheCashier: /cmp slash commands.
--
-- The core and every module register their own /cmp commands here. A
-- command of a load-on-demand module that isn't loaded yet (listed in its
-- .toc as ## X-CueTheCashier-Commands) loads the module first.
-- Copyright (C) 2026 Kim. Licensed under the GNU GPL v3 or later; see LICENSE.
local _, CM = ...

local commands, order = {}, {}

-- Where a command lives when its folder is missing, so we can say which
-- folder to install. The .toc files are the real source; this is a hint.
local SHIPPED = {
  fullscan = "CueTheCashier_Auctioning", test = "CueTheCashier_Auctioning", button = "CueTheCashier_Auctioning",
  ledger = "CueTheCashier_Accounting", dis = "CueTheCashier_Destroying", prof = "CueTheCashier_Crafting",
}

-- fn(rest of the line). usage: text for /cmp help, e.g. "/cmp ledger".
function CM.RegisterCommand(name, owner, fn, usage)
  name = name:lower()
  if not commands[name] then order[#order + 1] = name end
  commands[name] = { owner = owner, fn = fn, usage = usage or ("/cmp " .. name) }
end

local function AddonForCommand(name)
  for addon, info in pairs(CM.moduleAddons) do
    for _, c in ipairs(info.commands) do
      if c:lower() == name then return addon end
    end
  end
end

-- Runs one /cmp command (also used by the minimap button). Returns false
-- when there is no such command.
function CM.RunCommand(name, rest)
  name = (name or ""):lower()
  local c = commands[name]
  if not c then
    local addon = AddonForCommand(name)
    if addon and CM.LoadModuleAddon(addon, "/cmp " .. name) then c = commands[name] end
    if not c and (addon or SHIPPED[name]) then
      CM.Print(("/cmp %s needs the %s folder, installed and turned on in the AddOns list."):format(
        name, addon or SHIPPED[name]))
      return true
    end
  end
  if not c then return false end
  if type(c.owner) == "table" and c.owner.IsEnabled and not c.owner:IsEnabled() then
    CM.Print(("/cmp %s: the %s module is turned off."):format(name, tostring(c.owner.name)))
    return true
  end
  local ok, err = pcall(c.fn, rest or "")
  if not ok then CM.ReportError("/cmp " .. name, err) end
  return true
end

local function Help()
  local parts = {}
  for _, name in ipairs(order) do parts[#parts + 1] = commands[name].usage end
  -- Commands of modules that aren't loaded yet.
  local extra = {}
  for _, info in pairs(CM.moduleAddons) do
    for _, c in ipairs(info.commands) do
      if not commands[c:lower()] then extra[#extra + 1] = "/cmp " .. c:lower() end
    end
  end
  table.sort(extra)
  for _, u in ipairs(extra) do parts[#parts + 1] = u end
  CM.Print(table.concat(parts, ", "))
end

SLASH_CRAFTMARKET1 = "/cmp"
SLASH_CRAFTMARKET2 = "/cuethecashier"
-- Old commands from before the rename keep working.
SLASH_CRAFTMARKET3 = "/cm"
SLASH_CRAFTMARKET4 = "/craftmarket"
SlashCmdList.CRAFTMARKET = function(msg)
  local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
  if cmd == "" then
    -- /cmp alone opens the main window; /cmp help lists the commands.
    local ok, err = pcall(CM.MainWindow.Toggle, CM.MainWindow)
    if not ok then CM.ReportError("/cmp", err) end
  elseif cmd:lower() == "help" or not CM.RunCommand(cmd, rest) then
    Help()
  end
end

-- ------------------------------------------------------------------
-- Diagnostics
-- ------------------------------------------------------------------
-- /cmp realm: what the game says about the server. Forever's mega servers
-- leave GetRealmName() empty (seen in game), so this looks for what names
-- the server type ("Normal"). 0.13.0 tried every Get*Realm/Server
-- function; C_Discord ones gave ADDON_ACTION_FORBIDDEN, so now it only
-- calls a fixed list plus the C_GameRules getters.
function CM.RealmReport()
  local function Show(v)
    if type(v) == "table" then
      local parts = {}
      for k, x in pairs(v) do parts[#parts + 1] = tostring(k) .. "=" .. tostring(x) end
      return "{" .. table.concat(parts, ", ") .. "}"
    end
    return ("%q"):format(tostring(v))
  end
  local function Try(label, fn, ...)
    if type(fn) ~= "function" then return end
    local res = { pcall(fn, ...) }
    if not res[1] then return end
    local out = {}
    for i = 2, #res do out[#out + 1] = Show(res[i]) end
    CM.Print(label .. " = " .. (#out > 0 and table.concat(out, ", ") or "(nothing)"))
  end
  Try("UnitFullName(player)", UnitFullName, "player")
  Try("GetRealmName()", GetRealmName)
  Try("GetCurrentRegionName()", GetCurrentRegionName)
  Try("GetRealmID()", GetRealmID)
  local rules = {}
  for name, f in pairs(C_GameRules or {}) do
    if type(f) == "function" and (name:find("^Get") or name:find("^Is")) then rules[#rules + 1] = name end
  end
  table.sort(rules)
  for _, name in ipairs(rules) do Try("C_GameRules." .. name .. "()", C_GameRules[name]) end
  CM.Print(("Server number %s, type from rules: %s."):format(tostring(CM.ServerID()), tostring(CM.ServerType())))
  for key, e in pairs(CueTheCashierDB.servers or {}) do
    CM.Print(("  Known server %s = %s (seen %s)"):format(key, tostring(e.type), date("%Y-%m-%d", e.seen or 0)))
  end
  CM.Print("Saved prices use: " .. CM:GetAuctionKey())
end

-- /cmp item <id or link>: everything the game tells addons about an item
-- (GetItemInfo's 18 values and every tooltip line with its hidden
-- fields), to look for a vendor buy price. Also written to the debug log.
function CM.ItemReport(itemID)
  if not itemID then CM.Print("Usage: /cmp item <item id or link>, e.g. /cmp item 2320"); return end
  local Out = CM.Print -- also writes the debug log
  local t = { C_Item.GetItemInfo(itemID) }
  if not t[1] then
    Out("Item " .. itemID .. " isn't loaded yet; run the command again in a moment.")
    return
  end
  local names = { "name", "link", "quality", "itemLevel", "minLevel", "type", "subType", "stackCount",
    "equipLoc", "texture", "sellPrice", "classID", "subclassID", "bindType", "expansionID", "setID",
    "isCraftingReagent", "description" }
  for i = 1, 18 do Out(("%d %s = %s"):format(i, names[i], tostring(t[i]))) end
  if C_TooltipInfo and C_TooltipInfo.GetItemByID then
    local ok, d = pcall(C_TooltipInfo.GetItemByID, itemID)
    for n, l in ipairs(ok and d and d.lines or {}) do
      local parts = {}
      for k, v in pairs(l) do parts[#parts + 1] = k .. "=" .. tostring(v) end
      table.sort(parts)
      Out(("tooltip line %d: %s"):format(n, table.concat(parts, " ")))
    end
    if ok and d then
      for k, v in pairs(d) do
        if k ~= "lines" then Out(("tooltip %s = %s"):format(tostring(k), tostring(v))) end
      end
    end
  end
end

-- ------------------------------------------------------------------
-- Core commands
-- ------------------------------------------------------------------
local Print = CM.Print
local function m(v) return v and CM.FormatMoney(v) or "?" end

CM.RegisterCommand("status", CM, function()
  local data = CM:GetRealmData()
  local count = 0
  for _ in pairs(data.items) do count = count + 1 end
  Print(("%s: %d items, last scan %s."):format(CM:GetAuctionKey(), count,
    data.lastScan > 0 and date("%Y-%m-%d %H:%M", data.lastScan) or "never"))
  Print("Full scan ready in: " .. CM.FullScanCooldownText())
  local mods = {}
  for name, info in pairs(CM.moduleAddons) do
    mods[#mods + 1] = name .. (CM.IsAddOnLoaded(name) and "" or (info.lod and " (loads when needed)" or " (off)"))
  end
  table.sort(mods)
  Print(("CueTheCashier %s, API %d. Modules: %s."):format(CM.version, CM.API_VERSION,
    #mods > 0 and table.concat(mods, ", ") or "none installed"))
end, "/cmp status")

CM.RegisterCommand("price", CM, function(rest)
  if rest == "" then Print("Usage: /cmp price <item link or id>"); return end
  local itemID = CM.ParseItemID(rest)
  local e = CM:GetItemEntry(itemID)
  if not e then Print("No price saved for " .. rest); return end
  Print(("%s min %s, market %s, median %s, mean %s, max %s, %d for sale in %d auctions by %s sellers.")
    :format(rest, m(e.minBuyout), m(e.marketValue), m(e.median), m(e.mean), m(e.maxBuyout),
      e.quantity or 0, e.auctions or 0, tostring(e.sellers or "?")))
  local parts = {}
  for _, span in ipairs({ { 7, "7 days" }, { 30, "30 days" } }) do
    local avg, n = CM.Data:GetAverage(itemID, "market", span[1])
    if avg then parts[#parts + 1] = ("%s %s (%d days)"):format(span[2], m(avg), n) end
  end
  local all, n = CM.Data:GetAllTimeAverage(itemID, "market")
  if all then parts[#parts + 1] = ("all time %s (%d scans)"):format(m(all), n) end
  if #parts > 0 then Print("Average market value: " .. table.concat(parts, ", ") .. ".") end
  local rate = CM.Data:GetSaleRate(itemID)
  if rate then Print(("Sale rate %d%%."):format(math.floor(rate * 100 + 0.5))) end
  local st = CM.Data:GetSaleStats(itemID)
  if st then
    Print(("Your sales here: %d sold, %d expired, %.1f per day, %s each on average."):format(
      st.sold, st.expired, st.perDay, m(st.average)))
  end
end, "/cmp price <item>")

-- /cmp region <item>: what every server type in the region saw, to compare
-- them (e.g. are commodity prices the same everywhere = one shared AH?).
CM.RegisterCommand("region", CM, function(rest)
  local itemID = CM.ParseItemID(rest) or CM.Data:FindItemID(rest)
  if not itemID then Print("Usage: /cmp region <item link, id or name>"); return end
  local rows = CM.Data:RegionRows(itemID)
  Print(("Region %s, %s:"):format(CM.Data.RegionName(), CM.API.GetItemName(itemID) or tostring(itemID)))
  if #rows == 0 then Print("  No server in this region has a price for it yet.") end
  for _, r in ipairs(rows) do
    local age = r[4] and SecondsToTime and SecondsToTime(math.max(0, time() - r[4])) or "?"
    Print(("  %s: min %s, market %s (30-day %s), seen %s ago"):format(r[1], m(r[2]), m(r[3]), m(r[6]), age))
  end
  local g = CM.Data:GetRegion(itemID)
  if g then
    Print(("  Region: market %s, min %s from %d server(s)%s; sale rate %s, %s per day, %s each.")
      :format(m(g.market), m(g.min), g.servers, g.fromApp and " (app data)" or "",
        g.rate and ("%d%%"):format(math.floor(g.rate * 100 + 0.5)) or "?",
        g.perDay and ("%.1f"):format(g.perDay) or "?", m(g.average)))
  end
end, "/cmp region <item>")

CM.RegisterCommand("vendor", CM, function(rest)
  if rest == "" then Print("Usage: /cmp vendor <item link or id>"); return end
  -- Every vendor price source we know, to compare with the item tooltip.
  local itemID = CM.ParseItemID(rest)
  local name, tip, info, stack, saved = CM.Data:VendorPriceReport(itemID or 0)
  Print(("%s: tooltip %s, GetItemInfo %s (stack %s), saved %s."):format(
    name or rest, m(tip), m(info), tostring(stack or "?"), m(saved)))
  local buy = itemID and CM.Data:GetVendorBuyPrice(itemID)
  local tbl = itemID and CM.VendorBuy and CM.VendorBuy[itemID]
  Print(("Vendor buy price: %s (game data %s%s)."):format(
    buy and m(math.floor(buy + 0.5)) or "not sold by vendors as far as we know",
    tbl and m(math.floor(tbl + 0.5)) or "none",
    (CueTheCashierDB.vendorBuy or {})[itemID] and ", raised at a merchant" or ""))
end, "/cmp vendor <item>")

CM.RegisterCommand("sources", CM, function(rest)
  -- Every price source in the API; with an item, also its value.
  local itemID = CM.ParseItemID(rest)
  for _, s in ipairs(CM.API.GetPriceSources()) do
    if itemID then
      local v = CM.API.GetPrice(itemID, s.key)
      Print(("%s (%s): %s"):format(s.label, s.key, CM.API.FormatSourceValue(s.key, v) or m(v)))
    else
      Print(("%s: %s"):format(s.key, s.label))
    end
  end
end, "/cmp sources [item]")

-- /cmp tovendor                   the to-vendor list into the log
-- /cmp tovendor add <item> [n]     put an item on it by hand (Shift-click a link)
-- /cmp tovendor clear              empty it
CM.RegisterCommand("tovendor", CM, function(rest)
  local V = CM.VendorSell
  local cmd, arg = (rest or ""):match("^(%S*)%s*(.-)$")
  if cmd == "add" then
    local itemID = CM.ParseItemID(arg)
    if not itemID then Print("Usage: /cmp tovendor add <item link or id> [count]"); return end
    -- The count comes after the link ("|r 5") or after a plain id ("2318 5").
    local n = tonumber(arg:match("|r%s*(%d+)%s*$") or arg:match("^%d+%s+(%d+)%s*$") or "") or 1
    V.AddBuy(itemID, n)
    Print(("Added to the to-vendor list: %s."):format((C_Item.GetItemInfo(itemID)) or ("item " .. itemID)))
  elseif cmd == "clear" then
    V.Clear()
    Print("To-vendor list emptied.")
  else
    V.Report()
    Print("To-vendor list written to the log (/cmp log).")
  end
end, "/cmp tovendor [add <item> [count] | clear]")

CM.RegisterCommand("mail", CM, function()
  CM.Mailing.Report()
  Print("Mailing report written to the log (/cmp log).")
end, "/cmp mail")

CM.RegisterCommand("minimap", CM, function() CM.ToggleMinimapButton() end, "/cmp minimap")

CM.RegisterCommand("blocked", CM, function()
  -- The last calls Blizzard blocked, without digging through the log.
  if #(CM.blockedLines or {}) == 0 then Print("Nothing has been blocked since login.") end
  for _, l in ipairs(CM.blockedLines or {}) do Print("Blocked: " .. l) end
end, "/cmp blocked")

CM.RegisterCommand("realm", CM, function() CM.RealmReport() end, "/cmp realm")

CM.RegisterCommand("item", CM, function(rest) CM.ItemReport(CM.ParseItemID(rest)) end, "/cmp item <id>")

-- Debug mode on or off (/cmp debug and the Settings tab).
function CM.SetDebugMode(on)
  local s = CM.Settings()
  on = on and true or false
  if (s.debug and true or false) == on then return end
  s.debug = on
  Print("Debug mode " .. (s.debug and "on: the debug log records more (/cmp log shows it)." or "off."))
  CM.UpdateEventSpy()
  CM.SendMessage("CM_DEBUG_MODE_CHANGED", s.debug)
  if s.debug then
    CM.LogEnvironment()
    CM.ShowDebugWindow()
  end
end

CM.RegisterCommand("debug", CM, function(rest)
  local s = CM.Settings()
  if rest == "verbose" then
    -- Also log every search event and call (very long logs).
    s.debugVerbose = not s.debugVerbose
    Print("Verbose debug log " .. (s.debugVerbose and "on." or "off."))
    return
  end
  CM.SetDebugMode(not s.debug)
end, "/cmp debug [verbose]")

CM.RegisterCommand("settings", CM, function() CM.MainWindow:Toggle("settings") end, "/cmp settings")

CM.RegisterCommand("log", CM, function() CM.ToggleDebugWindow() end, "/cmp log")

CM.RegisterCommand("skin", CM, function(rest)
  if rest == "" then
    Print("Skins: " .. table.concat(CM.Skins:List(), ", ") .. ". Current: " .. CM.Settings().skin)
  elseif CM.Skins:Set(rest) then
    Print("Skin set to " .. rest .. ". Type /reload to apply.")
  else
    Print("Unknown skin: " .. rest)
  end
end, "/cmp skin [name]")

CM.RegisterCommand("reset", CM, function()
  CueTheCashierDB.realms[CM:GetAuctionKey()] = nil
  Print("Prices cleared for " .. CM:GetAuctionKey())
end, "/cmp reset")

-- The one-key macro (OneKey.lua).
local K = CM.OneKey
CM.RegisterCommand("macro", K, function(rest)
  rest = (rest or ""):lower()
  if rest == "wheel" then
    K.SetWheelModifier(K.WheelModifier() == "off" and "ALT" or "off")
    local mod = K.WheelModifier()
    CM.Print(mod ~= "off" and (mod:sub(1, 1) .. mod:sub(2):lower() .. " + mouse wheel now presses the CueTheCashier key (change it in Settings).")
      or "The mouse wheel is back to normal.")
  elseif rest == "next" then
    CM.Print("Next press: " .. (K.Next() or "nothing to do"))
  else
    K.MakeMacro()
  end
end, "/cmp macro [wheel|next]")

