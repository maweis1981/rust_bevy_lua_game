#!/bin/sh
# package-timedodge.sh — assemble a STANDALONE Time Dodge TikTok Mini Game
# (TTMinis HTML runtime). Ships ONLY Time Dodge: the same engine.js + fengari +
# its unmodified native Lua, the TTMinis SDK entry (boots straight into the game,
# single-game mode), rewarded-video ads, and the validator-required config trio.
# Output: miniprogram/tiktok-lua/dist/timedodge/.
#
#   sh miniprogram/tiktok-lua/package-timedodge.sh
set -e

HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$HERE/dist/timedodge"

# Only the timedodge pack, no top-level games, lean assets.
echo ">> refreshing Lua + assets (Time Dodge only)"
EXTRA="" PACKS="timedodge" LEAN=1 sh "$HERE/prepare.sh" >/dev/null

echo ">> staging $OUT"
rm -rf "$OUT"; mkdir -p "$OUT/vendor"
cp "$HERE/engine.js"              "$OUT/engine.js"
cp "$HERE/vendor/fengari-web.js"  "$OUT/vendor/fengari-web.js"
cp "$HERE/manifest.json"          "$OUT/manifest.json"
cp "$HERE/main.lua"               "$OUT/main.lua"
cp -r "$HERE/packs"               "$OUT/packs"
# Only the textures + audio Time Dodge actually uses (keeps the bundle small —
# well under TikTok's 4MB main-package limit). Player=rockball, foes=meteor,
# gate=gem, HUD icons; SFX hit/score/wall + one looping music track.
mkdir -p "$OUT/textures" "$OUT/audio"
for t in rockball meteor gem icon_base icon_mass icon_time icon_clock; do
  [ -f "$HERE/textures/$t.png" ] && cp "$HERE/textures/$t.png" "$OUT/textures/" || true
done
for w in hit score wall music; do
  [ -f "$HERE/audio/$w.wav" ] && cp "$HERE/audio/$w.wav" "$OUT/audio/" || true
done
# standalone entry + the validator-required trio + TTMinis SDK
cp "$HERE/timedodge/index.html"          "$OUT/index.html"
cp "$HERE/tiktok/game.json"              "$OUT/game.json"
cp "$HERE/tiktok/minigame.config.json"   "$OUT/minigame.config.json"
cp "$HERE/tiktok/project.config.json"    "$OUT/project.config.json"

echo ""
echo "Standalone Time Dodge bundle: $OUT"
echo "  entry:  index.html  (TTMinis SDK -> boots straight into Time Dodge)"
echo "  ads:    rewarded video (revive + cancel-hit) via TTMinis.game.createRewardedVideoAd"
echo "  config: game.json · minigame.config.json · project.config.json"
echo "  size:   $(du -sh "$OUT" | cut -f1) total"
echo ""
echo "Before upload, in $OUT:"
echo "  1. index.html      -> set clientKey ('YOUR_TIKTOK_CLIENT_KEY')"
echo "  2. project.config.json -> set appid"
echo "  3. engine.js       -> set the two rewarded-ad adUnitIds (revive, cancel_hit)"
echo "                        from the TikTok Developer Portal (AD_UNITS map)"
echo "Then zip \$OUT and upload via the TikTok Mini Games DevTools (compileType: game)."
