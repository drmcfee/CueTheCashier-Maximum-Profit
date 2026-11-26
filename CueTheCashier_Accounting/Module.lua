-- CueTheCashier Accounting: the module object. The ledger of what you buy and
-- sell (Ledger.lua) and its tab in the main window (LedgerUI.lua).
-- Loaded by the core when you open a mailbox, a merchant, the auction
-- house or the main window, hover the minimap button or type /cmp ledger
-- (see the .toc).
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
    print("|cffff4444CueTheCashier: the CueTheCashier (core) folder is older than CueTheCashier_Accounting. Copy all six folders from the zip.|r")
  end
end

local Module = CM:NewModule("Accounting", { addon = ADDON_NAME, api = 1 })
ns.module = Module

-- Saved: CueTheCashierAccountingDB = { ledger = { ["<server> - <faction>"] = {...} } }
function Module:OnInitialize()
  CueTheCashier.AdoptOldSaved("CueTheCashierAccountingDB")
  if type(CueTheCashierAccountingDB) ~= "table" then CueTheCashierAccountingDB = {} end
  local db = CueTheCashierAccountingDB
  db.ledger = db.ledger or {}
  -- Up to 0.13.0 the ledger was kept in CueTheCashierDB: move it here once.
  local old = CM.TakeLegacyData("ledger")
  if type(old) == "table" then
    for key, d in pairs(old) do
      if not db.ledger[key] then db.ledger[key] = d end
    end
    CM.Print("Ledger moved to its own saved file (CueTheCashier_Accounting).")
  end
  ns.db = db
end

function Module:OnEnable()
  local Ledger = ns.Ledger
  local function Try(label, fn, ...) CM.Try(label, fn, ...) end

  -- Buys made in CueTheCashier (sent by the Auctioning module).
  self:RegisterMessage("CM_BUYOUT_PLACED", function(_, _, auctionID, itemID, name, money)
    Ledger:ExpectAuction(auctionID, itemID, name, money)
  end)
  self:RegisterMessage("CM_STACK_PURCHASE_CONFIRMING", function(_, _, itemID, name, qty, money)
    Ledger:ExpectStack(itemID, name, qty, money)
  end)
  -- ...and what Blizzard says about them.
  self:RegisterEvent("AUCTION_HOUSE_PURCHASE_COMPLETED", function(_, _, auctionID)
    Try("Ledger purchase", Ledger.PurchaseCompleted, Ledger, auctionID)
  end)
  self:RegisterEvent("COMMODITY_PURCHASE_SUCCEEDED", function()
    Try("Ledger purchase", Ledger.StackSucceeded, Ledger)
  end)
  self:RegisterEvent("COMMODITY_PURCHASE_FAILED", function() Ledger:StackFailed() end)

  -- Mail and merchants.
  self:RegisterEvent("MAIL_INBOX_UPDATE", function() Try("Ledger mail", Ledger.ScanMail, Ledger) end)
  self:RegisterEvent("MERCHANT_SHOW", function() Try("Ledger merchant", Ledger.StartMerchant) end)
  self:RegisterEvent("MERCHANT_CLOSED", function() Try("Ledger merchant", Ledger.MerchantClosed) end)
  self:RegisterEvent("BAG_UPDATE_DELAYED", Ledger.BagsOrMoneyChanged)
  self:RegisterEvent("PLAYER_MONEY", Ledger.BagsOrMoneyChanged)

  -- Postage (0.36): Blizzard's SendMail is only watched, never replaced.
  if SendMail then hooksecurefunc("SendMail", function(to) Try("Ledger postage", Ledger.MailSending, to) end) end
  self:RegisterEvent("MAIL_SEND_SUCCESS", function() Try("Ledger postage", Ledger.MailSent) end)
  self:RegisterEvent("MAIL_FAILED", function() Ledger.MailFailed() end)
  -- Trades.
  self:RegisterEvent("TRADE_SHOW", function() Try("Ledger trade", Ledger.TradeShown) end)
  self:RegisterEvent("TRADE_MONEY_CHANGED", function() Try("Ledger trade", Ledger.TradeChanged) end)
  self:RegisterEvent("TRADE_ACCEPT_UPDATE", function() Try("Ledger trade", Ledger.TradeChanged) end)
  self:RegisterEvent("UI_INFO_MESSAGE", function(_, _, _, message) Try("Ledger trade", Ledger.InfoMessage, message) end)

  -- Today's numbers on the minimap button's tooltip.
  self:RegisterMessage("CM_MINIMAP_TOOLTIP", function(_, _, tooltip)
    local _, today = Ledger:Summary(Ledger:Today())
    tooltip:AddDoubleLine("Spent today", CM.FormatMoney(today.spent), 1, 1, 1, 1, 1, 1)
    tooltip:AddDoubleLine("Received today", CM.FormatMoney(today.received), 1, 1, 1, 1, 1, 1)
    local p = today.profit
    tooltip:AddDoubleLine("Profit today", (p < 0 and "-" or "") .. CM.FormatMoney(math.abs(p)),
      1, 1, 1, p < 0 and 1 or 0, p < 0 and 0.13 or 1, p < 0 and 0.13 or 0)
  end)

  self:RegisterCommand("ledger", function() ns.LedgerUI:Toggle() end, "/cmp ledger")
  Try("Sale rates", Ledger.SaleRates, Ledger)
  ns.AddToMainWindow()
