<a id="top"></a>

<div align="center">
  <img src="assets/branding/wordmark.png" alt="万象 Logo" width="620">
  <h1>万象 · Wanxiang</h1>
  <p><strong>一个应用，连接多家 AI 模型。</strong></p>
  <p>以 Android 为起点，让模型选择回到你手中。</p>
  <p>
    <a href="https://github.com/tingwu-h/wanxiang-chat-app/releases/tag/v1.2.0"><img src="https://img.shields.io/badge/version-v1.2.0-1677FF" alt="版本 v1.2.0"></a>
    <img src="https://img.shields.io/badge/Android-7.0%2B-16C9B2" alt="Android 7.0 及以上">
    <img src="https://img.shields.io/badge/Built_with-Flutter-28BCEF" alt="使用 Flutter 构建">
    <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-8B5CF6" alt="MIT 许可证"></a>
  </p>
  <p>
    <a href="https://github.com/tingwu-h/wanxiang-chat-app/releases/tag/v1.2.0">v1.2.0 发布页</a> ·
    <a href="#preview">界面预览</a> ·
    <a href="#quick-start">开始使用</a> ·
    <a href="#providers">服务商</a> ·
    <a href="docs/1.2.0-更新说明.md">更新说明</a>
  </p>
</div>

---

**万象**是一款开源 Android 多模型聊天客户端，前身为 DeepSeek 助手。使用自己的 API Key，在同一个应用里切换服务商与模型，保留会话历史，用文字、图片和文本文件展开对话。

蓝紫与青色交汇的轨道，是万象的品牌视觉：不同模型汇聚在一个入口，让选择更自由，让对话更连贯。

> **Android v1.2.0** · 使用自己的 API Key，选择你熟悉的模型，开始新的对话。

<a id="preview"></a>

## 看见万象

<table>
  <tr>
    <td align="center"><strong>浅色对话</strong></td>
    <td align="center"><strong>深色对话</strong></td>
    <td align="center"><strong>服务商设置</strong></td>
  </tr>
  <tr>
    <td><img src="docs/screenshots/chat-light.png" alt="万象浅色聊天界面" width="260"></td>
    <td><img src="docs/screenshots/chat-dark.png" alt="万象深色聊天界面" width="260"></td>
    <td><img src="docs/screenshots/settings.png" alt="万象服务商与模型设置" width="260"></td>
  </tr>
</table>

<sub>以上为 Flutter 测试渲染的模拟会话截图，用于展示布局，不是真机实拍或服务商线上回复。</sub>

## 一个入口，多种选择

| 能力 | 在万象中可以做什么 |
| --- | --- |
| **多服务商切换** | 内置八家服务商，在聊天页选择服务商与模型；各自保存接口配置与密钥。 |
| **流式对话** | 逐步阅读生成中的回复、随时取消；展示接口实际返回的思考片段。 |
| **会话延续** | 本地保存多会话历史，重新打开会话时恢复对应服务商和模型。 |
| **图片与文本附件** | 向支持视觉的模型发送图片，或附加 TXT、Markdown、JSON、CSV、代码等纯文本。 |
| **舒适阅读** | Markdown 回复、浅色与深色模式，让长对话更易阅读。 |
| **自己的配置** | 使用自己的 API Key、自定义模型 ID 和接口地址；Android 密钥加密保存在本机。 |

<a id="providers"></a>

## 连接你常用的服务商

| 服务商 | 默认接入协议 | 配置方式 |
| --- | --- | --- |
| DeepSeek | OpenAI 兼容 Chat Completions | DeepSeek API Key 与账号可用模型 |
| OpenAI | OpenAI Responses | OpenAI API Key 与账号可用模型 |
| Kimi · Moonshot | OpenAI 兼容 Chat Completions | Moonshot API Key 与账号可用模型 |
| Qwen · 通义千问 | OpenAI 兼容 Chat Completions | DashScope API Key；默认中国内地接口 |
| Anthropic · Claude | Anthropic Messages | Anthropic API Key 与账号可用模型 |
| Google · Gemini | Google Gemini | Gemini API Key 与账号可用模型 |
| xAI · Grok | OpenAI 兼容 Chat Completions | xAI API Key 与账号可用模型 |
| GLM · 智谱 | OpenAI 兼容 Chat Completions | 智谱 API Key 与账号可用模型 |
| 自定义 | 可选择上述四类协议 | 填写 Base URL、API Key 和模型 ID |

预置模型仅用于方便配置，不代表你的账号已经获得调用权限。请以服务商当前开放的模型、区域和账号权限为准；可在设置中修改模型 ID、接口地址和图片能力。兼容接口的具体行为可能因服务商而异。

<a id="quick-start"></a>

## 开始第一段对话

