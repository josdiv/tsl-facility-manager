import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar(this.initials, {this.size = 40, super.key});

  final String initials;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: AppColors.primarySoft,
        shape: BoxShape.circle,
      ),
      child: Text(
        initials,
        style: TextStyle(
          color: AppColors.primary,
          fontSize: size * 0.32,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
