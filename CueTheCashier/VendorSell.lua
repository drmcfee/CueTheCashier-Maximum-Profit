-- CueTheCashier: selling to vendors.
--
-- Two kinds of items go to a vendor with one click on the "Sell to vendor"
-- button on the merchant window:
--   * vendor buys: items bought on the auction house to sell to a vendor
--     (Vendor tab, Vendor Snipe). The Auctioning module adds them with
--     API.AddVendorBuy. Only that many are sold, never your own copies.
--   * items whose Vendoring operation says so (Operations tab): sell when
--     the auction value is under "When auction value is under", keeping
--     "Keep in bags".
--
-- Vendor buys count down when items leave your bags at a merchant, and
-- shrink when you have fewer than the list (posted on the AH instead,
-- used, ...). Items bought but still in the mail count as "in the mail"
-- until the mailbox has been read.
--
-- Saved per character: CueTheCashierDB.toVendor["Name - <server key>"] =
--   { items = { [itemID] = { n = count, pending = bought, not yet seen in the mailbox } },
--     mail = { [itemID] = count in the mailbox when last read } }
-- Copyright (C) 2026 Kim. Licensed under the GNU GPL v3 or later; see LICENSE.
local _, CM = ...
local API = CM.API

local V = {}
CM.VendorSell = V

local SELL_GAP = 0.2 -- seconds between two sales
local MAX_PER_CLICK = 12 -- the buyback tab holds 12: one click never sells more

local function Char()
  CueTheCashierDB.toVendor = CueTheCashierDB.toVendor or {}
  local key = (UnitName("player") or "?") .. " - " .. CM:GetAuctionKey()
  local c = CueTheCashierDB.toVendor[key]
  if not c then
    c = { items = {}, mail = {} }
    CueTheCashierDB.toVendor[key] = c
  end
  return c
end

local function ItemName(id) return (C_Item.GetItemInfo(id)) or ("item " .. id) end

local function BagsAndBank(id)
  local ok, n = pcall(C_Item.GetItemCount, id, true)
  return ok and n or 0
end

local function LastBag() return NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4 end

-- ------------------------------------------------------------------
-- The vendor-buy list
-- ------------------------------------------------------------------
function V.AddBuy(itemID, n)
  itemID, n = tonumber(itemID), tonumber(n) or 1
  if not itemID or n <= 0 then return end
  local e = Char().items[itemID] or { n = 0, pending = 0 }
  e.n, e.pending = e.n + n, (e.pending or 0) + n
  Char().items[itemID] = e
  CM.Debug(("To vendor: +%d %s (now %d)."):format(n, ItemName(itemID), e.n))
  CM.SendMessage("CM_VENDOR_LIST_CHANGED")
end

-- How many of an item you have: bags, bank, mailbox, and bought but not
-- seen in the mailbox yet.
function V.Have(itemID)
  local c = Char()
  local e = c.items[itemID]
  return BagsAndBank(itemID) + (c.mail[itemID] or 0) + (e and e.pending or 0)
end

-- Shrinks entries you no longer have that many of.
function V.Clamp()
  local c = Char()
  for id, e in pairs(c.items) do
    e.n = math.min(e.n, V.Have(id))
    if e.n <= 0 then c.items[id] = nil end
  end
end

