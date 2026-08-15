#!/bin/zsh

set -euo pipefail

readonly ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
readonly OUTPUT="${1:-$ROOT/lib/DiaZhMenu.dylib}"

mkdir -p "$(dirname -- "$OUTPUT")"
xcrun clang \
  -dynamiclib \
  -fobjc-arc \
  -fblocks \
  -arch arm64 \
  -mmacosx-version-min=14.0 \
  -framework Cocoa \
  -Wl,-install_name,@rpath/DiaZhMenu.dylib \
  "$ROOT/native/DiaZhMenu.m" \
  -o "$OUTPUT"

codesign --force --sign - --timestamp=none "$OUTPUT" >/dev/null 2>&1
file "$OUTPUT" | grep -q "arm64" ||
  { print -ru2 -- "构建产物不是 arm64：$OUTPUT"; exit 1; }
print -r -- "已构建：$OUTPUT"
