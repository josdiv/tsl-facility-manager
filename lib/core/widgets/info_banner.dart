import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

enum BannerTone { brand, success, warning, danger, neutral }

class InfoBanner extends StatelessWidget {
  const InfoBanner(
    this.message, {
    this.icon,
    this.tone = BannerTone.brand,
    super.key,
  });

  final String message;
  final IconData? icon;
  final BannerTone tone;

  @override
  Widget build(BuildContext context) {
    final (background, border, foreground) = switch (tone) {
      BannerTone.brand => (
        AppColors.primarySoft,
        AppColors.primaryBorder,
        AppColors.primaryDark,
      ),
      BannerTone.success => (
        AppColors.successSoft,
        AppColors.successSoft,
        AppColors.success,
      ),
      BannerTone.warning => (
        AppColors.warningSoft,
        AppColors.warningSoft,
        AppColors.warning,
      ),
      BannerTone.danger => (
        AppColors.dangerSoft,
        AppColors.dangerSoft,
        AppColors.danger,
      ),
      BannerTone.neutral => (AppColors.surface, AppColors.line, AppColors.body),
    };
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: foreground),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 13, height: 1.4, color: foreground),
            ),
          ),
        ],
      ),
    );
  }
}
