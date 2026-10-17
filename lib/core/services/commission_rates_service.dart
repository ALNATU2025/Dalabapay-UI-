// lib/core/services/commission_rates_service.dart
// Reads the commission rates the backend applies to each service
// (GET /api/commission/rates) so review screens can show an estimate before
// the user pays. If the rates can't be fetched, no estimate is shown.
import 'api_service.dart';

class CommissionRatesService {
  CommissionRatesService._();

  static Map<String, double>? _cache;
  static DateTime? _fetchedAt;

  /// service keys: airtime, data, electricity, cable, education, insurance,
  /// international, default
  static Future<Map<String, double>?> load({bool force = false}) async {
    final fresh = _fetchedAt != null &&
        DateTime.now().difference(_fetchedAt!) < const Duration(minutes: 10);
    if (!force && fresh && _cache != null) return _cache;
    try {
      final res = await ApiService.authenticatedGet('/api/commission/rates');
      final raw = res['rates'];
      if (res['success'] == true && raw is Map) {
        final parsed = <String, double>{};
        raw.forEach((k, v) {
          final d = v is num ? v.toDouble() : double.tryParse('$v');
          if (d != null) parsed[k.toString()] = d;
        });
        if (parsed.isNotEmpty) {
          _cache = parsed;
          _fetchedAt = DateTime.now();
        }
      }
    } catch (_) {
      // Endpoint unavailable — callers simply hide the estimate.
    }
    return _cache;
  }

  /// Estimated commission for [service] on [amount], or null if unknown.
  static double? estimate(String service, double amount) {
    final rates = _cache;
    if (rates == null || amount <= 0) return null;
    final rate = rates[service] ?? rates['default'];
    if (rate == null || rate <= 0) return null;
    return (amount * rate * 100).roundToDouble() / 100;
  }
}
