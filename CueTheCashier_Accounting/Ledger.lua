-- CueTheCashier: ledger. Records what you buy and sell, so the Ledger window
-- can show your spending, income and profit per item.
--
-- What is recorded, and where it comes from:
--   Bought on the AH  - buys made in CueTheCashier are recorded the moment
--                       Blizzard says they completed (exact price). Buys
--                       made in Blizzard's window come from the "Auction
--                       won" mails when you open the mailbox. A mail for a
--                       buy that is already recorded is not counted again.
--   Sold on the AH    - from the "Auction successful" mails; they hold the
--                       exact money after the cut.
--   Vendor            - at a merchant, by comparing your bags and gold
--                       before and after (sold items, and items bought).
--   Other (0.36)      - money that isn't an item bought or sold: repairs
--                       (gold gone at a merchant with no item), postage
--                       (each mail you send), the auction house cut (from
--                       the sale mails), deposits lost on expired and
--                       cancelled auctions (an estimate: 20% of the vendor
--                       price, the mails don't say) and gold traded.
-- The ledger never hooks Blizzard's functions: in 0.10.x hooks on the
-- auction house buy functions came just before stack buys got blocked.
-- The ledger is shared by all your characters on the same realm and
-- faction; each line remembers which character did it.
--
-- Saved in CueTheCashierAccountingDB.ledger["<server> - <faction>"] = {
--   bought = { {t, id, name, qty, money, source, char}, ... },
--   sold   = { {t, id, name, qty, money, source, char}, ... },
--   mails  = { [signature] = time } -- mails already counted
--   other  = { {t, kind, money (+ income, - cost), note, char}, ... }
-- }
-- (Before 0.14.0 this was CueTheCashierDB.ledger; Module.lua moves it once.)
-- Copyright (C) 2026 Kim. Licensed under the GNU GPL v3 or later; see LICENSE.
local _, ns = ...
local CM = CueTheCashier
local API = CM.API

local Ledger = {}
ns.Ledger = Ledger

local MAX_LINES = 5000 -- per list; the oldest lines are dropped after that

function Ledger:Data()
  local ledger = ns.db.ledger
  local key = API.GetServerKey()
  local d = ledger[key]
  if not d then
    d = { bought = {}, sold = {}, mails = {} }
    ledger[key] = d
  end
  d.other = d.other or {}
  if not d.qtyFixed then
    d.qtyFixed = true
    Ledger.FixZeroQty(d)
  end
  return d
end

-- 0.10.10: lines recorded from mails with count 0 (before MailCount).
-- Use the quantity of a sale of the same item, else 1.
function Ledger.FixZeroQty(d)
  for _, list in ipairs({ d.bought, d.sold }) do
    for _, l in ipairs(list) do
      if not l.qty or l.qty <= 0 then
        local guess
        local other = list == d.bought and d.sold or d.bought
        for _, o in ipairs(other) do
          if o.name == l.name and o.qty and o.qty > 0 then guess = o.qty end
        end
        l.qty = guess or 1
      end
    end
  end
end

local listeners = {}
function Ledger:OnChange(fn) listeners[#listeners + 1] = fn end

local function Add(list, line)
  line.t = line.t or time()
  line.char = line.char or UnitName("player")
  table.insert(list, line)
  while #list > MAX_LINES do table.remove(list, 1) end
  for _, fn in ipairs(listeners) do pcall(fn) end
end

function Ledger:AddBought(id, name, qty, money, source)
  CM.Debug(("Ledger: bought %d x %s for %d (%s)."):format(qty, tostring(name), money, source))
  Add(self:Data().bought, { id = id, name = name, qty = qty, money = money, source = source })
end

-- kind: "Repairs", "Postage", "AH cut", "Expired", "Cancelled", "Trade".
-- money: + income, - cost.
function Ledger:AddOther(kind, money, note)
  if not money or money == 0 then return end
  CM.Debug(("Ledger: %s %d (%s)."):format(kind, money, tostring(note)))
  Add(self:Data().other, { kind = kind, money = money, note = note })
end

-- Totals of the other lines: { [kind] = money }, income, costs.
function Ledger:OtherTotals(since)
  local byKind, income, costs = {}, 0, 0
  for _, l in ipairs(self:Data().other) do
    if not since or l.t >= since then
      byKind[l.kind] = (byKind[l.kind] or 0) + l.money
      if l.money > 0 then income = income + l.money else costs = costs - l.money end
    end
  end
  return byKind, income, costs
end

function Ledger:AddSold(id, name, qty, money, source)
  CM.Debug(("Ledger: sold %d x %s for %d (%s)."):format(qty, tostring(name), money, source))
  Add(self:Data().sold, { id = id, name = name, qty = qty, money = money, source = source })
end

-- ------------------------------------------------------------------
-- Buys made in CueTheCashier. The buying code says what it is about to buy;
-- the line is added when Blizzard reports the purchase completed
-- (AUCTION_HOUSE_PURCHASE_COMPLETED for one auction,
-- COMMODITY_PURCHASE_SUCCEEDED for a stack). The line waits for its mails
-- (mailLeft) so they aren't counted twice.
-- ------------------------------------------------------------------
local expectAuction, expectStack = {}, nil

function Ledger:ExpectAuction(auctionID, id, name, money)
  if auctionID then expectAuction[auctionID] = { id = id, name = name, qty = 1, money = money } end
end

function Ledger:ExpectStack(id, name, qty, money)
  expectStack = { id = id, name = name, qty = qty, money = money }
end

local function AddExpected(e)
  Ledger:AddBought(e.id, e.name, e.qty, e.money, "AH")
  local d = Ledger:Data()
  local line = d.bought[#d.bought]
  line.mailQty, line.mailMoney = e.qty, e.money
end

function Ledger:PurchaseCompleted(auctionID)
  local e = auctionID and expectAuction[auctionID]
  if e then
    expectAuction[auctionID] = nil
    AddExpected(e)
  end
end

function Ledger:StackSucceeded()
  if expectStack then
    local e = expectStack
    expectStack = nil
    AddExpected(e)
  end
end

function Ledger:StackFailed() expectStack = nil end

-- A "buyer" mail for a buy already recorded: use it up and return true.
-- A stack can come in several mails (one per seller), so the line counts
-- down what it still waits for.
local function SameName(a, b)
  if not (a and b) then return false end
  return a == b or a:sub(1, #b) == b or b:sub(1, #a) == a
end

function Ledger:MatchRecordedBuy(itemName, count, money)
  local d = self:Data()
  local cutoff = time() - 31 * 86400
  for i = #d.bought, 1, -1 do
    local l = d.bought[i]
    if l.t < cutoff then break end
    if l.mailQty and l.mailQty >= count and l.mailMoney >= money and SameName(l.name, itemName) then
      l.mailQty, l.mailMoney = l.mailQty - count, l.mailMoney - money
      if l.mailQty <= 0 or l.mailMoney <= 0 then l.mailQty, l.mailMoney = nil, nil end
      return true
    end
  end
  return false
end

-- ------------------------------------------------------------------
-- Profit: per item, money received minus the average price you paid for
-- what you sold. Items you never bought (farmed, crafted) count as free.
-- since: only lines at or after this time (nil = all time).
-- ------------------------------------------------------------------

function Ledger:Summary(since)
  local d = self:Data()
  local items = {}
  -- Mail sales only know the item's name: match them to the ID other lines
  -- have for the same name.
  local idByName = {}
  for _, list in ipairs({ d.bought, d.sold }) do
    for _, l in ipairs(list) do if l.id and l.name then idByName[l.name] = l.id end end
  end
  local function Item(line)
    local k = line.id or idByName[line.name or ""] or line.name or "?"
    local it = items[k]
    if not it then
      it = { id = line.id or idByName[line.name or ""], name = line.name, boughtQty = 0, spent = 0, soldQty = 0, received = 0,
        avgQty = 0, avgSpent = 0 }
      items[k] = it
    end
    it.name = it.name or line.name
    return it
  end
  -- Average cost uses every purchase ever made, so selling today what you
  -- bought last week still has its cost.
  for _, l in ipairs(d.bought) do
    local it = Item(l)
    it.avgQty, it.avgSpent = it.avgQty + l.qty, it.avgSpent + l.money
    if not since or l.t >= since then
      it.boughtQty, it.spent = it.boughtQty + l.qty, it.spent + l.money
    end
  end
  for _, l in ipairs(d.sold) do
    if not since or l.t >= since then
      local it = Item(l)
      it.soldQty, it.received = it.soldQty + l.qty, it.received + l.money
    end
  end
  local list, total = {}, { spent = 0, received = 0, profit = 0 }
  for _, it in pairs(items) do
    local avg = it.avgQty > 0 and it.avgSpent / it.avgQty or 0
    it.cost = math.floor(avg * it.soldQty + 0.5)
    it.profit = it.received - it.cost
    -- Per item: average price paid (all time) and received (this period);
    -- resale = what one earns over what one cost (only items you bought).
    it.avgBuy = it.avgQty > 0 and math.floor(avg + 0.5) or nil
    it.avgSell = it.soldQty > 0 and math.floor(it.received / it.soldQty + 0.5) or nil
    it.resale = (it.avgBuy and it.avgSell) and (it.avgSell - it.avgBuy) or nil
    total.spent = total.spent + it.spent
    total.received = total.received + it.received
    total.profit = total.profit + it.profit
    if it.boughtQty > 0 or it.soldQty > 0 then list[#list + 1] = it end
  end
  return list, total
end

-- Start of today (local time) and of 7 days ago.
function Ledger:Today()
  local d = date("*t")
  return time({ year = d.year, month = d.month, day = d.day, hour = 0 })
end

local function ItemNameOf(id)
  local name = C_Item.GetItemInfo(id)
  return name
end

-- ------------------------------------------------------------------
-- Recording: auction house mails (purchases and sales)
-- ------------------------------------------------------------------
-- A mail has no id, so it is recognised by its contents and the time it
-- expires (which doesn't change while it sits in the mailbox).
local function MailSignature(kind, itemName, other, bid, count, daysLeft)
  local expires = math.floor((time() + (daysLeft or 0) * 86400) / 3600)
  return ("%s|%s|%s|%d|%d"):format(kind, itemName or "", other or "", bid or 0, count or 0), expires
end

-- The invoice's count can be 0 on Forever (seen in game: a sword and a
-- stack of 2 claws were both recorded as 0). Then count what's attached.
local function MailCount(i, count)
  if count and count > 0 then return count end
  local n = 0
  if GetInboxItem then
    for a = 1, (ATTACHMENTS_MAX_RECEIVE or 16) do
      local name, _, _, c = GetInboxItem(i, a)
      if name then n = n + ((c and c > 0) and c or 1) end
    end
  end
  return n > 0 and n or 1
end

function Ledger:ScanMail()
  if not (GetInboxNumItems and GetInboxInvoiceInfo) then return end
  local d = self:Data()
  for i = 1, GetInboxNumItems() do
    local invoiceType, itemName, other, bid, _, _, consignment, _, _, count = GetInboxInvoiceInfo(i)
    if (invoiceType == "seller" or invoiceType == "buyer") and itemName and bid then
      -- The signature uses the invoice's own count: the attachment count
      -- changes when you take the items, and the same mail then looked new
      -- (0.10.10 counted 2 bought Dire Wolf Fangs as 3).
      local daysLeft = select(7, GetInboxHeaderInfo(i))
      local sig, expires = MailSignature(invoiceType, itemName, other, bid, count, daysLeft)
      count = MailCount(i, count)
      -- The same mail read an hour later may round to the next hour.
      local seen = d.mails[sig .. "|" .. expires] or d.mails[sig .. "|" .. (expires - 1)]
        or d.mails[sig .. "|" .. (expires + 1)]
      if not seen then
        d.mails[sig .. "|" .. expires] = time()
        local id = API.FindItemID(itemName)
        if invoiceType == "seller" then
          self:AddSold(id, itemName, count, bid - (consignment or 0), "AH")
          if API.LotSold then CM.Try("Lot sold", API.LotSold, id, count) end -- 0.46.1
          if consignment and consignment > 0 then
            self:AddOther("AH cut", -consignment, ("%d x %s"):format(count, itemName))
          end
        elseif self:MatchRecordedBuy(itemName, count, bid) then
          CM.Debug(("Ledger: mail for %d x %s already recorded."):format(count, itemName))
        else
          self:AddBought(id, itemName, count, bid, "AH")
        end
      end
    end
  end
  -- Expired and cancelled auctions: the deposit stays with the auction
  -- house. The mail doesn't say how much, so it is estimated.
  if API.GetMailKind then
    for i = 1, GetInboxNumItems() do
      local kind = API.GetMailKind(i)
      if kind == "expired" or kind == "cancelled" then
        local subject, _, _, daysLeft = select(4, GetInboxHeaderInfo(i))
        local name, itemID, _, count = GetInboxItem(i, 1)
        local sig, expires = MailSignature(kind, subject, name, 0, count or 0, daysLeft)
        local seen = d.mails[sig .. "|" .. expires] or d.mails[sig .. "|" .. (expires - 1)]
          or d.mails[sig .. "|" .. (expires + 1)]
        if not seen and name then
          d.mails[sig .. "|" .. expires] = time()
          local n = (count and count > 0) and count or 1
          local deposit = itemID and API.GetAuctionDeposit and API.GetAuctionDeposit(itemID, n) or 0
          local line = { kind = kind == "expired" and "Expired" or "Cancelled", money = -deposit, id = itemID,
            note = ("%d x %s (deposit, estimate)"):format(n, name) }
          -- Listed even when the deposit is unknown (0), so you see it expired.
          Add(d.other, line)
          -- 0.46.1: those units are back, one more failed try when expired.
          if API.LotReturned and itemID then CM.Try("Lot returned", API.LotReturned, itemID, n, kind == "expired") end
        end
      end
    end
  end
  CM.Try("Sale rates", Ledger.SaleRates, Ledger)
  -- Forget mails older than 31 days (they have expired from the mailbox).
  local cutoff = time() - 31 * 86400
  for k, t in pairs(d.mails) do if t < cutoff then d.mails[k] = nil end end
end

-- ------------------------------------------------------------------
-- Recording: at a merchant. Bags and gold are compared after each change:
-- items gone + more gold = sold, items added + less gold = bought.
-- ------------------------------------------------------------------
local atMerchant, lastBags, lastMoney = false, nil, 0

local function BagCounts()
  local counts, names = {}, {}
  for bag = 0, (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) do
    for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      if info and info.itemID then
        counts[info.itemID] = (counts[info.itemID] or 0) + (info.stackCount or 1)
        names[info.itemID] = info.hyperlink and info.hyperlink:match("%[(.-)%]")
      end
    end
  end
  return counts, names
end

function Ledger:MerchantChanged()
  if not atMerchant or not lastBags then return end
  local counts, names = BagCounts()
  local money = GetMoney()
  local diff = money - lastMoney
  local gone, added = {}, {}
  for id, n in pairs(lastBags.counts) do
    local now = counts[id] or 0
    if now < n then gone[#gone + 1] = { id = id, qty = n - now, name = lastBags.names[id] } end
  end
  for id, n in pairs(counts) do
    local before = lastBags.counts[id] or 0
    if n > before then added[#added + 1] = { id = id, qty = n - before, name = names[id] } end
  end
  if diff > 0 and #gone > 0 then
    -- Sold. One item: the gold change is its exact price; several (Sell
    -- All Junk): each at its vendor price.
    for _, g in ipairs(gone) do
      local money = #gone == 1 and diff or (API.GetVendorSellPrice(g.id) or 0) * g.qty
      self:AddSold(g.id, g.name or ItemNameOf(g.id), g.qty, money, "Vendor")
    end
  elseif diff < 0 and #added == 1 then
    local a = added[1]
    self:AddBought(a.id, a.name or ItemNameOf(a.id), a.qty, -diff, "Vendor")
  elseif diff < 0 and #added == 0 and #gone == 0 then
    -- Gold gone and no item changed: a repair.
    self:AddOther("Repairs", diff, UnitName("npc"))
  end
  if diff ~= 0 or #gone > 0 or #added > 0 then
    lastBags, lastMoney = { counts = counts, names = names }, money
  end
end

function Ledger.StartMerchant()
  atMerchant = true
  local counts, names = BagCounts()
  lastBags, lastMoney = { counts = counts, names = names }, GetMoney()
end

function Ledger.MerchantClosed()
  Ledger:MerchantChanged()
  atMerchant = false
end

-- Bags and gold update in separate events: look once both settled.
local pending = false
function Ledger.BagsOrMoneyChanged()
  if not atMerchant or pending then return end
  pending = true
  C_Timer.After(0.3, function()
    pending = false
    CM.Try("Ledger merchant", Ledger.MerchantChanged, Ledger)
  end)
end
-- (The events are registered in Module.lua.)

-- ------------------------------------------------------------------
-- Recording: postage and trades
-- ------------------------------------------------------------------
-- What the mail you are sending costs (read when you click Send; Blizzard
-- clears the form after). Counted when the game says it was sent.
local postage
function Ledger.MailSending(recipient)
  local price = GetSendMailPrice and GetSendMailPrice() or 0
  postage = { price = price, to = recipient }
end

function Ledger.MailSent()
  if postage and postage.price > 0 then
    Ledger:AddOther("Postage", -postage.price, postage.to and ("to " .. postage.to) or nil)
  end
  postage = nil
end

function Ledger.MailFailed() postage = nil end

-- Trades: the gold on both sides is read whenever someone accepts, and
-- counted when the game says the trade is complete.
local trade
function Ledger.TradeChanged()
  trade = {
    give = GetPlayerTradeMoney and GetPlayerTradeMoney() or 0,
    get = GetTargetTradeMoney and GetTargetTradeMoney() or 0,
    who = UnitName("npc") or trade and trade.who,
  }
end

function Ledger.TradeShown()
  trade = { give = 0, get = 0, who = UnitName("npc") }
end

function Ledger.InfoMessage(message)
  if not (trade and ERR_TRADE_COMPLETE and message == ERR_TRADE_COMPLETE) then return end
  if trade.get > 0 then Ledger:AddOther("Trade", trade.get, trade.who and ("from " .. trade.who)) end
  if trade.give > 0 then Ledger:AddOther("Trade", -trade.give, trade.who and ("to " .. trade.who)) end
  trade = nil
end

-- ------------------------------------------------------------------
-- Sale numbers (0.37, all servers since 0.43): of your auctions that ran
-- out, the share that sold. Every "Auction successful" mail is one auction
-- sold, every "Auction expired" mail one that didn't. Cancelled auctions
-- don't count (you took them back). Also items sold per day (last 30 days)
-- and the average money per item. Worked out for every server and faction
-- in the ledger and handed to the core (API.SetSaleStats), which keeps
-- them for tooltips, price sources and the region numbers.
-- ------------------------------------------------------------------
local DAY = 86400

-- One ledger's numbers: { t, days, items = { [id] = { sold, expired,
-- sold30, itemsSold, money, depositsLost, expiredSinceSale } } }, and the
-- item count. 0.46.0: depositsLost = deposits lost on expired auctions
-- (copper), expiredSinceSale = expired auctions after the last sale (the
-- "failed posts in a row" for "Vendor it").
function Ledger.SaleStats(d)
  local now = time()
  local idByName = {}
  for _, list in ipairs({ d.bought, d.sold }) do
    for _, l in ipairs(list) do if l.id and l.name then idByName[l.name] = l.id end end
  end
  local items, n = {}, 0
  local function Get(id)
    local c = items[id]
    if not c then c = { 0, 0, 0, 0, 0, 0, 0 }; items[id] = c; n = n + 1 end
    return c
  end
  -- The ledger covers the days since its oldest line (at most 30 count).
  local oldest = now
  for _, list in ipairs({ d.bought or {}, d.sold or {}, d.other or {} }) do
    for _, l in ipairs(list) do if l.t and l.t < oldest then oldest = l.t end end
  end
  local days = math.min(30, math.max(1, math.ceil((now - oldest) / DAY)))
  local lastSale = {}
  for _, l in ipairs(d.sold or {}) do
    local id = l.source == "AH" and (l.id or idByName[l.name or ""])
    if id then
      local c, qty = Get(id), (l.qty and l.qty > 0) and l.qty or 1
      c[1] = c[1] + 1
      if (l.t or 0) > (lastSale[id] or 0) then lastSale[id] = l.t or 0 end
      if (l.t or 0) >= now - 30 * DAY then c[3] = c[3] + qty end
      if (l.money or 0) > 0 then c[4], c[5] = c[4] + qty, c[5] + l.money end
    end
  end
  for _, l in ipairs(d.other or {}) do
    if l.kind == "Expired" then
      local name = l.note and l.note:match("^%d+ x (.-) %(")
      local id = l.id or (name and idByName[name]) or (name and API.FindItemID(name))
      if id then
        local c = Get(id)
        c[2] = c[2] + 1
        if (l.money or 0) < 0 then c[6] = c[6] - l.money end
        if (l.t or 0) > (lastSale[id] or 0) then c[7] = c[7] + 1 end
      end
    end
  end
  return { t = now, days = days, items = items }, n
end

-- Works the numbers out for every server and faction in the ledger.
-- Returns how many items on this server have a sale rate.
function Ledger:SaleRates()
  self:Data() -- makes sure this server's ledger exists and is tidy
  local here, rated = API.GetServerKey(), 0
  for key, d in pairs(ns.db.ledger) do
    if type(d) == "table" and type(d.sold) == "table" then
      local stats = Ledger.SaleStats(d)
      if API.SetSaleStats then
        API.SetSaleStats(key, stats)
      elseif key == here and API.SetSaleRate then -- core older than 0.43
        for id, c in pairs(stats.items) do
          if c[1] + c[2] >= 2 then API.SetSaleRate(id, c[1] / (c[1] + c[2]), ("%d of your %d auctions sold"):format(c[1], c[1] + c[2])) end
        end
      end
      if key == here then
        for _, c in pairs(stats.items) do if c[1] + c[2] >= 2 then rated = rated + 1 end end
      end
    end
  end
  return rated
end
