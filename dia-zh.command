#!/bin/zsh

set -euo pipefail
setopt NO_NOMATCH

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd -P)"
readonly PATCH_VERSION="$(<"$SCRIPT_DIR/VERSION")"
readonly MANIFEST_INDEX="$SCRIPT_DIR/manifests/index.json"
readonly STRINGS_FILE="$SCRIPT_DIR/translations/zh-Hans.strings"
readonly MENU_KEYS_FILE="$SCRIPT_DIR/translations/menu-keys.txt"
readonly MENU_DYLIB="$SCRIPT_DIR/lib/DiaZhMenu.dylib"
readonly WEB_HELPER="$SCRIPT_DIR/scripts/patch-webui.jxa"
readonly SIGN_HELPER="$SCRIPT_DIR/scripts/sign-app.zsh"
readonly APP_PATH="${DIA_APP_PATH:-/Applications/Dia.app}"
readonly STATE_ROOT="${DIA_ZH_STATE_DIR:-$HOME/Library/Application Support/DiaZhPatch}"
readonly STATE_FILE="$STATE_ROOT/current-state"
readonly REPORT_DIR="$STATE_ROOT/reports"
readonly BACKUP_ROOT="$STATE_ROOT/backups"
readonly LOCK_DIR="$STATE_ROOT/.lock"
readonly REQUESTED_MODE="${DIA_ZH_MODE:-auto}"

readonly SUPPORTED_BUNDLE_ID="company.thebrowser.dia"
readonly OFFICIAL_TEAM_ID="S6N382Y83G"
readonly MENU_LOAD_PATH="@executable_path/../Frameworks/DiaZhMenu.dylib"

typeset -g APPLY_ACTIVE=0
typeset -g LOCK_HELD=0
typeset -g CREATED_BACKUP=""
typeset -g COVERAGE_MODE="incompatible"
typeset -g COVERAGE_REASON=""
typeset -g MANIFEST=""
typeset -g WEB_HASHES_ORIGINAL=""
typeset -g WEB_HASHES_PATCHED=""

log() {
  print -r -- "[dia-zh] $*"
}

warn() {
  print -ru2 -- "[dia-zh] 警告：$*"
}

die() {
  print -ru2 -- "[dia-zh] 错误：$*"
  exit 1
}

usage() {
  cat <<EOF
Dia 简体中文补丁 $PATCH_VERSION

用法：
  ./dia-zh.command apply
  ./dia-zh.command audit
  ./dia-zh.command status
  ./dia-zh.command restore
  ./dia-zh.command help

覆盖级别：
  full          已验证 Build：Chromium、词表、菜单和 WebUI
  core          其他兼容 Build：Chromium、词表和菜单核心汉化
  incompatible  结构或签名不兼容，写入前拒绝安装

环境变量：
  DIA_ZH_MODE=core         主动跳过已知 Build 的 WebUI 替换
  DIA_APP_PATH             Dia.app 路径，默认 /Applications/Dia.app
  DIA_ZH_STATE_DIR         备份、状态和报告目录
  DIA_ZH_ASSUME_SMOKE_OK=1 非交互环境下接受启动冒烟检查
EOF
}

require_macos() {
  [[ "$(uname -s)" == "Darwin" ]] || die "补丁只能在 macOS 上运行。"
  [[ "$(uname -m)" == "arm64" ]] || die "首发版仅支持 Apple Silicon（arm64）。"

  local product_version major
  product_version="$(sw_vers -productVersion)"
  major="${product_version%%.*}"
  (( major >= 14 )) || die "需要 macOS 14.0 或更高版本，当前为 $product_version。"
}

require_common_project_files() {
  [[ -f "$MANIFEST_INDEX" ]] || die "缺少版本索引：$MANIFEST_INDEX"
  [[ -f "$STRINGS_FILE" ]] || die "缺少统一翻译词表：$STRINGS_FILE"
  [[ -f "$MENU_KEYS_FILE" ]] || die "缺少菜单键白名单：$MENU_KEYS_FILE"
  [[ -x "$SIGN_HELPER" ]] || die "缺少签名脚本：$SIGN_HELPER"
  [[ -f "$WEB_HELPER" ]] || die "缺少 WebUI 补丁器：$WEB_HELPER"
  osascript -l JavaScript -e \
    'ObjC.import("Foundation"); function run(argv) { JSON.parse(ObjC.unwrap($.NSString.stringWithContentsOfFileEncodingError(argv[0], $.NSUTF8StringEncoding, null))); }' \
    "$MANIFEST_INDEX" >/dev/null 2>&1 || die "版本索引不是有效 JSON。"
  plutil -lint "$STRINGS_FILE" >/dev/null || die "zh-Hans.strings 格式无效。"
}

