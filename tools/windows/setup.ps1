#Requires -Version 5.1
<#
  dsh-boot-suite —— 统一维护入口（Windows）

  用法：双击仓库根目录的 setup.cmd，出现中文菜单：
        1 安装 / 更新   2 卸载   3 诊断   4 打开离线预览   0 退出

  为什么要这个菜单：以前根目录摆着安装 / 卸载 / 诊断 / 预览四个中文名的双击文件，
  用户分不清该点哪个；而且中文文件名在跨平台仓库里会带来编码麻烦（.cmd 必须纯 ASCII）。
  现在根目录只留 setup.cmd 一个薄壳，中文菜单逻辑集中到这里。

  本脚本只做转发：调用同目录的 install.ps1 / uninstall.ps1 / diagnose.ps1，自己不含
  安装逻辑；全程不会自动启动 DSH —— 装完让用户自己打开，避免「装完自动启动」出事故。
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
function Say($m) { Write-Host $m }

# 本脚本在 tools\windows\ 下：往上一级是 tools，再往上一级才是仓库根（v2.16.11 目录重排）。
$RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (-not (Test-Path (Join-Path $RepoRoot 'package.json'))) {
  Say ('[x] 这不像插件目录：' + $RepoRoot)
  Say '    请把压缩包完整解压后再双击 setup.cmd（不要在压缩软件里直接双击）。'
  exit 1
}

$version = '未知'
try {
  $pkgText = [System.IO.File]::ReadAllText((Join-Path $RepoRoot 'package.json'))
  $pkgObj = $pkgText | ConvertFrom-Json
  $version = [string]$pkgObj.version
} catch {}

function Invoke-Sibling([string]$Name) {
  $scriptPath = Join-Path $PSScriptRoot $Name
  if (-not (Test-Path $scriptPath)) {
    Say ('[x] 缺少脚本：' + $scriptPath)
    return 1
  }
  # 用独立 PowerShell 进程跑子脚本：它们失败时是 exit 1，如果直接 & 调用，会把整个
  # 菜单进程一起带走，用户就没机会「安装失败立刻点卸载」了。
  # -File 后面整段加引号：仓库路径可能带空格（例如 ...\DeepSeek harness 开机动画\...）。
  $argLine = '-NoProfile -ExecutionPolicy Bypass -File "' + $scriptPath + '"'
  $proc = Start-Process -FilePath 'powershell.exe' -ArgumentList $argLine -Wait -PassThru -NoNewWindow
  return $proc.ExitCode
}

function Open-Preview {
  $preview = Join-Path $RepoRoot 'preview\index.html'
  if (-not (Test-Path $preview)) {
    Say ('[x] 找不到离线预览：' + $preview)
    return
  }
  Say ('用默认浏览器打开：' + $preview)
  try { Start-Process -FilePath $preview } catch {
    Say ('[x] 打开失败：' + $_.Exception.Message)
    Say '    请手动双击仓库根目录的 preview\index.html。'
  }
}

while ($true) {
  Write-Host ''
  Write-Host '============================================================' -ForegroundColor Cyan
  Write-Host ('  dsh-boot-suite v' + $version + ' —— 维护菜单') -ForegroundColor Cyan
  Write-Host ('  仓库位置：' + $RepoRoot) -ForegroundColor Cyan
  Write-Host '============================================================' -ForegroundColor Cyan
  Say '  1. 安装 / 更新（请先完全退出 DeepSeek Harness，右下角托盘也退出）'
  Say '  2. 卸载（黑屏、界面点不动时用这个）'
  Say '  3. 诊断（在桌面生成报告，发给作者）'
  Say '  4. 打开离线预览（不装进 DSH 也能看动画）'
  Say '  0. 退出'
  Say ''

  $choice = ''
  try { $choice = Read-Host '请输入序号后回车（默认 1）' } catch {
    Say '（读不到键盘输入，已退出）'
    exit 2
  }
  $choice = ([string]$choice).Trim()
  if ($choice -eq '') { $choice = '1' }

  $code = 0
  if ($choice -eq '1') { $code = Invoke-Sibling 'install.ps1' }
  elseif ($choice -eq '2') { $code = Invoke-Sibling 'uninstall.ps1' }
  elseif ($choice -eq '3') { $code = Invoke-Sibling 'diagnose.ps1' }
  elseif ($choice -eq '4') { Open-Preview }
  elseif ($choice -eq '0') {
    Say '已退出。'
    exit 0
  } else {
    Say ('[!] 没有这个选项：' + $choice)
    Say ''
    continue
  }

  if ($code -ne 0) {
    Say ''
    Say ('[!] 上面的操作没有成功（退出码 ' + $code + '）。可以再选 1 试一次，或把窗口里的输出发给作者。')
  }
  Say ''
  try { Read-Host '按回车返回菜单' | Out-Null } catch { exit 0 }
}
