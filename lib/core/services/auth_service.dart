// lib/core/services/auth_service.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

class AuthService {
  // ============================================
  // Configuration
  // ============================================
  static bool forceCloudInDebug = true;
  static bool get isProduction => forceCloudInDebug || !kDebugMode;

  // ============================================
  // Constants
  // ============================================
  static const String _tokenKey = 'token';
  static const String _refreshTokenKey = 'refreshToken';
  static const String _userIdKey = 'userId';
  static const String _userKey = 'user';
  static const String _lastActivityKey = 'lastActivity';
  static const String _autoLogoutKey = 'autoLogout';
  static const String _manualLogoutKey = 'manualLogout';
  static const String _pinSetKey = 'transactionPinSet';

  // ✅ 30-MINUTE SESSION TIMEOUT (extended from 3 minutes)
  static const Duration _sessionTimeout = Duration(minutes: 30);
  static Timer? _inactivityTimer;
  static Timer? _refreshTimer;
  static Timer? _healthCheckTimer;

  static int _refreshAttempts = 0;
  static const int maxRefreshAttempts = 3;

  // ============================================
  // Auth State
  // ============================================
  static final _authStateController = StreamController<bool>.broadcast();
  static Stream<bool> get authStateStream => _authStateController.stream;
  static bool _isAuthenticated = false;
  static bool get isAuthenticated => _isAuthenticated;

  static Map<String, dynamic>? _currentUser;
  static Map<String, dynamic>? get currentUser => _currentUser;

  // ============================================
  // Logging
  // ============================================
  static void _log(String message) {
    debugPrint('🔐 AuthService: $message');
  }

  // ============================================
  // INITIALIZATION
  // ============================================

  static Future<void> initialize() async {
    await _loadStoredAuth();

    if (_isAuthenticated) {
      _startAutoRefresh();
      _startHealthCheck();
      startSessionMonitoring();
    }

    _log('✅ AuthService initialized: isAuthenticated=$_isAuthenticated');
  }

  // ============================================
  // SESSION MANAGEMENT
  // ============================================

  /// ✅ Start session monitoring (30-minute timeout)
  static void startSessionMonitoring() {
    _log('🕐 Starting session monitoring...');
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(_sessionTimeout, () {
      _handleAutoLogout();
    });
    _log(
      '🕐 Session monitoring started (timeout: ${_sessionTimeout.inMinutes} min)',
    );
  }

  /// ✅ Stop session monitoring
  static void stopSessionMonitoring() {
    _inactivityTimer?.cancel();
    _inactivityTimer = null;
    _log('🕐 Session monitoring stopped');
  }

