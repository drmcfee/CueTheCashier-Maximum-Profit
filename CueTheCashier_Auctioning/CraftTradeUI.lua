-- CueTheCashier: the "Craft Trade" window and the button that switches to it.
--
-- While the auction house is open, a button next to the AH close button
-- swaps Blizzard's auction house window for our own Craft Trade window.
-- Our window has the same button (reading "Auction House") to swap back.
--
-- Blizzard's window is never really closed while Craft Trade is shown,
-- because closing it ends the auction house session. Instead it is made
-- invisible and moved off screen, the same trick TSM uses.
-- Copyright (C) 2026 Kim. Licensed under the GNU GPL v3 or later; see LICENSE.
local _, ns = ...
local CM = CueTheCashier
local API = CM.API

local CraftTrade = {}
ns.CraftTrade = CraftTrade

-- ===================================================================
-- CRAFT TRADE BUTTON: names and size.
-- The window/button name may change later. Change the texts here and
-- every place that shows them follows.
-- ===================================================================
CraftTrade.WINDOW_TITLE = "Craft Trade"   -- title of our window
CraftTrade.BUTTON_TO_OURS = "Craft Trade"   -- button text on Blizzard's AH window
CraftTrade.BUTTON_TO_BLIZZARD = "Auction House" -- button text on our window
local BUTTON_WIDTH, BUTTON_HEIGHT = 135, 22
-- ===================================================================
-- END CRAFT TRADE BUTTON names and size
-- ===================================================================

local window          -- our Craft Trade window
local blizzButton     -- the switch button on Blizzard's window
local savedPoints     -- where Blizzard's window was before we hid it
local switching = false

-- ===================================================================
-- CRAFT TRADE BUTTON: creates the switch button and puts it just left
-- of a window's close (X) button.
-- ===================================================================
local switchButtons = {}

-- Width, extra height and raise: from /cmp button if set, else Skins.lua.
local function ButtonLayout()
  local st = CM.Skins:Get().titleButton
  local o = CM.Settings().titleButton or {}
  return o.width or BUTTON_WIDTH, o.extraHeight or st.extraHeight, o.raise or st.raise, st.gap
end

local function PlaceSwitchButton(button)
  local width, extraHeight, raise, gap = ButtonLayout()
  local parent = button:GetParent()
  local close = parent.CloseButton
  button:ClearAllPoints()
  button:SetWidth(width)
  if close then
    -- Lined up with the X: same top and bottom, then grown/raised by the
    -- numbers above.
    button:SetPoint("TOPRIGHT", close, "TOPLEFT", -gap, raise + extraHeight / 2)
    button:SetPoint("BOTTOMRIGHT", close, "BOTTOMLEFT", -gap, raise - extraHeight / 2)
  else
    -- GUESS: fallback spot if the window has no CloseButton field.
    button:SetHeight(BUTTON_HEIGHT)
    button:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -26, -1)
  end
end

-- Re-places both switch buttons (used by /cmp button).
function CraftTrade:ApplyButtonLayout()
  for _, b in ipairs(switchButtons) do PlaceSwitchButton(b) end
  local w, h, r = ButtonLayout()
  CM.Print(("Button: width %d, extra height %d, raise %d."):format(w, h, r))
end

local function CreateSwitchButton(parent, name, text, onClick)
  local button = CM.Skins:CreateTitleButton(parent, name)
  local close = parent.CloseButton
  switchButtons[#switchButtons + 1] = button
  PlaceSwitchButton(button)
  button:SetFrameLevel((close or parent):GetFrameLevel() + 1)
  button:SetText(text)
  button:SetScript("OnClick", onClick)
  return button
end
-- ===================================================================
-- END CRAFT TRADE BUTTON
-- ===================================================================

-- Hides Blizzard's AH window without ending the auction house session.
local function HideBlizzard()
  local f = AuctionHouseFrame
  if savedPoints then return end
  savedPoints = {}
  for i = 1, f:GetNumPoints() do savedPoints[i] = { f:GetPoint(i) } end
  f:SetAlpha(0)
  f:ClearAllPoints()
  -- GUESS: far off screen, like TSM. If Blizzard's window pops back into
  -- view (for example when another panel opens), tell Claude.
  f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10000, 10000)
  CM.Debug("Craft Trade: Blizzard AH window hidden off screen.")
end

local function RestoreBlizzard()
  local f = AuctionHouseFrame
  if not (f and savedPoints) then return end
  f:ClearAllPoints()
  for _, p in ipairs(savedPoints) do f:SetPoint(unpack(p)) end
  f:SetAlpha(1)
  savedPoints = nil
  CM.Debug("Craft Trade: Blizzard AH window restored.")
