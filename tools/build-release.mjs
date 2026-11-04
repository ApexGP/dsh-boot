import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync, execSync } from 'node:child_process';

const root = process.cwd();
const stage = fs.mkdtempSync(path.join(os.tmpdir(), 'dsh-release-'));
/* 输出目录：默认仍是仓库上一级的「03-发布包」（Windows 发版机保持原有行为）；
   macOS 上没有固定盘符约定，支持用 DSH_RELEASE_OUT 指到任意目录。
   先建目录，否则 zip / npm pack 会因目录不存在直接失败。 */
const outDir = process.env.DSH_RELEASE_OUT
  ? path.resolve(process.env.DSH_RELEASE_OUT)
  : path.join(root, '..', '03-发布包');
fs.mkdirSync(outDir, { recursive: true });
const out = path.join(outDir, 'dsh-boot-suite-win.zip');
/* code-motion：另一条工作线（动效研究/验证）的文档与媒体，不属于插件本体，发布包不打包 */
/* docs：主线（编辑器重制/风格库/演示素材）文档与媒体，体积可能非常大（GB 级），不属于插件运行必需，发布包不打包 */
const skip = new Set(['.git', 'node_modules', '08-备份', 'code-motion', 'docs', '02-文档', '03-发布包']);
function copy(src, dst) {
  fs.mkdirSync(dst, { recursive: true });
  for (const e of fs.readdirSync(src, { withFileTypes: true })) {
    if (skip.has(e.name)) continue;
    if (e.name.endsWith('.zip') || e.name.endsWith('.tgz')) continue;
    const s = path.join(src, e.name);
    const d = path.join(dst, e.name);
    if (e.isDirectory()) copy(s, d); else fs.copyFileSync(s, d);
  }
}
function validatePackageJson(file, label) {
  const buf = fs.readFileSync(file);
  if (buf.length >= 3 && buf[0] === 0xEF && buf[1] === 0xBB && buf[2] === 0xBF) {
    throw new Error(label + ' 的 package.json 带 UTF-8 BOM，DSH 会拒绝加载');
  }
  const pkg = JSON.parse(buf.toString('utf8'));
  if (!pkg.version) throw new Error(label + ' 的 package.json 缺少 version');
  return pkg;
}
const REQUIRED_FILES = [
  'lib/index.js', 'lib/splash.js', 'lib/client.js', 'lib/assets/default-background.jpg', 'templates',
  '安装.cmd', 'tools/install.ps1', 'tools/update-apply.ps1',
  /* v2.16.11：同一个 zip 同时服务 Windows 与 macOS（文件名仍叫 dsh-boot-suite-win.zip），
     mac 侧的安装器、更新器、公共库和双击入口必须一起打进去，否则 mac 用户解压后无从下手。 */
  'tools/install-macos.sh', 'tools/update-apply.sh', 'tools/lib/mac-common.sh',
  'tools/lib/profile-json.mjs', '安装-mac.command', 'install-online.sh',
];

/* macOS 自带的 Info-ZIP 3.0 会把中文名按 UTF-8 字节写进 zip，却不设「语言编码」标志位
   （general purpose bit 11）。Windows 资源管理器 / Expand-Archive 只认标志位，解压后
   中文名会变乱码（安装.cmd、安装-mac.command 变成乱码就双击不到了）。打完包后统一补标志位：
   中央目录头偏移 8、本地文件头偏移 6，两处都要改。Windows 分支不经过这里，行为不变。 */
