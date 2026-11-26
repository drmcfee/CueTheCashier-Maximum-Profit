-- CueTheCashier: auction house fees.
--
-- Forever (seen by Kim, 25 Nov): the auction house keeps 5% of a sale, and
-- the deposit is about 20% of the item's vendor sell price. The neutral
-- (goblin) auction houses take more; 15% is the classic rate and is a guess
-- until it is checked in game.
--
-- Which kind of auction house you use is noticed when one opens and
-- remembered, so prices away from the auction house use the last one.
--
-- Price sources: auction.cut (market value x cut) and auction.deposit
-- (vendor sell price x deposit rate), per item.
-- Copyright (C) 2026 Kim. Licensed under the GNU GPL v3 or later; see LICENSE.
local _, CM = ...

local Fees = {}
CM.Fees = Fees

Fees.CUT = 0.05
Fees.NEUTRAL_CUT = 0.15 -- not checked on Forever yet
Fees.DEPOSIT = 0.20
Fees.NEUTRAL_DEPOSIT = 0.20 -- not checked on Forever yet

-- Places with a neutral auction house (English and their sub zones).
local NEUTRAL_ZONES = { ["Booty Bay"] = true, ["Gadgetzan"] = true, ["Everlook"] = true }

-- true when the auction house in front of you is a neutral one.
function Fees.DetectNeutral()
  local faction = UnitFactionGroup and UnitFactionGroup("npc")
  if faction == "Alliance" or faction == "Horde" then return false end
  local sub = GetSubZoneText and GetSubZoneText() or ""
  local zone = GetZoneText and GetZoneText() or ""
  if NEUTRAL_ZONES[sub] or NEUTRAL_ZONES[zone] then return true end
  -- A neutral NPC outside the known towns counts as neutral too.
  return faction == "Neutral"
end

function Fees.IsNeutral() return CM.Settings().lastAHNeutral == true end

function Fees.CutRate() return Fees.IsNeutral() and Fees.NEUTRAL_CUT or Fees.CUT end
function Fees.DepositRate() return Fees.IsNeutral() and Fees.NEUTRAL_DEPOSIT or Fees.DEPOSIT end

-- Deposit for a stack (copper); hours does not change it on Forever as far as seen.
function Fees.Deposit(itemID, count)
  local sell = CM.Data:GetVendorPrice(itemID)
  if not sell then return nil end
  return math.floor(sell * (count or 1) * Fees.DepositRate() + 0.5)
end

CM.RegisterEvent(Fees, "AUCTION_HOUSE_SHOW", function()
  local neutral = Fees.DetectNeutral()
  CM.Settings().lastAHNeutral = neutral
  CM.Debug(("Auction house: %s (cut %d%%)"):format(neutral and "neutral" or "faction", Fees.CutRate() * 100))
end)

local API = CM.API
API.GetAuctionCutRate = Fees.CutRate         -- () -> 0.05 or 0.15 (minor 8)
API.GetAuctionDepositRate = Fees.DepositRate -- () -> 0.20 (minor 8)
API.IsNeutralAuctionHouse = Fees.IsNeutral   -- () -> bool, last auction house opened (minor 8)
API.GetAuctionDeposit = Fees.Deposit         -- (itemID, [count]) -> copper (minor 8)

API.RegisterPriceSource("auction.cut", { label = "Auction house cut",
  get = function(id)
    local v = API.GetPrice(id, "auction.market")
    return v and math.floor(v * Fees.CutRate() + 0.5)
  end,
  description = "What the auction house keeps when one sells at market value (5%, 15% at a neutral auction house)." })
API.RegisterPriceSource("auction.deposit", { label = "Auction deposit",
  get = function(id) return Fees.Deposit(id, 1) end,
  description = "Deposit to post one, lost if it doesn't sell (about 20% of the vendor sell price)." })