end

local function BuildWindow()
  local skin = CM.Skins:Get()
  -- Same frame style and size as Blizzard's auction house window.
  local f = CreateFrame("Frame", "CueTheCashierCraftTradeFrame", UIParent, skin.craftTradeTemplate)
  CM.Skins:ApplyWindow(f)
  f:SetSize(AuctionHouseFrame:GetWidth(), AuctionHouseFrame:GetHeight())
  f:SetFrameStrata(AuctionHouseFrame:GetFrameStrata())
  f:SetToplevel(true)
  f:EnableMouse(true)
  f:SetMovable(true)
  f:SetClampedToScreen(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)

  if f.SetTitle then
    f:SetTitle(CraftTrade.WINDOW_TITLE)
  else
    local title = f:CreateFontString(nil, "OVERLAY", skin.fontNormal)
    title:SetPoint("TOP", 0, -5)
    title:SetText(CraftTrade.WINDOW_TITLE)
  end
  -- Portrait in the corner, like Blizzard's own windows.
  if f.SetPortraitToAsset then
    f:SetPortraitToAsset("Interface\\Icons\\INV_Misc_Coin_01")
  elseif ButtonFrameTemplate_HidePortrait then
    ButtonFrameTemplate_HidePortrait(f)
  end

  -- Pages, one per tab along the bottom (like Buy / Sell / Auctions).
  -- To add a tab later: add a line here with its name and its Build.
  f.pages = {
    { name = "Buy", build = function(parent) return ns.BuyTab:Build(parent) end },
    { name = "Sell", build = function(parent) return ns.SellTab:Build(parent) end },
    { name = "Auctions", build = function(parent) return ns.AuctionsTab:Build(parent) end,
      noScanBar = true },
    { name = "Post", build = function(parent) return ns.PostTab:Build(parent) end,
      noScanBar = true },
    { name = "Vendor", build = function(parent) return ns.VendorTab:Build(parent) end,
      noScanBar = true },
    { name = "Snipe", build = function(parent) return ns.SnipeTab:Build(parent) end,
      noScanBar = true },
    { name = "Disenchant", build = function(parent) return ns.DisenchantTab:Build(parent) end,
      noScanBar = true },
    { name = "Shopping", build = function(parent) return ns.ShoppingTab:Build(parent) end,
      noScanBar = true },
  }
  f.Tabs = {}
  for i, page in ipairs(f.pages) do
    -- A broken page must not break the whole window: log it and show an
    -- empty page instead.
    local ok, frame = pcall(page.build, f)
    if not ok then
      CM.Print(page.name .. " tab failed to build: " .. tostring(frame))
      frame = CreateFrame("Frame", nil, f)
    end
    page.frame = frame
    local tab = CreateFrame("Button", "CueTheCashierCraftTradeFrameTab" .. i, f, "PanelTabButtonTemplate")
    tab:SetText(page.name)
    tab:SetID(i)
    if i == 1 then
      tab:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 19, 2)
    else
      tab:SetPoint("LEFT", f.Tabs[i - 1], "RIGHT", 3, 0)
    end
    tab:SetScript("OnClick", function() CraftTrade:SelectTab(i) end)
    f.Tabs[i] = tab
  end
  if PanelTemplates_SetNumTabs then PanelTemplates_SetNumTabs(f, #f.Tabs) end

  -- Full Scan and the scan status, bottom right.
  local bar = ns.BuildScanBar(f)
  bar:ClearAllPoints()
  bar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 4)

  -- The X button closes the auction house, like Blizzard's X does.
  if f.CloseButton then
    f.CloseButton:SetScript("OnClick", function() CraftTrade:CloseAll() end)
  end

  -- ===================================================================
  -- CRAFT TRADE BUTTON on our window ("Auction House"): switches back.
  -- ===================================================================
  f.switchButton = CreateSwitchButton(f, "CueTheCashierShowAuctionHouseButton",
    CraftTrade.BUTTON_TO_BLIZZARD, function()
      CM.ProfileSettings().openCraftTrade = false -- remembered for next visit
      CraftTrade:ShowBlizzard()
    end)
  -- ===================================================================
  -- END CRAFT TRADE BUTTON on our window
  -- ===================================================================

  -- Escape: not in UISpecialFrames (0.19.3). Blizzard's auction window
  -- stays open (hidden) under ours, so Escape closes it in one press;
  -- AUCTION_HOUSE_CLOSED then hides ours. Our own entry in the Escape
  -- list took a second press and gave "blocked" warnings in game.
  -- New frames start shown; hide it BEFORE adding OnHide, or this first
  -- Hide() would close the auction house.
  f:Hide()
  f:SetScript("OnHide", function()
    if not switching then CraftTrade:CloseAll() end
  end)
  return f
