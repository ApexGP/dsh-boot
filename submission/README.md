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
