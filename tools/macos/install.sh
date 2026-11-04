#!/bin/sh
# ============================================================================
# dsh-boot-suite —— macOS 一键安装
#
# 用法（最省事：双击仓库根目录的 setup.command，再选 1）：
#   sh tools/macos/install.sh                       # 安装到 desktop / web 中已初始化的 profile
#   sh tools/macos/install.sh --check-only          # 只看计划，不修改任何东西
#   sh tools/macos/install.sh --force               # DSH 还在运行时也继续（装完手动重启）
#   sh tools/macos/install.sh --profiles desktop,web
#
# 它做什么（与 Windows 的 tools/windows/install.ps1 行为对齐）：
#   1. 找 DSH 命令行（dsh）与已初始化过的 profile（web / desktop）
#   2. 桌面端在跑就先要求完全退出（--force 可热装）
#   3. 换版本安装前，在桌面留一个「紧急回滚」按钮（出了事双击就能退回去）
#   4. 优先用「dsh plugin add link:<仓库>」；命令行不可用 / 被拒 / 没真正装成时，
#      改为手动改 profile/package.json + 建 node_modules 符号链接
#   5. 安装后校验只信 profile 的真实文件，不信 CLI 退出码；失败自动恢复备份
#
# 环境变量：DSH_HOME 覆盖用户数据目录（默认 ~/.dsh，主要用于测试）
#           DSH_BOOT_SUITE_ROLLBACK=1 时跳过回滚 checkpoint（回滚脚本会设置）
# ============================================================================

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P)
# 本脚本在 tools/macos/ 下，仓库根在上两级（仓库整理前在 tools/ 下，只上一级）
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd -P)

# 公共函数库：与本脚本同目录的 lib/（rollback-version.sh 被复制到更新目录时结构同构）
if [ -f "$SCRIPT_DIR/lib/mac-common.sh" ]; then
  . "$SCRIPT_DIR/lib/mac-common.sh"
else
  printf '[x] 缺少公共函数库：%s\n' "$SCRIPT_DIR/lib/mac-common.sh" >&2
  exit 1
fi
PROFILE_JSON_TOOL="$SCRIPT_DIR/lib/profile-json.mjs"

Say() { printf '%s\n' "$*"; }
Die() { printf '[x] %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
dsh-boot-suite —— macOS 一键安装

用法：
  sh tools/macos/install.sh [选项]
  （也可以双击仓库根目录的 setup.command，选 1）

选项：
  --check-only            只打印计划，绝不修改任何文件；DSH 在运行时也不会失败
  --force                 DSH 还在运行时继续安装（不推荐；装完请手动重启 DSH）
  --profiles <a,b>        指定 profile（逗号分隔），默认取 desktop / web 中已初始化的
  -h, --help              显示本帮助

环境变量：
  DSH_HOME                覆盖用户数据目录，默认 ~/.dsh（测试用）
  DSH_CLI                 覆盖 dsh 命令行路径（测试用）
  DSH_APP_DIR             覆盖 DeepSeek Harness.app 路径（测试用）

说明：
  · 安装方式是 link（把插件链接到仓库目录），改代码立即生效，不复制文件
  · 装完不会自动启动 DSH，请手动打开
  · 出问题先完全退出 DSH，再双击仓库根目录的 setup.command（选 2 卸载）
EOF
}

# ── 0. 基本检查 ────────────────────────────────────────────────────────────
[ -f "$REPO_ROOT/package.json" ] || Die "这不像插件目录：$REPO_ROOT"
[ -f "$REPO_ROOT/lib/index.js" ] || Die '源码不完整（缺 lib/index.js），你下载的可能是残缺的压缩包'
[ -f "$SCRIPT_DIR/lib/mac-common.sh" ] || Die "源码不完整（缺 tools/macos/lib/mac-common.sh）：$REPO_ROOT"
[ -f "$PROFILE_JSON_TOOL" ] || Die "源码不完整（缺 tools/macos/lib/profile-json.mjs）：$REPO_ROOT"

# 直接按 package.json 的机器格式取版本，避免依赖 node（--check-only 要尽量「什么都不启动」）
read_version() {
  sed -n 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$1" 2>/dev/null | head -n 1
}
VER=$(read_version "$REPO_ROOT/package.json")
[ -n "$VER" ] || Die '读不出本仓库的版本号（package.json 的 version 字段）'

Say "dsh-boot-suite v$VER"
Say "仓库位置：$REPO_ROOT"

