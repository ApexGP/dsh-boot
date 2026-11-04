#!/bin/sh
# ============================================================================
# dsh-boot-suite —— macOS 自动更新执行器（对齐 Windows 的 tools/update-apply.ps1）
#
# 为什么需要这个脚本：插件运行时跑在 DSH 进程里，自己不能替换自己。Windows 版是
# 宿主启动一个 PowerShell 窗口等用户退出后再换版本；macOS 没有 .ps1，宿主（
# lib/host-startup.js 的 darwin 分支）会写一个 .command 交给 Terminal 打开，最终
# 执行的就是本脚本。
#
# 宿主调用约定（--zip/--version/--exe/--config 由 host-startup.js 传）：
#   sh tools/update-apply.sh --zip <安装包绝对路径> --version <目标版本> \
#      --exe <桌面端可执行路径> --config <用户配置文件路径>
#
# 流程：等用户完全退出 DSH → 校验 zip → 备份配置 → 解压到 pkg.new → 校验版本
#       → 旧 pkg 移 pkg.old、pkg.new 就位 → 跑 pkg 里的 install-macos.sh
#       → 成功删除 pkg.old 并重开 DSH；失败恢复 pkg.old 和配置后重开 DSH。
# 任何情况下都不删用户配置和模板（只动 $DSH_HOME/boot-suite-updates/<版本>/ 里
# 我们自己的 pkg / pkg.new / pkg.old）。
# ============================================================================
set -u

# ── 0. 定位脚本自身，载入 macOS 公共函数库 ─────────────────────────────────
# Terminal 打开 .command 时工作目录不确定，所有路径必须以脚本位置为准。
UA_HERE=$(cd "$(dirname "$0")" 2>/dev/null && pwd) || {
  printf '[x] 无法定位脚本所在目录（$0=%s）\n' "$0" >&2
  exit 1
}
UA_LIB="$UA_HERE/lib/mac-common.sh"
if [ ! -f "$UA_LIB" ]; then
  printf '[x] 缺少公共函数库：%s\n' "$UA_LIB" >&2
  printf '    安装包不完整，或脚本被单独拷了出来。请重新下载完整发布包。\n' >&2
  exit 1
fi
# shellcheck source=tools/lib/mac-common.sh
. "$UA_LIB"

UA_USAGE() {
  cat <<'EOF'
用法：
  sh tools/update-apply.sh --zip <安装包绝对路径> --version <目标版本> \
     [--exe <桌面端可执行路径>] [--config <用户配置文件路径>]

参数：
  --zip      新版本安装包（.zip）的绝对路径，必填
  --version  目标版本号（例如 2.16.10），必填；必须与包内 package.json 的 version 一致
  --exe      桌面端可执行路径；不填则自动探测 /Applications/DeepSeek Harness.app
  --config   用户配置文件路径，默认 $DSH_HOME/dsh-startup.json；更新失败时会恢复它
  --help     显示本帮助并退出

环境变量（自动化测试用，正常更新不用设）：
  DSH_HOME                 用户数据根目录，默认 ~/.dsh
  DSH_UPDATE_WAIT_SECONDS  等待 DSH 退出的超时秒数，默认 900（15 分钟）
  DSH_UPDATE_LOG_DIR       更新日志目录，默认桌面
  DSH_SKIP_PROCESS_CHECK=1 公共库开关：不真的检测 DSH 进程
  DSH_SKIP_REOPEN=1        公共库开关：不真的重新打开 DSH

说明：
  1. 本窗口会先等你完全退出 DSH（窗口 + 菜单栏图标），最多等 900 秒；
  2. 然后用 unzip -t 校验安装包完整性，解压到临时目录并核对版本号；
  3. 运行新版本自带的安装器，成功后自动重开 DSH；
  4. 失败会恢复旧版本目录和用户配置，并把「更新日志」留在桌面。
EOF
}

