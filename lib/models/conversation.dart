import 'package:deepseek_chat/models/chat_message.dart';

/// 一个会话（对话）。
///
/// 之前只保存「一份当前历史」，无法新建对话、无法回看以前的对话；
/// 现在把每个会话独立保存，标题取第一条用户消息。
class Conversation {
  Conversation({
    required this.id,
    List<ChatMessage>? messages,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : messages = messages ?? <ChatMessage>[],
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  /// 唯一 id（用时间戳，够用且不引入额外依赖）
  final String id;

  final List<ChatMessage> messages;

  final DateTime createdAt;

  DateTime updatedAt;

  /// 列表里显示的标题：第一条用户消息的前 20 个字
  String get title {
    for (final ChatMessage m in messages) {
      if (m.isUser && m.content.trim().isNotEmpty) {
        final String t = m.content.replaceAll('\n', ' ').trim();
        return t.length <= 20 ? t : '${t.substring(0, 20)}…';
      }
    }
    // 只有图片没文字的情况
    for (final ChatMessage m in messages) {
      if (m.isUser && m.attachments.isNotEmpty) return '（图片/文件）';
    }
    return '新对话';
  }

  /// 列表右侧的摘要：最后一条有内容的消息
  String get preview {
    for (int i = messages.length - 1; i >= 0; i--) {
      final ChatMessage m = messages[i];
      if (m.content.trim().isNotEmpty) {
        final String t = m.content.replaceAll('\n', ' ').trim();
        return t.length <= 40 ? t : '${t.substring(0, 40)}…';
      }
    }
    return '暂无消息';
  }

  bool get isEmpty => messages.isEmpty;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'updatedAt': updatedAt.millisecondsSinceEpoch,
        'messages': messages.map((ChatMessage m) => m.toJson()).toList(),
      };

  factory Conversation.fromJson(Map<String, dynamic> json) {
    final List<dynamic> raw = (json['messages'] as List<dynamic>?) ?? <dynamic>[];
    return Conversation(
      id: (json['id'] as String?) ?? DateTime.now().microsecondsSinceEpoch.toString(),
      messages: raw
          .whereType<Map<String, dynamic>>()
          .map(ChatMessage.fromJson)
          .toList(),
      createdAt: json['createdAt'] is int
          ? DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int)
          : null,
      updatedAt: json['updatedAt'] is int
          ? DateTime.fromMillisecondsSinceEpoch(json['updatedAt'] as int)
          : null,
    );
  }

  static String newId() => DateTime.now().microsecondsSinceEpoch.toString();
}
