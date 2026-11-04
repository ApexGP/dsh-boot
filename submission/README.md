# 市场提交材料

给 DSH 插件市场用的两条数据，格式照 `yannicksong0106/dsh-550c-boot` 的 `submission/` 目录：

- `data/plugins/ApexGP__dsh-boot.yml` —— 登记条目（含 tarball 直链；市场格式是 `<owner>__<repo>.yml`）
- `data/community/dsh-boot-suite.json` —— 社区展示条目

tarball 约定：release 里挂一个固定名字的资源

    https://github.com/ApexGP/dsh-boot/releases/latest/download/dsh-boot-suite.tgz

发布新版本时：改 `package.json` 版本 → `npm pack` → 把产物重命名为 `dsh-boot-suite.tgz` → 挂到对应 release。

自动发版（2026-11-05 起）：给仓库推 tag（`git tag v<版本> && git push origin v<版本>`）后，
GitHub Actions（`.github/workflows/release.yml`）自动跑测试并产出四件资产并创建 Release：
固定名 `dsh-boot-suite-win.zip`、版本化 zip `dsh-boot-suite-win-V<版本>.zip`、
`dsh-boot-suite.tgz`、`SHA256SUMS.txt`。所以市场里的 `latest/download` 链接**不用每次手改**，
发版即生效；本地不再手工上传资产，补发用 `workflow_dispatch`。

## DSH-Store 预检现状（issue #1760，2026-11-05）

自动预检报 `SUBMISSION_SCAN_INCOMPLETE`。已用 DSH-Store 仓库同版本扫描模块在本地复现（不需要猜），v2.16.12 剩余三项：

1. `package contains unsupported artifacts requiring review` —— 必需音视频素材（mp3/wav/mp4，约 133 个）不在扫描器静态放行类型（只放行图片/字体/文本/样式）；这些是启动动画配音、循环视频与内置模板的核心内容。
2. `dynamic module loading or code evaluation requires separate review` —— `lib/client.js` 自举 `loadScript()` 与 `lib/splash.js` 的 `injectSelf()` 用 `document.createElement('script')` 挂固定 Host 路由的 splash.js（首帧兜底 / 预览重播）。
3. 2 条 `warning/shell/child-process` —— 仅用于「打开目录」与「自动更新器」，参数为固定数组。

已做整改：`package.json files` 只保留运行时（扫描面 96→70 个源码文件、告警 9→2）、Windows 更新器去掉 `shell: true`、版本升到 2.16.12。
按 `registry/README.md` 的 bounded-source 政策，扫描预算/覆盖/文件类型限制的责任方是 `store-scanner`，且「不要求作者拆包、压缩或删除功能」→ 走**人工准入复核**，不要删音频/视频或自举功能去过检。

重新触发预检：push 新 commit 后编辑 Issue #1760（任何编辑都会重跑）。回复模板见 `issue-reply-1760.md`。