end

function CraftTrade:SelectTab(index)
  if not window then return end
  for i, page in ipairs(window.pages) do page.frame:SetShown(i == index) end
  -- The scan row shows on pages that leave the bottom right free, and not
  -- while the Buy tab's item page is open.
  if CueTheCashierAuctionBar then
    local page = window.pages[index]
    CueTheCashierAuctionBar:SetShown(not page.noScanBar
      and not (index == 1 and CueTheCashierItemPage and CueTheCashierItemPage:IsShown()))
  end
  if PanelTemplates_SetTab then PanelTemplates_SetTab(window, index) end
end

function CraftTrade:ShowOurs()
  if not (AuctionHouseFrame and AuctionHouseFrame:IsShown()) then return end
  window = window or BuildWindow()
  -- Open in the same place Blizzard's window was.
  window:ClearAllPoints()
  window:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPLEFT")
  local left, top = AuctionHouseFrame:GetLeft(), AuctionHouseFrame:GetTop()
  if left and top then
    window:ClearAllPoints()
    window:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
  end
  HideBlizzard()
  window:Show()
  self:SelectTab(window.selectedTab or 1)
  self.showingOurs = true
end

function CraftTrade:ShowBlizzard()
  RestoreBlizzard()
  if window and window:IsShown() then
    switching = true
    window:Hide()
    switching = false
  end
  self.showingOurs = false
end

