-- CueTheCashier: Mailing operations at the mailbox.
--
-- A "Send Mail (n)" button on the mailbox window sends the items in your
-- bags whose Mailing operation names a character (Operations tab: Send to
-- character, Send at most, Keep in bags). One click sends everything,
-- one mail per character and up to 12 stacks per mail, one after the
-- other (each mail waits for the game to say it was sent).
--
-- On the Inbox tab the same spot holds "Open Mail": click takes expired,
-- cancelled and bought auction items, right-click the money from sales.
--
-- Whole stacks only: when only part of a stack may go, it stays (split it
-- by hand). Soulbound items are never sent.
-- Copyright (C) 2026 Kim. Licensed under the GNU GPL v3 or later; see LICENSE.
local _, CM = ...
local API = CM.API

local Mail = {}
CM.Mailing = Mail

local function MaxAttach() return ATTACHMENTS_MAX_SEND or 12 end
local function LastBag() return NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4 end
local function ItemName(id) return (C_Item.GetItemInfo(id)) or ("item " .. id) end

-- Same character? Names on Forever have two parts; compare the first.
local function IsMe(target)
  local me = (UnitName("player") or ""):lower()
  local first = tostring(target):lower():match("^(%S+)") or ""
  return first == me or tostring(target):lower() == me
end