require_apply_artifacts() {
  [[ -f "$MENU_DYLIB" ]] ||
    die "缺少 arm64 菜单动态库。请下载 Release 安装包，或先运行 scripts/build-menu.zsh。"
  file "$MENU_DYLIB" | grep -q "arm64" ||
    die "菜单动态库不是 arm64 构建。"
}

require_app() {
  [[ -d "$APP_PATH" ]] || die "未找到 Dia：$APP_PATH"
  [[ "$APP_PATH" == */Dia.app ]] || die "DIA_APP_PATH 必须指向名为 Dia.app 的应用包。"
  [[ -f "$APP_PATH/Contents/Info.plist" ]] ||
    die "Dia.app 缺少 Contents/Info.plist。"
}

plist_value() {
  local key="$1"
  /usr/libexec/PlistBuddy -c "Print :$key" \
    "$APP_PATH/Contents/Info.plist" 2>/dev/null
}

app_version() {
  plist_value "CFBundleShortVersionString"
}

app_build() {
  plist_value "CFBundleVersion"
}

app_bundle_id() {
  plist_value "CFBundleIdentifier"
}

validate_requested_mode() {
  case "$REQUESTED_MODE" in
    auto|core) ;;
    *) die "DIA_ZH_MODE 仅支持 core；不提供对未知版本强制执行完整替换的选项。" ;;
  esac
}

lookup_known_build() {
  local version="$1" build="$2"
  osascript -l JavaScript -e '
    ObjC.import("Foundation");
    function read(path) {
      return ObjC.unwrap($.NSString.stringWithContentsOfFileEncodingError(
        path, $.NSUTF8StringEncoding, null
      ));
    }
    function run(argv) {
      const index = JSON.parse(read(argv[0]));
      const found = index.knownBuilds.find(
        item => item.shortVersion === argv[1] && item.buildVersion === argv[2]
      );
      if (!found) return "";
      return [
        found.manifest,
        found.originalWebHashes,
        found.patchedWebHashes
      ].join("\t");
    }' "$MANIFEST_INDEX" "$version" "$build"
}

load_known_manifest() {
  local record="$1" manifest_relative original_relative patched_relative
  IFS=$'\t' read -r \
    manifest_relative original_relative patched_relative <<< "$record"
  MANIFEST="$SCRIPT_DIR/$manifest_relative"
  WEB_HASHES_ORIGINAL="$SCRIPT_DIR/$original_relative"
  WEB_HASHES_PATCHED="$SCRIPT_DIR/$patched_relative"
  [[ -f "$MANIFEST" ]] || die "版本索引引用了不存在的清单：$MANIFEST"
  [[ -f "$WEB_HASHES_ORIGINAL" ]] || die "缺少官方 WebUI 哈希清单。"
  [[ -f "$WEB_HASHES_PATCHED" ]] || die "缺少补丁后 WebUI 哈希清单。"
}

core_structure_reason() {
  local locale_root="$APP_PATH/Contents/Frameworks/ArcCore.framework/Versions/A/Resources"
  local executable="$APP_PATH/Contents/MacOS/Dia"
  [[ "$(app_bundle_id 2>/dev/null || true)" == "$SUPPORTED_BUNDLE_ID" ]] ||
    { print -r -- "Bundle ID 异常"; return 1; }
  [[ -f "$executable" ]] || { print -r -- "缺少主程序 Mach-O"; return 1; }
  lipo -archs "$executable" 2>/dev/null | grep -qw "arm64" ||
    { print -r -- "主程序不含 arm64 架构"; return 1; }
  [[ -f "$locale_root/zh_CN.lproj/locale.pak" ]] ||
    { print -r -- "缺少官方简体中文 Chromium 资源"; return 1; }
  [[ -f "$locale_root/en.lproj/locale.pak" ]] ||
    { print -r -- "缺少 Chromium 英文资源入口"; return 1; }
  [[ -d "$APP_PATH/Contents/Resources" ]] ||
    { print -r -- "缺少主资源目录"; return 1; }
  [[ -d "$APP_PATH/Contents/Frameworks/ArcCore.framework" ]] ||
    { print -r -- "缺少 ArcCore.framework"; return 1; }
}

detect_coverage() {
  COVERAGE_MODE="incompatible"
  COVERAGE_REASON=""
  MANIFEST=""
  WEB_HASHES_ORIGINAL=""
  WEB_HASHES_PATCHED=""

  local reason known
  if ! reason="$(core_structure_reason)"; then
    COVERAGE_REASON="$reason"
    return 1
  fi

  known="$(lookup_known_build "$(app_version)" "$(app_build)")"
  if [[ -n "$known" ]]; then
    load_known_manifest "$known"
    if [[ "$REQUESTED_MODE" == "core" ]]; then
      COVERAGE_MODE="core"
      COVERAGE_REASON="已知 Build，按 DIA_ZH_MODE=core 跳过 WebUI"
    else
      COVERAGE_MODE="full"
      COVERAGE_REASON="已验证 Build，启用完整汉化"
    fi
  else
    COVERAGE_MODE="core"
    COVERAGE_REASON="结构兼容的未知 Build，安全跳过 WebUI"
  fi
}

