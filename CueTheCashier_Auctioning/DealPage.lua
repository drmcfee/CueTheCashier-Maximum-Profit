-- CueTheCashier: shared code for the Vendor and Snipe tabs.
-- Both tabs search the whole auction house with a browse search, list the
-- items that are cheap enough, look up one item's listings when you click
-- it, and buy the cheap ones on the tab.
--
-- A tab is made with ns.DealPage.New(config); see VendorTab.lua and
-- SnipeTab.lua for the config fields.
--
-- How it works:
-- 1. A search sends one empty browse search (every item on the auction
--    house) and pages through the answers. Each answer has the item's
--    lowest price right now; config.Evaluate decides if it is a deal.
--    Snipe repeats this, and only reports prices that dropped since the
--    last round (new, cheaper postings).
-- 2. Clicking a deal searches that item's listings and counts how many are
--    at or under the deal's price limit.
-- 3. Buy buys them: stackables in one go (the server tells us the exact
--    price first), single items one auction at a time, cheapest first.
--    Every purchase comes from your click (Blizzard rule) and is refused
--    when it would not be a profit.
-- Copyright (C) 2026 Kim. Licensed under the GNU GPL v3 or later; see LICENSE.
local _, ns = ...
local CM = CueTheCashier
local API = CM.API

local DealPage = {}
ns.DealPage = DealPage

local ROW_HEIGHT = 20
local LIST_TOP = -80
local LEFT = 8

local function Money(c) return c and CM.FormatMoney(c) or "?" end

local function KeyString(k)
  return ("%d:%d:%d:%d"):format(k.itemID or 0, k.itemLevel or 0, k.itemSuffix or 0, k.battlePetSpeciesID or 0)
end
DealPage.KeyString = KeyString

local function ItemName(itemKey)
  local info = C_AuctionHouse.GetItemKeyInfo and C_AuctionHouse.GetItemKeyInfo(itemKey)
  if info and info.itemName then return info.itemName, info.quality end
  local name, _, quality = C_Item.GetItemInfo(itemKey.itemID)
  return name, quality
end

-- Price per item of one listing, or nil when it can't be bought out.
-- A buyout (or unit price) of 0 means "bid only", never "free".
local function UnitOf(l)
  if l.buyoutAmount then
    -- Single items: Forever gives the buyout per item, and quantity is how
    -- many identical auctions the row holds (seen in game: White Leather
    -- Bag, buyout 8s 75c with quantity 50 is 8s 75c each, not 17c).
    if l.buyoutAmount > 0 then return l.buyoutAmount end
    return nil
  end
  if l.unitPrice and l.unitPrice > 0 then return l.unitPrice end
end

local Page = {}
Page.__index = Page

