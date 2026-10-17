import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:dalabapay/presentation/screens/dashboard/dashboard_screen.dart';
import 'package:dalabapay/presentation/screens/auth/pin_login_screen.dart';
import 'harness.dart';

final demoPrefs = <String, Object>{
  'token': 'demo-token',
  'userId': 'u1',
  'transactionPinSet': true,
  'user': jsonEncode({
    '_id': 'u1',
    'fullName': 'Adaeze Okafor',
    'email': 'adaeze.okafor@email.com',
    'transactionPinSet': true,
  }),
  'walletBalance': 124850.0,
  'commissionBalance': 2450.0,
};

void main() {
  setUpAll(() async {
    mockPlatform(demoPrefs);
    await loadFonts();
  });

  testWidgets('home', (t) async => shoot(t, '10_home', const DashboardScreen(), height: 900));
  testWidgets('pin login', (t) async => shoot(t, '05_pin_login', const PinLoginScreen()));
}