-- { [target] = { { bag, slot, itemID, count }, ... } }, number of stacks,
-- and { { itemID, target, count, op } } for the tooltip.
function Mail.Plan()
  local stacks, inBags = {}, {}
  for bag = 0, LastBag() do
    for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      if info and info.itemID and not info.isLocked and not info.isBound then
        stacks[#stacks + 1] = { bag = bag, slot = slot, itemID = info.itemID, count = info.stackCount or 1 }
        inBags[info.itemID] = (inBags[info.itemID] or 0) + (info.stackCount or 1)
      end
    end
  end
  -- How many of each item may go, and to whom.
  local want, targets, summary = {}, {}, {}
  for id, have in pairs(inBags) do
    local name, s = CM.Operations.ForItem(id, "mail")
    local target = name and CM.Operations and tostring(s.target or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if name and target ~= "" and not IsMe(target) then
      local n = have - (tonumber(s.keep) or 0)
      local cap = tonumber(s.send) or 0
      if cap > 0 then n = math.min(n, cap) end
      if n > 0 then want[id], targets[id] = n, target end
    end
  end
  -- Whole stacks, biggest that fits first.
  table.sort(stacks, function(a, b) return a.count > b.count end)
  local byTarget, total, counted = {}, 0, {}
  for _, s in ipairs(stacks) do
    local left = want[s.itemID]
    if left and left >= s.count then
      want[s.itemID] = left - s.count
      local t = targets[s.itemID]
      byTarget[t] = byTarget[t] or {}
      table.insert(byTarget[t], s)
      total = total + 1
      counted[s.itemID] = (counted[s.itemID] or 0) + s.count
    end
  end
  for id, n in pairs(counted) do
    summary[#summary + 1] = { itemID = id, target = targets[id], count = n }
  end
  table.sort(summary, function(a, b)
    if a.target ~= b.target then return a.target < b.target end
    return ItemName(a.itemID) < ItemName(b.itemID)
  end)
  return byTarget, total, summary
end

-- ------------------------------------------------------------------
-- Sending: one mail at a time, the next after MAIL_SEND_SUCCESS.
-- ------------------------------------------------------------------
local queue, sending

local function Finish(text)
  queue, sending = nil, nil
  if text then CM.Print(text) end
  Mail.Refresh()
end

local function SendNext()
  local m = queue and table.remove(queue, 1)
  if not m then return Finish("Mailing done.") end
  if ClearSendMail then ClearSendMail() end
  local attached = 0
  for i, s in ipairs(m.stacks) do
    local info = C_Container.GetContainerItemInfo(s.bag, s.slot)
    if info and info.itemID == s.itemID and not info.isLocked then
      C_Container.PickupContainerItem(s.bag, s.slot)
      ClickSendMailItemButton(i)
      attached = attached + 1
    end
  end
  if GetCursorInfo and GetCursorInfo() then ClearCursor() end
  if attached == 0 then return SendNext() end
  local cost = GetSendMailPrice and GetSendMailPrice() or 0
  if cost > GetMoney() then
    if ClearSendMail then ClearSendMail() end
    return Finish("Not enough money for the postage.")
  end
  sending = m
  local subject = ("CueTheCashier: %d items"):format(attached)
  CM.Debug(("Mailing %d stacks to %s (postage %d)."):format(attached, m.target, cost))
  CM.Try("SendMail", SendMail, m.target, subject, "")
end

function Mail.IsSending() return queue ~= nil end

function Mail.SendAll()
  if queue then return end
  local byTarget, total = Mail.Plan()
  if total == 0 then
    CM.Print("Nothing to mail. Give a group a Mailing operation with Send to character.")
    return
  end
  queue = {}
  for target, list in pairs(byTarget) do
    for i = 1, #list, MaxAttach() do
      local part = {}
      for j = i, math.min(i + MaxAttach() - 1, #list) do part[#part + 1] = list[j] end
      queue[#queue + 1] = { target = target, stacks = part }
    end
  end
  CM.Print(("Mailing: %d %s to send."):format(#queue, #queue == 1 and "mail" or "mails"))
  SendNext()
end

-- ------------------------------------------------------------------
-- The button
-- ------------------------------------------------------------------
local button -- one button: "Open Mail" on the Inbox tab, "Send Mail" on Send Mail

-- Is the mailbox showing its Inbox tab (else Send Mail)?
local function OnInbox()
  if InboxFrame and InboxFrame:IsVisible() then return true end
  if SendMailFrame and SendMailFrame:IsVisible() then return false end
  return (MailFrame and MailFrame.selectedTab or 1) == 1
end

local function SendTooltip(self, tooltip)
  local tt = tooltip or GameTooltip
  local _, n, summary = Mail.Plan()
  tt:AddLine("Send Mail (Mailing operations)", 1, 1, 1)
  local last
  for _, x in ipairs(summary) do
    if x.target ~= last then tt:AddLine("To " .. x.target, 1, 0.82, 0); last = x.target end
    tt:AddLine(("  %d x %s"):format(x.count, ItemName(x.itemID)), 1, 1, 1)
  end
  if n == 0 then
    tt:AddLine("Nothing to send: no item in your bags has a Mailing operation with Send to character (and more than Keep in bags). Groups > a group > Operations > Mailing. /cmp mail writes the details to the log.", 0.7, 0.7, 0.7, true)
  end
  tt:AddLine("Whole stacks only; up to 12 per mail. Postage is paid as usual.", 0.7, 0.7, 0.7, true)
end

Mail.SendTooltip = SendTooltip

local OpenTooltip -- below

function Mail.UpdateButton()
  local frame = MailFrame
  if not (frame and frame:IsShown()) then
    if button then button:Hide() end
    return
  end
  if not button then
    local skin = CM.Skins:Get()
    button = CreateFrame("Button", "CueTheCashierMailButton", frame, skin.buttonTemplate)
    button:SetSize(140, 22)
    -- GUESS: free space at the top right of the mailbox window.
    CM.Place.Attach(button, frame, {
      { "TOPRIGHT", frame, "TOPRIGHT", -12, -30 },
      { "TOPRIGHT", frame, "BOTTOMRIGHT", -12, -2 },
      { "BOTTOMRIGHT", frame, "TOPRIGHT", -12, 2 },
    }, { name = "Mail button" })
    button:SetFrameLevel((frame:GetFrameLevel() or 1) + 20)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:SetScript("OnClick", function(_, mouse)
      if button.mode == "send" then Mail.SendAll()
      else Mail.OpenAll(mouse == "RightButton" and "money" or "items") end
    end)
    button:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      if self.mode == "send" then SendTooltip(self) else OpenTooltip(self) end
      GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end
  if queue or not OnInbox() then
    -- Send Mail tab: no big button any more (0.42.3, Kim). Sending by
    -- Mailing operations is in the small arrow menu next to To: (MailTo.lua).
    button.mode = "send"
    button:Hide()
    if CM.MailTo then CM.MailTo.Update() end
    return
  else
    local n = Mail.OpenCount()
    button.mode = "open"
    button:SetText(Mail.IsOpening() and "Opening..." or ("Open Mail (%d)"):format(n))
    button:SetEnabled(not Mail.IsOpening() and n > 0)
  end
  button:Show()
end

-- /cmp mail: every Mailing operation, and what would be sent now, into the log.
function Mail.Report()
  CM.Log("=== Mailing ===")
  local names = CM.Operations.Names("mail")
  if #names == 0 then CM.Log("No Mailing operations yet (Operations tab > Mailing > New).") end
  for _, name in ipairs(names) do
    local s = CM.Operations.Settings("mail", name)
    local used = CM.Operations.UsedBy("mail", name)
    CM.Log(("Operation %s: send to %s, at most %s, keep %s. Groups: %s."):format(name,
      s.target ~= "" and s.target or "(nobody: fill in Send to character)", s.send == 0 and "all" or tostring(s.send),
      tostring(s.keep), #used > 0 and table.concat(used, ", ") or "none"))
  end
  local _, n, summary = Mail.Plan()
  for _, x in ipairs(summary) do CM.Log(("Would send %d x %s to %s."):format(x.count, ItemName(x.itemID), x.target)) end
  CM.Log(("%d stacks to send now. Mailbox open: %s."):format(n, tostring(MailFrame and MailFrame:IsShown() or false)))
end

-- ------------------------------------------------------------------
-- Open All, with a filter: everything, or only sales, buys, expired or
-- cancelled auctions. Takes money and items, one mail at a time, and
-- stops when your bags are full. Mails with cash on delivery and from
-- Blizzard (GM) are left alone.
-- ------------------------------------------------------------------
Mail.FILTERS = {
  { key = "items", label = "Click: expired, cancelled and bought items" },
  { key = "money", label = "Right-click: money from sales" },
}
-- Which mail kinds each filter opens.
local FILTER_KINDS = {
  items = { expired = true, cancelled = true, buy = true },
  money = { sale = true },
}

local function SubjectPattern(fmt)
  if not fmt then return nil end
  local p = fmt:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
  p = p:gsub("%%s", "(.+)"):gsub("%%d", "%%d+")
  return "^" .. p .. "$"
end

-- What kind of mail inbox index i is: "sale", "buy", "expired", "cancelled", "pending" or "other".
function Mail.Kind(i)
  local invoiceType = GetInboxInvoiceInfo and GetInboxInvoiceInfo(i)
  if invoiceType == "seller" then return "sale" end
  if invoiceType == "buyer" then return "buy" end
  if invoiceType == "seller_temp_invoice" then return "pending" end
  local subject = select(4, GetInboxHeaderInfo(i)) or ""
  local exp = SubjectPattern(AUCTION_EXPIRED_MAIL_SUBJECT)
  local can = SubjectPattern(AUCTION_REMOVED_MAIL_SUBJECT)
  if exp and subject:find(exp) then return "expired" end
  if can and subject:find(can) then return "cancelled" end
  return "other"
end

local function FreeSlots()
  local free = 0
  for bag = 0, LastBag() do
    local ok, n = pcall(C_Container.GetContainerNumFreeSlots, bag)
    if ok and n then free = free + n end
  end
  return free
end

-- Inbox indexes to open for a filter (last first, so indexes stay right).
function Mail.ToOpen(filter)
  local list = {}
  for i = (GetInboxNumItems() or 0), 1, -1 do
    local _, _, _, _, money, cod, _, itemCount, _, _, _, _, isGM = GetInboxHeaderInfo(i)
    local kind = Mail.Kind(i)
    local has = (money or 0) > 0 or (itemCount or 0) > 0
    if has and (cod or 0) == 0 and not isGM and kind ~= "pending"
        and (filter == "all" or filter == kind or (FILTER_KINDS[filter] and FILTER_KINDS[filter][kind])) then
      list[#list + 1] = i
    end
  end
  return list
end

local opening
local function OpenNext()
  if not opening then return end
  local i = table.remove(opening.list, 1)
  if not i or not (MailFrame and MailFrame:IsShown()) then
    local o = opening
    opening = nil
    CM.Print(("Opened %d %s%s."):format(o.done, o.done == 1 and "mail" or "mails", o.money > 0 and (", " .. API.FormatMoney(o.money)) or ""))
    Mail.Refresh()
    -- The inbox list catches up a moment later: count again then.
    C_Timer.After(1, Mail.Refresh)
    return
  end
  local _, _, _, _, money, _, _, itemCount = GetInboxHeaderInfo(i)
  if (itemCount or 0) > 0 and FreeSlots() == 0 then
    local o = opening
    opening = nil
    CM.Print(("Bags full: opened %d mails, stopped."):format(o.done))
    return
  end
  opening.done, opening.money = opening.done + 1, opening.money + (money or 0)
  if opening.filter == "money" then
    -- Money only: items (if any) stay in the mail.
    CM.Try("TakeInboxMoney", TakeInboxMoney, i)
  elseif AutoLootMailItem then
    CM.Try("AutoLootMailItem", AutoLootMailItem, i)
  else
    if (money or 0) > 0 then CM.Try("TakeInboxMoney", TakeInboxMoney, i) end
    for a = 1, ATTACHMENTS_MAX_RECEIVE or 16 do
      if GetInboxItem(i, a) then CM.Try("TakeInboxItem", TakeInboxItem, i, a) end
    end
  end
  -- The server answers each take; give it a moment before the next mail.
  C_Timer.After(0.4, OpenNext)
end

function Mail.OpenAll(filter)
  if opening then return end
  local list = Mail.ToOpen(filter or "all")
  if #list == 0 then CM.Print("No mail to open for that choice."); return end
  opening = { list = list, done = 0, money = 0, filter = filter or "all" }
  Mail.Refresh()
  OpenNext()
end

local function Count(filter) return #Mail.ToOpen(filter) end
function Mail.OpenCount() return Count("items") + Count("money") end
function Mail.IsOpening() return opening ~= nil end

OpenTooltip = function()
  GameTooltip:AddLine("Open Mail", 1, 1, 1)
  for _, f in ipairs(Mail.FILTERS) do
    GameTooltip:AddDoubleLine(f.label, tostring(Count(f.key)), 1, 1, 1, 1, 1, 1)
  end
  local sales = 0
  for _, i in ipairs(Mail.ToOpen("money")) do sales = sales + (select(5, GetInboxHeaderInfo(i)) or 0) end
  if sales > 0 then GameTooltip:AddDoubleLine("Money waiting from sales", API.FormatMoney(sales), 1, 0.82, 0, 1, 1, 1) end
  GameTooltip:AddLine("Cash on delivery and Blizzard mail are left alone. The Send Mail tab shows Send Mail here.", 0.7, 0.7, 0.7, true)
end

local owner = {}
local hooked
function Mail.Refresh()
  CM.Try("Mail button", Mail.UpdateButton)
  -- Switching between the Inbox and Send Mail tabs changes the button.
  -- Hooks add to Blizzard's code without replacing it.
  if not hooked then
    hooked = true
    local function Later() C_Timer.After(0.05, Mail.Refresh) end
    if hooksecurefunc and MailFrameTab_OnClick then hooksecurefunc("MailFrameTab_OnClick", Later) end
    for _, f in ipairs({ InboxFrame, SendMailFrame }) do
      if f and f.HookScript then f:HookScript("OnShow", Later) end
    end
  end
end
local Update = Mail.Refresh
CM.RegisterEvent(owner, "MAIL_SHOW", function()
  Update()
  C_Timer.After(0.3, Update) -- the mail window may open after this event reaches us
end)
CM.RegisterEvent(owner, "MAIL_CLOSED", function()
  if queue then Finish("Mailing stopped: the mailbox closed.") end
  opening = nil
  if button then button:Hide() end
end)
CM.RegisterEvent(owner, "MAIL_INBOX_UPDATE", function()
  if MailFrame and MailFrame:IsShown() and not opening then Mail.Refresh() end
end)
CM.RegisterEvent(owner, "MAIL_SEND_SUCCESS", function()
  if not sending then return end
  local m = sending
  sending = nil
  CM.Debug("Mail sent to " .. m.target .. ".")
  C_Timer.After(0.5, function() if queue then SendNext() end end)
end)
CM.RegisterEvent(owner, "MAIL_FAILED", function()
  if sending then Finish("A mail could not be sent (check the name in the Mailing operation).") end
end)
CM.RegisterEvent(owner, "BAG_UPDATE_DELAYED", function()
  if MailFrame and MailFrame:IsShown() and not queue then Update() end
end)
CM.RegisterMessage(owner, "CM_OPERATIONS_CHANGED", function() if MailFrame and MailFrame:IsShown() then Update() end end)

API.OpenMail = Mail.OpenAll -- ([filter]): "items", "money", "all", "sale", "buy", "expired", "cancelled"
API.GetMailPlan = function() local _, n, summary = Mail.Plan(); return summary, n end -- { { itemID, target, count } }, stacks
API.GetMailKind = Mail.Kind -- (inbox index) -> sale/buy/pending/expired/cancelled/other (minor 10)
