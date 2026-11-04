#!/bin/sh
# ============================================================================
# dsh-boot-suite —— macOS 公共函数（被同目录的 install.sh / update-apply.sh /
# rollback-version.sh / uninstall.sh / diagnose.sh source）
#
# 位置约定：本文件在 tools/macos/lib/。安装器把 rollback-version.sh 复制到
# $DSH_HOME/boot-suite-updates/ 时会一并复制 lib/mac-common.sh，保持同构目录，
# 所以脚本里统一按「$SCRIPT_DIR/lib/mac-common.sh」定位，不做其它兜底。
#
# 目标：把「找 DSH 安装位置 / 找 CLI / 找 node / 判断进程在不在 / 等退出 /
#       重新打开 / 找桌面目录」这些每个脚本都要做的事收敛到一处。
#
# 约定：
#   · 纯 POSIX sh（macOS 自带 /bin/sh），不依赖 bash 数组、不依赖 jq/python3
#   · 只读探测；唯一会 spawn 进程的是 dsh_run_node / dsh_reopen
#   · 所有函数把结果打到 stdout；失败返回非 0（安装脚本据此给中文报错）
#   · 支持 DSH_HOME 覆盖（与插件运行时 lib/index.js 的 DSH_HOME 语义一致）
#   · 测试可覆盖 DSH_NODE / DSH_APP_DIR，避免真机依赖
# ============================================================================

# 用户数据根：DSH_HOME 优先，默认 ~/.dsh
dsh_home() {
  if [ -n "${DSH_HOME:-}" ]; then
    printf '%s\n' "$DSH_HOME"
  else
    printf '%s\n' "$HOME/.dsh"
  fi
}

# profile 根目录：$DSH_HOME/profiles
dsh_profiles_root() {
  printf '%s\n' "$(dsh_home)/profiles"
}

# 桌面端 .app 路径（找不到返回非 0，不输出）
# 顺序：DSH_APP_DIR 覆盖 → /Applications → ~/Applications → mdfind
dsh_find_app() {
  if [ -n "${DSH_APP_DIR:-}" ] && [ -d "$DSH_APP_DIR" ]; then
    printf '%s\n' "$DSH_APP_DIR"
    return 0
  fi
  for _p in "/Applications/DeepSeek Harness.app" "$HOME/Applications/DeepSeek Harness.app"; do
    if [ -d "$_p" ]; then printf '%s\n' "$_p"; return 0; fi
  done
  if command -v mdfind >/dev/null 2>&1; then
    _hit=$(mdfind "kMDItemCFBundleIdentifier == 'com.deepseek.dsh'" 2>/dev/null | head -n 1)
    if [ -n "$_hit" ] && [ -d "$_hit" ]; then printf '%s\n' "$_hit"; return 0; fi
  fi
  return 1
}

# DSH 命令行（mac 上是 POSIX sh 启动器）
# 顺序：DSH_CLI 覆盖 → app 内官方 CLI → PATH（跳过第三方 ai-manager 包装）
dsh_find_cli() {
  if [ -n "${DSH_CLI:-}" ] && [ -x "$DSH_CLI" ]; then
    printf '%s\n' "$DSH_CLI"
    return 0
  fi
  _app=$(dsh_find_app 2>/dev/null || true)
  if [ -n "$_app" ] && [ -x "$_app/Contents/Resources/runtime/cli/bin/dsh" ]; then
    printf '%s\n' "$_app/Contents/Resources/runtime/cli/bin/dsh"
    return 0
  fi
  for _p in /usr/local/bin/dsh /opt/homebrew/bin/dsh; do
    if [ -x "$_p" ]; then printf '%s\n' "$_p"; return 0; fi
  done
  _w=$(command -v dsh 2>/dev/null || true)
  if [ -n "$_w" ]; then
    case "$_w" in
      *ai-manager*) : ;;
      *) [ -x "$_w" ] && { printf '%s\n' "$_w"; return 0; } ;;
    esac
  fi
  return 1
}

