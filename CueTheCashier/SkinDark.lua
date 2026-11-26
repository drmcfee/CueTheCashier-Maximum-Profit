-- CueTheCashier: the "Dark" skin, and an example of how to make a skin.
-- A skin only lists what it changes; the rest stays Blizzard's (see
-- Skins.lua and SKINS.md). This file uses nothing but the public
-- CueTheCashier.Skins:Register, so a skin addon can be made the same way:
--   ## Dependencies: CueTheCashier   in its .toc, and this code in its .lua.
-- Copyright (C) 2026 Kim. Licensed under the GNU GPL v3 or later; see LICENSE.
local Skins = CueTheCashier.Skins

Skins:Register("Dark", {
  colors = {
    stripe = { 1, 1, 1, 0.04 },
    highlight = { 0.35, 0.65, 1, 0.15 },
    selected = { 0.35, 0.65, 1, 0.25 },
    chartBar = { 0.35, 0.65, 1, 0.85 },
  },
  window = { background = { 0.04, 0.04, 0.06, 0.9 } },
  progressBar = { color = { 0.25, 0.55, 0.95 } },
})
