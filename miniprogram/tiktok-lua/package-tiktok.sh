#!/bin/sh
# package-tiktok.sh — assemble a TikTok Mini Games (TTMinis HTML runtime) upload
# bundle from the fengari runtime. Output: miniprogram/tiktok-lua/dist/tiktok/.
#
# The bundle is the SAME engine.js + fengari + native Lua that the browser
# runtime uses, plus the TTMinis-aware index.html and the three config files the
# DevTools validator requires (game.json, minigame.config.json,
# project.config.json). Zip dist/tiktok/ (or point the TikTok DevTools at it).
#
#   sh miniprogram/tiktok-lua/package-tiktok.sh
set -e

HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$HERE/dist/tiktok"

# TikTok ships the tight ARCADE set — the games that fit a vertical, tap-first,
# viral audience. The visual-novel packs (ponies, gallery) and the tech-demo
# (showcase) are excluded here (they stay in web/native's full collection); that
# also drops their heavy VN backdrops/BGM, keeping the bundle well under budget.
# LEAN=1 trims audio to SFX+music and textures to what these packs reference.
echo ">> refreshing Lua + assets from source (arcade set, lean)"
PACKS="catch fireflies forge timedodge" LEAN=1 sh "$HERE/prepare.sh" >/dev/null

echo ">> staging $OUT"
rm -rf "$OUT"; mkdir -p "$OUT/vendor"

# runtime + Lua + assets (assembled by prepare.sh)
cp "$HERE/engine.js"              "$OUT/engine.js"
cp "$HERE/vendor/fengari-web.js"  "$OUT/vendor/fengari-web.js"
cp "$HERE/manifest.json"          "$OUT/manifest.json"
cp "$HERE/main.lua"               "$OUT/main.lua"
cp -r "$HERE/games"               "$OUT/games"
cp -r "$HERE/packs"               "$OUT/packs"
cp -r "$HERE/textures"            "$OUT/textures"
cp -r "$HERE/audio"               "$OUT/audio"

# TikTok entry + config (the validator-required trio + TTMinis SDK html)
cp "$HERE/tiktok/index.html"             "$OUT/index.html"
cp "$HERE/tiktok/game.json"              "$OUT/game.json"
cp "$HERE/tiktok/minigame.config.json"   "$OUT/minigame.config.json"
cp "$HERE/tiktok/project.config.json"    "$OUT/project.config.json"

echo ""
echo "TikTok bundle ready: $OUT"
echo "  entry:   index.html  (TTMinis SDK + fengari boot)"
echo "  config:  game.json · minigame.config.json · project.config.json"
TOTAL=$(du -sh "$OUT" | cut -f1)
MAIN=$(du -ch "$OUT/index.html" "$OUT/engine.js" "$OUT/vendor" "$OUT"/*.lua "$OUT/packs" "$OUT"/*.json 2>/dev/null | tail -1 | cut -f1)
echo "  size:    total $TOTAL   (code+Lua ~$MAIN; the rest is textures/ audio/)"
echo ""
echo "TikTok limits: main package <= 4MB, total <= 30MB. If total is tight, move"
echo "textures/ + audio/ into a subpackage or lazy-load large BGM from a CDN"
echo "(add the CDN host to the app's trusted request domains)."
echo ""
echo "Next: set clientKey in index.html + appid in project.config.json, then zip"
echo "\$OUT and upload via the TikTok Mini Games DevTools (compileType: game)."
