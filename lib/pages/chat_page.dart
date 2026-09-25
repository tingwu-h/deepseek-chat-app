import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:deepseek_chat/models/app_settings.dart';
import 'package:deepseek_chat/models/chat_message.dart';
import 'package:deepseek_chat/pages/settings_page.dart';
import 'package:deepseek_chat/providers/app_settings_provider.dart';
import 'package:deepseek_chat/providers/chat_provider.dart';
import 'package:deepseek_chat/utils/formatters.dart';
import 'package:deepseek_chat/widgets/chat_input_bar.dart';
import 'package:deepseek_chat/widgets/message_list_view.dart';

/// 主页面：顶部标题 / 中间气泡列表 / 底部输入栏。
class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  String? _shownError;

  Future<void> _handleSend(String text) async {
    final ChatProvider chat = context.read<ChatProvider>();
    final AppSettingsProvider settings = context.read<AppSettingsProvider>();

    if (!settings.hasApiKey) {
      _showSnack('请先在「设置」里填写 DeepSeek API Key');
      _openSettings();
      return;
    }

    // 故意不 await：让界面立刻回到可输入状态，内容由流式回调驱动刷新
    unawaited(chat.send(text, settings.settings));
  }

  void _openSettings() {
    Navigator.of(context).pushNamed(SettingsPage.routeName);
  }

  /// 顶栏上的模型切换按钮。
  ///
  /// 之前模型只能在「设置」页最底部改，聊天时想换个模型得翻半天；
  /// 现在点标题右边这个按钮就能直接切，切完即时生效（下次发送就用新模型）。
  Widget _buildModelSelector(AppSettingsProvider provider, ChatProvider chat) {
    final String current = provider.model;
    return PopupMenuButton<String>(
      tooltip: '切换模型',
      initialValue: current,
      onSelected: (String value) async {
        if (value == current) return;
        await provider.update(model: value);
        if (!mounted) return;
        _showSnack('已切换到 $value');
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        for (final String m in AppSettings.availableModels)
          PopupMenuItem<String>(
            value: m,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                m == current
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 20,
                color: m == current
                    ? Theme.of(context).colorScheme.primary
                    : null,
              ),
              title: Text(AppSettings.modelLabel(m)),
            ),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Chip(
          visualDensity: VisualDensity.compact,
          avatar: const Icon(Icons.memory_outlined, size: 16),
          label: Text(
            AppSettings.modelShortName(current),
            style: Theme.of(context).textTheme.labelSmall,
          ),
          // 生成过程中不让切，避免中途换模型造成上下文混乱
          backgroundColor: chat.isLoading
              ? Theme.of(context).colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.5)
              : null,
        ),
      ),
    );
  }


  void _showSnack(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _confirmClear() async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('清空当前对话？'),
        content: const Text('本地保存的历史记录也会一起删除，此操作无法撤销。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await context.read<ChatProvider>().clearConversation();
      if (mounted) _showSnack('已清空对话');
    }
  }

  /// 把 Provider 里的错误转成 SnackBar（同一条错误只提示一次）
  void _maybeShowError(ChatProvider chat) {
    final String? error = chat.error;
    if (error == null || error == _shownError) return;
    _shownError = error;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _showSnack(error);
      _shownError = null;
      chat.dismissError();
    });
  }

  @override
  Widget build(BuildContext context) {
    final ChatProvider chat = context.watch<ChatProvider>();
    final AppSettingsProvider settings = context.watch<AppSettingsProvider>();
    final List<ChatMessage> messages = chat.messages;

    _maybeShowError(chat);

    return PopScope(
      // 正在生成时先拦一次返回：中断流式请求并保留已收到的内容，然后再退出
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop) return;
        await chat.stopAndPersist();
        // 用 State.context（已被上面的 mounted 守卫），避免 analyzer 的
        // use_build_context_synchronously 提示
        if (!context.mounted) return;
        Navigator.of(context).maybePop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(
                conversationTitle(
                  messages
                      .where((ChatMessage m) => m.isUser)
                      .map((ChatMessage m) => m.content)
                      .toList(),
                ),
              ),
              Text(
                settings.hasApiKey ? '已配置 API Key' : '未配置 API Key',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
          actions: <Widget>[
            // 模型切换放在聊天页：换模型不用再进设置页翻到最底下
            _buildModelSelector(settings, chat),
            // 设置入口只保留这一个（之前齿轮和 ⋮ 菜单里各有一个，重复了）
            IconButton(
              tooltip: '设置',
              onPressed: _openSettings,
              icon: const Icon(Icons.settings_outlined),
            ),
            PopupMenuButton<String>(
              tooltip: '更多',
              onSelected: (String value) {
                switch (value) {
                  case 'clear':
                    _confirmClear();
                    break;
                  case 'stop':
                    chat.stop();
                    break;
                }
              },
              itemBuilder: (BuildContext context) =>
                  <PopupMenuEntry<String>>[
                const PopupMenuItem<String>(
                  value: 'clear',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.delete_outline),
                    title: Text('清空当前对话'),
                  ),
                ),
                if (chat.isLoading)
                  const PopupMenuItem<String>(
                    value: 'stop',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.stop_circle_outlined),
                      title: Text('停止生成'),
                    ),
                  ),
              ],
            ),
          ],
        ),
        body: Column(
          children: <Widget>[
            Expanded(
              child: MessageListView(
                messages: messages,
                isLoading: chat.isLoading,
              ),
            ),
            ChatInputBar(
              isLoading: chat.isLoading,
              enabled: settings.hasApiKey,
              onSend: _handleSend,
              onStop: chat.stop,
            ),
          ],
        ),
      ),
    );
  }
}
