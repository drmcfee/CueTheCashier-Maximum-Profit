-- CueTheCashier: adds saved auction prices to item tooltips.
-- Copyright (C) 2026 Kim. Licensed under the GNU GPL v3 or later; see LICENSE.
local _, CM = ...

local LABEL = { 1, 1, 1 }       -- white, like Blizzard's own tooltip lines
local VALUE = { 1, 1, 1 }

local function Money(c) return CM.FormatMoney(c) end

local AddScanLines, AddSaleLines

local function MaterialName(itemID)
  local name, _, quality = C_Item.GetItemInfo(itemID)
  if not name then
    if C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(itemID) end
    return "Item " .. itemID
  end
  local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality or 1]
  return c and c.hex and (c.hex .. name .. "|r") or name
end

local function AddDisenchantLines(tooltip, itemID)
  local DE = CM.Disenchant
  local showValue, showMats = CM.TooltipLineShown("disenchant"), CM.TooltipLineShown("deMats")
  if not (showValue or showMats) then return end
  local quality, level, classID = DE.ItemFacts(itemID)
  if not quality or quality == "wait" then return end
  local outcomes = DE.Outcomes(quality, level, classID)
  if not outcomes then return end
  if showValue and (DE.IsBoE(itemID) or DE.IsEnchanter()) then
    local de, complete = DE.Value(itemID)
    if type(de) == "number" and de > 0 then
      tooltip:AddDoubleLine("Disenchant value" .. (complete and "" or " (some prices missing)"), Money(de),
        LABEL[1], LABEL[2], LABEL[3], VALUE[1], VALUE[2], VALUE[3])
    end
  end
  if showMats then
    if not showValue or not (DE.IsBoE(itemID) or DE.IsEnchanter()) then
      tooltip:AddLine("Disenchants into:", LABEL[1], LABEL[2], LABEL[3])
    end
    for _, o in ipairs(outcomes) do
      local count = o[3] == o[4] and tostring(o[3]) or (o[3] .. "-" .. o[4])
      local pct = o[2] * 100
      local pctText = (pct < 1 and ("%.1f%%"):format(pct)) or ("%d%%"):format(math.floor(pct + 0.5))
      tooltip:AddDoubleLine("   " .. count .. " x " .. MaterialName(o[1]), pctText,
        LABEL[1], LABEL[2], LABEL[3], VALUE[1], VALUE[2], VALUE[3])
    end
  end
end

local function AddPrice(tooltip, data)
  if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
  local itemID = data and data.id
  if not itemID then return end
  local entry = CM:GetItemEntry(itemID)
  if entry then AddScanLines(tooltip, itemID, entry) end
  AddSaleLines(tooltip, itemID)
  -- Disenchant (estimate from the classic table; needs testing on Forever):
  -- the materials with their chance, and the value only when it matters
  -- to you: BoE items (anyone can sell them on) or when you can disenchant.
  AddDisenchantLines(tooltip, itemID)
  -- Groups the item is in (GroupsTab.lua).
  if CM.AddGroupLines then CM.AddGroupLines(tooltip, itemID) end
end

AddScanLines = function(tooltip, itemID, entry)
  -- Each line can be turned off on the Settings tab (CM.TooltipLineShown).
  local Shown = CM.TooltipLineShown
  local old = entry.seenInLastScan and "" or " (old)"
  if entry.minBuyout and Shown("min") then
    tooltip:AddDoubleLine("|cff33ff99CueTheCashier|r min buyout" .. old, Money(entry.minBuyout),
      LABEL[1], LABEL[2], LABEL[3], VALUE[1], VALUE[2], VALUE[3])
  end
  if entry.marketValue and Shown("market") then
    tooltip:AddDoubleLine("Market value", Money(entry.marketValue),
      LABEL[1], LABEL[2], LABEL[3], VALUE[1], VALUE[2], VALUE[3])
  end
  local week, wn = CM.Data:GetAverage(itemID, "market", 7)
  if week and wn >= 2 and Shown("avg7") then
    tooltip:AddDoubleLine("7-day average", Money(week),
      LABEL[1], LABEL[2], LABEL[3], VALUE[1], VALUE[2], VALUE[3])
  end
  -- 30 days only once it covers more than the week does.
  local month, mn = CM.Data:GetAverage(itemID, "market", 30)
  if month and mn > (wn or 0) and Shown("avg30") then
    tooltip:AddDoubleLine("30-day average", Money(month),
      LABEL[1], LABEL[2], LABEL[3], VALUE[1], VALUE[2], VALUE[3])
  end
end

local function Pct(v) return ("%d%%"):format(math.floor(v * 100 + 0.5)) end
local function PerDay(v) return v >= 10 and tostring(math.floor(v + 0.5)) or ("%.1f"):format(v) end
local function Line(tooltip, left, right)
  tooltip:AddDoubleLine(left, right, LABEL[1], LABEL[2], LABEL[3], VALUE[1], VALUE[2], VALUE[3])
end

-- Your own sales, and the region (all server types) numbers (0.43.0).
-- Shown even for items without a scan on this server.
-- "(low data)" (0.45.0): the numbers rest on fewer sold + expired auctions
-- than Settings > Item tooltips > "Low data below" (Data.LowDataAt).
local LOW = " |cffff9933(low data)|r"
local function Low(flag)
  return (flag and CM.TooltipLineShown("lowData")) and LOW or ""
end

AddSaleLines = function(tooltip, itemID)
  local Shown = CM.TooltipLineShown
  local rate, from, low = CM.Data:GetSaleRate(itemID)
  if rate and Shown("saleRate") then
    Line(tooltip, "Sale rate" .. (from and (" |cff808080(" .. from .. ")|r") or "") .. Low(low), Pct(rate))
  end
  local st = CM.Data:GetSaleStats(itemID)
  if st and st.perDay > 0 and Shown("soldPerDay") then
    Line(tooltip, "Sold per day |cff808080(you, 30 days)|r" .. Low(st.lowData), PerDay(st.perDay))
  end
  local r = CM.Data:GetRegion(itemID)
  -- Only when another server adds something (else it is this server again).
  if not (r and (r.otherServers or r.fromApp) and Shown("region")) then return end
  local note = r.fromApp and " |cff808080(app)|r" or (r.servers > 1 and (" |cff808080(" .. r.servers .. " servers)|r") or "")
  if r.market then Line(tooltip, "Region market value" .. note, Money(r.market)) end
  if r.rate then Line(tooltip, "Region sale rate" .. Low(r.lowData), Pct(r.rate)) end
  if r.perDay and r.perDay > 0 then Line(tooltip, "Region sold per day" .. Low(r.lowData), PerDay(r.perDay)) end
end

if TooltipDataProcessor and Enum.TooltipDataType then
  TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, AddPrice)
end
