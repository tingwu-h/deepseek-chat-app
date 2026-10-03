import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:deepseek_chat/models/app_settings.dart';
import 'package:deepseek_chat/models/chat_message.dart';
import 'package:deepseek_chat/providers/chat_provider.dart';
import 'package:deepseek_chat/services/deepseek_service.dart';
import 'package:deepseek_chat/services/storage_service.dart';

/// 专测「历史对话」相关的持久化：这类 bug 会让用户丢数据，必须有测试守着。
void main() {
  test('保存会话后，重建 Provider 仍能读到历史（模拟关掉 App 再打开）', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final StorageService storage = StorageService();

    // 第一次：写入两条消息
    final ChatProvider first = ChatProvider(
      api: _offlineApi(),
      storage: storage,
    );
    await first.init();
    first.messages; // 触发读取
    await first.send('你好', _fakeSettings());
    // send 里会先插 user 再插 assistant（假 Key 下会失败成错误气泡，但消息应留存）
    expect(first.messages.isNotEmpty, isTrue);

    // 第二次：全新 Provider，应该还能看到
    final ChatProvider second = ChatProvider(
      api: _offlineApi(),
      storage: storage,
    );
    await second.init();
    expect(second.messages.isNotEmpty, isTrue, reason: '重开后历史不见了，说明没有正确落盘或读取');
    expect(second.messages.first.content, '你好');
    expect(
      second.conversations.where((c) => !c.isEmpty).length,
      greaterThanOrEqualTo(1),
    );
  });

  test('旧版本的单份历史（ds_chat_history）能被迁移过来', () async {
    // 模拟 v1.0.1 时代留下的数据
    final List<ChatMessage> legacy = <ChatMessage>[
      ChatMessage.user('旧版本的提问'),
      ChatMessage.assistant('旧版本的回答'),
    ];
    SharedPreferences.setMockInitialValues(<String, Object>{
      'ds_chat_history': ChatMessage.listToJsonString(legacy),
    });

    final StorageService storage = StorageService();
    final ChatProvider provider = ChatProvider(
      api: _offlineApi(),
      storage: storage,
    );
    await provider.init();

    expect(provider.messages.length, 2, reason: '旧数据没有迁移过来 —— 升级后用户会以为历史丢了');
    expect(provider.messages.first.content, '旧版本的提问');

    // 迁移后旧 key 应被清掉，且新结构里确实有数据
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('ds_chat_history'), isNull);
    expect(prefs.getStringList('ds_conversations'), isNotNull);
  });

  test('多会话：新建后旧会话仍在，切换回来内容不丢', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final StorageService storage = StorageService();
    final ChatProvider provider = ChatProvider(
      api: _offlineApi(),
      storage: storage,
    );
    await provider.init();

    // 会话 A
    await provider.send('A 的问题', _fakeSettings());
    final String? idA = provider.activeConversationId;
    expect(idA, isNotNull);
    final int countA = provider.messages.length;

    // 新建会话 B
    await provider.newConversation();
    expect(provider.messages, isEmpty);
    expect(provider.activeConversationId, isNot(idA));

    // 切回 A
    await provider.switchConversation(idA!);
    expect(provider.messages.length, countA, reason: '切回旧会话后内容丢失');

    // 再整体重载一次，两个会话都应在
    final ChatProvider reloaded = ChatProvider(
      api: _offlineApi(),
      storage: storage,
    );
    await reloaded.init();
    expect(reloaded.conversations.length, greaterThanOrEqualTo(2));
  });

  test('重命名会话会落盘，重载后名字还在', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final StorageService storage = StorageService();
    final ChatProvider p = ChatProvider(api: _offlineApi(), storage: storage);
    await p.init();
    await p.send('原始内容', _fakeSettings());
    final String id = p.activeConversationId!;

    // 改名前是自动标题
    expect(p.activeTitle, '原始内容');

    await p.renameConversation(id, '我的自定义名字');
    expect(p.activeTitle, '我的自定义名字');

    // 重载后仍是自定义名字
    final ChatProvider reloaded = ChatProvider(
      api: _offlineApi(),
      storage: storage,
    );
    await reloaded.init();
    final custom = reloaded.conversations.firstWhere((c) => c.id == id);
    expect(custom.title, '我的自定义名字');
    expect(custom.hasCustomTitle, isTrue);

    // 传空串应恢复自动标题
    await reloaded.renameConversation(id, '   ');
    expect(reloaded.conversations.firstWhere((c) => c.id == id).title, '原始内容');
  });

  test('存储里缺索引 key 但内容还在时，不应当静默丢光（当前行为的记录）', () async {
    // 记录一个真实的脆弱点：读取完全依赖 ds_conversations 这个索引。
    // 如果索引丢了（或写入中断），内容即使还在 ds_conv_* 里也读不出来。
    final Map<String, Object> seeded = <String, Object>{
      'ds_conv_orphan': jsonEncode(<String, dynamic>{
        'id': 'orphan',
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
        'messages': <dynamic>[ChatMessage.user('孤儿会话的消息').toJson()],
      }),
      // 故意不写 ds_conversations
    };
    SharedPreferences.setMockInitialValues(seeded);

    final StorageService storage = StorageService();
    final List<dynamic> loaded = await storage.loadConversations();
    // 现状：读不到（这就是脆弱点）
    expect(loaded, hasLength(1), reason: '索引丢失时应恢复仍在磁盘的会话');
  });
}

/// 一份假的设置：Key 无效，send 会走失败分支，但「用户消息已写入并落盘」这件事仍会验证到
AppSettings _fakeSettings() => AppSettings(apiKey: 'sk-invalid-for-test');
DeepSeekService _offlineApi() => DeepSeekService(
  client: MockClient(
    (_) async => http.Response('{"error":{"message":"offline fixture"}}', 401),
  ),
);
