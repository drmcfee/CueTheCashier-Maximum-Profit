-- CueTheCashier: Post tab (Craft Trade). Posts and cancels by your Posting
-- operations (main window: Operations tab, picked per group).
--
-- Post Scan:   every item in your bags whose group has a Posting operation.
--              For each item it looks up the cheapest other auction, works
--              out a price from the operation, and how many to post (most
--              to have posted, minus what you already have up, never the
--              last "keep in bags" ones).
-- Cancel Scan: your auctions (with Cancel when undercut on) that someone
--              posted under, when reposting would still be at or above
--              your lowest price.
-- The scan only reads the auction house. Every post or cancel is one
-- click on the big button (Blizzard wants a click for each). If Forever
-- blocks that from our button, it switches to a confirm box for each
-- (one more click), like buying.
--
-- Price rules for posting (per item):
--   nobody else selling        normal price (or highest, as set)
--   cheapest other auction     post that much minus "undercut by"
--   ... above highest price    post at highest price
--   ... below lowest price     as set: don't post / lowest / normal / highest
-- Copyright (C) 2026 Kim. Licensed under the GNU GPL v3 or later; see LICENSE.
local _, ns = ...
local CM = CueTheCashier
local API = CM.API

local PostTab = {}
ns.PostTab = PostTab

local ROW_HEIGHT = 20
local LIST_TOP = -80
local LEFT = 8
local LOOKUP_TIMEOUT = 4
-- Game duration index: 1 = 2 hours, 2 = 8 hours, 3 = 24 hours on Forever.
local DURATIONS = { short = 1, medium = 2, long = 3, ["12"] = 1, ["24"] = 2, ["48"] = 3 }

local COLUMNS = {
  { title = "Item", width = 230 },
  { title = "Qty", width = 50, right = true },
  { title = "Price each", width = 120, right = true },
  { title = "Cheapest other", width = 120, right = true },
  { title = "What", width = 230 },
}

local tab
local state = { mode = nil, rows = {}, owned = {}, cache = {}, current = nil, pending = nil, usePopup = false }

local function Money(c) return c and CM.FormatMoney(c) or "" end
local function Sorts()
  local o = Enum.AuctionHouseSortOrder
  return o and { { sortOrder = o.Price, reverseSort = false } } or {}
end

-- ------------------------------------------------------------------
-- Bags
-- ------------------------------------------------------------------
local function LastBag() return NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4 end