# ── 1. 解析参数 ────────────────────────────────────────────────────────────
CHECK_ONLY=0
FORCE=0
PROFILES_ARG=''
while [ $# -gt 0 ]; do
  case "$1" in
    --check-only) CHECK_ONLY=1 ;;
    --force) FORCE=1 ;;
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
    -h|--help) usage; exit 0 ;;
    *)
      printf '[x] 未知参数：%s\n\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done
if [ "$CHECK_ONLY" = 1 ]; then
  Say '[检查模式] 只报告计划，不修改任何东西'
fi
Say "DSH 数据目录：$(dsh_home)"

# ── 2. 找 DSH 命令行（找不到就全程走手动安装） ─────────────────────────────
CLI=$(dsh_find_cli 2>/dev/null || true)
MANUAL_MODE=0
if [ -z "$CLI" ]; then
  Say ''
  Say '[!] 没找到 DeepSeek Harness 的命令行（dsh）。'
  Say '    不一定是没装：精简安装 / 便携版可能不带 CLI。'
  Say '    本次改用「手动安装」：直接改 profile 配置 + 建符号链接，效果一样。'
  MANUAL_MODE=1
else
  Say "DSH 命令行：$CLI"
fi

# ── 3. 找 profile ──────────────────────────────────────────────────────────
PROFILES_ROOT=$(dsh_profiles_root)
[ -d "$PROFILES_ROOT" ] || Die "还没初始化过 profile（$PROFILES_ROOT 不存在）。请先打开一次 DeepSeek Harness Desktop，完全退出后再运行本脚本。"

TARGETS=''
add_target() {
  case "$1" in
    ''|*[!A-Za-z0-9._-]*) Die "profile 名不合法：$1" ;;
  esac
  for _exist in $TARGETS; do
    [ "$_exist" = "$1" ] && return 0
  done
  TARGETS="$TARGETS $1"
}
if [ -n "$PROFILES_ARG" ]; then
  for _p in $(printf '%s' "$PROFILES_ARG" | tr ',' ' '); do
    if [ -d "$PROFILES_ROOT/$_p" ]; then
      add_target "$_p"
    else
      Say "[!] 跳过不存在的 profile：$_p"
    fi
  done
else
  for _p in desktop web; do
    [ -d "$PROFILES_ROOT/$_p" ] && add_target "$_p"
  done
fi
TARGETS=$(printf '%s' "$TARGETS" | sed 's/^ *//')
[ -n "$TARGETS" ] || Die '没有找到已初始化的 profile（desktop / web）。先打开一次桌面端再退出。'
Say "要装的 profile：$(printf '%s' "$TARGETS" | tr ' ' '、')"

# ── 4. 桌面端必须先完全退出（--check-only 只提示，--force 热装） ────────────
case " $TARGETS " in
  *' desktop '*)
    if dsh_is_running; then
      if [ "$CHECK_ONLY" = 1 ]; then
        Say '（检查模式）桌面端正在运行 —— 真正安装前建议先完全退出'
      elif [ "$FORCE" = 1 ]; then
        Say '[!] 桌面端还在运行：--force 热装继续；装完请手动重启 DSH 让新代码生效。'
      else
        Die '桌面端还在运行。请先完全退出 DeepSeek Harness（窗口 + 菜单栏图标）再运行本脚本；确实要热装可加 --force（不推荐）。'
      fi
    fi
    ;;
esac

# ── 5. 非检查模式：确认 node 可用（改 JSON / 校验都要它） ──────────────────
if [ "$CHECK_ONLY" != 1 ]; then
  if ! dsh_run_node "$PROFILE_JSON_TOOL" --help >/dev/null 2>&1; then
    Die '找不到可用的 node（PATH 里没有 node，DSH 客户端自带的 Electron 也没找到）。请装 Node.js 20+ 或重装 DeepSeek Harness Desktop 后再试。'
  fi
fi

# ── 小工具 ─────────────────────────────────────────────────────────────────
# 从 profile 读一个字段（读不到输出空行）
get_field() {
  _v=''
  if [ -f "$1/package.json" ]; then
    _v=$(dsh_run_node "$PROFILE_JSON_TOOL" get-field --profile-dir "$1" --name "$2" --field "$3" 2>/dev/null) || _v=''
  fi
  printf '%s\n' "$_v"
}

