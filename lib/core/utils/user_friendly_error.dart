// lib/core/utils/user_friendly_error.dart

import 'package:flutter/foundation.dart';

/// 🛡️ CENTRALIZED USER-FRIENDLY ERROR SYSTEM
///
/// Rules:
/// 1. NEVER expose: URLs, hostnames, .onrender.com, .herokuapp.com, VTpass,
///    exception class names, HTTP codes, stack traces, MongoDB errors
/// 2. ALWAYS map to what actually happened
/// 3. ALWAYS tell user the best next action
class UserFriendlyError {
  final String title;
  final String message;
  final String action;
  final ErrorSeverity severity;
  final String code;

  const UserFriendlyError({
    required this.title,
    required this.message,
    required this.action,
    required this.severity,
    required this.code,
  });

  /// Full user-facing text (message + action)
  String get fullText => '$message $action';

  /// Short text for snackbars
  String get shortText => message;
}

enum ErrorSeverity { info, warning, error, critical }

/// 🎯 THE MASTER ERROR MAPPER
/// Takes ANY exception/dynamic and returns a clean UserFriendlyError.
UserFriendlyError mapToUserFriendlyError(dynamic error) {
  final raw = error?.toString() ?? '';

  if (kDebugMode) {
    debugPrint('🔍 [UserFriendlyError] Raw: $raw');
  }

  final lower = raw.toLowerCase();

  // ============================================================
  // 1. NETWORK & CONNECTIVITY
  // ============================================================
  if (lower.contains('socketexception') ||
      lower.contains('clientexception') ||
      lower.contains('failed to fetch') ||
      lower.contains('network is unreachable') ||
      lower.contains('connection refused') ||
      lower.contains('connection reset') ||
      lower.contains('connection closed') ||
      lower.contains('xmlhttprequest') ||
      lower.contains('handshakeexception') ||
      lower.contains('no internet')) {
    return const UserFriendlyError(
      title: 'Connection Problem',
      message: 'We can\'t reach our servers right now.',
      action: 'Please check your internet connection and try again.',
      severity: ErrorSeverity.error,
      code: 'NETWORK_ERROR',
    );
  }

  if (lower.contains('timeoutexception') ||
      lower.contains('timeout') ||
      lower.contains('took too long')) {
    return const UserFriendlyError(
      title: 'Request Timed Out',
      message: 'The request took too long to complete.',
      action: 'Please check your network and try again.',
      severity: ErrorSeverity.warning,
      code: 'TIMEOUT',
    );
  }

  // ============================================================
  // 2. SERVER ERRORS (5xx)
  // ============================================================
  if (lower.contains('500') ||
      lower.contains('502') ||
      lower.contains('503') ||
      lower.contains('504') ||
      lower.contains('internal server error') ||
      lower.contains('service unavailable') ||
      lower.contains('bad gateway')) {
    return const UserFriendlyError(
      title: 'Service Unavailable',
      message: 'Our service is temporarily unavailable.',
      action: 'Please try again in a few minutes.',
      severity: ErrorSeverity.critical,
      code: 'SERVER_ERROR',
    );
  }

  // ============================================================
  // 3. AUTHENTICATION & SESSION
  // ============================================================
  if (lower.contains('token expired') ||
      lower.contains('token_expired') ||
      lower.contains('session expired') ||
      lower.contains('session_expired') ||
      lower.contains('requireslogin') ||
      lower.contains('requires login')) {
    return const UserFriendlyError(
      title: 'Session Expired',
      message: 'Your login session has expired.',
      action: 'Please log in again to continue.',
      severity: ErrorSeverity.warning,
      code: 'SESSION_EXPIRED',
    );
  }

  if (lower.contains('invalid token') ||
      lower.contains('invalid_token') ||
      lower.contains('no token') ||
      lower.contains('no_token') ||
      lower.contains('401') ||
      lower.contains('unauthorized') ||
      lower.contains('not authorized') ||
      lower.contains('authentication required') ||
      lower.contains('authenticationtoken') ||
      lower.contains('authentication token not found')) {
    return const UserFriendlyError(
      title: 'Login Required',
      message: 'We couldn\'t verify your identity.',
      action: 'Please log in again to continue.',
      severity: ErrorSeverity.warning,
      code: 'AUTH_REQUIRED',
    );
  }

  if (lower.contains('403') || lower.contains('forbidden')) {
    return const UserFriendlyError(
      title: 'Access Denied',
      message: 'You don\'t have permission to do that.',
      action: 'Please contact support if you believe this is a mistake.',
      severity: ErrorSeverity.warning,
      code: 'FORBIDDEN',
    );
  }

  // ============================================================
  // 4. RATE LIMITING
  // ============================================================
  if (lower.contains('429') ||
      lower.contains('too many requests') ||
      lower.contains('too many attempts') ||
      lower.contains('rate limit') ||
      lower.contains('slow down') ||
      lower.contains('per_minute_limit') ||
      lower.contains('global_per_minute')) {
    return const UserFriendlyError(
      title: 'Please Slow Down',
      message: 'You\'ve made too many requests in a short time.',
      action: 'Please wait a moment and try again.',
      severity: ErrorSeverity.warning,
      code: 'RATE_LIMITED',
    );
  }

  // ============================================================
  // 5. WALLET & BALANCE
  // ============================================================
  if (lower.contains('insufficient wallet balance') ||
      lower.contains('insufficient balance') ||
      lower.contains('insufficient_balance') ||
      lower.contains('insufficient funds')) {
    return const UserFriendlyError(
      title: 'Insufficient Balance',
      message: 'You don\'t have enough money in your wallet.',
      action: 'Please fund your wallet and try again.',
      severity: ErrorSeverity.warning,
      code: 'INSUFFICIENT_BALANCE',
    );
  }

  if (lower.contains('insufficient commission')) {
    return const UserFriendlyError(
      title: 'Insufficient Commission',
      message: 'You don\'t have enough commission balance.',
      action:
          'Keep transacting to earn more commission, or pay from your wallet instead.',
      severity: ErrorSeverity.warning,
      code: 'INSUFFICIENT_COMMISSION',
    );
  }

  // ============================================================
  // 6. TRANSACTION PIN
  // ============================================================
  if (lower.contains('invalid transaction pin') ||
      lower.contains('invalid pin')) {
    final attemptsMatch = RegExp(r'(\d+)\s+attempt').firstMatch(lower);
    final attempts = attemptsMatch?.group(1);
    final attemptsText =
        attempts != null
            ? 'You have $attempts attempt${attempts == '1' ? '' : 's'} left.'
            : 'Please try again carefully.';

    return UserFriendlyError(
      title: 'Incorrect PIN',
      message: 'The PIN you entered is incorrect.',
      action: attemptsText,
      severity: ErrorSeverity.warning,
      code: 'INVALID_PIN',
    );
  }

  if (lower.contains('pin not set') ||
      lower.contains('transaction pin not set')) {
    return const UserFriendlyError(
      title: 'PIN Not Set',
      message: 'You haven\'t set up a transaction PIN yet.',
      action: 'Go to Settings → Security to create your PIN.',
      severity: ErrorSeverity.info,
      code: 'PIN_NOT_SET',
    );
  }

  if (lower.contains('account locked') ||
      lower.contains('pin locked') ||
      lower.contains('too many failed attempts')) {
    final minMatch = RegExp(r'(\d+)\s+minute').firstMatch(lower);
    final mins = minMatch?.group(1);
    final actionText =
        mins != null
            ? 'Your account is temporarily locked for $mins minute${mins == '1' ? '' : 's'}. Please try again later or reset your PIN.'
            : 'Your account is temporarily locked. Please try again later or reset your PIN.';

    return UserFriendlyError(
      title: 'Account Locked',
      message: 'Too many incorrect PIN attempts.',
      action: actionText,
      severity: ErrorSeverity.warning,
      code: 'ACCOUNT_LOCKED',
    );
  }

  // ============================================================
  // 7. TRANSACTION LIMITS
  // ============================================================
  if (lower.contains('per_transaction_limit_exceeded') ||
      (lower.contains('maximum') && lower.contains('per transaction'))) {
    final amountMatch = RegExp(r'₦([\d,]+(?:\.\d{1,2})?)').firstMatch(raw);
    final limit = amountMatch?.group(1);
    final actionText =
        limit != null
            ? 'Please try a lower amount (max ₦$limit) or request a limit increase from support.'
            : 'Please try a lower amount or request a limit increase from support.';

    return UserFriendlyError(
      title: 'Amount Too High',
      message: 'This amount exceeds your per-transaction limit.',
      action: actionText,
      severity: ErrorSeverity.warning,
      code: 'PER_TX_LIMIT',
    );
  }

  if (lower.contains('daily_limit_exceeded') ||
      (lower.contains('daily') &&
          lower.contains('limit') &&
          lower.contains('exceeded'))) {
    final amountMatch = RegExp(r'₦([\d,]+(?:\.\d{1,2})?)').firstMatch(raw);
    final limit = amountMatch?.group(1);
    final actionText =
        limit != null
            ? 'You\'ve reached your daily limit of ₦$limit. Try again tomorrow or contact support for an increase.'
            : 'You\'ve reached your daily limit. Try again tomorrow or contact support.';

    return UserFriendlyError(
      title: 'Daily Limit Reached',
      message: 'You\'ve hit today\'s transaction limit.',
      action: actionText,
      severity: ErrorSeverity.warning,
      code: 'DAILY_LIMIT',
    );
  }

  // ============================================================
  // 8. DUPLICATE / ALREADY PROCESSED
  // ============================================================
  if (lower.contains('already processed') ||
      lower.contains('duplicate') ||
      lower.contains('recent_transaction_exists') ||
      lower.contains('already completed') ||
      lower.contains('this transaction was already')) {
    return const UserFriendlyError(
      title: 'Already Processed',
      message: 'This transaction was already processed.',
      action: 'Please check your transaction history for the result.',
      severity: ErrorSeverity.info,
      code: 'DUPLICATE',
    );
  }

  // ============================================================
  // 9. SERVICE UNAVAILABLE / DISABLED
  // ============================================================
  if (lower.contains('service_disabled') ||
      lower.contains('currently disabled') ||
      lower.contains('service is not available') ||
      lower.contains('service not available')) {
    return const UserFriendlyError(
      title: 'Service Unavailable',
      message: 'This service is temporarily unavailable.',
      action: 'Please try again later or use another service.',
      severity: ErrorSeverity.warning,
      code: 'SERVICE_DISABLED',
    );
  }

  if (lower.contains('maintenance')) {
    return const UserFriendlyError(
      title: 'Under Maintenance',
      message: 'Our system is undergoing scheduled maintenance.',
      action: 'Please try again in a little while.',
      severity: ErrorSeverity.info,
      code: 'MAINTENANCE',
    );
  }

  // ============================================================
  // 10. PROVIDER / VTPASS-SIDE ISSUES (hidden from user)
  // ============================================================
  if (lower.contains('vtpass') ||
      lower.contains('provider wallet') ||
      lower.contains('low wallet balance') ||
      lower.contains('biller not reachable') ||
      lower.contains('biller unreachable')) {
    return const UserFriendlyError(
      title: 'Service Temporarily Down',
      message: 'We\'re having trouble reaching the service provider.',
      action: 'Please try again in a few minutes.',
      severity: ErrorSeverity.warning,
      code: 'PROVIDER_ISSUE',
    );
  }

  // ============================================================
  // 11. VALIDATION / INPUT ERRORS
  // ============================================================
  if (lower.contains('invalid phone') || lower.contains('valid phone')) {
    return const UserFriendlyError(
      title: 'Invalid Phone Number',
      message: 'The phone number you entered doesn\'t look right.',
      action: 'Please check the number and try again.',
      severity: ErrorSeverity.info,
      code: 'INVALID_PHONE',
    );
  }

  if (lower.contains('invalid email')) {
    return const UserFriendlyError(
      title: 'Invalid Email',
      message: 'The email address you entered doesn\'t look right.',
      action: 'Please check the email and try again.',
      severity: ErrorSeverity.info,
      code: 'INVALID_EMAIL',
    );
  }

  if (lower.contains('invalid meter') ||
      lower.contains('invalid smartcard') ||
      lower.contains('invalid biller')) {
    return const UserFriendlyError(
      title: 'Invalid Details',
      message: 'The number you entered doesn\'t match any customer.',
      action: 'Please double-check the number and try again.',
      severity: ErrorSeverity.info,
      code: 'INVALID_METER',
    );
  }

  if (lower.contains('amount below minimum') ||
      lower.contains('minimum amount') ||
      lower.contains('below minimum')) {
    return const UserFriendlyError(
      title: 'Amount Too Low',
      message: 'The amount you entered is below the minimum allowed.',
      action: 'Please enter a higher amount.',
      severity: ErrorSeverity.info,
      code: 'BELOW_MINIMUM',
    );
  }

  // ============================================================
  // 12. EMAIL / PHONE DUPLICATE
  // ============================================================
  if (lower.contains('email already exists') ||
      lower.contains('this email is already registered')) {
    return const UserFriendlyError(
      title: 'Email Already Registered',
      message: 'An account with this email already exists.',
      action: 'Please log in instead, or use a different email.',
      severity: ErrorSeverity.info,
      code: 'EMAIL_DUPLICATE',
    );
  }

  if (lower.contains('phone already') ||
      lower.contains('phone number already') ||
      lower.contains('this phone number is already')) {
    return const UserFriendlyError(
      title: 'Phone Already Registered',
      message: 'This phone number is already in use.',
      action: 'Please log in instead, or use a different phone number.',
      severity: ErrorSeverity.info,
      code: 'PHONE_DUPLICATE',
    );
  }

  // ============================================================
  // 13. ACCOUNT APPROVAL
  // ============================================================
  if (lower.contains('account_pending_approval') ||
      lower.contains('under approval')) {
    return const UserFriendlyError(
      title: 'Account Pending Approval',
      message: 'Your account is still being reviewed.',
      action:
          'You\'ll be able to transact once our team approves your account.',
      severity: ErrorSeverity.info,
      code: 'PENDING_APPROVAL',
    );
  }

  if (lower.contains('account_rejected') ||
      lower.contains('account has been rejected')) {
    return const UserFriendlyError(
      title: 'Account Rejected',
      message: 'Your account was rejected.',
      action: 'Please contact support for more information.',
      severity: ErrorSeverity.error,
      code: 'ACCOUNT_REJECTED',
    );
  }

  if (lower.contains('account deactivated') || lower.contains('inactive')) {
    return const UserFriendlyError(
      title: 'Account Deactivated',
      message: 'Your account has been deactivated.',
      action: 'Please contact support to reactivate it.',
      severity: ErrorSeverity.error,
      code: 'ACCOUNT_INACTIVE',
    );
  }

  // ============================================================
  // 14. FILE UPLOAD
  // ============================================================
  if (lower.contains('file too large') || lower.contains('payload too large')) {
    return const UserFriendlyError(
      title: 'File Too Large',
      message: 'The file you\'re trying to upload is too big.',
      action: 'Please use a smaller file (under 2MB).',
      severity: ErrorSeverity.info,
      code: 'FILE_TOO_LARGE',
    );
  }

  if (lower.contains('only image')) {
    return const UserFriendlyError(
      title: 'Invalid File Type',
      message: 'Only image files are allowed.',
      action: 'Please choose a JPG, PNG, or GIF file.',
      severity: ErrorSeverity.info,
      code: 'INVALID_FILE',
    );
  }

  // ============================================================
  // 15. GENERIC FALLBACK — safe, friendly, no leakage
  // ============================================================
  return const UserFriendlyError(
    title: 'Something Went Wrong',
    message: 'We couldn\'t complete that request.',
    action: 'Please try again. If the problem continues, contact support.',
    severity: ErrorSeverity.error,
    code: 'UNKNOWN',
  );
}

/// ✅ Convenience: get only the user-facing message string
String getUserFriendlyMessage(dynamic error) {
  return mapToUserFriendlyError(error).fullText;
}

/// ✅ Convenience: get short snackbar-friendly text
String getUserFriendlyShortMessage(dynamic error) {
  return mapToUserFriendlyError(error).shortText;
}
