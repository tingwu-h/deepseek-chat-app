import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:deepseek_chat/main.dart';
import 'package:deepseek_chat/pages/settings_page.dart';
import 'package:deepseek_chat/providers/app_settings_provider.dart';
import 'package:deepseek_chat/providers/chat_provider.dart';
import 'package:deepseek_chat/services/deepseek_service.dart';
import 'package:deepseek_chat/services/storage_service.dart';

void main() {
  testWidgets(
    'provider drafts preserve keys and save the selected native protocol',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService();
      final settings = AppSettingsProvider(storage: storage);
      final chat = ChatProvider(api: DeepSeekService(), storage: storage);
      await settings.init();
      await settings.update(apiKey: 'ds-fixture');
      await chat.init();
      await tester.pumpWidget(
        DeepSeekChatApp(settingsProvider: settings, chatProvider: chat),
      );
      final context = tester.element(find.byType(Scaffold).first);
      Navigator.of(context).pushNamed(SettingsPage.routeName);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('section-model')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('provider-deepseek')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OpenAI · GPT').last);
      await tester.pumpAndSettle();
      final field = find.widgetWithText(TextField, 'OpenAI · GPT API Key');
      expect(tester.widget<TextField>(field).controller!.text, isEmpty);
      await tester.enterText(field, 'openai-fixture');
      await tester.tap(find.byKey(const ValueKey('provider-openai')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('DeepSeek').last);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(
              find.widgetWithText(TextField, 'DeepSeek API Key'),
            )
            .controller!
            .text,
        'ds-fixture',
      );
      await tester.tap(find.byKey(const ValueKey('provider-deepseek')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OpenAI · GPT').last);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(field).controller!.text,
        'openai-fixture',
      );
      await tester.tap(find.text('保存').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认使用'));
      await tester.pumpAndSettle();
      expect(settings.settings.providerId, 'openai');
      expect(settings.settings.protocol, 'responses');
      expect(settings.apiKey, 'openai-fixture');
      final restored = await storage.loadSettings();
      expect(restored.forProvider('deepseek').apiKey, 'ds-fixture');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      chat.dispose();
    },
  );
}
