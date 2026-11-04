#!/bin/sh
# ============================================================================
# dsh-boot-suite —— 彻底卸载（macOS 急救版）
#
# 会处理 desktop / web 两个 profile，清掉：
#   · dsh-boot-suite / dsh-startup-screen / dsh-chat-wallpaper 的依赖与 bundles
#   · node_modules 下同名的符号链接（真实目录先移到备份，不直接删）
#   · 不删 pnpm-lock.yaml，不自动启动 DSH
#
# 用法：先完全退出桌面端（窗口 + 菜单栏图标），再双击仓库根目录的 setup.command（选 2）；
#       或者 sh tools/macos/uninstall.sh [--profiles desktop,web]
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
Die() { printf '[x] %s\n' "$*" >&2; exit 1; }

read_version() {
  sed -n 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$1" 2>/dev/null | head -n 1
}
# 仓库根：从 tools/macos/ 上两级
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd -P)
VER=$(read_version "$REPO_ROOT/package.json")

if [ -n "$VER" ]; then Say "dsh-boot-suite v$VER"; fi
Say "脚本位置：$SCRIPT_DIR"

usage() {
  cat <<'EOF'
dsh-boot-suite —— macOS 彻底卸载（急救）

用法：
  sh tools/macos/uninstall.sh [--profiles desktop,web]
  （也可以双击仓库根目录的 setup.command，选 2）

选项：
  --profiles <a,b>   只处理指定 profile（逗号分隔），默认 desktop / web
  -h, --help         显示本帮助

说明：
  · 运行前必须先完全退出 DeepSeek Harness（窗口 + 菜单栏图标），否则会报错退出
  · 只删插件相关内容，用户配置 / 模板 / 底图 / pnpm-lock.yaml 都不动
  · 卸载完不会自动启动 DSH
EOF
}

CHECK_ONLY=0
PROFILES_ARG=''
while [ $# -gt 0 ]; do
  case "$1" in
    --profiles)
      shift
      if [ $# -lt 1 ]; then
        printf '[x] 缺少 --profiles 的取值\n\n' >&2
        usage >&2
        exit 2
      fi
      PROFILES_ARG=$1
      ;;
    --profiles=*) PROFILES_ARG=$(printf '%s' "$1" | sed 's/^--profiles=//') ;;
    --check-only) CHECK_ONLY=1 ;;
    -h|--help) usage; exit 0 ;;
    *)
      printf '[x] 未知参数：%s\n\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

PROFILES_ROOT=$(dsh_profiles_root)
[ -d "$PROFILES_ROOT" ] || Die '找不到 profile 目录，可能还没装过 DeepSeek Harness。'

# ── 1. 桌面端必须先完全退出（与 Windows 一致，不做热卸载） ─────────────────
if dsh_is_running; then
  if [ "$CHECK_ONLY" = 1 ]; then
    Say '（检查模式）桌面端正在运行 —— 真正卸载前必须先完全退出'
  else
    Die '桌面端还在运行。请先完全退出 DeepSeek Harness（窗口 + 菜单栏图标），再运行卸载。'
  fi
fi

# ── 2. 找要处理的 profile ──────────────────────────────────────────────────
TARGETS=''
if [ -n "$PROFILES_ARG" ]; then
  for _p in $(printf '%s' "$PROFILES_ARG" | tr ',' ' '); do
    case "$_p" in
      ''|*[!A-Za-z0-9._-]*) Die "profile 名不合法：$_p" ;;
    esac
    if [ -d "$PROFILES_ROOT/$_p" ]; then
      TARGETS="$TARGETS $_p"
    else
      Say "[!] 跳过不存在的 profile：$_p"
    fi
  done
else
  for _p in desktop web; do
    [ -d "$PROFILES_ROOT/$_p" ] && TARGETS="$TARGETS $_p"
  done
fi
TARGETS=$(printf '%s' "$TARGETS" | sed 's/^ *//')
[ -n "$TARGETS" ] || Die '没有找到 desktop / web profile。请先确认 DeepSeek Harness 已经初始化过。'

# 改 JSON 需要 node；没有 node 就不动手，避免留下半卸状态
if ! dsh_run_node "$PROFILE_JSON_TOOL" --help >/dev/null 2>&1; then
  Die '找不到可用的 node（PATH 里没有，DSH 客户端自带的 Electron 也没找到），无法安全修改 profile 配置。'
