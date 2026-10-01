import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:deepseek_chat/utils/app_info.dart';

/// 用系统浏览器打开任意 http(s) 链接。
///
/// 统一放在这里，是因为「打开链接」出现在好几处：
/// 关于页的三个链接与创作者主页、需要 API Key 时的申请入口。
/// 逻辑与失败兜底保持一致。
Future<void> openExternalUrl(BuildContext context, String url) async {
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  try {
    final bool ok = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!ok) throw Exception('无法打开');
  } catch (_) {
    // 没有浏览器可用时，至少把网址显示出来，而不是静默失败
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('无法打开链接：$url')));
  }
}

/// 打开 DeepSeek 开放平台（申请 API Key）
Future<void> openDeepSeekPlatform(BuildContext context) =>
    openExternalUrl(context, kDeepSeekPlatformUrl);
