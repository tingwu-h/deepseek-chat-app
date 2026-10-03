import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:deepseek_chat/models/app_settings.dart';
import 'package:deepseek_chat/models/chat_message.dart';
import 'package:deepseek_chat/models/conversation.dart';
import 'package:deepseek_chat/services/platform_service.dart';
import 'package:deepseek_chat/services/attachment_service.dart';

/// 普通设置与历史存入 shared_preferences；密钥独立存入平台安全存储。
///
/// 存储结构：
/// - `ds_settings`        ：设置（一个 JSON 对象）
/// - `ds_conversations`   ：会话 id 列表（JSON 数组），保持顺序（最近的在前面）
/// - `ds_conv_<id>`       ：每个会话的完整内容（一个 JSON 对象）
///
/// 会话分开存的好处：切换会话时不用把全部历史读进内存，改一个会话也只写一个 key。
class StorageService {
  StorageService({
    SharedPreferences? preferences,
    Future<String?> Function()? readKey,
    Future<void> Function(String)? writeKey,
  }) : _prefs = preferences,
       _readKey = readKey ?? PlatformService.readKey,
       _writeKey = writeKey ?? PlatformService.writeKey;
  final Future<String?> Function() _readKey;
  final Future<void> Function(String) _writeKey;

  static const String _kSettings = 'ds_settings';
  static const String _kConversations = 'ds_conversations';
  static const String _kConvPrefix = 'ds_conv_';
  static const String _kActiveConv = 'ds_active_conv';

  /// 旧版本的单份历史 key（需要迁移过来）
  static const String _kLegacyHistory = 'ds_chat_history';

  SharedPreferences? _prefs;
  Future<void> _writes = Future<void>.value();

  Future<void> _write(Future<void> Function() action) {
    final next = _writes.then((_) => action());
    _writes = next.catchError((Object _) {});
    return next;
  }

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
        final legacy = (decoded['apiKey'] as String?) ?? '';
        if (legacy.isNotEmpty) {
          await _writeKey(legacy);
          decoded.remove('apiKey');
          if (!await prefs.setString(_kSettings, jsonEncode(decoded))) {
            throw StateError('密钥迁移未完成');
          }
        }
        decoded['apiKey'] = await _readKey() ?? '';
        return AppSettings.fromJson(decoded);
      }
      return AppSettings();
    } on FormatException {
      return AppSettings();
    }
  }

  Future<void> saveSettings(AppSettings settings) => _write(() async {
    final SharedPreferences prefs = await _p;
    await _writeKey(settings.apiKey);
    final json = settings.toJson()..remove('apiKey');
    if (!await prefs.setString(_kSettings, jsonEncode(json))) {
      throw StateError('保存设置失败');
    }
  });

  // ------------------------------------------------------------------ 会话

  /// 读取全部会话（按最近更新排序）。
  ///
  /// 首次运行且存在旧版本单份历史时，会自动迁移成一个会话，并删掉旧 key。
  Future<List<Conversation>> loadConversations() async {
    final SharedPreferences prefs = await _p;
    final List<Conversation> result = <Conversation>[];

    // Recover records even if the index was lost or a previous write was interrupted.
    final List<String> ids = <String>{
      if (prefs.get(_kConversations) case final List<String> indexed)
        ...indexed,
      ...prefs
          .getKeys()
          .where((k) => k.startsWith(_kConvPrefix))
          .map((k) => k.substring(_kConvPrefix.length)),
    }.toList();
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

    result.sort(
      (Conversation a, Conversation b) => b.updatedAt.compareTo(a.updatedAt),
    );
    return result;
  }

  Future<void> saveConversation(Conversation conv) => _write(() async {
    final SharedPreferences prefs = await _p;

    // Never silently delete user history to enforce a UI capacity target.
    conv.updatedAt = DateTime.now();

    if (!await prefs.setString(
      '$_kConvPrefix${conv.id}',
      jsonEncode(conv.toJson()),
    )) {
      throw StateError('保存对话失败');
    }

    // 更新 id 索引（最近更新的排最前）
    final List<String> ids = prefs.getStringList(_kConversations) ?? <String>[];
    ids.remove(conv.id);
    ids.insert(0, conv.id);
    await prefs.setStringList(_kConversations, ids);
  });

  Future<void> deleteConversation(String id) => _write(() async {
    final SharedPreferences prefs = await _p;
    final deleted = _attachmentPaths(prefs.getString('$_kConvPrefix$id'));
    await prefs.remove('$_kConvPrefix$id');
    final List<String> ids = prefs.getStringList(_kConversations) ?? <String>[];
    ids.remove(id);
    await prefs.setStringList(_kConversations, ids);
    if (prefs.getString(_kActiveConv) == id) {
      await prefs.remove(_kActiveConv);
    }
    final retained = <String>{};
    for (final key in prefs.getKeys().where(
      (k) => k.startsWith(_kConvPrefix),
    )) {
      retained.addAll(_attachmentPaths(prefs.getString(key)));
    }
    for (final path in deleted.difference(retained)) {
      await AttachmentService.removeOwnedFile(path);
    }
  });

  Future<void> deleteAllConversations() => _write(() async {
    final SharedPreferences prefs = await _p;
    final List<String> ids = prefs
        .getKeys()
        .where((k) => k.startsWith(_kConvPrefix))
        .map((k) => k.substring(_kConvPrefix.length))
        .toList();
    final deleted = <String>{};
    for (final String id in ids) {
      deleted.addAll(_attachmentPaths(prefs.getString('$_kConvPrefix$id')));
      await prefs.remove('$_kConvPrefix$id');
    }
    await prefs.remove(_kConversations);
    await prefs.remove(_kActiveConv);
    await prefs.remove(_kLegacyHistory);
    for (final path in deleted) {
      await AttachmentService.removeOwnedFile(path);
    }
  });

  Future<String?> loadActiveConversationId() async {
    final SharedPreferences prefs = await _p;
    return prefs.getString(_kActiveConv);
  }

  Future<void> saveActiveConversationId(String id) async {
    final SharedPreferences prefs = await _p;
    await prefs.setString(_kActiveConv, id);
  }

  Set<String> _attachmentPaths(String? raw) {
    if (raw == null) return {};
    try {
      return Conversation.fromJson(jsonDecode(raw) as Map<String, dynamic>)
          .messages
          .expand((m) => m.attachments)
          .where((a) => a.isImage)
          .map((a) => a.path)
          .toSet();
    } catch (_) {
      return {};
    }
  }

  Future<String> exportHistory() async {
    final conversations = await loadConversations();
    return const JsonEncoder.withIndent('  ').convert({
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'note': '仅包含聊天文字及附件名称；不包含 API Key 和图片文件。',
      'conversations': conversations.map((c) {
        final json = c.toJson();
        for (final message in json['messages'] as List) {
          for (final attachment in (message['attachments'] as List? ?? [])) {
            attachment.remove('path');
          }
        }
        return json;
      }).toList(),
    });
  }
}
