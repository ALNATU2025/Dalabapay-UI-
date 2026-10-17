// lib/core/constants/colors.dart
import 'package:flutter/material.dart';

class AppColors {
  static const Color primary = Color(0xFF168566);
  static const Color primaryLight = Color(0xFFDDF4E8);
  static const Color secondary = Color(0xFF102C68);
  static const Color white = Color(0xFFFFFFFF);
  static const Color black = Color(0xFF000000);
  static const Color grey = Color(0xFF808080);
  static const Color lightGrey = Color(0xFFF5F5F5);
  static const Color darkGrey = Color(0xFF333333);
  static const Color success = Color(0xFF168566);
  static const Color error = Color(0xFFE53935);
  static const Color warning = Color(0xFFFFC107);
  static const Color info = Color(0xFF2196F3);

  static const Color textPrimary = Color(0xFF14263D);
  static const Color textSecondary = Color(0xFF728078);
  static const Color border = Color(0xFFE0E0E0);
  static const Color background = Color(0xFFF8F9F5);

  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF168566), Color(0xFF0F6B51)],
  );

  static const BoxShadow cardShadow = BoxShadow(
    color: Color(0x0A000000),
    blurRadius: 10,
    offset: Offset(0, 4),
  );
}