end

-- The Ledger tab and the Overview boxes in the CueTheCashier main window
-- (API minor 2). This module loads when the window opens (see the .toc).
local function Money(c) return CM.FormatMoney(c or 0) end
local function ProfitText(c)
  if not c then return "" end
  if c < 0 then return "|cffff2020-" .. Money(-c) .. "|r" end
  return "|cff00ff00" .. Money(c) .. "|r"
end

function ns.AddToMainWindow()
  local API = CM.API
  if not API.RegisterMainTab then return end -- core older than 0.23.0
  local Ledger = ns.Ledger
  API.RegisterMainTab("ledger", { title = "Ledger", order = 20,
    build = function(page) ns.LedgerUI.Build(page) end,
    show = function() ns.LedgerUI:Refresh() end,
  })

  API.RegisterOverviewSection("profit", { title = "Profit", order = 30, lines = function()
    local today = Ledger:Today()
    local _, day = Ledger:Summary(today)
    local _, week = Ledger:Summary(today - 6 * 86400)
    local _, all = Ledger:Summary(nil)
    return {
      { left = "Today", right = ProfitText(day.profit) },
      { left = "Last 7 days", right = ProfitText(week.profit) },
      { left = "All time", right = ProfitText(all.profit) },
      { left = "|cffaaaaaaSpent, 7 days|r", right = Money(week.spent) },
      { left = "|cffaaaaaaReceived, 7 days|r", right = Money(week.received) },
      { left = "|cffaaaaaaOther (repairs, postage, cut...), 7 days|r",
        right = ProfitText(select(2, Ledger:OtherTotals(today - 6 * 86400)) - select(3, Ledger:OtherTotals(today - 6 * 86400))) },
    }
  end })

  API.RegisterOverviewSection("recentSales", { title = "Recent sales", order = 40, wide = true, lines = function()
    local sold, lines = Ledger:Data().sold, {}
    for i = #sold, math.max(1, #sold - 20), -1 do
      local l = sold[i]
      lines[#lines + 1] = { itemID = l.id, right = Money(l.money),
        left = ("|cffaaaaaa%s|r  %s x%d"):format(date("%d %b", l.t), l.name or ("item " .. tostring(l.id)), l.qty or 1) }
    end
    return lines
  end })

  API.RegisterOverviewSection("bestItems", { title = "Best items, last 7 days", order = 50, wide = true,
    lines = function()
      local list = Ledger:Summary(Ledger:Today() - 6 * 86400)
      table.sort(list, function(a, b) return a.profit > b.profit end)
      local lines = {}
      for _, it in ipairs(list) do
        if it.profit <= 0 or #lines >= 20 then break end
        lines[#lines + 1] = { itemID = it.id, right = ProfitText(it.profit),
          left = ("%s  |cffaaaaaa%d sold|r"):format(it.name or ("item " .. tostring(it.id)), it.soldQty) }
      end
      return lines
    end })

  -- Keep the Overview up to date when the ledger changes.
  Ledger:OnChange(function() API.RefreshMainWindow() end)
end
