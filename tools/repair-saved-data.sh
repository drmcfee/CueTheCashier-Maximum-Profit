#!/usr/bin/env bash
# One-off repair for the CraftMarket -> CueTheCashier rename (0.41.0).
# Close the game first. Usage:
#   bash repair-saved-data.sh            (default WoW Forever folder under Wine)
#   bash repair-saved-data.sh "/path/to/World of Warcraft/_forever_"
#
# A saved file can now hold the same data twice (a new, empty one and the
# old, full one). This looks at EVERY copy it can find for each data file:
# the current files, the .bak files, old CraftMarket*.lua files and all
# SavedVariables-backup-* folders. From all of them it takes the single
# biggest data block (CraftMarket...DB or CueTheCashier...DB) and writes a
# clean CueTheCashier*.lua that holds only that block, under the new name.
# It shows the plan and asks first, and makes one more backup.
set -euo pipefail

FOREVER="${1:-$HOME/Games/battlenet/drive_c/Program Files (x86)/World of Warcraft/_forever_}"
WTF="$FOREVER/WTF/Account"
[ -d "$WTF" ] || { echo "Can't find $WTF"; exit 1; }

PARTS=(
  ":CraftMarketDB:CueTheCashierDB"
  "_Accounting:CraftMarketAccountingDB:CueTheCashierAccountingDB"
  "_Crafting:CraftMarketCraftingDB:CueTheCashierCraftingDB"
  "_Destroying:CraftMarketDestroyingDB:CueTheCashierDestroyingDB"
  "_History:CraftMarketHistoryDB:CueTheCashierHistoryDB"
)

# Prints the size of the biggest block of oldvar/newvar in a file, and
# writes that block (renamed) to $2. A block runs from "Name = " at the
# start of a line to the next top-level "Name = " line.
extract() { # file out oldvar newvar -> prints bytes
  awk -v old="$3" -v new="$4" -v out="$2" '
    function flush() {
      if (cur != "" && length(buf) > best) { best = length(buf); keep = buf }
      buf = ""; cur = ""
    }
    /^[A-Za-z_][A-Za-z0-9_]* = / {
      flush()
      name = $1
      if ((name == old || name == new) && $0 !~ / = nil$/) { cur = name; sub("^" name, new) }
    }
    { if (cur != "") buf = buf $0 "\n" }
    END { flush(); if (best > 0) printf "%s", keep > out; print best + 0 }
  ' "$1"
}

stamp=$(date +%Y%m%d-%H%M%S)
for SV in "$WTF"/*/SavedVariables; do
  [ -d "$SV" ] || continue
  acc=$(dirname "$SV")
  echo; echo "== Account $(basename "$acc")"
  work=$(mktemp -d)
  plan=()
  for part in "${PARTS[@]}"; do
    IFS=: read -r suffix oldvar newvar <<<"$part"
    best=0 bestfrom=""
    while IFS= read -r -d '' f; do
      n=$(extract "$f" "$work/cand" "$oldvar" "$newvar")
      if [ "$n" -gt "$best" ]; then best=$n; bestfrom=$f; cp "$work/cand" "$work/best$suffix"; fi
    done < <(find "$acc" -path "$acc/SavedVariables*" -type f \
               \( -name "CraftMarket$suffix.lua*" -o -name "CueTheCashier$suffix.lua*" \) -print0)
    if [ "$best" -gt 0 ]; then
      echo "   CueTheCashier$suffix.lua  <-  ${bestfrom#$acc/}  ($best bytes of data)"
      plan+=("$suffix")
    else
      echo "   CueTheCashier$suffix.lua: no data anywhere, left alone"
    fi
  done
  if [ ${#plan[@]} -gt 0 ]; then
    read -r -p "   Write these files? [y/N] " ok
    if [ "$ok" = "y" ] || [ "$ok" = "Y" ]; then
      cp -a "$SV" "$SV-backup-$stamp"
      echo "   Extra backup: SavedVariables-backup-$stamp"
      for suffix in "${plan[@]}"; do
        cp "$work/best$suffix" "$SV/CueTheCashier$suffix.lua"
        rm -f "$SV/CueTheCashier$suffix.lua.bak"
        echo "   Wrote CueTheCashier$suffix.lua"
      done
    else
      echo "   Skipped."
    fi
  fi
  rm -rf "$work"
done
echo
echo "Done. Start the game (CueTheCashier 0.41.0, no CraftMarket folders)."