# ── 1. 解析参数 ─────────────────────────────────────────────────────────────
UA_ZIP=""
UA_VERSION=""
UA_EXE=""
UA_CONFIG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --zip)
      [ $# -ge 2 ] || { printf '[x] --zip 缺少参数值\n' >&2; UA_USAGE >&2; exit 2; }
      UA_ZIP=$2; shift 2 ;;
    --zip=*) UA_ZIP=${1#--zip=}; shift ;;
    --version)
      [ $# -ge 2 ] || { printf '[x] --version 缺少参数值\n' >&2; UA_USAGE >&2; exit 2; }
      UA_VERSION=$2; shift 2 ;;
    --version=*) UA_VERSION=${1#--version=}; shift ;;
    --exe)
      [ $# -ge 2 ] || { printf '[x] --exe 缺少参数值\n' >&2; UA_USAGE >&2; exit 2; }
      UA_EXE=$2; shift 2 ;;
    --exe=*) UA_EXE=${1#--exe=}; shift ;;
    --config)
      [ $# -ge 2 ] || { printf '[x] --config 缺少参数值\n' >&2; UA_USAGE >&2; exit 2; }
      UA_CONFIG=$2; shift 2 ;;
    --config=*) UA_CONFIG=${1#--config=}; shift ;;
    --help|-h) UA_USAGE; exit 0 ;;
    *)
      printf '[x] 不认识的参数：%s\n\n' "$1" >&2
      UA_USAGE >&2
      exit 2 ;;
  esac
done

if [ -z "$UA_ZIP" ]; then
  printf '[x] 缺少必需参数 --zip <安装包绝对路径>\n\n' >&2
  UA_USAGE >&2
  exit 2
fi
if [ -z "$UA_VERSION" ]; then
  printf '[x] 缺少必需参数 --version <目标版本>\n\n' >&2
  UA_USAGE >&2
  exit 2
fi
# 版本号会拼进目录名，必须挡住 ../ 之类的路径穿越；宿主侧也做了同样的白名单。
case "$UA_VERSION" in
  *[!0-9A-Za-z._+-]*)
    printf '[x] 版本号不合法：%s（只允许数字、字母、点、下划线、加号、减号）\n' "$UA_VERSION" >&2
    exit 2 ;;
esac

