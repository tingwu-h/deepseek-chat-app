import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:deepseek_chat/main.dart';
import 'package:deepseek_chat/models/app_settings.dart';
import 'package:deepseek_chat/providers/app_settings_provider.dart';
import 'package:deepseek_chat/providers/chat_provider.dart';
import 'package:deepseek_chat/services/deepseek_service.dart';
import 'package:deepseek_chat/services/storage_service.dart';

/// 用假的 http.Client 替代真实网络请求。
class _FakeClient extends http.BaseClient {
  _FakeClient({this.streaming = true});

  final bool streaming;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final String body = streaming
        // 两个 SSE 数据帧 + 结束标记
        ? 'data: ${jsonEncode(<String, dynamic>{
            'choices': <dynamic>[
              <String, dynamic>{
                'delta': <String, dynamic>{'content': '你好'},
              }
            ],
          })}\n\n'
            'data: ${jsonEncode(<String, dynamic>{
              'choices': <dynamic>[
                <String, dynamic>{
                  'delta': <String, dynamic>{'content': '，世界'},
                }
              ],
            })}\n\n'
            'data: [DONE]\n\n'
        : jsonEncode(<String, dynamic>{
            'choices': <dynamic>[
              <String, dynamic>{
                'message': <String, dynamic>{'content': '你好，世界'},
              }
            ],
          });

    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(body)),
      200,
      headers: <String, String>{'content-type': 'text/event-stream'},
    );
  }
}

Future<_Harness> _buildHarness({bool streaming = true}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final StorageService storage = StorageService();
  final AppSettingsProvider settings =
      AppSettingsProvider(storage: storage);
  await settings.init();
  await settings.update(apiKey: 'sk-test-key');

  final ChatProvider chat = ChatProvider(
    api: DeepSeekService(client: _FakeClient(streaming: streaming)),
    storage: storage,
  );
  await chat.init();

  return _Harness(settings: settings, chat: chat);
}

class _Harness {
  _Harness({required this.settings, required this.chat});

  final AppSettingsProvider settings;
  final ChatProvider chat;

  Widget get app => DeepSeekChatApp(
        settingsProvider: settings,
        chatProvider: chat,
      );
}

void main() {
  testWidgets('首页展示标题、输入框与发送按钮', (WidgetTester tester) async {
    final _Harness h = await _buildHarness();
    await tester.pumpWidget(h.app);
    await tester.pumpAndSettle();

    expect(find.text('新对话'), findsOneWidget);
    expect(find.text('给 DeepSeek 发消息…'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
    expect(find.text('开始和 DeepSeek 聊天'), findsOneWidget);
  });

  testWidgets('设置入口唯一：只在 ⋮ 菜单里（回归：曾同时有齿轮和菜单两项）',
      (WidgetTester tester) async {
    final _Harness h = await _buildHarness();
    await tester.pumpWidget(h.app);
    await tester.pumpAndSettle();

    // 顶栏不再有齿轮图标（已收进 ⋮ 菜单）
    expect(find.byIcon(Icons.settings_outlined), findsNothing);

    // ⋮ 菜单里只有一个「设置」，且旧的「API Key 与设置」已不存在
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    expect(find.text('设置'), findsOneWidget);
    expect(find.text('API Key 与设置'), findsNothing);
    expect(find.text('清空当前对话'), findsOneWidget);
  });

  testWidgets('顶栏有新建对话按钮，点了会开新会话', (WidgetTester tester) async {
    final _Harness h = await _buildHarness();
    await tester.pumpWidget(h.app);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '第一轮提问');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await tester.pumpAndSettle();
    expect(h.chat.messages.length, 2);
    final String? firstId = h.chat.activeConversationId;

    await tester.tap(find.byIcon(Icons.add_comment_outlined));
    await tester.pumpAndSettle();

    // 新会话应为空，且 id 变了
    expect(h.chat.messages, isEmpty);
    expect(h.chat.activeConversationId, isNot(firstId));
    // 旧会话仍在列表里
    expect(h.chat.conversations.length, greaterThanOrEqualTo(2));
  });

  testWidgets('聊天页顶栏可以直接切换模型（回归：曾只能在设置页底部改）',
      (WidgetTester tester) async {
    final _Harness h = await _buildHarness();
    await tester.pumpWidget(h.app);
    await tester.pumpAndSettle();

    // 默认 deepseek-flash，顶栏胶囊显示 flash
    expect(find.text('flash'), findsOneWidget);
    expect(h.settings.model, 'deepseek-flash');

    // 点开模型菜单，选 deepseek-v4-pro
    await tester.tap(find.text('flash'));
    await tester.pumpAndSettle();
    expect(find.text('deepseek-v4-pro（强，复杂推理）'), findsOneWidget);

    await tester.tap(find.text('deepseek-v4-pro（强，复杂推理）'));
    await tester.pumpAndSettle();

    // 顶栏胶囊更新，且已持久化到设置
    expect(find.text('v4-pro'), findsOneWidget);
    expect(h.settings.model, 'deepseek-v4-pro');
  });

  testWidgets('发送消息后流式拼接助手回复', (WidgetTester tester) async {
    final _Harness h = await _buildHarness();
    await tester.pumpWidget(h.app);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '你好');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await tester.pumpAndSettle();

    // 助手回复由 flutter_markdown 渲染成富文本
    expect(find.textContaining('你好，世界'), findsOneWidget);
    expect(h.chat.messages.length, 2);
  });

  testWidgets('设置页显示 API Key 输入框（Key 不硬编码）', (WidgetTester tester) async {
    final _Harness h = await _buildHarness();
    await tester.pumpWidget(h.app);
    await tester.pumpAndSettle();

    // 现在设置入口在 ⋮ 菜单里
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();

    expect(find.text('DeepSeek API Key'), findsOneWidget);
    // 之前保存的测试 Key 应该回填到输入框
    expect(find.text('sk-test-key'), findsOneWidget);

    // 「测试连接」按钮在页面底部，ListView 懒加载还没构建它，
    // 必须先滚动到底部再断言（这是测试写法，不是应用问题）。
    await tester.scrollUntilVisible(
      find.text('测试连接'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('测试连接'), findsOneWidget);
  });

  test('AppSettings 默认值正确', () {
    final AppSettings s = AppSettings();
    expect(s.baseUrl, 'https://api.deepseek.com');
    expect(s.model, 'deepseek-flash');
    expect(s.hasApiKey, isFalse);
  });
}
