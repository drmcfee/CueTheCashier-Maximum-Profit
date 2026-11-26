-- CueTheCashier Crafting: the Inventory tab of the main window (0.36).
-- Everything your characters on this server own, on one page: bags, bank,
-- mailbox and auctions, per item, for all characters or one. The counts
-- are the ones the craft list already keeps (Inventory.lua): bags always,
-- the bank and mailbox as they were when you last opened them, auctions
-- as of your last visit to the auction house. Value = count x market value.
-- Copyright (C) 2026 Kim. Licensed under the GNU GPL v3 or later; see LICENSE.
local _, ns = ...
local CM = CueTheCashier
local API = CM.API

local T = {}
ns.InventoryTab = T

local ROW_HEIGHT = 20
local LIST_TOP = -90
local view = { who = nil, filter = "", sortKey = "value", reverse = true }
local page

-- { { name, key, inv }, ... } for this server, sorted by name.
function T.Characters()
  local server = API.GetServerKey()
  local out = {}
  for key, c in pairs(ns.db.chars or {}) do
    if c.inv and key:sub(-#server - 3) == " - " .. server then
      out[#out + 1] = { name = key:sub(1, #key - #server - 3), key = key, inv = c.inv }
    end
  end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

local PLACES = { "bags", "bank", "mail", "auctions" }

-- Rows { id, name, quality, bags, bank, mail, auctions, total, value }, and totals.
function T.Rows(who, filter)
  local items = {}
  for _, ch in ipairs(T.Characters()) do
    if not who or ch.name == who then
      for _, place in ipairs(PLACES) do
        local counts = ch.inv[place] or {}
        for id, n in pairs(counts) do
          local r = items[id] or { id = id, bags = 0, bank = 0, mail = 0, auctions = 0, total = 0 }
          items[id] = r
          r[place] = r[place] + n
          r.total = r.total + n
        end
        if place == "mail" then
          for id, n in pairs(ch.inv.incoming or {}) do
            local r = items[id] or { id = id, bags = 0, bank = 0, mail = 0, auctions = 0, total = 0 }
            items[id] = r
            r.mail, r.total = r.mail + n, r.total + n
          end
        end
      end
    end
  end
  local list, sum = {}, { total = 0, value = 0 }
  filter = (filter or ""):lower()
  for id, r in pairs(items) do
    r.name, _, r.quality = C_Item.GetItemInfo(id)
    r.name = r.name or ("item " .. id)
    if r.total > 0 and (filter == "" or r.name:lower():find(filter, 1, true)) then
      local price = API.GetPrice(id, "auction.market") or API.GetPrice(id, "vendor.sell")
      r.value = price and price * r.total or 0
      list[#list + 1] = r
      sum.total, sum.value = sum.total + r.total, sum.value + r.value
    end
  end
  local key, rev = view.sortKey, view.reverse
  table.sort(list, function(a, b)
    local x, y = a[key], b[key]
    if key == "name" then x, y = x:lower(), y:lower() end
    if x == y then return a.name < b.name end
    if rev then return x > y end
    return x < y
  end)
  return list, sum
end

local function Money(c) return (c and c > 0) and CM.FormatMoney(c) or "" end
local function Count(n) return (n and n > 0) and tostring(n) or "" end

local COLUMNS = {
  { key = "name", title = "Item", width = 236, left = true, get = function(r)
    local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[r.quality or 1]
    return (c and c.hex or "") .. r.name .. (c and "|r" or "") end },
  { key = "bags", title = "Bags", width = 66, get = function(r) return Count(r.bags) end },
  { key = "bank", title = "Bank", width = 66, get = function(r) return Count(r.bank) end },
  { key = "mail", title = "Mail", width = 66, get = function(r) return Count(r.mail) end },
  { key = "auctions", title = "Auctions", width = 72, get = function(r) return Count(r.auctions) end },
  { key = "total", title = "Total", width = 66, get = function(r) return Count(r.total) end },
  { key = "value", title = "Value", width = 128, get = function(r) return Money(r.value) end },
}

local function InitRow(row, r)
  if not row.cells then
    row.cells = {}
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    CM.Skins:Paint(hl, "highlight")
    local x = 4
    for i, col in ipairs(COLUMNS) do
      local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      fs:SetWordWrap(false)
      fs:SetPoint("LEFT", x, 0)
      fs:SetWidth(col.width - 10)
      fs:SetJustifyH(col.left and "LEFT" or "RIGHT")
      row.cells[i] = fs
      x = x + col.width
    end
    row:SetScript("OnEnter", function(rw)
      if not rw.data then return end
      CM.ShowItemTooltip(rw, { itemID = rw.data.id })
      -- Who has it (all characters view).
      if not view.who then
        GameTooltip:AddLine(" ")
        for _, ch in ipairs(T.Characters()) do
          local n = 0
          for _, place in ipairs(PLACES) do n = n + ((ch.inv[place] or {})[rw.data.id] or 0) end
          if n > 0 then GameTooltip:AddDoubleLine(ch.name, n, 1, 1, 1, 1, 1, 1) end
        end
        GameTooltip:Show()
      end
    end)
    row:SetScript("OnLeave", GameTooltip_Hide)
  end
  row.data = r
  CM.Skins:Stripe(row.bg, r.index)
  for i, col in ipairs(COLUMNS) do row.cells[i]:SetText(col.get(r)) end
end

function T.Refresh()
  if not (page and page:IsVisible()) then return end
  ns.Safe("Read bags", ns.Inventory.ScanBags)
  local list, sum = T.Rows(view.who, view.filter)
  for i, r in ipairs(list) do r.index = i end
  CM.SetRows(page.list, list)
  page.empty:SetShown(#list == 0)
  page.who:SetText((view.who or "All characters") .. " |cff808080(change)|r")
  page.summary:SetText(("%d items, worth %s at market value."):format(#list, CM.FormatMoney(sum.value)))
end

local function Build(p)
  page = p
  local skin = CM.Skins:Get()
  local who = CreateFrame("Button", nil, page, skin.buttonTemplate)
  who:SetSize(200, 22)
  who:SetPoint("TOPLEFT", 70, -34)
  who:SetScript("OnClick", function(b)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
    MenuUtil.CreateContextMenu(b, function(_, root)
      root:CreateRadio("All characters", function() return view.who == nil end,
        function() view.who = nil; T.Refresh() end)
      for _, ch in ipairs(T.Characters()) do
        root:CreateRadio(ch.name, function() return view.who == ch.name end,
          function() view.who = ch.name; T.Refresh() end)
      end
    end)
  end)
  page.who = who
  local search = CreateFrame("EditBox", nil, page, "SearchBoxTemplate")
  search:SetSize(200, 20)
  search:SetPoint("TOPRIGHT", -16, -35)
  search:SetAutoFocus(false)
  search:SetScript("OnTextChanged", function(b)
    if SearchBoxTemplate_OnTextChanged then SearchBoxTemplate_OnTextChanged(b) end
    view.filter = b:GetText() or ""
    T.Refresh()
  end)
  page.summary = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  page.summary:SetPoint("TOPLEFT", 70, -66)

  local x = 16
  for _, col in ipairs(COLUMNS) do
    local h = CreateFrame("Button", nil, page)
    h:SetSize(col.width - 2, ROW_HEIGHT)
    h:SetPoint("TOPLEFT", x, LIST_TOP)
    local bg = h:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    if not pcall(bg.SetAtlas, bg, "auctionhouse-tableheader") then bg:SetColorTexture(0.15, 0.15, 0.15, 0.9) end
    h:SetHighlightTexture("Interface\\PaperDollInfoFrame\\UI-Character-Tab-Highlight", "ADD")
    local label = h:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("LEFT", 8, 0)
    label:SetText(col.title)
    h:SetScript("OnClick", function()
      if view.sortKey == col.key then view.reverse = not view.reverse
      else view.sortKey, view.reverse = col.key, col.key ~= "name" end
      T.Refresh()
    end)
    x = x + col.width
  end

  local inset = CreateFrame("Frame", nil, page, "InsetFrameTemplate")
  inset:SetPoint("TOPLEFT", 12, LIST_TOP - ROW_HEIGHT)
  inset:SetPoint("BOTTOMRIGHT", -30, 12)
  local box = CreateFrame("Frame", nil, page, "WowScrollBoxList")
  local bar = CreateFrame("EventFrame", nil, page, "MinimalScrollBar")
  local v = CreateScrollBoxListLinearView()
  v:SetElementInitializer("CueTheCashierResultRowTemplate", InitRow)
  if v.SetElementExtent then v:SetElementExtent(ROW_HEIGHT) end
  ScrollUtil.InitScrollBoxListWithScrollBar(box, bar, v)
  box:SetPoint("TOPLEFT", inset, "TOPLEFT", 4, -4)
  box:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -4, 4)
  bar:SetPoint("TOPLEFT", inset, "TOPRIGHT", 6, 0)
  bar:SetPoint("BOTTOMLEFT", inset, "BOTTOMRIGHT", 6, 0)
  page.list = box
  page.empty = page:CreateFontString(nil, "OVERLAY", "GameFontNormalMed1")
  page.empty:SetPoint("TOP", inset, "TOP", 0, -100)
  page.empty:SetText("Nothing found. Open your bank and mailbox once on each character to fill this in.")
end

function T.Register()
  if not API.RegisterMainTab then return end
  API.RegisterMainTab("inventory", { title = "Inventory", order = 35, build = Build, show = T.Refresh })
end