function markZipUtf8(file) {
  const buf = fs.readFileSync(file);
  let eocd = -1;
  for (let i = buf.length - 22; i >= Math.max(0, buf.length - 22 - 0xffff); i--) {
    if (buf.readUInt32LE(i) === 0x06054b50) { eocd = i; break; }
  }
  if (eocd < 0) throw new Error('zip 结构异常：找不到中央目录结尾记录（EOCD）');
  const count = buf.readUInt16LE(eocd + 10);
  let p = buf.readUInt32LE(eocd + 16);
  if (count === 0xffff || p === 0xffffffff) throw new Error('zip 触发了 zip64，暂不支持自动补 UTF-8 标志位');
  for (let i = 0; i < count; i++) {
    if (buf.readUInt32LE(p) !== 0x02014b50) throw new Error('zip 结构异常：中央目录项偏移不对');
    buf.writeUInt16LE(buf.readUInt16LE(p + 8) | 0x0800, p + 8);
    const local = buf.readUInt32LE(p + 42);
    if (buf.readUInt32LE(local) !== 0x04034b50) throw new Error('zip 结构异常：本地文件头偏移不对');
    buf.writeUInt16LE(buf.readUInt16LE(local + 6) | 0x0800, local + 6);
    const nlen = buf.readUInt16LE(p + 28), elen = buf.readUInt16LE(p + 30), clen = buf.readUInt16LE(p + 32);
    p += 46 + nlen + elen + clen;
  }
  fs.writeFileSync(file, buf);
}

function makeZip() {
  if (process.platform === 'win32') {
    /* Windows 保持原样：PowerShell Compress-Archive 打包 */
    execFileSync('powershell.exe', ['-NoProfile', '-Command', "Compress-Archive -Path '" + stage + "\\*' -DestinationPath '" + out + "' -CompressionLevel Optimal"], { stdio: 'inherit' });
    return;
  }
  /* macOS / POSIX：系统 zip，在 stage 目录里用相对路径打包（解压出来不会多套一层目录）；
     不加 -X，保留 Unix 权限位，否则解压后的 .command / .sh 没有执行权限、双击没反应。 */
  execFileSync('zip', ['-r', '-q', out, '.'], {
    cwd: stage,
    stdio: 'inherit',
    /* 显式给 UTF-8 locale：纯 C locale 的终端里 Info-ZIP 可能按本地字符集处理中文名 */
    env: { ...process.env, LANG: 'en_US.UTF-8', LC_ALL: 'en_US.UTF-8' },
  });
  markZipUtf8(out);
}

function verifyZip(verifyDir) {
  if (process.platform === 'win32') {
    execFileSync('powershell.exe', ['-NoProfile', '-Command', "Expand-Archive -Path '" + out + "' -DestinationPath '" + verifyDir + "' -Force"], { stdio: 'inherit' });
    return;
  }
  /* 系统 unzip：-t 验 CRC、-l 打印人眼可读清单、-Z1 取纯文件名做机器断言，最后真解压一份 */
  execFileSync('unzip', ['-t', '-q', out], { stdio: 'inherit' });
  execFileSync('unzip', ['-l', out], { stdio: 'inherit' });
  const names = execFileSync('unzip', ['-Z1', out], { encoding: 'utf8' }).split(/\r?\n/).filter(Boolean);
  if (names.length < 50) throw new Error('zip 内容异常（只有 ' + names.length + ' 个文件）');
  /* macOS 自带的 unzip 在列目录时会把 UTF-8 中文名显示成 ?（解压本身是正确的），
     所以这里只对 ASCII 名做字符串断言；中文文件（安装.cmd / 安装-mac.command）
     交给下面「解压后按真实文件系统再查一遍」的通用逻辑。 */
  const missing = REQUIRED_FILES.filter((f) => /^[\x00-\x7F]+$/.test(f))
    .filter((f) => !names.includes(f) && !names.some((n) => n.startsWith(f + '/')));
  if (missing.length) throw new Error('zip 内缺少必需文件：' + missing.join('、'));
  execFileSync('unzip', ['-q', '-o', out, '-d', verifyDir], { stdio: 'inherit' });
}

function humanSize(n) {
  return (n / 1024 / 1024).toFixed(1) + ' MB';
}

