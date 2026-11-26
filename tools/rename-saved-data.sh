#!/usr/bin/env bash
# One-off: moves CraftMarket saved data to the CueTheCashier names (0.41.0).
# Close the game first. Usage:
#   bash rename-saved-data.sh            (default WoW Forever folder under Wine)
#   bash rename-saved-data.sh "/path/to/World of Warcraft/_forever_"
#
# For each of the five data files it picks the biggest file that holds
# real data (old CraftMarket*.lua, the renamed CueTheCashier*.lua, or
# their .bak copies), shows the plan, asks, then writes CueTheCashier*.lua
# with the variable inside renamed (CraftMarketDB -> CueTheCashierDB, ...).
# A full backup of every SavedVariables folder is made first.
set -euo pipefail

FOREVER="${1:-$HOME/Games/battlenet/drive_c/Program Files (x86)/World of Warcraft/_forever_}"
WTF="$FOREVER/WTF/Account"

if [ ! -d "$WTF" ]; then
  echo "Can't find $WTF"
  echo "Run it with your _forever_ folder: bash $0 \"/path/to/World of Warcraft/_forever_\""
  exit 1
fi

if pgrep -fi "wow.*\.exe|Wow\.exe|WowClassic" >/dev/null 2>&1; then
  echo "The game seems to be running. Close it completely first (it rewrites these files when it exits)."
  exit 1
fi

# suffix of the file name : old variable : new variable
PARTS=(
  ":CraftMarketDB:CueTheCashierDB"
  "_Accounting:CraftMarketAccountingDB:CueTheCashierAccountingDB"
  "_Crafting:CraftMarketCraftingDB:CueTheCashierCraftingDB"
  "_Destroying:CraftMarketDestroyingDB:CueTheCashierDestroyingDB"
  "_History:CraftMarketHistoryDB:CueTheCashierHistoryDB"
)

stamp=$(date +%Y%m%d-%H%M%S)
found=0
for SV in "$WTF"/*/SavedVariables; do
  [ -d "$SV" ] || continue
  found=1
  account=$(basename "$(dirname "$SV")")
  backup="$SV-backup-$stamp"
  cp -a "$SV" "$backup"
  echo
  echo "== Account $account"
  echo "   Backup of the whole folder: $backup"

  plan=()
  for part in "${PARTS[@]}"; do
    IFS=: read -r suffix oldvar newvar <<<"$part"
    best="" bestsize=0
    for f in "$SV/CraftMarket$suffix.lua" "$SV/CraftMarket$suffix.lua.bak" \
             "$SV/CueTheCashier$suffix.lua" "$SV/CueTheCashier$suffix.lua.bak"; do
      [ -f "$f" ] || continue
      grep -qE "^($oldvar|$newvar) = " "$f" || continue
      size=$(stat -c %s "$f")
      if [ "$size" -gt "$bestsize" ]; then best="$f"; bestsize="$size"; fi
    done
    target="$SV/CueTheCashier$suffix.lua"
    if [ -n "$best" ]; then
      echo "   CueTheCashier$suffix.lua  <-  $(basename "$best")  ($bestsize bytes)"
      plan+=("$best|$target|$oldvar|$newvar")
    else
      echo "   CueTheCashier$suffix.lua: no data found, left alone"
    fi
  done

  [ ${#plan[@]} -gt 0 ] || continue
  read -r -p "   Write these files? [y/N] " ok
  if [ "$ok" != "y" ] && [ "$ok" != "Y" ]; then echo "   Skipped."; continue; fi
  for p in "${plan[@]}"; do
    IFS='|' read -r src target oldvar newvar <<<"$p"
    tmp="$target.tmp-$stamp"
    sed -E "s/^$oldvar = /$newvar = /" "$src" > "$tmp"
    mv "$tmp" "$target"
    rm -f "$target.bak"
    echo "   Wrote $(basename "$target") ($(grep -cE "^$newvar = " "$target") x $newvar)"
  done
done

if [ "$found" = 0 ]; then echo "No SavedVariables folder under $WTF"; exit 1; fi
echo
echo "Done. Start the game with CueTheCashier 0.41.0 installed (old CraftMarket folders deleted)."
echo "If anything looks wrong, close the game and copy the backup folder back."