acquire_lock() {
  mkdir -p "$STATE_ROOT"
  if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    die "另一个 dia-zh 进程可能仍在运行：$LOCK_DIR"
  fi
  LOCK_HELD=1
}

release_lock() {
  if (( LOCK_HELD )); then
    rmdir "$LOCK_DIR" 2>/dev/null || true
    LOCK_HELD=0
  fi
}

safe_remove_tree() {
  local target="$1"
  [[ -n "$target" ]] || die "拒绝删除空路径。"
  [[ "$target" == "$STATE_ROOT"/* ]] ||
    die "拒绝删除状态目录以外的路径：$target"
  [[ "$target" != "$STATE_ROOT" ]] || die "拒绝删除整个状态目录。"
  rm -rf -- "$target"
}

safe_remove_current_app() {
  local target="$1"
  [[ "$target" == "$APP_PATH" ]] || die "拒绝删除非目标应用：$target"
  [[ "$target" == */Dia.app ]] || die "拒绝删除名称不是 Dia.app 的目标。"
  [[ "$(dirname -- "$target")" != "/" ]] ||
    die "拒绝操作文件系统根目录下的应用。"
  rm -rf -- "$target"
}

stop_dia() {
  local force_for_rollback="${1:-0}"
  [[ "$APP_PATH" == "/Applications/Dia.app" ]] || return 0
  if pgrep -x "Dia" >/dev/null 2>&1; then
    log "正在退出 Dia…"
    osascript -e 'tell application "Dia" to quit' >/dev/null 2>&1 || true
    local attempt
    for attempt in {1..20}; do
      pgrep -x "Dia" >/dev/null 2>&1 || return 0
      sleep 0.5
    done
    if [[ "$force_for_rollback" == "1" ]]; then
      warn "自动回滚等待 Dia 正常退出超时，正在终止本次冒烟检查启动的进程。"
      pkill -TERM -x "Dia" >/dev/null 2>&1 || true
      for attempt in {1..10}; do
        pgrep -x "Dia" >/dev/null 2>&1 || return 0
        sleep 0.5
      done
    fi
    die "Dia 未能正常退出，请手动退出后重试。"
  fi
}

verify_signature() {
  codesign --verify --deep --strict "$1" >/dev/null 2>&1
}

signature_team_id() {
  codesign -dv --verbose=4 "$1" 2>&1 |
    awk -F= '$1 == "TeamIdentifier" {print $2; exit}'
}

verify_official_signature_path() {
  local target="$1" signature_info team_id
  verify_signature "$target" || return 1
  signature_info="$(codesign -dv --verbose=4 "$target" 2>&1)"
  team_id="$(print -r -- "$signature_info" |
    awk -F= '$1 == "TeamIdentifier" {print $2; exit}')"
  [[ "$team_id" == "$OFFICIAL_TEAM_ID" ]] || return 1
  print -r -- "$signature_info" | grep -q \
    "^Authority=Developer ID Application: The Browser Company of New York Inc. ($OFFICIAL_TEAM_ID)$"
}

verify_official_signature() {
  verify_official_signature_path "$APP_PATH" ||
    die "Dia 官方签名身份或严格校验失败；请重新安装官方版本。"
}

state_value() {
  local key="$1" file="${2:-$STATE_FILE}"
  [[ -f "$file" ]] || return 1
  awk -F= -v wanted="$key" \
    '$1 == wanted { print substr($0, index($0, "=") + 1); exit }' "$file"
}

state_matches_current_build() {
  [[ -f "$STATE_FILE" ]] || return 1
  [[ "$(state_value APP_PATH)" == "$APP_PATH" ]] || return 1
  [[ "$(state_value SOURCE_VERSION)" == "$(app_version)" ]] || return 1
  [[ "$(state_value SOURCE_BUILD)" == "$(app_build)" ]]
}

write_state() {
  local state_status="$1" backup_path="$2" timestamp="$3"
  local mode="$4" menu_hash="$5"
  local temp="$STATE_FILE.tmp.$$"
  umask 077
  {
    print -r -- "SCHEMA_VERSION=2"
    print -r -- "STATUS=$state_status"
    print -r -- "PATCH_VERSION=$PATCH_VERSION"
    print -r -- "APP_PATH=$APP_PATH"
    print -r -- "SOURCE_VERSION=$(app_version)"
    print -r -- "SOURCE_BUILD=$(app_build)"
    print -r -- "COVERAGE_MODE=$mode"
    print -r -- "BACKUP_PATH=$backup_path"
    print -r -- "MENU_DYLIB_SHA256=$menu_hash"
    print -r -- "TIMESTAMP=$timestamp"
  } > "$temp"
  mv -f "$temp" "$STATE_FILE"
}

