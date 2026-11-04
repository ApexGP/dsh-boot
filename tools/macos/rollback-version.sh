#!/bin/sh
# ============================================================================
# dsh-boot-suite —— 紧急回滚到更新前的版本（macOS）
#
# 安装器在每次「换版本安装」前会自动在桌面生成：
#   紧急回滚-V<旧版本>（先完全退出 DSH 再双击）.command
# 它调用的就是本脚本：把插件 link 回更新前那个版本的目录。
# 只换插件版本，不碰用户配置（~/.dsh/*.json、模板、底图）。
#
# 用法：
#   sh tools/macos/rollback-version.sh --target-pkg "<旧版本pkg目录>" --profile desktop
#   sh tools/macos/rollback-version.sh --target-pkg "..." --profile desktop --check-only
#   sh tools/macos/rollback-version.sh --target-pkg "..." --profile desktop --no-start
#
# 选项：
#   --target-pkg <dir>   更新前那个版本的仓库/解压目录（新布局含 tools/macos/install.sh，
#                        仓库整理前的旧版本目录含 tools/install-macos.sh，两种都支持）
#   --profile <name>     要回滚的 profile，默认 desktop
#   --check-only         只校验目标目录与 profile，不改动任何东西
#   --no-start           回滚成功后不自动打开 DSH
#   -h, --help           显示帮助
# 环境变量：DSH_HOME 覆盖用户数据目录；DSH_ROLLBACK_WAIT_SECONDS 覆盖等待退出秒数（默认 300）
# ============================================================================

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P)
Say() { printf '%s\n' "$*"; }
Die() { printf '[x] %s\n' "$*" >&2; exit 1; }

# 公共函数库：始终在脚本同目录的 lib/。安装器把本脚本复制到
# $DSH_HOME/boot-suite-updates/ 时按同构目录一起复制 lib/mac-common.sh。
if [ -f "$SCRIPT_DIR/lib/mac-common.sh" ]; then
  . "$SCRIPT_DIR/lib/mac-common.sh"
else
  printf '[x] 缺少公共函数库：%s\n' "$SCRIPT_DIR/lib/mac-common.sh" >&2
  exit 1
fi

read_version() {
  sed -n 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$1" 2>/dev/null | head -n 1
}

# 回滚副本会被放到 $DSH_HOME/boot-suite-updates/，那里没有 package.json；有就读版本，没有就只报位置
VER=''
# 仓库布局：本脚本在 tools/macos/，仓库根在上两级；被单独拷出来时同目录有
# package.json 也能读（两种情况都读不到就只报脚本位置，不影响回滚）
if [ -f "$SCRIPT_DIR/../../package.json" ]; then
  VER=$(read_version "$SCRIPT_DIR/../../package.json")
elif [ -f "$SCRIPT_DIR/package.json" ]; then
  VER=$(read_version "$SCRIPT_DIR/package.json")
fi
if [ -n "$VER" ]; then
  Say "dsh-boot-suite v$VER"
else
  Say 'dsh-boot-suite 紧急回滚工具（独立副本）'
fi
Say "脚本位置：$SCRIPT_DIR"

usage() {
  cat <<'EOF'
dsh-boot-suite —— macOS 紧急回滚

用法：
  sh tools/macos/rollback-version.sh --target-pkg <旧版本目录> [--profile desktop] [--check-only] [--no-start]

选项：
  --target-pkg <dir>   更新前的版本目录（必须含 package.json / lib/index.js / 安装器；
                       新布局安装器在 tools/macos/install.sh，旧版本目录是 tools/install-macos.sh）
  --profile <name>     要回滚的 profile，默认 desktop
  --check-only         只检查目标目录与 profile，不改动任何东西
  --no-start           回滚成功后不自动打开 DSH
  -h, --help           显示本帮助

环境变量：
  DSH_HOME                     覆盖用户数据目录（默认 ~/.dsh，测试用）
  DSH_ROLLBACK_WAIT_SECONDS    等待 DSH 退出的秒数（默认 300；测试时可设小）
EOF
}

