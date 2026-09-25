import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:deepseek_chat/models/app_settings.dart';
import 'package:deepseek_chat/models/chat_message.dart';
import 'package:deepseek_chat/models/conversation.dart';

/// 本地持久化：设置 + 多会话历史，都放在 shared_preferences 里。
///
/// 存储结构：
/// - `ds_settings`        ：设置（一个 JSON 对象）
/// - `ds_conversations`   ：会话 id 列表（JSON 数组），保持顺序（最近的在前面）
/// - `ds_conv_<id>`       ：每个会话的完整内容（一个 JSON 对象）
///
/// 会话分开存的好处：切换会话时不用把全部历史读进内存，改一个会话也只写一个 key。
class StorageService {
  StorageService({SharedPreferences? preferences}) : _prefs = preferences;

  static const String _kSettings = 'ds_settings';
  static const String _kConversations = 'ds_conversations';
  static const String _kConvPrefix = 'ds_conv_';
  static const String _kActiveConv = 'ds_active_conv';

  /// 旧版本的单份历史 key（需要迁移过来）
  static const String _kLegacyHistory = 'ds_chat_history';

  /// 单个会话最多保留多少条消息
  static const int maxMessagesPerConversation = 500;

  /// 最多保留多少个会话
  static const int maxConversations = 100;

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

  // ------------------------------------------------------------------ 会话

  /// 读取全部会话（按最近更新排序）。
  ///
  /// 首次运行且存在旧版本单份历史时，会自动迁移成一个会话，并删掉旧 key。
  Future<List<Conversation>> loadConversations() async {
    final SharedPreferences prefs = await _p;
    final List<Conversation> result = <Conversation>[];

    final List<String> ids =
        prefs.getStringList(_kConversations) ?? <String>[];
    for (final String id in ids) {
      final String? raw = prefs.getString('$_kConvPrefix$id');
      if (raw == null || raw.isEmpty) continue;
      try {
        final Object? decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          result.add(Conversation.fromJson(decoded));
        }
      } catch (_) {
        // 单个会话损坏就跳过，不影响其它会话
      }
    }

    // 旧数据迁移
    if (result.isEmpty) {
      final String legacy = prefs.getString(_kLegacyHistory) ?? '';
      final List<ChatMessage> old = ChatMessage.listFromJsonString(legacy);
      if (old.isNotEmpty) {
        final Conversation c = Conversation(
          id: Conversation.newId(),
          messages: old,
        );
        await saveConversation(c);
        await prefs.setStringList(_kConversations, <String>[c.id]);
        await prefs.setString(_kActiveConv, c.id);
        await prefs.remove(_kLegacyHistory);
        return <Conversation>[c];
      }
    }

    result.sort((Conversation a, Conversation b) =>
        b.updatedAt.compareTo(a.updatedAt));
    return result;
  }

  Future<void> saveConversation(Conversation conv) async {
    final SharedPreferences prefs = await _p;

    // 裁剪过长的会话
    List<ChatMessage> msgs = conv.messages;
    if (msgs.length > maxMessagesPerConversation) {
      msgs = msgs.sublist(msgs.length - maxMessagesPerConversation);
      conv.messages
        ..clear()
        ..addAll(msgs);
    }
    conv.updatedAt = DateTime.now();

    await prefs.setString(
      '$_kConvPrefix${conv.id}',
      jsonEncode(conv.toJson()),
    );

    // 更新 id 索引（最近更新的排最前）
    final List<String> ids =
        prefs.getStringList(_kConversations) ?? <String>[];
    ids.remove(conv.id);
    ids.insert(0, conv.id);
    // 超量时删掉最旧的
    while (ids.length > maxConversations) {
      final String dropped = ids.removeLast();
      await prefs.remove('$_kConvPrefix$dropped');
    }
    await prefs.setStringList(_kConversations, ids);
  }

  Future<void> deleteConversation(String id) async {
    final SharedPreferences prefs = await _p;
    await prefs.remove('$_kConvPrefix$id');
    final List<String> ids =
        prefs.getStringList(_kConversations) ?? <String>[];
    ids.remove(id);
    await prefs.setStringList(_kConversations, ids);
    if (prefs.getString(_kActiveConv) == id) {
      await prefs.remove(_kActiveConv);
    }
  }

  Future<void> deleteAllConversations() async {
    final SharedPreferences prefs = await _p;
    final List<String> ids =
        prefs.getStringList(_kConversations) ?? <String>[];
    for (final String id in ids) {
      await prefs.remove('$_kConvPrefix$id');
    }
    await prefs.remove(_kConversations);
    await prefs.remove(_kActiveConv);
  }

  Future<String?> loadActiveConversationId() async {
    final SharedPreferences prefs = await _p;
    return prefs.getString(_kActiveConv);
  }

  Future<void> saveActiveConversationId(String id) async {
    final SharedPreferences prefs = await _p;
    await prefs.setString(_kActiveConv, id);
  }
}
