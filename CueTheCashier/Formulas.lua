-- CueTheCashier: price formulas and custom prices.
--
-- A price formula works out a price for an item, for example
--   min(market, 7d) * 90%
--   vendor.sell * 3
--   max(100g, craft.cost * 120%)
--   first(7d, market, 1g)
-- What a formula can hold:
--   price sources   any key from the Prices tab (auction.market, vendor.sell,
--                   craft.cost, ...) or a short name: market, min, median,
--                   mean, max, 7d, 30d, all, vendor, vendorbuy, de,
--                   crafting, value, profit, salerate, soldperday, saleavg,
--                   regionmarket, regionmin, regionsalerate,
--                   regionsoldperday, regionsaleavg
--                   (sale rates are 0-1, so market * salerate works)
--   custom prices   a formula saved under a name (Prices tab), used by name
--   money           100g, 5s, 20c, 1g50s
--   percent         90% (the same as 0.9)
--   plain numbers   3, 1.5
--   + - * / and ( )
--   min(a, b, ...), max(...), avg(...)  ignore values that aren't known
--   first(a, b, ...)                    the first value that is known
-- When a source has no value for the item (never scanned, no vendor price)
-- a calculation with it has no value either; min/max/avg/first skip it.
-- The result is copper, rounded.
--
-- Custom prices are saved in the profile, CM.Profile().customPrices
-- ([name] = formula). Names are letters, digits and _, starting with a
-- letter, and can't be a source, short name or function.
-- Copyright (C) 2026 Kim. Licensed under the GNU GPL v3 or later; see LICENSE.
local _, CM = ...
local API = CM.API

local F = {}
CM.Formula = F

local ALIASES = {
  market = "auction.market", min = "auction.min", median = "auction.median", mean = "auction.mean",
  max = "auction.max", ["7d"] = "auction.market.7d", ["30d"] = "auction.market.30d",
  all = "auction.market.all", vendor = "vendor.sell", vendorbuy = "vendor.buy", de = "disenchant", cut = "auction.cut", deposit = "auction.deposit",
  crafting = "craft.cost", value = "craft.value", profit = "craft.profit",
  salerate = "sale.rate", soldperday = "sale.perday", saleavg = "sale.avg",
  regionmarket = "region.market", regionmin = "region.min", regionsalerate = "region.salerate",
  regionsoldperday = "region.perday", regionsaleavg = "region.saleavg",
}
F.ALIASES = ALIASES
-- Old short names that still work in saved formulas (not listed).
local OLD_ALIASES = { cost = "craft.cost" }

local FUNCTIONS = { min = true, max = true, avg = true, first = true }
local MAX_DEPTH = 8 -- custom prices using custom prices; stops loops
local MONEY = { g = 10000, s = 100, c = 1 }

local function Customs()
  local p = CM.Profile()
  p.customPrices = p.customPrices or {}
  return p.customPrices
end

