import 'package:flutter_test/flutter_test.dart';

import 'package:deepseek_chat/models/app_settings.dart';
import 'package:deepseek_chat/models/chat_message.dart';
import 'package:deepseek_chat/services/deepseek_service.dart';

/// 纯逻辑层单元测试：不联网、不消耗 API 额度。
///
/// 运行：flutter test test/unit_test.dart
void main() {
  group('AppSettings', () {
    test('默认值：模型是 deepseek-flash，Base URL 是官方地址', () {
      final AppSettings s = AppSettings();
      expect(s.model, 'deepseek-flash');
      expect(s.baseUrl, 'https://api.deepseek.com');
      expect(s.hasApiKey, isFalse);
      expect(s.themeMode, 'system');
    });

    test('JSON 往返一致', () {
      final AppSettings s = AppSettings(
        apiKey: 'sk-abc',
        model: 'deepseek-reasoner',
        systemPrompt: '你是助手',
        temperature: 1.3,
        themeMode: 'dark',
      );
      final AppSettings back = AppSettings.fromJson(s.toJson());
      expect(back.apiKey, 'sk-abc');
      expect(back.model, 'deepseek-reasoner');
      expect(back.systemPrompt, '你是助手');
      expect(back.temperature, 1.3);
      expect(back.themeMode, 'dark');
    });

    test('API Key 掩码不泄露完整 Key', () {
      final AppSettings s = AppSettings(apiKey: 'sk-1234567890abcdef');
      expect(s.maskedApiKey.contains('abcdef'), isFalse);
      expect(s.maskedApiKey.startsWith('sk-123'), isTrue);
      expect(AppSettings().maskedApiKey, '未设置');
    });
  });

  group('ChatMessage', () {
    test('JSON 往返保留 role / 内容 / 错误标记', () {
      final List<ChatMessage> list = <ChatMessage>[
        ChatMessage.user('你好'),
        ChatMessage.assistant('你好！有什么可以帮你？'),
        ChatMessage(
          role: MessageRole.assistant,
          content: '出错了',
          error: true,
        ),
      ];
      final List<ChatMessage> back =
          ChatMessage.listFromJsonString(ChatMessage.listToJsonString(list));
      expect(back.length, 3);
      expect(back[0].isUser, isTrue);
      expect(back[1].isAssistant, isTrue);
      expect(back[1].content, '你好！有什么可以帮你？');
      expect(back[2].error, isTrue);
    });

    test('损坏的历史数据不会抛异常', () {
      expect(ChatMessage.listFromJsonString('').length, 0);
      expect(ChatMessage.listFromJsonString('这不是 json').length, 0);
      expect(ChatMessage.listFromJsonString('{"a":1}').length, 0);
    });
  });

  group('DeepSeekService.buildApiMessages', () {
    test('注入 system 提示词，并过滤错误气泡 / 空内容', () async {
      final DeepSeekService service = DeepSeekService();
      final List<Map<String, dynamic>> api = await service.buildApiMessages(
        <ChatMessage>[
          ChatMessage.user('你好'),
          ChatMessage(
            role: MessageRole.assistant,
            content: '哎呀',
            error: true,
          ),
          ChatMessage.assistant('   '),
          ChatMessage.assistant('正常回复'),
        ],
        systemPrompt: '你是 DeepSeek 助手',
      );

      expect(api.length, 3);
      expect(api[0]['role'], MessageRole.system);
      expect(api[0]['content'], '你是 DeepSeek 助手');
      expect(api[1]['content'], '你好');
      expect(api[2]['content'], '正常回复');
      service.dispose();
    });

    test('没有 system 提示词时不插入 system 消息', () async {
      final DeepSeekService service = DeepSeekService();
      final List<Map<String, dynamic>> api = await service.buildApiMessages(
        <ChatMessage>[ChatMessage.user('hi')],
      );
      expect(api.length, 1);
      expect(api.first['role'], MessageRole.user);
      service.dispose();
    });
  });
}
