import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:deepseek_chat/utils/app_info.dart';

/// 用系统浏览器打开 DeepSeek 开放平台。
///
/// 统一放在这里，是因为「需要用户配 API Key」的提示出现在好几处
/// （新用户空态、未配置时点发送、设置页），逻辑和失败兜底要一致。
Future<void> openDeepSeekPlatform(BuildContext context) async {
  await _open(context, kDeepSeekPlatformUrl);
}

/// 打开任意链接，失败时把网址显示出来（没有浏览器可用时不至于静默失败）
Future<void> _open(BuildContext context, String url) async {
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
