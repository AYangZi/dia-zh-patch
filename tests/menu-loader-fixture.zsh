#!/bin/zsh
set -euo pipefail

readonly ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
readonly HOST_ARCH="$(uname -m)"
readonly FIXTURE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/dia-zh-loader.XXXXXX")"
trap 'rm -rf -- "$FIXTURE_ROOT"' EXIT
readonly APP="$FIXTURE_ROOT/Dia.app"
readonly CHILD="$FIXTURE_ROOT/nested-helper/child"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "${CHILD:h}"
# Exercise the same source on Intel CI as well as Apple Silicon hosts.
# run-tests.zsh separately verifies the production arm64 library.
xcrun clang -dynamiclib -fobjc-arc -fblocks -arch "$HOST_ARCH" \
  -mmacosx-version-min=14.0 -framework Cocoa \
  "$ROOT/native/DiaZhMenu.m" -o "$APP/Contents/Frameworks/DiaZhMenu.dylib"
codesign --force --sign - --timestamp=none \
  "$APP/Contents/Frameworks/DiaZhMenu.dylib" >/dev/null 2>&1
xcrun clang -arch "$HOST_ARCH" -fobjc-arc -framework Foundation \
  "$ROOT/tests/fixtures/menu-loader-main.m" -o "$APP/Contents/MacOS/Dia"
xcrun clang -arch "$HOST_ARCH" -fobjc-arc -framework Foundation \
  "$ROOT/tests/fixtures/minimal-main.m" -o "$CHILD"
DYLD_INSERT_LIBRARIES='@executable_path/../Frameworks/DiaZhMenu.dylib' \
  "$APP/Contents/MacOS/Dia" "$CHILD"
print -r -- "菜单加载与子进程环境 Fixture 通过。"
