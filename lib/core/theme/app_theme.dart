// lib/core/theme/app_theme.dart
// Dalabapay redesign theme. Colours come from lib/ui/dp_tokens.dart so every
// Material widget in the app (including screens without a bespoke layout)
// picks up the new look automatically.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../ui/dp_tokens.dart';

class AppTheme {
  static const Color primaryColor = DP.green;
  static const Color secondaryColor = DP.navy;
  static const Color accentColor = DP.mint;
  static const Color successColor = DP.green;
  static const Color errorColor = DP.red;
  static const Color warningColor = DP.amber;

  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [DP.green, DP.greenDeep],
  );

  static const LinearGradient secondaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [DP.navy, DP.navyDeep],
  );

  static const LinearGradient cardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [DP.navy, DP.navyDeep],
  );

  static OutlineInputBorder _border(Color c, [double w = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(DP.rMd),
        borderSide: BorderSide(color: c, width: w),
      );

  static final TextTheme _text = GoogleFonts.interTextTheme().apply(
    bodyColor: DP.ink,
    displayColor: DP.ink,
  );

  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    primaryColor: primaryColor,
    scaffoldBackgroundColor: DP.bg,
    canvasColor: DP.bg,
    dividerColor: DP.border,
    splashFactory: InkRipple.splashFactory,
    colorScheme: const ColorScheme.light(
      primary: DP.green,
      onPrimary: Colors.white,
      primaryContainer: DP.mint,
      onPrimaryContainer: DP.greenDeep,
      secondary: DP.navy,
      onSecondary: Colors.white,
      tertiary: DP.mint,
      error: DP.red,
      surface: DP.surface,
      onSurface: DP.ink,
      surfaceTint: Colors.transparent,
      outline: DP.border,
      outlineVariant: DP.borderSoft,
    ),
    textTheme: _text,
    fontFamily: GoogleFonts.inter().fontFamily,
    appBarTheme: AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      backgroundColor: DP.bg,
      surfaceTintColor: Colors.transparent,
      foregroundColor: DP.ink,
      iconTheme: const IconThemeData(color: DP.ink),
      titleTextStyle: GoogleFonts.inter(
        fontSize: 20,
        fontWeight: FontWeight.w400,
        color: DP.ink,
      ),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      type: BottomNavigationBarType.fixed,
      backgroundColor: DP.surface,
      selectedItemColor: DP.green,
      unselectedItemColor: DP.muted,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: DP.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: DP.border),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: DP.bg,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DP.rXl),
      ),
      titleTextStyle: GoogleFonts.inter(
        fontSize: 20,
        fontWeight: FontWeight.w500,
        color: DP.ink,
      ),
      contentTextStyle: GoogleFonts.inter(fontSize: 14.5, color: DP.inkSoft),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: DP.bg,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: DP.bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(DP.rXl)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: DP.ink,
      contentTextStyle: GoogleFonts.inter(color: Colors.white, fontSize: 14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DP.rMd),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: DP.surface,
      border: _border(DP.border),
      enabledBorder: _border(DP.border),
      disabledBorder: _border(DP.borderSoft),
      focusedBorder: _border(DP.green, 1.4),
      errorBorder: _border(DP.red),
      focusedErrorBorder: _border(DP.red, 1.4),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
      hintStyle: const TextStyle(color: DP.faint),
      labelStyle: const TextStyle(color: DP.muted),
      floatingLabelStyle: const TextStyle(color: DP.green),
      prefixIconColor: DP.muted,
      suffixIconColor: DP.muted,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: DP.green,
        foregroundColor: Colors.white,
        disabledBackgroundColor: DP.green.withValues(alpha: 0.45),
        disabledForegroundColor: Colors.white,
        minimumSize: const Size(64, 52),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DP.rLg),
        ),
        elevation: 0,
        textStyle: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: DP.green,
        foregroundColor: Colors.white,
        minimumSize: const Size(64, 52),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DP.rLg),
        ),
        textStyle: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: DP.ink,
        backgroundColor: DP.surface,
        minimumSize: const Size(64, 52),
        side: const BorderSide(color: DP.border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DP.rLg),
        ),
        textStyle: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: DP.green,
        textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: DP.surface,
      selectedColor: DP.mint,
      side: const BorderSide(color: DP.border),
      labelStyle: const TextStyle(color: DP.inkSoft),
      secondaryLabelStyle: const TextStyle(color: DP.green),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DP.rSm),
      ),
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: DP.green,
      unselectedLabelColor: DP.muted,
      indicatorColor: DP.green,
      dividerColor: DP.border,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? Colors.white : DP.faint,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? DP.green : DP.borderSoft,
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? DP.green : DP.border,
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? DP.green : Colors.transparent,
      ),
      side: const BorderSide(color: DP.faint, width: 1.4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? DP.green : DP.faint,
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: DP.green,
      linearTrackColor: DP.mint,
      circularTrackColor: Colors.transparent,
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: DP.navyIcon,
      textColor: DP.ink,
    ),
    dividerTheme: const DividerThemeData(
      color: DP.border,
      thickness: 1,
      space: 1,
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: DP.green,
      foregroundColor: Colors.white,
      elevation: 0,
    ),
    drawerTheme: const DrawerThemeData(
      backgroundColor: DP.bg,
      surfaceTintColor: Colors.transparent,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: DP.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DP.rMd),
        side: const BorderSide(color: DP.border),
      ),
    ),
    datePickerTheme: const DatePickerThemeData(
      backgroundColor: DP.bg,
      surfaceTintColor: Colors.transparent,
    ),
  );

  // The app runs in light mode only (themeMode: ThemeMode.light). The dark
  // theme is kept so existing references still compile.
  static ThemeData darkTheme = lightTheme;
}
