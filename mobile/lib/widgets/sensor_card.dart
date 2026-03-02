import 'package:flutter/material.dart';

class SensorCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final bool expanded;

  const SensorCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.expanded = false,
  });

  @override
  Widget build(BuildContext context) {
    final content = Row(
      mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            Text(
              value,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ],
        ),
      ],
    );

    if (expanded) {
      return Card(
        elevation: 0,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: content,
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: content,
    );
  }
}
