#!/bin/sh
# ============================================================================
# dsh-boot-suite —— macOS 在线一键安装（对齐 Windows 的 install-online.ps1）
#
# 它会：下载最新发布包 → 解压到临时目录 → 找到 tools/install-macos.sh → 执行它。
# 用户数据（~/.dsh 下的配置、模板、底图）全由 install-macos.sh 负责，本脚本只
# 管「把安装包拿到手并交给安装器」。
#
# 为什么下载的是 dsh-boot-suite-win.zip：
#   发布流程沿用 Windows 打包机产出的 dsh-boot-suite-win.zip，它其实是**跨平台
#   包**——里面同时有 安装.cmd 和 安装-mac.command / tools/install-macos.sh。
#   资产名带 win 只是历史命名；不改名是因为宿主自动更新（lib/host-startup.js）
#   和旧版更新说明里都写死了这个文件名，改名会让老用户更新断链。
#
# 用法：
#   sh install-online.sh              # 下载并安装
#   sh install-online.sh --check-only # 只下载解压、打印安装计划，不改任何东西
#   sh install-online.sh --help
#
# 本脚本故意不 source tools/lib/mac-common.sh：文档里推荐的一行命令是
#   curl -fsSL https://raw.githubusercontent.com/LeeRolling/dsh-boot-suite/main/install-online.sh | sh
# 管道方式下没有「脚本所在目录」，只能依赖系统自带命令（curl/ditto/unzip/find）。
# ============================================================================
set -u

IO_USAGE() {
  cat <<'EOF'
用法：
  sh install-online.sh              # 下载最新发布包并安装
  sh install-online.sh --check-only # 只下载解压、打印安装计划，不修改任何东西
  sh install-online.sh --help       # 显示本帮助

也可以先不下载，直接一条命令（需要 curl）：
  curl -fsSL https://raw.githubusercontent.com/LeeRolling/dsh-boot-suite/main/install-online.sh | sh

环境变量（自动化测试用，正常安装不用设）：
  DSH_ONLINE_ZIP_URL       覆盖发布包下载地址
  DSH_ONLINE_FALLBACK_URL  覆盖源码包兜底下载地址
EOF
}

IO_SAY() { printf '%s\n' "$1"; }
IO_ERR() { printf '[x] %s\n' "$1" >&2; }

# ── 1. 解析参数 ─────────────────────────────────────────────────────────────
IO_CHECK_ONLY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --check-only) IO_CHECK_ONLY=1; shift ;;
    --help|-h) IO_USAGE; exit 0 ;;
    *)
      printf '[x] 不认识的参数：%s\n\n' "$1" >&2
      IO_USAGE >&2
      exit 2 ;;
  esac
done

# 默认下载地址：latest 发布包（跨平台 zip）；失败回退到 main 分支源码包。
IO_PRIMARY_URL=${DSH_ONLINE_ZIP_URL:-https://github.com/LeeRolling/dsh-boot-suite/releases/latest/download/dsh-boot-suite-win.zip}
IO_FALLBACK_URL=${DSH_ONLINE_FALLBACK_URL:-https://github.com/LeeRolling/dsh-boot-suite/archive/refs/heads/main.zip}

# ── 2. 开场横幅 ─────────────────────────────────────────────────────────────
IO_SAY ''
IO_SAY '============================================================'
IO_SAY '  dsh-boot-suite —— macOS 在线安装'
IO_SAY '============================================================'
IO_SAY '  [重要] 请先完全退出 DeepSeek Harness（窗口 + 菜单栏图标）'
IO_SAY '         安装器在检测到 DSH 还在运行时会要求你先退出。'
IO_SAY ''
case "$(uname -s 2>/dev/null)" in
  Darwin) : ;;
  *) IO_SAY '[!] 提示：本脚本面向 macOS，当前系统可能不是 macOS，仍会继续尝试。' ;;
esac

# ── 3. 环境检查 + 临时目录 ──────────────────────────────────────────────────
if ! command -v curl >/dev/null 2>&1; then
  IO_ERR '系统缺少 curl，无法下载。请手动到 GitHub Releases 下载发布包，解压后双击「安装-mac.command」。'
  exit 1
fi
IO_TMP=$(mktemp -d "${TMPDIR:-/tmp}/dsh-boot-suite-online.XXXXXX") || {
  IO_ERR '无法创建临时目录（TMPDIR/ /tmp 可能不可写）。'
  exit 1
}
IO_ZIP="$IO_TMP/package.zip"
IO_DIR="$IO_TMP/pkg"
IO_ON_INT() {
  printf '\n[x] 安装被中断。临时目录（可手动删除）：%s\n' "$IO_TMP"
  exit 1
}
trap IO_ON_INT INT TERM HUP

