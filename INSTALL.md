# 安装

## 普通用户：Windows 一键安装（推荐）

1. 下载 **`dsh-boot-suite-win.zip`**（不是 `.tgz`，见下方 FAQ）
2. 右键 → **全部解压**（不要在压缩包里直接双击）
3. **完全退出** DeepSeek Harness Desktop（托盘图标也要退出）
4. 双击解压出来的 **`安装.cmd`**
5. 弹出 PowerShell 窗口 → 一路确认；安装完成后重新打开 DSH
6. 设置页应多出「启动动画」「聊天背景」两项

> 如果双击后一闪而过：右键 `安装.cmd` → 以管理员身份运行，或在 PowerShell 里执行
> `powershell -ExecutionPolicy Bypass -File .\tools\install.ps1`

## 下载了 `.tgz` 找不到安装.cmd？

`.tgz` 是给 `npm` / 命令行用户的压缩包，Windows 资源管理器**不能直接打开**，
有些解压软件还会把里面的中文文件名解成乱码（`��װ.cmd`）。

**请改下 `dsh-boot-suite-win.zip`**：解压后根目录第一个文件就是 `安装.cmd`。

## 开发者 / 命令行安装

## 桌面端（DeepSeek Harness Desktop）

    1) 完全退出桌面端（任务管理器里不要留进程）
    2) dsh plugin --profile desktop add link:<本仓库路径>\01-源码
    3) 重新打开桌面端

桌面端必须在**完全退出**的状态下装 —— profile 的 package.json 由桌面端进程加锁管理。

装之前若还装着旧的两个插件，先卸掉：

    dsh plugin --profile desktop remove dsh-startup-screen
    dsh plugin --profile desktop remove dsh-chat-wallpaper

## web profile

    dsh plugin --profile web add link:<本仓库路径>\01-源码

## 换装后要确认的三件事

1. 设置页多出**两项**：「启动动画」（顶部显示当前版本号）和「聊天背景」
2. 冷启动播六幕动画，播完进聊天；随后落在聊天底图上（大字横幅可选）
3. 左下角不再有浮层「🖼 背景」按钮（设置已并入设置页）

## 卸载

    dsh plugin --profile desktop remove dsh-boot-suite

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

---

## macOS（v2.16.11 起）

macOS 上插件本体一样，安装 / 卸载 / 回滚 / 诊断都换成了 POSIX sh 脚本，并带 `.command` 双击入口，
不需要 PowerShell，也不需要 Homebrew。

### 安装（三选一）

**方式 A：下载 Release 压缩包（推荐，不需要命令行）**

1. 下载 **`dsh-boot-suite-win.zip`**（文件名带 win，但它是**跨平台包**，macOS 用的就是这一份）
2. 双击解压（不要在压缩包里直接双击）
3. **完全退出** DeepSeek Harness（窗口 + 菜单栏图标都要退出）
4. 双击解压出来的 **`安装-mac.command`**
   - 若提示「无法打开，因为无法验证开发者」：右键 `安装-mac.command` → **打开**；或在终端 `chmod +x 安装-mac.command` 后再双击（Gatekeeper 对下载脚本的通用限制，不是插件问题）
5. 重新打开桌面端，设置页应多出「启动动画」「聊天背景」

**方式 B：终端一行命令（在线安装）**

```sh
curl -fsSL https://raw.githubusercontent.com/LeeRolling/dsh-boot-suite/main/install-online.sh | sh
```

下载的是同一个 Release 包；直连失败会自动回退到 GitHub 源码包。想先看它要做什么：

```sh
curl -fsSL https://raw.githubusercontent.com/LeeRolling/dsh-boot-suite/main/install-online.sh | sh -s -- --check-only
```

**方式 C：命令行（dsh 插件命令）**

```sh
# 桌面端：先完全退出 DeepSeek Harness
dsh plugin --profile desktop add link:<本仓库路径>
```

`dsh` 不在 PATH 里时，桌面端自带的是
`/Applications/DeepSeek Harness.app/Contents/Resources/runtime/cli/bin/dsh`。
web profile 把 `desktop` 换成 `web`。

只想看安装器要做什么、不动任何文件：

```sh
sh tools/install-macos.sh --check-only
```

### 卸载

先完全退出 DSH，再双击根目录的 **`卸载-mac.command`**，或者：

```sh
sh tools/emergency-uninstall.sh
```

卸载前会先把 profile 里的配置备份到 `~/.dsh/profiles/<profile>/_backup-uninstall-<时间戳>/`；不会删
`~/.dsh/dsh-startup.json`、`~/.dsh/chat-wallpaper.json`，也不会自动启动 DSH。

### 回滚（新版打不开时）

安装 / 更新前，安装器会在桌面生成
「**紧急回滚-V<旧版本>（先完全退出 DSH 再双击）.command**」。
新版装不上、或装完 DSH 打不开时：完全退出 DSH → 双击它。也可以手动：

```sh
sh tools/rollback-version.sh --target-pkg <旧版本目录> --profile desktop
```

只换插件版本，不动你的设置；每次回滚会在桌面写「dsh-boot-suite 回滚日志 <时间戳>.txt」。

### 诊断

完全退出 DSH 后双击根目录的 **`诊断-mac.command`**（或 `sh tools/doctor.sh`），
桌面会生成 **`dsh诊断-<时间戳>.txt`**：系统版本、DSH 路径与版本、CLI、node、DSH 进程、
各 profile 的 dependencies / bundles / node_modules、配置与模板列表、诊断日志末尾。

### 自动更新

设置页「立即更新」在 macOS 上同样可用：会打开一个 **Terminal** 窗口运行
`tools/update-apply.sh`，等你完全退出 DSH 后校验安装包、解压、跑安装器并自动重开 DSH。
**关掉那个 Terminal 窗口 = 中止更新**。失败会恢复旧版本目录和配置，日志写桌面
「dsh-boot-suite 更新日志 <时间戳>.txt」，真出问题时把它发给作者。
