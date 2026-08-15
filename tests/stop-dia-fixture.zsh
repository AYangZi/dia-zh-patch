#!/bin/zsh

set -euo pipefail

readonly PROJECT_ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
readonly FIXTURE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/dia-zh-stop.XXXXXX")"
readonly FIXTURE_BIN="$FIXTURE_ROOT/bin"
readonly PROCESS_STATE="$FIXTURE_ROOT/process-state"
readonly PKILL_LOG="$FIXTURE_ROOT/pkill-log"

cleanup() {
  rm -rf -- "$FIXTURE_ROOT"
}
trap cleanup EXIT

mkdir -p "$FIXTURE_BIN"
print -r -- alive > "$PROCESS_STATE"

cat > "$FIXTURE_BIN/pgrep" <<'EOF'
#!/bin/zsh
[[ "$(<"$DIA_ZH_TEST_PROCESS_STATE")" == "alive" ]]
EOF

cat > "$FIXTURE_BIN/osascript" <<'EOF'
#!/bin/zsh
exit 0
EOF

cat > "$FIXTURE_BIN/open" <<'EOF'
#!/bin/zsh
exit 0
EOF

cat > "$FIXTURE_BIN/sleep" <<'EOF'
#!/bin/zsh
exit 0
EOF

cat > "$FIXTURE_BIN/pkill" <<'EOF'
#!/bin/zsh
print -r -- "$*" >> "$DIA_ZH_TEST_PKILL_LOG"
print -r -- stopped > "$DIA_ZH_TEST_PROCESS_STATE"
EOF

chmod +x "$FIXTURE_BIN"/*

PATH="$FIXTURE_BIN:$PATH" \
  DIA_ZH_LIBRARY_ONLY=1 \
  DIA_ZH_TEST_PROCESS_STATE="$PROCESS_STATE" \
  DIA_ZH_TEST_PKILL_LOG="$PKILL_LOG" \
  zsh -c 'source "$1"; if smoke_test; then exit 1; fi; print -r -- returned > "$2"' \
  _ "$PROJECT_ROOT/dia-zh.command" "$FIXTURE_ROOT/smoke-returned"

[[ "$(<"$FIXTURE_ROOT/smoke-returned")" == "returned" ]]

PATH="$FIXTURE_BIN:$PATH" \
  DIA_ZH_LIBRARY_ONLY=1 \
  DIA_ZH_TEST_PROCESS_STATE="$PROCESS_STATE" \
  DIA_ZH_TEST_PKILL_LOG="$PKILL_LOG" \
  zsh -c 'source "$1"; stop_dia 1' _ "$PROJECT_ROOT/dia-zh.command"

[[ "$(<"$PROCESS_STATE")" == "stopped" ]]
grep -Fx -- "-TERM -x Dia" "$PKILL_LOG" >/dev/null

print -r -- "Dia 自动回滚退出 Fixture 通过。"
