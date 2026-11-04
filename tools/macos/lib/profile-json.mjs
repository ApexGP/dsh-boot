#!/usr/bin/env node
/* ============================================================================
 * dsh-boot-suite —— profile package.json 专用读写工具（macOS 安装/卸载/回滚共用）
 *
 * 为什么单独写一个 .mjs：
 *   macOS 的 POSIX sh 没有可靠的 JSON 编辑手段。用 sed / grep 直接改
 *   ~/.dsh/profiles/<name>/package.json 很容易把用户其它字段、缩进、键顺序弄坏，
 *   甚至写出带 BOM 的文件让 DSH 解析失败。这里把「读/改/校验」收口到一处：
 *   · 始终 UTF-8 无 BOM、JSON.stringify(pkg, null, 2) + 换行
 *   · 只动目标字段，保留无关字段与原有键顺序（JS 对象属性顺序天然保留）
 *   · 写入走「临时文件 + rename」，中途失败不会留下半截 JSON
 *
 * 用法见下面的 USAGE。只被 tools/*.sh 调用，不依赖任何第三方包。
 * ========================================================================== */
import fs from 'node:fs'
import path from 'node:path'

const USAGE = `dsh-boot-suite profile 配置工具

用法：
  node tools/macos/lib/profile-json.mjs get --profile-dir <dir> --name <name>
  node tools/macos/lib/profile-json.mjs get-field --profile-dir <dir> --name <name> --field <dependency|installed|version|linkTarget|bundlesHas>
  node tools/macos/lib/profile-json.mjs add-dependency --profile-dir <dir> --name <name> --spec <spec>
  node tools/macos/lib/profile-json.mjs ensure-bundle --profile-dir <dir> --name <name>
  node tools/macos/lib/profile-json.mjs remove-plugin --profile-dir <dir> --name <name>
  node tools/macos/lib/profile-json.mjs verify-installed --profile-dir <dir> --name <name> --spec <spec> --version <v>
  node tools/macos/lib/profile-json.mjs show --profile-dir <dir>

参数：
  --profile-dir  profile 目录（里面有 package.json），例如 ~/.dsh/profiles/desktop
  --name         插件名，例如 dsh-boot-suite
  --spec         依赖描述，例如 link:/Users/me/dsh-boot-suite
  --version      期望的插件版本（verify-installed 用）

输出约定：
  get           只输出 JSON：{dependency,bundlesHas,installed,version,linkTarget}
                （linkTarget = node_modules/<name> 符号链接目标；没有链接时回退到 dependencies 里的 link: 路径）
  get-field     只输出字段原始值（空值输出空行），方便 shell 直接取值
  show          输出两行：dependencies: ... / bundles: ...
  其它子命令    输出中文 [ok] 提示

退出码：0 成功；1 失败（stderr 中文原因）；2 参数错误
`

function usage(code) {
  const text = USAGE
  if (code === 0) process.stdout.write(text)
  else process.stderr.write(text)
  process.exit(code)
}

function fail(msg, code = 1) {
  process.stderr.write('[x] ' + msg + '\n')
  process.exit(code)
}

function usageErr(msg) {
  process.stderr.write('[x] ' + msg + '\n\n')
  usage(2)
}

/* 解析 --key value / --key=value；值以 -- 开头会被当成下一个参数（这些字段没有以 -- 开头的合法值） */
function parseArgs(argv) {
  const out = {}
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i]
    if (a === '--help' || a === '-h') { out.help = '1'; continue }
    if (!a.startsWith('--')) usageErr('无法识别的参数：' + a)
    const eq = a.indexOf('=')
    if (eq > 0) {
      out[a.slice(2, eq)] = a.slice(eq + 1)
      continue
    }
    const key = a.slice(2)
    if (i + 1 >= argv.length || argv[i + 1].startsWith('--')) usageErr('参数 --' + key + ' 缺少取值')
    out[key] = argv[++i]
  }
  return out
}

