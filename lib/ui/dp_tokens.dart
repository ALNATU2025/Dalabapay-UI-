// lib/ui/dp_tokens.dart
import 'package:flutter/material.dart';

/// Colour, radius and text tokens taken from the Dalabapay redesign.
class DP {
  DP._();

  // ── Surfaces ──────────────────────────────────────────────
  static const Color bg = Color(0xFFF7F9FC);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color border = Color(0xFFE6ECF3);
  static const Color borderSoft = Color(0xFFF0F3F8);

  // ── Text ──────────────────────────────────────────────────
  static const Color ink = Color(0xFF10255A);
  static const Color inkSoft = Color(0xFF3E4E74);
  static const Color muted = Color(0xFF7B87A1);
  static const Color faint = Color(0xFFB2BBCB);

  // ── Brand ─────────────────────────────────────────────────
  static const Color navy = Color(0xFF15368A);
  static const Color navyDeep = Color(0xFF0E2766);
  static const Color navyRaised = Color(0xFF2450B4);
  static const Color navyIcon = Color(0xFF2563EB);
  static const Color blue = Color(0xFF2779FD);
  static const Color greenBright = Color(0xFF04AB79);
  static const Color blueTint = Color(0xFFEAF1FF);

  static const Color green = Color(0xFF079A68);
  static const Color greenDeep = Color(0xFF026C45);
  static const Color greenSoft = Color(0xFF35C08E);
  static const Color mint = Color(0xFFE4F6EE);
  static const Color mintLine = Color(0xFFC3EAD8);

  // ── Status ────────────────────────────────────────────────
  static const Color amber = Color(0xFFB7791F);
  static const Color amberBg = Color(0xFFFFF4E0);
  static const Color amberLine = Color(0xFFF5E1BC);
  static const Color red = Color(0xFFE5484D);
  static const Color redBg = Color(0xFFFDECEC);
  static const Color redLine = Color(0xFFF8CFD0);

  // ── Radii ─────────────────────────────────────────────────
  static const double rSm = 10;
  static const double rMd = 12;
  static const double rLg = 14;
  static const double rXl = 18;

  // ── Spacing ───────────────────────────────────────────────
  static const double gutter = 24;
  static const EdgeInsets page = EdgeInsets.fromLTRB(24, 8, 24, 32);

  // ── Type ──────────────────────────────────────────────────
  // The Inter family comes from the app theme, so these styles only set
  // size, weight and colour.
  static const TextStyle display = TextStyle(
    fontSize: 26,
    height: 1.2,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.4,
    color: ink,
  );
  static const TextStyle title = TextStyle(
    fontSize: 19,
    height: 1.25,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.2,
    color: ink,
  );
  static const TextStyle section = TextStyle(
    fontSize: 16,
    height: 1.3,
    fontWeight: FontWeight.w700,
    color: ink,
  );
  static const TextStyle body = TextStyle(
    fontSize: 14.5,
    height: 1.4,
    fontWeight: FontWeight.w400,
    color: ink,
  );
  static const TextStyle bodyStrong = TextStyle(
    fontSize: 15,
    height: 1.4,
    fontWeight: FontWeight.w600,
    color: ink,
  );
  static const TextStyle label = TextStyle(
    fontSize: 14,
    height: 1.3,
    fontWeight: FontWeight.w500,
    color: ink,
  );
  static const TextStyle caption = TextStyle(
    fontSize: 13,
    height: 1.4,
    fontWeight: FontWeight.w400,
    color: muted,
  );
  static const TextStyle tiny = TextStyle(
    fontSize: 11,
    height: 1.3,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.6,
    color: muted,
  );
  static const TextStyle link = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: green,
  );
  static const TextStyle money = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: ink,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static const List<BoxShadow> softShadow = [
    BoxShadow(color: Color(0x0D10255A), blurRadius: 16, offset: Offset(0, 6)),
  ];

  /// Navy balance card (Home).
  static const LinearGradient navyGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1B3F99), Color(0xFF15368A), Color(0xFF0E2766)],
  );

  /// Green balance card (My Wallet).
  static const LinearGradient greenGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF079A68), Color(0xFF02804F), Color(0xFF026C45)],
  );

  /// ₦ formatting with thousands separators: 124850 → ₦124,850.00
  static String naira(num? value, {bool decimals = true}) {
    final v = (value ?? 0).toDouble();
    final neg = v < 0;
    final fixed = v.abs().toStringAsFixed(decimals ? 2 : 0);
    final parts = fixed.split('.');
    final whole = parts[0].replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (m) => ',',
    );
    final s = parts.length > 1 ? '$whole.${parts[1]}' : whole;
    return '${neg ? '-' : ''}₦$s';
  }
}

