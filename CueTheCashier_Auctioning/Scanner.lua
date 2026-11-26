-- CueTheCashier: full auction house scan.
-- Uses C_AuctionHouse.ReplicateItems, which asks the server for a snapshot of
-- every auction at once. Blizzard allows this about once per 15 minutes per
-- account, so we track the cooldown ourselves.
-- Copyright (C) 2026 Kim. Licensed under the GNU GPL v3 or later; see LICENSE.
local _, ns = ...
local CM = CueTheCashier
local API = CM.API

local Scanner = {
  state = "idle",       -- idle | waiting | processing
  progress = 0,         -- 0..1 while processing
  callbacks = {},
}
ns.Scanner = Scanner

-- How many auctions to read per frame. Keeps the game from freezing on big
-- auction houses. Lower it if scanning stutters.
local ROWS_PER_FRAME = 1000
-- Give up if the server never answers.
local WAIT_TIMEOUT = 60

function Scanner:OnChange(fn)
  self.callbacks[#self.callbacks + 1] = fn
end

local function Notify(self)
  for _, fn in ipairs(self.callbacks) do fn(self.state, self.progress) end
end

-- The cooldown is account-wide saved data, so the core keeps it.
function Scanner:CooldownRemaining()
  return API.GetFullScanCooldown()
end

function Scanner:CooldownText()
  return CM.FullScanCooldownText()
end

function Scanner:CanScan(force)
  if self.state ~= "idle" then return false, "A scan is already running." end
  if not (AuctionHouseFrame and AuctionHouseFrame:IsShown()) then
    return false, "Open the auction house first."
  end
  if not (C_AuctionHouse and C_AuctionHouse.ReplicateItems) then
    return false, "This client has no full-scan API (C_AuctionHouse.ReplicateItems)."
  end
  if self:CooldownRemaining() > 0 and not force then
    return false, "Full scan is on cooldown for " .. self:CooldownText() .. "."
  end
  return true
end

-- Must be called from a player click (Blizzard rule for AH actions).
-- force (debug only) skips our own 15 minute timer. The server still has its
-- own limit, so a forced scan may simply get no answer.
function Scanner:Start(force)
  force = force and CM.IsDebug()
  -- The log no longer opens by itself (0.42.0, Kim): /cmp log shows it.
  CM.Debug("--- Full scan" .. (force and " (forced, our timer skipped)" or "") .. " ---")
  local ok, why = self:CanScan(force)
  if not ok then CM.Print(why); return false end

  self.state = "waiting"
  self.progress = 0
  self.startedAt = GetTime()
  CM.MarkFullScan()
  ns.module:RegisterEvent("REPLICATE_ITEM_LIST_UPDATE", Scanner.OnReplicateUpdate)
  CM.Debug("Calling C_AuctionHouse.ReplicateItems()")
  C_AuctionHouse.ReplicateItems()
  CM.Print("Full scan requested. This can take a few seconds.")
  Notify(self)

  local startedAt = self.startedAt
  C_Timer.After(WAIT_TIMEOUT, function()
    if self.state ~= "waiting" or self.startedAt ~= startedAt then return end
    -- No usable answer event. Read the list directly in case the data is
    -- there anyway.
    local _, n = CM.Try("GetNumReplicateItems() after timeout", C_AuctionHouse.GetNumReplicateItems)
    if (tonumber(n) or 0) > 0 then
      self:Process()
    else
      CM.Print("The server did not send scan results. Try again after the cooldown.")
      self:Stop()
    end
  end)
  return true
end

function Scanner:Stop()
  ns.module:UnregisterEvent("REPLICATE_ITEM_LIST_UPDATE")
  self.state = "idle"
  self.progress = 0
  self.results = nil
  Notify(self)
end

-- Reads auctions in chunks, keeping the lowest buyout per single item.
local ProcessUnsafe
function Scanner:Process()
  local ok, err = pcall(ProcessUnsafe, self)
  if not ok then
    CM.Print("Full scan crashed while reading results: " .. tostring(err))
    self:Stop()
  end
end

function ProcessUnsafe(self)
  ns.module:UnregisterEvent("REPLICATE_ITEM_LIST_UPDATE")
  self.state = "processing"
  local total = C_AuctionHouse.GetNumReplicateItems() or 0
  CM.Debug("Reading replicate list, GetNumReplicateItems() = " .. tostring(total))
  if total > 0 then
    CM.Debug("First row:", { C_AuctionHouse.GetReplicateItemInfo(0) })
    CM.Debug("First row link: " .. tostring(C_AuctionHouse.GetReplicateItemLink
      and C_AuctionHouse.GetReplicateItemLink(0)))
  end
  local stats = { noID = 0, idFromLink = 0, notAllInfo = 0, bidOnly = 0 }
  self.stats = stats
  local results = {}
  self.results = results
  local index = 0 -- replicate indexes start at 0

  local Step
  local function StepUnsafe()
    local last = math.min(index + ROWS_PER_FRAME, total) - 1
    for i = index, last do
      -- Returns: name, texture, count, qualityID, usable, level, levelType,
      -- minBid, minIncrement, buyoutPrice, bidAmount, highBidder, bidderName,
      -- owner, ownerFullName, saleStatus, itemID, hasAllInfo
      local name, _, count, quality, _, level, _, _, _, buyout, _, _, _, owner, _, _, itemID, hasAllInfo =
        C_AuctionHouse.GetReplicateItemInfo(i)
      if not hasAllInfo then stats.notAllInfo = stats.notAllInfo + 1 end
      if not itemID then
        -- Item data not loaded yet: the link may still carry the ID.
        local link = C_AuctionHouse.GetReplicateItemLink and C_AuctionHouse.GetReplicateItemLink(i)
        itemID = link and tonumber(link:match("item:(%d+)"))
        if itemID then stats.idFromLink = stats.idFromLink + 1
        else stats.noID = stats.noID + 1 end
      end
      if not buyout or buyout <= 0 then stats.bidOnly = stats.bidOnly + 1 end
      -- Bid-only auctions have buyout 0 and are skipped.
      -- GUESS: buyoutPrice is for the whole stack, as on retail.
      if itemID and buyout and buyout > 0 then
        count = (count and count > 0) and count or 1
        local r = results[itemID]
        if not r then
          r = { prices = {}, owners = {}, sellers = 0 }
          results[itemID] = r
        end
        local p = r.prices
        p[#p + 1] = math.floor(buyout / count)
        p[#p + 1] = count
        if owner and owner ~= "" and not r.owners[owner] then
          r.owners[owner] = true
          r.sellers = r.sellers + 1
        end
        if hasAllInfo and not r.info and name then
          r.info = { name = name, quality = quality, level = level }
        end
      end
    end
    index = last + 1
    self.progress = total > 0 and index / total or 1
    Notify(self)
    if index < total then
      C_Timer.After(0, Step)
    else
      self:Finish(results, total)
    end
  end
  Step = function()
    if self.results ~= results then return end -- stopped or restarted
    local ok, err = pcall(StepUnsafe)
    if not ok then
      CM.Print("Full scan crashed while reading row " .. index .. ": " .. tostring(err))
      self:Stop()
    end
  end
  Step()
end

function Scanner:Finish(results, total)
  for _, r in pairs(results) do r.owners = nil end -- not saved
  local count = API.RecordScan(results, "full", total)
  CM.Print(("Scan done: %d auctions, %d different items."):format(total, count))
  if self.stats then
    CM.Debug(("Rows without full item info: %d. IDs taken from link: %d. Rows with no ID at all (skipped): %d. Bid-only rows (skipped): %d.")
      :format(self.stats.notAllInfo, self.stats.idFromLink, self.stats.noID, self.stats.bidOnly))
  end
  self.results = nil
  self.state = "idle"
  self.progress = 1
  Notify(self)
end

-- Events (registered through the module, see Module.lua).
function Scanner.OnReplicateUpdate()
  local n = C_AuctionHouse.GetNumReplicateItems() or 0
  CM.Debug("REPLICATE_ITEM_LIST_UPDATE, GetNumReplicateItems() = " .. n)
  if Scanner.state ~= "waiting" then return end
  if n > 0 then
    Scanner:Process()
  else
    -- GUESS: an empty first answer can come before the real data.
    CM.Debug("List is empty, waiting for another update.")
  end
end

function Scanner.OnAuctionHouseClosed()
  if Scanner.state ~= "idle" then
    CM.Print("Auction house closed, scan stopped.")
    Scanner:Stop()
  end
end
