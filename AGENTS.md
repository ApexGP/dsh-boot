# AGENTS.md · 工作规范（每个会话开始先读这份）

> 这份文件是给"下一个我"看的：上下文被压缩、或者换了会话，先读这里，别重新摸索。
> 最后更新：2026-11-05 · 版本 2.16.11（新增 macOS 支持；未发版，npm 公共包仍为 2.16.10 之前）

## 一、项目坐标

| 东西 | 路径 |
|---|---|
| 源码根目录 | `F:\Lee的GitHub仓库\DeepSeek harness 开机动画\01-源码` |
| 仓库 | https://github.com/LeeRolling/dsh-boot-suite |
| 模板商店数据源 | https://github.com/LeeRolling/dsh-boot-suite-templates |
| 备份目录 | `...\08-备份\known-good-<版本>-<说明>` |
| 发布包 | `...\03-发布包\dsh-boot-suite.tgz` |
| 参考 skill（本地） | `F:\Lee的GitHub仓库\_vendor\refactoring-ui-skill` |
| 诊断日志 | `~/.dsh/boot-suite-diag.log` |
| 用户配置 | `~/.dsh/dsh-startup.json`、`~/.dsh/chat-wallpaper.json` |
| macOS 开发机 checkout | `/Users/iracing/projectRoot/js/dsh-boot-suite`（与 Windows 同一仓库，改动可直接推） |
| macOS 桌面端 | `/Applications/DeepSeek Harness.app`（bundle id `com.deepseek.dsh`） |
| macOS 自带 CLI | `…/DeepSeek Harness.app/Contents/Resources/runtime/cli/bin/dsh`（`/usr/local/bin/dsh` 是符号链接） |

## 二、硬规则（违反过，代价很大）

1. **改之前先备份**：整仓快照进 `08-备份`；用户明确要求"凡事都要留 backup"。
2. **插件绝不黑屏**：缺模板/缺素材/字段坏了 → 一律回落默认，不能把界面锁死。
3. **模板只能是数据**：template.json 里不许出现可执行代码。
4. **自定义路由必须过信任栅栏**：`registerRoute` 已包了 `connection.requestRejection`，别绕开。
5. **首帧注入走 index 行**：`script-src` 行才会执行；`html` 行里的 `<script>` 在桌面端不跑。
6. **作者字段如实标**：`author` 写原作者，`adaptedBy` 写改版者（沈宏宏的作品不能署成自己的）。
7. **用户目录优先**：`~/.dsh/startup-templates` 覆盖内置同名模板，别写反。
8. **.cmd 必须纯 ASCII**：UTF-8 无 BOM 的 .cmd 会被当 GBK 执行成乱码。**交付给用户的 .cmd/.ps1 必须由模板或生成器产出并读回校验**，禁止用「数组 + 字符串拼接」生成（2026-10-28 v2.13.9 事故：`+$v+` 被拆成独立数组元素，版本号单独成行，用户双击后 cmd 把 `2.13.9` 当命令、更新器未启动）。生成器：`node tools/make-upgrade-helper.mjs <版本>`；交付前自己逐行读一遍。
9. **PowerShell 5.1 读 UTF-8** 用 `[System.IO.File]::ReadAllText`，别用 `Get-Content`。
10. **装/更新插件后禁止自动启动 DSH**：助手只负责安装，最后让用户手动打开；不要连续快速重启。若 DSH 报 `desktop welcome: Web authentication failed`，先备份 webstate/profile 再按官方恢复流程处理（2026-10-26 事故，详见交接文档第 2/7 节）。
11. **每次 Release 必须同步发 npm**：GitHub Release 上传完三资产（两 zip + `dsh-boot-suite.tgz`）后，在仓库根目录跑 `npm publish`（账号 `leerolling`，令牌存 `~/.npmrc`，带 bypass 2FA、2027-01-26 到期），再用 `npm view dsh-boot-suite version` 核对版本；若出现 EOTP 浏览器确认，先 `npm login` 再重试，必要时临时重建发布助手。只发 Release 不发 npm 视为发版未完成。
12. **跨窗口互通记忆必须带时间 + 窗口标题**：写入互通记忆/摘要时，第一行必须是 `YYYY年M月D日HH:mm（窗口：<窗口标题>）`，时间到分钟，然后另起一行写「记忆如下：」或「摘要如下：」；标题识别不到就写「窗口标题未知（待用户补）」，禁止省略或猜。示例：`2026年10月30日13:24（窗口：开机动画修复和维护）`。本窗口标题：`开机动画修复和维护`（可从 `~/.dsh/storages/session_projcache/sessions/*.json` 查到）。
13. **macOS 的 shell 变量一律写 `${VAR}`**：macOS 的 /bin/sh 是 bash 3.2，`$name（中文` 会把中文首字节吞进变量名（表现为 unset 变量或中文乱码；2026-11-05 实测）。`test/smoke-macos.mjs` 有静态扫描，别让它变红。
14. **mac 的 .command 双击入口必须满足**：POSIX sh（macOS 自带 /bin/sh，不依赖 bash 数组/Homebrew/PowerShell）、chmod 755、生成后写后读回校验；更新/回滚要在 Terminal 里可见进度，失败必须恢复旧版本目录与配置。

