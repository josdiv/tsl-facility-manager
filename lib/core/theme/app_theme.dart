import 'package:flutter/material.dart';

import 'app_colors.dart';

abstract final class AppTheme {
  static const _heading = 'Manrope';
  static const _body = 'DMSans';

  static final ThemeData light = _build();

  static ThemeData _build() {
    const scheme = ColorScheme.light(
      primary: AppColors.primary,
      onPrimary: Colors.white,
      secondary: AppColors.teal,
      onSecondary: Colors.white,
      surface: AppColors.surface,
      onSurface: AppColors.ink,
      error: AppColors.danger,
      outline: AppColors.fieldBorder,
      outlineVariant: AppColors.line,
    );
    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
    );
    const buttonText = TextStyle(
      fontFamily: _body,
      fontSize: 14,
      fontWeight: FontWeight.w600,
    );
    const buttonSize = Size(48, 48);
    OutlineInputBorder border(Color color) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: color),
    );

    return ThemeData(
      colorScheme: scheme,
      fontFamily: _body,
      scaffoldBackgroundColor: AppColors.background,
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          fontFamily: _heading,
          fontSize: 24,
          fontWeight: FontWeight.w800,
          color: AppColors.heading,
          letterSpacing: -0.5,
        ),
        headlineSmall: TextStyle(
          fontFamily: _heading,
          fontSize: 21,
          fontWeight: FontWeight.w800,
          color: AppColors.heading,
          letterSpacing: -0.3,
        ),
        titleLarge: TextStyle(
          fontFamily: _heading,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppColors.ink,
        ),
        titleMedium: TextStyle(
          fontFamily: _heading,
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: AppColors.ink,
        ),
        titleSmall: TextStyle(
          fontFamily: _heading,
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: AppColors.ink,
        ),
        bodyLarge: TextStyle(fontSize: 15, color: AppColors.ink),
        bodyMedium: TextStyle(fontSize: 14, height: 1.4, color: AppColors.body),
        bodySmall: TextStyle(
          fontSize: 12,
          height: 1.35,
          color: AppColors.muted,
        ),
        labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        labelMedium: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: AppColors.body,
        ),
        labelSmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppColors.ink,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: _heading,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppColors.ink,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: buttonSize,
          shape: buttonShape,
          textStyle: buttonText,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: buttonSize,
          shape: buttonShape,
          textStyle: buttonText,
          foregroundColor: AppColors.body,
          backgroundColor: AppColors.surface,
          side: const BorderSide(color: AppColors.fieldBorder),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 44),
          textStyle: const TextStyle(
            fontFamily: _body,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        hintStyle: const TextStyle(fontSize: 14, color: AppColors.muted),
        border: border(AppColors.fieldBorder),
        enabledBorder: border(AppColors.fieldBorder),
        focusedBorder: border(AppColors.primary),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: AppColors.primary,
        unselectedLabelColor: AppColors.muted,
        indicatorColor: AppColors.primary,
        dividerColor: AppColors.line,
        tabAlignment: TabAlignment.start,
        labelStyle: TextStyle(
          fontFamily: _body,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: TextStyle(
          fontFamily: _body,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: AppColors.primarySoft,
        height: 68,
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontFamily: _body,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: states.contains(WidgetState.selected)
                ? AppColors.primary
                : AppColors.muted,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 23,
            color: states.contains(WidgetState.selected)
                ? AppColors.primary
                : AppColors.muted,
          ),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Color(0xFF253344),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.line,
        space: 1,
        thickness: 1,
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
    );
  }
}
