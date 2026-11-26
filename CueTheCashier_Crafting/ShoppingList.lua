-- CueTheCashier Crafting: the Shopping List.
--
-- Where to get every reagent the Crafting List still needs, in sections:
--   Auction House  to buy there (click: Shopping tab, buy box)
--   Vendor         to buy from a merchant (click at a merchant: buy it)
--   Mailbox        already yours, waiting in the mail, including what you
--                  just bought on the auction house (click: take it)
--   Bank           in your bank (click with the bank open: take a stack)
--   Alts           on your other characters on this server and faction
-- What is in your bags already is not listed. The window opens by itself
-- at the auction house, a mailbox, the bank or a merchant when it has
-- something for that place (and closes again with it); the Crafting
-- List's Shopping List button or /cmp prof shop opens it any time.
-- Copyright (C) 2026 Kim. Licensed under the GNU GPL v3 or later; see LICENSE.
local _, ns = ...
local CM = CueTheCashier
local API = CM.API

local SL = {}
ns.ShoppingList = SL

local window
local GRAY = "|cff808080"

local function Money(c) return API.FormatMoney(math.floor((c or 0) + 0.5)) end
local function Name(id) return ns.Costs.ItemName(id) end

local function Build()
  local f = ns.ListWindow.New("CueTheCashierShoppingListFrame", "Shopping List", 360, 420, 56)
  CM.CloseOnEscape(f) -- one Escape closes it with Blizzard's windows (Core.lua)
  -- Opens where you last dragged it (0.42.0).
  f:LoadPosition(ns.db.settings, "shopPos")
  f.OnMoved = function(self) self:SavePosition(ns.db.settings, "shopPos") end
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

local function Lines(sec)
  local lines = {}
  local function Header(text, right)
    if #lines > 0 then lines[#lines + 1] = { left = " " } end
    lines[#lines + 1] = { header = text, right = right }
  end
  if #sec.auction > 0 then
    Header("Auction House", Money(sec.costAH))
    for _, e in ipairs(sec.auction) do
      lines[#lines + 1] = { left = ("%d x %s"):format(e.buy, Name(e.id)), right = Money(e.cost), itemID = e.id,
        tip = { { "To buy", e.buy }, { "Price each", Money(e.each) },
          "Click with the auction house open: the Shopping tab looks it up and asks to buy it." },
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
    lines[1] = { left = GRAY .. "Nothing to get: every reagent is in your bags (or nothing is on the Crafting List).|r" }
  end
  return lines
end

function SL.Refresh(summary)
  if not (window and window:IsShown()) then return end
  summary = summary or ns.CraftList.Summary()
  local sec = SL.Sections(summary)
  window:SetLines(Lines(sec))
  window.totals:SetText(("To buy: %s"):format(Money(sec.costAH + sec.costVendor)))
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
    CM.RegisterEvent(SL, event, function() ns.Debounce("Shopping list " .. event, 0.5, function() Opened(event) end) end)
  end
end