## 三、每轮收尾清单（做完功能必跑）

```powershell
cd "F:\Lee的GitHub仓库\DeepSeek harness 开机动画\01-源码"
npm test                     # 全套断言：host + splash + client + desktop + merge
npm run motion:check         # 动效回归：画面在动/分幕换过/根节点移除/无异常
npm run ui:detect            # impeccable 61 条规则（需要网络，跑不跑都可）
```

macOS 上等价：

```sh
cd ~/projectRoot/js/dsh-boot-suite
npm test                                   # 14 套冒烟（含 test/smoke-macos.mjs）
node test/smoke-macos.mjs                  # mac 专项：文件/语法/契约/profile-json/--check-only/中文变量坑
sh -n tools/*.sh tools/lib/mac-common.sh *.command   # 语法
npm run motion:check                       # 同上（Chrome 路径已跨平台）
```

然后：`git add -A` → 提交（中文说明"为什么"）→ push → 如有发版：tag + `gh release create`（三资产含 tgz）→ `npm publish`（若弹浏览器确认就用桌面发布助手）→ 两处都复核版本。
**push 完成要用 `git ls-remote` 核对远端**，网络经常 reset，命令"看起来成功"不算数。

## 四、impeccable 的用法（2026-10-18 决定：只当发布前检查，不装 skill）

```powershell
npx --yes impeccable@latest detect --json --no-config tools/editor.html preview/index.html
```

- 61 条确定性规则，不需要 LLM；发现问题会以 `warning` / `advisory` 标出
- 已知历史：编辑器主按钮 hover 4.05:1 已被抓过并修成 `#3f68f5`
- 预览页剩余的 11px 小字 / 装饰条纹属刻意，不用修

## 五、常用命令与路径

| 用途 | 命令 |
|---|---|
| DSH CLI | `C:\Users\Admin\AppData\Local\Programs\DeepSeek Harness\resources\runtime\cli\bin\dsh.cmd` |
| pnpm | `...\resources\runtime\primary-runtime\dependencies\pnpm\bin\pnpm.cjs` |
| Chrome（截图/验证） | `C:\Program Files\Google\Chrome\Application\chrome.exe` |
| 打包 | `npm pack --pack-destination ..\03-发布包` 然后重命名成 `dsh-boot-suite.tgz` |
| 发布 npm | 仓库根目录 `npm publish`（令牌带 bypass；若 EOTP 用桌面发布助手），发布后 `npm view dsh-boot-suite version` 核对 |
| 编辑器官网入口 | 设置 →「启动动画」→「打开模板编辑器」 |
| 生成桌面升级助手 | `node tools/make-upgrade-helper.mjs <版本>`（整段模板 + 写后读回校验） |
| 生成紧急回滚助手 | 由 `tools/install.ps1` 安装时自动生成（`tools/rollback-version.ps1` + 桌面 bat），无需手工 |

macOS（v2.16.11 起）对应命令：