fi

get_field() {
  _v=''
  if [ -f "$1/package.json" ]; then
    _v=$(dsh_run_node "$PROFILE_JSON_TOOL" get-field --profile-dir "$1" --name "$2" --field "$3" 2>/dev/null) || _v=''
  fi
  printf '%s\n' "$_v"
}

PLUGIN_NAMES='dsh-boot-suite dsh-startup-screen dsh-chat-wallpaper'
STAMP=$(date +%Y%m%d-%H%M%S)

Say "要处理的 profile：$(printf '%s' "$TARGETS" | tr ' ' '、')"
if [ "$CHECK_ONLY" = 1 ]; then
  Say '[检查模式] 只报告计划，不修改任何东西'
  for _p in $TARGETS; do
    Say "  会清理 profile $_p 的依赖 / bundles / node_modules 链接（备份到 _backup-uninstall-$STAMP/）"
  done
  exit 0
fi

# ── 3. 逐 profile 清理 ─────────────────────────────────────────────────────
for _prof in $TARGETS; do
  _dir="$PROFILES_ROOT/$_prof"
  Say ''
  Say "=== profile: $_prof ==="
  if [ ! -f "$_dir/package.json" ]; then
    Say '  （没有 package.json，跳过）'
    continue
  fi

  _bk="$_dir/_backup-uninstall-$STAMP"
  if ! mkdir -p "$_bk"; then
    Say "  [!] 无法创建备份目录：${_bk}（跳过该 profile）"
    continue
  fi
  cp "$_dir/package.json" "$_bk/package.json" 2>/dev/null || Say "  [!] 备份 package.json 失败"
  if [ -f "$_dir/pnpm-lock.yaml" ]; then
    cp "$_dir/pnpm-lock.yaml" "$_bk/pnpm-lock.yaml" 2>/dev/null || true
  fi
  Say "  备份 → $_bk"

  # 1) 用 profile-json 从 dependencies / bundles 里删掉三个插件名（唯一改 package.json 的地方）
  _removed=''
  for _name in $PLUGIN_NAMES; do
    _dep=$(get_field "$_dir" "$_name" dependency)
    if dsh_run_node "$PROFILE_JSON_TOOL" remove-plugin --profile-dir "$_dir" --name "$_name" >/dev/null 2>&1; then
      [ -n "$_dep" ] && _removed="$_removed $_name"
    else
      Say "  [!] 从 package.json 移除 $_name 失败"
    fi
  done
  _removed=$(printf '%s' "$_removed" | sed 's/^ *//')
  if [ -n "$_removed" ]; then
    Say "  依赖已移除：$(printf '%s' "$_removed" | tr ' ' '、')"
  else
    Say '  依赖已移除：（本来就没有）'
  fi
  _show=$(dsh_run_node "$PROFILE_JSON_TOOL" show --profile-dir "$_dir" 2>/dev/null || true)
  _bundles_line=$(printf '%s\n' "$_show" | grep '^bundles: ' | head -n 1)
  Say "  $_bundles_line"

  # 2) 删 node_modules 下同名的链接 / 目录（真实目录先移到备份，不直接删）
  _nm="$_dir/node_modules"
  if [ -d "$_nm" ]; then
    for _name in $PLUGIN_NAMES dsh-boot-suite-link; do
      _inst="$_nm/$_name"
      if [ -L "$_inst" ]; then
        rm -f "$_inst" && Say "  已删除符号链接 node_modules/$_name"
      elif [ -d "$_inst" ]; then
        mkdir -p "$_bk"
        mv "$_inst" "$_bk/node_modules-$_name" && Say "  真实目录已移到备份：$_bk/node_modules-$_name"
      elif [ -e "$_inst" ]; then
        rm -f "$_inst" && Say "  已删除 node_modules/$_name"
      fi
    done
  fi
  # 3) lockfile 只备份不删（保持与 Windows 一致）
done

Say ''
Say '完成。请重新打开 DeepSeek Harness，确认界面恢复且没有开机动画。'
Say '如果仍有动画：说明还有第二份安装（另一个 profile 或另一个插件目录），'
Say '请双击仓库根目录的 setup.command（选 3）生成报告发给作者。'
exit 0
