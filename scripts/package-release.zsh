#!/bin/zsh

set -euo pipefail
export LC_ALL=C

readonly ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
readonly VERSION="$(<"$ROOT/VERSION")"
readonly OUTPUT_DIR="${1:-$ROOT/dist}"
readonly BASENAME="dia-zh-patch-$VERSION-macos-arm64"
readonly STAGE="$(mktemp -d "${TMPDIR:-/tmp}/dia-zh-release.XXXXXX")"

cleanup() {
  rm -rf -- "$STAGE"
}
trap cleanup EXIT

mkdir -p "$OUTPUT_DIR" "$STAGE/$BASENAME/lib"
readonly OUTPUT_DIR_ABS="$(cd -- "$OUTPUT_DIR" && pwd -P)"
(
  cd "$ROOT"
  git archive --format=tar HEAD
) | tar -xf - -C "$STAGE/$BASENAME"

"$ROOT/scripts/build-menu.zsh" "$STAGE/$BASENAME/lib/DiaZhMenu.dylib"
rm -f "$OUTPUT_DIR_ABS/$BASENAME.zip" \
  "$OUTPUT_DIR_ABS/$BASENAME.zip.sha256"
(
  cd "$STAGE"
  zip -qry -X "$OUTPUT_DIR_ABS/$BASENAME.zip" "$BASENAME"
)
(
  cd "$OUTPUT_DIR_ABS"
  shasum -a 256 "$BASENAME.zip" > "$BASENAME.zip.sha256"
)
print -r -- "已生成：$OUTPUT_DIR_ABS/$BASENAME.zip"
print -r -- "已生成：$OUTPUT_DIR_ABS/$BASENAME.zip.sha256"
