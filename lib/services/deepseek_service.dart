import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:deepseek_chat/models/app_settings.dart';
import 'package:deepseek_chat/models/chat_message.dart';

/// 流式返回的一小段内容。
class ChatChunk {
  const ChatChunk(this.text, {this.thinking = false});

  /// 本段的文字（可能为空串，例如只带 finish_reason 的最后一帧）
  final String text;

  /// 是否是 `deepseek-reasoner` 的思维链（reasoning_content）
  final bool thinking;

  bool get isEmpty => text.isEmpty;
}

/// 调用失败的异常，`message` 已经是可以直接展示给用户的中文提示。
class DeepSeekException implements Exception {
  DeepSeekException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// DeepSeek API 封装：`POST {baseUrl}/chat/completions`（OpenAI 兼容格式）。
///
/// 同时实现了：
/// - `stream: true` 的 SSE 逐字返回（打字机效果）
/// - `stream: false` 的一次性返回（自动降级 / 备用）
class DeepSeekService {
  DeepSeekService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// 单次请求最长等待时间（流式请求是「首包 + 每个数据块」的超时）
  static const Duration timeout = Duration(seconds: 90);

  /// 这个 App 默认用流式；如果某些路由器/代理吞掉了 SSE，会自动降级成非流式。
  static const bool preferStream = true;

  void dispose() => _client.close();

  Uri _endpoint(String baseUrl) {
    String base = baseUrl.trim();
    if (base.isEmpty) base = AppSettings.defaultBaseUrl;
    if (!base.startsWith('http://') && !base.startsWith('https://')) {
      base = 'https://$base';
    }
    // 允许用户直接粘贴 ".../chat/completions" 或 ".../v1"
    final int idx = base.indexOf('/chat/completions');
    if (idx >= 0) base = base.substring(0, idx);
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    return Uri.parse('$base/chat/completions');
  }

  Map<String, String> _headers(String apiKey) => <String, String>{
        'Content-Type': 'application/json; charset=utf-8',
        'Accept': 'text/event-stream, application/json',
        'Authorization': 'Bearer ${apiKey.trim()}',
      };

  /// 把 UI 上的消息整理成 API 需要的 `messages`（过滤错误气泡 / 空内容）。
  List<Map<String, dynamic>> buildApiMessages(
    List<ChatMessage> history, {
    String? systemPrompt,
  }) {
    final List<Map<String, dynamic>> result = <Map<String, dynamic>>[];
    final String sys = (systemPrompt ?? '').trim();
    if (sys.isNotEmpty) {
      result.add(<String, dynamic>{'role': MessageRole.system, 'content': sys});
    }
    for (final ChatMessage m in history) {
      if (m.error) continue;
      if (m.content.trim().isEmpty) continue;
      result.add(m.toApiJson());
    }
    return result;
  }

  Map<String, dynamic> _body({
    required String model,
    required List<Map<String, dynamic>> messages,
    required bool stream,
    required double temperature,
  }) =>
      <String, dynamic>{
        'model': model,
        'messages': messages,
        'stream': stream,
        'temperature': temperature,
      };

  // --------------------------------------------------------------- 流式请求

  /// 边收边吐的流式接口。
  ///
  /// 用法：
  /// ```dart
  /// await for (final chunk in service.streamChat(...)) {
  ///   setState(() => text += chunk.text);
  /// }
  /// ```
  Stream<ChatChunk> streamChat({
    required AppSettings settings,
    required List<ChatMessage> history,
  }) async* {
    final String apiKey = settings.apiKey.trim();
    if (apiKey.isEmpty) {
      throw DeepSeekException('还没有填写 API Key，请先到「设置」里填写。');
    }

    final Uri uri = _endpoint(settings.baseUrl);
    final List<Map<String, dynamic>> messages = buildApiMessages(
      history,
      systemPrompt: settings.systemPrompt,
    );
    if (messages.isEmpty) {
      throw DeepSeekException('没有可发送的内容。');
    }

    final http.Request request = http.Request('POST', uri)
      ..headers.addAll(_headers(apiKey))
      ..body = jsonEncode(_body(
        model: settings.model,
        messages: messages,
        stream: true,
        temperature: settings.temperature,
      ));

    final http.StreamedResponse response =
        await _client.send(request).timeout(timeout);

    // 服务端直接报错（401 / 402 / 429 ...）：把 JSON 里的 message 读出来
    if (response.statusCode != 200) {
      final String raw = await response.stream.bytesToString();
      throw DeepSeekException(
        _friendlyError(response.statusCode, raw),
        statusCode: response.statusCode,
      );
    }

    // ---------- 增量解析 SSE ----------
    // 注意：必须用 utf8.decoder 而不是 response.stream.transform(utf8.decoder)
    // 的简写形式在多字节字符（中文）跨 buffer 时也不会乱码 —— 两者等价，
    // 这里显式写出是为了强调字符集问题。
    final Stream<String> lines = response.stream
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter());

