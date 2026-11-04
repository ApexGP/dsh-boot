# dsh-boot-suite

[简体中文](README.md) | [English](README.en.md)

> **DeepSeek Harness 开机套件** —— 冷启动的开机动画，加上进入聊天后的那张壁纸。
> 一个插件，两个互不牵连的半侧：动画坏了不影响壁纸，壁纸坏了不影响动画，界面照常进。

[![platform](https://img.shields.io/badge/platform-Windows%20%7C%20macOS%20%7C%20Web-lightgrey)](#安装)
[![release](https://img.shields.io/github/v/release/LeeRolling/dsh-boot-suite?label=release)](https://github.com/LeeRolling/dsh-boot-suite/releases)
[![license](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

![开机动画主画面](docs/hero.png)

![启动过程演示](docs/demo.gif)

> GIF 是由 `preview/demo.html` 逐帧录制的 5 秒循环（无声）；真实播放带真声台词与界面音效。

---

## 特性

| | 开机动画 | 聊天壁纸 |
|---|---|---|
| 入口 | 设置 →「启动动画」 | 设置 →「聊天背景」 |
| 内容 | 分幕动画、逐字打出的英文副标题、环形准星、色散揭幕 | 内置默认背景（装好即有）、静态图、循环视频、大字横幅 |
| 可调 | 模板、转场、配音音色与音效、背景音乐、自定义视频/图片 | 底图、纱的浓度、镜头模糊、横幅文字、色彩模式 |

- **不是视频，是代码动画**：DOM + CSS + WebAudio 现场绘制，不依赖视频素材。
- **模板与编辑器**：分幕是纯数据（1~24 幕任意），可导入 mp4 / webm / gif / 图片；设置页「启动动画」→「打开模板编辑器」内含时间线编辑器与「🏪 商店」（模板源 [dsh-boot-suite-templates](https://github.com/LeeRolling/dsh-boot-suite-templates)），模板只当数据读、运行时绝不执行模板里的代码。
- **不露底、不黑屏**：首帧在文档解析阶段就画上，DSH 自带的「HARNESS / Loading plugins…」卡片被按掉；模板缺字段、id 非法一律回落内置。

## 安装

**先完全退出 DeepSeek Harness（窗口 + 菜单栏/托盘图标都要退），装完再打开。** Release 里的 `dsh-boot-suite-win.zip` 是跨平台包，Windows 与 macOS 共用（文件名沿用 win）。

### macOS

1. **双击安装（推荐）**：解压 `dsh-boot-suite-win.zip`，双击根目录的 `setup.command`，菜单里选「安装 / 更新」。第一次打不开就右键 → 打开（Gatekeeper 对下载脚本的通用限制）。
2. **一行在线安装**：

   ```sh
   curl -fsSL https://raw.githubusercontent.com/LeeRolling/dsh-boot-suite/main/install-online.sh | sh
   ```

3. **npm**：桌面端：设置 → 插件 → 添加插件，输入 `dsh-boot-suite`；普通 dsh web：`dsh plugin add dsh-boot-suite`。
4. **CLI**：`dsh plugin --profile desktop add link:<仓库路径>`。`dsh` 不在 PATH 里时，桌面端自带在 `/Applications/DeepSeek Harness.app/Contents/Resources/runtime/cli/bin/dsh`。

### Windows

1. **双击安装（推荐）**：解压 `dsh-boot-suite-win.zip`，双击根目录的 `setup.cmd`，菜单里选「安装 / 更新」。
2. **一行在线安装**（PowerShell）：

   ```powershell
   irm https://raw.githubusercontent.com/LeeRolling/dsh-boot-suite/main/install-online.ps1 | iex
   ```

3. **npm**：桌面端：设置 → 插件 → 添加插件，输入 `dsh-boot-suite`；普通 dsh web：`dsh plugin add dsh-boot-suite`。
4. **CLI**：`dsh plugin --profile desktop add link:<仓库路径>`。

> npm 版本可能落后于最新 Release；要用最新功能（含 macOS 支持）请走 Release 包或在线安装。

## 维护入口

| 入口 | 说明 |
|---|---|
| `setup.command` / `setup.cmd` | 双击打开菜单：安装 / 更新、卸载、诊断、预览 |
| 设置页 | 「启动动画」「聊天背景」两个面板，改配置不用手改文件 |
| 桌面回滚按钮 | 每次安装/更新前自动生成「紧急回滚-V<旧版本>（先完全退出 DSH 再双击）」；新版打不开时双击切回，只换插件版本、不动设置 |
| 诊断报告 | 菜单里选「诊断」，桌面生成 `dsh诊断-<时间戳>.txt` |
| 配置文件 | `~/.dsh/dsh-startup.json`、`~/.dsh/chat-wallpaper.json` |
| 用户模板 | `~/.dsh/startup-templates/<id>/template.json`，同 id 覆盖插件自带模板 |

只想看安装计划、不动任何文件：macOS `sh tools/macos/install.sh --check-only`，Windows `powershell -NoProfile -ExecutionPolicy Bypass -File tools\windows\install.ps1 -CheckOnly`。

## 出事了怎么救 🧯

插件注入的是**首屏**，坏起来可能整块黑屏、连「跳过」都点不到。救人顺序：

1. 完全退出 DeepSeek Harness（窗口 + 菜单栏/托盘，确认没有残留进程）；
2. 双击仓库根目录的 `setup.command`（macOS）或 `setup.cmd`（Windows）；
3. 菜单里选「卸载」，界面恢复后重开 DSH。

只想回滚、不想卸载：退出 DSH 后双击桌面的「紧急回滚-V<旧版本>」按钮（Windows 为 `.cmd`，macOS 为 `.command`）。诊断报告在桌面 `dsh诊断-<时间戳>.txt`，运行日志在 `~/.dsh/boot-suite-diag.log`。
底层脚本也能单独跑：macOS `tools/macos/uninstall.sh` / `tools/macos/diagnose.sh` / `tools/macos/rollback-version.sh`；Windows `tools/windows/uninstall.ps1` / `tools/windows/diagnose.ps1` / `tools/windows/rollback-version.ps1`。

## 开发与测试

```sh
npm test    # 14 套零依赖冒烟（含 macOS 专项），约 1000 项断言
```

- 环境：Node ≥ 20。
- 发布打包：`node tools/dev/build-release.mjs`（跨平台 zip，`DSH_RELEASE_OUT` 指定输出目录）
- 动效回归：`node tools/dev/motion-check.mjs`；录屏用的逐帧导出：`node tools/dev/export-frames.mjs`
- 目录：`lib/`（宿主半 + 浏览器半）、`templates/`（内置模板）、`preview/`（离线预览页）、`test/`（冒烟）、`tools/`（`tools/windows/`、`tools/macos/` 维护脚本，`tools/dev/` 开发工具）
- 文档：[模板格式](docs/模板格式.md) · [引擎能力清单](docs/引擎能力清单.md) · [安装与排错](INSTALL.md) · [更新日志](CHANGELOG.md)

## 许可与致谢

MIT（只覆盖作者原创代码与文案）。视觉风格参考自动画作品；音频素材权利归原权利人，**未授权任何商业用途**。

原作者：**沈宏宏**；合并、修复与维护：LeeRolling。参考作品与第三方素材清单见 [CREDITS.md](CREDITS.md)。