archive_superseded_state() {
  [[ -f "$STATE_FILE" ]] || return 0
  local source_build timestamp destination
  source_build="$(state_value SOURCE_BUILD 2>/dev/null || print unknown)"
  timestamp="$(date -u '+%Y%m%dT%H%M%SZ')"
  destination="$STATE_ROOT/superseded/$source_build-$timestamp.state"
  mkdir -p "$(dirname -- "$destination")"
  mv "$STATE_FILE" "$destination"
  {
    print -r -- "SUPERSEDED_BY_VERSION=$(app_version)"
    print -r -- "SUPERSEDED_BY_BUILD=$(app_build)"
    print -r -- "SUPERSEDED_AT=$timestamp"
  } >> "$destination"
  warn "检测到 Dia 官方更新；旧补丁状态已标记为 superseded，不会用旧备份覆盖新 Build。"
}

prepare_state_for_apply() {
  [[ -f "$STATE_FILE" ]] || return 0
  if state_matches_current_build; then
    die "当前 Build 已有补丁状态。请先运行 status；需要重装时先执行 restore。"
  fi
  verify_official_signature ||
    die "补丁状态与当前 Build 不一致，且当前 Dia 不是有效官方签名；拒绝继续。"
  archive_superseded_state
}

check_chromium_locale() {
  local root="$APP_PATH/Contents/Frameworks/ArcCore.framework/Versions/A/Resources"
  local source="$root/zh_CN.lproj/locale.pak"
  local destination="$root/en.lproj/locale.pak"
  [[ -f "$source" ]] || die "缺少官方中文 Chromium locale：$source"
  [[ -f "$destination" ]] || die "缺少英文 Chromium locale：$destination"
  local bytes
  bytes="$(stat -f '%z' "$source")"
  (( bytes >= 500000 )) || die "中文 locale.pak 大小异常：$bytes bytes"
}

verify_chromium_locale_patched() {
  local root="$APP_PATH/Contents/Frameworks/ArcCore.framework/Versions/A/Resources"
  cmp -s "$root/zh_CN.lproj/locale.pak" "$root/en.lproj/locale.pak" ||
    die "Chromium 英文入口尚未切换到官方简体中文 locale.pak。"
}

verify_localizations() {
  local resource_root="$APP_PATH/Contents/Resources"
  local locale bundle prefix count=0
  for locale in "en.lproj" "zh-Hans.lproj"; do
    cmp -s "$STRINGS_FILE" "$resource_root/$locale/Localizable.strings" ||
      die "主程序本地化文件缺失或内容不一致：$locale"
  done
  for prefix in "BoostBrowser_" "ARC_" "ARCUI_" "ARCClients_"; do
    while IFS= read -r bundle; do
      [[ -d "$bundle/Contents/Resources" ]] || continue
      for locale in "en.lproj" "zh-Hans.lproj"; do
        cmp -s "$STRINGS_FILE" \
          "$bundle/Contents/Resources/$locale/Localizable.strings" ||
          die "Bundle 本地化文件缺失或内容不一致：$bundle/$locale"
      done
      count=$(( count + 1 ))
    done < <(
      find "$resource_root" -maxdepth 1 -type d \
        -name "${prefix}*.bundle" -print | LC_ALL=C sort
    )
  done
  (( count > 0 )) || die "未找到需要验证的 Dia 资源 Bundle。"
  log "主程序与 $count 个资源 Bundle 的本地化文件校验通过。"
}

manifest_critical_files() {
  osascript -l JavaScript -e '
    ObjC.import("Foundation");
    function run(argv) {
      const text = ObjC.unwrap($.NSString.stringWithContentsOfFileEncodingError(
        argv[0], $.NSUTF8StringEncoding, null
      ));
      return JSON.parse(text).criticalFiles
        .map(item => `${item.path}|${item.bytes}`).join("\n");
    }' "$MANIFEST"
}

check_critical_files() {
  local entry relative expected actual
  while IFS= read -r entry; do
    [[ -n "$entry" ]] || continue
    relative="${entry%%|*}"
    expected="${entry##*|}"
    [[ -f "$APP_PATH/$relative" ]] ||
      die "缺少已知 Build 的关键资源：$relative"
    actual="$(stat -f '%z' "$APP_PATH/$relative")"
    [[ "$actual" == "$expected" ]] ||
      die "关键资源大小异常：$relative，预期 $expected，实际 $actual。"
  done < <(manifest_critical_files)
}

verify_web_hash_manifest() {
  local kind="$1" hashes
  case "$kind" in
    original) hashes="$WEB_HASHES_ORIGINAL" ;;
    patched) hashes="$WEB_HASHES_PATCHED" ;;
    *) die "未知 WebUI 哈希清单类型：$kind" ;;
  esac
  (
    cd "$APP_PATH"
    shasum -a 256 -c "$hashes" >/dev/null
  ) || die "WebUI $kind SHA-256 校验失败；已知 Build 资源与清单不一致。"
  log "WebUI $kind SHA-256 校验通过。"
}