/// Icon set for the redesign. Material outlined/rounded glyphs chosen to match
/// the line icons in the design files.
class DPIcons {
  DPIcons._();
  // services
  static const IconData phone = Icons.phone_outlined;
  static const IconData wifi = Icons.wifi_rounded;
  static const IconData bolt = Icons.bolt_outlined;
  static const IconData tv = Icons.live_tv_outlined;
  static const IconData trophy = Icons.emoji_events_outlined;
  static const IconData plane = Icons.flight_outlined;
  static const IconData globe = Icons.public_rounded;
  static const IconData grid = Icons.grid_view_rounded;
  static const IconData router = Icons.router_outlined;
  static const IconData school = Icons.school_outlined;
  static const IconData shield = Icons.shield_outlined;
  static const IconData heart = Icons.volunteer_activism_outlined;
  static const IconData ticket = Icons.confirmation_number_outlined;
  // navigation
  static const IconData home = Icons.home_outlined;
  static const IconData homeFilled = Icons.home_rounded;
  static const IconData activity = Icons.swap_horiz_rounded;
  static const IconData earnings = Icons.auto_awesome_outlined;
  static const IconData user = Icons.person_outline_rounded;
  static const IconData userFilled = Icons.person_rounded;
  static const IconData back = Icons.arrow_back_rounded;
  static const IconData forward = Icons.arrow_forward_rounded;
  static const IconData upRight = Icons.north_east_rounded;
  static const IconData downLeft = Icons.south_west_rounded;
  static const IconData chevronRight = Icons.chevron_right_rounded;
  static const IconData chevronDown = Icons.keyboard_arrow_down_rounded;
  static const IconData close = Icons.close_rounded;
  static const IconData menu = Icons.menu_rounded;
  // actions
  static const IconData plus = Icons.add_rounded;
  static const IconData copy = Icons.copy_rounded;
  static const IconData share = Icons.share_outlined;
  static const IconData search = Icons.search_rounded;
  static const IconData refresh = Icons.refresh_rounded;
  static const IconData edit = Icons.edit_outlined;
  static const IconData download = Icons.download_rounded;
  static const IconData scan = Icons.qr_code_scanner_rounded;
  static const IconData contact = Icons.perm_contact_calendar_outlined;
  static const IconData calendar = Icons.calendar_today_outlined;
  static const IconData logout = Icons.logout_rounded;
  // status
  static const IconData eye = Icons.visibility_outlined;
  static const IconData eyeOff = Icons.visibility_off_outlined;
  static const IconData sparkle = Icons.auto_awesome_outlined;
  static const IconData sun = Icons.wb_sunny_outlined;
  static const IconData shieldCheck = Icons.verified_user_outlined;
  static const IconData info = Icons.info_outline_rounded;
  static const IconData alert = Icons.error_outline_rounded;
  static const IconData check = Icons.check_rounded;
  static const IconData checkCircle = Icons.check_circle_outline_rounded;
  static const IconData pending = Icons.schedule_rounded;
  static const IconData failed = Icons.cancel_outlined;
  // account
  static const IconData lock = Icons.lock_outline_rounded;
  static const IconData fingerprint = Icons.fingerprint_rounded;
  static const IconData bell = Icons.notifications_none_rounded;
  static const IconData help = Icons.help_outline_rounded;
  static const IconData mail = Icons.mail_outline_rounded;
  static const IconData bank = Icons.account_balance_outlined;
  static const IconData wallet = Icons.account_balance_wallet_outlined;
  static const IconData people = Icons.group_outlined;
  static const IconData referral = Icons.group_add_outlined;
  static const IconData badge = Icons.badge_outlined;
  static const IconData receipt = Icons.receipt_long_outlined;
  static const IconData history = Icons.history_rounded;
  static const IconData settings = Icons.settings_outlined;
  static const IconData flag = Icons.flag_outlined;
  static const IconData messageCircle = Icons.chat_bubble_outline_rounded;
  static const IconData gift = Icons.card_giftcard_outlined;
  static const IconData smartphone = Icons.smartphone_rounded;
  static const IconData sms = Icons.sms_outlined;
  static const IconData chart = Icons.bar_chart_rounded;
  static const IconData key = Icons.key_outlined;
  static const IconData admin = Icons.admin_panel_settings_outlined;
}
