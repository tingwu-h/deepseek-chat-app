import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:deepseek_chat/models/app_settings.dart';
import 'package:deepseek_chat/models/chat_attachment.dart';
import 'package:deepseek_chat/pages/settings_page.dart';
import 'package:deepseek_chat/providers/app_settings_provider.dart';
import 'package:deepseek_chat/providers/chat_provider.dart';
import 'package:deepseek_chat/services/attachment_service.dart';
import 'package:deepseek_chat/widgets/chat_input_bar.dart';
import 'package:deepseek_chat/widgets/conversation_drawer.dart';
import 'package:deepseek_chat/widgets/message_list_view.dart';

/// 主页面：抽屉(历史会话) + 顶栏(标题/新建/模型/更多) + 气泡列表 + 输入栏。
class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final AttachmentService _attachments = AttachmentService();

  /// 已选、还没发出去的附件
  final List<ChatAttachment> _pending = <ChatAttachment>[];

  String? _shownError;

  // -------------------------------------------------------------- 发送

  Future<void> _handleSend(String text) async {
    final ChatProvider chat = context.read<ChatProvider>();
    final AppSettingsProvider settings = context.read<AppSettingsProvider>();

    if (!settings.hasApiKey) {
      _showSnack('请先在「设置」里填写 DeepSeek API Key');
      _openSettings();
      return;
    }
    if (text.trim().isEmpty && _pending.isEmpty) return;

    final List<ChatAttachment> sending = List<ChatAttachment>.from(_pending);
    setState(_pending.clear);

    // 故意不 await：让界面立刻回到可输入状态，内容由流式回调驱动刷新
    unawaited(chat.send(text, settings.settings, attachments: sending));
  }

  // -------------------------------------------------------------- 附件

  Future<void> _pickImages() async {
    try {
      final List<ChatAttachment> picked = await _attachments.pickImages();
      if (picked.isEmpty || !mounted) return;
      setState(() => _pending.addAll(picked));
    } on AttachmentException catch (e) {
      _showSnack(e.message);
    } catch (e) {
      _showSnack('选择图片失败：$e');
    }
  }

  Future<void> _pickFiles() async {
    try {
      final List<ChatAttachment> picked = await _attachments.pickFiles();
      if (picked.isEmpty || !mounted) return;
      setState(() => _pending.addAll(picked));
    } on AttachmentException catch (e) {
      _showSnack(e.message);
    } catch (e) {
      _showSnack('选择文件失败：$e');
    }
  }

  void _removePending(ChatAttachment a) {
    setState(() => _pending.remove(a));
  }

  // -------------------------------------------------------------- 会话

  Future<void> _newConversation() async {
    await context.read<ChatProvider>().newConversation();
    if (!mounted) return;
    setState(_pending.clear);
  }

  void _openSettings() {
    Navigator.of(context).pushNamed(SettingsPage.routeName);
  }

  void _showSnack(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _confirmClearCurrent() async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('清空当前对话？'),
        content: const Text('这个对话里的消息会被删除，此操作无法撤销。'),
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
      final ChatProvider chat = context.read<ChatProvider>();
      final String? id = chat.activeConversationId;
      if (id != null) await chat.deleteConversation(id);
      if (mounted) _showSnack('已清空当前对话');
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

  // -------------------------------------------------------------- 构建

  @override
  Widget build(BuildContext context) {
    final ChatProvider chat = context.watch<ChatProvider>();
    final AppSettingsProvider settings = context.watch<AppSettingsProvider>();

    _maybeShowError(chat);

    return PopScope(
      // 正在生成时先拦一次返回：中断流式请求并保留已收到的内容，然后再退出
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop) return;
        await chat.stopAndPersist();
        if (!context.mounted) return;
        Navigator.of(context).maybePop();
      },
      child: Scaffold(
        key: _scaffoldKey,
        drawer: ConversationDrawer(
          conversations: chat.conversations,
          activeId: chat.activeConversationId,
          onNew: _newConversation,
          onSelect: (String id) => chat.switchConversation(id),
          onDelete: (String id) => chat.deleteConversation(id),
          onOpenSettings: _openSettings,
          onClearAll: () => chat.clearAllConversations(),
        ),
        appBar: AppBar(
          leading: IconButton(
            tooltip: '历史对话',
            icon: const Icon(Icons.menu),
            onPressed: () => _scaffoldKey.currentState?.openDrawer(),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(
                chat.activeTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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
            IconButton(
              tooltip: '新建对话',
              onPressed: _newConversation,
              icon: const Icon(Icons.add_comment_outlined),
            ),
            _buildModelSelector(settings, chat),
            // ⋮ 菜单只有「清空当前对话」这一项。
            // 停止生成已集成在发送按钮上（生成时它会变成 ⏹），不再在这里重复一份。
            PopupMenuButton<String>(
              tooltip: '清空当前对话',
              onSelected: (String value) {
                if (value == 'clear') _confirmClearCurrent();
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
              ],
            ),
          ],
        ),
        body: Column(
          children: <Widget>[
            Expanded(
              child: MessageListView(
                messages: chat.messages,
                isLoading: chat.isLoading,
              ),
            ),
            ChatInputBar(
              isLoading: chat.isLoading,
              enabled: settings.hasApiKey,
              attachments: _pending,
              onSend: _handleSend,
              onStop: chat.stop,
              onPickImages: _pickImages,
              onPickFiles: _pickFiles,
              onRemoveAttachment: _removePending,
            ),
          ],
        ),
      ),
    );
  }

  /// 顶栏上的模型切换按钮
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
              ? Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest
                  .withValues(alpha: 0.5)
              : null,
        ),
      ),
    );
  }
}