run_web_audit() {
  local mode="$1" report="$2"
  mkdir -p "$(dirname -- "$report")"
  osascript -l JavaScript \
    "$WEB_HELPER" "$mode" "$APP_PATH" "$MANIFEST" "$report" >/dev/null
  log "WebUI 审计报告：$report"
}

menu_environment_value() {
  /usr/libexec/PlistBuddy -c \
    "Print :LSEnvironment:DYLD_INSERT_LIBRARIES" \
    "$APP_PATH/Contents/Info.plist" 2>/dev/null
}

preflight_menu_environment() {
  local existing
  existing="$(menu_environment_value || true)"
  [[ -z "$existing" || "$existing" == "$MENU_LOAD_PATH" ]] ||
    die "Dia 已配置其他 DYLD_INSERT_LIBRARIES，拒绝覆盖：$existing"
}

verify_menu_installation() {
  local installed="$APP_PATH/Contents/Frameworks/DiaZhMenu.dylib"
  local resource="$APP_PATH/Contents/Resources/DiaZhPatch"
  [[ -f "$installed" ]] || die "菜单动态库未安装。"
  [[ "$(menu_environment_value || true)" == "$MENU_LOAD_PATH" ]] ||
    die "菜单动态库加载配置不一致。"
  cmp -s "$STRINGS_FILE" "$resource/zh-Hans.strings" ||
    die "菜单动态库词表不一致。"
  cmp -s "$MENU_KEYS_FILE" "$resource/menu-keys.txt" ||
    die "菜单键白名单不一致。"
  if [[ -f "$STATE_FILE" ]]; then
    local expected actual
    expected="$(state_value MENU_DYLIB_SHA256 2>/dev/null || true)"
    actual="$(shasum -a 256 "$installed" | awk '{print $1}')"
    [[ -z "$expected" || "$actual" == "$expected" ]] ||
      die "菜单动态库哈希与状态文件不一致。"
  fi
}

ensure_backup_space() {
  mkdir -p "$STATE_ROOT"
  local app_kb available_kb required_kb
  app_kb="$(du -sk "$APP_PATH" | awk '{print $1}')"
  available_kb="$(df -Pk "$STATE_ROOT" | awk 'NR == 2 {print $4}')"
  required_kb=$(( app_kb * 2 ))
  (( available_kb >= required_kb )) ||
    die "可用空间不足。至少需要约 $(( required_kb / 1024 )) MiB，当前可用约 $(( available_kb / 1024 )) MiB。"
}

create_backup() {
  local timestamp="$1"
  local version="$(app_version)" build="$(app_build)"
  local backup_dir="$BACKUP_ROOT/$version-$build/$timestamp"
  local backup="$backup_dir/Dia.app.zip"
  local temp="$backup.tmp"
  local verification="$backup_dir/verify-$$"

  mkdir -p "$backup_dir"
  log "正在创建完整官方备份：$backup"
  ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$temp"
  mv -f "$temp" "$backup"
  [[ -s "$backup" ]] || die "备份文件为空。"
  mkdir -p "$verification"
  ditto -x -k "$backup" "$verification"
  [[ -d "$verification/Dia.app" ]] || die "备份验证解压后缺少 Dia.app。"
  verify_official_signature_path "$verification/Dia.app" ||
    die "备份验证中的 Dia 官方签名身份无效。"
  safe_remove_tree "$verification"
  CREATED_BACKUP="$backup"
  log "完整备份已解压复核，官方签名有效。"
}

install_chromium_locale() {
  local root="$APP_PATH/Contents/Frameworks/ArcCore.framework/Versions/A/Resources"
  cp -p "$root/zh_CN.lproj/locale.pak" "$root/en.lproj/locale.pak"
  log "已启用 Dia 包内的官方 Chromium 简体中文资源。"
}

install_localizations() {
  local resource_root="$APP_PATH/Contents/Resources"
  local locale bundle prefix count=0
  for locale in "en.lproj" "zh-Hans.lproj"; do
    mkdir -p "$resource_root/$locale"
    cp -p "$STRINGS_FILE" "$resource_root/$locale/Localizable.strings"
  done

  for prefix in "BoostBrowser_" "ARC_" "ARCUI_" "ARCClients_"; do
    while IFS= read -r bundle; do
      [[ -d "$bundle/Contents/Resources" ]] || continue
      for locale in "en.lproj" "zh-Hans.lproj"; do
        mkdir -p "$bundle/Contents/Resources/$locale"
        cp -p "$STRINGS_FILE" \
          "$bundle/Contents/Resources/$locale/Localizable.strings"
      done
      count=$(( count + 1 ))
    done < <(
      find "$resource_root" -maxdepth 1 -type d \
        -name "${prefix}*.bundle" -print | LC_ALL=C sort
    )
  done
  log "已向 $count 个 Dia 资源 Bundle 注入统一词表。"
}

