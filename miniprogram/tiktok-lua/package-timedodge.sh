#!/bin/sh
# package-timedodge.sh — assemble the STANDALONE Time Dodge TikTok Mini Game
# (TTMinis HTML runtime) into dist/timedodge/. Single global build with In-App
# Ads (IAA): rewarded video for revive, ABSORB cancel-hit, and an always-on
# "watch ad -> gold skin" entry on the home screen. Ships to regions where you
# hold rewarded-ad rights. (The US-only ads-off + IAP variant still exists in
# the sources — index-us.html + server/ — if you ever need the two-app split.)
#
#   sh miniprogram/tiktok-lua/package-timedodge.sh
set -e

HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$HERE/dist/timedodge"

echo ">> refreshing Lua + assets (Time Dodge only)"
EXTRA="" PACKS="timedodge" LEAN=1 sh "$HERE/prepare.sh" >/dev/null

echo ">> staging $OUT"
rm -rf "$OUT"; mkdir -p "$OUT/vendor" "$OUT/textures" "$OUT/audio"
cp "$HERE/engine.js"              "$OUT/engine.js"
cp "$HERE/vendor/fengari-web.js"  "$OUT/vendor/fengari-web.js"
cp "$HERE/manifest.json"          "$OUT/manifest.json"
cp "$HERE/main.lua"               "$OUT/main.lua"
cp -r "$HERE/packs"               "$OUT/packs"
# Only the textures + audio Time Dodge uses (tiny; well under the 4MB limit).
for t in rockball meteor gem icon_base icon_mass icon_time icon_clock; do
  [ -f "$HERE/textures/$t.png" ] && cp "$HERE/textures/$t.png" "$OUT/textures/" || true
done
for w in hit score wall music; do
  [ -f "$HERE/audio/$w.wav" ] && cp "$HERE/audio/$w.wav" "$OUT/audio/" || true
done
cp "$HERE/timedodge/index.html"          "$OUT/index.html"
cp "$HERE/tiktok/game.json"              "$OUT/game.json"
cp "$HERE/tiktok/minigame.config.json"   "$OUT/minigame.config.json"
cp "$HERE/tiktok/project.config.json"    "$OUT/project.config.json"

echo ""
echo "Time Dodge (IAA / ads) build ready: $OUT   ($(du -sh "$OUT" | cut -f1))"
echo "  revenue: rewarded video (TTMinis.game.createRewardedVideoAd) — revive,"
echo "           ABSORB cancel-hit, and a home-screen WATCH-AD -> gold skin."
echo "  ad unit: set in engine.js (AD_UNIT) — currently ad7660402788282714128."
echo ""
echo "Before upload:"
echo "  index.html         -> set clientKey (your TikTok app)"
echo "  project.config.json-> set appid"
echo "Then zip $OUT and upload via the TikTok Mini Games DevTools (compileType: game)."
