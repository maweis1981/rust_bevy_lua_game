#!/usr/bin/env bash
# Build the static web site (engine homepage + WebAssembly game) into build/web/.
#
# Output layout (100% static — any host or GitHub Pages):
#   /              engine homepage + blog/ + docs/  (from web/site/)
#   /play/         the game: index.html (from web/game.html) + hollowlullaby.js
#                  + *_bg.wasm + assets/
#   /blog/posts/   markdown copied verbatim from docs/blog/ (rendered client-side
#                  by marked.js; the post list lives in web/site/blog/posts.js)
#   /blog/img/     blog images (docs/blog/img/)
#   /docs/md/      markdown copied from docs/showcase/
# Requires: rustup target add wasm32-unknown-unknown; wasm-bindgen-cli (matching
# the wasm-bindgen crate version); optional wasm-opt (binaryen) to shrink output.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/build/web"
PLAY="$OUT/play"
TARGET=wasm32-unknown-unknown
PROFILE="${PROFILE:-release}" # debug builds are huge & slow; ship release

echo ">> cargo build ($PROFILE) for $TARGET"
CARGO_FLAGS=(--target "$TARGET" --bin hollowlullaby)
[ "$PROFILE" = release ] && CARGO_FLAGS+=(--release)
cargo build "${CARGO_FLAGS[@]}"

WASM="$ROOT/target/$TARGET/$PROFILE/hollowlullaby.wasm"

echo ">> wasm-bindgen"
rm -rf "$OUT"; mkdir -p "$PLAY"
wasm-bindgen --target web --no-typescript \
  --out-dir "$PLAY" --out-name hollowlullaby "$WASM"

# wasm-opt is OPT-IN (WASM_OPT=1), and off by default. wasm-bindgen emits an
# externref table; older binaryen (e.g. Ubuntu's 108) corrupts it during
# optimization so the module traps at init with
#   RangeError: WebAssembly.Table.grow() failed / __wbindgen_init_externref_table
# even with --enable-reference-types. Ship the un-optimized wasm (it works;
# Pages gzips it on the wire). Enable only with a binaryen new enough to keep
# reference types intact: WASM_OPT=1 make web.
if [ "${WASM_OPT:-0}" = 1 ] && command -v wasm-opt >/dev/null 2>&1; then
  echo ">> wasm-opt -Os (WASM_OPT=1; needs a recent binaryen)"
  wasm-opt -Os --enable-reference-types --enable-bulk-memory \
    -o "$PLAY/hollowlullaby_bg.wasm" "$PLAY/hollowlullaby_bg.wasm"
else
  echo ">> skipping wasm-opt (set WASM_OPT=1 with a recent binaryen to enable)"
fi

echo ">> assembling game page (/play/)"
cp "$ROOT/web/game.html" "$PLAY/index.html"
cp -r "$ROOT/assets" "$PLAY/assets"

echo ">> assembling site pages (homepage / blog / docs)"
cp -r "$ROOT/web/site/." "$OUT/"
cp "$ROOT/docs/showcase/media/keyart.png" "$OUT/assets/keyart.png"

mkdir -p "$OUT/blog/posts" "$OUT/blog/img" "$OUT/docs/md"
cp "$ROOT"/docs/blog/*.md "$OUT/blog/posts/"
cp -r "$ROOT/docs/blog/img/." "$OUT/blog/img/"
cp "$ROOT"/docs/showcase/{product-intro,user-manual,use-cases}.md "$OUT/docs/md/"

echo ">> done: $OUT"
du -sh "$OUT" "$PLAY/hollowlullaby_bg.wasm"
