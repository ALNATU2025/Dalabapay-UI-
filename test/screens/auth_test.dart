import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dalabapay/presentation/screens/splash/splash_screen.dart';
import 'package:dalabapay/presentation/screens/onboarding/onboarding_screen.dart';
import 'package:dalabapay/presentation/screens/auth/login_screen.dart';
import 'package:dalabapay/presentation/screens/auth/register_screen.dart';
import 'harness.dart';

void main() {
  setUpAll(() async {
    mockPlatform();
    await loadFonts();
  });

  testWidgets('splash', (t) async {
    await shoot(t, '01_splash', const SplashScreen());
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 5));
  });
  testWidgets('onboarding', (t) async => shoot(t, '02_onboarding', const OnboardingScreen()));
  testWidgets('login', (t) async => shoot(t, '03_login', const LoginScreen()));
  testWidgets('register', (t) async => shoot(t, '04_register', const RegisterScreen(), height: 1500));
}