remove_node_modules_entry() {
  # $1=profile 目录 $2=包名 $3=备份目录
  _inst="$1/node_modules/$2"
  if [ -L "$_inst" ]; then
    rm -f "$_inst" && Say "        已删除符号链接 node_modules/$2"
  elif [ -d "$_inst" ]; then
    mkdir -p "$3"
    mv "$_inst" "$3/node_modules-$2" && Say "        真实目录已移到备份：$3/node_modules-$2"
  elif [ -e "$_inst" ]; then
    rm -f "$_inst"
  fi
  return 0
}

# 安装失败时恢复 profile 备份（只动 package.json / pnpm-lock.yaml，与 Windows 一致）
restore_backup() {
  _dir=$1
  _bk=$2
  if [ -f "$_bk/package.json" ]; then
    cp "$_bk/package.json" "$_dir/package.json" 2>/dev/null && Say '  已恢复 profile/package.json'
  fi
  if [ -f "$_bk/pnpm-lock.yaml" ]; then
    cp "$_bk/pnpm-lock.yaml" "$_dir/pnpm-lock.yaml" 2>/dev/null && Say '  已恢复 profile/pnpm-lock.yaml'
  fi
  # 手动安装时若把真实目录挪进了备份，恢复回去
  if [ -d "$_bk/node_modules-old" ] && [ ! -e "$_dir/node_modules/dsh-boot-suite" ]; then
    mkdir -p "$_dir/node_modules"
    mv "$_bk/node_modules-old" "$_dir/node_modules/dsh-boot-suite" 2>/dev/null && Say '  已恢复原来的 node_modules/dsh-boot-suite 目录'
  fi
  # 手动安装 / CLI 安装留下的、指向本仓库的符号链接也清掉，避免「JSON 回滚了、链接还指着新版」
  _inst="$_dir/node_modules/dsh-boot-suite"
  if [ -L "$_inst" ] && [ ! -d "$_bk/node_modules-old" ]; then
    _lt=$(readlink "$_inst" 2>/dev/null || true)
    case "$_lt" in
      "$REPO_ROOT") rm -f "$_inst" && Say '  已移除本次安装创建的符号链接' ;;
    esac
  fi
}

# 把字符串包成 shell 双引号参数（转义反斜杠、双引号），用于生成可双击的 .command 内容
dq() {
  printf '"%s"' "$(printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"
}

write_rollback_button() {
  # $1=按钮路径 $2=rollback-version.sh 路径 $3=旧版本目录 $4=profile $5=旧版本号
  _btn=$1
  _rb=$2
  _tgt=$3
  _prof=$4
  _ver=$5
  _tmp="$_btn.tmp-$$"
  {
    printf '%s\n' '#!/bin/sh'
    printf '%s\n' '# dsh-boot-suite 紧急回滚按钮（安装器自动生成，请勿手改）'
    printf '# 目标旧版本：v%s\n' "$_ver"
    printf '%s\n' '# 用法：先完全退出 DeepSeek Harness（窗口 + 菜单栏图标），再双击本文件。'
    printf '%s\n' 'echo "============================================================"'
    printf '%s\n' 'echo "  dsh-boot-suite 紧急回滚按钮"'
    printf '%s\n' "echo \"  只把插件切换回 v${_ver}，你的设置 / 模板 / 底图都不会动\""
    printf '%s\n' 'echo "============================================================"'
    printf 'exec sh %s --target-pkg %s --profile %s\n' "$(dq "$_rb")" "$(dq "$_tgt")" "$(dq "$_prof")"
  } > "$_tmp" || { rm -f "$_tmp"; return 1; }
  chmod +x "$_tmp" 2>/dev/null || { rm -f "$_tmp"; return 1; }
  mv "$_tmp" "$_btn" || { rm -f "$_tmp"; return 1; }
  chmod +x "$_btn" 2>/dev/null || return 1
  return 0
}

# ── 6. 更新前的紧急回滚 checkpoint（与 Windows install.ps1 等价） ──────────
CHECKPOINT_PATH=''
CHECKPOINT_VERSION=''
CHECKPOINT_PROFILE=''
CHECKPOINT_BUTTON=''

