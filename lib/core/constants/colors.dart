// lib/core/constants/colors.dart
// Mapped onto the redesign palette (lib/ui/dp_tokens.dart).
import 'package:flutter/material.dart';

import '../../ui/dp_tokens.dart';

class AppColors {
  static const Color primary = DP.green;
  static const Color primaryLight = DP.mint;
  static const Color secondary = DP.navy;
  static const Color white = Color(0xFFFFFFFF);
  static const Color black = Color(0xFF000000);
  static const Color grey = DP.muted;
  static const Color lightGrey = DP.borderSoft;
  static const Color darkGrey = DP.inkSoft;
  static const Color success = DP.green;
  static const Color error = DP.red;
  static const Color warning = DP.amber;
  static const Color info = DP.navyIcon;

  static const Color textPrimary = DP.ink;
  static const Color textSecondary = DP.muted;
  static const Color border = DP.border;
  static const Color background = DP.bg;

  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [DP.green, DP.greenDeep],
  );

  static const BoxShadow cardShadow = BoxShadow(
    color: Color(0x0A14263D),
    blurRadius: 18,
    offset: Offset(0, 6),
  );
}
