// lib/core/services/bank_transfer_service.dart
//
// Client for the bank-transfer endpoints added to vtpass-backend
// (routes/bankTransferRoutes.js). Bank payouts go through Paystack Transfers
// and are switched off on the server until the business enables them.
import 'api_service.dart';

class BankInfo {
  final String name;
  final String code;
  const BankInfo(this.name, this.code);
}

class BankTransferConfig {
  final bool enabled;
  final double fee;
  final double minAmount;
  final double maxAmount;
  final String? message;

  const BankTransferConfig({
    required this.enabled,
    required this.fee,
    required this.minAmount,
    required this.maxAmount,
    this.message,
  });

  static const disabled = BankTransferConfig(
    enabled: false,
    fee: 0,
    minAmount: 100,
    maxAmount: 0,
  );
}

class BankTransferService {
  BankTransferService._();

  static List<BankInfo>? _banksCache;

  static double _num(dynamic v, double fallback) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? fallback;
  }

  /// Whether bank transfers are switched on, plus fee and limits.
  static Future<BankTransferConfig> getConfig() async {
    try {
      final res = await ApiService.authenticatedGet('/api/bank-transfer/config');
      return BankTransferConfig(
        enabled: res['enabled'] == true,
        fee: _num(res['fee'], 0),
        minAmount: _num(res['minAmount'], 100),
        maxAmount: _num(res['maxAmount'], 0),
        message: res['message']?.toString(),
      );
    } catch (_) {
      return BankTransferConfig.disabled;
    }
  }

  /// Nigerian banks supported for payouts.
  static Future<List<BankInfo>> getBanks({bool forceRefresh = false}) async {
    if (!forceRefresh && _banksCache != null && _banksCache!.isNotEmpty) {
      return _banksCache!;
    }
    final res = await ApiService.authenticatedGet('/api/bank-transfer/banks');
    final list = (res['banks'] as List? ?? const [])
        .whereType<Map>()
        .map((b) => BankInfo(b['name'].toString(), b['code'].toString()))
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    _banksCache = list;
    return list;
  }

  /// Looks up the account holder's name. Returns null when it can't be resolved.
  static Future<String?> resolveAccount({
    required String accountNumber,
    required String bankCode,
  }) async {
    final res = await ApiService.authenticatedPost('/api/bank-transfer/resolve', {
      'accountNumber': accountNumber,
      'bankCode': bankCode,
    });
    if (res['success'] == true && (res['accountName'] ?? '').toString().isNotEmpty) {
      return res['accountName'].toString();
    }
    return null;
  }

  /// Sends money from the wallet to a bank account.
  /// Exactly one of [transactionPin] or [useBiometric] should be provided.
  static Future<Map<String, dynamic>> send({
    required String accountNumber,
    required String bankCode,
    required String bankName,
    required String accountName,
    required double amount,
    String? narration,
    String? transactionPin,
    bool useBiometric = false,
    required String clientReference,
  }) async {
    return ApiService.authenticatedPost(
      '/api/bank-transfer/send',
      {
        'accountNumber': accountNumber,
        'bankCode': bankCode,
        'bankName': bankName,
        'accountName': accountName,
        'amount': amount,
        if (narration != null && narration.trim().isNotEmpty) 'narration': narration.trim(),
        if (transactionPin != null) 'transactionPin': transactionPin,
        if (useBiometric) 'useBiometric': true,
        'clientReference': clientReference,
      },
      useBiometric: useBiometric,
    );
  }

  /// Re-checks a pending transfer with the payment provider.
  static Future<Map<String, dynamic>> status(String reference) {
    return ApiService.authenticatedGet('/api/bank-transfer/status/$reference');
  }

  /// Looks up a Dalabapay user by email for wallet-to-wallet transfers.
  /// Returns the recipient's display name or null if not found.
  static Future<String?> lookupWalletRecipient(String email) async {
    try {
      final res = await ApiService.authenticatedGet(
        '/api/bank-transfer/wallet-recipient?email=${Uri.encodeQueryComponent(email.trim().toLowerCase())}',
      );
      if (res['success'] == true) return res['name']?.toString();
    } catch (_) {}
    return null;
  }
}
