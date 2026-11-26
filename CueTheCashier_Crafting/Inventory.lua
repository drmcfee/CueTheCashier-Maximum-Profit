-- CueTheCashier Crafting: what every character owns.
--
-- For the craft list and restocking we need to know where materials are:
-- this character's bags, bank and mailbox, and the same for your other
-- characters on this server and faction. Each character's counts are
-- saved when they change:
--   bags  at login and when bags change,
--   bank  when the bank is open (the game only shows it there),
--   mail  when the mailbox is open (items attached to unread mail too),
--   incoming  auction house buys made in CueTheCashier, counted as "in the
--         mailbox" right away (they arrive by mail) until you open it.
-- Saved per character: chars[key].inv = { bags = {[itemID]=n}, bank = {...},
--   mail = {...}, bagsT, bankT, mailT }.
-- Copyright (C) 2026 Kim. Licensed under the GNU GPL v3 or later; see LICENSE.
local _, ns = ...
local CM = CueTheCashier

local I = {}
ns.Inventory = I

local function Inv()
  local c = ns.Char()
  c.inv = c.inv or { bags = {}, bank = {}, mail = {} }
  return c.inv
end

local function CountBags(list)
  local counts, seen = {}, {}
  for _, bag in ipairs(list) do
    if bag and not seen[bag] then
      seen[bag] = true
      local ok, slots = pcall(C_Container.GetContainerNumSlots, bag)
      for slot = 1, (ok and slots) or 0 do
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if info and info.itemID then
          counts[info.itemID] = (counts[info.itemID] or 0) + (info.stackCount or 1)
        end
      end
    end
  end
  return counts
end

