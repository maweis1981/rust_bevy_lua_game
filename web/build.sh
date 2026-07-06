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

if command -v wasm-opt >/dev/null 2>&1; then
  echo ">> wasm-opt -Os"
  # --enable-reference-types + --enable-bulk-memory are REQUIRED: wasm-bindgen
  # emits an externref table and bulk-memory ops; without these flags wasm-opt
  # silently corrupts them and the module traps at init
  # (WebAssembly.Table.grow failed / __wbindgen_init_externref_table).
  wasm-opt -Os --enable-reference-types --enable-bulk-memory \
    -o "$OUT/hollowlullaby_bg.wasm" "$OUT/hollowlullaby_bg.wasm"
else
  echo ">> (wasm-opt not found; skipping size optimization)"
fi

echo ">> copying index.html + assets/"
cp "$ROOT/web/index.html" "$OUT/index.html"
cp -r "$ROOT/assets" "$OUT/assets"

echo ">> done: $OUT"
du -sh "$OUT" "$OUT/hollowlullaby_bg.wasm"
