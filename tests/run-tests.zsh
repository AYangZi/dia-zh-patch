#!/bin/zsh

set -euo pipefail

readonly ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
readonly BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/dia-zh-tests.XXXXXX")"
readonly HOST_ARCH="$(uname -m)"

cleanup() {
  local code=$?
  rm -rf -- "$BUILD_DIR"
  return "$code"
}
trap cleanup EXIT

node "$ROOT/tests/validate-project.mjs"
zsh -n "$ROOT/dia-zh.command"
for script in "$ROOT"/scripts/*.zsh; do
  zsh -n "$script"
done
plutil -lint "$ROOT/translations/zh-Hans.strings" >/dev/null
plutil -lint "$ROOT/native/entitlements/"*.plist >/dev/null

xcrun clang \
  -fobjc-arc \
  -fblocks \
  -arch "$HOST_ARCH" \
  -mmacosx-version-min=14.0 \
  -framework Cocoa \
  "$ROOT/tests/menu-policy.m" \
  -o "$BUILD_DIR/menu-policy"
DIA_ZH_RESOURCE_ROOT="$ROOT/translations" \
  "$BUILD_DIR/menu-policy" "$ROOT/translations"

"$ROOT/scripts/build-menu.zsh" "$BUILD_DIR/DiaZhMenu.dylib"
codesign --verify --strict "$BUILD_DIR/DiaZhMenu.dylib"
"$ROOT/tests/signing-fixture.zsh"
"$ROOT/tests/stop-dia-fixture.zsh"
"$ROOT/tests/status-fixture.zsh"
print -r -- "全部静态与菜单策略测试通过。"
