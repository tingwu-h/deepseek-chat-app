import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:deepseek_chat/utils/app_info.dart';

/// 用系统浏览器打开任意 http(s) 链接。
///
/// 统一放在这里，是因为「打开链接」出现在好几处：
/// 关于页的链接、需要 API Key 时的申请入口。
/// 逻辑与失败兜底保持一致（失败时至少把网址显示出来，不静默失败）。
Future<void> openExternalUrl(BuildContext context, String url) async {
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  try {
    final bool ok = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!ok) throw Exception('无法打开');
  } catch (_) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('无法打开链接：$url')));
  }
}

/// 打开创作者的 GitHub 主页。
///
/// 优先尝试 GitHub App 的自定义 scheme（装了 App 就直接进 App），
/// App 不存在或它不接管这个 scheme 时，回退到网页版。
///
/// 只接受 github:// 与 https://github.com/ 开头的地址：
/// 自定义 scheme 可能被别的应用抢注，限制前缀可以避免跳到意料之外的应用。
Future<void> openGithubProfile(BuildContext context) async {
  final Uri? appUri = Uri.tryParse(kAuthorGithubScheme);
  if (appUri != null && appUri.scheme == 'github') {
    try {
      if (await canLaunchUrl(appUri)) {
        final bool ok = await launchUrl(
          appUri,
          mode: LaunchMode.externalApplication,
        );
        if (ok) return; // 成功打开 App，不用再走网页
      }
    } catch (_) {
      // 查询/启动 App 失败，继续走网页版
    }
  }
  if (!context.mounted) return;
  await openExternalUrl(context, kAuthorGithubUrl);
}

/// 打开 DeepSeek 开放平台（申请 API Key）
Future<void> openDeepSeekPlatform(BuildContext context) =>
    openExternalUrl(context, kDeepSeekPlatformUrl);
