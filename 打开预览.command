#!/bin/sh
# ============================================================================
# dsh-boot-suite —— macOS 双击入口：打开启动动画离线预览
#
# 用默认浏览器打开 preview/index.html（不需要安装插件、不碰 ~/.dsh）。
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

if [ ! -f "$HERE/preview/index.html" ]; then
  printf '  [x] 找不到预览页：%s\n' "$HERE/preview/index.html"
  printf '\n  按回车关闭窗口…'
  if [ -t 0 ]; then read -r _; fi
  exit 1
fi

sh "$HERE/open-preview.sh"
rc=$?

printf '\n'
printf '  预览页应该已经在浏览器里打开了。按回车关闭窗口…\n'
if [ -t 0 ]; then read -r _; fi
exit "$rc"
