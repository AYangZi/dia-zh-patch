#!/bin/zsh

set -euo pipefail

readonly PROJECT_ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
readonly FIXTURE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/dia-zh-status.XXXXXX")"

cleanup() {
  rm -rf -- "$FIXTURE_ROOT"
}
trap cleanup EXIT

DIA_ZH_LIBRARY_ONLY=1 DIA_ZH_STATE_DIR="$FIXTURE_ROOT/state" zsh -c '
  source "$1"
  require_macos() { return 0; }
  require_common_project_files() { return 0; }
  require_app() { return 0; }
  validate_requested_mode() { return 0; }
  app_version() { print -r -- 1.0; }
  app_build() { print -r -- 1; }
  signature_description() { print -r -- fixture; }
  detect_coverage() {
    COVERAGE_MODE=core
    COVERAGE_REASON=fixture
    return 0
  }
  show_status >/dev/null
' _ "$PROJECT_ROOT/dia-zh.command"

print -r -- "status 成功退出 Fixture 通过。"
