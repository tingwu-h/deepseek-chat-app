# DeepSeek 助手（Flutter 跨平台聊天 App）

一个使用 **Flutter + Dart + Provider** 编写的 DeepSeek 聊天客户端，Android / iOS 通用。

| 功能 | 实现方式 |
| --- | --- |
| 聊天界面（标题 / 气泡列表 / 输入框 + 发送按钮） | `lib/pages/chat_page.dart` + `lib/widgets/` |
| 调用 `/chat/completions` | `lib/services/deepseek_service.dart`（`http` 包） |
| **流式输出（打字机效果）** | `http.Client.send()` → SSE 增量解析 `data:` 帧，逐段 `notifyListeners()` |
| 对话历史本地保存 | `shared_preferences`（`lib/services/storage_service.dart`） |
| 设置页自填 API Key | `lib/pages/settings_page.dart`（**代码里没有任何硬编码 Key**） |
| 深色模式 | `lib/theme/app_theme.dart` + 设置页「跟随系统 / 浅色 / 深色」 |
| 状态管理 | `provider`（`AppSettingsProvider` + `ChatProvider`） |

---

## 1）项目结构

```text
deepseek移动端/
├── pubspec.yaml                      # 依赖清单（provider / http / shared_preferences / flutter_markdown）
├── analysis_options.yaml             # 静态检查规则
├── README.md                         # 本文档
│
├── lib/
│   ├── main.dart                     # 入口：初始化存储 → 注入 Provider → MaterialApp（主题/路由）
│   │
│   ├── models/
│   │   ├── chat_message.dart         # 消息模型（role/content/timestamp），JSON 序列化
│   │   └── app_settings.dart         # 设置模型（apiKey/baseUrl/model/systemPrompt/themeMode）
│   │
│   ├── services/
│   │   ├── deepseek_service.dart     # ★ API 封装：SSE 流式 + 非流式 + 错误中文化 + 连通性自检
│   │   └── storage_service.dart      # ★ 本地持久化：设置 + 聊天历史（shared_preferences）
│   │
│   ├── providers/
│   │   ├── app_settings_provider.dart# 设置状态（含主题模式），落盘保存
│   │   └── chat_provider.dart        # ★ 对话状态机：发送 / 流式追加 / 停止生成 / 清空 / 持久化
│   │
│   ├── pages/
│   │   ├── chat_page.dart            # ★ 主页面：AppBar + 气泡列表 + 输入栏
│   │   └── settings_page.dart        # ★ 设置页：API Key、模型、Base URL、温度、主题、测试连接
│   │
│   ├── widgets/
│   │   ├── message_bubble.dart       # 单条气泡（Markdown 渲染、长按复制、错误样式）
│   │   ├── message_list_view.dart    # 反向 ListView（新消息自动贴底）+ 空状态引导
│   │   ├── chat_input_bar.dart       # 多行输入框 + 发送/停止按钮
│   │   └── typing_indicator.dart     # 「正在思考」三点动画
│   │
│   ├── theme/app_theme.dart          # Material 3 浅色/深色主题（品牌蓝 #4D6BFE）
│   └── utils/formatters.dart         # 时间格式化、会话标题
│
├── test/widget_test.dart             # Widget 测试（用假 http.Client，不需要真实 Key）
│
├── tools/                            # ★ 一键打包 APK 的脚本
│   ├── setup_android_build.ps1       # 装工具链（Flutter/JDK/Android SDK）+ 出 release APK
│   ├── build_apk.ps1                 # 工具链已装好后，只重新编译
│   └── download.mjs                  # 纯 Node 下载器（断点续传 / 代理 / 重试）
│
├── android/                          # Android 工程（已含 INTERNET 权限）
│   ├── settings.gradle.kts
│   ├── build.gradle.kts
│   ├── gradle.properties
│   ├── gradle/wrapper/gradle-wrapper.properties
│   └── app/
│       ├── build.gradle.kts
│       └── src/main/
│           ├── AndroidManifest.xml   # ★ uses-permission INTERNET
│           ├── kotlin/com/example/deepseek_chat/MainActivity.kt
│           └── res/{values,values-night,drawable,drawable-v21}/...
│
└── ios/Runner/Info.plist             # iOS 配置（HTTPS 直连，无需额外权限）
```

