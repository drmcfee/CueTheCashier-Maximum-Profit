-- CueTheCashier: the small arrow next to Send Mail's To: box (0.42.3, Kim).
--
-- Replaces the big "Send Mail (n)" button. Click the arrow for a menu:
--   * Send by Mailing operations (n)  sends your group items, as the old
--     button did (hover it to see what goes where),
--   * Alts           your other characters on this server,
--   * Recently mailed  the last people you sent mail to,
--   * Friends / Guild  online first.
-- Picking a name puts it in the To: box. The button sits right of the box
-- (Kim's spot); if something else is there it goes just above the box.
-- Saved: CueTheCashierDB.mailNames[server key] = { full names by first name },
--        CueTheCashierDB.recentMail[server key] = { name, ... } (newest first).
-- Copyright (C) 2026 Kim. Licensed under the GNU GPL v3 or later; see LICENSE.
local _, CM = ...

local T = {}
CM.MailTo = T

local MAX_RECENT = 15
local MAX_LIST = 25
local arrow

local function Key() return CM:GetAuctionKey() end

local function Store(field)
  CueTheCashierDB[field] = CueTheCashierDB[field] or {}
  local t = CueTheCashierDB[field][Key()]
  if not t then
    t = {}
    CueTheCashierDB[field][Key()] = t
  end
  return t
end

-- Forever names can have two parts (first name and surname).
local function MyFullName()
  local first, second = UnitFullName and UnitFullName("player")
  first = first or UnitName("player")
  if not first then return nil end
  return (second and second ~= "") and (first .. " " .. second) or first, first
end

local function RememberMe()
  local full, first = MyFullName()
  if full then Store("mailNames")[first] = full end
end
CM.RegisterEvent(T, "PLAYER_LOGIN", function() CM.Try("Mail names", RememberMe) end)

local function IsMe(name)
  local me = (UnitName("player") or ""):lower()
  return (tostring(name):lower():match("^(%S+)") or "") == me
end

local function Alts()
  local out, names = {}, Store("mailNames")
  local gold = CueTheCashierDB.gold and CueTheCashierDB.gold[Key()] or {}
  local seen = {}
  local function Add(first)
    if seen[first] or IsMe(first) then return end
    seen[first] = true
    out[#out + 1] = names[first] or first
  end
  for first in pairs(names) do Add(first) end
  for first in pairs(gold) do Add(first) end
  table.sort(out)
  return out
end

local function Friends()
  local out = {}
  if not (C_FriendList and C_FriendList.GetNumFriends) then return out end
  for i = 1, C_FriendList.GetNumFriends() or 0 do
    local f = C_FriendList.GetFriendInfoByIndex(i)
    if f and f.name then out[#out + 1] = { name = f.name, online = f.connected } end
  end
  return out
end

local function Guild()
  local out = {}
  if not (IsInGuild and IsInGuild() and GetNumGuildMembers and GetGuildRosterInfo) then return out end
  for i = 1, GetNumGuildMembers() or 0 do
    local name, _, _, _, _, _, _, _, online = GetGuildRosterInfo(i)
    if name and not IsMe(name) then out[#out + 1] = { name = name, online = online } end
  end
  return out
end

-- Online first, then by name; at most MAX_LIST.
local function Sorted(list)
  table.sort(list, function(a, b)
    if (a.online and true or false) ~= (b.online and true or false) then return a.online and true or false end
    return a.name < b.name
  end)
  while #list > MAX_LIST do table.remove(list) end
  return list
end

local function Pick(name)
  local box = SendMailNameEditBox
  if not box then return end
  box:SetText(name)
  box:SetCursorPosition(0)
  if SendMailSubjectEditBox then SendMailSubjectEditBox:SetFocus() end
end

-- Remember who you mail: the name sent with SendMail, kept on success.
local pendingName, hooked
local function HookSend()
  if hooked or not hooksecurefunc or type(SendMail) ~= "function" then return end
  hooked = true
  hooksecurefunc("SendMail", function(name) pendingName = name end)
end
HookSend()
CM.RegisterEvent(T, "MAIL_SEND_SUCCESS", function()
  local name = pendingName
  pendingName = nil
  if not name or name == "" or IsMe(name) then return end
  local list = Store("recentMail")
  for i = #list, 1, -1 do
    if list[i]:lower() == name:lower() then table.remove(list, i) end
  end
  table.insert(list, 1, name)
  while #list > MAX_RECENT do table.remove(list) end
end)

local function NameList(root, title, list, empty)
  local sub = root:CreateButton(title)
  if #list == 0 then
    sub:CreateTitle(empty)
    return
  end
  for _, e in ipairs(list) do
    local name = type(e) == "table" and e.name or e
    local text = (type(e) == "table" and not e.online) and ("|cff808080" .. name .. "|r") or name
    sub:CreateButton(text, function() Pick(name) end)
  end
end

local function ShowMenu(owner)
  if not (MenuUtil and MenuUtil.CreateContextMenu) then
    -- No menu API: just send by operations.
    CM.Mailing.SendAll()
    return
  end
  local _, total = CM.Mailing.Plan()
  MenuUtil.CreateContextMenu(owner, function(_, root)
    root:CreateTitle("Send to")
    local send = root:CreateButton(CM.Mailing.IsSending() and "Sending..." or
      ("Send by Mailing operations (%d)"):format(total), function() CM.Mailing.SendAll() end)
    if send.SetEnabled then send:SetEnabled(total > 0 and not CM.Mailing.IsSending()) end
    if send.SetTooltip then
      send:SetTooltip(function(tooltip) pcall(CM.Mailing.SendTooltip, nil, tooltip) end)
    end
    root:CreateDivider()
    NameList(root, "Alts", Alts(), "No other characters seen yet")
    NameList(root, "Recently mailed", Store("recentMail"), "Nobody yet")
    NameList(root, "Friends", Sorted(Friends()), "No friends on your list")
    NameList(root, "Guild", Sorted(Guild()), "Not in a guild")
  end)
end

local function Make()
  if arrow or not (SendMailFrame and SendMailNameEditBox) then return arrow end
  local b = CreateFrame("Button", "CueTheCashierMailToButton", SendMailFrame)
  b:SetSize(22, 22)
  -- Blizzard's own small down arrow (the chat scroll-down button art).
  b:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
  b:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Down")
  b:SetDisabledTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Disabled")
  b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
  CM.Place.Attach(b, SendMailFrame, {
    { "LEFT", SendMailNameEditBox, "RIGHT", 6, 0 },
    { "BOTTOMRIGHT", SendMailNameEditBox, "TOPRIGHT", 0, 2 },
  }, { name = "Mail To arrow" })
  b:SetFrameLevel((SendMailNameEditBox:GetFrameLevel() or 1) + 2)
  b:SetScript("OnClick", function(self) ShowMenu(self) end)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Send to...", 1, 1, 1)
    GameTooltip:AddLine("Alts, people you mailed, friends, guild, or send your group items by their Mailing operations.",
      nil, nil, nil, true)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", GameTooltip_Hide)
  arrow = b
  return b
end

function T.Update()
  HookSend()
  CM.Try("Mail To arrow", Make)
end
CM.RegisterEvent(T, "MAIL_SHOW", function() C_Timer.After(0.3, T.Update) end)
