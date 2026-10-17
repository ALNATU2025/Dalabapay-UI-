// lib/core/services/update_service.dart
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:package_info_plus/package_info_plus.dart';

import 'api_service.dart';

class UpdateService {
  static Future<Map<String, dynamic>?> checkForUpdate() async {
    try {
      // Get the actual app version from PackageInfo
      final packageInfo = await PackageInfo.fromPlatform();
      final fullVersion = packageInfo.version; // "1.4.0+1"
      final cleanVersion = fullVersion.split('+')[0]; // "1.4.0"

      debugPrint('📱 Current app version: $fullVersion (clean: $cleanVersion)');

      // Send the clean version to backend for comparison
      final response = await http
          .get(
            Uri.parse(
              '${ApiService.baseUrl}/api/app/version?platform=android&version=$cleanVersion',
            ),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          final responseData = data['data'];

          // Get versions from response
          final latestVersion = responseData['latestVersion'] ?? '1.0.0';
          final currentVersion = responseData['currentVersion'] ?? cleanVersion;

          // Properly compare versions
          final needsUpdate =
              _compareVersions(currentVersion, latestVersion) < 0;

          debugPrint(
            '📊 Version comparison: Current=$currentVersion, Latest=$latestVersion, NeedsUpdate=$needsUpdate',
          );

          // Return the data with the full version for display
          return {
            ...responseData,
            'currentVersion': fullVersion, // Use full version for display
            'needsUpdate': needsUpdate, // Override with proper comparison
          };
        }
      } else {
        debugPrint('⚠️ Backend returned status: ${response.statusCode}');
      }
      return null;
    } catch (e) {
      debugPrint('❌ Update check error: $e');
      return null;
    }
  }

  // Helper function to compare versions
  static int _compareVersions(String v1, String v2) {
    try {
      final parts1 =
          v1.split('.').map((part) {
            // Handle version parts that might contain non-numeric characters
            final numericPart = part.replaceAll(RegExp(r'[^0-9]'), '');
            return int.tryParse(numericPart) ?? 0;
          }).toList();

      final parts2 =
          v2.split('.').map((part) {
            final numericPart = part.replaceAll(RegExp(r'[^0-9]'), '');
            return int.tryParse(numericPart) ?? 0;
          }).toList();

      final maxLength =
          parts1.length > parts2.length ? parts1.length : parts2.length;

      for (int i = 0; i < maxLength; i++) {
        final num1 = i < parts1.length ? parts1[i] : 0;
        final num2 = i < parts2.length ? parts2[i] : 0;

        if (num1 != num2) {
          return num1.compareTo(num2);
        }
      }
      return 0;
    } catch (e) {
      debugPrint('⚠️ Error comparing versions: $e');
      return 0;
    }
  }

  static Future<void> openPlayStore(String url) async {
    try {
      final Uri uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        debugPrint('⚠️ Could not launch $url');
      }
    } catch (e) {
      debugPrint('❌ Error opening play store: $e');
    }
  }
}