| 用途 | 命令 |
|---|---|
| DSH CLI | `/Applications/DeepSeek Harness.app/Contents/Resources/runtime/cli/bin/dsh`（或 `/usr/local/bin/dsh`） |
| node 兜底（没有 node 命令时） | `ELECTRON_RUN_AS_NODE=1 "/Applications/DeepSeek Harness.app/Contents/MacOS/DeepSeek Harness" -e '...'` |
| 安装 / 卸载 / 诊断 / 预览 | 仓库根目录双击 `安装-mac.command` / `卸载-mac.command` / `诊断-mac.command` / `打开预览.command` |
| 只看安装计划 | `sh tools/install-macos.sh --check-only` |
| 打包（跨平台） | `node tools/build-release.mjs`（mac 用 zip/unzip；`DSH_RELEASE_OUT` 可指定输出目录） |
| 桌面端路径 | `/Applications/DeepSeek Harness.app`（bundle id `com.deepseek.dsh`） |
| 重新打开桌面端 | `open -b com.deepseek.dsh`（失败再 `open -a "DeepSeek Harness"`） |
| 进程检测 | `pgrep -f "DeepSeek Harness.app/Contents/"` |
| 用户数据 | `~/.dsh`（`DSH_HOME` 可覆盖） |

macOS 脚本对照（Windows 能力全部有对应）：

| 能力 | Windows | macOS |
|---|---|---|
| 安装/更新 | `tools/install.ps1` | `tools/install-macos.sh` |
| 卸载 | `tools/emergency-uninstall.ps1` | `tools/emergency-uninstall.sh` |
| 回滚 | `tools/rollback-version.ps1` | `tools/rollback-version.sh` |
| 自动更新执行器 | `tools/update-apply.ps1` | `tools/update-apply.sh`（宿主打开 Terminal 运行） |
| 诊断 | `tools/doctor.ps1` | `tools/doctor.sh` |
| 在线安装 | `install-online.ps1` | `install-online.sh` |
| 公共函数 | —（PS 内联） | `tools/lib/mac-common.sh` |
| JSON 读写 | ConvertTo-Json | `tools/lib/profile-json.mjs`（UTF-8 无 BOM，保留无关字段） |

## 六、验证套路（别靠"应该没问题"）

- **动画类**：`tools/motion-check.mjs`（headless Chrome，按真实时间跑，断言帧差异/文案变化/收尾）
- **UI 类**：`npx impeccable detect`（对比度/字号/阴影/装饰规则）
- **截图**：CDP 实时抓帧（不要用 virtual time，会把 CSS 动画冻住）；GIF 用 Pillow 合成，没有 ffmpeg
- **宿主路由**：`test/smoke-host.mjs` 里 stub 掉 `globalThis.fetch`，不碰真网络
- **mac 安装/更新脚本（沙箱验收，不碰真机数据）**：
  ```sh
  TMP=$(mktemp -d); mkdir -p "$TMP/.dsh/profiles/desktop" "$TMP/Desktop"
  printf '%s' '{"name":"dsh-profile-desktop","private":true,"dependencies":{},"dsh":{"profile":{"bundles":["@deepseek-ai/dsh-base"]}}}' > "$TMP/.dsh/profiles/desktop/package.json"
  HOME="$TMP" DSH_HOME="$TMP/.dsh" DSH_SKIP_PROCESS_CHECK=1 DSH_SKIP_REOPEN=1 sh tools/install-macos.sh   # 真装进假 HOME
  ```
  更新器同理：`DSH_UPDATE_WAIT_SECONDS=2` 缩短等待，`DSH_UPDATE_LOG_DIR="$TMP/Desktop"` 重定向日志；zip 用仓库现状打一个最小合法包。
- **mac OS 版本号一致性**：改 `package.json` version 时，必须同步 `lib/client.js` 的 `FALLBACK_VERSION`（smoke-merge 会断言两者一致）

## 七、踩过的坑（重复率很高）

