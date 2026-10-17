import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:dalabapay/presentation/screens/transactions/transactions_screen.dart';
import 'package:dalabapay/presentation/screens/commission/commission_screen.dart';
import 'package:dalabapay/presentation/screens/settings/settings_screen.dart';
import 'harness.dart';
import 'home_test.dart' show demoPrefs;

void main() {
  final now = DateTime.now();
  String at(int daysAgo, int h, int m) =>
      DateTime(now.year, now.month, now.day - daysAgo, h, m).toUtc().toIso8601String();
  final txs = [
    {'_id': '1', 'type': 'Airtime Purchase', 'description': 'MTN airtime', 'amount': 2000, 'status': 'Successful', 'createdAt': at(0, 10, 42), 'reference': 'R1'},
    {'_id': '2', 'type': 'Wallet Funding', 'description': 'Wallet top-up', 'amount': 50000, 'status': 'Successful', 'createdAt': at(0, 9, 15), 'reference': 'R2'},
    {'_id': '3', 'type': 'Electricity Payment', 'description': 'Ikeja Electric', 'amount': 10100, 'status': 'Successful', 'createdAt': at(1, 18, 20), 'reference': 'R3'},
    {'_id': '4', 'type': 'Data Purchase', 'description': 'Airtel data', 'amount': 3000, 'status': 'Successful', 'createdAt': at(1, 13, 8), 'reference': 'R4'},
    {'_id': '5', 'type': 'Cable TV Subscription', 'description': 'DStv subscription', 'amount': 4500, 'status': 'Pending', 'createdAt': at(1, 8, 32), 'reference': 'R5'},
    {'_id': '6', 'type': 'Transfer Sent', 'description': 'Transfer to Tobi', 'amount': 5000, 'status': 'Failed', 'createdAt': at(2, 15, 0), 'reference': 'R6'},
  ];
  setUpAll(() async {
    mockPlatform({...demoPrefs, 'user_u1_user_transactions': jsonEncode(txs)});
    await loadFonts();
  });

  testWidgets('activity', (t) async =>
      shoot(t, '19_activity', const TransactionsScreen(userId: 'u1'), height: 1300));
  testWidgets('commission', (t) async => shoot(t, '20_commission',
      CommissionScreen(userId: 'u1', onBalanceUpdate: (_) {}), height: 1500));
  testWidgets('profile', (t) async => shoot(t, '21_profile', const SettingsScreen(), height: 1500));
}