### 数据流（一次发送发生了什么）

```text
ChatInputBar.onSend
      ↓
ChatPage._handleSend ──(无 Key 就跳设置页)──► SettingsPage
      ↓ chat.send(text, settings)
ChatProvider：追加 user 消息 + 一个空 assistant 气泡（先显示三点动画）
      ↓
DeepSeekService.streamChat()  POST {baseUrl}/chat/completions  stream: true
      ↓ SSE: data: {"choices":[{"delta":{"content":"你"}}]}
  每收到一段 → assistant.content += 片段 → notifyListeners()
      ↓
MessageBubble 重绘 = 打字机效果；同时 StorageService 把历史写进 shared_preferences
```

关键细节：

* **强制 UTF-8**：用 `Utf8Decoder` 而不是按字节切分，中文不会乱码。
* **按行解析 SSE**：只处理 `data:` 行，`[DONE]` 结束；空行 / 心跳 / 半包 JSON 直接跳过，不会中断回答。
* **可中断**：每次发送分配一个自增 token，「停止生成」让 token 失效，旧流的残余数据不会污染新一轮对话。
* **错误中文化**：401/402/429 等状态码翻译成「API Key 无效」「余额不足」「请求过于频繁」等提示。

---

## 2）关键代码文件

下面按「最值得看的顺序」列出，完整内容见对应文件。

### 2.1 `pubspec.yaml`（依赖）

```yaml
environment:
  sdk: ">=3.3.0 <4.0.0"

dependencies:
  flutter:
    sdk: flutter
  provider: ^6.1.2            # 状态管理
  http: ^1.2.2                # 网络请求（流式）
  shared_preferences: ^2.3.2  # 本地持久化
  flutter_markdown: ^0.7.4+1  # 助手气泡的 Markdown/代码块渲染
  cupertino_icons: ^1.0.8

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^4.0.0
```

### 2.2 `lib/services/deepseek_service.dart`（API 封装，核心）

```dart
/// 流式请求：async* 生成器，UI 用 await for 边收边显示
Stream<ChatChunk> streamChat({
  required AppSettings settings,
  required List<ChatMessage> history,
}) async* {
  final apiKey = settings.apiKey.trim();
  if (apiKey.isEmpty) throw DeepSeekException('还没有填写 API Key，请先到「设置」里填写。');

  final request = http.Request('POST', _endpoint(settings.baseUrl))
    ..headers.addAll({
      'Content-Type': 'application/json; charset=utf-8',
      'Accept': 'text/event-stream, application/json',
      'Authorization': 'Bearer $apiKey',
    })
    ..body = jsonEncode({
      'model': settings.model,              // 默认 deepseek-chat
      'messages': buildApiMessages(history, systemPrompt: settings.systemPrompt),
      'stream': true,
      'temperature': settings.temperature,
    });

  final response = await _client.send(request).timeout(timeout);
  if (response.statusCode != 200) {
    throw DeepSeekException(_friendlyError(response.statusCode,
        await response.stream.bytesToString()));
  }

  // 关键：Utf8Decoder + LineSplitter，中文不会乱码
  final lines = response.stream
      .transform(const Utf8Decoder(allowMalformed: true))
      .transform(const LineSplitter());

  await for (final rawLine in lines.timeout(timeout)) {
    final line = rawLine.trim();
    if (!line.startsWith('data:')) continue;       // 跳过 event:/id:/心跳
    final payload = line.substring(5).trim();
    if (payload == '[DONE]') break;                // 流结束
    // ... jsonDecode 后取出 choices[0].delta.content / reasoning_content
    yield ChatChunk(content);
  }
}
```

完整实现（含错误映射、非流式备用接口、测试连接）在
`lib/services/deepseek_service.dart`，约 300 行。

### 2.3 `lib/providers/chat_provider.dart`（流式状态机）

