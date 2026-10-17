import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth/error_codes.dart' as auth_error;
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

class BiometricService {
  final LocalAuthentication _auth = LocalAuthentication();

  // Singleton instance
  static final BiometricService _instance = BiometricService._internal();
  factory BiometricService() => _instance;
  BiometricService._internal();

  /// Check if device supports biometrics
  Future<bool> isBiometricAvailable() async {
    try {
      final bool canCheckBiometrics = await _auth.canCheckBiometrics;
      final bool isDeviceSupported = await _auth.isDeviceSupported();
      return canCheckBiometrics && isDeviceSupported;
    } catch (e) {
      debugPrint('Biometric availability error: $e');
      return false;
    }
  }

  /// Get available biometric types (fingerprint, face, etc.)
  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _auth.getAvailableBiometrics();
    } catch (e) {
      debugPrint('Error fetching biometrics: $e');
      return [];
    }
  }

  /// Get human-readable biometric name
  Future<String> getBiometricName() async {
    try {
      final types = await getAvailableBiometrics();
      if (types.contains(BiometricType.face)) {
        return 'Face ID';
      } else if (types.contains(BiometricType.fingerprint)) {
        return 'Fingerprint';
      } else if (types.contains(BiometricType.iris)) {
        return 'Iris';
      } else {
        return 'Biometric';
      }
    } catch (e) {
      return 'Biometric';
    }
  }

  /// Get the current biometric enabled status from local storage
  Future<bool> getBiometricEnabledStatus({String? userId}) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Try user-specific key first
      if (userId != null && userId.isNotEmpty) {
        final userSpecificKey = 'biometricEnabled_$userId';
        if (prefs.containsKey(userSpecificKey)) {
          return prefs.getBool(userSpecificKey) ?? false;
        }
      }

      // Fallback to global key
      return prefs.getBool('biometricEnabled') ?? false;
    } catch (e) {
      debugPrint('Error getting biometric status: $e');
      return false;
    }
  }

  /// Save biometric enabled status locally
  Future<void> saveBiometricStatus({
    required bool enabled,
    String? userId,
    String? biometricKey,
    String? biometricCredentialId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Save user-specific key
      if (userId != null && userId.isNotEmpty) {
        await prefs.setBool('biometricEnabled_$userId', enabled);
      }

      // Also save global key for backward compatibility
      await prefs.setBool('biometricEnabled', enabled);

      // Save biometric credentials if provided
            // Save biometric credentials if provided
      if (enabled) {
        if (biometricKey != null && biometricKey.isNotEmpty) {
          await prefs.setString('biometricKey', biometricKey);
          if (userId != null && userId.isNotEmpty) {
            await prefs.setString('biometricKey_$userId', biometricKey);
          }
        }
        if (biometricCredentialId != null && biometricCredentialId.isNotEmpty) {
          await prefs.setString('biometricCredentialId', biometricCredentialId);
          if (userId != null && userId.isNotEmpty) {
            await prefs.setString('biometricCredentialId_$userId', biometricCredentialId);
          }
        }
      } else {
        await prefs.remove('biometricKey');
        await prefs.remove('biometricCredentialId');
        if (userId != null && userId.isNotEmpty) {
          await prefs.remove('biometricKey_$userId');
          await prefs.remove('biometricCredentialId_$userId');
        }
      }

      await prefs.reload();
      debugPrint('✅ Biometric status saved: $enabled');
    } catch (e) {
      debugPrint('❌ Error saving biometric status: $e');
      rethrow;
    }
  }

  /// Check if biometric is enabled for a specific user (local + backend)
  Future<bool> isBiometricEnabledForUser(String userId) async {
    try {
      final localEnabled = await getBiometricEnabledStatus(userId: userId);

      if (!localEnabled) {
        final prefs = await SharedPreferences.getInstance();
        final hasBiometricKey = prefs.containsKey('biometricKey');
        return hasBiometricKey;
      }

      return localEnabled;
    } catch (e) {
      debugPrint('Error checking biometric enabled: $e');
      return false;
    }
  }

  /// Authenticate user with biometrics
  Future<bool> authenticate({
    required String reason,
    bool biometricOnly = false,
    bool stickyAuth = true,
  }) async {
    if (kIsWeb) {
      debugPrint('Biometric authentication not supported on web');
      return false;
    }

    try {
      final bool isAvailable = await isBiometricAvailable();

      if (!isAvailable) {
        debugPrint('Biometric not available on this device');
        throw PlatformException(
          code: auth_error.notAvailable,
          message: 'Biometric authentication is not available on this device',
        );
      }

      // Stop any ongoing authentication before starting a new request
      await stopAuthentication();

      final bool isAuthenticated = await _auth.authenticate(
        localizedReason: reason,
        options: AuthenticationOptions(
          biometricOnly: biometricOnly,
          stickyAuth: stickyAuth, // Must be true on both Android and iOS!
          useErrorDialogs: true,
        ),
      );

      return isAuthenticated;
    } on PlatformException catch (e) {
      debugPrint('Biometric PlatformException: ${e.code} - ${e.message}');
      rethrow; // Re-throw so caller can display the exact native error message
    } catch (e) {
      debugPrint('Unexpected authentication error: $e');
      return false;
    }
  }

  /// Stop any ongoing authentication
  Future<void> stopAuthentication() async {
    try {
      await _auth.stopAuthentication();
    } catch (e) {
      debugPrint('Error stopping authentication: $e');
    }
  }

  /// Toggle biometric with backend sync
  Future<Map<String, dynamic>> toggleBiometric({
    required String userId,
    required bool enable,
    String? biometricKey,
    String? biometricCredentialId,
  }) async {
    debugPrint('🔄 Toggling biometric for user: $userId, enable: $enable');

    try {
      final response = await ApiService.toggleBiometric(
        userId: userId,
        enable: enable,
        biometricKey: biometricKey,
        biometricCredentialId: biometricCredentialId,
      );

      await saveBiometricStatus(
        enabled: enable,
        userId: userId,
        biometricKey: biometricKey,
        biometricCredentialId: biometricCredentialId,
      );

      return response;
    } catch (e) {
      debugPrint('❌ Error toggling biometric: $e');

      await saveBiometricStatus(
        enabled: enable,
        userId: userId,
        biometricKey: biometricKey,
        biometricCredentialId: biometricCredentialId,
      );

      return {
        'success': true,
        'message': 'Biometric ${enable ? 'enabled' : 'disabled'} locally',
        'localOnly': true,
      };
    }
  }

  /// Get saved biometric credentials
  Future<Map<String, String?>> getSavedBiometricCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return {
        'biometricKey': prefs.getString('biometricKey'),
        'biometricCredentialId': prefs.getString('biometricCredentialId'),
      };
    } catch (e) {
      debugPrint('Error getting biometric credentials: $e');
      return {'biometricKey': null, 'biometricCredentialId': null};
    }
  }


  /// Get the biometric credential ID for a specific user
Future<String?> getBiometricCredentialId({required String userId}) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    
    // Try user-specific key first
    if (userId.isNotEmpty) {
      final userSpecificKey = 'biometricCredentialId_$userId';
      if (prefs.containsKey(userSpecificKey)) {
        return prefs.getString(userSpecificKey);
      }
    }
    
    // Fallback to global key
    return prefs.getString('biometricCredentialId');
  } catch (e) {
    debugPrint('Error getting biometric credential ID: $e');
    return null;
  }
}

  /// Clear all biometric data for a user
  Future<void> clearBiometricData({String? userId}) async {
    try {
      final prefs = await SharedPreferences.getInstance();

        if (userId != null && userId.isNotEmpty) {
        await prefs.remove('biometricEnabled_$userId');
        await prefs.remove('biometricKey_$userId');
        await prefs.remove('biometricCredentialId_$userId');
      }

      await prefs.remove('biometricEnabled');
      await prefs.remove('biometricKey');
      await prefs.remove('biometricCredentialId');

      await prefs.reload();
      debugPrint('✅ Biometric data cleared');
    } catch (e) {
      debugPrint('❌ Error clearing biometric data: $e');
      rethrow;
    }
  }
}

// Singleton instance for easy access
final biometricService = BiometricService();
