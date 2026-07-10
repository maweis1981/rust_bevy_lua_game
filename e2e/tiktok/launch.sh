#!/usr/bin/env bash
# launch.sh — open the TikTok mini-game preview via its deep link (no camera scan).
#
# Usage:
#   ./launch.sh "<preview-deep-link-uri>"        # uses default TikTok global pkg
#   TIKTOK_PKG=com.ss.android.ugc.trill ./launch.sh "<uri>"   # override package
#
# The URI is whatever the developer-portal preview QR encodes. On a device that is
# already logged in as a registered test user, opening it jumps straight into the
# mini-game preview.
set -euo pipefail

URI="${1:-}"
PKG="${TIKTOK_PKG:-com.zhiliaoapp.musically}"   # TikTok (global). Douyin: com.ss.android.ugc.aweme
SERIAL_ARG=()
[ -n "${ANDROID_SERIAL:-}" ] && SERIAL_ARG=(-s "$ANDROID_SERIAL")

if [ -z "$URI" ]; then
  echo "usage: $0 '<preview-deep-link-uri>'" >&2
  exit 2
fi

if ! command -v adb >/dev/null 2>&1; then
  echo "adb not found on PATH (install Android platform-tools)" >&2
  exit 1
fi

echo "device(s):"
adb "${SERIAL_ARG[@]}" devices | sed '1d;/^$/d'

# Confirm TikTok is installed.
if ! adb "${SERIAL_ARG[@]}" shell pm list packages | tr -d '\r' | grep -qx "package:$PKG"; then
  echo "TikTok package '$PKG' not installed on the device." >&2
  echo "Install TikTok and log in as the test user first (manual, one-time)." >&2
  exit 1
fi

case "$URI" in
  http://*|https://*)
    # Universal link: constrain to TikTok so the chooser doesn't pop.
    echo "opening universal link via $PKG ..."
    adb "${SERIAL_ARG[@]}" shell am start -a android.intent.action.VIEW \
        -d "$URI" -p "$PKG"
    ;;
  *://*)
    # Custom scheme (snssdk*, aweme, ...): let the system resolve the handler.
    echo "opening custom-scheme deep link ..."
    adb "${SERIAL_ARG[@]}" shell am start -a android.intent.action.VIEW -d "$URI"
    ;;
  *)
    echo "URI does not look like a link (expected scheme://...): $URI" >&2
    exit 2
    ;;
esac

echo "launched. Give the mini-game a few seconds to load, then run playtest.py."
