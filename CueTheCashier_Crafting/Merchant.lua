-- CueTheCashier Crafting: buying the craft list's vendor reagents.
--
-- When a merchant sells reagents the craft list still needs (its "vendor"
-- items), a **Buy Reagents** button shows on the merchant window. It asks
-- first (the box lists what and the total cost), then buys exactly the
-- missing amounts. /cmp prof buy does the same.
-- Copyright (C) 2026 Kim. Licensed under the GNU GPL v3 or later; see LICENSE.
local _, ns = ...
local CM = CueTheCashier
local API = CM.API

local M = {}
ns.Merchant = M

local button

local function Info(i)
  if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
    local info = C_MerchantFrame.GetItemInfo(i)
    if not info then return nil end
    return info.price, info.stackCount, info.numAvailable, info.hasExtendedCost
  elseif GetMerchantItemInfo then
    local _, _, price, stack, available, _, _, extended = GetMerchantItemInfo(i)
    return price, stack, available, extended
  end
end

-- What this merchant can sell from the list:
-- { { index, itemID, want, bundle, price (per bundle), buys, cost }, ... }, total cost
function M.Plan(onlyItem)
  local list = API.GetShoppingList("vendor")
  if onlyItem then list = { [onlyItem] = list[onlyItem] } end
  local plan, total = {}, 0
  if not (GetMerchantNumItems and GetMerchantItemID and next(list)) then return plan, 0 end
  for i = 1, GetMerchantNumItems() do
    local id = GetMerchantItemID(i)
    local want = id and list[id] and list[id].quantity
    if want and want > 0 then
      local price, bundle, available, extended = Info(i)
      if price and price > 0 and not extended then
        bundle = math.max(bundle or 1, 1)
        local buys = math.ceil(want / bundle) -- whole bundles
        if available and available >= 0 then buys = math.min(buys, available) end
        if buys > 0 then
          plan[#plan + 1] = { index = i, itemID = id, want = want, bundle = bundle, price = price,
            buys = buys, cost = buys * price }
          total = total + buys * price
          list[id] = nil -- a merchant may list an item twice
        end
      end
    end
  end
  return plan, total
end

function M.BuyItem(itemID) M.BuyAll(itemID) end

-- ------------------------------------------------------------------
-- Vendor flip (0.46.0, Kim): with a reputation discount at this merchant
-- (Honored 10%, Revered 15%, Exalted 20%), buy cheap and post on the
-- auction house a little higher. Only shown when it really pays after the
-- AH cut and the deposit, and the post price stays under the full vendor
-- price (above that, everyone would buy from a vendor instead) and at or
-- under the cheapest auction now. The profit is small on purpose; the list
-- says so in gold per item and per stack.
-- Defaults for the open questions: markup 8% over what you pay (Settings >
-- Crafting, 0 turns it off); items with your sale rate under 25% are skipped.
-- ------------------------------------------------------------------
local DISCOUNT = { [6] = 0.10, [7] = 0.15, [8] = 0.20 }
M.FLIP_MIN_SALE_RATE = 0.25

function M.FlipMarkup()
  local v = tonumber(ns.db.settings.flipMarkup)
  if v == nil then return 8 end
  return v
end

-- { { index, itemID, paid, base, post, profit, stack, discount }, ... } at the open merchant.
function M.Flips()
  local out = {}
  local markup = M.FlipMarkup() / 100
  if markup <= 0 or not (MerchantFrame and MerchantFrame:IsShown() and GetMerchantNumItems and GetMerchantItemID) then
    return out
  end
  local reaction = UnitReaction and UnitReaction("npc", "player") or 4
  local discount = DISCOUNT[reaction]
  if not discount then return out end
  local cut = API.GetAuctionCutRate and API.GetAuctionCutRate() or 0.05
  for i = 1, GetMerchantNumItems() do
    local id = GetMerchantItemID(i)
    local price, bundle, available, extended = Info(i)
    if id and price and price > 0 and not extended and available ~= 0 then
      bundle = math.max(bundle or 1, 1)
      local paid = price / bundle
      local base = (API.GetVendorBuyPrice and API.GetVendorBuyPrice(id)) or paid / (1 - discount)
      local lowest = API.GetPrice(id, "auction.min")
      local deposit = (API.GetAuctionDeposit and API.GetAuctionDeposit(id, 1)) or 0
      local rate = CM.Data and CM.Data.GetSaleRate and CM.Data:GetSaleRate(id)
      if lowest and lowest > 0 and not (rate and rate < M.FLIP_MIN_SALE_RATE) then
        local need = (paid * (1 + markup) + deposit) / (1 - cut)
        local post = math.min(lowest, math.floor(base) - 1)
        if post >= need then
          local profit = post * (1 - cut) - deposit - paid
          local stack = select(8, C_Item.GetItemInfo(id)) or bundle
          out[#out + 1] = { index = i, itemID = id, paid = paid, base = base, post = post, profit = profit,
            stack = math.max(stack or 1, 1), bundle = bundle, discount = discount }
        end
      end
    end
  end
  table.sort(out, function(a, b) return a.profit * a.stack > b.profit * b.stack end)
  return out
end

