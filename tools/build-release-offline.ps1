param([string]$ToolRoot = 'C:\dsbuild')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $projectRoot
$flutter = Join-Path $ToolRoot 'flutter/bin/flutter.bat'
$env:PUB_CACHE = Join-Path $ToolRoot 'pub-cache'
$env:GRADLE_USER_HOME = Join-Path $ToolRoot 'gradle-home'
$env:JAVA_HOME = Join-Path $ToolRoot 'jdk17'
$env:ANDROID_HOME = Join-Path $ToolRoot 'android-sdk'
$env:DS_OFFLINE_BUILD = 'true'
$env:FLUTTER_SUPPRESS_ANALYTICS = 'true'
foreach ($required in @($flutter, $env:PUB_CACHE, $env:GRADLE_USER_HOME, $env:JAVA_HOME, $env:ANDROID_HOME)) {
    if (!(Test-Path -LiteralPath $required)) { throw "缺少本地工具或缓存：$required；本脚本不会自动下载。" }
}
& $flutter pub get --offline
if ($LASTEXITCODE -ne 0) { throw '离线依赖解析失败' }
& $flutter analyze --no-pub
if ($LASTEXITCODE -ne 0) { throw '静态分析失败' }
& $flutter test --no-pub
if ($LASTEXITCODE -ne 0) { throw '回归测试失败' }
& $flutter build apk --release --no-pub
if ($LASTEXITCODE -ne 0) { throw 'APK 构建失败' }
$apk = Join-Path $projectRoot 'build/app/outputs/flutter-apk/app-release.apk'
$java = Join-Path $env:JAVA_HOME 'bin/java.exe'
$signer = Join-Path $env:ANDROID_HOME 'build-tools/36.0.0/lib/apksigner.jar'
$certificate = & $java -jar $signer verify --print-certs $apk
if ($LASTEXITCODE -ne 0 -or ($certificate -join "`n") -notmatch '566bba04384837a3d4903ce70281374412d516c74a1f3275d7ec27d34f87cbc1') {
    throw '签名与 v1.1.6 不一致，停止发布以避免覆盖升级失败。请使用原有签名环境。'
}
New-Item -ItemType Directory -Path (Join-Path $projectRoot 'dist') -Force | Out-Null
$output = Join-Path $projectRoot 'dist/deepseek-chat-v1.1.7.apk'
Copy-Item -LiteralPath $apk -Destination $output -Force
Get-FileHash -LiteralPath $output -Algorithm SHA256
Write-Output "构建与校验完成：$output"
