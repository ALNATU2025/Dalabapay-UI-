// lib/core/widgets/country_flag_widget.dart

import 'package:dalabapay/core/services/api_service.dart';
import 'package:flutter/material.dart';

class CountryFlagWidget extends StatelessWidget {
  final String? flagUrl;
  final double size;
  final bool showBorder;
  final double borderRadius;

  const CountryFlagWidget({
    super.key,
    this.flagUrl,
    this.size = 30,
    this.showBorder = true,
    this.borderRadius = 4,
  });

  @override
  Widget build(BuildContext context) {
    final raw = (flagUrl ?? '').trim();
    final String countryCode = _extractCountryCode(raw);
    final String targetUrl = _resolveFlagUrl(raw, countryCode);

    debugPrint('🇺🇳 CountryFlagWidget: raw="$raw" → code="$countryCode"');

    // ✅ Route through OUR backend proxy
    final String proxiedUrl =
        '${ApiService.baseUrl}/api/operator-logo?url=${Uri.encodeComponent(targetUrl)}';

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Container(
        width: size,
        height: size * 0.75,
        decoration: BoxDecoration(
          border:
              showBorder
                  ? Border.all(color: Colors.grey.shade300, width: 1)
                  : null,
          borderRadius: BorderRadius.circular(borderRadius),
        ),
              child: Image.network(
          proxiedUrl,
          width: size,
          height: size * 0.75,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return _buildLoading();
          },
          errorBuilder: (context, error, stackTrace) {
            // ✅ Fallback: try flagcdn.com directly (bypassing proxy)
            final fallbackUrl = 'https://flagcdn.com/w40/$countryCode.png';
            return Image.network(
              fallbackUrl,
              width: size,
              height: size * 0.75,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (context, error2, stackTrace2) {
                return _buildPlaceholder(countryCode);
              },
            );
          },
        ),
      ),
    );
  }

  String _extractCountryCode(String input) {
    if (input.isEmpty) return 'un';

    // If it's a URL, extract the filename part
    if (input.startsWith('http')) {
      final uri = Uri.tryParse(input);
      final segments = uri?.pathSegments ?? [];
      if (segments.isNotEmpty) {
        final last = segments.last; // "NG.png"
        final base = last.split('.').first; // "NG"
        if (base.length >= 2) return base.substring(0, 2).toLowerCase();
      }
      return 'un';
    }

    if (input.length >= 2) return input.substring(0, 2).toLowerCase();
    return 'un';
  }

   /// ✅ Always prefer flagcdn.com — fast, reliable, has every country.
  /// Only fall back to whatever URL was passed in if we can't derive a code.
  String _resolveFlagUrl(String raw, String code) {
    // If we got a valid 2-letter code → use flagcdn (fast, reliable)
    if (code.length == 2 && code != 'un') {
      return 'https://flagcdn.com/w40/$code.png';
    }

    // Otherwise, if the caller passed a full URL, use it
    if (raw.startsWith('http')) return raw;

    // Last resort — neutral placeholder
    return 'https://flagcdn.com/w40/un.png';
  }
  
  Widget _buildLoading() {
    return Container(
      width: size,
      height: size * 0.75,
      color: Colors.grey.shade100,
      child: Center(
        child: SizedBox(
          width: size * 0.4,
          height: size * 0.4,
          child: const CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF102C68)),
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholder(String code) {
    return Container(
      width: size,
      height: size * 0.75,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(borderRadius),
        border:
            showBorder
                ? Border.all(color: Colors.grey.shade300, width: 1)
                : null,
      ),
      child: Center(
        child: Text(
          code.length >= 2 ? code.substring(0, 2).toUpperCase() : '🌍',
          style: TextStyle(
            fontSize: size * 0.35,
            fontWeight: FontWeight.bold,
            color: Colors.grey.shade600,
          ),
        ),
      ),
    );
  }
}
