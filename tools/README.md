# tools —— 维护者工具索引

> 用户不需要进这个目录：Windows 双击仓库根目录的 `setup.cmd`，macOS 双击 `setup.command`，
> 菜单里就能安装 / 卸载 / 诊断 / 看离线预览。这里是给维护者的脚本本体与开发工具。

**约定：脚本文件名一律 ASCII kebab-case，中文只出现在脚本内容与输出里。**
中文文件名在 Windows 压缩包 / 解压、shell glob、跨平台 git 里都会连环踩坑，仓库不再新增。

## 一、根目录入口（只这 4 个脚本）

| 脚本 | 平台 | 干什么 |
|---|---|---|
| `setup.cmd` | Windows | 双击入口：中文菜单（1 安装/更新、2 卸载、3 诊断、4 打开离线预览、0 退出）。纯 ASCII 薄壳，逻辑在 `tools/windows/setup.ps1` |
| `setup.command` | macOS | 双击入口：Finder 双击在 Terminal 打开同一个中文菜单。逻辑在 `tools/macos/setup.sh` |
| `install-online.ps1` | Windows | 在线安装：`irm https://raw.githubusercontent.com/ApexGP/dsh-boot/main/install-online.ps1 \| iex` |
| `install-online.sh` | macOS | 在线安装：`curl -fsSL https://raw.githubusercontent.com/ApexGP/dsh-boot/main/install-online.sh \| sh` |

## 二、Windows（`tools/windows/`）

| 脚本 | 干什么 | 什么时候用 |
|---|---|---|
| `setup.ps1` | 中文菜单：转调下面几个脚本，附带离线预览 | `setup.cmd` 调它 |
| `install.ps1` | 安装 / 更新到 desktop、web profile；装前留「紧急回滚」checkpoint，装后按真实文件校验 | 首次安装、升级 |
| `uninstall.ps1` | 彻底卸载插件（配置先备份到 `~/.dsh/profiles/<profile>/_backup-uninstall-<时间戳>/`） | **开机黑屏、界面点不动** |
| `rollback-version.ps1` | 回滚到更新前的版本（桌面「紧急回滚-V…」按钮调它） | 新版打不开 |
| `diagnose.ps1` | 生成桌面诊断报告 `dsh诊断-<时间戳>.txt` | 排查 / 反馈给作者 |
| `update-apply.ps1` | 自动更新执行器：等 DSH 退出后校验 zip、换版本、重开 DSH | 设置页「立即更新」 |

> 过渡兼容垫片 `tools/install.ps1` 已在 v2.16.15 删除。
> 影响范围：仍停留在 ≤2.16.10 的用户，如果用旧更新器直接升级到 ≥2.16.15，会在「检查安装器」阶段失败（旧更新器硬编码旧路径）；请改用 `install-online.ps1`，或先升级到 2.16.11–2.16.14 再更新。2.16.11+ 的更新器只认 `tools/windows/install.ps1`，不受影响。

## 三、macOS（`tools/macos/`）

macOS 没有 PowerShell，对应能力全部换成 POSIX sh（macOS 自带 `/bin/sh` 即可），不需要 Homebrew。

| 脚本 | 干什么 | 什么时候用 |
|---|---|---|
| `setup.sh` | 中文菜单（与 Windows 菜单一致） | `setup.command` 调它 |
| `install.sh` | 安装 / 更新（对齐 `install.ps1`）；支持 `--check-only` / `--force` / `--profiles` | 首次安装、升级 |
| `uninstall.sh` | 彻底卸载插件（配置先备份到 `~/.dsh/profiles/<profile>/_backup-uninstall-<时间戳>/`） | **mac 开机黑屏、界面点不动** |
| `rollback-version.sh` | 回滚到更新前的插件版本（桌面「紧急回滚-V<版本>…command」调它） | 新版打不开 |
| `diagnose.sh` | 生成桌面诊断报告 `dsh诊断-<时间戳>.txt` | 排查 / 反馈给作者 |
| `update-apply.sh` | 自动更新执行器：等 DSH 退出后校验 zip、替换版本、重开 DSH | 设置页「立即更新」（宿主打开 Terminal 运行） |
| `lib/mac-common.sh` | 公共函数库（找 app / CLI / node、判断进程、等退出、重开） | 被上面脚本 source，不单独运行 |
| `lib/profile-json.mjs` | profile 的 `package.json` 读写（UTF-8 无 BOM，保留无关字段与顺序） | 被上面脚本调用 |

## 四、开发工具（`tools/dev/`）

| 脚本 | 干什么 | 用法 |
|---|---|---|
| `build-release.mjs` | 打发布包：zip + npm tgz；校验必需文件、版本、UTF-8 文件名标志位 | `npm run release` |
| `motion-check.mjs` | 动效回归：headless Chrome 按真实时间跑一遍，断言画面在动 / 分幕换过 / 收得干净 | `npm run motion:check` |
| `export-frames.mjs` | 按 fps 把模板逐帧导出成 PNG + `manifest.json`（剪辑软件当图片序列用） | `node tools/dev/export-frames.mjs --template=<id>` |
| `stage-local.mjs` | 安全暂存本机升级包：解压到临时目录校验后再原子替换 `pkg/`，失败保留旧版本 | `node tools/dev/stage-local.mjs <版本>` |
| `make-upgrade-helper.mjs` | 生成桌面升级助手 `.cmd`（整段模板 + 写后读回校验，防再次被拆行） | `node tools/dev/make-upgrade-helper.mjs <版本>` |
| `make-backup.ps1` | 改代码前留整仓快照到 `backups/known-good-<时间戳>/`（源码 + 两个用户配置） | `powershell -File tools\dev\make-backup.ps1` |
| `rollback.ps1` | 回滚到某个快照（默认取最新） | `powershell -File tools\dev\rollback.ps1 [-Backup <目录>]` |

## 五、其它与常用命令

- `editor.html` —— 模板编辑器（设置页「打开模板编辑器」用的就是它），也可以直接双击打开。
- 在仓库根目录跑：

```sh
npm test                                  # 全套冒烟（host/splash/client/desktop/壁纸/合并/坐标/包/macOS）
npm run motion:check                      # 动效回归，需要本机 Chrome（CHROME_PATH 可覆盖）
npm run release                           # 打发布包 zip + tgz
node test/smoke-package.mjs               # 只查编码/路径/交叉引用（改脚本后必跑）
node test/smoke-macos.mjs                 # mac 侧专项（文件/语法/契约/profile-json/--check-only）
sh tools/macos/install.sh --check-only    # 只看 macOS 安装计划，不动任何文件
```

- 编码硬约束：`.ps1` 必须 UTF-8 带 BOM（首三字节 `EF BB BF`），`.cmd` 必须纯 ASCII，
  `.command` / `.sh` 必须是 POSIX sh、可执行位 755。`test/smoke-package.mjs` 会逐条拦。
- 目录里没有 `node_modules` 依赖：这些脚本只用 Node 标准库 / 系统 `sh` / PowerShell 5.1。