-- { [itemID] = { count, location } } of items that can go on the AH.
local function BagItems()
  local out, refused = {}, {}
  for bag = 0, LastBag() do
    for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      if info and info.itemID and not info.isLocked then
        local e = out[info.itemID]
        if not e then
          local loc = ItemLocation and ItemLocation:CreateFromBagAndSlot(bag, slot)
          local ok = loc and (not C_AuctionHouse.IsSellItemValid
            or select(2, pcall(C_AuctionHouse.IsSellItemValid, loc, false)) ~= false)
          if ok then
            e = { count = 0, location = loc }
            out[info.itemID] = e
          elseif not refused[info.itemID] then
            refused[info.itemID] = true
            refused[#refused + 1] = (C_Item.GetItemInfo(info.itemID)) or ("item " .. info.itemID)
          end
        end
        if e then e.count = e.count + (info.stackCount or 1) end
      end
    end
  end
  if #refused > 0 then
    CM.Debug(("Post scan: Blizzard says these can't be sold here: %s."):format(table.concat(refused, ", ")))
  end
  return out
end

local function FindLocation(itemID)
  for bag = 0, LastBag() do
    for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      if info and info.itemID == itemID and not info.isLocked then
        return ItemLocation:CreateFromBagAndSlot(bag, slot)
      end
    end
  end
end

local function IsCommodity(loc)
  if not (loc and Enum.ItemCommodityStatus) then return false end
  local ok, status = pcall(C_AuctionHouse.GetItemCommodityStatus, loc)
  return ok and status == Enum.ItemCommodityStatus.Commodity
end

-- ------------------------------------------------------------------
-- Rules
-- ------------------------------------------------------------------
local function OpPrice(r, key) return API.GetOperationPrice("post", r.op, key, r.itemID) end

-- Works out the post price and quantity of a post row.
local function DecidePost(r)
  local s = r.settings
  -- 0.46.0 (Kim): expired so often that the deposits lost have eaten what
  -- the auction house earns over a vendor: sell it to a vendor instead.
  if API.GetRepostAdvice then
    local vendorIt, why = API.GetRepostAdvice(r.itemID)
    if vendorIt then
      r.action, r.note = "skip", "Vendor it: " .. tostring(why)
      return
    end
  end
  local minP, normal, maxP = OpPrice(r, "minPrice"), OpPrice(r, "normalPrice"), OpPrice(r, "maxPrice")
  local undercut = OpPrice(r, "undercut") or 0
  if not (minP and normal and maxP) then
    r.action, r.note = "skip", "a price in \"" .. r.op .. "\" has no value for this item"
    return
  end
  if maxP < minP then maxP = minP end
  local price, why
  if not r.lowest then
    if s.alone == "max" then price, why = maxP, "nobody else: highest" else price, why = normal, "nobody else: normal" end
  else
    local target = r.lowest - undercut
    if target > maxP then
      price, why = maxP, "cheapest is above highest"
    elseif target < minP then
      local rule = s.belowMin
      if rule == "min" then price, why = minP, "under lowest: at lowest"
      elseif rule == "normal" then price, why = normal, "under lowest: at normal"
      elseif rule == "max" then price, why = maxP, "under lowest: at highest"
      else r.action, r.note = "skip", "cheapest is under your lowest price"; return end
    else
      price, why = target, "undercut"
    end
  end
  local room = (s.postCap or 0) - (state.owned[r.itemID] or 0)
  local spare = r.count - (s.keep or 0)
  local qty = math.min(room, spare)
  if qty <= 0 then
    r.action = "skip"
    r.note = room <= 0 and ("%d already posted"):format(state.owned[r.itemID] or 0) or "keeping the rest"
    return
  end
  r.qty, r.price, r.action, r.note = qty, math.max(1, math.floor(price)), "post", why
end

local function DecideCancel(r)
  if not r.lowest or r.lowest >= r.price then
    r.action, r.note = "skip", "still the cheapest"
    return
  end
  local minP = OpPrice(r, "minPrice")
  local undercut = OpPrice(r, "undercut") or 0
  if minP and r.lowest - undercut < minP then
    r.action, r.note = "skip", "undercut, but under your lowest price"
    return
  end
  r.action, r.note = "cancel", "undercut"
end

-- ------------------------------------------------------------------
-- Looking up the cheapest other auction, one item at a time
-- ------------------------------------------------------------------
local LookupNext

local function ReadLowest(r)
  local lowest
  if r.isCommodity then
    for i = 1, C_AuctionHouse.GetNumCommoditySearchResults(r.itemID) or 0 do
      local x = C_AuctionHouse.GetCommoditySearchResultInfo(r.itemID, i)
      if x and x.unitPrice and x.unitPrice > 0 and (x.quantity or 0) > (x.numOwnerItems or 0) then
        lowest = x.unitPrice
        break
      end
    end
  else
    for i = 1, C_AuctionHouse.GetNumItemSearchResults(r.itemKey) or 0 do
      local x = C_AuctionHouse.GetItemSearchResultInfo(r.itemKey, i)
      -- Forever gives single items' buyout per item (seen in game).
      if x and not x.containsOwnerItem and (x.buyoutAmount or 0) > 0 then
        if not lowest or x.buyoutAmount < lowest then lowest = x.buyoutAmount end
      end
    end
  end
  return lowest
end

local function Decide(r)
  if r.kind == "cancel" then DecideCancel(r) else DecidePost(r) end
end

local function Finished(r, lowest)
  state.cache[r.itemID] = { lowest = lowest }
  r.lowest = lowest
  Decide(r)
  state.current = nil
  PostTab:Refresh()
  C_Timer.After(0.05, LookupNext)
end

local function Search(r, attempt)
  if state.current ~= r then return end
  r.waitingKey = false
  CM.Try("Post SendSearchQuery", C_AuctionHouse.SendSearchQuery, r.itemKey, Sorts(), true)
  C_Timer.After(LOOKUP_TIMEOUT, function()
    if state.current ~= r or r.answered then return end
    if attempt < 2 then
      Search(r, attempt + 1)
    else
      r.action, r.note = "skip", "no answer from the auction house"
      state.current = nil
      PostTab:Refresh()
      LookupNext()
    end
  end)
end

LookupNext = function()
  if not tab or state.current then return end
  for _, r in ipairs(state.rows) do
    if r.action == "lookup" then
      local hit = state.cache[r.itemID]
      if hit then
        r.lowest = hit.lowest
        Decide(r)
      else
        state.current = r
        r.answered = false
        local info = C_AuctionHouse.GetItemKeyInfo(r.itemKey)
        if info then
          Search(r, 1)
        else
          -- Searches for items whose info isn't loaded are dropped (seen
          -- in game): wait for it first.
          r.waitingKey = true
          C_Timer.After(2, function() if r.waitingKey and state.current == r then Search(r, 1) end end)
        end
        PostTab:Refresh()
        return
      end
    end
  end
  -- All looked up.
  local n = 0
  for _, r in ipairs(state.rows) do if r.action == "post" or r.action == "cancel" then n = n + 1 end end
  state.scanning = false
  CM.Print(("%s scan done: %d to %s."):format(state.mode == "cancel" and "Cancel" or "Post", n,
    state.mode == "cancel" and "cancel" or "post"))
  PostTab:Refresh()