copy(root, stage);
const pkg = validatePackageJson(path.join(stage, 'package.json'), '源目录');
for (const f of REQUIRED_FILES) {
  if (!fs.existsSync(path.join(stage, f))) throw new Error('发布包缺少 ' + f);
}
if (fs.existsSync(out)) fs.renameSync(out, out.replace(/\.zip$/, '') + '-bak-' + Date.now() + '.zip');
makeZip();
const verify = fs.mkdtempSync(path.join(os.tmpdir(), 'dsh-verify-'));
verifyZip(verify);
const vpkg = validatePackageJson(path.join(verify, 'package.json'), 'zip 内');
if (vpkg.version !== pkg.version) throw new Error('zip 内版本 ' + vpkg.version + ' 与源目录 ' + pkg.version + ' 不一致');
/* 解压出来再逐个查一遍（含中文文件名），能抓到打包/解压链路把文件名弄坏的情况。
   Windows 分支保持历史行为：只校验 package.json 版本 —— Expand-Archive 解压非 ASCII
   文件名时的编码随系统区域设置而变，额外断言可能把一直可用的 Windows 发版流程卡死。 */
if (process.platform !== 'win32') {
  for (const f of REQUIRED_FILES) {
    if (!fs.existsSync(path.join(verify, f))) throw new Error('zip 解压后缺少 ' + f);
  }
}
fs.rmSync(stage, { recursive: true, force: true });
fs.rmSync(verify, { recursive: true, force: true });

/* 硬性规定（2026-10-28）：每次发版必须带 dsh-boot-suite.tgz ——
   插件市场的安装链接固定指向 latest/download/dsh-boot-suite.tgz，
   少了它市场里的“安装”按钮就会指向旧版。所以打包脚本自己产，不靠手打。 */
const tgz = path.join(outDir, 'dsh-boot-suite.tgz');
if (fs.existsSync(tgz)) fs.renameSync(tgz, tgz.replace(/\.tgz$/, '-bak-' + Date.now() + '.tgz'));
/* Node 24 在 Windows 上不允许直接 spawn .cmd（CVE 修复），所以直接找 npm-cli.js
   用当前 node 执行；找不到才退回 shell 调 npm。 */
const npmCli = path.join(path.dirname(process.execPath), 'node_modules', 'npm', 'bin', 'npm-cli.js');
let packOut;
if (fs.existsSync(npmCli)) {
  packOut = execFileSync(process.execPath, [npmCli, 'pack', '--silent', '--pack-destination', outDir], { cwd: root, encoding: 'utf8' }).trim();
} else {
  packOut = execSync('npm pack --silent --pack-destination "' + outDir + '"', { cwd: root, encoding: 'utf8' }).trim();
}
const packName = packOut.split(/\r?\n/).filter(Boolean).pop();
const packed = path.join(outDir, packName);
if (!fs.existsSync(packed)) throw new Error('npm pack 没有产出 tgz: ' + packName);
fs.renameSync(packed, tgz);
const tbuf = fs.readFileSync(tgz);
if (tbuf.length < 3 || tbuf[0] !== 0x1f || tbuf[1] !== 0x8b) throw new Error('dsh-boot-suite.tgz 不是合法的 gzip');
if (tbuf.length < 1024 * 1024) throw new Error('dsh-boot-suite.tgz 太小（' + tbuf.length + ' B），疑似打包不完整');
console.log('TGZ OK version=' + vpkg.version + ' size=' + tbuf.length + ' bytes -> ' + tgz);
console.log('RELEASE OK version=' + vpkg.version + ' size=' + fs.statSync(out).size + ' bytes -> ' + out);
console.log('');
console.log('发布包目录：' + outDir);
console.log('  zip  ' + humanSize(fs.statSync(out).size) + '  ' + out);
console.log('  tgz  ' + humanSize(tbuf.length) + '  ' + tgz);
/* 发版流程不变：Release 资产用的是版本化文件名，脚本只产固定名，仍需人工复制改名 */
console.log('提醒：Release 上传的版本化文件名（dsh-boot-suite-win-V' + vpkg.version + '.zip）脚本不会自动改名，发版时仍需手动复制/重命名后再上传。');