/* 校验必填参数 + 拒绝拼错的未知参数（避免把 --profile 写成 --profiles 却静默成功） */
function requireArgs(args, keys) {
  const allowed = {}
  for (const k of keys) allowed[k] = true
  for (const k of keys) {
    if (args[k] === undefined || args[k] === '') usageErr('缺少参数 --' + k)
  }
  for (const k of Object.keys(args)) {
    if (!allowed[k]) usageErr('未知参数：--' + k)
  }
}

function profilePaths(profileDir) {
  const dir = path.resolve(profileDir)
  return { dir, pkgPath: path.join(dir, 'package.json') }
}

function readPackage(profileDir) {
  const { dir, pkgPath } = profilePaths(profileDir)
  if (!fs.existsSync(pkgPath)) fail('profile 目录里没有 package.json：' + pkgPath)
  let raw
  try {
    raw = fs.readFileSync(pkgPath, 'utf8')
  } catch (err) {
    fail('读取 package.json 失败：' + pkgPath + '：' + String((err && err.message) || err))
  }
  /* 兼容历史版本可能写过 BOM 的情况：解析前剥掉，写回时一律无 BOM */
  if (raw.charCodeAt(0) === 0xfeff) raw = raw.slice(1)
  let pkg
  try {
    pkg = JSON.parse(raw)
  } catch (err) {
    fail('profile 的 package.json 不是合法 JSON：' + pkgPath + '：' + String((err && err.message) || err))
  }
  if (!pkg || typeof pkg !== 'object' || Array.isArray(pkg)) {
    fail('profile 的 package.json 顶层不是对象：' + pkgPath)
  }
  return { dir, pkgPath, pkg }
}

function writePackage(pkgPath, pkg) {
  const text = JSON.stringify(pkg, null, 2) + '\n'
  let cur = ''
  try { cur = fs.readFileSync(pkgPath, 'utf8') } catch { cur = '' }
  if (cur.charCodeAt(0) === 0xfeff) cur = cur.slice(1)
  if (cur === text) return false
  const tmp = pkgPath + '.tmp-' + process.pid
  try {
    fs.writeFileSync(tmp, text, 'utf8')
    fs.renameSync(tmp, pkgPath)
  } catch (err) {
    try { fs.unlinkSync(tmp) } catch {}
    fail('写入 package.json 失败：' + pkgPath + '：' + String((err && err.message) || err))
  }
  return true
}

/* create=false 时返回 null（只读场景，不创建字段、不改文件） */
function depsOf(pkg, create) {
  if (pkg.dependencies !== undefined && (pkg.dependencies === null || typeof pkg.dependencies !== 'object' || Array.isArray(pkg.dependencies))) {
    if (!create) return null
    fail('profile 的 package.json 里 dependencies 不是对象，为避免破坏配置已停止')
  }
  if (pkg.dependencies === undefined) {
    if (!create) return null
    pkg.dependencies = {}
  }
  return pkg.dependencies
}

function bundlesOf(pkg, create) {
  if (pkg.dsh !== undefined && (pkg.dsh === null || typeof pkg.dsh !== 'object' || Array.isArray(pkg.dsh))) {
    if (!create) return null
    fail('profile 的 package.json 里 dsh 字段不是对象，为避免破坏配置已停止')
  }
  if (pkg.dsh === undefined) {
    if (!create) return null
    pkg.dsh = {}
  }
  if (pkg.dsh.profile !== undefined && (pkg.dsh.profile === null || typeof pkg.dsh.profile !== 'object' || Array.isArray(pkg.dsh.profile))) {
    if (!create) return null
    fail('profile 的 package.json 里 dsh.profile 字段不是对象，为避免破坏配置已停止')
  }
  if (pkg.dsh.profile === undefined) {
    if (!create) return null
    pkg.dsh.profile = {}
  }
  if (pkg.dsh.profile.bundles === undefined) {
    if (!create) return null
    pkg.dsh.profile.bundles = []
  }
  if (!Array.isArray(pkg.dsh.profile.bundles)) {
    if (!create) return null
    fail('profile 的 package.json 里 dsh.profile.bundles 不是数组，为避免破坏配置已停止')
  }
  return pkg.dsh.profile.bundles
}

function hasOwn(obj, key) {
  return !!obj && Object.prototype.hasOwnProperty.call(obj, key)
}

