# 万象开发与构建指南

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
- [ApiProtocol](../lib/services/api_protocol.dart)：处理不同服务商的请求和响应协议。
- [ProviderCatalog](../lib/models/provider_catalog.dart)：维护服务商预置与配置入口。
- [PlatformBackend](../lib/services/platform_service.dart)：隔离安全存储、导出和退出等平台服务。

后续桌面端可以复用聊天与协议逻辑，再实现对应系统的安全存储和文件导出。本版非 Android 的密钥回退仅保存在内存中，不能视为完整桌面支持。

</details>

### 已验证的范围

截至 **2026-10-03**：静态分析无问题，**51 项测试通过**，Release APK 构建成功，版本号、包名与原签名一致性已校验。

测试覆盖模拟协议请求、流式响应、多服务商密钥隔离、旧数据迁移及聊天回归。**八家服务商的真实账号调用与手机覆盖升级尚未实测**，模拟测试通过不代表所有账号和模型均可在线使用。