-- Buys one stack of a flip (whole bundles).
function M.BuyFlip(f)
  if not (f and MerchantFrame and MerchantFrame:IsShown()) then return end
  if GetMerchantItemID(f.index) ~= f.itemID then return end
  local buys = math.max(1, math.floor(f.stack / f.bundle))
  CM.Try("BuyMerchantItem", BuyMerchantItem, f.index, buys * f.bundle)
  CM.Print(("Bought %d %s to flip: post at %s each."):format(buys * f.bundle, ns.Costs.ItemName(f.itemID),
    API.FormatMoney(f.post)))
end

local function Describe(plan)
  local parts = {}
  for _, p in ipairs(plan) do parts[#parts + 1] = ("%d %s"):format(p.buys * p.bundle, ns.Costs.ItemName(p.itemID)) end
  return table.concat(parts, ", ")
end

-- Buys the plan. Must run from a click or a confirm box.
function M.Buy(plan)
  for _, p in ipairs(plan) do
    -- The item list may have changed since the plan was made.
    if GetMerchantItemID(p.index) == p.itemID then
      if p.bundle > 1 then
        -- Bundles (e.g. 5 vials): one purchase per bundle.
        for _ = 1, p.buys do BuyMerchantItem(p.index) end
      else
        local max = (GetMerchantItemMaxStack and GetMerchantItemMaxStack(p.index)) or 20
        local left = p.buys
        while left > 0 do
          local n = math.min(left, math.max(max, 1))
          BuyMerchantItem(p.index, n)
          left = left - n
        end
      end
      CM.Debug(("Merchant: bought %d x %s (%d each purchase of %d)."):format(p.buys * p.bundle,
        ns.Costs.ItemName(p.itemID), p.price, p.bundle))
    end
  end
end

-- itemID: only that item (a click on a reagent in the craft list).
function M.BuyAll(itemID)
  if not (MerchantFrame and MerchantFrame:IsShown()) then
    CM.Print("Open a merchant first.")
    return
  end
  local plan, total = M.Plan(itemID)
  if #plan == 0 then
    CM.Print(itemID and ("This merchant doesn't sell " .. ns.Costs.ItemName(itemID) .. ".")
      or "This merchant sells nothing the craft list still needs.")
    return
  end
  if total > GetMoney() then
    CM.Print(("Not enough gold: the reagents cost %s."):format(API.FormatMoney(total)))
    return
  end
  CM.Confirm(("Buy for the craft list: %s?\nTotal %s."):format(Describe(plan), API.FormatMoney(total)),
    function() ns.Safe("Merchant buy", M.Buy, plan) end)
end

local function Update()
  if not (MerchantFrame and MerchantFrame:IsShown()) then
    if button then button:Hide() end
    return
  end
  local plan, total = M.Plan()
  if not button then
    local skin = CM.Skins:Get()
    button = CreateFrame("Button", nil, MerchantFrame, skin.buttonTemplate)
    button:SetSize(130, 22)
    -- GUESS: free space at the top right of the merchant window.
    CM.Place.Attach(button, MerchantFrame, {
      { "TOPRIGHT", MerchantFrame, "TOPRIGHT", -12, -30 },
      { "TOPRIGHT", MerchantFrame, "BOTTOMRIGHT", -12, -2 },
      { "BOTTOMRIGHT", MerchantFrame, "TOPRIGHT", -12, 2 },
    }, { name = "Buy Reagents button" })
    button:SetFrameLevel((MerchantFrame:GetFrameLevel() or 1) + 20)
    button:SetScript("OnClick", function() M.BuyAll() end)
    button:SetScript("OnEnter", function(self)
      local p, t = M.Plan()
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:AddLine("Craft list reagents", 1, 1, 1)
      for _, x in ipairs(p) do
        GameTooltip:AddDoubleLine(("%d x %s"):format(x.buys * x.bundle, ns.Costs.ItemName(x.itemID)),
          API.FormatMoney(x.cost), 1, 1, 1, 1, 1, 1)
      end
      GameTooltip:AddDoubleLine("Total", API.FormatMoney(t), 1, 0.82, 0, 1, 1, 1)
      GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end
  button:SetText(("Buy Reagents (%d)"):format(#plan))
  button:SetShown(#plan > 0)
end

function M.Register(module)
  module:RegisterEvent("MERCHANT_SHOW", function()
    ns.Debounce("Merchant button", 0.3, Update)
    ns.Debounce("Record vendor", 0.5, ns.Vendors.Record)
    ns.Debounce("Task list flips", 0.5, function() if ns.TaskList then ns.TaskList.Refresh() end end)
  end)
  module:RegisterEvent("MERCHANT_UPDATE", function()
    ns.Debounce("Merchant button", 0.3, Update)
    ns.Debounce("Task list flips", 0.5, function() if ns.TaskList then ns.TaskList.Refresh() end end)
  end)
  module:RegisterEvent("MERCHANT_CLOSED", function()
    if button then button:Hide() end
    ns.Costs.Changed() -- vendor prices may have been learned there
  end)
  module:RegisterMessage("CM_SHOPPING_LIST_CHANGED", function()
    if MerchantFrame and MerchantFrame:IsShown() then ns.Debounce("Merchant button", 0.3, Update) end
  end)
end
