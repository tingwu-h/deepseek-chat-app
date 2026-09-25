import 'package:flutter/material.dart';

import 'package:deepseek_chat/models/conversation.dart';
import 'package:deepseek_chat/utils/formatters.dart';

/// 左侧抽屉：会话列表（新建 / 切换 / 删除）。
class ConversationDrawer extends StatelessWidget {
  const ConversationDrawer({
    super.key,
    required this.conversations,
    required this.activeId,
    required this.onNew,
    required this.onSelect,
    required this.onDelete,
    required this.onOpenSettings,
    required this.onClearAll,
  });

  final List<Conversation> conversations;
  final String? activeId;
  final VoidCallback onNew;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onDelete;
  final VoidCallback onOpenSettings;
  final VoidCallback onClearAll;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Drawer(
      child: SafeArea(
        child: Column(
          children: <Widget>[
            // 顶部：新建对话
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: FilledButton.tonalIcon(
                onPressed: () {
                  Navigator.of(context).pop(); // 先关抽屉
                  onNew();
                },
                icon: const Icon(Icons.add_comment_outlined),
                label: const Text('新建对话'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: <Widget>[
                  Text(
                    '历史对话',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                  const Spacer(),
                  Text(
                    '${conversations.where((Conversation c) => !c.isEmpty).length} 条',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            const Divider(height: 1),
            Expanded(
              child: conversations.isEmpty
                  ? Center(
                      child: Text(
                        '还没有历史对话',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: conversations.length,
                      itemBuilder: (BuildContext context, int i) {
                        final Conversation c = conversations[i];
                        final bool selected = c.id == activeId;
                        return ListTile(
                          selected: selected,
                          selectedTileColor:
                              scheme.primary.withValues(alpha: 0.10),
                          leading: Icon(
                            c.isEmpty
                                ? Icons.chat_bubble_outline
                                : Icons.chat_bubble,
                            size: 20,
                            color: selected ? scheme.primary : null,
                          ),
                          title: Text(
                            c.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          subtitle: Text(
                            '${formatRelative(c.updatedAt)} · ${c.preview}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                          trailing: IconButton(
                            tooltip: '删除',
                            icon: const Icon(Icons.delete_outline, size: 18),
                            onPressed: () async {
                              final bool? ok = await showDialog<bool>(
                                context: context,
                                builder: (BuildContext ctx) => AlertDialog(
                                  title: const Text('删除这个对话？'),
                                  content: Text('「${c.title}」将被永久删除。'),
                                  actions: <Widget>[
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(ctx, false),
                                      child: const Text('取消'),
                                    ),
                                    FilledButton(
                                      onPressed: () => Navigator.pop(ctx, true),
                                      child: const Text('删除'),
                                    ),
                                  ],
                                ),
                              );
                              if (ok == true) onDelete(c.id);
                            },
                          ),
                          onTap: () {
                            Navigator.of(context).pop();
                            onSelect(c.id);
                          },
                        );
                      },
                    ),
            ),
            const Divider(height: 1),
            // 底部：设置 / 清空
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('设置'),
              onTap: () {
                Navigator.of(context).pop();
                onOpenSettings();
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_sweep_outlined),
              title: const Text('清空全部对话'),
              onTap: () async {
                final bool? ok = await showDialog<bool>(
                  context: context,
                  builder: (BuildContext ctx) => AlertDialog(
                    title: const Text('清空全部对话？'),
                    content: const Text('所有历史对话都会被删除，此操作无法撤销。'),
                    actions: <Widget>[
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('取消'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('清空'),
                      ),
                    ],
                  ),
                );
                if (ok == true) onClearAll();
              },
            ),
          ],
        ),
      ),
    );
  }
}
