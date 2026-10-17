import 'package:flutter_test/flutter_test.dart';

import 'package:dalabapay/presentation/screens/airtime/airtime_screen.dart';
import 'package:dalabapay/presentation/screens/internet/internet_screen.dart';
import 'package:dalabapay/presentation/screens/wallet/wallet_screen.dart';
import 'package:dalabapay/presentation/screens/send_money/send_money_screen.dart';
import 'package:dalabapay/presentation/screens/support/help_support_screen.dart';
import 'package:dalabapay/presentation/screens/electricity/electricity_screen.dart';
import 'package:dalabapay/presentation/screens/cabletv/cabletv_screen.dart';
import 'package:dalabapay/presentation/screens/international_airtime/international_airtime_screen.dart';
import 'package:dalabapay/presentation/screens/education/education_screen.dart';
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
      InternetScreen(userId: 'u1', onBalanceUpdate: (_) {}), height: 1000));
  testWidgets('add money', (t) async => shoot(t, '13_add_money',
      WalletTopUpScreen(userId: 'u1', onBalanceUpdate: (_) {}), height: 1400));
  testWidgets('send money', (t) async => shoot(t, '14_send_money',
      const SendMoneyScreen(userId: 'u1'), height: 1000));
  testWidgets('help', (t) async => shoot(t, '15_help', const HelpSupportScreen(), height: 1300));
  testWidgets('electricity', (t) async => shoot(t, '16_electricity',
      ElectricityScreen(userId: 'u1', onBalanceUpdate: (_) {}), height: 1300));
  testWidgets('cable', (t) async => shoot(t, '17_cable',
      CableTVScreen(userId: 'u1', onBalanceUpdate: (_) {}), height: 1200));
  testWidgets('intl', (t) async => shoot(t, '18_intl',
      IntlAirtimeScreen(userId: 'u1', onBalanceUpdate: (_) {}), height: 900));
  testWidgets('education', (t) async => shoot(t, '22_education',
      EducationScreen(userId: 'u1', onBalanceUpdate: (_) {}), height: 1000));
}
