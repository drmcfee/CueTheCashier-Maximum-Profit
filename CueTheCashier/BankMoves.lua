-- CueTheCashier: moving group items between bags and bank.
--
-- At the bank a "Bank Moves" button (top right of Blizzard's bank window)
-- opens a menu:
--   To Bank / To Bags: every item whose group has a Warehousing operation.
--     To Bank leaves "Keep in bags" in your bags; To Bags takes from the
--     bank until your bags hold "Take to bags" (0 = everything).
--   A whole group, to the bank or to your bags (its Warehousing operation
--     still sets the amounts when it has one, otherwise everything moves).
-- One stack moves every 0.15 seconds (stacks are split when only part of
-- one should move). Items go into empty slots; the reagent bag is left out.
-- GUESS: Forever's bank uses either the classic bank bags or the newer
-- character bank tabs; both are looked for.
-- Copyright (C) 2026 Kim. Licensed under the GNU GPL v3 or later; see LICENSE.
local _, CM = ...
local API = CM.API

local B = {}
CM.BankMoves = B

local STEP = 0.15
local MAX_STEPS = 300
local running

function B.Bags()
  local list = {}
  for bag = 0, NUM_BAG_SLOTS or 4 do list[#list + 1] = bag end
  return list
end

function B.BankBags()
  local list = {}
  local idx = Enum and Enum.BagIndex
  if idx and idx.CharacterBankTab_1 then
    for i = 1, 6 do
      local id = idx["CharacterBankTab_" .. i]
      if id and (C_Container.GetContainerNumSlots(id) or 0) > 0 then list[#list + 1] = id end
    end
  end
  if #list == 0 then
    list[#list + 1] = BANK_CONTAINER or -1
    local first = (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) + 1
    for bag = first, first + (NUM_BANKBAGSLOTS or 7) - 1 do
      if (C_Container.GetContainerNumSlots(bag) or 0) > 0 then list[#list + 1] = bag end
    end
  end
  return list
end

-- { [itemID] = { count, slots = { {bag, slot, count, locked}, ... } } }
local function Contents(bags)
  local out = {}
  for _, bag in ipairs(bags) do
    for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      if info and info.itemID then
        local e = out[info.itemID] or { count = 0, slots = {} }
        out[info.itemID] = e
        e.count = e.count + (info.stackCount or 1)
        e.slots[#e.slots + 1] = { bag = bag, slot = slot, count = info.stackCount or 1, locked = info.isLocked }
      end
    end
  end
  return out
end

local function EmptySlot(bags)
  for _, bag in ipairs(bags) do
    for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
      if not C_Container.GetContainerItemInfo(bag, slot) then return bag, slot end
    end
  end
end

-- The items to move and their limits. which = "ops" or a group id.
-- Returns { [itemID] = { keep = n, take = n } } (take 0 = all).
function B.Targets(which, bagItems, bankItems)
  local out = {}
  local function Add(id, settings)
    out[id] = { keep = tonumber(settings and settings.keepInBags) or 0,
                take = tonumber(settings and settings.takeToBags) or 0 }
  end
  if which == "ops" then
    for _, list in ipairs({ bagItems, bankItems }) do
      for id in pairs(list) do
        local op, settings = API.GetItemOperation(id, "bank")
        if op then Add(id, settings) end
      end
    end
  else
    for id in pairs(API.GetGroupItems(which, true)) do
      local _, settings = API.GetItemOperation(id, "bank")
      Add(id, settings)
    end
  end
  return out
end

-- The next move: { from = {bag, slot}, to = {bag, slot}, count, split }, or nil.
-- Also returns how many moves are left (rough, for the report).
function B.NextMove(direction, which)
  local bags, bank = B.Bags(), B.BankBags()
  local bagItems, bankItems = Contents(bags), Contents(bank)
  local targets = B.Targets(which, bagItems, bankItems)
  local fromItems, toBags = direction == "bank" and bagItems or bankItems, direction == "bank" and bank or bags
  local left, move = 0, nil
  for id, t in pairs(targets) do
    local src = fromItems[id]
    local inBags = bagItems[id] and bagItems[id].count or 0
    local want
    if direction == "bank" then
      want = inBags - t.keep
    else
      want = (t.take == 0) and math.huge or (t.take - inBags)
    end
    if src and want > 0 then
      left = left + 1
      if not move then
        table.sort(src.slots, function(a, b) return a.count > b.count end)
        for _, s in ipairs(src.slots) do
          if not s.locked then
            local bag, slot = EmptySlot(toBags)
            if not bag then return nil, left, "full" end
            local n = math.min(s.count, want)
            move = { itemID = id, from = { s.bag, s.slot }, to = { bag, slot }, count = n, split = n < s.count }
            break
          end
        end
      end
    end
  end
  return move, left
end

local function Step(direction, which, steps, moved)
  if not running then return end
  if not B.atBank or steps > MAX_STEPS then
    running = nil
    CM.Print(("Bank moves stopped after %d moves."):format(moved))
    return
  end
  local move, left, why = B.NextMove(direction, which)
  if not move then
    running = nil
    if why == "full" then
      CM.Print(("No room left in your %s; %d moves made."):format(direction == "bank" and "bank" or "bags", moved))
    else
      CM.Print(("Bank moves done: %d moves."):format(moved))
    end
    if CM.Debug then CM.Debug("Bank moves: " .. direction .. " " .. tostring(which) .. " " .. moved .. " moves") end
    return
  end
  ClearCursor()
  if move.split then
    C_Container.SplitContainerItem(move.from[1], move.from[2], move.count)
  else
    C_Container.PickupContainerItem(move.from[1], move.from[2])
  end
  C_Container.PickupContainerItem(move.to[1], move.to[2])
  ClearCursor()
  C_Timer.After(STEP, function() Step(direction, which, steps + 1, moved + 1) end)
end

-- direction "bank" or "bags"; which "ops" or a group id.
function B.Start(direction, which)
  if not B.atBank then CM.Print("Open your bank first.") return end
  if running then running = nil; CM.Print("Bank moves stopped.") return end
  running = true
  Step(direction, which, 1, 0)
end

function B.IsRunning() return running and true or false end

local function ShowMenu(owner)
  if not (MenuUtil and MenuUtil.CreateContextMenu) then
    B.Start("bank", "ops")
    return
  end
  MenuUtil.CreateContextMenu(owner, function(_, root)
    root:CreateTitle("Warehousing operations")
    root:CreateButton("To Bank", function() B.Start("bank", "ops") end)
    root:CreateButton("To Bags", function() B.Start("bags", "ops") end)
    root:CreateDivider()
    local toBank = root:CreateButton("A whole group to the bank")
    local toBags = root:CreateButton("A whole group to your bags")
    for _, g in ipairs(API.GetGroups()) do
      if not g.base then
        local label = string.rep("  ", (g.depth or 1) - 1) .. g.name
        toBank:CreateButton(label, function() B.Start("bank", g.id) end)
        toBags:CreateButton(label, function() B.Start("bags", g.id) end)
      end
    end
    if running then
      root:CreateDivider()
      root:CreateButton(STOP or "Stop", function() running = nil end)
    end
  end)
end

local function MakeButton()
  if B.button or not BankFrame then return B.button end
  local b = CreateFrame("Button", "CueTheCashierBankButton", BankFrame, CM.Skins:Get().buttonTemplate)
  b:SetSize(110, 22)
  -- Bottom right of the bank window, right of Purchase and above the gold
  -- (Kim's spot, 0.42.0; the top right covered the search box). GUESS:
  -- offsets read from Kim's screenshot. Else just under or above the window.
  CM.Place.Attach(b, BankFrame, {
    { "BOTTOMRIGHT", BankFrame, "BOTTOMRIGHT", -30, 36 },
    { "TOPRIGHT", BankFrame, "BOTTOMRIGHT", -30, -2 },
    { "BOTTOMRIGHT", BankFrame, "TOPRIGHT", -30, 2 },
  }, { name = "Bank Moves button" })
  b:SetFrameStrata("HIGH")
  b:SetText("Bank Moves")
  b:SetScript("OnClick", function(self) ShowMenu(self) end)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:SetText("CueTheCashier Bank Moves")
    GameTooltip:AddLine("Move group items between your bags and the bank, by their Warehousing operation or a whole group.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", GameTooltip_Hide)
  B.button = b
  return b
end

CM.RegisterEvent(B, "BANKFRAME_OPENED", function()
  B.atBank = true
  local b = MakeButton()
  if b then b:Show() end
end)
CM.RegisterEvent(B, "BANKFRAME_CLOSED", function()
  B.atBank, running = false, nil
end)

API.MoveToBank = function(which) B.Start("bank", which or "ops") end   -- ([groupID]) (minor 9)
API.MoveToBags = function(which) B.Start("bags", which or "ops") end   -- ([groupID]) (minor 9)
