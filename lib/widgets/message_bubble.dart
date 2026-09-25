import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import 'package:deepseek_chat/models/chat_attachment.dart';
import 'package:deepseek_chat/models/chat_message.dart';
import 'package:deepseek_chat/utils/formatters.dart';
import 'package:deepseek_chat/widgets/typing_indicator.dart';

/// 单条聊天气泡：用户消息靠右，助手消息靠左。
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    this.showTyping = false,
  });

  final ChatMessage message;

  /// 助手消息还没有任何内容时，显示跳动圆点
  final bool showTyping;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool isUser = message.isUser;
    final bool isError = message.error;

    final Color bubbleColor = isError
        ? scheme.errorContainer
        : isUser
            ? scheme.primary
            : scheme.surfaceContainerHighest;

    final Color textColor = isError
        ? scheme.onErrorContainer
        : isUser
            ? scheme.onPrimary
            : scheme.onSurface;

    final BorderRadius radius = BorderRadius.only(
      topLeft: const Radius.circular(18),
      topRight: const Radius.circular(18),
      bottomLeft: Radius.circular(isUser ? 18 : 4),
      bottomRight: Radius.circular(isUser ? 4 : 18),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Column(
        crossAxisAlignment:
            isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: <Widget>[
          // 角色标签
          Padding(
            padding: const EdgeInsets.only(left: 6, right: 6, bottom: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  isUser ? Icons.person_outline : Icons.auto_awesome,
                  size: 13,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  isUser ? '我' : 'DeepSeek',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),

          // 气泡本体：限制最大宽度，长按可复制
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.80,
            ),
            child: GestureDetector(
              onLongPress: () => _copy(context),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: bubbleColor,
                  borderRadius: radius,
                  border: isError
                      ? Border.all(color: scheme.error.withValues(alpha: 0.5))
                      : null,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    // 附件：图片缩略图（点开可看大图）/ 文本文件标签
                    if (message.attachments.isNotEmpty) ...<Widget>[
                      _buildAttachments(context),
                      if (message.content.trim().isNotEmpty)
                        const SizedBox(height: 6),
                    ],
                    if (message.content.isEmpty && showTyping)
                      const TypingIndicator(label: '正在思考')
                    else if (message.content.isEmpty && message.attachments.isNotEmpty)
                      // 只发了附件没写文字：不显示空文本
                      const SizedBox.shrink()
                    else if (isUser || isError)
                      SelectableText(
                        message.content,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: textColor,
                          height: 1.42,
                        ),
                      )
                    else
                      MarkdownBody(
                        data: message.content,
                        styleSheet: _markdownStyle(theme, textColor),
                      ),
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.bottomRight,
                      child: Text(
                        formatTime(message.timestamp),
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontSize: 10,
                          color: textColor.withValues(alpha: 0.72),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 气泡里的附件展示：图片缩略图 + 文本文件标签
  Widget _buildAttachments(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final List<Widget> children = <Widget>[];

    for (final ChatAttachment a in message.attachments) {
      if (a.isImage) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: GestureDetector(
              onTap: () => _showFullImage(context, a),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.file(
                  File(a.path),
                  width: 200,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 200,
                    height: 80,
                    alignment: Alignment.center,
                    color: scheme.surface.withValues(alpha: 0.5),
                    child: const Text('图片已不在本地'),
                  ),
                ),
              ),
            ),
          ),
        );
      } else {
        children.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: scheme.surface.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(Icons.description_outlined,
                      size: 16, color: scheme.primary),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      '${a.name}（${a.sizeLabel}）',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }

  /// 点缩略图看大图
  void _showFullImage(BuildContext context, ChatAttachment a) {
    showDialog<void>(
      context: context,
      builder: (BuildContext context) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        backgroundColor: Colors.transparent,
        child: GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: InteractiveViewer(
            maxScale: 5,
            child: Image.file(
              File(a.path),
              errorBuilder: (_, __, ___) => const Padding(
                padding: EdgeInsets.all(24),
                child: Text('图片已不在本地',
                    style: TextStyle(color: Colors.white)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _copy(BuildContext context) {
    if (message.content.isEmpty) return;
    Clipboard.setData(ClipboardData(text: message.content));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('已复制这条消息'),
          duration: Duration(milliseconds: 1200),
        ),
      );
  }

  /// Markdown 渲染样式（深色模式下自动适配）
  MarkdownStyleSheet _markdownStyle(ThemeData theme, Color textColor) {
    final ColorScheme scheme = theme.colorScheme;
    return MarkdownStyleSheet.fromTheme(theme).copyWith(
      p: theme.textTheme.bodyMedium?.copyWith(
        color: textColor,
        height: 1.45,
      ),
      h1: theme.textTheme.titleLarge?.copyWith(color: textColor),
      h2: theme.textTheme.titleMedium?.copyWith(color: textColor),
      h3: theme.textTheme.titleSmall?.copyWith(color: textColor),
      listBullet: theme.textTheme.bodyMedium?.copyWith(color: textColor),
      strong: theme.textTheme.bodyMedium?.copyWith(
        color: textColor,
        fontWeight: FontWeight.w700,
      ),
      em: theme.textTheme.bodyMedium?.copyWith(
        color: textColor,
        fontStyle: FontStyle.italic,
      ),
      a: theme.textTheme.bodyMedium?.copyWith(
        color: scheme.primary,
        decoration: TextDecoration.underline,
      ),
      code: TextStyle(
        fontFamily: 'monospace',
        fontSize: 13,
        color: textColor,
        backgroundColor: scheme.surface.withValues(alpha: 0.6),
      ),
      codeblockDecoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(10),
      ),
      blockquoteDecoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.45),
        border: Border(
          left: BorderSide(color: scheme.primary, width: 3),
        ),
      ),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: scheme.outlineVariant),
        ),
      ),
    );
  }
}