-- ------------------------------------------------------------------
-- Purchase calls (PlaceBid, StartCommoditiesPurchase,
-- ConfirmCommoditiesPurchase) go through ns.ProtectedCall.
-- Confirmed in game (0.10.8): Forever blocks these when made straight from
-- our buttons (ADDON_ACTION_BLOCKED), but allows them from a confirm
-- popup's Accept. So every buy asks in a popup and makes the call from its
-- Accept. If even that is blocked, o.onBlocked runs (hand-off to
-- Blizzard's window).
-- o = { label, fn, args = {...}, ask = popup text (nil = we are already in
--       a popup's Accept), onDone, onCancel, onBlocked }
-- ------------------------------------------------------------------
function ns.ProtectedCall(o)
  local function Attempt()
    local before = CM.blockedCount or 0
    CM.Try(o.label, o.fn, unpack(o.args or {}))
    if (CM.blockedCount or 0) == before then
      if o.onDone then o.onDone() end
    else
      CM.Debug(o.label .. " blocked even from the popup.")
      if o.onBlocked then o.onBlocked() end
    end
  end
  if o.ask then
    CM.Confirm(o.ask, Attempt, o.onCancel)
  else
    Attempt()
  end
end

-- Starts a stack purchase (after a popup). If Blizzard blocks it,
-- hands the purchase to Blizzard's window and calls onBlocked so the
-- caller can reset its buttons. onCancel: the popup was cancelled.
-- ask: the popup text (what you'll pay); the server price that follows is
-- bought without a second popup when it isn't higher (ns.AutoConfirmStack).
function ns.StartStackPurchase(itemID, qty, name, maxUnit, onBlocked, onCancel, ask)
  ns.ProtectedCall({
    label = "StartCommoditiesPurchase",
    fn = C_AuctionHouse.StartCommoditiesPurchase,
    args = { itemID, qty },
    ask = ask or ("Check the price for %d %s?"):format(qty or 0, name or "items"),
    onCancel = onCancel or onBlocked,
    onBlocked = function()
      if onBlocked then onBlocked() end
      CraftTrade:BuyInBlizzard(name, qty, maxUnit)
    end,
  })
end

-- After the server's price for a stack: if it isn't above what you
-- accepted in the first popup, buy straight away (one popup in all).
-- Returns true when bought. Returns false when a second popup is needed:
-- no approved price, the price went up, or Blizzard blocks a confirm made
-- outside a popup (then the rest of the session always asks).
function ns.AutoConfirmStack(itemID, qty, name, total, approved)
  if not (approved and total and total <= approved) or ns.stackConfirmNeedsPopup then return false end
  -- The ledger (Accounting module) listens for this.
  CM.SendMessage("CM_STACK_PURCHASE_CONFIRMING", itemID, name, qty, total)
  local before = CM.blockedCount or 0
  CM.Try("ConfirmCommoditiesPurchase (after accepted price)", C_AuctionHouse.ConfirmCommoditiesPurchase, itemID, qty)
  if (CM.blockedCount or 0) ~= before then
    ns.stackConfirmNeedsPopup = true
    CM.Debug("Confirm outside a popup is blocked; stacks ask a second time this session.")
    return false
  end
  return true
end

-- Buys at the quoted stack price; called from the price popup's Accept.
-- total: the quoted price, for the ledger.
function ns.ConfirmStackPurchase(itemID, qty, name, maxUnit, onBlocked, total)
  if total then CM.SendMessage("CM_STACK_PURCHASE_CONFIRMING", itemID, name, qty, total) end
  ns.ProtectedCall({
    label = "ConfirmCommoditiesPurchase",
    fn = C_AuctionHouse.ConfirmCommoditiesPurchase,
    args = { itemID, qty },
    onBlocked = function()
      if C_AuctionHouse.CancelCommoditiesPurchase then pcall(C_AuctionHouse.CancelCommoditiesPurchase) end
      if onBlocked then onBlocked() end
      CraftTrade:BuyInBlizzard(name, qty, maxUnit)
    end,
  })
end

-- Buys (or bids on) one auction.
-- o = { auctionID, amount, itemID, name, ask = popup text (nil when
--       already in a popup), buyout = true for a buyout (goes in the
--       ledger when it completes; bids come from the mail), onDone,
--       onBlocked, onCancel }
function ns.BuyAuction(o)
  ns.ProtectedCall({
    label = "PlaceBid",
    fn = C_AuctionHouse.PlaceBid,
    args = { o.auctionID, o.amount },
    ask = o.ask,
    onDone = function()
      if o.buyout then CM.SendMessage("CM_BUYOUT_PLACED", o.auctionID, o.itemID, o.name, o.amount) end
      if o.onDone then o.onDone() end
    end,
    onCancel = o.onCancel,
    onBlocked = function()
      if o.onBlocked then o.onBlocked() end
      CraftTrade:BuyInBlizzard(o.name)
    end,
  })
end

-- Fallback when Blizzard blocks a purchase even from the popup
-- (C_AuctionHouse.StartCommoditiesPurchase gave ADDON_ACTION_BLOCKED in
-- game with 0.10.5). We switch to Blizzard's window with the item's
-- name in its search box, and you finish the purchase there. Nothing else
-- is set on Blizzard's window, so its Buy Now stays untouched by addon code.
-- Only this one visit goes to Blizzard's window; the saved choice of which
-- window opens first doesn't change.
function CraftTrade:BuyInBlizzard(name, qty, maxUnit)
  self:ShowBlizzard()
  local bar = AuctionHouseFrame and AuctionHouseFrame.SearchBar
  local box = bar and bar.SearchBox
  if box and name then pcall(box.SetText, box, name) end
  local what = qty and ("buy %d"):format(qty) or "buy it"
  CM.Print(("Blizzard blocked this purchase from CueTheCashier. Click Search in Blizzard's window, pick %s and %s%s. "
    .. "\"Craft Trade\" (top right) brings you back."):format(name or "the item", what,
    maxUnit and (" (good up to " .. CM.FormatMoney(maxUnit) .. " each)") or ""))
end

-- Ends the auction house session and tidies up both windows.
function CraftTrade:CloseAll()
  self:ShowBlizzard()
  if AuctionHouseFrame and AuctionHouseFrame:IsShown() and C_AuctionHouse.CloseAuctionHouse then
    C_AuctionHouse.CloseAuctionHouse()
  end
end

-- AUCTION_HOUSE_SHOW and AUCTION_HOUSE_CLOSED (registered in Module.lua).
-- The core loads this module when the auction house opens and then hands
-- it that same AUCTION_HOUSE_SHOW, so the first visit works too.
function CraftTrade:OnAuctionHouseEvent(event)
  if event == "AUCTION_HOUSE_SHOW" then
    -- =================================================================
    -- CRAFT TRADE BUTTON on Blizzard's window ("Craft Trade")
    -- =================================================================
    if not blizzButton and AuctionHouseFrame then
      blizzButton = CreateSwitchButton(AuctionHouseFrame, "CueTheCashierShowCraftTradeButton",
        CraftTrade.BUTTON_TO_OURS, function()
          CM.ProfileSettings().openCraftTrade = true -- remembered for next visit
          CraftTrade:ShowOurs()
        end)
    end
    -- Open whichever window was used last (Craft Trade the first time).
    -- Waits one frame so Blizzard's window is open and placed first.
    if CM.ProfileSettings().openCraftTrade ~= false then
      C_Timer.After(0, function() CraftTrade:ShowOurs() end)
    end
    -- =================================================================
    -- END CRAFT TRADE BUTTON on Blizzard's window
    -- =================================================================
  elseif event == "AUCTION_HOUSE_CLOSED" then
    -- Walking away from the auctioneer: put everything back.
    CraftTrade:ShowBlizzard()
  end
end