function readJsonVersion(file) {
  try {
    let raw = fs.readFileSync(file, 'utf8')
    if (raw.charCodeAt(0) === 0xfeff) raw = raw.slice(1)
    const obj = JSON.parse(raw)
    return obj && typeof obj.version === 'string' ? obj.version : null
  } catch { return null }
}

/* node_modules/<name> 的真实状态：是否安装、版本、符号链接指向 */
function installInfo(dir, name) {
  const inst = path.join(dir, 'node_modules', name)
  const info = { installed: false, version: null, linkTarget: null }
  try {
    const st = fs.lstatSync(inst)
    info.installed = true
    if (st.isSymbolicLink()) {
      try { info.linkTarget = path.resolve(path.dirname(inst), fs.readlinkSync(inst)) } catch {}
    }
  } catch { /* 不存在 */ }
  if (info.installed) info.version = readJsonVersion(path.join(inst, 'package.json'))
  return info
}

function dependencyOf(pkg, name) {
  const deps = depsOf(pkg, false)
  if (!hasOwn(deps, name)) return null
  return String(deps[name])
}

function cmdGet(args) {
  requireArgs(args, ['profile-dir', 'name'])
  const { dir, pkg } = readPackage(args['profile-dir'])
  const name = args.name
  const dep = dependencyOf(pkg, name)
  const bundles = bundlesOf(pkg, false)
  const info = installInfo(dir, name)
  /* 没有符号链接时（例如手工 npm 安装成真实目录），用 dependencies 里的 link: 作为兜底 */
  let linkTarget = info.linkTarget
  if (!linkTarget && dep && dep.indexOf('link:') === 0) linkTarget = dep.slice(5)
  const out = {
    dependency: dep,
    bundlesHas: !!bundles && bundles.indexOf(name) >= 0,
    installed: info.installed,
    version: info.version,
    linkTarget,
  }
  process.stdout.write(JSON.stringify(out, null, 2) + '\n')
}

function cmdGetField(args) {
  requireArgs(args, ['profile-dir', 'name', 'field'])
  const { dir, pkg } = readPackage(args['profile-dir'])
  const name = args.name
  const field = args.field
  let value = ''
  if (field === 'dependency') {
    value = dependencyOf(pkg, name) || ''
  } else if (field === 'installed') {
    value = installInfo(dir, name).installed ? '1' : ''
  } else if (field === 'version') {
    value = installInfo(dir, name).version || ''
  } else if (field === 'linkTarget') {
    const info = installInfo(dir, name)
    value = info.linkTarget || ''
    if (!value) {
      const dep = dependencyOf(pkg, name)
      if (dep && dep.indexOf('link:') === 0) value = dep.slice(5)
    }
  } else if (field === 'bundlesHas') {
    const bundles = bundlesOf(pkg, false)
    value = bundles && bundles.indexOf(name) >= 0 ? '1' : ''
  } else {
    usageErr('未知字段：' + field)
  }
  if (value) process.stdout.write(value + '\n')
}

function cmdAddDependency(args) {
  requireArgs(args, ['profile-dir', 'name', 'spec'])
  const { pkgPath, pkg } = readPackage(args['profile-dir'])
  const deps = depsOf(pkg, true)
  /* 已存在的键直接赋值不会改变它在 JSON 里的位置，顺序天然保留 */
  deps[args.name] = args.spec
  const wrote = writePackage(pkgPath, pkg)
  process.stdout.write(wrote
    ? '[ok] 已写入 dependencies.' + args.name + ' = ' + args.spec + '\n'
    : '[ok] dependencies.' + args.name + ' 已经是 ' + args.spec + '（文件未改动）\n')
}

