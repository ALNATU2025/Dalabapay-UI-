import 'package:flutter_test/flutter_test.dart';

import 'package:dalabapay/presentation/screens/airtime/airtime_screen.dart';
import 'package:dalabapay/presentation/screens/data/data_screen.dart';
import 'package:dalabapay/presentation/screens/wallet/wallet_screen.dart';
import 'package:dalabapay/presentation/screens/send_money/send_money_screen.dart';
import 'package:dalabapay/presentation/screens/support/help_support_screen.dart';
import 'harness.dart';
import 'home_test.dart' show demoPrefs;

void main() {
  setUpAll(() async {
    mockPlatform(demoPrefs);
    await loadFonts();
  });

  testWidgets('airtime', (t) async => shoot(t, '11_airtime',
      AirtimeScreen(userId: 'u1', onBalanceUpdate: (_) {}), height: 1100));
  testWidgets('data', (t) async => shoot(t, '12_data',
      DataScreen(userId: 'u1', onBalanceUpdate: (_) {}), height: 1000));
  testWidgets('add money', (t) async => shoot(t, '13_add_money',
      WalletTopUpScreen(userId: 'u1', onBalanceUpdate: (_) {}), height: 1400));
  testWidgets('send money', (t) async => shoot(t, '14_send_money',
      const SendMoneyScreen(userId: 'u1'), height: 1000));
  testWidgets('help', (t) async => shoot(t, '15_help', const HelpSupportScreen(), height: 1300));
}
