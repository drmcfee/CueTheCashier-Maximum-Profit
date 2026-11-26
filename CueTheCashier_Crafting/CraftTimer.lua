-- CueTheCashier Crafting: queue timer on the cast bar (0.42.0, Kim).
--
-- When you craft several at once (our Craft button, Blizzard's Create or
-- Create All: anything that calls C_TradeSkillUI.CraftRecipe with a
-- count), a small label next to the cast bar shows how long the whole
-- batch takes: "01:00/02:00" = time spent so far / time for all of them.
-- The total is worked out from the cast time of the craft in progress, so
-- it corrects itself as it goes. It goes away when the batch is done or
-- stops (moving, Escape, out of reagents).
--
-- The label sits on Blizzard's player cast bar. When that bar isn't
-- shown (another addon draws its own), the label stands alone just above
-- the middle of the screen's bottom instead. No rules per addon.
-- Copyright (C) 2026 Kim. Licensed under the GNU GPL v3 or later; see LICENSE.
local _, ns = ...
local CM = CueTheCashier

local T = {}
ns.CraftTimer = T

local frame, label
local batch -- { recipeID, count, done, started, castTime }

local function Clock(sec)
  sec = math.max(0, math.floor((sec or 0) + 0.5))
  local h, m, s = math.floor(sec / 3600), math.floor(sec / 60) % 60, sec % 60
  if h > 0 then return ("%d:%02d:%02d"):format(h, m, s) end
  return ("%02d:%02d"):format(m, s)
end

local function CastBar()
  local bar = _G.PlayerCastingBarFrame or _G.CastingBarFrame
  if bar and bar.IsVisible and bar:IsVisible() then return bar end
end

local function Place()
  local bar = CastBar()
  label:ClearAllPoints()
  if bar then
    -- On the line of the bar's spell name when it has one, at the right.
    local dy = -2
    local text = bar.Text
    if text and text.GetCenter and bar.GetCenter then
      local _, ty = text:GetCenter()
      local _, by = bar:GetCenter()
      if ty and by then dy = ty - by end
    end
    if dy == -2 then
      label:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, dy)
    else
      label:SetPoint("RIGHT", bar, "RIGHT", -4, dy)
    end
  else
    label:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 190)
  end
  T.onBar = bar and true or false
end

-- The current cast, if it is our batch's recipe: seconds left, cast length.
local function CurrentCast()
  if not UnitCastingInfo then return nil end
  local _, _, _, startMS, endMS, _, _, _, spellID = UnitCastingInfo("player")
  if not (startMS and endMS) then return nil end
  if batch and spellID and spellID ~= batch.recipeID then return nil end
  return math.max(0, endMS / 1000 - GetTime()), (endMS - startMS) / 1000
end

local function Update()
  if not batch then return end
  local now = GetTime()
  local elapsed = now - batch.started
  local left, length = CurrentCast()
  if length and length > 0 then batch.castTime = length end
  -- Nothing cast for a while: the batch has ended some other way.
  if left then batch.idle = nil
  else
    batch.idle = batch.idle or now
    if now - batch.idle > 3 then T.Stop("no cast for 3 s") return end
  end
  local text
  if batch.castTime then
    local remaining = batch.count - batch.done
    local total
    if left then
      total = elapsed + left + math.max(0, remaining - 1) * batch.castTime
    else
      total = elapsed + remaining * batch.castTime
    end
    text = Clock(elapsed) .. "/" .. Clock(total)
  else
    text = Clock(elapsed) .. "/--:--"
  end
  if not T.onBar then text = ("Crafting %d/%d  %s"):format(math.min(batch.done + 1, batch.count), batch.count, text) end
  label:SetText(text)
end

local function Build()
  frame = CreateFrame("Frame", "CueTheCashierCraftTimer", UIParent)
  frame:SetFrameStrata("HIGH")
  frame:SetSize(1, 1)
  frame:SetPoint("CENTER")
  label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  T.label = label
  local tick, placed = 0, 0
  frame:SetScript("OnUpdate", function(_, dt)
    tick, placed = tick + dt, placed + dt
    if placed > 1 then placed = 0; Place() end -- the cast bar can come and go
    if tick >= 0.2 then tick = 0; Update() end
  end)
  frame:Hide()
end

function T.Stop(why)
  if not batch then return end
  CM.Debug(("Craft timer: stopped (%s) after %d of %d, %s."):format(why or "?", batch.done, batch.count,
    Clock(GetTime() - batch.started)))
  batch = nil
  if frame then frame:Hide() end
end

-- A batch was started. Only batches of 2 or more get a timer.
function T.Start(recipeID, count)
  count = tonumber(count) or 1
  if not recipeID or count < 2 then T.Stop("single craft"); return end
  if not frame then Build() end
  batch = { recipeID = recipeID, count = count, done = 0, started = GetTime() }
  Place()
  Update()
  frame:Show()
  CM.Debug(("Craft timer: %d x recipe %d."):format(count, recipeID))
end

function T.SpellDone(spellID)
  if not (batch and spellID == batch.recipeID) then return end
  batch.done = batch.done + 1
  if batch.done >= batch.count then T.Stop("done") end
end

function T.SpellStopped(spellID)
  if batch and spellID == batch.recipeID then
    -- Interrupted or failed: the rest of the batch won't be made.
    local b = batch
    C_Timer.After(0.3, function()
      if batch == b and not CurrentCast() then T.Stop("cast interrupted") end
    end)
  end
end

function T.Hook()
  if T.hooked or not (C_TradeSkillUI and C_TradeSkillUI.CraftRecipe) then return end
  T.hooked = true
  -- A post-hook: runs after Blizzard's function, changes nothing in it.
  hooksecurefunc(C_TradeSkillUI, "CraftRecipe", function(recipeID, count)
    ns.Safe("Craft timer", T.Start, recipeID, count)
  end)
end
