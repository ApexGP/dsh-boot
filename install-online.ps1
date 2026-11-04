#Requires -Version 5.1
<#
  dsh-boot-suite —— 在线一键安装（GitHub 直连，不用网盘）
  用法（PowerShell 里执行一行）：
    irm https://raw.githubusercontent.com/LeeRolling/dsh-boot-suite/main/install-online.ps1 | iex
    本地已下载时：powershell -NoProfile -ExecutionPolicy Bypass -File install-online.ps1 [-CheckOnly]
#>
[CmdletBinding()]
param([switch]$CheckOnly)

$ErrorActionPreference = 'Stop'
$repo = 'LeeRolling/dsh-boot-suite'
$zipUrl = 'https://github.com/' + $repo + '/releases/latest/download/dsh-boot-suite-win.zip'
$fallbackUrl = 'https://github.com/' + $repo + '/archive/refs/heads/main.zip'

Write-Host ''
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host '  dsh-boot-suite —— 在线安装' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host '  [重要] 请先完全退出 DeepSeek Harness Desktop（右下角托盘也要退出）'
Write-Host ''

$tmp = Join-Path $env:TEMP ('dsh-boot-suite-online-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$zip = Join-Path $tmp 'package.zip'
$dir = Join-Path $tmp 'pkg'

Write-Host '[1/3] 下载最新版…'
$downloaded = $false
try {
  Invoke-WebRequest -Uri $zipUrl -OutFile $zip -UseBasicParsing -TimeoutSec 120
  $downloaded = $true
} catch {
  Write-Host ('      发布包下载失败：' + $_.Exception.Message)
  Write-Host '      改用源码包（main 分支）…'
}
if (-not $downloaded) {
  Invoke-WebRequest -Uri $fallbackUrl -OutFile $zip -UseBasicParsing -TimeoutSec 120
}

Write-Host '[2/3] 解压…'
Expand-Archive -Path $zip -DestinationPath $dir -Force

# 发布包根目录有 setup.cmd，但那是给人双击的菜单壳；本脚本已在非交互环境里跑，
# 直接找安装器并把 -CheckOnly 透传下去。
# 优先新布局 tools/windows/install.ps1（v2.16.11 目录重排后）；找不到就回退旧布局
# tools/install.ps1（重排前的发布包；新包根的 tools\install.ps1 只是转发垫片）。
$installPs1 = Get-ChildItem $dir -Recurse -Filter 'install.ps1' -ErrorAction SilentlyContinue | Where-Object { $_.FullName -match '[/\\]tools[/\\]windows[/\\]install\.ps1$' } | Select-Object -First 1
if (-not $installPs1) {
  Write-Host '      没有新布局安装器，按旧布局（tools/install.ps1）再找一次…'
  $installPs1 = Get-ChildItem $dir -Recurse -Filter 'install.ps1' -ErrorAction SilentlyContinue | Where-Object { $_.FullName -match '[/\\]tools[/\\]install\.ps1$' } | Select-Object -First 1
}
if (-not $installPs1) {
  Write-Host '[x] 压缩包里没找到安装器（tools/windows/install.ps1 或 tools/install.ps1），可能下载不完整。' -ForegroundColor Red
  Write-Host '    请到 https://github.com/LeeRolling/dsh-boot-suite/releases 下载最新版 zip 后重试。' -ForegroundColor Red
  exit 1
}

Write-Host '[3/3] 开始安装…'
if ($CheckOnly) { & powershell -NoProfile -ExecutionPolicy Bypass -File $installPs1.FullName -CheckOnly }
else { & powershell -NoProfile -ExecutionPolicy Bypass -File $installPs1.FullName }

Write-Host ''
Write-Host ('临时目录：' + $tmp)
Write-Host '安装结束。如果失败，请运行包里的 setup.cmd → 菜单选 3（诊断），把桌面生成的报告发给作者。'
