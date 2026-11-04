// macOS 支持专项冒烟测试（v2.16.11）
//
// 目标：macOS 的安装/卸载/回滚/诊断/自动更新全是 POSIX sh 脚本，Windows 那套 .ps1
// 在 mac 上一条都命不中。这里不启动 DSH、不动真实 ~/.dsh，按四层检查兜底：
//   1) 文件清单与可执行位（发布包必须带齐，否则 mac 用户解压后无从下手）
//   2) sh -n 语法（POSIX；Windows 上没有 /bin/sh，跳过）
//   3) 关键契约字符串（回滚 checkpoint、安装后校验、自动更新、.command 入口）
//   4) 真跑：profile-json.mjs 全命令 + install-macos.sh --check-only（临时 DSH_HOME）
//
// 全程零第三方依赖；临时目录跑完即删。
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import crypto from 'node:crypto'
import { spawnSync } from 'node:child_process'
import { fileURLToPath } from 'node:url'

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const isWin = process.platform === 'win32'

let pass = 0
let fail = 0
function check(label, ok, extra) {
  if (ok) { pass++; console.log('  ok   ' + label) }
  else { fail++; console.log('  FAIL ' + label + (extra !== undefined && extra !== '' ? '  → ' + extra : '')) }
}
function skip(label) { console.log('  skip ' + label) }

const read = (rel) => fs.readFileSync(path.join(ROOT, rel), 'utf8')
const exists = (rel) => fs.existsSync(path.join(ROOT, rel))

/* 临时目录统一登记，最后一起删；绝不碰真实 ~/.dsh 与桌面 */
const TMP_DIRS = []
function mkTmp(prefix) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), prefix))
  TMP_DIRS.push(dir)
  return dir
}

