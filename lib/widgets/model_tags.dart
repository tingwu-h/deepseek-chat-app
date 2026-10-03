import 'package:flutter/material.dart';
import 'package:deepseek_chat/models/model_info.dart';

class ModelTags extends StatelessWidget {
  const ModelTags({super.key, required this.providerId, required this.model});
  final String providerId;
  final String model;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final tag in modelInfo(providerId, model).tags)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: scheme.secondaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              tag,
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: scheme.onSecondaryContainer),
            ),
          ),
      ],
    );
  }
}
