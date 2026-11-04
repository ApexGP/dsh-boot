#!/bin/sh
# ============================================================================
# dsh-boot-suite —— macOS 双击入口：一键安装
#
# 为什么需要 .command：Finder 里双击 .sh 不会执行；.command 会用 Terminal 打开运行。
# 用法：双击本文件；也可以在终端里 sh "安装-mac.command" --check-only
# ============================================================================

# Finder 双击时工作目录可能是任意位置，先切到仓库根目录
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
printf '    DeepSeek Harness 开机动画插件 —— macOS 一键安装\n'
printf '  ============================================================\n\n'
printf '    [重要] 请先完全退出 DeepSeek Harness（窗口 + 菜单栏图标）\n\n'
printf '    安装方式：把插件链接到 DSH 的插件目录（不复制文件，改代码直接生效）\n'
printf '    卸载方式：双击仓库根目录的「卸载-mac.command」\n\n'

if [ ! -f "$HERE/tools/install-macos.sh" ]; then
  printf '  [x] 找不到 tools/install-macos.sh，你下载的可能是残缺的压缩包。\n'
  printf '\n  按回车关闭窗口…'
  if [ -t 0 ]; then read -r _; fi
  exit 1
fi

if [ -t 0 ]; then
  printf '    按回车开始安装…'
  read -r _
fi
printf '\n'

sh "$HERE/tools/install-macos.sh" "$@"
rc=$?

printf '\n'
if [ "$rc" -eq 0 ]; then
  printf '  安装脚本结束。按回车关闭窗口…\n'
else
  printf '  安装没有成功（退出码 %s）。按回车关闭窗口，把上面的报错整段发给作者。\n' "$rc"
fi
if [ -t 0 ]; then read -r _; fi
exit "$rc"