| 坑 | 表现 | 修法 |
|---|---|---|
| 类名撞车 | 终端身份卡用了 `.dsu-card`，和档案版式里原有小卡冲突 | 加前缀 `dsu-term-card-` |
| 归一化白名单 | 模板自定义字段（`screen`）被 `normalizeSteps` 丢掉 | 在归一化里显式加字段 |
| 客户端提前 return | 宿主注入成功时 `selfBoot()` 直接返回，`injectRoot()` 里的逻辑全不执行 | 关键逻辑提到 `apply()` 级 |
| 标题栏透明化 | DSH preload 量 `body>span` 探针颜色再 IPC 重画 | 解析阶段就插样式（`BOOTSTRAP_JS`），不是客户端挂载时 |
| 双订阅 | `ctx.inject` 与 `ctx.on` 同时订阅 → 两个启动根 → 黑屏 | 互斥订阅 + `contributeRows` 幂等 |
| 早退不揭幕 | 单幕播放播完接终幕，看起来"闪到最后一屏" | 有 `count` 时播完停住 |
| 装完自动启动 DSH | `DeepSeek Harness is unavailable` / `desktop welcome: Web authentication failed`，连点多次也打不开 | 安装助手只安装、不启动；失败时先彻底退出所有 DSH 进程、备份 webstate，再手动打开一次，禁止循环重启 |
| 生成 .cmd 被拆行 | 用户双击后报 `'2.13.9' is not recognized`、`Processing -File ... failed`，更新器根本没启动 | 用 `tools/make-upgrade-helper.mjs` 模板生成；写后读回逐行校验，版本号不能单独成行、install.ps1 路径必须完整（2026-10-28 事故） |
| 路径 `/` 转 `\` | mac 上 /video 404、/videos/delete 报「outside root」（17 项冒烟红） | 宿主一律用 Node 原生路径，别按平台拼反斜杠（libuv 在 Windows 上也认 `/`） |
| `spawn('explorer.exe')` 无 error 监听 | mac 上点「打开目录」→ ENOENT unhandled error 直接打崩宿主进程 | 统一 `openInFileManager()`：win32 explorer / darwin open / 其他 xdg-open，且必须挂 `'error'` 监听 |
| `$VAR（中文` | macOS bash 3.2 把中文首字节吞进变量名 → 变量变空、输出乱码；回滚按钮名缺版本号 | 全部写 `${VAR}`；`test/smoke-macos.mjs` 有静态扫描防复发 |
| .command 双击没反应 | Finder 双击 .sh 不执行；下载来的脚本被 Gatekeeper 拦 | 入口用 `.command` 扩展名 + chmod 755 + 生成后读回校验；文档提示「右键 → 打开」 |

## 八、文档索引（压缩后按需读）

| 想知道 | 读 |
|---|---|
| 引擎现在能做什么 | `docs/引擎能力清单.md` |
| 模板 JSON 怎么写 | `docs/模板格式.md` |
| 时间线编辑器怎么做 | `docs/编辑器v2-时间线规格.md` |
| 动效参数（弹簧/错峰） | `docs/引擎v2-动效物理参数.md` |
| 设计审查记录 | `docs/设计走查-编辑器-2026-10-18.md`、`docs/设计审查-impeccable-2026-10-18.md` |
| 参考动画拆解 | `docs/参考分析-龙娘启动动画.md`、`docs/出图要求-描线动画.md` |
| 术语中英对照 | `docs/术语表.md` |
| 干音怎么录 | `docs/干音台词单-深海声呐.md` |
| macOS 怎么装 / 卸 / 回滚 / 诊断 | `INSTALL.md` 的「macOS」章节、`DESKTOP.md` 第六节、`tools/README.md` 的 macOS 表格 |

## 九、人机协作约定

- 需要在真实客户端里看效果的，一律给**明确的 human gate 清单**（看什么、期望什么、不对反馈什么）
- 用户是创作者不是程序员：能点就别让他打字；能预览就别让他重启
- 不确定就问，别猜着做；做错了直接认，别圆
- **子智能体（Agent Teams）：觉得需要就自由开，数量 < 10 个，不必每次请示**（用户 2026-10-25 授权：“当你觉得需要开子智能体的时候，请自由开启。数量小于10个即可。”）
