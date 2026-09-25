# 上传到 GitHub 的文件清单

本项目目录下共 **10,386 个文件**，但真正需要上传的只有 **41 个**。
其余绝大部分是 `.toolchain\` 里的 pub 包缓存（1 万多个第三方包源码），**必须排除**。

---

## 一、应该上传的 41 个文件

### 1. 根目录（5 个）

| 文件 | 上传 | 说明 |
| --- | :---: | --- |
| `pubspec.yaml` | ✅ **必须** | 依赖清单，没它项目跑不起来 |
| `analysis_options.yaml` | ✅ **必须** | 静态检查规则 |
| `.gitignore` | ✅ **必须** | 告诉 git 哪些别传（已配好） |
| `README.md` | ✅ 建议 | 项目说明，别人看你仓库第一眼就读它 |
| `打包结果说明.md` | ⭕ 可选 | 你的构建记录，想当技术笔记留着就传 |

> `pubspec.lock` 目前还没生成（还没在项目根目录跑过 `pub get`）。
> 应用类项目**建议一起提交**，可锁定依赖版本；等你在本机跑一次 `flutter pub get` 后它就会出现。

### 2. `lib/` —— 全部 15 个 ✅ **必须**

应用的源代码，一个都不能少：

```
lib/main.dart                          入口
lib/models/app_settings.dart           设置模型
lib/models/chat_message.dart           消息模型
lib/providers/app_settings_provider.dart  设置状态
lib/providers/chat_provider.dart          对话状态机（流式）
lib/services/deepseek_service.dart     ★ DeepSeek API 封装（SSE 流式）
lib/services/storage_service.dart      本地持久化
lib/pages/chat_page.dart               ★ 主页面
lib/pages/settings_page.dart           ★ 设置页
lib/theme/app_theme.dart               浅色/深色主题
lib/utils/formatters.dart              工具函数
lib/widgets/chat_input_bar.dart        输入栏
lib/widgets/message_bubble.dart        聊天气泡
lib/widgets/message_list_view.dart     气泡列表
lib/widgets/typing_indicator.dart      「正在思考」动画
```

### 3. `test/` —— 2 个 ✅ 建议传

```
test/unit_test.dart     7 个单元测试
test/widget_test.dart   4 个 Widget 测试（含流式拼接、设置页）
```

### 4. `android/` —— 12 个 ✅ **必须**

```
android/settings.gradle.kts                                  AGP/Kotlin 版本、仓库配置
android/build.gradle.kts                                     根构建脚本
android/gradle.properties                                    Gradle 内存等参数
android/gradle/wrapper/gradle-wrapper.properties             Gradle 9.3.1（版本必须对）
android/app/build.gradle.kts                                 应用模块构建配置
android/app/src/main/AndroidManifest.xml                     ★ 含 INTERNET 权限
android/app/src/main/kotlin/.../MainActivity.kt              Android 入口
android/app/src/main/res/values/strings.xml                  应用名
android/app/src/main/res/values/styles.xml                   浅色启动主题
android/app/src/main/res/values-night/styles.xml             深色启动主题
android/app/src/main/res/drawable/launch_background.xml      启动图
android/app/src/main/res/drawable-v21/launch_background.xml  启动图（API 21+）
```

> ⚠️ **`android/gradle/wrapper/gradle-wrapper.jar` 不要上传**——这是 Flutter 官方约定：
> Flutter 官方模板的 `android/.gitignore` 里就明确排除了它：
> ```
> gradle-wrapper.jar
> /gradlew
> /gradlew.bat
> /local.properties
> ```
> 原因是 Flutter 在构建时会自动生成/覆盖这些文件。所以别人 clone 后跑一次
> `flutter create .` 或直接 `flutter run` 就能补全，仓库里不需要放二进制。
>
> 同理，`android/app/src/main/res/mipmap-*/ic_launcher.png`（启动图标，共约 4 KB）
> 和 `android/app/src/debug|profile/AndroidManifest.xml` 也是 `flutter create` 生成的。
> 官方模板也没有把它们纳入版本管理——不提交完全没问题，README 里已说明补全方式。
> 如果你希望别人 clone 后**不需要**再跑 `flutter create`，可以额外提交图标，
> 但要在 README 里写明，否则会和官方约定不一致。

**以下 android 文件不要上传**（构建时自动生成）：
```
android/local.properties          ← 记录了你自己电脑的 SDK 绝对路径，传上去对别人没用还有隐私
android/.gradle/                  ← 构建缓存
android/app/src/debug/            ← flutter create 生成的调试清单（可选，传了也无妨）
android/app/src/profile/          ← 同上
android/deepseek_chat_android.iml ← IDE 文件
android/.gitignore                ← flutter create 生成的，会和你根目录的 .gitignore 重复
```

### 5. `ios/Runner/Info.plist` —— 1 个 ⭕ 可选

```
ios/Runner/Info.plist    iOS 应用名/版本配置
```
你目前只做了 Android 打包。如果暂时不管 iOS，也可以不传；将来要做 iOS 时
在 macOS 上跑 `flutter create . --platforms=ios` 会补全整个 Xcode 工程。

### 6. `tools/` —— 4 个 ⭕ 可选（但对你自己有用）

```
tools/ascii_build.ps1         一键构建 APK（本次实际使用的脚本）
tools/setup_android_build.ps1 从零装工具链 + 构建
tools/build_apk.ps1           复用工具链重新构建
tools/download.mjs            带断点续传的下载器
```
这些是 Windows PowerShell 脚本，跟 App 本身无关，但记录了「怎么把环境折腾通」，
以后换电脑或给别人参考都值钱。**建议传**，纯文本、体积很小。

---

## 二、绝对不要上传的文件

| 路径 | 原因 |
| --- | --- |
| **`.toolchain/`（1 万多个文件，113 MB）** | pub 包缓存，是第三方包的源码副本，不是你的代码；传上去既臃肿又可能有许可证问题 |
| **`dist/deepseek-chat-v1.0.0.apk`（51 MB）** | 二进制产物，每次重新构建哈希都变，不该进版本库。要发布应该用 GitHub Releases |
| `build/`、`.dart_tool/` | 构建中间产物 |
| `android/local.properties` | 你电脑的 SDK 绝对路径 |
| `android/key.properties`、`*.jks`、`*.keystore` | **签名密钥，泄露等于别人能伪造你的应用更新** |
| `.idea/`、`*.iml`、`.vscode/` | IDE 个人配置 |
| `*.log` | 构建日志 |

这些**已经全部写在 `.gitignore` 里了**，你不用手动排除，`git add .` 会自动跳过。

---

## 三、发起上传（命令直接可抄）

在**项目根目录**打开 PowerShell：

### 第 1 步：确认 .gitignore 真的生效（重要）

```powershell
cd <你的项目目录>

