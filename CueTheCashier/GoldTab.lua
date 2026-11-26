-- CueTheCashier: gold over time (the Gold tab of the main window).
--
-- Every character's gold is saved once a day (the last amount of the day
-- counts), per server and faction:
--   CueTheCashierDB.goldHistory["EU Normal - Alliance"]["Malaeiel"] = { [dayStart] = copper }
-- Kept for 400 days. The tab shows one bar per day for all characters
-- together or one character, over 30 days, 90 days or a year.
-- Copyright (C) 2026 Kim. Licensed under the GNU GPL v3 or later; see LICENSE.
local _, CM = ...
local API = CM.API

local H = {}
CM.GoldHistory = H

local DAY = 86400
local KEEP_DAYS = 400

function H.DayStart(t)
  local d = date("*t", t or time())
  return time({ year = d.year, month = d.month, day = d.day, hour = 0 })
end

local function Server(key)
  CueTheCashierDB.goldHistory = CueTheCashierDB.goldHistory or {}
  local s = CueTheCashierDB.goldHistory[key or CM:GetAuctionKey()]
  if not s then
    s = {}
    CueTheCashierDB.goldHistory[key or CM:GetAuctionKey()] = s
  end
  return s
end

function H.Record(key, name, copper)
  local s = Server(key)
  s[name] = s[name] or {}
  local today = H.DayStart()
  s[name][today] = copper
  local cutoff = today - KEEP_DAYS * DAY
  for day in pairs(s[name]) do if day < cutoff then s[name][day] = nil end end
end

