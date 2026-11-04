# 安装

> 先**完全退出** DeepSeek Harness（窗口 + 菜单栏/托盘图标都要退），装完再手动打开。
> Release 里的 `dsh-boot-suite-win.zip` 是跨平台包，Windows 与 macOS 共用（文件名沿用 win）。

## Windows

### 方式 A：双击安装（推荐，不需要命令行）

1. 下载 **`dsh-boot-suite-win.zip`**（不是 `.tgz`，见下方 FAQ）
2. 右键 → **全部解压**（不要在压缩包里直接双击）
3. **完全退出** DeepSeek Harness Desktop（托盘图标也要退出）
4. 双击解压出来的 **`setup.cmd`**
5. 在中文菜单里选 **「1. 安装 / 更新」**；装完重新打开 DSH
6. 设置页应多出「启动动画」「聊天背景」两项

> 如果双击一闪而过：右键 `setup.cmd` → **以管理员身份运行**；或在 PowerShell 里执行
> `powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\windows\install.ps1`

### 方式 B：一行在线安装（PowerShell）

```powershell
irm https://raw.githubusercontent.com/LeeRolling/dsh-boot-suite/main/install-online.ps1 | iex
```

只看它要做什么、不动任何文件（本地已下载时）：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install-online.ps1 -CheckOnly
```

### 方式 C：npm

桌面端：设置 → 插件 → 添加插件，输入 `dsh-boot-suite`；普通 dsh web 用 `dsh plugin add dsh-boot-suite`。

> npm 版本可能落后于最新 Release；要用最新功能（含 macOS 支持）请走 Release 包或在线安装。

### 方式 D：CLI（开发者 / 本仓库）

先完全退出桌面端，再：

```powershell
dsh plugin --profile desktop add link:<本仓库路径>
dsh plugin --profile web add link:<本仓库路径>
```

桌面端 profile 的 `package.json` 由桌面端进程加锁管理，必须在**完全退出**状态下装。
装之前若还装着旧的两个插件，先卸掉：

```powershell
dsh plugin --profile desktop remove dsh-startup-screen
dsh plugin --profile desktop remove dsh-chat-wallpaper
```

### 只看安装计划 / 不动文件

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\windows\install.ps1 -CheckOnly
```

## macOS（v2.16.11 起）

macOS 不需要 PowerShell、也不需要 Homebrew：安装 / 卸载 / 回滚 / 诊断全是仓库自带的 POSIX sh，
双击入口是 `setup.command`（Finder 双击会在 Terminal 里打开中文菜单）。

### 方式 A：双击安装（推荐，不需要命令行）

1. 下载 **`dsh-boot-suite-win.zip`**（文件名带 win，但它是**跨平台包**，macOS 用的就是这一份）
2. 双击解压（不要在压缩包里直接双击）
3. **完全退出** DeepSeek Harness（窗口 + 菜单栏图标都要退出）
4. 双击解压出来的 **`setup.command`**，菜单里选 **「1. 安装 / 更新」**
   - 若提示「无法打开，因为无法验证开发者」：右键 `setup.command` → **打开**；或在终端
     `chmod +x setup.command` 后再双击（Gatekeeper 对下载脚本的通用限制，不是插件问题）
5. 重新打开桌面端，设置页应多出「启动动画」「聊天背景」

### 方式 B：一行在线安装

```sh
curl -fsSL https://raw.githubusercontent.com/LeeRolling/dsh-boot-suite/main/install-online.sh | sh
```

下载的是同一个 Release 包；直连失败会自动回退到 GitHub 源码包。想先看它要做什么：

```sh
curl -fsSL https://raw.githubusercontent.com/LeeRolling/dsh-boot-suite/main/install-online.sh | sh -s -- --check-only
```

### 方式 C：CLI（开发者 / 本仓库）

```sh
# 桌面端：先完全退出 DeepSeek Harness
dsh plugin --profile desktop add link:<本仓库路径>
```

`dsh` 不在 PATH 里时，桌面端自带的是
`/Applications/DeepSeek Harness.app/Contents/Resources/runtime/cli/bin/dsh`。
web profile 把 `desktop` 换成 `web`。

### 只看安装计划 / 不动文件

```sh
sh tools/macos/install.sh --check-only
```

