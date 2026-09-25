#requires -Version 5.1
<#
    一键准备 Android 打包环境 + 生成可安装的 APK
    ------------------------------------------------------------
    用法（在项目根目录）：
        powershell -ExecutionPolicy Bypass -File tools\setup_android_build.ps1

    可选参数：
        -ProxyUrl http://127.0.0.1:7897   手动指定代理（默认自动探测：环境变量 → 注册表 → 7897 端口）
        -FlutterVersion 3.32.8            指定 Flutter 版本（默认取官方最新 stable）
        -SkipDownload                     工具链已装好，只重新编译
        -SplitPerAbi                      按 CPU 架构拆分 APK（体积更小，但每个手机只能装对应的那个）
        -Release                          生成自己的签名密钥（而不是用 debug 签名）
        -KeystorePassword xxx             配合 -Release，非交互式指定密钥库口令
        -Sources official                 不用国内镜像，全部走官方源（默认 auto：镜像优先、失败回退官方）

    国内镜像（默认使用，实测快 20 倍以上）：
        Flutter  https://mirrors.cloud.tencent.com/flutter/...
        Gradle   https://mirrors.cloud.tencent.com/gradle/...
        JDK 17   https://mirrors.huaweicloud.com/openjdk/...
        Android cmdline-tools 无可用镜像，仍走 dl.google.com
#>
[CmdletBinding()]
param(
    [string]$ProxyUrl = '',
    [string]$FlutterVersion = '',
    [string]$Org = 'com.example',
    [string]$ProjectName = 'deepseek_chat',
    [switch]$SkipDownload,
    [switch]$SplitPerAbi,
    [switch]$Release,
    [string]$KeystorePassword = '',
    # auto = 优先国内镜像、失败回退官方源；official = 全部走官方源
    [ValidateSet('auto', 'official')]
    [string]$Sources = 'auto'
)

$UseOfficial = ($Sources -eq 'official')
$MirrorFlutterBase = 'https://mirrors.cloud.tencent.com'
$MirrorGradleBase = 'https://mirrors.cloud.tencent.com/gradle'
$MirrorJdkUrl = 'https://mirrors.huaweicloud.com/openjdk/17.0.2/openjdk-17.0.2_windows-x64_bin.zip'

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# 本文件是 UTF-8(带 BOM) 保存的，这里再声明一次，避免中文输出乱码
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

$ProjectRoot = Split-Path -Parent $PSScriptRoot      # tools\ 的上一级 = 项目根目录
$Toolchain   = Join-Path $ProjectRoot '.toolchain'
$Downloads   = Join-Path $Toolchain 'downloads'
$Downloader  = Join-Path $PSScriptRoot 'download.mjs'
$EnvFile     = Join-Path $PSScriptRoot 'env.generated.ps1'

$JDK_DIR     = Join-Path $Toolchain 'jdk17'
$FLUTTER_DIR = Join-Path $Toolchain 'flutter'
$SDK_DIR     = Join-Path $Toolchain 'android-sdk'

function Write-Step($n, $text) {
    Write-Host ''
    Write-Host ("=" * 72) -ForegroundColor DarkGray
    Write-Host ("[$n] $text") -ForegroundColor Cyan
    Write-Host ("=" * 72) -ForegroundColor DarkGray
}
function Write-Ok($text)   { Write-Host "  [OK] $text"   -ForegroundColor Green }
function Write-Info($text) { Write-Host "  [..] $text"   -ForegroundColor Gray }
function Write-Warn($text){ Write-Host "  [!!] $text"   -ForegroundColor Yellow }

function Fail($text) {
    Write-Host ''
    Write-Host "  [失败] $text" -ForegroundColor Red
    Write-Host ''
    exit 1
}

