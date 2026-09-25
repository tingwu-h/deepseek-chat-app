import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:deepseek_chat/main.dart';
import 'package:deepseek_chat/models/app_settings.dart';
import 'package:deepseek_chat/models/chat_message.dart';
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
        // 一个思考帧 + 两个正文帧 + 结束标记
        // 思考帧用来验证 reasoning_content 不会被混进正文
        ? 'data: ${jsonEncode(<String, dynamic>{
            'choices': <dynamic>[
              <String, dynamic>{
                'delta': <String, dynamic>{
                  'reasoning_content': '我需要先想想怎么回答。',
                },
              }
            ],
          })}\n\n'
            'data: ${jsonEncode(<String, dynamic>{
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

  testWidgets('设置入口唯一：只在会话抽屉里（回归：曾齿轮/菜单/抽屉三处重复）',
      (WidgetTester tester) async {
    final _Harness h = await _buildHarness();
    await tester.pumpWidget(h.app);
    await tester.pumpAndSettle();

    // 顶栏不再有齿轮图标
    expect(find.byIcon(Icons.settings_outlined), findsNothing);

    // ⋮ 菜单里只有「清空当前对话」，没有设置
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    expect(find.text('清空当前对话'), findsOneWidget);
    expect(find.text('设置'), findsNothing);
    expect(find.text('API Key 与设置'), findsNothing);

    // 关掉菜单，打开会话抽屉，设置在这里
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    expect(find.text('设置'), findsOneWidget);
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

    // 回归：思考过程必须和正文分开，不能混在一起
    final ChatMessage reply = h.chat.messages.last;
    expect(reply.content, '你好，世界');
    expect(reply.content.contains('我需要先想想'), isFalse);
    expect(reply.thinking, '我需要先想想怎么回答。');
    // 思考过程默认收起，界面上只显示「点击展开」的提示
    expect(find.textContaining('思考过程'), findsOneWidget);
    expect(find.textContaining('我需要先想想'), findsNothing);
  });

  testWidgets('设置页显示 API Key 输入框（Key 不硬编码）', (WidgetTester tester) async {
    final _Harness h = await _buildHarness();
    await tester.pumpWidget(h.app);
    await tester.pumpAndSettle();

    // 设置入口在会话抽屉底部
    await tester.tap(find.byIcon(Icons.menu));
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
