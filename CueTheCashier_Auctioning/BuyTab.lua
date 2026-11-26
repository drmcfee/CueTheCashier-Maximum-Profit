-- CueTheCashier: the Buy tab of the Craft Trade window.
-- A copy of Blizzard's "Browse Auctions" page: favorites star, search box,
-- Filter, Search, the category list on the left, and Price / Name /
-- Available columns. Click a row for the item page (Bid / Buyout).
-- 0.34: level boxes, a "Max % of value" filter (hides results priced over
-- that share of their market value) and a Saved menu with your recent
-- searches and named saved searches (text, category, levels, filters).
--
-- Positions are in UI units and were measured from a screenshot of
-- Blizzard's window, so the two windows line up.
-- Copyright (C) 2026 Kim. Licensed under the GNU GPL v3 or later; see LICENSE.
local _, ns = ...
local CM = CueTheCashier
local API = CM.API

local BuyTab = {}
ns.BuyTab = BuyTab

local ROW_HEIGHT = 20
local TOP = -43            -- top of the search row
local LIST_TOP = -78       -- top of category list and result headers
local LIST_BOTTOM = 30     -- space under the lists for money and scan row
local CAT_LEFT, CAT_WIDTH = 8, 156
local RESULTS_LEFT = 174
local COLUMNS = {          -- result columns, left to right
  { key = "fav", title = "", width = 24 },  -- favorite star
  { key = "price", title = "Price", width = 165, justify = "RIGHT" },
  { key = "name", title = "Name", width = 311, justify = "LEFT" },
  { key = "quantity", title = "Available", width = 88, justify = "RIGHT" },
}

local state = {
  results = {},          -- { itemKey, minPrice, totalQuantity, name, quality, icon }
  sortKey = "price",
  sortReverse = false,
  category = nil,        -- selected category node
  expanded = {},         -- [node] = true
  filters = {            -- Filter menu state
    UsableOnly = false, ExactMatch = false,
    PoorQuality = true, CommonQuality = true, UncommonQuality = true,
    RareQuality = true, EpicQuality = true, LegendaryQuality = true,
  },
  maxPct = nil,          -- only results at or under this % of market value
  hidden = 0,            -- results the % filter hid in the last search
}

local MAX_RECENT = 10
local RefreshCategories -- defined with the category list below
local PCT_CHOICES = { 100, 80, 60, 40 }

-- ------------------------------------------------------------------
-- Helpers
-- ------------------------------------------------------------------
local function TrySetAtlas(tex, atlas, r, g, b, a)
  if not (tex.SetAtlas and pcall(tex.SetAtlas, tex, atlas)) then
    tex:SetColorTexture(r or 0.2, g or 0.2, b or 0.2, a or 0.6) -- GUESS fallback look
  end
end

local function PriceSorts()
  local order = Enum.AuctionHouseSortOrder
  return order and { { sortOrder = order.Price, reverseSort = false } } or {}
end

