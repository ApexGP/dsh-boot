#!/bin/sh
# ============================================================================
# dsh-boot-suite —— macOS 双击入口：彻底卸载（界面出问题时的急救）
#
# 为什么需要 .command：Finder 里双击 .sh 不会执行；.command 会用 Terminal 打开运行。
# 用法：双击本文件。
# ============================================================================

cd "$(dirname "$0")" || exit 1
HERE=$(pwd -P)
VER=$(sed -n 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$HERE/package.json" 2>/dev/null | head -n 1)

printf '\n'
if [ -n "$VER" ]; then
  printf '  dsh-boot-suite v%s\n' "$VER"
else
  printf '  dsh-boot-suite\n'
fi
printf '  仓库位置：%s\n\n' "$HERE"
printf '  ============================================================\n'
printf '    dsh-boot-suite 卸载（界面出问题时的急救）\n'
printf '  ============================================================\n\n'
printf '    [重要] 请先完全退出 DeepSeek Harness（窗口 + 菜单栏图标）\n'
printf '    卸载不会删你的设置 / 模板 / 底图。\n\n'

if [ ! -f "$HERE/tools/emergency-uninstall.sh" ]; then
  printf '  [x] 找不到 tools/emergency-uninstall.sh，你下载的可能是残缺的压缩包。\n'
  printf '\n  按回车关闭窗口…'
  if [ -t 0 ]; then read -r _; fi
  exit 1
fi

if [ -t 0 ]; then
  printf '    按回车开始卸载…'
  read -r _
fi
printf '\n'

sh "$HERE/tools/emergency-uninstall.sh" "$@"
rc=$?

printf '\n'
if [ "$rc" -eq 0 ]; then
  printf '  卸载脚本结束。按回车关闭窗口…\n'
else
  printf '  卸载没有成功（退出码 %s）。按回车关闭窗口，把上面的报错整段发给作者。\n' "$rc"
fi
if [ -t 0 ]; then read -r _; fi
exit "$rc"
