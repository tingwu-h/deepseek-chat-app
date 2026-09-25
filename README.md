# DeepSeek 助手

一个第三方 DeepSeek 手机客户端。支持流式回复、图片理解、多会话历史，API Key 由你自己填写。

<p>
  <img alt="platform" src="https://img.shields.io/badge/platform-Android-3ddc84">
  <img alt="flutter" src="https://img.shields.io/badge/Flutter-3.22%2B-02569b">
  <img alt="license" src="https://img.shields.io/badge/license-MIT-blue">
  <img alt="version" src="https://img.shields.io/badge/version-1.1.0-orange">
</p>

## 下载

到 [Releases](../../releases/latest) 页面下载 `deepseek-chat-v1.1.0.apk`，传到手机点开安装。

> 支持 Android 7.0+（arm64-v8a / armeabi-v7a / x86_64）。

## 功能

- **流式回复** —— 边生成边显示，打字机效果；随时可以停止
- **发图片** —— 拍照或从相册选图，让模型看图说话（`deepseek-flash` 支持图像理解）
- **发文件** —— 支持 txt / md / json / csv 以及各种代码文件，内容会读进对话
- **多会话** —— 左侧抽屉管理历史对话，随时新建、切换、删除
- **本地保存** —— 对话记录存在手机本地，重开应用还在
- **Markdown 渲染** —— 代码块、列表都能正常显示，长按气泡可复制
- **深色模式** —— 跟随系统，也可以手动指定浅色 / 深色
- **模型可切换** —— 顶栏一键切换，还能自己填模型名

## 截图

> 欢迎提 PR 补充截图。

| 聊天 | 发图片 | 历史会话 | 设置 |
| :---: | :---: | :---: | :---: |
| _待补充_ | _待补充_ | _待补充_ | _待补充_ |

## 快速开始

需要 Flutter 3.22 或更高版本。

```bash
git clone https://github.com/tingwu-h/deepseek-chat-app.git
cd deepseek-chat-app
flutter pub get
flutter create . --platforms=android   # 补齐原生工程（图标、Gradle wrapper 等）
flutter run
```

启动后点右上角 **⋮ → 设置** 填入 API Key：

1. 打开 [platform.deepseek.com](https://platform.deepseek.com) 注册登录
2. 左侧 **API Keys** → 创建，复制 `sk-` 开头的字符串
3. 回到应用粘贴进设置页，点 **测试连接** 确认可用

> API Key 只保存在手机本地（`shared_preferences`），代码里没有硬编码，
> 也不会发给除了 DeepSeek 官方接口以外的任何服务器。

## 项目结构

```
lib/
├── main.dart                       入口：初始化存储、注入 Provider、主题与路由
├── models/                         数据模型（消息、附件、会话、设置）
├── services/
│   ├── deepseek_service.dart        API 调用（SSE 流式 + 多模态）
│   ├── storage_service.dart         本地持久化（多会话）
│   └── attachment_service.dart      选图 / 选文件
├── providers/                      状态管理
├── pages/                          聊天页、设置页
├── widgets/                        气泡、输入栏、会话抽屉等组件
├── theme/                          浅色 / 深色主题
└── utils/                          小工具
```

## 常见问题

**回复不是流式，而是一次性出现？**
部分代理会缓冲 SSE，检查是否开了会改写响应的网络中间层。

**报 401 / 402？**
401 是 Key 无效或过期；402 是账户余额不足，去[开放平台](https://platform.deepseek.com/top_up)充值。

**模型名报错？**
模型名以[官方文档](https://api-docs.deepseek.com/zh-cn/quick_start/pricing)为准。
官方改版后，到设置页的「自定义模型名」里填新的即可，不用改代码。

**聊天记录存在哪？怎么清？**
存在应用私有的 `shared_preferences` 里。
聊天页 **⋮ → 清空当前对话** 删当前会话，设置页可以清空全部。

## 说明

- 本项目是个人学习作品，与 DeepSeek 官方无关。
- 使用前请确认符合 [DeepSeek 服务条款](https://platform.deepseek.com)。
- 构建产物使用 debug 签名，安装时系统可能提示「未经安全检测」，继续安装即可。

## 许可证

[MIT](LICENSE)
