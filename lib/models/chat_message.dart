import 'dart:convert';

import 'package:deepseek_chat/models/chat_attachment.dart';

/// 对话中的一条消息。
///
/// 与 DeepSeek `/chat/completions` 的 message 结构保持一致：
/// `{"role": "system|user|assistant", "content": "..."}`，
/// 另外多存一个本地时间戳，用于列表右侧的时间显示与排序。
///
/// 带附件时 content 会变成 block 数组（图片走 image_url），
/// 具体拼装见 [toApiJsonWithAttachments]。
class ChatMessage {
  ChatMessage({
    required this.role,
    required this.content,
    DateTime? timestamp,
    this.error = false,
    List<ChatAttachment>? attachments,
  })  : timestamp = timestamp ?? DateTime.now(),
        attachments = attachments ?? <ChatAttachment>[];

  /// 便捷构造：用户消息
  ChatMessage.user(String content, {List<ChatAttachment>? attachments})
      : this(
          role: MessageRole.user,
          content: content,
          attachments: attachments,
        );

  /// 便捷构造：助手消息
  ChatMessage.assistant(String content)
      : this(role: MessageRole.assistant, content: content);

  /// `system` / `user` / `assistant`
  final String role;

  /// 消息正文（流式输出时会被不断追加）
  String content;

  /// 本地时间
  final DateTime timestamp;

  /// 是否是「本地生成的错误提示气泡」（不参与下次请求的上下文）
  ///
  /// 注意：必须是可变的。ChatProvider 在流式接收失败时会把已经插入的空气泡
  /// 就地标记成错误气泡（`assistant.error = true`），final 会导致编译失败。
  bool error;

  /// 附件（图片 / 文本类文件）。只有用户消息会有。
  final List<ChatAttachment> attachments;

  bool get isUser => role == MessageRole.user;
  bool get isAssistant => role == MessageRole.assistant;
  bool get isSystem => role == MessageRole.system;

  /// 内容和附件都空才算空消息
  bool get isBlank => content.trim().isEmpty && attachments.isEmpty;

  /// 发送给 API 的 JSON（纯文本，无附件时用）。
  /// 注意：错误气泡与空内容不能进入上下文，否则会被服务端拒绝。
  Map<String, dynamic> toApiJson() => <String, dynamic>{
        'role': role,
        'content': content,
      };

  /// 发送给 API 的 JSON（带附件时用 block 数组）。
  ///
  /// 官方限制：图片只能出现在 user 消息里，且 content 必须是块数组。
  Future<Map<String, dynamic>> toApiJsonWithAttachments() async {
    final List<Map<String, dynamic>> blocks = <Map<String, dynamic>>[];
    if (content.trim().isNotEmpty) {
      blocks.add(<String, dynamic>{'type': 'text', 'text': content});
    }
    for (final ChatAttachment a in attachments) {
      final Map<String, dynamic>? b = await a.toApiBlock();
      if (b != null) blocks.add(b);
    }
    return <String, dynamic>{'role': role, 'content': blocks};
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'role': role,
        'content': content,
        'timestamp': timestamp.millisecondsSinceEpoch,
        'error': error,
        if (attachments.isNotEmpty)
          'attachments': attachments
              .map((ChatAttachment a) => a.toJson())
              .toList(),
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final List<dynamic> rawA =
        (json['attachments'] as List<dynamic>?) ?? <dynamic>[];
    return ChatMessage(
      role: (json['role'] as String?) ?? MessageRole.assistant,
      content: (json['content'] as String?) ?? '',
      timestamp: json['timestamp'] is int
          ? DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int)
          : (DateTime.tryParse('${json['timestamp']}') ?? DateTime.now()),
      error: json['error'] == true,
      attachments: rawA
          .whereType<Map<String, dynamic>>()
          .map(ChatAttachment.fromJson)
          .toList(),
    );
  }

  static List<ChatMessage> listFromJsonString(String raw) {
    if (raw.trim().isEmpty) return <ChatMessage>[];
    try {
      final dynamic decoded = jsonDecode(raw);
      if (decoded is! List) return <ChatMessage>[];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(ChatMessage.fromJson)
          .where((ChatMessage m) => !m.isBlank)
          .toList();
    } catch (_) {
      // 历史数据损坏时直接丢弃，避免整个 App 起不来
      return <ChatMessage>[];
    }
  }

  static String listToJsonString(List<ChatMessage> messages) =>
      jsonEncode(messages.map((ChatMessage m) => m.toJson()).toList());
}

/// role 常量，避免魔法字符串写错。
class MessageRole {
  const MessageRole._();

  static const String system = 'system';
  static const String user = 'user';
  static const String assistant = 'assistant';
}
