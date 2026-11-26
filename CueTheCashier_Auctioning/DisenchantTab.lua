-- CueTheCashier: Disenchant tab.
-- A live search for gear on the auction house that costs less than what
-- disenchanting it is expected to give (see Disenchant.lua; the table is
-- the classic one and still needs testing on Forever). The search, list
-- and buying code is shared with the Vendor and Snipe tabs (DealPage.lua).
-- Copyright (C) 2026 Kim. Licensed under the GNU GPL v3 or later; see LICENSE.
local _, ns = ...
local CM = CueTheCashier
local API = CM.API

local function DisenchantDeal(b)
  local value, complete = API.GetDisenchantValue(b.itemKey.itemID, b.itemKey.itemLevel)
  if value == "wait" then return "wait" end
  if not value or value <= 0 or not complete then return end -- a material without a price
  if b.minPrice and b.minPrice > 0 and value > b.minPrice then
    return { disenchant = value, ref = value, limit = value - 1, why = "Market" }
  end
end
ns.DisenchantDeal = DisenchantDeal

ns.DisenchantTab = ns.DealPage.New({
  name = "Disenchant",
  owner = "disenchant",
  loop = false,
  sortKey = "each",
  modes = { { mode = "disenchant", label = SEARCH or "Search", buttonName = "SearchButton" } },
  columns = {
    { key = "name", title = "Item", width = 206, kind = "text" },
    { key = "minBuyout", title = "Lowest Buyout", width = 100, kind = "money" },
    { key = "disenchant", title = "Disenchant", width = 96, kind = "money" },
    { key = "each", title = "Profit Each", width = 92, kind = "profit" },
    { key = "available", title = "Available", width = 72, kind = "count" },
    { key = "qty", title = "Below Value", width = 82, kind = "count" },
    { key = "total", title = "Total Profit", width = 88, kind = "profit" },
  },
  emptyText = "Nothing is selling below its disenchant value right now.",
  boughtText = "Purchase complete. Disenchant it to get the materials.",
  Evaluate = DisenchantDeal,
  InfoText = function(s)
    if s.searching then
      return ("Searching... %d items checked, %d deals so far."):format(s.seen, #s.rows)
    elseif s.finishedAt then
      return ("%d deals from the search at %s. Disenchant values are estimates.")
        :format(#s.rows, date("%H:%M", s.finishedAt))
    end
    return "Click Search to find gear selling below its disenchant value (materials priced from your scans)."
  end,
})
