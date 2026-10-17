// lib/core/utils/image_helper.dart
import 'package:flutter/foundation.dart';
import '../services/api_service.dart';

class ImageHelper {
  /// Builds a full, absolute URL for any image path.
  ///
  /// Handles:
  /// - Full URLs (http/https) → returned as-is (with path encoding)
  /// - Relative paths (/uploads/...) → prepended with assetBaseUrl
  /// - Bare filenames → prepended with assetBaseUrl + /uploads/
  /// - Null/empty → returns null
  ///
  /// ✅ Encodes unsafe characters (spaces, parentheses, etc.) in the PATH
  ///    so URLs like `/uploads/scaled_images (13).jpg` become
  ///    `/uploads/scaled_images%20(13).jpg` — which servers serve correctly.
  static String? buildImageUrl(String? path, {String? cacheBuster}) {
    if (path == null || path.trim().isEmpty) return null;

    final trimmed = path.trim();
    String url;

    // Already a full URL
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      url = trimmed;
    } else if (trimmed.startsWith('/uploads/')) {
      url = '${ApiService.assetBaseUrl}$trimmed';
    } else if (trimmed.startsWith('/')) {
      url = '${ApiService.assetBaseUrl}$trimmed';
    } else {
      // Bare filename → assume /uploads/
      url = '${ApiService.assetBaseUrl}/uploads/$trimmed';
    }

    // ✅ Encode the PATH portion only (preserves ://, ?, &, =)
    url = _encodeUrlPath(url);

    // ✅ Add cache buster
    if (cacheBuster != null && cacheBuster.isNotEmpty) {
      final separator = url.contains('?') ? '&' : '?';
      url = '$url${separator}v=$cacheBuster';
    }

    return url;
  }

  /// Encodes only the path portion of a URL.
  /// Leaves the scheme, host, port, query and fragment untouched.
  /// This is what fixes filenames with spaces, parentheses, etc.
  static String _encodeUrlPath(String url) {
    try {
      final uri = Uri.parse(url);

      // Encode each path segment individually — this is the correct way.
      // Uri.encodeComponent encodes spaces as %20, parentheses as %28/%29, etc.
      // BUT: we need to preserve `(` and `)` since they're valid in URLs.
      final encodedSegments =
          uri.pathSegments.map((segment) {
            return Uri.encodeComponent(
              segment,
            ).replaceAll('%28', '(').replaceAll('%29', ')');
          }).toList();

      final encodedPath =
          encodedSegments.isEmpty ? '/' : '/${encodedSegments.join('/')}';

      // Rebuild the URI with the encoded path — this preserves scheme, host, port, query
      final rebuilt = uri.replace(path: encodedPath);

      return rebuilt.toString();
    } catch (e) {
      // Fallback: manually encode only spaces (the most common issue)
      if (kDebugMode) {
        debugPrint('⚠️ URL parse failed, using fallback encoding: $e');
      }
      return url.replaceAll(' ', '%20');
    }
  }

  /// Fallback URL when primary fails — tries alternate paths.
  static String? buildFallbackUrl(String? path) {
    if (path == null || path.trim().isEmpty) return null;

    final trimmed = path.trim();
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return null; // Already absolute, no better fallback
    }

    // ✅ NOTE: We no longer need /api/uploads/ fallback since the real
    // backend serves at /uploads/. Keep this returning null to avoid
    // unnecessary 404 network requests.
    return null;
  }

  /// Debug logger — only prints in debug mode.
  static void logImageLoad(String? original, String? resolved) {
    if (kDebugMode) {
      debugPrint('📸 Original: $original');
      debugPrint('📸 Resolved: $resolved');
    }
  }
}