install_menu_translator() {
  local destination="$APP_PATH/Contents/Frameworks/DiaZhMenu.dylib"
  local resource="$APP_PATH/Contents/Resources/DiaZhPatch"
  mkdir -p "$resource"
  cp -p "$MENU_DYLIB" "$destination"
  cp -p "$STRINGS_FILE" "$resource/zh-Hans.strings"
  cp -p "$MENU_KEYS_FILE" "$resource/menu-keys.txt"

  /usr/libexec/PlistBuddy -c "Add :LSEnvironment dict" \
    "$APP_PATH/Contents/Info.plist" >/dev/null 2>&1 || true
  /usr/libexec/PlistBuddy -c \
    "Set :LSEnvironment:DYLD_INSERT_LIBRARIES $MENU_LOAD_PATH" \
    "$APP_PATH/Contents/Info.plist" >/dev/null 2>&1 ||
    /usr/libexec/PlistBuddy -c \
      "Add :LSEnvironment:DYLD_INSERT_LIBRARIES string $MENU_LOAD_PATH" \
      "$APP_PATH/Contents/Info.plist" >/dev/null
  log "已安装菜单翻译器及其统一词表。"
}

apply_web_rules() {
  local report="$1"
  osascript -l JavaScript \
    "$WEB_HELPER" apply "$APP_PATH" "$MANIFEST" "$report" >/dev/null
  log "WebUI 精确替换报告：$report"
}

smoke_test() {
  if [[ "${DIA_ZH_SKIP_SMOKE:-0}" == "1" ]]; then
    warn "测试环境已跳过应用启动检查。"
    return 0
  fi

  log "正在启动 Dia 进行冒烟检查…"
  open -na "$APP_PATH"
  local attempt
  for attempt in {1..30}; do
    pgrep -x "Dia" >/dev/null 2>&1 && break
    sleep 0.5
  done
  if ! pgrep -x "Dia" >/dev/null 2>&1; then
    print -ru2 -- "[dia-zh] 错误：Dia 未能启动。"
    return 1
  fi

  if [[ "${DIA_ZH_ASSUME_SMOKE_OK:-0}" == "1" ]]; then
    warn "已通过 DIA_ZH_ASSUME_SMOKE_OK 接受非交互冒烟检查。"
    return 0
  fi
  if [[ ! -t 0 ]]; then
    print -ru2 -- \
      "[dia-zh] 错误：非交互执行必须设置 DIA_ZH_ASSUME_SMOKE_OK=1，否则无法确认关键功能。"
    return 1
  fi
  print
  print -r -- "请检查：新标签页、普通网页、聊天、设置、扩展和菜单。"
  print -n -r -- "以上功能是否正常？输入 yes 提交，其他输入将自动回滚："
  local answer
  read -r answer
  if [[ "$answer" != "yes" ]]; then
    print -ru2 -- "[dia-zh] 错误：用户未确认功能正常。"
    return 1
  fi
}

restore_from_state() {
  local automatic="${1:-0}"
  [[ -f "$STATE_FILE" ]] || die "没有当前补丁状态或可恢复备份。"
  [[ "$(state_value SCHEMA_VERSION)" == "2" ]] ||
    die "状态文件版本过旧；请使用创建它的补丁版本执行恢复。"

  local backup expected_app expected_version expected_build
  backup="$(state_value BACKUP_PATH)"
  expected_app="$(state_value APP_PATH)"
  expected_version="$(state_value SOURCE_VERSION)"
  expected_build="$(state_value SOURCE_BUILD)"
  [[ "$expected_app" == "$APP_PATH" ]] || die "备份对应其他应用路径：$expected_app"
  [[ -f "$backup" ]] || die "备份文件不存在：$backup"

  local had_current_app=0
  if [[ -d "$APP_PATH" ]]; then
    had_current_app=1
    if [[ "$(app_version)" != "$expected_version" ||
          "$(app_build)" != "$expected_build" ]]; then
      die "当前 Dia 已更新为 $(app_version) ($(app_build))，拒绝用旧备份覆盖。"
    fi
  fi

  stop_dia "$automatic"
  local stamp stage restored retired
  stamp="$(date -u '+%Y%m%dT%H%M%SZ')-$$"
  stage="$STATE_ROOT/restore-$stamp"
  retired="$STATE_ROOT/patched-Dia-$stamp.app"
  mkdir -p "$stage"
  log "正在解压官方备份…"
  ditto -x -k "$backup" "$stage"
  restored="$stage/Dia.app"
  [[ -d "$restored" ]] || die "备份中没有 Dia.app。"
  verify_official_signature_path "$restored" ||
    die "备份中的 Dia 官方签名身份无效。"

  if (( had_current_app )); then
    mv "$APP_PATH" "$retired"
  fi
  if ! mv "$restored" "$APP_PATH"; then
    (( had_current_app )) && mv "$retired" "$APP_PATH" || true
    die "无法把恢复版本放回原路径。"
  fi

  if ! verify_official_signature_path "$APP_PATH"; then
    safe_remove_current_app "$APP_PATH"
    (( had_current_app )) && mv "$retired" "$APP_PATH" || true
    die "恢复后的官方签名校验失败，已尝试放回补丁版本。"
  fi

  (( had_current_app )) && safe_remove_tree "$retired"
  safe_remove_tree "$stage"
  rm -f "$STATE_FILE"
  APPLY_ACTIVE=0
  if (( automatic )); then
    warn "安装失败，已自动恢复原版 Dia。"
  else
    log "已恢复原版 Dia，官方 Team ID 与严格签名均通过。"
  fi
}

