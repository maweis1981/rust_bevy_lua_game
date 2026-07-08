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

PACKS="${PACKS:-catch fireflies forge gallery ponies timedodge}"
LEAN="${LEAN:-0}"

echo ">> main.lua"
cp "$A/scripts/main.lua" "$HERE/main.lua"

echo ">> packs: $PACKS"
rm -rf "$HERE/packs"; mkdir -p "$HERE/packs"
MANIFEST_PACKS=""
SHIP_LUA="$A/scripts/main.lua"
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
if [ "$LEAN" = "1" ]; then
  echo ">> textures (lean: referenced + UI/icon families)"
  # names referenced as literals in the shipped Lua
  REF="$(grep -rhoE '(spawn_sprite|spawn_sheet|set_sprite_image)\([^)]*"[a-z_0-9]+"|icon *= *"[a-z_0-9]+"' $SHIP_LUA 2>/dev/null | grep -oE '"[a-z_0-9]+"' | tr -d '"' | sort -u)"
  for name in $REF; do
    [ -f "$A/textures/$name.png" ] && cp "$A/textures/$name.png" "$HERE/textures/" || true
  done
  # families used via constructed names (forge_up_core, icon_*, r* UI tiles, g* pickups)
  for pat in 'forge_*' 'icon_*' 'rtile' 'rpill' 'rcard' 'rxmark' 'orb' 'brick' 'paddle' 'snakehead' 'snakebody' 'food' 'sparkle' 'meteor' 'gberry' 'gbell' 'gdaisy' 'gleaf' 'gviola' 'gmush' 'btn_back'; do
    cp $A/textures/$pat.png "$HERE/textures/" 2>/dev/null || true
  done
else
  echo ">> textures (all — full collection)"
  cp "$A"/textures/*.png "$HERE/textures/" 2>/dev/null || true
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
