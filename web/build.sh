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

# wasm-opt shrinks the linked module (typically 15-25% on top of opt-level=z).
# CAVEAT: wasm-bindgen emits an externref table that OLD binaryen (Ubuntu's 108)
# corrupts, trapping at init with "WebAssembly.Table.grow() failed /
# __wbindgen_init_externref_table". So we only run a binaryen >= 116, and we
# auto-discover one: an explicit $WASM_OPT, then the npm `binaryen` package
# (npm i -g binaryen ships a current wasm-opt), then PATH. On by default;
# set WASM_OPT=0 to skip. A too-old PATH wasm-opt is refused, not shipped broken.
pick_wasm_opt() {
  for c in "${WASM_OPT:-}" \
           "$(command -v wasm-opt 2>/dev/null)" \
           /opt/node22/lib/node_modules/binaryen/bin/wasm-opt \
           "$(npm root -g 2>/dev/null)/binaryen/bin/wasm-opt"; do
    [ -n "$c" ] && [ -x "$c" ] || continue
    v=$("$c" --version 2>/dev/null | grep -oE '[0-9]+' | head -1)
    [ -n "$v" ] && [ "$v" -ge 116 ] && { echo "$c"; return 0; }
  done
  return 1
}
if [ "${WASM_OPT:-1}" != 0 ] && WO=$(pick_wasm_opt); then
  before=$(wc -c < "$PLAY/hollowlullaby_bg.wasm")
  echo ">> wasm-opt -Oz with $("$WO" --version | head -1)"
  # Enable every wasm feature rustc's default target emits (sign-ext,
  # nontrapping-fptoint, bulk-memory, reference-types, mutable-globals, …) or
  # wasm-opt rejects the module at load. On any failure we keep the (valid)
  # un-opt wasm and continue — a binaryen quirk must never break the build.
  if "$WO" -Oz --all-features \
       -o "$PLAY/hollowlullaby_bg.wasm.opt" "$PLAY/hollowlullaby_bg.wasm" 2>/tmp/wasmopt.err; then
    mv "$PLAY/hollowlullaby_bg.wasm.opt" "$PLAY/hollowlullaby_bg.wasm"
    after=$(wc -c < "$PLAY/hollowlullaby_bg.wasm")
    echo ">> wasm-opt: $((before/1048576))MB -> $((after/1048576))MB"
  else
    rm -f "$PLAY/hollowlullaby_bg.wasm.opt"
    echo ">> wasm-opt failed (kept un-opt wasm): $(tail -1 /tmp/wasmopt.err)"
  fi
else
  echo ">> skipping wasm-opt (no binaryen >= 116 found; set WASM_OPT=/path/wasm-opt)"
fi

echo ">> assembling game page (/play/)"
cp "$ROOT/web/game.html" "$PLAY/index.html"
# Inject the wasm's true (decompressed) byte size so the loading bar measures
# progress correctly even when the host serves gzip (compressed Content-Length).
WASM_BYTES=$(wc -c < "$PLAY/hollowlullaby_bg.wasm" | tr -d ' ')
sed -i.bak "s/__WASM_SIZE__/$WASM_BYTES/" "$PLAY/index.html" && rm -f "$PLAY/index.html.bak"
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
