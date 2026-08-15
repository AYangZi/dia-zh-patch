#!/bin/zsh

set -euo pipefail
setopt NO_NOMATCH

readonly APP_PATH="${1:?用法：sign-app.zsh /path/to/Dia.app /path/to/work-dir}"
readonly WORK_DIR="${2:?用法：sign-app.zsh /path/to/Dia.app /path/to/work-dir}"
readonly ENTITLEMENTS_DIR="$WORK_DIR/entitlements"
readonly EMPTY_ENTITLEMENTS="$WORK_DIR/empty-entitlements.plist"

typeset -ga MACHO_TARGETS=()
typeset -ga BUNDLE_TARGETS=()

die() {
  print -ru2 -- "[sign-app] 错误：$*"
  exit 1
}

target_key() {
  print -rn -- "$1" | LC_ALL=C shasum -a 256 | awk '{print $1}'
}

entitlements_path() {
  print -r -- "$ENTITLEMENTS_DIR/$(target_key "$1").plist"
}

sort_deepest_first() {
  awk '{ print length($0) "\t" $0 }' |
    LC_ALL=C sort -rn |
    cut -f2-
}

discover_targets() {
  local target
  while IFS= read -r target; do
    file "$target" | grep -q "Mach-O" && MACHO_TARGETS+=("$target")
  done < <(find "$APP_PATH/Contents" -type f -print | LC_ALL=C sort)

  while IFS= read -r target; do
    if [[ "$target" == *.bundle &&
          ! -f "$target/Contents/Info.plist" ]]; then
      continue
    fi
    BUNDLE_TARGETS+=("$target")
  done < <(
    find "$APP_PATH/Contents" -type d \
      \( -name '*.app' -o -name '*.xpc' -o -name '*.framework' \
         -o -name '*.plugin' -o -name '*.bundle' \) -print |
      sort_deepest_first
  )

  (( ${#MACHO_TARGETS[@]} > 0 )) || die "未发现 Mach-O 文件。"
}

make_empty_entitlements() {
  /usr/bin/plutil -create xml1 "$EMPTY_ENTITLEMENTS"
}

sanitize_entitlements() {
  local target="$1" destination="$2"
  local raw="$destination.raw"
  codesign -d --entitlements :- "$target" > "$raw" 2>/dev/null || true
  if [[ -s "$raw" ]] && plutil -lint "$raw" >/dev/null 2>&1; then
    cp -p "$raw" "$destination"
    plutil -convert xml1 "$destination"
  else
    cp -p "$EMPTY_ENTITLEMENTS" "$destination"
  fi
  rm -f "$raw"

  local restricted
  for restricted in \
    "com.apple.application-identifier" \
    "com.apple.developer.associated-domains" \
    "com.apple.developer.team-identifier" \
    "com.apple.developer.web-browser.public-key-credential" \
    "keychain-access-groups"; do
    /usr/libexec/PlistBuddy -c "Delete :$restricted" \
      "$destination" >/dev/null 2>&1 || true
  done

  /usr/libexec/PlistBuddy -c \
    "Set :com.apple.security.cs.disable-library-validation true" \
    "$destination" >/dev/null 2>&1 ||
    /usr/libexec/PlistBuddy -c \
      "Add :com.apple.security.cs.disable-library-validation bool true" \
      "$destination" >/dev/null
  if [[ "$target" == "$APP_PATH" ]]; then
    /usr/libexec/PlistBuddy -c \
      "Set :com.apple.security.cs.allow-dyld-environment-variables true" \
      "$destination" >/dev/null 2>&1 ||
      /usr/libexec/PlistBuddy -c \
        "Add :com.apple.security.cs.allow-dyld-environment-variables bool true" \
        "$destination" >/dev/null
  fi
  plutil -lint "$destination" >/dev/null
}

capture_entitlements() {
  mkdir -p "$ENTITLEMENTS_DIR"
  make_empty_entitlements
  local target
  for target in "${MACHO_TARGETS[@]}" "${BUNDLE_TARGETS[@]}" "$APP_PATH"; do
    sanitize_entitlements "$target" "$(entitlements_path "$target")"
  done
}

sign_target() {
  local target="$1" entitlements
  entitlements="$(entitlements_path "$target")"
  codesign --force --sign - --timestamp=none --options runtime \
    --entitlements "$entitlements" "$target" >/dev/null 2>&1 ||
    die "无法签名：$target"
}

sign_all() {
  local target
  while IFS= read -r target; do
    sign_target "$target"
  done < <(print -rl -- "${MACHO_TARGETS[@]}" | sort_deepest_first)

  for target in "${BUNDLE_TARGETS[@]}"; do
    sign_target "$target"
  done
  sign_target "$APP_PATH"
}

entitlement_is_true() {
  local target="$1" key="$2"
  local extracted="$WORK_DIR/check-$(target_key "$target").plist"
  codesign -d --entitlements :- "$target" > "$extracted" 2>/dev/null || true
  [[ -s "$extracted" ]] || return 1
  /usr/libexec/PlistBuddy -c "Print :$key" "$extracted" 2>/dev/null |
    grep -qx "true"
}

verify_all() {
  codesign --verify --deep --strict "$APP_PATH" >/dev/null ||
    die "codesign --verify --deep --strict 未通过。"

  local target info team
  for target in "${MACHO_TARGETS[@]}" "${BUNDLE_TARGETS[@]}" "$APP_PATH"; do
    codesign --verify --strict "$target" >/dev/null 2>&1 ||
      die "内部组件签名无效：$target"
    info="$(codesign -dv --verbose=4 "$target" 2>&1 || true)"
    print -r -- "$info" | grep -q '^Signature=adhoc$' ||
      die "内部组件不是统一的 ad-hoc 身份：$target"
    team="$(print -r -- "$info" |
      awk -F= '$1 == "TeamIdentifier" {print $2; exit}')"
    [[ -z "$team" || "$team" == "not set" ]] ||
      die "内部组件仍带 Team ID：$target ($team)"
  done

  entitlement_is_true \
    "$APP_PATH" "com.apple.security.cs.disable-library-validation" ||
    die "Dia.app 未保留 Library Validation 兼容设置。"
  entitlement_is_true \
    "$APP_PATH" "com.apple.security.cs.allow-dyld-environment-variables" ||
    die "Dia.app 未允许已验证的 DYLD 菜单加载环境变量。"

  local helper
  for helper in \
    "$APP_PATH/Contents/Frameworks/ArcCore.framework/Versions/A/Helpers/Browser Helper (GPU).app" \
    "$APP_PATH/Contents/Frameworks/ArcCore.framework/Versions/A/Helpers/Browser Helper (Renderer).app"; do
    [[ -d "$helper" ]] || continue
    entitlement_is_true "$helper" "com.apple.security.cs.allow-jit" ||
      die "$(basename "$helper") 的 JIT 权限丢失。"
    entitlement_is_true \
      "$helper" "com.apple.security.cs.disable-library-validation" ||
      die "$(basename "$helper") 的 Library Validation 设置丢失。"
  done
}

[[ -d "$APP_PATH" && "$APP_PATH" == */Dia.app ]] ||
  die "目标必须是 Dia.app。"
mkdir -p "$WORK_DIR"
discover_targets
capture_entitlements
sign_all
verify_all
print -r -- "[sign-app] 已按内部 Mach-O → 嵌套 Bundle → Dia.app 完成统一签名。"
