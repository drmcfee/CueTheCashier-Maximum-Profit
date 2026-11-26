-- CueTheCashier History: holds CueTheCashierHistoryDB, the daily price points
-- for the last 30 days. It has no code of its own; CueTheCashier loads it
-- when it scans or needs history (see Data.lua in CueTheCashier).
-- Copyright (C) 2026 Kim. Licensed under the GNU GPL v3 or later; see LICENSE.
CueTheCashierHistoryDB = CueTheCashierHistoryDB or {}