    await for (final String rawLine in lines.timeout(timeout)) {
      final String line = rawLine.trim();
      if (line.isEmpty) continue;

      // SSE 里还有 "event:" / "id:" / ":keep-alive" 等行，只要 data:
      if (!line.startsWith('data:')) continue;
      final String payload = line.substring(5).trim();
      if (payload.isEmpty) continue;
      if (payload == '[DONE]') break;

      Map<String, dynamic> json;
      try {
        final Object? decoded = jsonDecode(payload);
        if (decoded is! Map<String, dynamic>) continue;
        json = decoded;
      } catch (_) {
        // 半包/心跳等异常片段，跳过即可，不要中断整个回答
        continue;
      }

      // 有些兼容代理把错误塞在流里
      final Object? error = json['error'];
      if (error is Map && error['message'] is String) {
        throw DeepSeekException('服务端返回错误：${error['message']}');
      }

      final Object? choices = json['choices'];
      if (choices is! List || choices.isEmpty) continue;
      final Object? first = choices.first;
      if (first is! Map) continue;

      final Object? delta = first['delta'];
      if (delta is Map) {
        final Object? reasoning = delta['reasoning_content'];
        if (reasoning is String && reasoning.isNotEmpty) {
          yield ChatChunk(reasoning, thinking: true);
        }
        final Object? content = delta['content'];
        if (content is String && content.isNotEmpty) {
          yield ChatChunk(content);
        }
      } else {
        // 少数代理会把 stream 响应降级成完整 message
        final Object? message = first['message'];
        if (message is Map && message['content'] is String) {
          final String text = message['content'] as String;
          if (text.isNotEmpty) yield ChatChunk(text);
        }
      }
    }
  }

  // ------------------------------------------------------------- 非流式请求

  /// 备用方案：一次性拿完整答案。
  Future<String> completeChat({
    required AppSettings settings,
    required List<ChatMessage> history,
  }) async {
    final String apiKey = settings.apiKey.trim();
    if (apiKey.isEmpty) {
      throw DeepSeekException('还没有填写 API Key，请先到「设置」里填写。');
    }

    final http.Response response = await _client
        .post(
          _endpoint(settings.baseUrl),
          headers: _headers(apiKey),
          body: jsonEncode(_body(
            model: settings.model,
            messages: buildApiMessages(history,
                systemPrompt: settings.systemPrompt),
            stream: false,
            temperature: settings.temperature,
          )),
        )
        .timeout(timeout);

    final String raw = utf8.decode(response.bodyBytes, allowMalformed: true);
    if (response.statusCode != 200) {
      throw DeepSeekException(
        _friendlyError(response.statusCode, raw),
        statusCode: response.statusCode,
      );
    }

    try {
      final Map<String, dynamic> json =
          jsonDecode(raw) as Map<String, dynamic>;
      final List<dynamic> choices = json['choices'] as List<dynamic>;
      final Map<String, dynamic> message =
          (choices.first as Map<String, dynamic>)['message']
              as Map<String, dynamic>;
      return (message['content'] as String?) ?? '';
    } catch (e) {
      throw DeepSeekException('无法解析服务端返回：${e.toString()}');
    }
  }

  // ------------------------------------------------------------------ 工具

  /// 把 HTTP 状态码 + 响应体翻译成用户能看懂的中文提示。
  String _friendlyError(int statusCode, String rawBody) {
    String detail = '';
    try {
      final Object? decoded = jsonDecode(rawBody);
      if (decoded is Map && decoded['error'] is Map) {
        final Object? msg = (decoded['error'] as Map)['message'];
        if (msg is String) detail = msg;
      }
    } catch (_) {
      detail = rawBody.length > 200 ? rawBody.substring(0, 200) : rawBody;
    }

    final String prefix = switch (statusCode) {
      400 => '请求格式有误（400）',
      401 => 'API Key 无效或已过期（401）',
      402 => '账户余额不足（402）',
      403 => '没有权限访问该模型（403）',
      404 => '接口地址不存在（404），请检查 Base URL',
      422 => '请求参数不合法（422）',
      429 => '请求过于频繁或被限流（429），稍后再试',
      500 || 502 || 503 || 504 => 'DeepSeek 服务暂时不可用（$statusCode），请稍后重试',
      _ => '请求失败（$statusCode）',
    };
    return detail.isEmpty ? prefix : '$prefix：$detail';
  }

  /// 连通性自检：设置页的「测试连接」按钮用。
  Future<String> testConnection(AppSettings settings) async {
    final ChatMessage probe = ChatMessage.user('你好');
    final String reply = await completeChat(
      settings: settings,
      history: <ChatMessage>[probe],
    );
    return reply.isEmpty ? '（服务端返回了空内容）' : reply;
  }
}
