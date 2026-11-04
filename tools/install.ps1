#Requires -Version 5.1
<#
  dsh-boot-suite —— 旧路径兼容垫片（过渡期用，下个版本删除）

  为什么保留这个文件：
    2.16.10 及以前的自动更新器和桌面「升级到…」助手，把安装器路径写死成 tools\install.ps1：
    更新时先检查新 zip 里有没有这个文件，然后再运行它。2.16.11 仓库整理把 Windows
    安装器搬到了 tools\windows\install.ps1；如果这里直接删掉，老用户点「检查更新」就会
    报「安装包缺少必需文件」，升级链直接断掉。

    所以保留一个只做转发的垫片：
      · 自己不含任何安装逻辑，只把参数原样交给 tools\windows\install.ps1；
      · 退出码原样带回（旧更新器/回滚助手就是靠退出码判断成败的）。
    下个版本（2.16.12）删除本文件：等确认没有用户还在跨重排版升级后，旧引用自然消失。

  用法（与旧版完全相同）：
    powershell -NoProfile -ExecutionPolicy Bypass -File tools\install.ps1 [-CheckOnly] [-Force] [-Profiles desktop,web]
#>
[CmdletBinding()]
param(
  [switch]$CheckOnly,
  [switch]$Force,
  [string[]]$Profiles
)

$ErrorActionPreference = 'Stop'

# 新版安装器的真实位置：本文件在仓库根的 tools\ 下，所以往下走一层 windows\。
$target = Join-Path (Join-Path $PSScriptRoot 'windows') 'install.ps1'
if (-not (Test-Path $target)) {
  Write-Host ('[x] 找不到新版安装器：' + $target) -ForegroundColor Red
  Write-Host '    压缩包可能不完整，请重新下载完整包后重试。'
  exit 1
}

# 参数用 $PSBoundParameters 原样转发：里面只有调用方真正传了的开关，参数名和旧版签名一致；
# 未知参数会在参数绑定阶段直接报错，不会被悄悄吞掉（旧版也是这个行为）。
# 退出码：用 & 在当前进程里跑，新版安装器自己的 exit 1 会直接成为本垫片的退出码；
# 成功跑完则落到下面的 exit 0 —— 旧更新器/回滚助手就是靠这个退出码判断成败的。
& $target @PSBoundParameters
exit 0