# ---------------------------------------------------------------- Node 检查
function Assert-Node {
    $node = Get-Command node -ErrorAction SilentlyContinue
    if (-not $node) { Fail '未找到 Node.js。请先安装 Node.js（https://nodejs.org）后重试；或改用 README 里的「手动编译」方式。' }
    $ver = (& node -v).TrimStart('v')
    $major = [int]($ver.Split('.')[0])
    if ($major -lt 16) { Fail "Node.js 版本过低（$ver），需要 16 以上。" }
    Write-Ok "Node.js $ver"
}

function Run {
    param([string]$Exe, [string[]]$Arguments, [string]$WorkDir = $ProjectRoot, [switch]$Quiet)
    if (-not $Quiet) {
        Write-Host "  > $Exe $($Arguments -join ' ')" -ForegroundColor DarkGray
    }
    Push-Location $WorkDir
    try {
        $all = @($Arguments)
        & $Exe @all
        $code = $LASTEXITCODE
    } finally {
        Pop-Location
    }
    if ($code -ne 0) { Fail "命令执行失败（退出码 $code）：$Exe $($Arguments -join ' ')" }
}

function Invoke-Native {
    <#
        安全地执行原生命令：
        flutter / gradle / sdkmanager 会把正常日志写到 stderr，
        而 PowerShell 5.1 在 $ErrorActionPreference='Stop' 时会把 stderr 当成终止错误。
        这里把 stderr 合并进 stdout，就不会误判失败。
    #>
    param([string]$Exe, [string[]]$Arguments = @())
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $out = & $Exe @Arguments 2>&1
        return @{ Output = @($out); ExitCode = $LASTEXITCODE }
    } finally {
        $ErrorActionPreference = $prev
    }
}
function Invoke-Download {
    param([string]$Url, [string]$Dest, [string]$Sha256 = '')
    if ($SkipDownload -and (Test-Path $Dest)) { Write-Ok "已存在，跳过下载：$Dest"; return }
    $dlArgs = @($Downloader, $Url, $Dest)
    if ($ProxyUrl) { $dlArgs += "--proxy=$ProxyUrl" }
    if ($Sha256)   { $dlArgs += "--sha256=$Sha256" }
    Write-Host "  > 下载 $Url" -ForegroundColor DarkGray
    # 注意：这里不用 Run（Run 失败会直接退出脚本），
    # 必须抛异常，调用方才能捕获并回退到备用源。
    & node @dlArgs
    if ($LASTEXITCODE -ne 0) {
        throw "下载失败（退出码 $LASTEXITCODE）：$Url"
    }
}

function Expand-Zip {
    param([string]$Zip, [string]$Dest)
    if (Test-Path $Dest) { Remove-Item $Dest -Recurse -Force }
    New-Item -ItemType Directory -Path $Dest -Force | Out-Null
    Write-Info "解压 $(Split-Path -Leaf $Zip) ..."
    # tar.exe 支持 zip；比 Expand-Archive 快很多，且不会因为长路径失败
    & tar.exe -xf $Zip -C $Dest
    if ($LASTEXITCODE -ne 0) {
        Write-Warn 'tar 解压失败，回退到 Expand-Archive（较慢，请耐心等）'
        Expand-Archive -LiteralPath $Zip -DestinationPath $Dest -Force
    }
}

# ================================================================ 0. 预检
Write-Host ''
Write-Host '  DeepSeek 助手 —— Android APK 一键打包' -ForegroundColor White
Write-Host "  项目目录：$ProjectRoot"

Write-Step 0 '环境预检'
Assert-Node

if (-not (Test-Path $Downloader)) { Fail "找不到下载器：$Downloader" }

