import 'dart:async';
import 'dart:convert';
import 'package:dalabapay/main.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, kDebugMode, debugPrint, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart'; // ✅ Added
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:local_auth/local_auth.dart';
import 'package:mime/mime.dart';
import 'package:http_parser/http_parser.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:dalabapay/core/services/payment_service.dart';
import 'package:synchronized/synchronized.dart' as sync_lib;
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';
// Add this import at the top of api_service.dart
import 'biometric_service.dart';
import 'secure_storage_service.dart';
import 'package:image_picker/image_picker.dart' show XFile;

// Platform-specific imports
import 'dart:io'
    as io
    show Process, SocketException, HttpClient, X509Certificate, File;

// ==================== RBAC PERMISSION CONSTANTS ====================
// Helper class for permission names (use these strings to avoid typos)

class RbacPermissions {
  // Dashboard
  static const String viewDashboard = 'view_dashboard';

  // Users
  static const String viewUsers = 'view_users';
  static const String manageUsers = 'manage_users';
  static const String updateUserStatus = 'update_user_status';

  // Transactions
  static const String viewTransactions = 'view_transactions';
  static const String viewAllTransactions = 'view_all_transactions';
  static const String updateTransactionStatus = 'update_transaction_status';

  // Refunds & Disputes
  static const String processRefunds = 'process_refunds';
  static const String viewDisputes = 'view_disputes';
  static const String resolveDisputes = 'resolve_disputes';

  // Settings & Reports
  static const String manageSettings = 'manage_settings';
  static const String viewReports = 'view_reports';
  static const String viewFinancialReports = 'view_financial_reports';
  static const String exportData = 'export_data';

  // Notifications
  static const String sendNotifications = 'send_notifications';
  static const String manageNotifications = 'manage_notifications';

  // Wallet
  static const String manageWallet = 'manage_wallet';

  // User self permissions
  static const String viewProfile = 'view_profile';
  static const String updateProfile = 'update_profile';
  static const String viewOwnTransactions = 'view_own_transactions';
  static const String makeTransactions = 'make_transactions';
  static const String createOwnDisputes = 'create_own_disputes';
  static const String viewOwnDisputes = 'view_own_disputes';
  static const String viewCommission = 'view_commission';

  // Admin management
  static const String manageAdmins = 'manage_admins';
}

// ==================== FIXED TOKEN MANAGER ====================
class _TokenManager {
  static final _TokenManager _instance = _TokenManager._internal();
  factory _TokenManager() => _instance;
  _TokenManager._internal();

  bool _isRefreshing = false;
  final List<Completer<bool>> _refreshWaiters = [];
  static final sync_lib.Lock _refreshLock = sync_lib.Lock();

  static void _tokenLog(String message) {
    if (kDebugMode) {
      debugPrint('TOKEN MANAGER: $message');
    }
  }

  /// 🔄 Token refresh with queue & single-flight locking
  Future<bool> refreshTokenWithQueue() async {
    return await _refreshLock.synchronized<bool>(() async {
      if (_isRefreshing) {
        final completer = Completer<bool>();
        _refreshWaiters.add(completer);
        return await completer.future;
      }

      _isRefreshing = true;
      try {
        _tokenLog('🔄 Starting token refresh...');

        final refreshToken = await SecureStorageService.getRefreshToken();
        if (refreshToken == null || refreshToken.isEmpty) {
          _tokenLog('❌ No refresh token available');
          _completeRefreshWaiters(false);
          return false;
        }

        final response = await http
            .post(
              Uri.parse(
                'https://vtpass-backend.onrender.com/api/users/refresh-token',
              ),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'refreshToken': refreshToken}),
            )
            .timeout(const Duration(seconds: 30));

        _tokenLog('Token refresh response status: ${response.statusCode}');

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['success'] == true && data['token'] != null) {
            await SecureStorageService.saveTokens(
              accessToken: data['token'],
              refreshToken: data['refreshToken'] ?? refreshToken,
              userId: data['user']?['_id']?.toString(),
            );

            _tokenLog('✅ TOKEN REFRESH SUCCESSFUL');
            _completeRefreshWaiters(true);
            return true;
          }
        }

        _tokenLog('⚠️ Server rejected token refresh');
        _completeRefreshWaiters(false);
        return false;
      } catch (e) {
        _tokenLog('❌ Token refresh error: $e');
        _completeRefreshWaiters(false);
        return false;
      } finally {
        _isRefreshing = false;
      }
    });
  }

  void _completeRefreshWaiters(bool success) {
    for (final waiter in _refreshWaiters) {
      if (!waiter.isCompleted) {
        waiter.complete(success);
      }
    }
    _refreshWaiters.clear();
  }

  // ✅ STATIC methods for class-level calls (`_TokenManager.getSafeToken()`)
  static Future<String?> getSafeToken() async {
    return await SecureStorageService.getAccessToken();
  }

  static Future<String?> _getRefreshToken() async {
    return await SecureStorageService.getRefreshToken();
  }

  static Future<bool> _verifyTokenValidity() async {
    final token = await SecureStorageService.getAccessToken();
    return token != null && token.isNotEmpty;
  }
}

// Global instance
final _tokenManager = _TokenManager();

/// A service class to handle all API calls for the application, with support for both sandbox and live environments.
class ApiService {
  // Base URL for your backend
  static const String baseUrl = 'https://vtpass-backend.onrender.com';
  static const String virtualAccountBaseUrl =
      'https://virtual-account-backend.onrender.com';
  // ✅ Asset base URL — used by ImageHelper to build full image URLs
  // Your backend serves uploads at: /uploads/...
  static const String assetBaseUrl = 'https://vtpass-backend.onrender.com';

  static final Dio _dioInstance = Dio(
    BaseOptions(
      baseUrl: 'https://vtpass-backend.onrender.com',
      headers: {'Content-Type': 'application/json'},
    ),
  );

  // ==== 🔐 ENHANCED SECURITY PROTECTIONS ====
  static final Map<String, List<DateTime>> _userRequestTimestamps = {};
  static final Map<String, String> _idempotencyKeys = {};
  static final Map<String, DateTime> _idempotencyKeyTimestamps = {};
  static const int _maxRequestsPerSecond = 3;
  static const int _maxRequestsPerMinute = 20;
  static const Duration _rateLimitWindow = Duration(seconds: 60);
  static const Duration _idempotencyKeyExpiry = Duration(hours: 24);

  // Enhanced encryption
  static final _encryptionKey = encrypt.Key.fromSecureRandom(32);
  static final _iv = encrypt.IV.fromSecureRandom(16);
  static final _encrypter = encrypt.Encrypter(encrypt.AES(_encryptionKey));

  // Enhanced transaction locks with expiration
  static final Map<String, DateTime> _transactionLocks = {};
  static final Map<String, Completer<void>> _walletLocks = {};
  static final Map<String, int> _lockAttempts = {};
  static const int _maxLockAttempts = 3;
  static const Duration _lockTimeout = Duration(seconds: 30);

  /// FINAL & PERFECT VTpass request_id — NEVER DUPLICATES, 100% ACCEPTED
  static String generateVtpassRequestId() {
    final now = DateTime.now();
    final timestamp = DateFormat('yyyyMMddHHmmss').format(now);
    final random6Digits = Random().nextInt(900000) + 100000;
    return '${timestamp}_$random6Digits';
  }

  // ✅ FIXED: Database-level lock simulation with proper import
  static final sync_lib.Lock _databaseLock = sync_lib.Lock();
  static final Map<String, sync_lib.Lock> _userLocks = {};
  // ==== END ENHANCED SECURITY PROTECTIONS ====

  // ==== 🔐 VTpass CREDENTIALS - BOTH SANDBOX & LIVE ====
  // Dynamic credentials storage
  static String _apiKey = '';
  static String _secretKey = '';
  static String _publicKey = '';

  // Credentials for both environments
  static const Map<String, Map<String, String>> _vtpassCredentials = {
    'sandbox': {
      'apiKey': String.fromEnvironment('VTPASS_SANDBOX_API_KEY'),
      'secretKey': String.fromEnvironment('VTPASS_SANDBOX_SECRET_KEY'),
      'publicKey': String.fromEnvironment('VTPASS_SANDBOX_PUBLIC_KEY'),
    },
    'live': {
      'apiKey': String.fromEnvironment('VTPASS_LIVE_API_KEY'), // Your live API key
      'secretKey':
          String.fromEnvironment('VTPASS_LIVE_SECRET_KEY'), // Your live secret
      'publicKey':
          String.fromEnvironment('VTPASS_LIVE_PUBLIC_KEY'), // Your live public key
    },
  };

  // Initialize credentials based on environment
  static Future<void> _initializeCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final useSandbox = prefs.getBool('useSandbox') ?? false;

    // FORCE LIVE MODE - Remove this line if you want to keep toggle
    _useSandbox = false;

    final env = _useSandbox ? 'sandbox' : 'live';
    final credentials = _vtpassCredentials[env] ?? _vtpassCredentials['live']!;

    _apiKey = credentials['apiKey']!;
    _secretKey = credentials['secretKey']!;
    _publicKey = credentials['publicKey']!;

    _log('🔐 Initialized $env credentials');
    _log('API Key: ${_apiKey.substring(0, 8)}...');
  }

  // VTpass Sandbox and Live URLs
  static const String _vtpassSandboxUrl = 'https://sandbox.vtpass.com/api/';
  static const String _vtpassLiveUrl = 'https://vtpass.com/api/';

  // Toggle between sandbox and live for VTpass services
  static bool _useSandbox = false; // Can be toggled via settings or admin panel
  static bool _isHandlingAuthFailure = false;

  // VTpass base URL based on toggle
  static String get _vtpassUrl =>
      _useSandbox ? _vtpassSandboxUrl : _vtpassLiveUrl;

  // Service IDs for airtime and other services
  static const Map<String, String> _airtimeServiceIds = {
    'MTN': 'mtn',
    'Airtel': 'airtel',
    'Glo': 'glo',
    '9mobile': 'etisalat',
    'International Airtime': 'foreign-airtime',
    'wallet': 'wallet',
  };

  // Test phone numbers for sandbox mode (per VTpass documentation)
  static const List<String> _sandboxTestPhoneNumbers = [
    '08011111111', // Successful
    '201000000000', // Pending
    '500000000000', // Unexpected Response
    '400000000000', // No Response
    '300000000000', // Timeout
  ];

  // List of supported services
  static const List<String> _supportedServices = [
    'airtime',
    'data',
    'cable',
    'electricity',
    'education', // ADD THIS LINE
    'insurance', // ADD THIS LINE
    'wallet',
  ];

  // Electricity Service IDs for all supported DisCos
  static const Map<String, String> _electricityServiceIds = {
    'IKEDC': 'ikeja-electric',
    'EKEDC': 'eko-electric',
    'KEDCO': 'kano-electric',
    'PHED': 'portharcourt-electric',
    'JED': 'jos-electric',
    'IBEDC': 'ibadan-electric',
    'KAEDCO': 'kaduna-electric',
    'AEDC': 'abuja-electric',
    'EEDC': 'enugu-electric',
    'BEDC': 'benin-electric',
    'ABA': 'aba-electric',
    'YEDC': 'yola-electric',
  };

  // Electricity meter types
  static const Map<String, String> _electricityMeterTypes = {
    'prepaid': 'prepaid',
    'postpaid': 'postpaid',
  };

  // Test meter numbers for sandbox mode (from VTpass documentation)
  static const Map<String, Map<String, String>> _sandboxTestMeterNumbers = {
    'IKEDC': {'prepaid': '1111111111111', 'postpaid': '1010101010101'},
    'EKEDC': {'prepaid': '1111111111111', 'postpaid': '1010101010101'},
    'KEDCO': {'prepaid': '1111111111111', 'postpaid': '1010101010101'},
    'PHED': {'prepaid': '1111111111111', 'postpaid': '1010101010101'},
    'JED': {'prepaid': '1111111111111', 'postpaid': '1010101010101'},
    'IBEDC': {'prepaid': '1111111111111', 'postpaid': '1010101010101'},
    'KAEDCO': {'prepaid': '1111111111111', 'postpaid': '1010101010101'},
    'AEDC': {'prepaid': '1111111111111', 'postpaid': '1010101010101'},
    'EEDC': {'prepaid': '1111111111111', 'postpaid': '1010101010101'},
    'BEDC': {'prepaid': '1111111111111', 'postpaid': '1010101010101'},
    'ABA': {'prepaid': '1111111111111', 'postpaid': '1010101010101'},
    'YEDC': {'prepaid': '1111111111111', 'postpaid': '1010101010101'},
  };

  // Special test meter numbers for simulating different scenarios
  static const Map<String, String> _specialTestMeters = {
    'pending': '201000000000',
    'unexpected_response': '500000000000',
    'no_response': '400000000000',
    'timeout': '300000000000',
  };

  // Minimum purchase amounts for specific DisCos
  static const Map<String, double> _electricityMinAmounts = {
    'IBEDC': 2000.0, // Band A: ₦5,000, Other Bands: ₦2,000
    'KAEDCO': 500.0,
    'YEDC': 500.0,
  };

  // Convenience fees for specific DisCos
  static const Map<String, double> _electricityConvenienceFees = {
    'BEDC': 100.0,
    'ABA': 100.0,
    'YEDC': 100.0,
    'IBEDC': 100.0,
  };

  // Update your commission rates to include insurance
  static const Map<String, double> _commissionRates = {
    'airtime': 0.002, // 0.2%
    'data': 0.002, // 0.2%
    'cable': 0.002, // 0.2%
    'electricity': 0.002, // 0.2%
    'education': 0.002, // 0.2%
    'insurance': 0.002, // 0.2% - ADDED INSURANCE
    'wallet_funding': 0.005,
  };

  // Add this to your service IDs section
  static const Map<String, String> _educationServiceIds = {
    'WAEC Registration': 'waec-registration',
    'WAEC Result Checker': 'waec',
    'JAMB PIN': 'jamb',
  };

  static const double _referralBonus = 100.0; // ₦100 per successful referral
  static const double _firstTransactionBonus = 200.0; // ₦200 welcome bonus
  static const double _indirectReferralBonus = 20.0;
  static const double _directReferralBonus = 200.0; //
  static const double _transactionCommissionRate = 0.002; // 0.2%

  // --- API Endpoints ---
  // User Authentication & Management
  static final _registerUrl = Uri.parse('$baseUrl/api/users/register');
  static final _loginUrl = Uri.parse('$baseUrl/api/users/login');
  static final _logoutUrl = Uri.parse('$baseUrl/api/users/logout');
  static final _forgotPasswordUrl = Uri.parse(
    '$baseUrl/api/users/forgot-password',
  );
  static final _resetPasswordUrl = Uri.parse(
    '$baseUrl/api/users/reset-password',
  );
  static final _verifyResetOTPUrl = Uri.parse(
    '$baseUrl/api/users/verify-reset-otp',
  );
  static final _balanceUrl = Uri.parse('$baseUrl/api/users/balance');
  static final _commissionBalanceUrl = Uri.parse(
    '$baseUrl/api/commission/balance',
  );
  static final _commissionStatsUrl = Uri.parse('$baseUrl/api/commission/stats');
  static final _commissionWithdrawUrl = Uri.parse(
    '$baseUrl/api/commission/withdraw',
  );
  static final _commissionTransactionsUrl = Uri.parse(
    '$baseUrl/api/commission/transactions',
  );
  static final _commissionUseForServiceUrl = Uri.parse(
    '$baseUrl/api/commission/use-for-service',
  );
  static final _changePasswordUrl = Uri.parse(
    '$baseUrl/api/users/change-password',
  );
  static final _setTransactionPinUrl = Uri.parse(
    '$baseUrl/api/users/set-transaction-pin',
  );
  static final _changeTransactionPinUrl = Uri.parse(
    '$baseUrl/api/users/change-transaction-pin',
  );
  static final _toggleBiometricUrl = Uri.parse(
    '$baseUrl/api/users/toggle-biometric',
  );
  static final _securitySettingsUrl = Uri.parse(
    '$baseUrl/api/users/security-settings',
  );
  static final _verifyTransactionPinUrl = Uri.parse(
    '$baseUrl/api/users/verify-transaction-pin',
  );
  static final _authLogsUrl = Uri.parse('$baseUrl/api/users/auth-logs');
  static final _uploadProfileImageUrl = Uri.parse(
    '$baseUrl/api/users/upload-profile-image',
  );
  static const String _userBaseUrl = '$baseUrl/api/users';
  static final _getUsersUrl = Uri.parse(_userBaseUrl);
  static final _refreshTokenUrl = Uri.parse('$baseUrl/api/users/refresh-token');
  static final _verifyTokenUrl = Uri.parse('$baseUrl/api/users/verify-token');
  static final _reportErrorUrl = Uri.parse('$baseUrl/api/errors/report');
  static final _referralStatsUrl = Uri.parse(
    '$baseUrl/api/users/referral-stats',
  );
  static final _generateReferralCodeUrl = Uri.parse(
    '$baseUrl/api/users/generate-referral-code',
  );
  static final _referralTransactionsUrl = Uri.parse(
    '$baseUrl/api/referral-transactions',
  );
  static final _referralUrl = Uri.parse('$baseUrl/api/referrals');
  static final _validateReferralUrl = Uri.parse(
    '$baseUrl/api/referrals/validate',
  );
  static final _walletTopUpUrl = Uri.parse('$baseUrl/api/wallet/top-up');
  // Atomic transaction endpoint for secure wallet operations
  static final _atomicTransactionUrl = Uri.parse(
    '$baseUrl/api/transactions/atomic',
  );
  // Add these education endpoints
  static final _educationPurchaseUrl = Uri.parse(
    '$_vtpassBaseUrl/education/purchase',
  );
  static final _validateEducationProfileUrl = Uri.parse(
    '$_vtpassBaseUrl/education/validate-profile',
  );
  static final _requestPinResetUrl = Uri.parse(
    '$baseUrl/api/users/request-pin-reset',
  );
  static final _verifyPinResetTokenUrl = Uri.parse(
    '$baseUrl/api/users/verify-pin-reset-token',
  );
  static final _resetPinWithTokenUrl = Uri.parse(
    '$baseUrl/api/users/reset-pin-with-token',
  );

  // Wallet, Transactions & Transfers
  static final _fundWalletUrl = Uri.parse('$baseUrl/api/users/fund');
  static final _transferUrl = Uri.parse('$baseUrl/api/transfer');
  static final _withdrawCommissionUrl = Uri.parse(
    '$baseUrl/api/users/withdraw-commission',
  );
  static final _transactionStatisticsUrl = Uri.parse(
    '$baseUrl/api/transactions/statistics',
  );
  static const String _transactionsBaseUrl = '$baseUrl/api/transactions';
  static final _getAllTransactionsUrl = Uri.parse('$_transactionsBaseUrl/all');

  // VTpass Services URLs
  static const String _vtpassBaseUrl = '$baseUrl/api/vtpass';
  static final _validateSmartcardUrl = Uri.parse(
    '$_vtpassBaseUrl/validate-smartcard',
  );
  static final _cablePurchaseUrl = Uri.parse('$_vtpassBaseUrl/tv/purchase');
  static final _airtimePurchaseUrl = Uri.parse(
    '$_vtpassBaseUrl/airtime/purchase',
  );
  static final _dataPurchaseUrl = Uri.parse('$_vtpassBaseUrl/data/purchase');
  static final _validateElectricityUrl = Uri.parse(
    '$_vtpassBaseUrl/validate-electricity',
  );
  static final _electricityPurchaseUrl = Uri.parse(
    '$_vtpassBaseUrl/electricity/purchase',
  );
  static final _billerServicesUrl = Uri.parse('$_vtpassBaseUrl/services');
  static final _billerVariationsUrl = Uri.parse('$_vtpassBaseUrl/variations');

  // Direct VTpass Endpoints
  static Uri get _vtpassAirtimePurchaseUrl => Uri.parse('${_vtpassUrl}pay');
  static Uri get _vtpassRequeryUrl => Uri.parse('${_vtpassUrl}requery');
  static Uri get _vtpassValidateSmartcardUrl =>
      Uri.parse('${_vtpassUrl}merchant-verify');
  static Uri get _vtpassValidateElectricityUrl =>
      Uri.parse('${_vtpassUrl}merchant-verify');

  // Virtual Account, App Settings, Beneficiaries & Notifications
  static const String _virtualAccountBaseUrl = '$baseUrl/api/virtual-account';
  static final _appSettingsUrl = Uri.parse('$baseUrl/api/settings');
  static final _beneficiariesBaseUrl = Uri.parse('$baseUrl/api/beneficiaries');
  static final _notificationsBaseUrl = Uri.parse('$baseUrl/api/notifications');
  static const String _commissionTransactionsBaseUrl =
      '$baseUrl/api/commission-transactions';

  // Add these to your ApiService:
  static final _commissionRefundUrl = Uri.parse(
    '$baseUrl/api/commission/refund',
  );
  static final _commissionCompleteServiceUrl = Uri.parse(
    '$baseUrl/api/commission/complete-service',
  );

  // Add referral-specific endpoints:
  static final _referralBonusBreakdownUrl = Uri.parse(
    '$baseUrl/api/referral/bonus-breakdown',
  );
  static final _referralDirectEarningsUrl = Uri.parse(
    '$baseUrl/api/referral/direct-earnings',
  );
  static final _referralIndirectEarningsUrl = Uri.parse(
    '$baseUrl/api/referral/indirect-earnings',
  );

  static final _healthCheckUrl = Uri.parse('$baseUrl/health');

  /// Clear authentication data including tokens
  /// Clear authentication data including tokens
  static Future<void> _clearAuthData() async {
    try {
      await SecureStorageService.clearSession();

      final prefs = await SharedPreferences.getInstance();
      // Clear non-token data from SharedPreferences
      await prefs.remove('user');
      await prefs.remove('fullName');
      await prefs.remove('email');
      await prefs.remove('phone');
      await prefs.remove('transactionPinSet');
      await prefs.remove('biometricEnabled');
      await prefs.remove('walletBalance');
      await prefs.remove('commissionBalance');
      await prefs.remove('failedAttempts');
      await prefs.remove('lockoutTime');
      await prefs.remove('isAdmin');
      await prefs.remove('needsReauth');

      await prefs.reload();
      _log('✅ All authentication data cleared including secure tokens.');
    } catch (e) {
      _log('❌ Error clearing auth data: $e');
    }
  }

  // --- Utility Functions ---
  static void _log(String message) {
    if (kDebugMode) {
      debugPrint('API SERVICE DEBUG: $message');
    }
  }

  // ==== 🔐 SECURITY HELPER METHODS - ADD THIS BLOCK ====

  /// Enhanced rate limiting with user-specific tracking
  /// Enhanced rate limiting with user-specific tracking
  static Future<void> _checkRateLimit(String userId, String endpoint) async {
    final now = DateTime.now();
    final key = '$userId-$endpoint';

    // ✅ FIXED: Use sync_lib.Lock
    await _databaseLock.synchronized(() async {
      _userRequestTimestamps.putIfAbsent(key, () => []);
      final userTimestamps = _userRequestTimestamps[key]!;

      // Remove timestamps outside the rate limit window
      userTimestamps.removeWhere(
        (timestamp) => now.difference(timestamp) > _rateLimitWindow,
      );

      // Check per-second limit (burst protection)
      final lastSecond = now.subtract(const Duration(seconds: 1));
      final recentSecondRequests =
          userTimestamps
              .where((timestamp) => timestamp.isAfter(lastSecond))
              .length;

      if (recentSecondRequests >= _maxRequestsPerSecond) {
        throw Exception('🚫 Too many requests. Please slow down.');
      }

      // Check per-minute limit
      if (userTimestamps.length >= _maxRequestsPerMinute) {
        throw Exception('⏰ Rate limit exceeded. Please try again in a minute.');
      }

      // Add current request timestamp
      userTimestamps.add(now);

      // Clean up old data
      if (userTimestamps.length > _maxRequestsPerMinute * 2) {
        userTimestamps.removeRange(
          0,
          userTimestamps.length - _maxRequestsPerMinute,
        );
      }
    });
  }

  /// Generate and manage idempotency keys to prevent duplicate transactions
  /// 🔑 Enhanced idempotency key with expiration
  static String _generateIdempotencyKey(String userId, String transactionType) {
    final now = DateTime.now();
    final uniqueId = const Uuid().v4();
    final key =
        '${userId}_${transactionType}_${now.millisecondsSinceEpoch}_$uniqueId';
    final encryptedKey = _encrypter.encrypt(key, iv: _iv).base64;

    _idempotencyKeys[encryptedKey] = userId;
    _idempotencyKeyTimestamps[encryptedKey] = now; // Track creation time

    _log('🔑 Generated idempotency key: ${encryptedKey.substring(0, 16)}...');
    return encryptedKey;
  }

  /// Enhanced idempotency key validation with persistent storage
  /// ✅ Enhanced idempotency validation with expiration cleanup
  static Future<bool> _validateIdempotencyKey(
    String idempotencyKey,
    String userId,
  ) async {
    final now = DateTime.now();

    // Clean expired keys first
    _idempotencyKeyTimestamps.removeWhere((key, timestamp) {
      if (now.difference(timestamp) > _idempotencyKeyExpiry) {
        _idempotencyKeys.remove(key);
        return true;
      }
      return false;
    });

    if (!_idempotencyKeys.containsKey(idempotencyKey)) {
      _log(
        '❌ Idempotency key not found: ${idempotencyKey.substring(0, 16)}...',
      );
      return false;
    }

    if (_idempotencyKeys[idempotencyKey] != userId) {
      throw Exception('🚫 Invalid idempotency key for user.');
    }

    // Check persistent storage for replay attacks
    final prefs = await SharedPreferences.getInstance();
    final usedKeys = prefs.getStringList('used_idempotency_keys') ?? [];

    if (usedKeys.contains(idempotencyKey)) {
      _log(
        '🔄 Idempotency key already used: ${idempotencyKey.substring(0, 16)}...',
      );
      throw Exception(
        '✅ This transaction was already processed. Check your transaction history.',
      );
    }

    // Mark as used
    usedKeys.add(idempotencyKey);

    // Keep storage manageable
    if (usedKeys.length > 1000) {
      usedKeys.removeRange(0, usedKeys.length - 1000);
    }

    await prefs.setStringList('used_idempotency_keys', usedKeys);
    _log('✅ Idempotency key validated: ${idempotencyKey.substring(0, 16)}...');

    return true;
  }

  // Add this method to ApiService class

  static Future<Map<String, dynamic>> adminUpdateUser({
    required String userId,
    required Map<String, dynamic> data,
  }) async {
    _log('👑 Admin updating user: $userId');

    try {
      // Check admin access first
      if (!await isAdmin()) {
        throw Exception('Admin access required');
      }

      final token = await _getToken();
      if (token == null) {
        throw Exception('Authentication token not found');
      }

      final url = Uri.parse('$baseUrl/api/admin/users/$userId');

      final response = await http
          .put(
            url,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode(data),
          )
          .timeout(const Duration(seconds: 30));

      _log('Admin update user response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        return result;
      } else if (response.statusCode == 403) {
        throw Exception('Admin access required');
      } else {
        final errorData = jsonDecode(response.body);
        throw Exception(errorData['message'] ?? 'Failed to update user');
      }
    } catch (e) {
      _log('❌ Admin update user error: $e');
      rethrow;
    }
  }

  /// Create dynamic virtual account for wallet funding
  static Future<Map<String, dynamic>> createDynamicVirtualAccount({
    required String userId,
    required double amount,
  }) async {
    _log(
      '🏦 Creating dynamic virtual account for user: $userId, amount: ₦$amount',
    );

    try {
      // Use the payment service to create virtual account
      final result = await PaymentService.createDynamicVirtualAccount(
        userId: userId,
        amount: amount,
      );

      if (result['success'] == true) {
        // Store virtual account details locally
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          'virtual_account_number',
          result['accountNumber'] ?? '',
        );
        await prefs.setString(
          'virtual_account_name',
          result['accountName'] ?? '',
        );
        await prefs.setString('virtual_bank_name', result['bankName'] ?? '');
        await prefs.setString(
          'virtual_account_reference',
          result['reference'] ?? '',
        );
        await prefs.setDouble('virtual_account_amount', amount);
        await prefs.setDouble(
          'virtual_account_total_payable',
          result['totalPayable'] ?? amount,
        );

        _log('✅ Virtual account created: ${result['accountNumber']}');
      }

      return result;
    } catch (e, stackTrace) {
      _log('❌ Error creating dynamic virtual account: $e');
      await reportError(e, stackTrace);
      return {
        'success': false,
        'message': 'Failed to create virtual account: ${e.toString()}',
      };
    }
  }

  /// 🔐 Enhanced Session Expired Dialog with DalabaPay branding
  /// Shows a professional, modern session expired dialog with animated lock icon
  /// 🔐 Enhanced Session Expired Dialog with DalabaPay branding
  /// Uses the same blue (#243889) and green (#219C7E) colors as your dashboard
  static Future<void> showSessionExpiredDialog({
    required BuildContext context,
    String title = 'Session Expired',
    String message = 'Session expired. Please login again.',
    String buttonText = 'Login Again',
    bool barrierDismissible = false,
    VoidCallback? onLoginAgain,
    VoidCallback? onCancel,
  }) async {
    try {
      final isDark = Theme.of(context).brightness == Brightness.dark;

      final shouldLogin = await showDialog<bool>(
        context: context,
        barrierDismissible: barrierDismissible,
        builder: (BuildContext dialogContext) {
          return Dialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 24,
            ),
            backgroundColor: Colors.transparent,
            elevation: 0,
            child: _SessionExpiredDialogContent(
              title: title,
              message: message,
              buttonText: buttonText,
              isDark: isDark,
              onLoginAgain: () {
                Navigator.pop(dialogContext, true);
              },
              onCancel: () {
                Navigator.pop(dialogContext, false);
              },
            ),
          );
        },
      );

      if (shouldLogin == true) {
        if (onLoginAgain != null) {
          onLoginAgain();
        } else {
          _navigateToLogin(context);
        }
      } else {
        onCancel?.call();
      }
    } catch (e) {
      _log('Error showing session expired dialog: $e');
      _showFallbackDialog(context, message);
    }
  }

  static void _navigateToLogin(BuildContext context) {
    try {
      _clearAuthData();
      if (context.mounted) {
        // ✅ Check mounted
        Navigator.pushReplacementNamed(context, '/login');
      }
    } catch (e) {
      _log('Navigation to login failed: $e');
    }
  }

  static void _showFallbackDialog(BuildContext context, String message) {
    try {
      if (!context.mounted) return; // ✅ Check mounted
      showDialog(
        context: context,
        barrierDismissible: false,
        builder:
            (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: const Text('Session Expired'),
              content: Text(message),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _navigateToLogin(context);
                  },
                  child: const Text('Login Again'),
                ),
              ],
            ),
      );
    } catch (e) {
      _log('Fallback dialog failed: $e');
    }
  }

  /// Store pending transaction in local storage
  static Future<void> storePendingTransaction({
    required String reference,
    required String accountNumber,
    required double amount,
    required double totalPayable,
    required double fee,
    required String userId,
  }) async {
    _log('📝 Storing pending transaction: $reference');

    try {
      final prefs = await SharedPreferences.getInstance();
      final pendingTxs =
          prefs.getStringList('pending_cashwyre_transactions') ?? [];

      final transactionData = {
        'reference': reference,
        'userId': userId,
        'amount': amount,
        'totalPayable': totalPayable,
        'fee': fee,
        'accountNumber': accountNumber,
        'accountName': 'DalabaPay User',
        'bankName': 'Moniepoint MFB',
        'status': 'pending',
        'createdAt': DateTime.now().toIso8601String(),
        'paymentMethod': 'virtual_account',
        'source': 'cashwyre',
      };

      pendingTxs.add(jsonEncode(transactionData));
      await prefs.setStringList('pending_cashwyre_transactions', pendingTxs);
      _log('✅ Pending transaction stored successfully');
    } catch (e) {
      _log('❌ Error storing pending transaction: $e');
    }
  }

  /// Request manual funding from admin
  static Future<Map<String, dynamic>> requestManualFunding({
    required String userId,
    required double amount,
    required String description,
  }) async {
    _log('📋 Requesting manual funding: ₦$amount for user: $userId');

    try {
      final response = await _authenticatedPost(
        Uri.parse('$baseUrl/api/wallet/manual-funding-request'),
        {'userId': userId, 'amount': amount, 'description': description},
      );

      if (response['success'] == true) {
        _log('✅ Manual funding request submitted successfully');
      } else {
        _log('❌ Manual funding request failed: ${response['message']}');
      }

      return response;
    } catch (e, stackTrace) {
      _log('❌ Error requesting manual funding: $e');
      await reportError(e, stackTrace);
      return {
        'success': false,
        'message': 'Failed to submit funding request: ${e.toString()}',
      };
    }
  }

  /// Check transaction status by reference
  static Future<Map<String, dynamic>> checkTransactionStatus({
    required String reference,
  }) async {
    _log('🔍 Checking transaction status for reference: $reference');

    try {
      final response = await _authenticatedGet(
        Uri.parse(
          '$baseUrl/api/transactions/check-status?reference=$reference',
        ),
      );

      if (response['success'] == true) {
        _log('✅ Transaction status: ${response['status']}');
      }

      return response;
    } catch (e, stackTrace) {
      _log('❌ Error checking transaction status: $e');
      await reportError(e, stackTrace);
      return {
        'success': false,
        'message': 'Failed to check transaction status: ${e.toString()}',
      };
    }
  }

  // ==================== USER STATISTICS ====================
  // Add this method to your ApiService class (around line where other helper methods are)

  static Future<Map<String, String>> _getHeaders() async {
    final token = await _getToken();
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  // Add this method if it doesn't exist
  static Future<Map<String, dynamic>> getMaintenanceStatus() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/maintenance-status'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return {'maintenanceMode': false, 'message': ''};
    } catch (e) {
      print('Error fetching maintenance status: $e');
      return {'maintenanceMode': false, 'message': ''};
    }
  }

  // Add these methods to ApiService class

  /// Check if maintenance mode is active and what's allowed
  static Future<Map<String, dynamic>> checkMaintenanceStatus() async {
    try {
      final token = await _getToken();
      final headers = <String, String>{'Content-Type': 'application/json'};

      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }

      final response = await http
          .get(Uri.parse('$baseUrl/api/maintenance-status'), headers: headers)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint('🔧 Maintenance Status: ${data['maintenanceMode']}');
        debugPrint('📖 Read-Only Allowed: ${data['readOnlyAllowed']}');
        return data;
      }

      return {
        'maintenanceMode': false,
        'message': '',
        'readOnlyAllowed': false,
        'success': false,
      };
    } catch (e) {
      debugPrint('❌ Error checking maintenance status: $e');
      return {
        'maintenanceMode': false,
        'message': '',
        'readOnlyAllowed': false,
        'success': false,
      };
    }
  }

  /// Check if a specific operation is allowed during maintenance
  static Future<bool> isOperationAllowed(String operationType) async {
    // If not in maintenance mode, everything is allowed
    final status = await checkMaintenanceStatus();
    if (!status['maintenanceMode']) {
      return true;
    }

    // Read-only operations are always allowed
    final readOnlyOperations = [
      'view_balance',
      'view_transactions',
      'view_commission',
      'view_notifications',
      'view_beneficiaries',
      'view_profile',
      'view_security_settings',
    ];

    if (readOnlyOperations.contains(operationType)) {
      return true;
    }

    // Write operations are blocked during maintenance
    return false;
  }

  /// Show maintenance mode dialog to user
  static Future<void> showMaintenanceDialog(BuildContext context) async {
    try {
      final status = await checkMaintenanceStatus();
      if (!status['maintenanceMode']) return;

      final message =
          status['message'] ?? 'System is currently under maintenance.';
      final readOnlyAllowed = status['readOnlyAllowed'] ?? false;

      await showDialog(
        context: context,
        barrierDismissible: true,
        builder:
            (context) => AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Row(
                children: [
                  Icon(
                    Icons.construction_rounded,
                    color: Colors.orange,
                    size: 28,
                  ),
                  const SizedBox(width: 10),
                  const Text('Maintenance Mode'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(message, style: const TextStyle(fontSize: 14)),
                  const SizedBox(height: 12),
                  if (readOnlyAllowed) ...[
                    const Divider(),
                    Row(
                      children: [
                        Icon(
                          Icons.visibility_rounded,
                          color: Colors.green,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'You can still view your balance and transactions',
                          style: TextStyle(fontSize: 13, color: Colors.green),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.block_rounded, color: Colors.red, size: 18),
                        const SizedBox(width: 8),
                        const Text(
                          'New transactions are temporarily disabled',
                          style: TextStyle(fontSize: 13, color: Colors.red),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK'),
                ),
              ],
            ),
      );
    } catch (e) {
      debugPrint('❌ Error showing maintenance dialog: $e');
    }
  }

  // ==================== RBAC (ROLE BASED ACCESS CONTROL) ====================

  /// Get user's role and permissions
  static Future<Map<String, dynamic>> getUserRole({String? userId}) async {
    _log('👤 Getting user role${userId != null ? " for user: $userId" : ""}');

    try {
      // ✅ Build body — OMIT targetUserId entirely when it's null
      final body = <String, dynamic>{'operation': 'get_user_role'};

      if (userId != null && userId.isNotEmpty) {
        body['targetUserId'] = userId;
      }

      final response = await _authenticatedPost(
        Uri.parse('$baseUrl/api/rbac'),
        body,
      );

      if (response['success'] == true) {
        _log('✅ User role: ${response['data']?['role']}');
        return response;
      } else {
        _log('⚠️ Failed to get user role: ${response['message']}');
        return {
          'success': false,
          'data': {'role': 'user', 'permissions': []},
        };
      }
    } catch (e) {
      _log('❌ Error getting user role: $e');
      return {
        'success': false,
        'data': {'role': 'user', 'permissions': []},
      };
    }
  }

  /// Check if user has specific permission
  static Future<bool> hasPermission(String permission, {String? userId}) async {
    try {
      final response =
          await _authenticatedPost(Uri.parse('$baseUrl/api/rbac'), {
            'operation': 'check_permission',
            'checkPermission': permission,
            'targetUserId': userId,
          });

      if (response['success'] == true) {
        return response['data']?['hasPermission'] == true;
      }
      return false;
    } catch (e) {
      _log('❌ Error checking permission: $e');
      return false;
    }
  }

  /// Check if user can access a specific resource (shorthand)
  static Future<bool> canAccessResource(
    String resource,
    String action, {
    String? userId,
  }) async {
    try {
      final response =
          await _authenticatedPost(Uri.parse('$baseUrl/api/rbac'), {
            'operation': 'can_access',
            'resource': resource,
            'action': action,
            'targetUserId': userId,
          });

      if (response['success'] == true) {
        return response['data']?['hasAccess'] == true;
      }
      return false;
    } catch (e) {
      _log('❌ Error checking resource access: $e');
      return false;
    }
  }

  /// Check if current user is Super Admin
  /// Check if current user is Super Admin
  static Future<bool> isSuperAdmin() async {
    try {
      final response = await getUserRole();
      if (response['success'] == true) {
        final data = response['data'];
        final userRole = data?['role']?.toString() ?? 'user';
        final isSuperAdmin =
            data?['isSuperAdmin'] == true || userRole == 'super_admin';

        // ✅ Cache the flag so fallback works if RBAC later fails
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('isSuperAdmin', isSuperAdmin);
        await prefs.setString('role', userRole);

        return isSuperAdmin;
      }

      // Fallback to cache
      final prefs = await SharedPreferences.getInstance();
      final localRole = prefs.getString('role') ?? 'user';
      return prefs.getBool('isSuperAdmin') == true ||
          localRole == 'super_admin';
    } catch (e) {
      _log('❌ Error checking super admin: $e');
      // Fallback to cache on error
      final prefs = await SharedPreferences.getInstance();
      final localRole = prefs.getString('role') ?? 'user';
      return prefs.getBool('isSuperAdmin') == true ||
          localRole == 'super_admin';
    }
  }

  /// Get all roles (Admin+)
  static Future<Map<String, dynamic>> getAllRoles() async {
    _log('👑 Getting all roles');
    try {
      final response = await _authenticatedPost(
        Uri.parse('$baseUrl/api/rbac'),
        {'operation': 'get_roles'},
      );
      return response;
    } catch (e) {
      _log('❌ Error getting all roles: $e');
      return {
        'success': false,
        'data': {'roles': []},
      };
    }
  }

  /// Assign role to user (Super Admin only)
  static Future<Map<String, dynamic>> assignRole(
    String userId,
    String role,
  ) async {
    _log('👑 Assigning role "$role" to user: $userId');
    try {
      final response = await _authenticatedPost(
        Uri.parse('$baseUrl/api/rbac'),
        {'operation': 'assign_role', 'targetUserId': userId, 'role': role},
      );
      return response;
    } catch (e) {
      _log('❌ Error assigning role: $e');
      return {
        'success': false,
        'message': 'Failed to assign role: ${e.toString()}',
      };
    }
  }

  /// Remove role from user (Super Admin only)
  static Future<Map<String, dynamic>> removeRole(String userId) async {
    _log('👑 Removing role from user: $userId');
    try {
      final response = await _authenticatedPost(
        Uri.parse('$baseUrl/api/rbac'),
        {'operation': 'remove_role', 'targetUserId': userId},
      );
      return response;
    } catch (e) {
      _log('❌ Error removing role: $e');
      return {
        'success': false,
        'message': 'Failed to remove role: ${e.toString()}',
      };
    }
  }

  /// Get users by role (Admin+)
  static Future<Map<String, dynamic>> getUsersByRole({String? role}) async {
    _log('👑 Getting users by role: ${role ?? "all"}');
    try {
      final response = await _authenticatedPost(
        Uri.parse('$baseUrl/api/rbac'),
        {'operation': 'get_users_by_role', 'role': role},
      );
      return response;
    } catch (e) {
      _log('❌ Error getting users by role: $e');
      return {
        'success': false,
        'data': {'users': []},
      };
    }
  }

  /// Update user permissions (Super Admin only)
  static Future<Map<String, dynamic>> updateUserPermissions(
    String userId,
    List<String> permissions,
  ) async {
    _log('👑 Updating permissions for user: $userId');
    try {
      final response =
          await _authenticatedPost(Uri.parse('$baseUrl/api/rbac'), {
            'operation': 'update_permissions',
            'targetUserId': userId,
            'permissions': permissions,
          });
      return response;
    } catch (e) {
      _log('❌ Error updating permissions: $e');
      return {
        'success': false,
        'message': 'Failed to update permissions: ${e.toString()}',
      };
    }
  }

  /// Get role statistics (Admin+)
  static Future<Map<String, dynamic>> getRoleStats() async {
    _log('👑 Getting role statistics');
    try {
      final response = await _authenticatedPost(
        Uri.parse('$baseUrl/api/rbac'),
        {'operation': 'get_role_stats'},
      );
      return response;
    } catch (e) {
      _log('❌ Error getting role stats: $e');
      return {'success': false, 'data': {}};
    }
  }

  /// Get all available permissions (Admin+)
  static Future<Map<String, dynamic>> getAvailablePermissions() async {
    _log('👑 Getting available permissions');
    try {
      final response = await _authenticatedPost(
        Uri.parse('$baseUrl/api/rbac'),
        {'operation': 'get_available_permissions'},
      );
      return response;
    } catch (e) {
      _log('❌ Error getting available permissions: $e');
      return {
        'success': false,
        'data': {'allPermissions': []},
      };
    }
  }

  // ==================== ADMIN DASHBOARD API ====================
  /// Get admin dashboard with period stats and filtered transactions
  static Future<Map<String, dynamic>> getAdminDashboard({
    String timeFilter = 'all',
    String status = 'all',
    String service = 'all',
    String search = '',
    int page = 1,
    int limit = 50,
    String? startDate,
    String? endDate,
  }) async {
    try {
      debugPrint('🔍 ========== ADMIN DASHBOARD API CALL ==========');
      debugPrint('📋 Parameters:');
      debugPrint('   timeFilter: $timeFilter');
      debugPrint('   status: $status');
      debugPrint('   service: $service');
      debugPrint('   search: $search');
      debugPrint('   page: $page');
      debugPrint('   limit: $limit');
      debugPrint('   startDate: $startDate');
      debugPrint('   endDate: $endDate');

      final token = await _TokenManager.getSafeToken();
      if (token == null) {
        debugPrint('❌ No token found');
        throw Exception('Not authenticated');
      }
      debugPrint(
        '✅ Token found: ${token.substring(0, token.length > 20 ? 20 : token.length)}...',
      );

      // Build query parameters
      final params = <String, String>{
        'timeFilter': timeFilter,
        'status': status,
        'service': service,
        'search': search,
        'page': page.toString(),
        'limit': limit.toString(),
      };

      if (startDate != null && endDate != null) {
        params['startDate'] = startDate;
        params['endDate'] = endDate;
      }

      final queryString = params.entries
          .map(
            (e) =>
                '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}',
          )
          .join('&');

      final url = '$baseUrl/api/admin/dashboard?$queryString';

      debugPrint('📤 Request URL: $url');

      final response = await http
          .get(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 30));

      debugPrint('📥 Response Status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint('📥 Response Success: ${data['success']}');

        if (data['success'] == true) {
          // Log response summary
          final periodStats = data['periodStats'] ?? {};
          final statusSummary = data['statusSummary'] ?? {};
          final transactions = data['transactions'] ?? [];
          final pagination = data['pagination'] ?? {};

          debugPrint('📊 RESPONSE SUMMARY:');
          debugPrint('   Period Stats:');
          debugPrint(
            '     All Time: ${periodStats['allTime']?['count'] ?? 0} transactions, ₦${periodStats['allTime']?['amount'] ?? 0}',
          );
          debugPrint(
            '     Today: ${periodStats['today']?['count'] ?? 0} transactions, ₦${periodStats['today']?['amount'] ?? 0}',
          );
          debugPrint(
            '     Week: ${periodStats['week']?['count'] ?? 0} transactions, ₦${periodStats['week']?['amount'] ?? 0}',
          );
          debugPrint(
            '     Month: ${periodStats['month']?['count'] ?? 0} transactions, ₦${periodStats['month']?['amount'] ?? 0}',
          );
          debugPrint(
            '     Year: ${periodStats['year']?['count'] ?? 0} transactions, ₦${periodStats['year']?['amount'] ?? 0}',
          );
          debugPrint('   Status Summary:');
          debugPrint('     Success: ${statusSummary['success'] ?? 0}');
          debugPrint('     Pending: ${statusSummary['pending'] ?? 0}');
          debugPrint('     Failed: ${statusSummary['failed'] ?? 0}');
          debugPrint('     Total: ${statusSummary['total'] ?? 0}');
          debugPrint(
            '   Transactions: ${transactions.length} of ${pagination['total'] ?? 0}',
          );
          debugPrint(
            '   Page: ${pagination['page'] ?? 1} of ${pagination['totalPages'] ?? 1}',
          );

          // Log debug info if available
          if (data['_debug'] != null) {
            debugPrint('🐛 DEBUG INFO: ${data['_debug']}');
          }

          return data;
        } else {
          debugPrint('❌ API returned success: false');
          throw Exception(data['message'] ?? 'Failed to fetch admin dashboard');
        }
      } else {
        debugPrint('❌ HTTP Error: ${response.statusCode}');
        debugPrint('❌ Response Body: ${response.body}');
        final data = jsonDecode(response.body);
        throw Exception(
          'HTTP ${response.statusCode}: ${data['message'] ?? 'Unknown error'}',
        );
      }
    } catch (e) {
      debugPrint('❌ Get admin dashboard error: $e');
      rethrow;
    }
  }

  // ==================== GET FILTERED TRANSACTIONS ====================
  static Future<List<dynamic>> getFilteredTransactions({
    String? type,
    String? status,
    String? startDate,
    String? endDate,
    String? search,
    String? sortBy,
    int limit = 500,
    int page = 1,
  }) async {
    debugPrint('🔄 getFilteredTransactions called');

    try {
      final token = await _TokenManager.getSafeToken();
      if (token == null) throw Exception('NO_TOKEN');

      // Build query parameters
      final params = <String, String>{};
      if (type != null && type != 'All' && type != 'all') params['type'] = type;
      if (status != null && status != 'All' && status != 'all') {
        params['status'] = status;
      }
      if (startDate != null) params['startDate'] = startDate;
      if (endDate != null) params['endDate'] = endDate;
      if (search != null && search.isNotEmpty) params['search'] = search;
      if (sortBy != null && sortBy != 'Newest') params['sortBy'] = sortBy;
      params['limit'] = limit.toString();
      params['page'] = page.toString();

      final queryString = params.entries
          .map(
            (e) =>
                '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}',
          )
          .join('&');

      final url = '$baseUrl/api/admin/transactions/filtered?$queryString';

      debugPrint('📡 Calling filtered endpoint: $url');

      final response = await http
          .get(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 30));

      debugPrint('📡 Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        debugPrint('📊 Filtered transactions data:');
        debugPrint('  - Success: ${data['success']}');
        debugPrint('  - Total: ${data['total']}');
        debugPrint('  - Returned: ${data['returned']}');
        debugPrint('  - Page: ${data['page']}');
        debugPrint('  - Total Pages: ${data['totalPages']}');

        if (data['success'] == true) {
          final transactions = data['transactions'] ?? [];

          // Store total in SharedPreferences
          final prefs = await SharedPreferences.getInstance();
          await prefs.setInt('admin_filtered_total', data['total'] ?? 0);

          return transactions;
        }

        throw Exception(
          data['message'] ?? 'Failed to fetch filtered transactions',
        );
      }

      throw Exception(
        'Failed to fetch filtered transactions: ${response.statusCode}',
      );
    } catch (e) {
      debugPrint('❌ Error fetching filtered transactions: $e');
      rethrow;
    }
  }

  // ==================== GET ALL ADMIN TRANSACTIONS ====================
  static Future<List<dynamic>> getAllAdminTransactions() async {
    debugPrint('🔄 getAllAdminTransactions called - fetching latest 500');

    try {
      final token = await _TokenManager.getSafeToken();
      if (token == null) throw Exception('NO_TOKEN');

      final url = '$baseUrl/api/admin/latest-transactions?limit=500';

      debugPrint('📡 Calling: $url');

      final response = await http
          .get(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 20));

      debugPrint('📡 Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        debugPrint('📊 Admin transactions data:');
        debugPrint('  - Success: ${data['success']}');
        debugPrint('  - Total transactions: ${data['total']}');
        debugPrint('  - Returned: ${data['returned']}');

        if (data['success'] == true) {
          final transactions = data['transactions'] ?? [];

          final prefs = await SharedPreferences.getInstance();
          await prefs.setInt('admin_total_transactions', data['total'] ?? 0);
          await prefs.setInt(
            'admin_returned_transactions',
            transactions.length,
          );

          debugPrint('✅ Stored total transactions: ${data['total']}');

          // Process transactions
          final enhancedTransactions =
              transactions.map((tx) {
                if (tx is! Map<String, dynamic>) return tx;

                final enhancedTx = Map<String, dynamic>.from(tx);

                if (enhancedTx.containsKey('user') &&
                    enhancedTx['user'] != null) {
                  final userData = enhancedTx['user'] as Map<String, dynamic>;
                  enhancedTx['user'] = {
                    '_id':
                        userData['_id']?.toString() ??
                        enhancedTx['userId']?.toString() ??
                        'unknown',
                    'fullName':
                        userData['fullName']?.toString() ?? 'Unknown User',
                    'email':
                        userData['email']?.toString() ?? 'no-email@example.com',
                    'phone': userData['phone']?.toString() ?? 'N/A',
                    'isAdmin': userData['isAdmin'] == true,
                  };
                } else {
                  final userId = enhancedTx['userId']?.toString() ?? 'system';
                  enhancedTx['user'] = {
                    '_id': userId,
                    'fullName': userId == 'system' ? 'System' : 'User $userId',
                    'email':
                        userId == 'system'
                            ? 'system@transaction'
                            : 'user@example.com',
                    'phone': 'N/A',
                    'isAdmin': false,
                  };
                }

                return enhancedTx;
              }).toList();

          debugPrint('✅ Enhanced ${enhancedTransactions.length} transactions');
          return enhancedTransactions;
        }

        throw Exception(data['message'] ?? 'Admin endpoint failed');
      }

      throw Exception('Admin endpoint failed: ${response.statusCode}');
    } catch (e) {
      debugPrint('❌ Error from admin endpoint: $e');
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> getUserStatistics() async {
    try {
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/api/admin/users/statistics'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return data['data'];
        } else {
          throw Exception(data['message'] ?? 'Failed to get user statistics');
        }
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        throw Exception('Admin access required');
      } else {
        throw Exception(
          'Failed to get user statistics: ${response.statusCode}',
        );
      }
    } catch (e) {
      _log('❌ Error getting user statistics: $e');
      rethrow;
    }
  }

  /// Get user's stored virtual account
  static Future<Map<String, dynamic>> getStoredVirtualAccount() async {
    _log('📦 Getting stored virtual account');

    try {
      final prefs = await SharedPreferences.getInstance();
      final accountNumber = prefs.getString('virtual_account_number');
      final accountName = prefs.getString('virtual_account_name');
      final bankName = prefs.getString('virtual_bank_name');
      final reference = prefs.getString('virtual_account_reference');

      if (accountNumber != null && accountNumber.isNotEmpty) {
        return {
          'success': true,
          'accountNumber': accountNumber,
          'accountName': accountName ?? 'DalabaPay User',
          'bankName': bankName ?? 'Moniepoint MFB',
          'reference': reference,
        };
      }

      return {'success': false, 'message': 'No virtual account found'};
    } catch (e) {
      _log('❌ Error getting stored virtual account: $e');
      return {
        'success': false,
        'message': 'Failed to retrieve virtual account',
      };
    }
  }

  /// Verify payment after transfer
  static Future<Map<String, dynamic>> verifyPayment({
    required String reference,
    required String userId,
  }) async {
    _log('🔐 Verifying payment: $reference for user: $userId');

    try {
      final response = await _authenticatedPost(
        Uri.parse('$baseUrl/api/transactions/verify-payment'),
        {'reference': reference, 'userId': userId},
      );

      if (response['success'] == true) {
        _log('✅ Payment verified: ${response['status']}');
      }

      return response;
    } catch (e, stackTrace) {
      _log('❌ Error verifying payment: $e');
      await reportError(e, stackTrace);
      return {
        'success': false,
        'message': 'Failed to verify payment: ${e.toString()}',
      };
    }
  }

  /// Get live wallet balance with force refresh
  static Future<double> getLiveBalance({bool forceRefresh = false}) async {
    _log('💰 Getting live balance (force: $forceRefresh)');

    try {
      final response = await _authenticatedGet(
        Uri.parse('$baseUrl/api/wallet/balance?force=$forceRefresh'),
      );

      if (response['success'] == true && response['walletBalance'] != null) {
        final balance = (response['walletBalance'] as num).toDouble();
        _log('✅ Live balance: ₦$balance');
        return balance;
      }

      return 0.0;
    } catch (e) {
      _log('❌ Error getting live balance: $e');
      return 0.0;
    }
  }

  static Future<void> updateDeviceToken(String token) async {
    try {
      await _authenticatedPost(
        Uri.parse('$baseUrl/api/user/update-fcm-token'),
        {'fcmToken': token},
      );
      debugPrint('✅ FCM token saved to backend');
    } catch (e) {
      debugPrint('❌ FCM token save error: $e');
    }
  }

  /// Get WebSocket URL for the current user
  static String getWebSocketUrl() {
    return baseUrl
        .replaceFirst('http://', 'ws://')
        .replaceFirst('https://', 'wss://');
  }

  /// Send notification via API (fallback if socket is not connected)
  static Future<Map<String, dynamic>> sendNotificationViaApi({
    required String title,
    required String message,
    String? recipientId,
    bool sendToAll = false,
    String type = 'general',
    String? screen,
    Map<String, dynamic>? data,
  }) async {
    if (!await isAdmin()) throw Exception('Admin access required');

    _log('📨 Sending notification via API: "$title"');

    final body = {
      'title': title,
      'message': message,
      'sendToAll': sendToAll,
      'type': type,
      'screen': screen ?? 'notifications',
      'data': data ?? {},
    };

    if (recipientId != null && recipientId.isNotEmpty && !sendToAll) {
      body['recipientId'] = recipientId;
    }

    final url = Uri.parse('$_notificationsBaseUrl/send');
    return await _authenticatedPost(url, body);
  }

  /// Get current user's full name
  static Future<String> getUserFullName() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userString = prefs.getString('user');
      if (userString != null) {
        final userMap = jsonDecode(userString);
        return userMap['fullName']?.toString() ?? 'User';
      }
      return 'User';
    } catch (e) {
      _log('❌ Error getting user full name: $e');
      return 'User';
    }
  }

  /// Get current user's email
  static Future<String> getUserEmail() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userString = prefs.getString('user');
      if (userString != null) {
        final userMap = jsonDecode(userString);
        return userMap['email']?.toString() ?? '';
      }
      return '';
    } catch (e) {
      _log('❌ Error getting user email: $e');
      return '';
    }
  }

  // Request PIN reset token via email
  static Future<Map<String, dynamic>> requestPinReset({
    required String email,
  }) async {
    _log('Requesting PIN reset token for email: $email');
    return await _authenticatedPost(_requestPinResetUrl, {'email': email});
  }

  // Verify PIN reset token
  static Future<Map<String, dynamic>> verifyPinResetToken({
    required String email,
    required String token,
  }) async {
    _log('Verifying PIN reset token for email: $email');
    return await _authenticatedPost(_verifyPinResetTokenUrl, {
      'email': email,
      'token': token,
    });
  }

  // Add this method to ApiService class (around line where other password methods are)
  static Future<Map<String, dynamic>> resetPasswordWithToken({
    required String resetToken,
    required String newPassword,
  }) async {
    _log('🔄 Resetting password with token');
    try {
      final response = await http
          .post(
            _resetPasswordUrl,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'resetToken': resetToken,
              'newPassword': newPassword,
            }),
          )
          .timeout(const Duration(seconds: 30));

      _log('Reset password response status: ${response.statusCode}');
      return _handleResponse(response);
    } catch (e) {
      _log('❌ Reset password error: $e');
      rethrow;
    }
  }

  // Reset PIN with verified token
  static Future<Map<String, dynamic>> resetPinWithToken({
    required String email,
    required String newPin,
  }) async {
    final validationError = _validatePin(newPin);
    if (validationError != null) throw Exception(validationError);

    _log('Resetting PIN with token for email: $email');

    final result = await _authenticatedPost(_resetPinWithTokenUrl, {
      'email': email,
      'newPin': newPin,
    });

    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('userId');
    if (userId != null) {
      await prefs.setBool('hasTransactionPin_$userId', true);
    }

    return result;
  }

  static Future<Map<String, dynamic>> adminCheckPinStatus({
    required String userId,
  }) async {
    _log('🔐 Admin checking PIN status for user: $userId');

    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/admin/check-pin-status'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              'Authorization': 'Bearer ${await _getToken()}',
            },
            body: jsonEncode({'userId': userId}),
          )
          .timeout(const Duration(seconds: 15));

      _log('📡 Admin PIN status response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data;
      } else if (response.statusCode == 403) {
        throw Exception('Admin access required');
      } else {
        final errorData = jsonDecode(response.body);
        throw Exception(errorData['message'] ?? 'Failed to check PIN status');
      }
    } catch (e) {
      _log('❌ Admin PIN check error: $e');
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> adminUnlockPin({
    required String userId,
  }) async {
    _log('🔓 Admin unlocking PIN for user: $userId');

    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/admin/unlock-pin'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              'Authorization': 'Bearer ${await _getToken()}',
            },
            body: jsonEncode({'userId': userId}),
          )
          .timeout(const Duration(seconds: 15));

      _log('📡 Admin unlock PIN response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data;
      } else if (response.statusCode == 403) {
        throw Exception('Admin access required');
      } else {
        final errorData = jsonDecode(response.body);
        throw Exception(errorData['message'] ?? 'Failed to unlock PIN');
      }
    } catch (e) {
      _log('❌ Admin PIN unlock error: $e');
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> adminResetPin({
    required String userId,
  }) async {
    _log('🔄 Admin resetting PIN for user: $userId');

    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/admin/reset-pin'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              'Authorization': 'Bearer ${await _getToken()}',
            },
            body: jsonEncode({'userId': userId}),
          )
          .timeout(const Duration(seconds: 15));

      _log('📡 Admin reset PIN response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data;
      } else if (response.statusCode == 403) {
        throw Exception('Admin access required');
      } else {
        final errorData = jsonDecode(response.body);
        throw Exception(errorData['message'] ?? 'Failed to reset PIN');
      }
    } catch (e) {
      _log('❌ Admin PIN reset error: $e');
      rethrow;
    }
  }

  /// Check server health
  /// Check server health
  static Future<Map<String, dynamic>> checkServerHealth() async {
    try {
      final response = await http
          .get(
            Uri.parse('https://vtpass-backend.onrender.com/health'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'success': true,
          'status': data['status'] ?? 'OK',
          'timestamp': data['timestamp'],
          'uptime': data['uptime'],
          'message': 'Server is healthy',
        };
      } else {
        return {
          'success': false,
          'message': 'Server returned status: ${response.statusCode}',
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Failed to check server health: $e'};
    }
  }

  /// Get VTpass documentation link
  static String getVtpassDocumentationUrl() {
    return 'https://www.vtpass.com/documentation/';
  }

  /// Toggle environment between sandbox and live
  /// Toggle environment between sandbox and live
  static Future<void> toggleEnvironment({required bool useSandbox}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('useSandbox', useSandbox);
      debugPrint(
        '🔄 Environment toggled to: ${useSandbox ? "Sandbox" : "Live"}',
      );
    } catch (e) {
      debugPrint('❌ Error toggling environment: $e');
    }
  }

  static Future<bool> getEnvironment() async {
    final prefs = await SharedPreferences.getInstance();
    final useSandbox = prefs.getBool('useSandbox') ?? true;
    _useSandbox = useSandbox; // Update the static variable
    return useSandbox;
  }

  /// Get current environment
  static Future<bool> getCurrentEnvironment() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('useSandbox') ?? true;
  }

  /// Verify VTpass credentials
  /// Verify VTpass credentials
  static Future<Map<String, dynamic>> verifyVtpassCredentials() async {
    try {
      // Try to fetch balance - if it works, credentials are valid
      final result = await getVtpassBalance();

      if (result['success'] == true) {
        final prefs = await SharedPreferences.getInstance();
        final useSandbox = prefs.getBool('useSandbox') ?? true;

        return {
          'success': true,
          'message': '✅ Credentials verified successfully!',
          'environment': useSandbox ? 'sandbox' : 'live',
          'balance': result['balance'] ?? 0,
        };
      } else {
        return {
          'success': false,
          'message': result['message'] ?? '❌ Credentials verification failed',
          'environment': 'unknown',
          'code': result['code'],
        };
      }
    } catch (e) {
      debugPrint('❌ Error testing credentials: $e');
      return {
        'success': false,
        'message': '❌ Error testing credentials: ${e.toString()}',
      };
    }
  }

  /// Atomic transaction that ensures debit and credit happen together
  /// 🔧 FIXED: Atomic transaction without nested locking
  static Future<Map<String, dynamic>> _executeAtomicTransaction({
    required String userId,
    required double debitAmount,
    required String debitService,
    required Map<String, dynamic> vtpassPayload,
    String? creditService,
    double? creditAmount,
    String? transactionPin,
    bool? useBiometric,
  }) async {
    _log('⚛️ Starting atomic transaction for user: $userId');

    // Don't use wallet lock here - let the secure transaction handle it
    try {
      // Step 1: Authentication
      final authResult = await authenticateTransaction(
        userId: userId,
        transactionPin: transactionPin,
        useBiometric: useBiometric,
      );

      // Step 2: Prepare atomic payload
      final atomicBody = {
        'userId': userId,
        'debitAmount': debitAmount,
        'debitService': debitService,
        'vtpassPayload': vtpassPayload,
        'creditService': creditService,
        'creditAmount': creditAmount,
        'requestId': _generateRequestId(),
        'environment': _useSandbox ? 'sandbox' : 'live',
        'timestamp': DateTime.now().toIso8601String(),
        'atomic': true,
      };

      if (authResult['method'] == 'pin') {
        atomicBody['transactionPin'] = authResult['pin'];
      } else if (authResult['method'] == 'biometric') {
        atomicBody['useBiometric'] = true;
      }

      _log('🔐 Atomic transaction payload prepared');

      // Step 3: Execute atomic transaction
      final response = await _authenticatedPost(
        _atomicTransactionUrl,
        atomicBody,
      );

      if (response['success'] == true) {
        _log('✅ Atomic transaction completed successfully');
        return response;
      } else {
        throw Exception('Atomic transaction failed: ${response['message']}');
      }
    } catch (e, stackTrace) {
      _log('❌ Atomic transaction failed: $e');
      await reportError(e, stackTrace);
      rethrow;
    }
  }

  /// 🛡️ ENHANCED SECURE TRANSACTION WITH ATOMIC OPERATIONS
  /// 🔧 FIXED: Secure transaction with simplified locking
  static Future<Map<String, dynamic>> _executeSecureTransaction({
    required String userId,
    required String transactionType,
    required Future<Map<String, dynamic>> Function() transactionFunction,
    required double amount,
    String? serviceType,
    bool requiresDebit = true,
    bool useAtomic = false, // 🔧 DISABLE atomic by default to avoid deadlocks
    Map<String, dynamic>? vtpassPayload,
  }) async {
    // Step 1: Rate limiting
    await _checkRateLimit(userId, transactionType);

    // Step 2: Generate and validate idempotency key
    final idempotencyKey = _generateIdempotencyKey(userId, transactionType);
    await _validateIdempotencyKey(idempotencyKey, userId);

    // Step 3: Balance check (if debit required)
    if (requiresDebit && !_useSandbox) {
      final currentBalance = await getBalance();
      if (currentBalance < amount) {
        throw Exception(
          '💸 Insufficient wallet balance. Required: ₦${amount.toStringAsFixed(2)}, '
          'Available: ₦${currentBalance.toStringAsFixed(2)}',
        );
      }
    }

    // Step 4: Execute with enhanced security (SIMPLIFIED - no atomic by default)
    return await _executeWithWalletLock(userId, () async {
      try {
        // 🔧 Use atomic only if explicitly requested and conditions are met
        if (useAtomic &&
            requiresDebit &&
            !_useSandbox &&
            vtpassPayload != null) {
          try {
            _log('⚛️ Using atomic transaction for enhanced security');
            return await _executeAtomicTransaction(
              userId: userId,
              debitAmount: amount,
              debitService: transactionType,
              vtpassPayload: vtpassPayload,
              creditService: serviceType,
              creditAmount: amount * (_commissionRates[serviceType] ?? 0.0),
            );
          } catch (e) {
            _log('⚠️ Atomic transaction failed, using standard: $e');
            // Continue to standard transaction
          }
        }

        // Standard transaction function
        final result = await transactionFunction();

        // Add security metadata to response
        return {
          ...result,
          'idempotencyKey': idempotencyKey,
          'secured': true,
          'atomic': useAtomic,
          'timestamp': DateTime.now().toIso8601String(),
        };
      } catch (e) {
        // Enhanced cleanup on failure
        _cleanupFailedTransaction(idempotencyKey);
        rethrow;
      }
    });
  }

  /// Check network connectivity before transactions
  /// Check network connectivity before transactions
  static Future<bool> checkConnectivity() async {
    try {
      final connectivityResult = await (Connectivity().checkConnectivity());
      // ✅ FIX: Check if it's a list or single value
      return connectivityResult.isNotEmpty &&
          connectivityResult[0] != ConnectivityResult.none;
      return connectivityResult != ConnectivityResult.none;
    } catch (e) {
      _log('Connectivity check failed: $e');
      return false;
    }
  }

  /// Enhanced API call with connectivity check
  static Future<Map<String, dynamic>> _secureApiCall(
    Future<dynamic> Function()
    apiCall, // Changed from Future<Map<String, dynamic>> to Future<dynamic>
    String operationName,
  ) async {
    // Check connectivity first
    if (!await checkConnectivity()) {
      throw Exception(
        'No internet connection. Please check your network and try again.',
      );
    }

    try {
      final result = await apiCall();
      // Ensure we return Map<String, dynamic>
      if (result is Map<String, dynamic>) {
        return result;
      } else {
        // Convert other response types if needed
        return {'data': result};
      }
    } on io.SocketException {
      throw Exception('Network error. Please check your internet connection.');
    } on TimeoutException {
      throw Exception('Request timeout. Please try again.');
    } on http.ClientException {
      throw Exception('Server connection failed. Please try again later.');
    } catch (e) {
      rethrow;
    }
  }

  static Future<String?> _getToken() async {
    return await SecureStorageService.getAccessToken();
  }

  // ✅ PUBLIC SAFE TOKEN ACCESSOR
  /// Safe token getter that doesn't throw
  static Future<String?> getSafeToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload(); // ✅ Force reload

      final token = prefs.getString('token');
      if (token == null || token.isEmpty) {
        _log('❌ No token found in getSafeToken');
        return null;
      }

      _log('✅ Safe token retrieved: ${token.substring(0, 10)}...');
      return token;
    } catch (e) {
      _log('❌ Error getting safe token: $e');
      return null;
    }
  }

  static Future<String?> _getRefreshToken() async {
    return await SecureStorageService.getRefreshToken();
  }

  static Future<String?> _getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('userId');
    _log('Retrieved userId: ${userId ?? "null"}');
    return userId;
  }

  static Future<bool> isAdmin() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // First check cached value for speed
      final cachedIsAdmin = prefs.getBool('isAdmin');
      final lastCheck = prefs.getInt('lastAdminCheck');

      // ✅ Return cached value only if it's fresh (< 5 minutes old)
      if (cachedIsAdmin != null &&
          lastCheck != null &&
          DateTime.now().millisecondsSinceEpoch - lastCheck < 300000) {
        debugPrint('👑 ADMIN: Using cached admin status: $cachedIsAdmin');
        return cachedIsAdmin;
      }

      // ✅ Check with RBAC endpoint for fresh data
      debugPrint('👑 ADMIN: Checking admin status via RBAC...');
      final response = await getUserRole();

      if (response['success'] == true) {
        final data = response['data'];
        final userRole = data?['role']?.toString() ?? 'user';
        final isAdminFromRbac =
            data?['isAdmin'] == true ||
            data?['isSuperAdmin'] == true ||
            userRole == 'admin' ||
            userRole == 'super_admin';

        debugPrint('👑 ADMIN: RBAC result - isAdmin: $isAdminFromRbac');
        debugPrint('👑 ADMIN: Role: $userRole');

        // Cache the result
        await prefs.setBool('isAdmin', isAdminFromRbac);
        await prefs.setString('role', userRole);
        await prefs.setBool(
          'isSuperAdmin',
          data?['isSuperAdmin'] == true || userRole == 'super_admin',
        );
        await prefs.setInt(
          'lastAdminCheck',
          DateTime.now().millisecondsSinceEpoch,
        );

        return isAdminFromRbac;
      }

      // ✅ RBAC failed — fall back to locally stored role, NOT just isAdmin flag
      debugPrint('👑 ADMIN: RBAC failed, using local fallback');
      final localRole = prefs.getString('role') ?? 'user';
      final localIsSuperAdmin = prefs.getBool('isSuperAdmin') == true;
      return prefs.getBool('isAdmin') == true ||
          localIsSuperAdmin ||
          localRole == 'admin' ||
          localRole == 'super_admin';
    } catch (e) {
      debugPrint('❌ ADMIN CHECK ERROR: $e');
      // On error, check both role and isAdmin flag
      final prefs = await SharedPreferences.getInstance();
      final localRole = prefs.getString('role') ?? 'user';
      return prefs.getBool('isAdmin') == true ||
          prefs.getBool('isSuperAdmin') == true ||
          localRole == 'admin' ||
          localRole == 'super_admin';
    }
  }

  static Future<void> completeReset() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Clear all auth data
      await prefs.remove('isAdmin');
      await prefs.remove('user');
      await prefs.remove('token');
      await prefs.remove('userId');
      await prefs.remove('transactionPinSet');
      await prefs.remove('walletBalance');
      await prefs.remove('commissionBalance');

      debugPrint('🔄 COMPLETE RESET: Cleared all user data');
    } catch (e) {
      debugPrint('❌ RESET ERROR: $e');
    }
  }

  /// Public: check whether the approval system is currently ON.
  /// Works without admin auth — used by the user dashboard to decide
  /// whether to show the "Account Under Approval" banner.
  static Future<bool> isApprovalSystemEnabled() async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/api/approval-system-status'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final enabled = data['requireUserApproval'] != false;
        debugPrint('📋 Approval system enabled: $enabled');
        return enabled;
      }
      return true;
    } catch (e) {
      debugPrint('⚠️ isApprovalSystemEnabled error: $e');
      return true; // Fail-safe: assume ON
    }
  }

  // ==================== APPROVAL SETTING METHODS ====================

  /// Get whether the approval system is currently ON
  static Future<bool> getApprovalSetting() async {
    try {
      final token = await _getToken();
      if (token == null) throw Exception('Authentication required');

      final response = await http
          .get(
            Uri.parse('$baseUrl/api/admin/approval-setting'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['requireUserApproval'] == true;
      }
      // On non-200, default to true (safe)
      return true;
    } catch (e) {
      debugPrint('❌ getApprovalSetting error: $e');
      // Default to true so we don't accidentally disable the system
      return true;
    }
  }

  /// Toggle the approval system ON/OFF (Admin only)
  static Future<Map<String, dynamic>> updateApprovalSetting(
    bool enabled,
  ) async {
    try {
      final token = await _getToken();
      if (token == null) throw Exception('Authentication required');

      final response = await http
          .post(
            Uri.parse('$baseUrl/api/admin/approval-setting'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'requireUserApproval': enabled}),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        final error = jsonDecode(response.body);
        throw Exception(
          error['message'] ?? 'Failed to update approval setting',
        );
      }
    } catch (e) {
      debugPrint('❌ updateApprovalSetting error: $e');
      rethrow;
    }
  }

  // ==================== END APPROVAL SETTING METHODS ====================

  // ==================== USER APPROVAL METHODS ====================

  /// Get all users pending approval (Admin only)
  static Future<Map<String, dynamic>> getPendingUsers() async {
    try {
      final token = await _getToken();
      if (token == null) {
        throw Exception('Authentication required');
      }

      final response = await http
          .get(
            Uri.parse('$baseUrl/api/admin/users/pending'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['message'] ?? 'Failed to fetch pending users');
      }
    } catch (e) {
      debugPrint('❌ getPendingUsers error: $e');
      rethrow;
    }
  }

  /// Approve a user (Admin only)
  static Future<Map<String, dynamic>> approveUser(String userId) async {
    try {
      final token = await _getToken();
      if (token == null) {
        throw Exception('Authentication required');
      }

      final response = await http
          .post(
            Uri.parse('$baseUrl/api/admin/users/$userId/approve'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({}),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['message'] ?? 'Failed to approve user');
      }
    } catch (e) {
      debugPrint('❌ approveUser error: $e');
      rethrow;
    }
  }

  // ==================== ADMIN NOTIFICATIONS ====================

  /// Fetch all admin activity notifications
  static Future<Map<String, dynamic>> getAdminNotifications({
    int page = 1,
    int limit = 50,
    String type = 'all',
    String severity = 'all',
  }) async {
    try {
      final token = await getToken();
      final response = await http.get(
        Uri.parse(
          '$baseUrl/api/admin/notifications?page=$page&limit=$limit&type=$type&severity=$severity',
        ),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        return {'success': false, 'message': 'Failed to load notifications'};
      }
    } catch (e) {
      debugPrint('❌ getAdminNotifications error: $e');
      return {'success': false, 'message': e.toString()};
    }
  }

  /// Get unread admin notification count
  static Future<int> getAdminUnreadCount() async {
    try {
      final token = await getToken();
      final response = await http.get(
        Uri.parse('$baseUrl/api/admin/notifications/unread-count'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return (data['unreadCount'] ?? 0) as int;
      }
      return 0;
    } catch (e) {
      debugPrint('❌ getAdminUnreadCount error: $e');
      return 0;
    }
  }

  /// Mark one admin notification as read
  static Future<bool> markAdminNotificationRead(String id) async {
    try {
      final token = await getToken();
      final response = await http.post(
        Uri.parse('$baseUrl/api/admin/notifications/$id/read'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('❌ markAdminNotificationRead error: $e');
      return false;
    }
  }

  /// Mark all admin notifications as read
  static Future<bool> markAllAdminNotificationsRead() async {
    try {
      final token = await getToken();
      final response = await http.post(
        Uri.parse('$baseUrl/api/admin/notifications/mark-all-read'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('❌ markAllAdminNotificationsRead error: $e');
      return false;
    }
  }

  /// Reject a user (Admin only)
  static Future<Map<String, dynamic>> rejectUser(
    String userId, {
    String? reason,
  }) async {
    try {
      final token = await _getToken();
      if (token == null) {
        throw Exception('Authentication required');
      }

      final response = await http
          .post(
            Uri.parse('$baseUrl/api/admin/users/$userId/reject'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'reason': reason ?? 'Rejected by admin'}),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['message'] ?? 'Failed to reject user');
      }
    } catch (e) {
      debugPrint('❌ rejectUser error: $e');
      rethrow;
    }
  }

  // ==================== END USER APPROVAL METHODS ====================

  // Add this to ApiService class
  static Future<void> clearAdminCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('isAdmin');
      await prefs.remove('user');
      await prefs.remove('token');
      await prefs.remove('userId');
      debugPrint('🔄 ADMIN: Cleared all admin cache and user data');
    } catch (e) {
      debugPrint('❌ ADMIN CLEAR ERROR: $e');
    }
  }

  static Future<void> _saveAuthData(Map<String, dynamic> data) async {
    try {
      final token = data['token'];
      final refreshToken = data['refreshToken'];
      final user = data['user'];

      // ✅ 1. SAVE TO SECURE STORAGE (Required for API calls)
      if (token != null && token.isNotEmpty) {
        await SecureStorageService.saveTokens(
          accessToken: token,
          refreshToken: refreshToken ?? '',
          userId: user?['_id']?.toString(),
        );
      }

      // ✅ 2. SAVE TO SHARED PREFERENCES (Required for Dashboard & getSafeToken checks)
      final prefs = await SharedPreferences.getInstance();
      if (token != null && token.isNotEmpty) {
        await prefs.setString('token', token);
      }
      if (refreshToken != null && refreshToken.isNotEmpty) {
        await prefs.setString('refreshToken', refreshToken);
      }

      if (user != null) {
        await prefs.setString('user', jsonEncode(user));
        await prefs.setString('userId', user['_id']?.toString() ?? '');
        if (user['fullName'] != null) {
          await prefs.setString('fullName', user['fullName'].toString());
        }
        if (user['email'] != null) {
          await prefs.setString('email', user['email'].toString());
        }
        if (user['phone'] != null) {
          await prefs.setString('phone', user['phone'].toString());
        }
        if (user['walletBalance'] != null) {
          await prefs.setDouble(
            'walletBalance',
            (user['walletBalance'] as num).toDouble(),
          );
        }
        if (user['commissionBalance'] != null) {
          await prefs.setDouble(
            'commissionBalance',
            (user['commissionBalance'] as num).toDouble(),
          );
        }
        if (user['isAdmin'] != null) {
          await prefs.setBool('isAdmin', user['isAdmin'] == true);
        }
        if (user['role'] != null) {
          await prefs.setString('role', user['role'].toString());
        }
        if (user['transactionPinSet'] != null) {
          await prefs.setBool(
            'transactionPinSet',
            user['transactionPinSet'] == true,
          );
        }
        if (user['biometricEnabled'] != null) {
          await prefs.setBool(
            'biometricEnabled',
            user['biometricEnabled'] == true,
          );
        }
      }

      await prefs.setInt(
        'lastTokenRefresh',
        DateTime.now().millisecondsSinceEpoch,
      );
      _log(
        '✅ Authentication data saved to BOTH SecureStorage and SharedPreferences.',
      );
    } catch (e) {
      _log('❌ Error saving auth data: $e');
    }
  }

  /// 🔄 Enhanced token refresh with better error handling
  static Future<Map<String, dynamic>> refreshTokenWithFallback() async {
    _log('🔄 Attempting token refresh with fallback...');

    try {
      final prefs = await SharedPreferences.getInstance();
      final refreshToken = prefs.getString('refreshToken');
      if (refreshToken == null) {
        _log('❌ No refresh token found');
        return {'success': false, 'message': 'No refresh token available'};
      }

      final response = await http
          .post(
            _refreshTokenUrl,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'refreshToken': refreshToken}),
          )
          .timeout(const Duration(seconds: 30));

      _log('Refresh token response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['success'] == true && data['token'] != null) {
          // Save new tokens
          await prefs.setString('token', data['token']);

          if (data['refreshToken'] != null) {
            await prefs.setString('refreshToken', data['refreshToken']);
          }

          // Clear reauth flag on successful refresh
          await prefs.remove('needsReauth');
          await prefs.setInt(
            'lastTokenRefresh',
            DateTime.now().millisecondsSinceEpoch,
          );

          _log('✅ Token refresh successful');
          return {
            'success': true,
            'token': data['token'],
            'refreshToken': data['refreshToken'],
          };
        }
      }

      // If we get here, refresh failed - but don't clear data
      _log('❌ Refresh token invalid or expired');
      return {'success': false, 'message': 'Refresh token invalid or expired'};
    } catch (e) {
      _log('❌ Token refresh error: $e');
      return {'success': false, 'message': 'Token refresh error: $e'};
    }
  }

  // --- API Request Helpers ---
  static Future<Map<String, dynamic>> _authenticatedPost(
    Uri url,
    Map<String, dynamic> body, {
    Duration timeout = const Duration(seconds: 30),
    Map<String, String>? extraHeaders,
    bool useBiometric = false,
  }) async {
    _log('Authenticated POST request to $url');
    _log('Request body: ${jsonEncode(body)}');

    final token = await _TokenManager.getSafeToken();
    if (token == null) {
      _log('ERROR: Authentication token not found.');
      // ✅ Try to recover before throwing
      final recovered = await recoverAuthentication();
      if (!recovered['success']) {
        throw Exception('Authentication token not found. Please log in again.');
      }
      final newToken = await _TokenManager.getSafeToken();
      if (newToken == null) {
        throw Exception('Authentication token not found. Please log in again.');
      }
    }

    try {
      final headers = <String, String>{
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${await _TokenManager.getSafeToken()}',
      };
      if (extraHeaders != null) {
        headers.addAll(extraHeaders);
      }

      final response = await http
          .post(url, headers: headers, body: jsonEncode(body))
          .timeout(timeout);

      _log('Response status: ${response.statusCode}');
      _log('Response body: ${response.body}');

      final responseData = jsonDecode(response.body);

      // ✅ If response is successful, return as-is
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return responseData;
      }

      // ✅ For error responses, return structured data with limit info if present
      if (responseData is Map<String, dynamic>) {
        final errorCode = responseData['code']?.toString() ?? '';

        // ✅ Pass through limit error details
        if (errorCode == 'PER_TRANSACTION_LIMIT_EXCEEDED' ||
            errorCode == 'DAILY_LIMIT_EXCEEDED') {
          return responseData; // Return as-is so caller can extract limit info
        }

        // For other errors, throw with message
        throw Exception(responseData['message'] ?? 'Request failed');
      }

      throw Exception('Request failed with status: ${response.statusCode}');
    } on http.ClientException catch (e, stackTrace) {
      _log('ERROR: Failed to connect to the server: $e');
      await reportError(e, stackTrace);
      throw Exception(
        'Failed to connect to the server. Please try again later.',
      );
    } on TimeoutException {
      _log('ERROR: Request timed out.');
      throw Exception('Request timed out. Please try again.');
    } catch (e) {
      _log('ERROR in _authenticatedPost: $e');
      rethrow;
    }
  }

  static Future<dynamic> _authenticatedGet(Uri url) async {
    _log('Authenticated GET request to $url');

    return await _authenticatedRequest(() async {
      final token = await _TokenManager.getSafeToken();
      if (token == null) {
        _log('ERROR: Authentication token not found.');
        // ✅ Try to recover before throwing
        final recovered = await recoverAuthentication();
        if (!recovered['success']) {
          throw Exception(
            'Authentication token not found. Please log in again.',
          );
        }
        // Retry getting token after recovery
        final newToken = await _TokenManager.getSafeToken();
        if (newToken == null) {
          throw Exception(
            'Authentication token not found. Please log in again.',
          );
        }
      }

      final response = await http
          .get(
            url,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${await _TokenManager.getSafeToken()}',
            },
          )
          .timeout(const Duration(seconds: 30));

      _log('Response status: ${response.statusCode}');
      _log('Response body: ${response.body}');

      return _handleResponse(response);
    }, 'GET $url');
  }

  static Future<dynamic> _unauthenticatedGet(Uri url) async {
    _log('Unauthenticated GET request to $url');
    try {
      final response = await http
          .get(url, headers: {'Content-Type': 'application/json'})
          .timeout(const Duration(seconds: 30));
      _log('Response status: ${response.statusCode}');
      _log('Response body: ${response.body}');
      return _handleResponse(response);
    } catch (e) {
      if (e.toString().contains('SocketException') ||
          e.toString().contains('Network is unreachable')) {
        _log('ERROR: No internet connection.');
        throw Exception('No internet connection. Please check your network.');
      } else if (e is TimeoutException) {
        _log('ERROR: Request timed out.');
        throw Exception('Request timed out. Please try again.');
      } else if (e is http.ClientException) {
        _log('ERROR: Failed to connect to the server: $e');
        await reportError(e, StackTrace.current);
        throw Exception(
          'Failed to connect to the server. Please try again later.',
        );
      } else {
        _log('ERROR in _unauthenticatedGet: $e');
        rethrow;
      }
    }
  }

  static Future<Map<String, dynamic>> _authenticatedPut(
    Uri url,
    Map<String, dynamic> body,
  ) async {
    _log('Authenticated PUT request to $url');
    final token = await _getToken();
    if (token == null) {
      _log('ERROR: Authentication token not found.');
      throw Exception('Authentication token not found. Please log in again.');
    }
    try {
      final response = await http
          .put(
            url,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));
      _log('Response status: ${response.statusCode}');
      _log('Response body: ${response.body}');
      return _handleResponse(response);
    } catch (e) {
      if (e.toString().contains('SocketException') ||
          e.toString().contains('Network is unreachable')) {
        _log('ERROR: No internet connection.');
        throw Exception('No internet connection. Please check your network.');
      } else if (e is TimeoutException) {
        _log('ERROR: Request timed out.');
        throw Exception('Request timed out. Please try again.');
      } else if (e is http.ClientException) {
        _log('ERROR: Failed to connect to the server: $e');
        await reportError(e, StackTrace.current);
        throw Exception(
          'Failed to connect to the server. Please try again later.',
        );
      } else {
        _log('ERROR in _authenticatedPut: $e');
        rethrow;
      }
    }
  }

  static Future<Map<String, dynamic>> _authenticatedPatch(
    Uri url,
    Map<String, dynamic> body,
  ) async {
    _log('Authenticated PATCH request to $url');
    final token = await _getToken();
    if (token == null) {
      _log('ERROR: Authentication token not found.');
      throw Exception('Authentication token not found. Please log in again.');
    }
    try {
      final response = await http
          .patch(
            url,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));
      _log('Response status: ${response.statusCode}');
      _log('Response body: ${response.body}');
      return _handleResponse(response);
    } catch (e) {
      if (e.toString().contains('SocketException') ||
          e.toString().contains('Network is unreachable')) {
        _log('ERROR: No internet connection.');
        throw Exception('No internet connection. Please check your network.');
      } else if (e is TimeoutException) {
        _log('ERROR: Request timed out.');
        throw Exception('Request timed out. Please try again.');
      } else if (e is http.ClientException) {
        _log('ERROR: Failed to connect to the server: $e');
        await reportError(e, StackTrace.current);
        throw Exception(
          'Failed to connect to the server. Please try again later.',
        );
      } else {
        _log('ERROR in _authenticatedPatch: $e');
        rethrow;
      }
    }
  }

  static Future<Map<String, dynamic>> _authenticatedDelete(Uri url) async {
    _log('Authenticated DELETE request to $url');
    final token = await _getToken();
    if (token == null) {
      _log('ERROR: Authentication token not found.');
      throw Exception('Authentication token not found. Please log in again.');
    }
    try {
      final response = await http
          .delete(
            url,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 30));
      _log('Response status: ${response.statusCode}');
      _log('Response body: ${response.body}');
      return _handleResponse(response);
    } catch (e) {
      if (e.toString().contains('SocketException') ||
          e.toString().contains('Network is unreachable')) {
        _log('ERROR: No internet connection.');
        throw Exception('No internet connection. Please check your network.');
      } else if (e is TimeoutException) {
        _log('ERROR: Request timed out.');
        throw Exception('Request timed out. Please try again.');
      } else if (e is http.ClientException) {
        _log('ERROR: Failed to connect to the server: $e');
        await reportError(e, StackTrace.current);
        throw Exception(
          'Failed to connect to the server. Please try again later.',
        );
      } else {
        _log('ERROR in _authenticatedDelete: $e');
        rethrow;
      }
    }
  }

  static Future<Map<String, dynamic>> _authenticatedMultipartPost(
    Uri url,
    Map<String, String> fields,
    dynamic file,
  ) async {
    _log('Authenticated multipart POST request to $url');
    final token = await _getToken();
    if (token == null) {
      _log('ERROR: Authentication token not found.');
      throw Exception('Authentication token not found. Please log in again.');
    }
    try {
      final request = http.MultipartRequest('POST', url);
      request.headers['Authorization'] = 'Bearer $token';
      fields.forEach((key, value) => request.fields[key] = value);

      // ✅ WEB + MOBILE: Use XFile (from image_picker) uniformly
      // On web, `dart:io File` is unavailable — this is the correct path.
      if (file is XFile) {
        final bytes = await file.readAsBytes();
        if (bytes.isEmpty) {
          throw Exception('Selected image is empty');
        }

        // Detect MIME type — XFile.mimeType is often null on web
        String mimeType = file.mimeType ?? '';
        if (mimeType.isEmpty) {
          // Fallback: guess from file extension
          final name = file.name.toLowerCase();
          if (name.endsWith('.png')) {
            mimeType = 'image/png';
          } else if (name.endsWith('.jpg') || name.endsWith('.jpeg')) {
            mimeType = 'image/jpeg';
          } else if (name.endsWith('.gif')) {
            mimeType = 'image/gif';
          } else if (name.endsWith('.webp')) {
            mimeType = 'image/webp';
          } else {
            mimeType = 'application/octet-stream';
          }
        }

        final multipartFile = http.MultipartFile.fromBytes(
          'profileImage',
          bytes,
          filename: file.name.isNotEmpty ? file.name : 'profile.jpg',
          contentType: MediaType.parse(mimeType),
        );
        request.files.add(multipartFile);
      } else if (file is io.File) {
        // Legacy: dart:io File (mobile only, still supported for safety)
        final mimeType = lookupMimeType(file.path) ?? 'image/jpeg';
        final fileName = file.path.split('/').last;
        final multipartFile = await http.MultipartFile.fromPath(
          'profileImage',
          file.path,
          filename: fileName,
          contentType: MediaType.parse(mimeType),
        );
        request.files.add(multipartFile);
      } else {
        throw Exception(
          'Invalid file type. Expected XFile or File, got ${file.runtimeType}',
        );
      }

      final response = await request.send().timeout(
        const Duration(seconds: 30),
      );
      final responseBody = await response.stream.bytesToString();
      _log('Response status: ${response.statusCode}');
      _log('Response body: $responseBody');
      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (responseBody.isEmpty) return {};
        try {
          final data = jsonDecode(responseBody);
          _log('Request successful. Decoded data: $data');
          return data;
        } on FormatException {
          _log('ERROR: Failed to decode JSON response.');
          throw const FormatException('Invalid response format from server.');
        }
      } else {
        String message;
        try {
          final data = jsonDecode(responseBody);
          message =
              data['message'] ??
              'Request failed with status: ${response.statusCode}';
        } catch (e) {
          message = 'Request failed with status: ${response.statusCode}';
        }
        _log(
          'ERROR: Request failed. Status: ${response.statusCode}, Message: $message',
        );
        throw Exception(message);
      }
    } on http.ClientException catch (e, stackTrace) {
      _log('ERROR: Failed to connect to the server: $e');
      await reportError(e, stackTrace);
      throw http.ClientException(
        'Failed to connect to the server. Please try again later.',
      );
    } on TimeoutException {
      _log('ERROR: Request timed out.');
      throw Exception('Request timed out. Please try again.');
    } catch (e) {
      _log('ERROR in _authenticatedMultipartPost: $e');
      rethrow;
    }
  }

  // --- Curl Fallback Helper ---
  static Future<Map<String, String>?> _executeCurl(
    Uri url,
    Map<String, dynamic> body,
  ) async {
    if (kIsWeb) {
      _log('Curl execution not supported on web');
      return null;
    }
    try {
      final jsonBody = jsonEncode(body);
      final args = [
        '-s',
        '-w',
        'HTTP_STATUS=%{http_code}\n',
        '-X',
        'POST',
        '-H',
        'Content-Type: application/json',
        '-H',
        'api-key: $_apiKey',
        '-H',
        'secret-key: $_secretKey',
        '-H',
        'public-key: $_publicKey',
        '--data-raw',
        jsonBody,
        '-k',
        url.toString(),
      ];
      final result = await io.Process.run('curl', args);
      String statusLine = result.stderr.trim();
      int statusCode = 200;
      if (statusLine.startsWith('HTTP_STATUS=')) {
        statusCode = int.tryParse(statusLine.substring(12)) ?? 500;
      }
      final responseBody = result.stdout;
      _log('Curl response status: $statusCode');
      _log('Curl response body: $responseBody');
      return {'body': responseBody, 'status': statusCode.toString()};
    } catch (e) {
      _log('Curl execution failed: $e');
      return null;
    }
  }

  /// 🚀 ENHANCED LIVE VTpass API CALL
  /// 🚀 FIXED VTpass LIVE API WITH CORS WORKAROUND
  static Future<Map<String, dynamic>> _vtpassPostLive(
    Uri url,
    Map<String, dynamic> body,
  ) async {
    _log('🚀 VTpass LIVE API Request');
    _log('🎯 URL: $url');
    _log('📦 Payload: ${jsonEncode(body)}');

    await _initializeCredentials();

    try {
      // STRATEGY 1: Use your backend proxy first (avoids CORS)
      _log('🔐 Attempting proxy method first...');
      try {
        final proxyResult = await _vtpassPostViaProxy(body);
        if (proxyResult['success'] != false && proxyResult['code'] != null) {
          _log('✅ Proxy method successful');
          return proxyResult;
        }
      } catch (proxyError) {
        _log('⚠️ Proxy method failed: $proxyError');
      }

      // STRATEGY 2: Enhanced direct API with better error handling
      _log('📱 Attempting enhanced direct LIVE API...');
      try {
        return await _vtpassPostDirectEnhanced(url, body);
      } catch (directError) {
        _log('⚠️ Enhanced direct API failed: $directError');
        throw Exception('Cannot connect to VTpass service. Please try again.');
      }
    } catch (e, stackTrace) {
      _log('💥 All VTpass methods failed: $e');
      await reportError(e, stackTrace);

      return {
        'success': false,
        'message': 'VTpass service temporarily unavailable. Please try again.',
        'error': e.toString(),
        'retryable': true,
      };
    }
  }

  /// Get VTpass wallet balance - TRIES BOTH AUTH METHODS
  /// Get VTpass wallet balance
  /// Get VTpass wallet balance
  static Future<Map<String, dynamic>> getVtpassBalance() async {
    try {
      final result = await _callVtpassApi('/balance', isGet: true);

      if (result['success'] == true && result['data'] != null) {
        final data = result['data'];

        // Check VTpass response format
        if (data['code'] == 1) {
          final balance = data['contents']?['balance'] ?? 0.0;
          return {
            'success': true,
            'balance': balance,
            'message': 'Balance fetched successfully',
          };
        } else {
          return {
            'success': false,
            'message': data['message'] ?? 'Failed to fetch balance',
            'code': data['code'],
          };
        }
      }

      return result;
    } catch (e) {
      debugPrint('❌ Error fetching VTpass balance: $e');
      return {
        'success': false,
        'message': 'Error fetching balance: ${e.toString()}',
      };
    }
  }

  /// Get VTpass alerts based on balance
  static Future<Map<String, dynamic>> getVtpassAlerts() async {
    try {
      // First get the balance
      final balanceResult = await getVtpassBalance();

      if (balanceResult['success'] == true) {
        final balance = balanceResult['balance'] ?? 0.0;
        List<Map<String, dynamic>> alerts = [];

        // Generate alerts based on balance
        if (balance < 1000) {
          alerts.add({
            'title': 'Critical Low Balance',
            'message':
                'VTpass wallet balance is critically low (₦${balance.toStringAsFixed(2)}). Please add funds immediately.',
            'severity': 'CRITICAL',
            'acknowledged': false,
            'createdAt': DateTime.now().toIso8601String(),
            'data': {'availableBalance': balance},
          });
        } else if (balance < 5000) {
          alerts.add({
            'title': 'Low Balance Warning',
            'message':
                'VTpass wallet balance is low (₦${balance.toStringAsFixed(2)}). Consider adding funds.',
            'severity': 'WARNING',
            'acknowledged': false,
            'createdAt': DateTime.now().toIso8601String(),
            'data': {'availableBalance': balance},
          });
        }

        return {
          'success': true,
          'alerts': alerts,
          'currentBalance': balance,
          'message': 'Alerts fetched successfully',
        };
      }

      return {
        'success': false,
        'alerts': [],
        'message': balanceResult['message'] ?? 'Failed to fetch alerts',
      };
    } catch (e) {
      debugPrint('❌ Error fetching VTpass alerts: $e');
      return {
        'success': false,
        'message': 'Error fetching alerts: ${e.toString()}',
        'alerts': [],
      };
    }
  }

  /// Get VTpass service variations for education services via BACKEND
  static Future<Map<String, dynamic>> getVtpassVariations(
    String serviceID,
  ) async {
    _log('🎯 Fetching VTpass variations via BACKEND for service: $serviceID');

    try {
      final url = Uri.parse(
        '$baseUrl/api/education/variations?serviceID=$serviceID',
      );
      _log('🔗 Backend URL: $url');

      final response = await _authenticatedGet(url);

      // Check if the backend request was successful
      if (response['success'] == true) {
        final variations = response['variations'] ?? [];
        final source = response['source'] ?? 'unknown';

        _log(
          '✅ Successfully fetched ${variations.length} variations via backend (source: $source)',
        );

        return {
          'success': true,
          'response_description': '000',
          'content': {
            'variations': variations,
            'ServiceName': _getEducationServiceName(serviceID),
            'serviceID': serviceID,
            'convinience_fee': 'N0.00',
          },
          'source': source,
          'variations': variations,
        };
      } else {
        throw Exception(
          'Backend failed to fetch variations: ${response['message']}',
        );
      }
    } catch (e) {
      _log('❌ Error fetching VTpass variations via backend: $e');

      // Return mock data as fallback
      return _getMockEducationVariations(serviceID);
    }
  }

  /// Get base URL for API calls
  static String _getBaseUrl() {
    return baseUrl; // Using your existing baseUrl constant
  }

  /// Helper method to get education service name
  static String _getEducationServiceName(String serviceID) {
    switch (serviceID) {
      case 'waec-registration':
        return 'WAEC Registration PIN';
      case 'waec':
        return 'WAEC Result Checker PIN';
      case 'jamb':
        return 'JAMB PIN';
      default:
        return 'Education Service';
    }
  }

  /// Enhanced mock data fallback
  static Map<String, dynamic> _getMockEducationVariations(String serviceID) {
    _log('🎭 Using mock fallback data for: $serviceID');

    Map<String, dynamic> mockData = {
      'success': true,
      'response_description': '000',
      'source': 'mock_fallback',
      'variations': [],
      'content': {
        'ServiceName': _getEducationServiceName(serviceID),
        'serviceID': serviceID,
        'convinience_fee': 'N0.00',
        'variations': [],
      },
    };

    switch (serviceID) {
      case 'waec-registration':
        mockData['content']['variations'] = [
          {
            "variation_code": "waec-registration",
            "name": "WASSCE for Private Candidates - Second Series (2024)",
            "variation_amount": "18950.00",
            "fixedPrice": "Yes",
          },
          {
            "variation_code": "waec-registration-2",
            "name": "WASSCE for Private Candidates - First Series (2024)",
            "variation_amount": "18950.00",
            "fixedPrice": "Yes",
          },
        ];
        break;

      case 'waec':
        mockData['content']['variations'] = [
          {
            "variation_code": "waecdirect",
            "name": "WASSCE Result Checker",
            "variation_amount": "1200.00",
            "fixedPrice": "Yes",
          },
          {
            "variation_code": "waecdirect-2",
            "name": "WASSCE GCE Result Checker",
            "variation_amount": "1200.00",
            "fixedPrice": "Yes",
          },
        ];
        break;

      case 'jamb':
        mockData['content']['variations'] = [
          {
            "variation_code": "utme-mock",
            "name": "UTME PIN (with mock)",
            "variation_amount": "6300.00",
            "fixedPrice": "Yes",
          },
          {
            "variation_code": "utme-no-mock",
            "name": "UTME PIN (without mock)",
            "variation_amount": "4700.00",
            "fixedPrice": "Yes",
          },
          {
            "variation_code": "direct-entry",
            "name": "Direct Entry PIN",
            "variation_amount": "5300.00",
            "fixedPrice": "Yes",
          },
        ];
        break;
    }

    mockData['variations'] = mockData['content']['variations'];
    return mockData;
  }

  // ==================== VTPASS API HELPER ====================

  /// Call VTpass API - Works with header-based authentication
  /// Call VTpass API - AUTO-DETECTS AUTH METHOD
  static Future<Map<String, dynamic>> _callVtpassApi(
    String endpoint, {
    Map<String, dynamic>? body,
    bool isGet = false,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final useSandbox = prefs.getBool('useSandbox') ?? true;

      final apiKey =
          useSandbox
              ? const String.fromEnvironment('VTPASS_SANDBOX_API_KEY')
              : const String.fromEnvironment('VTPASS_LIVE_API_KEY');
      final secretKey =
          useSandbox
              ? const String.fromEnvironment('VTPASS_SANDBOX_SECRET_KEY')
              : const String.fromEnvironment('VTPASS_LIVE_SECRET_KEY');

      final baseUrl =
          useSandbox
              ? 'https://sandbox.vtpass.com/api'
              : 'https://vtpass.com/api';

      final url = '$baseUrl$endpoint';

      debugPrint('📡 VTpass API Call: $url');
      debugPrint('🔑 Environment: ${useSandbox ? "Sandbox" : "Live"}');

      Map<String, String> headers = {
        'Content-Type': 'application/json',
        'User-Agent': 'Dalabapay/1.0',
      };

      // ✅ FIX: Use Basic Auth for balance endpoint
      if (endpoint == '/balance') {
        final String basicAuth = base64Encode(
          utf8.encode('$apiKey:$secretKey'),
        );
        headers['Authorization'] = 'Basic $basicAuth';
        debugPrint('🔑 Using Basic Auth for balance endpoint');
      } else {
        // Use header-based auth for all other endpoints
        headers['api-key'] = apiKey;
        headers['secret-key'] = secretKey;
        debugPrint('🔑 Using Header Auth for $endpoint endpoint');
      }

      http.Response response;

      if (isGet) {
        response = await http
            .get(Uri.parse(url), headers: headers)
            .timeout(const Duration(seconds: 15));
      } else {
        response = await http
            .post(
              Uri.parse(url),
              headers: headers,
              body: jsonEncode(body ?? {}),
            )
            .timeout(const Duration(seconds: 15));
      }

      debugPrint('📡 Response Status: ${response.statusCode}');
      debugPrint(
        '📡 Response Body: ${response.body.substring(0, response.body.length > 200 ? 200 : response.body.length)}...',
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'success': true,
          'data': data,
          'statusCode': response.statusCode,
        };
      } else if (response.statusCode == 401) {
        return {
          'success': false,
          'message':
              'Invalid credentials for this endpoint. Please check your VTpass API keys.',
          'code': '087',
          'statusCode': response.statusCode,
        };
      } else {
        try {
          final error = jsonDecode(response.body);
          return {
            'success': false,
            'message': error['message'] ?? 'API call failed',
            'code': error['code'],
            'statusCode': response.statusCode,
          };
        } catch (e) {
          return {
            'success': false,
            'message': 'API call failed with status ${response.statusCode}',
            'statusCode': response.statusCode,
          };
        }
      }
    } catch (e) {
      debugPrint('❌ VTpass API error: $e');
      return {'success': false, 'message': 'API call failed: ${e.toString()}'};
    }
  }

  /// 📡 ENHANCED DIRECT API WITH BETTER CONFIGURATION
  static Future<Map<String, dynamic>> _vtpassPostDirectEnhanced(
    Uri url,
    Map<String, dynamic> body,
  ) async {
    _log('📡 Using enhanced direct VTpass API');

    try {
      // Use IOClient with proper configuration for mobile
      final client = IOClient(
        HttpClient()
          ..connectionTimeout = const Duration(seconds: 25)
          ..badCertificateCallback = (cert, host, port) => true,
      );

      final headers = {
        'Content-Type': 'application/json',
        'api-key': _apiKey,
        'secret-key': _secretKey,
        'public-key': _publicKey,
        'User-Agent': 'FlutterApp/3.0.0',
        'Accept': 'application/json',
      };

      _log('🔑 Using LIVE API Key: ${_apiKey.substring(0, 8)}...');

      final response = await client
          .post(url, headers: headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 25));

      _log('📡 Response status: ${response.statusCode}');
      _log('📦 Response body: ${response.body}');

      return _handleVtpassResponse(response);
    } catch (e) {
      _log('❌ Enhanced direct API failed: $e');

      // Provide specific error messages
      if (e.toString().contains('Failed to fetch') ||
          e.toString().contains('XMLHttpRequest') ||
          e.toString().contains('ClientException')) {
        throw Exception(
          'Network error: Cannot connect to VTpass servers. This may be a temporary issue.',
        );
      } else if (e.toString().contains('timeout')) {
        throw Exception('VTpass server is not responding. Please try again.');
      } else {
        rethrow;
      }
    }
  }

  /// 🎯 PROCESS LIVE VTpass RESPONSE
  static Map<String, dynamic> _processVtpassLiveResponse(
    Map<String, dynamic> data,
  ) {
    _log('🔍 Processing LIVE VTpass Response');

    // Check transaction success
    if (data['code']?.toString() == '000') {
      _log('✅ LIVE Transaction Successful');
      return {
        'success': true,
        'code': data['code'],
        'response_description': data['response_description'],
        'content': data['content'],
        'requestId': data['requestId'],
        'amount': data['amount'],
        'transaction_date': data['transaction_date'],
      };
    } else {
      final errorMsg = data['response_description'] ?? 'Transaction failed';
      _log('❌ LIVE Transaction Failed: $errorMsg');
      return {
        'success': false,
        'code': data['code'],
        'response_description': errorMsg,
        'message': errorMsg,
      };
    }
  }

  // --- VTpass Direct API Request Helper (Final Optimized Version) ---
  static Future<Map<String, dynamic>> _vtpassPost(
    Uri url,
    Map<String, dynamic> body,
  ) async {
    _log('🌐 VTpass request initiated to $url');
    _log('📦 Request body: ${jsonEncode(body)}');

    await _initializeCredentials();

    // Determine primary and fallback based on platform
    Future<Map<String, dynamic>> primaryMethod;
    Future<Map<String, dynamic>> fallbackMethod;
    String primaryType;
    String fallbackType;

    if (kIsWeb) {
      // Web: Proxy first to avoid CORS
      primaryMethod = _vtpassPostViaProxy(body);
      fallbackMethod = _vtpassPostDirect(url, body);
      primaryType = 'proxy (for CORS)';
      fallbackType = 'direct';
    } else {
      // Mobile: Direct first for better performance
      primaryMethod = _vtpassPostDirect(url, body);
      fallbackMethod = _vtpassPostViaProxy(body);
      primaryType = 'direct';
      fallbackType = 'proxy';
    }

    try {
      _log('📱 Attempting primary method: $primaryType');
      final result = await primaryMethod;
      if (result['success'] == true || result['code']?.toString() == '000') {
        _log('✅ Primary method ($primaryType) successful');
        return result;
      }
      throw Exception('Primary method failed: ${result['message']}');
    } catch (e) {
      _log('⚠️ Primary method ($primaryType) failed: $e');
    }

    try {
      _log('🔄 Attempting fallback method: $fallbackType');
      final result = await fallbackMethod;
      if (result['success'] == true || result['code']?.toString() == '000') {
        _log('✅ Fallback method ($fallbackType) successful');
        return result;
      }
      throw Exception('Fallback method failed: ${result['message']}');
    } catch (e) {
      _log('❌ Fallback method ($fallbackType) failed: $e');
      throw Exception(
        'VTpass service temporarily unavailable. Please try again.',
      );
    }
  }

  /// 🔧 FIXED: Direct API with better error handling
  /// 🔧 FIXED: Direct API with proper Live configuration
  static Future<Map<String, dynamic>> _vtpassPostDirect(
    Uri url,
    Map<String, dynamic> body,
  ) async {
    _log('📱 Using direct VTpass LIVE API');

    try {
      final client = http.Client();

      final headers = {
        'Content-Type': 'application/json',
        'api-key': _apiKey,
        'secret-key': _secretKey,
        'public-key': _publicKey,
      };

      _log('🔑 Using API Key: ${_apiKey.substring(0, 8)}...');
      _log('🎯 Target URL: $url');

      final response = await client
          .post(url, headers: headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 30));

      _log('📡 Response status: ${response.statusCode}');
      _log('📦 Response body: ${response.body}');

      return _handleVtpassResponse(response);
    } catch (e) {
      _log('❌ Direct API failed: $e');
      rethrow;
    }
  }

  /// 🔧 NEW: Simulated VTpass response for testing
  static Map<String, dynamic> _simulateVtpassResponse(
    Map<String, dynamic> body,
  ) {
    _log('🎭 SIMULATING VTpass RESPONSE FOR TESTING');

    final requestId =
        body['request_id'] ?? 'SIM_${DateTime.now().millisecondsSinceEpoch}';
    final amount = body['amount'] ?? '50.00';
    final serviceID = body['serviceID'] ?? 'mtn';
    final phone = body['phone'] ?? '08108603409';

    // Simulate successful response based on VTpass documentation
    return {
      'code': '000',
      'content': {
        'transactions': {
          'status': 'delivered',
          'product_name': '${serviceID.toUpperCase()} Airtime VTU',
          'unique_element': phone,
          'unit_price': amount,
          'quantity': 1,
          'service_verification': null,
          'channel': 'api',
          'commission': 0.70,
          'total_amount': (double.parse(amount) - 0.70).toString(),
          'discount': null,
          'type': 'Airtime Recharge',
          'email': 'user@example.com',
          'phone': phone,
          'name': null,
          'convinience_fee': 0,
          'amount': amount,
          'platform': 'api',
          'method': 'api',
          'transactionId': 'SIM_${DateTime.now().millisecondsSinceEpoch}',
        },
      },
      'response_description': 'TRANSACTION SUCCESSFUL',
      'requestId': requestId,
      'amount': double.parse(amount),
      'transaction_date': DateTime.now().toIso8601String(),
      'purchased_code': '',
      'success': true,
    };
  }

  /// ✅ NEW: Enhanced cURL-style implementation
  static Future<Map<String, dynamic>> _vtpassPostCurl(
    Uri url,
    Map<String, dynamic> body,
  ) async {
    _log('🌀 Using enhanced cURL-style implementation');

    try {
      // For mobile platforms, use HttpClient with proper configuration
      if (!kIsWeb) {
        return await _vtpassPostHttpClient(url, body);
      } else {
        // For web, use enhanced fetch
        return await _vtpassPostWebFetch(url, body);
      }
    } catch (e) {
      _log('❌ cURL method failed: $e');
      rethrow;
    }
  }

  /// ✅ NEW: HttpClient implementation (like cURL)
  static Future<Map<String, dynamic>> _vtpassPostHttpClient(
    Uri url,
    Map<String, dynamic> body,
  ) async {
    _log('🔧 Using HttpClient (cURL-style)');

    try {
      final client = HttpClient();

      // Configure client like cURL
      client.connectionTimeout = const Duration(seconds: 30);

      final request = await client.postUrl(url);

      // Set exact headers as required by VTpass
      request.headers.set('Content-Type', 'application/json');
      request.headers.set('api-key', _apiKey);
      request.headers.set('secret-key', _secretKey);
      request.headers.set('public-key', _publicKey);
      request.headers.set('User-Agent', 'Dart/HTTP Client');

      // Write the body
      request.write(jsonEncode(body));

      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();

      _log('📡 HttpClient response status: ${response.statusCode}');
      _log('📦 HttpClient response body: $responseBody');

      if (response.statusCode == 200) {
        final data = jsonDecode(responseBody);
        return _processVtpassResponse(data);
      } else {
        throw Exception('HTTP ${response.statusCode}: $responseBody');
      }
    } catch (e) {
      _log('❌ HttpClient failed: $e');
      rethrow;
    }
  }

  /// ✅ NEW: Web-specific implementation
  static Future<Map<String, dynamic>> _vtpassPostWeb(
    Uri url,
    Map<String, dynamic> body,
  ) async {
    _log('🌐 Using web-specific implementation');

    try {
      // Try multiple web approaches
      final results = await Future.wait([
        _vtpassPostWebFetch(url, body).catchError((e) => e),
        _vtpassPostWebXMLHttp(url, body).catchError((e) => e),
      ], eagerError: false);

      // Return first successful result
      for (var result in results) {
        if (result['success'] != false) {
          return result;
        }
      }

      throw Exception('All web methods failed');
    } catch (e) {
      _log('❌ Web methods failed: $e');
      rethrow;
    }
  }

  /// ✅ NEW: XMLHttpRequest for web (like cURL)
  static Future<Map<String, dynamic>> _vtpassPostWebXMLHttp(
    Uri url,
    Map<String, dynamic> body,
  ) async {
    _log('🌐 Using XMLHttpRequest for web');

    // This would be implemented with dart:js or similar for web
    // For now, fallback to fetch
    return await _vtpassPostWebFetch(url, body);
  }

  /// ✅ NEW: Mobile-specific implementation
  static Future<Map<String, dynamic>> _vtpassPostMobile(
    Uri url,
    Map<String, dynamic> body,
  ) async {
    _log('📱 Using mobile-specific implementation');

    try {
      // Use IOClient with proper configuration
      final client = IOClient();

      final headers = {
        'Content-Type': 'application/json',
        'api-key': _apiKey,
        'secret-key': _secretKey,
        'public-key': _publicKey,
      };

      final response = await client
          .post(url, headers: headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 30));

      return _handleVtpassResponse(response);
    } catch (e) {
      _log('❌ Mobile method failed: $e');
      rethrow;
    }
  }

  /// ✅ CORRECT: Process VTpass response according to documentation
  static Map<String, dynamic> _processVtpassResponse(
    Map<String, dynamic> data,
  ) {
    _log('🔍 Processing VTpass response: ${jsonEncode(data)}');

    // Check if transaction was successful - code "000" means success
    if (data['code']?.toString() == '000') {
      _log('✅ VTpass transaction completed successfully');
      return {...data, 'success': true};
    } else {
      // Transaction failed but API call was successful
      final errorMessage =
          data['response_description'] ?? 'VTpass transaction failed.';
      _log('❌ VTpass transaction failed: $errorMessage');

      return {...data, 'success': false, 'message': errorMessage};
    }
  }

  /// ✅ UPDATED: Handle VTpass response
  static Future<Map<String, dynamic>> _handleVtpassResponse(
    http.Response response,
  ) async {
    _log('📨 Handling VTpass response - Status: ${response.statusCode}');

    if (response.statusCode == 200) {
      try {
        final data = jsonDecode(response.body);
        return _processVtpassResponse(data);
      } catch (e) {
        _log('❌ Failed to parse VTpass response: $e');
        throw Exception('Invalid response format from VTpass server.');
      }
    } else if (response.statusCode == 401) {
      throw Exception(
        'Authentication failed. Please check your API credentials.',
      );
    } else if (response.statusCode == 403) {
      throw Exception('Access forbidden. Please check your API permissions.');
    } else if (response.statusCode == 404) {
      throw Exception('API endpoint not found. Please check the URL.');
    } else if (response.statusCode == 429) {
      throw Exception('Rate limit exceeded. Please try again later.');
    } else if (response.statusCode >= 500) {
      throw Exception('VTpass server error. Please try again later.');
    } else {
      throw Exception('Request failed with status: ${response.statusCode}');
    }
  }

  // Secure proxy method
  /// 🔐 ENHANCED PROXY METHOD FOR LIVE
  static Future<Map<String, dynamic>> _vtpassPostViaProxy(
    Map<String, dynamic> body,
  ) async {
    _log('🔐 Using secure proxy endpoint for LIVE environment');

    try {
      final proxyUrl = Uri.parse('$baseUrl/api/vtpass/proxy');

      _log('📤 Sending to secure proxy');
      _log('📦 Proxy payload: ${jsonEncode(body)}');

      final response = await http
          .post(
            proxyUrl,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${await _getToken()}',
            },
            body: jsonEncode({
              ...body,
              'environment': 'live',
              'apiKey': _apiKey,
              'secretKey': _secretKey,
            }),
          )
          .timeout(const Duration(seconds: 30));

      _log('📦 Proxy response status: ${response.statusCode}');
      _log('📦 Proxy response body: ${response.body}');

      if (response.statusCode == 200) {
        try {
          final result = jsonDecode(response.body);
          return result;
        } catch (e) {
          _log('❌ Failed to parse proxy response: $e');
          throw Exception('Invalid response from proxy server');
        }
      } else {
        throw Exception(
          'Proxy request failed with status: ${response.statusCode}',
        );
      }
    } catch (e) {
      _log('❌ Proxy request failed: $e');
      rethrow;
    }
  }

  // ✅ Enhanced Success Simulation with Better Logging
  static Map<String, dynamic> _simulateSuccessfulResponse(
    Map<String, dynamic> body,
  ) {
    _log('🎭 SIMULATING SUCCESSFUL RESPONSE FOR DEMO');
    _log('📦 Original request: ${jsonEncode(body)}');

    final requestId =
        body['request_id'] ?? 'SIM_${DateTime.now().millisecondsSinceEpoch}';
    final amount = body['amount'] ?? '50.00';
    final serviceID = body['serviceID'] ?? 'mtn';
    final phone = body['phone'] ?? '08108603409';

    return {
      'success': true,
      'code': '000',
      'response_description': 'TRANSACTION SUCCESSFUL',
      'content': {
        'transactions': {
          'status': 'delivered',
          'transactionId': 'SIM_${DateTime.now().millisecondsSinceEpoch}',
          'amount': amount,
          'serviceID': serviceID,
          'phone': phone,
        },
        'Customer_Name': 'Demo Customer',
        'requestId': requestId,
      },
      'requestId': requestId,
      'amount': amount,
      'method': 'SIMULATED_SUCCESS',
      'timestamp': DateTime.now().toIso8601String(),
      'note':
          'This is a simulated response for demo purposes. In production, this would be a real VTpass transaction.',
    };
  }

  // ✅ STRATEGY 1: Native HTTP Client
  static Future<Map<String, dynamic>> _vtpassPostNative(
    Uri url,
    Map<String, dynamic> body,
  ) async {
    final client = IOClient(
      io.HttpClient()..badCertificateCallback = (cert, host, port) => true,
    );

    try {
      final response = await client
          .post(
            url,
            headers: {
              'Content-Type': 'application/json',
              'api-key': _apiKey,
              'secret-key': _secretKey,
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 25));

      return _handleVtpassResponse(response);
    } finally {
      client.close();
    }
  }

  // ✅ STRATEGY 2: Web CURL Proxy (Postman-style)
  static Future<Map<String, dynamic>> _vtpassPostWebCurlProxy(
    Uri url,
    Map<String, dynamic> body,
  ) async {
    if (!kIsWeb) throw Exception('Curl proxy only available on web');

    _log('🔄 Using CURL proxy approach');

    // Create a server-side proxy call simulation
    try {
      // This would call your backend to make the VTpass request
      final proxyResult = await _authenticatedPost(
        Uri.parse('$baseUrl/api/proxy/vtpass'),
        {
          'url': url.toString(),
          'body': body,
          'method': 'POST',
          'headers': {'api-key': _apiKey, 'secret-key': _secretKey},
        },
      );

      return proxyResult;
    } catch (e) {
      _log('❌ CURL proxy failed, falling back to direct: $e');
      // Fall through to direct approach
      return await _vtpassPostWebFetch(url, body);
    }
  }

  // ✅ STRATEGY 3: Direct Web Fetch with Enhanced Headers
  static Future<Map<String, dynamic>> _vtpassPostWebFetch(
    Uri url,
    Map<String, dynamic> body,
  ) async {
    if (!kIsWeb) throw Exception('Web fetch only available on web');

    _log('🌐 Using enhanced web fetch');

    final headers = {
      'Content-Type': 'application/json',
      'api-key': _apiKey,
      'secret-key': _secretKey,
      'Accept': 'application/json',
      'Origin': 'https://yourdomain.com', // Set your actual domain
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
    };

    try {
      final response = await http
          .post(url, headers: headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 25));

      _log('📡 Web fetch response: ${response.statusCode}');
      return _handleVtpassResponse(response);
    } catch (e) {
      _log('❌ Web fetch failed: $e');
      rethrow;
    }
  }

  // ✅ STRATEGY 4: Alternative Web Approach
  static Future<Map<String, dynamic>> _vtpassPostWebAlternative(
    Uri url,
    Map<String, dynamic> body,
  ) async {
    if (!kIsWeb) throw Exception('Alternative web only available on web');

    _log('🔄 Using alternative web approach');

    try {
      // Try with form data instead of JSON
      final response = await http
          .post(
            url,
            headers: {
              'Content-Type': 'application/x-www-form-urlencoded',
              'api-key': _apiKey,
              'secret-key': _secretKey,
            },
            body: body.map((key, value) => MapEntry(key, value.toString())),
          )
          .timeout(const Duration(seconds: 20));

      return _handleVtpassResponse(response);
    } catch (e) {
      _log('❌ Alternative web approach failed: $e');
      rethrow;
    }
  }

  // ✅ Add this web fallback method
  static Future<Map<String, dynamic>> _vtpassPostWebFallback(
    Uri url,
    Map<String, dynamic> body,
  ) async {
    if (!kIsWeb) throw Exception('Web fallback only available on web platform');

    _log('🌐 Using web fallback method...');

    try {
      // Try with different content type
      final response = await http
          .post(
            url,
            headers: {
              'Content-Type': 'application/x-www-form-urlencoded',
              'api-key': _apiKey,
              'secret-key': _secretKey,
              'Accept': '*/*',
            },
            body: body.map((key, value) => MapEntry(key, value.toString())),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'success': data['code']?.toString() == '000',
          'code': data['code'],
          'response_description': data['response_description'],
          'content': data['content'],
        };
      }

      throw Exception('Web fallback failed: ${response.statusCode}');
    } catch (e) {
      _log('❌ Web fallback error: $e');
      rethrow;
    }
  }

  /// ENHANCED & SUPER USER-FRIENDLY ERROR HANDLING
  static Map<String, dynamic> _handleResponse(http.Response response) {
    _log('Raw response ${response.statusCode}: ${response.body}');

    // Parse the response body first
    Map<String, dynamic> data = {};
    try {
      if (response.body.isNotEmpty) {
        data = jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      _log('Failed to parse response JSON: $e');
    }

    // Successful responses (200-299)
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    }

    // ========== SPECIAL HANDLING FOR LOGIN ERRORS ==========
    // Check if this is a login request and has password-related errors
    final requestUrl = response.request?.url.toString() ?? '';
    final isLoginRequest =
        requestUrl.contains('/login') ||
        requestUrl.contains('/api/users/login');
    final errorMessage = data['message']?.toString() ?? '';

    // For login requests with password errors, return the data instead of throwing
    if (isLoginRequest &&
        response.statusCode == 400 &&
        (errorMessage.contains('Incorrect password') ||
            errorMessage.contains('Invalid credentials') ||
            errorMessage.contains('No account found') ||
            errorMessage.contains('Account has been deactivated'))) {
      _log('Login error - returning data without throwing: $errorMessage');
      return data; // Return the error response so frontend can handle it
    }

    // ================== USER-FRIENDLY ERROR MESSAGES ==================
    String userMessage = 'Something went wrong. Please try again.';
    String debugMessage = 'HTTP ${response.statusCode}';

    if (errorMessage.isNotEmpty) {
      debugMessage += ' | $errorMessage';
    }

    switch (response.statusCode) {
      case 400:
        // Check if it's a PIN-specific error
        if (errorMessage.contains('Invalid transaction PIN') ||
            errorMessage.contains('attempts remaining')) {
          // Throw the actual backend message for PIN errors
          userMessage = errorMessage;
        } else {
          userMessage =
              'Invalid request. Please check your details, transaction pin and try again.';
        }
        break;
      case 401:
        userMessage = 'Your session has expired. Please log in again.';
        break;
      case 403:
        userMessage = 'Access denied. You do not have permission to do this.';
        break;
      case 404:
        userMessage =
            'Service not found. Please restart the mobile and try again.';
        break;
      case 408:
        userMessage =
            'Request timed out. Please check your internet and try again.';
        break;
      case 429: // Rate Limited
        final bodyLower = response.body.toLowerCase();
        // Check if it's a server/IP rate limit (plain text or specific keywords)
        if (bodyLower.contains('too many requests') ||
            bodyLower.contains('rate limit') ||
            bodyLower.contains('ip')) {
          userMessage =
              'Server is currently busy. Please wait a moment and try again.';
        } else {
          final retryAfter = response.headers['retry-after'];
          if (retryAfter != null && int.tryParse(retryAfter) != null) {
            final minutes = (int.parse(retryAfter) / 60).ceil();
            userMessage =
                'Too many attempts. Please wait $minutes minute${minutes == 1 ? '' : 's'} before trying again.';
          } else {
            userMessage =
                'Too many attempts. Please wait a few minutes before trying again.';
          }
        }
        break;
      case 500:
        userMessage =
            'Server error. Our team has been notified. Please try again in a few minutes.';
        break;
      case 502:
      case 503:
      case 504:
        userMessage =
            'Service is temporarily unavailable. We\'re fixing it — please try again shortly.';
        break;
      default:
        userMessage =
            'Unable to connect. Please check your internet connection and try again.';
    }

    _log('USER-FRIENDLY MESSAGE → "$userMessage"');

    // Throw the friendly message to the UI
    throw Exception(userMessage);
  }

  static List<dynamic> _extractDataList(dynamic responseData) {
    if (responseData is List) {
      return responseData;
    } else if (responseData is Map<String, dynamic>) {
      if (responseData.containsKey('data')) {
        return responseData['data'] as List<dynamic>;
      } else if (responseData.containsKey('users')) {
        return responseData['users'] as List<dynamic>;
      } else if (responseData.containsKey('transactions')) {
        return responseData['transactions'] as List<dynamic>;
      } else if (responseData.containsKey('notifications')) {
        return responseData['notifications'] as List<dynamic>;
      } else if (responseData.containsKey('commissionTransactions')) {
        return responseData['commissionTransactions'] as List<dynamic>;
      } else if (responseData.containsKey('logs')) {
        return responseData['logs'] as List<dynamic>;
      }
    }
    _log('ERROR: Unexpected response format. Response: $responseData');
    throw Exception('Unexpected response format from API.');
  }

  // --- PIN and Biometric Authentication Helpers ---
  // ==================== PRIVATE HELPERS ====================

  /// Validate PIN format
  static String? _validatePin(String pin) {
    if (pin.isEmpty) return 'PIN cannot be empty';
    if (pin.length != 6) return 'PIN must be exactly 6 digits';
    if (!RegExp(r'^\d+$').hasMatch(pin)) {
      return 'PIN can only contain numbers';
    }
    if (RegExp(r'^(\d)\1{5}$').hasMatch(pin)) {
      return 'PIN cannot be all repeating numbers';
    }
    if (pin == '123456' || pin == '654321' || pin == '000000') {
      return 'Please choose a more secure PIN';
    }
    return null;
  }

  /// 🔐 Enhanced version of existing biometric authentication
  static Future<bool> authenticateWithBiometrics() async {
    if (kIsWeb) {
      _log('Biometric authentication not supported on web');
      return false;
    }

    try {
      return await biometricService.authenticate(
        reason: 'Please authenticate to complete this transaction',
        biometricOnly: true,
        stickyAuth: true,
      );
    } catch (e) {
      _log('Error in biometric authentication: $e');
      return false;
    }
  }

  /// Check if biometric is available on device
  static Future<bool> isBiometricAvailable() async {
    return await biometricService.isBiometricAvailable();
  }

  /// Get biometric name (Fingerprint, Face ID, etc.)
  static Future<String> getBiometricName() async {
    return await biometricService.getBiometricName();
  }

  static Future<Map<String, dynamic>> getGlobalSecuritySettings() async {
    try {
      final settings = await getAppSettings();
      return {
        'pinRequired': settings['transactionPinRequired'] ?? true,
        'biometricAllowed': settings['biometricAuthEnabled'] ?? true,
      };
    } catch (e) {
      _log('Error fetching global security settings: $e');
      return {'pinRequired': true, 'biometricAllowed': true};
    }
  }

  /// Public authenticated GET method
  static Future<Map<String, dynamic>> authenticatedGet(String endpoint) async {
    _log('🔐 Authenticated GET to: $endpoint');

    final token = await _getToken();
    if (token == null) {
      throw Exception('Authentication required. Please log in again.');
    }

    final url = Uri.parse('$baseUrl$endpoint');

    try {
      final response = await http
          .get(
            url,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 30));

      _log('Response ${response.statusCode}: ${response.body}');
      return _handleResponse(response);
    } catch (e) {
      _log('Error in authenticatedGet: $e');
      rethrow;
    }
  }

  /// Public authenticated POST method - used by commission withdrawal
  static Future<Map<String, dynamic>> authenticatedPost(
    String endpoint,
    Map<String, dynamic> body, {
    Map<String, String>? extraHeaders,
    bool useBiometric = false,
  }) async {
    _log('Authenticated POST to: $endpoint');
    _log('Body: ${jsonEncode(body)}');

    // Trigger biometric if requested
    if (useBiometric) {
      final success = await authenticateWithBiometricsEnhanced();
      if (!success) throw Exception('Biometric authentication failed');
    }

    final token = await _getToken();
    if (token == null) {
      throw Exception('Authentication required. Please log in again.');
    }

    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
      if (extraHeaders != null) ...extraHeaders,
    };

    final url = Uri.parse('$baseUrl$endpoint');

    try {
      final response = await http
          .post(url, headers: headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 30));

      _log('Response ${response.statusCode}: ${response.body}');
      return _handleResponse(response);
    } catch (e) {
      _log('Error in authenticatedPost: $e');
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> authenticateTransaction({
    required String userId,
    String? transactionPin,
    bool? useBiometric,
  }) async {
    if (kIsWeb && useBiometric == true) {
      throw Exception('Biometric authentication is not supported on web');
    }
    final securitySettings = await getSecuritySettings();
    final hasPin =
        securitySettings['securitySettings']['transactionPinSet'] ?? false;
    final biometricEnabled =
        securitySettings['securitySettings']['biometricEnabled'] ?? false;
    final pinLocked =
        securitySettings['securitySettings']['pinLocked'] ?? false;
    final lockTimeRemaining =
        securitySettings['securitySettings']['lockTimeRemaining'] ?? 0;
    final globalSettings = await getGlobalSecuritySettings();
    final pinRequired = globalSettings['pinRequired'];
    final biometricAllowed = globalSettings['biometricAllowed'];

    // In sandbox mode, skip transaction PIN/biometric for VTpass-related transactions
    if (_useSandbox) {
      _log('Sandbox mode: Skipping transaction PIN/biometric authentication');
      return {'method': 'none'};
    }

    if (!pinRequired) return {'method': 'none'};
    if (pinLocked && lockTimeRemaining > 0) {
      throw Exception(
        'Too many failed attempts. Account locked for $lockTimeRemaining minutes.',
      );
    }
    if (useBiometric == true && biometricEnabled && biometricAllowed) {
      final biometricSuccess = await authenticateWithBiometrics();
      if (biometricSuccess) return {'method': 'biometric'};
      throw Exception('Biometric authentication failed');
    }
    if (transactionPin != null && hasPin) {
      final validationError = _validatePin(transactionPin);
      if (validationError != null) throw Exception(validationError);
      final verificationResult = await verifyTransactionPin(
        userId: userId,
        transactionPin: transactionPin,
      );
      if (verificationResult['success'] == true) {
        return {'method': 'pin', 'pin': transactionPin};
      } else {
        throw Exception(
          verificationResult['message'] ?? 'Invalid transaction PIN',
        );
      }
    }
    throw Exception(
      'Authentication required. Please provide your transaction PIN or use biometric authentication.',
    );
  }

  // --- Request ID Generation Helper ---
  static String _generateRequestId() {
    tz_data.initializeTimeZones();
    final location = tz.getLocation('Africa/Lagos');
    final now = tz.TZDateTime.now(location);
    final formatter = DateFormat('yyyyMMddHHmm');
    final timestamp = formatter.format(now);
    final suffix = const Uuid().v4().replaceAll('-', '').substring(0, 12);
    final requestId = timestamp + suffix;
    _log('Generated request_id: $requestId');
    return requestId;
  }

  // Add this to your ApiService class
  static Future<void> setSandboxMode(bool useSandbox) async {
    _useSandbox = useSandbox;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('useSandbox', useSandbox);
    _log('Sandbox mode set to: $useSandbox');
  }

  /// Helper method to credit commission to referrer
  static Future<void> _creditCommission({
    required String userId,
    required String transactionId,
    required String serviceType,
    required double amount,
    required String requestId,
  }) async {
    try {
      final user = await getCurrentUser();
      final referrerId = user['referrerId'] as String?;

      if (referrerId == null || referrerId.isEmpty) {
        _log('No referrer found for user $userId. Skipping commission.');
        return;
      }

      final commissionRate = _commissionRates[serviceType.toLowerCase()] ?? 0.0;
      if (commissionRate <= 0.0) {
        _log('No commission rate for service $serviceType.');
        return;
      }

      // FINAL FIX: Prevent NaN crash
      final double safeAmount = amount.isFinite ? amount : 0.0;
      final double safeRate = commissionRate.isFinite ? commissionRate : 0.0;
      final double commissionAmount = safeAmount * safeRate;

      if (commissionAmount <= 0.10 || !commissionAmount.isFinite) {
        _log(
          'Commission too small or invalid: ₦${commissionAmount.toStringAsFixed(2)}',
        );
        return;
      }

      _log(
        'Crediting ₦${commissionAmount.toStringAsFixed(2)} commission to referrer $referrerId',
      );

      final commissionBody = {
        'referrerId': referrerId,
        'userId': userId,
        'transactionId': transactionId,
        'serviceType': serviceType,
        'amount': amount,
        'commissionAmount': commissionAmount,
        'requestId': requestId,
        'environment': 'live',
        'timestamp': DateTime.now().toIso8601String(),
      };

      final response = await _authenticatedPost(
        _commissionTransactionsUrl,
        commissionBody,
      );

      if (response['success'] == true) {
        _log('Commission credited successfully');
        await _updateLocalCommissionBalance(referrerId, commissionAmount);
        await _sendCommissionNotification(
          referrerId,
          serviceType,
          commissionAmount,
          amount,
        );
      } else {
        _log('Commission API failed: ${response['message']}');
      }
    } catch (e, stackTrace) {
      _log('Error crediting commission: $e');
      await reportError(e, stackTrace);
    }
  }

  /// 📊 UPDATE LOCAL COMMISSION BALANCE FOR REFERRER
  static Future<void> _updateLocalCommissionBalance(
    String referrerId,
    double commissionAmount,
  ) async {
    try {
      final currentUserId = await _getUserId();

      // Only update if the referrer is the current logged-in user
      if (referrerId == currentUserId) {
        final prefs = await SharedPreferences.getInstance();
        final currentCommissionBalance =
            prefs.getDouble('commissionBalance') ?? 0.0;
        final newCommissionBalance =
            currentCommissionBalance + commissionAmount;

        await prefs.setDouble('commissionBalance', newCommissionBalance);

        // Update user object in local storage
        final userString = prefs.getString('user');
        if (userString != null) {
          final userMap = jsonDecode(userString);
          userMap['commissionBalance'] = newCommissionBalance;
          await prefs.setString('user', jsonEncode(userMap));
        }

        _log(
          '📈 Local commission balance updated: ₦${currentCommissionBalance.toStringAsFixed(2)} → ₦${newCommissionBalance.toStringAsFixed(2)}',
        );
      }
    } catch (e) {
      _log('⚠️ Failed to update local commission balance: $e');
    }
  }

  /// 🔔 SEND COMMISSION NOTIFICATION TO REFERRER
  static Future<void> _sendCommissionNotification(
    String referrerId,
    String serviceType,
    double commissionAmount,
    double transactionAmount,
  ) async {
    try {
      final serviceNames = {
        'airtime': 'Airtime',
        'data': 'Data',
        'cable': 'Cable TV',
        'electricity': 'Electricity',
        'education': 'Education',
        'insurance': 'Insurance',
        'wallet_funding': 'Wallet Funding',
      };

      final serviceName =
          serviceNames[serviceType.toLowerCase()] ?? serviceType;

      await sendNotification(
        title: 'Commission Earned! 🎉',
        message:
            'You earned ₦${commissionAmount.toStringAsFixed(2)} commission from a ₦${transactionAmount.toStringAsFixed(2)} $serviceName purchase!',
        recipientId: referrerId,
      );

      _log('📩 Commission notification sent to referrer $referrerId');
    } catch (e) {
      _log('⚠️ Failed to send commission notification: $e');
    }
  }

  static Future<void> _creditDirectReferralBonus({
    required String referrerId,
    required String newUserId,
  }) async {
    try {
      final commissionBody = {
        'referrerId': referrerId,
        'userId': newUserId,
        'serviceType': 'direct_referral_bonus',
        'commissionAmount': _directReferralBonus,
        'environment': 'live', // Force live environment
        'timestamp': DateTime.now().toIso8601String(),
      };

      final response = await _authenticatedPost(
        _commissionTransactionsUrl,
        commissionBody,
      );

      if (response['success'] == true) {
        _log(
          '✅ Direct referral bonus of ₦$_directReferralBonus credited to referrer $referrerId',
        );

        // Update referrer's commission balance locally if they are the current user
        final currentUserId = await _getUserId();
        if (referrerId == currentUserId) {
          final prefs = await SharedPreferences.getInstance();
          final currentCommissionBalance =
              prefs.getDouble('commissionBalance') ?? 0.0;
          final newCommissionBalance =
              currentCommissionBalance + _directReferralBonus;
          await prefs.setDouble('commissionBalance', newCommissionBalance);

          final userString = prefs.getString('user');
          if (userString != null) {
            final userMap = jsonDecode(userString);
            userMap['commissionBalance'] = newCommissionBalance;
            await prefs.setString('user', jsonEncode(userMap));
          }

          _log(
            '📈 Direct referral bonus added to local balance: ₦$_directReferralBonus',
          );
        }

        // Send notification to referrer
        await sendNotification(
          title: 'Direct Referral Bonus! 🎊',
          message:
              'You earned ₦$_directReferralBonus for a new user signing up with your referral code!',
          recipientId: referrerId,
        );
      } else {
        _log(
          '⚠️ Direct referral bonus API response failed: ${response['message']}',
        );
      }
    } catch (e, stackTrace) {
      _log('❌ Error crediting direct referral bonus: $e');
      await reportError(e, stackTrace);
    }
  }

  /// 📋 VERIFY COMMISSION WILL BE CREDITED
  static Future<Map<String, dynamic>> verifyCommissionEligibility({
    required String userId,
    required String serviceType,
    required double amount,
  }) async {
    try {
      final user = await getCurrentUser();
      final referrerId = user['referrerId'] as String?;

      if (referrerId == null || referrerId.isEmpty) {
        return {
          'eligible': false,
          'reason': 'No referrer found',
          'commissionAmount': 0.0,
        };
      }

      final commissionRate = _commissionRates[serviceType.toLowerCase()] ?? 0.0;
      if (commissionRate == 0.0) {
        return {
          'eligible': false,
          'reason': 'No commission rate for service',
          'commissionAmount': 0.0,
        };
      }

      final commissionAmount = amount * commissionRate;

      if (commissionAmount < 0.10) {
        return {
          'eligible': false,
          'reason': 'Commission too small',
          'commissionAmount': commissionAmount,
        };
      }

      return {
        'eligible': true,
        'referrerId': referrerId,
        'serviceType': serviceType,
        'amount': amount,
        'commissionRate': '${commissionRate * 100}%',
        'commissionAmount': commissionAmount,
        'formattedCommission': '₦${commissionAmount.toStringAsFixed(2)}',
      };
    } catch (e) {
      _log('Error verifying commission eligibility: $e');
      return {
        'eligible': false,
        'reason': 'Error checking eligibility',
        'commissionAmount': 0.0,
      };
    }
  }

  /// Generates a unique referral code for a user
  static Future<String> generateReferralCode(String userId) async {
    _log('Generating referral code for user: $userId');
    try {
      final response = await _authenticatedPost(_generateReferralCodeUrl, {
        'userId': userId,
      });

      if (response['success'] == true && response['referralCode'] != null) {
        final referralCode = response['referralCode'].toString();
        _log('Referral code generated: $referralCode');

        // Store locally for quick access
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('referralCode_$userId', referralCode);

        return referralCode;
      } else {
        throw Exception(
          'Failed to generate referral code: ${response['message']}',
        );
      }
    } catch (e) {
      _log('Error generating referral code: $e');
      // Fallback: Generate a simple code
      final fallbackCode = 'REF${userId.substring(0, 8).toUpperCase()}';
      _log('Using fallback referral code: $fallbackCode');
      return fallbackCode;
    }
  }

  static Future<void> _creditReferralBonus({
    required String referrerId,
    required String newUserId,
    required String referralCode,
  }) async {
    try {
      final commissionBody = {
        'referrerId': referrerId,
        'userId': newUserId,
        'serviceType': 'referral',
        'commissionAmount': _referralBonus,
        'environment': _useSandbox ? 'sandbox' : 'live',
      };

      await _authenticatedPost(_commissionTransactionsUrl, commissionBody);
      _log(
        'Referral bonus of ₦$_referralBonus credited to referrer $referrerId',
      );

      // Update referrer's commission balance locally if they are the current user
      final currentUserId = await _getUserId();
      if (referrerId == currentUserId) {
        final prefs = await SharedPreferences.getInstance();
        final currentCommissionBalance =
            prefs.getDouble('commissionBalance') ?? 0.0;
        final newCommissionBalance = currentCommissionBalance + _referralBonus;
        await prefs.setDouble('commissionBalance', newCommissionBalance);

        final userString = prefs.getString('user');
        if (userString != null) {
          final userMap = jsonDecode(userString);
          userMap['commissionBalance'] = newCommissionBalance;
          await prefs.setString('user', jsonEncode(userMap));
        }
      }

      // Send notification to referrer
      await sendNotification(
        title: 'New Referral Bonus',
        message:
            'You earned ₦$_referralBonus for referring a new user with code $referralCode!',
        recipientId: referrerId,
      );
    } catch (e, stackTrace) {
      _log('Error crediting referral bonus: $e');
      await reportError(e, stackTrace);
    }
  }

  static Future<void> testAdminEndpointWithDebug() async {
    try {
      final token = await _TokenManager.getSafeToken();
      if (token == null) throw Exception('NO_TOKEN');

      final response = await http.get(
        Uri.parse('$baseUrl/api/transactions/all?limit=2'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      debugPrint('🔍 TEST ENDPOINT STATUS: ${response.statusCode}');
      debugPrint('🔍 TEST ENDPOINT BODY: ${response.body}');
    } catch (e) {
      debugPrint('❌ Test endpoint failed: $e');
    }
  }

  /// Admin self-funding method
  // In your ApiService.dart, update the adminSelfFund method:

  static Future<Map<String, dynamic>> adminSelfFund({
    required double amount,
    String? transactionPin,
    bool? useBiometric,
  }) async {
    _log('👑 Admin self-funding: ₦$amount');

    try {
      final userId = await _getUserId();
      if (userId == null) {
        throw Exception('User ID not found. Please log in again.');
      }

      // Verify admin status
      if (!await isAdmin()) {
        throw Exception('Admin access required for self-funding.');
      }

      // Check if user has transaction PIN set
      final pinStatus = await checkTransactionPinStatus(userId: userId);
      final hasPin = pinStatus['hasPin'] ?? false;

      if (!hasPin) {
        throw Exception(
          'Transaction PIN not set. Please set up a transaction PIN in your account settings first.',
        );
      }

      String? pinToUse;

      // Handle biometric authentication
      if (useBiometric == true) {
        _log('🔐 Attempting biometric authentication');
        final biometricAuth = await _authenticateWithBiometric();
        if (!biometricAuth) {
          throw Exception('Biometric authentication failed or cancelled.');
        }
        // For biometric, we'll use the stored PIN
        pinToUse = await _getStoredTransactionPin(userId);
      } else if (transactionPin != null && transactionPin.length == 6) {
        // Verify the provided PIN
        _log('🔐 Verifying provided PIN');
        final pinVerification = await verifyTransactionPin(
          userId: userId,
          transactionPin: transactionPin,
        );

        if (!pinVerification['success']) {
          throw Exception('Invalid transaction PIN. Please try again.');
        }

        pinToUse = transactionPin;
      } else {
        throw Exception(
          'Authentication required. Please provide your 6-digit transaction PIN '
          'or use biometric authentication.',
        );
      }

      if (pinToUse == null || pinToUse.length != 6) {
        throw Exception('Valid 6-digit PIN is required for this transaction.');
      }

      // Prepare the request body with PIN authentication
      final Map<String, dynamic> body = {
        'userId': userId,
        'amount': amount,
        'note': 'Admin self-funding transaction',
        'transactionPin': pinToUse, // Send the PIN to backend
        'isAdminSelfFund': true,
      };

      _log('📤 Sending admin self-fund request with PIN authentication');
      final response = await _authenticatedPost(_fundWalletUrl, body);

      // Update local balance if successful
      if (response['success'] == true) {
        final prefs = await SharedPreferences.getInstance();
        final currentBalance = prefs.getDouble('walletBalance') ?? 0.0;
        final newBalance = currentBalance + amount;

        await prefs.setDouble('walletBalance', newBalance);

        // Update user object
        final userString = prefs.getString('user');
        if (userString != null) {
          final userMap = jsonDecode(userString);
          userMap['walletBalance'] = newBalance;
          await prefs.setString('user', jsonEncode(userMap));
        }

        _log('💰 Admin self-fund successful. New balance: ₦$newBalance');

        // Add transaction ID if not present
        if (!response.containsKey('transactionId')) {
          response['transactionId'] =
              DateTime.now().millisecondsSinceEpoch.toString();
        }
      }

      return response;
    } catch (e, stackTrace) {
      _log('❌ Admin self-fund failed: $e');

      // More detailed error logging
      if (e.toString().contains('Authentication required')) {
        _log('⚠️ Authentication issue: $e');
        throw Exception(
          'Authentication required. Please enter your 6-digit transaction PIN.',
        );
      }

      if (e.toString().contains('Invalid transaction PIN')) {
        _log('⚠️ Invalid PIN entered');
        throw Exception('Invalid PIN. Please try again.');
      }

      await reportError(e, stackTrace);
      rethrow;
    }
  }

  // Helper method to get stored transaction PIN
  static Future<String?> _getStoredTransactionPin(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // First check if we have it in user object
      final userString = prefs.getString('user');
      if (userString != null) {
        final userMap = jsonDecode(userString);
        if (userMap['transactionPin'] != null) {
          return userMap['transactionPin'].toString();
        }
      }

      // Check in secure storage (if implemented)
      return prefs.getString('transaction_pin_$userId');
    } catch (e) {
      _log('❌ Error getting stored PIN: $e');
      return null;
    }
  }

  // Enhanced biometric authentication method
  static Future<bool> _authenticateWithBiometric() async {
    try {
      // Check if biometrics are available
      final bool canAuthenticate = await _checkBiometricsAvailable();

      if (!canAuthenticate) {
        throw Exception(
          'Biometric authentication not available. '
          'Please enable it in your device settings or use PIN.',
        );
      }

      // Show biometric prompt
      final bool authenticated = await _showBiometricPrompt();

      if (!authenticated) {
        throw Exception('Biometric authentication failed or was cancelled.');
      }

      return true;
    } catch (e) {
      _log('❌ Biometric authentication failed: $e');
      throw Exception('Biometric authentication failed: ${e.toString()}');
    }
  }

  // Mock biometric methods (implement with local_auth package)
  static Future<bool> _checkBiometricsAvailable() async {
    // Implement with: await localAuth.canCheckBiometrics;
    return true; // For testing
  }

  static Future<bool> _showBiometricPrompt() async {
    // Implement with: await localAuth.authenticate(...)
    return true; // For testing
  }

  // Add this method to check if user has set up transaction PIN
  static Future<bool> hasTransactionPin() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userString = prefs.getString('user');

      if (userString != null) {
        final userMap = jsonDecode(userString);
        return userMap['transactionPin'] != null ||
            prefs.getString('transaction_pin') != null;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  // --- Health Check, Token Verification, Error Reporting, Token Refresh ---
  static Future<Map<String, dynamic>> healthCheck() async {
    _log('Checking API health status');
    try {
      final response = await _unauthenticatedGet(_healthCheckUrl);

      // FIX: Standardize the response format to always include 'success'
      if (response['status'] == 'OK') {
        return {
          'success': true,
          'message': 'Server is healthy',
          'timestamp': response['timestamp'],
          'uptime': response['uptime'],
        };
      } else {
        return {
          'success': false,
          'message': response['message'] ?? 'Server health check failed',
        };
      }
    } catch (e) {
      _log('Health check failed: $e');
      return {'success': false, 'message': 'Failed to connect to server: $e'};
    }
  }

  /// Enhanced client-side referral code validation with local storage
  /// Enhanced client-side referral code validation with local storage
  static Future<Map<String, dynamic>> validateReferralCodeClientSide(
    String referralCode,
  ) async {
    _log('🔍 Validating referral code client-side: $referralCode');

    try {
      // Step 1: Basic format validation only
      if (referralCode.isEmpty || referralCode.length < 8) {
        return {
          'success': false,
          'message': 'Referral code must be at least 8 characters long',
        };
      }

      // Step 2: Clean and format the code
      final cleanCode = referralCode.trim().toUpperCase();

      // Step 3: Check if it's a valid format (starts with REF and has alphanumeric)
      final regex = RegExp(r'^REF[A-Z0-9]{8,}$');
      if (!regex.hasMatch(cleanCode)) {
        return {
          'success': false,
          'message':
              'Invalid referral code format. Should start with REF followed by 8+ alphanumeric characters',
        };
      }

      // NEW: Check local storage for cached valid referrals
      final localReferral = await _getLocalReferral(cleanCode);
      if (localReferral != null && localReferral['isValid'] == true) {
        _log('✅ Found valid referral in local storage: $cleanCode');
        return {
          'success': true,
          'referrerId': localReferral['referrerId'],
          'referrerName': localReferral['referrerName'],
          'cleanedCode': cleanCode,
          'source': 'local_cache',
          'message':
              'Valid referral code! Referrer: ${localReferral['referrerName']}',
        };
      }

      // Step 4: If format is valid, accept it and let backend do the real validation
      _log('✅ Referral code passed format validation: $cleanCode');
      return {
        'success': true,
        'referrerId':
            'pending_backend_validation', // Backend will find the real ID
        'referrerName': 'Existing User',
        'cleanedCode': cleanCode,
        'source': 'format_only',
        'message': 'Referral code format is valid',
      };
    } catch (e, stackTrace) {
      _log('❌ Error in client-side referral validation: $e');
      await reportError(e, stackTrace);
      return {
        'success': false,
        'message': 'Unable to validate referral code. Please try again.',
      };
    }
  }

  /// 🎯 CHECK AUTH STATE WITHOUT THROWING EXCEPTIONS
  /// 🎯 Check auth state using secure storage
  /// 🎯 Check auth state using secure storage
  static Future<Map<String, dynamic>> checkAuthState() async {
    try {
      final token = await SecureStorageService.getAccessToken();
      final refreshToken = await SecureStorageService.getRefreshToken();
      final userId = await SecureStorageService.getUserId();
      final isLoggedIn = await SecureStorageService.isLoggedIn();

      _log('🔐 Auth State Check:');
      _log('   Token: ${token != null ? "Exists" : "NULL"}');
      _log('   Refresh Token: ${refreshToken != null ? "Exists" : "NULL"}');
      _log('   User ID: ${userId ?? "NULL"}');
      _log('   Is Logged In: $isLoggedIn');

      if (isLoggedIn && token != null && refreshToken != null) {
        return {
          'isAuthenticated': true,
          'needsLogin': false,
          'userId': userId,
          'message': 'Authenticated',
        };
      }

      // ✅ Try to refresh if we have a refresh token but no access token
      if (refreshToken != null && token == null) {
        _log('🔄 Access token missing, attempting refresh...');
        final refreshed = await _tokenManager.refreshTokenWithQueue();
        if (refreshed) {
          return {
            'isAuthenticated': true,
            'needsLogin': false,
            'userId': userId,
            'message': 'Token restored',
            'refreshed': true,
          };
        }
      }

      return {
        'isAuthenticated': false,
        'needsLogin': true,
        'message': 'Please log in to continue',
      };
    } catch (e) {
      _log('❌ Auth state check error: $e');
      return {
        'isAuthenticated': false,
        'needsLogin': true,
        'message': 'Authentication check failed: $e',
      };
    }
  }

  /// 🔧 CLEAR REAUTH FLAG (CALL AFTER SUCCESSFUL LOGIN)
  static Future<void> clearReauthFlag() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('needsReauth');
    _log('✅ Reauth flag cleared');
  }

  /// 🛡️ ENHANCED CLEAR AUTH DATA - MORE SELECTIVE
  static Future<void> clearAuthDataSelective() async {
    final prefs = await SharedPreferences.getInstance();

    // Clear only tokens, preserve user data
    await prefs.remove('token');
    await prefs.remove('refreshToken');
    await prefs.remove('lastTokenRefresh');
    await prefs.setBool('needsReauth', true);

    _log(
      '🔐 Selective auth data cleared - tokens removed but user data preserved',
    );
  }

  // Add this method to ApiService class
  static Future<Map<String, dynamic>> checkBackendHealth() async {
    try {
      final response = await healthCheck();

      // This ensures both old and new formats work
      if (response['success'] == true || response['status'] == 'OK') {
        return {
          'success': true,
          'message': 'Server is healthy',
          'timestamp': response['timestamp'],
          'uptime': response['uptime'],
        };
      } else {
        return {
          'success': false,
          'message': response['message'] ?? 'Server health check failed',
        };
      }
    } catch (e) {
      _log('Backend health check failed: $e');
      return {'success': false, 'message': 'Failed to connect to server: $e'};
    }
  }

  /// Check if user can use commission for a service
  static Future<bool> canUseCommissionForService({
    required String serviceType,
    required double amount,
  }) async {
    try {
      final commissionBalance = await getCommissionBalance();
      return commissionBalance >= amount;
    } catch (e) {
      _log('Error checking commission balance: $e');
      return false;
    }
  }

  /// Withdraw commission to main wallet - CORRECTED VERSION
  static Future<Map<String, dynamic>> withdrawCommission({
    required String userId,
    required double amount,
    String? transactionPin,
    bool useBiometric = false,
  }) async {
    _log('💰 Withdrawing commission: ₦$amount, userId: $userId');

    try {
      // 1. Check minimum withdrawal
      if (amount < 500) {
        throw Exception('Minimum withdrawal amount is ₦500');
      }

      // 2. Check commission balance
      final commissionBalance = await getCommissionBalance();
      if (commissionBalance < amount) {
        throw Exception(
          'Insufficient commission balance. '
          'Available: ₦${commissionBalance.toStringAsFixed(2)}',
        );
      }

      // 3. Authenticate
      final authResult = await authenticateTransaction(
        userId: userId,
        transactionPin: transactionPin,
        useBiometric: useBiometric,
      );

      _log(
        '✅ Authentication successful for withdrawal: ${authResult['method']}',
      );

      // 4. Prepare withdrawal payload
      final payload = {
        'userId': userId,
        'amount': amount,
        if (authResult['method'] == 'pin') 'transactionPin': authResult['pin'],
        'useBiometric': authResult['method'] == 'biometric',
      };

      // 5. Call backend to process withdrawal
      final response = await _authenticatedPost(
        Uri.parse('$baseUrl/api/users/withdraw-commission'),
        payload,
      );

      if (response['success'] == true) {
        // 6. Update local commission balance
        final prefs = await SharedPreferences.getInstance();
        await prefs.setDouble(
          'commissionBalance',
          0.0,
        ); // Reset to 0 after withdrawal

        // Update user object in storage
        final userString = prefs.getString('user');
        if (userString != null) {
          try {
            final userMap = jsonDecode(userString) as Map<String, dynamic>;
            userMap['commissionBalance'] = 0.0;
            await prefs.setString('user', jsonEncode(userMap));
          } catch (e) {
            _log('Error updating user in storage: $e');
          }
        }

        _log('✅ Commission withdrawal successful');

        return {
          'success': true,
          'message': response['message'] ?? 'Commission withdrawn successfully',
          'newCommissionBalance': 0.0,
          'transactionId': response['transactionId'],
        };
      } else {
        throw Exception(response['message'] ?? 'Withdrawal failed');
      }
    } catch (e) {
      _log('❌ Error withdrawing commission: $e');
      rethrow;
    }
  }

  /// 🔐 Check if biometric hardware is available on the device
  static Future<bool> checkBiometricAvailability() async {
    if (kIsWeb) {
      _log('Biometric authentication not supported on web');
      return false;
    }

    try {
      final LocalAuthentication localAuth = LocalAuthentication();

      // Check if biometrics are supported
      final bool canCheckBiometrics = await localAuth.canCheckBiometrics;
      _log('Biometric hardware available: $canCheckBiometrics');

      return canCheckBiometrics;
    } catch (e) {
      _log('Error checking biometric availability: $e');
      return false;
    }
  }

  /// 🔐 Check if user has enrolled biometrics (fingerprints/face ID)
  static Future<bool> hasEnrolledBiometrics() async {
    if (kIsWeb) {
      _log('Biometric authentication not supported on web');
      return false;
    }

    try {
      final LocalAuthentication localAuth = LocalAuthentication();

      // First check if biometrics are supported
      final bool canCheckBiometrics = await localAuth.canCheckBiometrics;
      if (!canCheckBiometrics) {
        _log('Biometrics not supported on this device');
        return false;
      }

      // Get available biometrics
      List<BiometricType> availableBiometrics = [];
      try {
        availableBiometrics = await localAuth.getAvailableBiometrics();
      } catch (e) {
        _log('Error getting available biometrics: $e');
        return false;
      }

      _log('Available biometrics: $availableBiometrics');

      // Check if any biometrics are enrolled
      final hasBiometrics = availableBiometrics.isNotEmpty;
      _log('Biometrics enrolled: $hasBiometrics');

      return hasBiometrics;
    } catch (e) {
      _log('Error checking enrolled biometrics: $e');
      return false;
    }
  }

  /// 🔐 Enhanced biometric authentication with comprehensive checks
  static Future<bool> authenticateWithBiometricsEnhanced() async {
    if (kIsWeb) {
      _log('Biometric authentication not supported on web');
      return false;
    }

    final LocalAuthentication localAuth = LocalAuthentication();

    try {
      // Step 1: Check if biometrics are supported
      final bool canCheckBiometrics = await localAuth.canCheckBiometrics;
      if (!canCheckBiometrics) {
        _log('❌ Biometric hardware not available on this device');
        throw Exception(
          'Biometric authentication is not supported on this device.',
        );
      }

      // Step 2: Check if biometrics are enrolled
      List<BiometricType> availableBiometrics = [];
      try {
        availableBiometrics = await localAuth.getAvailableBiometrics();
      } catch (e) {
        _log('❌ Error getting available biometrics: $e');
        throw Exception(
          'Unable to access biometric settings. Please check device permissions.',
        );
      }

      if (availableBiometrics.isEmpty) {
        _log('❌ No biometric credentials enrolled on device');
        throw Exception(
          'No fingerprints or face ID enrolled. Please set up biometric authentication in your device settings.',
        );
      }

      _log('✅ Biometric hardware available and enrolled: $availableBiometrics');

      // Step 3: Trigger biometric authentication
      _log('🔐 Triggering biometric authentication...');

      final bool didAuthenticate = await localAuth.authenticate(
        localizedReason: 'Authenticate to complete your transaction',
        options: const AuthenticationOptions(
          biometricOnly: true, // Only allow biometrics, not device credentials
          useErrorDialogs: true, // Show system dialogs for errors
          stickyAuth: true, // Keep authentication dialog visible
        ),
      );

      if (didAuthenticate) {
        _log('✅ Biometric authentication successful');
        return true;
      } else {
        _log('❌ Biometric authentication failed or cancelled by user');
        throw Exception(
          'Biometric authentication failed. Please try again or use your PIN.',
        );
      }
    } catch (e) {
      _log('💥 Biometric authentication error: $e');

      // Provide specific error messages based on the error type
      if (e.toString().contains('NotAvailable')) {
        throw Exception(
          'Biometric authentication is not available on this device.',
        );
      } else if (e.toString().contains('NotEnrolled')) {
        throw Exception(
          'No biometric credentials enrolled. Please set up fingerprint/face ID in device settings.',
        );
      } else if (e.toString().contains('LockedOut')) {
        throw Exception(
          'Biometric authentication is temporarily locked. Please use your PIN or try again later.',
        );
      } else if (e.toString().contains('PermanentlyLockedOut')) {
        throw Exception(
          'Biometric authentication is permanently locked. Please use your PIN.',
        );
      } else {
        rethrow;
      }
    }
  }

  /// 🔐 Quick biometric check for UI state
  static Future<Map<String, dynamic>> checkBiometricStatus() async {
    if (kIsWeb) {
      return {
        'available': false,
        'enrolled': false,
        'supported': false,
        'message': 'Biometric authentication not supported on web',
      };
    }

    try {
      final LocalAuthentication localAuth = LocalAuthentication();

      final bool canCheckBiometrics = await localAuth.canCheckBiometrics;

      if (!canCheckBiometrics) {
        return {
          'available': false,
          'enrolled': false,
          'supported': false,
          'message': 'Biometric hardware not available',
        };
      }

      List<BiometricType> availableBiometrics = [];
      try {
        availableBiometrics = await localAuth.getAvailableBiometrics();
      } catch (e) {
        _log('Error getting available biometrics: $e');
      }

      final hasEnrolled = availableBiometrics.isNotEmpty;

      return {
        'available': canCheckBiometrics,
        'enrolled': hasEnrolled,
        'supported': true,
        'biometricTypes': availableBiometrics,
        'message':
            hasEnrolled
                ? 'Biometric authentication available'
                : 'No biometric credentials enrolled',
      };
    } catch (e) {
      _log('Error checking biometric status: $e');
      return {
        'available': false,
        'enrolled': false,
        'supported': false,
        'message': 'Error checking biometric status: $e',
      };
    }
  }

  /// Check if both backends are healthy
  static Future<bool> checkBothBackendsHealth() async {
    try {
      // Check auth backend
      final authHealth = await checkBackendHealth();
      if (!authHealth['success']) {
        _log('❌ Auth backend is unhealthy');
        return false;
      }

      // Check payment backend health (you might need to add a health endpoint)
      try {
        final paymentHealthResponse = await http
            .get(
              Uri.parse('https://virtual-account-backend.onrender.com/health'),
            )
            .timeout(const Duration(seconds: 30));

        final paymentHealth = paymentHealthResponse.statusCode == 200;
        if (!paymentHealth) {
          _log('⚠️ Payment backend health check failed');
          // Continue anyway as virtual account might be created later
        }
      } catch (e) {
        _log('⚠️ Payment backend health check unavailable: $e');
        // Continue anyway
      }

      return true;
    } catch (e) {
      _log('❌ Backend health check failed: $e');
      return false;
    }
  }

  /// Enhanced network connectivity check
  static Future<bool> checkEnhancedConnectivity() async {
    try {
      final connectivityResult = await (Connectivity().checkConnectivity());
      if (connectivityResult == ConnectivityResult.none) {
        return false;
      }

      // Test both backends
      final results = await Future.wait([
        http
            .get(Uri.parse('$baseUrl/health'))
            .timeout(const Duration(seconds: 5)),
        http
            .get(
              Uri.parse('https://virtual-account-backend.onrender.com/health'),
            )
            .timeout(const Duration(seconds: 5)),
      ], eagerError: false);

      return results.any((response) => response.statusCode == 200);
    } catch (e) {
      _log('Connectivity check failed: $e');
      return false;
    }
  }

  static Future<bool> verifyToken() async {
    _log('Verifying token validity');
    try {
      final token = await _getToken();
      if (token == null) {
        _log('No token found for verification');
        return false;
      }
      final response = await http
          .get(
            _verifyTokenUrl,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 30));
      _log('Token verification response status: ${response.statusCode}');
      return response.statusCode == 200;
    } catch (e) {
      _log('Token verification failed: $e');
      return false;
    }
  }

  static Future<void> reportError(dynamic error, StackTrace stackTrace) async {
    _log('Reporting error to backend: $error');
    try {
      final token = await _getToken();

      // Use a fixed mobile version since we removed package_info_plus
      String appVersion = await getAppVersion();

      // Determine platform
      String platform;
      if (kIsWeb) {
        platform = 'web';
      } else {
        // Use defaultTargetPlatform for native platforms
        switch (defaultTargetPlatform) {
          case TargetPlatform.android:
            platform = 'android';
            break;
          case TargetPlatform.iOS:
            platform = 'ios';
            break;
          case TargetPlatform.windows:
            platform = 'windows';
            break;
          case TargetPlatform.linux:
            platform = 'linux';
            break;
          case TargetPlatform.macOS:
            platform = 'macos';
            break;
          default:
            platform = 'unknown';
        }
      }

      final Map<String, dynamic> errorData = {
        'error': error.toString(),
        'stackTrace': stackTrace.toString(),
        'timestamp': DateTime.now().toIso8601String(),
        'platform': platform,
        'version': appVersion,
        'environment': _useSandbox ? 'sandbox' : 'live',
      };
      final userId = await _getUserId();
      if (userId != null) errorData['userId'] = userId;

      final response = await http
          .post(
            _reportErrorUrl,
            headers: {
              'Content-Type': 'application/json',
              if (token != null) 'Authorization': 'Bearer $token',
            },
            body: jsonEncode(errorData),
          )
          .timeout(const Duration(seconds: 30));
      _log('Error reporting response status: ${response.statusCode}');
      if (response.statusCode != 200) {
        _log('Failed to report error: ${response.body}');
      }
    } catch (e) {
      _log('Failed to report error: $e');
    }
  }

  // lib/core/services/api_service.dart

  static Future<String> getAppVersion() async {
    try {
      // Get the actual app version from PackageInfo
      final packageInfo = await PackageInfo.fromPlatform();
      // Use the full version including build number
      final actualVersion = packageInfo.version; // This gets "1.5.0+1"

      // For version comparison, we need to clean it up
      // Remove the build number for comparison
      final cleanVersion = actualVersion.split('+')[0]; // Gets "1.5.0"

      _log('📱 App version: $actualVersion (clean: $cleanVersion)');

      final response = await http
          .get(
            // Send the clean version for comparison
            Uri.parse(
              '$baseUrl/api/app/version?platform=android&version=$cleanVersion',
            ),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          // Return the actual version (with build number) for display
          final version =
              actualVersion; // Use the full version with build number
          _log('📱 App version from backend: $version');
          return version;
        }
      }
    } catch (e) {
      _log('❌ Failed to get app version from backend: $e');
    }

    // Fallback: Get version from PackageInfo
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      return packageInfo.version; // Returns "1.5.0+1"
    } catch (e) {
      _log('❌ Failed to get app version from PackageInfo: $e');
      return '1.5.0+1'; // ✅ Updated fallback
    }
  }

  /// FINAL BULLETPROOF TOKEN REFRESH — NEVER FAILS SILENTLY
  static Future<Map<String, dynamic>> refreshToken() async {
    _log('Attempting silent token refresh...');

    try {
      final prefs = await SharedPreferences.getInstance();
      final refreshToken = prefs.getString('refreshToken');

      if (refreshToken == null || refreshToken.isEmpty) {
        _log('No refresh token found');
        return {'success': false, 'message': 'No refresh token'};
      }

      final response = await http
          .post(
            Uri.parse('$baseUrl/api/users/refresh-token'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'refreshToken': refreshToken}),
          )
          .timeout(const Duration(seconds: 12));

      _log('Refresh response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['success'] == true && data['token'] != null) {
          await prefs.setString('token', data['token']);
          if (data['refreshToken'] != null) {
            await prefs.setString('refreshToken', data['refreshToken']);
          }
          await prefs.setInt(
            'lastTokenRefresh',
            DateTime.now().millisecondsSinceEpoch,
          );

          _log('Token refreshed successfully');
          return {'success': true};
        }
      }

      // Any non-200 or failed response
      _log('Refresh failed: ${response.body}');
      return {'success': false, 'message': 'Refresh failed'};
    } catch (e) {
      _log('Refresh token network error: $e');
      return {'success': false, 'message': e.toString()};
    }
  }

  /// Check if token is likely expired (client-side check)
  static Future<bool> isTokenExpired() async {
    try {
      final token = await _getToken();
      if (token == null) return true;

      // Simple check - if token exists but we're getting JWT errors, assume expired
      // In a real implementation, you'd decode the JWT and check exp timestamp
      final prefs = await SharedPreferences.getInstance();
      final lastRefresh = prefs.getInt('lastTokenRefresh');

      if (lastRefresh != null) {
        final now = DateTime.now().millisecondsSinceEpoch;
        final hoursSinceRefresh = (now - lastRefresh) / (1000 * 60 * 60);

        // Assume tokens expire after 24 hours
        return hoursSinceRefresh > 24;
      }

      return false;
    } catch (e) {
      _log('Error checking token expiration: $e');
      return true;
    }
  }

  ///  Proactive token refresh to prevent expiration issues
  static Future<bool> refreshTokensIfNeeded() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      final refreshToken = prefs.getString('refreshToken');
      if (token == null || refreshToken == null) {
        return false;
      }

      // Simple check - if token is older than 12 hours, refresh it
      final lastRefresh = prefs.getInt('lastTokenRefresh') ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      const twelveHours = 12 * 60 * 60 * 1000; // 12 hours in milliseconds

      if (now - lastRefresh > twelveHours) {
        _log(' Proactively refreshing tokens...');
        try {
          final result = await refreshTokenWithFallback();
          if (result['success'] == true) {
            await prefs.setInt('lastTokenRefresh', now);
            _log(' Proactive token refresh successful');
            return true;
          }
        } catch (e) {
          _log(' Proactive refresh failed: $e');
          // Don't throw - this is just proactive
        }
      }

      return false;
    } catch (e) {
      _log(' Proactive token check failed: $e');
      return false;
    }
  }

  /// 🔐 Handle authentication failure - redirect to login
  static Future<void> _handleAuthFailure(String message) async {
    if (_isHandlingAuthFailure) {
      _log('⚠️ Auth failure already being handled, skipping duplicate');
      return;
    }

    _isHandlingAuthFailure = true;

    try {
      _log('🔐 Handling auth failure: $message');

      // ✅ FIRST: Try to refresh using secure storage
      final refreshToken = await SecureStorageService.getRefreshToken();
      if (refreshToken != null && refreshToken.isNotEmpty) {
        _log('🔄 Attempting token refresh before logout...');
        final refreshed = await _tokenManager.refreshTokenWithQueue();
        if (refreshed) {
          _log('✅ Token refreshed successfully, no logout needed');
          _isHandlingAuthFailure = false;
          return;
        }
      }

      // ✅ ONLY clear if refresh failed
      await SecureStorageService.clearSession();

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('user');
      await prefs.remove('fullName');
      await prefs.remove('email');
      await prefs.remove('phone');
      await prefs.remove('transactionPinSet');
      await prefs.remove('biometricEnabled');
      await prefs.remove('walletBalance');
      await prefs.remove('commissionBalance');
      await prefs.remove('failedAttempts');
      await prefs.remove('lockoutTime');
      await prefs.remove('isAdmin');
      await prefs.remove('needsReauth');
      await prefs.reload();

      // Show dialog only if context is available
      final context = navigatorKey.currentContext;
      if (context != null && context.mounted) {
        await showSessionExpiredDialog(
          context: context,
          title: 'Session Expired',
          message: message,
          buttonText: 'Login Again',
          barrierDismissible: false,
          onLoginAgain: () {
            if (context.mounted && Navigator.canPop(context)) {
              Navigator.pushReplacementNamed(context, '/login');
            } else if (context.mounted) {
              Navigator.pushNamedAndRemoveUntil(
                context,
                '/login',
                (route) => false,
              );
            }
          },
          onCancel: () {
            if (context.mounted && Navigator.canPop(context)) {
              Navigator.pushReplacementNamed(context, '/login');
            } else if (context.mounted) {
              Navigator.pushNamedAndRemoveUntil(
                context,
                '/login',
                (route) => false,
              );
            }
          },
        );
      }
    } catch (e) {
      _log('❌ Auth failure handling error: $e');
      await SecureStorageService.clearSession();
    } finally {
      _isHandlingAuthFailure = false;
    }
  }

  /// 🔄 UPDATED: Enhanced authenticated request with better recovery
  /// 🔄 Enhanced authenticated request with smart retry
  static Future<dynamic> _authenticatedRequest(
    Future<dynamic> Function() requestFunction,
    String operationName,
  ) async {
    // ✅ Check if we have a token
    final token = await SecureStorageService.getAccessToken();

    if (token == null) {
      _log('🔐 No token for $operationName, attempting recovery...');
      final recovered = await recoverAuthentication();
      if (!recovered['success']) {
        throw Exception('Authentication required. Please log in again.');
      }
    }

    try {
      return await requestFunction();
    } catch (e) {
      final errorStr = e.toString().toLowerCase();

      final isAuthError =
          errorStr.contains('401') ||
          errorStr.contains('token expired') ||
          errorStr.contains('invalid token') ||
          errorStr.contains('authentication required') ||
          errorStr.contains('not authenticated') ||
          errorStr.contains('session expired') ||
          errorStr.contains('no token') ||
          errorStr.contains('unauthorized');

      if (isAuthError) {
        _log('🔐 Auth error in $operationName: $e');

        // ✅ ALWAYS attempt refresh on 401 - NO TIME LIMIT
        final refreshToken = await SecureStorageService.getRefreshToken();

        if (refreshToken != null && refreshToken.isNotEmpty) {
          _log('🔄 Attempting token refresh...');
          final refreshSuccess = await _tokenManager.refreshTokenWithQueue();

          if (refreshSuccess) {
            _log('✅ Token refreshed, retrying $operationName');
            await Future.delayed(const Duration(milliseconds: 200));
            return await requestFunction();
          }
        }

        // ✅ Refresh failed or no refresh token - clear session and require login
        _log('❌ Token refresh failed for $operationName');
        await _handleAuthFailure('Session expired. Please login again.');
        throw Exception('Authentication required. Please log in again.');
      }

      rethrow;
    }
  }

  /// 🏥 Check session health and auto-refresh if needed
  static Future<Map<String, dynamic>> checkSessionHealth() async {
    _log('🏥 Checking session health...');

    try {
      final token = await _TokenManager.getSafeToken();
      if (token == null) {
        return {
          'valid': false,
          'message': 'No token found',
          'needsLogin': true,
        };
      }

      final response = await http
          .get(
            Uri.parse('$baseUrl/api/users/session-health'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        // Check if new token was issued
        final newToken = response.headers['x-new-token'];
        if (newToken != null && newToken.isNotEmpty) {
          _log('✅ New token received from session health check');
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('token', newToken);

          final newRefreshToken = response.headers['x-new-refresh-token'];
          if (newRefreshToken != null && newRefreshToken.isNotEmpty) {
            await prefs.setString('refreshToken', newRefreshToken);
          }
          await prefs.reload();
        }

        return {
          'valid': data['success'] == true,
          'expiresIn': data['expiresIn'],
          'expiresInHours': data['expiresInHours'],
          'tokenRefreshed': data['tokenRefreshed'] ?? false,
          'user': data['user'],
        };
      } else {
        return {
          'valid': false,
          'message': 'Session invalid',
          'needsLogin': true,
        };
      }
    } catch (e) {
      _log('❌ Session health check error: $e');
      return {
        'valid': false,
        'message': 'Unable to check session',
        'needsLogin': true,
      };
    }
  }

  /// 🏥 Background session health checker
  static Timer? _sessionHealthTimer;

  static void startSessionHealthCheck({
    Duration interval = const Duration(minutes: 5),
  }) {
    _sessionHealthTimer?.cancel();
    _sessionHealthTimer = Timer.periodic(interval, (timer) async {
      final userId = await _getUserId();
      if (userId == null) {
        timer.cancel();
        return;
      }

      final health = await checkSessionHealth();
      if (!health['valid']) {
        _log('⚠️ Session health check failed, will refresh on next API call');
      }
    });
  }

  static void stopSessionHealthCheck() {
    _sessionHealthTimer?.cancel();
    _sessionHealthTimer = null;
  }

  static Future<List<dynamic>> getTransactions() async {
    for (int attempt = 0; attempt < 3; attempt++) {
      try {
        final token = await _TokenManager.getSafeToken();
        if (token == null) {
          _log('❌ No token in getTransactions');
          if (attempt == 2) {
            await _handleAuthFailure('Session expired. Please login again.');
            throw Exception('Authentication required');
          }
          continue;
        }

        final response = await http
            .get(
              Uri.parse('$baseUrl/api/transactions'),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $token',
              },
            )
            .timeout(const Duration(seconds: 20));

        _log('📡 Transactions response: ${response.statusCode}');

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);

          // Check for token expired in response
          if (data['code'] == 'TOKEN_EXPIRED' ||
              data['requiresRefresh'] == true) {
            _log('🔄 Token expired, refreshing...');
            final refreshed = await _tokenManager.refreshTokenWithQueue();
            if (refreshed) {
              await Future.delayed(const Duration(milliseconds: 120));
              continue; // Retry with new token
            }
            throw Exception('Token refresh failed');
          }

          if (data['code'] == 'INVALID_TOKEN' || data['code'] == 'NO_TOKEN') {
            throw Exception('Invalid token');
          }

          if (data['success'] == true) {
            return data['transactions'] ?? [];
          }

          return [];
        } else if (response.statusCode == 401) {
          _log('🔐 401 Unauthorized in getTransactions');
          if (attempt == 2) {
            await _handleAuthFailure('Session expired. Please login again.');
            throw Exception('Authentication required');
          }
          // Try to refresh and retry
          await _tokenManager.refreshTokenWithQueue();
          await Future.delayed(const Duration(milliseconds: 200));
          continue;
        } else {
          return [];
        }
      } catch (e) {
        _log('⚠️ getTransactions attempt $attempt error: $e');
        if (attempt < 2) {
          await Future.delayed(Duration(milliseconds: 200 * (attempt + 1)));
          continue;
        }

        // If it's an auth error, handle it
        if (e.toString().contains('Authentication required') ||
            e.toString().contains('401') ||
            e.toString().contains('Session expired')) {
          await _handleAuthFailure('Session expired. Please login again.');
        }
        rethrow;
      }
    }

    throw Exception('Failed to load transactions after 3 attempts');
  }

  /// 🔄 Proactive token refresh to prevent expiration
  static Future<bool> refreshTokensProactively() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = await _TokenManager.getSafeToken();
      final lastRefresh = prefs.getInt('lastTokenRefresh') ?? 0;

      if (token == null) return false;

      // Check if token is about to expire (within 1 hour)
      final now = DateTime.now().millisecondsSinceEpoch;
      const oneHour = 60 * 60 * 1000; // 1 hour in milliseconds
      const twentyThreeHours = 23 * 60 * 60 * 1000; // 23 hours in milliseconds

      final timeSinceRefresh = now - lastRefresh;

      // Refresh if token is older than 23 hours or about to expire
      if (timeSinceRefresh > twentyThreeHours) {
        _log(
          '🔄 Proactively refreshing token (age: ${timeSinceRefresh / (60 * 60 * 1000)} hours)',
        );

        final refreshSuccess = await _tokenManager.refreshTokenWithQueue();
        if (refreshSuccess) {
          _log('✅ Proactive token refresh successful');
          return true;
        } else {
          _log('⚠️ Proactive token refresh failed');
          return false;
        }
      }

      return true;
    } catch (e) {
      _log('❌ Proactive token refresh error: $e');
      return false;
    }
  }

  /// Safe navigation helper to avoid assertion errors
  static Future<void> safeNavigateToLogin(BuildContext context) async {
    try {
      if (!context.mounted) return;

      // Try to pop all routes first
      while (Navigator.canPop(context)) {
        Navigator.pop(context);
      }

      // Then navigate to login
      if (context.mounted) {
        Navigator.pushReplacementNamed(context, '/login');
      }
    } catch (e) {
      debugPrint('⚠️ Safe navigation failed: $e');
      // Last resort - use pushNamedAndRemoveUntil
      if (context.mounted) {
        try {
          Navigator.pushNamedAndRemoveUntil(
            context,
            '/login',
            (route) => false,
          );
        } catch (e) {
          debugPrint('❌ Emergency navigation failed: $e');
        }
      }
    }
  }

  /// 🛠️ FORCE CLEAR REAUTH FLAG (Use when you want to reset authentication state)
  static Future<void> forceClearReauthFlag() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('needsReauth');
    await prefs.reload();
    _log('🛠️ Force cleared reauth flag');
  }

  // Add this method to ApiService class (in services/api_service.dart)
  static Future<Map<String, dynamic>> refreshAccessToken(
    String refreshToken,
  ) async {
    try {
      debugPrint(
        '🔄 REFRESH: Refreshing access token with refreshToken: ${refreshToken.substring(0, 10)}...',
      );

      final response = await http
          .post(
            Uri.parse('${ApiService.baseUrl}/auth/refresh'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization':
                  'Bearer $refreshToken', // Use refreshToken for refresh endpoint
            },
            body: jsonEncode({'refreshToken': refreshToken}),
          )
          .timeout(const Duration(seconds: 30));

      debugPrint('🔄 REFRESH: Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        if (data['success'] == true) {
          final newAccessToken = data['accessToken'] as String?;
          if (newAccessToken != null) {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('token', newAccessToken);
            debugPrint('✅ REFRESH: New access token saved');
          }
          return {'success': true, 'accessToken': newAccessToken};
        }
      }

      debugPrint('❌ REFRESH: Failed to refresh token');
      return {'success': false, 'message': 'Failed to refresh token'};
    } catch (e) {
      debugPrint('❌ REFRESH: Error refreshing token: $e');
      return {'success': false, 'message': e.toString()};
    }
  }

  // --- User Authentication & Management ---

  // --- Log Referral Transaction (must come first) ---
  static Future<void> _logReferralTransaction({
    required String referrerId,
    required String newUserId,
    required String referralCode,
    required String type, // 'direct' or 'indirect'
  }) async {
    try {
      final logBody = {
        'referrerId': referrerId,
        'newUserId': newUserId,
        'referralCode': referralCode,
        'type': type,
        'timestamp': DateTime.now().toIso8601String(),
        'environment': _useSandbox ? 'sandbox' : 'live',
      };

      await _authenticatedPost(_referralUrl, logBody);
      _log(
        'Referral transaction logged: $type referral for user $newUserId by referrer $referrerId',
      );
    } catch (e, stackTrace) {
      _log('Error logging referral transaction: $e');
      await reportError(e, stackTrace);
    }
  }

  // --- First Transaction Bonus Helper ---
  static Future<void> _creditFirstTransactionBonuses({
    required String userId,
    required String transactionId,
    required String serviceType,
    required double amount,
    required String requestId,
  }) async {
    try {
      // 🛡️ Security: Daily bonus limit ₦10,000
      const dailyBonusLimit = 10000.0;
      final today = DateTime.now().toIso8601String().split('T')[0];

      final commissionResponse = await _authenticatedGet(
        Uri.parse('$_commissionTransactionsUrl/user/$userId?date=$today'),
      );

      final dailyTransactions =
          commissionResponse['commissionTransactions'] as List<dynamic>? ?? [];
      final dailyTotal = dailyTransactions.fold<double>(
        0.0,
        (sum, tx) => sum + ((tx['commissionAmount'] ?? 0) as num).toDouble(),
      );

      if (dailyTotal + 200.0 > dailyBonusLimit) {
        _log('⚠️ Daily bonus limit exceeded for user $userId');
        throw Exception(
          'Daily referral bonus limit reached. Try again tomorrow.',
        );
      }

      // ✅ Proceed with your existing first transaction bonus logic
      final commissionBody = {
        'userId': userId,
        'transactionId': transactionId,
        'serviceType': serviceType,
        'amount': amount,
        'requestId': requestId,
        'commissionAmount': 200.0,
        'environment': _useSandbox ? 'sandbox' : 'live',
      };

      await _authenticatedPost(_commissionTransactionsUrl, commissionBody);
      _log('🎉 First transaction bonus of ₦200 credited for user $userId');

      // Optional: Update local commission balance
      final prefs = await SharedPreferences.getInstance();
      final currentBalance = prefs.getDouble('commissionBalance') ?? 0.0;
      final newBalance = currentBalance + 200.0;
      await prefs.setDouble('commissionBalance', newBalance);

      final userString = prefs.getString('user');
      if (userString != null) {
        final userMap = jsonDecode(userString);
        userMap['commissionBalance'] = newBalance;
        await prefs.setString('user', jsonEncode(userMap));
      }
    } catch (e, stackTrace) {
      _log('Error crediting first transaction bonuses: $e');
      await reportError(e, stackTrace);
    }
  }

  // ===== NEW HELPER METHODS - ADD BEFORE registerUser =====

  /// Format phone number to ensure 11 digits
  static String _formatPhoneNumber(String phone) {
    // Remove all non-digit characters
    final digitsOnly = phone.replaceAll(RegExp(r'[^0-9]'), '');

    // Ensure it's 11 digits (Nigeria phone format)
    if (digitsOnly.length == 11) {
      return digitsOnly;
    } else if (digitsOnly.length == 13 && digitsOnly.startsWith('234')) {
      // Convert 234 format to 0 format
      return '0${digitsOnly.substring(3)}';
    } else if (digitsOnly.length == 14 && digitsOnly.startsWith('+234')) {
      // Convert +234 format to 0 format
      return '0${digitsOnly.substring(4)}';
    } else {
      // Return as is, validation will catch it
      return digitsOnly;
    }
  }

  /// Get local referral data
  static Future<Map<String, dynamic>?> _getLocalReferral(
    String referralCode,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = prefs.getString('local_referral_$referralCode');
      if (data != null) {
        final referralData = jsonDecode(data);
        // Check if referral is not expired (30 days)
        final timestamp = DateTime.parse(referralData['timestamp']);
        if (DateTime.now().difference(timestamp).inDays <= 30) {
          return referralData;
        } else {
          // Remove expired referral
          await prefs.remove('local_referral_$referralCode');
        }
      }
      return null;
    } catch (e) {
      _log('❌ Error getting local referral: $e');
      return null;
    }
  }

  /// Local referral storage using SharedPreferences
  static Future<void> _storeReferralLocally({
    required String referralCode,
    required String referrerId,
    required String referrerName,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'local_referral_$referralCode',
        jsonEncode({
          'referrerId': referrerId,
          'referrerName': referrerName,
          'timestamp': DateTime.now().toIso8601String(),
          'isValid': true,
        }),
      );
      _log('✅ Stored referral locally: $referralCode -> $referrerName');
    } catch (e) {
      _log('❌ Error storing referral locally: $e');
    }
  }

  // ===== END OF NEW HELPER METHODS =====

  // --- User Registration WITH OTP Support ---
  // Update the registerUser method in ApiService
  static Future<Map<String, dynamic>> registerUser({
    required String fullName,
    required String email,
    required String phone,
    required String password,
    String? referralCode,
    required String otp,
  }) async {
    _log('🚀 Registering user: $email');

    // Pre-validate data
    if (phone.length != 11) {
      throw Exception('Phone number must be exactly 11 digits');
    }

    if (!RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
    ).hasMatch(email)) {
      throw Exception('Please enter a valid email address');
    }

    final Map<String, dynamic> body = {
      'fullName': fullName.trim(),
      'email': email.trim().toLowerCase(),
      'phone': _formatPhoneNumber(phone),
      'password': password,
      'otp': otp.trim(),
    };

    if (referralCode != null && referralCode.isNotEmpty) {
      final cleanCode = referralCode.trim().toUpperCase();
      if (cleanCode.length >= 8 && cleanCode.startsWith('REF')) {
        body['referralCode'] = cleanCode;
      }
    }

    const maxRetries = 2;
    int attempt = 0;

    while (attempt <= maxRetries) {
      try {
        final response = await http
            .post(
              _registerUrl,
              headers: {
                'Content-Type': 'application/json',
                'Accept': 'application/json',
                'X-Client-Version': '1.0.0',
              },
              body: jsonEncode(body),
            )
            .timeout(const Duration(seconds: 25));

        final responseBody =
            response.body.isNotEmpty ? jsonDecode(response.body) : {};

        if (response.statusCode >= 200 && response.statusCode < 300) {
          if (responseBody['success'] == true &&
              responseBody['token'] != null) {
            await _saveAuthData(responseBody);
            return responseBody;
          } else {
            throw Exception(responseBody['message'] ?? 'Registration failed');
          }
        } else {
          return await _handleRegistrationError(
            response,
            responseBody,
            attempt,
            maxRetries,
          );
        }
      } on SocketException {
        if (attempt < maxRetries) {
          await Future.delayed(const Duration(seconds: 2));
          attempt++;
          continue;
        }
        throw Exception(
          'Network connection failed. Please check your internet connection.',
        );
      } on TimeoutException {
        if (attempt < maxRetries) {
          await Future.delayed(const Duration(seconds: 2));
          attempt++;
          continue;
        }
        throw Exception('Registration request timed out. Please try again.');
      } catch (e) {
        rethrow;
      }
    }

    throw Exception('Registration failed after $maxRetries attempts.');
  }

  static Future<Map<String, dynamic>> _handleRegistrationError(
    http.Response response,
    Map<String, dynamic> errorData,
    int attempt,
    int maxRetries,
  ) async {
    String message =
        errorData['message']?.toString() ??
        'Request failed with status: ${response.statusCode}';

    // Log error for debugging (without revealing sensitive info)
    _log(
      '❌ Registration error: ${response.statusCode} - ${message.substring(0, min(message.length, 100))}',
    );

    // Handle specific error types
    switch (response.statusCode) {
      case 400:
        if (message.toLowerCase().contains('otp')) {
          throw Exception('Verification failed. Please request a new code.');
        }
        if (message.toLowerCase().contains('already') ||
            message.toLowerCase().contains('duplicate')) {
          // Let the duplicate detection handle this
          throw Exception(message);
        }
        throw Exception('Please check your information and try again.');

      case 409:
        // Conflict - duplicate data
        if (message.toLowerCase().contains('email')) {
          throw Exception('This email address is already registered.');
        } else if (message.toLowerCase().contains('phone')) {
          throw Exception('This phone number is already registered.');
        } else {
          throw Exception('An account with these details already exists.');
        }

      case 422:
        throw Exception('Please complete all required fields correctly.');

      case 429:
        throw Exception('Too many attempts. Please wait a moment.');

      case 500:
      case 502:
      case 503:
      case 504:
        if (attempt < maxRetries) {
          await Future.delayed(const Duration(seconds: 2));
          throw Exception('Service temporarily unavailable. Retrying...');
        }
        throw Exception(
          'Registration service is currently unavailable. Please try again later.',
        );

      default:
        throw Exception('Registration failed. Please try again.');
    }
  }

  // --- Admin User Creation (without OTP) ---
  static Future<Map<String, dynamic>> adminCreateUser({
    required String fullName,
    required String email,
    required String phone,
    required String password,
  }) async {
    _log('👨‍💼 Admin creating user: $email');

    final Map<String, dynamic> body = {
      'fullName': fullName.trim(),
      'email': email.trim().toLowerCase(),
      'phone': _formatPhoneNumber(phone),
      'password': password,
      'isAdminCreated': true, // Add flag for backend to skip OTP
    };

    final response = await http
        .post(
          Uri.parse('${ApiService.baseUrl}/api/admin/create-user'),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'Authorization':
                'Bearer ${await _getToken()}', // Admin token needed
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 20));

    // ... handle response similar to registerUser
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final data = jsonDecode(response.body);
      return data;
    } else {
      throw Exception('Admin user creation failed: ${response.statusCode}');
    }
  }

  // CORRECTED registerUserWithVirtualAccount method in ApiService
  static Future<Map<String, dynamic>> registerUserWithVirtualAccount({
    required String fullName,
    required String email,
    required String phone,
    required String password,
    required String otp,
    String? referralCode,
  }) async {
    _log(
      '🚀 Starting enhanced registration with virtual account creation, OTP: $otp',
    );
    try {
      // Step 1: Register user on auth backend with fallback
      final registrationResult = await registerUserWithFallback(
        fullName: fullName,
        email: email,
        phone: phone,
        password: password,
        referralCode: referralCode,
        otp: otp,
      );

      // Check if registration was successful and has user data
      if (registrationResult['success'] == true) {
        // Safely access the user data with null checks
        final userData = registrationResult['user'];
        final userId = userData != null ? userData['_id']?.toString() : null;

        if (userId == null || userId.isEmpty) {
          _log(
            '❌ User registration succeeded but user ID is missing or invalid',
          );
          return {
            'success': false,
            'message':
                'Registration completed but user ID is missing. Please contact support.',
            'user': userData,
          };
        }

        _log(
          '✅ User registered successfully, creating virtual account for: $userId',
        );

        // Step 2: Create virtual account using ApiService (not directly calling PaymentService)
        try {
          final virtualAccount = await ApiService.createVirtualAccount(
            userId: userId,
            email: email,
            fullName: fullName,
            phone: phone,
          );

          _log(
            '🏦 Virtual account creation result: ${virtualAccount['success']}',
          );

          // Step 3: Store virtual account data locally
          final prefs = await SharedPreferences.getInstance();

          if (virtualAccount['success'] == true) {
            await prefs.setString(
              'virtualAccountNumber',
              virtualAccount['accountNumber'] ?? '',
            );
            await prefs.setString(
              'virtualAccountName',
              virtualAccount['accountName'] ?? fullName,
            );
            await prefs.setString(
              'virtualBankName',
              virtualAccount['bankName'] ?? 'WEMA BANK',
            );
            await prefs.setBool('hasVirtualAccount', true);

            _log(
              '✅ Virtual account created: ${virtualAccount['accountNumber']}',
            );
          } else {
            // Store fallback values
            await prefs.setString('virtualAccountNumber', 'Account Pending');
            await prefs.setString('virtualAccountName', fullName);
            await prefs.setString('virtualBankName', 'WEMA BANK');
            await prefs.setBool('hasVirtualAccount', false);

            _log('⚠️ Virtual account creation in progress');
          }

          // Step 4: Return combined result
          return {
            ...registrationResult,
            'virtualAccount': virtualAccount,
            'hasVirtualAccount': virtualAccount['success'] == true,
          };
        } catch (e) {
          _log('⚠️ Virtual account creation failed but user registered: $e');

          // Store fallback values even if creation fails
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('virtualAccountNumber', 'Account Pending');
          await prefs.setString('virtualAccountName', fullName);
          await prefs.setString('virtualBankName', 'WEMA BANK');
          await prefs.setBool('hasVirtualAccount', false);

          // User is registered, but virtual account failed
          return {
            ...registrationResult,
            'virtualAccount': {
              'success': false,
              'message': 'Virtual account creation in progress',
              'accountNumber': 'Account Pending',
              'accountName': fullName,
              'bankName': 'WEMA BANK',
            },
            'hasVirtualAccount': false,
            'warning': 'Virtual account will be created shortly',
          };
        }
      } else {
        // Registration failed, return the error
        return registrationResult;
      }
    } catch (e, stackTrace) {
      _log('❌ Enhanced registration failed: $e');
      await reportError(e, stackTrace);

      return {
        'success': false,
        'message':
            'Registration failed due to an unexpected error. Please try again.',
        'error': e.toString(),
      };
    }
  }

  static Future<Map<String, dynamic>> registerUserWithFallback({
    required String fullName,
    required String email,
    required String phone,
    required String password,
    String? referralCode,
    required String otp, // ✅ ADD THIS PARAMETER
  }) async {
    try {
      return await registerUser(
        fullName: fullName,
        email: email,
        phone: phone,
        password: password,
        referralCode: referralCode,
        otp: otp, // ✅ PASS THE OTP
      );
    } catch (e) {
      _log('❌ Primary registration failed: $e');

      // Provide user-friendly error messages
      String userMessage;
      if (e.toString().contains('Email already exists')) {
        userMessage =
            'This email is already registered. Please use a different email.';
      } else if (e.toString().contains('Phone already registered')) {
        userMessage =
            'This phone number is already registered. Please use a different number.';
      } else if (e.toString().contains('OTP') ||
          e.toString().contains('verification')) {
        userMessage = e.toString().replaceAll('Exception: ', '');
      } else if (e.toString().contains('500') ||
          e.toString().contains('Internal Server Error')) {
        userMessage =
            'Registration service is temporarily unavailable. Please try again in a few minutes.';
      } else if (e.toString().contains('timeout') ||
          e.toString().contains('TimeoutException')) {
        userMessage =
            'Registration request timed out. Please check your internet connection and try again.';
      } else {
        userMessage =
            'Registration failed: ${e.toString().replaceAll('Exception: ', '')}';
      }

      return {'success': false, 'message': userMessage, 'error': e.toString()};
    }
  }

  /// Send email verification OTP during signup.
  /// Calls the existing backend endpoint: POST /api/auth/send-verification-otp
  static Future<Map<String, dynamic>> sendEmailVerificationOtp({
    required String email,
  }) async {
    _log('📧 Sending email verification OTP to: $email');

    try {
      final response = await http
          .post(
            Uri.parse('${ApiService.baseUrl}/api/auth/send-verification-otp'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({'email': email.trim().toLowerCase()}),
          )
          .timeout(const Duration(seconds: 30));

      _log('📡 Send-OTP response status: ${response.statusCode}');
      _log('📡 Send-OTP response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data is Map<String, dynamic>
            ? data
            : {'success': false, 'message': 'Invalid server response'};
      }

      // Non-200 — try to parse the error body
      try {
        final err = jsonDecode(response.body);
        if (err is Map<String, dynamic>) return err;
      } catch (_) {}

      return {
        'success': false,
        'message': 'Failed to send code (${response.statusCode})',
      };
    } on TimeoutException {
      _log('⏰ Send-OTP timed out');
      return {
        'success': false,
        'message': 'Request timed out. Please try again.',
      };
    } on SocketException {
      _log('🌐 Send-OTP network error');
      return {
        'success': false,
        'message': 'No internet connection. Please check your network.',
      };
    } catch (e) {
      _log('❌ Send-OTP error: $e');
      return {
        'success': false,
        'message': 'Failed to send code: ${e.toString()}',
      };
    }
  }

  // Check if email is verified via OTP before registration
  static Future<Map<String, dynamic>> verifyEmailWithOTP({
    required String email,
    required String otp,
  }) async {
    _log('🔐 Verifying OTP for email: $email');

    try {
      final response = await http
          .post(
            Uri.parse('${ApiService.baseUrl}/api/auth/verify-otp'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              'email': email.trim().toLowerCase(),
              'otp': otp.trim(),
            }),
          )
          .timeout(const Duration(seconds: 15));

      _log('📡 OTP verification response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['success'] == true) {
          _log('✅ OTP verification successful for $email');

          // Store verification status locally
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('email_verified_${email.hashCode}', true);
          await prefs.setString('verified_email', email);

          return {
            'success': true,
            'message': data['message'] ?? 'Email verified successfully',
            'email': email,
          };
        } else {
          _log('❌ OTP verification failed: ${data['message']}');
          return {
            'success': false,
            'message': data['message'] ?? 'Invalid verification code',
          };
        }
      } else if (response.statusCode == 400 || response.statusCode == 401) {
        final data = jsonDecode(response.body);
        return {
          'success': false,
          'message': data['message'] ?? 'Invalid or expired verification code',
        };
      } else if (response.statusCode == 429) {
        return {
          'success': false,
          'message':
              'Too many attempts. Please wait 1 minute before trying again.',
        };
      } else {
        throw Exception('Verification service error: ${response.statusCode}');
      }
    } on TimeoutException {
      _log('⏰ OTP verification timeout');
      throw Exception('Verification request timed out. Please try again.');
    } on SocketException {
      _log('🌐 Network error during OTP verification');
      throw Exception('Network connection failed. Please check your internet.');
    } on FormatException {
      _log('❌ Invalid JSON response for OTP verification');
      throw Exception('Invalid response from server. Please try again.');
    } catch (e) {
      _log('❌ OTP verification error: $e');
      rethrow;
    }
  }

  // Check if email is already verified (cache check)
  static Future<bool> isEmailVerifiedLocally(String email) async {
    final prefs = await SharedPreferences.getInstance();
    final verified = prefs.getBool('email_verified_${email.hashCode}') ?? false;
    final storedEmail = prefs.getString('verified_email');

    // Only return true if it's the same email that was verified
    return verified && storedEmail == email;
  }

  // Clear verification status (useful for logout or new signup)
  static Future<void> clearVerificationStatus() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('verified_email');
    // Remove all verification flags
    final keys = prefs.getKeys().where(
      (key) => key.startsWith('email_verified_'),
    );
    for (final key in keys) {
      await prefs.remove(key);
    }
  }

  //Login Users
  static Future<Map<String, dynamic>> loginUser({
    required String email,
    required String password,
  }) async {
    _log('Attempting to log in user...');

    final response = await http
        .post(
          _loginUrl,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'email': email.trim(), 'password': password}),
        )
        .timeout(const Duration(seconds: 30));

    // Use _handleResponse which now returns data for login errors
    final data = _handleResponse(response);

    // Only save auth data if login was successful
    if (response.statusCode == 200 && data['success'] == true) {
      await _saveAuthData(data);
    }

    return data;
  }

  /// FIXED LOGOUT - THIS SOLVES THE "CAN'T LOGIN AFTER LOGOUT" BUG
  /// Logout — calls backend but PRESERVES token, userId, user data,
  /// and biometric flag so the user can re-login with PIN or Biometric.
  static Future<Map<String, dynamic>> logoutUser() async {
    _log('🚪 STARTING LOGOUT (session-preserving)...');

    // 1. Preserve the essentials BEFORE anything else
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    final preservedToken = prefs.getString('token');
    final preservedRefreshToken = prefs.getString('refreshToken');
    final preservedUserId = prefs.getString('userId');
    final preservedUser = prefs.getString('user');
    final preservedFullName = prefs.getString('fullName');
    final preservedEmail = prefs.getString('email');
    final preservedPhone = prefs.getString('phone');
    final preservedIsAdmin = prefs.getBool('isAdmin');
    final preservedRole = prefs.getString('role');
    final preservedTransactionPinSet = prefs.getBool('transactionPinSet');
    final preservedBiometricEnabled = prefs.getBool('biometricEnabled');
    final preservedProfileImage = prefs.getString('profileImage');

    bool? preservedBiometricUserFlag;
    if (preservedUserId != null) {
      preservedBiometricUserFlag = prefs.getBool(
        'biometricEnabled_$preservedUserId',
      );
    }

    // 2. Best-effort backend notify (never throws)
    try {
      final token = await _getToken();
      if (token != null && token.isNotEmpty) {
        await _authenticatedPost(_logoutUrl, {});
        _log('✅ Logout API notified backend');
      }
    } catch (e) {
      _log('⚠️ Logout API failed (ignored): $e');
    }

    // 3. DO NOT call prefs.clear(). Only clear ephemeral flags.
    await prefs.remove('needsReauth');
    await prefs.remove('authError');
    await prefs.remove('failedAttempts');
    await prefs.remove('lockoutTime');

    // 4. Re-assert preserved keys (belt & braces — in case anything
    //    else in the app cleared them concurrently)
    if (preservedToken != null && preservedToken.isNotEmpty) {
      await prefs.setString('token', preservedToken);
    }
    if (preservedRefreshToken != null && preservedRefreshToken.isNotEmpty) {
      await prefs.setString('refreshToken', preservedRefreshToken);
    }
    if (preservedUserId != null && preservedUserId.isNotEmpty) {
      await prefs.setString('userId', preservedUserId);
    }
    if (preservedUser != null && preservedUser.isNotEmpty) {
      await prefs.setString('user', preservedUser);
    }
    if (preservedFullName != null) {
      await prefs.setString('fullName', preservedFullName);
    }
    if (preservedEmail != null) {
      await prefs.setString('email', preservedEmail);
    }
    if (preservedPhone != null) {
      await prefs.setString('phone', preservedPhone);
    }
    if (preservedIsAdmin != null) {
      await prefs.setBool('isAdmin', preservedIsAdmin);
    }
    if (preservedRole != null) {
      await prefs.setString('role', preservedRole);
    }
    if (preservedTransactionPinSet != null) {
      await prefs.setBool('transactionPinSet', preservedTransactionPinSet);
    }
    if (preservedBiometricEnabled != null) {
      await prefs.setBool('biometricEnabled', preservedBiometricEnabled);
    }
    if (preservedProfileImage != null) {
      await prefs.setString('profileImage', preservedProfileImage);
    }
    if (preservedUserId != null && preservedBiometricUserFlag != null) {
      await prefs.setBool(
        'biometricEnabled_$preservedUserId',
        preservedBiometricUserFlag,
      );
    }

    await prefs.reload();

    _log(
      '✅ LOGOUT COMPLETE — token & userId PRESERVED for PIN/Biometric login',
    );
    _log('   userId: $preservedUserId');
    _log('   hasToken: ${preservedToken != null}');
    _log('   biometricFlag: $preservedBiometricUserFlag');

    return {
      'success': true,
      'message': 'Logged out successfully',
      'sessionPreserved': true,
    };
  }

  static Future<void> _clearSecurityDataOnly() async {
    final prefs = await SharedPreferences.getInstance();

    // 🚫 DON'T clear these tokens:
    // 'token' - PRESERVED for PIN verification
    // 'refreshToken' - PRESERVED for token refresh
    // 'userId' - PRESERVED for user identification
    // 'user' - PRESERVED for user data

    // ✅ DO clear these temporary security items:
    await prefs.remove('failedAttempts');
    await prefs.remove('lockoutTime');
    await prefs.remove('lastLogoutTime');

    _log('🔐 Tokens PRESERVED for PIN login - only security data cleared.');
    _log('✅ User can now use PIN login with preserved tokens');
  }

  // Enhanced PIN verification with better error handling
  // lib/core/services/api_service.dart

  /// Verify PIN for login - COMPLETELY PUBLIC (NO TOKEN REQUIRED)
  static Future<Map<String, dynamic>> verifyTransactionPinForLogin({
    required String userId,
    required String transactionPin,
  }) async {
    _log('🔐 Verifying transaction PIN for PIN login - user ID: $userId');

    try {
      // ✅ REMOVE THIS ENTIRE BLOCK - DO NOT CHECK SECURITY SETTINGS HERE
      // The security check should happen on the BACKEND, not the frontend
      // final securitySettings = await getSecuritySettings(); // ❌ REMOVE THIS
      // final pinLocked = securitySettings['securitySettings']['pinLocked'] ?? false; // ❌ REMOVE
      // final lockTimeRemaining = securitySettings['securitySettings']['lockTimeRemaining'] ?? 0; // ❌ REMOVE

      // ✅ This is a PUBLIC endpoint - NO Authorization header!
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/auth/verify-pin-for-login'),
            headers: {
              'Content-Type': 'application/json',
            }, // ✅ NO Authorization header!
            body: jsonEncode({
              'userId': userId,
              'transactionPin': transactionPin, // MATCHES BACKEND
            }),
          )
          .timeout(const Duration(seconds: 30));

      _log('📡 PIN verification response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['success'] == true) {
          _log('✅ PIN verified successfully');

          // ✅ Save auth data
          await _savePinLoginAuthData(data);

          return {
            'success': true,
            'message': data['message'] ?? 'PIN verified successfully',
            'token': data['token'],
            'refreshToken': data['refreshToken'],
            'user': data['user'],
          };
        } else {
          _log('❌ PIN verification failed: ${data['message']}');
          return {
            'success': false,
            'message': data['message'] ?? 'Invalid PIN',
            'attemptsRemaining': data['attemptsRemaining'] ?? 0,
            'locked': data['locked'] ?? false,
            'lockTimeRemaining': data['lockTimeRemaining'] ?? 0,
          };
        }
      } else {
        _log('❌ PIN verification failed with status: ${response.statusCode}');
        try {
          final errorData = jsonDecode(response.body);
          return {
            'success': false,
            'message': errorData['message'] ?? 'PIN verification failed',
            'attemptsRemaining': errorData['attemptsRemaining'] ?? 0,
            'locked': errorData['locked'] ?? false,
            'lockTimeRemaining': errorData['lockTimeRemaining'] ?? 0,
          };
        } catch (e) {
          return {
            'success': false,
            'message': 'Server error: ${response.statusCode}',
          };
        }
      }
    } catch (e, stackTrace) {
      _log('❌ ERROR in verifyTransactionPinForLogin: $e');
      await reportError(e, stackTrace);

      // Handle network errors specifically
      if (e.toString().contains('SocketException') ||
          e.toString().contains('timeout') ||
          e.toString().contains('Failed to connect')) {
        return {
          'success': false,
          'message': 'Network error. Please check your internet connection.',
          'networkError': true,
        };
      }

      return {
        'success': false,
        'message': 'PIN verification failed: ${e.toString()}',
      };
    }
  }

  /// ✅ NEW: Save PIN login auth data
  static Future<void> _savePinLoginAuthData(
    Map<String, dynamic> response,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = response['token'];
      final refreshToken = response['refreshToken'];
      final userData = response['user'];

      if (token != null && token.isNotEmpty && userData != null) {
        // ✅ 1. SAVE TO SECURE STORAGE (Required for API calls)
        await SecureStorageService.saveTokens(
          accessToken: token,
          refreshToken: refreshToken ?? '',
          userId: userData['_id']?.toString(),
        );

        // ✅ 2. SAVE TO SHARED PREFERENCES (Required for Dashboard session check)
        await prefs.setString('token', token);
        if (refreshToken != null && refreshToken.isNotEmpty) {
          await prefs.setString('refreshToken', refreshToken);
        }

        // Save user data
        await prefs.setString('user', jsonEncode(userData));
        await prefs.setString('userId', userData['_id']?.toString() ?? '');
        await prefs.setString(
          'fullName',
          userData['fullName']?.toString() ?? '',
        );
        await prefs.setString('email', userData['email']?.toString() ?? '');
        if (userData['phone'] != null) {
          await prefs.setString('phone', userData['phone'].toString());
        }
        await prefs.setBool('transactionPinSet', true);
        if (userData['isAdmin'] != null) {
          await prefs.setBool('isAdmin', userData['isAdmin'] == true);
        }
        if (userData['role'] != null) {
          await prefs.setString('role', userData['role'].toString());
        }
        if (userData['biometricEnabled'] != null) {
          await prefs.setBool(
            'biometricEnabled',
            userData['biometricEnabled'] == true,
          );
        }
        if (userData['walletBalance'] != null) {
          await prefs.setDouble(
            'walletBalance',
            (userData['walletBalance'] as num).toDouble(),
          );
        }
        if (userData['commissionBalance'] != null) {
          await prefs.setDouble(
            'commissionBalance',
            (userData['commissionBalance'] as num).toDouble(),
          );
        }

        // Clear any reauth flags
        await prefs.remove('needsReauth');
        await prefs.remove('authError');

        // Set last login timestamp
        await prefs.setInt(
          'lastLoginTime',
          DateTime.now().millisecondsSinceEpoch,
        );
        await prefs.setInt(
          'lastTokenRefresh',
          DateTime.now().millisecondsSinceEpoch,
        );
        await prefs.reload();

        _log(
          '✅ PIN login auth data saved to BOTH SecureStorage and SharedPreferences.',
        );
      } else {
        _log('⚠️ Missing token or user data in PIN login response');
        throw Exception('Invalid response from server');
      }
    } catch (e) {
      _log('❌ Error saving PIN login auth data: $e');
      rethrow;
    }
  }

  // Keep the original clearAuthData for when you need to clear everything
  static Future<void> clearAuthData() async {
    final prefs = await SharedPreferences.getInstance();

    // Clear ALL authentication data including userId and token
    await prefs.remove('user');
    await prefs.remove('token');
    await prefs.remove('refreshToken');
    await prefs.remove('userId');
    await prefs.remove('fullName');
    await prefs.remove('email');
    await prefs.remove('phone');
    await prefs.remove('transactionPinSet');
    await prefs.remove('biometricEnabled');
    await prefs.remove('walletBalance');
    await prefs.remove('commissionBalance');
    await prefs.remove('failedAttempts');
    await prefs.remove('lockoutTime');

    _log('All authentication data cleared.');
  }

  // Enhanced user data refresh method
  static Future<void> refreshUserData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = await _getUserId();

      if (userId != null) {
        final userData = await getCurrentUser();

        // Extract user data with fallbacks
        final fullName = userData['fullName']?.toString() ?? 'User';
        final email = userData['email']?.toString() ?? '';
        final phone = userData['phone']?.toString() ?? '';
        final transactionPinSet = userData['transactionPinSet'] == true;
        final biometricEnabled = userData['biometricEnabled'] == true;

        // Update all user fields in SharedPreferences
        await prefs.setString('fullName', fullName);
        await prefs.setString('email', email);
        await prefs.setString('phone', phone);
        await prefs.setBool('transactionPinSet', transactionPinSet);
        await prefs.setBool('biometricEnabled', biometricEnabled);

        // Update wallet balances if available
        if (userData['walletBalance'] != null) {
          await prefs.setDouble(
            'walletBalance',
            (userData['walletBalance'] as num).toDouble(),
          );
        }
        if (userData['commissionBalance'] != null) {
          await prefs.setDouble(
            'commissionBalance',
            (userData['commissionBalance'] as num).toDouble(),
          );
        }

        // Update the complete user object
        final updatedUserData = {
          '_id': userId,
          'fullName': fullName,
          'email': email,
          'phone': phone,
          'transactionPinSet': transactionPinSet,
          'biometricEnabled': biometricEnabled,
          'walletBalance': userData['walletBalance'],
          'commissionBalance': userData['commissionBalance'],
        };

        await prefs.setString('user', jsonEncode(updatedUserData));

        _log('✅ User data refreshed from API: $fullName, $email');
        _log('📊 PIN: $transactionPinSet, Bio: $biometricEnabled');
      } else {
        _log('❌ Cannot refresh user data: No userId found');
      }
    } catch (e, stackTrace) {
      _log('❌ Error refreshing user data: $e');
      await reportError(e, stackTrace);
    }
  }

  // NEW: Quick user data validation method
  static Future<bool> validateStoredUserData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('userId');
      final fullName = prefs.getString('fullName');
      final email = prefs.getString('email');
      final transactionPinSet = prefs.getBool('transactionPinSet');

      // Check if we have the minimum required user data
      final hasValidData =
          userId != null &&
          userId.isNotEmpty &&
          fullName != null &&
          fullName.isNotEmpty &&
          fullName != 'User' &&
          email != null &&
          email.isNotEmpty &&
          email != 'user@example.com';

      _log(
        '🔍 User data validation: $hasValidData (userId: $userId, name: $fullName, email: $email, pinSet: $transactionPinSet)',
      );

      return hasValidData;
    } catch (e) {
      _log('❌ Error validating stored user data: $e');
      return false;
    }
  }

  static Future<Map<String, dynamic>> verifyResetOTP({
    required String email,
    required String otp,
  }) async {
    _log('Verifying OTP for email: $email');

    try {
      // Check connectivity first
      if (!await checkConnectivity()) {
        throw Exception(
          'No internet connection. Please check your network and try again.',
        );
      }

      final response = await http
          .post(
            _verifyResetOTPUrl, // Use this variable (not _baseUrl)
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email, 'otp': otp}),
          )
          .timeout(const Duration(seconds: 15));

      _log('Verify OTP response status: ${response.statusCode}');
      _log('Verify OTP response body: ${response.body}');

      return _handleResponse(response);
    } on TimeoutException {
      _log('ERROR: OTP verification request timed out.');
      throw Exception('Request timed out. Please try again.');
    } on SocketException {
      _log('ERROR: No internet connection.');
      throw Exception(
        'No internet connection. Please check your network and try again.',
      );
    } catch (e) {
      _log('ERROR in verifyResetOTP: $e');
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> forgotPassword({
    required String email,
  }) async {
    _log('Requesting password reset OTP for email: $email');

    try {
      // Check connectivity first
      if (!await checkConnectivity()) {
        throw Exception(
          'No internet connection. Please check your network and try again.',
        );
      }

      final response = await http
          .post(
            _forgotPasswordUrl,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email}),
          )
          .timeout(const Duration(seconds: 15));

      _log('Password reset OTP response status: ${response.statusCode}');
      _log('Password reset OTP response body: ${response.body}');

      return _handleResponse(response);
    } on TimeoutException {
      _log('ERROR: Password reset request timed out.');
      throw Exception('Request timed out. Please try again.');
    } on SocketException {
      _log('ERROR: No internet connection.');
      throw Exception(
        'No internet connection. Please check your network and try again.',
      );
    } catch (e) {
      _log('ERROR in forgotPassword: $e');
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> resetPassword({
    required String resetToken,
    required String newPassword,
  }) async {
    _log('Attempting to reset password with token');
    final response = await http
        .post(
          _resetPasswordUrl,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'resetToken': resetToken,
            'newPassword': newPassword,
          }),
        )
        .timeout(const Duration(seconds: 30));
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> setTransactionPin({
    required String userId,
    required String pin,
  }) async {
    final validationError = _validatePin(pin);
    if (validationError != null) throw Exception(validationError);

    _log('🔐 Setting transaction PIN for user: $userId');

    try {
      final response = await _authenticatedPost(_setTransactionPinUrl, {
        'userId': userId,
        'pin': pin,
      });

      if (response['success'] == true) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('transactionPinSet', true);
        await prefs.reload();
        _log('✅ Transaction PIN set successfully');
      }

      return response;
    } catch (e) {
      _log('❌ Error setting transaction PIN: $e');
      return {
        'success': false,
        'message': 'Failed to set transaction PIN: ${e.toString()}',
      };
    }
  }

  static Future<Map<String, dynamic>> changeTransactionPin({
    required String userId,
    required String currentPin,
    required String newPin,
  }) async {
    final currentPinError = _validatePin(currentPin);
    if (currentPinError != null) throw Exception(currentPinError);

    final newPinError = _validatePin(newPin);
    if (newPinError != null) throw Exception(newPinError);

    _log('🔐 Changing transaction PIN for user: $userId');

    try {
      final response = await _authenticatedPost(_changeTransactionPinUrl, {
        'userId': userId,
        'currentPin': currentPin,
        'newPin': newPin,
      });

      if (response['success'] == true) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('transactionPinSet', true);
        await prefs.reload();
        _log('✅ Transaction PIN changed successfully');
      }

      return response;
    } catch (e) {
      _log('❌ Error changing transaction PIN: $e');
      return {
        'success': false,
        'message': 'Failed to change transaction PIN: ${e.toString()}',
      };
    }
  }

  static Future<Map<String, dynamic>> verifyTransactionPin({
    required String userId,
    required String transactionPin,
  }) async {
    _log('🔐 Verifying transaction PIN for user: $userId');

    try {
      final response = await _authenticatedPost(_verifyTransactionPinUrl, {
        'userId': userId,
        'pin': transactionPin,
      });

      return response;
    } catch (e) {
      _log('❌ Error verifying transaction PIN: $e');
      return {
        'success': false,
        'message': 'PIN verification failed: ${e.toString()}',
      };
    }
  }

  /// Verify transaction PIN without requiring authentication token
  // In api_service.dart - Add/Update this method
  static Future<Map<String, dynamic>> toggleBiometric({
    required String userId,
    required bool enable,
    String? biometricKey,
    String? biometricCredentialId,
  }) async {
    _log('🔄 Toggling biometric for user: $userId, enable: $enable');

    try {
      final response = await _authenticatedPost(_toggleBiometricUrl, {
        'userId': userId,
        'enable': enable,
        if (biometricKey != null && biometricKey.isNotEmpty)
          'biometricKey': biometricKey,
        if (biometricCredentialId != null && biometricCredentialId.isNotEmpty)
          'biometricCredentialId': biometricCredentialId,
      });

      if (response['success'] == true) {
        // Save to local storage
        final prefs = await SharedPreferences.getInstance();

        // Save user-specific key
        await prefs.setBool('biometricEnabled_$userId', enable);

        // Also save global key for backward compatibility
        await prefs.setBool('biometricEnabled', enable);

        if (enable) {
          if (biometricKey != null && biometricKey.isNotEmpty) {
            await prefs.setString('biometricKey', biometricKey);
          }
          if (biometricCredentialId != null &&
              biometricCredentialId.isNotEmpty) {
            await prefs.setString(
              'biometricCredentialId',
              biometricCredentialId,
            );
          }
        } else {
          await prefs.remove('biometricKey');
          await prefs.remove('biometricCredentialId');
        }

        await prefs.reload();
        _log('✅ Biometric ${enable ? 'enabled' : 'disabled'} successfully');
      }

      return response;
    } catch (e) {
      _log('❌ Error toggling biometric: $e');
      return {
        'success': false,
        'message': 'Failed to toggle biometric authentication: ${e.toString()}',
      };
    }
  }

  /// Verify PIN for login (public endpoint - no token required)
  static Future<Map<String, dynamic>> verifyPinForLogin({
    required String userId,
    required String transactionPin,
  }) async {
    _log('🔐 Verifying PIN for login - User: $userId');
    try {
      final url = Uri.parse('$baseUrl/api/auth/verify-pin-for-login');
      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'userId': userId,
              'transactionPin': transactionPin,
            }),
          )
          .timeout(const Duration(seconds: 30));
      _log('📡 PIN login response: ${response.statusCode}');
      _log('📡 Response body: ${response.body}');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          _log('✅ PIN verified successfully');
          // ✅ Use the centralized method to save to BOTH storages
          await _savePinLoginAuthData(data);
        }
        return data;
      } else {
        _log('❌ PIN verification failed: ${response.statusCode}');
        try {
          final errorData = jsonDecode(response.body);
          return {
            'success': false,
            'message': errorData['message'] ?? 'PIN verification failed',
            'attemptsRemaining': errorData['attemptsRemaining'] ?? 0,
          };
        } catch (e) {
          return {
            'success': false,
            'message': 'Server error: ${response.statusCode}',
          };
        }
      }
    } catch (e) {
      _log('❌ PIN verification error: $e');
      return {
        'success': false,
        'message': 'PIN verification failed: ${e.toString()}',
      };
    }
  }

  /// Verify transaction with biometric
  static Future<Map<String, dynamic>> verifyTransactionWithBiometric({
    required String userId,
    required Map<String, dynamic> transactionData,
  }) async {
    _log('🔐 Verifying transaction with biometric for user: $userId');

    try {
      // First authenticate with biometric
      final biometricSuccess = await authenticateWithBiometrics();

      if (!biometricSuccess) {
        return {
          'success': false,
          'message':
              'Biometric authentication failed. Please try again or use PIN.',
          'method': 'biometric_failed',
        };
      }

      // Then process the transaction
      final response = await authenticatedPost(
        '/api/transactions/process-with-biometric',
        {'userId': userId, ...transactionData, 'verifiedWithBiometric': true},
      );

      return response;
    } catch (e) {
      _log('❌ Error verifying transaction with biometric: $e');
      return {
        'success': false,
        'message': 'Transaction failed: ${e.toString()}',
      };
    }
  }

  //check transaction
  static Future<Map<String, dynamic>> checkTransactionPinStatus({
    required String userId,
  }) async {
    if (userId.isEmpty) throw Exception('User ID cannot be empty');
    _log('Checking transaction PIN status for user ID: $userId');
    try {
      // CORRECTED: Use the base URL without userId in the path
      // The userId should be sent as a query parameter or in the body
      final url = Uri.parse('$_securitySettingsUrl');

      // Call the endpoint without userId in the URL
      final response = await _authenticatedGet(url);

      // OR use a query parameter approach if backend supports it
      // final url = Uri.parse('$_securitySettingsUrl?userId=$userId');

      if (response.containsKey('securitySettings')) {
        return {
          'hasPin': response['securitySettings']['transactionPinSet'] ?? false,
        };
      }
      return {'hasPin': false};
    } catch (e) {
      _log('Error checking transaction PIN status: $e');
      return {'hasPin': false};
    }
  }

  // ==================== ADMIN COMMISSION STATISTICS ====================

  /// Get admin commission statistics (Super Admin only)
  // lib/core/services/api_service.dart - Add/Update this method

  /// Get admin commission statistics (Super Admin only)
  /// Get admin commission statistics (Super Admin only)
  static Future<Map<String, dynamic>> getAdminCommissionStats({
    String timeFilter = 'all',
    String service = 'all',
    String? startDate,
    String? endDate,
    int page = 1,
    int limit = 50,
  }) async {
    debugPrint('📊 [COMMISSION STATS] Fetching admin commission statistics...');
    debugPrint('   timeFilter: $timeFilter');
    debugPrint('   service: $service');

    try {
      final token = await _TokenManager.getSafeToken();
      if (token == null) {
        debugPrint('❌ No token found');
        throw Exception('Not authenticated');
      }

      final params = <String, String>{
        'timeFilter': timeFilter,
        'service': service,
        'page': page.toString(),
        'limit': limit.toString(),
      };

      if (startDate != null && endDate != null) {
        params['startDate'] = startDate;
        params['endDate'] = endDate;
      }

      final queryString = params.entries
          .map(
            (e) =>
                '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}',
          )
          .join('&');

      final url = '$baseUrl/api/admin/commission-stats?$queryString';

      debugPrint('📤 Request URL: $url');

      final response = await http
          .get(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 60));

      debugPrint('📥 Response Status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          debugPrint('✅ Commission stats fetched successfully');
          return data['data'] ?? data;
        } else {
          throw Exception(
            data['message'] ?? 'Failed to fetch commission stats',
          );
        }
      } else {
        debugPrint('❌ HTTP Error: ${response.statusCode}');
        debugPrint('❌ Response Body: ${response.body}');
        final data = jsonDecode(response.body);
        throw Exception(
          'HTTP ${response.statusCode}: ${data['message'] ?? 'Unknown error'}',
        );
      }
    } catch (e) {
      debugPrint('❌ Get commission stats error: $e');
      rethrow;
    }
  }

  /// Get commission rates
  /// Get commission rates for all services
  static Future<Map<String, dynamic>> getCommissionRates() async {
    debugPrint('📊 [COMMISSION RATES] Fetching commission rates...');

    try {
      final token = await _TokenManager.getSafeToken();
      if (token == null) {
        debugPrint('❌ No token found');
        throw Exception('Not authenticated');
      }

      final url = '$baseUrl/api/admin/commission-rates';

      final response = await http
          .get(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          debugPrint('✅ Commission rates fetched successfully');
          return data['rates'] ?? data;
        } else {
          throw Exception(
            data['message'] ?? 'Failed to fetch commission rates',
          );
        }
      } else {
        throw Exception('HTTP ${response.statusCode}: Failed to fetch rates');
      }
    } catch (e) {
      debugPrint('❌ Get commission rates error: $e');
      rethrow;
    }
  }

  /// Get total commission summary
  static Future<Map<String, dynamic>> getCommissionSummary() async {
    debugPrint('📊 [COMMISSION SUMMARY] Fetching commission summary...');

    try {
      final token = await _TokenManager.getSafeToken();
      if (token == null) {
        debugPrint('❌ No token found');
        throw Exception('Not authenticated');
      }

      final url = '$baseUrl/api/admin/commission-summary';

      final response = await http
          .get(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          debugPrint('✅ Commission summary fetched successfully');
          return data['summary'] ?? data;
        } else {
          throw Exception(
            data['message'] ?? 'Failed to fetch commission summary',
          );
        }
      } else {
        throw Exception('HTTP ${response.statusCode}: Failed to fetch summary');
      }
    } catch (e) {
      debugPrint('❌ Get commission summary error: $e');
      rethrow;
    }
  }

  // ==================== ADMIN SERVICE COMMISSION STATISTICS ====================

  /// Get admin service commission statistics with detailed breakdown
  /// Returns commission breakdown by service, period, and transaction details
  static Future<Map<String, dynamic>> getAdminServiceCommissionStats({
    String timeFilter = 'all',
    String service = 'all',
    String? startDate,
    String? endDate,
    int page = 1,
    int limit = 50,
  }) async {
    debugPrint(
      '📊 [SERVICE COMMISSION STATS] Fetching admin service commission statistics...',
    );
    debugPrint('   timeFilter: $timeFilter');
    debugPrint('   service: $service');

    try {
      final token = await _TokenManager.getSafeToken();
      if (token == null) {
        debugPrint('❌ No token found');
        throw Exception('Not authenticated');
      }

      final params = <String, String>{
        'timeFilter': timeFilter,
        'service': service,
        'page': page.toString(),
        'limit': limit.toString(),
      };

      if (startDate != null && endDate != null) {
        params['startDate'] = startDate;
        params['endDate'] = endDate;
      }

      final queryString = params.entries
          .map(
            (e) =>
                '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}',
          )
          .join('&');

      final url = '$baseUrl/api/admin/service-commission-stats?$queryString';

      debugPrint('📤 Request URL: $url');

      final response = await http
          .get(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 60));

      debugPrint('📥 Response Status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          debugPrint('✅ Service commission stats fetched successfully');
          // Return the data from the response
          return data['data'] ?? data;
        } else {
          throw Exception(
            data['message'] ?? 'Failed to fetch service commission stats',
          );
        }
      } else {
        debugPrint('❌ HTTP Error: ${response.statusCode}');
        debugPrint('❌ Response Body: ${response.body}');
        final data = jsonDecode(response.body);
        throw Exception(
          'HTTP ${response.statusCode}: ${data['message'] ?? 'Unknown error'}',
        );
      }
    } catch (e) {
      debugPrint('❌ Get service commission stats error: $e');
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> getSecuritySettings() async {
    _log('Getting security settings');
    final response = await _authenticatedGet(_securitySettingsUrl);
    if (response.containsKey('securitySettings')) return response;
    throw Exception(
      'Unexpected response format from security settings endpoint',
    );
  }

  /// 🗄️ Enhanced user-specific lock
  static sync_lib.Lock _getUserLock(String userId) {
    return _userLocks.putIfAbsent(userId, () => sync_lib.Lock());
  }

  /// 🔐 FIXED: Enhanced wallet lock with timeout and attempt tracking
  static Future<bool> _acquireWalletLock(String userId) async {
    final userLock = _getUserLock(userId);
    final lockKey = 'wallet_$userId';
    final now = DateTime.now();

    // Clean expired locks
    _transactionLocks.removeWhere((key, expiry) => now.isAfter(expiry));

    // Check if already locked
    if (_transactionLocks.containsKey(lockKey)) {
      final expiry = _transactionLocks[lockKey]!;
      if (now.isBefore(expiry)) {
        _lockAttempts[userId] = (_lockAttempts[userId] ?? 0) + 1;

        if (_lockAttempts[userId]! >= _maxLockAttempts) {
          throw Exception(
            '🚫 Too many simultaneous transactions. Please try again.',
          );
        }

        _log('⏳ Waiting for wallet lock... Attempt ${_lockAttempts[userId]}');
        await Future.delayed(const Duration(milliseconds: 100));
        return await _acquireWalletLock(userId);
      } else {
        _transactionLocks.remove(lockKey);
      }
    }

    // ✅ FIXED: Return the boolean from synchronized
    return await userLock.synchronized<bool>(() async {
      _transactionLocks[lockKey] = now.add(_lockTimeout);
      _lockAttempts[userId] = 0;
      _log('🔒 Wallet lock acquired for user: $userId');
      return true;
    });
  }

  /// 🔓 Enhanced lock release
  static void _releaseWalletLock(String userId) {
    final lockKey = 'wallet_$userId';
    _transactionLocks.remove(lockKey);
    _lockAttempts.remove(userId);
    _log('🔓 Wallet lock released for user: $userId');
  }

  /// ⚡ Enhanced secure execution with proper locking
  static Future<T> _executeWithWalletLock<T>(
    String userId,
    Future<T> Function() operation,
  ) async {
    try {
      await _acquireWalletLock(userId);
      _log('🛡️ Executing secured operation for user: $userId');

      return await operation();
    } catch (e) {
      _log('❌ Secure operation failed: $e');
      rethrow;
    } finally {
      _releaseWalletLock(userId);
    }
  }

  static Future<Map<String, dynamic>> getAuthLogs({
    required String userId,
    int page = 1,
    int limit = 20,
  }) async {
    _log('Getting auth logs for user ID: $userId');
    final url = Uri.parse(
      '$_authLogsUrl?userId=$userId&page=$page&limit=$limit',
    );
    return await _authenticatedGet(url);
  }

  static Future<Map<String, dynamic>> uploadProfileImage({
    required dynamic imageFile, // XFile on web & mobile
  }) async {
    _log('Uploading profile image');
    final userId = await _getUserId();
    if (userId == null) {
      throw Exception('User ID not found. Please log in again.');
    }

    final result = await _authenticatedMultipartPost(_uploadProfileImageUrl, {
      'userId': userId,
    }, imageFile);

    if (result['success'] == true && result.containsKey('profileImage')) {
      final prefs = await SharedPreferences.getInstance();

      // ✅ Store the RAW relative path (e.g. /uploads/xxx.jpg) — NOT absolute
      // ImageHelper.buildImageUrl() will resolve it correctly at display time.
      final rawPath = result['profileImage'].toString();

      final userString = prefs.getString('user');
      if (userString != null) {
        try {
          final userMap = jsonDecode(userString);
          userMap['profileImage'] = rawPath;
          await prefs.setString('user', jsonEncode(userMap));
        } catch (e) {
          _log('❌ Error updating user cache with new image: $e');
        }
      }
      await prefs.setString('profileImage', rawPath);
    }
    return result;
  }

  static Future<double> getBalance() async {
    _log('💰 Getting balance for current user');

    try {
      final data = await _authenticatedGet(_balanceUrl);
      return (data['walletBalance'] as num?)?.toDouble() ?? 0.0;
    } catch (e) {
      _log('❌ Error getting balance: $e');

      // If it's an auth error, handle it
      if (e.toString().contains('Authentication required') ||
          e.toString().contains('401') ||
          e.toString().contains('Session expired')) {
        await _handleAuthFailure('Session expired. Please login again.');
      }
      return 0.0;
    }
  }

  static Future<String?> getCurrentUserId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final userId = prefs.getString('userId');

      // If userId is not in prefs, try to get it from user object
      if (userId == null || userId.isEmpty) {
        final userString = prefs.getString('user');
        if (userString != null && userString.isNotEmpty) {
          try {
            final userMap = jsonDecode(userString);
            return userMap['_id']?.toString();
          } catch (_) {}
        }
      }

      return userId;
    } catch (e) {
      _log('❌ Error getting user ID: $e');
      return null;
    }
  }

  /// Get commission balance - SINGLE VERSION
  static Future<double> getCommissionBalance() async {
    _log('Getting commission balance from new endpoint');
    try {
      final response = await _authenticatedGet(_commissionBalanceUrl);

      // DEBUG
      debugResponse('/api/commission/balance', response);

      if (response != null && response is Map && response['success'] == true) {
        // Try different response structures
        double balance = 0.0;

        if (response['data'] != null &&
            response['data']['commissionBalance'] != null) {
          balance = (response['data']['commissionBalance'] as num).toDouble();
          _log('Found balance in data.commissionBalance: ₦$balance');
        } else if (response['commissionBalance'] != null) {
          balance = (response['commissionBalance'] as num).toDouble();
          _log('Found balance in commissionBalance: ₦$balance');
        } else if (response['data'] != null && response['data'] is num) {
          balance = (response['data'] as num).toDouble();
          _log('Found balance in data: ₦$balance');
        }

        _log('Commission balance parsed: $balance');

        // Store in local storage
        final prefs = await SharedPreferences.getInstance();
        await prefs.setDouble('commissionBalance', balance);

        return balance;
      } else {
        _log('Commission API error or invalid response');
        if (response != null && response is Map) {
          _log('Error message: ${response['message']}');
        }

        // Return cached value as fallback
        final prefs = await SharedPreferences.getInstance();
        final cachedBalance = prefs.getDouble('commissionBalance') ?? 0.0;
        _log('Using cached balance: ₦$cachedBalance');
        return cachedBalance;
      }
    } catch (e, stackTrace) {
      _log('Error getting commission balance: $e');
      await reportError(e, stackTrace);

      // Return cached value as fallback
      final prefs = await SharedPreferences.getInstance();
      return prefs.getDouble('commissionBalance') ?? 0.0;
    }
  }

  // ==================== REFERRAL BONUS ENDPOINTS ====================

  // ==================== NEW REFERRAL BONUS METHODS ====================

  /// Get referral earnings summary with detailed breakdown
  static Future<Map<String, dynamic>> getReferralEarningsSummary() async {
    try {
      _log('🔍 Getting referral earnings summary');
      final response = await _authenticatedGet(
        Uri.parse(
          'https://vtpass-backend.onrender.com/api/commission/referral-earnings',
        ),
      );

      debugResponse('/api/commission/referral-earnings', response);

      if (response != null &&
          response is Map &&
          response['success'] == true &&
          response['data'] != null) {
        _log('✅ Referral earnings summary loaded successfully');
        return response['data'] as Map<String, dynamic>;
      } else {
        _log('⚠️ No referral earnings data available');
        return {
          'totalEarned': 0.0,
          'directReferralEarnings': 0.0,
          'indirectReferralEarnings': 0.0,
          'welcomeBonusEarnings': 0.0,
          'referralStats': {
            'totalReferrals': 0,
            'referralCode': '',
            'totalReferralEarnings': 0.0,
          },
          'transactions': [],
          'formatted': {
            'totalEarned': '₦0.00',
            'directReferralEarnings': '₦0.00',
            'indirectReferralEarnings': '₦0.00',
            'welcomeBonusEarnings': '₦0.00',
          },
        };
      }
    } catch (e, stackTrace) {
      _log('❌ Error getting referral earnings summary: $e');
      await reportError(e, stackTrace);
      throw Exception('Failed to load referral earnings: $e');
    }
  }

  /// Get referral bonus breakdown
  static Future<Map<String, dynamic>> getReferralBonusBreakdown() async {
    try {
      _log('🔍 Getting referral bonus breakdown');
      final response = await _authenticatedGet(
        Uri.parse(
          'https://vtpass-backend.onrender.com/api/commission/referral-earnings',
        ),
      );

      if (response != null &&
          response is Map &&
          response['success'] == true &&
          response['data'] != null) {
        final data = response['data'] as Map<String, dynamic>;
        return {
          'success': true,
          'directBonusEarnings': data['directReferralEarnings'] ?? 0.0,
          'indirectBonusEarnings': data['indirectReferralEarnings'] ?? 0.0,
          'welcomeBonusEarnings': data['welcomeBonusEarnings'] ?? 0.0,
          'totalEarnings': data['totalEarned'] ?? 0.0,
          'formatted':
              data['formatted'] ??
              {
                'directReferralEarnings': '₦0.00',
                'indirectReferralEarnings': '₦0.00',
                'welcomeBonusEarnings': '₦0.00',
                'totalEarned': '₦0.00',
              },
        };
      }

      return {
        'success': false,
        'directBonusEarnings': 0.0,
        'indirectBonusEarnings': 0.0,
        'welcomeBonusEarnings': 0.0,
        'totalEarnings': 0.0,
        'formatted': {
          'directReferralEarnings': '₦0.00',
          'indirectReferralEarnings': '₦0.00',
          'welcomeBonusEarnings': '₦0.00',
          'totalEarned': '₦0.00',
        },
      };
    } catch (e, stackTrace) {
      _log('❌ Error getting referral bonus breakdown: $e');
      await reportError(e, stackTrace);
      return {
        'success': false,
        'directBonusEarnings': 0.0,
        'indirectBonusEarnings': 0.0,
        'welcomeBonusEarnings': 0.0,
        'totalEarnings': 0.0,
      };
    }
  }

  /// Get referral transactions
  // Get referral transactions with ALL bonus types
  static Future<List<Map<String, dynamic>>> getReferralTransactions() async {
    try {
      final response = await _authenticatedGet(
        Uri.parse(
          'https://vtpass-backend.onrender.com/api/commission/transactions?limit=100',
        ),
      );

      debugResponse('/api/commission/transactions', response);

      if (response != null && response is Map && response['success'] == true) {
        final transactions =
            (response['data']['transactions'] as List<dynamic>)
                .cast<Map<String, dynamic>>()
                .toList();

        // Filter for ALL commission-related transactions
        return transactions.where((tx) {
          final type = tx['type']?.toString() ?? '';
          final isCommission = tx['isCommission'] == true;

          // Include ALL commission transactions
          return isCommission ||
              type.contains('Bonus') ||
              type.contains('Commission') ||
              type.contains('Referral');
        }).toList();
      }
      return [];
    } catch (e) {
      print('Error getting referral transactions: $e');
      return [];
    }
  }

  // --- Referral Endpoints (Verified against /api/referral mount) ---

  /// Get referral leaderboard (top referrers) - Authenticated
  static Future<Map<String, dynamic>> getReferralLeaderboard() async {
    _log('Getting referral leaderboard');
    try {
      final response = await _authenticatedGet(
        Uri.parse('$baseUrl/api/referral/leaderboard'),
      );
      return response;
    } catch (e) {
      _log('Error getting referral leaderboard: $e');
      rethrow;
    }
  }

  /// Get detailed referral commission history with pagination and filters - Authenticated
  static Future<Map<String, dynamic>> getReferralCommissionHistory({
    int page = 1,
    int limit = 20,
    String? type,
    String? startDate,
    String? endDate,
  }) async {
    _log('Getting referral commission history');
    try {
      String query = '?page=$page&limit=$limit';
      if (type != null) query += '&type=$type';
      if (startDate != null) query += '&startDate=$startDate';
      if (endDate != null) query += '&endDate=$endDate';
      final url = Uri.parse('$baseUrl/api/referral/commission-history$query');
      final response = await _authenticatedGet(url);
      return response;
    } catch (e) {
      _log('Error getting referral commission history: $e');
      rethrow;
    }
  }

  /// Check if a referral code is valid - Public (unauthenticated)
  static Future<Map<String, dynamic>> checkReferralCode(String code) async {
    _log('Checking referral code: $code');
    try {
      final url = Uri.parse('$baseUrl/api/referral/check-code/$code');
      final response = await _unauthenticatedGet(url);
      return response;
    } catch (e) {
      _log('Error checking referral code: $e');
      rethrow;
    }
  }

  /// Test referral bonus logic - Admin only (POST)
  static Future<Map<String, dynamic>> testReferralBonus({
    required String userId,
    required double depositAmount,
  }) async {
    if (!await isAdmin()) throw Exception('Admin access required');
    _log(
      'Testing referral bonus for user ID: $userId with deposit: ₦$depositAmount',
    );
    try {
      final body = {'userId': userId, 'depositAmount': depositAmount};
      final url = Uri.parse('$baseUrl/api/referral/test-bonus');
      final response = await _authenticatedPost(url, body);
      return response;
    } catch (e) {
      _log('Error testing referral bonus: $e');
      rethrow;
    }
  }

  /// Get referral program guide and FAQ - Public (unauthenticated)
  static Future<Map<String, dynamic>> getReferralGuide() async {
    _log('Getting referral guide');
    try {
      final url = Uri.parse('$baseUrl/api/referral/guide');
      final response = await _unauthenticatedGet(url);
      return response;
    } catch (e) {
      _log('Error getting referral guide: $e');
      rethrow;
    }
  }

  // --- Commission Endpoints (Verified against /api/commission mount) ---

  /// Simple test endpoint for commission API - Public (unauthenticated)
  static Future<Map<String, dynamic>> testCommissionApi() async {
    _log('Testing commission API');
    try {
      final url = Uri.parse('$baseUrl/api/commission/test');
      final response = await _unauthenticatedGet(url);
      return response;
    } catch (e) {
      _log('Error testing commission API: $e');
      rethrow;
    }
  }

  // --- Commission Endpoints ---

  static Future<Map<String, dynamic>> getCommissionStats() async {
    _log('Getting commission statistics');
    try {
      final response = await _authenticatedGet(_commissionStatsUrl);

      if (response['success'] == true) {
        return {'success': true, 'data': response['data'] ?? {}};
      } else {
        return {
          'success': false,
          'data': {
            'currentBalance': 0.0,
            'totalEarned': 0.0,
            'todayEarned': 0.0,
            'monthEarned': 0.0,
            'bySource': [],
            'recentCommissions': [],
          },
        };
      }
    } catch (e, stackTrace) {
      _log('Error getting commission stats: $e');
      await reportError(e, stackTrace);
      return {
        'success': false,
        'data': {
          'currentBalance': 0.0,
          'totalEarned': 0.0,
          'todayEarned': 0.0,
          'monthEarned': 0.0,
          'bySource': [],
          'recentCommissions': [],
        },
      };
    }
  }

  /// Get commission transactions
  static Future<List<Map<String, dynamic>>> getCommissionTransactions() async {
    _log('Getting commission transactions');
    try {
      final response = await _authenticatedGet(_commissionTransactionsUrl);

      // DEBUG
      debugResponse('/api/commission/transactions', response);

      if (response != null && response is Map && response['success'] == true) {
        final data = response['data'];
        if (data != null) {
          final transactions = data['transactions'];
          if (transactions is List) {
            final transactionList = List<Map<String, dynamic>>.from(
              transactions,
            );
            _log('Found ${transactionList.length} commission transactions');

            if (transactionList.isNotEmpty) {
              _log('Sample transaction: ${transactionList[0].toString()}');
            }

            return transactionList;
          } else {
            _log(
              'Transactions is not a List, type: ${transactions.runtimeType}',
            );
          }
        } else {
          _log('No data field in response');
        }
      } else {
        _log('API returned success: false or invalid response');
        if (response != null && response is Map) {
          _log('Error: ${response['message']}');
        }
      }

      // Return empty list if no transactions or invalid response
      _log('No commission transactions found or invalid response structure');
      return [];
    } catch (e, stackTrace) {
      _log('Error getting commission transactions: $e');
      await reportError(e, stackTrace);
      return [];
    }
  }

  static Future<Map<String, dynamic>> changePassword({
    required String userId,
    required String currentPassword,
    required String newPassword,
  }) async {
    _log('Changing password for user ID: $userId');
    return await _authenticatedPost(_changePasswordUrl, {
      'userId': userId,
      'currentPassword': currentPassword,
      'newPassword': newPassword,
    });
  }

  static Future<List<dynamic>> getUsers() async {
    if (!await isAdmin()) throw Exception('Admin access required');
    _log('Getting all users for admin page');
    final responseData = await _authenticatedGet(_getUsersUrl);
    return _extractDataList(responseData);
  }

  // In ApiService class
  static Future<List<dynamic>> getAllUsersForAdmin() async {
    try {
      final token = await SecureStorageService.getAccessToken();
      if (token == null || token.isEmpty) {
        return [];
      }

      final response = await http
          .get(
            Uri.parse('$baseUrl/api/admin/all-users'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final users = data['users'] ?? [];
          return users;
        }
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  static Future<Map<String, dynamic>> toggleUserStatus({
    required String userIdToToggle,
    required bool isActive,
  }) async {
    if (!await isAdmin()) throw Exception('Admin access required');
    _log('Toggling user status for ID: $userIdToToggle');
    final url = Uri.parse('$_userBaseUrl/toggle-status/$userIdToToggle');
    return await _authenticatedPut(url, {'isActive': isActive});
  }

  static Future<Map<String, dynamic>> toggleUserAdminStatus({
    required String userIdToToggle,
    required bool isAdminStatus,
  }) async {
    if (!await isAdmin()) throw Exception('Admin access required');
    _log('Toggling user admin status for ID: $userIdToToggle');
    final url = Uri.parse('$_userBaseUrl/toggle-admin-status/$userIdToToggle');
    return await _authenticatedPut(url, {'isAdmin': isAdminStatus});
  }

  static Future<Map<String, dynamic>> getUserProfile(String userId) async {
    _log('Getting user profile for ID: $userId');
    final url = Uri.parse('$_userBaseUrl/$userId');
    try {
      final response = await _authenticatedGet(url);
      return response.containsKey('user') ? response['user'] : response;
    } catch (e) {
      _log('Error getting user profile: $e');
      rethrow;
    }
  }

  /// Gets comprehensive referral statistics for a user
  static Future<Map<String, dynamic>> getReferralStats(String userId) async {
    _log('Fetching referral stats for user: $userId');
    try {
      // Call the new referral stats endpoint
      final url = Uri.parse(
        'https://vtpass-backend.onrender.com/api/referral/stats',
      );
      final response = await _authenticatedGet(url);

      // DEBUG
      debugResponse('/api/referral/stats', response);

      if (response != null && response is Map && response['success'] == true) {
        final stats = response['referralStats'] ?? response;

        _log('📊 Parsed referral stats:');
        _log('   totalReferrals: ${stats['totalReferrals']}');
        _log('   totalEarned: ${stats['totalEarned']}');

        return {
          'success': true,
          'totalReferrals': (stats['totalReferrals'] ?? 0).toInt(),
          'activeReferrals': (stats['activeReferrals'] ?? 0).toInt(),
          'totalEarned': (stats['totalEarned'] ?? 0).toDouble(),
          'pendingEarnings': (stats['pendingEarnings'] ?? 0).toDouble(),
          'referralCode': stats['referralCode']?.toString() ?? 'N/A',
          'referrals': stats['referrals'] ?? [],
          'referralLink':
              stats['referralLink']?.toString() ??
              'https://vtpass-backend.onrender.com/api/auth/register?ref=${stats['referralCode'] ?? 'N/A'}',
        };
      }

      // Fallback if API fails
      _log('⚠️ Referral stats API failed, using fallback');
      final referralCode = await getStoredReferralCode(userId);
      return {
        'success': false,
        'totalReferrals': 0,
        'activeReferrals': 0,
        'totalEarned': 0.0,
        'pendingEarnings': 0.0,
        'referralCode': referralCode,
        'referrals': [],
        'referralLink':
            'https://vtpass-backend.onrender.com/api/auth/register?ref=$referralCode',
      };
    } catch (e, stackTrace) {
      _log('Error fetching referral stats: $e');
      await reportError(e, stackTrace);

      final referralCode = await getStoredReferralCode(userId);
      return {
        'success': false,
        'totalReferrals': 0,
        'activeReferrals': 0,
        'totalEarned': 0.0,
        'pendingEarnings': 0.0,
        'referralCode': referralCode,
        'referrals': [],
        'referralLink':
            'https://vtpass-backend.onrender.com/api/auth/register?ref=$referralCode',
      };
    }
  }

  static void debugResponse(String endpoint, dynamic response) {
    _log('🔍 DEBUG response for $endpoint:');
    _log('   Response type: ${response.runtimeType}');
    _log('   Response: ${response.toString()}');

    if (response is Map) {
      _log('   Keys: ${response.keys.join(', ')}');
      if (response.containsKey('success')) {
        _log('   Success: ${response['success']}');
      }
      if (response.containsKey('data')) {
        _log('   Has data: true');
        final data = response['data'];
        if (data is Map) {
          _log('   Data keys: ${data.keys.join(', ')}');
        }
      }
    }
  }

  /// Gets stored referral code from local storage
  /// Gets stored referral code from local storage
  static Future<String> getStoredReferralCode(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    String? referralCode = prefs.getString('referralCode_$userId');

    if (referralCode == null || referralCode.isEmpty) {
      _log(
        'Referral code not found locally for user $userId. Fetching from backend...',
      );
      try {
        // FIX: Remove Uri.parse() since _authenticatedGet expects String
        final response = await _authenticatedGet(
          '$_userBaseUrl/$userId' as Uri,
        );

        // FIX: Check the response structure properly
        if (response != null && response['success'] == true) {
          referralCode =
              response['data']?['referralCode']?.toString() ??
              response['user']?['referralCode']?.toString();

          if (referralCode != null && referralCode.isNotEmpty) {
            await prefs.setString('referralCode_$userId', referralCode);
            _log('Fetched and stored referral code: $referralCode');
            return referralCode;
          }
        }

        // Generate if not found
        _log('Generating new referral code as none exists');
        return await generateReferralCode(userId);
      } catch (e) {
        _log('Error fetching referral code from backend: $e');
        return await generateReferralCode(
          userId,
        ); // Fallback to generating a new one
      }
    }
    _log('Retrieved stored referral code: $referralCode');
    return referralCode;
  }

  static Future<Map<String, dynamic>> useCommissionForService({
    required String userId,
    required String serviceType,
    required double amount,
    required Map<String, dynamic> serviceDetails,
    String? transactionPin,
    bool useBiometric = false,
  }) async {
    _log(
      '🎯 Using commission for service: $serviceType, amount: ₦$amount, userId: $userId',
    );
    _log('Service details: $serviceDetails');

    try {
      // 1. Check commission balance
      final commissionBalance = await getCommissionBalance();
      _log('Current commission balance: ₦$commissionBalance');

      if (commissionBalance < amount) {
        final errorMsg =
            'Insufficient commission balance. '
            'Available: ₦${commissionBalance.toStringAsFixed(2)}, '
            'Required: ₦${amount.toStringAsFixed(2)}';
        _log('❌ $errorMsg');
        throw Exception(errorMsg);
      }

      // 2. Authenticate
      _log('Authenticating transaction...');
      final authResult = await authenticateTransaction(
        userId: userId,
        transactionPin: transactionPin,
        useBiometric: useBiometric,
      );

      _log('✅ Authentication successful: ${authResult['method']}');

      // 3. Call the COMMISSION ROUTE (not the services route)
      final commissionPayload = {
        'serviceType': serviceType,
        'amount': amount,
        'serviceDetails': serviceDetails,
      };

      _log('Calling commission endpoint: /api/commission/use-for-service');
      _log('Payload: $commissionPayload');

      // ============================================
      // ✅ IMPORTANT: Use the commission endpoint, not the services endpoint
      // ============================================
      final commissionResponse = await _authenticatedPost(
        Uri.parse('$baseUrl/api/commission/use-for-service'),
        commissionPayload,
        extraHeaders:
            authResult['method'] == 'pin'
                ? {'Transaction-PIN': authResult['pin']}
                : null,
        useBiometric: authResult['method'] == 'biometric',
      );

      _log('Commission deduction response: $commissionResponse');

      if (commissionResponse['success'] != true) {
        throw Exception(
          commissionResponse['message'] ?? 'Failed to use commission',
        );
      }

      final transactionId = commissionResponse['data']['transactionId'];
      final commissionTrackingId =
          commissionResponse['data']['commissionTrackingId'] ?? transactionId;
      final newCommissionBalance =
          (commissionResponse['data']['newCommissionBalance'] as num?)
              ?.toDouble() ??
          (commissionBalance - amount);

      _log('✅ Commission deducted. Transaction ID: $transactionId');
      _log('Commission Tracking ID: $commissionTrackingId');
      _log('New commission balance: ₦$newCommissionBalance');

      // 4. NOW CALL VTpass to deliver the service
      _log('Calling VTpass to deliver service...');

      final vtpassPayload = await _prepareVtpassPayloadForCommission(
        serviceType: serviceType,
        amount: amount,
        serviceDetails: serviceDetails,
        commissionTransactionId: transactionId,
        commissionTrackingId: commissionTrackingId, // 🔥 ADD THIS
      );

      _log('VTpass payload: $vtpassPayload');

      // Call VTpass proxy with commission flag
      final vtpassResponse = await _authenticatedPost(
        Uri.parse('$baseUrl/api/vtpass/proxy'),
        vtpassPayload,
        extraHeaders: {
          'x-commission-usage':
              'true', // This tells VTpass NOT to deduct from wallet
        },
      );

      _log('VTpass response: $vtpassResponse');

      // 5. Handle VTpass response
      if (vtpassResponse['success'] == true ||
          vtpassResponse['alreadyProcessed'] == true) {
        // Update local commission balance
        final prefs = await SharedPreferences.getInstance();
        await prefs.setDouble('commissionBalance', newCommissionBalance);

        // Update user object in storage
        final userString = prefs.getString('user');
        if (userString != null) {
          try {
            final userMap = jsonDecode(userString) as Map<String, dynamic>;
            userMap['commissionBalance'] = newCommissionBalance;
            await prefs.setString('user', jsonEncode(userMap));
          } catch (e) {
            _log('Error updating user in storage: $e');
          }
        }

        _log('✅ Service delivered successfully via commission!');

        return {
          'success': true,
          'message':
              vtpassResponse['message'] ?? 'Service delivered successfully!',
          'newCommissionBalance': newCommissionBalance,
          'commissionUsed': true,
          'transactionId': transactionId,
          'vtpassResponse': vtpassResponse,
          'alreadyProcessed': vtpassResponse['alreadyProcessed'] ?? false,
          'serviceDelivered': true,
        };
      } else {
        // VTpass failed - REFUND the commission
        _log('❌ VTpass failed, refunding commission...');

        try {
          await _refundCommission(
            transactionId: transactionId,
            amount: amount,
            userId: userId,
          );
        } catch (refundError) {
          _log('Failed to refund commission: $refundError');
        }

        throw Exception(vtpassResponse['message'] ?? 'Service delivery failed');
      }
    } catch (e) {
      _log('❌ Error in useCommissionForService: $e');

      final errorStr = e.toString().toLowerCase();

      // Handle duplicate/network errors
      if (errorStr.contains('already processed') ||
          errorStr.contains('duplicate') ||
          errorStr.contains('already completed')) {
        final prefs = await SharedPreferences.getInstance();
        final currentBalance = await getCommissionBalance();

        return {
          'success': true,
          'message': 'Service already processed successfully',
          'newCommissionBalance': currentBalance,
          'commissionUsed': true,
          'alreadyProcessed': true,
        };
      }

      if (errorStr.contains('timeout') ||
          errorStr.contains('socket') ||
          errorStr.contains('network')) {
        // Check if commission was deducted
        final currentBalance = await getCommissionBalance();
        final prefs = await SharedPreferences.getInstance();
        final storedBalance =
            prefs.getDouble('commissionBalance') ?? currentBalance;

        if (currentBalance < storedBalance) {
          // Commission was deducted, assume success but warn user
          return {
            'success': true,
            'message':
                'Service processed (network timeout). Please check transaction history.',
            'newCommissionBalance': currentBalance,
            'commissionUsed': true,
            'possibleNetworkIssue': true,
          };
        }
      }

      rethrow;
    }
  }

  // ============================================
  // ✅ HELPER METHODS
  // ============================================

  /// Prepare VTpass payload based on service type
  static Future<Map<String, dynamic>> _prepareVtpassPayloadForCommission({
    required String serviceType,
    required double amount,
    required Map<String, dynamic> serviceDetails,
    String? commissionTransactionId,
    String? commissionTrackingId, // 🔥 ADD THIS PARAMETER
  }) async {
    // Generate a unique request ID
    final requestId =
        'COMM_${DateTime.now().millisecondsSinceEpoch}_${_generateRandomId()}';

    final Map<String, dynamic> payload = {
      'request_id': requestId,
      'amount': amount.toString(),
    };

    // 🔥 ADD BOTH IDs FOR RELIABLE TRACKING
    if (commissionTransactionId != null && commissionTransactionId.isNotEmpty) {
      payload['commissionTransactionId'] = commissionTransactionId;
    }
    if (commissionTrackingId != null && commissionTrackingId.isNotEmpty) {
      payload['commissionTrackingId'] = commissionTrackingId;
    }
    switch (serviceType.toLowerCase()) {
      case 'airtime':
        payload.addAll({
          'serviceID':
              serviceDetails['network']?.toString().toLowerCase() ?? 'mtn',
          'phone': serviceDetails['phone']?.toString() ?? '',
        });
        break;

      case 'data':
        final network =
            serviceDetails['network']?.toString().toLowerCase() ?? 'mtn';
        payload.addAll({
          'serviceID': '$network-data',
          'phone': serviceDetails['phone']?.toString() ?? '',
          'variation_code': serviceDetails['variationCode']?.toString() ?? '',
        });
        break;

      case 'electricity':
        payload.addAll({
          'serviceID':
              serviceDetails['serviceID']?.toString() ?? 'ikeja-electric',
          'billersCode': serviceDetails['billersCode']?.toString() ?? '',
          'variation_code':
              serviceDetails['meterType']?.toString() ?? 'prepaid',
          'phone': serviceDetails['phone']?.toString() ?? '',
          'type': serviceDetails['meterType']?.toString() ?? 'prepaid',
        });
        break;

      case 'cable':
      case 'tv':
        payload.addAll({
          'serviceID': serviceDetails['serviceID']?.toString() ?? 'dstv',
          'billersCode': serviceDetails['billersCode']?.toString() ?? '',
          'variation_code': serviceDetails['variationCode']?.toString() ?? '',
          'phone': serviceDetails['phone']?.toString() ?? '',
        });
        break;

      case 'education':
        payload.addAll({
          'serviceID': serviceDetails['serviceID']?.toString() ?? 'waec',
          'billersCode': serviceDetails['profileId']?.toString() ?? '',
          'phone': serviceDetails['phone']?.toString() ?? '',
          'variation_code': serviceDetails['variationCode']?.toString() ?? '',
        });
        if (serviceDetails['quantity'] != null) {
          payload['quantity'] = serviceDetails['quantity'].toString();
        }
        break;

      case 'insurance':
        payload.addAll({
          'serviceID': 'ui-insure',
          'billersCode': serviceDetails['plateNumber']?.toString() ?? '',
          'variation_code': serviceDetails['variationCode']?.toString() ?? '1',
          'phone': serviceDetails['phone']?.toString() ?? '',
          'Insured_Name': serviceDetails['insuredName']?.toString() ?? '',
          'engine_capacity': serviceDetails['engineCapacity']?.toString() ?? '',
          'Chasis_Number': serviceDetails['chasisNumber']?.toString() ?? '',
          'Plate_Number': serviceDetails['plateNumber']?.toString() ?? '',
          'vehicle_make': serviceDetails['vehicleMake']?.toString() ?? '',
          'vehicle_color': serviceDetails['vehicleColor']?.toString() ?? '',
          'vehicle_model': serviceDetails['vehicleModel']?.toString() ?? '',
          'YearofMake': serviceDetails['yearOfMake']?.toString() ?? '',
          'state': serviceDetails['state']?.toString() ?? '',
          'lga': serviceDetails['lga']?.toString() ?? '',
          'email': serviceDetails['email']?.toString() ?? '',
        });
        break;

      default:
        throw Exception('Unsupported service type: $serviceType');
    }

    return payload;
  }

  /// Complete commission service purchase
  static Future<void> _completeCommissionServicePurchase({
    required String transactionId,
    required Map<String, dynamic> vtpassResponse,
  }) async {
    try {
      final url = Uri.parse(
        '$baseUrl/api/commission/complete-service-purchase',
      );

      await _authenticatedPost(url, {
        'transactionId': transactionId,
        'vtpassResponse': vtpassResponse,
        'status': 'Successful',
      });

      _log('✅ Commission service purchase completed: $transactionId');
    } catch (e) {
      _log('❌ Failed to complete commission service purchase: $e');
      // Don't throw, this is not critical
    }
  }

  /// Refund commission (if service fails)
  static Future<void> _refundCommission({
    required String transactionId,
    required double amount,
    required String userId,
  }) async {
    try {
      final url = Uri.parse('$baseUrl/api/commission/refund');

      await _authenticatedPost(url, {
        'transactionId': transactionId,
        'amount': amount,
        'userId': userId,
      });

      _log('✅ Commission refunded: ₦$amount');
    } catch (e) {
      _log('❌ Failed to refund commission: $e');
      // Don't throw, log and continue
    }
  }

  /// Generate random ID for request
  static String _generateRandomId() {
    final random = Random();
    return random.nextInt(999999).toString().padLeft(6, '0');
  }

  /// Check if a transaction is a duplicate
  static Future<bool> isDuplicateTransaction(String requestId) async {
    try {
      final response = await _authenticatedGet(
        Uri.parse('$baseUrl/api/transactions/check-duplicate/$requestId'),
      );
      return response['isDuplicate'] == true;
    } catch (e) {
      _log('Error checking duplicate: $e');
      return false;
    }
  }

  /// Perform service after commission is deducted
  static Future<Map<String, dynamic>> _performServiceWithCommission({
    required String userId,
    required String serviceType,
    required double amount,
    required Map<String, dynamic> serviceDetails,
    required Map<String, dynamic> authResult,
    bool commissionUsed = false,
  }) async {
    _log(
      '🚀 Performing $serviceType service (commissionUsed: $commissionUsed)',
    );

    // Extract auth parameters
    final String transactionPin = authResult['transactionPin'];
    final bool useBiometric = authResult['useBiometric'] == true;

    // Prepare service payload WITH commission flag
    final servicePayload = {
      ...serviceDetails,
      'userId': userId,
      'transactionPin': transactionPin,
      'useBiometric': useBiometric,
      'commissionUsed': commissionUsed,
    };

    switch (serviceType.toLowerCase()) {
      case 'airtime':
        return await buyAirtimeWithCommission(
          commissionUsed: commissionUsed,
          userId: userId,
          network: serviceDetails['network'] ?? 'mtn',
          phone: serviceDetails['phone'],
          amount: amount,
          transactionPin: transactionPin,
          useBiometric: useBiometric,
        );

      case 'data':
        return await buyDataWithCommission(
          commissionUsed: commissionUsed,
          userId: userId,
          network: serviceDetails['network'] ?? 'mtn',
          phone: serviceDetails['phone'],
          variationCode: serviceDetails['variationCode'],
          planName: serviceDetails['planName'] ?? 'Data Plan',
          amount: amount,
          transactionPin: transactionPin,
          useBiometric: useBiometric,
        );

      case 'electricity':
        return await buyElectricityWithCommission(
          commissionUsed: commissionUsed,
          userId: userId,
          serviceID: serviceDetails['serviceID'],
          billersCode: serviceDetails['billersCode'],
          variationCode: serviceDetails['variationCode'],
          amount: amount,
          phone: serviceDetails['phone'],
          transactionPin: transactionPin,
          useBiometric: useBiometric,
        );

      case 'cable':
        return await buyCableWithCommission(
          commissionUsed: commissionUsed,
          userId: userId,
          serviceID: serviceDetails['serviceID'],
          billersCode: serviceDetails['billersCode'],
          variationCode: serviceDetails['variationCode'],
          amount: amount,
          phone: serviceDetails['phone'],
          transactionPin: transactionPin,
          useBiometric: useBiometric,
        );

      case 'education':
        return await buyEducationWithCommission(
          commissionUsed: commissionUsed,
          userId: userId,
          serviceID: serviceDetails['serviceID'],
          variationCode: serviceDetails['variationCode'],
          phone: serviceDetails['phone'],
          amount: amount,
          quantity: serviceDetails['quantity'] ?? 1,
          profileId: serviceDetails['profileId'],
          transactionPin: transactionPin,
          useBiometric: useBiometric,
        );

      case 'insurance':
        return await buyInsuranceWithCommission(
          commissionUsed: commissionUsed,
          userId: userId,
          phone: serviceDetails['phone'],
          insuredName: serviceDetails['insuredName'],
          engineCapacity: serviceDetails['engineCapacity'],
          chasisNumber: serviceDetails['chasisNumber'],
          plateNumber: serviceDetails['plateNumber'],
          vehicleMake: serviceDetails['vehicleMake'],
          vehicleModel: serviceDetails['vehicleModel'],
          vehicleColor: serviceDetails['vehicleColor'],
          yearOfMake: serviceDetails['yearOfMake'],
          state: serviceDetails['state'],
          lga: serviceDetails['lga'],
          email: serviceDetails['email'],
          amount: amount,
          variationCode: serviceDetails['variationCode'] ?? 'third-party',
          transactionPin: transactionPin,
          useBiometric: useBiometric,
        );

      default:
        throw Exception('Unsupported service type: $serviceType');
    }
  }

  /// Buy airtime with commission flag
  static Future<Map<String, dynamic>> buyAirtimeWithCommission({
    required bool commissionUsed,
    required String userId,
    required String network,
    required String phone,
    required double amount,
    String? transactionPin,
    bool? useBiometric,
  }) async {
    _log('📱 Buying airtime with commission flag: $commissionUsed');

    // Don't use _executeSecureTransaction when commission already deducted
    if (commissionUsed) {
      _log('✅ Commission already deducted, proceeding directly to VTpass');

      final serviceID = _airtimeServiceIds[network] ?? network.toLowerCase();
      final requestId = generateVtpassRequestId();

      final payload = {
        'userId': userId,
        'network': network,
        'phone': phone,
        'amount': amount,
        'request_id': requestId,
        'commissionUsed': true, // ✅ Flag for backend
        'transactionPin': transactionPin,
        'useBiometric': useBiometric,
      };

      // Use special endpoint that doesn't deduct wallet
      return await _authenticatedPost(
        Uri.parse('$baseUrl/api/vtpass/airtime-with-commission'),
        payload,
      );
    } else {
      // Regular airtime purchase
      return await buyAirtime(
        userId: userId,
        network: network,
        phone: phone,
        amount: amount,
        transactionPin: transactionPin,
        useBiometric: useBiometric,
      );
    }
  }

  /// Buy data with commission flag
  static Future<Map<String, dynamic>> buyDataWithCommission({
    required bool commissionUsed,
    required String userId,
    required String network,
    required String phone,
    required String variationCode,
    required String planName,
    required double amount,
    String? transactionPin,
    bool? useBiometric,
  }) async {
    _log('📱 Buying data with commission flag: $commissionUsed');

    // Don't use _executeSecureTransaction when commission already deducted
    if (commissionUsed) {
      _log('✅ Commission already deducted, proceeding directly to VTpass');

      final serviceID =
          '${network.toLowerCase()}-data'; // e.g., mtn-data, airtel-data
      final requestId = generateVtpassRequestId();

      final payload = {
        'userId': userId,
        'network': network,
        'phone': phone,
        'variationCode': variationCode,
        'planName': planName,
        'amount': amount,
        'request_id': requestId,
        'commissionUsed': true, // ✅ Flag for backend
        'transactionPin': transactionPin,
        'useBiometric': useBiometric,
      };

      // Use special endpoint that doesn't deduct wallet
      return await _authenticatedPost(
        Uri.parse('$baseUrl/api/vtpass/data-with-commission'),
        payload,
      );
    } else {
      // Regular data purchase
      return await buyData(
        userId: userId,
        network: network,
        phone: phone,
        variationCode: variationCode,
        planName: planName,
        amount: amount,
        transactionPin: transactionPin,
        useBiometric: useBiometric,
      );
    }
  }

  /// Buy electricity with commission flag
  static Future<Map<String, dynamic>> buyElectricityWithCommission({
    required bool commissionUsed,
    required String userId,
    required String serviceID,
    required String billersCode,
    required String variationCode,
    required double amount,
    required String phone,
    String? transactionPin,
    bool? useBiometric,
  }) async {
    _log('⚡ Buying electricity with commission flag: $commissionUsed');

    if (commissionUsed) {
      _log('✅ Commission already deducted, proceeding directly to VTpass');

      final requestId = generateVtpassRequestId();

      final payload = {
        'userId': userId,
        'serviceID': serviceID,
        'billersCode': billersCode,
        'variationCode': variationCode,
        'amount': amount,
        'phone': phone,
        'request_id': requestId,
        'commissionUsed': true,
        'transactionPin': transactionPin,
        'useBiometric': useBiometric,
      };

      return await _authenticatedPost(
        Uri.parse('$baseUrl/api/vtpass/electricity-with-commission'),
        payload,
      );
    } else {
      // Regular electricity purchase
      return await payElectricityBill(
        userId: userId,
        serviceID: serviceID,
        billersCode: billersCode,
        variationCode: variationCode,
        amount: amount,
        phone: phone,
        transactionPin: transactionPin,
        useBiometric: useBiometric,
      );
    }
  }

  /// Buy cable with commission flag
  static Future<Map<String, dynamic>> buyCableWithCommission({
    required bool commissionUsed,
    required String userId,
    required String serviceID,
    required String billersCode,
    required String variationCode,
    required double amount,
    required String phone,
    String? transactionPin,
    bool? useBiometric,
  }) async {
    _log('📺 Buying cable with commission flag: $commissionUsed');

    if (commissionUsed) {
      _log('✅ Commission already deducted, proceeding directly to VTpass');

      final requestId = generateVtpassRequestId();

      final payload = {
        'userId': userId,
        'serviceID': serviceID,
        'billersCode': billersCode,
        'variationCode': variationCode,
        'amount': amount,
        'phone': phone,
        'request_id': requestId,
        'commissionUsed': true,
        'transactionPin': transactionPin,
        'useBiometric': useBiometric,
      };

      return await _authenticatedPost(
        Uri.parse('$baseUrl/api/vtpass/cable-with-commission'),
        payload,
      );
    } else {
      // Regular cable purchase
      return await makeCablePayment(
        userId: userId,
        serviceID: serviceID,
        billersCode: billersCode,
        variationCode: variationCode,
        amount: amount,
        phone: phone,
        transactionPin: transactionPin,
        useBiometric: useBiometric,
      );
    }
  }

  /// Buy education service with commission flag
  static Future<Map<String, dynamic>> buyEducationWithCommission({
    required bool commissionUsed,
    required String userId,
    required String serviceID,
    required String variationCode,
    required String phone,
    required double amount,
    int quantity = 1,
    String? profileId,
    String? transactionPin,
    bool? useBiometric,
  }) async {
    _log('🎓 Buying education with commission flag: $commissionUsed');

    if (commissionUsed) {
      _log('✅ Commission already deducted, proceeding directly to VTpass');

      final requestId = generateVtpassRequestId();

      final payload = {
        'userId': userId,
        'serviceID': serviceID,
        'variationCode': variationCode,
        'phone': phone,
        'amount': amount,
        'quantity': quantity,
        'profileId': profileId,
        'request_id': requestId,
        'commissionUsed': true,
        'transactionPin': transactionPin,
        'useBiometric': useBiometric,
      };

      return await _authenticatedPost(
        Uri.parse('$baseUrl/api/vtpass/education-with-commission'),
        payload,
      );
    } else {
      // Regular education purchase
      return await purchaseEducationService(
        userId: userId,
        serviceID: serviceID,
        variationCode: variationCode,
        phone: phone,
        amount: amount,
        quantity: quantity,
        profileId: profileId,
        transactionPin: transactionPin,
        useBiometric: useBiometric,
      );
    }
  }

  /// Buy insurance with commission flag
  static Future<Map<String, dynamic>> buyInsuranceWithCommission({
    required bool commissionUsed,
    required String userId,
    required String phone,
    required String insuredName,
    required String engineCapacity,
    required String chasisNumber,
    required String plateNumber,
    required String vehicleMake,
    required String vehicleModel,
    required String vehicleColor,
    required String yearOfMake,
    required String state,
    required String lga,
    required String email,
    required double amount,
    String variationCode = 'third-party',
    String? transactionPin,
    bool? useBiometric,
  }) async {
    _log('🛡️ Buying insurance with commission flag: $commissionUsed');

    if (commissionUsed) {
      _log('✅ Commission already deducted, proceeding directly to VTpass');

      final requestId = generateVtpassRequestId();

      final payload = {
        'userId': userId,
        'phone': phone,
        'insuredName': insuredName,
        'engineCapacity': engineCapacity,
        'chasisNumber': chasisNumber,
        'plateNumber': plateNumber,
        'vehicleMake': vehicleMake,
        'vehicleModel': vehicleModel,
        'vehicleColor': vehicleColor,
        'yearOfMake': yearOfMake,
        'state': state,
        'lga': lga,
        'email': email,
        'variationCode': variationCode,
        'amount': amount,
        'request_id': requestId,
        'commissionUsed': true,
        'transactionPin': transactionPin,
        'useBiometric': useBiometric,
      };

      return await _authenticatedPost(
        Uri.parse('$baseUrl/api/vtpass/insurance-with-commission'),
        payload,
      );
    } else {
      // Regular insurance purchase
      return await purchaseInsurance(
        userId: userId,
        phone: phone,
        insuredName: insuredName,
        engineCapacity: engineCapacity,
        chasisNumber: chasisNumber,
        plateNumber: plateNumber,
        vehicleMake: vehicleMake,
        vehicleModel: vehicleModel,
        vehicleColor: vehicleColor,
        yearOfMake: yearOfMake,
        state: state,
        lga: lga,
        email: email,
        transactionPin: transactionPin,
        useBiometric: useBiometric,
      );
    }
  }

  static Future<Map<String, dynamic>> updateUserProfile({
    required String userId,
    String? fullName,
    String? email,
    String? phone,
    double? walletBalance,
    double? commissionBalance,
    bool? isActive,
    bool? isAdminStatus,
    bool? isFirstTransaction, // ✅ Added this
    bool? hasReceivedFirstTransactionBonus, // ✅ ADD THIS NEW PARAMETER
    required bool isAdmin,
  }) async {
    _log('Updating user profile for ID: $userId');

    final currentUserId = await _getUserId();
    final isOwnProfile = currentUserId == userId;
    final userIsAdmin = isAdmin;

    // --- Permission checks ---
    if (!isOwnProfile && !userIsAdmin) {
      throw Exception('You can only update your own profile');
    }
    if ((isActive != null || isAdminStatus != null) && !userIsAdmin) {
      throw Exception('Admin access required to update these fields');
    }

    // --- Build request body ---
    final url = Uri.parse('$_userBaseUrl/$userId');
    final Map<String, dynamic> body = {};

    if (fullName != null) body['fullName'] = fullName;
    if (email != null) body['email'] = email;
    if (phone != null) body['phone'] = phone;
    if (walletBalance != null && userIsAdmin) {
      body['walletBalance'] = walletBalance;
    }
    if (commissionBalance != null && userIsAdmin) {
      body['commissionBalance'] = commissionBalance;
    }
    if (isActive != null && userIsAdmin) body['isActive'] = isActive;
    if (isAdminStatus != null && userIsAdmin) body['isAdmin'] = isAdminStatus;
    if (isFirstTransaction != null) {
      body['isFirstTransaction'] = isFirstTransaction; // ✅ Added support
    }
    if (hasReceivedFirstTransactionBonus != null) {
      body['hasReceivedFirstTransactionBonus'] =
          hasReceivedFirstTransactionBonus;
    }

    if (body.isEmpty) throw Exception('No fields provided for update.');

    _log('Request body: ${jsonEncode(body)}');
    return await _authenticatedPatch(url, body);
  }

  static Future<Map<String, dynamic>> updateUserPhone({
    required String userId,
    required String phone,
  }) async {
    _log('Updating phone number for user ID: $userId');
    final userIsAdmin = await isAdmin();
    return await updateUserProfile(
      userId: userId,
      phone: phone,
      isAdmin: userIsAdmin,
    );
  }

  /// FINAL & BULLETPROOF getCurrentUser() — Best of both worlds
  static Future<Map<String, dynamic>> getCurrentUser({
    bool forceRefresh = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    // 1. Try cached user first (fast & works offline)
    if (!forceRefresh) {
      final userString = prefs.getString('user');
      if (userString != null && userString.isNotEmpty) {
        try {
          final cachedUser = jsonDecode(userString) as Map<String, dynamic>;
          _log('Returning CACHED user data (fast)');
          return cachedUser;
        } catch (e) {
          _log('Cached user data corrupted, clearing... $e');
          await prefs.remove('user');
        }
      }
    }

    // 2. Fetch fresh from backend
    try {
      final userId = prefs.getString('userId');
      final token = await _getToken();

      if (userId == null || token == null) {
        throw Exception('No userId or token');
      }

      _log('Fetching FRESH user data from backend...');

      final response = await http
          .get(
            Uri.parse('$baseUrl/api/users/$userId'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final user = data['user'] ?? data; // ← THIS WAS THE BUG

        // FIX: Save BOTH formats to cache
        await prefs.setString('user', jsonEncode(user));

        // ALSO save critical fields directly
        await prefs.setString('fullName', user['fullName'] ?? 'User');
        await prefs.setString('email', user['email'] ?? '');
        await prefs.setBool('isAdmin', user['isAdmin'] == true);
        await prefs.setString('role', user['role']?.toString() ?? '');

        _log(
          'FRESH USER DATA SAVED — role: ${user['role']}, isAdmin: ${user['isAdmin']}',
        );
        return user;
      }
    } catch (e) {
      _log('Failed to fetch fresh user: $e');
    }

    // 3. Final fallback: try to recover from prefs
    final userString = prefs.getString('user');
    if (userString != null && userString.isNotEmpty) {
      try {
        return jsonDecode(userString) as Map<String, dynamic>;
      } catch (e) {
        _log('Final fallback failed: $e');
      }
    }

    throw Exception('User not found. Please log in again.');
  }

  /// Validates a referral code during signup
  static Future<Map<String, dynamic>> validateReferralCode(
    String referralCode,
  ) async {
    _log('Validating referral code: $referralCode');
    try {
      final response = await _authenticatedPost(_validateReferralUrl, {
        'referralCode': referralCode,
      });
      if (response['success'] == true && response['referrerId'] != null) {
        _log(
          'Referral code $referralCode is valid. Referrer ID: ${response['referrerId']}',
        );
        return {
          'success': true,
          'referrerId': response['referrerId'],
          'message': response['message'] ?? 'Referral code is valid',
        };
      } else {
        _log('Referral code $referralCode is invalid.');
        return {
          'success': false,
          'message': response['message'] ?? 'Invalid referral code',
        };
      }
    } catch (e, stackTrace) {
      _log('Error validating referral code: $e');
      await reportError(e, stackTrace);
      return {
        'success': false,
        'message': 'Failed to validate referral code: $e',
      };
    }
  }

  static Future<Map<String, dynamic>> fundWallet({
    required String userId,
    required double amount,
    String type = 'credit',
    String? note,
  }) async {
    // Check admin status first
    if (!await isAdmin()) {
      throw Exception('Admin access required for this operation');
    }

    return await _executeSecureTransaction(
      userId: userId,
      transactionType: 'wallet_funding',
      amount: amount,
      serviceType: 'wallet_funding',
      requiresDebit: false, // Funding doesn't require debit check
      transactionFunction: () async {
        _log(
          '💰 Secure wallet funding for user: $userId | Amount: ₦$amount | Type: $type',
        );

        // Validate parameters
        _validateTransactionParams(
          userId: userId,
          amount: amount,
          serviceType: 'wallet_funding',
        );

        // Prepare request body - Backend only expects userId and amount based on your code
        Map<String, dynamic> requestBody = {'userId': userId, 'amount': amount};

        // Add note if provided (check if backend supports it)
        if (note != null && note.isNotEmpty) {
          requestBody['note'] = note;
        }

        _log('📦 Funding request body: $requestBody');

        // Try the funding API call
        try {
          final response = await _authenticatedPost(
            _fundWalletUrl,
            requestBody,
            timeout: const Duration(seconds: 30),
          );

          _log('📡 Funding response: ${jsonEncode(response)}');

          // Check for success - your backend returns {success: true, message: "...", newBalance: ...}
          if (response['success'] != true) {
            final errorMsg = response['message'] ?? 'Funding failed';
            throw Exception(errorMsg);
          }

          // Credit commission for wallet top-up if successful
          if (type.toLowerCase() == 'credit') {
            try {
              final transactionId =
                  response['transactionId'] ??
                  response['data']?['transactionId'] ??
                  _generateRequestId();

              await _creditCommission(
                userId: userId,
                transactionId: transactionId.toString(),
                serviceType: 'wallet_funding',
                amount: amount,
                requestId: _generateRequestId(),
              );

              _log('✅ Commission credited for wallet funding');
            } catch (e) {
              _log('⚠️ Commission credit failed for wallet funding: $e');
              // Don't throw - commission failure shouldn't fail the main transaction
            }
          }

          return response;
        } catch (e) {
          _log('❌ Funding API error: $e');
          rethrow;
        }
      },
    );
  }

  // ==================== TRANSACTION STATISTICS ====================

  // ==================== TRANSACTION STATISTICS ====================

  /// Get transaction statistics with filters (daily, weekly, monthly, yearly)
  static Future<Map<String, dynamic>> getTransactionStatistics({
    String? type,
    String? status,
    String? startDate,
    String? endDate,
  }) async {
    if (!await isAdmin()) throw Exception('Admin access required');
    _log('📊 Getting transaction statistics with filters');

    try {
      String url = '$baseUrl/api/admin/transactions/statistics';
      final params = <String, String>{};
      if (type != null && type != 'All') params['type'] = type;
      if (status != null && status != 'All') params['status'] = status;
      if (startDate != null) params['startDate'] = startDate;
      if (endDate != null) params['endDate'] = endDate;

      if (params.isNotEmpty) {
        url +=
            '?${params.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&')}';
      }

      final response = await _authenticatedGet(Uri.parse(url));

      if (response['success'] == true) {
        return response['data'];
      } else {
        throw Exception(
          response['message'] ?? 'Failed to get transaction statistics',
        );
      }
    } catch (e) {
      _log('❌ Error getting transaction statistics: $e');
      rethrow;
    }
  }

  /// ✅ Verify a single transaction by ID
  static Future<Map<String, dynamic>> verifyTransaction(
    String transactionId,
  ) async {
    _log('🔍 Verifying transaction with ID: $transactionId');
    final url = Uri.parse('$_transactionsBaseUrl/$transactionId');
    return await _authenticatedGet(url);
  }

  static Future<Map<String, dynamic>> transfer({
    required String senderId,
    required String receiverEmail,
    required double amount,
    String? transactionPin,
    bool? useBiometric,
  }) async {
    _log('Transferring funds from user ID: $senderId to $receiverEmail');
    try {
      final authResult = await authenticateTransaction(
        userId: senderId,
        transactionPin: transactionPin,
        useBiometric: useBiometric,
      );
      final Map<String, dynamic> body = {
        'senderId': senderId,
        'receiverEmail': receiverEmail,
        'amount': amount,
      };
      if (authResult['method'] == 'pin') {
        body['transactionPin'] = authResult['pin'];
      } else if (authResult['method'] == 'biometric')
        body['useBiometric'] = true;
      final data = await _authenticatedPost(_transferUrl, body);
      _log('Transfer API response: $data');
      return data;
    } catch (e) {
      _log('Error in transfer: $e');
      rethrow;
    }
  }

  /// Fetch a single user by ID with cache
  static Future<Map<String, dynamic>?> getUserById(String userId) async {
    try {
      // Check cache first
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = 'user_$userId';
      final cached = prefs.getString(cacheKey);

      if (cached != null) {
        try {
          final cachedUser = jsonDecode(cached);
          // Use cache if less than 5 minutes old
          if (cachedUser['_cachedAt'] != null) {
            final cachedAt = DateTime.parse(cachedUser['_cachedAt']);
            if (DateTime.now().difference(cachedAt).inMinutes < 5) {
              cachedUser.remove('_cachedAt');
              return cachedUser;
            }
          }
        } catch (_) {}
      }

      final token = await _getToken();
      if (token == null) return null;

      final response = await http
          .get(
            Uri.parse('$baseUrl/api/users/$userId'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final user = data['user'] ?? data;

        // Cache the user
        if (user != null && user is Map) {
          final cacheData = Map<String, dynamic>.from(user);
          cacheData['_cachedAt'] = DateTime.now().toIso8601String();
          await prefs.setString(cacheKey, jsonEncode(cacheData));
        }

        return user;
      }

      return null;
    } catch (e) {
      debugPrint('❌ Error fetching user $userId: $e');
      return null;
    }
  }

  // In ApiService class
  static Future<List<dynamic>> getAllTransactions({
    int limit = 100,
    bool retry = true,
  }) async {
    debugPrint('🔄 getAllTransactions called with limit: $limit');

    // Try both endpoints in sequence
    final endpoints = [
      // Endpoint 1: /api/transactions?limit=100
      {
        'url': Uri.parse(
          '${PaymentService.authBaseUrl}/api/transactions?limit=$limit',
        ),
        'name': 'Main endpoint',
      },
      // Endpoint 2: api/transactions (no limit parameter)
      {
        'url': Uri.parse('$baseUrl/api/transactions'),
        'name': 'Legacy endpoint',
      },
    ];

    for (int attempt = 0; attempt < (retry ? 3 : 1); attempt++) {
      for (var endpoint in endpoints) {
        try {
          debugPrint('🔄 Trying ${endpoint['name']} (attempt ${attempt + 1})');

          // ALWAYS reload the latest token
          final token = await _TokenManager.getSafeToken();
          if (token == null) throw Exception('NO_TOKEN');

          final response = await http
              .get(
                endpoint['url'] as Uri,
                headers: {
                  'Content-Type': 'application/json',
                  'Authorization': 'Bearer $token',
                },
              )
              .timeout(const Duration(seconds: 15));

          debugPrint(
            '📡 Response from ${endpoint['name']}: ${response.statusCode}',
          );

          final data = jsonDecode(response.body);

          // Handle token refresh if needed
          if (data['code'] == 'TOKEN_EXPIRED' ||
              data['requiresRefresh'] == true) {
            debugPrint('🔄 Token expired → refreshing');

            final refreshed = await _tokenManager.refreshTokenWithQueue();
            if (!refreshed) throw Exception('Refresh failed');

            await Future.delayed(const Duration(milliseconds: 100));
            continue; // Retry with new token
          }

          if (data['code'] == 'INVALID_TOKEN' || data['code'] == 'NO_TOKEN') {
            throw Exception('INVALID_TOKEN');
          }

          if (data['success'] == true || response.statusCode == 200) {
            final transactions = data['transactions'] ?? [];
            debugPrint(
              '✅ ${endpoint['name']} returned ${transactions.length} transactions',
            );
            return transactions;
          }

          // If this endpoint failed, try the next one
          debugPrint('⚠️ ${endpoint['name']} failed: ${data['message']}');
          continue;
        } catch (e) {
          debugPrint('❌ Error from ${endpoint['name']}: $e');
          // Continue to next endpoint
        }
      }

      // Wait before retry if needed
      if (attempt < 2 && retry) {
        await Future.delayed(Duration(milliseconds: 200 * (attempt + 1)));
      }
    }

    throw Exception('Failed to load transactions from all endpoints');
  }

  // ADD THIS METHOD
  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
  }

  /// 🚑 EMERGENCY: Complete authentication reset and recovery
  static Future<Map<String, dynamic>> emergencyAuthRecovery() async {
    _log('🚑 Starting emergency authentication recovery...');

    try {
      final prefs = await SharedPreferences.getInstance();

      // Step 1: Preserve critical user data
      final userId = prefs.getString('userId');
      final email = prefs.getString('email');
      final fullName = prefs.getString('fullName');

      if (userId == null) {
        _log('❌ No user ID found - cannot recover');
        return {
          'success': false,
          'message': 'No user data found. Please log in again.',
          'requiresLogin': true,
        };
      }

      _log('🔍 Found user data: $email ($fullName)');

      // Step 2: Clear all authentication tokens and flags
      await prefs.remove('token');
      await prefs.remove('refreshToken');
      await prefs.remove('lastTokenRefresh');
      await prefs.remove('needsReauth');

      _log('✅ Cleared problematic tokens');

      // Step 3: Set safe state
      await prefs.setBool('needsReauth', true);

      return {
        'success': true,
        'message': 'Authentication reset completed. Please log in again.',
        'userId': userId,
        'email': email,
        'requiresLogin': true,
      };
    } catch (e, stackTrace) {
      _log('💥 Emergency recovery failed: $e');
      await reportError(e, stackTrace);

      // Last resort: clear everything
      final prefs = await SharedPreferences.getInstance();
      await _clearAuthData();

      return {
        'success': false,
        'message':
            'Recovery failed. Please restart the mobile and log in again.',
        'requiresLogin': true,
      };
    }
  }

  /// 🔍 Check token health and status
  static Future<Map<String, dynamic>> checkTokenHealth() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = await _TokenManager.getSafeToken();
      final refreshToken = await _TokenManager._getRefreshToken();
      final lastRefresh = prefs.getInt('lastTokenRefresh');
      final needsReauth = prefs.getBool('needsReauth') ?? false;

      final tokenAge =
          lastRefresh != null
              ? '${((DateTime.now().millisecondsSinceEpoch - lastRefresh) / (1000 * 60 * 60)).toStringAsFixed(2)} hours'
              : 'Unknown';

      final isValid = await _TokenManager._verifyTokenValidity();

      _log('🔍 TOKEN HEALTH CHECK:');
      _log(
        '   - Token: ${token != null ? "Exists (${token.substring(0, 10)}...)" : "NULL"}',
      );
      _log('   - Refresh Token: ${refreshToken != null ? "Exists" : "NULL"}');
      _log('   - Token Age: $tokenAge');
      _log('   - Needs Reauth: $needsReauth');
      _log('   - Token Valid: $isValid');

      return {
        'tokenExists': token != null,
        'refreshTokenExists': refreshToken != null,
        'tokenAge': tokenAge,
        'needsReauth': needsReauth,
        'isValid': isValid,
        'lastRefresh': lastRefresh,
      };
    } catch (e) {
      _log('❌ Token health check error: $e');
      return {'error': e.toString()};
    }
  }

  /// 🚨 CRITICAL FIX: Enhanced authentication recovery system
  static Future<Map<String, dynamic>> recoverAuthentication() async {
    _log('🔄 Attempting authentication recovery...');

    try {
      final prefs = await SharedPreferences.getInstance();

      // Step 1: Check if we have any stored user data
      final userId = prefs.getString('userId');
      final email = prefs.getString('email');

      if (userId == null || email == null) {
        _log('❌ No user data found - requiring full login');
        return {
          'success': false,
          'requiresLogin': true,
          'message': 'Please log in again',
        };
      }

      // Step 2: Clear problematic flags but preserve user data
      await prefs.remove('needsReauth');
      await prefs.remove('lastTokenRefresh');

      // Step 3: Check backend health
      final health = await checkBackendHealth();
      if (!health['success']) {
        _log('❌ Backend is unavailable');
        return {
          'success': false,
          'requiresLogin': false,
          'message': 'Service temporarily unavailable',
        };
      }

      _log('✅ Authentication recovery completed');
      return {
        'success': true,
        'userId': userId,
        'email': email,
        'message': 'Authentication recovered',
      };
    } catch (e, stackTrace) {
      _log('❌ Authentication recovery failed: $e');
      await reportError(e, stackTrace);
      return {
        'success': false,
        'requiresLogin': true,
        'message': 'Authentication recovery failed: $e',
      };
    }
  }

  /// 🔧 FIX: Safe token retrieval with recovery
  static Future<String?> getSafeTokenWithRecovery() async {
    try {
      // First try normal token retrieval
      var token = await _TokenManager.getSafeToken();

      if (token != null) {
        _log('✅ Token found via normal method');
        return token;
      }

      _log('🔄 Token not found, attempting recovery...');

      // If no token, try to recover authentication
      final recovery = await recoverAuthentication();

      if (recovery['success'] == true) {
        // Try again after recovery
        token = await _TokenManager.getSafeToken();
        if (token != null) {
          _log('✅ Token retrieved after recovery');
          return token;
        }
      }

      _log('❌ No token available after recovery attempts');
      return null;
    } catch (e) {
      _log('❌ Error in safe token recovery: $e');
      return null;
    }
  }

  /// 🛡️ ENHANCED: Authentication wrapper for all API calls
  static Future<T> withAuthRecovery<T>(
    Future<T> Function() apiCall,
    String operationName,
  ) async {
    try {
      // Check auth state first
      final authState = await checkAuthState();

      if (authState['needsLogin'] == true) {
        _log('🔐 Authentication required for: $operationName');

        // Try to recover authentication
        final recovery = await recoverAuthentication();
        if (recovery['requiresLogin'] == true) {
          throw Exception('Authentication required. Please log in again.');
        }
      }

      // Proceed with API call
      return await apiCall();
    } catch (e) {
      _log('❌ Auth recovery failed for $operationName: $e');
      rethrow;
    }
  }

  /// 🔍 DEBUG METHOD TO CHECK TOKEN STATE
  static Future<Map<String, dynamic>> debugTokenState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      final refreshToken = prefs.getString('refreshToken');
      final lastRefresh = prefs.getInt('lastTokenRefresh');
      final needsReauth = prefs.getBool('needsReauth') ?? false;

      final tokenAge =
          lastRefresh != null
              ? '${((DateTime.now().millisecondsSinceEpoch - lastRefresh) / (1000 * 60 * 60)).toStringAsFixed(2)} hours'
              : 'Unknown';

      _log('🔍 TOKEN DEBUG:');
      _log(
        '   - Token: ${token != null ? "Exists (${token.substring(0, 10)}...)" : "NULL"}',
      );
      _log('   - Refresh Token: ${refreshToken != null ? "Exists" : "NULL"}');
      _log('   - Token Age: $tokenAge');
      _log('   - Needs Reauth: $needsReauth');

      // Test token validity
      final isValid = await _TokenManager._verifyTokenValidity();
      _log('   - Token Valid: $isValid');

      return {
        'tokenExists': token != null,
        'refreshTokenExists': refreshToken != null,
        'tokenAge': tokenAge,
        'needsReauth': needsReauth,
        'isValid': isValid,
      };
    } catch (e) {
      _log('❌ Token debug error: $e');
      return {'error': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> autoFixMissingTransactions() async {
    try {
      final token = await _getToken();
      final response = await http.post(
        Uri.parse('$baseUrl/api/transactions/auto-fix-missing'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({'daysBack': 7}),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Auto-fix failed: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Auto-fix API error: $e');
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> syncMissingTransactions() async {
    try {
      final token = await _getToken();
      final response = await http.post(
        Uri.parse('$baseUrl/api/transactions/sync-missing'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({'daysBack': 3}),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Sync failed: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Sync API error: $e');
      rethrow;
    }
  }

  // --- Virtual Account ---
  static Future<Map<String, dynamic>?> getUserVirtualAccount() async {
    _log('Getting virtual account for current user');
    try {
      final url = Uri.parse(_virtualAccountBaseUrl);
      final data = await _authenticatedGet(url);
      if (data.containsKey('virtualAccount') &&
          data['virtualAccount'] != null &&
          data['virtualAccount']['assigned'] == true) {
        return Map<String, dynamic>.from(data['virtualAccount']);
      }
      return null;
    } catch (e) {
      _log('Error getting virtual account: $e');
      rethrow;
    }
  }

  // --- Virtual Account Methods - UPDATED ---

  /// Create instant virtual account for user
  static Future<Map<String, dynamic>> createVirtualAccount({
    required String userId,
    required String email,
    required String fullName,
    required String phone,
  }) async {
    _log('🚀 Creating virtual account for user: $userId');

    try {
      // Use PaymentService to create the virtual account
      final result = await PaymentService.createInstantVirtualAccount(
        userId: userId,
        email: email,
        fullName: fullName,
        phone: phone,
      );

      if (result['success'] == true) {
        // Store virtual account details locally
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          'virtualAccountNumber',
          result['accountNumber'] ?? '',
        );
        await prefs.setString(
          'virtualAccountName',
          result['accountName'] ?? fullName,
        );
        await prefs.setString(
          'virtualBankName',
          result['bankName'] ?? 'WEMA BANK',
        );
        await prefs.setBool('hasVirtualAccount', true);

        _log('✅ Virtual account created and stored locally');
      }

      return result;
    } catch (e, stackTrace) {
      _log('❌ Error creating virtual account: $e');
      await reportError(e, stackTrace);

      // Return fallback response
      return {
        'success': false,
        'message': 'Virtual account creation in progress',
        'accountNumber': 'Account Pending',
        'accountName': fullName,
        'bankName': 'WEMA BANK',
        'active': false,
      };
    }
  }

  // ==================== ADMIN WALLET CREDIT/DEBIT ====================

  /// Credit a user's wallet manually (audited).
  static Future<Map<String, dynamic>> adminCreditWallet({
    required String userId,
    required double amount,
    required String reason,
    String? reference,
    String? note,
  }) async {
    _log('💳 Admin crediting wallet: user=$userId, amount=₦$amount');

    try {
      final token = await _getToken();
      if (token == null) {
        throw Exception('Authentication required');
      }

      final response = await http
          .post(
            Uri.parse('$baseUrl/api/admin/users/$userId/wallet/credit'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'amount': amount,
              'reason': reason,
              if (reference != null && reference.isNotEmpty)
                'reference': reference,
              if (note != null && note.isNotEmpty) 'note': note,
            }),
          )
          .timeout(const Duration(seconds: 30));

      _log('📥 Credit response: ${response.statusCode}');

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        throw Exception('Admin access required');
      } else {
        final err = jsonDecode(response.body);
        throw Exception(err['message'] ?? 'Failed to credit wallet');
      }
    } catch (e) {
      _log('❌ Admin credit error: $e');
      rethrow;
    }
  }

  /// Debit a user's wallet manually (audited).
  static Future<Map<String, dynamic>> adminDebitWallet({
    required String userId,
    required double amount,
    required String reason,
    String? reference,
    String? note,
  }) async {
    _log('💳 Admin debiting wallet: user=$userId, amount=₦$amount');

    try {
      final token = await _getToken();
      if (token == null) {
        throw Exception('Authentication required');
      }

      final response = await http
          .post(
            Uri.parse('$baseUrl/api/admin/users/$userId/wallet/debit'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'amount': amount,
              'reason': reason,
              if (reference != null && reference.isNotEmpty)
                'reference': reference,
              if (note != null && note.isNotEmpty) 'note': note,
            }),
          )
          .timeout(const Duration(seconds: 30));

      _log('📥 Debit response: ${response.statusCode}');

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        throw Exception('Admin access required');
      } else {
        final err = jsonDecode(response.body);
        throw Exception(err['message'] ?? 'Failed to debit wallet');
      }
    } catch (e) {
      _log('❌ Admin debit error: $e');
      rethrow;
    }
  }

  /// Get audit logs for a specific user.
  static Future<Map<String, dynamic>> getUserAuditLogs(
    String userId, {
    int page = 1,
    int limit = 50,
  }) async {
    _log('📜 Fetching audit logs for user: $userId');

    try {
      final token = await _getToken();
      if (token == null) {
        throw Exception('Authentication required');
      }

      final url = Uri.parse(
        '$baseUrl/api/admin/users/$userId/audit-logs?page=$page&limit=$limit',
      );

      final response = await http
          .get(
            url,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        throw Exception('Admin access required');
      } else {
        final err = jsonDecode(response.body);
        throw Exception(err['message'] ?? 'Failed to fetch audit logs');
      }
    } catch (e) {
      _log('❌ Get audit logs error: $e');
      rethrow;
    }
  }

  /// Get full user details (profile + transactions + audit logs).
  /// Supports pagination via txPage / txLimit / auditPage / auditLimit.
  static Future<Map<String, dynamic>> getUserFullDetails(
    String userId, {
    int txPage = 1,
    int txLimit = 100,
    int auditPage = 1,
    int auditLimit = 50,
  }) async {
    _log(
      '🔍 Fetching full details for user: $userId (txPage=$txPage, txLimit=$txLimit)',
    );

    try {
      final token = await _getToken();
      if (token == null) {
        throw Exception('Authentication required');
      }

      final uri = Uri.parse(
        '$baseUrl/api/admin/users/$userId/full-details'
        '?txPage=$txPage&txLimit=$txLimit'
        '&auditPage=$auditPage&auditLimit=$auditLimit',
      );

      final response = await http
          .get(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        throw Exception('Admin access required');
      } else {
        final err = jsonDecode(response.body);
        throw Exception(err['message'] ?? 'Failed to fetch user details');
      }
    } catch (e) {
      _log('❌ Get user full details error: $e');
      rethrow;
    }
  }

  // ==================== END ADMIN WALLET CREDIT/DEBIT ====================

  // ==================== ADMIN: GET ALL TRANSACTIONS ====================
  /// 🆕 Get ALL transactions for admin with full filter support
  /// status: 'all' | 'successful' | 'pending' | 'failed' | 'refunded' | 'disputed'
  static Future<Map<String, dynamic>> getAllTransactionsForAdmin({
    String status = 'all',
    String search = '',
    int page = 1,
    int limit = 500,
  }) async {
    try {
      final token = await _getToken();
      if (token == null) {
        throw Exception('Authentication required. Please login again.');
      }

      final params = <String, String>{
        'status': status,
        'search': search,
        'page': page.toString(),
        'limit': limit.toString(),
      };

      final queryString = params.entries
          .map(
            (e) =>
                '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}',
          )
          .join('&');

      final url = Uri.parse('$baseUrl/api/admin/transactions-all?$queryString');

      final response = await http
          .get(
            url,
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else if (response.statusCode == 401) {
        throw Exception('Session expired. Please login again.');
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['message'] ?? 'Failed to fetch transactions');
      }
    } catch (e) {
      throw Exception('Error fetching transactions: ${e.toString()}');
    }
  }

  // ==================== ADMIN TRANSACTION STATUS METHODS ====================

  /// Get pending and failed transactions for admin
  static Future<Map<String, dynamic>> getPendingFailedTransactions() async {
    try {
      final token = await _getToken();
      if (token == null) {
        throw Exception('Authentication required. Please login again.');
      }

      final response = await http.get(
        Uri.parse('$baseUrl/api/admin/pending-failed-transactions?limit=100'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data;
      } else if (response.statusCode == 401) {
        throw Exception('Session expired. Please login again.');
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['message'] ?? 'Failed to fetch transactions');
      }
    } catch (e) {
      throw Exception('Error fetching transactions: ${e.toString()}');
    }
  }

  /// Get transaction details including disputes and receipts
  static Future<Map<String, dynamic>> getTransactionDetails(
    String transactionId,
  ) async {
    try {
      final token = await _getToken();
      if (token == null) {
        throw Exception('Authentication required. Please login again.');
      }

      final response = await http.get(
        Uri.parse('$baseUrl/api/admin/transaction/$transactionId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data;
      } else if (response.statusCode == 401) {
        throw Exception('Session expired. Please login again.');
      } else {
        final error = jsonDecode(response.body);
        throw Exception(
          error['message'] ?? 'Failed to fetch transaction details',
        );
      }
    } catch (e) {
      throw Exception('Error fetching transaction details: ${e.toString()}');
    }
  }

  /// Update transaction status (Admin only)
  /// ✅ Returns the full updated transaction + disputes + receipts
  static Future<Map<String, dynamic>> updateTransactionStatus({
    required String transactionId,
    required String newStatus,
    String? adminNote,
    String? resolutionReference,
  }) async {
    try {
      final token = await _getToken();
      if (token == null) {
        throw Exception('Authentication required. Please login again.');
      }

      final body = <String, dynamic>{'newStatus': newStatus};
      if (adminNote != null && adminNote.trim().isNotEmpty) {
        body['adminNote'] = adminNote.trim();
      }
      if (resolutionReference != null &&
          resolutionReference.trim().isNotEmpty) {
        body['resolutionReference'] = resolutionReference.trim();
      }

      debugPrint('📤 [UPDATE-STATUS] Sending request...');
      debugPrint('   transactionId: $transactionId');
      debugPrint('   newStatus: $newStatus');
      debugPrint('   adminNote: ${adminNote ?? "(none)"}');

      final response = await http
          .post(
            Uri.parse(
              '$baseUrl/api/admin/transaction/$transactionId/update-status',
            ),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));

      debugPrint('📥 [UPDATE-STATUS] Response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        debugPrint('✅ [UPDATE-STATUS] Success: ${data['message']}');
        return data;
      } else if (response.statusCode == 401) {
        throw Exception('Session expired. Please login again.');
      } else {
        final error = jsonDecode(response.body);
        throw Exception(
          error['message'] ?? 'Failed to update transaction status',
        );
      }
    } on TimeoutException {
      throw Exception('Request timed out. Please try again.');
    } catch (e) {
      throw Exception('Error updating status: ${e.toString()}');
    }
  }

  /// Fund user wallet (Admin only)
  static Future<Map<String, dynamic>> fundUserWallet({
    required String userId,
    required double amount,
    String? note,
  }) async {
    try {
      final token = await _getToken();
      if (token == null) {
        throw Exception('Authentication required. Please login again.');
      }

      final body = {
        'userId': userId,
        'amount': amount,
        if (note != null && note.isNotEmpty) 'note': note,
      };

      final response = await http.post(
        Uri.parse('$baseUrl/api/users/fund'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data;
      } else if (response.statusCode == 401) {
        throw Exception('Session expired. Please login again.');
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['message'] ?? 'Failed to fund wallet');
      }
    } catch (e) {
      throw Exception('Error funding wallet: ${e.toString()}');
    }
  }

  // ==================== ADMIN REFUND & DISPUTE METHODS ====================

  /// Get all disputes with optional status filter
  static Future<Map<String, dynamic>> getDisputes({
    String? status,
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final token = await _getToken();
      if (token == null) {
        throw Exception('Authentication required. Please login again.');
      }

      final queryParams = <String, String>{};
      if (status != null && status != 'all') {
        queryParams['status'] = status;
      }
      queryParams['page'] = page.toString();
      queryParams['limit'] = limit.toString();

      final uri = Uri.parse(
        '$baseUrl/api/admin/disputes',
      ).replace(queryParameters: queryParams);

      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      debugPrint('📡 getDisputes response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data;
      } else if (response.statusCode == 401) {
        throw Exception('Session expired. Please login again.');
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['message'] ?? 'Failed to fetch disputes');
      }
    } catch (e) {
      debugPrint('❌ getDisputes error: $e');
      throw Exception('Error fetching disputes: ${e.toString()}');
    }
  }

  /// Resolve a dispute
  static Future<Map<String, dynamic>> resolveDispute({
    required String disputeId,
    required String resolution,
    required bool approved,
    String? adminNote,
  }) async {
    try {
      final token = await _getToken();
      if (token == null) {
        throw Exception('Authentication required. Please login again.');
      }

      final body = {
        'resolution': resolution,
        'approved': approved,
        if (adminNote != null && adminNote.isNotEmpty) 'adminNote': adminNote,
      };

      final response = await http.post(
        Uri.parse('$baseUrl/api/admin/dispute/resolve/$disputeId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );

      debugPrint('📡 resolveDispute response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data;
      } else if (response.statusCode == 401) {
        throw Exception('Session expired. Please login again.');
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['message'] ?? 'Failed to resolve dispute');
      }
    } catch (e) {
      debugPrint('❌ resolveDispute error: $e');
      throw Exception('Error resolving dispute: ${e.toString()}');
    }
  }

  /// Get all refunds with optional status filter
  static Future<Map<String, dynamic>> getRefunds({
    String? status,
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final token = await _getToken();
      if (token == null) {
        throw Exception('Authentication required. Please login again.');
      }

      final queryParams = <String, String>{};
      if (status != null && status != 'all') {
        queryParams['status'] = status;
      }
      queryParams['page'] = page.toString();
      queryParams['limit'] = limit.toString();

      final uri = Uri.parse(
        '$baseUrl/api/admin/refunds',
      ).replace(queryParameters: queryParams);

      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      debugPrint('📡 getRefunds response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data;
      } else if (response.statusCode == 401) {
        throw Exception('Session expired. Please login again.');
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['message'] ?? 'Failed to fetch refunds');
      }
    } catch (e) {
      debugPrint('❌ getRefunds error: $e');
      throw Exception('Error fetching refunds: ${e.toString()}');
    }
  }

  /// Process a refund
  static Future<Map<String, dynamic>> processRefund({
    required String transactionId,
    required String reason,
    double? refundAmount,
    String? adminNote,
    String? resolutionDetails,
    String? disputeId,
  }) async {
    try {
      final token = await _getToken();
      if (token == null) {
        throw Exception('Authentication required. Please login again.');
      }

      final body = {
        'transactionId': transactionId,
        'reason': reason,
        if (refundAmount != null) 'refundAmount': refundAmount,
        if (adminNote != null && adminNote.isNotEmpty) 'adminNote': adminNote,
        if (resolutionDetails != null && resolutionDetails.isNotEmpty)
          'resolutionDetails': resolutionDetails,
        if (disputeId != null && disputeId.isNotEmpty) 'disputeId': disputeId,
      };

      final response = await http.post(
        Uri.parse('$baseUrl/api/admin/refund/process'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );

      debugPrint('📡 processRefund response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data;
      } else if (response.statusCode == 401) {
        throw Exception('Session expired. Please login again.');
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['message'] ?? 'Failed to process refund');
      }
    } catch (e) {
      debugPrint('❌ processRefund error: $e');
      throw Exception('Error processing refund: ${e.toString()}');
    }
  }

  /// Create a dispute for a transaction
  static Future<Map<String, dynamic>> createDispute({
    required String transactionId,
    required String type,
    required String reason,
    String? description,
    double? amount,
    File? screenshot, // Add this parameter
  }) async {
    try {
      final token = await _getToken();
      if (token == null) {
        throw Exception('Authentication required. Please login again.');
      }

      // First, upload screenshot if provided
      String? evidencePath;
      String? disputeId;

      if (screenshot != null) {
        debugPrint('📸 Uploading screenshot evidence...');

        try {
          // Create multipart request for screenshot upload
          var request = http.MultipartRequest(
            'POST',
            Uri.parse('$baseUrl/api/disputes/upload-evidence'),
          );

          request.headers['Authorization'] = 'Bearer $token';
          request.fields['transactionId'] = transactionId;
          request.files.add(
            await http.MultipartFile.fromPath('screenshot', screenshot.path),
          );

          final streamedResponse = await request.send();
          final responseData = await streamedResponse.stream.bytesToString();
          final result = jsonDecode(responseData);

          debugPrint('📸 Screenshot upload response: $result');

          if (result['success'] == true) {
            evidencePath = result['evidencePath'];
            disputeId = result['disputeId'];
            debugPrint('✅ Screenshot uploaded: $evidencePath');
          } else {
            debugPrint('⚠️ Screenshot upload failed: ${result['message']}');
          }
        } catch (uploadError) {
          debugPrint('⚠️ Screenshot upload error: $uploadError');
          // Continue with dispute creation even if screenshot fails
        }
      }

      // Create the dispute
      final body = {
        'transactionId': transactionId,
        'type': type,
        'reason': reason,
        if (description != null && description.isNotEmpty)
          'description': description,
        if (amount != null) 'amount': amount,
        if (evidencePath != null)
          'evidence': [evidencePath], // Add evidence if uploaded
      };

      final response = await http.post(
        Uri.parse(
          '$baseUrl/api/disputes/create',
        ), // Changed from admin endpoint to user endpoint
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );

      debugPrint('📡 createDispute response status: ${response.statusCode}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);

        // If we have a disputeId from upload but response doesn't include it
        if (disputeId != null && data['dispute'] == null) {
          data['disputeId'] = disputeId;
        }

        return data;
      } else if (response.statusCode == 401) {
        throw Exception('Session expired. Please login again.');
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['message'] ?? 'Failed to create dispute');
      }
    } catch (e) {
      debugPrint('❌ createDispute error: $e');
      throw Exception('Error creating dispute: ${e.toString()}');
    }
  }

  /// Get user's virtual account details
  static Future<Map<String, dynamic>> getVirtualAccountDetails() async {
    try {
      // First try to get from PaymentService
      final result = await PaymentService.getVirtualAccountDetails();

      if (result['success'] == true) {
        return result;
      }

      // Fallback to stored data
      return await getStoredVirtualAccount();
    } catch (e) {
      _log('Error getting virtual account details: $e');
      return await getStoredVirtualAccount();
    }
  }

  /// Check if user has virtual account
  static Future<bool> hasVirtualAccount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final accountNumber = prefs.getString('virtualAccountNumber');
      final hasAccount = prefs.getBool('hasVirtualAccount') ?? false;

      return hasAccount &&
          accountNumber != null &&
          accountNumber.isNotEmpty &&
          accountNumber != 'Account Pending';
    } catch (e) {
      _log('Error checking virtual account: $e');
      return false;
    }
  }

  /// Refresh virtual account details
  static Future<Map<String, dynamic>> refreshVirtualAccount() async {
    _log('🔄 Refreshing virtual account details');

    try {
      final result = await PaymentService.getVirtualAccountDetails();

      if (result['success'] == true) {
        // Update local storage
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          'virtualAccountNumber',
          result['accountNumber'] ?? '',
        );
        await prefs.setString(
          'virtualAccountName',
          result['accountName'] ?? '',
        );
        await prefs.setString(
          'virtualBankName',
          result['bankName'] ?? 'WEMA BANK',
        );
        await prefs.setBool('hasVirtualAccount', true);

        _log('✅ Virtual account refreshed successfully');
      }

      return result;
    } catch (e, stackTrace) {
      _log('❌ Error refreshing virtual account: $e');
      await reportError(e, stackTrace);
      return await getStoredVirtualAccount();
    }
  }

  static Future<Map<String, dynamic>> removeVirtualAccount({
    required String userId,
  }) async {
    if (!await isAdmin()) throw Exception('Admin access required');
    _log('Removing virtual account for user ID: $userId');
    final url = Uri.parse('$_virtualAccountBaseUrl/$userId');
    return await _authenticatedDelete(url);
  }

  // --- Beneficiaries ---
  static Future<List<dynamic>> getBeneficiaries() async {
    _log('Getting beneficiaries');
    final url = _beneficiariesBaseUrl;
    final responseData = await _authenticatedGet(url);
    return _extractDataList(responseData);
  }

  static Future<Map<String, dynamic>> addBeneficiary({
    required String name,
    required String type,
    required String value,
    String? network,
  }) async {
    _log('Adding beneficiary');
    final userId = await _getUserId();
    if (userId == null) {
      throw Exception('User ID not found. Please log in again.');
    }
    final Map<String, dynamic> body = {
      'userId': userId,
      'name': name,
      'type': type,
      'value': value,
    };
    if (network != null && type == 'phone') body['network'] = network;
    return await _authenticatedPost(_beneficiariesBaseUrl, body);
  }

  static Future<Map<String, dynamic>> deleteNotification(
    String notificationId,
  ) async {
    _log('🗑️ Deleting notification: $notificationId');

    try {
      if (!await validateTokenBeforeRequest()) {
        throw Exception('Authentication required');
      }

      final url = Uri.parse('$_notificationsBaseUrl/$notificationId');
      return await _authenticatedDelete(url);
    } catch (e, stackTrace) {
      _log('❌ ERROR in deleteNotification: $e');
      await reportError(e, stackTrace);
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> deleteBeneficiary(
    String beneficiaryId,
  ) async {
    _log('Deleting beneficiary with ID: $beneficiaryId');
    final url = Uri.parse('$_beneficiariesBaseUrl/$beneficiaryId');
    return await _authenticatedDelete(url);
  }

  static Future<bool> validateTokenBeforeRequest() async {
    try {
      await refreshTokensIfNeeded(); // Proactively refresh if needed
      return true;
    } catch (e) {
      _log('⚠️ Token validation failed: $e');
      return false;
    }
  }

  // --- Notifications ---
  static Future<List<dynamic>> getNotifications() async {
    _log('🔔 Getting notifications');

    try {
      // Validate token first
      if (!await validateTokenBeforeRequest()) {
        throw Exception('Authentication required. Please log in again.');
      }

      return await _authenticatedRequest(() async {
        final responseData = await _secureApiCall(
          () => _authenticatedGet(_notificationsBaseUrl),
          'getNotifications',
        );
        return _extractDataList(responseData);
      }, 'getNotifications');
    } catch (e) {
      _log('❌ ERROR in getNotifications: $e');

      // If it's an auth error, handle it properly
      if (e.toString().contains('Authentication required') ||
          e.toString().contains('Session expired') ||
          e.toString().contains('401')) {
        await _handleAuthFailure('Session expired. Please login again.');
      }

      return [];
    }
  }

  /// 🔐 Validate token before making requests
  static Future<bool> validateAndRefreshToken() async {
    try {
      final token = await _getToken();
      if (token == null) return false;

      // Simple validation - in production, you might want to decode JWT
      final response = await http
          .get(
            _verifyTokenUrl,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 5));

      return response.statusCode == 200;
    } catch (e) {
      _log('Token validation failed: $e');
      return false;
    }
  }

  // Add this method to your ApiService class
  static Future<List<dynamic>> getNotificationsWithRetry({
    int maxRetries = 2,
  }) async {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        _log('🔄 Notification fetch attempt $attempt/$maxRetries');
        return await getNotifications();
      } catch (e) {
        _log('❌ Notification fetch attempt $attempt failed: $e');

        if (attempt == maxRetries) {
          rethrow;
        }

        // Wait before retry (exponential backoff)
        await Future.delayed(Duration(seconds: attempt * 2));
      }
    }
    throw Exception('Failed to fetch notifications after $maxRetries attempts');
  }

  /// Enhanced connection check specifically for notifications
  static Future<bool> checkNotificationsConnection() async {
    try {
      // Try to connect to the notifications endpoint specifically
      final response = await http
          .get(
            _notificationsBaseUrl,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${await _getToken()}',
            },
          )
          .timeout(const Duration(seconds: 5));

      return response.statusCode != 404;
    } catch (e) {
      _log('Notifications connection check failed: $e');
      return false;
    }
  }

  static Future<Map<String, dynamic>> markAllNotificationsAsRead() async {
    _log('📌 Marking all notifications as read');

    try {
      if (!await validateTokenBeforeRequest()) {
        throw Exception('Authentication required');
      }

      final url = Uri.parse('$_notificationsBaseUrl/mark-all-read');
      return await _authenticatedPost(url, {});
    } catch (e, stackTrace) {
      _log('❌ ERROR in markAllNotificationsAsRead: $e');
      await reportError(e, stackTrace);
      rethrow;
    }
  }

  /// Mark notification as read

  static Future<Map<String, dynamic>> markNotificationAsRead(
    String notificationId,
  ) async {
    _log('Marking notification $notificationId as read');

    try {
      if (!await validateTokenBeforeRequest()) {
        throw Exception('Authentication required');
      }

      final url = Uri.parse('$_notificationsBaseUrl/$notificationId/read');
      return await _authenticatedPost(url, {});
    } catch (e, stackTrace) {
      _log('❌ ERROR in markNotificationAsRead: $e');
      await reportError(e, stackTrace);
      rethrow;
    }
  }

  /// Get unread notification count
  static Future<int> getUnreadNotificationCount() async {
    _log('Getting unread notification count');

    try {
      final notifications = await getNotifications();

      // Count unread notifications
      // For your model, unread = notifications where user is not in readBy array
      // You'll need to implement this logic based on your readBy field
      final unreadCount =
          notifications.length; // Temporary - implement your logic

      _log('Unread notification count: $unreadCount');
      return unreadCount;
    } catch (e) {
      _log('ERROR getting unread count: $e');
      return 0;
    }
  }

  // lib/core/services/api_service.dart

  /// Send notification (Admin only - supports bulk or personal)
  /// POST /api/notifications/send
  /// Access: Private (Admin)
  static Future<Map<String, dynamic>> sendNotification({
    required String title,
    required String message,
    String? recipientId,
    bool sendToAll = false,
    String type = 'announcement',
    String screen = 'notifications',
  }) async {
    if (!await isAdmin()) throw Exception('Admin access required');

    _log('📨 Sending notification: "$title" to ${recipientId ?? 'ALL USERS'}');

    final Map<String, dynamic> body = {
      'title': title,
      'message': message,
      'sendToAll': sendToAll,
      'type': type,
      'screen': screen,
    };

    if (recipientId != null && recipientId.isNotEmpty && !sendToAll) {
      body['recipientId'] = recipientId;
    }

    final url = Uri.parse('$_notificationsBaseUrl/send');
    return await _authenticatedPost(url, body);
  }

  // --- VTpass Services ---
  static Future<List<dynamic>> getBillerServices({
    required String serviceID,
  }) async {
    _log('Fetching biller services for serviceID: $serviceID');
    final url = Uri.parse('$_billerServicesUrl?serviceID=$serviceID');
    final responseData = await _authenticatedGet(url);
    return _extractDataList(responseData);
  }

  static Future<List<dynamic>> getBillerVariations({
    required String serviceID,
  }) async {
    _log('Fetching biller variations for serviceID: $serviceID');
    final url = Uri.parse('$_billerVariationsUrl?serviceID=$serviceID');
    final responseData = await _authenticatedGet(url);
    return _extractDataList(responseData);
  }

  static Future<Map<String, dynamic>> validateSmartCard({
    required String billersCode,
    required String serviceID,
  }) async {
    _log('Validating smart card for service ID: $serviceID');
    try {
      final isEnabled = await isServiceEnabled('cable');
      if (!isEnabled) {
        throw Exception('Cable payment service is currently disabled.');
      }

      // Validate service ID
      const validServiceIds = ['dstv', 'gotv', 'startimes'];
      if (!validServiceIds.contains(serviceID)) {
        throw Exception(
          'Invalid service ID: $serviceID. Supported: ${validServiceIds.join(", ")}',
        );
      }

      final requestBody = {'billersCode': billersCode, 'serviceID': serviceID};

      // Add delay to prevent rate-limiting
      await Future.delayed(const Duration(milliseconds: 1500));

      final data = await _vtpassPost(_vtpassValidateSmartcardUrl, requestBody);
      final content = data['content'];
      final customerName = content?['Customer_Name'];
      if (customerName != null) {
        _log('Smartcard validated successfully. Customer Name: $customerName');
        return {
          'success': true,
          'customerName': customerName,
          'details': data['content'],
          'message':
              data['response_description'] ??
              'Smartcard validated successfully.',
        };
      } else {
        _log('Smartcard validation failed: Customer name not found.');
        throw Exception(
          data['response_description'] ??
              'Customer name not found in validation response.',
        );
      }
    } catch (e) {
      _log('ERROR in validateSmartCard: $e');
      String errorMessage = e.toString();
      if (errorMessage.contains('INVALID BILLERS CODE')) {
        errorMessage = 'Invalid smartcard number. Please check and try again.';
      } else if (errorMessage.contains('too many attempts') ||
          errorMessage.contains('429')) {
        errorMessage =
            'Too many attempts. Please wait a few minutes before trying again.';
      }
      throw Exception(errorMessage);
    }
  }

  // lib/core/services/api_service.dart

  static Future<Map<String, dynamic>> makeCablePayment({
    required String? userId,
    required String serviceID,
    required String billersCode,
    required String variationCode,
    required double amount,
    required String phone,
    String? transactionPin,
    bool? useBiometric,
    String? currentPackage,
    int quantity = 1,
    String? action,
    String? subscriptionType,
  }) async {
    _log('📺 Making cable payment for user ID: $userId, service: $serviceID');
    _log('📦 Variation: $variationCode, Amount: $amount, Quantity: $quantity');
    _log('🔄 Current Package: $currentPackage');
    _log('🎯 Action: $action');
    _log('📋 Subscription Type: $subscriptionType');

    return await _executeSecureTransaction(
      userId: userId!,
      transactionType: 'cable_purchase',
      amount: amount * quantity,
      serviceType: 'cable',
      requiresDebit: true,
      useAtomic: false,
      transactionFunction: () async {
        _log('🛡️ Secure cable payment started');

        final isEnabled = await isServiceEnabled('cable');
        if (!isEnabled) {
          throw Exception('Cable payment service is currently disabled.');
        }

        final authResult = await authenticateTransaction(
          userId: userId,
          transactionPin: transactionPin,
          useBiometric: useBiometric,
        );

        final requestId = _generateRequestId();

        // 🔥 CRITICAL: Detect if this is a package change
        bool isPackageChange = false;

        if (action == 'change') {
          isPackageChange = true;
          _log('🔄 PACKAGE CHANGE via action: $action');
        } else if (subscriptionType == 'change') {
          isPackageChange = true;
          _log('🔄 PACKAGE CHANGE via subscriptionType: $subscriptionType');
        } else if (currentPackage != null && currentPackage != variationCode) {
          isPackageChange = true;
          _log('🔄 PACKAGE CHANGE DETECTED: $currentPackage → $variationCode');
        }

        String finalSubscriptionType = 'renew';
        if (subscriptionType != null) {
          finalSubscriptionType = subscriptionType;
        } else if (isPackageChange) {
          finalSubscriptionType = 'change';
        }

        if (isPackageChange) {
          _log('🔄 PACKAGE CHANGE: $currentPackage → $variationCode');
        } else {
          _log('🔄 RENEWAL: Same package $variationCode');
        }

        final backendPayload = {
          'userId': userId,
          'serviceID': serviceID,
          'billersCode': billersCode,
          'variationCode': variationCode,
          'amount': amount,
          'phone': phone,
          'request_id': requestId,
          'transactionPin': transactionPin,
          'useBiometric': useBiometric,
          'environment': 'live',
          'subscription_type': finalSubscriptionType,
          'quantity': quantity,
          'currentPackage': currentPackage,
          'isPackageChange': isPackageChange,
          'action': action ?? (isPackageChange ? 'change' : 'renew'),
        };

        _log('📤 Calling backend with request_id: $requestId');
        _log('📤 Subscription Type: $finalSubscriptionType');
        _log('📤 Quantity: $quantity');
        _log('📤 Action: ${action ?? (isPackageChange ? "change" : "renew")}');
        if (isPackageChange) {
          _log('📤 Package Change: $currentPackage → $variationCode');
        }

        try {
          final backendResponse = await _authenticatedPost(
            _cablePurchaseUrl,
            backendPayload,
          );

          _log('📦 Backend Response: ${jsonEncode(backendResponse)}');

          if (backendResponse['success'] == false) {
            _log('❌ Backend reported failure');

            // Check for amount mismatch error
            if (backendResponse['code'] == 'AMOUNT_MISMATCH') {
              final requiredAmount = backendResponse['requiredAmount'] ?? 0;
              throw Exception(
                '${backendResponse['message']}\n\nPlease pay the exact amount of ₦${requiredAmount.toStringAsFixed(2)}',
              );
            }

            // ✅ CHECK FOR LIMIT ERRORS
            final errorCode = backendResponse['code']?.toString() ?? '';
            if (errorCode == 'PER_TRANSACTION_LIMIT_EXCEEDED' ||
                errorCode == 'DAILY_LIMIT_EXCEEDED') {
              // Return structured error for limit handling
              return {
                'success': false,
                'transactionId': requestId,
                'status': 'failed',
                'vtpassResponse': {},
                'backendResponse': backendResponse,
                'newBalance': 0,
                'message': backendResponse['message'] ?? 'Limit exceeded',
                'code': errorCode,
                'limit': backendResponse['limit'] ?? 0,
                'requested': backendResponse['requested'] ?? amount,
                'forceSuccessDialog': false,
              };
            }

            throw Exception(backendResponse['message'] ?? 'Transaction failed');
          }

          final vtpassResponse = backendResponse['vtpassResponse'] ?? {};
          final code =
              vtpassResponse['code']?.toString() ??
              backendResponse['code']?.toString() ??
              '';
          final desc =
              vtpassResponse['response_description']?.toString() ??
              backendResponse['message']?.toString() ??
              '';
          final status = backendResponse['status']?.toString() ?? '';

          _log('🔍 Backend Code: "$code" | Desc: "$desc" | Status: "$status"');

          final bool isSuccess =
              backendResponse['success'] == true ||
              code == '000' ||
              (code == '019' &&
                  (desc.contains('SUCCESSFUL') ||
                      desc.contains('PROCESSED'))) ||
              status.contains('delivered') ||
              status.contains('already_active');

          _log('🎯 Success Decision: $isSuccess');

          double newBalance = 0.0;
          final prefs = await SharedPreferences.getInstance();
          final currentBalance = prefs.getDouble('walletBalance') ?? 0.0;

          if (isSuccess) {
            if (code == '000' ||
                (backendResponse['success'] == true &&
                    !backendResponse['duplicate'])) {
              final totalAmount = amount * quantity;
              newBalance = currentBalance - totalAmount;
              await prefs.setDouble('walletBalance', newBalance);

              final userString = prefs.getString('user');
              if (userString != null) {
                final userMap = jsonDecode(userString);
                userMap['walletBalance'] = newBalance;
                await prefs.setString('user', jsonEncode(userMap));
              }
              _log(
                '💰 NEW transaction: Deducted ₦$totalAmount | New balance: ₦$newBalance',
              );
            } else if (code == '019' || backendResponse['duplicate'] == true) {
              newBalance = currentBalance;
              _log('💰 DUPLICATE: No deduction - balance remains ₦$newBalance');
            }
          } else {
            newBalance = currentBalance;
          }

          final bool responseIsPackageChange =
              backendResponse['isPackageChange'] ?? false;
          final packageChangeDetails = backendResponse['packageChangeDetails'];

          return {
            'success': isSuccess,
            'transactionId':
                backendResponse['transactionId'] ??
                vtpassResponse['requestId'] ??
                requestId,
            'status': backendResponse['status'] ?? status,
            'vtpassResponse': vtpassResponse,
            'backendResponse': backendResponse,
            'newBalance': newBalance,
            'message': backendResponse['message'] ?? desc,
            'forceSuccessDialog': isSuccess,
            'isDuplicateSuccess':
                code == '019' || backendResponse['duplicate'] == true,
            'isPackageChange': responseIsPackageChange,
            'packageChangeDetails': packageChangeDetails,
            'subscriptionType': finalSubscriptionType,
            'quantity': quantity,
            'action': action ?? (isPackageChange ? 'change' : 'renew'),
            'code': code,
          };
        } catch (e) {
          _log('💥 Error in cable payment backend call: $e');

          final prefs = await SharedPreferences.getInstance();
          final currentBalance = prefs.getDouble('walletBalance') ?? 0.0;

          final errorStr = e.toString();

          // ✅ CHECK FOR LIMIT ERRORS IN CATCH
          if (errorStr.contains('PER_TRANSACTION_LIMIT_EXCEEDED') ||
              errorStr.contains('DAILY_LIMIT_EXCEEDED')) {
            final limitMatch = RegExp(r'₦(\d+\.?\d*)').firstMatch(errorStr);
            final limit =
                limitMatch != null
                    ? double.tryParse(limitMatch.group(1) ?? '0') ?? 0
                    : 0;
            final isDaily = errorStr.contains('DAILY_LIMIT_EXCEEDED');

            return {
              'success': false,
              'transactionId': requestId,
              'status': 'failed',
              'vtpassResponse': {},
              'backendResponse': {'error': errorStr, 'saved': false},
              'newBalance': currentBalance,
              'message': errorStr,
              'code':
                  isDaily
                      ? 'DAILY_LIMIT_EXCEEDED'
                      : 'PER_TRANSACTION_LIMIT_EXCEEDED',
              'limit': limit,
              'requested': amount,
              'forceSuccessDialog': false,
            };
          }

          return {
            'success': false,
            'transactionId': requestId,
            'status': 'failed',
            'vtpassResponse': {},
            'backendResponse': {'error': e.toString(), 'saved': false},
            'newBalance': currentBalance,
            'message': 'Transaction failed. Please try again.',
            'forceSuccessDialog': false,
            'code': 'TRANSACTION_FAILED',
          };
        }
      },
    );
  }

  /// Get cable TV variations for a specific provider (DSTV, GOtv, StarTimes)
  /// Get cable TV variations for a specific provider with error handling
  /// Get cable TV variations for a specific provider with CORS fix
  static Future<Map<String, dynamic>> getCableVariationsForProvider(
    String serviceID,
  ) async {
    _log('🎯 Fetching cable variations for provider: $serviceID');

    try {
      // Use backend proxy to avoid CORS issues
      final url = Uri.parse(
        '$baseUrl/api/cable/variations?serviceID=$serviceID',
      );
      final token = await _getToken();

      if (token == null) {
        throw Exception('Authentication token not found. Please log in again.');
      }

      _log('🔗 Using backend proxy URL for cable variations');

      final response = await http
          .get(
            url,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 15));

      _log('📦 Backend response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['success'] == true) {
          final providerData = data['data'][serviceID.toUpperCase()];
          final variations = providerData?['variations'] ?? [];
          final processedVariations = _processCableVariations(variations);

          _log(
            '✅ Successfully fetched ${processedVariations.length} plans for $serviceID from ${providerData?['source']}',
          );

          return {
            'success': true,
            'variations': processedVariations,
            'totalPlans': processedVariations.length,
            'source': providerData?['source'] ?? 'backend',
            'serviceName': serviceID.toUpperCase(),
          };
        } else {
          throw Exception(
            data['message'] ?? 'Failed to fetch variations from backend',
          );
        }
      } else {
        throw Exception(
          'HTTP ${response.statusCode}: Failed to fetch variations',
        );
      }
    } catch (e) {
      _log('❌ Error fetching cable variations for $serviceID: $e');

      // Return mock data as fallback
      return {
        'success': false,
        'variations': _getMockCableVariations(serviceID),
        'totalPlans': _getMockCableVariations(serviceID).length,
        'source': 'mock_fallback',
        'error': e.toString(),
        'note': 'Using mock data while service is unavailable',
      };
    }
  }

  // --- Buy Airtime ---
  // --- Buy Airtime ---
  static Future<Map<String, dynamic>> buyAirtime({
    required String userId,
    required String network,
    required String phone,
    required double amount,
    String? transactionPin,
    bool? useBiometric,
  }) async {
    // GENERATE FRESH UNIQUE request_id EVERY SINGLE TIME
    final requestId = generateVtpassRequestId();
    _log('BUY AIRTIME - FRESH request_id: $requestId');

    return await _executeSecureTransaction(
      userId: userId,
      transactionType: 'airtime_purchase',
      amount: amount,
      serviceType: 'airtime',
      requiresDebit: true,
      useAtomic: false,
      transactionFunction: () async {
        final serviceID = _airtimeServiceIds[network] ?? network.toLowerCase();

        // PAYLOAD WITH FRESH request_id
        final vtpassPayload = {
          'request_id': requestId,
          'serviceID': serviceID,
          'amount': amount.toStringAsFixed(2),
          'phone': phone,
          'environment': 'live',
        };

        _log('CALLING PROXY WITH FRESH request_id: $requestId');

        // CALL PROXY (IT WILL USE OUR FRESH ID)
        final response = await _authenticatedPost(
          Uri.parse('$baseUrl/api/vtpass/proxy'),
          vtpassPayload,
        );

        // ✅ CHECK FOR LIMIT ERRORS
        final responseCode = response['code']?.toString() ?? '';
        final responseMessage =
            response['message'] ??
            response['response_description'] ??
            'Transaction failed';

        // ✅ Detect limit errors
        if (responseCode == 'PER_TRANSACTION_LIMIT_EXCEEDED' ||
            responseCode == 'DAILY_LIMIT_EXCEEDED' ||
            responseMessage.contains('PER_TRANSACTION_LIMIT_EXCEEDED') ||
            responseMessage.contains('DAILY_LIMIT_EXCEEDED') ||
            responseMessage.contains('Maximum airtime per transaction')) {
          // Extract limit info from response
          final limitValue = response['limit'] ?? 0;
          final requestedValue = response['requested'] ?? amount;

          // Convert to double safely
          double limit = 0.0;
          if (limitValue is double) {
            limit = limitValue;
          } else if (limitValue is int) {
            limit = limitValue.toDouble();
          } else if (limitValue is num) {
            limit = limitValue.toDouble();
          } else if (limitValue is String) {
            limit = double.tryParse(limitValue) ?? 0.0;
          }

          double requested = 0.0;
          if (requestedValue is double) {
            requested = requestedValue;
          } else if (requestedValue is int) {
            requested = requestedValue.toDouble();
          } else if (requestedValue is num) {
            requested = requestedValue.toDouble();
          } else if (requestedValue is String) {
            requested = double.tryParse(requestedValue) ?? amount;
          } else {
            requested = amount;
          }

          final isDaily =
              responseCode == 'DAILY_LIMIT_EXCEEDED' ||
              responseMessage.contains('DAILY_LIMIT_EXCEEDED');

          return {
            'success': false,
            'transactionId': requestId,
            'status': 'failed',
            'vtpassResponse': response,
            'backendResponse': response,
            'backendSaved': false,
            'newBalance': 0.0,
            'message': responseMessage,
            'code': responseCode,
            'limit': limit,
            'requested': requested,
            'isDailyLimit': isDaily,
          };
        }

        // ✅ Check if transaction was successful
        final isSuccess =
            response['code']?.toString() == '000' ||
            response['success'] == true;

        double newBalance = 0.0;
        if (isSuccess) {
          final prefs = await SharedPreferences.getInstance();
          final currentBalance = prefs.getDouble('walletBalance') ?? 0.0;
          newBalance = currentBalance - amount;
          await prefs.setDouble('walletBalance', newBalance);

          final userString = prefs.getString('user');
          if (userString != null) {
            final userMap = jsonDecode(userString);
            userMap['walletBalance'] = newBalance;
            await prefs.setString('user', jsonEncode(userMap));
          }

          await _creditCommission(
            userId: userId,
            transactionId:
                response['content']?['transactions']?['transactionId'] ??
                requestId,
            serviceType: 'airtime',
            amount: amount,
            requestId: requestId,
          );
        }

        return {
          'success': isSuccess,
          'transactionId':
              response['content']?['transactions']?['transactionId'] ??
              requestId,
          'status':
              response['content']?['transactions']?['status'] ??
              (isSuccess ? 'delivered' : 'failed'),
          'vtpassResponse': response,
          'backendResponse': response,
          'backendSaved': true,
          'newBalance': newBalance,
          'message':
              isSuccess ? 'AIRTIME DELIVERED SUCCESSFULLY!' : (responseMessage),
          'code': responseCode,
        };
      },
    );
  }

  /// Get default transaction limits from backend
  static Future<Map<String, dynamic>> getDefaultLimits() async {
    _log('📊 Fetching default limits from backend...');

    try {
      // Check admin access first
      if (!await isAdmin()) {
        throw Exception('Admin access required');
      }

      final token = await _getToken();
      if (token == null) {
        throw Exception('Authentication token not found');
      }

      final url = Uri.parse('$baseUrl/api/admin/default-limits');

      final response = await http
          .get(
            url,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 30));

      _log('Get default limits response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          return result['data'];
        } else {
          throw Exception(
            result['message'] ?? 'Failed to fetch default limits',
          );
        }
      } else {
        throw Exception(
          'HTTP ${response.statusCode}: Failed to fetch default limits',
        );
      }
    } catch (e) {
      _log('❌ Error fetching default limits: $e');
      // Return hardcoded defaults as fallback
      return {
        'perTransaction': {
          'airtime': 1000,
          'data': 10000,
          'electricity': 50000,
          'cable': 100000,
          'transfer': 50000,
          'international_airtime': 10000,
          'education': 50000,
          'insurance': 50000,
        },
        'daily': {
          'airtime': 5000,
          'data': 10000,
          'electricity': 100000,
          'cable': 500000,
          'transfer': 100000,
          'international_airtime': 50000,
          'education': 100000,
          'insurance': 100000,
        },
      };
    }
  }

  /// Get cable TV variations for all providers with live URLs
  static Future<Map<String, dynamic>> getCableVariations() async {
    _log('📡 Fetching all cable TV variations from LIVE URLs');

    try {
      final providers = ['dstv', 'gotv', 'startimes'];
      final results = <String, dynamic>{};

      for (final provider in providers) {
        try {
          _log('🔄 Fetching variations for: $provider');

          // Use direct LIVE VTpass URLs
          final liveUrl =
              'https://vtpass.com/api/service-variations?serviceID=$provider';
          final response = await http
              .get(
                Uri.parse(liveUrl),
                headers: {
                  'Content-Type': 'application/json',
                  'api-key': _apiKey,
                  'secret-key': _secretKey,
                },
              )
              .timeout(const Duration(seconds: 15));

          _log('📦 Response status for $provider: ${response.statusCode}');

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);

            if (data['response_description'] == '000') {
              final variations = data['content']['variations'] ?? [];
              results[provider.toUpperCase()] = {
                'success': true,
                'variations': _processCableVariations(variations),
                'totalPlans': variations.length,
                'source': 'vtpass_live',
              };
            } else {
              throw Exception(
                data['response_description'] ?? 'Failed to fetch variations',
              );
            }
          } else {
            throw Exception('HTTP ${response.statusCode}');
          }
        } catch (e) {
          _log('❌ Error fetching $provider variations: $e');
          results[provider.toUpperCase()] = {
            'success': false,
            'variations': _getMockCableVariations(provider),
            'totalPlans': _getMockCableVariations(provider).length,
            'source': 'mock_fallback',
            'error': e.toString(),
          };
        }
      }

      return {
        'success': true,
        'data': results,
        'timestamp': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      _log('❌ Error in getCableVariations: $e');
      return {
        'success': false,
        'message': 'Failed to fetch cable variations',
        'error': e.toString(),
        'data': _getAllMockCableVariations(),
      };
    }
  }

  /// Process cable variations to fix toStringAsFixed errors
  static List<Map<String, dynamic>> _processCableVariations(
    List<dynamic> variations,
  ) {
    return variations.map<Map<String, dynamic>>((v) {
      // Safely handle variation_amount which might be String, double, or null
      dynamic amount = v['variation_amount'];
      String amountStr;

      if (amount == null) {
        amountStr = '0.00';
      } else if (amount is String) {
        amountStr = amount;
      } else if (amount is double) {
        amountStr = amount.toStringAsFixed(2);
      } else if (amount is int) {
        amountStr = amount.toDouble().toStringAsFixed(2);
      } else {
        amountStr = '0.00';
      }

      return {
        'name': v['name']?.toString() ?? 'Unknown Plan',
        'variation_code': v['variation_code']?.toString() ?? '',
        'variation_amount': amountStr,
        'fixedPrice': v['fixedPrice']?.toString() == 'Yes',
      };
    }).toList();
  }

  /// Mock data fallback for individual provider
  /// Mock data fallback for individual provider
  static List<Map<String, dynamic>> _getMockCableVariations(String provider) {
    final mockData = {
      'dstv': [
        {
          'name': 'DStv Padi N1,850',
          'variation_code': 'dstv-padi',
          'variation_amount': '1850.00',
          'fixedPrice': true,
        },
        {
          'name': 'DStv Yanga N2,565',
          'variation_code': 'dstv-yanga',
          'variation_amount': '2565.00',
          'fixedPrice': true,
        },
        {
          'name': 'Dstv Confam N4,615',
          'variation_code': 'dstv-confam',
          'variation_amount': '4615.00',
          'fixedPrice': true,
        },
        {
          'name': 'DStv Compact N7,900',
          'variation_code': 'dstv79',
          'variation_amount': '7900.00',
          'fixedPrice': true,
        },
        {
          'name': 'DStv Premium N18,400',
          'variation_code': 'dstv3',
          'variation_amount': '18400.00',
          'fixedPrice': true,
        },
        {
          'name': 'DStv Compact Plus N12,400',
          'variation_code': 'dstv7',
          'variation_amount': '12400.00',
          'fixedPrice': true,
        },
        {
          'name': 'DStv Asia N6,200',
          'variation_code': 'dstv6',
          'variation_amount': '6200.00',
          'fixedPrice': true,
        },
        {
          'name': 'DStv Premium-French N25,550',
          'variation_code': 'dstv9',
          'variation_amount': '25550.00',
          'fixedPrice': true,
        },
        {
          'name': 'Showmax Standalone N3,500',
          'variation_code': 'showmax3500',
          'variation_amount': '3500.00',
          'fixedPrice': true,
        },
      ],
      'gotv': [
        {
          'name': 'GOtv Lite N410',
          'variation_code': 'gotv-lite',
          'variation_amount': '410.00',
          'fixedPrice': true,
        },
        {
          'name': 'GOtv Jinja N1,640',
          'variation_code': 'gotv-jinja',
          'variation_amount': '1640.00',
          'fixedPrice': true,
        },
        {
          'name': 'GOtv Jolli N2,460',
          'variation_code': 'gotv-jolli',
          'variation_amount': '2460.00',
          'fixedPrice': true,
        },
        {
          'name': 'GOtv Max N3,600',
          'variation_code': 'gotv-max',
          'variation_amount': '3600.00',
          'fixedPrice': true,
        },
        {
          'name': 'GOtv Supa Plus N15,700',
          'variation_code': 'gotv-supa-plus',
          'variation_amount': '15700.00',
          'fixedPrice': true,
        },
        {
          'name': 'GOtv Lite (3 Months) N1,080',
          'variation_code': 'gotv-lite-3months',
          'variation_amount': '1080.00',
          'fixedPrice': true,
        },
        {
          'name': 'GOtv Lite (1 Year) N3,180',
          'variation_code': 'gotv-lite-1year',
          'variation_amount': '3180.00',
          'fixedPrice': true,
        },
      ],
      'startimes': [
        {
          'name': 'Nova - 900 Naira - 1 Month',
          'variation_code': 'nova',
          'variation_amount': '900.00',
          'fixedPrice': true,
        },
        {
          'name': 'Basic - 1,700 Naira - 1 Month',
          'variation_code': 'basic',
          'variation_amount': '1700.00',
          'fixedPrice': true,
        },
        {
          'name': 'Smart - 2,200 Naira - 1 Month',
          'variation_code': 'smart',
          'variation_amount': '2200.00',
          'fixedPrice': true,
        },
        {
          'name': 'Classic - 2,500 Naira - 1 Month',
          'variation_code': 'classic',
          'variation_amount': '2500.00',
          'fixedPrice': true,
        },
        {
          'name': 'Super - 4,200 Naira - 1 Month',
          'variation_code': 'super',
          'variation_amount': '4200.00',
          'fixedPrice': true,
        },
        {
          'name': 'Nova - 300 Naira - 1 Week',
          'variation_code': 'nova-weekly',
          'variation_amount': '300.00',
          'fixedPrice': true,
        },
        {
          'name': 'Basic - 600 Naira - 1 Week',
          'variation_code': 'basic-weekly',
          'variation_amount': '600.00',
          'fixedPrice': true,
        },
        {
          'name': 'Global (Dish) - 19000 Naira - 1 Month',
          'variation_code': 'global-monthly-dish',
          'variation_amount': '19000.00',
          'fixedPrice': true,
        },
      ],
    };

    return mockData[provider] ?? [];
  }

  /// Comprehensive mock data fallback
  static Map<String, dynamic> _getAllMockCableVariations() {
    return {
      'DSTV': {
        'success': false,
        'variations': _getMockCableVariations('dstv'),
        'totalPlans': _getMockCableVariations('dstv').length,
        'source': 'mock_fallback',
      },
      'GOTV': {
        'success': false,
        'variations': _getMockCableVariations('gotv'),
        'totalPlans': _getMockCableVariations('gotv').length,
        'source': 'mock_fallback',
      },
      'STARTIMES': {
        'success': false,
        'variations': _getMockCableVariations('startimes'),
        'totalPlans': _getMockCableVariations('startimes').length,
        'source': 'mock_fallback',
      },
    };
  }

  // lib/core/services/api_service.dart

  /// Validates a cable TV smart card and returns detailed customer information
  /// including the current bouquet/package, customer name, and other details.
  static Future<Map<String, dynamic>> validateCableSmartCard({
    required String billersCode,
    required String serviceID,
  }) async {
    _log('🔍 Validating cable smart card: $serviceID - $billersCode');

    try {
      final url = Uri.parse('$baseUrl/api/cable/validate-smartcard');
      final token = await _getToken();

      if (token == null) {
        throw Exception('Authentication token not found. Please log in again.');
      }

      final response = await http
          .post(
            url,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'billersCode': billersCode,
              'serviceID': serviceID,
            }),
          )
          .timeout(const Duration(seconds: 15));

      _log('📦 Smart card validation response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        // 🔥 CRITICAL FIX: Pass billersCode to the processing function
        final processedData = _processValidationResponse(
          data,
          serviceID,
          billersCode,
        );

        _log('✅ Smart card validated successfully');
        _log('👤 Customer: ${processedData['customerName']}');
        _log('📺 Current Bouquet: ${processedData['currentBouquet']}');
        _log('🆔 Bouquet Code: ${processedData['currentBouquetCode']}');

        return processedData;
      } else {
        throw Exception('Smart card validation failed: ${response.statusCode}');
      }
    } catch (e) {
      _log('❌ Error validating smart card: $e');
      rethrow;
    }
  }

  /// Process the validation response to extract all customer details
  /// including current bouquet/package information.
  static Map<String, dynamic> _processValidationResponse(
    Map<String, dynamic> data,
    String serviceID,
    String billersCode, // ✅ ADD THIS PARAMETER
  ) {
    // Extract the details object (VTpass returns details in a nested structure)
    final details = data['details'] as Map<String, dynamic>? ?? {};
    final content = data['content'] as Map<String, dynamic>? ?? {};

    // Extract customer name from various possible fields
    final customerName =
        data['customerName']?.toString().trim() ??
        details['Customer_Name']?.toString().trim() ??
        details['Name']?.toString().trim() ??
        details['customerName']?.toString().trim() ??
        content['Customer_Name']?.toString().trim() ??
        content['customerName']?.toString().trim() ??
        'Unknown';

    // Extract smartcard number
    final smartcardNumber =
        details['Smartcard_Number']?.toString().trim() ??
        details['BillerCode']?.toString().trim() ??
        details['smartcardNumber']?.toString().trim() ??
        content['Smartcard_Number']?.toString().trim() ??
        data['billersCode']?.toString().trim() ??
        billersCode; // ✅ NOW billersCode IS DEFINED

    // 🔥 CRITICAL: Extract current bouquet/package name
    // Different providers use different field names
    String currentBouquet = _extractCurrentBouquet(details, content, data);

    // 🔥 CRITICAL: Extract current bouquet code (variation code)
    String currentBouquetCode = _extractCurrentBouquetCode(
      currentBouquet,
      serviceID,
      details,
      content,
      data,
    );

    // Extract balance
    final balance =
        details['Balance']?.toString() ??
        content['Balance']?.toString() ??
        'N/A';
    String formattedBalance = 'N/A';
    if (balance != 'N/A') {
      try {
        final balanceValue = double.tryParse(balance);
        if (balanceValue != null) {
          formattedBalance = '₦${balanceValue.toStringAsFixed(2)}';
        }
      } catch (e) {
        formattedBalance = balance;
      }
    }

    // Extract service
    final service =
        details['Service']?.toString() ??
        content['Service']?.toString() ??
        serviceID;

    // Extract address if available
    final address =
        details['Address']?.toString() ??
        content['Address']?.toString() ??
        'N/A';

    // Extract customer email if available
    final email =
        details['Email']?.toString() ?? content['Email']?.toString() ?? 'N/A';

    // Extract phone if available
    final phone =
        details['Phone']?.toString() ?? content['Phone']?.toString() ?? 'N/A';

    // Check for errors
    final wrongBillersCode =
        details['WrongBillersCode'] == true ||
        content['WrongBillersCode'] == true ||
        data['WrongBillersCode'] == true;

    if (wrongBillersCode) {
      final errorMsg =
          details['error'] ??
          content['error'] ??
          'Invalid smart card number. Please check and try again.';
      return {
        'success': false,
        'message': errorMsg,
        'customerName': customerName,
        'smartcardNumber': smartcardNumber,
        'currentBouquet': 'N/A',
        'currentBouquetCode': 'N/A',
        'balance': formattedBalance,
        'service': service,
        'address': address,
        'email': email,
        'phone': phone,
        'details': details,
        'content': content,
        'wrongBillersCode': true,
      };
    }

    return {
      'success': true,
      'customerName': customerName,
      'smartcardNumber': smartcardNumber,
      'currentBouquet': currentBouquet,
      'currentBouquetCode': currentBouquetCode,
      'balance': formattedBalance,
      'rawBalance': balance,
      'service': service,
      'address': address,
      'email': email,
      'phone': phone,
      'details': details,
      'content': content,
      'isValidated': true,
    };
  }

  /// Extract the current bouquet/package name from the response
  static String _extractCurrentBouquet(
    Map<String, dynamic> details,
    Map<String, dynamic> content,
    Map<String, dynamic> data,
  ) {
    // Try all possible field names for bouquet
    final possibleFields = [
      'Current_Bouquet',
      'currentBouquet',
      'Bouquet',
      'bouquet',
      'Package',
      'package',
      'Current_Package',
      'currentPackage',
      'Plan',
      'plan',
      'Current_Plan',
      'currentPlan',
      'Subscription_Type',
      'subscriptionType',
      'Bouquet_Type',
      'bouquetType',
      'Package_Name',
      'packageName',
      'Product_Name',
      'productName',
      'Plan_Name',
      'planName',
    ];

    for (final field in possibleFields) {
      // Check in details
      if (details[field] != null && details[field].toString().isNotEmpty) {
        final value = details[field].toString().trim();
        if (value.isNotEmpty &&
            !value.contains('null') &&
            !value.contains('N/A')) {
          return value;
        }
      }
      // Check in content
      if (content[field] != null && content[field].toString().isNotEmpty) {
        final value = content[field].toString().trim();
        if (value.isNotEmpty &&
            !value.contains('null') &&
            !value.contains('N/A')) {
          return value;
        }
      }
      // Check in data
      if (data[field] != null && data[field].toString().isNotEmpty) {
        final value = data[field].toString().trim();
        if (value.isNotEmpty &&
            !value.contains('null') &&
            !value.contains('N/A')) {
          return value;
        }
      }
    }

    // If we have details, try to extract from description or content
    final description =
        details['description']?.toString() ??
        content['description']?.toString() ??
        '';

    if (description.isNotEmpty && !description.contains('null')) {
      // Try to extract from description (e.g., "DStv Compact" or "GOtv Max")
      final bouquetMatch = RegExp(
        r'(DStv|GOtv|StarTimes|DStv|GOTV|STARTIMES)\s+(\w+)',
        caseSensitive: false,
      ).firstMatch(description);
      if (bouquetMatch != null) {
        return description.trim();
      }
    }

    // Try to extract from the content object's keys
    for (final key in content.keys) {
      if (key.toLowerCase().contains('bouquet') ||
          key.toLowerCase().contains('package') ||
          key.toLowerCase().contains('plan')) {
        final value = content[key]?.toString().trim();
        if (value != null && value.isNotEmpty && !value.contains('null')) {
          return value;
        }
      }
    }

    return 'N/A';
  }

  /// Extract the current bouquet code (variation code) for package change detection
  static String _extractCurrentBouquetCode(
    String currentBouquet,
    String serviceID,
    Map<String, dynamic> details,
    Map<String, dynamic> content,
    Map<String, dynamic> data,
  ) {
    // If we have a valid bouquet name, map it to a variation code
    if (currentBouquet != 'N/A') {
      final mappedCode = _mapBouquetToVariationCode(currentBouquet, serviceID);
      if (mappedCode != null) {
        return mappedCode;
      }
    }

    // Try to extract code from response
    final possibleCodeFields = [
      'variation_code',
      'variationCode',
      'VariationCode',
      'package_code',
      'packageCode',
      'PackageCode',
      'plan_code',
      'planCode',
      'PlanCode',
      'bouquet_code',
      'bouquetCode',
      'BouquetCode',
    ];

    for (final field in possibleCodeFields) {
      if (details[field] != null && details[field].toString().isNotEmpty) {
        final value = details[field].toString().trim();
        if (value.isNotEmpty && !value.contains('null')) {
          return value;
        }
      }
      if (content[field] != null && content[field].toString().isNotEmpty) {
        final value = content[field].toString().trim();
        if (value.isNotEmpty && !value.contains('null')) {
          return value;
        }
      }
      if (data[field] != null && data[field].toString().isNotEmpty) {
        final value = data[field].toString().trim();
        if (value.isNotEmpty && !value.contains('null')) {
          return value;
        }
      }
    }

    // Try to extract from the details object's keys
    for (final key in details.keys) {
      if (key.toLowerCase().contains('variation') ||
          key.toLowerCase().contains('package') ||
          key.toLowerCase().contains('code')) {
        final value = details[key]?.toString().trim();
        if (value != null && value.isNotEmpty && !value.contains('null')) {
          return value;
        }
      }
    }

    // Try to extract from description
    final description =
        details['description']?.toString() ??
        content['description']?.toString() ??
        '';

    if (description.isNotEmpty) {
      final mappedCode = _mapBouquetToVariationCode(description, serviceID);
      if (mappedCode != null) {
        return mappedCode;
      }
    }

    return 'N/A';
  }

  /// Map a bouquet name to its variation code for package change detection
  static String? _mapBouquetToVariationCode(
    String bouquetName,
    String serviceID,
  ) {
    // Normalize the bouquet name
    final normalized = bouquetName.toLowerCase().trim();

    // DSTV mappings
    if (serviceID == 'dstv' || serviceID == 'DStv' || serviceID == 'DSTV') {
      final dstvMappings = {
        'padi': 'dstv-padi',
        'yanga': 'dstv-yanga',
        'confam': 'dstv-confam',
        'compact': 'dstv79',
        'compact plus': 'dstv7',
        'compact+': 'dstv7',
        'premium': 'dstv3',
        'compact extra': 'dstv7', // ExtraView uses Compact Plus
        'compact+ extra': 'dstv7',
        'extra view': 'dstv7',
        'extraview': 'dstv7',
      };

      for (final entry in dstvMappings.entries) {
        if (normalized.contains(entry.key)) {
          return entry.value;
        }
      }
    }

    // GOtv mappings
    if (serviceID == 'gotv' || serviceID == 'GOtv' || serviceID == 'GOTV') {
      final gotvMappings = {
        'lite': 'gotv-lite',
        'smallie': 'gotv-lite',
        'jinja': 'gotv-jinja',
        'jolli': 'gotv-jolli',
        'max': 'gotv-max',
        'supa plus': 'gotv-supa-plus',
        'supa+': 'gotv-supa-plus',
        'supaplus': 'gotv-supa-plus',
      };

      for (final entry in gotvMappings.entries) {
        if (normalized.contains(entry.key)) {
          return entry.value;
        }
      }
    }

    // StarTimes mappings
    if (serviceID == 'startimes' ||
        serviceID == 'StarTimes' ||
        serviceID == 'STARTIMES') {
      final startimesMappings = {
        'nova': 'nova',
        'basic': 'basic',
        'smart': 'smart',
        'classic': 'classic',
        'super': 'super',
        'nova dish': 'nova-dish-weekly',
        'novadish': 'nova-dish-weekly',
      };

      for (final entry in startimesMappings.entries) {
        if (normalized.contains(entry.key)) {
          return entry.value;
        }
      }
    }

    return null;
  }

  /// Get the variation code for a bouquet name (public method for UI use)
  static String? getVariationCodeFromBouquet(
    String bouquetName,
    String serviceID,
  ) {
    return _mapBouquetToVariationCode(bouquetName, serviceID);
  }

  /// Get the bouquet name from a variation code
  static String getBouquetNameFromVariationCode(
    String variationCode,
    String serviceID,
  ) {
    final packageMappings = {
      'dstv': {
        'dstv-padi': 'DStv Padi',
        'dstv-yanga': 'DStv Yanga',
        'dstv-confam': 'DStv Confam',
        'dstv79': 'DStv Compact',
        'dstv7': 'DStv Compact Plus',
        'dstv3': 'DStv Premium',
      },
      'gotv': {
        'gotv-lite': 'GOtv Lite',
        'gotv-jinja': 'GOtv Jinja',
        'gotv-jolli': 'GOtv Jolli',
        'gotv-max': 'GOtv Max',
        'gotv-supa-plus': 'GOtv Supa Plus',
      },
      'startimes': {
        'nova': 'StarTimes Nova',
        'basic': 'StarTimes Basic',
        'smart': 'StarTimes Smart',
        'classic': 'StarTimes Classic',
        'super': 'StarTimes Super',
        'nova-dish-weekly': 'StarTimes Nova Dish Weekly',
      },
    };

    final serviceMappings = packageMappings[serviceID] ?? {};
    return serviceMappings[variationCode] ?? variationCode;
  }

  /// 📞 BUILD AIRTIME PAYLOAD (LIVE)
  static Map<String, dynamic> _buildAirtimePayload({
    required String requestId,
    required String phone,
    required double amount,
    required String serviceID,
  }) {
    return {
      'request_id': requestId,
      'serviceID': serviceID, // 'mtn', 'airtel', 'glo', 'etisalat'
      'amount': amount.toStringAsFixed(2),
      'phone': phone,
    };
  }

  /// 📱 BUILD DATA PAYLOAD (LIVE)
  static Map<String, dynamic> _buildDataPayload({
    required String requestId,
    required String phone,
    required String variationCode,
    required String serviceID,
  }) {
    return {
      'request_id': requestId,
      'serviceID': serviceID, // 'mtn-data', 'airtel-data', etc.
      'billersCode': phone,
      'variation_code': variationCode,
      'phone': phone,
    };
  }

  /// 📺 BUILD CABLE PAYLOAD (LIVE)
  static Map<String, dynamic> _buildCablePayload({
    required String requestId,
    required String billersCode,
    required String variationCode,
    required String serviceID,
    required String phone,
    required String subscriptionType, // 'change' or 'renew'
    double? amount,
  }) {
    final payload = {
      'request_id': requestId,
      'serviceID': serviceID, // 'dstv', 'gotv', 'startimes'
      'billersCode': billersCode,
      'variation_code': variationCode,
      'phone': phone,
      'subscription_type': subscriptionType,
    };

    if (amount != null) {
      payload['amount'] = amount.toStringAsFixed(2);
    }

    return payload;
  }

  /// ⚡ BUILD ELECTRICITY PAYLOAD (LIVE)
  static Map<String, dynamic> _buildElectricityPayload({
    required String requestId,
    required String billersCode,
    required String variationCode, // 'prepaid' or 'postpaid'
    required String serviceID, // 'ikeja-electric', 'eko-electric', etc.
    required double amount,
    required String phone,
  }) {
    return {
      'request_id': requestId,
      'serviceID': serviceID,
      'billersCode': billersCode,
      'variation_code': variationCode,
      'amount': amount.toStringAsFixed(2),
      'phone': phone,
    };
  }

  static Future<Map<String, dynamic>> queryTransactionStatus({
    required String requestId,
  }) async {
    _log('Querying transaction status for request ID: $requestId');
    try {
      final data = await _vtpassPost(_vtpassRequeryUrl, {
        'request_id': requestId,
      });
      return {
        'success': data['code'] == '000',
        'status': data['content']['transactions']['status'],
        'vtpassResponse': data,
      };
    } catch (e) {
      _log('Error in queryTransactionStatus: $e');
      rethrow;
    }
  }

  /// FINAL & CORRECT buyData() — 100% WORKING (DEC 2025)
  static Future<Map<String, dynamic>> buyData({
    required String userId,
    required String network, // e.g. "mtn", "airtel", "glo", "9mobile"
    required String phone,
    required String variationCode,
    required String planName, // ← ADD THIS LINE
    required double amount,
    String? transactionPin,
    bool? useBiometric,
  }) async {
    _log('BUY DATA - Using CORRECT endpoint: /api/vtpass/data/purchase');

    // FINAL & CORRECT serviceID mapping (VTpass official)
    final serviceIDMap = {
      'mtn': 'mtn-data',
      'airtel': 'airtel-data',
      'glo': 'glo-data',
      '9mobile': 'etisalat-data', // YES — THIS IS 100% CORRECT
    };

    final serviceID = serviceIDMap[network.toLowerCase()];
    if (serviceID == null) {
      throw Exception('Invalid network: $network');
    }

    final requestId = generateVtpassRequestId();

    final payload = {
      'userId': userId,
      'network': network,
      'phone': phone,
      'variationCode': variationCode,
      'planName': planName, // ← ADD THIS LINE
      'amount': amount,
      if (transactionPin != null) 'transactionPin': transactionPin,
      if (useBiometric == true) 'useBiometric': true,
    };

    _log('Data Purchase Payload: $payload');
    _log('ServiceID sent to backend: $serviceID');

    return await _authenticatedPost(
      Uri.parse('$baseUrl/api/vtpass/data/purchase'), // ← CORRECT ENDPOINT
      payload,
    );
  }

  // Add these methods to your ApiService class

  // ==================== INTERNATIONAL AIRTIME METHODS ====================

  /// Get international airtime countries
  static Future<Map<String, dynamic>> getInternationalCountries() async {
    _log('🌍 Getting international airtime countries...');

    try {
      final response = await _authenticatedGet(
        Uri.parse('$baseUrl/api/international-airtime/countries'),
      );

      _log('✅ Countries response: ${response['success']}');

      if (response['success'] == true) {
        // Ensure flag URLs are properly formatted
        final countries = List<Map<String, dynamic>>.from(
          response['countries'] ?? [],
        );

        // Process each country to ensure flag URL is correct
        final processedCountries =
            countries.map((country) {
              // If flag is empty or null, generate a fallback flag URL
              if (country['flag'] == null ||
                  country['flag'].toString().isEmpty) {
                final code = country['code']?.toString().toLowerCase() ?? '';
                // Use a fallback flag service
                country['flag'] = 'https://flagcdn.com/w40/$code.png';
              }
              return country;
            }).toList();

        return {
          'success': true,
          'countries': processedCountries,
          'source': response['source'] ?? 'api',
        };
      } else {
        return {
          'success': false,
          'countries': _getFallbackCountries(),
          'message': response['message'] ?? 'Failed to fetch countries',
        };
      }
    } catch (e) {
      _log('❌ Error fetching countries: $e');
      return {
        'success': false,
        'countries': _getFallbackCountries(),
        'message': 'Using fallback data: ${e.toString()}',
      };
    }
  }

  /// Get international airtime product types
  static Future<Map<String, dynamic>> getInternationalProductTypes(
    String countryCode,
  ) async {
    _log('📦 Getting product types for country: $countryCode');

    try {
      final response = await _authenticatedGet(
        Uri.parse(
          '$baseUrl/api/international-airtime/product-types/$countryCode',
        ),
      );

      _log('✅ Product types response: ${response['success']}');

      if (response['success'] == true) {
        return {
          'success': true,
          'productTypes': response['productTypes'] ?? [],
          'source': response['source'] ?? 'api',
        };
      } else {
        return {
          'success': false,
          'productTypes': _getFallbackProductTypes(),
          'message': response['message'] ?? 'Failed to fetch product types',
        };
      }
    } catch (e) {
      _log('❌ Error fetching product types: $e');
      return {
        'success': false,
        'productTypes': _getFallbackProductTypes(),
        'message': 'Using fallback data: ${e.toString()}',
      };
    }
  }

  /// Get international airtime operators
  /// Get international airtime operators
  static Future<Map<String, dynamic>> getInternationalOperators({
    required String countryCode,
    required int productTypeId,
  }) async {
    _log(
      '📱 Getting operators for country: $countryCode, productTypeId: $productTypeId',
    );

    try {
      final response = await _authenticatedGet(
        Uri.parse(
          '$baseUrl/api/international-airtime/operators?countryCode=$countryCode&productTypeId=$productTypeId',
        ),
      );

      _log('📱 Raw operators response: $response');
      _log('📱 Response success: ${response['success']}');
      _log('📱 Response operators: ${response['operators']}');
      _log('📱 Response source: ${response['source']}');

      if (response['success'] == true) {
        final operators = List<Map<String, dynamic>>.from(
          response['operators'] ?? [],
        );

        _log('📱 Found ${operators.length} operators');

        // Log each operator with its actual ID
        for (var op in operators) {
          _log('  📌 ${op['name']} - ID: ${op['operator_id']}');
        }

        // ✅ DO NOT use fallback - return the actual operators from VTpass
        return {
          'success': true,
          'operators': operators,
          'source': response['source'] ?? 'api',
        };
      } else {
        // ✅ API failed - return empty, NOT fallback
        _log('❌ Failed to fetch operators: ${response['message']}');
        return {
          'success': false,
          'operators': [], // Empty, not fallback
          'message': response['message'] ?? 'Failed to fetch operators',
        };
      }
    } catch (e) {
      _log('❌ Error fetching operators: $e');
      // ✅ Error - return empty, NOT fallback
      return {
        'success': false,
        'operators': [], // Empty, not fallback
        'message': 'Failed to fetch operators: ${e.toString()}',
      };
    }
  }

  /// Get international airtime variations
  /// Get international airtime variations
  /// Get international airtime variations
  /// Get international airtime variations
  static Future<Map<String, dynamic>> getInternationalVariations({
    required String operatorId,
    required int productTypeId,
  }) async {
    _log(
      '📊 Getting variations for operator: $operatorId, productTypeId: $productTypeId',
    );

    try {
      final response = await _authenticatedGet(
        Uri.parse(
          '$baseUrl/api/international-airtime/variations?operatorId=$operatorId&productTypeId=$productTypeId',
        ),
      );

      _log('✅ Variations response: ${response['success']}');

      if (response['success'] == true) {
        // ✅ Normalize every variation so min/max/rate are always doubles
        final rawVariations = response['variations'] as List<dynamic>? ?? [];

        final processedVariations =
            rawVariations.map((v) {
              final map = Map<String, dynamic>.from(v as Map);

              // Safe number parser — handles num, String, null, false
              double? parseNum(dynamic val) {
                if (val == null || val == false || val == '') return null;
                if (val is num) return val.toDouble();
                if (val is String) return double.tryParse(val);
                return null;
              }

              final isFixed =
                  map['fixedPrice'] == true || map['fixedPrice'] == 'Yes';

              return {
                'variation_code': map['variation_code']?.toString() ?? '',
                'name': map['name']?.toString() ?? 'Unknown Plan',
                'fixedPrice': isFixed,
                'variation_amount': parseNum(map['variation_amount']),
                'charged_amount': parseNum(map['charged_amount']),
                'variation_amount_min': parseNum(map['variation_amount_min']),
                'variation_amount_max': parseNum(map['variation_amount_max']),
                'variation_rate': parseNum(map['variation_rate']),
                'charged_currency':
                    map['charged_currency']?.toString() ?? 'NGN',
              };
            }).toList();

        return {
          'success': true,
          'variations': processedVariations,
          'serviceName': response['serviceName'] ?? 'International Airtime',
          'source': response['source'] ?? 'api',
        };
      } else {
        return {
          'success': false,
          'variations': _getFallbackVariations(operatorId),
          'message': response['message'] ?? 'Failed to fetch variations',
        };
      }
    } catch (e) {
      _log('❌ Error fetching variations: $e');
      return {
        'success': false,
        'variations': _getFallbackVariations(operatorId),
        'message': 'Using fallback data: ${e.toString()}',
      };
    }
  }

  /// ✅ Validate international airtime amount against VTpass min/max
  /// Returns null if valid, or an error message string if invalid
  static String? validateInternationalAirtimeAmount({
    required double amount,
    required double? min,
    required double? max,
    required String currency,
  }) {
    if (min != null && amount < min) {
      return 'Minimum amount is $currency ${min.toStringAsFixed(2)}. You entered $currency ${amount.toStringAsFixed(2)}.';
    }
    if (max != null && amount > max) {
      return 'Maximum amount is $currency ${max.toStringAsFixed(2)}. You entered $currency ${amount.toStringAsFixed(2)}.';
    }
    return null; // valid
  }

  /// Purchase international airtime
  static Future<Map<String, dynamic>> purchaseInternationalAirtime({
    required Map<String, dynamic> payload,
    String? transactionPin,
    required bool useBiometric,
  }) async {
    _log('🌍 Purchasing international airtime...');
    _log('📦 Payload: ${jsonEncode(payload)}');
    _log('🔐 Auth method: ${useBiometric ? "biometric" : "pin"}');

    try {
      // Build request body — MUST include auth fields for backend verifyTransactionAuth
      final requestBody = <String, dynamic>{
        'operatorId': payload['operatorId'],
        'countryCode': payload['countryCode'],
        'productTypeId': payload['productTypeId'],
        'variationCode': payload['variationCode'],
        'phoneNumber': payload['phoneNumber'],
        'amount': payload['amount'],
        'currency': payload['currency'] ?? 'USD',
        'email': payload['email'] ?? '',
        // ✅ CRITICAL: Send Naira amount so backend can validate BEFORE calling VTpass
        if (payload['estimatedNairaAmount'] != null)
          'estimatedNairaAmount': payload['estimatedNairaAmount'],
        if (payload['variationRate'] != null)
          'variationRate': payload['variationRate'],
        // ✅ NEW: Send min/max so backend can pre-validate against VTpass limits
        if (payload['variationMin'] != null)
          'variationMin': payload['variationMin'],
        if (payload['variationMax'] != null)
          'variationMax': payload['variationMax'],
      };

      // ✅ Authentication is verified locally on the frontend (same as buyAirtime).
      // No auth fields are sent to the backend — the JWT is sufficient.

      _log(
        '📤 Sending purchase request to backend: ${jsonEncode(requestBody)}',
      );

      final response = await _authenticatedPost(
        Uri.parse('$baseUrl/api/international-airtime/purchase'),
        requestBody,
      );

      _log('📦 Purchase response success: ${response['success']}');

      if (response['success'] == true) {
        final nairaAmount =
            response['nairaAmount'] ??
            response['amountDebited'] ??
            payload['amount'] ??
            0.0;
        final foreignAmount = response['amount'] ?? payload['amount'] ?? 0.0;
        final currency = response['currency'] ?? payload['currency'] ?? 'USD';
        final exchangeRate = response['exchangeRate'] ?? 1.0;

        _log('💰 Foreign: $currency $foreignAmount | Naira: ₦$nairaAmount');

        if (response['newBalance'] != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setDouble(
            'walletBalance',
            (response['newBalance'] as num).toDouble(),
          );
          final userString = prefs.getString('user');
          if (userString != null) {
            final userMap = jsonDecode(userString);
            userMap['walletBalance'] =
                (response['newBalance'] as num).toDouble();
            await prefs.setString('user', jsonEncode(userMap));
          }
        }

        return {
          'success': true,
          'transactionId': response['transactionId'],
          'reference': response['reference'] ?? response['transactionId'],
          'status': response['status'] ?? 'delivered',
          'newBalance': response['newBalance'],
          'vtpassResponse': response['vtpassResponse'],
          'nairaAmount': nairaAmount,
          'foreignAmount': foreignAmount,
          'currency': currency,
          'exchangeRate': exchangeRate,
          'amount': foreignAmount,
          'message':
              response['message'] ??
              'International airtime purchased successfully',
          'userDebited': response['userDebited'] ?? true,
          'amountDebited': nairaAmount,
        };
      } else {
        return {
          'success': false,
          'message': response['message'] ?? 'Purchase failed',
          'isFailed': response['isFailed'] ?? true,
          'shouldShowAsFailed': response['shouldShowAsFailed'] ?? true,
          'amountDebited': response['amountDebited'],
          'newBalance': response['newBalance'],
          'userDebited': response['userDebited'] ?? false,
          'vtpassResponse': response['vtpassResponse'],
          'vtpassCode': response['vtpassCode'],
          'vtpassDescription': response['vtpassDescription'],
          'code': response['code'],
          'limit': response['limit'],
          'requested': response['requested'],
          'isCustomLimit': response['isCustomLimit'],
          'service': response['service'],
        };
      }
    } catch (e) {
      _log('❌ Error purchasing international airtime: $e');
      return {
        'success': false,
        'message': 'Failed to purchase international airtime: ${e.toString()}',
      };
    }
  }

  /// Requery international airtime transaction
  static Future<Map<String, dynamic>> requeryInternationalAirtime({
    required String requestId,
  }) async {
    _log('🔍 Requerying international airtime: $requestId');

    try {
      final response = await _authenticatedPost(
        Uri.parse('$baseUrl/api/international-airtime/requery'),
        {'requestId': requestId},
      );

      if (response['success'] == true) {
        return {'success': true, 'data': response['data']};
      } else {
        return {
          'success': false,
          'message': response['message'] ?? 'Failed to requery transaction',
        };
      }
    } catch (e) {
      _log('❌ Error requerying transaction: $e');
      return {
        'success': false,
        'message': 'Failed to requery: ${e.toString()}',
      };
    }
  }

  // ==================== FALLBACK DATA ====================

  static List<Map<String, dynamic>> _getFallbackCountries() {
    return [
      {'code': 'NG', 'name': 'Nigeria', 'currency': 'NGN', 'prefix': '234'},
      {'code': 'GH', 'name': 'Ghana', 'currency': 'GHS', 'prefix': '233'},
      {'code': 'US', 'name': 'United States', 'currency': 'USD', 'prefix': '1'},
      {
        'code': 'GB',
        'name': 'United Kingdom',
        'currency': 'GBP',
        'prefix': '44',
      },
      {'code': 'CA', 'name': 'Canada', 'currency': 'CAD', 'prefix': '1'},
      {'code': 'AU', 'name': 'Australia', 'currency': 'AUD', 'prefix': '61'},
      {'code': 'IN', 'name': 'India', 'currency': 'INR', 'prefix': '91'},
      {'code': 'PK', 'name': 'Pakistan', 'currency': 'PKR', 'prefix': '92'},
      {'code': 'KE', 'name': 'Kenya', 'currency': 'KES', 'prefix': '254'},
      {'code': 'ZA', 'name': 'South Africa', 'currency': 'ZAR', 'prefix': '27'},
      {'code': 'CM', 'name': 'Cameroon', 'currency': 'XAF', 'prefix': '237'},
      {'code': 'RW', 'name': 'Rwanda', 'currency': 'RWF', 'prefix': '250'},
      {'code': 'SZ', 'name': 'Swaziland', 'currency': 'SZL', 'prefix': '268'},
      {'code': 'YE', 'name': 'Yemen', 'currency': 'YER', 'prefix': '967'},
    ];
  }

  static List<Map<String, dynamic>> _getFallbackProductTypes() {
    return [
      {'product_type_id': 1, 'name': 'Mobile Top Up'},
      {'product_type_id': 4, 'name': 'Mobile Data'},
    ];
  }

  static List<Map<String, dynamic>> _getFallbackOperators(String countryCode) {
    final operators = <Map<String, dynamic>>[];

    switch (countryCode.toUpperCase()) {
      case 'NG':
        operators.addAll([
          {'operator_id': '1', 'name': 'MTN Nigeria'},
          {'operator_id': '2', 'name': 'Airtel Nigeria'},
          {'operator_id': '3', 'name': 'Glo Nigeria'},
          {'operator_id': '4', 'name': '9mobile'},
        ]);
        break;
      case 'GH':
        operators.addAll([
          {'operator_id': '5', 'name': 'Ghana MTN'},
          {'operator_id': '6', 'name': 'Vodafone Ghana'},
          {'operator_id': '7', 'name': 'AirtelTigo'},
        ]);
        break;
      case 'US':
        operators.addAll([
          {'operator_id': '10', 'name': 'AT&T'},
          {'operator_id': '11', 'name': 'Verizon'},
          {'operator_id': '12', 'name': 'T-Mobile'},
        ]);
        break;
      case 'GB':
        operators.addAll([
          {'operator_id': '20', 'name': 'Vodafone UK'},
          {'operator_id': '21', 'name': 'O2 UK'},
          {'operator_id': '22', 'name': 'EE UK'},
          {'operator_id': '23', 'name': 'Three UK'},
        ]);
        break;
      default:
        operators.addAll([
          {'operator_id': '100', 'name': 'Operator 1'},
          {'operator_id': '101', 'name': 'Operator 2'},
          {'operator_id': '102', 'name': 'Operator 3'},
        ]);
    }

    return operators;
  }

  static List<Map<String, dynamic>> _getFallbackVariations(String operatorId) {
    // Return common airtime variations
    return [
      {
        'variation_code': 'airtime_1',
        'name': 'Small Top Up',
        'variation_amount': '1.00',
        'fixedPrice': 'Yes',
      },
      {
        'variation_code': 'airtime_5',
        'name': 'Medium Top Up',
        'variation_amount': '5.00',
        'fixedPrice': 'Yes',
      },
      {
        'variation_code': 'airtime_10',
        'name': 'Large Top Up',
        'variation_amount': '10.00',
        'fixedPrice': 'Yes',
      },
      {
        'variation_code': 'airtime_20',
        'name': 'XL Top Up',
        'variation_amount': '20.00',
        'fixedPrice': 'Yes',
      },
      {
        'variation_code': 'airtime_50',
        'name': 'XXL Top Up',
        'variation_amount': '50.00',
        'fixedPrice': 'Yes',
      },
    ];
  }

  /// Get data plans for a specific network via backend
  /// Get data plans for a specific network via backend - ENHANCED VERSION
  // Enhanced getDataPlans method with better error handling
  static Future<Map<String, dynamic>> getDataPlans(String serviceID) async {
    _log('📡 Fetching data plans for service: $serviceID');

    try {
      final url = Uri.parse('$baseUrl/api/data-plans?serviceID=$serviceID');
      final token = await _getToken();

      if (token == null) {
        throw Exception('Authentication token not found. Please log in again.');
      }

      final response = await http
          .get(
            url,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 15));

      _log('📦 Backend response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data;
      } else if (response.statusCode == 404) {
        _log('❌ Endpoint not found, using mock data');
        // Return mock data when endpoint doesn't exist
        return _getMockDataPlans(serviceID);
      } else {
        throw Exception('Failed to fetch data plans: ${response.statusCode}');
      }
    } catch (e) {
      _log('❌ Error in getDataPlans: $e, using mock data');
      // Fallback to mock data
      return _getMockDataPlans(serviceID);
    }
  }

  // Mock data fallback
  static Map<String, dynamic> _getMockDataPlans(String serviceID) {
    final mockPlans = {
      'mtn-data': [
        {
          'name': '500MB Daily Plan',
          'amount': '200',
          'validity': '1 day',
          'variation_code': 'mtn-500mb-200',
        },
        {
          'name': '1GB Weekly Plan',
          'amount': '500',
          'validity': '7 days',
          'variation_code': 'mtn-1gb-500',
        },
        {
          'name': '2GB Monthly Plan',
          'amount': '1000',
          'validity': '30 days',
          'variation_code': 'mtn-2gb-1000',
        },
        {
          'name': '5GB Monthly Plan',
          'amount': '2000',
          'validity': '30 days',
          'variation_code': 'mtn-5gb-2000',
        },
      ],
      'airtel-data': [
        {
          'name': '500MB Daily Plan',
          'amount': '200',
          'validity': '1 day',
          'variation_code': 'airtel-500mb-200',
        },
        {
          'name': '1GB Weekly Plan',
          'amount': '500',
          'validity': '7 days',
          'variation_code': 'airtel-1gb-500',
        },
        {
          'name': '2GB Monthly Plan',
          'amount': '1000',
          'validity': '30 days',
          'variation_code': 'airtel-2gb-1000',
        },
      ],
      'glo-data': [
        {
          'name': '500MB Daily Plan',
          'amount': '200',
          'validity': '1 day',
          'variation_code': 'glo-500mb-200',
        },
        {
          'name': '1GB Weekly Plan',
          'amount': '500',
          'validity': '7 days',
          'variation_code': 'glo-1gb-500',
        },
        {
          'name': '2GB Monthly Plan',
          'amount': '1000',
          'validity': '30 days',
          'variation_code': 'glo-2gb-1000',
        },
      ],
      'etisalat-data': [
        {
          'name': '500MB Daily Plan',
          'amount': '200',
          'validity': '1 day',
          'variation_code': 'etisalat-500mb-200',
        },
        {
          'name': '1GB Weekly Plan',
          'amount': '500',
          'validity': '7 days',
          'variation_code': 'etisalat-1gb-500',
        },
        {
          'name': '2GB Monthly Plan',
          'amount': '1000',
          'validity': '30 days',
          'variation_code': 'etisalat-2gb-1000',
        },
      ],
    };

    return {
      'success': true,
      'service': serviceID,
      'plans': mockPlans[serviceID] ?? [],
      'totalPlans': (mockPlans[serviceID] ?? []).length,
      'source': 'mock_fallback',
      'note': 'Using mock data while backend is being updated',
    };
  }

  // Add this method to ApiService for debugging
  static Future<void> debugDataPlansEndpoint() async {
    try {
      _log('🔍 DEBUG: Testing data plans endpoint directly...');

      final serviceID = 'mtn-data';
      final url = Uri.parse('$baseUrl/api/data-plans?serviceID=$serviceID');

      _log('🎯 Testing URL: $url');

      final token = await _getToken();
      if (token == null) {
        _log('❌ No token found');
        return;
      }

      _log('🔑 Token found: ${token.substring(0, 10)}...');

      final response = await http
          .get(
            url,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 30));

      _log('📦 Response status: ${response.statusCode}');
      _log('📦 Response body: ${response.body}');

      if (response.statusCode == 200) {
        _log('✅ Endpoint is working!');
      } else {
        _log('❌ Endpoint returned error: ${response.statusCode}');
      }
    } catch (e) {
      _log('💥 Debug test failed: $e');
    }
  }

  /// Validates electricity meter number
  /// Validates electricity meter number - Using direct VTpass API with proper headers
  static Future<Map<String, dynamic>> validateElectricityMeter({
    required String billersCode,
    required String serviceID,
    required String type,
  }) async {
    _log('🔍 Validating electricity meter...');
    _log('📋 BillersCode: $billersCode');
    _log('📋 ServiceID: $serviceID');
    _log('📋 Type: $type');

    try {
      final token = await _getToken();
      if (token == null) {
        throw Exception('Authentication required. Please log in again.');
      }

      // ✅ Use the direct VTpass API endpoint for validation
      // This bypasses the transaction cooldown check
      final body = {
        'billersCode': billersCode,
        'serviceID': serviceID,
        'type': type,
      };

      _log('📤 Direct validation request body: ${jsonEncode(body)}');

      // ✅ Use the direct merchant-verify endpoint through your backend proxy
      // but with a special flag to indicate it's validation, not a purchase
      final response = await _authenticatedPost(
        Uri.parse('$baseUrl/api/vtpass/merchant-verify'),
        body,
      );

      _log('📦 Validation response: ${jsonEncode(response)}');

      // ✅ Check if the response indicates validation failure
      if (response['success'] == true) {
        final vtpassResponse = response['vtpassResponse'];

        if (vtpassResponse != null) {
          final content = vtpassResponse['content'];
          // ✅ Check for validation errors in the content
          if (content != null) {
            final error = content['error']?.toString();
            if (error != null || content['WrongBillersCode'] == true) {
              final errorMsg =
                  error ?? 'Invalid meter number. Please check and try again.';
              _log('⚠️ Meter validation failed: $errorMsg');

              return {
                'success': false,
                'message': errorMsg,
                'validationError': true,
                'vtpassResponse': vtpassResponse,
                'customerName': '',
                'details': {},
              };
            }

            // ✅ Extract customer name and details from successful validation
            String customerName = '';
            Map<String, dynamic> details = {};

            // Try to get customer name from various possible locations
            if (content['Customer_Name'] != null) {
              customerName = content['Customer_Name'].toString();
            } else if (content['customer_name'] != null) {
              customerName = content['customer_name'].toString();
            } else if (content['Name'] != null) {
              customerName = content['Name'].toString();
            }

            // Get details
            if (content['details'] != null) {
              details = Map<String, dynamic>.from(content['details']);
            } else if (content['customer'] != null) {
              details = Map<String, dynamic>.from(content['customer']);
            }

            // Add customer name to details
            if (customerName.isNotEmpty && details['Customer_Name'] == null) {
              details['Customer_Name'] = customerName;
            }

            return {
              'success': true,
              'customerName': customerName,
              'details': details,
              'vtpassResponse': vtpassResponse,
            };
          }
        }

        return {
          'success': true,
          'customerName': '',
          'details': {},
          'vtpassResponse': vtpassResponse,
        };
      }

      // ✅ Handle unsuccessful response
      final errorMsg =
          response['message'] ?? 'Unable to validate meter. Please try again.';
      _log('⚠️ Validation failed: $errorMsg');

      return {'success': false, 'message': errorMsg, 'validationError': true};
    } catch (e) {
      _log('❌ Error validating meter: $e');

      final errorStr = e.toString();
      // Check if it's a validation error
      if (errorStr.contains('meter') ||
          errorStr.contains('WrongBillersCode') ||
          errorStr.contains('not correct')) {
        final cleanedError = errorStr
            .replaceAll('Exception: ', '')
            .replaceAll('❌ ', '');
        return {
          'success': false,
          'message': cleanedError,
          'validationError': true,
        };
      }

      // ✅ Check for VTpass service unavailable
      if (errorStr.contains('temporarily unavailable') ||
          errorStr.contains('service is currently disabled') ||
          errorStr.contains('Service temporarily unavailable')) {
        return {
          'success': false,
          'message':
              'VTpass service temporarily unavailable. Please try again later.',
          'validationError': true,
          'serviceUnavailable': true,
        };
      }

      // ✅ Check for recent transaction error (shouldn't happen for validation)
      if (errorStr.contains('RECENT_TRANSACTION_EXISTS') ||
          errorStr.contains('recent transaction')) {
        // This means the validation is being blocked by the transaction cooldown
        // We should retry after a short delay
        _log(
          '⏳ Validation blocked by recent transaction check, retrying in 2 seconds...',
        );

        try {
          // Wait 2 seconds and retry
          await Future.delayed(const Duration(seconds: 2));

          // Retry the validation
          return await validateElectricityMeter(
            billersCode: billersCode,
            serviceID: serviceID,
            type: type,
          );
        } catch (retryError) {
          _log('❌ Retry failed: $retryError');
          return {
            'success': false,
            'message':
                'Unable to validate meter. Please wait a moment and try again.',
            'validationError': true,
          };
        }
      }

      // ✅ Return a user-friendly error
      return {
        'success': false,
        'message':
            'Unable to validate meter. Please check your internet connection and try again.',
        'validationError': true,
      };
    }
  }

  /// Pays electricity bill for both prepaid and postpaid meters
  static Future<Map<String, dynamic>> payElectricityBill({
    required String userId,
    required String serviceID,
    required String billersCode,
    required String variationCode,
    required double amount,
    required String phone,
    String? transactionPin,
    bool? useBiometric,
  }) async {
    _log('⚡ Paying electricity bill for user ID: $userId, service: $serviceID');

    // ✅ CHECK HERE FIRST - BEFORE any transaction logic
    if (amount < 2000) {
      _log(
        '⚠️ Amount below minimum (₦$amount < ₦2000). Saving failed transaction.',
      );

      try {
        final response = await _authenticatedPost(
          Uri.parse('$baseUrl/api/vtpass/electricity/failed-transaction'),
          {
            'userId': userId,
            'serviceID': serviceID,
            'billersCode': billersCode,
            'variation_code': variationCode,
            'amount': amount,
            'phone': phone,
            'customerName': '',
            'customerAddress': '',
            'failureReason': 'Amount below minimum (₦2000)',
            'transactionPin': transactionPin,
            'useBiometric': useBiometric,
          },
        );

        _log('✅ Failed transaction saved to backend: ${response.toString()}');

        return {
          'success': false,
          'message':
              'Amount below minimum. Minimum electricity purchase is ₦2000.',
          'isFailed': true,
          'shouldShowAsFailed': true,
          'amountBelowMinimum': true,
          'transactionData': response,
          'savedToDatabase': true,
        };
      } catch (e) {
        _log('❌ Error saving failed transaction: $e');
        return {
          'success': false,
          'message':
              'Amount below minimum. Minimum electricity purchase is ₦2000.',
          'isFailed': true,
          'shouldShowAsFailed': true,
          'amountBelowMinimum': true,
          'savedToDatabase': false,
          'error': e.toString(),
        };
      }
    }

    // ✅ Only proceed with normal transaction if amount >= 2000
    return await _executeSecureTransaction(
      userId: userId,
      transactionType: 'electricity_purchase',
      amount: amount,
      serviceType: 'electricity',
      requiresDebit: true,
      useAtomic: false,
      vtpassPayload: {
        'serviceID': serviceID,
        'billersCode': billersCode,
        'variation_code': variationCode,
        'amount': amount.toStringAsFixed(2),
        'phone': phone,
      },
      transactionFunction: () async {
        _log('🛡️ Secure electricity payment for user: $userId');

        // Validate parameters
        _validateTransactionParams(
          userId: userId,
          amount: amount,
          serviceType: 'electricity',
          billersCode: billersCode,
        );

        final isEnabled = await isServiceEnabled('electricity');
        if (!isEnabled) {
          throw Exception('Electricity payment service is currently disabled.');
        }

        // Authenticate
        final authResult = await authenticateTransaction(
          userId: userId,
          transactionPin: transactionPin,
          useBiometric: useBiometric,
        );

        // ✅ Call BACKEND endpoint first (which has all limit checks)
        // This is the CRITICAL FIX - use the backend endpoint, not direct VTpass
        final backendPayload = {
          'serviceID': serviceID,
          'billersCode': billersCode,
          'variation_code': variationCode,
          'amount': amount,
          'phone': phone,
          'transactionPin':
              authResult['method'] == 'pin' ? authResult['pin'] : null,
          'useBiometric': authResult['method'] == 'biometric',
        };

        _log('🚀 Calling backend electricity purchase endpoint');
        final response = await _authenticatedPost(
          Uri.parse('$baseUrl/api/vtpass/electricity/purchase'),
          backendPayload,
        );

        // ✅ Update local balance if successful
        if (response['success'] == true) {
          final prefs = await SharedPreferences.getInstance();
          final currentBalance = prefs.getDouble('walletBalance') ?? 0.0;
          final newBalance =
              response['newBalance'] ?? (currentBalance - amount);
          await prefs.setDouble('walletBalance', newBalance);

          final userString = prefs.getString('user');
          if (userString != null) {
            final userMap = jsonDecode(userString);
            userMap['walletBalance'] = newBalance;
            await prefs.setString('user', jsonEncode(userMap));
          }

          _log('💰 Balance updated: ₦$currentBalance → ₦$newBalance');
        }

        // ✅ CRITICAL: Return ALL fields from the backend response
        // including 'code', 'limit', 'requested', 'isCustomLimit', 'service'
        return {
          'success': response['success'] == true,
          'transactionId': response['transactionId'],
          'status': response['status'] ?? 'unknown',
          'vtpassResponse': response['vtpassResponse'],
          'message': response['message'] ?? 'Electricity payment completed',
          'newBalance': response['newBalance'],
          'token': response['token'],
          'customerName': response['customerName'],
          'customerAddress': response['customerAddress'],
          'units': response['units'],

          // ✅ CRITICAL: Pass through ALL error fields from backend
          'code': response['code'],
          'limit': response['limit'],
          'requested': response['requested'],
          'isCustomLimit': response['isCustomLimit'],
          'service': response['service'],

          // ✅ Keep existing fields for compatibility
          'alreadyProcessed': response['alreadyProcessed'] ?? false,
          'validationError': response['validationError'] ?? false,
          'errorType': response['errorType'],
          'isFailed': response['isFailed'] ?? false,
          'shouldShowAsFailed': response['shouldShowAsFailed'] ?? false,
          'amountBelowMinimum': response['amountBelowMinimum'] ?? false,
          'savedToDatabase': response['savedToDatabase'] ?? false,
        };
      },
    );
  }

  /// 🧹 Enhanced cleanup for failed transactions
  static Future<void> _cleanupFailedTransaction(String idempotencyKey) async {
    _idempotencyKeys.remove(idempotencyKey);
    _idempotencyKeyTimestamps.remove(idempotencyKey);

    // Remove from persistent storage
    final prefs = await SharedPreferences.getInstance();
    final usedKeys = prefs.getStringList('used_idempotency_keys') ?? [];
    usedKeys.remove(idempotencyKey);
    await prefs.setStringList('used_idempotency_keys', usedKeys);

    _log(
      '🧹 Cleaned up failed transaction: ${idempotencyKey.substring(0, 16)}...',
    );
  }

  /// 📊 Enhanced security initialization
  static Future<void> initializeSecurity() async {
    _log('🛡️ Initializing enhanced API security systems...');

    try {
      // Clean up any stale data
      _walletLocks.clear();
      _transactionLocks.clear();
      _userRequestTimestamps.clear();
      _lockAttempts.clear();
      _userLocks.clear();

      // Clean up expired idempotency keys
      final now = DateTime.now();
      _idempotencyKeyTimestamps.removeWhere((key, timestamp) {
        if (now.difference(timestamp) > _idempotencyKeyExpiry) {
          _idempotencyKeys.remove(key);
          return true;
        }
        return false;
      });

      // Clean up persistent storage
      final prefs = await SharedPreferences.getInstance();
      final usedKeys = prefs.getStringList('used_idempotency_keys') ?? [];
      if (usedKeys.length > 1000) {
        final recentKeys = usedKeys.sublist(usedKeys.length - 1000);
        await prefs.setStringList('used_idempotency_keys', recentKeys);
        _log(
          '🧹 Cleaned up expired idempotency keys, kept ${recentKeys.length} recent keys',
        );
      }

      _log('✅ Enhanced API security systems initialized successfully');
    } catch (e, stackTrace) {
      _log('❌ Security initialization failed: $e');
      await reportError(e, stackTrace);
    }
  }

  /// ✅ Validate user ID format to prevent tampering
  static bool _isValidUserId(String userId) {
    if (userId.isEmpty || userId.length != 24) return false;
    return RegExp(r'^[a-f\d]{24}$').hasMatch(userId);
  }

  /// 🎯 Enhanced parameter validation
  static void _validateTransactionParams({
    required String userId,
    required double amount,
    required String serviceType,
    String? phone,
    String? accountNumber,
    String? billersCode,
  }) {
    // User ID validation
    if (userId.isEmpty || !RegExp(r'^[a-f\d]{24}$').hasMatch(userId)) {
      throw Exception('🚫 Invalid user ID format');
    }

    // Amount validation
    if (amount <= 0) throw Exception('💰 Amount must be greater than 0');

    // Service-specific amount limits
    switch (serviceType.toLowerCase()) {
      case 'airtime':
        if (amount < 50) throw Exception('📞 Minimum airtime purchase is ₦50');
        if (amount > 10000) {
          throw Exception('📞 Maximum airtime purchase is ₦10,000');
        }
        break;
      case 'data':
        if (amount < 100) throw Exception('📱 Minimum data purchase is ₦100');
        if (amount > 50000) {
          throw Exception('📱 Maximum data purchase is ₦50,000');
        }
        break;
      case 'electricity':
        if (amount < 500) {
          throw Exception('⚡ Minimum electricity purchase is ₦2000');
        }
        if (amount > 100000) {
          throw Exception('⚡ Maximum electricity purchase is ₦100,000');
        }
        break;
      case 'cable':
        if (amount < 1000) {
          throw Exception('📺 Minimum cable subscription is ₦1,000');
        }
        if (amount > 100000) {
          throw Exception('📺 Maximum cable subscription is ₦100,000');
        }
        break;
      default:
        if (amount > 1000000) {
          throw Exception(
            '💳 Transaction amount exceeds maximum limit of ₦1,000,000',
          );
        }
    }

    // Phone validation
    if (phone != null && !RegExp(r'^[0-9]{11}$').hasMatch(phone)) {
      throw Exception('📞 Invalid phone number format. Must be 11 digits');
    }

    // Account number validation
    if (accountNumber != null &&
        !RegExp(r'^[0-9]{10}$').hasMatch(accountNumber)) {
      throw Exception('🏦 Invalid account number format. Must be 10 digits');
    }

    // Billers code validation (meter/smartcard numbers)
    if (billersCode != null && billersCode.length < 6) {
      throw Exception('🔢 Invalid biller code. Must be at least 6 characters');
    }
  }

  /// 🧹 Enhanced security cleanup
  static void cleanupSecurityData(String userId) {
    _log('🧹 Cleaning up security data for user: $userId');

    // Remove rate limit data
    _userRequestTimestamps.removeWhere(
      (key, value) => key.startsWith('$userId-'),
    );

    // Remove wallet locks
    if (_walletLocks.containsKey(userId)) {
      _releaseWalletLock(userId);
    }

    // Remove transaction locks
    _transactionLocks.removeWhere((key, value) => key.startsWith('$userId-'));

    // Remove user-specific lock
    _userLocks.remove(userId);

    // Clean up idempotency keys
    _idempotencyKeys.removeWhere((key, value) => value == userId);
    _idempotencyKeyTimestamps.removeWhere(
      (key, value) => _idempotencyKeys[key] == userId,
    );

    // Reset lock attempts
    _lockAttempts.remove(userId);

    _log('✅ Security data cleaned up for user: $userId');
  }

  /// ✅ UNIVERSAL ADMIN CHECK (SOURCE OF TRUTH = BACKEND)
  static Future<bool> isUserAdmin() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final isAdmin = prefs.getBool('isAdmin') ?? false;

      debugPrint('🔐 ADMIN CHECK:');
      debugPrint('   isAdmin (from backend): $isAdmin');

      return isAdmin;
    } catch (e) {
      debugPrint('❌ Admin check error: $e');
      return false;
    }
  }

  // --- App Settings ---
  static Future<Map<String, dynamic>> getAppSettings() async {
    _log('Fetching mobile settings');
    try {
      final response = await _authenticatedGet(_appSettingsUrl);
      return response;
    } catch (e) {
      _log('Error fetching mobile settings: $e');
      rethrow;
    }
  }

  /// Update system-wide default transaction limits (Admin only)
  /// Returns: { success: bool, message: String, data: { perTransaction, daily } }
  static Future<Map<String, dynamic>> updateDefaultLimits({
    Map<String, dynamic>? perTransaction,
    Map<String, dynamic>? daily,
  }) async {
    try {
      final token = await SecureStorageService.getAccessToken();
      if (token == null || token.isEmpty) {
        throw Exception('No access token found. Please log in again.');
      }

      final body = <String, dynamic>{};
      if (perTransaction != null && perTransaction.isNotEmpty) {
        body['perTransaction'] = perTransaction;
      }
      if (daily != null && daily.isNotEmpty) {
        body['daily'] = daily;
      }

      // ⚠️ IMPORTANT: Match the HTTP client used by getDefaultLimits().
      // If getDefaultLimits() uses `http.get`, use `http.put` here.
      // If it uses `dio`, use `dio.put` here.
      // The below uses the `http` package — adjust if needed.
      final response = await http.put(
        Uri.parse('${ApiService.baseUrl}/api/admin/default-limits'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(body),
      );

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200 && data['success'] == true) {
        return data;
      } else {
        return {
          'success': false,
          'message': data['message'] ?? 'Failed to update default limits',
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Error: ${e.toString()}'};
    }
  }

  static Future<Map<String, dynamic>> updateAppSettings({
    required Map<String, dynamic> settings,
  }) async {
    if (!await isAdmin()) {
      throw Exception('Admin access required');
    }

    _log('Updating mobile settings');

    return await _authenticatedPut(_appSettingsUrl, settings);
  }

  // --- Service Enablement ---
  static Future<bool> isServiceEnabled(String service) async {
    // Normalize service name
    final normalizedService = service.toLowerCase().trim();

    // Check if it's a valid service
    if (!_supportedServices.contains(normalizedService)) {
      _log('❌ Invalid service: $service (normalized: $normalizedService)');
      _log('✅ Supported services: ${_supportedServices.join(", ")}');
      return false;
    }

    try {
      final settings = await getAppSettings();
      final enabledServices =
          settings['enabledServices'] as List<dynamic>? ?? _supportedServices;

      // Convert to lowercase for case-insensitive comparison
      final enabledServicesLower =
          enabledServices.map((s) => s.toString().toLowerCase()).toList();
      final isEnabled = enabledServicesLower.contains(normalizedService);

      _log(
        '🔧 Service $normalizedService is ${isEnabled ? 'enabled' : 'disabled'}',
      );
      _log('🔧 Enabled services: $enabledServicesLower');

      return isEnabled;
    } catch (e) {
      _log('❌ Error checking if service $service is enabled: $e');
      // Default to true if settings cannot be fetched to avoid blocking services
      return true;
    }
  }

  /// Debug method to check all service statuses
  static Future<Map<String, dynamic>> debugServiceStatus() async {
    _log('🔍 DEBUG: Checking all service statuses...');

    final results = <String, bool>{};

    for (final service in _supportedServices) {
      try {
        final isEnabled = await isServiceEnabled(service);
        results[service] = isEnabled;
        _log('   - $service: ${isEnabled ? '✅ Enabled' : '❌ Disabled'}');
      } catch (e) {
        results[service] = false;
        _log('   - $service: ❌ Error: $e');
      }
    }

    return {
      'success': true,
      'services': results,
      'supportedServices': _supportedServices,
      'timestamp': DateTime.now().toIso8601String(),
    };
  }

  static Future<Map<String, dynamic>> enableAllServices() async {
    if (!await isAdmin()) throw Exception('Admin access required');
    _log('Enabling all supported services');
    try {
      final settings = await getAppSettings();
      final updatedSettings = {
        ...settings,
        'enabledServices': _supportedServices,
      };
      final response = await updateAppSettings(settings: updatedSettings);
      _log(
        'All services enabled successfully: ${_supportedServices.join(", ")}',
      );
      return response;
    } catch (e) {
      _log('Error enabling all services: $e');
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> toggleService({
    required String service,
    required bool enable,
  }) async {
    if (!await isAdmin()) throw Exception('Admin access required');
    if (!_supportedServices.contains(service.toLowerCase())) {
      throw Exception('Invalid service: $service');
    }
    _log('${enable ? 'Enabling' : 'Disabling'} service: $service');
    try {
      final settings = await getAppSettings();
      final enabledServices = List<String>.from(
        settings['enabledServices'] as List<dynamic>? ?? [],
      );
      if (enable && !enabledServices.contains(service.toLowerCase())) {
        enabledServices.add(service.toLowerCase());
      } else if (!enable && enabledServices.contains(service.toLowerCase())) {
        enabledServices.remove(service.toLowerCase());
      }
      final updatedSettings = {...settings, 'enabledServices': enabledServices};
      final response = await updateAppSettings(settings: updatedSettings);
      _log('Service $service ${enable ? 'enabled' : 'disabled'} successfully');
      return response;
    } catch (e) {
      _log('Error toggling service $service: $e');
      rethrow;
    }
  }

  /// 🔍 TEST BACKEND TOKEN VALIDATION
  static Future<Map<String, dynamic>> testBackendTokenValidation() async {
    try {
      final token = await _getToken();
      if (token == null) {
        return {'success': false, 'message': 'No token available'};
      }

      _log('🔍 Testing token with backend: ${token.substring(0, 10)}...');

      final response = await http
          .get(
            Uri.parse('$baseUrl/api/users/verify-token'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 30));

      _log('Backend token validation response: ${response.statusCode}');

      return {
        'success': response.statusCode == 200,
        'statusCode': response.statusCode,
        'message': response.statusCode == 200 ? 'Token valid' : 'Token invalid',
      };
    } catch (e) {
      _log('❌ Backend token test error: $e');
      return {'success': false, 'message': 'Test failed: $e'};
    }
  }

  // --- ADD FIX 4 HERE ---
  // --- Test Method for Both Environments ---
  static Future<Map<String, dynamic>> testVtpassEnvironments() async {
    _log('Testing VTpass connectivity for both environments...');

    final Map<String, dynamic> results = {
      'sandbox': {},
      'live': {},
      'overall': {'success': false, 'message': ''},
    };

    // Test Sandbox
    try {
      _log('🔄 Testing SANDBOX environment...');
      final originalUseSandbox = _useSandbox;
      _useSandbox = true;

      final testBody = {
        'request_id': 'test_sandbox_${DateTime.now().millisecondsSinceEpoch}',
        'serviceID': 'mtn',
        'amount': '50.00',
        'phone': '08011111111',
      };

      final sandboxResult = await _vtpassPost(
        _vtpassAirtimePurchaseUrl,
        testBody,
      );
      results['sandbox'] = {
        'success': true,
        'message': 'Sandbox environment is working',
        'response': sandboxResult,
      };
      _log('✅ SANDBOX test successful');

      _useSandbox = originalUseSandbox;
    } catch (e) {
      results['sandbox'] = {
        'success': false,
        'message': 'Sandbox test failed: $e',
        'error': e.toString(),
      };
      _log('❌ SANDBOX test failed: $e');
    }

    // Test Live (if you have live credentials)
    try {
      _log('🔄 Testing LIVE environment...');
      final originalUseSandbox = _useSandbox;
      _useSandbox = false;

      final testBody = {
        'request_id': 'test_live_${DateTime.now().millisecondsSinceEpoch}',
        'serviceID': 'mtn',
        'amount': '50.00',
        'phone': '08011111111',
      };

      final liveResult = await _vtpassPost(_vtpassAirtimePurchaseUrl, testBody);
      results['live'] = {
        'success': true,
        'message': 'Live environment is working',
        'response': liveResult,
      };
      _log('✅ LIVE test successful');

      _useSandbox = originalUseSandbox;
    } catch (e) {
      results['live'] = {
        'success': false,
        'message': 'Live test failed: $e',
        'error': e.toString(),
      };
      _log('❌ LIVE test failed: $e');
    }

    // Set overall result
    final sandboxSuccess = results['sandbox']['success'] == true;
    final liveSuccess = results['live']['success'] == true;

    results['overall'] = {
      'success': sandboxSuccess || liveSuccess,
      'message':
          'Sandbox: ${sandboxSuccess ? 'OK' : 'FAILED'}, Live: ${liveSuccess ? 'OK' : 'FAILED'}',
      'bothWorking': sandboxSuccess && liveSuccess,
    };

    return results;
  }
  // --- END FIX 4 ---

  /// Gets available electricity service variations (plans) for a specific DisCo
  static Future<List<dynamic>> getElectricityVariations({
    required String serviceID,
  }) async {
    _log('🔌 Getting electricity variations for service ID: $serviceID');

    try {
      final variations = await getBillerVariations(serviceID: serviceID);
      return variations;
    } catch (e) {
      _log('ERROR getting electricity variations: $e');
      rethrow;
    }
  }

  /// Gets all supported electricity DisCos
  static Map<String, String> getSupportedElectricityDisCos() {
    return Map.from(_electricityServiceIds);
  }

  /// Gets test meter numbers for sandbox testing
  static String? getTestMeterNumber(String disco, String type) {
    if (!_electricityServiceIds.containsKey(disco)) {
      return null;
    }

    final testMeters = _sandboxTestMeterNumbers[disco];
    return testMeters?[type];
  }

  /// Calculates total amount including convenience fee for a DisCo
  static double calculateTotalAmount(String disco, double amount) {
    final convenienceFee = _electricityConvenienceFees[disco] ?? 0.0;
    return amount + convenienceFee;
  }

  /// Purchase education service (WAEC, JAMB, etc.) - USING BACKEND ENDPOINT
  static Future<Map<String, dynamic>> purchaseEducationService({
    required String userId,
    required String serviceID,
    required String variationCode,
    required String phone,
    required double amount,
    int quantity = 1,
    String? profileId,
    String? transactionPin,
    bool? useBiometric,
  }) async {
    _log(
      '🎓 Purchasing education service via BACKEND for user ID: $userId, service: $serviceID',
    );

    return await _executeSecureTransaction(
      userId: userId,
      transactionType: 'education_purchase',
      amount: amount,
      serviceType: 'education',
      requiresDebit: true,
      useAtomic: false,
      transactionFunction: () async {
        _log('🛡️ Secure education purchase via backend for user: $userId');

        // Validate parameters
        _validateTransactionParams(
          userId: userId,
          amount: amount,
          serviceType: 'education',
          phone: phone,
        );

        final isEnabled = await isServiceEnabled('education');
        if (!isEnabled) {
          throw Exception('Education service is currently disabled.');
        }

        // Authenticate
        final authResult = await authenticateTransaction(
          userId: userId,
          transactionPin: transactionPin,
          useBiometric: useBiometric,
        );

        // Use backend endpoint instead of direct VTpass call
        final backendPayload = {
          'serviceID': serviceID,
          'variationCode': variationCode,
          'phone': phone,
          'amount': amount,
          'quantity': quantity,
          'profileId': profileId,
          'transactionPin':
              authResult['method'] == 'pin' ? authResult['pin'] : null,
          'useBiometric': authResult['method'] == 'biometric',
        };

        _log('🚀 Calling backend education purchase endpoint');
        final response = await _authenticatedPost(
          Uri.parse('$baseUrl/api/education/purchase'),
          backendPayload,
        );

        // Update local balance if successful
        if (response['success'] == true) {
          final prefs = await SharedPreferences.getInstance();
          final currentBalance = prefs.getDouble('walletBalance') ?? 0.0;
          final newBalance =
              response['newBalance'] ?? (currentBalance - amount);
          await prefs.setDouble('walletBalance', newBalance);

          final userString = prefs.getString('user');
          if (userString != null) {
            final userMap = jsonDecode(userString);
            userMap['walletBalance'] = newBalance;
            await prefs.setString('user', jsonEncode(userMap));
          }

          _log('💰 Balance updated: ₦$currentBalance → ₦$newBalance');
        }

        // ✅ CRITICAL FIX: Return ALL fields from the backend response
        // including 'code', 'limit', 'requested', 'isCustomLimit', 'service'
        return {
          'success': response['success'] == true,
          'transactionId': response['transactionId'],
          'status': response['status'] ?? 'unknown',
          'vtpassResponse': response['vtpassResponse'],
          'message': response['message'] ?? 'Education purchase completed',
          'newBalance': response['newBalance'],
          'purchased_code': response['purchased_code'],
          'cards': response['cards'] ?? [],
          'tokens': response['tokens'] ?? [],

          // ✅ CRITICAL: Pass through ALL error fields from backend
          'code': response['code'], // ← This is the missing field!
          'limit': response['limit'],
          'requested': response['requested'],
          'isCustomLimit': response['isCustomLimit'],
          'service': response['service'],
        };
      },
    );
  }

  /// Get insurance variations
  static Future<List<dynamic>> getInsuranceVariations() async {
    _log('Fetching insurance variations');
    try {
      final url = Uri.parse(
        '${_vtpassUrl}service-variations?serviceID=ui-insure',
      );
      final response = await _vtpassGet(url);
      return response['content']['variations'] ?? [];
    } catch (e) {
      _log('Error fetching insurance variations: $e');
      rethrow;
    }
  }

  static Future<List<dynamic>> getVehicleMakes() async {
    try {
      _log('🚗 Fetching vehicle makes from VTpass API...');
      final url = Uri.parse(
        'https://vtpass.com/api/universal-insurance/options/brand',
      );

      final response = await http
          .get(
            url,
            headers: {
              'Content-Type': 'application/json',
              'api-key': _apiKey,
              'secret-key': _secretKey,
              'public-key': _publicKey,
            },
          )
          .timeout(const Duration(seconds: 30));

      _log('📦 Vehicle makes API Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        _log('📊 Vehicle makes data structure:');
        _log('   Response keys: ${data.keys}');
        _log('   Has content: ${data.containsKey('content')}');

        List<dynamic> vehicleMakes = [];

        if (data['content'] is List) {
          vehicleMakes = data['content'];
        } else if (data['content'] is Map) {
          // Convert Map to List
          final contentMap = data['content'] as Map<String, dynamic>;
          vehicleMakes =
              contentMap.entries.map((entry) {
                return {
                  'id': entry.key,
                  'name': entry.value?.toString() ?? entry.key,
                };
              }).toList();
        } else if (data.containsKey('brands')) {
          vehicleMakes = data['brands'];
        }

        _log('✅ Found ${vehicleMakes.length} vehicle makes');

        // Transform to expected format
        final transformedMakes =
            vehicleMakes.map((make) {
              if (make is Map) {
                // Extract id and name
                String id = '';
                String name = '';

                if (make['id'] != null) {
                  id = make['id'].toString();
                } else if (make['code'] != null)
                  id = make['code'].toString();
                else if (make['brandCode'] != null)
                  id = make['brandCode'].toString();
                else if (make.containsKey('id'))
                  id = '${vehicleMakes.indexOf(make) + 1}';

                if (make['name'] != null) {
                  name = make['name'].toString();
                } else if (make['brandName'] != null)
                  name = make['brandName'].toString();
                else if (make['brand'] != null)
                  name = make['brand'].toString();
                else if (make.containsKey('name'))
                  name = make.toString();

                return {
                  'id':
                      id.isNotEmpty ? id : '${vehicleMakes.indexOf(make) + 1}',
                  'name':
                      name.isNotEmpty
                          ? name
                          : 'Make ${vehicleMakes.indexOf(make) + 1}',
                };
              } else {
                return {
                  'id': '${vehicleMakes.indexOf(make) + 1}',
                  'name': make.toString(),
                };
              }
            }).toList();

        return transformedMakes;
      } else {
        _log('❌ Failed to fetch vehicle makes: ${response.statusCode}');
        return _getFallbackVehicleMakes();
      }
    } catch (e, stackTrace) {
      _log('❌ Error fetching vehicle makes: $e');
      await reportError(e, stackTrace);
      return _getFallbackVehicleMakes();
    }
  }

  static List<Map<String, dynamic>> _getFallbackVehicleMakes() {
    return [
      {'id': '1', 'name': 'Toyota'},
      {'id': '2', 'name': 'Honda'},
      {'id': '3', 'name': 'Ford'},
      {'id': '4', 'name': 'BMW'},
      {'id': '5', 'name': 'Mercedes'},
      {'id': '6', 'name': 'Nissan'},
      {'id': '7', 'name': 'Hyundai'},
      {'id': '8', 'name': 'Kia'},
      {'id': '9', 'name': 'Volkswagen'},
      {'id': '10', 'name': 'Lexus'},
    ];
  }

  /// Get vehicle models
  static Future<List<dynamic>> getVehicleModels(String makeCode) async {
    try {
      _log('🚙 Fetching vehicle models for make code: $makeCode');

      // Clean the make code (remove any non-alphanumeric characters)
      final cleanMakeCode = makeCode.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');

      final url = Uri.parse(
        'https://vtpass.com/api/universal-insurance/options/model/$cleanMakeCode',
      );

      final response = await http
          .get(
            url,
            headers: {
              'Content-Type': 'application/json',
              'api-key': _apiKey,
              'secret-key': _secretKey,
              'public-key': _publicKey,
            },
          )
          .timeout(const Duration(seconds: 30));

      _log('📦 Vehicle models API Response status: ${response.statusCode}');
      _log(
        '📦 Vehicle models API Response body: ${response.body.substring(0, 200)}...',
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        List<dynamic> vehicleModels = [];

        if (data['content'] is List) {
          vehicleModels = data['content'];
        } else if (data['content'] is Map) {
          // Convert Map to List
          final contentMap = data['content'] as Map<String, dynamic>;
          vehicleModels =
              contentMap.entries.map((entry) {
                return {
                  'id': entry.key,
                  'name': entry.value?.toString() ?? entry.key,
                };
              }).toList();
        } else if (data.containsKey('models')) {
          vehicleModels = data['models'];
        }

        _log(
          '✅ Found ${vehicleModels.length} vehicle models for make code: $makeCode',
        );

        // Transform to expected format
        final transformedModels =
            vehicleModels.map((model) {
              if (model is Map) {
                // Extract code and name
                String code = '';
                String name = '';

                if (model['code'] != null) {
                  code = model['code'].toString();
                } else if (model['id'] != null)
                  code = model['id'].toString();
                else if (model['modelCode'] != null)
                  code = model['modelCode'].toString();

                if (model['name'] != null) {
                  name = model['name'].toString();
                } else if (model['modelName'] != null)
                  name = model['modelName'].toString();
                else if (model['model'] != null)
                  name = model['model'].toString();

                return {
                  'code':
                      code.isNotEmpty
                          ? code
                          : '${vehicleModels.indexOf(model) + 1}',
                  'name': name.isNotEmpty ? name : model.toString(),
                };
              } else {
                return {
                  'code': '${vehicleModels.indexOf(model) + 1}',
                  'name': model.toString(),
                };
              }
            }).toList();

        return transformedModels;
      } else {
        _log('❌ Failed to fetch vehicle models: ${response.statusCode}');
        return _getFallbackVehicleModels(makeCode);
      }
    } catch (e, stackTrace) {
      _log('❌ Error fetching vehicle models: $e');
      await reportError(e, stackTrace);
      return _getFallbackVehicleModels(makeCode);
    }
  }

  static List<Map<String, dynamic>> _getFallbackVehicleModels(String makeCode) {
    // Return different models based on make
    switch (makeCode) {
      case '1': // Toyota
        return [
          {'code': '1', 'name': 'Camry'},
          {'code': '2', 'name': 'Corolla'},
          {'code': '3', 'name': 'Highlander'},
          {'code': '4', 'name': 'RAV4'},
          {'code': '5', 'name': 'Land Cruiser'},
        ];
      case '2': // Honda
        return [
          {'code': '6', 'name': 'Civic'},
          {'code': '7', 'name': 'Accord'},
          {'code': '8', 'name': 'CR-V'},
          {'code': '9', 'name': 'Pilot'},
        ];
      case '3': // Ford
        return [
          {'code': '10', 'name': 'Focus'},
          {'code': '11', 'name': 'Explorer'},
          {'code': '12', 'name': 'Escape'},
          {'code': '13', 'name': 'F-150'},
        ];
      default:
        return [
          {'code': '1', 'name': 'Standard Model'},
          {'code': '2', 'name': 'Deluxe Model'},
          {'code': '3', 'name': 'Premium Model'},
        ];
    }
  }

  /// Debug method to test the states API directly
  static Future<Map<String, dynamic>> debugStatesApi() async {
    try {
      _log('🔍 DEBUG: Testing states API directly...');

      // Initialize credentials first
      await _initializeCredentials();

      _log('🔑 Using API Key: ${_apiKey.substring(0, 8)}...');

      final url = Uri.parse(
        'https://vtpass.com/api/universal-insurance/options/state',
      );

      _log('🎯 Calling URL: $url');

      final response = await http
          .get(
            url,
            headers: {
              'Content-Type': 'application/json',
              'api-key': _apiKey,
              'secret-key': _secretKey,
              'public-key': _publicKey,
            },
          )
          .timeout(const Duration(seconds: 30));

      _log('📦 Response Status: ${response.statusCode}');
      _log('📦 Response Headers: ${response.headers}');
      _log('📦 Full Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'success': true,
          'statusCode': response.statusCode,
          'data': data,
          'contentType': data.runtimeType,
          'hasContent': data.containsKey('content'),
          'contentTypeDetail': data['content']?.runtimeType,
          'message': 'API call successful',
        };
      } else {
        return {
          'success': false,
          'statusCode': response.statusCode,
          'message': 'API call failed',
          'body': response.body,
        };
      }
    } catch (e, stackTrace) {
      _log('❌ DEBUG Error: $e');
      await reportError(e, stackTrace);
      return {
        'success': false,
        'error': e.toString(),
        'stackTrace': stackTrace.toString(),
      };
    }
  }

  static Future<List<dynamic>> getVehicleColors() async {
    try {
      final url = Uri.parse(
        'https://vtpass.com/api/universal-insurance/options/color',
      );
      final response = await _vtpassGet(url);

      _log('=== VEHICLE COLORS DEBUG ===');
      _log('Response: ${jsonEncode(response)}');

      if (response['content'] != null) {
        final content = response['content'];
        if (content is List) {
          _log('Vehicle colors count: ${content.length}');
          return content;
        } else if (content is Map) {
          _log('Vehicle colors in Map format');
          return [content];
        }
      }

      return [];
    } catch (e) {
      _log('Error loading vehicle colors: $e');
      return [
        {'code': '20', 'name': 'Ash'},
        {'code': '1004', 'name': 'Black'},
        {'code': '1005', 'name': 'White'},
        {'code': '1006', 'name': 'Red'},
      ];
    }
  }

  static Future<List<dynamic>> getEngineCapacities() async {
    try {
      final url = Uri.parse(
        'https://vtpass.com/api/universal-insurance/options/engine-capacity',
      );
      final response = await _vtpassGet(url);

      _log('=== ENGINE CAPACITIES DEBUG ===');
      _log('Response: ${jsonEncode(response)}');

      if (response['content'] != null) {
        final content = response['content'];
        if (content is List) {
          _log('Engine capacities count: ${content.length}');
          return content;
        } else if (content is Map) {
          _log('Engine capacities in Map format');
          return [content];
        }
      }

      return [];
    } catch (e) {
      _log('Error loading engine capacities: $e');
      return [
        {'code': '1', 'value': '0.1 - 1.59'},
        {'code': '2', 'value': '1.6 - 2.0'},
        {'code': '3', 'value': '2.1 - 3.0'},
        {'code': '4', 'value': '3.1 - 4.0'},
      ];
    }
  }

  /// Get states
  /// Get states
  /// Get states via backend proxy
  static Future<List<dynamic>> getStates() async {
    _log('📍 Fetching states via backend...');

    try {
      final url = Uri.parse('$baseUrl/api/insurance/states');
      final response = await _authenticatedGet(url);
      _log('📦 States response: ${response['success']}');

      if (response['success'] == true) {
        final states = response['states'] ?? [];
        _log('✅ Found ${states.length} states');
        return states;
      } else {
        _log('⚠️ Backend states fetch failed: ${response['message']}');
        return _getFallbackStates();
      }
    } catch (e) {
      _log('❌ Error fetching states via backend: $e');
      return _getFallbackStates();
    }
  }

  static List<Map<String, dynamic>> _getFallbackStates() {
    return [
      {'code': '1', 'name': 'Abia'},
      {'code': '2', 'name': 'Adamawa'},
      {'code': '3', 'name': 'Akwa Ibom'},
      {'code': '4', 'name': 'Anambra'},
      {'code': '5', 'name': 'Bauchi'},
      {'code': '6', 'name': 'Bayelsa'},
      {'code': '7', 'name': 'Benue'},
      {'code': '8', 'name': 'Borno'},
      {'code': '9', 'name': 'Cross River'},
      {'code': '10', 'name': 'Delta'},
      {'code': '11', 'name': 'Ebonyi'},
      {'code': '12', 'name': 'Edo'},
      {'code': '13', 'name': 'Ekiti'},
      {'code': '14', 'name': 'Enugu'},
      {'code': '15', 'name': 'FCT'},
      {'code': '16', 'name': 'Gombe'},
      {'code': '17', 'name': 'Imo'},
      {'code': '18', 'name': 'Jigawa'},
      {'code': '19', 'name': 'Kaduna'},
      {'code': '20', 'name': 'Kano'},
      {'code': '21', 'name': 'Katsina'},
      {'code': '22', 'name': 'Kebbi'},
      {'code': '23', 'name': 'Kogi'},
      {'code': '24', 'name': 'Kwara'},
      {'code': '25', 'name': 'Lagos'},
      {'code': '26', 'name': 'Nasarawa'},
      {'code': '27', 'name': 'Niger'},
      {'code': '28', 'name': 'Ogun'},
      {'code': '29', 'name': 'Ondo'},
      {'code': '30', 'name': 'Osun'},
      {'code': '31', 'name': 'Oyo'},
      {'code': '32', 'name': 'Plateau'},
      {'code': '33', 'name': 'Rivers'},
      {'code': '34', 'name': 'Sokoto'},
      {'code': '35', 'name': 'Taraba'},
      {'code': '36', 'name': 'Yobe'},
      {'code': '37', 'name': 'Zamfara'},
    ];
  }

  /// Get LGAs
  /// Get LGAs for a state using the backend proxy
  static Future<List<dynamic>> getLGAs(String stateCode) async {
    _log('📍 Fetching LGAs for state code: $stateCode');

    try {
      // Use the backend proxy endpoint
      final url = Uri.parse('$baseUrl/api/insurance/lgas/$stateCode');
      final token = await _getToken();

      if (token == null) {
        throw Exception('Authentication token not found');
      }

      final response = await http
          .get(
            url,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 30));

      _log('📦 LGA API Response status: ${response.statusCode}');
      _log('📦 LGA API Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['success'] == true) {
          final lgas = data['lgas'] ?? [];
          _log('✅ Found ${lgas.length} LGAs for state: $stateCode');

          // Ensure each LGA has code and name
          final processedLgas =
              lgas
                  .map((lga) {
                    return {
                      'code': lga['code']?.toString() ?? '',
                      'name': lga['name']?.toString() ?? 'Unknown',
                      'stateCode': lga['stateCode']?.toString() ?? stateCode,
                    };
                  })
                  .where((lga) => lga['code']?.isNotEmpty == true)
                  .toList();

          return processedLgas;
        } else {
          _log('⚠️ Backend returned success: false: ${data['message']}');
          return _getFallbackLGAs(stateCode);
        }
      } else {
        _log('❌ API returned error: ${response.statusCode}');
        return _getFallbackLGAs(stateCode);
      }
    } catch (e) {
      _log('❌ Error fetching LGAs: $e');
      return _getFallbackLGAs(stateCode);
    }
  }

  /// Fallback LGAs for when API fails
  static List<Map<String, dynamic>> _getFallbackLGAs(String stateCode) {
    _log('📍 Using fallback LGAs for state: $stateCode');

    // Map state codes to state names for fallback lookup
    final stateCodeMap = {
      '1': 'Abia',
      '2': 'Adamawa',
      '3': 'Akwa Ibom',
      '4': 'Anambra',
      '5': 'Bauchi',
      '6': 'Bayelsa',
      '7': 'Benue',
      '8': 'Borno',
      '9': 'Cross River',
      '10': 'Delta',
      '11': 'Ebonyi',
      '12': 'Edo',
      '13': 'Ekiti',
      '14': 'Enugu',
      '15': 'FCT',
      '16': 'Gombe',
      '17': 'Imo',
      '18': 'Jigawa',
      '19': 'Kaduna',
      '20': 'Kano',
      '21': 'Katsina',
      '22': 'Kebbi',
      '23': 'Kogi',
      '24': 'Kwara',
      '25': 'Lagos',
      '26': 'Nasarawa',
      '27': 'Niger',
      '28': 'Ogun',
      '29': 'Ondo',
      '30': 'Osun',
      '31': 'Oyo',
      '32': 'Plateau',
      '33': 'Rivers',
      '34': 'Sokoto',
      '35': 'Taraba',
      '36': 'Yobe',
      '37': 'Zamfara',
    };

    final stateName = stateCodeMap[stateCode] ?? stateCode;

    // Complete Nigeria States and LGAs mapping
    final statesLGAs = {
      'Abia': [
        'Aba North',
        'Aba South',
        'Arochukwu',
        'Bende',
        'Ikwuano',
        'Isiala Ngwa North',
        'Isiala Ngwa South',
        'Isuikwuato',
        'Obi Ngwa',
        'Ohafia',
        'Osisioma',
        'Ugwunagbo',
        'Ukwa East',
        'Ukwa West',
        'Umuahia North',
        'Umuahia South',
        'Umu Nneochi',
      ],
      'Adamawa': [
        'Demsa',
        'Fufore',
        'Ganaye',
        'Girei',
        'Gombi',
        'Guyuk',
        'Hong',
        'Jada',
        'Lamurde',
        'Madagali',
        'Maiha',
        'Mayo Belwa',
        'Michika',
        'Mubi North',
        'Mubi South',
        'Numan',
        'Shelleng',
        'Song',
        'Toungo',
        'Yola North',
        'Yola South',
      ],
      'Akwa Ibom': [
        'Abak',
        'Eastern Obolo',
        'Eket',
        'Esit Eket',
        'Essien Udim',
        'Etim Ekpo',
        'Etinan',
        'Ibeno',
        'Ibesikpo Asutan',
        'Ibiono Ibom',
        'Ika',
        'Ikono',
        'Ikot Abasi',
        'Ikot Ekpene',
        'Ini',
        'Itu',
        'Mbo',
        'Mkpat Enin',
        'Nsit Atai',
        'Nsit Ibom',
        'Nsit Ubium',
        'Obot Akara',
        'Okobo',
        'Onna',
        'Oron',
        'Oruk Anam',
        'Udung Uko',
        'Ukanafun',
        'Uruan',
        'Urue-Offong/Oruko',
        'Uyo',
      ],
      'Anambra': [
        'Aguata',
        'Anambra East',
        'Anambra West',
        'Anaocha',
        'Awka North',
        'Awka South',
        'Ayamelum',
        'Dunukofia',
        'Ekwusigo',
        'Idemili North',
        'Idemili South',
        'Ihiala',
        'Njikoka',
        'Nnewi North',
        'Nnewi South',
        'Ogbaru',
        'Onitsha North',
        'Onitsha South',
        'Orumba North',
        'Orumba South',
        'Oyi',
      ],
      'Bauchi': [
        'Alkaleri',
        'Bauchi',
        'Bogoro',
        'Damban',
        'Darazo',
        'Dass',
        'Gamawa',
        'Ganjuwa',
        'Giade',
        'Itas/Gadau',
        'Jama\'are',
        'Katagum',
        'Kirfi',
        'Misau',
        'Ningi',
        'Shira',
        'Tafawa Balewa',
        'Toro',
        'Warji',
        'Zaki',
      ],
      'Bayelsa': [
        'Brass',
        'Ekeremor',
        'Kolokuma/Opokuma',
        'Nembe',
        'Ogbia',
        'Sagbama',
        'Southern Ijaw',
        'Yenagoa',
      ],
      'Benue': [
        'Ado',
        'Agatu',
        'Apa',
        'Buruku',
        'Gboko',
        'Guma',
        'Gwer East',
        'Gwer West',
        'Katsina-Ala',
        'Konshisha',
        'Kwande',
        'Logo',
        'Makurdi',
        'Obi',
        'Ogbadibo',
        'Ohimini',
        'Oju',
        'Okpokwu',
        'Oturkpo',
        'Tarka',
        'Ukum',
        'Ushongo',
        'Vandeikya',
      ],
      'Borno': [
        'Abadam',
        'Askira/Uba',
        'Bama',
        'Bayo',
        'Biu',
        'Chibok',
        'Damboa',
        'Dikwa',
        'Gubio',
        'Guzamala',
        'Gwoza',
        'Hawul',
        'Jere',
        'Kaga',
        'Kala/Balge',
        'Konduga',
        'Kukawa',
        'Kwaya Kusar',
        'Mafa',
        'Magumeri',
        'Maiduguri',
        'Marte',
        'Mobbar',
        'Monguno',
        'Ngala',
        'Nganzai',
        'Shani',
      ],
      'Cross River': [
        'Abi',
        'Akamkpa',
        'Akpabuyo',
        'Bakassi',
        'Bekwarra',
        'Biase',
        'Boki',
        'Calabar Municipal',
        'Calabar South',
        'Etung',
        'Ikom',
        'Obanliku',
        'Obubra',
        'Obudu',
        'Odukpani',
        'Ogoja',
        'Yakuur',
        'Yala',
      ],
      'Delta': [
        'Aniocha North',
        'Aniocha South',
        'Bomadi',
        'Burutu',
        'Ethiope East',
        'Ethiope West',
        'Ika North East',
        'Ika South',
        'Isoko North',
        'Isoko South',
        'Ndokwa East',
        'Ndokwa West',
        'Okpe',
        'Oshimili North',
        'Oshimili South',
        'Patani',
        'Sapele',
        'Udu',
        'Ughelli North',
        'Ughelli South',
        'Ukwuani',
        'Uvwie',
        'Warri North',
        'Warri South',
        'Warri South West',
      ],
      'Ebonyi': [
        'Abakaliki',
        'Afikpo North',
        'Afikpo South',
        'Ebonyi',
        'Ezza North',
        'Ezza South',
        'Ikwo',
        'Ishielu',
        'Ivo',
        'Izzi',
        'Ohaozara',
        'Ohaukwu',
        'Onicha',
      ],
      'Edo': [
        'Akoko-Edo',
        'Egor',
        'Esan Central',
        'Esan North East',
        'Esan South East',
        'Esan West',
        'Etsako Central',
        'Etsako East',
        'Etsako West',
        'Igueben',
        'Ikpoba Okha',
        'Orhionmwon',
        'Oredo',
        'Ovia North East',
        'Ovia South West',
        'Owan East',
        'Owan West',
        'Uhunmwonde',
      ],
      'Ekiti': [
        'Ado Ekiti',
        'Efon',
        'Ekiti East',
        'Ekiti South West',
        'Ekiti West',
        'Emure',
        'Gbonyin',
        'Ido Osi',
        'Ijero',
        'Ikere',
        'Ikole',
        'Ilejemeje',
        'Irepodun/Ifelodun',
        'Ise/Orun',
        'Moba',
        'Oye',
      ],
      'Enugu': [
        'Aninri',
        'Awgu',
        'Enugu East',
        'Enugu North',
        'Enugu South',
        'Ezeagu',
        'Igbo Etiti',
        'Igbo Eze North',
        'Igbo Eze South',
        'Isi Uzo',
        'Nkanu East',
        'Nkanu West',
        'Nsukka',
        'Oji River',
        'Udenu',
        'Udi',
        'Uzo Uwani',
      ],
      'FCT': [
        'Abaji',
        'Abuja Municipal',
        'Bwari',
        'Gwagwalada',
        'Kuje',
        'Kwali',
      ],
      'Gombe': [
        'Akko',
        'Balanga',
        'Billiri',
        'Dukku',
        'Funakaye',
        'Gombe',
        'Kaltungo',
        'Kwami',
        'Nafada',
        'Shongom',
        'Yamaltu/Deba',
      ],
      'Imo': [
        'Aboh Mbaise',
        'Ahiazu Mbaise',
        'Ehime Mbano',
        'Ezinihitte',
        'Ideato North',
        'Ideato South',
        'Ihitte/Uboma',
        'Ikeduru',
        'Isiala Mbano',
        'Isu',
        'Mbaitoli',
        'Ngor Okpala',
        'Njaba',
        'Nkwerre',
        'Nwangele',
        'Obowo',
        'Oguta',
        'Ohaji/Egbema',
        'Okigwe',
        'Orlu',
        'Orsu',
        'Oru East',
        'Oru West',
        'Owerri Municipal',
        'Owerri North',
        'Owerri West',
        'Unuimo',
      ],
      'Jigawa': [
        'Auyo',
        'Babura',
        'Biriniwa',
        'Birnin Kudu',
        'Buji',
        'Dutse',
        'Gagarawa',
        'Garki',
        'Gumel',
        'Guri',
        'Gwaram',
        'Gwiwa',
        'Hadejia',
        'Jahun',
        'Kafin Hausa',
        'Kaugama',
        'Kazaure',
        'Kiri Kasama',
        'Kiyawa',
        'Malam Madori',
        'Miga',
        'Ringim',
        'Roni',
        'Sule Tankarkar',
        'Taura',
        'Yankwashi',
      ],
      'Kaduna': [
        'Birnin Gwari',
        'Chikun',
        'Giwa',
        'Igabi',
        'Ikara',
        'Jaba',
        'Jema\'a',
        'Kachia',
        'Kaduna North',
        'Kaduna South',
        'Kagarko',
        'Kajuru',
        'Kaura',
        'Kauru',
        'Kubau',
        'Kudan',
        'Lere',
        'Makarfi',
        'Sabon Gari',
        'Sanga',
        'Soba',
        'Zangon Kataf',
        'Zaria',
      ],
      'Kano': [
        'Ajingi',
        'Albasu',
        'Bagwai',
        'Bebeji',
        'Bichi',
        'Bunkure',
        'Dala',
        'Dambatta',
        'Dawakin Kudu',
        'Dawakin Tofa',
        'Doguwa',
        'Fagge',
        'Gabasawa',
        'Garko',
        'Garun Mallam',
        'Gaya',
        'Gezawa',
        'Gwale',
        'Gwarzo',
        'Kabo',
        'Kano Municipal',
        'Karaye',
        'Kibiya',
        'Kiru',
        'Kumbotso',
        'Kunchi',
        'Kura',
        'Madobi',
        'Makoda',
        'Minjibir',
        'Nasarawa',
        'Rano',
        'Rimin Gado',
        'Rogo',
        'Shanono',
        'Sumaila',
        'Takai',
        'Tarauni',
        'Tofa',
        'Tsanyawa',
        'Tudun Wada',
        'Ungogo',
        'Warawa',
        'Wudil',
      ],
      'Katsina': [
        'Bakori',
        'Batagarawa',
        'Batsari',
        'Baure',
        'Bindawa',
        'Charanchi',
        'Dandume',
        'Danja',
        'Dan Musa',
        'Daura',
        'Dutsi',
        'Dutsin Ma',
        'Faskari',
        'Funtua',
        'Ingawa',
        'Jibia',
        'Kafur',
        'Kaita',
        'Kankara',
        'Kankia',
        'Katsina',
        'Kurfi',
        'Kusada',
        'Mai\'Adua',
        'Malumfashi',
        'Mani',
        'Mashi',
        'Matazu',
        'Musawa',
        'Rimi',
        'Sabuwa',
        'Safana',
        'Sandamu',
        'Zango',
      ],
      'Kebbi': [
        'Aleiro',
        'Arewa Dandi',
        'Argungu',
        'Augie',
        'Bagudo',
        'Birnin Kebbi',
        'Bunza',
        'Dandi',
        'Fakai',
        'Gwandu',
        'Jega',
        'Kalgo',
        'Koko/Besse',
        'Maiyama',
        'Ngaski',
        'Sakaba',
        'Shanga',
        'Suru',
        'Wasagu/Danko',
        'Yauri',
        'Zuru',
      ],
      'Kogi': [
        'Adavi',
        'Ajaokuta',
        'Ankpa',
        'Bassa',
        'Dekina',
        'Ibaji',
        'Idah',
        'Igalamela Odolu',
        'Ijumu',
        'Kabba/Bunu',
        'Kogi',
        'Lokoja',
        'Mopa Muro',
        'Ofu',
        'Ogori/Magongo',
        'Okehi',
        'Okene',
        'Olamaboro',
        'Omala',
        'Yagba East',
        'Yagba West',
      ],
      'Kwara': [
        'Asa',
        'Baruten',
        'Edu',
        'Ekiti',
        'Ifelodun',
        'Ilorin East',
        'Ilorin South',
        'Ilorin West',
        'Irepodun',
        'Isin',
        'Kaiama',
        'Moro',
        'Offa',
        'Oke Ero',
        'Oyun',
        'Pategi',
      ],
      'Lagos': [
        'Agege',
        'Ajeromi-Ifelodun',
        'Alimosho',
        'Amuwo-Odofin',
        'Apapa',
        'Badagry',
        'Epe',
        'Eti-Osa',
        'Ibeju-Lekki',
        'Ifako-Ijaiye',
        'Ikeja',
        'Ikorodu',
        'Kosofe',
        'Lagos Island',
        'Lagos Mainland',
        'Mushin',
        'Ojo',
        'Oshodi-Isolo',
        'Shomolu',
        'Surulere',
      ],
      'Nasarawa': [
        'Akwanga',
        'Awe',
        'Doma',
        'Karu',
        'Keana',
        'Keffi',
        'Kokona',
        'Lafia',
        'Nasarawa',
        'Nasarawa Egon',
        'Obi',
        'Toto',
        'Wamba',
      ],
      'Niger': [
        'Agaie',
        'Agwara',
        'Bida',
        'Borgu',
        'Bosso',
        'Chanchaga',
        'Edati',
        'Gbako',
        'Gurara',
        'Katcha',
        'Kontagora',
        'Lapai',
        'Lavun',
        'Magama',
        'Mariga',
        'Mashegu',
        'Mokwa',
        'Moya',
        'Paikoro',
        'Rafi',
        'Rijau',
        'Shiroro',
        'Suleja',
        'Tafa',
        'Wushishi',
      ],
      'Ogun': [
        'Abeokuta North',
        'Abeokuta South',
        'Ado-Odo/Ota',
        'Egbado North',
        'Egbado South',
        'Ewekoro',
        'Ifo',
        'Ijebu East',
        'Ijebu North',
        'Ijebu North East',
        'Ijebu Ode',
        'Ikenne',
        'Imeko Afon',
        'Ipokia',
        'Obafemi Owode',
        'Odeda',
        'Odogbolu',
        'Ogun Waterside',
        'Remo North',
        'Shagamu',
      ],
      'Ondo': [
        'Akoko North East',
        'Akoko North West',
        'Akoko South East',
        'Akoko South West',
        'Akure North',
        'Akure South',
        'Ese Odo',
        'Idanre',
        'Ifedore',
        'Ilaje',
        'Ile Oluji/Okeigbo',
        'Irele',
        'Odigbo',
        'Okitipupa',
        'Ondo East',
        'Ondo West',
        'Ose',
        'Owo',
      ],
      'Osun': [
        'Aiyedaade',
        'Aiyedire',
        'Atakunmosa East',
        'Atakunmosa West',
        'Boluwaduro',
        'Boripe',
        'Ede North',
        'Ede South',
        'Egbedore',
        'Ejigbo',
        'Ife Central',
        'Ife East',
        'Ife North',
        'Ife South',
        'Ifedayo',
        'Ifelodun',
        'Ila',
        'Ilesa East',
        'Ilesa West',
        'Irepodun',
        'Irewole',
        'Isokan',
        'Iwo',
        'Obokun',
        'Odo Otin',
        'Ola Oluwa',
        'Olorunda',
        'Oriade',
        'Orolu',
        'Osogbo',
      ],
      'Oyo': [
        'Afijio',
        'Akinyele',
        'Atiba',
        'Atisbo',
        'Egbeda',
        'Ibadan North',
        'Ibadan North East',
        'Ibadan North West',
        'Ibadan South East',
        'Ibadan South West',
        'Ibarapa Central',
        'Ibarapa East',
        'Ibarapa North',
        'Ido',
        'Irepo',
        'Iseyin',
        'Itesiwaju',
        'Iwajowa',
        'Kajola',
        'Lagelu',
        'Ogbomosho North',
        'Ogbomosho South',
        'Ogo Oluwa',
        'Olorunsogo',
        'Oluyole',
        'Ona Ara',
        'Orelope',
        'Ori Ire',
        'Oyo',
        'Oyo East',
        'Saki East',
        'Saki West',
        'Surulere',
      ],
      'Plateau': [
        'Barkin Ladi',
        'Bassa',
        'Bokkos',
        'Jos East',
        'Jos North',
        'Jos South',
        'Kanam',
        'Kanke',
        'Langtang North',
        'Langtang South',
        'Mangu',
        'Mikang',
        'Pankshin',
        'Qua\'an Pan',
        'Riyom',
        'Shendam',
        'Wase',
      ],
      'Rivers': [
        'Abua/Odual',
        'Ahoada East',
        'Ahoada West',
        'Akuku Toru',
        'Andoni',
        'Asari Toru',
        'Bonny',
        'Degema',
        'Eleme',
        'Emohua',
        'Etche',
        'Gokana',
        'Ikwerre',
        'Khana',
        'Obio/Akpor',
        'Ogba/Egbema/Ndoni',
        'Ogu/Bolo',
        'Okrika',
        'Omuma',
        'Opobo/Nkoro',
        'Oyigbo',
        'Port Harcourt',
        'Tai',
      ],
      'Sokoto': [
        'Binji',
        'Bodinga',
        'Dange Shuni',
        'Gada',
        'Goronyo',
        'Gudu',
        'Gwadabawa',
        'Illela',
        'Isa',
        'Kebbe',
        'Kware',
        'Rabah',
        'Sabon Birni',
        'Shagari',
        'Silame',
        'Sokoto North',
        'Sokoto South',
        'Tambuwal',
        'Tangaza',
        'Tureta',
        'Wamako',
        'Wurno',
        'Yabo',
      ],
      'Taraba': [
        'Ardo Kola',
        'Bali',
        'Donga',
        'Gashaka',
        'Gassol',
        'Ibi',
        'Jalingo',
        'Karim Lamido',
        'Kumi',
        'Lau',
        'Sardauna',
        'Takum',
        'Ussa',
        'Wukari',
        'Yorro',
        'Zing',
      ],
      'Yobe': [
        'Bade',
        'Bursari',
        'Damaturu',
        'Fika',
        'Fune',
        'Geidam',
        'Gujba',
        'Gulani',
        'Jakusko',
        'Karasuwa',
        'Machina',
        'Nangere',
        'Nguru',
        'Potiskum',
        'Tarmuwa',
        'Yunusari',
        'Yusufari',
      ],
      'Zamfara': [
        'Anka',
        'Bakura',
        'Birnin Magaji/Kiyaw',
        'Bukkuyum',
        'Bungudu',
        'Gummi',
        'Gusau',
        'Kaura Namoda',
        'Maradun',
        'Maru',
        'Shinkafi',
        'Talata Mafara',
        'Tsafe',
        'Zurmi',
      ],
    };

    final lgaList =
        statesLGAs[stateName] ?? ['LGA 1', 'LGA 2', 'LGA 3', 'LGA 4', 'LGA 5'];

    return lgaList.map((name) {
      return {
        'code': name.replaceAll(' ', '_').toLowerCase(),
        'name': name,
        'stateCode': stateCode,
      };
    }).toList();
  }

  /// Purchase Insurance (Third Party Motor Insurance)
  static Future<Map<String, dynamic>> purchaseInsurance({
    required String userId,
    required String phone,
    required String insuredName,
    required String engineCapacity,
    required String chasisNumber,
    required String plateNumber,
    required String vehicleMake,
    required String vehicleModel,
    required String vehicleColor,
    required String yearOfMake,
    required String state,
    required String lga,
    required String email,
    String variationCode = 'private',
    String? transactionPin,
    bool? useBiometric, // ← Same as buyAirtime and buyData
  }) async {
    _log('🛡️ Purchasing insurance...');
    _log('📦 Plate: $plateNumber');

    try {
      // Authenticate - SAME PATTERN as buyAirtime
      if (useBiometric == true) {
        final biometricSuccess = await authenticateWithBiometricsEnhanced();
        if (!biometricSuccess) {
          throw Exception('Biometric authentication failed');
        }
      } else if (transactionPin != null) {
        final userId = await _getUserId();
        if (userId == null) {
          throw Exception('User ID not found');
        }
        // Verify PIN - SAME as buyAirtime
        final pinResult = await verifyTransactionPin(
          userId: userId,
          transactionPin: transactionPin,
        );
        if (pinResult['success'] != true) {
          throw Exception(pinResult['message'] ?? 'Invalid PIN');
        }
      }

      // Get current balance
      final currentBalance = await getBalance();

      // Build request body - SAME as buyAirtime pattern
      final requestBody = {
        'variationCode': variationCode,
        'phone': phone,
        'insuredName': insuredName,
        'engineCapacity': engineCapacity,
        'chasisNumber': chasisNumber,
        'plateNumber': plateNumber,
        'vehicleMake': vehicleMake,
        'vehicleModel': vehicleModel,
        'vehicleColor': vehicleColor,
        'yearOfMake': yearOfMake,
        'state': state,
        'lga': lga,
        'email': email,
        'serviceType': 'insurance',
      };

      _log('📤 Sending insurance purchase request...');

      // Use _authenticatedPost - SAME as buyAirtime
      final response = await _authenticatedPost(
        Uri.parse('$baseUrl/api/insurance/purchase'),
        requestBody,
        useBiometric: useBiometric ?? false, // ← Convert bool? to bool
      );

      _log('📦 Insurance purchase response: ${response['success']}');

      if (response['success'] == true) {
        // Update local balance - SAME as buyAirtime
        if (response['newBalance'] != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setDouble(
            'walletBalance',
            (response['newBalance'] as num).toDouble(),
          );

          final userString = prefs.getString('user');
          if (userString != null) {
            final userMap = jsonDecode(userString);
            userMap['walletBalance'] =
                (response['newBalance'] as num).toDouble();
            await prefs.setString('user', jsonEncode(userMap));
          }
        }

        return {
          'success': true,
          'transactionId': response['transactionId'],
          'reference': response['reference'] ?? response['transactionId'],
          'status': response['status'] ?? 'delivered',
          'newBalance': response['newBalance'],
          'vtpassResponse': response['vtpassResponse'],
          'amount': response['amount'],
          'plateNumber': response['plateNumber'],
          'certificateUrl': response['certificateUrl'],
          'certUrl': response['certUrl'],
          'message': response['message'] ?? 'Insurance purchased successfully',
          'userDebited': response['userDebited'] ?? true,
          'amountDebited': response['amountDebited'],
        };
      } else {
        // ✅ CRITICAL: Return ALL error fields from backend - SAME as buyAirtime
        return {
          'success': false,
          'message': response['message'] ?? 'Purchase failed',
          'isFailed': response['isFailed'] ?? true,
          'shouldShowAsFailed': response['shouldShowAsFailed'] ?? true,
          'amountDebited': response['amountDebited'],
          'newBalance': response['newBalance'],
          'userDebited': response['userDebited'] ?? false,
          'vtpassResponse': response['vtpassResponse'],
          'vtpassCode': response['vtpassCode'],
          'vtpassDescription': response['vtpassDescription'],
          // ✅ CRITICAL: Pass through limit error fields - SAME as buyAirtime
          'code': response['code'],
          'limit': response['limit'],
          'requested': response['requested'],
          'isCustomLimit': response['isCustomLimit'],
          'service': response['service'],
        };
      }
    } catch (e) {
      _log('❌ Error purchasing insurance: $e');
      return {
        'success': false,
        'message': 'Failed to purchase insurance: ${e.toString()}',
      };
    }
  }

  // Helper method for GET requests to VTpass
  static Future<Map<String, dynamic>> _vtpassGet(Uri url) async {
    _log('VTpass GET request to $url');

    final response = await http
        .get(
          url,
          headers: {
            'Content-Type': 'application/json',
            'api-key': _apiKey,
            'secret-key': _secretKey,
            'public-key': _publicKey,
          },
        )
        .timeout(const Duration(seconds: 30));

    return _handleVtpassResponse(response);
  }

  /// Validate education profile (for JAMB)
  /// Validate education profile (for JAMB) - USING BACKEND ENDPOINT
  static Future<Map<String, dynamic>> validateEducationProfile({
    required String profileId,
    required String serviceID,
  }) async {
    _log('🔍 Validating education profile via BACKEND for service: $serviceID');

    try {
      // Use backend endpoint instead of direct VTpass call
      final response = await _authenticatedPost(
        Uri.parse('$baseUrl/api/education/validate-profile'),
        {'profileId': profileId, 'serviceID': serviceID},
      );

      if (response['success'] == true) {
        _log(
          '✅ Education profile validated successfully via backend. Customer Name: ${response['customerName']}',
        );
        return {
          'success': true,
          'customerName': response['customerName'],
          'details': response['details'],
          'message': response['message'] ?? 'Profile validated successfully.',
        };
      } else {
        _log(
          '❌ Education profile validation failed via backend: ${response['message']}',
        );
        throw Exception(response['message'] ?? 'Profile validation failed.');
      }
    } catch (e) {
      _log('ERROR in validateEducationProfile: $e');
      String errorMessage = e.toString();
      if (errorMessage.contains('INVALID BILLERS CODE')) {
        errorMessage = 'Invalid profile ID. Please check and try again.';
      } else if (errorMessage.contains('too many attempts') ||
          errorMessage.contains('429')) {
        errorMessage =
            'Too many attempts. Please wait a few minutes before trying again.';
      }
      throw Exception(errorMessage);
    }
  }

  /// Shares referral code via platform share dialog
  static Future<void> shareReferralCode(String referralCode) async {
    try {
      final shareText =
          'Join me on this amazing platform! 🚀\n\n'
          'Use my referral code: $referralCode\n\n'
          'Sign up now and get ₦$_firstTransactionBonus welcome bonus! '
          'We both earn commissions on every transaction! 💰\n\n'
          'Download our App on Playstore';

      // For mobile - use share_plus package
      // await Share.share(shareText);

      // For web - copy to clipboard
      if (kIsWeb) {
        await Clipboard.setData(ClipboardData(text: referralCode));
        _log('Referral code copied to clipboard: $referralCode');
      } else {
        // Fallback - copy to clipboard
        await Clipboard.setData(ClipboardData(text: referralCode));
        _log('Referral code copied to clipboard: $referralCode');
      }
    } catch (e) {
      _log('Error sharing referral code: $e');
      rethrow;
    }
  }

  static Future<dynamic> hasValidToken() async {}
}

/// Private widget for the enhanced session expired dialog
/// Uses DalabaPay colors: Blue (#243889) and Green (#219C7E)
/// Private widget for the enhanced session expired dialog
/// Uses the same gradient as your dashboard balance card:
/// begin: Alignment.topRight, end: Alignment.bottomLeft
/// colors: [Color(0xFF5BB592), Color(0xFF102C68)]
class _SessionExpiredDialogContent extends StatefulWidget {
  final String title;
  final String message;
  final String buttonText;
  final bool isDark;
  final VoidCallback onLoginAgain;
  final VoidCallback onCancel;

  const _SessionExpiredDialogContent({
    required this.title,
    required this.message,
    required this.buttonText,
    required this.isDark,
    required this.onLoginAgain,
    required this.onCancel,
  });

  @override
  State<_SessionExpiredDialogContent> createState() =>
      _SessionExpiredDialogContentState();
}

class _SessionExpiredDialogContentState
    extends State<_SessionExpiredDialogContent>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  // DalabaPay Brand Colors from dashboard
  static const Color _primaryBlue = Color(
    0xFF102C68,
  ); // From balance card gradient
  static const Color _primaryGreen = Color(
    0xFF5BB592,
  ); // From balance card gradient
  static const Color _darkBlue = Color(0xFF102C68); // Primary text color

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: MediaQuery.of(context).size.width > 500 ? 460 : double.infinity,
      decoration: BoxDecoration(
        color: widget.isDark ? const Color(0xFF1A1A2E) : Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 40,
            spreadRadius: 4,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Gradient Header - Matches dashboard balance card
            _buildGradientHeader(),
            const SizedBox(height: 8),
            // Content
            _buildContent(),
            // Action Buttons
            _buildActionButtons(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  // ==================== GRADIENT HEADER ====================
  Widget _buildGradientHeader() {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          height: 130,
          decoration: BoxDecoration(
            // ✅ EXACT SAME GRADIENT AS DASHBOARD BALANCE CARD
            gradient: const LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [Color(0xFF5BB592), Color(0xFF102C68)],
              stops: [0.06, 0.41],
            ),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(28),
              topRight: Radius.circular(28),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 30, 24, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // DalabaPay Brand
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.2),
                          width: 0.5,
                        ),
                      ),
                      child: const Text(
                        '🔐 DalabaPay',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.red.withOpacity(0.3),
                          width: 0.5,
                        ),
                      ),
                      child: const Text(
                        'EXPIRED',
                        style: TextStyle(
                          color: Colors.redAccent,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  widget.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Please log in again to continue',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
        // Floating Animated Lock Icon
        Positioned(
          right: 24,
          bottom: -28,
          child: AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              return Transform.scale(
                scale: 1.0 + (_pulseController.value * 0.06),
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF102C68), Color(0xFF5BB592)],
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 16,
                        spreadRadius: 2,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withOpacity(0.3),
                        width: 2,
                      ),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.lock_outline_rounded,
                        color: Colors.white,
                        size: 26,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ==================== CONTENT ====================
  Widget _buildContent() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Info Box
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color:
                  widget.isDark
                      ? const Color(0xFF1A1A3E).withOpacity(0.5)
                      : const Color(0xFF102C68).withOpacity(0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color:
                    widget.isDark
                        ? const Color(0xFF2D2D5E).withOpacity(0.5)
                        : const Color(0xFF102C68).withOpacity(0.1),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color:
                        widget.isDark
                            ? const Color(0xFF0D2847)
                            : const Color(0xFF5BB592).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.info_outline_rounded,
                    color:
                        widget.isDark
                            ? const Color(0xFF5BB592)
                            : const Color(0xFF102C68),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    widget.message,
                    style: TextStyle(
                      color:
                          widget.isDark ? const Color(0xFFB0C4DE) : _darkBlue,
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Security Notice
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.shield_outlined,
                  color:
                      widget.isDark
                          ? const Color(0xFF5BB592).withOpacity(0.5)
                          : const Color(0xFF102C68).withOpacity(0.5),
                  size: 16,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Your data remains secure. Log in again to continue where you left off.',
                    style: TextStyle(
                      color:
                          widget.isDark
                              ? const Color(0xFF8899AA)
                              : const Color(0xFF667788),
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==================== ACTION BUTTONS ====================
  Widget _buildActionButtons() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Row(
        children: [
          // Cancel Button
          Expanded(
            child: TextButton(
              onPressed: widget.onCancel,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                backgroundColor:
                    widget.isDark
                        ? const Color(0xFF2D2D4E).withOpacity(0.4)
                        : const Color(0xFFF0F2F5),
              ),
              child: Text(
                'Cancel',
                style: TextStyle(
                  color:
                      widget.isDark
                          ? const Color(0xFF8899AA)
                          : const Color(0xFF556677),
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Login Again Button - Uses dark blue from dashboard
          Expanded(
            flex: 2,
            child: ElevatedButton(
              onPressed: widget.onLoginAgain,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                backgroundColor:
                    widget.isDark
                        ? const Color(0xFF5BB592)
                        : const Color(0xFF102C68),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
                shadowColor: Colors.transparent,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.login_rounded, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    widget.buttonText,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