# 用 node 跑脚本：DSH_NODE 覆盖 → PATH 里的 node → Electron 的 node 模式
# 失败返回 1（调用方给中文报错）
dsh_run_node() {
  if [ -n "${DSH_NODE:-}" ] && [ -x "$DSH_NODE" ]; then
    "$DSH_NODE" "$@"
    return $?
  fi
  if command -v node >/dev/null 2>&1; then
    node "$@"
    return $?
  fi
  _app=$(dsh_find_app 2>/dev/null || true)
  if [ -n "$_app" ] && [ -x "$_app/Contents/MacOS/DeepSeek Harness" ]; then
    ELECTRON_RUN_AS_NODE=1 "$_app/Contents/MacOS/DeepSeek Harness" "$@"
    return $?
  fi
  return 1
}

# 桌面端是否在运行（主进程 + GPU/renderer/utility 全部算）
# 测试开关：DSH_SKIP_PROCESS_CHECK=1 时永远当作「没在运行」（自动化测试用，正常脚本别设）
dsh_is_running() {
  if [ "${DSH_SKIP_PROCESS_CHECK:-}" = "1" ]; then
    return 1
  fi
  if ! command -v pgrep >/dev/null 2>&1; then
    return 1
  fi
  pgrep -f "DeepSeek Harness.app/Contents/" >/dev/null 2>&1
}

# 等桌面端完全退出：默认 300 秒，每 2 秒看一次。
# 参数：$1 超时秒数；$2 可选「等待提示」回调命令（每 15 秒执行一次，传给它已等秒数）
# 返回：0 = 已退出；1 = 超时仍在运行
dsh_wait_quit() {
  _timeout=${1:-300}
  _notify=${2:-}
  _waited=0
  _last_note=0
  while [ "$_waited" -lt "$_timeout" ]; do
    if ! dsh_is_running; then return 0; fi
    sleep 2
    _waited=$((_waited + 2))
    if [ -n "$_notify" ] && [ $((_waited - _last_note)) -ge 15 ]; then
      _last_note=$_waited
      $_notify "$_waited"
    fi
  done
  if dsh_is_running; then return 1; fi
  return 0
}

# 重新打开桌面端：优先 LaunchServices（bundle id），其次按名字，最后直接跑 exe
# 测试开关：DSH_SKIP_REOPEN=1 时直接返回成功、不真的拉起客户端
dsh_reopen() {
  _exe=${1:-}
  if [ "${DSH_SKIP_REOPEN:-}" = "1" ]; then
    return 0
  fi
  if command -v open >/dev/null 2>&1; then
    if open -b com.deepseek.dsh >/dev/null 2>&1; then return 0; fi
    if open -a "DeepSeek Harness" >/dev/null 2>&1; then return 0; fi
  fi
  if [ -n "$_exe" ] && [ -x "$_exe" ]; then
    "$_exe" >/dev/null 2>&1 &
    return 0
  fi
  return 1
}

# 桌面目录（拿不到就回退到 ${HOME}）
dsh_desktop_dir() {
  if [ -d "$HOME/Desktop" ]; then
    printf '%s\n' "$HOME/Desktop"
  else
    printf '%s\n' "$HOME"
  fi
}

# app 版本（CFBundleShortVersionString；拿不到返回非 0、不输出）
dsh_app_version() {
  _app=$(dsh_find_app 2>/dev/null || true)
  [ -n "$_app" ] || return 1
  if [ -x /usr/libexec/PlistBuddy ]; then
    /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$_app/Contents/Info.plist" 2>/dev/null && return 0
  fi
  return 1
}

# 诊断日志（与 lib/index.js 的 diag 写同一份文件）
dsh_diag_log() {
  printf '%s\n' "$(dsh_home)/boot-suite-diag.log"
}

# 临时目录（自动清理由调用方负责）
dsh_mktemp() {
  mktemp -d "${TMPDIR:-/tmp}/dsh-boot-suite.XXXXXX"
}
