#requires -Version 5.1
<#
    ASCII 路径构建方案（专治「路径含中文」+「flutter 每次启动 git fetch github 卡住」）

    背景（实测结论）：
      1. 本机路径含中文：C:\Users\侯宇鹏\deepseek移动端
         实测：Dart 写文件没问题，但在中文路径下 spawn 子进程会被沙箱拒绝
               （CreateFile failed 5 / ERROR_ACCESS_DENIED）
      2. flutter 每次启动都会 git fetch --tags 去连 github.com
         实测：连不上时等 21 秒失败，命令退出码 128，会让工具链反复重建、看起来像卡死

    本脚本做的事：
      - 在 C:\dsbuild（纯 ASCII）准备一套完整构建环境
      - 从已下载的包里解压 JDK / Android SDK，不重新下载
      - 复制项目源码到 C:\dsbuild\deepseek_chat（纯英文路径）
      - 关掉 flutter 的版本检查，避免 git fetch github
      - 跑 flutter build apk --release
      - 把 APK 复制回原项目的 dist\ 目录（中文路径下只做文件拷贝，不 spawn 构建进程）

    用法（该脚本位于项目目录，会自动提权前的环境准备）：
        powershell -ExecutionPolicy Bypass -File tools\ascii_build.ps1
#>
[CmdletBinding()]
param(
    # 构建根目录必须是不含中文的纯英文路径。
    # 默认放在 C:\dsbuild（本机已验证可用），可用 -BuildRoot 指定别处。
    [string]$BuildRoot = 'C:\dsbuild',
    [switch]$SkipCopy
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$Toolchain   = Join-Path $ProjectRoot '.toolchain'
$Downloads   = Join-Path $Toolchain 'downloads'

function Say($msg, $color = 'Gray') { Write-Host "  $msg" -ForegroundColor $color }
function Step($n, $t) {
    Write-Host ''
    Write-Host ("=" * 70) -ForegroundColor DarkGray
    Write-Host "[$n] $t" -ForegroundColor Cyan
    Write-Host ("=" * 70) -ForegroundColor DarkGray
}
function Die($m) { Write-Host "`n  [失败] $m" -ForegroundColor Red; exit 1 }

# ---------------------------------------------------------------- 重要
# java -version / sdkmanager / flutter / git 这些原生命令都会把正常信息写到 stderr，
# 而 $ErrorActionPreference='Stop' 会把「stderr 有输出」误判成致命错误直接中断脚本。
# 所以从这里开始统一切成 'Continue'，失败与否一律用 $LASTEXITCODE 判断。
$ErrorActionPreference = 'Continue'

# ============================================================ 0. 前置检查
Step 0 '前置检查'

if ($BuildRoot -match '[^\x00-\x7F]') { Die "BuildRoot 必须是不含中文的纯英文路径：$BuildRoot" }
$bf = Join-Path $BuildRoot 'flutter\bin\flutter.bat'
if (-not (Test-Path $bf)) { Die "找不到 $bf，请先执行昨晚的对照实验复制步骤（robocopy）" }
Say "Flutter SDK: $BuildRoot\flutter" Green

$jdkZip = Join-Path $Downloads 'jdk17.zip'
$cmdZip = Join-Path $Downloads 'commandlinetools-win.zip'
$fltZip = Join-Path $Downloads 'flutter_windows_3.47.5-stable.zip'

# 这些安装包只在「需要解压」时才有用；工具链已经装好的话，缺了也没关系
# （清理时删掉 .toolchain\downloads 就是这种情况），所以只提示不报错。
$jdkReady = Test-Path (Join-Path $BuildRoot 'jdk17\bin\java.exe')
$cmdReady = Test-Path (Join-Path $BuildRoot 'android-sdk\cmdline-tools\latest\bin\sdkmanager.bat')
if (-not (Test-Path $jdkZip) -and -not $jdkReady) { Die "缺少 $jdkZip，且 $BuildRoot 下没有可用的 JDK" }
if (-not (Test-Path $cmdZip) -and -not $cmdReady) { Die "缺少 $cmdZip，且 $BuildRoot 下没有可用的 Android cmdline-tools" }
if ((Test-Path $jdkZip) -and (Test-Path $cmdZip)) {
    Say '下载包齐全' Green
} else {
    Say '安装包已清理，但工具链已就绪，直接复用' Green
}

# ====================================================== 1. 构建根目录/环境变量
Step 1 "准备 $BuildRoot 下的纯英文环境"

$AppRoaming = Join-Path $BuildRoot 'appdata\Roaming'
$AppLocal   = Join-Path $BuildRoot 'appdata\Local'
$PubCache   = Join-Path $BuildRoot 'pub-cache'
$GradleHome = Join-Path $BuildRoot 'gradle-home'
$JdkDir     = Join-Path $BuildRoot 'jdk17'
$SdkDir     = Join-Path $BuildRoot 'android-sdk'
foreach ($d in @($AppRoaming, $AppLocal, $PubCache, $GradleHome, $SdkDir)) {
    New-Item -ItemType Directory -Path $d -Force | Out-Null
}

$GitConfig = Join-Path $BuildRoot 'gitconfig'
Set-Content -LiteralPath $GitConfig -Encoding ASCII -Value "[safe]`n    directory = *`n"

$env:APPDATA = $AppRoaming
$env:LOCALAPPDATA = $AppLocal
$env:PUB_CACHE = $PubCache
$env:GRADLE_USER_HOME = $GradleHome
$env:GIT_CONFIG_GLOBAL = $GitConfig
$env:FLUTTER_SUPPRESS_ANALYTICS = 'true'
Say "APPDATA / LOCALAPPDATA / PUB_CACHE / GRADLE_USER_HOME 全部指向 $BuildRoot" Green

# ============================================================== 2. 解压 JDK 17
Step 2 '解压 JDK 17（纯英文路径）'

if (-not (Test-Path (Join-Path $JdkDir 'bin\java.exe'))) {
    Say '解压 jdk17.zip ...'
    if (Test-Path $JdkDir) { Remove-Item $JdkDir -Recurse -Force }
    New-Item -ItemType Directory -Path $JdkDir -Force | Out-Null
    & tar.exe -xf $jdkZip -C $JdkDir
    if ($LASTEXITCODE -ne 0) { Die 'JDK 解压失败' }
    # zip 内层是 jdk-17.0.2/，提升一层
    $sub = Get-ChildItem $JdkDir -Directory | Select-Object -First 1
    if ($sub -and -not (Test-Path (Join-Path $JdkDir 'bin\java.exe'))) {
        Get-ChildItem $sub.FullName -Force | Move-Item -Destination $JdkDir -Force
        Remove-Item $sub.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }
} else { Say 'JDK 已解压，跳过' }

if (-not (Test-Path (Join-Path $JdkDir 'bin\java.exe'))) { Die "JDK 不完整：$JdkDir" }
$env:JAVA_HOME = $JdkDir
$env:Path = "$(Join-Path $JdkDir 'bin');$env:Path"
Say "java: $(& (Join-Path $JdkDir 'bin\java.exe') -version 2>&1 | Select-Object -First 1)" Green

# ======================================================== 3. 解压 Android SDK
Step 3 '解压 Android cmdline-tools（纯英文路径）'

$sdkManager = Join-Path $SdkDir 'cmdline-tools\latest\bin\sdkmanager.bat'
if (-not (Test-Path $sdkManager)) {
    $tmp = Join-Path $BuildRoot '_stage_cmd'
    if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    & tar.exe -xf $cmdZip -C $tmp
    $latest = Join-Path $SdkDir 'cmdline-tools\latest'
    New-Item -ItemType Directory -Path $latest -Force | Out-Null
    Get-ChildItem (Join-Path $tmp 'cmdline-tools') -Force | Move-Item -Destination $latest -Force
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
if (-not (Test-Path $sdkManager)) { Die "sdkmanager 不存在：$sdkManager" }
Say "sdkmanager: $sdkManager" Green

$env:ANDROID_HOME = $SdkDir
$env:ANDROID_SDK_ROOT = $SdkDir

$needInstall = -not (Test-Path (Join-Path $SdkDir 'platforms\android-35')) -or
               -not (Test-Path (Join-Path $SdkDir 'build-tools\35.0.0')) -or
               -not (Test-Path (Join-Path $SdkDir 'platform-tools\adb.exe'))
if ($needInstall) {
    Say '安装 SDK 组件（需要联网，约 700MB；实测 dl.google.com 1.5MB/s）...' Yellow
    New-Item -ItemType Directory -Path (Join-Path $SdkDir 'licenses') -Force | Out-Null
    ("y`r`n" * 60) | & $sdkManager --sdk_root="$SdkDir" --licenses 2>&1 | Out-Null
    & $sdkManager --sdk_root="$SdkDir" 'platform-tools' 'platforms;android-35' 'build-tools;35.0.0' 2>&1 |
        ForEach-Object { if ($_ -notmatch '^\s*$') { Write-Host "     $_" -ForegroundColor DarkGray } }
} else { Say 'SDK 组件已就绪，跳过' }
$env:Path = "$(Join-Path $SdkDir 'platform-tools');$env:Path"

# ============================================================ 4. 复制项目源码
Step 4 "复制项目源码到 $BuildRoot\deepseek_chat"

$BuildProject = Join-Path $BuildRoot 'deepseek_chat'
if (-not $SkipCopy) {
    foreach ($item in @('lib', 'test', 'pubspec.yaml', 'analysis_options.yaml', 'android', 'ios')) {
        $src = Join-Path $ProjectRoot $item
        if (-not (Test-Path $src)) { continue }
        $dst = Join-Path $BuildProject $item
        if (Test-Path $dst) {
            if ((Get-Item $dst).PSIsContainer) { Remove-Item $dst -Recurse -Force }
            else { Remove-Item $dst -Force }
        }
        Copy-Item $src $dst -Recurse -Force
    }
    Say '源码已复制（lib / test / pubspec / android / ios）' Green
} else { Say '跳过复制（-SkipCopy）' }

if (-not (Test-Path (Join-Path $BuildProject 'pubspec.yaml'))) { Die "项目复制失败：$BuildProject" }

# 清掉从中文路径带过来的构建产物，避免路径残留
foreach ($junk in @('build', '.dart_tool', '.flutter-plugins', '.flutter-plugins-dependencies')) {
    $p = Join-Path $BuildProject $junk
    if (Test-Path $p) { Remove-Item $p -Recurse -Force -ErrorAction SilentlyContinue }
}

# ============================================== 5. 关掉 flutter 的版本检查
Step 5 '关闭 flutter 版本检查（避免 git fetch github 卡住）'

$flSettings = Join-Path $AppRoaming '.flutter_settings'
Set-Content -LiteralPath $flSettings -Encoding UTF8 -Value '{"no-version-check":true}'
Say "已写入 $flSettings" Green
Say '（这就是卡点：flutter 每次启动都 git fetch --tags 连 github，连不上等 21 秒后失败）' Yellow

# ============================================================== 6. 配置 flutter
Step 6 'flutter create 补齐原生工程 + pub get'

Push-Location $BuildProject
try {
    & $bf config --android-sdk "$SdkDir" --no-analytics 2>&1 | Out-Null
    & $bf config --jdk-dir "$JdkDir" 2>&1 | Out-Null
    Say 'flutter config 完成'

    # 备份所有可能被 flutter create 覆盖的文件（含清单、入口、依赖、测试）
    $manifest = Join-Path $BuildProject 'android\app\src\main\AndroidManifest.xml'
    $protectDir = Join-Path $BuildRoot 'protected'
    if (Test-Path $protectDir) { Remove-Item $protectDir -Recurse -Force }
    New-Item -ItemType Directory -Path $protectDir -Force | Out-Null
    $protectList = @(
        'android\app\src\main\AndroidManifest.xml',
        'lib\main.dart',
        'pubspec.yaml',
        'test\widget_test.dart',
        'analysis_options.yaml'
    )
    foreach ($pf in $protectList) {
        $s = Join-Path $BuildProject $pf
        if (Test-Path $s) {
            $d = Join-Path $protectDir $pf
            New-Item -ItemType Directory -Path (Split-Path $d -Parent) -Force | Out-Null
            Copy-Item $s $d -Force
        }
    }
    Say "已备份 $($protectList.Count) 个易被模板覆盖的文件"

    Say 'flutter create ...'
    # 注意：绝对不要加 --overwrite！
    # 它会用模板覆盖 lib\main.dart、pubspec.yaml、test\widget_test.dart（我们已实测踩过这个坑，
    # 结果打出来的 APK 是个计数器 Demo）。不带时 flutter create 只会「创建缺失文件」，
    # 已存在的文件会显示 (skipped)，正是我们想要的。
    & $bf create . --platforms=android --org com.example --project-name deepseek_chat
    if ($LASTEXITCODE -ne 0) { Die 'flutter create 失败' }

    # 把备份整体还原回去（这是防止打出 Demo APK 的关键一步）
    foreach ($pf in $protectList) {
        $s = Join-Path $protectDir $pf
        if (Test-Path $s) {
            $d = Join-Path $BuildProject $pf
            New-Item -ItemType Directory -Path (Split-Path $d -Parent) -Force | Out-Null
            Copy-Item $s $d -Force
        }
    }
    Say '已还原被 flutter create 覆盖的文件' Green

    # 硬校验：确认还原后确实是我们的应用，否则直接失败（避免又打出 Demo）
    $mainTxt = Get-Content (Join-Path $BuildProject 'lib\main.dart') -Raw
    $pubTxt = Get-Content (Join-Path $BuildProject 'pubspec.yaml') -Raw
    if ($mainTxt -notmatch 'DeepSeekChatApp') { Die 'lib\main.dart 不是我们的代码（疑似被模板覆盖），拒绝继续编译' }
    if ($pubTxt -notmatch 'provider:' -or $pubTxt -notmatch 'flutter_markdown:') { Die 'pubspec.yaml 缺少我们的依赖，拒绝继续编译' }
    Say '校验通过：lib/main.dart 与 pubspec.yaml 都是本项目代码' Green
    $mt = Get-Content $manifest -Raw
    if ($mt -notmatch 'android.permission.INTERNET') {
        $mt = $mt -replace '(<manifest[^>]*>)', "`$1`r`n    <uses-permission android:name=""android.permission.INTERNET"" />"
        Set-Content -LiteralPath $manifest -Value $mt -Encoding UTF8
        Say '已补上 INTERNET 权限' Green
    }

    Say 'flutter pub get ...'
    & $bf pub get
    if ($LASTEXITCODE -ne 0) { Die 'flutter pub get 失败' }

    Say 'flutter precache --android（下载引擎产物）...'
    & $bf precache --android

    # ========================================================== 7. 编译 APK
    Step 7 'flutter build apk --release（第一次 5~20 分钟）'
    & $bf build apk --release
    $buildExit = $LASTEXITCODE

    # 注意：本项目的 android/build.gradle.kts 没做 Flutter 模板那种 build 目录重定向，
    # Gradle 会把 APK 放在 android\app\build\outputs\ 下。此时 flutter 会因为
    # 「在预期路径找不到 apk」而返回非 0，但 APK 其实已经成功生成。
    # 所以这里不能只看退出码，必须实际找一遍产物。
    $foundApk = @()
    foreach ($cand in @(
        (Join-Path $BuildProject 'build\app\outputs\flutter-apk'),
        (Join-Path $BuildProject 'android\app\build\outputs\flutter-apk'),
        (Join-Path $BuildProject 'android\app\build\outputs\apk\release')
    )) {
        if (Test-Path $cand) {
            $foundApk += Get-ChildItem $cand -Filter '*.apk' -ErrorAction SilentlyContinue
        }
    }
    if ($foundApk.Count -eq 0) {
        Die "flutter build apk 失败（退出码 $buildExit），且找不到任何 APK 产物"
    }
    if ($buildExit -ne 0) {
        Say "flutter 退出码为 $buildExit（它没在默认路径找到 apk），但产物确实已生成，继续" Yellow
    }
} finally {
    Pop-Location
}

# ============================================================ 8. 交回产物
Step 8 '把 APK 复制回原项目 dist\'

$dist = Join-Path $ProjectRoot 'dist'
New-Item -ItemType Directory -Path $dist -Force | Out-Null

# 产物路径不固定：本项目的 android/build.gradle.kts 没有做 Flutter 模板那种
# build 目录重定向，所以 Gradle 会把 APK 放在 android\app\build\outputs\ 下，
# 而不是 build\app\outputs\。这里两处都找。
$apks = @()
foreach ($cand in @(
    (Join-Path $BuildProject 'build\app\outputs\flutter-apk'),
    (Join-Path $BuildProject 'android\app\build\outputs\flutter-apk'),
    (Join-Path $BuildProject 'android\app\build\outputs\apk\release')
)) {
    if (Test-Path $cand) {
        $apks += Get-ChildItem $cand -Filter '*.apk' -ErrorAction SilentlyContinue
    }
}
$apks = $apks | Sort-Object Length -Descending | Group-Object Name | ForEach-Object { $_.Group[0] }
if (-not $apks) { Die "没找到 APK，已搜索 build 与 android\app\build 下的 outputs 目录" }
Say "找到 $($apks.Count) 个 APK"

# 取版本号：必须逐行解析。
# 不能用 Get-Content -Raw —— PowerShell 5.1 会按 ANSI 解码 UTF-8 文件，
# pubspec.yaml 里的中文注释会让整段文本损坏，正则直接匹配不上（已实测踩坑）。
# 用 aapt2 读 APK 里真实的 versionName 最可靠，取不到再退回解析 pubspec。
$version = $null
$aapt2 = Get-ChildItem (Join-Path $SdkDir 'build-tools') -Directory -ErrorAction SilentlyContinue |
    Sort-Object Name -Descending |
    ForEach-Object { Join-Path $_.FullName 'aapt2.exe' } |
    Where-Object { Test-Path $_ } |
    Select-Object -First 1
if ($aapt2) {
    $badging = & $aapt2 dump badging $apks[0].FullName 2>$null
    $vm = [regex]::Match(($badging -join "`n"), "versionName='([^']+)'")
    if ($vm.Success) { $version = $vm.Groups[1].Value }
}
if (-not $version) {
    foreach ($line in (Get-Content (Join-Path $ProjectRoot 'pubspec.yaml'))) {
        $mm = [regex]::Match($line, '^\s*version:\s*([0-9]+\.[0-9]+\.[0-9]+)')
        if ($mm.Success) { $version = $mm.Groups[1].Value; break }
    }
}
if (-not $version) { $version = '1.0.0'; Say '未取到版本号，回退用 1.0.0' }
Say "版本号: $version" Green

foreach ($apk in $apks) {
    # 产物校验：确认 APK 里确实包含本应用（而不是模板 Demo）
    $checkDir = Join-Path $BuildRoot 'apkverify'
    if (Test-Path $checkDir) { Remove-Item $checkDir -Recurse -Force }
    New-Item -ItemType Directory -Path $checkDir -Force | Out-Null
    Copy-Item $apk.FullName (Join-Path $checkDir 'a.zip') -Force
    Expand-Archive -LiteralPath (Join-Path $checkDir 'a.zip') -DestinationPath (Join-Path $checkDir 'x') -Force
    $dex = Get-ChildItem (Join-Path $checkDir 'x') -Filter '*.dex' -ErrorAction SilentlyContinue
    $hit = $false
    foreach ($d in $dex) {
        $bytes = [System.IO.File]::ReadAllBytes($d.FullName)
        $txt = [System.Text.Encoding]::ASCII.GetString($bytes)
        if ($txt.Contains('DeepSeek') -or $txt.Contains('deepseek_chat')) { $hit = $true; break }
    }
    if (-not $hit) { Die "产物校验失败：$($apk.Name) 里找不到本应用特征，可能又打成了模板 Demo" }
    Say '产物校验通过：APK 内确实包含本应用代码' Green

    $target = Join-Path $dist "deepseek-chat-v$version.apk"
    Copy-Item $apk.FullName $target -Force
    Say "$target  ($([math]::Round($apk.Length / 1MB, 1)) MB)" Green
}

Write-Host ''
Write-Host ("=" * 70) -ForegroundColor Green
Write-Host '  打包成功！' -ForegroundColor Green
Write-Host ("=" * 70) -ForegroundColor Green
Write-Host "  APK: $dist" -ForegroundColor White
Write-Host ''
Write-Host '  装到手机：' -ForegroundColor White
Write-Host "    adb install -r `"$dist\deepseek-chat-v$version.apk`""
Write-Host '    或把 APK 发到手机（微信/QQ/网盘）点击安装'
Write-Host ''
