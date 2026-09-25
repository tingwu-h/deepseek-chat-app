import 'dart:convert';

/// 对话中的一条消息。
///
/// 与 DeepSeek `/chat/completions` 的 message 结构保持一致：
/// `{"role": "system|user|assistant", "content": "..."}`，
/// 另外多存一个本地时间戳，用于列表右侧的时间显示与排序。
class ChatMessage {
  ChatMessage({
    required this.role,
    required this.content,
    DateTime? timestamp,
    this.error = false,
  }) : timestamp = timestamp ?? DateTime.now();

  /// 便捷构造：用户消息
  ChatMessage.user(String content)
      : this(role: MessageRole.user, content: content);

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

  bool get isUser => role == MessageRole.user;
  bool get isAssistant => role == MessageRole.assistant;
  bool get isSystem => role == MessageRole.system;

  /// 发送给 API 的 JSON。
  /// 注意：错误气泡与空内容不能进入上下文，否则会被服务端拒绝。
  Map<String, dynamic> toApiJson() => <String, dynamic>{
        'role': role,
        'content': content,
      };

  Map<String, dynamic> toJson() => <String, dynamic>{
        'role': role,
        'content': content,
        'timestamp': timestamp.millisecondsSinceEpoch,
        'error': error,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      role: (json['role'] as String?) ?? MessageRole.assistant,
      content: (json['content'] as String?) ?? '',
      timestamp: json['timestamp'] is int
          ? DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int)
          : (DateTime.tryParse('${json['timestamp']}') ?? DateTime.now()),
      error: json['error'] == true,
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
          .where((ChatMessage m) => m.content.isNotEmpty)
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
