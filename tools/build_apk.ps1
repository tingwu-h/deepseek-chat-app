#requires -Version 5.1
<#
    重新编译 APK（工具链已经用 setup_android_build.ps1 装好之后使用）

    用法：
        powershell -ExecutionPolicy Bypass -File tools\build_apk.ps1
        powershell -ExecutionPolicy Bypass -File tools\build_apk.ps1 -SplitPerAbi
        powershell -ExecutionPolicy Bypass -File tools\build_apk.ps1 -Clean
#>
[CmdletBinding()]
param(
    [switch]$SplitPerAbi,
    [string]$FlutterVersion = '',
    [string]$ProxyUrl = '',
    [switch]$Clean
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$Setup = Join-Path $PSScriptRoot 'setup_android_build.ps1'

if ($Clean) {
    $buildDir = Join-Path $ProjectRoot 'build'
    if (Test-Path $buildDir) {
        Write-Host "清理 $buildDir ..." -ForegroundColor Yellow
        Remove-Item $buildDir -Recurse -Force
    }
}

$forward = @('-SkipDownload')
if ($SplitPerAbi)      { $forward += '-SplitPerAbi' }
if ($FlutterVersion)   { $forward += @('-FlutterVersion', $FlutterVersion) }
if ($ProxyUrl)         { $forward += @('-ProxyUrl', $ProxyUrl) }

Write-Host '重新编译中（只跑编译这一步，工具链复用 .toolchain 目录）...' -ForegroundColor Cyan

& powershell -NoProfile -ExecutionPolicy Bypass -File $Setup @forward
exit $LASTEXITCODE
