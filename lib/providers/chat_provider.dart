import 'package:flutter/foundation.dart';

import 'package:deepseek_chat/models/app_settings.dart';
import 'package:deepseek_chat/models/chat_attachment.dart';
import 'package:deepseek_chat/models/chat_message.dart';
import 'package:deepseek_chat/models/conversation.dart';
import 'package:deepseek_chat/services/deepseek_service.dart';
import 'package:deepseek_chat/services/storage_service.dart';

/// 对话状态：多会话管理 + 流式接收 + 中断控制 + 本地持久化。
class ChatProvider extends ChangeNotifier {
  ChatProvider({
    required DeepSeekService api,
    required StorageService storage,
  })  : _api = api,
        _storage = storage;

  final DeepSeekService _api;
  final StorageService _storage;

  /// 全部会话
  final List<Conversation> _conversations = <Conversation>[];

  /// 当前会话
  Conversation? _active;

  bool _loading = false;
  String? _error;
  bool _initialized = false;

  /// 每次发送分配一个自增 token，只有 token 匹配的流才允许写入界面。
  /// 这样「停止生成」之后旧流的残余数据不会污染新的一轮对话。
  int _activeToken = 0;

  // ------------------------------------------------------------ 对外读取

  /// 当前会话的消息（UI 直接绑定这个）
  List<ChatMessage> get messages =>
      List<ChatMessage>.unmodifiable(_active?.messages ?? <ChatMessage>[]);

  /// 会话列表（最近更新在前）
  List<Conversation> get conversations {
    final List<Conversation> copy = List<Conversation>.from(_conversations);
    copy.sort((Conversation a, Conversation b) =>
        b.updatedAt.compareTo(a.updatedAt));
    return List<Conversation>.unmodifiable(copy);
  }

  String? get activeConversationId => _active?.id;

  /// 当前会话标题（顶栏显示）
  String get activeTitle => _active?.title ?? '新对话';

  bool get isLoading => _loading;
  String? get error => _error;
  bool get isInitialized => _initialized;
  bool get hasMessages => _active?.messages.isNotEmpty ?? false;

  // ---------------------------------------------------------------- 初始化

  Future<void> init() async {
    final List<Conversation> loaded = await _storage.loadConversations();
    _conversations
      ..clear()
      ..addAll(loaded);

    final String? activeId = await _storage.loadActiveConversationId();
    if (_conversations.isEmpty) {
      _active = Conversation(id: Conversation.newId());
      _conversations.add(_active!);
    } else {
      _active = _conversations.firstWhere(
        (Conversation c) => c.id == activeId,
        orElse: () => _conversations.first,
      );
    }
    _initialized = true;
    notifyListeners();
  }

  // ------------------------------------------------------------ 会话操作

  /// 开一个新会话（当前会话本来就是空的就不重复新建）
  Future<void> newConversation() async {
    _activeToken++; // 中断可能正在跑的流
    _loading = false;
    _error = null;

    if (_active != null && _active!.isEmpty) {
      notifyListeners();
      return;
    }
    final Conversation c = Conversation(id: Conversation.newId());
    _conversations.insert(0, c);
    _active = c;
    notifyListeners();
    await _storage.saveActiveConversationId(c.id);
  }

  /// 切换到指定会话
  Future<void> switchConversation(String id) async {
    final int idx = _conversations.indexWhere((Conversation c) => c.id == id);
    if (idx < 0) return;
    _activeToken++;
    _loading = false;
    _error = null;
    _active = _conversations[idx];
    notifyListeners();
    await _storage.saveActiveConversationId(id);
  }

  /// 删除一个会话
  Future<void> deleteConversation(String id) async {
    _conversations.removeWhere((Conversation c) => c.id == id);
    await _storage.deleteConversation(id);
    if (_active?.id == id) {
      _activeToken++;
      _loading = false;
      if (_conversations.isEmpty) {
        _active = Conversation(id: Conversation.newId());
        _conversations.add(_active!);
      } else {
        _active = _conversations.first;
      }
      await _storage.saveActiveConversationId(_active!.id);
    }
    notifyListeners();
  }

