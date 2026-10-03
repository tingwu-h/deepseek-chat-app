import 'package:flutter/material.dart';
import 'package:deepseek_chat/utils/app_localizations.dart';

/// Reference directions for the provider's preset models, not rankings or
/// guarantees that every model supports every capability.
List<String> providerTags(String id) => switch (id) {
  'deepseek' => ['复杂推理', '数学', '编程'],
  'openai' => ['日常问答', '编程', '图片理解'],
  'kimi' => ['长文', '写作', '编程'],
  'qwen' => ['日常问答', '编程', '图文问答'],
  'anthropic' => ['编程', '写作', '图片理解'],
  'google' => ['图片理解', '长文', '复杂推理'],
  'xai' => ['复杂推理', '日常问答'],
  'glm' => ['编程', '复杂推理', '图文问答'],
  'openrouter' => ['多模型聚合', '免费模型入口'],
  _ => ['能力待确认'],
};

class ProviderTags extends StatelessWidget {
  const ProviderTags({super.key, required this.providerId});
  final String providerId;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final tag in providerTags(providerId))
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: scheme.secondaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              tr(context, tag),
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: scheme.onSecondaryContainer),
            ),
          ),
      ],
    );
  }
}