on_exit() {
  local code="$1"
  if (( APPLY_ACTIVE )); then
    warn "安装未完成，开始自动回滚。"
    APPLY_ACTIVE=0
    DIA_ZH_LIBRARY_ONLY=1 /bin/zsh -c \
      'source "$1"; restore_from_state 1' _ "$SCRIPT_DIR/dia-zh.command" ||
      warn "自动回滚失败，请保留 $STATE_FILE 并手动检查。"
  fi
  release_lock
  return "$code"
}

apply_patch_transaction() {
  require_macos
  require_common_project_files
  require_apply_artifacts
  require_app
  validate_requested_mode
  verify_official_signature
  detect_coverage || die "当前 Dia 不兼容：$COVERAGE_REASON"
  check_chromium_locale
  preflight_menu_environment
  prepare_state_for_apply

  if [[ "$COVERAGE_MODE" == "full" ]]; then
    check_critical_files
    verify_web_hash_manifest original
  fi
  ensure_backup_space

  stop_dia
  acquire_lock
  trap 'release_lock' EXIT INT TERM HUP

  local timestamp backup transaction_dir menu_hash
  timestamp="$(date -u '+%Y%m%dT%H%M%SZ')"
  create_backup "$timestamp"
  backup="$CREATED_BACKUP"
  write_state "applying" "$backup" "$timestamp" "$COVERAGE_MODE" ""
  APPLY_ACTIVE=1
  trap 'on_exit $?' EXIT INT TERM HUP

  transaction_dir="$STATE_ROOT/transactions/$timestamp"
  mkdir -p "$transaction_dir"
  if [[ "$COVERAGE_MODE" == "full" ]]; then
    run_web_audit audit "$transaction_dir/webui-audit.json"
  fi

  install_chromium_locale
  install_localizations
  install_menu_translator
  verify_chromium_locale_patched
  verify_localizations

  if [[ "$COVERAGE_MODE" == "full" ]]; then
    apply_web_rules "$transaction_dir/webui-apply.json"
    verify_web_hash_manifest patched
    run_web_audit verify "$transaction_dir/webui-verify.json"
  fi

  "$SIGN_HELPER" "$APP_PATH" "$transaction_dir/signing"
  verify_menu_installation
  if ! smoke_test; then
    warn "冒烟检查未通过，开始自动回滚。"
    APPLY_ACTIVE=0
    if ! restore_from_state 1; then
      warn "自动回滚失败，请保留 $STATE_FILE 并手动检查。"
    fi
    release_lock
    trap - EXIT INT TERM HUP
    return 1
  fi

  menu_hash="$(shasum -a 256 \
    "$APP_PATH/Contents/Frameworks/DiaZhMenu.dylib" | awk '{print $1}')"
  write_state "applied" "$backup" "$timestamp" "$COVERAGE_MODE" "$menu_hash"
  APPLY_ACTIVE=0
  trap - EXIT INT TERM HUP
  release_lock
  log "Dia 简体中文补丁 $PATCH_VERSION 安装完成（$COVERAGE_MODE）。"
  log "如有异常，请运行：$SCRIPT_DIR/dia-zh.command restore"
}

