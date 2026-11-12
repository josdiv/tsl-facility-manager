import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'app_card.dart';

class StatTile extends StatelessWidget {
  const StatTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.caption,
    this.iconColor = AppColors.primary,
    this.iconBackground = AppColors.primarySoft,
    this.captionColor = AppColors.muted,
    super.key,
  });

  final IconData icon;
  final String label;
  final String value;
  final String caption;
  final Color iconColor;
  final Color iconBackground;
  final Color captionColor;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: iconBackground,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(height: 12),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Text(value, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 4),
          Text(
            caption,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: captionColor),
          ),
        ],
      ),
    );
  }
}

/// Two stat tiles of equal height, side by side.
class StatRow extends StatelessWidget {
  const StatRow({required this.first, required this.second, super.key});

  final StatTile first;
  final StatTile second;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: first),
            const SizedBox(width: 12),
            Expanded(child: second),
          ],
        ),
      ),
    );
  }
}