prepare_checkpoint() {
  [ "$CHECK_ONLY" = 1 ] && return 0
  [ "$DSH_BOOT_SUITE_ROLLBACK" = "1" ] && return 0
  for _p in $TARGETS; do
    _dir="$PROFILES_ROOT/$_p"
    [ -f "$_dir/package.json" ] || continue
    _ver=$(get_field "$_dir" dsh-boot-suite version)
    [ -n "$_ver" ] || continue
    [ "$_ver" != "$VER" ] || continue
    _link=$(get_field "$_dir" dsh-boot-suite linkTarget)
    [ -n "$_link" ] || continue
    [ -d "$_link" ] || continue
    [ -f "$_link/package.json" ] || continue
    CHECKPOINT_PATH=$_link
    CHECKPOINT_VERSION=$_ver
    CHECKPOINT_PROFILE=$_p
    break
  done
  [ -n "$CHECKPOINT_PATH" ] || return 0

  UPDATES_ROOT="$(dsh_home)/boot-suite-updates"
  ROLLBACK_SRC="$SCRIPT_DIR/rollback-version.sh"
  if [ ! -f "$ROLLBACK_SRC" ]; then
    Say '[!] 找不到 tools/macos/rollback-version.sh，跳过回滚保护。'
    return 0
  fi
  if ! mkdir -p "$UPDATES_ROOT/lib"; then
    Say "[!] 无法创建 ${UPDATES_ROOT}，跳过回滚保护。"
    return 0
  fi
  if ! cp "$ROLLBACK_SRC" "$UPDATES_ROOT/rollback-version.sh"; then
    Say '[!] 复制回滚脚本失败，跳过回滚保护。'
    return 0
  fi
  # 回滚脚本依赖公共函数库，按同构目录复制一份（$UPDATES_ROOT/lib/mac-common.sh）
  cp "$SCRIPT_DIR/lib/mac-common.sh" "$UPDATES_ROOT/lib/mac-common.sh" 2>/dev/null || true
  chmod +x "$UPDATES_ROOT/rollback-version.sh" 2>/dev/null || true

  _desk=$(dsh_desktop_dir)
  mkdir -p "$_desk" 2>/dev/null || true
  BUTTON_NAME="紧急回滚-V${CHECKPOINT_VERSION}（先完全退出 DSH 再双击）.command"
  CHECKPOINT_BUTTON="$_desk/$BUTTON_NAME"
  if write_rollback_button "$CHECKPOINT_BUTTON" "$UPDATES_ROOT/rollback-version.sh" "$CHECKPOINT_PATH" "$CHECKPOINT_PROFILE" "$CHECKPOINT_VERSION"; then
    # 写后读回校验：文件可执行、内容含关键参数、目标目录还在
    _bad=''
    [ -x "$CHECKPOINT_BUTTON" ] || _bad='不可执行'
    [ -n "$_bad" ] || grep -q -e '--target-pkg' "$CHECKPOINT_BUTTON" || _bad='缺 --target-pkg'
    [ -n "$_bad" ] || grep -q -e '--profile' "$CHECKPOINT_BUTTON" || _bad='缺 --profile'
    [ -n "$_bad" ] || grep -q -e 'rollback-version.sh' "$CHECKPOINT_BUTTON" || _bad='缺 rollback-version.sh'
    [ -n "$_bad" ] || [ -f "$CHECKPOINT_PATH/package.json" ] || _bad='目标版本目录不见了'
    if [ -z "$_bad" ]; then
      Say ''
      Say "[回滚保护] 当前 v$CHECKPOINT_VERSION 已记成桌面按钮：$BUTTON_NAME"
      Say '           新版装不上或打不开 DSH 时，完全退出 DSH 后双击它即可回滚。'
    else
      Say "[!] 回滚按钮写入校验失败（${_bad}），已删除该按钮；继续安装。"
      rm -f "$CHECKPOINT_BUTTON"
      CHECKPOINT_BUTTON=''
    fi
  else
    Say '[!] 回滚按钮写入失败（不影响本次安装），桌面暂时没有回滚按钮。'
    CHECKPOINT_BUTTON=''
  fi
  return 0
}

