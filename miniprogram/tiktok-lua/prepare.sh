#!/bin/sh
# prepare.sh — assemble the fengari runtime bundle from the single Lua source.
# Copies the UNMODIFIED assets/scripts/main.lua + shippable packs + the textures
# and audio they reference into this directory, and writes manifest.json (the
# pack load order; main.lua loads last). Re-run whenever the Lua or assets change
# — the runtime (engine.js) is fixed; only these assets are refreshed.
#
#   sh prepare.sh                 # dev bundle: full collection, all assets
#   PACKS="catch forge" LEAN=1 sh prepare.sh   # lean ship (arcade set, SFX+music)
#
# Env overrides:
#   PACKS  — space-separated pack keys to ship (default: the full playable set).
#            `showcase` is never shippable here: it is the engine tech-demo and
#            the ONLY pack using rigs/sheets/tilemap/cam — heavy features the
#            Canvas runtime only stubs. Everything else uses the core+juice
#            surface this runtime implements for real.
#   LEAN=1 — audio: SFX + music.wav only (drop large pack BGM/voice); textures:
#            only those the shipped Lua references (+ common UI/icon families).
#            Used by package-tiktok.sh to stay well under TikTok's size budget.
set -e

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
A="$ROOT/assets"

# EXTRA = the curated top-level game scripts (src/script.rs EXTRA_SCRIPTS). Like
# packs, they load BEFORE main.lua and self-register into PACKS. All are core+juice
# arcade games — kept in sync with the native list. PACKS = the drop-in packs.
# `-` (not `:-`) so an explicitly-empty EXTRA="" / PACKS="" means "none" (used by
# the standalone single-game package), while unset falls back to the full set.
EXTRA="${EXTRA-roguelike game2048 shooter world craftworld match3 umami}"
PACKS="${PACKS-catch fireflies forge gallery ponies timedodge}"
LEAN="${LEAN:-0}"

echo ">> main.lua"
cp "$A/scripts/main.lua" "$HERE/main.lua"

# All modules that load before main.lua, in native order: EXTRA then packs. Each
# is copied into the bundle and listed (in this order) in manifest.json.
MANIFEST_PACKS=""
SHIP_LUA="$A/scripts/main.lua"

echo ">> games (top-level): $EXTRA"
rm -rf "$HERE/games"; mkdir -p "$HERE/games"
for p in $EXTRA; do
  src="$A/scripts/$p.lua"
  if [ -f "$src" ]; then
    cp "$src" "$HERE/games/$p.lua"
    MANIFEST_PACKS="$MANIFEST_PACKS\"games/$p.lua\","
    SHIP_LUA="$SHIP_LUA $src"
  else
    echo "   (skip missing $p)"
  fi
done

echo ">> packs: $PACKS"
rm -rf "$HERE/packs"; mkdir -p "$HERE/packs"
for p in $PACKS; do
  src="$A/scripts/packs/$p.lua"
  if [ -f "$src" ]; then
    cp "$src" "$HERE/packs/$p.lua"
    MANIFEST_PACKS="$MANIFEST_PACKS\"packs/$p.lua\","
    SHIP_LUA="$SHIP_LUA $src"
  else
    echo "   (skip missing $p)"
  fi
done

rm -rf "$HERE/textures"; mkdir -p "$HERE/textures"
# Always copy everything, then (LEAN) prune only the big visual-novel/backdrop
# families the arcade ship doesn't use. This is robust: textures referenced via
# the KIT `T.sprite("name")` wrapper or via a variable icon (which a literal grep
# would miss, e.g. timedodge's "rockball"/"gem"/icon_*) are never dropped.
cp "$A"/textures/*.png "$HERE/textures/" 2>/dev/null || true
if [ "$LEAN" = "1" ]; then
  echo ">> textures (lean: all minus the big VN/backdrop families the arcade set never uses)"
  # Only the visual-novel packs (gallery/ponies — excluded from the arcade ship)
  # reference these; the arcade games do not. Verified against the shipped Lua.
  for pat in 'bg_*' 'arena_*' 'vg_*' 'decor_*' 'ground_*'; do
    rm -f $HERE/textures/$pat.png 2>/dev/null || true
  done
else
  echo ">> textures (all — full collection)"
fi

rm -rf "$HERE/audio"; mkdir -p "$HERE/audio"
if [ "$LEAN" = "1" ]; then
  echo ">> audio (lean: SFX + music)"
  AUDIO="hit score wall music"
else
  echo ">> audio (full: SFX + music + pack BGM/voice)"
  AUDIO="hit score wall music garden forge_theme forge_hi forge_menu ponies gallery vo_coach vo_ol vo_teacher"
fi
for w in $AUDIO; do
  [ -f "$A/audio/$w.wav" ] && cp "$A/audio/$w.wav" "$HERE/audio/" || true
done

# manifest.json — the runtime fetches this, loads each pack (self-register into
# PACKS), then main.lua (reads PACKS in on_start). Trailing comma trimmed.
PACKS_JSON="$(printf '%s' "$MANIFEST_PACKS" | sed 's/,$//')"
cat > "$HERE/manifest.json" <<EOF
{
  "packs": [$PACKS_JSON],
  "main": "main.lua"
}
EOF

echo ""
echo "Bundle ready in $HERE  (LEAN=$LEAN)"
echo "  Lua source: main.lua + packs/  (byte-for-byte the native scripts)"
du -sh "$HERE/textures" "$HERE/audio" 2>/dev/null || true
echo "Serve this dir and open index.html (or package for TikTok via package-tiktok.sh)."