audit_all() {
  require_macos
  require_common_project_files
  require_app
  validate_requested_mode

  local patched=0 stale=0 mode recorded_status
  if [[ -f "$STATE_FILE" ]] && state_matches_current_build; then
    patched=1
    mode="$(state_value COVERAGE_MODE 2>/dev/null || print incompatible)"
    recorded_status="$(state_value STATUS 2>/dev/null || print unknown)"
    [[ "$(state_value SCHEMA_VERSION 2>/dev/null || true)" == "2" ]] ||
      die "当前状态文件不是 schema v2。"
    [[ "$recorded_status" == "applied" ]] ||
      die "补丁状态为 $recorded_status；请先恢复或完成安装。"
    verify_signature "$APP_PATH" || die "Dia 严格签名校验失败。"
    COVERAGE_MODE="$mode"
    COVERAGE_REASON="由 schema v2 状态文件记录"
  else
    [[ -f "$STATE_FILE" ]] && stale=1
    verify_official_signature
    detect_coverage || die "当前 Dia 不兼容：$COVERAGE_REASON"
  fi

  check_chromium_locale
  mkdir -p "$REPORT_DIR"
  local stamp report
  stamp="$(date -u '+%Y%m%dT%H%M%SZ')"
  report="$REPORT_DIR/audit-$(app_build)-$stamp.json"

  if (( patched )); then
    verify_chromium_locale_patched
    verify_localizations
    verify_menu_installation
    if [[ "$COVERAGE_MODE" == "full" ]]; then
      detect_coverage
      verify_web_hash_manifest patched
      run_web_audit verify "$report"
    fi
  elif [[ "$COVERAGE_MODE" == "full" ]]; then
    check_critical_files
    verify_web_hash_manifest original
    run_web_audit audit "$report"
  fi

  log "版本：$(app_version) ($(app_build))"
  log "覆盖级别：$COVERAGE_MODE"
  log "判断：$COVERAGE_REASON"
  (( stale )) &&
    warn "检测到旧 Build 状态；当前官方版本不会被旧备份覆盖，下次 apply 会归档旧状态。"
  log "只读审计通过，未修改 Dia.app。"
}

signature_description() {
  if verify_official_signature_path "$APP_PATH"; then
    print -r -- "Dia 官方签名"
  elif verify_signature "$APP_PATH"; then
    local team
    team="$(signature_team_id "$APP_PATH" 2>/dev/null || true)"
    if [[ -z "$team" || "$team" == "not set" ]]; then
      print -r -- "有效的统一 ad-hoc 签名"
    else
      print -r -- "有效但身份异常（Team ID: $team）"
    fi
  else
    print -r -- "签名无效"
  fi
}

show_status() {
  require_macos
  require_common_project_files
  require_app
  validate_requested_mode

  local patch_status="未安装" coverage reason stale="no"
  if [[ -f "$STATE_FILE" ]] && state_matches_current_build; then
    patch_status="$(state_value STATUS 2>/dev/null || print unknown)"
    coverage="$(state_value COVERAGE_MODE 2>/dev/null || print incompatible)"
    reason="由状态文件记录"
  else
    [[ -f "$STATE_FILE" ]] && stale="yes"
    if detect_coverage; then
      coverage="$COVERAGE_MODE"
      reason="$COVERAGE_REASON"
    else
      coverage="incompatible"
      reason="$COVERAGE_REASON"
    fi
  fi

  print -r -- "Dia 路径：$APP_PATH"
  print -r -- "版本：$(app_version) ($(app_build))"
  print -r -- "签名：$(signature_description)"
  print -r -- "补丁状态：$patch_status"
  print -r -- "覆盖级别：$coverage"
  print -r -- "判断：$reason"
  if [[ -f "$STATE_FILE" ]]; then
    print -r -- "状态 schema：$(state_value SCHEMA_VERSION 2>/dev/null || print unknown)"
    print -r -- "状态源 Build：$(state_value SOURCE_BUILD 2>/dev/null || print unknown)"
    print -r -- "备份：$(state_value BACKUP_PATH 2>/dev/null || print unknown)"
  fi
  if [[ "$stale" == "yes" ]]; then
    warn "旧状态已被当前 Build 取代；apply 将安全归档它，restore 不会跨 Build 覆盖。"
  fi
}

restore_command() {
  require_macos
  require_common_project_files
  require_app
  acquire_lock
  trap 'release_lock' EXIT INT TERM HUP
  restore_from_state 0
  release_lock
  trap - EXIT INT TERM HUP
}

interactive_menu() {
  print -r -- "Dia 简体中文补丁 $PATCH_VERSION"
  print -r -- "1) 安装补丁"
  print -r -- "2) 只读审计"
  print -r -- "3) 查看状态"
  print -r -- "4) 恢复原版"
  print -r -- "5) 退出"
  print -n -r -- "请选择 [1-5]："
  local choice
  read -r choice
  case "$choice" in
    1) apply_patch_transaction ;;
    2) audit_all ;;
    3) show_status ;;
    4) restore_command ;;
    5) return 0 ;;
    *) die "无效选择。" ;;
  esac
}

main() {
  local command="${1:-}"
  case "$command" in
    apply) apply_patch_transaction ;;
    audit) audit_all ;;
    status) show_status ;;
    restore) restore_command ;;
    help|-h|--help) usage ;;
    "") interactive_menu ;;
    *)
      usage
      die "未知命令：$command"
      ;;
  esac
}

if [[ "${DIA_ZH_LIBRARY_ONLY:-0}" != "1" ]]; then
  main "$@"
fi
