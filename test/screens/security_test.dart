import 'package:flutter_test/flutter_test.dart';

import 'package:dalabapay/presentation/screens/change_pin_screen.dart';
import 'package:dalabapay/presentation/screens/change_password_screen.dart';
import 'package:dalabapay/presentation/screens/auth/pin_lock_screen.dart';
import 'package:dalabapay/presentation/screens/kyc/kyc_screen.dart';
import 'package:dalabapay/presentation/screens/user_disputes_page.dart';
import 'package:dalabapay/presentation/screens/transaction_validation_page.dart';
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
  testWidgets('disputes', (t) async => shoot(t, '34_disputes', const UserDisputesPage(), settle: const Duration(seconds: 3)));
  testWidgets('validation', (t) async =>
      shoot(t, '35_validation', const TransactionValidationPage(), height: 1300, settle: const Duration(seconds: 3)));
}