1. 前往 [v1.2.0 发布页](https://github.com/tingwu-h/wanxiang-chat-app/releases/tag/v1.2.0)查看版本说明与可用附件，也可以按下文从源码构建 APK。
2. 打开万象的**设置**，选择服务商并填写自己的 API Key。
3. 选择模型，或填写账号当前可用的自定义模型 ID；需要时调整 Base URL。
4. 保存配置，可使用**测试连接**检查接口，然后回到聊天页开始对话。
5. 在聊天页顶部切换服务商和模型。发送图片前，请确认所选模型具备视觉能力。

测试连接和聊天均会发出真实 API 请求，可能产生用量费用。API 资格、区域限制及计费由服务商管理；万象与这些服务商没有隶属关系。

### 从旧版升级

v1.2.0 的构建号为 **11**。为延续已有安装与数据，Android 包名仍为 `com.example.deepseek_chat`，沿用原有签名证书。不要为升级主动卸载旧版；真机覆盖安装与数据保留尚待验证，升级前建议导出重要聊天文字。

内部 Dart 包名、存储键和平台通道保留部分旧名称，用于兼容旧数据；对外品牌统一为**万象**。构建信息、APK 校验值与验证范围见 [v1.2.0 更新说明](docs/1.2.0-更新说明.md)。

## 你的密钥，你的数据

| 数据 | 保存或发送方式 |
| --- | --- |
| API Key | Android 使用 Keystore + AES-GCM 加密保存；普通设置不包含密钥。 |
| 聊天记录 | 保存在应用私有目录；聊天内容并非全部加密。 |
| 模型请求 | 发送到你配置的接口，包含认证信息、当前会话上下文及本次提交的附件内容。 |
| 聊天导出 | 包含聊天文字和附件名称，不包含 API Key、图片文件或本机图片路径。 |
| 系统备份 | 已排除应用数据；重要聊天文字请主动导出。 |

使用自定义地址前，请确认你信任该接口的运营方。提交问题反馈时，请去除密钥、私人聊天和其他敏感内容。

## 从源码运行

项目使用 Flutter + Provider。v1.2.0 已在 Flutter **3.47.5**、Dart **3.13.4**、JDK **17**、Android SDK **36** 的现有工具环境中完成构建；最低 Android 版本为 **7.0 / API 24**。

```powershell
git clone https://github.com/tingwu-h/wanxiang-chat-app.git
cd wanxiang-chat-app
flutter pub get
flutter analyze
flutter test
flutter run
```

运行前准备 Android 模拟器或已开启 USB 调试的 Android 手机，并通过 `flutter doctor` 检查本地环境。

<details>
<summary><strong>维护者离线构建与原签名升级</strong></summary>

```powershell
& .\tools\build-release-offline.ps1 -ToolRoot C:\dsbuild
```

该脚本使用维护者已有的 Flutter、JDK、Android SDK 与 Pub / Gradle 缓存，执行依赖解析、静态分析、测试、Release APK 构建和证书校验；不自动安装或上传。产物为 `dist/wanxiang-v1.2.0.apk`。

脚本沿用当前用户 Android 配置目录中的原有 `debug.keystore`，不移动或重建文件，并检查预期证书。签名文件不包含在仓库中；其他开发者自己的签名不能覆盖安装维护者签名的版本。

</details>

<details>
<summary><strong>协议与平台扩展结构</strong></summary>

- `ChatService`：定义通用聊天能力，供聊天状态层调用。
- [ApiProtocol](lib/services/api_protocol.dart)：处理不同服务商的请求和响应协议。
- [ProviderCatalog](lib/models/provider_catalog.dart)：维护服务商预置与配置入口。
- [PlatformBackend](lib/services/platform_service.dart)：隔离安全存储、导出和退出等平台服务。

后续桌面端可以复用聊天与协议逻辑，再实现对应系统的安全存储和文件导出。本版非 Android 的密钥回退仅保存在内存中，不能视为完整桌面支持。

</details>

### 已验证的范围

截至 **2026-10-03**：静态分析无问题，**51 项测试通过**，Release APK 构建成功，版本号、包名与原签名一致性已校验。

测试覆盖模拟协议请求、流式响应、多服务商密钥隔离、旧数据迁移及聊天回归。**八家服务商的真实账号调用与手机覆盖升级尚未实测**，模拟测试通过不代表所有账号和模型均可在线使用。

## 接下来

- 当前重点：完善 Android 的多模型体验，补充真实账号与真机升级验证。
- 后续方向：在现有平台接口基础上评估桌面端；暂未开始桌面端开发。
- 本版边界：不包含联网搜索、工具执行、语音或 PDF / Word 文档解析。

## 参与万象

欢迎通过 [Issues](https://github.com/tingwu-h/wanxiang-chat-app/issues) 反馈问题或提出建议，也欢迎提交 Pull Request。反馈时请提供应用版本、Android 版本、服务商、模型 ID 与可复现步骤；提交代码前运行静态分析及相关测试。

Logo 由项目所有者提供，品牌素材位于 [assets/branding](assets/branding)。项目采用 [MIT License](LICENSE)。

<div align="center">
  <br>
  <strong>万象，让不同模型在这里相遇。</strong><br>
  <a href="#top">回到顶部 ↑</a>
</div>
