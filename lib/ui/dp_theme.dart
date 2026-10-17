// Dalabapay design system: colour, type, spacing and the Material theme.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Design tokens taken from the Dalabapay redesign.
class DP {
  DP._();

  // Surfaces
  static const Color bg = Color(0xFFF8F9F5);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color border = Color(0xFFE5EAE3);
  static const Color borderStrong = Color(0xFFD3DAD2);

  // Text
  static const Color ink = Color(0xFF14263D);
  static const Color ink2 = Color(0xFF4D5B6B);
  static const Color muted = Color(0xFF728078);
  static const Color faint = Color(0xFFA9B2AC);

  // Brand
  static const Color green = Color(0xFF168566);
  static const Color greenDark = Color(0xFF0F6B51);
  static const Color greenSoft = Color(0xFFDDF4E8);
  static const Color greenLine = Color(0xFF9FD3BE);
  static const Color navy = Color(0xFF102C68);
  static const Color navy2 = Color(0xFF294A80);
  static const Color blue = Color(0xFF173D88);
  static const Color blueSoft = Color(0xFFECF1FC);

  // Status
  static const Color warn = Color(0xFFA76B1D);
  static const Color warnSoft = Color(0xFFFFF3DE);
  static const Color danger = Color(0xFFC03A2B);
  static const Color dangerSoft = Color(0xFFFCEBE8);

  // Radii
  static const double rSm = 10;
  static const double rMd = 14;
  static const double rLg = 20;
  static const double rXl = 28;

  // Spacing
  static const double gutter = 20;

  static const String font = 'Inter';
}

/// Text styles. Headlines are deliberately light, numbers are semibold.
class DPText {
  DPText._();

  static const TextStyle display = TextStyle(
    fontFamily: DP.font,
    fontSize: 27,
    height: 1.18,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.6,
    color: DP.ink,
  );
  static const TextStyle title = TextStyle(
    fontFamily: DP.font,
    fontSize: 18,
    height: 1.3,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.2,
    color: DP.ink,
  );
  static const TextStyle section = TextStyle(
    fontFamily: DP.font,
    fontSize: 17,
    height: 1.3,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.2,
    color: DP.ink,
  );
  static const TextStyle body = TextStyle(
    fontFamily: DP.font,
    fontSize: 15,
    height: 1.4,
    fontWeight: FontWeight.w400,
    color: DP.ink,
  );
  static const TextStyle bodyMuted = TextStyle(
    fontFamily: DP.font,
    fontSize: 14,
    height: 1.45,
    fontWeight: FontWeight.w400,
    color: DP.muted,
  );
  static const TextStyle label = TextStyle(
    fontFamily: DP.font,
    fontSize: 13,
    height: 1.3,
    fontWeight: FontWeight.w500,
    color: DP.ink,
  );
  static const TextStyle small = TextStyle(
    fontFamily: DP.font,
    fontSize: 12,
    height: 1.35,
    fontWeight: FontWeight.w400,
    color: DP.muted,
  );
  static const TextStyle overline = TextStyle(
    fontFamily: DP.font,
    fontSize: 11,
    height: 1.3,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.6,
    color: DP.green,
  );
  static const TextStyle button = TextStyle(
    fontFamily: DP.font,
    fontSize: 15,
    height: 1.2,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.1,
  );
  static const TextStyle link = TextStyle(
    fontFamily: DP.font,
    fontSize: 13,
    height: 1.3,
    fontWeight: FontWeight.w600,
    color: DP.green,
  );
  static const TextStyle amount = TextStyle(
    fontFamily: DP.font,
    fontSize: 32,
    height: 1.1,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.8,
    color: DP.ink,
    fontFeatures: [FontFeature.tabularFigures()],
  );
  static const TextStyle value = TextStyle(
    fontFamily: DP.font,
    fontSize: 14,
    height: 1.3,
    fontWeight: FontWeight.w500,
    color: DP.ink,
    fontFeatures: [FontFeature.tabularFigures()],
  );
}

class DPTheme {
  DPTheme._();

