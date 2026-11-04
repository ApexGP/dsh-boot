#!/bin/sh
# ============================================================================
# dsh-boot-suite —— macOS 运维菜单
#
# 为什么需要它：仓库整理后 macOS 侧只留一个双击入口 setup.command。用户不用记
# 路径、也不用在终端里敲命令，选个数字就能安装 / 卸载 / 诊断 / 打开离线预览。
#
# 用法：
#   双击仓库根目录的 setup.command
#   sh tools/macos/setup.sh
#   sh tools/macos/setup.sh --help
#
# 设计约定：
#   · 菜单只做「选路」，真正的活都交给同目录的 install.sh / uninstall.sh /
#     diagnose.sh（它们各自有完整的检查、备份、回滚与中文报错）
#   · 非交互式终端（stdin 不是终端，比如被脚本调用）只打印用法并 exit 2，
#     避免卡在 read 上把调用方挂死
#   · 全程 POSIX sh（macOS 自带 /bin/sh 是 bash 3.2），变量一律 ${VAR} 写法
# ============================================================================

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P)
# 本脚本在 tools/macos/ 下，仓库根在上两级
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd -P)
VER=$(sed -n 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$REPO_ROOT/package.json" 2>/dev/null | head -n 1)

Say() { printf '%s\n' "$*"; }
Die() { printf '[x] %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
dsh-boot-suite —— macOS 运维菜单

用法：
  sh tools/macos/setup.sh      # 交互菜单（最省事：双击仓库根目录的 setup.command）
  sh tools/macos/setup.sh -h   # 只显示本帮助

菜单项：
  1  安装 / 更新（装到 desktop / web 里已初始化的 profile，装完不会自动启动 DSH）
  2  卸载（界面出问题时的急救；运行前必须先完全退出 DSH）
  3  诊断（在桌面生成 dsh诊断-<时间>.txt，发给作者）
  4  打开离线预览（用浏览器看动画，不装插件、不碰 ~/.dsh）
  0  退出

说明：
  · 非交互式终端（stdin 不是终端）只打印本帮助并退出，不会卡住
  · 单独只想看安装计划：sh tools/macos/install.sh --check-only
EOF
}

# 参数只支持 -h / --help；双击入口默认不带参数
case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  '') : ;;
  *)
    printf '[x] 不认识的参数：%s\n\n' "$1" >&2
    usage >&2
    exit 2
    ;;
esac

# 菜单要有可读的输入；管道 / 被调用时直接给用法，别卡住
if [ ! -t 0 ]; then
  usage
  exit 2
fi

pause() {
  printf '\n按回车返回菜单…'
  read -r _ || exit 0
}

# 离线预览页：仓库根的 preview/index.html（不装插件、不碰用户目录）
open_preview() {
  _page="$REPO_ROOT/preview/index.html"
  if [ ! -f "$_page" ]; then
    Say ''
    Say "[x] 找不到离线预览页：${_page}（发布包可能不完整）"
    return 0
  fi
  if command -v open >/dev/null 2>&1; then
    if open "$_page" >/dev/null 2>&1; then
      Say ''
      Say '已在默认浏览器打开离线预览。'
    else
      Say ''
      Say "[!] 自动打开失败，请手动用浏览器打开：${_page}"
    fi
  else
    Say ''
    Say "请手动用浏览器打开：${_page}"
  fi
  return 0
}

# 调同目录脚本；找不到就报错并回菜单，主菜单不因为单项失败而退出
run_script() {
  _name=$1
  _label=$2
  _path="$SCRIPT_DIR/$_name"
  if [ ! -f "$_path" ]; then
    Say ''
    Say "[x] 找不到 ${_path}（发布包可能不完整），无法${_label}。"
    return 0
  fi
  Say ''
  sh "$_path"
  _rc=$?
  if [ "$_rc" -ne 0 ]; then
    Say ''
    Say "[!] ${_label}流程没有走完（退出码 ${_rc}）。把上面的输出整段发给作者。"
  fi
  return 0
}

while :; do
  printf '\n'
  printf '  ============================================================\n'
  if [ -n "$VER" ]; then
    printf '    dsh-boot-suite v%s · macOS 运维菜单\n' "$VER"
  else
    printf '    dsh-boot-suite · macOS 运维菜单\n'
  fi
  printf '    仓库位置：%s\n' "$REPO_ROOT"
  printf '  ============================================================\n'
  printf '    1) 安装 / 更新\n'
  printf '    2) 卸载（先完全退出 DSH）\n'
  printf '    3) 诊断（在桌面生成报告）\n'
  printf '    4) 打开离线预览\n'
  printf '    0) 退出\n'
  printf '\n'
  printf '  请选择 [0-4]：'
  read -r _choice || exit 0

  case "${_choice}" in
    1)
      Say ''
      Say '[提示] 安装/更新前建议先完全退出 DeepSeek Harness（窗口 + 菜单栏图标）。'
      run_script install.sh '安装/更新'
      ;;
    2) run_script uninstall.sh '卸载' ;;
    3) run_script diagnose.sh '诊断' ;;
    4) open_preview ;;
    0)
      Say ''
      Say '已退出。'
      exit 0
      ;;
    *)
      Say ''
      Say "[!] 无效选择：${_choice}（请输入 0-4）"
      ;;
  esac
  pause
done