function H.Characters()
  local list = {}
  for name in pairs(Server()) do list[#list + 1] = name end
  table.sort(list)
  return list
end

-- { { day, copper }, ... } for the last `days` days, oldest first. who =
-- a character name or nil for all. Days without a record carry the last
-- known amount forward; days before a character's first record count 0.
function H.Series(days, who)
  local s = Server()
  local today = H.DayStart()
  local out = {}
  local names = who and { who } or H.Characters()
  local last = {}
  -- Start from the newest record before the window.
  local first = today - (days - 1) * DAY
  for _, name in ipairs(names) do
    local best
    for day, copper in pairs(s[name] or {}) do
      if day < first and (not best or day > best) then best = day; last[name] = copper end
    end
  end
  for i = days - 1, 0, -1 do
    local day = H.DayStart(today - i * DAY + 3600) -- +1h: daylight saving changes
    local total, any = 0, false
    for _, name in ipairs(names) do
      local v = (s[name] or {})[day]
      if v then last[name] = v end
      if last[name] then total = total + last[name]; any = true end
    end
    out[#out + 1] = { day = day, copper = any and total or nil }
  end
  return out
end

-- ------------------------------------------------------------------
-- The tab
-- ------------------------------------------------------------------
local PERIODS = { { "30 Days", 30 }, { "90 Days", 90 }, { "1 Year", 365 } }
local view = { period = 1, who = nil }
local page

local function GoldText(c) return CM.FormatMoney(math.floor((c or 0) / 10000) * 10000) end

local function Refresh()
  if not (page and page:IsVisible()) then return end
  local days = PERIODS[view.period][2]
  local series = H.Series(days, view.who)
  local max, lastValue, firstValue = 0, nil, nil
  for _, p in ipairs(series) do
    if p.copper then
      max = math.max(max, p.copper)
      firstValue = firstValue or p.copper
      lastValue = p.copper
    end
  end
  local chart = page.chart
  local w, h = chart:GetWidth() - 8, chart:GetHeight() - 8
  local barW = w / days
  for i, p in ipairs(series) do
    local bar = page.bars[i]
    if not bar then
      bar = CreateFrame("Frame", nil, chart)
      bar.tex = bar:CreateTexture(nil, "ARTWORK")
      bar.tex:SetPoint("BOTTOMLEFT")
      bar.tex:SetPoint("BOTTOMRIGHT")
      CM.Skins:Paint(bar.tex, "chartBar")
      bar:EnableMouse(true)
      bar:SetScript("OnEnter", function(b)
        GameTooltip:SetOwner(b, "ANCHOR_TOP")
        GameTooltip:SetText(date("%d %b %Y", b.point.day))
        GameTooltip:AddLine(b.point.copper and CM.FormatMoney(b.point.copper) or "No data", 1, 1, 1)
        GameTooltip:Show()
      end)
      bar:SetScript("OnLeave", GameTooltip_Hide)
      page.bars[i] = bar
    end
    bar.point = p
    bar:ClearAllPoints()
    bar:SetPoint("BOTTOMLEFT", chart, "BOTTOMLEFT", 4 + (i - 1) * barW, 4)
    bar:SetSize(math.max(1, barW - (days <= 90 and 1 or 0)), h)
    local frac = (max > 0 and p.copper) and (p.copper / max) or 0
    bar.tex:SetHeight(math.max(frac > 0 and 1 or 0.01, frac * h))
    bar.tex:SetShown(frac > 0)
    bar:Show()
  end
  for i = #series + 1, #page.bars do page.bars[i]:Hide() end
  page.topLabel:SetText(GoldText(max))
  page.midLabel:SetText(GoldText(max / 2))
  page.leftDate:SetText(date("%d %b", series[1].day))
  page.rightDate:SetText(date("%d %b", series[#series].day))
  local change = (lastValue and firstValue) and (lastValue - firstValue) or 0
  local changeText = (change < 0 and "|cffff2020-" or "|cff00ff00+") .. CM.FormatMoney(math.abs(change)) .. "|r"
  page.summary:SetText(("%s: %s now, %s over %s."):format(view.who or "All characters",
    CM.FormatMoney(lastValue or 0), changeText, PERIODS[view.period][1]:lower()))
  page.who:SetText((view.who or "All characters") .. " |cff808080(change)|r")
  for i, b in ipairs(page.periodButtons) do
    if i == view.period then b:LockHighlight() else b:UnlockHighlight() end
  end
end
H.Refresh = Refresh

local function Build(p)
  page = p
  local skin = CM.Skins:Get()
  page.bars = {}
  local who = CreateFrame("Button", nil, page, skin.buttonTemplate)
  who:SetSize(200, 22)
  who:SetPoint("TOPLEFT", 70, -34)
  who:SetScript("OnClick", function(b)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
    MenuUtil.CreateContextMenu(b, function(_, root)
      root:CreateRadio("All characters", function() return view.who == nil end,
        function() view.who = nil; Refresh() end)
      for _, name in ipairs(H.Characters()) do
        root:CreateRadio(name, function() return view.who == name end, function() view.who = name; Refresh() end)
      end
    end)
  end)
  page.who = who
  page.periodButtons = {}
  local anchor
  for i = #PERIODS, 1, -1 do
    local b = CreateFrame("Button", nil, page, skin.buttonTemplate)
    b:SetSize(80, 22)
    if anchor then b:SetPoint("RIGHT", anchor, "LEFT", -4, 0) else b:SetPoint("TOPRIGHT", -12, -34) end
    b:SetText(PERIODS[i][1])
    b:SetScript("OnClick", function() view.period = i; Refresh() end)
    page.periodButtons[i] = b
    anchor = b
  end
  page.summary = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  page.summary:SetPoint("TOPLEFT", 70, -66)
  local chart = CreateFrame("Frame", nil, page, "InsetFrameTemplate")
  chart:SetPoint("TOPLEFT", 90, -92)
  chart:SetPoint("BOTTOMRIGHT", -16, 30)
  page.chart = chart
  page.topLabel = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  page.topLabel:SetPoint("TOPRIGHT", chart, "TOPLEFT", -4, -2)
  page.midLabel = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  page.midLabel:SetPoint("RIGHT", chart, "LEFT", -4, 0)
  page.leftDate = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  page.leftDate:SetPoint("TOPLEFT", chart, "BOTTOMLEFT", 0, -4)
  page.rightDate = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  page.rightDate:SetPoint("TOPRIGHT", chart, "BOTTOMRIGHT", 0, -4)
end

API.RegisterMainTab("gold", { title = "Gold", order = 25, build = Build, show = function() Refresh() end })

CM.RegisterEvent(H, "PLAYER_MONEY", function() if page and page:IsVisible() then Refresh() end end)

API.GetGoldHistory = H.Series -- (days, [character]) -> { { day, copper }, ... } (minor 10)