if (-not $ProxyUrl) {
    foreach ($candidate in @($env:HTTPS_PROXY, $env:HTTP_PROXY, $env:ALL_PROXY)) {
        if ($candidate) { $ProxyUrl = $candidate; break }
    }
}
if (-not $ProxyUrl) {
    try {
        $reg = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction SilentlyContinue
        if ($reg.ProxyServer) {
            $s = $reg.ProxyServer
            if ($s -notmatch '://') { $s = "http://$s" }
            $ProxyUrl = $s
        }
    } catch { }
}
if (-not $ProxyUrl) {
    try {
        $t = Test-NetConnection -ComputerName 127.0.0.1 -Port 7897 -WarningAction SilentlyContinue
        if ($t.TcpTestSucceeded) { $ProxyUrl = 'http://127.0.0.1:7897' }
    } catch { }
}
if ($ProxyUrl) { Write-Ok "检测到代理：$ProxyUrl（直连失败时会自动走它）" }
else           { Write-Info '没有检测到代理，将全部直连下载' }

New-Item -ItemType Directory -Path $Downloads -Force | Out-Null

# 把 git 的全局配置重定向到工作区内并预先建好。
# 原因：部分受管环境（如 DSH 沙箱）不允许写用户目录下的 .gitconfig，
# flutter / gradle 内部调用 git 时会因为拿不到锁而失败。
$env:GIT_CONFIG_GLOBAL = Join-Path $Toolchain 'gitconfig'
if (-not (Test-Path $env:GIT_CONFIG_GLOBAL)) {
    Set-Content -LiteralPath $env:GIT_CONFIG_GLOBAL -Encoding ASCII `
        -Value "[safe]`n    directory = *`n"
    Write-Info "git 全局配置重定向到：$env:GIT_CONFIG_GLOBAL"
}

# ---------------------------------------------------------------- 路径重定向
# 两个必须处理的坑（都跟「用户名含中文」+「受管沙箱不允许写用户目录」有关）：
#
#  1) Flutter/Dart 把 %APPDATA% 按 Latin-1 解码，中文用户名会变成乱码路径，
#     于是报 "Flutter failed to write to ... C:\Users\渚畤楣廫AppData\Roaming\.flutter_tool_state"。
#  2) 很多受管环境不允许写用户目录。
#
# 所以把 APPDATA / LOCALAPPDATA / PUB_CACHE 全部改成工作区内的纯英文路径。
$ToolAppData   = Join-Path $Toolchain 'appdata'
$ToolLocalData = Join-Path $ToolAppData 'Local'
$ToolRoaming   = Join-Path $ToolAppData 'Roaming'
$PubCacheDir   = Join-Path $Toolchain 'pub-cache'
foreach ($d in @($ToolAppData, $ToolLocalData, $ToolRoaming, $PubCacheDir)) {
    New-Item -ItemType Directory -Path $d -Force | Out-Null
}
$env:APPDATA = $ToolRoaming
$env:LOCALAPPDATA = $ToolLocalData
$env:PUB_CACHE = $PubCacheDir
# 关掉匿名统计，少一次网络请求、也少一次写配置
$env:FLUTTER_SUPPRESS_ANALYTICS = 'true'
$env:CI = 'true'
Write-Info "APPDATA / PUB_CACHE 已重定向到工作区（中文用户名 + 只读用户目录的兼容处理）"

# 注意：这里刻意【不】给 flutter / gradle 设置 HTTP_PROXY、HTTPS_PROXY。
# 实测 Clash 等客户端的 TUN/透明代理模式下，直连本来就会走代理；
# 而把 7897 当成普通 HTTP 代理去访问任意 HTTPS 站点会超时，反而会弄坏网络。
# 只有 download.mjs 在直连失败时，才会回退到显式代理。

# ============================================================ 1. Flutter SDK
Write-Step 1 '准备 Flutter SDK'

$flutterExe = Join-Path $FLUTTER_DIR 'bin\flutter.bat'
if (Test-Path $flutterExe) {
    $probe = Invoke-Native $flutterExe @('--version')
    $flutterVerLine = ($probe.Output | Where-Object { $_ -match 'Flutter' } | Select-Object -First 1)
    Write-Ok "Flutter 已就绪：$flutterVerLine"
} else {
    $url = $null
    $ver = $FlutterVersion
    if (-not $ver) {
        Write-Info '查询官方最新 stable 版本 ...'
        $ver = (& node $Downloader '--latest-flutter-version').Trim()
        if ($LASTEXITCODE -ne 0 -or -not $ver) { Fail '查询 Flutter 版本失败，请检查网络/代理后用 -FlutterVersion 手动指定。' }
    }
    Write-Ok "目标版本：Flutter $ver"
    # 国内镜像实测比 storage.googleapis.com 快 20 倍以上；失败会自动回退官方源
    $zipName = "flutter_windows_$ver-stable.zip"
    $zip = Join-Path $Downloads $zipName
    $mirrorUrl = "$MirrorFlutterBase/flutter_infra_release/releases/stable/windows/$zipName"
    $officialUrl = "https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/$zipName"

    Write-Info '下载 Flutter SDK（约 1.8 GB，支持断点续传，中断后重跑本脚本会继续）...'
    try {
        Invoke-Download -Url $mirrorUrl -Dest $zip
    } catch {
        if ($UseOfficial) { throw }
        Write-Warn "镜像下载失败（$($_.Exception.Message)），改用官方源重试 ..."
        Invoke-Download -Url $officialUrl -Dest $zip
    }

    Write-Info '解压 Flutter SDK（约需 1~3 分钟）...'
    $stage = Join-Path $Toolchain '_stage_flutter'
    Expand-Zip -Zip $zip -Dest $stage
    # zip 内层目录名固定是 flutter
    $inner = Join-Path $stage 'flutter'
    if (-not (Test-Path $inner)) { Fail "解压结果不符合预期，未找到 $inner" }
    if (Test-Path $FLUTTER_DIR) { Remove-Item $FLUTTER_DIR -Recurse -Force }
    Move-Item $inner $FLUTTER_DIR
    Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
    Write-Ok "Flutter SDK -> $FLUTTER_DIR"

    # 把 git 的全局配置重定向到工作区内
    # （有些受管环境不允许写用户目录下的 .gitconfig，会让 flutter 调用的 git 报错）
    $env:GIT_CONFIG_GLOBAL = Join-Path $Toolchain 'gitconfig'
    if (-not (Test-Path $env:GIT_CONFIG_GLOBAL)) {
        Set-Content -LiteralPath $env:GIT_CONFIG_GLOBAL -Encoding ASCII `
            -Value "[safe]`n    directory = *`n"
    }
    # 兜底：能写就顺手把 Flutter 目录标成 safe.directory，写不进去也无所谓
    try {
        & git config --global --add safe.directory ($FLUTTER_DIR -replace '\\', '/') 2>$null | Out-Null
    } catch {
        Write-Info '[!] 无法写入用户级 .gitconfig（已改用工作区内的 git 配置，不影响编译）'
    }
}