# ── 7. 单个 profile 的安装流程 ─────────────────────────────────────────────
remove_old_plugin() {
  # $1=profile 目录 $2=profile 名 $3=旧插件名 $4=备份目录
  _dir=$1
  _prof=$2
  _name=$3
  _bk=$4
  _dep=$(get_field "$_dir" "$_name" dependency)
  if [ -z "$_dep" ]; then
    Say "        跳过 ${_name}（未安装）"
    return 0
  fi
  Say "        卸载旧插件 $_name …"
  _ok=0
  if [ "$MANUAL_MODE" = 0 ]; then
    _out=$("$CLI" plugin --profile "$_prof" remove "$_name" 2>&1)
    _rc=$?
    [ -n "$_out" ] && printf '%s\n' "$_out" | sed 's/^/        /'
    if [ "$_rc" -eq 0 ]; then
      case "$_out" in
        *'managed exclusively'*|*'not installed'*|*'未安装'*) _ok=0 ;;
        *) _ok=1 ;;
      esac
    fi
  fi
  if [ "$_ok" -eq 0 ]; then
    if dsh_run_node "$PROFILE_JSON_TOOL" remove-plugin --profile-dir "$_dir" --name "$_name" >/dev/null 2>&1; then
      remove_node_modules_entry "$_dir" "$_name" "$_bk"
      Say '        已改为手动清理'
    else
      Say "        [!] 手动清理 $_name 失败（继续）"
    fi
  fi
  return 0
}

install_manual() {
  # $1=profile 目录 $2=备份目录
  _dir=$1
  _bk=$2
  Say '        手动安装：写 profile/package.json 的 dependencies + 建 node_modules 符号链接…'
  if ! dsh_run_node "$PROFILE_JSON_TOOL" add-dependency --profile-dir "$_dir" --name dsh-boot-suite --spec "link:$REPO_ROOT" >/dev/null; then
    Say '        [x] 写入 dependencies 失败'
    return 1
  fi
  if ! mkdir -p "$_dir/node_modules"; then
    Say '        [x] 创建 node_modules 目录失败'
    return 1
  fi
  _inst="$_dir/node_modules/dsh-boot-suite"
  if [ -L "$_inst" ]; then
    rm -f "$_inst"
  elif [ -d "$_inst" ]; then
    mkdir -p "$_bk"
    mv "$_inst" "$_bk/node_modules-old" || { Say '        [x] 备份旧的 node_modules/dsh-boot-suite 失败'; return 1; }
  fi
  if ! ln -s "$REPO_ROOT" "$_inst"; then
    Say '        [x] 创建符号链接失败（可能被安全软件拦截）'
    return 1
  fi
  if [ ! -f "$_inst/package.json" ]; then
    Say '        [x] 符号链接建好了，但读不到 package.json'
    return 1
  fi
  Say "        ok -> $_inst"
  return 0
}

ensure_bundle() {
  dsh_run_node "$PROFILE_JSON_TOOL" ensure-bundle --profile-dir "$1" --name dsh-boot-suite >/dev/null
}

verify_installed() {
  dsh_run_node "$PROFILE_JSON_TOOL" verify-installed --profile-dir "$1" --name dsh-boot-suite --spec "link:$REPO_ROOT" --version "$VER"
}