end

-- ------------------------------------------------------------------
-- Scans
-- ------------------------------------------------------------------
local function CountOwned()
  wipe(state.owned)
  state.ownedList = {}
  for i = 1, C_AuctionHouse.GetNumOwnedAuctions() or 0 do
    local a = C_AuctionHouse.GetOwnedAuctionInfo(i)
    if a and a.itemKey and not (Enum.AuctionStatus and a.status == Enum.AuctionStatus.Sold) then
      local id = a.itemKey.itemID
      state.owned[id] = (state.owned[id] or 0) + (a.quantity or 1)
      state.ownedList[#state.ownedList + 1] = a
    end
  end
end

local function BuildPostRows()
  local rows = {}
  for itemID, e in pairs(BagItems()) do
    local op, settings = API.GetItemOperation(itemID, "post")
    if op then
      local isCommodity = IsCommodity(e.location)
      local S = Enum.ItemCommodityStatus
      if not isCommodity and S and e.location then
        -- Unknown status (item not loaded): the item's stack size tells,
        -- stackable trade goods and consumables are commodities. The
        -- search answer corrects it either way (see OnEvent).
        local status = select(2, pcall(C_AuctionHouse.GetItemCommodityStatus, e.location))
        if status ~= S.Item then
          local stack = select(8, C_Item.GetItemInfo(itemID))
          if stack and stack > 1 then isCommodity = true end
        end
      end
      local key = (not isCommodity and C_AuctionHouse.GetItemKeyFromItem
        and C_AuctionHouse.GetItemKeyFromItem(e.location)) or C_AuctionHouse.MakeItemKey(itemID)
      rows[#rows + 1] = { kind = "post", itemID = itemID, itemKey = key, isCommodity = isCommodity,
        count = e.count, op = op, settings = settings, action = "lookup", note = "looking up" }
    end
  end
  return rows
end

local function BuildCancelRows()
  local rows = {}
  for _, a in ipairs(state.ownedList or {}) do
    local itemID = a.itemKey.itemID
    local op, settings = API.GetItemOperation(itemID, "post")
    if op and settings.cancelUndercut then
      local isCommodity = C_AuctionHouse.GetItemKeyInfo(a.itemKey)
        and C_AuctionHouse.GetItemKeyInfo(a.itemKey).isCommodity
      rows[#rows + 1] = { kind = "cancel", itemID = itemID, auctionID = a.auctionID,
        itemKey = isCommodity and C_AuctionHouse.MakeItemKey(itemID) or a.itemKey,
        isCommodity = isCommodity and true or false, qty = a.quantity or 1, price = a.buyoutAmount,
        op = op, settings = settings, action = "lookup", note = "looking up" }
    end
  end
  return rows
end

local function SortRows()
  for _, r in ipairs(state.rows) do
    r.name = (C_Item.GetItemInfo(r.itemID)) or ("item " .. r.itemID)
  end
  table.sort(state.rows, function(a, b) return a.name < b.name end)
end

-- Bag items the game hasn't loaded yet. Kim's first Post Scan of a
-- session (0.41) found 4 items to post and the next one 10: until an item
-- is loaded, Blizzard's sell check and commodity status can say "no" or
-- "unknown", so such items were left out. Now we ask for them first and
-- wait (at most 3 seconds) before building the list.
local function NotLoaded()
  local list = {}
  for bag = 0, LastBag() do
    for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      local id = info and info.itemID
      if id and not list[id] and not C_Item.GetItemInfo(id) then
        list[id] = true
        if C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
      end
    end
  end
  return next(list) and list or nil
end

local BuildRows
local function AfterOwned()
  state.waitingOwned = false
  CountOwned()
  if state.mode ~= "cancel" and NotLoaded() then
    local started = GetTime()
    local function Wait()
      if not state.scanning then return end
      local left = NotLoaded()
      if left and GetTime() - started < 3 then C_Timer.After(0.2, Wait) return end
      if left then
        local n = 0
        for _ in pairs(left) do n = n + 1 end
        CM.Debug(("Post scan: %d bag items still not loaded after 3 s; going on without waiting."):format(n))
      end
      BuildRows()
    end
    CM.Debug("Post scan: waiting for bag items the game hasn't loaded yet.")
    Wait()
    return
  end
  BuildRows()
end

BuildRows = function()
  state.rows = state.mode == "cancel" and BuildCancelRows() or BuildPostRows()
  SortRows()
  if #state.rows == 0 then
    state.scanning = false
    CM.Print(state.mode == "cancel" and "Nothing to check: none of your auctions has a Posting operation with Cancel when undercut."
      or "Nothing to post: no item in your bags is in a group with a Posting operation.")
  end
  PostTab:Refresh()
  LookupNext()
end

function PostTab:Start(mode)
  if state.scanning then
    state.scanning, state.current = false, nil
    for _, r in ipairs(state.rows) do if r.action == "lookup" then r.action, r.note = "skip", "stopped" end end
    self:Refresh()
    return
  end
  state.mode, state.rows, state.current, state.pending, state.scanning = mode, {}, nil, nil, true
  wipe(state.cache)
  state.waitingOwned = true
  -- Your own auctions first: how many are up, and which to check.
  CM.Try("Post QueryOwnedAuctions", C_AuctionHouse.QueryOwnedAuctions, Sorts())
  C_Timer.After(3, function() if state.waitingOwned then AfterOwned() end end)
  self:Refresh()
end

-- ------------------------------------------------------------------
-- Posting and cancelling, one click each
-- ------------------------------------------------------------------
local function NextRow()
  for _, r in ipairs(state.rows) do
    if r.action == "post" or r.action == "cancel" then return r end
  end
end

local function Call(r)
  if r.action == "cancel" then
    return "CancelAuction", C_AuctionHouse.CancelAuction, { r.auctionID }
  end
  local loc = FindLocation(r.itemID)
  if not loc then return nil end
  r.location = loc
  local duration = DURATIONS[tostring(r.settings.duration)] or 2
  r.duration = duration
  if r.isCommodity then
    return "PostCommodity", C_AuctionHouse.PostCommodity, { loc, duration, r.qty, r.price }
  end
  return "PostItem", C_AuctionHouse.PostItem, { loc, duration, r.qty, nil, r.price }
end

local function Sent(r)
  r.action, r.note = "sent", r.kind == "cancel" and "cancelling..." or "posting..."
  state.pending = r
  -- No answer in 5 seconds: let the next one go anyway.
  C_Timer.After(5, function()
    if state.pending == r then
      state.pending = nil
      r.action, r.note = "done", "sent (no answer)"
      PostTab:Refresh()
    end
  end)
  PostTab:Refresh()
end

function PostTab:DoNext()
  if state.pending then return end
  local r = NextRow()
  if not r then return end
  local label, fn, args = Call(r)
  if not label then
    r.action, r.note = "skip", "not in your bags any more"
    self:Refresh()
    return
  end
  local text = r.action == "cancel"
    and ("Cancel your %s at %s?"):format(r.name, Money(r.price))
    or ("Post %d %s at %s each?"):format(r.qty, r.name, Money(r.price))
  if state.usePopup then
    ns.ProtectedCall({ label = label, fn = fn, args = args, ask = text, onDone = function() Sent(r) end,
      onBlocked = function() CM.Print("Blizzard blocked that even from the box. Post it in the Sell tab.") end })
    return
  end
  local before = CM.blockedCount or 0
  CM.Try(label, fn, unpack(args))
  if (CM.blockedCount or 0) > before then
    -- Like buying: Forever wants it from a confirm box. Ask from now on.
    state.usePopup = true
    CM.Print("Blizzard wants a confirm box for this. From now on every post and cancel asks first.")
    self:DoNext()
    return
  end
  Sent(r)
end

function PostTab:Skip()
  local r = NextRow()
  if r then r.action, r.note = "skip", "skipped" end
  self:Refresh()
end

-- ------------------------------------------------------------------
-- List
-- ------------------------------------------------------------------
local ACTION_COLOR = { post = "|cff00ff00", cancel = "|cffff9900", skip = "|cffaaaaaa", done = "|cffaaaaaa",
  sent = "|cffffff00", lookup = "|cffaaaaaa" }

local function InitRow(row, r)
  if not row.cells then
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    CM.Skins:Paint(hl, "highlight")
    row.icon = row:CreateTexture(nil, "OVERLAY")
    row.icon:SetSize(16, 16)
    row.icon:SetPoint("LEFT", 6, 0)
    row.cells = {}
    local x = 4
    for i, col in ipairs(COLUMNS) do
      local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      fs:SetPoint("LEFT", x + (i == 1 and 20 or 0), 0)
      fs:SetWidth(col.width - (i == 1 and 26 or 8))
      fs:SetJustifyH(col.right and "RIGHT" or "LEFT")
      fs:SetWordWrap(false)
      row.cells[i] = fs
      x = x + col.width
    end
    row:SetScript("OnEnter", function(rw) CM.ShowItemTooltip(rw, { itemID = rw.data.itemID }) end)
    row:SetScript("OnLeave", GameTooltip_Hide)
  end
  row.data = r
  CM.Skins:Stripe(row.bg, r.index)
  row.icon:SetTexture(C_Item.GetItemIconByID and C_Item.GetItemIconByID(r.itemID) or nil)
  local quality = select(3, C_Item.GetItemInfo(r.itemID))
  local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality or 1]
  row.cells[1]:SetText(((color and color.hex) or "") .. r.name .. "|r")
  row.cells[2]:SetText(r.qty or "")
  row.cells[3]:SetText(Money(r.price))
  row.cells[4]:SetText(r.action == "lookup" and "" or (r.lowest and Money(r.lowest) or "|cffaaaaaanone|r"))
  local verb = ({ post = "Post: ", cancel = "Cancel: " })[r.action] or ""
  row.cells[5]:SetText((ACTION_COLOR[r.action] or "") .. verb .. (r.note or "") .. "|r")
