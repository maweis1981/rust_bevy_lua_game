#!/bin/sh
# prepare.sh — assemble the fengari runtime bundle from the single Lua source.
# Copies the UNMODIFIED assets/scripts/main.lua + shippable packs + the textures
# and audio they reference into this directory, and writes manifest.json (the
# pack load order; main.lua loads last). Re-run whenever the Lua or assets change
# — the runtime (engine.js) is fixed; only these assets are refreshed.
#
#   sh miniprogram/tiktok-lua/prepare.sh
set -e

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
A="$ROOT/assets"

# Packs to ship. `showcase` is excluded on purpose: it is the engine tech-demo
# and the ONLY pack using rigs/sheets/tilemap/cam — heavy features the Canvas
# runtime only stubs. Every other pack uses the core+juice surface that this
# runtime implements for real.
PACKS="catch fireflies forge gallery ponies timedodge"

echo ">> main.lua"
cp "$A/scripts/main.lua" "$HERE/main.lua"

echo ">> packs: $PACKS"
rm -rf "$HERE/packs"; mkdir -p "$HERE/packs"
MANIFEST_PACKS=""
for p in $PACKS; do
  src="$A/scripts/packs/$p.lua"
  if [ -f "$src" ]; then
    cp "$src" "$HERE/packs/$p.lua"
    MANIFEST_PACKS="$MANIFEST_PACKS\"packs/$p.lua\","
  else
    echo "   (skip missing $p)"
  fi
done

echo ">> textures (all — small procedural PNGs)"
rm -rf "$HERE/textures"; mkdir -p "$HERE/textures"
cp "$A"/textures/*.png "$HERE/textures/" 2>/dev/null || true

echo ">> audio (SFX + music the shipped packs reference)"
rm -rf "$HERE/audio"; mkdir -p "$HERE/audio"
# SFX are tiny; music/voice are larger. showcase.wav is skipped with its pack.
for w in hit score wall music garden forge_theme forge_hi forge_menu ponies gallery vo_coach vo_ol vo_teacher; do
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
echo "Bundle ready in $HERE"
echo "  Lua source: main.lua + packs/  (byte-for-byte the native scripts)"
echo "  assets:     textures/  audio/"
du -sh "$HERE/textures" "$HERE/audio" 2>/dev/null || true
echo "Serve this dir and open index.html (or package for TikTok via package-tiktok.sh)."