  /// ✅ Update last activity (call on every user interaction)
  static Future<void> updateLastActivity() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        _lastActivityKey,
        DateTime.now().millisecondsSinceEpoch,
      );
      await prefs.reload();

      // Reset the timer
      _inactivityTimer?.cancel();
      _inactivityTimer = Timer(_sessionTimeout, () {
        _handleAutoLogout();
      });
    } catch (e) {
      // Silent fail
    }
  }

  /// ✅ Handle auto-logout
  static Future<void> _handleAutoLogout() async {
    try {
      _log('🔐 Auto-logout: Session expired due to inactivity');

      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();

      // If we're already logged out, do nothing
      final token = prefs.getString(_tokenKey);
      if (token == null || token.isEmpty) {
        _log('🔐 Auto-logout: Already logged out');
        return;
      }

      // ✅ Capture what must survive
      final preservedUserId = prefs.getString(_userIdKey);
      final preservedUser = prefs.getString(_userKey);
      final preservedPinSet = prefs.getBool(_pinSetKey) ?? false;
      final preservedBioGlobal = prefs.getBool('biometricEnabled') ?? false;

      bool? preservedBioUser;
      if (preservedUserId != null && preservedUserId.isNotEmpty) {
        preservedBioUser = prefs.getBool('biometricEnabled_$preservedUserId');
      }

      // ✅ Mark as auto-logout (drives the "session expired" banner)
      await prefs.setBool(_autoLogoutKey, true);
      await prefs.remove(_lastActivityKey);

      // ✅ Re-assert critical keys — do NOT touch tokens
      if (preservedUserId != null && preservedUserId.isNotEmpty) {
        await prefs.setString(_userIdKey, preservedUserId);
      }
      if (preservedUser != null && preservedUser.isNotEmpty) {
        await prefs.setString(_userKey, preservedUser);
      }
      if (preservedPinSet) {
        await prefs.setBool(_pinSetKey, true);
      }
      if (preservedBioGlobal) {
        await prefs.setBool('biometricEnabled', true);
      }
      if (preservedUserId != null && preservedBioUser != null) {
        await prefs.setBool(
          'biometricEnabled_$preservedUserId',
          preservedBioUser,
        );
      }

      await prefs.reload();

      _isAuthenticated = false;
      _authStateController.add(false);

      _log('🔐 Auto-logout: All session data preserved (tokens + userId)');
    } catch (e) {
      _log('🔐 Auto-logout error: $e');
    }
  }

  /// ✅ Check session status
  static Future<Map<String, dynamic>> validateSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Check if token exists
      final token = prefs.getString(_tokenKey);
      if (token == null || token.isEmpty) {
        // Check if this was an auto-logout
        final isAutoLogout = prefs.getBool(_autoLogoutKey) ?? false;
        if (isAutoLogout) {
          _log('⚠️ Session validation: Auto-logout detected');
          return {
            'valid': false,
            'reason': 'auto_logout',
            'userId': prefs.getString(_userIdKey),
          };
        }
        return {'valid': false, 'reason': 'no_token'};
      }

      // Check if user data exists
      final userId = prefs.getString(_userIdKey);
      if (userId == null || userId.isEmpty) {
        return {'valid': false, 'reason': 'no_user'};
      }

      // Check last activity
      final lastActivity = prefs.getInt(_lastActivityKey);
      if (lastActivity != null) {
        final elapsed = DateTime.now().millisecondsSinceEpoch - lastActivity;
        final elapsedMinutes = elapsed / (1000 * 60);

        if (elapsedMinutes > _sessionTimeout.inMinutes) {
          _log(
            '⚠️ Session validation: Session expired (${elapsedMinutes.toStringAsFixed(1)} min)',
          );
          // Trigger auto-logout
          await _handleAutoLogout();
          return {'valid': false, 'reason': 'expired', 'userId': userId};
        }
      }

      // ✅ Session is valid
      return {'valid': true, 'userId': userId};
    } catch (e) {
      _log('❌ Session validation error: $e');
      return {'valid': false, 'reason': 'error'};
    }
  }

  /// ✅ Get session status for UI
  static Future<String> getSessionStatus() async {
    final validation = await validateSession();
    if (validation['valid'] == true) {
      return 'authenticated';
    }

    final reason = validation['reason'] ?? '';
    if (reason == 'auto_logout' || reason == 'expired') {
      return 'auto_logout';
    }

    return 'unauthenticated';
  }

  /// ✅ Check if user was auto-logged out
  static Future<bool> wasAutoLogout() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoLogoutKey) ?? false;
  }

  /// ✅ Check if user was manually logged out
  static Future<bool> wasManualLogout() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_manualLogoutKey) ?? false;
  }

  // ============================================
  // TOKEN MANAGEMENT
  // ============================================

  static Future<bool> _validateToken() async {
    try {
      final authState = await ApiService.checkAuthState();
      final isValid = authState['isAuthenticated'] == true;

      if (isValid) {
        await _loadUserData();
      }

      return isValid;
    } catch (e) {
      _log('⚠️ Token validation error: $e');
      return false;
    }
  }

  static Future<void> _loadStoredAuth() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Check for auto-logout flag
      final isAutoLogout = prefs.getBool(_autoLogoutKey) ?? false;
      if (isAutoLogout) {
        _log('ℹ️ Auto-logout state detected - not authenticating');
        _isAuthenticated = false;
        _authStateController.add(false);
        return;
      }

      final token = prefs.getString(_tokenKey);
      final userId = prefs.getString(_userIdKey);

      if (token != null &&
          token.isNotEmpty &&
          userId != null &&
          userId.isNotEmpty) {
        final isValid = await _validateToken();
        if (isValid) {
          _isAuthenticated = true;
          await _loadUserData();
          _authStateController.add(true);
          _log('✅ Auth loaded: user=$userId');
          return;
        }
      }

      _isAuthenticated = false;
      _currentUser = null;
      _authStateController.add(false);
      _log('ℹ️ No valid auth found');
    } catch (e) {
      _log('⚠️ Load auth error: $e');
      _isAuthenticated = false;
      _currentUser = null;
      _authStateController.add(false);
    }
  }

  static Future<void> _loadUserData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userString = prefs.getString(_userKey);

      if (userString != null && userString.isNotEmpty) {
        try {
          _currentUser = jsonDecode(userString);
          _log('✅ User data loaded from storage: ${_currentUser?['email']}');
          return;
        } catch (e) {
          _log('⚠️ Error parsing user JSON: $e');
        }
      }

      try {
        final token = await getToken();
        if (token != null && token.isNotEmpty) {
          final user = await ApiService.getCurrentUser();
          if (user.isNotEmpty) {
            _currentUser = user;
            await prefs.setString(_userKey, jsonEncode(user));
            await prefs.reload();
            _log('✅ User data loaded from API: ${user['email']}');
          }
        }
      } catch (e) {
        _log('⚠️ Could not fetch user data from API: $e');
      }
    } catch (e) {
      _log('⚠️ Load user data error: $e');
    }
  }

  static void _startAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(minutes: 25), (_) async {
      if (_isAuthenticated) {
        try {
          final result = await ApiService.refreshToken();
          if (result['success'] != true) {
            _refreshAttempts++;
            if (_refreshAttempts >= maxRefreshAttempts) {
              _log('⚠️ Max refresh attempts reached, logging out');
              await logout();
            }
          } else {
            _refreshAttempts = 0;
          }
        } catch (e) {
          _log('⚠️ Auto-refresh error: $e');
          _refreshAttempts++;
        }
      }
    });
  }

  static void _startHealthCheck() {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = Timer.periodic(const Duration(minutes: 5), (_) async {
      if (_isAuthenticated) {
        final isValid = await _validateToken();
        if (!isValid) {
          _log('⚠️ Token invalid, logging out');
          await logout();
        }
      }
    });
  }

  // ============================================
  // LOGIN METHODS
  // ============================================

  static Future<Map<String, dynamic>> loginUser({
    required String email,
    required String password,
  }) async {
    try {
      final response = await ApiService.loginUser(
        email: email,
        password: password,
      );

      if (response['success'] == true) {
        // ✅ Clear auto-logout flags
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_autoLogoutKey);
        await prefs.remove(_manualLogoutKey);
        await prefs.reload();

        _isAuthenticated = true;
        await _loadUserData();
        _authStateController.add(true);
        _startAutoRefresh();
        _startHealthCheck();
        startSessionMonitoring();
        _log('✅ User logged in: $email');
      }

      return response;
    } catch (e) {
      await ApiService.reportError(e, StackTrace.current);
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> loginWithPin({
    required String userId,
    required String pin,
  }) async {
    try {
      _log('🔐 PIN/Biometric login attempt for user: $userId');

      final prefs = await SharedPreferences.getInstance();
      final isAutoLogout = prefs.getBool(_autoLogoutKey) ?? false;

      if (isAutoLogout) {
        _log('ℹ️ Auto-logout detected - PIN login allowed');
      }

      // ✅ Verify PIN with backend
      final response = await ApiService.verifyTransactionPinForLogin(
        userId: userId,
        transactionPin: pin,
      );

      _log('📡 PIN verification response: ${response['success']}');

      if (response['success'] == true) {
        // ✅ SAVE BOTH TOKENS — critical for token refresh to work
        final newToken = response['token']?.toString();
        final newRefreshToken = response['refreshToken']?.toString();

        if (newToken != null && newToken.isNotEmpty) {
          await prefs.setString(_tokenKey, newToken);
          _log('✅ Access token saved');
        } else {
          _log('⚠️ WARNING: No access token returned from PIN login!');
        }

        if (newRefreshToken != null && newRefreshToken.isNotEmpty) {
          await prefs.setString(_refreshTokenKey, newRefreshToken);
          _log('✅ Refresh token saved');
        } else {
          _log('⚠️ WARNING: No refresh token returned from PIN login!');
        }

        // ✅ Save user data if returned
        if (response['user'] != null) {
          await prefs.setString(_userKey, jsonEncode(response['user']));
        }

        // ✅ Save user ID
        await prefs.setString(_userIdKey, userId);

        // ✅ Reset last activity to NOW so session timer restarts cleanly
        await prefs.setInt(
          _lastActivityKey,
          DateTime.now().millisecondsSinceEpoch,
        );

        // ✅ Clear auto-logout and manual-logout flags
        await prefs.remove(_autoLogoutKey);
        await prefs.remove(_manualLogoutKey);
        await prefs.reload();

        // ✅ Restore auth state
        _isAuthenticated = true;
        await _loadUserData();
        _authStateController.add(true);

        // ✅ Restart ALL monitoring (same as email login)
        _startAutoRefresh();
        _startHealthCheck();
        startSessionMonitoring();

        _log('✅ PIN/Biometric login successful');
        _log('   Session monitoring restarted (30-min timeout)');
        _log('   Auto-refresh timer restarted');
        _log('   Health check timer restarted');

        return {
          'success': true,
          'message': 'Login successful',
          'user': _currentUser,
        };
      } else {
        // ❌ PIN login failed
        final message = response['message'] ?? 'Invalid PIN';
        _log('❌ PIN login failed: $message');

        if (response['networkError'] == true) {
          return {
            'success': false,
            'message': 'Network error. Please check your internet connection.',
            'networkError': true,
          };
        }

        if (response['locked'] == true) {
          return {
            'success': false,
            'message': message,
            'locked': true,
            'lockTimeRemaining': response['lockTimeRemaining'] ?? 0,
          };
        }

        return {
          'success': false,
          'message': message,
          'attemptsRemaining': response['attemptsRemaining'] ?? 0,
        };
      }
    } catch (e) {
      _log('❌ PIN login error: $e');
      return {
        'success': false,
        'message': 'PIN verification failed: ${e.toString()}',
      };
    }
  }

  // ============================================
  // LOGOUT METHODS
  // ============================================

  /// ✅ Manual logout - clears everything
  // ============================================
  // LOGOUT METHODS
  // ============================================

  /// ✅ Session-preserving logout.
  /// Keeps token, refreshToken, userId, user JSON, PIN flag, and
  /// biometric flag in SharedPreferences so the user can re-login
  /// with PIN or Biometric without entering email + password.
  /// Only clears ephemeral state (activity timestamp, auto-logout flag).
  static Future<void> logout({bool isManual = true}) async {
    stopSessionMonitoring();
    _refreshTimer?.cancel();
    _healthCheckTimer?.cancel();

    try {
      await ApiService.logoutUser();
    } catch (e) {
      _log('Logout API error (safe): $e');
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    // ---------- 1. Capture everything we must preserve ----------
    final preservedToken = prefs.getString(_tokenKey);
    final preservedRefresh = prefs.getString(_refreshTokenKey);
    final preservedUserId = prefs.getString(_userIdKey);
    final preservedUser = prefs.getString(_userKey);
    final preservedPinSet = prefs.getBool(_pinSetKey) ?? false;
    final preservedBioGlobal = prefs.getBool('biometricEnabled') ?? false;

    bool? preservedBioUser;
    if (preservedUserId != null && preservedUserId.isNotEmpty) {
      preservedBioUser = prefs.getBool('biometricEnabled_$preservedUserId');
    }

    // ---------- 2. Clear ONLY ephemeral keys ----------
    await prefs.remove(_lastActivityKey);
    await prefs.remove(_autoLogoutKey);

    if (isManual) {
      await prefs.setBool(_manualLogoutKey, true);
    }

    // ---------- 3. Re-assert preserved keys (belt & braces) ----------
    if (preservedToken != null && preservedToken.isNotEmpty) {
      await prefs.setString(_tokenKey, preservedToken);
    }
    if (preservedRefresh != null && preservedRefresh.isNotEmpty) {
      await prefs.setString(_refreshTokenKey, preservedRefresh);
    }
    if (preservedUserId != null && preservedUserId.isNotEmpty) {
      await prefs.setString(_userIdKey, preservedUserId);
    }
    if (preservedUser != null && preservedUser.isNotEmpty) {
      await prefs.setString(_userKey, preservedUser);
    }
    if (preservedPinSet) {
      await prefs.setBool(_pinSetKey, true);
    }
    if (preservedBioGlobal) {
      await prefs.setBool('biometricEnabled', true);
    }
    if (preservedUserId != null && preservedBioUser != null) {
      await prefs.setBool(
        'biometricEnabled_$preservedUserId',
        preservedBioUser,
      );
    }

    await prefs.reload();

    // ---------- 4. Update in-memory auth state ----------
    _isAuthenticated = false;
    _currentUser = null;
    _authStateController.add(false);
    _refreshAttempts = 0;

    _log('✅ Logout complete (manual: $isManual) — session preserved');
    _log('   userId kept: ${preservedUserId != null}');
    _log('   token kept: ${preservedToken != null}');
    _log('   PIN flag kept: $preservedPinSet');
    _log(
      '   Biometric flag kept: ${preservedBioGlobal || (preservedBioUser ?? false)}',
    );
  }
  // ============================================
  // GETTERS
  // ============================================

  static Future<String?> getToken() async {
    return await ApiService.getToken();
  }

  static Future<String?> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_userIdKey);
  }

  static Future<Map<String, dynamic>?> getUser() async {
    if (_currentUser != null) {
      return _currentUser;
    }
    await _loadUserData();
    return _currentUser;
  }

  static String getFullName() {
    return _currentUser?['fullName'] ?? _currentUser?['name'] ?? 'User';
  }

  static String getEmail() {
    return _currentUser?['email'] ?? '';
  }

  static bool isAdmin() {
    return _currentUser?['isAdmin'] == true || _currentUser?['role'] == 'admin';
  }

  // ============================================
  // CLEANUP
  // ============================================

  static void dispose() {
    _inactivityTimer?.cancel();
    _refreshTimer?.cancel();
    _healthCheckTimer?.cancel();
    _authStateController.close();
  }
}
