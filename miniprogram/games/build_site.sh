#!/usr/bin/env bash
# build_site.sh — assemble a static GitHub Pages site of the JS mini-games, with
# EACH GAME as its own self-contained package plus the combined "arcade" shell
# and a landing hub. Pure JS (no Rust/wasm) — fast to build and deploy.
#
# Output (100% static, relative paths — works under any Pages subpath):
#   build/pages/
#     index.html            landing hub (links to each game)
#     assets/               shared art (bg, font) used by the hub
#     suika/                self-contained Suika package (index.html+bundle.js+assets/)
#     watersort/            self-contained Water Sort package
#     timedodge/            self-contained Time Dodge package (from ../tiktok)
#     arcade/               the combined collection shell (all games in one menu)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"          # miniprogram/games
MP="$(cd "$HERE/.." && pwd)"                    # miniprogram
ROOT="$(cd "$MP/.." && pwd)"                    # repo root
# Output dir: defaults to build/pages, or set PAGES_OUT to embed elsewhere
# (e.g. web/build.sh points it at build/web/games so the engine-site deploy
# ships the games under /games/).
OUT="${PAGES_OUT:-$ROOT/build/pages}"

echo ">> building game bundles + asset copies"
sh "$MP/prepare.sh" >/dev/null                  # builds tiktok/engine.bundle.js (Time Dodge)
sh "$HERE/suika/build.sh" >/dev/null
sh "$HERE/watersort/build.sh" >/dev/null
sh "$HERE/shell/build.sh" >/dev/null

echo ">> assembling $OUT"
rm -rf "$OUT"; mkdir -p "$OUT"

pkg() {  # $1 = src dir, $2 = dest name, then files...
  local src="$1" name="$2"; shift 2
  mkdir -p "$OUT/$name"
  for f in "$@"; do cp -R "$src/$f" "$OUT/$name/"; done
}

pkg "$HERE/suika"     suika     index.html bundle.js assets
pkg "$HERE/watersort" watersort index.html bundle.js assets
pkg "$HERE/shell"     arcade    index.html bundle.js assets
pkg "$MP/tiktok"      timedodge index.html adapter.js engine.bundle.js

# shared art for the hub landing page
mkdir -p "$OUT/assets"
cp "$HERE/assets/bg.jpg" "$HERE/assets/Baloo2.ttf" "$OUT/assets/" 2>/dev/null || true

cat > "$OUT/index.html" <<'HTML'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
  <title>Mini Arcade</title>
  <style>
    @font-face { font-family:'Baloo2'; src:url('./assets/Baloo2.ttf') format('truetype'); font-weight:400 800; font-display:swap; }
    * { box-sizing: border-box; }
    html,body { margin:0; height:100%; }
    body {
      font-family:'Baloo2', system-ui, sans-serif; color:#eaf0ff;
      min-height:100%; background:#0b1020 url('./assets/bg.jpg') center/cover fixed no-repeat;
      display:flex; flex-direction:column; align-items:center; padding:32px 18px 48px;
    }
    h1 { font-weight:800; font-size:clamp(34px,9vw,58px); margin:18px 0 2px; letter-spacing:.5px; text-shadow:0 4px 24px rgba(0,0,0,.5); }
    .sub { color:#c3cfe8; opacity:.85; margin:0 0 26px; font-size:clamp(14px,3.6vw,18px); }
    .grid { width:100%; max-width:440px; display:flex; flex-direction:column; gap:16px; }
    a.card {
      display:flex; align-items:center; justify-content:space-between; text-decoration:none; color:#fff;
      padding:20px 22px; border-radius:20px; font-weight:800; font-size:clamp(20px,5.5vw,26px);
      box-shadow:0 10px 30px rgba(0,0,0,.35); border:1px solid rgba(255,255,255,.14);
      transition:transform .12s ease, filter .12s ease;
    }
    a.card:hover { transform:translateY(-2px); filter:brightness(1.06); }
    a.card small { display:block; font-weight:600; font-size:.6em; opacity:.9; margin-top:2px; }
    a.card .arrow { font-size:1.1em; opacity:.9; }
    .suika     { background:linear-gradient(180deg,#49c46a,#2c8f46); }
    .watersort { background:linear-gradient(180deg,#3fb0f5,#2073c8); }
    .timedodge { background:linear-gradient(180deg,#ef5566,#c22a3a); }
    .arcade    { background:linear-gradient(180deg,#8f6df0,#5b3fd0); }
    .foot { margin-top:28px; font-size:12px; color:#9fb0d0; opacity:.7; text-align:center; }
  </style>
</head>
<body>
  <h1>MINI ARCADE</h1>
  <p class="sub">tap a game — plays right in your browser</p>
  <div class="grid">
    <a class="card suika" href="./suika/"><span>SUIKA<small>drop &amp; merge the fruit</small></span><span class="arrow">▶</span></a>
    <a class="card watersort" href="./watersort/"><span>WATER SORT<small>pour to sort the colors</small></span><span class="arrow">▶</span></a>
    <a class="card timedodge" href="./timedodge/"><span>TIME DODGE<small>hold time · dodge the deep</small></span><span class="arrow">▶</span></a>
    <a class="card arcade" href="./arcade/"><span>ALL-IN-ONE<small>the whole collection in one app</small></span><span class="arrow">▶</span></a>
  </div>
  <div class="foot">Dependency-free JS + Canvas 2D · art via the Floniks AI pipeline</div>
</body>
</html>
HTML

echo ">> done: $OUT"
find "$OUT" -maxdepth 2 -type d | sed "s#$OUT#  build/pages#"
