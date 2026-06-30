#!/usr/bin/env bash
# Build the Rust static library for the iOS arch Xcode is currently targeting,
# then copy it where the linker expects it. Invoked as a pre-build script by the
# generated Xcode project; also runnable by hand (defaults to the simulator).
set -euo pipefail

DEST_DIR="${1:?usage: build_rust.sh <dest-dir>}"
LIB_NAME="libhollowlullaby.a"

# Xcode provides these; fall back to simulator/Debug for manual runs.
PLATFORM_NAME="${PLATFORM_NAME:-iphonesimulator}"
CONFIGURATION="${CONFIGURATION:-Debug}"

case "$PLATFORM_NAME" in
  iphoneos)        TRIPLE="aarch64-apple-ios" ;;
  iphonesimulator) TRIPLE="aarch64-apple-ios-sim" ;;
  *) echo "unsupported PLATFORM_NAME: $PLATFORM_NAME" >&2; exit 1 ;;
esac

if [ "$CONFIGURATION" = "Release" ]; then
  PROFILE_FLAG="--release"
  PROFILE_DIR="release"
else
  PROFILE_FLAG=""
  PROFILE_DIR="debug"
fi

# Xcode runs with a sanitized PATH that omits ~/.cargo/bin.
export PATH="$HOME/.cargo/bin:$PATH"

cd "$(dirname "$0")/.."

echo "cargo build --lib --target $TRIPLE $PROFILE_FLAG"
cargo build --lib --target "$TRIPLE" $PROFILE_FLAG

# cargo's staticlib bundles the Rust objects but NOT the C libraries that build
# scripts produce (vendored Lua, blake3, etc.). Merge them all into one
# self-contained archive so Xcode's linker resolves e.g. lua_pcallk.
RUST_LIB="target/$TRIPLE/$PROFILE_DIR/$LIB_NAME"
NATIVE_LIBS=$(find "target/$TRIPLE/$PROFILE_DIR/build" -name '*.a' 2>/dev/null)

mkdir -p "$DEST_DIR"
echo "merging Rust staticlib + native libs:"
echo "$NATIVE_LIBS" | sed 's/^/  /'
libtool -static -o "$DEST_DIR/$LIB_NAME" "$RUST_LIB" $NATIVE_LIBS
echo "wrote self-contained $LIB_NAME -> $DEST_DIR"