# ── 1. 解析参数 ────────────────────────────────────────────────────────────
TARGET_PKG=''
PROFILE=desktop
CHECK_ONLY=0
NO_START=0
while [ $# -gt 0 ]; do
  case "$1" in
    --target-pkg)
      shift
      if [ $# -lt 1 ]; then
        printf '[x] 缺少 --target-pkg 的取值\n\n' >&2
        usage >&2
        exit 2
      fi
      TARGET_PKG=$1
      ;;
    --target-pkg=*) TARGET_PKG=$(printf '%s' "$1" | sed 's/^--target-pkg=//') ;;
    --profile)
      shift
      if [ $# -lt 1 ]; then
        printf '[x] 缺少 --profile 的取值\n\n' >&2
        usage >&2
        exit 2
      fi
      PROFILE=$1
      ;;
    --profile=*) PROFILE=$(printf '%s' "$1" | sed 's/^--profile=//') ;;
    --check-only) CHECK_ONLY=1 ;;
    --no-start) NO_START=1 ;;
    -h|--help) usage; exit 0 ;;
    *)
      printf '[x] 未知参数：%s\n\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done
if [ -z "$TARGET_PKG" ]; then
  printf '[x] 缺少 --target-pkg <旧版本目录>\n\n' >&2
  usage >&2
  exit 2
fi
case "$PROFILE" in
  ''|*[!A-Za-z0-9._-]*) Die "profile 名不合法：$PROFILE" ;;
esac
TARGET_PKG=$(printf '%s' "$TARGET_PKG" | sed 's:/*$::')
[ -n "$TARGET_PKG" ] || Die '--target-pkg 不是有效目录'

# ── 2. 日志（桌面 + $DSH_HOME/boot-suite-updates/ 兜底） ───────────────────
STAMP=$(date +%Y%m%d-%H%M%S)
DESK=$(dsh_desktop_dir)
UPDATES_ROOT="$(dsh_home)/boot-suite-updates"
mkdir -p "$UPDATES_ROOT" 2>/dev/null || true
LOG="$DESK/dsh-boot-suite 回滚日志 $STAMP.txt"
FALLBACK_LOG="$UPDATES_ROOT/dsh-boot-suite 回滚日志 $STAMP.txt"
Log() {
  _line="$(date +%H:%M:%S)  $*"
  printf '%s\n' "$_line"
  printf '%s\n' "$_line" >> "$LOG" 2>/dev/null || printf '%s\n' "$_line" >> "$FALLBACK_LOG" 2>/dev/null || true
}
Fail() {
  _line="$(date +%H:%M:%S)  [x] $*"
  printf '%s\n' "$_line" >&2
  printf '%s\n' "$_line" >> "$LOG" 2>/dev/null || printf '%s\n' "$_line" >> "$FALLBACK_LOG" 2>/dev/null || true
  exit 1
}

# ── 3. 校验目标版本目录 ────────────────────────────────────────────────────
Log "紧急回滚启动，目标目录：$TARGET_PKG"
[ -d "$TARGET_PKG" ] || Fail "目标版本目录不存在：$TARGET_PKG"
[ -f "$TARGET_PKG/package.json" ] || Fail "目标版本目录不完整（缺 package.json）：$TARGET_PKG"
TARGET_VER=$(read_version "$TARGET_PKG/package.json")
[ -n "$TARGET_VER" ] || Fail '目标版本的 package.json 无法解析出版本号'
[ -f "$TARGET_PKG/lib/index.js" ] || Fail '目标版本缺少 lib/index.js，目录不完整'
# 目标目录可能是「仓库整理前」发布的旧版本：那时安装器在 tools/install-macos.sh；
# 新布局在 tools/macos/install.sh。优先新布局，旧版本目录回退旧路径，两者都无才报错。
TARGET_INSTALLER="$TARGET_PKG/tools/macos/install.sh"
if [ ! -f "$TARGET_INSTALLER" ]; then
  TARGET_INSTALLER="$TARGET_PKG/tools/install-macos.sh"
fi
[ -f "$TARGET_INSTALLER" ] || Fail '目标版本缺少安装器（tools/macos/install.sh 与旧布局 tools/install-macos.sh 都没有），无法回滚'
Log "目标版本：v$TARGET_VER"
Log "目标安装器：$TARGET_INSTALLER"