# --zip 约定传绝对路径，但允许相对路径便于手工调试
case "$UA_ZIP" in
  /*) : ;;
  *)
    UA_ZIP_DIR=$(dirname "$UA_ZIP")
    if UA_ZIP_PARENT=$(cd "$UA_ZIP_DIR" 2>/dev/null && pwd); then
      UA_ZIP="$UA_ZIP_PARENT/$(basename "$UA_ZIP")"
    fi ;;
esac

# ── 2. 路径与日志 ───────────────────────────────────────────────────────────
# 用户数据根与 Windows 的 %USERPROFILE%\.dsh 对应；DSH_HOME 可覆盖（测试用）。
UA_ROOT_HOME=$(dsh_home)
UA_UPDATES="$UA_ROOT_HOME/boot-suite-updates"
UA_WORK="$UA_UPDATES/$UA_VERSION"
UA_PKG="$UA_WORK/pkg"
UA_PKG_NEW="$UA_WORK/pkg.new"
UA_PKG_OLD="$UA_WORK/pkg.old"
UA_CFG_BACKUP="$UA_WORK/backup/dsh-startup.json"

UA_STAMP=$(date '+%Y%m%d-%H%M%S')
UA_LOG_NAME="dsh-boot-suite 更新日志 $UA_STAMP.txt"
UA_LOG_DIR=${DSH_UPDATE_LOG_DIR:-$(dsh_desktop_dir)}
UA_LOG_DESKTOP=""
UA_LOG_FALLBACK=""
UA_LOG_HINT=""
# 桌面日志优先（用户容易找到），同时写一份到 $DSH_HOME/boot-suite-updates 兜底
# （桌面被同步盘锁住/权限异常时兜底副本还在）。两个都写，Windows 版是二选一。
if mkdir -p "$UA_LOG_DIR" 2>/dev/null && : >> "$UA_LOG_DIR/$UA_LOG_NAME" 2>/dev/null; then
  UA_LOG_DESKTOP="$UA_LOG_DIR/$UA_LOG_NAME"
  UA_LOG_HINT="$UA_LOG_DESKTOP"
fi
if mkdir -p "$UA_UPDATES" 2>/dev/null && : >> "$UA_UPDATES/$UA_LOG_NAME" 2>/dev/null; then
  UA_LOG_FALLBACK="$UA_UPDATES/$UA_LOG_NAME"
  [ -n "$UA_LOG_HINT" ] || UA_LOG_HINT="$UA_LOG_FALLBACK"
fi
if [ -z "$UA_LOG_DESKTOP" ] && [ -z "$UA_LOG_FALLBACK" ]; then
  printf '[!] 无法创建日志文件（桌面和 %s 都不可写），进度只显示在本窗口。\n' "$UA_UPDATES" >&2
fi

UA_LOG() {
  UA_LOG_LINE="$(date '+%H:%M:%S')  $1"
  printf '%s\n' "$UA_LOG_LINE" 2>/dev/null || true
  if [ -n "$UA_LOG_DESKTOP" ]; then
    printf '%s\n' "$UA_LOG_LINE" >> "$UA_LOG_DESKTOP" 2>/dev/null || true
  fi
  if [ -n "$UA_LOG_FALLBACK" ]; then
    printf '%s\n' "$UA_LOG_LINE" >> "$UA_LOG_FALLBACK" 2>/dev/null || true
  fi
}

# ── 3. 状态与工具函数 ───────────────────────────────────────────────────────
UA_HAD_OLD=0        # 本次更新前 <版本>/pkg 是否已存在（存在才在失败时恢复）
UA_CONFIG_BACKED=0  # 是否成功备份了用户配置
UA_DONE=0           # 防止失败清理函数被重复执行

UA_WAIT=${DSH_UPDATE_WAIT_SECONDS:-900}
case "$UA_WAIT" in
  ''|*[!0-9]*) UA_LOG "DSH_UPDATE_WAIT_SECONDS 不是数字（${UA_WAIT}），回退为 900 秒"; UA_WAIT=900 ;;
esac

# 只允许删除工作目录内部的东西。任何情况下不碰用户配置和模板。
UA_SAFE_RM() {
  case "$1" in
    "$UA_WORK"/*) : ;;
    *)
      UA_LOG "拒绝删除工作目录之外的路径：$1"
      return 1 ;;
  esac
  rm -rf "$1"
}

# 读 package.json 里的 version：优先 node（能正确处理 JSON），没有 node 用 grep/sed 严格匹配。
# macOS 自带 /bin/sh，但 node 不一定在 PATH 里（nvm 装的 Terminal 里常见），所以必须有兜底。
UA_READ_VERSION() {
  UA_RV_FILE=$1
  UA_RV_OUT=""
  UA_RV_OUT=$(dsh_run_node -e 'const fs=require("fs");let t=fs.readFileSync(process.argv[1],"utf8");if(t.charCodeAt(0)===0xFEFF)t=t.slice(1);const j=JSON.parse(t);process.stdout.write(String(j.version||""))' "$UA_RV_FILE" 2>/dev/null) && {
    if [ -n "$UA_RV_OUT" ]; then
      printf '%s\n' "$UA_RV_OUT"
      return 0
    fi
  }
  # node 不可用 / JSON 解析失败：按严格格式匹配 "version": "<值>"（取第一个匹配）
  # LC_ALL=C：JSON 里若有非法 UTF-8 字节，BSD sed 在 UTF-8 locale 下会报 illegal byte sequence
  LC_ALL=C sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$UA_RV_FILE" 2>/dev/null | head -n 1
}

# Windows 版会去掉 package.json 的 BOM（DSH/Node 拒绝带 BOM 的 JSON）；macOS 版对齐处理。
UA_STRIP_BOM() {
  UA_SB_FILE=$1
  UA_SB_BOM=$(head -c 3 "$UA_SB_FILE" 2>/dev/null | od -An -tx1 2>/dev/null | tr -d ' \n')
  if [ "$UA_SB_BOM" = "efbbbf" ]; then
    if tail -c +4 "$UA_SB_FILE" > "$UA_SB_FILE.nobom" 2>/dev/null && mv "$UA_SB_FILE.nobom" "$UA_SB_FILE" 2>/dev/null; then
      UA_LOG '已移除 package.json 的 BOM'
    else
      UA_LOG '警告：package.json 带 BOM 且移除失败（继续）'
    fi
  fi
}

# 结束时如果是交互式终端，停一下等回车，避免 Terminal 窗口一闪而过看不到结果。
UA_PROMPT_CLOSE() {
  if [ -t 0 ]; then
    printf '\n按回车关闭本窗口… '
    read -r UA_PROMPT_DUMMY 2>/dev/null || true
    printf '\n'
  fi
}

# 统一失败出口：恢复旧版本目录 + 配置 → 重开 DSH → 给出日志路径 → exit 1。
UA_FAIL() {
  trap - INT TERM HUP 2>/dev/null || true
  if [ "$UA_DONE" = "1" ]; then exit 1; fi
  UA_DONE=1
  UA_LOG '------------------------------------------------------------'
  UA_LOG "更新失败：$1"
  # 恢复旧版本目录（pkg.old 在「替换」步骤才会出现，之前失败不会走到这里）
  if [ "$UA_HAD_OLD" = "1" ] && [ -d "$UA_PKG_OLD" ]; then
    if [ -d "$UA_PKG" ]; then UA_SAFE_RM "$UA_PKG" || true; fi
    if mv "$UA_PKG_OLD" "$UA_PKG" 2>/dev/null; then
      UA_LOG '已恢复旧版本目录。'
    else
      UA_LOG "恢复旧版本目录失败：请手动把 $UA_PKG_OLD 改名为 $UA_PKG"
    fi
  fi
  # 恢复用户配置（只在更新前成功备份过时）
  if [ "$UA_CONFIG_BACKED" = "1" ] && [ -f "$UA_CFG_BACKUP" ]; then
    if cp "$UA_CFG_BACKUP" "$UA_CONFIG" 2>/dev/null; then
      UA_LOG "配置已恢复：$UA_CONFIG"
    else
      UA_LOG "配置恢复失败（备份还在：${UA_CFG_BACKUP}）"
    fi
  fi
  UA_LOG '旧版插件应仍可用，正在重新打开 DSH…'
  if dsh_reopen "$UA_EXE"; then
    UA_LOG '已请求系统重新打开 DSH。'
  else
    UA_LOG '没能自动打开 DSH，请手动打开客户端。'
  fi
  UA_LOG '请把「更新日志」文件发给作者：'
  if [ -n "$UA_LOG_HINT" ]; then
    UA_LOG "  $UA_LOG_HINT"
  else
    UA_LOG '  （日志文件写入失败，请把本窗口截图发给作者）'
  fi
  if [ -n "$UA_LOG_FALLBACK" ] && [ "$UA_LOG_FALLBACK" != "$UA_LOG_HINT" ]; then
    UA_LOG "  （兜底副本：${UA_LOG_FALLBACK}）"
  fi
  UA_PROMPT_CLOSE
  exit 1
}

UA_ON_SIGNAL() {
  UA_FAIL '已取消（窗口被关闭或收到中断信号），本次更新没有完成'
}
trap UA_ON_SIGNAL INT TERM HUP

# 默认的桌面端可执行文件：宿主通常会把 process.execPath 通过 --exe 传进来，
# 手工调用时自己找一遍；都找不到也没关系（dsh_reopen 会按 bundle id 打开）。
if [ -z "$UA_EXE" ]; then
  UA_APP=$(dsh_find_app 2>/dev/null || true)
  if [ -n "$UA_APP" ] && [ -x "$UA_APP/Contents/MacOS/DeepSeek Harness" ]; then
    UA_EXE="$UA_APP/Contents/MacOS/DeepSeek Harness"
  fi
fi
[ -n "$UA_CONFIG" ] || UA_CONFIG="$UA_ROOT_HOME/dsh-startup.json"

# ── 4. 开场日志 ─────────────────────────────────────────────────────────────
UA_LOG '============================================================'
UA_LOG ' dsh-boot-suite —— macOS 自动更新'
UA_LOG '============================================================'
UA_LOG "目标版本：v$UA_VERSION"
UA_LOG "安装包：$UA_ZIP"
UA_LOG "工作目录：$UA_WORK"
if [ -n "$UA_LOG_HINT" ]; then UA_LOG "更新日志：$UA_LOG_HINT"; fi
UA_OLD_VER=$(UA_READ_VERSION "$UA_HERE/../package.json" 2>/dev/null || true)
if [ -n "${UA_OLD_VER:-}" ]; then
  UA_LOG "当前版本：v$UA_OLD_VER → 目标版本：v$UA_VERSION"
fi

if ! mkdir -p "$UA_WORK" 2>/dev/null; then
  UA_FAIL "无法创建工作目录：${UA_WORK}（请检查磁盘空间和目录权限）"
fi

# ── 5. 第 1 步：等用户手动完全退出 DSH ─────────────────────────────────────
UA_LOG ''
UA_LOG '第 1 步：等待 DeepSeek Harness 完全退出'
UA_LOG '请手动完全退出 DeepSeek Harness（窗口 + 菜单栏图标）'
UA_LOG '检测到 DSH 完全退出后会自动安装并重新打开，请勿关闭本窗口。'
UA_WAIT_NOTE() { UA_LOG "仍在等待 DSH 完全退出…（已等 $1 秒）"; }
if dsh_is_running; then
  UA_LOG '检测到 DSH 正在运行，开始等待…'
else
  UA_LOG '未检测到运行中的 DSH，直接继续。'
fi
# 超时时间可用 DSH_UPDATE_WAIT_SECONDS 缩短（自测用），默认 900 秒与 Windows 一致。
if ! dsh_wait_quit "$UA_WAIT" UA_WAIT_NOTE; then
  UA_FAIL "等待 $UA_WAIT 秒仍未检测到 DSH 完全退出，已取消本次更新（未改动任何文件）"
fi
UA_LOG '已确认 DSH 完全退出。'

# ── 6. 第 2 步：校验安装包（对齐 Windows 的 Test-UpdateZip）────────────────
UA_LOG ''
UA_LOG '第 2 步：校验安装包'
if [ ! -f "$UA_ZIP" ]; then
  UA_FAIL "安装包不存在：${UA_ZIP}（请回设置页重新下载）"
fi
if [ ! -r "$UA_ZIP" ]; then
  UA_FAIL "安装包不可读（权限问题）：$UA_ZIP"
fi
UA_ZIP_SIZE=$(wc -c < "$UA_ZIP" 2>/dev/null | tr -d ' ')
UA_LOG "安装包大小：${UA_ZIP_SIZE:-未知} 字节"
if command -v shasum >/dev/null 2>&1; then
  UA_LOG "SHA256：$(shasum -a 256 "$UA_ZIP" 2>/dev/null | awk '{print $1}')"
fi
if ! command -v unzip >/dev/null 2>&1; then
  UA_FAIL '系统缺少 unzip 命令，无法校验安装包'
fi
if ! unzip -t -q "$UA_ZIP" >/dev/null 2>&1; then
  UA_FAIL '安装包不是完整的 zip（可能下载中断或被截断），请重新下载后再更新'
fi
UA_LIST="$UA_WORK/zip-list.txt"
if ! unzip -Z1 "$UA_ZIP" > "$UA_LIST" 2>/dev/null; then
  UA_FAIL '读取安装包文件列表失败，安装包可能已损坏'
fi
# 兼容以 ./ 开头的条目（部分打包工具会加）；去掉 CR，供精确匹配用。
# 必须 LC_ALL=C：macOS 自带 unzip -Z1 列中文名（安装.cmd 等）时会输出非法 UTF-8 字节，
# BSD tr/sed 在 UTF-8 locale（本机 LANG=C.UTF-8）下遇到非法字节会直接报
# "Illegal byte sequence" 且 rc=1，$UA_LIST.norm 变空 → 误判「只有 0 个文件」。
# 这里只是按行/按字节做归一化，用 C locale 完全够用（2026-11-05 发布阻断修复）。
LC_ALL=C tr -d '\r' < "$UA_LIST" | LC_ALL=C sed 's|^\./||' > "$UA_LIST.norm"
UA_COUNT=$(LC_ALL=C grep -c . "$UA_LIST.norm" 2>/dev/null || true)
UA_COUNT=${UA_COUNT:-0}
UA_LOG "包内文件数：$UA_COUNT"
if [ "$UA_COUNT" -lt 50 ]; then
  UA_FAIL "安装包内容异常（只有 $UA_COUNT 个文件），请确认下载的是完整发布包"
fi
UA_MISSING=''
for UA_NEED in package.json tools/install-macos.sh lib/index.js lib/splash.js lib/client.js; do
  if ! LC_ALL=C grep -Fxq "$UA_NEED" "$UA_LIST.norm"; then
    UA_MISSING="$UA_MISSING $UA_NEED"
  fi
done
if [ -n "$UA_MISSING" ]; then
  UA_FAIL "安装包缺少必需文件：$UA_MISSING"
fi
UA_LOG "zip 校验通过：$UA_COUNT 个文件"

# ── 7. 第 3 步：备份用户配置（只备份 --config 指向的那一个文件）───────────
UA_LOG ''
UA_LOG '第 3 步：备份用户配置'
if [ -f "$UA_CONFIG" ]; then
  if mkdir -p "$UA_WORK/backup" 2>/dev/null && cp "$UA_CONFIG" "$UA_CFG_BACKUP" 2>/dev/null; then
    UA_CONFIG_BACKED=1
    UA_LOG "已备份：$UA_CONFIG"
  else
    UA_LOG '警告：配置备份失败，若更新失败将无法自动恢复配置（继续）'
  fi
else
  UA_LOG "没有找到用户配置（跳过备份）：$UA_CONFIG"
fi

# ── 8. 第 4 步：解压并核对版本 ─────────────────────────────────────────────
UA_LOG ''
UA_LOG '第 4 步：解压并校验新版本'
UA_SAFE_RM "$UA_PKG_NEW" || true
if ! mkdir -p "$UA_PKG_NEW" 2>/dev/null; then
  UA_FAIL "无法创建临时解压目录：${UA_PKG_NEW}（请检查磁盘空间）"
fi
UA_EXTRACT_OK=0
if command -v ditto >/dev/null 2>&1; then
  # ditto 优先：能保留可执行位（.command/.sh 需要）和资源分叉，比 unzip 更贴近 Finder 行为
  if ditto -x -k "$UA_ZIP" "$UA_PKG_NEW" >/dev/null 2>&1; then
    UA_EXTRACT_OK=1
    UA_LOG '已用 ditto 解压（保留可执行位和资源分叉）'
  else
    UA_LOG 'ditto 解压失败，改用 unzip 重试…'
  fi
fi
if [ "$UA_EXTRACT_OK" != "1" ]; then
  if unzip -q -o "$UA_ZIP" -d "$UA_PKG_NEW" >/dev/null 2>&1; then
    UA_EXTRACT_OK=1
    UA_LOG '已用 unzip 解压'
  fi
fi
if [ "$UA_EXTRACT_OK" != "1" ]; then
  UA_FAIL '解压失败（安装包可能损坏），请重新下载后再更新'
fi
UA_NEW_PKG_JSON="$UA_PKG_NEW/package.json"
if [ ! -f "$UA_NEW_PKG_JSON" ]; then
  UA_FAIL '解压后没有 package.json（安装包目录结构不对）'
fi
UA_STRIP_BOM "$UA_NEW_PKG_JSON"
UA_NEW_VER=$(UA_READ_VERSION "$UA_NEW_PKG_JSON" 2>/dev/null || true)
if [ -z "${UA_NEW_VER:-}" ]; then
  UA_FAIL '包内 package.json 解析失败（读不出 version）'
fi
if [ "$UA_NEW_VER" != "$UA_VERSION" ]; then
  UA_FAIL "版本不匹配：包内为 v${UA_NEW_VER}，期望 v${UA_VERSION}"
fi
UA_LOG "临时目录校验通过：v$UA_NEW_VER"

# ── 9. 第 5 步：替换版本目录 ────────────────────────────────────────────────
UA_LOG ''
UA_LOG '第 5 步：替换版本目录'
if [ -d "$UA_PKG" ]; then
  UA_HAD_OLD=1
  if [ -e "$UA_PKG_OLD" ]; then UA_SAFE_RM "$UA_PKG_OLD" || true; fi
  if mv "$UA_PKG" "$UA_PKG_OLD" 2>/dev/null; then
    UA_LOG '已把原有版本目录移到 pkg.old（失败时可恢复）'
  else
    UA_HAD_OLD=0
    UA_FAIL "无法移动原有版本目录：${UA_PKG}（可能被占用，请重试）"
  fi
fi
if ! mv "$UA_PKG_NEW" "$UA_PKG" 2>/dev/null; then
  UA_FAIL '替换版本目录失败（磁盘空间不足或目录被占用）'
fi
UA_LOG '新版本目录已就位。'

# ── 10. 第 6 步：运行新版本安装器 ───────────────────────────────────────────
UA_LOG ''
UA_LOG '第 6 步：运行新版本安装器（可能需要几十秒，请勿关闭本窗口）'
UA_INSTALLER="$UA_PKG/tools/install-macos.sh"
if [ ! -f "$UA_INSTALLER" ]; then
  UA_FAIL '新版本里没有 tools/install-macos.sh，无法安装'
fi
# 非交互执行：stdin 接 /dev/null，避免安装器里的 read 卡死。DSH 已退出，
# 不需要 --force，也不传 --check-only。
UA_RC_FILE="$UA_WORK/installer-exit.txt"
rm -f "$UA_RC_FILE" 2>/dev/null || true
{
  sh "$UA_INSTALLER" </dev/null 2>&1
  printf '%s\n' "$?" > "$UA_RC_FILE"
} | while IFS= read -r UA_INSTALLER_LINE || [ -n "$UA_INSTALLER_LINE" ]; do
  # 去掉命令行进度条的 \r（dsh/pnpm 会输出），否则日志文件里会串成一行；
  # LC_ALL=C：安装器输出可能夹带非法 UTF-8 字节，UTF-8 locale 下 BSD tr 会报 illegal byte sequence
  UA_LOG "$(printf '%s' "$UA_INSTALLER_LINE" | LC_ALL=C tr -d '\r')"
done
UA_INSTALLER_RC=$(head -n 1 "$UA_RC_FILE" 2>/dev/null || true)
case "${UA_INSTALLER_RC:-}" in
  ''|*[!0-9]*) UA_FAIL '安装器没有返回有效退出码（可能被系统强制结束）' ;;
esac
if [ "$UA_INSTALLER_RC" != "0" ]; then
  UA_FAIL "新版本安装器退出码 $UA_INSTALLER_RC"
fi
UA_LOG '安装器执行完成（退出码 0）。'

# ── 11. 第 7 步：成功收尾 ───────────────────────────────────────────────────
UA_LOG ''
UA_LOG '第 7 步：收尾'
UA_LOG '安装完成，清理旧版本目录…'
if [ "$UA_HAD_OLD" = "1" ] && [ -d "$UA_PKG_OLD" ]; then
  if UA_SAFE_RM "$UA_PKG_OLD"; then
    UA_LOG '旧版本目录已清理。'
  else
    UA_LOG "警告：旧版本目录清理失败，可手动删除：$UA_PKG_OLD"
  fi
fi
UA_LOG '回滚保护：桌面上的「紧急回滚-V<旧版本>」可在新版打不开时用（安装器会自动更新并清理旧按钮）。'
UA_LOG '正在重新打开 DSH…'
if dsh_reopen "$UA_EXE"; then
  UA_LOG '已请求系统打开 DeepSeek Harness。'
else
  UA_LOG '没能自动打开 DSH，请手动打开客户端。'
fi
sleep 2
UA_LOG '更新成功。'
if [ -n "$UA_LOG_HINT" ]; then UA_LOG "更新日志已保存：$UA_LOG_HINT"; fi
UA_DONE=1
trap - INT TERM HUP 2>/dev/null || true
UA_PROMPT_CLOSE
exit 0