-- { { itemID, n, inMail }, ... } sorted by name.
function V.List()
  V.Clamp()
  local c, out = Char(), {}
  for id, e in pairs(c.items) do
    local bags = C_Item.GetItemCount(id, false) or 0
    out[#out + 1] = { itemID = id, n = e.n, inBags = math.min(e.n, bags), inMail = math.max(0, e.n - bags) }
  end
  table.sort(out, function(a, b) return ItemName(a.itemID) < ItemName(b.itemID) end)
  return out
end

function V.Clear()
  wipe(Char().items)
  CM.SendMessage("CM_VENDOR_LIST_CHANGED")
end

-- ------------------------------------------------------------------
-- What to sell now
-- ------------------------------------------------------------------
local function SellPrice(id)
  local p = API.GetPrice(id, "vendor.sell")
  return p and p > 0 and p or nil
end

-- ------------------------------------------------------------------
-- "Vendor it" after too many reposts (0.46.0, Kim; per unit since 0.46.1)
-- What the auction house earns over a vendor, per item: the expected sale
-- after the cut minus the vendor sell price. Each expired auction lost its
-- deposit (about 20% of the vendor price per item). Units that failed so
-- often that their lost deposits reach that extra are better sold to a
-- vendor. Failed tries are counted per unit (Lots.lua): only the very
-- units that came back that often, never fresh crafts, and a sale doesn't
-- count as a fail. The Vendoring operation can set its own limit: a number
-- of failed tries, or deposits reaching a % of the vendor price.
-- Returns vendorIt, why, tired (units in bags and bank to vendor), or nil.
-- ------------------------------------------------------------------
-- How many failed tries make a unit "Vendor it", and the rule's text.
function V.RepostNeed(id)
  local vendor = SellPrice(id)
  if not vendor then return nil end
  local deposit = math.max(1, (CM.Fees and CM.Fees.Deposit(id, 1)) or 1)
  local s
  if CM.Operations then s = select(2, CM.Operations.ForItem(id, "vendor")) end
  local limit = s and tonumber(s.repostLimit) or 0
  local pct = s and tonumber(s.repostDepositPct) or 0
  local need, rule
  if limit > 0 then
    need, rule = limit, ("limit %d"):format(limit)
  elseif pct > 0 then
    need = math.max(1, math.ceil(vendor * pct / 100 / deposit))
    rule = ("deposits reach %d%% of the vendor price"):format(pct)
  else
    local value = API.GetPrice(id, "auction.market") or API.GetPrice(id, "auction.min")
    if not value then return nil end
    local cut = (CM.Fees and CM.Fees.CutRate()) or 0.05
    local extra = value * (1 - cut) - vendor
    need = math.max(1, math.ceil(extra / deposit))
    rule = ("deposits lost reach the %s the auction house earns over a vendor"):format(
      API.FormatMoney(math.max(0, math.floor(extra + 0.5))))
  end
  return need, rule
end

function V.RepostCheck(id)
  if not (CM.Lots and id) then return nil end
  local need, rule = V.RepostNeed(id)
  if not need then return nil end
  local tired = CM.Lots.Tired(id, need)
  if tired <= 0 then return false end
  return true, ("%d failed %d+ times (%s)"):format(tired, need, rule), tired
end
API.GetRepostAdvice = V.RepostCheck -- (itemID) -> vendorIt, why, units (API minor 14; units since 15)

-- Vendoring operation: how many of an item in your bags to sell.
local function ByOperation(id, inBags)
  if not CM.Operations then return 0 end
  local name, s = CM.Operations.ForItem(id, "vendor")
  if not (name and s.sell) then return 0 end
  local vendorIt, _, tired = V.RepostCheck(id)
  if vendorIt then return math.max(0, math.min(tired, inBags - (tonumber(s.keep) or 0))), "Vendor it" end
  local below = CM.Operations.Price("vendor", name, "sellBelow", id)
  local value = API.GetPrice(id, "auction.market") or API.GetPrice(id, "auction.min")
  -- Never seen on the auction house: no value to compare, keep it.
  if not (below and value and value < below) then return 0 end
  return math.max(0, inBags - (tonumber(s.keep) or 0))
end

-- { { itemID, count, why, money }, ... }, total money. withOps: also the
-- items a Vendoring operation says to sell (Shift-click); without it only
-- what you bought to sell to a vendor.
function V.Plan(withOps)
  V.Clamp()
  local c = Char()
  local bags = {}
  for bag = 0, LastBag() do
    for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      if info and info.itemID and not info.isLocked and not info.hasNoValue then
        bags[info.itemID] = (bags[info.itemID] or 0) + (info.stackCount or 1)
      end
    end
  end
  local plan, total = {}, 0
  for id, inBags in pairs(bags) do
    local price = SellPrice(id)
    if price then
      local e = c.items[id]
      local fromList = e and math.min(e.n, inBags) or 0
      local fromOp, opWhy = 0, nil
      if withOps then fromOp, opWhy = ByOperation(id, inBags) end
      local n = math.max(fromList, fromOp)
      if n > 0 then
        plan[#plan + 1] = { itemID = id, count = n, money = n * price,
          why = fromList >= fromOp and "bought to vendor" or opWhy or "Vendoring operation" }
        total = total + n * price
      end
    end
  end
  table.sort(plan, function(a, b) return a.money > b.money end)
  return plan, total
end

-- ------------------------------------------------------------------
-- Selling (one click = up to 12 stacks, so the buyback tab can undo it)
-- ------------------------------------------------------------------
local selling = false

-- Slots to sell for a plan: whole stacks only, biggest that fits first, so we never
-- sell more than planned (no splitting).
local function Slots(plan)
  local want = {}
  for _, p in ipairs(plan) do want[p.itemID] = p.count end
  local stacks = {}
  for bag = 0, LastBag() do
    for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      if info and info.itemID and want[info.itemID] and not info.isLocked then
        stacks[#stacks + 1] = { bag = bag, slot = slot, itemID = info.itemID, count = info.stackCount or 1 }
      end
    end
  end
  table.sort(stacks, function(a, b) return a.count > b.count end)
  local out = {}
  for _, s in ipairs(stacks) do
    if want[s.itemID] >= s.count then
      want[s.itemID] = want[s.itemID] - s.count
      out[#out + 1] = s
    end
  end
  return out, want
end

function V.SellAll(withOps)
  if selling then return end
  if not (MerchantFrame and MerchantFrame:IsShown()) then
    CM.Print("Talk to a vendor first.")
    return
  end
  local plan = V.Plan(withOps)
  local slots, left = Slots(plan)
  if #slots == 0 then
    local split = false
    for _, n in pairs(left) do if n > 0 then split = true end end
    CM.Print(split and "Only part of a stack is to be sold: split it by hand (Shift-click) and click again."
      or (withOps and "Nothing to sell." or "Nothing bought to vendor in your bags. Shift-click also sells Vendoring operation items."))
    return
  end
  selling = true
  local i, sold, money = 0, 0, 0
  local function Next()
    i = i + 1
    local s = slots[i]
    if not s or i > MAX_PER_CLICK or not (MerchantFrame and MerchantFrame:IsShown()) then
      selling = false
      CM.Print(("Sold %d stacks to the vendor for about %s.%s"):format(sold, API.FormatMoney(money),
        slots[i] and " Click again for the rest." or ""))
      CM.SendMessage("CM_VENDOR_LIST_CHANGED")
      return
    end
    local info = C_Container.GetContainerItemInfo(s.bag, s.slot)
    if info and info.itemID == s.itemID then
      CM.Try("Vendor sell", C_Container.UseContainerItem, s.bag, s.slot)
      sold, money = sold + 1, money + (SellPrice(s.itemID) or 0) * s.count
    end
    C_Timer.After(SELL_GAP, Next)
  end
  Next()
end

-- ------------------------------------------------------------------
-- Counting down: items leaving your bags while a merchant is open were
-- sold (by the button or by hand).
-- ------------------------------------------------------------------
local atMerchant, before = false, nil

local function Snapshot()
  local t = {}
  for id in pairs(Char().items) do t[id] = C_Item.GetItemCount(id, false) or 0 end
  return t
end

local function BagsChanged()
  if not (atMerchant and before) then return end
  local c, changed = Char(), false
  for id, was in pairs(before) do
    local now = C_Item.GetItemCount(id, false) or 0
    local e = c.items[id]
    if e and now < was then
      e.n = e.n - (was - now)
      changed = true
      if e.n <= 0 then c.items[id] = nil end
    end
  end
  before = Snapshot()
  if changed then CM.SendMessage("CM_VENDOR_LIST_CHANGED") end
end

-- The mailbox: what is in it now replaces "bought, not seen yet".
local function ReadMail()
  if not (GetInboxNumItems and GetInboxItem) then return end
  local c = Char()
  local counts = {}
  for i = 1, GetInboxNumItems() or 0 do
    for a = 1, ATTACHMENTS_MAX_RECEIVE or 16 do
      local _, itemID, _, count = GetInboxItem(i, a)
      if itemID then counts[itemID] = (counts[itemID] or 0) + (count or 1) end
    end
  end
  c.mail = counts
  for _, e in pairs(c.items) do e.pending = 0 end
end

-- ------------------------------------------------------------------
-- The button on the merchant window
-- ------------------------------------------------------------------
local button

local function UpdateButton()
  if not (MerchantFrame and MerchantFrame:IsShown()) then
    if button then button:Hide() end
    return
  end
  local plan, opsPlan = V.Plan(false), V.Plan(true)
  if not button then
    local skin = CM.Skins:Get()
    button = CreateFrame("Button", "CueTheCashierVendorSellButton", MerchantFrame, skin.buttonTemplate)
    button:SetSize(130, 22)
    -- GUESS: free space at the top of the merchant window, left of the
    -- Crafting module's Buy Reagents button.
    CM.Place.Attach(button, MerchantFrame, {
      { "TOPRIGHT", MerchantFrame, "TOPRIGHT", -148, -30 },
      { "TOPRIGHT", MerchantFrame, "BOTTOMRIGHT", -148, -2 },
      { "BOTTOMRIGHT", MerchantFrame, "TOPRIGHT", -148, 2 },
    }, { name = "Sell to Vendor button" })
    button:SetFrameLevel((MerchantFrame:GetFrameLevel() or 1) + 20)
    button:SetScript("OnClick", function() V.SellAll(IsShiftKeyDown()) end)
    button:SetScript("OnEnter", function(self)
      local p, t = V.Plan(false)
      local all, allT = V.Plan(true)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:AddLine("Click: sell what you bought to vendor", 1, 1, 1)
      for _, x in ipairs(p) do
        GameTooltip:AddDoubleLine(("%d x %s"):format(x.count, ItemName(x.itemID)), API.FormatMoney(x.money), 1, 1, 1, 1, 1, 1)
      end
      GameTooltip:AddDoubleLine("Total", API.FormatMoney(t), 1, 0.82, 0, 1, 1, 1)
      local inList = {}
      for _, x in ipairs(p) do inList[x.itemID] = x.count end
      local extra = false
      for _, x in ipairs(all) do
        if x.count > (inList[x.itemID] or 0) then
          if not extra then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Shift-click: also these (Vendoring operation)", 1, 1, 1)
            extra = true
          end
          local n = x.count - (inList[x.itemID] or 0)
          GameTooltip:AddDoubleLine(("%d x %s"):format(n, ItemName(x.itemID)), API.FormatMoney(n * (SellPrice(x.itemID) or 0)), 1, 1, 1, 1, 1, 1)
        end
      end
      if extra then GameTooltip:AddDoubleLine("Total with Shift", API.FormatMoney(allT), 1, 0.82, 0, 1, 1, 1) end
      local mail = 0
      for _, e in ipairs(V.List()) do mail = mail + e.inMail end
      if mail > 0 then GameTooltip:AddLine(("%d more bought to vendor are still in the mail or bank."):format(mail), 0.7, 0.7, 0.7, true) end
      GameTooltip:AddLine("Up to 12 stacks per click; the vendor's Buyback tab can undo it.", 0.7, 0.7, 0.7, true)
      GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end
  local n = 0
  for _, x in ipairs(plan) do n = n + x.count end
  button:SetText(("Sell to Vendor (%d)"):format(n))
  -- Shown whenever there is a list or something to sell; greyed out when
  -- nothing is in your bags yet (hover tells where the rest is).
  button:SetShown(#opsPlan > 0 or next(Char().items) ~= nil)
  button:SetEnabled(#opsPlan > 0)
end

-- /cmp tovendor: the list and what would be sold now, into the log.
function V.Report()
  CM.Log("=== To vendor ===")
  local list = V.List()
  for _, e in ipairs(list) do
    CM.Log(("%s: %d on the list, %d in bags, %d in mail or bank. Vendor pays %s each."):format(ItemName(e.itemID),
      e.n, e.inBags, e.inMail, SellPrice(e.itemID) and API.FormatMoney(SellPrice(e.itemID)) or "nothing (can't sell)"))
  end
  if #list == 0 then CM.Log("The list is empty. Buys on the Vendor tab and Vendor Snipe are added; /cmp tovendor add <item> [count] adds by hand.") end
  local plan, total = V.Plan(true)
  for _, x in ipairs(plan) do
    CM.Log(("Would sell %d x %s (%s) for %s."):format(x.count, ItemName(x.itemID), x.why, API.FormatMoney(x.money)))
  end
  CM.Log(("Would sell %d items for %s now. Merchant window open: %s."):format(#plan, API.FormatMoney(total),
    tostring(MerchantFrame and MerchantFrame:IsShown() or false)))
end

local owner = {}
CM.RegisterEvent(owner, "MERCHANT_SHOW", function()
  atMerchant = true
  before = Snapshot()
  CM.Try("Vendor sell button", UpdateButton)
  -- Blizzard's merchant window may open after this event reaches us.
  C_Timer.After(0.3, function() if atMerchant then CM.Try("Vendor sell button", UpdateButton) end end)
end)
CM.RegisterEvent(owner, "MERCHANT_CLOSED", function()
  atMerchant, before, selling = false, nil, false
  if button then button:Hide() end
end)
CM.RegisterEvent(owner, "BAG_UPDATE_DELAYED", function()
  CM.Try("Vendor count down", BagsChanged)
  if atMerchant then CM.Try("Vendor sell button", UpdateButton) end
end)
CM.RegisterEvent(owner, "MAIL_INBOX_UPDATE", function() CM.Try("Vendor list mail", ReadMail) end)
CM.RegisterMessage(owner, "CM_OPERATIONS_CHANGED", function() if atMerchant then CM.Try("Vendor sell button", UpdateButton) end end)

-- ------------------------------------------------------------------
-- API (minor 6)
-- ------------------------------------------------------------------
API.AddVendorBuy = V.AddBuy        -- (itemID, count): bought to sell to a vendor
API.GetVendorBuys = V.List         -- { { itemID, n, inBags, inMail }, ... }
API.GetVendorSellPlan = V.Plan     -- ([withOps]) -> { { itemID, count, why, money }, ... }, total
