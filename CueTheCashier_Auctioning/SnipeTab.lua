-- CueTheCashier: Snipe tab.
-- Watches the auction house for new postings at a good price. It searches
-- every item over and over (like the Vendor tab's search) and only reports
-- items whose lowest price dropped since the round before, which means
-- someone just posted them cheaper.
--   Snipe:        under N% of the item's market value, or below vendor price.
--   Vendor Snipe: only below vendor price.
-- The first round after starting only learns the current prices. Leaving
-- the tab or closing the auction house stops it. Searching only reads the
-- auction house; every purchase is still your click.
-- Copyright (C) 2026 Kim. Licensed under the GNU GPL v3 or later; see LICENSE.
local _, ns = ...
local CM = CueTheCashier
local API = CM.API

local DEFAULT_PERCENT = 60

local function Percent()
  local p = tonumber(CM.ProfileSettings().snipePercent) or DEFAULT_PERCENT
  return math.max(1, math.min(p, 100))
end

-- Market value from the saved scans: 7-day average, else the last scan.
local function MarketValue(itemID)
  local avg = API.GetPrice(itemID, "auction.market.7d")
  if avg then return math.floor(avg) end
  return API.GetPrice(itemID, "auction.market")
end

local function SnipeDeal(b, mode)
  local vendorDeal = ns.VendorDeal(b)
  if vendorDeal == "wait" then return "wait" end
  local market = MarketValue(b.itemKey.itemID)
  if vendorDeal then
    vendorDeal.market = market
    return vendorDeal
  end
  if mode ~= "deal" or not (market and market > 0 and b.minPrice and b.minPrice > 0) then return end
  local limit = math.floor(market * Percent() / 100)
  if b.minPrice <= limit then
    return { vendor = API.GetVendorSellPrice(b.itemKey.itemID), market = market,
      ref = market, limit = limit, why = "Market" }
  end
end

local function BuildControls(tab, anchor)
  local box = CreateFrame("EditBox", "CueTheCashierSnipePercent", tab, "InputBoxTemplate")
  box:SetSize(36, 22)
  box:SetPoint("RIGHT", anchor, "LEFT", -12, 0)
  box:SetNumeric(true)
  box:SetMaxLetters(3)
  box:SetAutoFocus(false)
  CM.Skins:StyleInput(box)
  box:SetText(Percent())
  box:SetScript("OnTextChanged", function(b)
    local v = tonumber(b:GetText())
    if v and v > 0 and v <= 100 then CM.ProfileSettings().snipePercent = v end
  end)
  box:SetScript("OnEnterPressed", box.ClearFocus)
  box:SetScript("OnShow", function(b) b:SetText(Percent()) end)
  local label = tab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  label:SetPoint("RIGHT", box, "LEFT", -8, 0)
  label:SetText("Max % of market")
  return label
end

ns.SnipeTab = ns.DealPage.New({
  name = "Snipe",
  owner = "snipe",
  loop = true,
  roundPause = 2,
  sortKey = "found",
  modes = {
    { mode = "deal", label = "Snipe", buttonName = "Button" },
    { mode = "vendor", label = "Vendor Snipe", buttonName = "VendorButton", width = 130 },
  },
  columns = {
    { key = "found", title = "Found", width = 54, kind = "time" },
    { key = "name", title = "Item", width = 172, kind = "text" },
    { key = "minBuyout", title = "Price", width = 92, kind = "money" },
    { key = "market", title = "Market Value", width = 98, kind = "money" },
    { key = "vendor", title = "Vendor Price", width = 92, kind = "money" },
    { key = "each", title = "Profit Each", width = 88, kind = "profit" },
    { key = "qty", title = "Cheap", width = 54, kind = "count" },
    { key = "total", title = "Total Profit", width = 86, kind = "profit" },
  },
  emptyText = "No new cheap postings yet.",
  BuildControls = BuildControls,
  Evaluate = SnipeDeal,
  InfoText = function(s)
    local what = s.mode == "vendor" and "below vendor price" or "at a good price"
    if s.searching and s.rounds == 0 and s.firstRoundLearns then
      return ("Learning current prices... %d items checked."):format(s.seen)
    elseif s.searching then
      return ("Watching for new postings %s: round %d, %d deals."):format(what, s.rounds + 1, #s.rows)
    elseif #s.rows > 0 then
      return ("%d deals found. Start again to keep watching."):format(#s.rows)
    end
    return ("Watches for new postings under %d%% of market value or below vendor price. "
      .. "Vendor Snipe: only below vendor price."):format(Percent())
  end,
})
