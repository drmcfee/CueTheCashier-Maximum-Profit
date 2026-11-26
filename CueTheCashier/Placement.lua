-- CueTheCashier: keeping our buttons and windows out of other addons' way.
--
-- We add buttons to Blizzard windows (bank, merchant, mailbox, profession
-- window) and dock the Crafting List next to the profession window. Other
-- addons (ElvUI skins, MasterCraft, ...) put their own things in the same
-- places. So each of our parts gets a list of spots, best first. A short
-- moment after the window opens (other addons attach theirs first), we
-- check the spots in order and use the first one that covers nothing:
--   * buttons and boxes inside the Blizzard window (theirs or Blizzard's),
--   * frames of other addons anchored to that window (docked panels).
-- No rules per addon. When no spot is free, the first one is used and the
-- debug log gets a quiet note; nothing is printed to chat.
--
-- CM.Place.Attach(frame, host, spots, opts) for a part that lives on a
-- window: placed now (first spot) and checked every time the window opens.
-- CM.Place.Fit(frame, host, spots, opts) for one placement (e.g. docking).
-- spots: { { point, relativeTo, relativePoint, x, y }, ... }; relativeTo
-- may be a function (returns a frame, or nil to skip that spot).
-- opts.also: more of our frames that move with it (counted in its area).
-- opts.name: shown in the log. opts.delay: seconds to wait (default 0.3).
-- Copyright (C) 2026 Kim. Licensed under the GNU GPL v3 or later; see LICENSE.
local _, CM = ...

local P = {}
CM.Place = P

P.DELAY = 0.3
P.RECHECK = 1.5 -- once more, for addons that attach late
local MAX_DEPTH = 5

local function Call(f, method, ...)
  local fn = f and f[method]
  if type(fn) ~= "function" then return nil end
  local ok, a, b, c, d, e = pcall(fn, f, ...)
  if ok then return a, b, c, d, e end
end

-- Screen rect (left, bottom, right, top) in one common scale.
local function Rect(f)
  local l, b, w, h = Call(f, "GetRect")
  if not (l and b and w and h) or w <= 0 or h <= 0 then return nil end
  local s = Call(f, "GetEffectiveScale") or 1
  return { l * s, b * s, (l + w) * s, (b + h) * s }
end

local function Overlap(a, b)
  local w = math.min(a[3], b[3]) - math.max(a[1], b[1])
  local h = math.min(a[4], b[4]) - math.max(a[2], b[2])
  return w > 2 and h > 2
end

local function Area(r) return (r[3] - r[1]) * (r[4] - r[2]) end

-- true when f is x or inside x.
local function Inside(f, x)
  local depth = 0
  while f and depth < 30 do
    if f == x then return true end
    f = Call(f, "GetParent")
    depth = depth + 1
  end
  return false
end

local function Visible(f)
  if Call(f, "IsForbidden") then return false end
  return Call(f, "IsVisible") and (Call(f, "GetEffectiveAlpha") or 1) > 0.05
end

-- Clickable or typable things count; plain art and backgrounds don't.
local function Solid(f)
  if Call(f, "IsMouseEnabled") then return true end
  return Call(f, "IsObjectType", "Button") or Call(f, "IsObjectType", "EditBox") or false
end

-- The things our part must not cover. mine = our frames for this part.
local function Obstacles(host, mine)
  local out = {}
  local hostRect = Rect(host)
  local maxArea = hostRect and Area(hostRect) * 0.25 or math.huge
  local function Ours(f)
    for _, m in ipairs(mine) do
      if Inside(f, m) or Inside(m, f) then return true end
    end
    return false
  end
  -- 1. Inside the window: small solid things (buttons, boxes, tabs).
  local function Walk(f, depth)
    if depth > MAX_DEPTH then return end
    for _, c in ipairs({ Call(f, "GetChildren") }) do
      if type(c) == "table" and Visible(c) and not Ours(c) then
        local r = Rect(c)
        if r and Solid(c) and Area(r) < maxArea then out[#out + 1] = r end
        Walk(c, depth + 1)
      end
    end
  end
  Walk(host, 1)
  -- 2. Other addons' frames docked to the window (anchored to it, not
  --    inside it), e.g. a side panel. Our own windows are left out.
  for _, c in ipairs({ Call(UIParent, "GetChildren") }) do
    if type(c) == "table" and c ~= host and Visible(c) and not Ours(c) then
      local name = Call(c, "GetName")
      if not (name and name:find("^CueTheCashier")) then
        for i = 1, (Call(c, "GetNumPoints") or 0) do
          local _, rel = Call(c, "GetPoint", i)
          if rel and Inside(rel, host) then
            local r = Rect(c)
            if r then out[#out + 1] = r end
            break
          end
        end
      end
    end
  end
  -- 3. Other addons' frames that sit right next to the window without
  --    being anchored to it (e.g. a bar of profession tabs placed by
  --    position, seen in game 0.41): anything smaller than the window
  --    whose edge touches it. Plain frames count here, not only buttons.
  if hostRect then
    local grown = { hostRect[1] - 6, hostRect[2] - 6, hostRect[3] + 6, hostRect[4] + 6 }
    for _, c in ipairs({ Call(UIParent, "GetChildren") }) do
      if type(c) == "table" and c ~= host and Visible(c) and not Ours(c) and not Inside(c, host) then
        local name = Call(c, "GetName")
        if not (name and name:find("^CueTheCashier")) then
          local r = Rect(c)
          if r and Area(r) < Area(hostRect) and Overlap(r, grown) and not Overlap(r, hostRect) then
            out[#out + 1] = r
          end
        end
      end
    end
  end
  return out
end

-- A spot that puts the frame (partly) off the screen isn't free.
local function OnScreen(r)
  local s = Rect(UIParent)
  if not s then return true end
  return r[1] >= s[1] - 1 and r[2] >= s[2] - 1 and r[3] <= s[3] + 1 and r[4] <= s[4] + 1
end

local function SetSpot(frame, spot)
  local rel = spot[2]
  if type(rel) == "function" then rel = rel() end
  if spot[2] ~= nil and not rel then return false end
  frame:ClearAllPoints()
  frame:SetPoint(spot[1], rel, spot[3], spot[4] or 0, spot[5] or 0)
  return true
end

-- Checks the spots now. Returns the spot number used and whether it was free.
function P.Check(frame, host, spots, opts)
  opts = opts or {}
  local mine = { frame }
  for _, f in ipairs(opts.also or {}) do mine[#mine + 1] = f end
  local obstacles = Obstacles(host, mine)
  local first
  for i, spot in ipairs(spots) do
    if SetSpot(frame, spot) then
      first = first or i
      local free = true
      for _, m in ipairs(mine) do
        local r = Visible(m) and Rect(m)
        if r and not OnScreen(r) then free = false end
        if r and free then
          for _, o in ipairs(obstacles) do
            if Overlap(r, o) then free = false break end
          end
        end
        if not free then break end
      end
      if free then
        if i > 1 then CM.Debug(("%s moved to spot %d (spot 1 was taken)."):format(opts.name or "Button", i)) end
        return i, true
      end
    end
  end
  if first then
    SetSpot(frame, spots[first])
    CM.Debug(("%s: no free spot, using spot %d."):format(opts.name or "Button", first))
  end
  if not Visible(frame) and Call(frame, "IsShown") then
    CM.Debug(("%s is shown but can't be seen (its window is hidden or covered)."):format(opts.name or "Button"))
  end
  return first, false
end

-- One placement: the first spot right away (no flicker), then the check
-- after a moment, and once more a bit later.
function P.Fit(frame, host, spots, opts)
  if not (frame and host and spots and spots[1]) then return end
  SetSpot(frame, spots[1])
  local function Later()
    if Call(host, "IsShown") then
      local ok, err = pcall(P.Check, frame, host, spots, opts)
      if not ok then CM.Debug("Placement: " .. tostring(err)) end
    end
  end
  if C_Timer and C_Timer.After then
    C_Timer.After((opts and opts.delay) or P.DELAY, Later)
    C_Timer.After(P.RECHECK, Later)
  else
    Later()
  end
end

-- A part that lives on a window: placed every time the window opens.
function P.Attach(frame, host, spots, opts)
  if not (frame and host) then return end
  P.Fit(frame, host, spots, opts)
  if host.HookScript then
    host:HookScript("OnShow", function() P.Fit(frame, host, spots, opts) end)
  end
end
