#!/bin/zsh

set -euo pipefail

readonly ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
readonly FIXTURE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/dia-zh-signing.XXXXXX")"
readonly APP="$FIXTURE_ROOT/Dia.app"
readonly ARC="$APP/Contents/Frameworks/ArcCore.framework"
readonly ARC_A="$ARC/Versions/A"

cleanup() {
  local code=$?
  rm -rf -- "$FIXTURE_ROOT"
  return "$code"
}
trap cleanup EXIT

make_info_plist() {
  local destination="$1" identifier="$2" executable="$3"
  mkdir -p "$(dirname -- "$destination")"
  plutil -create xml1 "$destination"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string $identifier" "$destination"
  /usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string $executable" "$destination"
  /usr/libexec/PlistBuddy -c "Add :CFBundlePackageType string APPL" "$destination"
  /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string 1" "$destination"
}

make_helper() {
  local name="$1" identifier="$2"
  local helper="$ARC_A/Helpers/$name.app"
  mkdir -p "$helper/Contents/MacOS"
  make_info_plist "$helper/Contents/Info.plist" "$identifier" "$name"
  xcrun clang -fobjc-arc -framework Foundation \
    "$ROOT/tests/fixtures/minimal-main.m" -o "$helper/Contents/MacOS/$name"
  codesign --force --sign - --timestamp=none --options runtime \
    --entitlements "$ROOT/native/entitlements/helper-jit.plist" "$helper" >/dev/null
}

mkdir -p "$APP/Contents/MacOS" "$ARC_A/Resources" "$ARC_A/Helpers"
make_info_plist "$APP/Contents/Info.plist" "test.dia.fixture" "Dia"
xcrun clang -fobjc-arc -framework Foundation \
  "$ROOT/tests/fixtures/minimal-main.m" -o "$APP/Contents/MacOS/Dia"

plutil -create xml1 "$ARC_A/Resources/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string test.arccore.fixture" \
  "$ARC_A/Resources/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string ArcCore" \
  "$ARC_A/Resources/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundlePackageType string FMWK" \
  "$ARC_A/Resources/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleVersion string 1" \
  "$ARC_A/Resources/Info.plist"
xcrun clang -dynamiclib "$ROOT/tests/fixtures/minimal-dylib.c" -o "$ARC_A/ArcCore"

make_helper "Browser Helper (GPU)" "test.dia.fixture.gpu"
make_helper "Browser Helper (Renderer)" "test.dia.fixture.renderer"

ln -s A "$ARC/Versions/Current"
ln -s Versions/Current/ArcCore "$ARC/ArcCore"
ln -s Versions/Current/Resources "$ARC/Resources"
codesign --force --sign - --timestamp=none --options runtime "$ARC" >/dev/null
codesign --force --sign - --timestamp=none --options runtime \
  --entitlements "$ROOT/native/entitlements/helper.plist" "$APP" >/dev/null

"$ROOT/scripts/sign-app.zsh" "$APP" "$FIXTURE_ROOT/work"
codesign --verify --deep --strict "$APP"
print -r -- "签名 Fixture 通过。"