function I.ScanBags()
  local list = {}
  for bag = 0, (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) do list[#list + 1] = bag end
  local inv = Inv()
  inv.bags, inv.bagsT = CountBags(list), time()
end

-- Every bank container this client may have: the classic bank, bank bags,
-- the reagent bank and the newer bank tabs.
function I.ScanBank()
  local B = Enum and Enum.BagIndex or {}
  local list = { B.Bank or -1, B.Reagentbank or B.ReagentBank }
  local first = (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) + 1
  for bag = first, first + (NUM_BANKBAGSLOTS or 7) - 1 do list[#list + 1] = bag end
  for i = 1, 6 do list[#list + 1] = B["CharacterBankTab_" .. i] end
  local counts = CountBags(list)
  local inv = Inv()
  inv.bank, inv.bankT = counts, time()
  local n = 0
  for _ in pairs(counts) do n = n + 1 end
  CM.Debug(("Bank read: %d different items."):format(n))
end

function I.ScanMail()
  if not (GetInboxNumItems and GetInboxItem) then return end
  local counts = {}
  local max = ATTACHMENTS_MAX_RECEIVE or 16
  for i = 1, GetInboxNumItems() do
    for a = 1, max do
      local _, itemID, _, count = GetInboxItem(i, a)
      if itemID then counts[itemID] = (counts[itemID] or 0) + (count or 1) end
    end
  end
  local inv = Inv()
  inv.mail, inv.mailT = counts, time()
  inv.incoming = {} -- what was bought is now in the mail counts
end

-- A purchase made in CueTheCashier: on its way to the mailbox.
function I.Bought(itemID, n)
  if not itemID or not n or n <= 0 then return end
  local inv = Inv()
  inv.incoming = inv.incoming or {}
  inv.incoming[itemID] = (inv.incoming[itemID] or 0) + n
  CM.Debug(("Bought %d x %s: counted as in the mailbox."):format(n, ns.Costs.ItemName(itemID)))
  ns.CraftList.Refresh()
end

-- Other characters on this server and faction: { { name, bags, bank, mail }, ... }
local function Alts()
  local _, myKey = ns.Char()
  local server = CM.API.GetServerKey()
  local out = {}
  for key, c in pairs(ns.db.chars) do
    if key ~= myKey and c.inv and key:sub(-#server - 3) == " - " .. server then
      out[#out + 1] = { name = key:sub(1, #key - #server - 3), inv = c.inv }
    end
  end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

-- Where you have an item: { own = bags+bank, bags, bank, mail (incl.
--   bought and on the way), alts = { { name, count }, ... }, altTotal, total }
function I.Where(itemID)
  local inv = Inv()
  local bags = (inv.bags or {})[itemID] or 0
  local bank = (inv.bank or {})[itemID] or 0
  -- The game knows bags and bags + bank even away from the bank.
  if C_Item and C_Item.GetItemCount then
    local ok1, b = pcall(C_Item.GetItemCount, itemID, false)
    local ok2, all = pcall(C_Item.GetItemCount, itemID, true)
    if ok1 and b then bags = b end
    if ok2 and all then bank = math.max(0, all - bags) end
  end
  local own = bags + bank
  local mail = ((inv.mail or {})[itemID] or 0) + ((inv.incoming or {})[itemID] or 0)
  local auctions = (inv.auctions or {})[itemID] or 0
  local alts, altTotal = {}, 0
  for _, alt in ipairs(Alts()) do
    local i = alt.inv
    local n = ((i.bags or {})[itemID] or 0) + ((i.bank or {})[itemID] or 0) + ((i.mail or {})[itemID] or 0)
      + ((i.auctions or {})[itemID] or 0)
    if n > 0 then
      alts[#alts + 1] = { name = alt.name, count = n }
      altTotal = altTotal + n
    end
  end
  return { own = own, bags = bags, bank = bank, mail = mail, auctions = auctions, alts = alts, altTotal = altTotal,
    total = own + mail + auctions + altTotal }
end

-- Mailbox open: takes the first attachment of this item.
function I.TakeFromMail(itemID)
  if not (InboxFrame and InboxFrame:IsVisible() or (MailFrame and MailFrame:IsShown())) then
    CM.Print("Open your mailbox to take it.")
    return
  end
  for i = 1, GetInboxNumItems() do
    for a = 1, (ATTACHMENTS_MAX_RECEIVE or 16) do
      local _, id = GetInboxItem(i, a)
      if id == itemID then
        TakeInboxItem(i, a)
        return true
      end
    end
  end
  CM.Print("No mail with " .. ns.Costs.ItemName(itemID) .. " found.")
end

-- Bank open: moves one stack of this item to your bags.
function I.TakeFromBank(itemID)
  if not I.bankOpen then
    CM.Print("Open your bank to take it.")
    return
  end
  local B = Enum and Enum.BagIndex or {}
  local list = { B.Bank or -1, B.Reagentbank or B.ReagentBank }
  local first = (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) + 1
  for bag = first, first + (NUM_BANKBAGSLOTS or 7) - 1 do list[#list + 1] = bag end
  for i = 1, 6 do list[#list + 1] = B["CharacterBankTab_" .. i] end
  for _, bag in ipairs(list) do
    local ok, slots = pcall(C_Container.GetContainerNumSlots, bag)
    for slot = 1, (ok and slots) or 0 do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      if info and info.itemID == itemID then
        C_Container.UseContainerItem(bag, slot)
        return true
      end
    end
  end
  CM.Print("No " .. ns.Costs.ItemName(itemID) .. " found in the bank.")
end

-- Your own auctions still up (not sold), read whenever the AH lists them.
function I.ScanAuctions()
  if not (C_AuctionHouse and C_AuctionHouse.GetNumOwnedAuctions) then return end
  local counts = {}
  for i = 1, C_AuctionHouse.GetNumOwnedAuctions() or 0 do
    local a = C_AuctionHouse.GetOwnedAuctionInfo(i)
    local sold = a and Enum.AuctionStatus and a.status == Enum.AuctionStatus.Sold
    if a and a.itemKey and a.itemKey.itemID and not sold then
      counts[a.itemKey.itemID] = (counts[a.itemKey.itemID] or 0) + (a.quantity or 1)
    end
  end
  Inv().auctions = counts
end

function I.Register(module)
  module:RegisterEvent("OWNED_AUCTIONS_UPDATED", function() ns.Debounce("Read auctions", 0.3, function()
    I.ScanAuctions()
    ns.CraftList.Refresh()
  end) end)
  module:RegisterEvent("BAG_UPDATE_DELAYED", function()
    ns.Debounce("Read bags", 0.5, function()
      I.ScanBags()
      if I.bankOpen then I.ScanBank() end
      ns.CraftList.Refresh()
    end)
  end)
  module:RegisterEvent("BANKFRAME_OPENED", function()
    I.bankOpen = true
    ns.Debounce("Read bank", 0.3, I.ScanBank)
  end)
  module:RegisterEvent("BANKFRAME_CLOSED", function() I.bankOpen = false end)
  module:RegisterEvent("PLAYERBANKSLOTS_CHANGED", function()
    if I.bankOpen then ns.Debounce("Read bank", 0.3, I.ScanBank) end
  end)
  module:RegisterEvent("MAIL_INBOX_UPDATE", function() ns.Debounce("Read mail", 0.3, function()
    I.ScanMail()
    ns.CraftList.Refresh()
  end) end)
  -- Purchases made in CueTheCashier (Shopping, Buy, Vendor, Snipe tabs).
  local stack, singles = nil, {}
  module:RegisterMessage("CM_STACK_PURCHASE_CONFIRMING", function(_, _, itemID, _, quantity)
    stack = { itemID = itemID, quantity = quantity }
  end)
  module:RegisterEvent("COMMODITY_PURCHASE_SUCCEEDED", function()
    if stack then I.Bought(stack.itemID, stack.quantity) end
    stack = nil
  end)
  module:RegisterEvent("COMMODITY_PURCHASE_FAILED", function() stack = nil end)
  module:RegisterMessage("CM_BUYOUT_PLACED", function(_, _, auctionID, itemID)
    if auctionID then singles[auctionID] = itemID end
  end)
  module:RegisterEvent("AUCTION_HOUSE_PURCHASE_COMPLETED", function(_, _, auctionID)
    local id = auctionID and singles[auctionID]
    if id then
      singles[auctionID] = nil
      I.Bought(id, 1)
    end
  end)
  ns.Safe("Read bags", I.ScanBags)
end
