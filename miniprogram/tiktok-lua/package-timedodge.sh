#!/bin/sh
# package-timedodge.sh — assemble the STANDALONE Time Dodge TikTok Mini Game
# (TTMinis HTML runtime) as TWO builds, per TikTok's monetization rule that
# running In-App Ads in both US and ROW from one app needs a US data-scope
# upgrade — the simpler path is two apps:
#
#   dist/timedodge-us/   NO ads (ships to the US; __ADS_ENABLED=false, REVIVE hidden)
#   dist/timedodge-row/  rewarded video ON (ships to regions where you hold IAA rights)
#
# Both share the same engine.js + fengari + unmodified Time Dodge Lua + assets;
# only index.html (and the project name) differ. Each is a separate TikTok app
# (its own appid + clientKey). Zip a dist dir and upload via the DevTools.
#
#   sh miniprogram/tiktok-lua/package-timedodge.sh
set -e

HERE="$(cd "$(dirname "$0")" && pwd)"

echo ">> refreshing Lua + assets (Time Dodge only)"
EXTRA="" PACKS="timedodge" LEAN=1 sh "$HERE/prepare.sh" >/dev/null

# Stage one variant: $1=dir suffix, $2=entry html, $3=project name.
stage() {
  OUT="$HERE/dist/timedodge-$1"
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
  cp "$HERE/timedodge/$2"                 "$OUT/index.html"
  cp "$HERE/tiktok/game.json"             "$OUT/game.json"
  cp "$HERE/tiktok/minigame.config.json"  "$OUT/minigame.config.json"
  sed "s/\"time-dodge\"/\"$3\"/" "$HERE/tiktok/project.config.json" > "$OUT/project.config.json"
}

stage us  index-us.html time-dodge-us
stage row index.html     time-dodge-row

echo ""
echo "Two Time Dodge builds ready:"
echo "  US  (no ads): $HERE/dist/timedodge-us   ($(du -sh "$HERE/dist/timedodge-us" | cut -f1))"
echo "  ROW (ads on): $HERE/dist/timedodge-row  ($(du -sh "$HERE/dist/timedodge-row" | cut -f1))"
echo ""
echo "Before upload (each dir is a SEPARATE TikTok app):"
echo "  US  -> index.html: set clientKey (US app)      · project.config.json: US appid"
echo "  ROW -> index.html: set clientKey (ROW app)     · project.config.json: ROW appid"
echo "         engine.js:  set AD_UNITS.revive + .cancel_hit adUnitIds (Developer Portal)"
echo "Then zip each dir and upload via the TikTok Mini Games DevTools (compileType: game)."