local function QueryFilters()
  local list = {}
  if not Enum.AuctionHouseFilter then return list end
  for name, on in pairs(state.filters) do
    if on and Enum.AuctionHouseFilter[name] then list[#list + 1] = Enum.AuctionHouseFilter[name] end
  end
  return list
end

-- Fills in name, quality and icon. Returns false if the client has not
-- loaded the item yet (ITEM_KEY_ITEM_INFO_RECEIVED fires when it has).
local function FillItemInfo(r)
  if r.name then return true end
  local info = C_AuctionHouse.GetItemKeyInfo(r.itemKey)
  if not info then return false end
  r.name, r.quality, r.icon = info.itemName, info.quality, info.iconFileID
  return true
end

local function SortResults()
  local key, rev = state.sortKey, state.sortReverse
  for _, r in ipairs(state.results) do FillItemInfo(r) end
  table.sort(state.results, function(a, b)
    local x, y
    if key == "price" then x, y = a.minPrice or 0, b.minPrice or 0
    elseif key == "quantity" then x, y = a.totalQuantity or 0, b.totalQuantity or 0
    else
      -- Items still loading go last, whatever the direction.
      if not a.name or not b.name then
        if a.name ~= b.name then return a.name ~= nil end
        return false
      end
      x, y = a.name, b.name
    end
    if x == y then return (a.name or "") < (b.name or "") end
    if rev then return x > y end
    return x < y
  end)
end

-- ------------------------------------------------------------------
-- Result list
-- ------------------------------------------------------------------
local function InitResultRow(row, r)
  if not row.cells then
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    TrySetAtlas(hl, "auctionhouse-ui-row-highlight", 1, 1, 1, 0.08)
    hl:SetBlendMode("ADD")
    row.cells = {}
    local x = 4
    for _, col in ipairs(COLUMNS) do
      if col.key == "fav" then
        -- Favorite star: empty when not a favorite, filled when it is.
        local star = CreateFrame("Button", nil, row)
        star:SetSize(14, 14)
        star:SetPoint("LEFT", x + 2, 0)
        star.tex = star:CreateTexture(nil, "ARTWORK")
        star.tex:SetAllPoints()
        star:SetScript("OnClick", function(b)
          local key = b:GetParent().result.itemKey
          local fav = C_AuctionHouse.IsFavoriteItem(key)
          CM.Try("SetFavoriteItem", C_AuctionHouse.SetFavoriteItem, key, not fav)
          BuyTab:UpdateStar(b, key)
        end)
        row.star = star
        x = x + col.width
      else
      local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      fs:SetJustifyH(col.justify)
      fs:SetWordWrap(false)
      row.cells[col.key] = fs
      if col.key == "name" then
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(16, 16)
        row.icon:SetPoint("LEFT", x + 4, 0)
        fs:SetPoint("LEFT", x + 24, 0)
        fs:SetWidth(col.width - 28)
      else
        fs:SetPoint("LEFT", x, 0)
        fs:SetWidth(col.width - 12)
      end
      x = x + col.width
      end
    end
    row:SetScript("OnEnter", function(rw) CM.ShowItemTooltip(rw, rw.result.itemKey) end)
    row:SetScript("OnLeave", GameTooltip_Hide)
    -- Clicking a row opens the item page (Bid / Buyout).
    row:SetScript("OnClick", function(rw) ns.ItemPage:Show(rw.result) end)
  end
  row.result = r
  BuyTab:UpdateStar(row.star, r.itemKey)
  CM.Skins:Stripe(row.bg, r.index)
  row.cells.price:SetText(r.minPrice and CM.FormatMoney(r.minPrice) or "")
  row.cells.quantity:SetText(r.totalQuantity or "")
  if FillItemInfo(r) then
    local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[r.quality or 1]
    row.cells.name:SetText(r.name or "?")
    if color then row.cells.name:SetTextColor(color.r, color.g, color.b) end
    row.icon:SetTexture(r.icon)
  else
    row.cells.name:SetText("Loading...")
    row.cells.name:SetTextColor(0.6, 0.6, 0.6)
    row.icon:SetTexture(nil)
  end
end

-- Shows the star filled for favorites and empty otherwise.
-- GUESS: atlas names from retail; a gold/grey colour is the fallback.
function BuyTab:UpdateStar(star, itemKey)
  local fav = C_AuctionHouse.IsFavoriteItem and C_AuctionHouse.IsFavoriteItem(itemKey)
  if fav then
    if not (star.tex.SetAtlas and pcall(star.tex.SetAtlas, star.tex, "auctionhouse-icon-favorite")) then
      star.tex:SetColorTexture(1, 0.82, 0, 1)
    end
  elseif not (star.tex.SetAtlas and pcall(star.tex.SetAtlas, star.tex, "auctionhouse-icon-favorite-off")) then
    star.tex:SetColorTexture(0.4, 0.4, 0.4, 0.6)
  end
  star.isFavorite = fav and true or false
end

local function RefreshResults(self)
  SortResults()
  for i, r in ipairs(state.results) do r.index = i end
  CM.SetRows(self.resultsBox, state.results)
  for _, col in ipairs(COLUMNS) do
    local h = self.headers[col.key]
    if h then h.arrow:SetShown(state.sortKey == col.key)
    h.arrow:SetTexCoord(0, 1, state.sortReverse and 1 or 0, state.sortReverse and 0 or 1) end
  end
  if #state.results == 0 and self.searched then
    if state.hidden > 0 then
      self.emptyText:SetText(("No results found. %d were over %d%% of their market value."):format(
        state.hidden, state.maxPct or 100))
    else
      self.emptyText:SetText("No results found.")
    end
    self.emptyText:Show()
  elseif not self.searched then
    self.emptyText:Show()
  else
    self.emptyText:Hide()
  end
end

-- The "Max % of value" filter: true when the result may be shown.
local function UnderPct(r)
  if not state.maxPct then return true end
  local market = r.itemKey and API.GetPrice(r.itemKey.itemID, "auction.market")
  if not (market and market > 0 and r.minPrice) then return false end
  return r.minPrice <= market * state.maxPct / 100
end

local function ReadBrowseResults(self)
  state.results, state.hidden = {}, 0
  for _, r in ipairs(C_AuctionHouse.GetBrowseResults() or {}) do
    local e = { itemKey = r.itemKey, minPrice = r.minPrice, totalQuantity = r.totalQuantity }
    if UnderPct(e) then
      state.results[#state.results + 1] = e
    else
      state.hidden = state.hidden + 1
    end
  end
  CM.Debug(("Buy tab: %d browse results (%d hidden by max %% of value)."):format(#state.results, state.hidden))
  RefreshResults(self)
end

-- ------------------------------------------------------------------
-- Searching
-- ------------------------------------------------------------------
-- ------------------------------------------------------------------
-- Saved and recent searches (account wide: CueTheCashierDB.settings.searches)
-- ------------------------------------------------------------------
local function Searches()
  local st = CM.Settings()
  st.searches = st.searches or {}
  st.searches.recent = st.searches.recent or {}
  st.searches.saved = st.searches.saved or {}
  return st.searches
end
BuyTab.Searches = Searches

-- Names from the top category down to the node, or nil.
local function CategoryPath(nodes, target, path)
  for _, n in ipairs(nodes or {}) do
    path[#path + 1] = n.name
    if n == target then return path end
    if CategoryPath(n.children, target, path) then return path end
    path[#path] = nil
  end
end

local function FindCategory(nodes, path, depth)
  depth = depth or 1
  for _, n in ipairs(nodes or {}) do
    if n.name == path[depth] then
      if depth == #path then return n end
      return FindCategory(n.children, path, depth + 1)
    end
  end
end

local function LevelOf(box)
  local n = box and tonumber(box:GetText())
  if n and n > 0 then return math.floor(n) end
end

-- What the search row shows now, as a saved search entry.
function BuyTab:Current()
  local filters = {}
  for k, v in pairs(state.filters) do filters[k] = v end
  return {
    text = self.searchBox:GetText() or "",
    category = state.category and CategoryPath(self.categories, state.category, {}) or nil,
    minLevel = LevelOf(self.minLevel), maxLevel = LevelOf(self.maxLevel),
    filters = filters, maxPct = state.maxPct,
  }
end

-- A short description: "copper ore, Trade Goods > Metal & Stone, level 10-20, max 80%".
function BuyTab.Describe(e)
  local parts = {}
  if e.text and e.text ~= "" then parts[#parts + 1] = e.text end
  if e.category then parts[#parts + 1] = table.concat(e.category, " > ") end
  if e.minLevel or e.maxLevel then
    parts[#parts + 1] = ("level %s-%s"):format(e.minLevel or "", e.maxLevel or "")
  end
  if e.maxPct then parts[#parts + 1] = ("max %d%%"):format(e.maxPct) end
  if #parts == 0 then return "Everything" end
  return table.concat(parts, ", ")
end

local function SameSearch(a, b)
  if (a.text or ""):lower() ~= (b.text or ""):lower() then return false end
  if table.concat(a.category or {}, ">") ~= table.concat(b.category or {}, ">") then return false end
  if a.minLevel ~= b.minLevel or a.maxLevel ~= b.maxLevel or a.maxPct ~= b.maxPct then return false end
  for k, v in pairs(a.filters or {}) do if (b.filters or {})[k] ~= v then return false end end
  return true
end

local function Remember(e)
  if (e.text or "") == "" and not e.category then return end
  local recent = Searches().recent
  for i = #recent, 1, -1 do if SameSearch(recent[i], e) then table.remove(recent, i) end end
  table.insert(recent, 1, e)
  while #recent > MAX_RECENT do table.remove(recent) end
end

-- Puts a saved or recent search back in the search row and searches.
function BuyTab:Load(e)
  self.searchBox:SetText(e.text or "")
  if self.minLevel then
    self.minLevel:SetText(e.minLevel and tostring(e.minLevel) or "")
    self.maxLevel:SetText(e.maxLevel and tostring(e.maxLevel) or "")
  end
  for k in pairs(state.filters) do
    if e.filters and e.filters[k] ~= nil then state.filters[k] = e.filters[k] end
  end
  state.maxPct = e.maxPct
  state.category = e.category and FindCategory(self.categories, e.category) or nil
  if state.category then
    -- Open the category's parents so it is visible.
    local nodes = self.categories
    for _, name in ipairs(e.category) do
      for _, n in ipairs(nodes) do
        if n.name == name then state.expanded[n] = true; nodes = n.children; break end
      end
    end
  end
  RefreshCategories(self)
  self:Search()
end

-- Saves the current search under a name (same name replaces it).
function BuyTab:SaveSearch(name)
  name = tostring(name or ""):gsub("[\r\n|]", " "):gsub("^%s+", ""):gsub("%s+$", ""):sub(1, 40)
  if name == "" then return nil end
  local e = self:Current()
  e.name = name
  local saved = Searches().saved
  for i = #saved, 1, -1 do if saved[i].name == name then table.remove(saved, i) end end
  saved[#saved + 1] = e
  table.sort(saved, function(a, b) return a.name:lower() < b.name:lower() end)
  CM.Print(("Saved search \"%s\": %s."):format(name, BuyTab.Describe(e)))
  return true
end

function BuyTab:DeleteSearch(name)
  local saved = Searches().saved
  for i = #saved, 1, -1 do if saved[i].name == name then table.remove(saved, i) end end
end

function BuyTab:Search()
  ns.ItemPage:Hide()
  if C_AuctionHouse.IsThrottledMessageSystemReady
     and not C_AuctionHouse.IsThrottledMessageSystemReady() then
    CM.Debug("Buy tab: search skipped, auction house busy.")
    return
  end
  local query = {
    searchString = self.searchBox:GetText() or "",
    sorts = PriceSorts(),
    filters = QueryFilters(),
    itemClassFilters = state.category and state.category.filters or {},
  }
  local minLevel, maxLevel = LevelOf(self.minLevel), LevelOf(self.maxLevel)
  if minLevel then query.minLevel = minLevel end
  if maxLevel then query.maxLevel = maxLevel end
  Remember(self:Current())
  ns.browseOwner = "buy" -- Vendor and Snipe also browse; answers go to whoever asked last
  CM.Try("Buy tab SendBrowseQuery", C_AuctionHouse.SendBrowseQuery, query)
  self.searched = true
end

function BuyTab:SearchFavorites()
  ns.ItemPage:Hide()
  self.searchBox:SetText("")
  ns.browseOwner = "buy"
  CM.Try("Buy tab SearchForFavorites", C_AuctionHouse.SearchForFavorites, PriceSorts())
  self.searched = true
end

-- ------------------------------------------------------------------
-- Category list
-- ------------------------------------------------------------------
local CATEGORY_ATLAS = { "auctionhouse-nav-button", "auctionhouse-nav-button-secondary",
  "auctionhouse-nav-button-tertiary" }

local function VisibleCategories(nodes, out)
  for _, node in ipairs(nodes) do
    out[#out + 1] = node
    if state.expanded[node] then VisibleCategories(node.children, out) end
  end
  return out
end

function RefreshCategories(self)
  CM.SetRows(self.categoryBox, VisibleCategories(self.categories, {}))
end

local function InitCategoryRow(row, node)
  if not row.label then
    row.tex = row:CreateTexture(nil, "BACKGROUND")
    row.tex:SetAllPoints()
    row.selected = row:CreateTexture(nil, "ARTWORK")
    row.selected:SetAllPoints()
    TrySetAtlas(row.selected, "auctionhouse-nav-button-select", 1, 0.82, 0, 0.25)
    row.selected:SetBlendMode("ADD")
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    TrySetAtlas(hl, "auctionhouse-nav-button-highlight", 1, 1, 1, 0.1)
    hl:SetBlendMode("ADD")
    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.label:SetJustifyH("LEFT")
    row:SetScript("OnClick", function(r)
      local n = r.node
      if state.category == n then
        state.expanded[n] = not state.expanded[n]
      else
        state.category = n
        state.expanded[n] = true
      end
      RefreshCategories(BuyTab)
      BuyTab:Search() -- Blizzard also searches when you pick a category
    end)
  end
  row.node = node
  TrySetAtlas(row.tex, CATEGORY_ATLAS[math.min(node.depth, 3)])
  row.label:ClearAllPoints()
  row.label:SetPoint("LEFT", 8 + (node.depth - 1) * 10, 0)
  row.label:SetFontObject(node.depth == 1 and "GameFontNormal" or "GameFontHighlightSmall")
  row.label:SetText(node.name)
  row.selected:SetShown(state.category == node)
end

-- ------------------------------------------------------------------
-- Building the tab
-- ------------------------------------------------------------------
local function MakeList(self, parent, initializer)
  local box = CreateFrame("Frame", nil, parent, "WowScrollBoxList")
  local bar = CreateFrame("EventFrame", nil, parent, "MinimalScrollBar")
  local view = CreateScrollBoxListLinearView()
  view:SetElementInitializer("CueTheCashierResultRowTemplate", initializer)
  if view.SetElementExtent then view:SetElementExtent(ROW_HEIGHT) end
  ScrollUtil.InitScrollBoxListWithScrollBar(box, bar, view)
  return box, bar
end

local function MakeFilterButton(self, parent)
  local ok, button = pcall(CreateFrame, "DropdownButton", "CueTheCashierBuyFilterButton",
    parent, "WowStyle1FilterDropdownTemplate")
  if not ok or not button.SetupMenu then
    CM.Debug("Buy tab: filter dropdown template missing, plain Filter button used.")
    button = CreateFrame("Button", "CueTheCashierBuyFilterButton", parent, "UIPanelButtonTemplate")
    button:SetText(FILTER or "Filter")
    return button
  end
  button:SetText(FILTER or "Filter")
  local labels = {
    { "UsableOnly", "Usable Only" }, { "ExactMatch", "Exact Match" },
    { "PoorQuality", "Poor" }, { "CommonQuality", "Common" }, { "UncommonQuality", "Uncommon" },
    { "RareQuality", "Rare" }, { "EpicQuality", "Epic" }, { "LegendaryQuality", "Legendary" },
  }
  button:SetupMenu(function(_, root)
    for i, l in ipairs(labels) do
      if i == 3 then root:CreateDivider(); root:CreateTitle("Rarity") end
      root:CreateCheckbox(l[2],
        function() return state.filters[l[1]] end,
        function() state.filters[l[1]] = not state.filters[l[1]] end)
    end
    -- Only show results priced at or under this share of market value.
    root:CreateDivider()
    root:CreateTitle("Max % of value")
    root:CreateRadio("Any price", function() return state.maxPct == nil end,
      function() state.maxPct = nil end)
    for _, pct in ipairs(PCT_CHOICES) do
      root:CreateRadio(("%d%%"):format(pct), function() return state.maxPct == pct end,
        function() state.maxPct = pct end)
    end
  end)
  return button
end

-- A small panel under the Saved button that asks for a name.
function BuyTab:AskName(anchor)
  local p = self.namePanel
  if not p then
    p = CreateFrame("Frame", "CueTheCashierSaveSearchPanel", self.frame)
    p:SetSize(260, 74)
    p:SetFrameStrata("DIALOG")
    p:EnableMouse(true)
    local bg = p:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.05, 0.05, 0.05, 0.95)
    local ok, border = pcall(CreateFrame, "Frame", nil, p, "DialogBorderDarkTemplate")
    if not ok then CM.Debug("Buy tab: DialogBorderDarkTemplate missing.") end
    local label = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", 14, -12)
    label:SetText("Name this search:")
    local eb = CreateFrame("EditBox", nil, p, "InputBoxTemplate")
    eb:SetSize(160, 20)
    eb:SetPoint("TOPLEFT", 20, -32)
    eb:SetAutoFocus(false)
    eb:SetMaxLetters(40)
    local save = CreateFrame("Button", nil, p, CM.Skins:Get().buttonTemplate)
    save:SetSize(64, 22)
    save:SetPoint("LEFT", eb, "RIGHT", 8, 0)
    save:SetText(SAVE or "Save")
    local function Done()
      if BuyTab:SaveSearch(eb:GetText()) then p:Hide() end
    end
    save:SetScript("OnClick", Done)
    eb:SetScript("OnEnterPressed", Done)
    eb:SetScript("OnEscapePressed", function() p:Hide() end)
    p.editBox = eb
    self.namePanel = p
  end
  p:ClearAllPoints()
  p:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -4)
  local text = self.searchBox:GetText() or ""
  p.editBox:SetText(text ~= "" and text or BuyTab.Describe(self:Current()):sub(1, 40))
  p:Show()
  p.editBox:SetFocus()
  p.editBox:HighlightText()
end

function BuyTab:ShowSavedMenu(owner)
  if not (MenuUtil and MenuUtil.CreateContextMenu) then
    CM.Print("The saved searches menu needs Blizzard's menu system, which isn't there.")
    return
  end
  local s = Searches()
  MenuUtil.CreateContextMenu(owner, function(_, root)
    root:CreateTitle("Saved searches")
    if #s.saved == 0 then root:CreateTitle("|cff808080None yet|r") end
    for _, e in ipairs(s.saved) do
      local b = root:CreateButton(e.name, function() BuyTab:Load(e) end)
      if b.SetTooltip then
        b:SetTooltip(function(tt) tt:SetText(e.name); tt:AddLine(BuyTab.Describe(e), 1, 1, 1, true) end)
      end
    end
    root:CreateDivider()
    root:CreateTitle("Recent")
    if #s.recent == 0 then root:CreateTitle("|cff808080None yet|r") end
    for _, e in ipairs(s.recent) do
      root:CreateButton(BuyTab.Describe(e), function() BuyTab:Load(e) end)
    end
    root:CreateDivider()
    root:CreateButton("Save this search...", function() BuyTab:AskName(owner) end)
    if #s.saved > 0 then
      local del = root:CreateButton(DELETE or "Delete")
      for _, e in ipairs(s.saved) do
        del:CreateButton(e.name, function() BuyTab:DeleteSearch(e.name) end)
      end
    end
    if #s.recent > 0 then
      root:CreateButton("Clear recent", function() wipe(s.recent) end)
    end
  end)
end

function BuyTab:Build(parent)
  local skin = CM.Skins:Get()
  local f = CreateFrame("Frame", "CueTheCashierBuyTab", parent)
  f:SetAllPoints()
  self.frame = f

  -- Search row: favorites star, search box, Filter, Search.
  local star = CreateFrame("Button", "CueTheCashierBuyFavoritesButton", f)
  star:SetSize(24, 24)
  star:SetPoint("TOPLEFT", 175, TOP + 1)
  local starTex = star:CreateTexture(nil, "ARTWORK")
  starTex:SetAllPoints()
  TrySetAtlas(starTex, "auctionhouse-icon-favorite", 1, 0.82, 0, 1)
  star:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
  star:SetScript("OnClick", function() BuyTab:SearchFavorites() end)
  star:SetScript("OnEnter", function(b)
    GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
    GameTooltip:SetText("Search favorites")
    GameTooltip:Show()
  end)
  star:SetScript("OnLeave", GameTooltip_Hide)

  local search = CreateFrame("Button", "CueTheCashierBuySearchButton", f, skin.buttonTemplate)
  search:SetSize(128, 22)
  search:SetPoint("TOPRIGHT", -13, TOP)
  search:SetText(SEARCH or "Search")
  search:SetScript("OnClick", function() BuyTab:Search() end)

  local filter = MakeFilterButton(self, f)
  filter:SetSize(89, 22)
  filter:SetPoint("RIGHT", search, "LEFT", -22, 0)

  -- Saved searches menu and level boxes, between the search box and Filter.
  local savedButton = CreateFrame("Button", "CueTheCashierBuySavedButton", f, skin.buttonTemplate)
  savedButton:SetSize(70, 22)
  savedButton:SetPoint("RIGHT", filter, "LEFT", -8, 0)
  savedButton:SetText("Saved")
  savedButton:SetScript("OnClick", function(b) BuyTab:ShowSavedMenu(b) end)
  savedButton:SetScript("OnEnter", function(b)
    GameTooltip:SetOwner(b, "ANCHOR_BOTTOM")
    GameTooltip:SetText("Saved searches")
    GameTooltip:AddLine("Your recent searches and the ones you saved with a name, with their filters.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  savedButton:SetScript("OnLeave", GameTooltip_Hide)

  local function LevelBox(name)
    local lb = CreateFrame("EditBox", name, f, "InputBoxTemplate")
    lb:SetSize(28, 20)
    lb:SetAutoFocus(false)
    lb:SetNumeric(true)
    lb:SetMaxLetters(3)
    lb:SetJustifyH("CENTER")
    lb:SetScript("OnEnterPressed", function(b) b:ClearFocus(); BuyTab:Search() end)
    lb:SetScript("OnEnter", function(b)
      GameTooltip:SetOwner(b, "ANCHOR_BOTTOM")
      GameTooltip:SetText("Required level, lowest and highest")
      GameTooltip:Show()
    end)
    lb:SetScript("OnLeave", GameTooltip_Hide)
    return lb
  end
  local maxLevel = LevelBox("CueTheCashierBuyMaxLevel")
  maxLevel:SetPoint("RIGHT", savedButton, "LEFT", -10, 0)
  local dash = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  dash:SetPoint("RIGHT", maxLevel, "LEFT", -6, 0)
  dash:SetText("-")
  local minLevel = LevelBox("CueTheCashierBuyMinLevel")
  minLevel:SetPoint("RIGHT", dash, "LEFT", -8, 0)
  local lvl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  lvl:SetPoint("RIGHT", minLevel, "LEFT", -6, 0)
  lvl:SetText(LEVEL or "Level")
  self.minLevel, self.maxLevel = minLevel, maxLevel

  local box = CreateFrame("EditBox", "CueTheCashierBuySearchBox", f, "SearchBoxTemplate")
  box:SetHeight(20)
  box:SetPoint("LEFT", star, "RIGHT", 12, 0)
  box:SetPoint("RIGHT", lvl, "LEFT", -10, 0)
  box:SetAutoFocus(false)
  box:SetScript("OnEnterPressed", function(b) b:ClearFocus(); BuyTab:Search() end)
  self.searchBox = box

  -- Shift- or Ctrl-click an item (bags, chat links, ...) while the Buy tab
  -- is open: put its name in the search box and search, like Blizzard.
  if HandleModifiedItemClick then
    hooksecurefunc("HandleModifiedItemClick", function(link)
      if not (f:IsVisible() and type(link) == "string") then return end
      if not (IsShiftKeyDown() or IsControlKeyDown()) then return end
      local name = (C_Item.GetItemInfo and C_Item.GetItemInfo(link)) or link:match("%[(.-)%]")
      if not name then return end
      box:SetText(name)
      box:ClearFocus()
      BuyTab:Search()
    end)
  end

  -- Category list on the left.
  local catInset = CreateFrame("Frame", nil, f, "InsetFrameTemplate")
  catInset:SetPoint("TOPLEFT", CAT_LEFT, LIST_TOP)
  catInset:SetPoint("BOTTOMLEFT", CAT_LEFT, LIST_BOTTOM)
  catInset:SetWidth(CAT_WIDTH)
  local catBox, catBar = MakeList(self, f, InitCategoryRow)
  catBox:SetPoint("TOPLEFT", catInset, "TOPLEFT", 4, -4)
  catBox:SetPoint("BOTTOMRIGHT", catInset, "BOTTOMRIGHT", -16, 4)
  catBar:SetPoint("TOPLEFT", catBox, "TOPRIGHT", 2, 0)
  catBar:SetPoint("BOTTOMLEFT", catBox, "BOTTOMRIGHT", 2, 0)
  self.categoryBox = catBox
  self.categories = ns.Categories:Get()
  RefreshCategories(self)

  -- Result list with column headers. Lives in its own frame so the item
  -- page can take its place.
  local bv = CreateFrame("Frame", "CueTheCashierBuyBrowseView", f)
  bv:SetAllPoints()
  self.browseView = bv
  local resInset = CreateFrame("Frame", nil, bv, "InsetFrameTemplate")
  resInset:SetPoint("TOPLEFT", RESULTS_LEFT, LIST_TOP - ROW_HEIGHT)
  resInset:SetPoint("BOTTOMRIGHT", -28, LIST_BOTTOM)
  self.headers = {}
  local x = RESULTS_LEFT
  for _, col in ipairs(COLUMNS) do
    local h = CreateFrame("Button", nil, bv)
    h:SetSize(col.width, ROW_HEIGHT)
    h:SetPoint("TOPLEFT", x, LIST_TOP)
    local bg = h:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    TrySetAtlas(bg, "auctionhouse-tableheader", 0.15, 0.15, 0.15, 0.9)
    if col.key ~= "fav" then
      h:SetHighlightTexture("Interface\\PaperDollInfoFrame\\UI-Character-Tab-Highlight", "ADD")
    end
    local label = h:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("LEFT", 8, 0)
    label:SetText(col.title)
    local arrow = h:CreateTexture(nil, "OVERLAY")
    arrow:SetSize(9, 8)
    arrow:SetPoint("LEFT", label, "RIGHT", 6, 0)
    arrow:SetTexture("Interface\\Buttons\\UI-SortArrow")
    h.arrow = arrow
    h:SetScript("OnClick", function()
      if col.key == "fav" then return end
      if state.sortKey == col.key then state.sortReverse = not state.sortReverse
      else state.sortKey, state.sortReverse = col.key, false end
      RefreshResults(BuyTab)
    end)
    self.headers[col.key] = h
    x = x + col.width + 2
  end
  local resBox, resBar = MakeList(self, bv, InitResultRow)
  resBox:SetPoint("TOPLEFT", resInset, "TOPLEFT", 4, -4)
  resBox:SetPoint("BOTTOMRIGHT", resInset, "BOTTOMRIGHT", -4, 4)
  resBar:SetPoint("TOPLEFT", resInset, "TOPRIGHT", 6, 0)
  resBar:SetPoint("BOTTOMLEFT", resInset, "BOTTOMRIGHT", 6, 0)
  self.resultsBox = resBox

  -- Ask for the next page of results when scrolled near the bottom.
  if resBox.RegisterCallback and ScrollBoxListMixin and ScrollBoxListMixin.Event then
    resBox:RegisterCallback(ScrollBoxListMixin.Event.OnScroll, function()
      if ns.browseOwner == "buy" and C_AuctionHouse.HasFullBrowseResults
         and not C_AuctionHouse.HasFullBrowseResults()
         and resBox:GetScrollPercentage() > 0.9 then
        CM.Try("RequestMoreBrowseResults", C_AuctionHouse.RequestMoreBrowseResults)
      end
    end, self)
  end

  local empty = bv:CreateFontString(nil, "OVERLAY", "GameFontNormalMed1")
  empty:SetPoint("TOP", resInset, "TOP", 0, -100)
  empty:SetWidth(500)
  empty:SetText("Search for an item, or pick a category on the left.")
  self.emptyText = empty

  -- Your gold, bottom left like Blizzard's.
  local moneyInset = CreateFrame("Frame", nil, f, "InsetFrameTemplate")
  moneyInset:SetPoint("BOTTOMLEFT", CAT_LEFT, 5)
  moneyInset:SetSize(CAT_WIDTH, 20)
  local money = CreateFrame("Frame", "CueTheCashierBuyMoneyFrame", moneyInset, "SmallMoneyFrameTemplate")
  money:SetPoint("RIGHT", moneyInset, "RIGHT", 6, 0)
  local function UpdateMoney() MoneyFrame_Update(money, GetMoney()) end
  UpdateMoney()

  -- Events while the tab exists.
  f:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
  f:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_ADDED")
  f:RegisterEvent("ITEM_KEY_ITEM_INFO_RECEIVED")
  f:RegisterEvent("PLAYER_MONEY")
  f:RegisterEvent("AUCTION_HOUSE_FAVORITES_UPDATED")
  f:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_MONEY" then UpdateMoney()
    elseif event == "AUCTION_HOUSE_FAVORITES_UPDATED" then
      if bv:IsVisible() then RefreshResults(BuyTab) end
    elseif event == "ITEM_KEY_ITEM_INFO_RECEIVED" then
      if f:IsVisible() then RefreshResults(BuyTab) end
    elseif self.searched and (ns.browseOwner or "buy") == "buy" then
      ReadBrowseResults(BuyTab)
    end
  end)

  -- The item page (Bid / Buyout), shown instead of the browse view.
  ns.ItemPage:Build(f, self)

  RefreshResults(self)
  return f
end
