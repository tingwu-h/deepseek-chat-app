import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 底部输入栏：多行输入框 + 发送 / 停止按钮。
class ChatInputBar extends StatefulWidget {
  const ChatInputBar({
    super.key,
    required this.onSend,
    required this.onStop,
    required this.isLoading,
    required this.enabled,
  });

  /// 点击发送（参数已 trim，非空）
  final ValueChanged<String> onSend;

  /// 点击停止生成
  final VoidCallback onStop;

  final bool isLoading;

  /// false 表示还没配置 API Key，禁止发送
  final bool enabled;

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onTextChanged)
      ..dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final bool hasText = _controller.text.trim().isNotEmpty;
    if (hasText != _hasText) {
      setState(() => _hasText = hasText);
    }
  }

  void _submit() {
    if (widget.isLoading) return;
    final String text = _controller.text.trim();
    if (text.isEmpty) return;
    if (!widget.enabled) return;
    _controller.clear();
    _hasText = false;
    widget.onSend(text);
    // 保持焦点，方便连续提问
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border(
            top: BorderSide(color: scheme.outlineVariant, width: 0.6),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.newline,
                keyboardType: TextInputType.multiline,
                textCapitalization: TextCapitalization.sentences,
                enabled: !widget.isLoading,
                style: Theme.of(context).textTheme.bodyMedium,
                decoration: InputDecoration(
                  hintText: widget.enabled
                      ? (widget.isLoading ? '正在回复…' : '给 DeepSeek 发消息…')
                      : '请先到设置里填写 API Key',
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            _buildActionButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton() {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    if (widget.isLoading) {
      return IconButton.filledTonal(
        onPressed: () {
          HapticFeedback.selectionClick();
          widget.onStop();
        },
        tooltip: '停止生成',
        icon: const Icon(Icons.stop_rounded),
        style: IconButton.styleFrom(
          minimumSize: const Size(48, 48),
          backgroundColor: scheme.errorContainer,
          foregroundColor: scheme.onErrorContainer,
        ),
      );
    }

    final bool canSend = _hasText && widget.enabled;
    return IconButton.filled(
      onPressed: canSend
          ? () {
              HapticFeedback.lightImpact();
              _submit();
            }
          : null,
      tooltip: '发送',
      icon: const Icon(Icons.arrow_upward_rounded),
      style: IconButton.styleFrom(
        minimumSize: const Size(48, 48),
      ),
    );
  }
}
