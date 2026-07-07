#!/bin/sh
# prepare.sh — assemble each platform's project root from the single-source
# canonical folders, because WeChat/Douyin DevTools package only files under the
# opened root and require() paths may not escape it.
#
# Subpackage (分包) layout produced here, per platform (wechat/ and douyin/):
#   <plat>/                 MAIN package
#     game.js game.json project.config.json adapter.js   (checked in)
#     boot/                 <- copy of ../boot   (loading screen + launcher)
#     engine/               SUBPACKAGE root (declared in game.json "subpackages")
#       index.js            (checked in) subpackage entry
#       shared/             <- copy of ../shared  (the JS engine)
#
# The canonical sources are ../boot (main-package launcher) and ../shared (the
# engine that ships inside the subpackage). Run this before opening either
# folder in DevTools, and re-run after editing anything in boot/ or shared/.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
for target in wechat douyin; do
  rm -rf "$HERE/$target/boot" "$HERE/$target/engine/shared"
  cp -R "$HERE/boot" "$HERE/$target/boot"
  mkdir -p "$HERE/$target/engine"
  cp -R "$HERE/shared" "$HERE/$target/engine/shared"
  echo "assembled $target/: boot/ (main) + engine/shared/ (subpackage)"
done
echo "done. Open miniprogram/wechat in WeChat DevTools, or miniprogram/douyin in Douyin DevTools."
