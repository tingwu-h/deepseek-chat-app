import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:deepseek_chat/models/app_settings.dart';
import 'package:deepseek_chat/models/chat_message.dart';

/// 本地持久化：用 shared_preferences 保存设置与聊天历史。
///
/// - 设置整体存成一个 JSON 字符串（字段以后增加也不用改接口）
/// - 聊天历史存成一个 JSON 数组字符串
///
/// 如果想要「多会话 / 分页 / 全文搜索」，把本类换成 sqflite 实现即可，
/// 上层的 Provider 不需要改动。
class StorageService {
  StorageService({SharedPreferences? preferences}) : _prefs = preferences;

  static const String _kSettings = 'ds_settings';
  static const String _kHistory = 'ds_chat_history';

  /// 历史最多保留多少条，避免 shared_preferences 存太大
  static const int maxHistory = 500;

  SharedPreferences? _prefs;

  Future<SharedPreferences> get _p async =>
      _prefs ??= await SharedPreferences.getInstance();

  // ------------------------------------------------------------------ 设置

  Future<AppSettings> loadSettings() async {
    try {
      final SharedPreferences prefs = await _p;
      final String? raw = prefs.getString(_kSettings);
      if (raw == null || raw.isEmpty) return AppSettings();
      final Object? decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return AppSettings.fromJson(decoded);
      }
      return AppSettings();
    } catch (_) {
      return AppSettings();
    }
  }

  Future<void> saveSettings(AppSettings settings) async {
    final SharedPreferences prefs = await _p;
    await prefs.setString(_kSettings, jsonEncode(settings.toJson()));
  }

  // ------------------------------------------------------------------ 历史

  Future<List<ChatMessage>> loadHistory() async {
    try {
      final SharedPreferences prefs = await _p;
      return ChatMessage.listFromJsonString(prefs.getString(_kHistory) ?? '');
    } catch (_) {
      return <ChatMessage>[];
    }
  }

  Future<void> saveHistory(List<ChatMessage> messages) async {
    final SharedPreferences prefs = await _p;
    final List<ChatMessage> trimmed = messages.length > maxHistory
        ? messages.sublist(messages.length - maxHistory)
        : messages;
    await prefs.setString(_kHistory, ChatMessage.listToJsonString(trimmed));
  }

  Future<void> clearHistory() async {
    final SharedPreferences prefs = await _p;
    await prefs.remove(_kHistory);
  }
}