```dart
Future<void> send(String text, AppSettings settings) async {
  final token = ++_activeToken;              // 本轮请求的身份证
  _messages.add(ChatMessage.user(text.trim()));

  final assistant = ChatMessage.assistant('');  // 先插入空气泡 → 显示三点动画
  _messages.add(assistant);
  _loading = true;
  notifyListeners();

  final context = _messages.where((m) => !identical(m, assistant)).toList();

  try {
    await for (final chunk in _api.streamChat(settings: settings, history: context)) {
      if (token != _activeToken) break;      // 用户点了「停止生成」
      assistant.content += chunk.text;       // 追加 → 打字机效果
      notifyListeners();
    }
  } catch (e) { /* 错误转成气泡或追加提示 */ }
  finally {
    if (assistant.content.trim().isEmpty) _messages.remove(assistant);
    _loading = false;
    notifyListeners();
    await _storage.saveHistory(_messages);   // 落盘
  }
}
```

### 2.4 `lib/pages/chat_page.dart`（界面骨架）

```dart
Scaffold(
  appBar: AppBar(title: 会话标题 + 当前模型, actions: [设置, 更多(清空/停止)]),
  body: Column(children: [
    Expanded(child: MessageListView(messages: messages, isLoading: chat.isLoading)),
    ChatInputBar(
      isLoading: chat.isLoading,
      enabled: settings.hasApiKey,           // 没填 Key 就禁用发送
      onSend: _handleSend,
      onStop: chat.stop,                     // 停止生成
    ),
  ]),
)
```

### 2.5 设置页里 Key 的读取方式（不硬编码）

```dart
// 保存：用户输入 → AppSettingsProvider → shared_preferences
await context.read<AppSettingsProvider>().update(apiKey: _keyController.text.trim());

// 读取：只在内存/本地存储里，代码里搜不到任何 sk- 开头的常量
final apiKey = context.read<AppSettingsProvider>().settings.apiKey;
```

---

## 3）运行步骤

