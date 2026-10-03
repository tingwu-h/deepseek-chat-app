# 万象 · v1.2.0

个人开源 Android 多模型聊天客户端，前身为 DeepSeek 助手。支持流式回复、多会话历史、图片与文本附件、深色模式。

## 服务商

内置 DeepSeek、OpenAI、Kimi、Qwen、Anthropic、Google、xAI、GLM，以及自定义配置。各自保存 API Key、接口地址和所选模型。支持 OpenAI 兼容 Chat Completions、OpenAI Responses、Anthropic Messages、Google Gemini 四类协议。

预置名称不代表账号可用性，请填写账号当前可用的模型 ID。Qwen 默认中国内地接口，其他地域可修改 Base URL。图片能力可根据模型说明设置。只展示服务端实际返回的思考内容。联网搜索、工具执行和语音不在本版范围。

## 使用

设置 → 选择服务商 → 填写该服务商的 API Key → 选择模型或填写自定义模型 → 保存。测试连接会发出真实请求，可能产生 API 用量。

聊天页顶部切换服务商和模型，历史会话记住所用服务商和模型。文件支持 txt、md、json、csv、代码等纯文本，不解析 PDF / Word。

## 安装与升级

[仓库与发布页](https://github.com/tingwu-h/wanxiang-chat-app)。

v1.2.0 构建号为 11。包名继续使用 `com.example.deepseek_chat`，沿用原证书。覆盖升级无需卸载旧版，实际设备安装与数据保留仍需真机验证。内部 Dart 包名、平台通道和存储键保留旧名称。

Logo 由项目所有者提供，品牌参考和图标位于 `assets/branding`。

## 隐私与数据

Android 使用 Keystore + AES-GCM 加密保存密钥，普通设置不包含密钥。聊天内容存储在应用私有目录，并非全部加密。请求时，所选接口收到密钥、当前会话上下文和附件。导出只包含聊天文字及附件名称，不包含密钥、图片文件或本机图片路径。系统备份已排除应用数据，重要文字请主动导出。

应用与各服务商无隶属关系。API 使用资格和计费由各家平台管理。

## 本地离线构建

```powershell
& .\tools\build-release-offline.ps1 -ToolRoot C:\dsbuild
```

使用已有 Flutter、JDK 17、Android SDK、Pub / Gradle 缓存。脚本执行依赖解析、静态分析、测试、Release APK 构建及证书校验，不自动安装或上传。缺失依赖会明确报错。

产物：`dist/wanxiang-v1.2.0.apk`。签名沿用当前用户 Android 配置目录中的原有 `debug.keystore`，不移动或重建。证书 SHA-256：

```text
566bba04384837a3d4903ce70281374412d516c74a1f3275d7ec27d34f87cbc1
```

## 桌面端预留

本次只开发 Android。`ChatService` 为通用聊天接口，`ApiProtocol` 处理协议映射，`PlatformBackend` 提供安全存储、导出和退出接口。未来桌面端需实现系统安全存储与文件导出并完成测试；当前非 Android 回退仅在内存保存密钥，不代表桌面端已支持。

## 验证范围

测试覆盖协议请求、流式响应、密钥隔离、旧数据迁移与聊天回归。没有提供各家真实 API 密钥时，不能将模拟测试表述为八家线上实测通过。见 [v1.2.0 更新说明](docs/1.2.0-更新说明.md)。

[MIT](LICENSE)