function cmdEnsureBundle(args) {
  requireArgs(args, ['profile-dir', 'name'])
  const { pkgPath, pkg } = readPackage(args['profile-dir'])
  const bundles = bundlesOf(pkg, true)
  const name = args.name
  const before = bundles.slice()
  const seen = []
  for (const b of before) {
    if (seen.indexOf(b) < 0) seen.push(b)
  }
  let changed = seen.length !== before.length
  if (seen.indexOf(name) < 0) {
    const idx = seen.indexOf('dsh-plugin-desktop-notify')
    /* 与 Windows 安装器一致：插在 dsh-plugin-desktop-notify 之后，没有就追加到末尾 */
    if (idx >= 0) seen.splice(idx + 1, 0, name)
    else seen.push(name)
    changed = true
  }
  if (changed) {
    pkg.dsh.profile.bundles = seen
    writePackage(pkgPath, pkg)
    process.stdout.write('[ok] bundles 已更新：' + (seen.join(', ') || '（空）') + '\n')
  } else {
    process.stdout.write('[ok] bundles 已包含 ' + name + '（未改动）\n')
  }
}

function cmdRemovePlugin(args) {
  requireArgs(args, ['profile-dir', 'name'])
  const { pkgPath, pkg } = readPackage(args['profile-dir'])
  const name = args.name
  const messages = []
  let changed = false
  const deps = depsOf(pkg, false)
  if (hasOwn(deps, name)) {
    delete deps[name]
    changed = true
    messages.push('已从 dependencies 移除 ' + name)
  }
  const bundles = bundlesOf(pkg, false)
  if (bundles) {
    const keep = bundles.filter((b) => b !== name)
    if (keep.length !== bundles.length) {
      pkg.dsh.profile.bundles = keep
      changed = true
      messages.push('已从 bundles 移除 ' + name)
    }
  }
  if (changed) writePackage(pkgPath, pkg)
  process.stdout.write('[ok] ' + (messages.length ? messages.join('；') : 'profile 里本来就没有 ' + name) + '\n')
}

function cmdVerifyInstalled(args) {
  requireArgs(args, ['profile-dir', 'name', 'spec', 'version'])
  const name = args.name
  const { pkgPath, pkg } = readPackage(args['profile-dir'])
  const dep = dependencyOf(pkg, name)
  if (!dep) fail('安装校验失败：dependencies 里没有 ' + name + '（' + pkgPath + '）')
  if (dep !== args.spec) fail('安装校验失败：dependencies.' + name + ' 是 ' + dep + '，期望 ' + args.spec)
  const bundles = bundlesOf(pkg, false)
  if (!bundles || bundles.indexOf(name) < 0) fail('安装校验失败：bundles 里没有 ' + name + '（DSH 启动时不会加载它）')
  const info = installInfo(profilePaths(args['profile-dir']).dir, name)
  if (!info.installed) fail('安装校验失败：node_modules/' + name + ' 不存在（命令行可能没有真正安装）')
  if (info.version !== args.version) fail('安装校验失败：node_modules/' + name + ' 的版本是 ' + info.version + '，期望 ' + args.version)
  process.stdout.write('[ok] 安装校验通过：' + name + ' v' + info.version + '（' + profilePaths(args['profile-dir']).dir + '）\n')
}

function cmdShow(args) {
  requireArgs(args, ['profile-dir'])
  const { pkg } = readPackage(args['profile-dir'])
  const deps = depsOf(pkg, false)
  const bundles = bundlesOf(pkg, false)
  const depKeys = deps ? Object.keys(deps) : []
  const depText = depKeys.length ? depKeys.map((k) => k + '=' + String(deps[k])).join(', ') : '（空）'
  const bundleText = bundles && bundles.length ? bundles.join(', ') : '（空）'
  process.stdout.write('dependencies: ' + depText + '\n')
  process.stdout.write('bundles: ' + bundleText + '\n')
}

const CMD = process.argv[2]
if (!CMD) usageErr('缺少子命令')
if (CMD === '--help' || CMD === '-h' || CMD === 'help') usage(0)
const rawArgs = process.argv.slice(3)
const args = parseArgs(rawArgs)
if (args.help) usage(0)

switch (CMD) {
  case 'get': cmdGet(args); break
  case 'get-field': cmdGetField(args); break
  case 'add-dependency': cmdAddDependency(args); break
  case 'ensure-bundle': cmdEnsureBundle(args); break
  case 'remove-plugin': cmdRemovePlugin(args); break
  case 'verify-installed': cmdVerifyInstalled(args); break
  case 'show': cmdShow(args); break
  default: usageErr('未知子命令：' + CMD)
}