install_one_profile() {
  _prof=$1
  _dir="$PROFILES_ROOT/$_prof"
  Say ''
  Say "=== profile: $_prof ==="

  if [ "$CHECK_ONLY" = 1 ]; then
    Say "  会执行：dsh plugin --profile $_prof remove dsh-startup-screen / dsh-chat-wallpaper（装过才卸）"
    Say "  会执行：dsh plugin --profile $_prof add link:$REPO_ROOT"
    Say '  命令行不可用时兜底：手动改 profile/package.json + node_modules 符号链接'
    Say '  会执行：修正 bundles 列表，并按 profile 的真实文件做安装后校验（失败自动恢复备份）'
    return 0
  fi

  if [ ! -f "$_dir/package.json" ]; then
    Say '  （没有 package.json，跳过）'
    return 0
  fi

  _stamp=$(date +%Y%m%d-%H%M%S)
  _bk="$_dir/_backup-install-$_stamp"
  if ! mkdir -p "$_bk"; then
    Say "  [x] 无法创建备份目录：$_bk"
    return 1
  fi
  if ! cp "$_dir/package.json" "$_bk/package.json"; then
    Say '  [x] 备份 package.json 失败'
    return 1
  fi
  if [ -f "$_dir/pnpm-lock.yaml" ]; then
    cp "$_dir/pnpm-lock.yaml" "$_bk/pnpm-lock.yaml" 2>/dev/null || true
  fi
  Say "  备份 → $_bk"

  Say '  [1/3] 检查并卸掉同类旧插件…'
  for _old in dsh-startup-screen dsh-chat-wallpaper; do
    remove_old_plugin "$_dir" "$_prof" "$_old" "$_bk"
  done

  Say '  [2/3] 安装本插件（link 方式，改代码即生效）…'
  _used_cli=0
  if [ "$MANUAL_MODE" = 0 ]; then
    _out=$("$CLI" plugin --profile "$_prof" add "link:$REPO_ROOT" 2>&1)
    _rc=$?
    [ -n "$_out" ] && printf '%s\n' "$_out" | sed 's/^/        /'
    if [ "$_rc" -ne 0 ]; then
      Say '        第一次安装没成功，改用 npm 国内镜像重试一次…'
      _out=$(npm_config_registry=https://registry.npmmirror.com "$CLI" plugin --profile "$_prof" add "link:$REPO_ROOT" 2>&1)
      _rc=$?
      [ -n "$_out" ] && printf '%s\n' "$_out" | sed 's/^/        /'
    fi
    if [ "$_rc" -eq 0 ]; then
      case "$_out" in
        *'managed exclusively'*) _used_cli=0 ;;
        *) _used_cli=1 ;;
      esac
    fi
  else
    Say '        没找到 DSH 命令行，直接使用「手动安装」…'
  fi

  if [ "$_used_cli" = 0 ]; then
    if ! install_manual "$_dir" "$_bk"; then
      restore_backup "$_dir" "$_bk"
      Die '手动安装失败，已恢复 profile 备份。请把上面的输出发到仓库 issue。'
    fi
  fi

  Say '  [3/3] 修正 bundles 列表并做安装后校验…'
  ensure_bundle "$_dir"
  if ! verify_installed "$_dir"; then
    if [ "$_used_cli" = 1 ]; then
      Say '  [2/3] 命令行的退出码是 0，但插件并没有真正装进 profile。'
      Say '        （新版 DSH 的 dsh 命令行不解析 plugin 子命令时会这样：打印 web 地址就退出）'
      Say '        改用「手动安装」兜底…'
      if ! install_manual "$_dir" "$_bk"; then
        restore_backup "$_dir" "$_bk"
        Die '手动安装失败，已恢复 profile 备份。请把上面的输出发到仓库 issue。'
      fi
      ensure_bundle "$_dir"
    fi
    if ! verify_installed "$_dir"; then
      Say '  [x] 安装后校验失败：profile 里没有可用的 dsh-boot-suite'
      Say '      （bundles 里不会添加它，避免 DSH 启动时加载一个不存在的插件）'
      restore_backup "$_dir" "$_bk"
      Die '安装失败，已回滚。请把上面的输出发到仓库 issue。'
    fi
  fi

  _ver_now=$(get_field "$_dir" dsh-boot-suite version)
  Say "  装好了：v$_ver_now"
  return 0
}

prepare_checkpoint

for _prof in $TARGETS; do
  if ! install_one_profile "$_prof"; then
    Die "profile $_prof 安装流程失败，已中止（其它 profile 未处理）。"
  fi
done

Say ''
if [ "$CHECK_ONLY" = 1 ]; then
  Say '检查完毕 —— 没有修改任何东西。确认无误后双击仓库根目录的 setup.command（选 1）正式安装。'
  exit 0
fi

# 安装成功：桌面只保留最新一个回滚按钮（旧按钮自动清理，不会越积越多）
if [ -n "$CHECKPOINT_BUTTON" ] && [ -f "$CHECKPOINT_BUTTON" ]; then
  for _old in "$(dsh_desktop_dir)"/紧急回滚-*.command; do
    [ -e "$_old" ] || continue
    [ "$_old" = "$CHECKPOINT_BUTTON" ] && continue
    rm -f "$_old"
  done
  Say "[回滚保护] 新版安装成功，桌面回滚按钮已更新为：$(basename "$CHECKPOINT_BUTTON")"
  Say '           旧按钮已自动清理（下次更新会自动替换，不会越积越多）。'
fi

Say ''
Say '完成 —— 现在打开 DeepSeek Harness Desktop（菜单栏图标点开即可）。'
Say '打开后确认三件事：'
Say '  1) 设置页里多出「启动动画」和「聊天背景」两项'
Say '  2) 冷启动会播放开机动画'
Say '  3) 动画结束后落在聊天底图上（大字横幅可选）'
Say ''
Say '出问题（黑屏/点不动）：先完全退出 DeepSeek Harness（窗口 + 菜单栏图标），'
Say '再双击仓库根目录的 setup.command（选 2 卸载）；还不行就选 3 生成诊断报告发给作者。'
exit 0
