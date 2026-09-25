import 'package:flutter/material.dart';

/// 助手回复「等待首个字」时显示的三个跳动圆点。
class TypingIndicator extends StatefulWidget {
  const TypingIndicator({super.key, this.label = '正在思考'});

  final String label;

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Row(
      children: <Widget>[
        Icon(
          Icons.auto_awesome,
          size: 15,
          color: scheme.primary,
        ),
        const SizedBox(width: 6),
        Text(
          widget.label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(width: 6),
        AnimatedBuilder(
          animation: _controller,
          builder: (BuildContext context, _) {
            return Row(
              children: List<Widget>.generate(3, (int i) {
                // 每个点错开 1/3 个周期
                final double t = (_controller.value + i / 3) % 1.0;
                final double scale = 0.6 + 0.4 * (1 - (t - 0.5).abs() * 2);
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1.5),
                  child: Transform.scale(
                    scale: scale,
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: 0.75),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                );
              }),
            );
          },
        ),
      ],
    );
  }
}
