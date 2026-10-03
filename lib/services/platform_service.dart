import 'dart:io';

import 'package:flutter/services.dart';

/// Android implementation uses Keystore and the system document picker.
/// Unsupported platforms keep secrets in memory only, never plain preferences.
class PlatformService {
  static const channel = MethodChannel('deepseek_chat/platform');
  static String? _sessionKey;
  static Future<String?> readKey() async => Platform.isAndroid
      ? await channel.invokeMethod<String>('readKey')
      : _sessionKey;
  static Future<void> writeKey(String value) async {
    if (Platform.isAndroid) {
      await channel.invokeMethod<void>('writeKey', value);
    } else {
      _sessionKey = value;
    }
  }

  static Future<bool> exportHistory(String json) async =>
      await channel.invokeMethod<bool>('exportHistory', json) ?? false;
  static Future<void> goToDesktop() async {
    if (Platform.isAndroid) {
      await channel.invokeMethod<void>('goToDesktop');
    } else {
      await SystemNavigator.pop();
    }
  }
}
