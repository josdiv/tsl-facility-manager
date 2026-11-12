import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

enum BadgeTone { neutral, info, warning, success, danger, sla }

class AppBadge extends StatelessWidget {
  const AppBadge(this.label, {this.tone = BadgeTone.neutral, super.key});

  final String label;
  final BadgeTone tone;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (tone) {
      BadgeTone.neutral => (AppColors.neutralSoft, AppColors.neutral),
      BadgeTone.info => (AppColors.infoSoft, AppColors.info),
      BadgeTone.warning => (AppColors.warningSoft, AppColors.warning),
      BadgeTone.success => (AppColors.successSoft, AppColors.success),
      BadgeTone.danger => (AppColors.dangerSoft, AppColors.danger),
      BadgeTone.sla => (AppColors.slaSoft, AppColors.sla),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: foreground,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
