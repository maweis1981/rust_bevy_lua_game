#!/usr/bin/env bash
# Export ONE standalone web bundle PER GAME into build/web-games/<key>/ (+ .zip).
#
# The wasm binary is the engine; games are Lua assets. So a single-game bundle
# is the shared `make web` output with one line — AUTOBOOT = "<key>" — prepended
# to its copy of scripts/main.lua: the router boots straight into that game and
# every "back to menu" re-enters it (the lobby menu never shows). No per-game
# Rust compile. Files are hardlinked from build/web (cp -al) so 15 bundles cost
# almost no extra disk; main.lua is removed and rewritten so the shared inode
# is never touched.
#
# Usage: tools/export_web_games.sh [key ...]   (default: all registered games)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/build/web"
OUT="$ROOT/build/web-games"
[ -d "$SRC" ] || { echo "build/web missing — run 'make web' first" >&2; exit 1; }

GAMES=("$@")
if [ ${#GAMES[@]} -eq 0 ]; then
  GAMES=(grow breakout snake roguelike game2048 shooter world craft match3 \
         umami catch ponies gallery showcase timedodge)
fi

mkdir -p "$OUT"
for g in "${GAMES[@]}"; do
  rm -rf "$OUT/$g" "$OUT/$g.zip"
  cp -al "$SRC" "$OUT/$g"
  rm "$OUT/$g/assets/scripts/main.lua"           # break the hardlink first
  { echo "AUTOBOOT = \"$g\""; cat "$SRC/assets/scripts/main.lua"; } \
    > "$OUT/$g/assets/scripts/main.lua"
  (cd "$OUT" && zip -qr "$g.zip" "$g")
  echo "  $g -> $OUT/$g  ($(du -sh "$OUT/$g.zip" | cut -f1) zipped)"
done
echo "done: ${#GAMES[@]} single-game bundles in $OUT"