git init
git add .
git status --short
```

看输出：**应该只有约 40 个文件**（`lib/`、`android/`、`test/`、`tools/`、几个 md 和 yaml）。
如果看到 `.toolchain/` 或 `dist/` 开头的文件，说明 .gitignore 没生效，先别 commit，告诉我。

### 第 2 步：设置身份（只需一次）

```powershell
git config --global user.name  "你的名字"
git config --global user.email "你的邮箱"
```

### 第 3 步：提交

```powershell
git commit -m "feat: DeepSeek 聊天助手（Flutter + Provider，流式输出/本地历史/深色模式）"
git branch -M main
```

### 第 4 步：推到 GitHub

先在 <https://github.com/new> 创建一个**空仓库**（不要勾选 Add README / .gitignore / license，
否则会和你本地的冲突）。假设仓库地址是 `https://github.com/你的用户名/deepseek-chat-app.git`：

```powershell
git remote add origin https://github.com/你的用户名/deepseek-chat-app.git
git push -u origin main
```

> 国内直连 github 可能超时，多试几次；或给 git 配代理：
> `git config --global http.proxy http://127.0.0.1:7897`（用完记得 `--unset`）

---

## 四、上传前最后检查三件事

1. **确认没有 API Key 混进代码**
   ```powershell
   Select-String -Path lib\*.dart,lib\**\*.dart,android\**\* -Pattern "sk-" -ErrorAction SilentlyContinue
   ```
   应该没有任何输出。本项目的 Key 只存在手机本地的 `shared_preferences`，代码里是空的。

2. **确认 .gitignore 生效**
   ```powershell
   git status --short | Measure-Object -Line
   ```
   行数应该在 40 左右，不是几千。

3. **确认单文件没有超过 100 MB**
   GitHub 单文件上限 100 MB。你的文件都很小（最大的 APK 51 MB 且不上传），没问题。

---

## 五、上传之后别人怎么跑起来

在你的 `README.md` 里已经写了完整步骤，核心是这三条：

```bash
flutter pub get
flutter create . --platforms=android      # 补齐原生工程（Gradle wrapper jar、启动图标等）
flutter run
```

> 这一点和 Flutter 官方约定一致：`android/gradle/wrapper/gradle-wrapper.jar`、
> `gradlew`、`android/app/src/main/res/mipmap-*/ic_launcher.png` 这些
> 都在官方模板的 `.gitignore` 里，不会进仓库，需要靠 `flutter create` 补全。
> 所以 README 里那一步是**必需**的，不是可选的。
