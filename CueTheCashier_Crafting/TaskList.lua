-- CueTheCashier Crafting: the Task List (called the Shopping List before
-- 0.45.0; it now holds more than things to buy).
--
-- Profession crafts  what to craft (0.45.0; the Crafting List window is part
--                    of this since 0.46.0). Click: opens the right
--                    profession; with it open, a click crafts (the game
--                    needs that second click). Only when every reagent is
--                    in your bags; otherwise it says what is missing.
--                    Shift-click one more, right-click one less.
-- Then where to get every reagent the crafts still need:
--   Auction House  to buy there (click: Shopping tab, buy box)
--   Vendor         to buy from a merchant (click at a merchant: buy it)
--   Mailbox        already yours, waiting in the mail, including what you
--                  just bought on the auction house (click: take it)
--   Bank           in your bank (click with the bank open: take a stack)
--   Alts           on your other characters on this server and faction
-- What is in your bags already is not listed. The window opens by itself
-- at the auction house, a mailbox, the bank or a merchant when it has
-- something for that place, and with a profession window when crafts are
-- queued; the Craft List button's menu, the minimap button (right-click)
-- or /cmp prof tasks opens it any time. Saved settings keep their old names (shopPos,
-- shopAuto) so nothing is lost.
-- Copyright (C) 2026 Kim. Licensed under the GNU GPL v3 or later; see LICENSE.
local _, ns = ...
local CM = CueTheCashier
local API = CM.API

local SL = {}
ns.TaskList = SL
ns.ShoppingList = SL -- old name, kept so older callers still work

local window
local GRAY = "|cff808080"

local function Money(c) return API.FormatMoney(math.floor((c or 0) + 0.5)) end
local function Name(id) return ns.Costs.ItemName(id) end

local function Build()
  local f = ns.ListWindow.New("CueTheCashierTaskListFrame", "Task List", 360, 420, 56)
  CM.CloseOnEscape(f) -- one Escape closes it with Blizzard's windows (Core.lua)
  -- Opens where you last dragged it (0.42.0).
  f:LoadPosition(ns.db.settings, "shopPos")
  f.OnMoved = function(self) self:SavePosition(ns.db.settings, "shopPos") end
  -- The Crafting List's buttons (0.46.0, Kim: one list).
  f:AddButton("Clear", 60, function() ns.CraftList.Clear() end, "Takes every craft off the list.")
  local queue = f:AddButton("Queue...", 90, function(self, button)
    if button == "RightButton" then ns.CraftList.QueueMenu(self) else ns.GroupPicker.Show() end
  end, "Click: pick groups and queue their profitable recipes.\nRight-click: all profitable recipes, only the open profession, or restock items.")
  queue:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  return f
end

-- What each place has to do. sections = { auction, vendor, noPrice, mail, bank, alts }
function SL.Sections(summary)
  local out = { auction = {}, vendor = {}, noPrice = {}, mail = {}, bank = {}, alts = {}, costAH = 0, costVendor = 0 }
  for _, e in ipairs(summary.reagents) do
    local a = e.alloc
    if e.buy > 0 then
      if not e.each or not e.how or e.how == "craft" then
        table.insert(out.noPrice, e)
      elseif e.how == "vendor" then
        table.insert(out.vendor, e)
        out.costVendor = out.costVendor + e.cost
      else
        table.insert(out.auction, e)
        out.costAH = out.costAH + e.cost
      end
    end
    if a.mail > 0 then table.insert(out.mail, e) end
    if a.bank > 0 then table.insert(out.bank, e) end
    for _, alt in ipairs(a.alts) do
      out.alts[alt.name] = out.alts[alt.name] or {}
      table.insert(out.alts[alt.name], { e = e, count = alt.count })
    end
  end
  return out
end

local RED, GREEN = "|cffff4040", "|cff40ff40"