PROFILES_ROOT=$(dsh_profiles_root)
PROFILE_DIR="$PROFILES_ROOT/$PROFILE"
[ -f "$PROFILE_DIR/package.json" ] || Fail "找不到 profile：$PROFILE_DIR"
Log "回滚对象 profile：${PROFILE}（${PROFILE_DIR}）"

if [ "$CHECK_ONLY" = 1 ]; then
  Log '检查通过（CheckOnly，未修改任何东西）'
  exit 0
fi

# ── 4. 等 DSH 完全退出 ─────────────────────────────────────────────────────
WAIT_SECONDS=$DSH_ROLLBACK_WAIT_SECONDS
case "$WAIT_SECONDS" in
  ''|*[!0-9]*) WAIT_SECONDS=300 ;;
esac
if dsh_is_running; then
  Log "检测到 DSH 还在运行。请完全退出（窗口 + 菜单栏图标），本窗口会等待，最多 $WAIT_SECONDS 秒…"
  wait_note() { Log "仍在等待 DSH 退出…（已等 $1 秒）"; }
  if ! dsh_wait_quit "$WAIT_SECONDS" wait_note; then
    Fail "等了 $WAIT_SECONDS 秒 DSH 还没退出，已取消回滚（不会改动任何东西）"
  fi
fi
Log '已确认 DSH 完全退出'

# ── 5. 备份当前 profile 并运行旧版本安装器 ────────────────────────────────
KEEP="$UPDATES_ROOT/rollback-backup-$STAMP"
mkdir -p "$KEEP" || Fail "无法创建备份目录：$KEEP"
if ! cp "$PROFILE_DIR/package.json" "$KEEP/profile-package.json"; then
  Fail '备份 profile/package.json 失败，已取消回滚'
fi
if [ -f "$PROFILE_DIR/pnpm-lock.yaml" ]; then
  cp "$PROFILE_DIR/pnpm-lock.yaml" "$KEEP/pnpm-lock.yaml" 2>/dev/null || true
fi
Log "当前 profile 状态已备份到：$KEEP"

restore_profile() {
  cp "$KEEP/profile-package.json" "$PROFILE_DIR/package.json" 2>/dev/null && Log '已恢复 profile/package.json'
  if [ -f "$KEEP/pnpm-lock.yaml" ]; then
    cp "$KEEP/pnpm-lock.yaml" "$PROFILE_DIR/pnpm-lock.yaml" 2>/dev/null && Log '已恢复 profile/pnpm-lock.yaml'
  fi
}

Log '运行旧版本安装器（把插件 link 回旧版本目录）…'
if ! DSH_BOOT_SUITE_ROLLBACK=1 sh "$TARGET_INSTALLER" --profiles "$PROFILE"; then
  restore_profile
  Fail '旧版本安装器执行失败，已恢复 profile 配置。请把回滚日志发给作者。'
fi

# ── 6. 回滚后校验 ──────────────────────────────────────────────────────────
INST="$PROFILE_DIR/node_modules/dsh-boot-suite"
[ -e "$INST" ] || { restore_profile; Fail '回滚后 node_modules 里没有 dsh-boot-suite，已恢复 profile 备份。请把回滚日志发给作者。'; }
GOT_VER=$(read_version "$INST/package.json")
if [ "$GOT_VER" != "$TARGET_VER" ]; then
  restore_profile
  Fail "回滚后版本是 ${GOT_VER}，不是期望的 ${TARGET_VER}，已恢复 profile 备份。请把回滚日志发给作者。"
fi
Log "回滚成功：现在装的是 v$GOT_VER"

# ── 7. 重新打开 DSH + 收尾 ────────────────────────────────────────────────
if [ "$NO_START" != 1 ]; then
  if dsh_reopen; then
    Log '正在重新打开 DSH…'
  else
    Log '没找到 DSH 客户端，请手动打开。'
  fi
fi
Log "完成。回滚日志：$LOG"
Log '把这份回滚日志发给作者，方便定位新版为什么打不开。'
if [ -t 0 ]; then
  printf '\n按回车关闭窗口…'
  read -r _
fi
exit 0
