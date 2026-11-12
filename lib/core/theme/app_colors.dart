import 'package:flutter/material.dart';

/// Palette taken from the HTML prototype. Text-on-tint colours are darkened
/// from the prototype so small labels stay readable on site.
abstract final class AppColors {
  static const primary = Color(0xFFA54B8E);
  static const primaryDark = Color(0xFF804471);
  static const primarySoft = Color(0xFFF7EDF4);
  static const primaryBorder = Color(0xFFE5C9DD);

  static const heading = Color(0xFF28323F);
  static const ink = Color(0xFF202A36);
  static const body = Color(0xFF566170);
  static const muted = Color(0xFF6B7482);

  static const line = Color(0xFFE9ECF1);
  static const fieldBorder = Color(0xFFDFE4EB);
  static const background = Color(0xFFF8F9FC);
  static const surface = Colors.white;

  static const teal = Color(0xFF1F8783);

  static const success = Color(0xFF2E7D64);
  static const successSoft = Color(0xFFEAF7F1);
  static const warning = Color(0xFF8F6D1F);
  static const warningSoft = Color(0xFFFFF6E5);
  static const danger = Color(0xFFB84A5F);
  static const dangerSoft = Color(0xFFFFF0F2);
  static const info = Color(0xFF4A6FB0);
  static const infoSoft = Color(0xFFEDF2FC);
  static const sla = Color(0xFF8A5A9A);
  static const slaSoft = Color(0xFFF4EBF7);
  static const neutral = Color(0xFF5F7185);
  static const neutralSoft = Color(0xFFEFF3F8);
}
