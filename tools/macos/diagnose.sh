#!/bin/sh
# ============================================================================
# dsh-boot-suite —— 一键诊断（macOS）
#
# 把环境信息写到桌面：dsh诊断-<yyyyMMdd-HHmmss>.txt
# 用户把这个文件发给作者即可定位问题。只读收集，不改任何东西。
# ============================================================================

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P)
# 公共函数库固定在同目录的 lib/（仓库整理后不再有 tools/lib/）
if [ -f "$SCRIPT_DIR/lib/mac-common.sh" ]; then
  . "$SCRIPT_DIR/lib/mac-common.sh"
else
  printf '[x] 缺少公共函数库：%s\n' "$SCRIPT_DIR/lib/mac-common.sh" >&2
  exit 1
fi
PROFILE_JSON_TOOL="$SCRIPT_DIR/lib/profile-json.mjs"

Say() { printf '%s\n' "$*"; }

read_version() {
  sed -n 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$1" 2>/dev/null | head -n 1
}
# 仓库根：从 tools/macos/ 上两级
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd -P)
VER=$(read_version "$REPO_ROOT/package.json")
if [ -n "$VER" ]; then Say "dsh-boot-suite v$VER"; fi
Say "脚本位置：$SCRIPT_DIR"

if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
  cat <<'EOF'
dsh-boot-suite —— macOS 一键诊断

用法：
  sh tools/macos/diagnose.sh
  （也可以双击仓库根目录的 setup.command，选 3）

会在桌面生成 dsh诊断-<时间>.txt，把这个文件发给作者即可。
EOF
  exit 0
fi

STAMP=$(date +%Y%m%d-%H%M%S)
OUT="$(dsh_desktop_dir)/dsh诊断-$STAMP.txt"
if ! : > "$OUT" 2>/dev/null; then
  OUT="$(dsh_home)/dsh诊断-$STAMP.txt"
  : > "$OUT" 2>/dev/null || { printf '[x] 无法创建诊断报告文件：%s\n' "$OUT" >&2; exit 1; }
fi

# L：同时写到屏幕和报告文件
L() {
  printf '%s\n' "$*" >> "$OUT"
  printf '%s\n' "$*"
}
# Block：把 stdin 每行缩进两格，同时写到屏幕和报告文件
Block() {
  sed 's/^/  /' | tee -a "$OUT"
}

L '=== dsh-boot-suite 诊断报告 ==='
L "时间：$(date '+%Y-%m-%d %H:%M:%S')"
L "用户：$(id -un)　机器：$(hostname)"
L ''

L '--- 系统 ---'
sw_vers 2>&1 | tee -a "$OUT"
L "架构：$(uname -m)"
L "内核：$(uname -r)"
L ''

L '--- DSH 安装位置与版本 ---'
APP=$(dsh_find_app 2>/dev/null || true)
if [ -n "$APP" ]; then
  L "安装目录：$APP"
  AV=$(dsh_app_version 2>/dev/null || true)
  [ -n "$AV" ] && L "客户端版本：$AV"
  [ -f "$APP/Contents/Resources/app.asar" ] && L "app 资源：$APP/Contents/Resources/app.asar"
  [ -f "$APP/Contents/Resources/app/package.json" ] && L "app 资源：$APP/Contents/Resources/app/package.json"
  [ -x "$APP/Contents/Resources/runtime/cli/bin/dsh" ] && L "客户端内 CLI：$APP/Contents/Resources/runtime/cli/bin/dsh"
else
  L '（没找到 DeepSeek Harness.app：/Applications 与 ~/Applications 都没有）'
fi
L ''

L '--- dsh 命令行 / node ---'
CLI=$(dsh_find_cli 2>/dev/null || true)
if [ -n "$CLI" ]; then
  L "dsh 命令行：$CLI"
  if [ -L "$CLI" ]; then
    L "  （符号链接 → $(readlink "$CLI" 2>/dev/null)）"
  fi
else
  L 'dsh 命令行：（没找到，安装脚本会走手动安装）'
