<!-- 用法：把下面整段贴到 #1760 的评论里；把 <COMMIT_SHA> 换成你 push 后 git rev-parse HEAD 的 40 位哈希。
     顺带在 Issue 正文里任意编辑一处（比如加一行「已更新到 v2.16.17」）也会触发预检重跑。 -->

## 已按政策完成可整改项，请求人工准入复核（v2.16.17 / `<COMMIT_SHA>`）

感谢自动预检。作者侧能改的已全部改完：

1. **收紧 npm/市场包的文件面**（`package.json` 的 `files` 只保留运行时）：
   - 移出：`test/`、`tools/dev/`、`install-online.*`、`setup.*`、`preview/index.html`；
   - 保留：`lib/`、`templates/`、`tools/macos/`、`tools/windows/`、`tools/editor.html`、`cordis.patch.yml`、文档与 LICENSE。
   - 用 DSH-Store 仓库同版本的 `src/` 扫描模块本地复现：bounded 运行时源码 **96 → 70** 个文件，安全告警 **9 → 2**；无超限文件、无预算超限、无生命周期脚本、无运行依赖。
2. **移除 Windows 更新器的 `shell: true`**（改为 `cmd.exe /c` 固定参数），`shell-mode` 告警消失。
3. 版本升至 **v2.16.17**，包含上架整改、默认配置调整、自动播放节奏调整与兼容垫片清理；构建/测试 `npm test` 全绿。

自动预检仍为 `SUBMISSION_SCAN_INCOMPLETE`，剩余原因全部属于 bounded-source 扫描器的能力边界，不是可删除的功能：

- **unsupported artifacts（约 133 个 mp3/wav/mp4）**：启动动画配音、循环视频、内置模板素材。`package-source-surface.mjs` 的静态放行类型只含图片/字体/文本/样式；这些是插件的核心内容，删掉等于删掉主要功能。
- **dynamic module loading / code evaluation**：来自浏览器半侧自举与预览重播——`lib/client.js` 的 `loadScript()`（Host 未注入首帧时自举 splash.js）和 `lib/splash.js` 的 `injectSelf()`（设置页「立即预览」重播），均用 `document.createElement('script')` 挂固定 Host 路由 `/dsh-startup/splash.js` 或明示的预览入口，不执行第三方内容；改成 fetch+eval 只会更糟。
- **2 条 child-process 告警**（`lib/host-startup.js:17`、`lib/host-wallpaper.js:15`）：只用于 ① 设置页「打开下载文件夹/打开图片目录」（系统 `open`/`explorer`/`xdg-open`，固定数组参数）与 ② 自动更新器（等 DSH 退出后运行包内 `tools/*/update-apply.*`，安装包另经 zip 完整性与版本校验）。代码没有任何用户可控的 shell 字符串。

按 `registry/README.md` 的 bounded-source 政策：扫描预算/覆盖限制与文件类型限制的责任方是 `store-scanner`，并且明确「不要求作者拆包、压缩或删除功能」；其余情形应走人工准入复核。因此请求：

1. 按上述固定 Commit 做**人工准入复核**（可结合 build-dsh-plugin 只读预检结果）；
2. 明确本插件的音视频素材（数据文件、非可执行）与上述 child-process 边界，能否按「已披露能力」接受；
3. 若仍需补充证据，请指出具体材料（例如素材清单哈希、更新器参数边界说明、一次性 Profile 安装/运行记录），我们按清单补。

插件 README / DESKTOP.md 已披露：安装/更新会写 profile、自动更新会启动外部进程、音视频素材随包分发；不替换任何 `@deepseek-ai/*` 官方组件，所有自定义路由都过 `connection.requestRejection` 信任栅栏。
