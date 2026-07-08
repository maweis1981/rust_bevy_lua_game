#!/bin/sh
# new_game.sh <key> — scaffold a playable Lua game pack from tools/templates/.
# Produces assets/scripts/packs/<key>.lua (self-registering into the menu) and,
# because the web build can't scan the filesystem, registers it in the wasm pack
# list in src/script.rs. Native (desktop/iOS/Android) auto-discovers the file.
#   make new-game NAME=asteroids
set -e

KEY="$1"
if [ -z "$KEY" ]; then
  echo "usage: make new-game NAME=<key>   (lowercase, [a-z0-9_], starts with a letter)"; exit 1
fi
if ! echo "$KEY" | grep -qE '^[a-z][a-z0-9_]*$'; then
  echo "error: NAME must be lowercase [a-z0-9_] and start with a letter (got: $KEY)"; exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMPL="$ROOT/tools/templates/pack.lua.tmpl"
DEST="$ROOT/assets/scripts/packs/$KEY.lua"
[ -f "$DEST" ] && { echo "error: $DEST already exists — aborting"; exit 1; }

# Title-case label from the key: my_cool_game -> My Cool Game
LABEL="$(echo "$KEY" | sed 's/_/ /g' | awk '{for(i=1;i<=NF;i++)$i=toupper(substr($i,1,1)) substr($i,2)}1')"
# slot = (#existing packs) + 20, so new games sort after the curated ones
SLOT=$(( $(ls "$ROOT/assets/scripts/packs"/*.lua 2>/dev/null | wc -l) + 20 ))

sed -e "s/__KEY__/$KEY/g" -e "s/__LABEL__/$LABEL/g" -e "s/__SLOT__/$SLOT/" "$TMPL" > "$DEST"
echo "created  $DEST"

# Register in the wasm pack list (native auto-discovers; web needs it explicit).
if grep -q "PACKS_DIR}/$KEY.lua" "$ROOT/src/script.rs"; then
  echo "wasm list already has $KEY"
else
  awk -v key="$KEY" '
    /#\[cfg\(target_arch = "wasm32"\)\]/ { inwasm = 1 }
    inwasm && /^    \]$/ && !done { print "        format!(\"{PACKS_DIR}/" key ".lua\"),"; done = 1 }
    { print }
  ' "$ROOT/src/script.rs" > "$ROOT/src/script.rs.tmp" && mv "$ROOT/src/script.rs.tmp" "$ROOT/src/script.rs"
  echo "registered $KEY in the wasm pack list (src/script.rs)"
fi

echo ""
echo "Done. Next:"
echo "  - edit $DEST  (replace update() with your mechanic)"
echo "  - make run           # play on desktop (Lua hot-reloads)"
echo "  - make web-serve     # play in the browser"