  /// 清空全部会话
  Future<void> clearAllConversations() async {
    _activeToken++;
    _loading = false;
    _error = null;
    _conversations.clear();
    await _storage.deleteAllConversations();
    _active = Conversation(id: Conversation.newId());
    _conversations.add(_active!);
    notifyListeners();
  }

  // ---------------------------------------------------------------- 发送

  /// 发送一条用户消息，并流式接收助手回复。
  ///
  /// [settings] 由 AppSettingsProvider 传入，避免两个 Provider 之间互相依赖。
  /// [attachments] 图片 / 文本文件；可以只发附件不写文字。
  Future<void> send(
    String text,
    AppSettings settings, {
    List<ChatAttachment> attachments = const <ChatAttachment>[],
  }) async {
    final String content = text.trim();
    if (content.isEmpty && attachments.isEmpty) return;
    if (_loading) return;

    final Conversation? conv = _active;
    if (conv == null) return;

    final int token = ++_activeToken;
    _error = null;

    conv.messages.add(ChatMessage.user(
      content,
      attachments: List<ChatAttachment>.from(attachments),
    ));

    // 先放一个空气泡，流式内容会一段段追加进去，形成打字机效果
    final ChatMessage assistant = ChatMessage.assistant('');
    conv.messages.add(assistant);
    _loading = true;
    notifyListeners();
    await _persist();

    // 发给 API 的上下文：必须排除刚插入的那条空助手消息
    final List<ChatMessage> context = conv.messages
        .where((ChatMessage m) => !identical(m, assistant))
        .toList();

    bool receivedAny = false;
    try {
      await for (final ChatChunk chunk
          in _api.streamChat(settings: settings, history: context)) {
        if (token != _activeToken) break; // 用户点了停止 / 切换了会话
        if (chunk.isEmpty) continue;
        receivedAny = true;
        assistant.content += chunk.text;
        notifyListeners();
      }

      final bool finished = token == _activeToken;
      if (finished && assistant.content.trim().isEmpty) {
        assistant.content = '（模型没有返回内容，请重试或换一个模型）';
        assistant.error = true;
      }
    } catch (e) {
      final String msg =
          e is DeepSeekException ? e.message : '请求失败：${e.toString()}';

      if (token == _activeToken && !receivedAny) {
        // 一个字都没收到：把空气泡换成错误气泡，不留空白
        assistant.content = msg;
        assistant.error = true;
      } else if (token == _activeToken) {
        // 已经收到一部分：保留内容，把错误追加在后面
        assistant.content += '\n\n> ⚠️ 连接中断：$msg';
      }
      if (token == _activeToken) _error = msg;
    } finally {
      // 空内容气泡直接丢掉，避免历史里出现空白消息
      if (assistant.isBlank) {
        conv.messages.remove(assistant);
      }
      if (token == _activeToken) _loading = false;
      notifyListeners();
      await _persist();
    }
  }

  /// 停止生成：中断流式接收，已经收到的内容保留。
  void stop() {
    if (!_loading) return;
    _activeToken++;
    _loading = false;
    _error = '已停止生成。';
    notifyListeners();
  }

  /// 离开页面时调用：中断流式请求，但保留已经收到的内容。
  Future<void> stopAndPersist() async {
    if (!_loading) return;
    _activeToken++;
    _loading = false;
    notifyListeners();
    await _persist();
  }

  /// 只清掉提示信息
  void dismissError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }

  Future<void> _persist() async {
    final Conversation? conv = _active;
    if (conv == null) return;
    try {
      await _storage.saveConversation(conv);
      await _storage.saveActiveConversationId(conv.id);
    } catch (_) {
      // 存储失败不应该影响聊天本身
    }
  }
}
