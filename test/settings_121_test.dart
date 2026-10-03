import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:deepseek_chat/main.dart';
import 'package:deepseek_chat/models/app_settings.dart';
import 'package:deepseek_chat/models/model_info.dart';
import 'package:deepseek_chat/models/provider_catalog.dart';
import 'package:deepseek_chat/pages/settings_page.dart';
import 'package:deepseek_chat/providers/app_settings_provider.dart';
import 'package:deepseek_chat/providers/chat_provider.dart';
import 'package:deepseek_chat/services/deepseek_service.dart';
import 'package:deepseek_chat/services/storage_service.dart';

Future<AppSettingsProvider> mount(
  WidgetTester tester, {
  DeepSeekService Function()? service,
  bool Function()? failWrites,
}) async {
  SharedPreferences.setMockInitialValues({});
  String? key;
  final storage = StorageService(
    readKey: () async => key,
    writeKey: (v) async {
      if (failWrites?.call() == true) throw StateError('storage unavailable');
      key = v;
    },
  );
  final settings = AppSettingsProvider(storage: storage);
  final chat = ChatProvider(api: DeepSeekService(), storage: storage);
  await settings.init();
  await settings.update(apiKey: 'fixture-original');
  await chat.init();
  addTearDown(chat.dispose);
  await tester.pumpWidget(
    DeepSeekChatApp(settingsProvider: settings, chatProvider: chat),
  );
  await tester.pumpAndSettle();
  Navigator.of(tester.element(find.byType(Scaffold))).push(
    MaterialPageRoute<void>(
      builder: (_) => SettingsPage(serviceFactory: service),
    ),
  );
  await tester.pumpAndSettle();
  return settings;
}