### 卸载

先完全退出 DSH，双击仓库根目录的 **`setup.command`** → 菜单选 **「2. 卸载」**；或者：

```sh
sh tools/macos/uninstall.sh
```

卸载前会先把 profile 里的配置备份到 `~/.dsh/profiles/<profile>/_backup-uninstall-<时间戳>/`；不会删
`~/.dsh/dsh-startup.json`、`~/.dsh/chat-wallpaper.json`，也不会自动启动 DSH。

### 回滚（新版打不开时）

安装 / 更新前，安装器会在桌面生成
「**紧急回滚-V<旧版本>（先完全退出 DSH 再双击）.command**」。
新版装不上、或装完 DSH 打不开时：完全退出 DSH → 双击它。也可以手动：

```sh
sh tools/macos/rollback-version.sh --target-pkg <旧版本目录> --profile desktop
```

只换插件版本，不动你的设置；每次回滚会在桌面写「dsh-boot-suite 回滚日志 <时间戳>.txt」。

### 诊断

完全退出 DSH 后双击根目录的 **`setup.command`** → 菜单选 **「3. 诊断」**（或 `sh tools/macos/diagnose.sh`），
桌面会生成 **`dsh诊断-<时间戳>.txt`**：系统版本、DSH 路径与版本、CLI、node、DSH 进程、
各 profile 的 dependencies / bundles / node_modules、配置与模板列表、诊断日志末尾。

### 自动更新

设置页「立即更新」在 macOS 上同样可用：会打开一个 **Terminal** 窗口运行
`tools/macos/update-apply.sh`，等你完全退出 DSH 后校验安装包、解压、跑安装器并自动重开 DSH。
**关掉那个 Terminal 窗口 = 中止更新**。失败会恢复旧版本目录和配置，日志写桌面
「dsh-boot-suite 更新日志 <时间戳>.txt」，真出问题时把它发给作者。

## 下载了 `.tgz` 找不到 setup.cmd？

`.tgz` 是给 `npm` / 命令行用户的压缩包，Windows 资源管理器**不能直接打开**，
有些解压软件还会把里面的中文文件名解成乱码。

**请改下 `dsh-boot-suite-win.zip`**：解压后根目录第一个脚本就是 `setup.cmd`（macOS 是 `setup.command`）。

## 换装后要确认的三件事

1. 设置页多出**两项**：「启动动画」（顶部显示当前版本号）和「聊天背景」
2. 冷启动能播动画，播完进聊天；随后落在聊天底图上
3. 左下角不再有浮层「🖼 背景」按钮（设置已并入设置页）

## 卸载（Windows）

双击 `setup.cmd` → 菜单选 **「2. 卸载」**；或者：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\windows\uninstall.ps1
```

配置文件不会自动删除，要清干净手动删：

    ~/.dsh/dsh-startup.json
    ~/.dsh/chat-wallpaper.json

## 排错：安装时提示「找不到 DeepSeek Harness 的命令行（dsh）」

这不是你没装桌面端，而是你的桌面端**没有携带命令行工具**（精简安装 / 便携版 / 商店版常见）。

### v2.7.1 起

安装脚本会自动：

1. 依次查 PATH → `%LOCALAPPDATA%\Programs` → 注册表卸载项 → 运行中进程 → 常见目录递归
2. 仍找不到时改为**手动安装**（直接写 profile 配置 + 建 `node_modules` 目录联接），不需要 CLI

### 旧版（≤ v2.7.0）临时办法

1. 右键桌面快捷方式 → 打开文件所在位置
2. 看是否存在 `resources\runtime\cli\bin\dsh.cmd`
3. 有 → 把该目录加进 PATH 后重跑安装脚本
4. 没有 → 升级到 v2.7.1，或手动安装：
   - 编辑 `%USERPROFILE%\.dsh\profiles\desktop\package.json`，在 `dependencies` 里加 `"dsh-boot-suite": "link:你的插件绝对路径"`
   - 在 `dsh.profile.bundles` 里加 `dsh-boot-suite`
   - 用管理员 CMD 执行 `mklink /J "%USERPROFILE%\.dsh\profiles\desktop\node_modules\dsh-boot-suite" "你的插件绝对路径"`
