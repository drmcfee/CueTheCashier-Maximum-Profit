-- CueTheCashier: Vendor tab.
-- A live search for items on the auction house that sell for less than a
-- vendor pays for them. Buy them here, sell them to any vendor, keep the
-- difference. The search, list and buying code is shared with the Snipe
-- tab and lives in DealPage.lua.
-- Copyright (C) 2026 Kim. Licensed under the GNU GPL v3 or later; see LICENSE.
local _, ns = ...
local CM = CueTheCashier
local API = CM.API

local function VendorDeal(b)
  local vendor = API.GetVendorSellPrice(b.itemKey.itemID)
  if not vendor then return "wait" end
  if b.minPrice and b.minPrice > 0 and vendor > b.minPrice then
    return { vendor = vendor, ref = vendor, limit = vendor - 1, why = "Vendor" }
  end
end
ns.VendorDeal = VendorDeal

ns.VendorTab = ns.DealPage.New({
  name = "Vendor",
  owner = "vendor",
  loop = false,
  sortKey = "each",
  modes = { { mode = "vendor", label = SEARCH or "Search", buttonName = "SearchButton" } },
  columns = {
    { key = "name", title = "Item", width = 206, kind = "text" },
    { key = "minBuyout", title = "Lowest Buyout", width = 100, kind = "money" },
    { key = "vendor", title = "Vendor Price", width = 96, kind = "money" },
    { key = "each", title = "Profit Each", width = 92, kind = "profit" },
    { key = "available", title = "Available", width = 72, kind = "count" },
    { key = "qty", title = "Below Vendor", width = 82, kind = "count" },
    { key = "total", title = "Total Profit", width = 88, kind = "profit" },
  },
  emptyText = "Nothing is selling below vendor price right now.",
  boughtText = "Purchase complete. Sell them to any vendor.",
  Evaluate = VendorDeal,
  InfoText = function(s)
    if s.searching then
      return ("Searching... %d items checked, %d deals so far."):format(s.seen, #s.rows)
    elseif s.finishedAt then
      return ("%d deals from the search at %s.")
        :format(#s.rows, date("%H:%M", s.finishedAt))
    end
    return "Click Search to find items selling below vendor price right now."
  end,
})
