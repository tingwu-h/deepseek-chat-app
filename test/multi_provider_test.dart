import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:deepseek_chat/models/app_settings.dart';
import 'package:deepseek_chat/models/chat_message.dart';
import 'package:deepseek_chat/models/conversation.dart';
import 'package:deepseek_chat/services/api_protocol.dart';
import 'package:deepseek_chat/services/deepseek_service.dart';
import 'package:deepseek_chat/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('reply attribution persists without leaking into API messages', () {
    final message = ChatMessage.assistant('hello')
      ..providerId = 'anthropic'
      ..model = 'custom-claude';
    final restored = ChatMessage.fromJson(message.toJson());
    expect(restored.providerId, 'anthropic');
    expect(restored.model, 'custom-claude');
    expect(restored.toApiJson(), {'role': 'assistant', 'content': 'hello'});
    final s = AppSettings()
        .forProvider('google')
        .copyWith(model: 'custom-gemini');
    expect(
      s.copyWith(model: 'gemini-2.5-flash').modelChoices,
      contains('custom-gemini'),
    );
  });
  test(
    'provider keys and custom models survive restart without plaintext secrets',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      String? secure;
      final storage = StorageService(
        preferences: prefs,
        readKey: () async => secure,
        writeKey: (value) async {
          secure = value;
        },
      );
      var s = AppSettings(apiKey: 'ds-secret', model: 'ds-custom');
      s = s
          .forProvider('google')
          .copyWith(apiKey: 'google-secret', model: 'my-gemini');
      await storage.saveSettings(s);
      final raw = prefs.getString('ds_settings')!;
      expect(raw, isNot(contains('ds-secret')));
      expect(raw, isNot(contains('google-secret')));
      s = await storage.loadSettings();
      expect(s.apiKey, 'google-secret');
      expect(s.model, 'my-gemini');
      s = s.forProvider('deepseek');
      expect(s.apiKey, 'ds-secret');
      expect(s.model, 'ds-custom');
      expect(s.forProvider('anthropic').apiKey, isEmpty);
      await storage.saveSettings(AppSettings());
      expect(secure, isNot(contains('google-secret')));
    },
  );

  test(
    'legacy encrypted key and existing conversation survive v1.2 migration',
    () async {
      SharedPreferences.setMockInitialValues({
        'ds_settings': jsonEncode({
          'model': 'old-model',
          'baseUrl': 'https://api.deepseek.com',
        }),
      });
      String? secure = 'legacy-secret';
      final storage = StorageService(
        readKey: () async => secure,
        writeKey: (v) async {
          secure = v;
        },
      );
      var s = await storage.loadSettings();
      expect(s.providerId, 'deepseek');
      expect(s.apiKey, 'legacy-secret');
      await storage.saveSettings(
        s.forProvider('openai').copyWith(apiKey: 'new-secret'),
      );
      s = await storage.loadSettings();
      expect(s.forProvider('deepseek').apiKey, 'legacy-secret');
      final c = Conversation.fromJson({'id': 'old', 'messages': []});
      expect(c.providerId, isNull);
      c.providerId = 'google';
      c.model = 'my-model';
      await storage.saveConversation(c);
      final restored = (await storage.loadConversations()).single;
      expect(restored.providerId, 'google');
      expect(restored.model, 'my-model');
    },
  );

  test('native protocols map system, assistant and image blocks correctly', () {
    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': 'Be concise'},
      {
        'role': 'user',
        'content': [
          {'type': 'text', 'text': 'What is this?'},
          {
            'type': 'image_url',
            'image_url': {'url': 'data:image/png;base64,AQID'},
          },
        ],
      },
      {'role': 'assistant', 'content': 'A test'},
    ];
    final claude = ApiProtocol.body(
      AppSettings().forProvider('anthropic'),
      messages,
      true,
    );
    expect(claude['system'], 'Be concise');
    expect(
      claude['messages'][0]['content'][1]['source']['media_type'],
      'image/png',
    );
    final google = ApiProtocol.body(
      AppSettings().forProvider('google'),
      messages,
      true,
    );
    expect(google['contents'][1]['role'], 'model');
    expect(google['contents'][0]['parts'][1]['inlineData']['data'], 'AQID');
    final openai = ApiProtocol.body(
      AppSettings().forProvider('openai'),
      messages,
      true,
    );
    expect(openai['instructions'], 'Be concise');
    expect(openai['input'][0]['content'][1]['type'], 'input_image');
    expect(openai['input'][1]['content'][0]['type'], 'output_text');
    expect(openai['store'], false);
  });

  final fixtures = {
    'anthropic': [
      {
        'type': 'content_block_delta',
        'delta': {'type': 'thinking_delta', 'thinking': '分析'},
      },
      {
        'type': 'content_block_delta',
        'delta': {'type': 'text_delta', 'text': '你好'},
      },
      {'type': 'message_stop'},
    ],
    'google': [
      {
        'candidates': [
          {
            'content': {
              'parts': [
                {'text': '分析', 'thought': true},
              ],
            },
          },
        ],
      },
      {
        'candidates': [
          {
            'content': {
              'parts': [
                {'text': '你好'},
              ],
            },
            'finishReason': 'STOP',
          },
        ],
      },
    ],
    'openai': [
      {'type': 'response.reasoning_summary_text.delta', 'delta': '分析'},
      {'type': 'response.output_text.delta', 'delta': '你好'},
      {'type': 'response.completed'},
    ],
  };
  for (final id in fixtures.keys) {
    test(
      '$id streams Chinese text, thinking, completion and provider auth',
      () async {
        final s = AppSettings().forProvider(id).copyWith(apiKey: 'test-key');
        final api = DeepSeekService(
          client: MockClient((request) async {
            expect(request.url, ApiProtocol.endpoint(s, stream: true));
            final body = jsonDecode(request.body) as Map;
            expect(
              body.containsKey(
                id == 'google'
                    ? 'contents'
                    : id == 'openai'
                    ? 'input'
                    : 'messages',
              ),
              true,
            );
            if (id == 'anthropic') {
              expect(request.headers['x-api-key'], 'test-key');
              expect(request.headers['Authorization'], isNull);
            } else if (id == 'google') {
              expect(request.headers['x-goog-api-key'], 'test-key');
              expect(request.url.query, 'alt=sse');
              expect(request.url.toString(), isNot(contains('test-key')));
            } else {
              expect(request.headers['Authorization'], 'Bearer test-key');
            }
            return http.Response(
              fixtures[id]!.map((e) => 'data: ${jsonEncode(e)}\n\n').join(),
              200,
              headers: {'content-type': 'text/event-stream; charset=utf-8'},
            );
          }),
        );
        addTearDown(api.dispose);
        final parts = await api
            .streamChat(settings: s, history: [ChatMessage.user('你好')])
            .toList();
        expect(parts.where((p) => !p.thinking).map((p) => p.text).join(), '你好');
        expect(parts.where((p) => p.thinking).map((p) => p.text).join(), '分析');
        expect(parts.last.done, true);
      },
    );
  }

  for (final id in ['kimi', 'qwen', 'xai', 'glm', 'deepseek', 'openrouter']) {
    test('$id uses isolated OpenAI-compatible configuration', () async {
      final s = AppSettings().forProvider(id).copyWith(apiKey: '$id-key');
      final api = DeepSeekService(
        client: MockClient((r) async {
          expect(r.url, ApiProtocol.endpoint(s));
          expect(r.headers['Authorization'], 'Bearer $id-key');
          expect(jsonDecode(r.body)['model'], s.model);
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {'content': 'ok'},
                },
              ],
            }),
            200,
          );
        }),
      );
      addTearDown(api.dispose);
      expect(await api.testConnection(s), 'ok');
    });
  }
  test('reject insecure destinations and report native stream errors', () {
    expect(
      () => ApiProtocol.endpoint(AppSettings(baseUrl: 'http://example.com')),
      throwsFormatException,
    );
    expect(
      () =>
          ApiProtocol.endpoint(AppSettings(baseUrl: 'https://key@example.com')),
      throwsFormatException,
    );
    expect(
      () => ApiProtocol.decode('anthropic', {
        'error': {'message': 'overloaded'},
      }).toList(),
      throwsFormatException,
    );
    expect(
      () =>
          ApiProtocol.decode('responses', {'type': 'response.failed'}).toList(),
      throwsFormatException,
    );
  });
}