function DealPage.New(config)
  local p = setmetatable({ cfg = config }, Page)
  p.state = {
    rows = {}, byKey = {}, sortKey = config.sortKey, sortReverse = true,
    searching = false, mode = nil, seen = 0, waiting = {}, finishedAt = nil,
    lastMin = {}, rounds = 0, selected = nil, buying = false,
  }
  DealPage.pages = DealPage.pages or {}
  DealPage.pages[#DealPage.pages + 1] = p
  return p
end

-- ------------------------------------------------------------------
-- List
-- ------------------------------------------------------------------
function Page:Sort()
  local key, rev = self.state.sortKey, self.state.sortReverse
  table.sort(self.state.rows, function(a, b)
    local x, y = a[key], b[key]
    if key == "name" then x, y = x or "", y or "" else x, y = x or 0, y or 0 end
    if x == y then return (a.name or "") < (b.name or "") end
    if rev then return x > y end
    return x < y
  end)
end

-- Cells still waiting for the item's listings say so in gray.
local LOADING = "|cff808080loading|r"
local NO_ANSWER = "|cff808080no answer|r"
local CELL = {
  text = function(r, k) return r[k] or "" end,
  money = function(r, k) return r[k] and Money(r[k]) or "" end,
  profit = function(r, k)
    if not r[k] then return r.failed and NO_ANSWER or LOADING end
    -- Green: a vendor pays this for sure. Yellow: compared to market value.
    return (r.why == "Market" and "|cffffd100" or "|cff00ff00") .. Money(r[k]) .. "|r"
  end,
  count = function(r, k)
    if r[k] then return r[k] end
    if k ~= "qty" then return "" end
    return r.failed and NO_ANSWER or LOADING
  end,
  time = function(r, k) return r[k] and date("%H:%M", r[k]) or "" end,
}

function Page:InitRow(row, r)
  local cols = self.cfg.columns
  if not row.cells then
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.sel = row:CreateTexture(nil, "ARTWORK")
    row.sel:SetAllPoints()
    CM.Skins:Paint(row.sel, "selected")
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    CM.Skins:Paint(hl, "highlight")
    row.cells = {}
    local x = 4
    for _, col in ipairs(cols) do
      local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      fs:SetPoint("LEFT", x, 0)
      fs:SetWidth(col.width - 10)
      fs:SetJustifyH(col.kind == "text" and "LEFT" or "RIGHT")
      fs:SetWordWrap(false)
      row.cells[col.key] = fs
      x = x + col.width
    end
    row:SetScript("OnEnter", function(rw) CM.ShowItemTooltip(rw, rw.data.itemKey) end)
    row:SetScript("OnLeave", GameTooltip_Hide)
    row:SetScript("OnClick", function(rw) self:Select(rw.data) end)
  end
  -- Names the game hadn't loaded during the search: try again.
  if not r.name then r.name, r.quality = ItemName(r.itemKey) end
  row.data = r
  CM.Skins:Stripe(row.bg, r.index)
  row.sel:SetShown(self.state.selected == r)
  for _, col in ipairs(cols) do
    row.cells[col.key]:SetText(CELL[col.kind](r, col.key))
  end
  local fs = row.cells.name
  fs:SetText(r.name or "...")
  local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[r.quality or 1]
  if color then fs:SetTextColor(color.r, color.g, color.b) end
end

function Page:UpdateInfo()
  local s, tab = self.state, self.tab
  local n = 0
  for _ in pairs(s.waiting) do n = n + 1 end
  local text = self.cfg.InfoText(s, n)
  if n > 0 and not s.searching then text = text .. (" Loading prices for %d items..."):format(n) end
  local left = #(s.queue or {}) + (s.loadingRow and 1 or 0)
  if left > 0 and (s.loadTotal or 0) > 0 then
    text = text .. (" Loading listings %d of %d..."):format(s.loadTotal - left + 1, s.loadTotal)
  end
  tab.info:SetText(text)
  tab.empty:SetShown(s.finishedAt and not s.searching and #s.rows == 0 or false)
  if self.cfg.EmptyText then tab.empty:SetText(self.cfg.EmptyText(s)) end
  -- While searching or looking up listings, the active button says Stop.
  local busy = s.searching or self:IsLoading()
  for _, b in ipairs(tab.modeButtons) do
    b:SetText((busy and s.mode == b.mode) and (STOP or "Stop") or b.label)
    b:SetEnabled(not s.searching or s.mode == b.mode)
  end
end

function Page:Refresh()
  local s, tab = self.state, self.tab
  self:Sort()
  for i, r in ipairs(s.rows) do r.index = i end
  CM.SetRows(tab.list, s.rows)
  for _, col in ipairs(self.cfg.columns) do
    local h = tab.headers[col.key]
    h.arrow:SetShown(s.sortKey == col.key)
    h.arrow:SetTexCoord(0, 1, s.sortReverse and 1 or 0, s.sortReverse and 0 or 1)
  end
  self:UpdateInfo()
  self:UpdateBottom()
end

function Page:RefreshSoon()
  if self.refreshPending then return end
  self.refreshPending = true
  C_Timer.After(0.5, function()
    self.refreshPending = false
    if self.tab:IsVisible() then self:Refresh() end
  end)
end

-- ------------------------------------------------------------------
-- Searching
-- ------------------------------------------------------------------
-- One browse answer. Returns true when it added or updated a deal.
function Page:Check(b, report)
  local s = self.state
  local key = KeyString(b.itemKey)
  local deal = self.cfg.Evaluate(b, s.mode)
  if deal == "wait" then -- vendor price not loaded yet
    s.waiting[b.itemKey.itemID] = s.waiting[b.itemKey.itemID] or {}
    table.insert(s.waiting[b.itemKey.itemID], { b = b, report = report })
    return false
  end
  if not (deal and report) then return false end
  local r = s.byKey[key]
  if not r then
    r = {}
    s.byKey[key] = r
    s.rows[#s.rows + 1] = r
  end
  r.itemKey, r.itemID = b.itemKey, b.itemKey.itemID
  r.name, r.quality = ItemName(b.itemKey)
  r.minBuyout, r.available, r.found = b.minPrice, b.totalQuantity, time()
  r.qty, r.total, r.loaded = nil, nil, false
  for k, v in pairs(deal) do r[k] = v end
  r.each = r.ref - b.minPrice
  return true
end

function Page:FinishRound()
  local s = self.state
  s.rounds = s.rounds + 1
  CM.Debug(("%s round %d done: %d items, %d deals."):format(self.cfg.name, s.rounds, s.seen, #s.rows))
  self:QueueLoads()
  if self.cfg.loop then
    -- Next round shortly; stops when you click Stop, leave the tab or
    -- close the auction house.
    C_Timer.After(self.cfg.roundPause or 2, function()
      if s.searching and self.tab:IsVisible() then self:SendQuery() end
    end)
  else
    s.searching = false
    s.finishedAt = time()
  end
  self:Refresh()
end

function Page:AskForMore()
  local s = self.state
  if not s.searching then return end
  if C_AuctionHouse.HasFullBrowseResults and C_AuctionHouse.HasFullBrowseResults() then
    s.inRound = false
    self:FinishRound()
    return
  end
  if C_AuctionHouse.IsThrottledMessageSystemReady and not C_AuctionHouse.IsThrottledMessageSystemReady() then
    s.waitingForServer = true -- AUCTION_HOUSE_THROTTLED_SYSTEM_READY continues
    return
  end
  s.waitingForServer = false
  CM.Try(self.cfg.name .. " RequestMoreBrowseResults", C_AuctionHouse.RequestMoreBrowseResults)
end

function Page:ReadBrowse()
  local s = self.state
  if not s.inRound then return end
  local all = C_AuctionHouse.GetBrowseResults() or {}
  local onlyNew = self.cfg.loop
  -- The first Snipe round only learns the current prices.
  local learning = onlyNew and s.rounds == 0 and s.firstRoundLearns
  for i = s.seen + 1, #all do
    local b = all[i]
    local key = KeyString(b.itemKey)
    local before = s.lastMin[key]
    local report = not onlyNew or (not learning and (before == nil or (b.minPrice or 0) < before))
    if b.minPrice then s.lastMin[key] = b.minPrice end
    self:Check(b, report)
  end
  s.seen = #all
  self:Refresh()
  self:AskForMore()
end

function Page:SendQuery()
  local s = self.state
  local order = Enum.AuctionHouseSortOrder
  s.seen, s.inRound = 0, true
  ns.browseOwner = self.cfg.owner -- so other tabs ignore these answers
  CM.Try(self.cfg.name .. " SendBrowseQuery", C_AuctionHouse.SendBrowseQuery, {
    searchString = "",
    sorts = order and { { sortOrder = order.Price, reverseSort = false } } or {},
    filters = {}, itemClassFilters = {},
  })
end

function Page:Stop()
  local s = self.state
  if not s.searching then return end
  s.searching, s.inRound = false, false
  s.finishedAt = time()
  -- Stopping early still looks up the deals found so far.
  self:QueueLoads()
  self:Refresh()
end

function Page:IsLoading()
  local s = self.state
  return s.loadingRow ~= nil or #(s.queue or {}) > 0
end

-- Stops looking up listings (the rows keep what they have).
function Page:StopLoading()
  local s = self.state
  s.queue, s.loadingRow, s.waitingToLoad = {}, nil, false
  self:Refresh()
end

-- Rows with nothing under the price limit stay (keepEmpty = true, or a
-- function(state) deciding per search mode).
function Page:KeepEmpty()
  local k = self.cfg.keepEmpty
  if type(k) == "function" then return k(self.state) end
  return k
end

function Page:Toggle(mode)
  local s = self.state
  if s.searching then self:Stop(); return end
  if self:IsLoading() then
    self:StopLoading()
    if mode == s.mode then return end -- Stop; another button starts its search
  end
  if not self.cfg.loop or s.mode ~= mode then
    s.rows, s.byKey, s.selected = {}, {}, nil
  end
  s.mode, s.waiting, s.rounds = mode, {}, 0
  if self.cfg.FillRows then
    -- A fixed list of items (the Shopping tab): no browse search, just
    -- look up each item's listings.
    self.cfg.FillRows(self)
    s.searching, s.finishedAt = false, time()
    self:QueueLoads()
    self:Refresh()
    return
  end
  s.searching, s.finishedAt = true, nil
  -- Prices seen before are kept (also across modes), so a restarted Snipe
  -- reports what was posted since it last looked.
  s.firstRoundLearns = next(s.lastMin) == nil
  self:SendQuery()
  self:Refresh()
end

-- Prices that arrive late.
function Page:OnItemInfo(itemID)
  local s = self.state
  local list = s.waiting[itemID]
  local changed = false
  if list then
    s.waiting[itemID] = nil
    for _, w in ipairs(list) do self:Check(w.b, w.report) end
    changed = true
  end
  for _, r in ipairs(s.rows) do
    if not r.name and r.itemID == itemID then r.name, r.quality = ItemName(r.itemKey); changed = true end
  end
  return changed
end

-- ------------------------------------------------------------------
-- One item: its listings under the deal's price limit
-- ------------------------------------------------------------------
-- Stackables: cost and profit of buying `want` units, cheapest first.
local function Plan(r, want)
  local left, cost, n = want, 0, 0
  for _, l in ipairs(r.cheap) do
    if left <= 0 then break end
    local take = math.min(left, l.quantity or 1)
    cost, n, left = cost + take * l.unitPrice, n + take, left - take
  end
  return n, cost, n * r.ref - cost
end

-- Stackables: how many of the cheap ones your gold pays for.
local function Affordable(r)
  local money, n, cost = GetMoney(), 0, 0
  for _, l in ipairs(r.cheap) do
    local q = l.quantity or 1
    local can = math.min(q, math.floor((money - cost) / l.unitPrice))
    if can <= 0 then break end
    n, cost = n + can, cost + can * l.unitPrice
    if can < q then break end
  end
  return n
end

function Page:ReadListings(r)
  local rows = {}
  if r.isCommodity then
    local n = C_AuctionHouse.GetNumCommoditySearchResults(r.itemID) or 0
    for i = 1, n do rows[#rows + 1] = C_AuctionHouse.GetCommoditySearchResultInfo(r.itemID, i) end
  else
    local n = C_AuctionHouse.GetNumItemSearchResults(r.itemKey) or 0
    for i = 1, n do rows[#rows + 1] = C_AuctionHouse.GetItemSearchResultInfo(r.itemKey, i) end
  end
  local qty, total, cheap, lowest, available = 0, 0, {}, nil, 0
  for _, l in ipairs(rows) do
    local q = l.quantity or 1
    available = available + q
    local unit = UnitOf(l)
    if unit and not l.containsOwnerItem then
      lowest = lowest and math.min(lowest, unit) or unit
      if unit <= r.limit and unit < r.ref then
        qty = qty + q
        total = total + math.floor((r.ref - unit) * q)
        cheap[#cheap + 1] = l
      end
    end
  end
  table.sort(cheap, function(a, b) return UnitOf(a) < UnitOf(b) end)
  r.qty, r.total, r.cheap, r.loaded, r.available = qty, total, cheap, true, available
  r.failed = false
  if lowest then
    r.minBuyout = math.floor(lowest)
    r.each = r.ref - r.minBuyout
  end
  local st = self.state
  if r == st.selected then
    if qty == 0 and self:KeepEmpty() then
      CM.Print("None of " .. (r.name or "that item") .. " under your max price right now.")
    elseif qty == 0 then
      CM.Print((r.name or "That item") .. " is no longer at that price; removed from the list.")
      st.selected = nil
    elseif r.isCommodity then
      -- Prefill the quantity with what your gold pays for (or, on the
      -- Shopping tab, what you still need).
      local n = Affordable(r)
      if self.cfg.WantQty then n = self.cfg.WantQty(r, n) end
      self.tab.qty:SetText(n)
    end
  end
  if qty == 0 and not self:KeepEmpty() then
    -- Already gone (or never a real deal): drop the row.
    for i, other in ipairs(st.rows) do
      if other == r then table.remove(st.rows, i); break end
    end
    st.byKey[KeyString(r.itemKey)] = nil
  end
  if r == st.loadingRow then
    st.loadingRow = nil
    C_Timer.After(0.05, function() self:LoadNext() end)
  end
  if r == st.selected or qty == 0 then self:Refresh() else self:RefreshSoon() end
  -- Opened from a click elsewhere (Shopping tab): start the purchase.
  if self.autoBuy == r and r == st.selected then
    self.autoBuy = nil
    if qty > 0 then self:Buy() end
  end
end

-- ------------------------------------------------------------------
-- Background loading: after a search, look up every deal's listings one
-- by one, so Below Vendor and Total Profit fill in without clicking.
-- ------------------------------------------------------------------
function Page:QueueLoads()
  local st = self.state
  st.queue = {}
  for _, r in ipairs(st.rows) do
    if not r.loaded then st.queue[#st.queue + 1] = r end
  end
  -- Most profitable first, so the useful rows fill in early.
  local function Worth(r) return (r.each or 0) * (r.available or 1) end
  table.sort(st.queue, function(a, b) return Worth(a) > Worth(b) end)
  st.loadTotal = #st.queue
  self:LoadNext()
end

function Page:LoadNext()
  local st = self.state
  -- Paused while a purchase is going on: searching another item in the
  -- middle of a purchase could disturb it.
  if st.loadingRow or st.buying or not self.tab:IsVisible() then return end
  if C_AuctionHouse.IsThrottledMessageSystemReady and not C_AuctionHouse.IsThrottledMessageSystemReady() then
    st.waitingToLoad = true -- AUCTION_HOUSE_THROTTLED_SYSTEM_READY continues
    return
  end
  st.waitingToLoad = false
  local r
  repeat r = table.remove(st.queue or {}, 1) until not r or (not r.loaded and st.byKey[KeyString(r.itemKey)] == r)
  if not r then return end
  st.loadingRow = r
  r.waitedForKey = false
  self:SearchListings(r)
  -- Don't get stuck on an item the server never answers for.
  -- Don't wait long: try once more at the end of the queue, then give up.
  C_Timer.After(4, function()
    if st.loadingRow == r then
      st.loadingRow = nil
      if r.retried then
        r.failed = true
      else
        r.retried = true
        st.queue[#st.queue + 1] = r
      end
      self:RefreshSoon()
      self:LoadNext()
    end
  end)
end

function Page:SearchListings(r)
  local info = C_AuctionHouse.GetItemKeyInfo(r.itemKey)
  if not info and not r.waitedForKey then
    -- The game drops searches for items it hasn't loaded yet: wait for
    -- ITEM_KEY_ITEM_INFO_RECEIVED (at most 2 seconds).
    r.waitingForKey, r.waitedForKey = true, true
    C_Timer.After(2, function()
      if r.waitingForKey then r.waitingForKey = false; self:SearchListings(r) end
    end)
    return
  end
  r.waitingForKey = false
  if info then
    r.isCommodity = info.isCommodity and true or false
    r.name = r.name or info.itemName
  end
  local order = Enum.AuctionHouseSortOrder
  local sorts = order and { { sortOrder = order.Buyout or order.Price, reverseSort = false } } or {}
  CM.Try(self.cfg.name .. " SendSearchQuery", C_AuctionHouse.SendSearchQuery, r.itemKey, sorts, true)
end

function Page:Select(r)
  if self.state.buying and self.state.buying.quote and self.state.buying.row ~= r then self:CancelQuote() end
  if self.state.loadingRow == r then self.state.loadingRow = nil end
  self.state.selected = r
  r.loaded, r.waitedForKey = false, false
  self:Refresh()
  self:SearchListings(r)
  -- Carry on with background lookups (they pause during a purchase).
  C_Timer.After(1, function() self:LoadNext() end)
end

-- ------------------------------------------------------------------
-- Buying
-- ------------------------------------------------------------------
local function RefText(r)
  if r.why == "Shopping" then return "Your max price" end
  return r.why == "Market" and "Market value" or "A vendor pays"
end
-- "profit", or on the Shopping tab how much under your max price it is.
local function GainWord(r) return r.why == "Shopping" and "under max" or "profit" end
-- The Shopping tab's ref is max price + 1 (so a listing at exactly your
-- max still counts); shown amounts take that 1c per item off again.
local function Ref(r) return r.why == "Shopping" and r.ref - 1 or r.ref end
local function Gain(r, n, profit) return r.why == "Shopping" and profit - n or profit end

function Page:UpdateBottom()
  local s, tab = self.state, self.tab
  local r = s.selected
  local b = tab.buyButton
  b:SetText("Buy")
  b:Disable()
  tab.qtyRow:SetShown(r and r.loaded and r.isCommodity and (r.qty or 0) > 0 or false)
  local p = s.buying
  if p and p.quote and p.row == r then
    -- The server quoted the exact price: the same button now buys.
    tab.detail:SetText(("Server price: %d for %s (profit %s). Click Confirm to buy."):format(
      p.qty, Money(p.quote.total), Money(p.quote.profit)))
    b:SetText("Confirm")
    b:SetEnabled(true)
    return
  end
  if not r then
    tab.detail:SetText("")
  elseif not r.loaded then
    tab.detail:SetText("Looking up " .. (r.name or "the item") .. "...")
  elseif (r.qty or 0) == 0 then
    tab.detail:SetText("Nothing at that price any more.")
  elseif r.isCommodity then
    local want = math.min(tonumber(tab.qty:GetText()) or 0, r.qty)
    local n, cost, profit = Plan(r, want)
    if n == 0 then
      tab.detail:SetText(("%d at that price. You can afford %d."):format(r.qty, Affordable(r)))
    elseif cost > GetMoney() then
      tab.detail:SetText(("Not enough gold: %d cost %s. You can afford %d."):format(n, Money(cost), Affordable(r)))
    else
      tab.detail:SetText(("%d at that price. Costs %s, %s %s."):format(r.qty, Money(cost), GainWord(r), Money(Gain(r, n, profit))))
      b:SetText("Buy " .. n)
      b:SetEnabled(not s.buying)
    end
  else
    local a = r.cheap[1]
    if a.buyoutAmount > GetMoney() then
      tab.detail:SetText(("Not enough gold for the cheapest one (%s)."):format(Money(a.buyoutAmount)))
    else
      tab.detail:SetText(("%d auctions at that price, about %s %s. Buys the cheapest first.")
        :format(#r.cheap, Money(r.total), GainWord(r)))
      b:SetText("Buy " .. Money(a.buyoutAmount))
      b:SetEnabled(not s.buying)
    end
  end
end

function Page:AfterPurchase()
  self.state.buying = false
  local r = self.state.selected
  if r then self:Select(r) end
  C_Timer.After(1, function() self:LoadNext() end) -- carry on with the lookups
end

function Page:Buy()
  local s, name = self.state, self.cfg.name
  local r = s.selected
  local p = s.buying
  CM.Debug(("%s: Buy button clicked (%s)."):format(name, p and (p.quote and "Confirm" or "busy") or "Buy"))
  if p and p.quote then
    -- Second click: buy at the quoted price.
    CM.Debug(("%s confirm: %d x %d for %d."):format(name, p.itemID, p.qty, p.quote.total))
    p.quote = nil
    self:UpdateBottom()
    CM.Try(name .. " ConfirmCommoditiesPurchase", C_AuctionHouse.ConfirmCommoditiesPurchase, p.itemID, p.qty)
    return
  end
  if not (r and r.loaded and (r.qty or 0) > 0) or s.buying then return end
  if r.isCommodity then
    local n, cost, profit = Plan(r, math.min(tonumber(self.tab.qty:GetText()) or 0, r.qty))
    if n == 0 or profit <= 0 or cost > GetMoney() then return end
    -- Ask the server for the exact price; COMMODITY_PRICE_UPDATED answers.
    s.buying = { itemID = r.itemID, qty = n, row = r, approved = cost }
    self:UpdateBottom()
    CM.Debug(("%s buy: %d x %d, expect %d, %s %d each."):format(name, r.itemID, n, cost, r.why or "", r.ref))
    -- If Blizzard blocks it, the purchase moves to Blizzard's window.
    local function Reset()
      s.buying = false
      self:UpdateBottom()
    end
    ns.StartStackPurchase(r.itemID, n, r.name, math.min(r.limit, r.ref - 1), Reset, function()
      Reset()
      self:LoadNext()
    end, ("Buy %d %s for %s (%s each)?\n%s %s (%s %s)."):format(n, r.name or "", Money(cost),
      Money(math.floor(cost / n + 0.5)), RefText(r), Money(Ref(r) * n), GainWord(r), Money(Gain(r, n, profit))))
  else
    local a = r.cheap[1]
    local q = 1 -- one auction per Buy click; buyoutAmount is per item
    CM.Debug(("%s buy: item %d auction %s buyout %s qty %d, %s %d each."):format(name, r.itemID,
      tostring(a.auctionID), tostring(a.buyoutAmount), q, r.why or "", r.ref))
    -- Never buy above the deal's limit.
    if not (a.buyoutAmount and a.buyoutAmount > 0 and a.buyoutAmount <= r.limit * q and a.buyoutAmount < r.ref * q)
        or a.buyoutAmount > GetMoney() then
      CM.Print("Not bought: that auction is no longer a good price.")
      return
    end
    -- Forever only allows buys from a popup's Accept.
    s.buying = { auctionID = a.auctionID, row = r }
    self:UpdateBottom()
    local profit = r.ref * q - a.buyoutAmount
    local function Reset()
      s.buying = false
      self:UpdateBottom()
    end
    ns.BuyAuction({
      auctionID = a.auctionID, amount = a.buyoutAmount, itemID = r.itemID, name = r.name, buyout = true,
      ask = ("Buy %s for %s (%s %s)?"):format(r.name or "item", Money(a.buyoutAmount), GainWord(r), Money(Gain(r, q, profit))),
      onDone = function()
        if r.why == "Vendor" then ns.vendorSingles[a.auctionID] = r.itemID end
        CM.Print(("Bought %s for %s (%s %s)."):format(r.name or "item", Money(a.buyoutAmount), GainWord(r), Money(Gain(r, q, profit))))
        -- Look again shortly; the bought auction leaves the list.
        C_Timer.After(1, function() self:AfterPurchase() end)
      end,
      onBlocked = Reset,
      onCancel = function() Reset(); self:LoadNext() end,
    })
  end
end

function Page:OnCommodityPrice(unitPrice, totalPrice)
  local s = self.state
  local p = s.buying
  if not (p and p.qty) then return end
  local r = p.row
  local profit = r.ref * p.qty - totalPrice
  if profit <= 0 or totalPrice > r.limit * p.qty then
    -- Someone bought the cheap ones first: stop instead of overpaying.
    s.buying = false
    if C_AuctionHouse.CancelCommoditiesPurchase then C_AuctionHouse.CancelCommoditiesPurchase() end
    CM.Print(("Not bought: the price went up to %s."):format(Money(totalPrice)))
    self:Select(r)
    return
  end
  -- You accepted this price (or less) in the first popup: buy now.
  if ns.AutoConfirmStack(p.itemID, p.qty, r.name, totalPrice, p.approved) then return end
  -- The price went up (still a profit), or Blizzard wants a popup: ask again.
  CM.Confirm(("Buy %d %s for %s (%s each)?\n%s %s (%s %s)."):format(
      p.qty, r.name or "", Money(totalPrice), Money(unitPrice), RefText(r), Money(Ref(r) * p.qty),
      GainWord(r), Money(Gain(r, p.qty, profit))),
    function()
      ns.ConfirmStackPurchase(p.itemID, p.qty, r.name, math.min(r.limit, r.ref - 1), function()
        s.buying = false
        self:UpdateBottom()
      end, totalPrice)
    end,
    function()
      s.buying = false
      if C_AuctionHouse.CancelCommoditiesPurchase then C_AuctionHouse.CancelCommoditiesPurchase() end
      self:UpdateBottom()
      self:LoadNext()
    end)
end

function Page:CancelQuote()
  local s = self.state
  if not (s.buying and s.buying.quote) then return end
  s.buying = false
  if C_AuctionHouse.CancelCommoditiesPurchase then C_AuctionHouse.CancelCommoditiesPurchase() end
  self:UpdateBottom()
  self:LoadNext()
end

-- ------------------------------------------------------------------
-- Building
-- ------------------------------------------------------------------
function Page:Build(parent)
  local cfg, s = self.cfg, self.state
  local skin = CM.Skins:Get()
  local prefix = "CueTheCashier" .. cfg.name
  local tab = CreateFrame("Frame", prefix .. "Tab", parent)
  self.tab = tab
  tab:SetAllPoints()
  tab:Hide()

  -- Search buttons, top right like Blizzard's Search button.
  tab.modeButtons = {}
  local anchor
  for i = #cfg.modes, 1, -1 do
    local m = cfg.modes[i]
    local b = CreateFrame("Button", prefix .. m.buttonName, tab, skin.buttonTemplate)
    b:SetSize(m.width or 120, 22)
    if anchor then b:SetPoint("RIGHT", anchor, "LEFT", -6, 0)
    else b:SetPoint("TOPRIGHT", -12, -44) end
    b.mode, b.label = m.mode, m.label
    b:SetText(m.label)
    b:SetScript("OnClick", function() self:Toggle(m.mode) end)
    table.insert(tab.modeButtons, 1, b)
    anchor = b
  end
  -- Optional extra controls (Snipe's percent box) left of the buttons.
  if cfg.BuildControls then anchor = cfg.BuildControls(tab, anchor) or anchor end

  tab.info = tab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  tab.info:SetPoint("TOPLEFT", LEFT + 4, -44)
  tab.info:SetPoint("RIGHT", anchor, "LEFT", -12, 0)
  tab.info:SetHeight(22)
  tab.info:SetJustifyH("LEFT")

  tab.headers = {}
  local x = LEFT + 4
  for _, col in ipairs(cfg.columns) do
    local h = CreateFrame("Button", nil, tab)
    h:SetSize(col.width - 2, ROW_HEIGHT)
    h:SetPoint("TOPLEFT", x, LIST_TOP)
    local bg = h:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    if not pcall(bg.SetAtlas, bg, "auctionhouse-tableheader") then bg:SetColorTexture(0.15, 0.15, 0.15, 0.9) end
    h:SetHighlightTexture("Interface\\PaperDollInfoFrame\\UI-Character-Tab-Highlight", "ADD")
    local label = h:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("LEFT", 8, 0)
    label:SetText(col.title)
    h.arrow = h:CreateTexture(nil, "OVERLAY")
    h.arrow:SetSize(9, 8)
    h.arrow:SetPoint("LEFT", label, "RIGHT", 4, 0)
    h.arrow:SetTexture("Interface\\Buttons\\UI-SortArrow")
    h:SetScript("OnClick", function()
      if s.sortKey == col.key then s.sortReverse = not s.sortReverse
      else s.sortKey, s.sortReverse = col.key, col.key ~= "name" end
      self:Refresh()
    end)
    tab.headers[col.key] = h
    x = x + col.width
  end

  local inset = CreateFrame("Frame", nil, tab, "InsetFrameTemplate")
  inset:SetPoint("TOPLEFT", LEFT, LIST_TOP - ROW_HEIGHT)
  inset:SetPoint("BOTTOMRIGHT", -28, 30)
  local box = CreateFrame("Frame", nil, tab, "WowScrollBoxList")
  local bar = CreateFrame("EventFrame", nil, tab, "MinimalScrollBar")
  local view = CreateScrollBoxListLinearView()
  view:SetElementInitializer("CueTheCashierResultRowTemplate", function(row, r) self:InitRow(row, r) end)
  if view.SetElementExtent then view:SetElementExtent(ROW_HEIGHT) end
  ScrollUtil.InitScrollBoxListWithScrollBar(box, bar, view)
  box:SetPoint("TOPLEFT", inset, "TOPLEFT", 4, -4)
  box:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -4, 4)
  bar:SetPoint("TOPLEFT", inset, "TOPRIGHT", 6, 0)
  bar:SetPoint("BOTTOMLEFT", inset, "BOTTOMRIGHT", 6, 0)
  tab.list = box

  tab.empty = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalMed1")
  tab.empty:SetPoint("TOP", inset, "TOP", 0, -100)
  tab.empty:SetText(cfg.emptyText)
  tab.empty:Hide()

  -- Bottom row: what the selected item offers, Quantity, Buy.
  local buy = CreateFrame("Button", prefix .. "BuyButton", tab, skin.buttonTemplate)
  buy:SetSize(140, 22)
  buy:SetPoint("BOTTOMRIGHT", -2, 5)
  buy:SetScript("OnClick", function() self:Buy() end)
  tab.buyButton = buy
  local qtyRow = CreateFrame("Frame", nil, tab)
  qtyRow:SetSize(150, 22)
  qtyRow:SetPoint("RIGHT", buy, "LEFT", -8, 0)
  local qty = CreateFrame("EditBox", prefix .. "Quantity", qtyRow, "InputBoxTemplate")
  qty:SetSize(60, 22)
  qty:SetPoint("RIGHT", qtyRow, "RIGHT", -4, 0)
  qty:SetNumeric(true)
  qty:SetAutoFocus(false)
  CM.Skins:StyleInput(qty)
  qty:SetScript("OnTextChanged", function() self:UpdateBottom() end)
  qty:SetScript("OnEnterPressed", qty.ClearFocus)
  local qtyLabel = qtyRow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  qtyLabel:SetPoint("RIGHT", qty, "LEFT", -10, 0)
  qtyLabel:SetText("Quantity")
  qtyRow:Hide()
  tab.qty, tab.qtyRow = qty, qtyRow
  tab.detail = tab:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  tab.detail:SetPoint("RIGHT", qtyRow, "LEFT", -8, 0)
  tab.detail:SetJustifyH("RIGHT")

  for _, e in ipairs({ "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", "AUCTION_HOUSE_BROWSE_RESULTS_ADDED",
      "AUCTION_HOUSE_THROTTLED_SYSTEM_READY", "GET_ITEM_INFO_RECEIVED", "ITEM_KEY_ITEM_INFO_RECEIVED",
      "COMMODITY_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_ADDED",
      "COMMODITY_PRICE_UPDATED", "COMMODITY_PRICE_UNAVAILABLE",
      "COMMODITY_PURCHASE_SUCCEEDED", "COMMODITY_PURCHASE_FAILED", "AUCTION_HOUSE_CLOSED", "PLAYER_MONEY" }) do
    tab:RegisterEvent(e)
  end
  -- The rows waiting for a listing answer: the clicked one and the one
  -- loading in the background.
  local function Waiting(match)
    if s.selected and match(s.selected) then return s.selected end
    if s.loadingRow and match(s.loadingRow) then return s.loadingRow end
  end
  tab:SetScript("OnEvent", function(_, event, arg, arg2)
    local r = s.selected
    if event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" or event == "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" then
      if s.searching and ns.browseOwner == cfg.owner then self:ReadBrowse() end
    elseif event == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then
      if s.waitingForServer and ns.browseOwner == cfg.owner then self:AskForMore() end
      if s.waitingToLoad then self:LoadNext() end
    elseif event == "GET_ITEM_INFO_RECEIVED" then
      if self:OnItemInfo(arg) then self:RefreshSoon() end
    elseif event == "ITEM_KEY_ITEM_INFO_RECEIVED" then
      local w = Waiting(function(row) return row.waitingForKey and row.itemID == arg end)
      if w then w.waitingForKey = false; self:SearchListings(w) end
      if self:OnItemInfo(arg) then self:RefreshSoon() end
    elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
      local w = Waiting(function(row) return row.isCommodity and row.itemID == arg end)
      if w then self:ReadListings(w) end
    elseif event == "ITEM_SEARCH_RESULTS_UPDATED" or event == "ITEM_SEARCH_RESULTS_ADDED" then
      local w = type(arg) == "table" and Waiting(function(row)
        return not row.isCommodity and KeyString(arg) == KeyString(row.itemKey)
      end)
      if w then self:ReadListings(w) end
    elseif event == "PLAYER_MONEY" then
      if tab:IsVisible() then self:UpdateBottom() end
    elseif event == "COMMODITY_PRICE_UPDATED" then
      self:OnCommodityPrice(arg, arg2)
    elseif event == "AUCTION_HOUSE_CLOSED" then
      self:Stop()
      self:StopLoading()
      s.buying = false
    elseif not (s.buying and s.buying.qty) then
      return -- purchase events from another tab
    elseif event == "COMMODITY_PRICE_UNAVAILABLE" then
      s.buying = false
      CM.Print("Those items are no longer available at that price.")
      if r then self:Select(r) end
    elseif event == "COMMODITY_PURCHASE_SUCCEEDED" then
      -- Bought to sell to a vendor: onto the "to vendor" list.
      local b = s.buying
      if b.row and b.row.why == "Vendor" and API.AddVendorBuy then API.AddVendorBuy(b.itemID, b.qty) end
      CM.Print(cfg.boughtText or "Purchase complete.")
      self:AfterPurchase()
    elseif event == "COMMODITY_PURCHASE_FAILED" then
      CM.Print("Purchase failed.")
      self:AfterPurchase()
    end
  end)
  tab:SetScript("OnShow", function() self:Refresh(); self:LoadNext() end)
  -- Leaving the tab stops a running Snipe, so it doesn't steal the Buy
  -- tab's searches. Prices it saw are kept for the next start.
  if cfg.loop then tab:SetScript("OnHide", function() self:Stop() end) end
  return tab
end

-- The one-key macro (CueTheCashier\OneKey.lua): on a deal tab (Vendor,
-- Snipe, Disenchant, Shopping) a press buys the selected item, the same as
-- its Buy button (Forever still asks in a confirm box; the next press
-- accepts it).
DealPage.pages = DealPage.pages or {}
if CM.OneKey then
  CM.OneKey.AddStep(DealPage, function()
    for _, page in ipairs(DealPage.pages) do
      local s = page.state
      if page.tab and page.tab:IsVisible() then
        local r = s.selected
        if s.buying and s.buying.quote then return "Confirm buy", function() page:Buy() end end
        if r and r.loaded and (r.qty or 0) > 0 and not s.buying then
          return "Buy " .. (r.name or "item"), function() page:Buy() end
        end
      end
    end
  end)
end
