# tools —— 维护者工具

> 这三个脚本**不需要 DSH 界面能显示**，界面全黑时也能跑。
> 只依赖 PowerShell 5.1+ 和 node（PATH 里或 DSH 自带的 pnpm 都行）。

| 脚本 | 干什么 | 什么时候用 |
|---|---|---|
| `emergency-uninstall.cmd` | 把 `dsh-boot-suite` 从 profile 里彻底卸掉，恢复干净界面 | **开机黑屏、动画卡死、界面点不动** |
| `rollback.cmd` | 切回 `backups/` 下最新的 `known-good-*` 快照 | 想退回上一个能用的版本 |
| `make-backup.ps1` | 给当前状态留一份快照到 `backups/` | **改代码之前**（自保） |

## 用法

1. 用任务管理器结束全部 `DeepSeek Harness` 进程
2. 双击对应的 `.cmd`（或 `powershell -NoProfile -ExecutionPolicy Bypass -File xxx.ps1`）
3. 重新打开桌面端

## 参数

- `-Profile <名字>`：默认 `desktop`，也可以指定 `web` 等其他 profile
- `rollback.ps1 -Backup "backups/known-good-2026-10-18_170000"`：指定要回滚到的备份
- `make-backup.ps1`：无参数，直接生成

## 注意

- 三个脚本默认会**先检查桌面端是否完全退出**，运行中会拒绝（避免在进程锁着 profile 时写半截）；确认要热装可加 `-Force`，装完重启 DSH。
- 卸装 / 回滚都不会动 `~/.dsh/dsh-startup.json` 和 `~/.dsh/chat-wallpaper.json`（回滚会从备份里恢复它们）。

---

## macOS（v2.16.11 起）

macOS 没有 PowerShell，对应能力全部换成 POSIX sh（macOS 自带 `/bin/sh` 即可），并在仓库根目录提供双击入口。

| 脚本 | 干什么 | 什么时候用 |
|---|---|---|
| `install-macos.sh` | 安装 / 更新插件到 desktop、web profile（对齐 `install.ps1`） | 首次安装、升级（双击根目录 `安装-mac.command`） |
| `emergency-uninstall.sh` | 把插件从 profile 里彻底卸掉，配置先备份到 `~/.dsh/profiles/<profile>/_backup-uninstall-<时间戳>/` | **mac 开机黑屏、界面点不动**（双击 `卸载-mac.command`） |
| `rollback-version.sh` | 回滚到更新前的插件版本（桌面「紧急回滚-V<版本>…command」调它） | 新版打不开 |
| `doctor.sh` | 生成桌面诊断报告 `dsh诊断-<时间戳>.txt` | 排查问题、反馈给作者（双击 `诊断-mac.command`） |
| `update-apply.sh` | 自动更新执行器：等 DSH 退出后校验 zip、替换版本、重开 DSH | 设置页「立即更新」（宿主打开 Terminal 运行） |
| `lib/mac-common.sh` | macOS 公共函数库（找 app / CLI / node、判断进程、等退出、重开） | 被上面脚本 source，不单独运行 |
| `lib/profile-json.mjs` | profile 的 `package.json` 读写工具（UTF-8 无 BOM、保留无关字段与顺序） | 被上面脚本调用 |

用法：先**完全退出** DeepSeek Harness（窗口 + 菜单栏图标），再双击仓库根目录的 `安装-mac.command` / `卸载-mac.command` / `诊断-mac.command` / `打开预览.command`。
只想看安装器要做什么、不动文件：`sh tools/install-macos.sh --check-only`。