-- Profession crafts (0.45.0): one row per queued craft, in
-- the list's own order (rows keep their spots, Kim's rule).
local function CraftLines(lines, Header, crafts)
  if #crafts == 0 then return end
  local profit = 0
  for _, c in ipairs(crafts) do if not c.forReagent then profit = profit + (c.profit or 0) end end
  Header("Profession crafts", ns.ProfitText(profit))
  local profs = ns.Char().profs
  for _, c in ipairs(crafts) do
    local missing, can = ns.CraftList.BagCheck(c.id, 1)
    local prof = profs[c.skill]
    local right, tip
    if not missing then
      right = GRAY .. "open it once|r"
      tip = { "CueTheCashier hasn't read this recipe's reagents yet. Open its profession window once." }
    elseif #missing > 0 then
      right = RED .. "missing|r"
      tip = { "Missing in your bags (click does nothing else):" }
      for _, m in ipairs(missing) do
        tip[#tip + 1] = { ns.Costs.ItemName(m.id), ("%d of %d"):format(m.have, m.need) }
      end
    else
      right = GREEN .. "craft|r"
      local pname = prof and prof.name or "the profession"
      if c.skill and c.skill == ns.Professions.OpenProfession() then
        tip = { ("Click: crafts %d."):format(math.min(c.count, can)) }
      else
        tip = { ("Click: opens %s. Click again to craft %d (the game needs a second click)."):format(pname, math.min(c.count, can)) }
      end
      if can < c.count then tip[#tip + 1] = ("Your bags have reagents for %d of %d."):format(can, c.count) end
    end
    if c.forReagent then
      table.insert(tip, 1, "A reagent for another craft on the list: make it first.")
    elseif c.profit then
      table.insert(tip, 1, { "Profit", ns.ProfitText(c.profit) })
    end
    tip[#tip + 1] = "Shift-click: one more. Right-click: one less."
    local id = c.id
    lines[#lines + 1] = {
      left = ("%d x %s%s"):format(c.count, c.name, prof and (GRAY .. " (" .. prof.name .. ")|r") or ""),
      right = right, tip = tip,
      onClick = function(button)
        if button == "RightButton" then
          ns.CraftList.ChangeCount(id, -1)
        elseif IsShiftKeyDown and IsShiftKeyDown() then
          ns.CraftList.ChangeCount(id, 1)
        else
          ns.CraftList.CraftFromTask(c)
        end
      end }
  end
end

local function Lines(sec, crafts)
  local lines = {}
  local function Header(text, right)
    if #lines > 0 then lines[#lines + 1] = { left = " " } end
    lines[#lines + 1] = { header = text, right = right }
  end
  CraftLines(lines, Header, crafts or {})
  -- Crafts a Crafting operation gives to another character (0.46.0).
  local others = {}
  for itemID, x in pairs(ns.CraftList.Elsewhere()) do others[#others + 1] = { id = itemID, x = x } end
  table.sort(others, function(a, b)
    if a.x.who ~= b.x.who then return a.x.who < b.x.who end
    return Name(a.id) < Name(b.id)
  end)
  if #others > 0 then
    Header("Crafted by other characters")
    for _, o in ipairs(others) do
      local tip = { ("Log in on %s to craft it: the Crafting operation \"%s\" names them."):format(o.x.who, tostring(o.x.op)) }
      if o.x.note then tip[#tip + 1] = o.x.note end
      lines[#lines + 1] = { left = ("%s: %d x %s"):format(o.x.who, o.x.count, Name(o.id)), itemID = o.id, tip = tip }
    end
  end
  -- Vendor flip at this merchant (0.46.0).
  local flips = ns.Merchant.Flips and ns.Merchant.Flips() or {}
  if #flips > 0 then
    Header(("Vendor flip (%d%% discount)"):format(math.floor(flips[1].discount * 100 + 0.5)))
    for _, f in ipairs(flips) do
      lines[#lines + 1] = { left = Name(f.itemID), right = ns.ProfitText(f.profit), itemID = f.itemID,
        tip = { { "You pay", Money(f.paid) }, { "Post at", Money(f.post) },
          { "Profit each", Money(f.profit) }, { ("Profit per stack of %d"):format(f.stack), Money(f.profit * f.stack) },
          "After the auction house cut and deposit. A small profit on purpose: the post price stays under the full vendor price and at or under the cheapest auction now.",
          "Click: buy one stack." },
        onClick = function(button) if button == "LeftButton" then ns.Merchant.BuyFlip(f) end end }
    end
  end
  if #sec.auction > 0 then
    Header("Auction House", Money(sec.costAH))
    for _, e in ipairs(sec.auction) do
      -- "Vendor item, AH cheaper" (0.46.0): a vendor sells it too, but the
      -- auction house is cheaper now. Hidden when the saving is under 5%.
      local vendor = API.GetVendorBuyPrice and API.GetVendorBuyPrice(e.id)
      local cheaper = vendor and e.each and e.each < vendor * 0.95
      local tip = { { "To buy", e.buy }, { "Price each", Money(e.each) } }
      if cheaper then
        tip[#tip + 1] = { "Vendor price", Money(vendor) }
        tip[#tip + 1] = "A vendor sells it too, but the auction house is cheaper right now."
      end
      tip[#tip + 1] = "Click with the auction house open: the Shopping tab looks it up and asks to buy it."
      lines[#lines + 1] = { left = ("%d x %s%s"):format(e.buy, Name(e.id), cheaper and (GRAY .. " (vendor item, AH cheaper)|r") or ""),
        right = Money(e.cost), itemID = e.id,
        tip = tip,
        onClick = function(button) if button == "LeftButton" then ns.CraftList.BuyReagent(e) end end }
    end
  end
  if #sec.vendor > 0 then
    Header("Vendor", Money(sec.costVendor))
    for _, e in ipairs(sec.vendor) do
      local v = ns.Vendors.Nearest(e.id)
      lines[#lines + 1] = { left = ("%d x %s"):format(e.buy, Name(e.id)), right = Money(e.cost), itemID = e.id,
        tip = { { "To buy", e.buy }, { "Price each", Money(e.each) },
          { "Nearest vendor", v and ns.Vendors.Describe(v) or "none seen yet" },
          "Click: map pin on the nearest vendor that sells it. At that merchant, click buys it. Right-click: always the map pin." },
        onClick = function(button)
          if button == "LeftButton" and MerchantFrame and MerchantFrame:IsShown() then
            ns.CraftList.BuyReagent(e)
          else
            ns.Vendors.Pin(e.id)
          end
        end }
    end
  end
  if #sec.noPrice > 0 then
    Header("No price yet")
    for _, e in ipairs(sec.noPrice) do
      lines[#lines + 1] = { left = ("%d x %s"):format(e.buy, Name(e.id)), itemID = e.id,
        tip = { "Not on the auction house in your last scan and not sold by a vendor CueTheCashier knows." } }
    end
  end
  if #sec.mail > 0 then
    Header("Mailbox")
    for _, e in ipairs(sec.mail) do
      local id = e.id
      lines[#lines + 1] = { left = ("%d x %s"):format(e.alloc.mail, Name(id)), right = GRAY .. "take|r", itemID = id,
        tip = { "In your mailbox (bought items count here until you open it). Click with the mailbox open to take it." },
        onClick = function() ns.Inventory.TakeFromMail(id) end }
    end
  end
  if #sec.bank > 0 then
    Header("Bank")
    for _, e in ipairs(sec.bank) do
      local id = e.id
      lines[#lines + 1] = { left = ("%d x %s"):format(e.alloc.bank, Name(id)), right = GRAY .. "take|r", itemID = id,
        tip = { "In your bank. Click with the bank open to move a stack to your bags." },
        onClick = function() ns.Inventory.TakeFromBank(id) end }
    end
  end
  local alts = {}
  for name in pairs(sec.alts) do alts[#alts + 1] = name end
  table.sort(alts)
  if #alts > 0 then
    Header("Alts")
    local me = UnitName("player") or "you"
    for _, name in ipairs(alts) do
      for _, x in ipairs(sec.alts[name]) do
        lines[#lines + 1] = { left = ("%s: %d x %s"):format(name, x.count, Name(x.e.id)), itemID = x.e.id,
          tip = { ("Log in on %s and mail it to %s."):format(name, me) } }
      end
    end
  end
  if #lines == 0 then
    lines[1] = { left = GRAY .. "Nothing to do. Queue... (or the Craft List button in a profession window) adds crafts.|r" }
  end
  return lines
end

function SL.Refresh(summary)
  if not (window and window:IsShown()) then return end
  summary = summary or ns.CraftList.Summary()
  local sec = SL.Sections(summary)
  window:SetLines(Lines(sec, summary.crafts))
  window.totals:SetText(("Profit: %s     To buy: %s"):format(ns.ProfitText(summary.profit or 0),
    Money(sec.costAH + sec.costVendor)))
end

function SL.Show()
  window = window or Build()
  window:Show()
  SL.Refresh()
end

function SL.Hide()
  if window then window:Hide() end
end

-- Opens by itself at a place where the list has something to do, and
-- stays open after you leave (Kim, 0.19.1); close it yourself.
local PLACES = {
  AUCTION_HOUSE_SHOW = "auction",
  MERCHANT_SHOW = "vendor",
  MAIL_SHOW = "mail",
  BANKFRAME_OPENED = "bank",
}

local function Opened(event)
  if ns.db.settings.shopAuto == false then return end
  if window and window:IsShown() then return end
  local sec = SL.Sections(ns.CraftList.Summary())
  if #sec[PLACES[event]] > 0 then SL.Show() end
end

function SL.Register()
  for event in pairs(PLACES) do
    CM.RegisterEvent(SL, event, function() ns.Debounce("Task list " .. event, 0.5, function() Opened(event) end) end)
  end
end
