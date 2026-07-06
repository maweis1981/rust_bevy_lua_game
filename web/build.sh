#!/usr/bin/env bash
# Build the static web bundle (WebAssembly) into build/web/.
#
# Output is 100% static — index.html + hollowlullaby.js + *_bg.wasm + assets/ —
# so it can be served by any static host (see `make web-serve`) or GitHub Pages.
# Requires: rustup target add wasm32-unknown-unknown; wasm-bindgen-cli (matching
# the wasm-bindgen crate version); optional wasm-opt (binaryen) to shrink output.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/build/web"
TARGET=wasm32-unknown-unknown
PROFILE="${PROFILE:-release}" # debug builds are huge & slow; ship release

echo ">> cargo build ($PROFILE) for $TARGET"
CARGO_FLAGS=(--target "$TARGET" --bin hollowlullaby)
[ "$PROFILE" = release ] && CARGO_FLAGS+=(--release)
cargo build "${CARGO_FLAGS[@]}"

WASM="$ROOT/target/$TARGET/$PROFILE/hollowlullaby.wasm"

echo ">> wasm-bindgen"
rm -rf "$OUT"; mkdir -p "$OUT"
wasm-bindgen --target web --no-typescript \
  --out-dir "$OUT" --out-name hollowlullaby "$WASM"

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
    -o "$OUT/hollowlullaby_bg.wasm" "$OUT/hollowlullaby_bg.wasm"
else
  echo ">> skipping wasm-opt (set WASM_OPT=1 with a recent binaryen to enable)"
fi

echo ">> copying index.html + assets/"
cp "$ROOT/web/index.html" "$OUT/index.html"
cp -r "$ROOT/assets" "$OUT/assets"

echo ">> done: $OUT"
du -sh "$OUT" "$OUT/hollowlullaby_bg.wasm"
