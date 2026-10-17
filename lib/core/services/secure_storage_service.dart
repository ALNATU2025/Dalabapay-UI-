// lib/services/secure_storage_service.dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SecureStorageService {
  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  static const String _keyAccessToken = 'access_token';
  static const String _keyRefreshToken = 'refresh_token';
  static const String _keyUserId = 'user_id';
  static const String _keyIsLoggedIn = 'is_logged_in';
  static const String _keyLastRefresh = 'last_token_refresh';

  /// Save Auth Tokens securely
  static Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
    String? userId,
  }) async {
    await _storage.write(key: _keyAccessToken, value: accessToken);
    await _storage.write(key: _keyRefreshToken, value: refreshToken);
    
    if (userId != null && userId.isNotEmpty) {
      await _storage.write(key: _keyUserId, value: userId);
    }
    
    await _storage.write(
      key: _keyLastRefresh, 
      value: DateTime.now().millisecondsSinceEpoch.toString(),
    );

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyIsLoggedIn, true);
  }

  static Future<String?> getAccessToken() async {
    return await _storage.read(key: _keyAccessToken);
  }

  static Future<String?> getRefreshToken() async {
    return await _storage.read(key: _keyRefreshToken);
  }

  static Future<String?> getUserId() async {
    return await _storage.read(key: _keyUserId);
  }

  static Future<int> getLastRefreshTime() async {
    final value = await _storage.read(key: _keyLastRefresh);
    return int.tryParse(value ?? '0') ?? 0;
  }

  static Future<bool> isLoggedIn() async {
    final refreshToken = await getRefreshToken();
    final accessToken = await getAccessToken();
    final prefs = await SharedPreferences.getInstance();
    
    return (prefs.getBool(_keyIsLoggedIn) ?? false) && 
           (refreshToken != null && refreshToken.isNotEmpty) &&
           (accessToken != null && accessToken.isNotEmpty);
  }

  /// Complete Session Clear (Used on Manual Logout or True Expiration)
  static Future<void> clearSession() async {
    await _storage.delete(key: _keyAccessToken);
    await _storage.delete(key: _keyRefreshToken);
    await _storage.delete(key: _keyUserId);
    await _storage.delete(key: _keyLastRefresh);
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyIsLoggedIn, false);
  }

  static Future<void> clearAll() async {
    await _storage.deleteAll();
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}