$env:Path = "$(Join-Path $FLUTTER_DIR 'bin');$env:Path"

# ================================================================ 2. JDK 17
Write-Step 2 '准备 JDK 17（Android Gradle Plugin 8.x 要求 17）'

$javaHome = $null
$existing = @(
    "$env:ProgramFiles\Eclipse Adoptium",
    "$env:ProgramFiles\Java",
    "$env:ProgramFiles\Microsoft",
    "$env:USERPROFILE\.jdks"
) | Where-Object { Test-Path $_ } | ForEach-Object {
    Get-ChildItem $_ -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match 'jdk-?17|jdk17|jdk-17' } |
        Select-Object -First 1 -ExpandProperty FullName
} | Where-Object { $_ } | Select-Object -First 1

if ($existing) {
    $javaHome = $existing
    Write-Ok "使用系统已安装的 JDK：$javaHome"
} else {
    $javaExe = Join-Path $JDK_DIR 'bin\java.exe'
    if (-not (Test-Path $javaExe)) {
        $jdkZip = Join-Path $Downloads 'jdk17.zip'
        # 华为云镜像（实测 1.8 MB/s）→ 失败回退官方 Temurin
        $jdkOfficial = 'https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.13%2B11/OpenJDK17U-jdk_x64_windows_hotspot_17.0.13_11.zip'
        Write-Info '下载 JDK 17（约 180 MB）...'
        if ($UseOfficial) {
            Invoke-Download -Url $jdkOfficial -Dest $jdkZip
        } else {
            try {
                Invoke-Download -Url $MirrorJdkUrl -Dest $jdkZip
            } catch {
                Write-Warn "JDK 镜像下载失败（$($_.Exception.Message)），改用官方源重试 ..."
                if (Test-Path $jdkZip) { Remove-Item $jdkZip -Force }
                Invoke-Download -Url $jdkOfficial -Dest $jdkZip
            }
        }
        Write-Info '解压 JDK ...'
        Expand-Zip -Zip $jdkZip -Dest $JDK_DIR
        # 有些发行包内层还套一层目录（jdk-17.0.13+11 / jdk-17.0.2），把它提升成 $JDK_DIR 本身
        $sub = Get-ChildItem $JDK_DIR -Directory | Select-Object -First 1
        if ($sub -and -not (Test-Path (Join-Path $JDK_DIR 'bin\java.exe'))) {
            Get-ChildItem $sub.FullName -Force | Move-Item -Destination $JDK_DIR -Force
            Remove-Item $sub.FullName -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    $javaHome = $JDK_DIR
    Write-Ok "JDK 17 -> $JDK_DIR"
}

if (-not (Test-Path (Join-Path $javaHome 'bin\java.exe'))) { Fail "JDK 不完整：$javaHome" }
$env:JAVA_HOME = $javaHome
$env:Path = "$(Join-Path $javaHome 'bin');$env:Path"
    $javaProbe = Invoke-Native (Join-Path $javaHome 'bin\java.exe') @('-version')
$javaVersion = ($javaProbe.Output | Select-Object -First 1)
Write-Ok "$javaVersion"

# =========================================================== 3. Android SDK
Write-Step 3 '准备 Android SDK（cmdline-tools + platform-tools + platform 35 + build-tools 35）'

$sdkManager = Join-Path $SDK_DIR 'cmdline-tools\latest\bin\sdkmanager.bat'
if (-not (Test-Path $sdkManager)) {
    $cmdZip = Join-Path $Downloads 'commandlinetools-win.zip'
    $cmdUrl = 'https://dl.google.com/android/repository/commandlinetools-win-11076708_latest.zip'
    Write-Info '下载 Android 命令行工具（约 130 MB）...'
    Invoke-Download -Url $cmdUrl -Dest $cmdZip

    $tmp = Join-Path $Toolchain '_stage_cmdtools'
    Expand-Zip -Zip $cmdZip -Dest $tmp
    # 官方 zip 内层是 cmdline-tools/，必须重命名成 latest 才能被识别
    $latest = Join-Path $SDK_DIR 'cmdline-tools\latest'
    New-Item -ItemType Directory -Path $latest -Force | Out-Null
    Get-ChildItem (Join-Path $tmp 'cmdline-tools') -Force |
        Move-Item -Destination $latest -Force
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    Write-Ok "cmdline-tools -> $latest"
}

$env:ANDROID_HOME = $SDK_DIR
$env:ANDROID_SDK_ROOT = $SDK_DIR

# licenses 目录要预先建好，然后非交互接受全部许可
$licenses = Join-Path $SDK_DIR 'licenses'
New-Item -ItemType Directory -Path $licenses -Force | Out-Null

Write-Info '接受 Android SDK 许可协议 ...'
$yes = ("y`r`n" * 60)
$yes | & $sdkManager --sdk_root="$SDK_DIR" --licenses 2>&1 | Out-Null

Write-Info '安装 SDK 组件（platform-tools / platform 35 / build-tools 35.0.0，约 700 MB）...'
& $sdkManager --sdk_root="$SDK_DIR" 'platform-tools' 'platforms;android-35' 'build-tools;35.0.0' 2>&1 |
    Where-Object { $_ -notmatch '^\s*$' } | ForEach-Object { Write-Host "     $_" -ForegroundColor DarkGray }
Write-Ok 'Android SDK 组件安装完成'

$env:Path = "$(Join-Path $SDK_DIR 'platform-tools');$env:Path"

# ------------------------------------------------- 让 Flutter 知道这些路径
Write-Info '配置 Flutter 使用上面装的 JDK / Android SDK ...'
& $flutterExe config --android-sdk "$SDK_DIR" 2>&1 | Out-Null
& $flutterExe config --jdk-dir "$javaHome" 2>&1 | Out-Null
& $flutterExe config --no-analytics 2>&1 | Out-Null
Write-Ok 'flutter config 完成'

# ====================================================== 4. 补齐原生工程文件
Write-Step 4 '补齐 Android / iOS 原生工程文件（flutter create .）'

$manifest = Join-Path $ProjectRoot 'android\app\src\main\AndroidManifest.xml'
$backup = Join-Path $Toolchain 'backup_native'
New-Item -ItemType Directory -Path $backup -Force | Out-Null
if (Test-Path $manifest) {
    New-Item -ItemType Directory -Path (Join-Path $backup 'app\src\main') -Force | Out-Null
    Copy-Item $manifest (Join-Path $backup 'app\src\main\AndroidManifest.xml') -Force
    Write-Info '已备份现有 AndroidManifest.xml'
}

# 不要加 --overwrite！它会用模板覆盖 lib\main.dart / pubspec.yaml / test\widget_test.dart，
# 实测会导致打出来的 APK 是个计数器 Demo。不带时 flutter create 只补缺失文件。
Run $flutterExe @('create', '.', '--platforms=android', '--org', $Org, '--project-name', $ProjectName) $ProjectRoot

# flutter create 会用模板覆盖 manifest，这里把我们的版本（带 INTERNET 权限）恢复回去
# 额外保护：flutter create 可能覆盖 main.dart / pubspec.yaml / widget_test.dart
foreach ($pf in @('lib\main.dart', 'pubspec.yaml', 'test\widget_test.dart')) {
    $cur = Join-Path $ProjectRoot $pf
    $bak = Join-Path $Toolchain "protected_backup\$pf"
    if (Test-Path $cur) {
        New-Item -ItemType Directory -Path (Split-Path $bak -Parent) -Force | Out-Null
        Copy-Item $cur $bak -Force
    }
}
if (Test-Path (Join-Path $backup 'app\src\main\AndroidManifest.xml')) {
    Copy-Item (Join-Path $backup 'app\src\main\AndroidManifest.xml') $manifest -Force
    Write-Ok '已恢复自定义 AndroidManifest.xml（含 INTERNET 权限）'
}
# 还原被覆盖的文件
foreach ($pf in @('lib\main.dart', 'pubspec.yaml', 'test\widget_test.dart')) {
    $bak = Join-Path $Toolchain "protected_backup\$pf"
    if (Test-Path $bak) { Copy-Item $bak (Join-Path $ProjectRoot $pf) -Force }
}
$manifestText = Get-Content $manifest -Raw
if ($manifestText -notmatch 'android.permission.INTERNET') {
    Write-Warn 'Manifest 里没有 INTERNET 权限，正在补上 ...'
    $patched = $manifestText -replace '(<manifest[^>]*>)', "`$1`r`n    <uses-permission android:name=""android.permission.INTERNET"" />"
    Set-Content -LiteralPath $manifest -Value $patched -Encoding UTF8
}
Write-Ok 'Android 工程文件就绪'

# ============================================================ 5. 依赖与缓存
Write-Step 5 '拉取 Dart 依赖 + 预热构建缓存'

Run $flutterExe @('pub', 'get') $ProjectRoot
Write-Info 'precache（下载 Android 引擎产物，约 300~600 MB，第一次比较慢）...'
Run $flutterExe @('precache', '--android') $ProjectRoot

# ======================================================= 6. 预下载 Gradle 包
Write-Step 6 '预下载 Gradle 发行包（避免编译时再去网上拉）'

$wrapperProps = Join-Path $ProjectRoot 'android\gradle\wrapper\gradle-wrapper.properties'
if (Test-Path $wrapperProps) {
    $props = Get-Content $wrapperProps -Raw
    if ($props -match 'gradle-([\d\.]+)-all\.zip') {
        $gver = $Matches[1]
        $gradleZip = Join-Path $Downloads "gradle-$gver-all.zip"
        $gradleOfficial = "https://services.gradle.org/distributions/gradle-$gver-all.zip"
        $gradleMirror = "$MirrorGradleBase/gradle-$gver-all.zip"
        Write-Info "Gradle $gver（约 220 MB）..."
        if ($UseOfficial) {
            Invoke-Download -Url $gradleOfficial -Dest $gradleZip
        } else {
            try {
                Invoke-Download -Url $gradleMirror -Dest $gradleZip
            } catch {
                Write-Warn "Gradle 镜像下载失败（$($_.Exception.Message)），改用官方源重试 ..."
                if (Test-Path $gradleZip) { Remove-Item $gradleZip -Force }
                Invoke-Download -Url $gradleOfficial -Dest $gradleZip
            }
        }
        $env:GRADLE_PREDOWNLOADED = $gradleZip
    } else {
        Write-Warn '没解析出 Gradle 版本，编译时由 wrapper 自行下载'
    }
} else {
    Write-Warn "找不到 $wrapperProps"
}

# ================================================================ 7. 签名
Write-Step 7 '配置签名'

$keyProps = Join-Path $ProjectRoot 'android\key.properties'
$appGradle = Join-Path $ProjectRoot 'android\app\build.gradle.kts'

function New-Keystore {
    $ks = Join-Path $ProjectRoot 'android\app\deepseek-release.jks'
    if (Test-Path $ks) { Write-Ok "密钥库已存在：$ks"; return $ks }
    if (-not $KeystorePassword) {
        $KeystorePassword = Read-Host '  请输入要设置的密钥库口令（至少 6 位，记牢，以后更新 App 要用）'
    }
    if ($KeystorePassword.Length -lt 6) { Fail '口令太短，至少 6 位。' }
    Write-Info '生成签名密钥（有效期 10000 天）...'
    & keytool -genkeypair -v `
        -keystore $ks `
        -storetype JKS `
        -keyalg RSA -keysize 2048 -validity 10000 `
        -alias deepseek `
        -storepass $KeystorePassword -keypass $KeystorePassword `
        -dname "CN=DeepSeek Chat, OU=Mobile, O=Personal, L=Beijing, S=Beijing, C=CN" 2>&1 |
        ForEach-Object { Write-Host "     $_" -ForegroundColor DarkGray }
    if ($LASTEXITCODE -ne 0) { Fail '生成密钥库失败' }
    Write-Ok "密钥库 -> $ks"
    return $ks
}

if ($Release) {
    $ks = New-Keystore
    $rel = @"
storePassword=$KeystorePassword
keyPassword=$KeystorePassword
keyAlias=deepseek
storeFile=deepseek-release.jks
"@
    Set-Content -LiteralPath $keyProps -Value $rel -Encoding ASCII
    Write-Ok "android/key.properties 已写入（注意：这个文件不要提交到 git）"

    # 把 build.gradle.kts 里的 release 签名从 debug 换成 key.properties
    $gradleText = Get-Content $appGradle -Raw
    if ($gradleText -notmatch 'keystoreProperties') {
        $gradleText = $gradleText -replace '(?m)^(android \{)', @'
// 读取 android/key.properties 里的签名配置（不存在时自动回退到 debug 签名）
val keystoreProperties = java.util.Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

android {
'@
        $gradleText = $gradleText -replace '(?m)^(\s*)buildTypes \{', @'
    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
'@
        $gradleText = $gradleText -replace 'signingConfig = signingConfigs\.getByName\("debug"\)', 'signingConfig = if (keystorePropertiesFile.exists()) signingConfigs.getByName("release") else signingConfigs.getByName("debug")'
        Set-Content -LiteralPath $appGradle -Value $gradleText -Encoding UTF8
        Write-Ok 'build.gradle.kts 已改为使用 release 签名'
    } else {
        Write-Ok 'build.gradle.kts 已经配置过 release 签名'
    }
} else {
    Write-Info '使用 debug 签名生成 release APK（可以正常安装到手机；'
    Write-Info '  想用自己的密钥签名，请重跑并加上 -Release 参数）'
}

# ================================================================ 8. 编译
Write-Step 8 '编译 release APK（第一次会比较久，5~20 分钟）'

$env:GRADLE_USER_HOME = Join-Path $Toolchain 'gradle-home'
New-Item -ItemType Directory -Path $env:GRADLE_USER_HOME -Force | Out-Null

$buildArgs = @('build', 'apk', '--release')
if ($SplitPerAbi) { $buildArgs += '--split-per-abi' }
Run $flutterExe $buildArgs $ProjectRoot

# ================================================================ 9. 收集产物
Write-Step 9 '收集安装包'

$apkDir = Join-Path $ProjectRoot 'build\app\outputs\flutter-apk'
$dist = Join-Path $ProjectRoot 'dist'
New-Item -ItemType Directory -Path $dist -Force | Out-Null

$version = '1.0.0'
$pubspec = Join-Path $ProjectRoot 'pubspec.yaml'
if (Test-Path $pubspec) {
    $m = [regex]::Match((Get-Content $pubspec -Raw), '(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+)')
    if ($m.Success) { $version = $m.Groups[1].Value }
}

$apks = Get-ChildItem $apkDir -Filter '*.apk' -ErrorAction SilentlyContinue
if (-not $apks) { Fail "没有找到 APK，请检查上面的编译日志：$apkDir" }

foreach ($apk in $apks) {
    $suffix = if ($apk.Name -match 'arm64') { '-arm64-v8a' }
              elseif ($apk.Name -match 'armeabi') { '-armeabi-v7a' }
              elseif ($apk.Name -match 'x86') { '-x86_64' }
              else { '' }
    $target = Join-Path $dist "deepseek-chat-v$version$suffix.apk"
    Copy-Item $apk.FullName $target -Force
    Write-Ok "$target  ($([math]::Round($apk.Length/1MB,1)) MB)"
}

# ================================================================== 收尾
Write-Host ''
Write-Host ("=" * 72) -ForegroundColor Green
Write-Host '  打包完成！' -ForegroundColor Green
Write-Host ("=" * 72) -ForegroundColor Green
Write-Host ''
Write-Host "  APK 位置：$dist" -ForegroundColor White
Write-Host ''
Write-Host '  安装到手机（三种任选）：' -ForegroundColor White
Write-Host '    1) USB：手机开「USB 调试」，然后执行'
Write-Host "         adb install -r `"$dist\deepseek-chat-v$version.apk`""
Write-Host '    2) 微信/QQ/网盘：把 APK 发到手机，点击安装（需允许「安装未知来源应用」）'
Write-Host '    3) 数据线：直接拷到手机存储，用文件管理器打开'
Write-Host ''
Write-Host '  以后只改了 Dart 代码要重新出包，直接运行：' -ForegroundColor White
Write-Host '         powershell -ExecutionPolicy Bypass -File tools\build_apk.ps1'
Write-Host ''