> **只想拿到能装到手机上的 APK？** 直接跳到 **[步骤 4.5：一键打包 APK](#步骤-45一键打包-apk推荐不想手动装环境就看这里)**，
> 一条命令自动装好 Flutter + JDK + Android SDK 并产出安装包。

### 步骤 0：环境准备（一次性）

| 需要 | 说明 |
| --- | --- |
| Flutter SDK | 3.22 或更高（本文代码用到 `withValues()`、`PopScope.onPopInvokedWithResult`，所以**请不要低于 3.22**） |
| Android Studio | 提供 Android SDK / 模拟器；或者只装 Android SDK + 手机真机调试 |
| JDK 17 | Android Gradle Plugin 8.x 要求 |
| Xcode（仅 iOS） | macOS 上编译 iOS 才需要 |

**Windows 安装 Flutter（推荐方式）**

1. 下载 Flutter SDK 压缩包：<https://docs.flutter.dev/get-started/install/windows>
   （或 `git clone -b stable https://github.com/flutter/flutter.git D:\flutter`）
2. 把 `D:\flutter\bin` 加进系统环境变量 `Path`。
3. 打开**新的** PowerShell 验证：

   ```powershell
   flutter --version
   flutter doctor
   ```

   `flutter doctor` 里 Android toolchain 一行要打勾；如果提示缺少 cmdline-tools，
   执行 `flutter doctor --android-licenses` 一路 `y` 接受许可。

**macOS 安装 Flutter**

```bash
brew install --cask flutter      # 或下载 zip 后把 flutter/bin 加进 PATH
flutter doctor
```

### 步骤 1：获取 DeepSeek API Key

1. 打开 <https://platform.deepseek.com/>
2. 注册 / 登录 → 左侧 **API Keys** → **创建 API Key**
3. 复制形如 `sk-xxxxxxxxxxxxxxxxxxxxxxxx` 的字符串（**只显示一次，记得先存好**）
4. 到 **充值 / Billing** 里确认账户有余额（余额为 0 时接口会返回 402）

> Key 只填在 App 的设置页里，保存在手机本地（`shared_preferences`），
> 不会写进代码、也不会提交到 git。**不要把 Key 硬编码进任何源文件。**

### 步骤 2：拉取依赖

```powershell
cd <你的项目目录>
flutter pub get
```

### 步骤 3：生成平台工程文件（**第一次必做**）

本仓库里的 `lib/`、`test/`、`pubspec.yaml` 是完整的，可以直接编译；
但 Android/iOS 的**原生外壳**依赖于你本机 Flutter 版本的模板（Gradle wrapper 二进制、
各分辨率启动图标、iOS Xcode 工程等），这些没法直接放进源码仓库。

所以第一次运行前，在本项目根目录执行一次：

```powershell
flutter create . --platforms=android,ios --org com.example --project-name deepseek_chat
```

这条命令会：

* **补全**缺失的原生文件（`android/gradlew`、`gradle/wrapper/gradle-wrapper.jar`、
  `android/app/src/main/res/mipmap-*/ic_launcher.png`、`ios/Runner.xcodeproj` 等）
* **保留** `lib/` 与 `test/` 下你已有的代码（同名文件才会被覆盖，本项目里没有同名文件）
* 已有的 `android/app/src/main/AndroidManifest.xml` 会被模板覆盖，
  所以**执行完请检查一下 manifest 里是否还有这一行**，没有就补回去（联网必需）：

  ```xml
  <uses-permission android:name="android.permission.INTERNET" />
  ```

  本文档配套的 `android/` 目录里已经写好了正确的 manifest / 主题 / 权限，也可以直接
  从 git 恢复：`git checkout -- android/`。

若只想要 Android，把 `--platforms=android,ios` 换成 `--platforms=android` 即可。

### 步骤 4：真机调试运行

**Android 真机**

1. 手机 → 设置 → 关于手机 → 连续点「版本号」7 次，开启开发者选项
2. 开发者选项里打开 **USB 调试**，用数据线连电脑，手机上点「允许调试」
3. 执行：

   ```powershell
   flutter devices            # 应该能看到你的手机
   flutter run                # 热重载：按 r 重载、按 R 重启、按 q 退出
   ```

   首选用 USB；也可以无线调试（Android 11+）：

   ```powershell
   adb pair 手机IP:配对端口
   adb connect 手机IP:5555
   flutter run
   ```

**iPhone 真机（需 macOS + Xcode）**

```bash
cd ios && pod install && cd ..
open ios/Runner.xcworkspace     # 在 Xcode 里选团队签名（Signing & Capabilities）
flutter run
```

**只想要一个安装包发给别人（Android）**

```powershell
flutter build apk --release                 # 产物：build\app\outputs\flutter-apk\app-release.apk
flutter build apk --split-per-abi --release # 按 CPU 架构拆分，体积更小
flutter build appbundle --release           # 上架 Google Play 用 .aab
```

把 `app-release.apk` 传到手机点击安装即可（需要允许「安装未知来源应用」）。

> 默认用 debug 签名，方便自测；要正式发布请生成自己的 keystore，
> 并在 `android/app/build.gradle.kts` 里配置 `signingConfigs.release`。

### 步骤 4.5：一键打包 APK（推荐，不想手动装环境就看这里）

不想手动装 Flutter / JDK / Android SDK？仓库里带了自动化脚本，
**一条命令**把三件套装进项目里的 `.toolchain/`（不动你的系统环境），然后直接产出 APK。

#### 前置条件

| 条件 | 说明 |
| --- | --- |
| Node.js 16+ | 脚本用它做下载器（支持断点续传）。<https://nodejs.org> 装 LTS 版即可 |
| 网络能访问 Google / Gradle / pub.dev | 也就是需要能科学上网；**脚本会自动探测代理**（环境变量 → 注册表 → `127.0.0.1:7897`） |
| 磁盘 ≥ 8 GB | Flutter 约 1.2 GB + Android SDK 约 1 GB + JDK 0.3 GB + Gradle 缓存约 1 GB + 构建产物 |

#### 执行

```powershell
cd <你的项目目录>
powershell -ExecutionPolicy Bypass -File tools\setup_android_build.ps1
```

脚本会依次做完 9 件事：

1. 预检 Node / 磁盘 / 代理
2. 下载并解压 **Flutter SDK**（默认取官方最新 stable，例如 3.47.5；可用 `-FlutterVersion 3.32.8` 指定）
3. 下载并解压 **Temurin JDK 17**（Android Gradle Plugin 8.x 要求）
4. 下载 **Android cmdline-tools**，自动接受许可并安装 `platform-tools` / `platforms;android-35` / `build-tools;35.0.0`
5. 执行 `flutter create . --platforms=android` 补齐 Gradle wrapper、启动图标等原生文件，
   **并自动把带 `INTERNET` 权限的 AndroidManifest.xml 恢复回来**
6. `flutter pub get` + `flutter precache --android`
7. 预下载 Gradle 发行包（避免编译时再联网）
8. 配置签名（默认 debug 签名，见下）
9. `flutter build apk --release`，产物复制到 `dist\`

第一次执行需要 10~30 分钟（取决于网速，下载量约 2.5 GB）。
下载支持**断点续传**，中断了直接重跑同一条命令即可。

#### 常用参数

```powershell
# 手动指定代理
... -File tools\setup_android_build.ps1 -ProxyUrl http://127.0.0.1:7897

# 指定 Flutter 版本（网络不稳时建议锁版本）
... -File tools\setup_android_build.ps1 -FlutterVersion 3.32.8

# 按 CPU 架构拆分，APK 更小（一台手机只需装对应架构那个）
... -File tools\setup_android_build.ps1 -SplitPerAbi

# 生成自己的签名密钥（会让 release 包用正式签名而不是 debug 签名）
... -File tools\setup_android_build.ps1 -Release
```

#### 打包之后：装到手机上

产物在 `dist\deepseek-chat-v1.0.0.apk`（约 20~40 MB），三种安装方式任选：

| 方式 | 操作 |
| --- | --- |
| **USB（最快）** | 手机开「开发者选项 → USB 调试」，插线后执行 `adb install -r dist\deepseek-chat-v1.0.0.apk` |
| **微信 / QQ / 网盘** | 把 APK 发给自己，在手机上点开安装（需允许「安装未知来源应用」） |
| **数据线拷贝** | 拷到手机存储，用文件管理器点开安装 |

> 用 debug 签名打出来的 release 包**可以正常安装使用**，只是系统可能提示
> 「此应用未经过安全检测」，点继续即可。要发布给别人用，请加 `-Release` 生成正式密钥
> （密钥库在 `android/app/deepseek-release.jks`，**口令和文件务必自己备份，
> 丢了就没法给已安装的用户做覆盖升级**）。

#### 以后只改代码、重新出包

```powershell
powershell -ExecutionPolicy Bypass -File tools\build_apk.ps1
```

它复用 `.toolchain/` 里已经装好的环境，只跑编译（1~5 分钟）。
加 `-Clean` 可以先清掉 `build/` 再编。

#### 已经打包成功了（v1.0.0）

本项目的 APK 已经成功产出并验证通过：`dist\deepseek-chat-v1.0.0.apk`（51.1 MB）。

- 静态分析 `flutter analyze`：No issues found
- 测试 `flutter test`：11/11 通过
- APK 签名（v2）与清单（包名、应用名、INTERNET 权限）均已校验
- 已解包确认 `libapp.so` 内含本项目全部模块

详细的构建过程、踩过的坑、以及以后如何重新打包，见 **[打包结果说明.md](打包结果说明.md)**。

重新打包（复用已装好的工具链，约 1~2 分钟，需在普通终端而非沙箱里运行）：

```powershell
powershell -ExecutionPolicy Bypass -File tools\ascii_build.ps1
```

#### 已知限制：中文用户名 / 中文路径

本项目所在路径和 Windows 用户名都含中文（`<你的项目目录>`），
实测会踩到两个坑，脚本里已经做了规避，但**仍有一步未验证通过**：

| 坑 | 现象 | 处理 |
| --- | --- | --- |
| Dart 按 Latin-1 解码 `%APPDATA%` | `Flutter failed to write to ... C:\Users\渚畤楣廫AppData\Roaming\...` | 脚本已把 `APPDATA` / `LOCALAPPDATA` / `PUB_CACHE` 重定向到项目内 `.toolchain\appdata`，**已验证修复** |
| Windows 控制台按 GBK 解码输出 | 终端里中文显示成 `����������` | 用 `chcp 65001` 或改终端编码；也可 `powershell -File ... > log.txt` 后用编辑器看 |
| git 在 Dart 子进程里处理中文路径 | `CreateFile failed 5 (拒绝访问。)`，flutter 自举卡住 | **尚未解决**，见 `PACKAGING_PROGRESS.md` 的排查记录与后续方案 |

如果你的电脑用户名是纯英文，以上坑都不会遇到，直接跑脚本即可。

#### 工具链装在哪、怎么删

全部在 **项目目录下的 `.toolchain\`**（Flutter / JDK / Android SDK）与
`.toolchain\gradle-home\`（Gradle 缓存），不污染系统环境变量、不写注册表。
不想要了整个目录删掉即可；`.gitignore` 已经把它们排除，不会误提交。

### 步骤 5：在 App 里填 Key 并开始聊天
1. 首次打开会看到「还没有配置 API Key」的提示
2. 点右上角 **设置**（或 **⋮ → API Key 与设置**）
3. 粘贴 Key → 点 **测试连接**（会真的请求一次 `https://api.deepseek.com/chat/completions`）
   * 成功：弹出「连接成功：你好！…」
   * 失败：会显示中文原因，例如「API Key 无效或已过期（401）」
4. 回到聊天页输入问题，点右下角 ↑ 发送，回复会**一个字一个字**出现；
   生成过程中按钮变成 ⏹，点它可随时停止
5. 关掉 App 再打开，历史对话仍在（存在本地）

### 步骤 6（可选）：跑测试

```powershell
flutter analyze          # 静态检查，应为 No issues found!
flutter test             # 单元 + Widget 测试（用假 http.Client，不消耗额度）
```

---

## 常见问题

**Q：回复不是流式，而是一次性出现？**
A：检查是否用了公司代理 / VPN 中间层，部分代理会缓冲 SSE。代码里已经做了兜底
（如果服务端返回整段 `message` 也会正常显示），但要真正的打字机效果需要不被缓冲的直连。

**Q：406 / 400 报错？**
A：到设置页把 **模型** 切到 `deepseek-chat`，**Base URL** 保持 `https://api.deepseek.com`
（不要带 `/v1`，代码会自动补 `/chat/completions`；带 `https://api.deepseek.com/v1` 也支持）。

**Q：余额不足（402）？**
A：到 <https://platform.deepseek.com/top_up> 充值。注意赠送额度有时效。

**Q：历史记录存哪了？怎么清？**
A：`shared_preferences`（Android：应用私有 SharedPreferences；iOS：NSUserDefaults），
应用内 **设置 → 清空本地聊天记录** 或聊天页 **⋮ → 清空当前对话**。上限 500 条。

**Q：想换成 Riverpod / dio / sqflite？**
A：`StorageService` 与 `DeepSeekService` 已经把副作用隔离在两个类里，
换 ORM 或换网络库只需要改这两个文件，上层 Provider 与页面不用动。

**Q：编译报 `resource mipmap/ic_launcher not found`？**
A：说明还没执行步骤 3 的 `flutter create .`，缺少各分辨率的启动图标资源。
执行一次即可（图标是二进制文件，无法直接放进源码仓库）。

**Q：想用 git 管理？**
A：仓库里已经放好 `.gitignore`（忽略 `build/`、`.dart_tool/`、keystore 等）。
在本目录执行 `git init && git add . && git commit -m "init"` 即可开始版本管理；
**提交前确认设置页里的 Key 只在手机本地，不在任何源文件中**。

---

## 说明

本项目源码按 Flutter 3.22+ / Dart 3.3+ 编写（实测环境为 Flutter 3.47.5 + JDK 17 + Android SDK 35 可用）。
作者在生成这份代码时所在的环境里没有安装 Flutter SDK（`flutter` / `dart` 命令都不存在），
因此 **`lib/` 下的 Dart 代码没有在本机跑过 `flutter analyze` / `flutter test` 做编译验证**，
只做了逐文件人工核对（导入路径、依赖名、API 签名、空安全、常量拼写）。

不过 `tools/` 下的打包流程是**在本机实测过**的：Node 下载器、代理探测、
四个下载源（Flutter / Temurin JDK / Android cmdline-tools / Gradle）的连通性、
断点续传都已验证通过。真正编译 APK 时如果 `flutter analyze` 报出个别 lint 提示，
按提示微调即可，不影响运行。