# 下载：-f 让 HTTP 4xx/5xx 直接失败（否则会把错误页当 zip），-L 跟随跳转，
# --retry 2 抗网络抖动，-m 300 防止挂着不动。
IO_DOWNLOAD() {
  IO_D_URL=$1
  IO_D_OUT=$2
  IO_SAY "      地址：$IO_D_URL"
  curl -fL --retry 2 --retry-delay 1 -m 300 -o "$IO_D_OUT" "$IO_D_URL"
}
# 下载 + zip 完整性校验都通过才算成功（GitHub 偶发返回截断包）。
IO_FETCH_OK() {
  IO_F_URL=$1
  if ! IO_DOWNLOAD "$IO_F_URL" "$IO_ZIP"; then return 1; fi
  if [ ! -s "$IO_ZIP" ]; then return 1; fi
  if command -v unzip >/dev/null 2>&1; then
    unzip -t -q "$IO_ZIP" >/dev/null 2>&1 || return 1
  fi
  return 0
}

# ── 4. [1/3] 下载 ───────────────────────────────────────────────────────────
IO_SAY '[1/3] 下载最新版安装包…'
if IO_FETCH_OK "$IO_PRIMARY_URL"; then
  IO_SAY '      下载完成。'
else
  IO_SAY '      发布包下载失败或不是完整 zip。'
  IO_SAY '      改用源码包（main 分支）重试…'
  if ! IO_FETCH_OK "$IO_FALLBACK_URL"; then
    IO_ERR '下载失败（两个地址都不可用）。请检查网络/代理，或手动到 GitHub Releases 下载发布包。'
    IO_SAY "      临时目录：$IO_TMP"
    exit 1
  fi
  IO_SAY '      源码包下载完成。'
fi

# ── 5. [2/3] 解压 ───────────────────────────────────────────────────────────
IO_SAY '[2/3] 解压…'
if ! mkdir -p "$IO_DIR" 2>/dev/null; then
  IO_ERR "无法创建解压目录：$IO_DIR"
  IO_SAY "      临时目录：$IO_TMP"
  exit 1
fi
IO_EXTRACTED=0
if command -v ditto >/dev/null 2>&1; then
  # ditto 优先：保留可执行位（.command/.sh 双击入口需要）
  if ditto -x -k "$IO_ZIP" "$IO_DIR" >/dev/null 2>&1; then IO_EXTRACTED=1; fi
fi
if [ "$IO_EXTRACTED" != "1" ] && command -v unzip >/dev/null 2>&1; then
  if unzip -q -o "$IO_ZIP" -d "$IO_DIR" >/dev/null 2>&1; then IO_EXTRACTED=1; fi
fi
if [ "$IO_EXTRACTED" != "1" ]; then
  IO_ERR '解压失败（安装包可能损坏）。'
  IO_SAY "      临时目录：$IO_TMP"
  exit 1
fi

# ── 6. [3/3] 找到安装器并执行 ───────────────────────────────────────────────
IO_SAY '[3/3] 查找安装脚本…'
# 发布包是根目录布局；源码包（main.zip）会多一层 dsh-boot-suite-main/，所以用 find。
IO_INSTALLER=$(find "$IO_DIR" -type f -name 'install-macos.sh' 2>/dev/null | LC_ALL=C grep '/tools/install-macos.sh$' | head -n 1)
if [ -z "$IO_INSTALLER" ]; then
  IO_INSTALLER=$(find "$IO_DIR" -type f -name 'install-macos.sh' 2>/dev/null | head -n 1)
fi
if [ -z "$IO_INSTALLER" ]; then
  IO_ERR '压缩包里没找到 tools/install-macos.sh（可能下载不完整，或这个版本还没带 macOS 安装脚本）。'
  IO_SAY '      请到 https://github.com/LeeRolling/dsh-boot-suite/releases 手动下载最新发布包。'
  IO_SAY "      临时目录：$IO_TMP"
  exit 1
fi
IO_SAY "      安装脚本：$IO_INSTALLER"
IO_SAY ''

if [ "$IO_CHECK_ONLY" = "1" ]; then
  IO_SAY '开始检查（--check-only：只打印计划，不修改任何文件）…'
  sh "$IO_INSTALLER" --check-only
else
  IO_SAY '开始安装…'
  sh "$IO_INSTALLER"
fi
IO_RC=$?

IO_SAY ''
IO_SAY "临时目录：${IO_TMP}（可手动删除）"
if [ "$IO_RC" -ne 0 ]; then
  IO_ERR "安装器返回失败（退出码 ${IO_RC}）。"
  IO_SAY '      请运行包里的「诊断-mac.command」或 tools/doctor.sh，把桌面生成的诊断报告发给作者。'
  exit 1
fi
if [ "$IO_CHECK_ONLY" = "1" ]; then
  IO_SAY '检查完毕 —— 没有修改任何东西。确认无误后去掉 --check-only 再运行一次。'
else
  IO_SAY '安装完成 —— 现在打开 DeepSeek Harness Desktop。'
  IO_SAY '打开后确认三件事：'
  IO_SAY '  1) 设置页里多出「启动动画」和「聊天背景」两项'
  IO_SAY '  2) 冷启动会播开机动画'
  IO_SAY '  3) 动画结束后落在聊天底图上'
  IO_SAY ''
  IO_SAY '出问题（黑屏/点不动）：完全退出 DSH，运行「卸载-mac.command」（或 tools/emergency-uninstall.sh）。'
fi
exit 0
