// lib/services/cache_service.dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

class CacheService {
  // ==================== CONSTANTS ====================
  static const String _transactionsCacheKey = 'cached_transactions';
  static const String _balanceCacheKey = 'cached_balance';
  static const String _lastUpdatedKey = 'last_updated';
  static const String _cacheTimestampKey = 'cache_timestamp';
  static const String _userCachePrefix = 'user_';
  static const String _userBalanceKey = 'user_balance';
  static const String _userTransactionsKey = 'user_transactions';
  static const String _lastUserIdKey = 'last_logged_in_user';
  static const String _adminDashboardCacheKey = 'cached_admin_dashboard';
  static const String _adminDashboardTimestampKey = 'admin_dashboard_timestamp';

  // Size limits
  static const int _maxCacheSizeBytes = 4 * 1024 * 1024; // 4MB limit
  static const int _maxRecentTransactions = 5;

  // ==================== USER ID HELPERS ====================
  static Future<String?> _getCurrentUserId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userString = prefs.getString('user');
      if (userString != null && userString.isNotEmpty) {
        try {
          final userMap = jsonDecode(userString);
          final userId = userMap['_id']?.toString();
          if (userId != null && userId.isNotEmpty) {
            return userId;
          }
        } catch (e) {
          debugPrint('Error parsing user: $e');
        }
      }
      return prefs.getString('userId');
    } catch (e) {
      debugPrint('Error getting current user ID: $e');
      return null;
    }
  }

  static Future<String> _getUserKey(String key) async {
    final userId = await _getCurrentUserId();
    return userId != null ? '$_userCachePrefix${userId}_$key' : key;
  }

  // ==================== SIZE MANAGEMENT ====================
  static Future<bool> _willExceedQuota(Map<String, dynamic> data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final currentSize = await _getCurrentStorageSize();
      final newDataSize = utf8.encode(jsonEncode(data)).length;
      final totalSize = currentSize + newDataSize;

      debugPrint(
        '📊 Storage: Current=${currentSize ~/ 1024}KB, New=${newDataSize ~/ 1024}KB, Total=${totalSize ~/ 1024}KB, Limit=${_maxCacheSizeBytes ~/ 1024}KB',
      );

      return totalSize > _maxCacheSizeBytes;
    } catch (e) {
      debugPrint('Error checking storage size: $e');
      return true;
    }
  }

  static Future<int> _getCurrentStorageSize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      int totalSize = 0;

      for (String key in keys) {
        final value = prefs.get(key);
        if (value != null) {
          final stringValue = value.toString();
          totalSize += utf8.encode(stringValue).length;
        }
      }
      return totalSize;
    } catch (e) {
      debugPrint('Error calculating storage size: $e');
      return 0;
    }
  }

  static Map<String, dynamic> _minimizeDashboardData(
    Map<String, dynamic> data,
  ) {
    try {
      final minimized = <String, dynamic>{};

      minimized['totalUsers'] = data['totalUsers'] ?? 0;
      minimized['totalTransactions'] = data['totalTransactions'] ?? 0;
      minimized['totalRevenue'] = (data['totalRevenue'] ?? 0.0).toDouble();
      minimized['pendingCount'] = data['pendingCount'] ?? 0;
      minimized['cacheAge'] =
          data['cacheAge'] ?? DateTime.now().millisecondsSinceEpoch;

      final transactions = data['recentTransactions'] as List<dynamic>?;
      if (transactions != null && transactions.isNotEmpty) {
        final minimizedTransactions = <Map<String, dynamic>>[];
        final limit =
            transactions.length > _maxRecentTransactions
                ? _maxRecentTransactions
                : transactions.length;

        for (int i = 0; i < limit; i++) {
          final tx = transactions[i] as Map<String, dynamic>;
          final minimizedTx = <String, dynamic>{
            'amount': (tx['amount'] as num?)?.toDouble() ?? 0.0,
            'status': tx['status']?.toString() ?? 'Unknown',
            'type': tx['type']?.toString() ?? '',
            'createdAt': tx['createdAt']?.toString() ?? '',
          };

          final user = tx['user'];
          if (user is Map<String, dynamic>) {
            minimizedTx['userName'] =
                user['fullName'] ?? user['email'] ?? 'System';
          } else if (user is String) {
            minimizedTx['userName'] = user;
          } else {
            minimizedTx['userName'] = 'System';
          }

          minimizedTransactions.add(minimizedTx);
        }

        minimized['recentTransactions'] = minimizedTransactions;
      } else {
        minimized['recentTransactions'] = [];
      }

      return minimized;
    } catch (e) {
      debugPrint('Error minimizing data: $e');
      return data;
    }
  }

  static Future<void> _cleanOldAdminCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keysToRemove = <String>[];

      for (String key in prefs.getKeys()) {
        if (key.contains('admin') ||
            key.contains('_admin_') ||
            key == _adminDashboardCacheKey ||
            key == _adminDashboardTimestampKey) {
          keysToRemove.add(key);
        }
      }

      for (String key in keysToRemove) {
        await prefs.remove(key);
        debugPrint('🧹 Removed stale cache: $key');
      }

      debugPrint('✅ Cleaned ${keysToRemove.length} admin cache entries');
    } catch (e) {
      debugPrint('Error cleaning admin cache: $e');
    }
  }

  // ==================== TRANSACTIONS CACHE ====================
  static Future<void> cacheTransactions(List<dynamic> transactions) async {
    try {
      final key = await _getUserKey(_userTransactionsKey);
      final prefs = await SharedPreferences.getInstance();
      final transactionsJson = jsonEncode(transactions);
      await prefs.setString(key, transactionsJson);
      await prefs.setString(
        _cacheTimestampKey,
        DateTime.now().toIso8601String(),
      );
      debugPrint('✅ Cached ${transactions.length} transactions for user');
    } catch (e) {
      debugPrint('❌ Failed to cache transactions: $e');
    }
  }

  static Future<List<dynamic>> getCachedTransactions() async {
    try {
      final key = await _getUserKey(_userTransactionsKey);
      final prefs = await SharedPreferences.getInstance();
      final cachedJson = prefs.getString(key);
      if (cachedJson != null && cachedJson.isNotEmpty) {
        final List<dynamic> transactions = jsonDecode(cachedJson);
        debugPrint('📦 Loaded ${transactions.length} transactions from cache');
        return transactions;
      }
    } catch (e) {
      debugPrint('❌ Failed to load cached transactions: $e');
    }
    return [];
  }

  // ==================== BALANCE CACHE ====================
  static Future<void> cacheBalance(double balance) async {
    try {
      final key = await _getUserKey(_userBalanceKey);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(key, balance);
      debugPrint('✅ Cached balance for user: ₦$balance');
    } catch (e) {
      debugPrint('❌ Failed to cache balance: $e');
    }
  }

  static Future<double> getCachedBalance() async {
    try {
      final key = await _getUserKey(_userBalanceKey);
      final prefs = await SharedPreferences.getInstance();
      final balance = prefs.getDouble(key) ?? 0.0;
      if (balance > 0) {
        debugPrint('📦 Loaded cached balance: ₦$balance');
      }
      return balance;
    } catch (e) {
      debugPrint('❌ Failed to load cached balance: $e');
      return 0.0;
    }
  }

  // ==================== ADMIN DASHBOARD CACHE ====================
  static Future<void> cacheAdminDashboard(
    Map<String, dynamic> dashboardData,
  ) async {
    try {
      final minimalData = _minimizeDashboardData(dashboardData);

      final willExceed = await _willExceedQuota(minimalData);

      if (willExceed) {
        debugPrint(
          '⚠️ Admin dashboard data too large, cleaning old cache first...',
        );
        await _cleanOldAdminCache();

        final willExceedAfterClean = await _willExceedQuota(minimalData);
        if (willExceedAfterClean) {
          debugPrint('❌ Data still too large after cleanup, skipping cache');
          return;
        }
      }

      final prefs = await SharedPreferences.getInstance();
      final jsonString = jsonEncode(minimalData);
      final sizeKB = utf8.encode(jsonString).length ~/ 1024;

      debugPrint('💾 Caching admin dashboard (${sizeKB}KB)');
      await prefs.setString(_adminDashboardCacheKey, jsonString);
      await prefs.setString(
        _adminDashboardTimestampKey,
        DateTime.now().toIso8601String(),
      );
    } catch (e) {
      if (e.toString().contains('QuotaExceededError')) {
        debugPrint('❌ Quota exceeded, clearing admin cache and retrying...');
        await _cleanOldAdminCache();

        try {
          final prefs = await SharedPreferences.getInstance();
          final minimalData = _minimizeDashboardData(dashboardData);
          await prefs.setString(
            _adminDashboardCacheKey,
            jsonEncode(minimalData),
          );
          await prefs.setString(
            _adminDashboardTimestampKey,
            DateTime.now().toIso8601String(),
          );
          debugPrint('✅ Retry successful after cleanup');
        } catch (retryError) {
          debugPrint('❌ Still failing after cleanup: $retryError');
        }
      } else {
        debugPrint('❌ Failed to cache admin dashboard: $e');
      }
    }
  }

  static Future<Map<String, dynamic>?> getCachedAdminDashboard() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedJson = prefs.getString(_adminDashboardCacheKey);
      if (cachedJson != null && cachedJson.isNotEmpty) {
        final data = jsonDecode(cachedJson) as Map<String, dynamic>;
        debugPrint('📦 Loaded admin dashboard from cache');
        return data;
      }
    } catch (e) {
      debugPrint('❌ Failed to load cached admin dashboard: $e');
    }
    return null;
  }

  static Future<Duration?> getAdminDashboardCacheAge() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final timestamp = prefs.getString(_adminDashboardTimestampKey);
      if (timestamp != null) {
        final cacheTime = DateTime.parse(timestamp);
        return DateTime.now().difference(cacheTime);
      }
    } catch (e) {
      debugPrint('❌ Failed to get cache age: $e');
    }
    return null;
  }

  // ==================== UTILITY METHODS ====================
  static Future<DateTime?> getLastUpdateTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final timestamp = prefs.getString(_cacheTimestampKey);
      if (timestamp != null) {
        return DateTime.parse(timestamp);
      }
    } catch (e) {
      debugPrint('❌ Failed to get last update time: $e');
    }
    return null;
  }

  static Future<bool> isCacheStale() async {
    final lastUpdate = await getLastUpdateTime();
    if (lastUpdate == null) return true;
    final difference = DateTime.now().difference(lastUpdate);
    return difference.inMinutes > 5;
  }

  static Future<bool> isCacheCorrupted() async {
    final transactions = await getCachedTransactions();
    if (transactions.isEmpty) return false;

    final firstDate = transactions[0]['createdAt'];
    if (firstDate == null) return true;

    int sameDateCount = 0;
    for (
      int i = 0;
      i < (transactions.length > 5 ? 5 : transactions.length);
      i++
    ) {
      if (transactions[i]['createdAt'] == firstDate) {
        sameDateCount++;
      }
    }
    return sameDateCount >= 5;
  }

  static Future<void> forceRefreshAndClearCache() async {
    await clearAllCachedUserData();
    debugPrint('🗑️ Force cleared transaction cache');
  }

  static Future<void> clearAllCachedUserData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = await _getCurrentUserId();

      debugPrint('🗑️ Clearing all cached user data for user: $userId');

      final keys = prefs.getKeys();
      int deletedCount = 0;

      for (String key in keys) {
        if (key.contains(_userCachePrefix) ||
            key == _balanceCacheKey ||
            key == _transactionsCacheKey ||
            key == _userBalanceKey ||
            key == _userTransactionsKey ||
            key == 'walletBalance' ||
            key == 'commissionBalance' ||
            key == 'user' ||
            key == 'userId' ||
            key == 'fullName' ||
            key == 'email' ||
            key == 'phone' ||
            key == 'pending_cashwyre_transactions' ||
            key == 'cached_transactions' ||
            key == 'virtualAccountNumber' ||
            key == 'virtualAccountName' ||
            key == 'virtualBankName' ||
            key == 'hasVirtualAccount') {
          await prefs.remove(key);
          deletedCount++;
          debugPrint('   Cleared: $key');
        }
      }

      debugPrint('✅ Cleared $deletedCount cached items');
    } catch (e) {
      debugPrint('❌ Error clearing user cache: $e');
    }
  }

  static Future<void> clearCache() async {
    await clearAllCachedUserData();
  }

  static Future<void> clearCacheKey(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);
      debugPrint('🧹 Cleared cache key: $key');
    } catch (e) {
      debugPrint('Error clearing cache key $key: $e');
    }
  }
}