  static const SystemUiOverlayStyle overlay = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemNavigationBarColor: DP.bg,
    systemNavigationBarIconBrightness: Brightness.dark,
  );

  static ThemeData light() {
    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: DP.green,
      onPrimary: Colors.white,
      primaryContainer: DP.greenSoft,
      onPrimaryContainer: DP.green,
      secondary: DP.navy,
      onSecondary: Colors.white,
      secondaryContainer: DP.blueSoft,
      onSecondaryContainer: DP.navy,
      tertiary: DP.blue,
      onTertiary: Colors.white,
      error: DP.danger,
      onError: Colors.white,
      errorContainer: DP.dangerSoft,
      onErrorContainer: DP.danger,
      surface: DP.surface,
      onSurface: DP.ink,
      onSurfaceVariant: DP.muted,
      outline: DP.border,
      outlineVariant: DP.border,
      shadow: Color(0x14000000),
      scrim: Color(0x66000000),
      inverseSurface: DP.ink,
      onInverseSurface: Colors.white,
      inversePrimary: DP.greenSoft,
      surfaceTint: Colors.transparent,
    );

    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(DP.rMd),
      borderSide: const BorderSide(color: DP.border),
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      fontFamily: DP.font,
      colorScheme: scheme,
    );

    return base.copyWith(
      scaffoldBackgroundColor: DP.bg,
      canvasColor: DP.bg,
      primaryColor: DP.green,
      dividerColor: DP.border,
      splashFactory: InkSparkle.splashFactory,
      textTheme: base.textTheme
          .apply(fontFamily: DP.font, bodyColor: DP.ink, displayColor: DP.ink),
      appBarTheme: const AppBarTheme(
        backgroundColor: DP.bg,
        foregroundColor: DP.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: overlay,
        titleTextStyle: DPText.title,
        iconTheme: IconThemeData(color: DP.ink, size: 22),
      ),
      iconTheme: const IconThemeData(color: DP.ink, size: 22),
      dividerTheme: const DividerThemeData(color: DP.border, thickness: 1, space: 1),
      cardTheme: CardThemeData(
        color: DP.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DP.rLg),
          side: const BorderSide(color: DP.border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: DP.surface,
        isDense: false,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        hintStyle: DPText.body.copyWith(color: DP.faint),
        labelStyle: DPText.label.copyWith(color: DP.muted),
        floatingLabelStyle: DPText.label.copyWith(color: DP.green),
        helperStyle: DPText.small,
        errorStyle: DPText.small.copyWith(color: DP.danger),
        prefixIconColor: DP.muted,
        suffixIconColor: DP.muted,
        border: inputBorder,
        enabledBorder: inputBorder,
        disabledBorder: inputBorder,
        focusedBorder: inputBorder.copyWith(
          borderSide: const BorderSide(color: DP.green, width: 1.4),
        ),
        errorBorder: inputBorder.copyWith(
          borderSide: const BorderSide(color: DP.danger),
        ),
        focusedErrorBorder: inputBorder.copyWith(
          borderSide: const BorderSide(color: DP.danger, width: 1.4),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: DP.green,
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0xFFE3E8E2),
          disabledForegroundColor: DP.muted,
          elevation: 0,
          shadowColor: Colors.transparent,
          minimumSize: const Size(64, 54),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          textStyle: DPText.button,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DP.rMd + 2),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: DP.green,
          foregroundColor: Colors.white,
          minimumSize: const Size(64, 54),
          textStyle: DPText.button,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DP.rMd + 2),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: DP.ink,
          backgroundColor: DP.surface,
          minimumSize: const Size(64, 54),
          side: const BorderSide(color: DP.border),
          textStyle: DPText.button,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DP.rMd + 2),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: DP.green,
          textStyle: DPText.link.copyWith(fontSize: 14),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: DP.surface,
        selectedColor: DP.greenSoft,
        disabledColor: DP.bg,
        side: const BorderSide(color: DP.border),
        labelStyle: DPText.label.copyWith(color: DP.ink2),
        secondaryLabelStyle: DPText.label.copyWith(color: DP.green),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DP.rMd)),
        showCheckmark: false,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: DP.bg,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: DP.bg,
        showDragHandle: true,
        dragHandleColor: DP.borderStrong,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(DP.rXl)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: DP.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DP.rLg + 4)),
        titleTextStyle: DPText.title.copyWith(fontWeight: FontWeight.w500),
        contentTextStyle: DPText.bodyMuted,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: DP.ink,
        contentTextStyle: DPText.body.copyWith(color: Colors.white, fontSize: 14),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DP.rMd)),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: DP.green,
        linearTrackColor: DP.greenSoft,
        circularTrackColor: Colors.transparent,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colors.white : DP.surface,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? DP.green : DP.border,
        ),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? DP.green : Colors.transparent,
        ),
        side: const BorderSide(color: DP.borderStrong, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? DP.green : DP.borderStrong,
        ),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: DP.green,
        unselectedLabelColor: DP.muted,
        indicatorColor: DP.green,
        dividerColor: DP.border,
        labelStyle: DPText.label,
        unselectedLabelStyle: DPText.label,
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: DP.ink2,
        textColor: DP.ink,
        contentPadding: EdgeInsets.symmetric(horizontal: 4),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: DP.green,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: DP.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => DPText.small.copyWith(
            color: s.contains(WidgetState.selected) ? DP.green : DP.muted,
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w500 : FontWeight.w400,
          ),
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}
