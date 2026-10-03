import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:deepseek_chat/main.dart';
import 'package:deepseek_chat/providers/app_settings_provider.dart';
import 'package:deepseek_chat/widgets/message_list_view.dart';
import 'package:deepseek_chat/widgets/message_bubble.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:deepseek_chat/models/app_settings.dart';
import 'package:deepseek_chat/models/chat_message.dart';
import 'package:deepseek_chat/providers/chat_provider.dart';
import 'package:deepseek_chat/services/deepseek_service.dart';
import 'package:deepseek_chat/services/storage_service.dart';

class ControlledApi extends DeepSeekService {
  final controller = StreamController<ChatChunk>();
  bool cancelled = false;
  ControlledApi() {
    controller.onCancel = () {
      cancelled = true;
    };
  }
  @override
  Stream<ChatChunk> streamChat({
    required AppSettings settings,
    required List<ChatMessage> history,
  }) => controller.stream;
}

Future<void> tick() => Future<void>.delayed(const Duration(milliseconds: 60));

class BackProbe extends ChatProvider {
  BackProbe(StorageService storage)
    : super(api: DeepSeekService(), storage: storage);
  int calls = 0;
  @override
  Future<void> stopAndPersist() async {
    calls++;
  }
}

void main() {
  testWidgets('first back prompts, second back within two seconds exits once', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    final settings = AppSettingsProvider(storage: storage);
    final chat = BackProbe(storage);
    await settings.init();
    await chat.init();
    await tester.pumpWidget(
      DeepSeekChatApp(settingsProvider: settings, chatProvider: chat),
    );
    await tester.pumpAndSettle();
    int exits = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'SystemNavigator.pop') exits++;
        return null;
      },
    );
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('再按一次回到桌面'), findsOneWidget);
    expect(chat.calls, 0);
    expect(exits, 0);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(exits, 1);
    expect(chat.calls, 1);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
  });

  testWidgets(
    'review: partial reply keeps lightweight streaming rendering enabled',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageListView(
              messages: [
                ChatMessage.user('hello'),
                ChatMessage.assistant('partial'),
              ],
              isLoading: true,
            ),
          ),
        ),
      );
      final bubbles = tester.widgetList<MessageBubble>(
        find.byType(MessageBubble),
      );
      expect(
        bubbles.firstWhere((b) => b.message.isAssistant).showTyping,
        isTrue,
      );
    },
  );

  test(
    'review: stop cancels stream immediately without waiting for next chunk',
    () async {
      SharedPreferences.setMockInitialValues({});
      final api = ControlledApi();
      final p = ChatProvider(api: api, storage: StorageService());
      await p.init();
      final request = p.send('question', AppSettings(apiKey: 'test-only'));
      await tick();
      p.stop();
      await tick();
      final cancelledOnStop = api.cancelled;
      await api.controller.close();
      await request;
      api.dispose();
      expect(
        cancelledOnStop,
        isTrue,
        reason: 'Stop must cancel the pending network stream',
      );
    },
  );

  test(
    'review: switching conversations preserves received reply after restart',
    () async {
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService();
      final api = ControlledApi();
      final p = ChatProvider(api: api, storage: storage);
      await p.init();
      final request = p.send('question A', AppSettings(apiKey: 'test-only'));
      await tick();
      final idA = p.activeConversationId;
      api.controller.add(const ChatChunk('received reply A'));
      await tick();
      expect(p.messages.last.content, 'received reply A');
      await p.newConversation();
      await api.controller.close();
      await request;
      final reloaded = await storage.loadConversations();
      final a = reloaded.firstWhere((c) => c.id == idA);
      api.dispose();
      expect(
        a.messages.any((m) => m.content == 'received reply A'),
        isTrue,
        reason: 'Stream cleanup must save A, not the newly selected B',
      );
    },
  );

  test('review: API key masking accepts single character without crash', () {
    expect(() => AppSettings(apiKey: 'x').maskedApiKey, returnsNormally);
  });
}
