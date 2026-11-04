#!/bin/sh
# ============================================================================
# dsh-boot-suite —— macOS 双击入口：一键诊断
#
# 把环境信息写到桌面 dsh诊断-<时间>.txt，用户把这个文件发给作者即可。
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
printf '  正在收集诊断信息（只读，不会改任何东西）…\n\n'

if [ ! -f "$HERE/tools/doctor.sh" ]; then
  printf '  [x] 找不到 tools/doctor.sh，你下载的可能是残缺的压缩包。\n'
  printf '\n  按回车关闭窗口…'
  if [ -t 0 ]; then read -r _; fi
  exit 1
fi

sh "$HERE/tools/doctor.sh"
rc=$?

printf '\n'
if [ "$rc" -eq 0 ]; then
  printf '  诊断完成。按回车关闭窗口…\n'
else
  printf '  诊断没有成功（退出码 %s）。按回车关闭窗口，把上面的报错整段发给作者。\n' "$rc"
fi
if [ -t 0 ]; then read -r _; fi
exit "$rc"
