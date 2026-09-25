import 'package:flutter/foundation.dart';

import 'package:deepseek_chat/models/app_settings.dart';
import 'package:deepseek_chat/models/chat_message.dart';
import 'package:deepseek_chat/services/deepseek_service.dart';
import 'package:deepseek_chat/services/storage_service.dart';

/// 对话状态：消息列表、流式接收、中断控制、本地持久化。
class ChatProvider extends ChangeNotifier {
  ChatProvider({
    required DeepSeekService api,
    required StorageService storage,
  })  : _api = api,
        _storage = storage;

  final DeepSeekService _api;
  final StorageService _storage;

  final List<ChatMessage> _messages = <ChatMessage>[];
  bool _loading = false;
  String? _error;
  bool _initialized = false;

  /// 每次发送分配一个自增 token，只有 token 匹配的流才允许写入界面。
  /// 这样「停止生成」之后旧流的残余数据不会污染新的一轮对话。
  int _activeToken = 0;

  List<ChatMessage> get messages => List<ChatMessage>.unmodifiable(_messages);

  /// 是否正在等待或接收回复
  bool get isLoading => _loading;

  /// 最近一次错误 / 提示（已经是中文）
  String? get error => _error;

  bool get isInitialized => _initialized;

  /// 读取本地历史
  Future<void> init() async {
    final List<ChatMessage> saved = await _storage.loadHistory();
    _messages
      ..clear()
      ..addAll(saved);
    _initialized = true;
    notifyListeners();
  }

  /// 发送一条用户消息，并流式接收助手回复。
  ///
  /// [settings] 由 AppSettingsProvider 传入，避免两个 Provider 之间互相依赖。
  Future<void> send(String text, AppSettings settings) async {
    final String content = text.trim();
    if (content.isEmpty || _loading) return;

    final int token = ++_activeToken;
    _error = null;

    _messages.add(ChatMessage.user(content));

    // 先放一个空气泡，流式内容会一段段追加进去，形成打字机效果
    final ChatMessage assistant = ChatMessage.assistant('');
    _messages.add(assistant);
    _loading = true;
    notifyListeners();
    await _persist();

    // 发给 API 的上下文：必须排除刚插入的那条空助手消息
    final List<ChatMessage> context = _messages
        .where((ChatMessage m) => !identical(m, assistant))
        .toList();

    bool receivedAny = false;
    try {
      await for (final ChatChunk chunk
          in _api.streamChat(settings: settings, history: context)) {
        if (token != _activeToken) break; // 用户点了停止 / 开了新一轮
        if (chunk.isEmpty) continue;
        receivedAny = true;
        assistant.content += chunk.text;
        notifyListeners();
      }

      // finished 表示这一轮正常跑完（没有被 stop / clear 打断）
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
      if (assistant.content.trim().isEmpty) {
        _messages.remove(assistant);
      }
      if (token == _activeToken) _loading = false;
      notifyListeners();
      await _persist();
    }
  }

  /// 停止生成：中断流式接收，已经收到的内容保留。
  void stop() {
    if (!_loading) return;
    _activeToken++; // 让正在跑的流失效
    _loading = false;
    _error = '已停止生成。';
    notifyListeners();
  }

  /// 离开页面时调用：中断流式请求，但保留已经收到的内容。
  /// （不要用 clearConversation，那会把整个会话删掉）
  Future<void> stopAndPersist() async {
    if (!_loading) return;
    _activeToken++;
    _loading = false;
    notifyListeners();
    await _persist();
  }

  /// 清空当前会话，同时清掉本地历史
  Future<void> clearConversation() async {
    _activeToken++;
    _messages.clear();
    _error = null;
    _loading = false;
    notifyListeners();
    await _storage.clearHistory();
  }

  /// 只清掉提示信息
  void dismissError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }

  Future<void> _persist() async {
    try {
      await _storage.saveHistory(_messages);
    } catch (_) {
      // 存储失败不应该影响聊天本身
    }
  }
}