try {
  /* ── [1] 文件清单 ─────────────────────────────────────────────────────── */
  console.log('\n[1] macOS 脚本与双击入口文件清单')
  const MAC_SCRIPTS = [
    'tools/install-macos.sh',
    'tools/emergency-uninstall.sh',
    'tools/rollback-version.sh',
    'tools/doctor.sh',
    'tools/update-apply.sh',
  ]
  const MAC_LIBS = ['tools/lib/mac-common.sh', 'tools/lib/profile-json.mjs']
  const MAC_COMMANDS = ['安装-mac.command', '卸载-mac.command', '诊断-mac.command', '打开预览.command']
  const ONLINE = 'install-online.sh'
  for (const f of [...MAC_SCRIPTS, ...MAC_LIBS, ...MAC_COMMANDS, ONLINE]) {
    check('存在 ' + f, exists(f))
  }

  /* ── [2] POSIX 语法与可执行位 ─────────────────────────────────────────── */
  console.log('\n[2] POSIX sh 语法（sh -n）与可执行位')
  if (isWin) {
    skip('sh -n（Windows 上没有 /bin/sh，安装/更新脚本只在 mac 上执行）')
    skip('可执行位（Windows 文件系统不记录 Unix 权限位）')
  } else {
    for (const f of [...MAC_SCRIPTS, 'tools/lib/mac-common.sh', ONLINE, ...MAC_COMMANDS]) {
      if (!exists(f)) { check('sh -n ' + f, false, '文件不存在'); continue }
      const res = spawnSync('sh', ['-n', path.join(ROOT, f)], { encoding: 'utf8' })
      check('sh -n ' + f, res.status === 0, String((res.stderr || '').trim()).slice(0, 200))
    }
    for (const f of [...MAC_SCRIPTS, 'tools/lib/mac-common.sh', ONLINE, ...MAC_COMMANDS]) {
      if (!exists(f)) { check('可执行位 ' + f, false, '文件不存在'); continue }
      const mode = fs.statSync(path.join(ROOT, f)).mode
      check('可执行位 ' + f, (mode & 0o111) !== 0, 'mode=' + (mode & 0o777).toString(8))
    }
  }

  /* ── [3] 关键契约字符串 ───────────────────────────────────────────────── */
  console.log('\n[3] 脚本关键契约')
  function expectContains(file, needles) {
    if (!exists(file)) {
      check('内容检查 ' + file, false, '文件不存在')
      return
    }
    const text = read(file)
    for (const n of needles) check(file + ' 含「' + n + '」', text.includes(n))
  }
  /* 安装器：检查模式/强制模式/profile 选择、更新前回滚 checkpoint、安装后按真实文件校验 */
  expectContains('tools/install-macos.sh', [
    '--check-only', '--force', '--profiles',
    '紧急回滚-V', 'rollback-version.sh', 'DSH_BOOT_SUITE_ROLLBACK', '_backup-install-',
    'dsh plugin', 'verify-installed', 'managed exclusively',
  ])
  /* 更新执行器：宿主传参、zip 校验、pkg.new/pkg.old 替换、更新日志 */
  expectContains('tools/update-apply.sh', [
    '--zip', '--version', '--exe', '--config',
    'unzip -t', 'pkg.new', 'pkg.old', 'install-macos.sh', '更新日志',
  ])
  expectContains('tools/rollback-version.sh', ['--target-pkg', '--no-start', 'DSH_BOOT_SUITE_ROLLBACK'])
  expectContains('tools/emergency-uninstall.sh', [
    '_backup-uninstall-', 'dsh-boot-suite', 'dsh-startup-screen', 'dsh-chat-wallpaper',
  ])
  expectContains('tools/doctor.sh', ['dsh诊断-'])
  expectContains(ONLINE, ['dsh-boot-suite-win.zip', 'archive/refs/heads/main.zip'])
  /* 根目录 4 个 .command：双击后必须调对应脚本 */
  expectContains('安装-mac.command', ['install-macos.sh'])
  expectContains('卸载-mac.command', ['emergency-uninstall.sh'])
  expectContains('诊断-mac.command', ['doctor.sh'])
  expectContains('打开预览.command', ['open-preview.sh'])

  /* ── [4] 宿主自动更新的 macOS 分支 ───────────────────────────────────── */
  console.log('\n[4] lib/host-startup.js 的 macOS 自动更新分支')
  const hostStartup = read('lib/host-startup.js')
  check('宿主管引用 tools/update-apply.sh', hostStartup.includes('update-apply.sh'))
  check("宿主管含 darwin 分支", hostStartup.includes("'darwin'") || hostStartup.includes('"darwin"'))
  check('宿主管含 curl（mac 下载兜底）', hostStartup.includes('curl'))
  check('宿主管用 IS_MAC 或 process.platform 判定平台',
    hostStartup.includes('IS_MAC') || hostStartup.includes("process.platform === 'darwin'"))

  /* ── [5] 其它跨平台工具 ───────────────────────────────────────────────── */
  console.log('\n[5] 跨平台工具（Chrome 路径 / bundle patch 注释）')
  const CHROME_MAC = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
  const motion = read('tools/motion-check.mjs')
  check('motion-check 含 macOS Chrome 路径', motion.includes(CHROME_MAC))
  check('motion-check 保留 CHROME_PATH 覆盖逻辑', motion.includes('CHROME_PATH'))
  const frames = read('tools/export-frames.mjs')
  check('export-frames 含 macOS Chrome 路径', frames.includes(CHROME_MAC))
  check('export-frames 保留 CHROME_PATH 覆盖逻辑', frames.includes('CHROME_PATH'))
  const patch = read('cordis.patch.yml')
  check('cordis.patch.yml 注释含 macOS 安装示例',
    patch.includes('macOS:') && patch.includes('link:/Users/'))

  /* ── [6] profile-json.mjs 功能（临时 profile，真跑） ──────────────────── */
  console.log('\n[6] profile-json.mjs 功能（临时 profile）')
  const work = mkTmp('dsh-smoke-macos-')
  const profileDir = path.join(work, 'profiles', 'desktop')
  fs.mkdirSync(profileDir, { recursive: true })
  const pkgPath = path.join(profileDir, 'package.json')
  /* 形状对齐真实 profile：name/dependencies/dsh.profile.bundles；
     bundles 里故意放一个重复项，验证 ensure-bundle 去重 */
  fs.writeFileSync(pkgPath, JSON.stringify({
    name: 'desktop',
    private: true,
    dependencies: { '@deepseek-ai/dsh-base': '1.0.0' },
    dsh: { profile: { bundles: ['@deepseek-ai/dsh-base', 'dsh-plugin-desktop-notify', 'dsh-plugin-desktop-notify', 'legacy-plugin'] } },
  }, null, 2) + '\n', 'utf8')
  const spec = 'link:' + path.join(work, 'repo-link')
  const pjRun = (...a) => spawnSync(process.execPath, [path.join(ROOT, 'tools/lib/profile-json.mjs'), ...a], { encoding: 'utf8' })
  const readPkg = () => JSON.parse(fs.readFileSync(pkgPath, 'utf8'))
  const hasOwn = (o, k) => !!o && Object.prototype.hasOwnProperty.call(o, k)

  let res = pjRun('add-dependency', '--profile-dir', profileDir, '--name', 'dsh-boot-suite', '--spec', spec)
  check('add-dependency 退出码 0', res.status === 0, String((res.stderr || '').trim()))
  let pkg = readPkg()
  check('dependencies 写入 link: 规格', pkg.dependencies['dsh-boot-suite'] === spec, String(pkg.dependencies['dsh-boot-suite']))
  check('add-dependency 保留无关依赖', pkg.dependencies['@deepseek-ai/dsh-base'] === '1.0.0')

  res = pjRun('ensure-bundle', '--profile-dir', profileDir, '--name', 'dsh-boot-suite')
  check('ensure-bundle 退出码 0', res.status === 0, String((res.stderr || '').trim()))
  pkg = readPkg()
  let bundles = pkg.dsh.profile.bundles
  check('bundles 去重（无重复项）', new Set(bundles).size === bundles.length, bundles.join(', '))
  check('bundles 插在 dsh-plugin-desktop-notify 之后',
    bundles.indexOf('dsh-boot-suite') === bundles.indexOf('dsh-plugin-desktop-notify') + 1, bundles.join(', '))
  check('bundles 保留排在后面的无关插件', bundles[bundles.length - 1] === 'legacy-plugin', bundles.join(', '))
  const bundlesBefore = bundles.slice()
  res = pjRun('ensure-bundle', '--profile-dir', profileDir, '--name', 'dsh-boot-suite')
  check('ensure-bundle 幂等（重复调用不再改）',
    res.status === 0 && JSON.stringify(readPkg().dsh.profile.bundles) === JSON.stringify(bundlesBefore))

  /* 造一个假的已安装目录 + node_modules 符号链接，验证 get / verify-installed 走真实文件 */
  const installedDir = path.join(work, 'fake-installed')
  fs.mkdirSync(installedDir, { recursive: true })
  fs.writeFileSync(path.join(installedDir, 'package.json'),
    JSON.stringify({ name: 'dsh-boot-suite', version: '9.9.9' }, null, 2) + '\n', 'utf8')
  fs.mkdirSync(path.join(profileDir, 'node_modules'), { recursive: true })
  let linkOk = true
  try {
    /* Windows 上 junction 不需要管理员权限；macOS 用普通目录符号链接 */
    fs.symlinkSync(installedDir, path.join(profileDir, 'node_modules', 'dsh-boot-suite'), isWin ? 'junction' : 'dir')
  } catch (e) {
    linkOk = false
    check('创建 node_modules 符号链接（get/verify 前提）', false, String((e && e.message) || e))
  }
  if (linkOk) {
    res = pjRun('get', '--profile-dir', profileDir, '--name', 'dsh-boot-suite')
    check('get 退出码 0', res.status === 0, String((res.stderr || '').trim()))
    let info = null
    try { info = JSON.parse(res.stdout) } catch (e) { info = null }
    check('get 只输出合法 JSON', !!info, String(res.stdout || '').slice(0, 120))
    if (info) {
      check('get.dependency = link: 规格', info.dependency === spec, String(info.dependency))
      check('get.bundlesHas = true', info.bundlesHas === true)
      check('get.installed = true', info.installed === true)
      check('get.version = 9.9.9', info.version === '9.9.9', String(info.version))
      check('get.linkTarget 指向安装目录',
        typeof info.linkTarget === 'string' && info.linkTarget.includes('fake-installed'), String(info.linkTarget))
    }
    res = pjRun('verify-installed', '--profile-dir', profileDir, '--name', 'dsh-boot-suite',
      '--spec', spec, '--version', '9.9.9')
    check('verify-installed 通过（exit 0）', res.status === 0, String((res.stderr || '').trim()))
    res = pjRun('verify-installed', '--profile-dir', profileDir, '--name', 'dsh-boot-suite',
      '--spec', spec, '--version', '0.0.1')
    check('verify-installed 版本不符时失败（exit 1）', res.status === 1, 'exit=' + res.status)
    check('verify-installed 失败给中文原因', String(res.stderr || '').includes('校验失败'), String(res.stderr || '').slice(0, 120))
  }

  const rawBytes = fs.readFileSync(pkgPath)
  check('写回的 package.json 无 UTF-8 BOM',
    !(rawBytes.length >= 3 && rawBytes[0] === 0xEF && rawBytes[1] === 0xBB && rawBytes[2] === 0xBF))
  check('写回的 package.json 以换行结尾', fs.readFileSync(pkgPath, 'utf8').endsWith('\n'))

  res = pjRun('remove-plugin', '--profile-dir', profileDir, '--name', 'dsh-boot-suite')
  check('remove-plugin 退出码 0', res.status === 0, String((res.stderr || '').trim()))
  pkg = readPkg()
  check('remove-plugin 移除 dependencies 条目', !hasOwn(pkg.dependencies, 'dsh-boot-suite'))
  check('remove-plugin 移除 bundles 条目', !pkg.dsh.profile.bundles.includes('dsh-boot-suite'))
  check('remove-plugin 保留无关依赖与插件',
    pkg.dependencies['@deepseek-ai/dsh-base'] === '1.0.0' && pkg.dsh.profile.bundles.includes('legacy-plugin'))

  /* ── [7] install-macos.sh --check-only（临时 DSH_HOME） ───────────────── */
  console.log('\n[7] install-macos.sh --check-only 集成（临时 DSH_HOME，不修改任何文件）')
  if (isWin) {
    skip('install-macos.sh --check-only（Windows 上没有 /bin/sh）')
  } else if (!exists('tools/install-macos.sh')) {
    check('install-macos.sh --check-only 集成测试', false, '文件不存在')
  } else {
    const dshHome = path.join(work, 'dsh-home')
    const fakeProfileDir = path.join(dshHome, 'profiles', 'desktop')
    fs.mkdirSync(fakeProfileDir, { recursive: true })
    const fakePkgPath = path.join(fakeProfileDir, 'package.json')
    fs.writeFileSync(fakePkgPath, JSON.stringify({
      name: 'desktop',
      private: true,
      dependencies: { '@deepseek-ai/dsh-base': '1.0.0' },
      dsh: { profile: { bundles: ['@deepseek-ai/dsh-base'] } },
    }, null, 2) + '\n', 'utf8')
    const hashBefore = crypto.createHash('sha256').update(fs.readFileSync(fakePkgPath)).digest('hex')
    const runCheck = spawnSync('sh', [path.join(ROOT, 'tools/install-macos.sh'), '--check-only'], {
      encoding: 'utf8',
      timeout: 120000,
      env: { ...process.env, DSH_HOME: dshHome, DSH_SKIP_PROCESS_CHECK: '1', DSH_SKIP_REOPEN: '1' },
    })
    check('--check-only 退出码 0', runCheck.status === 0,
      'exit=' + runCheck.status + ' ' + String((runCheck.stderr || '').trim()).slice(0, 200))
    check('--check-only 输出中文检查计划', String(runCheck.stdout || '').includes('检查'),
      String(runCheck.stdout || '').slice(0, 160))
    check('--check-only 不修改 profile 的 package.json',
      crypto.createHash('sha256').update(fs.readFileSync(fakePkgPath)).digest('hex') === hashBefore)
    check('--check-only 不创建 node_modules',
      !fs.existsSync(path.join(fakeProfileDir, 'node_modules')))
  }

  /* ── [8] $VAR 紧跟非 ASCII 字符（bash 3.2 会把它吞进变量名） ─────────── */
  console.log('\n[8] $VAR 紧跟非 ASCII 字符静态扫描（macOS /bin/sh 是 bash 3.2）')
  /* macOS 的 /bin/sh 是 bash 3.2：写成 $name 后紧跟中文标点时，中文首字节会被
     吞进变量名，变量变成 unset（轻则中文丢失，重则参数错位）。所有 POSIX sh
     脚本一律要求用花括号包住变量名、或用空格与中文隔开。 */
  const scanTargets = []
  const collectShellScripts = (dir) => {
    for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
      if (e.name === '.git' || e.name === 'node_modules') continue
      const full = path.join(dir, e.name)
      if (e.isDirectory()) collectShellScripts(full)
      else if (e.name.endsWith('.sh') || e.name.endsWith('.command')) scanTargets.push(full)
    }
  }
  collectShellScripts(ROOT)
  const VAR_NON_ASCII = /\$[A-Za-z_][A-Za-z0-9_]*(?=[^\x00-\x7F])/g
  const offenders = []
  for (const file of scanTargets) {
    const rel = path.relative(ROOT, file)
    fs.readFileSync(file, 'utf8').split(/\r?\n/).forEach((line, i) => {
      if (/^\s*#/.test(line)) return /* 整行注释不会被 shell 展开，豁免 */
      const hits = line.match(VAR_NON_ASCII)
      if (hits) offenders.push(rel + ':' + (i + 1) + ' ' + hits.join(' ') + '  ' + line.trim().slice(0, 80))
    })
  }
  check('扫描到 ' + scanTargets.length + ' 个 .sh/.command 文件', scanTargets.length >= 12, String(scanTargets.length))
  check('没有「$VAR 紧跟非 ASCII 字符」的写法', offenders.length === 0, offenders.slice(0, 5).join(' | '))

  /* ── [9] unzip -Z1 中文名 + BSD tr 的发布阻断回归 ─────────────────────── */
  console.log('\n[9] update-apply.sh 的 unzip -Z1 / tr 回归（macOS BSD tr 遇非法 UTF-8 会 rc=1）')
  /* 背景：macOS 自带 unzip -Z1 在 UTF-8 locale 下列含中文名的 zip 会输出非法 UTF-8 字节，
     BSD tr 读到非法字节直接报「Illegal byte sequence」并返回 1。update-apply.sh 里
     tr -d CR < 文件列表 | sed ... 因此会产出空文件，自动更新 100% 失败。
     修法是在 tr 前加 LC_ALL=C（按字节处理，不做多字节解码）。 */
  const updateApplyText = exists('tools/update-apply.sh') ? read('tools/update-apply.sh') : ''
  const TR_CR = /tr\s+-d\s+['"]\\r['"]/g
  const trSites = []
  for (const hit of updateApplyText.matchAll(TR_CR)) {
    const before = updateApplyText.slice(Math.max(0, hit.index - 60), hit.index)
    trSites.push({ guarded: /LC_ALL=C\s+$/.test(before) })
  }
  const unguarded = trSites.filter((s) => !s.guarded).length
  check('update-apply.sh 的 tr -d 回车符每一处前都有 LC_ALL=C（' + (trSites.length - unguarded) + '/' + trSites.length + ' 处）',
    trSites.length > 0 && unguarded === 0, unguarded ? unguarded + ' 处裸 tr 未加 LC_ALL=C' : '没有 tr 调用')
  const lcAllTr = (updateApplyText.match(/LC_ALL=C\s+tr\b/g) || []).length
  check('update-apply.sh 的 LC_ALL=C tr 至少 2 处', lcAllTr >= 2, '实际 ' + lcAllTr + ' 处')

  if (isWin) {
    skip('unzip -Z1 / BSD tr 功能回归（Windows 没有 /bin/sh、zip、unzip）')
  } else {
    const trWork = mkTmp('dsh-smoke-tr-')
    const trSrc = path.join(trWork, 'src')
    fs.mkdirSync(trSrc, { recursive: true })
    fs.writeFileSync(path.join(trSrc, 'a.txt'), 'a\n')
    fs.writeFileSync(path.join(trSrc, 'b.txt'), 'b\n')
    fs.writeFileSync(path.join(trSrc, '安装.cmd'), 'x\n')
    const trZip = path.join(trWork, 'names.zip')
    const zipRes = spawnSync('zip', ['-r', '-q', trZip, '.'], { cwd: trSrc, encoding: 'utf8' })
    check('系统 zip 可用（功能回归前提）', zipRes.status === 0, String((zipRes.stderr || '').trim()))
    if (zipRes.status === 0) {
      const utf8Env = { ...process.env, LANG: 'en_US.UTF-8', LC_ALL: 'en_US.UTF-8' }
      const guarded = spawnSync('sh', ['-c', 'unzip -Z1 "$1" | LC_ALL=C ' + "tr -d '\\r'", 'sh', trZip], { encoding: 'utf8', env: utf8Env })
      check('unzip -Z1 含中文名 + LC_ALL=C tr：exit 0', guarded.status === 0,
        'exit=' + guarded.status + ' ' + String((guarded.stderr || '').trim()).slice(0, 120))
      const gotLines = String(guarded.stdout || '').split('\n').filter((l) => l !== '').length
      check('过滤后行数正确（3 条，中文名没被吞）', guarded.status === 0 && gotLines === 3, 'lines=' + gotLines)
      /* 复现负向：去掉 LC_ALL=C 时 BSD tr 在本机 UTF-8 locale 下应 rc=1。
         不是所有环境都触发（GNU tr、纯 C locale、或该 unzip 能正常转码），
         触发才断言；不触发就 skip，避免 Windows/Linux 机器被卡红。 */
      const bare = spawnSync('sh', ['-c', 'unzip -Z1 "$1" | ' + "tr -d '\\r'", 'sh', trZip], { encoding: 'utf8', env: utf8Env })
      if (bare.status !== 0) {
        check('复现：不加 LC_ALL=C 时 BSD tr 因非法字节失败（rc=' + bare.status + '）', true)
      } else {
        skip('复现：本环境未触发 BSD tr 非法字节错误（不视为失败）')
      }
    }
  }
} catch (e) {
  fail++
  console.log('  FAIL 测试本身抛异常：' + String((e && e.stack) || e))
} finally {
  for (const dir of TMP_DIRS) {
    try { fs.rmSync(dir, { recursive: true, force: true }) } catch { /* 清理失败不影响结果 */ }
  }
  console.log('\n' + (fail === 0 ? '✓ 全部通过' : '✗ ' + fail + ' 项失败') + '（' + pass + ' 项通过）')
  process.exit(fail === 0 ? 0 : 1)
}