end

function PostTab:Refresh()
  if not tab then return end
  for i, r in ipairs(state.rows) do r.index = i end
  CM.SetRows(tab.list, state.rows)
  tab.empty:SetShown(#state.rows == 0 and not state.scanning)
  local looking, todo = 0, 0
  for _, r in ipairs(state.rows) do
    if r.action == "lookup" then looking = looking + 1 end
    if r.action == "post" or r.action == "cancel" then todo = todo + 1 end
  end
  tab.postScan:SetText(state.scanning and state.mode == "post" and "Stop" or "Post Scan")
  tab.cancelScan:SetText(state.scanning and state.mode == "cancel" and "Stop" or "Cancel Scan")
  tab.postScan:SetEnabled(not state.scanning or state.mode == "post")
  tab.cancelScan:SetEnabled(not state.scanning or state.mode == "cancel")
  if state.scanning and state.waitingOwned then
    tab.info:SetText("Reading your auctions...")
  elseif state.scanning then
    tab.info:SetText(("Looking up prices: %d left, %d ready."):format(looking, todo))
  elseif #state.rows > 0 then
    tab.info:SetText(("%d ready to %s."):format(todo, state.mode == "cancel" and "cancel" or "post"))
  else
    tab.info:SetText("")
  end
  local nextRow = NextRow()
  tab.doButton:SetEnabled(nextRow ~= nil and not state.pending)
  tab.skipButton:SetEnabled(nextRow ~= nil)
  if nextRow then
    tab.doButton:SetText(nextRow.action == "cancel" and ("Cancel (%d)"):format(todo) or ("Post (%d)"):format(todo))
    tab.nextText:SetText(nextRow.action == "cancel"
      and ("Next: cancel %s at %s"):format(nextRow.name, Money(nextRow.price))
      or ("Next: %d %s at %s each"):format(nextRow.qty, nextRow.name, Money(nextRow.price)))
  else
    tab.doButton:SetText(state.mode == "cancel" and "Cancel" or "Post")
    tab.nextText:SetText("")
  end
end

-- ------------------------------------------------------------------
-- Build
-- ------------------------------------------------------------------
function PostTab:Build(parent)
  local skin = CM.Skins:Get()
  tab = CreateFrame("Frame", "CueTheCashierPostTab", parent)
  tab:SetAllPoints()
  tab:Hide()

  tab.cancelScan = CreateFrame("Button", "CueTheCashierCancelScanButton", tab, skin.buttonTemplate)
  tab.cancelScan:SetSize(120, 22)
  tab.cancelScan:SetPoint("TOPRIGHT", -12, -44)
  tab.cancelScan:SetScript("OnClick", function() PostTab:Start("cancel") end)
  tab.postScan = CreateFrame("Button", "CueTheCashierPostScanButton", tab, skin.buttonTemplate)
  tab.postScan:SetSize(120, 22)
  tab.postScan:SetPoint("RIGHT", tab.cancelScan, "LEFT", -6, 0)
  tab.postScan:SetScript("OnClick", function() PostTab:Start("post") end)

  tab.info = tab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  tab.info:SetPoint("TOPLEFT", LEFT + 4, -44)
  tab.info:SetPoint("RIGHT", tab.postScan, "LEFT", -12, 0)
  tab.info:SetHeight(22)
  tab.info:SetJustifyH("LEFT")

  local x = LEFT + 4
  for _, col in ipairs(COLUMNS) do
    local h = CreateFrame("Frame", nil, tab)
    h:SetSize(col.width - 2, ROW_HEIGHT)
    h:SetPoint("TOPLEFT", x, LIST_TOP)
    local bg = h:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    if not pcall(bg.SetAtlas, bg, "auctionhouse-tableheader") then bg:SetColorTexture(0.15, 0.15, 0.15, 0.9) end
    local label = h:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("LEFT", 8, 0)
    label:SetText(col.title)
    x = x + col.width
  end

  local inset = CreateFrame("Frame", nil, tab, "InsetFrameTemplate")
  inset:SetPoint("TOPLEFT", LEFT, LIST_TOP - ROW_HEIGHT)
  inset:SetPoint("BOTTOMRIGHT", -28, 30)
  local box = CreateFrame("Frame", nil, tab, "WowScrollBoxList")
  local bar = CreateFrame("EventFrame", nil, tab, "MinimalScrollBar")
  local view = CreateScrollBoxListLinearView()
  view:SetElementInitializer("CueTheCashierResultRowTemplate", InitRow)
  if view.SetElementExtent then view:SetElementExtent(ROW_HEIGHT) end
  ScrollUtil.InitScrollBoxListWithScrollBar(box, bar, view)
  box:SetPoint("TOPLEFT", inset, "TOPLEFT", 4, -4)
  box:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -4, 4)
  bar:SetPoint("TOPLEFT", inset, "TOPRIGHT", 6, 0)
  bar:SetPoint("BOTTOMLEFT", inset, "BOTTOMRIGHT", 6, 0)
  tab.list = box

  tab.empty = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalMed1")
  tab.empty:SetPoint("TOP", inset, "TOP", 0, -90)
  tab.empty:SetWidth(520)
  tab.empty:SetText("Post Scan finds items in your bags whose group has a Posting operation.\n" ..
    "Cancel Scan finds your auctions that someone undercut.\n\n" ..
    "Make operations in the CueTheCashier window (/cmp): Operations, then Groups > Operations.")

  tab.doButton = CreateFrame("Button", "CueTheCashierPostDoButton", tab, skin.buttonTemplate)
  tab.doButton:SetSize(140, 22)
  tab.doButton:SetPoint("BOTTOMRIGHT", -2, 5)
  tab.doButton:SetScript("OnClick", function() PostTab:DoNext() end)
  tab.skipButton = CreateFrame("Button", nil, tab, skin.buttonTemplate)
  tab.skipButton:SetSize(70, 22)
  tab.skipButton:SetPoint("RIGHT", tab.doButton, "LEFT", -6, 0)
  tab.skipButton:SetText("Skip")
  tab.skipButton:SetScript("OnClick", function() PostTab:Skip() end)
  tab.nextText = tab:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  tab.nextText:SetPoint("RIGHT", tab.skipButton, "LEFT", -12, 0)
  tab.nextText:SetPoint("LEFT", tab, "BOTTOMLEFT", LEFT + 4, 16)
  tab.nextText:SetJustifyH("RIGHT")
  tab.nextText:SetWordWrap(false)

  tab:RegisterEvent("OWNED_AUCTIONS_UPDATED")
  tab:RegisterEvent("COMMODITY_SEARCH_RESULTS_UPDATED")
  tab:RegisterEvent("ITEM_SEARCH_RESULTS_UPDATED")
  tab:RegisterEvent("ITEM_KEY_ITEM_INFO_RECEIVED")
  tab:RegisterEvent("AUCTION_HOUSE_AUCTION_CREATED")
  tab:RegisterEvent("AUCTION_CANCELED")
  tab:RegisterEvent("AUCTION_HOUSE_POST_WARNING")
  tab:SetScript("OnEvent", function(_, event, arg)
    if event == "OWNED_AUCTIONS_UPDATED" then
      if state.waitingOwned then AfterOwned() end
    elseif event == "ITEM_KEY_ITEM_INFO_RECEIVED" then
      local r = state.current
      if r and r.waitingKey and arg == r.itemID then Search(r, 1) end
    elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" or event == "ITEM_SEARCH_RESULTS_UPDATED" then
      local r = state.current
      local id = type(arg) == "table" and arg.itemID or arg
      if r and not r.answered and id == r.itemID then
        r.answered = true
        -- The kind of answer tells if it stacks, whatever we guessed.
        r.isCommodity = event == "COMMODITY_SEARCH_RESULTS_UPDATED"
        if type(arg) == "table" then r.itemKey = arg end
        Finished(r, ReadLowest(r))
      end
    elseif event == "AUCTION_HOUSE_AUCTION_CREATED" or event == "AUCTION_CANCELED" then
      local r = state.pending
      if r then
        state.pending = nil
        r.action, r.note = "done", r.kind == "cancel" and "cancelled" or "posted"
        if r.kind == "post" then state.owned[r.itemID] = (state.owned[r.itemID] or 0) + (r.qty or 0) end
        PostTab:Refresh()
      end
    elseif event == "AUCTION_HOUSE_POST_WARNING" then
      local r = state.pending
      if not (r and r.location) then return end
      CM.Confirm("Blizzard warns about this auction. Post it anyway?", function()
        if r.isCommodity then
          CM.Try("ConfirmPostCommodity", C_AuctionHouse.ConfirmPostCommodity, r.location, r.duration, r.qty, r.price)
        else
          CM.Try("ConfirmPostItem", C_AuctionHouse.ConfirmPostItem, r.location, r.duration, r.qty, nil, r.price)
        end
      end)
    end
  end)
  tab:SetScript("OnHide", function()
    if state.scanning then PostTab:Start(state.mode) end -- stops it
  end)
  tab:SetScript("OnShow", function() PostTab:Refresh() end)
  self:Refresh()
  return tab
end

-- The one-key macro (CueTheCashier\OneKey.lua): while the Post tab is open,
-- a press posts or cancels its next line.
if CM.OneKey then
  CM.OneKey.AddStep(PostTab, function()
    if not (tab and tab:IsVisible()) or state.pending or state.scanning then return end
    local r = NextRow()
    if r then
      return (r.action == "cancel" and "Cancel " or "Post ") .. (r.name or "item"), function() PostTab:DoNext() end
    end
  end)
end
