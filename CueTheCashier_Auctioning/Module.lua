-- CueTheCashier Auctioning: the module object. Everything on the auction
-- house: full scan, test scan, the Craft Trade window and its Buy, Sell,
-- Auctions, Post, Vendor, Snipe, Disenchant and Shopping tabs, and buying.
-- Loaded by the core when the auction house opens (see the .toc).
-- Copyright (C) 2026 Kim. Licensed under the GNU GPL v3 or later; see LICENSE.
local ADDON_NAME, ns = ...
local CM = CueTheCashier
-- 0.42.5: lists keep their scroll spot through CM.SetRows (core Widgets.lua,
-- 0.42.4). If the core folder is older than this module (not every folder
-- copied), stand in for it so lists still work, and say so once.
if not CM.SetRows then
  CM.SetRows = function(box, rows)
    local retain = ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition
    if retain then box:SetDataProvider(CreateDataProvider(rows), retain)
    else box:SetDataProvider(CreateDataProvider(rows)) end
  end
  if not CM.warnedOldCore then
    CM.warnedOldCore = true
    print("|cffff4444CueTheCashier: the CueTheCashier (core) folder is older than CueTheCashier_Auctioning. Copy all six folders from the zip.|r")
  end
end

local Module = CM:NewModule("Auctioning", { addon = ADDON_NAME, api = 1 })
ns.module = Module
ns.vendorSingles = {} -- auctionID -> itemID, bought to sell to a vendor

function Module:OnEnable()
  -- The other files fill in ns.CraftTrade, ns.Scanner, ... before this runs.
  self:RegisterEvent("AUCTION_HOUSE_SHOW", function(_, event) ns.CraftTrade:OnAuctionHouseEvent(event) end)
  self:RegisterEvent("AUCTION_HOUSE_CLOSED", function(_, event)
    ns.Scanner.OnAuctionHouseClosed()
    ns.CraftTrade:OnAuctionHouseEvent(event)
  end)
  self:RegisterEvent("AUCTION_HOUSE_PURCHASE_COMPLETED", function(_, _, auctionID)
    local id = auctionID and ns.vendorSingles[auctionID]
    if id then
      ns.vendorSingles[auctionID] = nil
      if CM.API.AddVendorBuy then CM.API.AddVendorBuy(id, 1) end
    end
  end)
  self:RegisterMessage("CM_SHOPPING_LIST_CHANGED", function() ns.ShoppingTab:ListChanged() end)
  self:RegisterMessage("CM_SHOP_ITEM", function(_, _, itemID) ns.ShoppingTab:BuyItem(itemID) end)
  self:RegisterMessage("CM_DEBUG_MODE_CHANGED", function()
    if ns.UpdateDebugButton then ns.UpdateDebugButton() end
  end)

  self:RegisterCommand("fullscan", function(_, rest)
    -- "/cmp fullscan force" skips our 15 minute timer (debug mode only).
    ns.Scanner:Start(rest == "force")
  end, "/cmp fullscan [force]")
  self:RegisterCommand("test", function(_, rest)
    -- Works without debug mode too. Optional item link or id, default Light Leather.
    ns.DebugScan:Start(CM.ParseItemID(rest))
  end, "/cmp test [item]")
  self:RegisterCommand("button", function(_, rest)
    -- /cmp button width|height|raise <number>, or /cmp button reset.
    -- Adjusts the Craft Trade / Auction House button live and remembers it.
    local what, num = rest:match("^(%a+)%s*(%-?[%d%.]*)$")
    local key = ({ width = "width", height = "extraHeight", raise = "raise" })[what or ""]
    local s = CM.Settings()
    if what == "reset" then
      s.titleButton = nil
    elseif key and tonumber(num) then
      s.titleButton = s.titleButton or {}
      s.titleButton[key] = tonumber(num)
    else
      CM.Print("/cmp button width 135 | height 1 | raise 3 | reset  (height and raise are compared to the X; 1 unit is about 2 pixels)")
    end
    ns.CraftTrade:ApplyButtonLayout()
  end, "/cmp button")
end
