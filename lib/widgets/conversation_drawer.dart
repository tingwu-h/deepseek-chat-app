import 'package:flutter/material.dart';

import 'package:deepseek_chat/models/conversation.dart';
import 'package:deepseek_chat/utils/formatters.dart';

/// 左侧抽屉：会话列表（新建 / 切换 / 重命名 / 删除）。
class ConversationDrawer extends StatelessWidget {
  const ConversationDrawer({
    super.key,
    required this.conversations,
    required this.activeId,
    required this.onNew,
    required this.onSelect,
    required this.onRename,
    required this.onDelete,
    required this.onOpenSettings,
    required this.onClearAll,
  });

  final List<Conversation> conversations;
  final String? activeId;
  final VoidCallback onNew;
  final ValueChanged<String> onSelect;

  /// 改名：(会话 id, 新名字)。传空串表示恢复自动标题。
  final void Function(String id, String name) onRename;

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
                    style: Theme.of(context).textTheme.labelMedium
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const Spacer(),
                  Text(
                    '${conversations.where((Conversation c) => !c.isEmpty).length} 条',
                    style: Theme.of(context).textTheme.labelSmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
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
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(
                        vertical: 8,
                        horizontal: 10,
                      ),
                      itemCount: conversations.length,
                      itemBuilder: (BuildContext context, int i) {
                        final Conversation c = conversations[i];
                        final bool selected = c.id == activeId;
                        return ListTile(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          selected: selected,
                          selectedTileColor: scheme.primary.withValues(
                            alpha: 0.10,
                          ),
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
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                          // 长按改名；右侧 ⋮ 里也有改名与删除
                          onLongPress: () =>
                              _showRenameDialog(context, c, onRename: onRename),
                          trailing: PopupMenuButton<String>(
                            tooltip: '更多',
                            icon: const Icon(Icons.more_vert, size: 18),
                            onSelected: (String v) {
                              if (v == 'rename') {
                                _showRenameDialog(
                                  context,
                                  c,
                                  onRename: onRename,
                                );
                              } else if (v == 'delete') {
                                _confirmDelete(context, c, onDelete: onDelete);
                              }
                            },
                            itemBuilder: (BuildContext ctx) =>
                                const <PopupMenuEntry<String>>[
                                  PopupMenuItem<String>(
                                    value: 'rename',
                                    child: ListTile(
                                      dense: true,
                                      contentPadding: EdgeInsets.zero,
                                      leading: Icon(Icons.edit_outlined),
                                      title: Text('重命名'),
                                    ),
                                  ),
                                  PopupMenuItem<String>(
                                    value: 'delete',
                                    child: ListTile(
                                      dense: true,
                                      contentPadding: EdgeInsets.zero,
                                      leading: Icon(Icons.delete_outline),
                                      title: Text('删除'),
                                    ),
                                  ),
                                ],
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

/// 改名弹窗：预填当前标题，清空则恢复自动标题
Future<void> _showRenameDialog(
  BuildContext context,
  Conversation conv, {
  required void Function(String id, String name) onRename,
}) async {
  final TextEditingController controller = TextEditingController(
    // 没手动命名过时，预填自动生成的标题方便修改
    text: conv.hasCustomTitle ? (conv.customTitle ?? '') : conv.title,
  );

  final String? result = await showDialog<String>(
    context: context,
    builder: (BuildContext ctx) => AlertDialog(
      title: const Text('重命名对话'),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: 40,
        decoration: const InputDecoration(
          hintText: '给这个对话起个名字',
          helperText: '留空则恢复为自动标题',
        ),
        onSubmitted: (String v) => Navigator.pop(ctx, v),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, controller.text),
          child: const Text('确定'),
        ),
      ],
    ),
  );

  controller.dispose();
  if (result != null) onRename(conv.id, result);
}

/// 删除确认
Future<void> _confirmDelete(
  BuildContext context,
  Conversation conv, {
  required ValueChanged<String> onDelete,
}) async {
  final bool? ok = await showDialog<bool>(
    context: context,
    builder: (BuildContext ctx) => AlertDialog(
      title: const Text('删除这个对话？'),
      content: Text('「${conv.title}」将被永久删除。'),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('删除'),
        ),
      ],
    ),
  );
  if (ok == true) onDelete(conv.id);
}