-- ------------------------------------------------------------------
-- Reading the text into tokens
-- ------------------------------------------------------------------
local function Tokenize(text)
  local tokens, i, n = {}, 1, #text
  local function Add(kind, value, at) tokens[#tokens + 1] = { kind = kind, value = value, at = at } end
  while i <= n do
    local c = text:sub(i, i)
    if c:find("%s") then
      i = i + 1
    elseif c:find("[%+%-%*/%(%),]") then
      Add(c, c, i)
      i = i + 1
    elseif c:find("%d") or (c == "." and text:sub(i + 1, i + 1):find("%d")) then
      local start = i
      -- Money: one or more of <digits><g|s|c>, like 1g50s.
      local copper, j = 0, i
      while true do
        local digits, unit = text:match("^(%d+)([gGsScC])", j)
        local after = digits and text:sub(j + #digits + 1, j + #digits + 1) or ""
        if not digits or after:find("[%w_%.]") and not after:find("%d") then break end
        copper = copper + tonumber(digits) * MONEY[unit:lower()]
        j = j + #digits + 1
      end
      if j > i then
        -- "1g 50s" is one amount, like 1g50s.
        local last = tokens[#tokens]
        if last and last.money then
          last.value = last.value + copper
        else
          Add("number", copper, start)
          tokens[#tokens].money = true
        end
        i = j
      else
        local num = text:match("^%d*%.?%d+", i) or text:match("^%d+", i)
        local nextc = text:sub(i + #num, i + #num)
        if nextc:find("[%a_]") then
          -- Starts with a digit but is a name, like 7d or 30d.
          local word = text:match("^[%w_%.]+", i)
          Add("name", word:lower(), start)
          i = i + #word
        elseif nextc == "%" then
          Add("number", tonumber(num) / 100, start)
          i = i + #num + 1
        else
          Add("number", tonumber(num), start)
          i = i + #num
        end
      end
    elseif c:find("[%a_]") then
      local word = text:match("^[%w_%.]+", i)
      Add("name", word:lower(), i)
      i = i + #word
    else
      return nil, ("Unexpected \"%s\" at position %d."):format(c, i)
    end
  end
  Add("end", nil, n + 1)
  return tokens
end

-- ------------------------------------------------------------------
-- Turning tokens into a function(itemID, depth) -> number or nil
-- ------------------------------------------------------------------
local function Const(v) return function() return v end end

local function Arith(op, a, b)
  return function(id, d)
    local x, y = a(id, d), b(id, d)
    if not (x and y) then return nil end
    if op == "+" then return x + y
    elseif op == "-" then return x - y
    elseif op == "*" then return x * y end
    if y == 0 then return nil end
    return x / y
  end
end

local function Call(name, args)
  return function(id, d)
    local vals = {}
    for _, a in ipairs(args) do
      local v = a(id, d)
      if name == "first" and v then return v end
      if v then vals[#vals + 1] = v end
    end
    if #vals == 0 then return nil end
    if name == "min" then return math.min(unpack(vals)) end
    if name == "max" then return math.max(unpack(vals)) end
    if name == "avg" then
      local sum = 0
      for _, v in ipairs(vals) do sum = sum + v end
      return sum / #vals
    end
  end
end

local function Source(key)
  return function(id) return API.GetPrice(id, key) end
end

local function CustomRef(name)
  return function(id, d) return F.Custom(name, id, d) end
end

local function Parse(tokens)
  local pos = 1
  local function Peek() return tokens[pos] end
  local function Take() pos = pos + 1; return tokens[pos - 1] end
  local function Fail(msg, t) error({ msg = msg .. ((t and t.at) and (" (position %d)"):format(t.at) or "") }) end
  local Expr

  local function Primary()
    local t = Take()
    if t.kind == "number" then return Const(t.value) end
    if t.kind == "(" then
      local e = Expr()
      if Take().kind ~= ")" then Fail("Missing )", t) end
      return e
    end
    if t.kind == "-" then
      local e = Primary()
      return function(id, d) local v = e(id, d); return v and -v end
    end
    if t.kind == "name" then
      if Peek().kind == "(" then
        if not FUNCTIONS[t.value] then Fail(("Unknown function \"%s\""):format(t.value), t) end
        Take()
        local args = {}
        if Peek().kind ~= ")" then
          repeat
            args[#args + 1] = Expr()
          until Peek().kind ~= "," or not Take()
        end
        if Take().kind ~= ")" then Fail("Missing ) after " .. t.value .. "(", t) end
        if #args == 0 then Fail(t.value .. "() needs at least one value", t) end
        return Call(t.value, args)
      end
      local key = ALIASES[t.value] or OLD_ALIASES[t.value] or t.value
      if API.HasPriceSource(key) then return Source(key) end
      if Customs()[t.value] then return CustomRef(t.value) end
      Fail(("Unknown price source \"%s\""):format(t.value), t)
    end
    if t.kind == "end" then Fail("The formula ends too early") end
    Fail(("Unexpected \"%s\""):format(tostring(t.value)), t)
  end

  local function Term()
    local left = Primary()
    while Peek().kind == "*" or Peek().kind == "/" do
      local op = Take().kind
      left = Arith(op, left, Primary())
    end
    return left
  end

  Expr = function()
    local left = Term()
    while Peek().kind == "+" or Peek().kind == "-" do
      local op = Take().kind
      left = Arith(op, left, Term())
    end
    return left
  end

  local e = Expr()
  if Peek().kind ~= "end" then Fail(("Unexpected \"%s\""):format(tostring(Peek().value)), Peek()) end
  return e
end

-- Compiled formulas by text. Cleared when custom prices change (a name
-- may now mean something else).
local cache = {}

-- Returns fn(itemID) -> copper or nil, or nil and what is wrong.
function F.Compile(text)
  text = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if text == "" then return nil, "The formula is empty." end
  local hit = cache[text]
  if hit then return hit end
  local tokens, err = Tokenize(text)
  if not tokens then return nil, err end
  local ok, res = pcall(Parse, tokens)
  if not ok then
    return nil, (type(res) == "table" and res.msg or tostring(res)) .. "."
  end
  local fn = function(itemID, depth)
    local v = res(itemID, depth or 0)
    if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return nil end
    return math.floor(v + 0.5)
  end
  cache[text] = fn
  return fn
end

-- Copper for an item, or nil (and an error when the formula is wrong).
function F.Evaluate(text, itemID)
  local fn, err = F.Compile(text)
  if not fn then return nil, err end
  return fn(itemID)
end

-- A custom price's value for an item.
function F.Custom(name, itemID, depth)
  depth = depth or 0
  if depth > MAX_DEPTH then return nil end
  local text = name and Customs()[tostring(name):lower()]
  if not text then return nil end
  local fn = F.Compile(text)
  return fn and fn(itemID, depth + 1) or nil
end

-- Checks a name for a new custom price. Returns the clean name or nil, error.
function F.CheckName(name)
  name = tostring(name or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  if not name:find("^%a[%w_]*$") then
    return nil, "A name is letters, digits and _, and starts with a letter."
  end
  if ALIASES[name] or OLD_ALIASES[name] or FUNCTIONS[name] or API.HasPriceSource(name) then
    return nil, ("\"%s\" is already a price source or function."):format(name)
  end
  return name
end

-- Saves (or replaces) a custom price. Returns true or nil, error.
function F.SetCustom(name, formula)
  local clean, err = F.CheckName(name)
  if not clean then return nil, err end
  local fn
  fn, err = F.Compile(formula)
  if not fn then return nil, err end
  Customs()[clean] = tostring(formula):gsub("^%s+", ""):gsub("%s+$", "")
  wipe(cache)
  -- A loop (a uses b, b uses a) only gives no value; warn about it.
  local probe = F.Custom(clean, 0)
  CM.SendMessage("CM_PRICES_CHANGED")
  return true, probe
end

-- Another profile: names may mean other formulas now.
CM.RegisterMessage(F, "CM_PROFILE_CHANGED", function() wipe(cache) end)

function F.DeleteCustom(name)
  name = tostring(name or ""):lower()
  if not Customs()[name] then return false end
  Customs()[name] = nil
  wipe(cache)
  CM.SendMessage("CM_PRICES_CHANGED")
  return true
end

function F.Customs()
  local list = {}
  for name, formula in pairs(Customs()) do list[#list + 1] = { name = name, formula = formula } end
  table.sort(list, function(a, b) return a.name < b.name end)
  return list
end

-- ------------------------------------------------------------------
-- API (minor 5)
-- ------------------------------------------------------------------
function API.ParsePrice(text)
  local fn, err = F.Compile(text)
  if fn then return true end
  return nil, err
end
API.EvaluatePrice = F.Evaluate            -- (formula, itemID) -> copper | nil, error
API.GetCustomPrices = F.Customs           -- { { name, formula }, ... }
API.SetCustomPrice = F.SetCustom          -- (name, formula) -> true | nil, error
API.DeleteCustomPrice = F.DeleteCustom    -- (name)
function API.GetPriceAliases()
  local out = {}
  for k, v in pairs(ALIASES) do out[k] = v end
  return out
end