fi
if command -v node >/dev/null 2>&1; then
  L "node：$(command -v node)（$(node --version 2>/dev/null)）"
else
  L 'node：PATH 里没有（安装脚本会回退到 DSH 客户端自带的 Electron）'
fi
L ''

L '--- 进程 ---'
PROC=$(ps -axo pid=,comm= 2>/dev/null | grep -F 'DeepSeek Harness' | grep -v 'grep' || true)
if [ -n "$PROC" ]; then
  printf '%s\n' "$PROC" | Block
else
  L '（DSH 未运行）'
fi
L ''

L '--- profiles ---'
PROFILES_ROOT=$(dsh_profiles_root)
if [ -d "$PROFILES_ROOT" ]; then
  for _d in "$PROFILES_ROOT"/*; do
    [ -d "$_d" ] || continue
    L "profile：$(basename "$_d")"
    if [ -f "$_d/package.json" ]; then
      L "  package.json：$_d/package.json"
      _show=$(dsh_run_node "$PROFILE_JSON_TOOL" show --profile-dir "$_d" 2>/dev/null || true)
      if [ -n "$_show" ]; then
        printf '%s\n' "$_show" | sed 's/^/  /' | tee -a "$OUT"
      else
        L '  （读不出 dependencies / bundles：node 不可用或 JSON 损坏）'
      fi
    else
      L '  （没有 package.json）'
    fi
    _nm="$_d/node_modules"
    if [ -d "$_nm" ]; then
      for _e in "$_nm"/dsh-*; do
        [ -e "$_e" ] || [ -L "$_e" ] || continue
        if [ -L "$_e" ]; then
          L "  node_modules/$(basename "$_e") → $(readlink "$_e" 2>/dev/null)"
        else
          L "  node_modules/$(basename "$_e")（真实目录）"
        fi
      done
    fi
    for _b in "$_d"/_backup-*; do
      [ -d "$_b" ] && L "  备份目录：$(basename "$_b")"
    done
  done
else
  L '（没有 profiles 目录）'
fi
L ''

L '--- DSH 配置与模板 ---'
_HOME_DIR=$(dsh_home)
for _f in dsh-startup.json chat-wallpaper.json config.json startup.json; do
  _p="$_HOME_DIR/$_f"
  if [ -f "$_p" ]; then
    L "存在：$_p"
    _flat=$(tr '\n' ' ' < "$_p" 2>/dev/null | cut -c1-600)
    L "  内容（前 600 字符）：$_flat"
  fi
done
_TPL="$_HOME_DIR/startup-templates"
if [ -d "$_TPL" ]; then
  L "用户模板目录：$_TPL"
  for _t in "$_TPL"/*; do
    [ -d "$_t" ] && L "  $(basename "$_t")"
  done
else
  L '（没有用户模板目录 ~/.dsh/startup-templates，使用内置模板）'
fi
L ''

L '--- 更新目录 / 回滚按钮 ---'
_UPD="$_HOME_DIR/boot-suite-updates"
if [ -d "$_UPD" ]; then
  L "更新目录：$_UPD"
  ls -1 "$_UPD" 2>/dev/null | sed 's/^/  /' | tee -a "$OUT"
else
  L '（没有 boot-suite-updates 目录）'
fi
_DESK=$(dsh_desktop_dir)
for _b in "$_DESK"/紧急回滚-*.command; do
  [ -e "$_b" ] && L "桌面回滚按钮：$(basename "$_b")"
done
L ''

L '--- 诊断日志末尾 120 行 ---'
_DIAG=$(dsh_diag_log)
if [ -f "$_DIAG" ]; then
  L "日志文件：$_DIAG"
  tail -n 120 "$_DIAG" 2>/dev/null | tee -a "$OUT"
else
  L "（还没有诊断日志：$_DIAG —— 插件可能从未成功加载）"
fi
L ''
L '=== 报告结束 ==='

printf '\n'
printf '诊断报告已生成：%s\n' "$OUT"
printf '把这个文件发给作者即可。\n'
exit 0