Future<void> tapVisible(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    target,
    180,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> group(WidgetTester tester, String id) =>
    tapVisible(tester, find.byKey(ValueKey('section-$id')));
Finder get keyField => find.widgetWithText(TextField, 'DeepSeek API Key');

void main() {
  testWidgets(
    'save feedback disappears and category content clears the header',
    (tester) async {
      await mount(tester);
      expect(find.text('设置已保存'), findsNothing);
      await group(tester, 'model');
      final header = find.byKey(const ValueKey('section-header-model'));
      final provider = find.byKey(const ValueKey('provider-deepseek'));
      expect(
        tester.getTopLeft(provider).dy - tester.getBottomLeft(header).dy,
        greaterThanOrEqualTo(12),
      );
      expect(tester.widget<Material>(header).clipBehavior, Clip.hardEdge);
      await tester.enterText(keyField, 'save-test');
      await tester.pump();
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.text('设置已保存'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.text('设置已保存'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'five collapsed categories fit small screens; theme and edits survive folding',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final settings = await mount(tester);
      expect(find.byType(TextField), findsNothing);
      for (final id in ['model', 'chat', 'appearance', 'data', 'about']) {
        expect(find.byKey(ValueKey('section-$id')), findsOneWidget);
      }
      await group(tester, 'model');
      await tester.ensureVisible(keyField);
      await tester.enterText(keyField, 'edited-key');
      await tester.pumpAndSettle();
      await group(tester, 'model');
      await group(tester, 'appearance');
      await tapVisible(tester, find.text('深色'));
      expect(settings.themeModeName, 'dark');
      expect(settings.apiKey, 'fixture-original');
      await group(tester, 'appearance');
      await group(tester, 'model');
      expect(tester.widget<TextField>(keyField).controller!.text, 'edited-key');
      expect(find.text('有未保存的修改'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'back offers continue, discard or save without silently losing edits',
    (tester) async {
      final settings = await mount(tester);
      await group(tester, 'model');
      await tester.enterText(keyField, 'new-key');
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('保存修改？'), findsOneWidget);
      await tester.tap(find.text('继续编辑'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(keyField).controller!.text, 'new-key');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存并返回'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsPage), findsNothing);
      expect(settings.apiKey, 'new-key');
    },
  );

  testWidgets('discard does not persist a key draft', (tester) async {
    final settings = await mount(tester);
    await group(tester, 'model');
    await tester.enterText(keyField, 'discarded');
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('放弃修改'));
    await tester.pumpAndSettle();
    expect(settings.apiKey, 'fixture-original');
    expect(find.byType(SettingsPage), findsNothing);
  });

  testWidgets('save failure leaves draft editable; retry commits it', (
    tester,
  ) async {
    var fail = false;
    final settings = await mount(tester, failWrites: () => fail);
    await group(tester, 'model');
    await tester.enterText(keyField, 'retry-key');
    await tester.pumpAndSettle();
    fail = true;
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(settings.apiKey, 'fixture-original');
    expect(find.text('有未保存的修改'), findsOneWidget);
    expect(tester.widget<TextField>(keyField).controller!.text, 'retry-key');
    fail = false;
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(settings.apiKey, 'retry-key');
    expect(find.text('有未保存的修改'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('connection test uses draft but does not silently save it', (
    tester,
  ) async {
    var calls = 0;
    final settings = await mount(
      tester,
      service: () => DeepSeekService(
        client: MockClient((request) async {
          calls++;
          expect(request.headers['Authorization'], 'Bearer draft-key');
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {'content': 'OK'},
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      ),
    );
    await group(tester, 'model');
    await tester.enterText(keyField, 'draft-key');
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('测试连接'));
    expect(calls, 1);
    expect(settings.apiKey, 'fixture-original');
    expect(find.text('连接成功：OK'), findsOneWidget);
    expect(find.text('有未保存的修改'), findsOneWidget);
  });

  testWidgets('empty custom model cannot save; reopening retains validation', (
    tester,
  ) async {
    final settings = await mount(tester);
    await group(tester, 'model');
    await tapVisible(
      tester,
      find.byKey(const ValueKey('model-deepseek-deepseek-flash-false')),
    );
    await tester.tap(find.text('自定义模型').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('请选择或填写模型'), findsOneWidget);
    expect(settings.model, 'deepseek-flash');
    final custom = find.widgetWithText(TextField, '模型 ID');
    await tester.ensureVisible(custom);
    await tester.enterText(custom, 'my-model');
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(settings.model, 'my-model');
  });

  testWidgets(
    'free shortcut configures provider, shows key channel and fee details',
    (tester) async {
      final settings = await mount(tester);
      await group(tester, 'model');
      await tapVisible(tester, find.text('选择免费模型'));
      await tester.tap(find.text('免费模型自动选择'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('provider-openrouter')), findsOneWidget);
      expect(find.text('获取 API Key'), findsOneWidget);
      expect(
        presetFor('openrouter').platform,
        'https://openrouter.ai/settings/keys',
      );
      expect(settings.settings.providerId, 'deepseek');
      await tapVisible(tester, find.text('查看免费额度说明'));
      // The link helper handles a platform without a browser; no credential is exposed.
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'keyboard leaves model editing and save accessible on a small screen',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      final settings = await mount(tester);
      await group(tester, 'model');
      tester.view.viewInsets = const FakeViewPadding(bottom: 250);
      await tester.pumpAndSettle();
      await tester.ensureVisible(keyField);
      await tester.enterText(keyField, 'keyboard-key');
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(settings.apiKey, 'keyboard-key');
      expect(tester.takeException(), isNull);
    },
  );

  test('known presets have hints; unknown IDs do not inherit free claims', () {
    for (final p in providerCatalog.where((p) => p.id != 'custom')) {
      for (final model in p.models) {
        expect(
          modelInfo(p.id, model).tags,
          isNot(contains('能力待确认')),
          reason: '${p.id}/$model',
        );
      }
    }
    expect(modelFreeNote('custom', 'gemini-2.5-flash-lite'), isNull);
    expect(modelFreeNote('openrouter', 'qwen/other:free'), isNull);
    expect(modelInfo('custom', 'new-model').tags, contains('能力待确认'));
    final config = AppSettings().forProvider('openrouter');
    expect(config.apiKey, isEmpty);
    expect(config.model, 'openrouter/free');
    expect(
      AppSettings()
          .forProvider('google')
          .copyWith(model: 'gemini-2.5-flash-lite')
          .supportsImages,
      isTrue,
    );
    expect(config.supportsImages, isTrue);
  });
}
