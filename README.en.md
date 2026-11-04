# dsh-boot-suite

[简体中文](README.md) | [English](README.en.md)

> **A boot suite for DeepSeek Harness** — a cold-start animation, plus the wallpaper you live on once the chat opens.
> One plugin, two independent halves: a broken animation never breaks the wallpaper, and vice versa — the UI always comes up.

[![platform](https://img.shields.io/badge/platform-Windows%20%7C%20macOS%20%7C%20Web-lightgrey)](#install)
[![release](https://img.shields.io/github/v/release/ApexGP/dsh-boot?label=release)](https://github.com/ApexGP/dsh-boot/releases)
[![license](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

![boot animation](docs/hero.png)

![demo](docs/demo.gif)

> The GIF is a silent 5-second loop recorded from `preview/demo.html`; the real thing plays voice lines and UI sound effects.

---

## Features

| | Boot animation | Chat wallpaper |
|---|---|---|
| Entry | Settings → "启动动画" | Settings → "聊天背景" |
| Content | act-by-act animation, typewriter subtitles, targeting ring, glitch reveal | built-in default background (ready out of the box), static image, loop video, big text banner |
| Tunable | templates, transitions, voice lines and effects, background music, custom video/image | background, veil opacity, lens blur, banner text, color mode |

- **Not a video — a code animation**: painted live with DOM + CSS + WebAudio; no video assets required.
- **Templates & editor**: acts are pure data (any number from 1 to 24); import mp4 / webm / gif / images; Settings → "启动动画" → "打开模板编辑器" opens the timeline editor and the "🏪 商店" template store (source: [dsh-boot-suite-templates](https://github.com/LeeRolling/dsh-boot-suite-templates)). Templates are read as data only — their code is never executed.
- **No blank frame, no black screen**: the first frame is painted during document parsing, so DSH's own "HARNESS / Loading plugins…" card is suppressed; missing fields or invalid ids always fall back to the bundled template.

## Install

**Fully quit DeepSeek Harness first (window + menu-bar/tray icon), then install and reopen it.** The release `dsh-boot-suite-win.zip` is the cross-platform package shared by Windows and macOS (the `win` in the file name is kept for history).

### macOS

1. **Double-click (recommended)**: unzip `dsh-boot-suite-win.zip`, double-click `setup.command` in the repo root and choose "安装 / 更新" (install / update). If Gatekeeper blocks it: right-click → Open.
2. **One-line online install**:

   ```sh
   curl -fsSL https://raw.githubusercontent.com/ApexGP/dsh-boot/main/install-online.sh | sh
   ```

3. **npm**: desktop — Settings → Plugins → Add plugin, enter `dsh-boot-suite`; plain dsh web — `dsh plugin add dsh-boot-suite`.
4. **CLI**: `dsh plugin --profile desktop add link:<repo path>`. If `dsh` is not on PATH, the bundled one is at `/Applications/DeepSeek Harness.app/Contents/Resources/runtime/cli/bin/dsh`.

### Windows

1. **Double-click (recommended)**: unzip `dsh-boot-suite-win.zip`, double-click `setup.cmd` in the repo root and choose "安装 / 更新" (install / update).
2. **One-line online install** (PowerShell):

   ```powershell
   irm https://raw.githubusercontent.com/ApexGP/dsh-boot/main/install-online.ps1 | iex
   ```

3. **npm**: desktop — Settings → Plugins → Add plugin, enter `dsh-boot-suite`; plain dsh web — `dsh plugin add dsh-boot-suite`.
4. **CLI**: `dsh plugin --profile desktop add link:<repo path>`.

> The npm package may lag behind the latest release; for the newest features (including macOS support) use the release zip or the online installer.

## Maintenance

| Entry | What it does |
|---|---|
| `setup.command` / `setup.cmd` | Double-click menu: install / update, uninstall, diagnose, preview |
| Settings | "启动动画" and "聊天背景" panels — no manual file editing needed |
| Desktop rollback button | Before every install/update, an "紧急回滚-V<old version>（先完全退出 DSH 再双击）" button is created; if the new version fails to open, fully quit DSH and double-click it. Plugin version only — your settings stay untouched. |
| Diagnostic report | Menu → "Diagnose" writes `dsh诊断-<timestamp>.txt` to the desktop |
| Config files | `~/.dsh/dsh-startup.json`, `~/.dsh/chat-wallpaper.json` |
| User templates | `~/.dsh/startup-templates/<id>/template.json`; the same id overrides the bundled template |

To preview the install plan without touching anything: macOS `sh tools/macos/install.sh --check-only`; Windows `powershell -NoProfile -ExecutionPolicy Bypass -File tools\windows\install.ps1 -CheckOnly`.

## Rescue

The plugin injects into the **first paint**, so a bug can mean a full black screen where even "skip" is unreachable. Recovery order:

1. Fully quit DeepSeek Harness (window + menu-bar/tray; make sure no process is left).
2. Double-click `setup.command` (macOS) or `setup.cmd` (Windows) in the repo root.
3. Choose "Uninstall"; once the UI is back, relaunch DSH.

To roll back instead of uninstalling: quit DSH, then double-click the desktop "紧急回滚-V<old version>" button (a `.cmd` on Windows, a `.command` on macOS). Reports land on the desktop as `dsh诊断-<timestamp>.txt`; runtime logs are at `~/.dsh/boot-suite-diag.log`.
The scripts also run standalone: macOS `tools/macos/uninstall.sh` / `tools/macos/diagnose.sh` / `tools/macos/rollback-version.sh`; Windows `tools/windows/uninstall.ps1` / `tools/windows/diagnose.ps1` / `tools/windows/rollback-version.ps1`.

## Development & testing

```sh
npm test    # 14 dependency-free smoke suites (incl. a macOS one), ~1000 assertions
```

- Requirements: Node ≥ 20.
- Release build: `node tools/dev/build-release.mjs` (cross-platform zip; set `DSH_RELEASE_OUT` for the output dir)
- Release: push `tag v<version>` (e.g. `git tag v2.16.11 && git push origin v2.16.11`) — GitHub Actions (`.github/workflows/release.yml`) runs the tests, builds four assets (`dsh-boot-suite-win.zip` / `dsh-boot-suite-win-V<version>.zip` / `dsh-boot-suite.tgz` / `SHA256SUMS.txt`) and creates the Release; npm publish is off by default (needs repo variable `PUBLISH_NPM=true` + secret `NPM_TOKEN`). The workflow fails if the tag does not match `package.json`'s version.
- Motion regression: `node tools/dev/motion-check.mjs`; frame export for recordings: `node tools/dev/export-frames.mjs`
- Layout: `lib/` (host + browser halves), `templates/` (bundled templates), `preview/` (offline preview), `test/` (smoke suites), `tools/` (`tools/windows/` and `tools/macos/` maintenance scripts, `tools/dev/` developer tools)
- Docs: [template format](docs/模板格式.md) · [engine capabilities](docs/引擎能力清单.md) · [install & troubleshooting](INSTALL.md) · [changelog](CHANGELOG.md)

## License & credits

MIT for the original code and copy. Visual style references an anime; audio assets remain with their rights holders. **No commercial use is granted.**

Original author: **沈宏宏**; merged, fixed and maintained by LeeRolling. Reference works and third-party assets: [CREDITS.md](CREDITS.md).

This repository is a community-maintained fork ([ApexGP/dsh-boot](https://github.com/ApexGP/dsh-boot)); the upstream is the original author LeeRolling's dsh-boot-suite repository. Original authorship and asset credits are unchanged.
