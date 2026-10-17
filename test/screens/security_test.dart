import 'package:flutter_test/flutter_test.dart';

import 'package:dalabapay/presentation/screens/change_pin_screen.dart';
import 'package:dalabapay/presentation/screens/change_password_screen.dart';
import 'package:dalabapay/presentation/screens/auth/pin_lock_screen.dart';
import 'package:dalabapay/presentation/screens/kyc/kyc_screen.dart';
import 'harness.dart';
import 'home_test.dart' show demoPrefs;

void main() {
  setUpAll(() async {
    mockPlatform(demoPrefs);
    await loadFonts();
  });

  testWidgets('change pin', (t) async => shoot(t, '30_change_pin',
      const ChangePinScreen(userId: 'u1', hasExistingPin: true, userEmail: 'a@b.c'), height: 1000));
  testWidgets('change password', (t) async =>
      shoot(t, '31_change_password', const ChangePasswordScreen(), height: 1100));
  testWidgets('pin lock', (t) async => shoot(t, '32_pin_lock', const PinLockScreen()));
  testWidgets('kyc', (t) async => shoot(t, '33_kyc', const KYCScreen(), height: 1700));
}
