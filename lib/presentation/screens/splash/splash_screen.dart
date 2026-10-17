// lib/presentation/screens/splash/splash_screen.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../onboarding/onboarding_screen.dart';
import '../auth/login_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _mainController;

  late Animation<double> _logo1Opacity;
  late Animation<double> _logo1Scale;
  late Animation<double> _logo1FadeOut;

  late Animation<double> _logo2Opacity;
  late Animation<double> _logo2Pulse;

  @override
  void initState() {
    super.initState();

    /// TOTAL = 10 SECONDS
    _mainController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    );

    // ----------------------------
    // SPLASH 1 (0s - 5s)
    // dabalogo.png
    // ----------------------------

    _logo1Opacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.00, 0.10, curve: Curves.easeOut),
      ),
    );

    _logo1Scale = Tween<double>(begin: 0.75, end: 1.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.00, 0.18, curve: Curves.elasticOut),
      ),
    );

    _logo1FadeOut = Tween<double>(begin: 1, end: 0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.42, 0.50, curve: Curves.easeInOut),
      ),
    );

    // ----------------------------
    // SPLASH 2 (5s - 10s)
    // dalabapay2.png
    // ----------------------------

    _logo2Opacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.50, 0.60, curve: Curves.easeOut),
      ),
    );

    _logo2Pulse = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.60, 1.00, curve: Curves.easeInOut),
      ),
    );

    _mainController.forward();

    // ✅ MODERN ROUTING: Check onboarding state after splash
    _checkRouteAfterSplash();
  }

  @override
  void dispose() {
    _mainController.dispose();
    super.dispose();
  }

  // ✅ Modern routing logic - checks onboarding state
  Future<void> _checkRouteAfterSplash() async {
    // Wait for splash screen animation to complete (10 seconds)
    await Future.delayed(const Duration(seconds: 10));

    if (!mounted) return;

    final prefs = await SharedPreferences.getInstance();
    final bool hasSeenOnboarding = prefs.getBool('hasSeenOnboarding') ?? false;

    // Modern routing logic:
    // First Launch: Splash -> Onboarding -> Login -> Home
    // Later Launches: Splash -> Login (or Home if already logged in)
    if (!hasSeenOnboarding) {
      // ✅ First time user → Go to Onboarding
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 800),
          pageBuilder: (_, __, ___) => const OnboardingScreen(),
          transitionsBuilder:
              (_, animation, __, child) =>
                  FadeTransition(opacity: animation, child: child),
        ),
      );
    } else {
      // ✅ Returning user → Go to Login
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 800),
          pageBuilder: (_, __, ___) => const LoginScreen(),
          transitionsBuilder:
              (_, animation, __, child) =>
                  FadeTransition(opacity: animation, child: child),
        ),
      );
    }
  }

  Widget _buildFirstSplash() {
    return FadeTransition(
      opacity: _logo1Opacity,
      child: FadeTransition(
        opacity: _logo1FadeOut,
        child: ScaleTransition(
          scale: _logo1Scale,
          child: Image.asset(
            'assets/dabalogo.png',
            width: 220,
            height: 220,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }

  Widget _buildSecondSplash() {
    return FadeTransition(
      opacity: _logo2Opacity,
      child: AnimatedBuilder(
        animation: _logo2Pulse,
        builder: (context, child) {
          return Transform.scale(scale: _logo2Pulse.value, child: child);
        },
        child: Image.asset(
          'assets/dalabapay2.png',
          width: 260,
          height: 260,
          fit: BoxFit.contain,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: AnimatedBuilder(
        animation: _mainController,
        builder: (context, child) {
          return Center(
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (_mainController.value <= 0.55) _buildFirstSplash(),
                if (_mainController.value >= 0.45) _buildSecondSplash(),
              ],
            ),
          );
        },
      ),
    );
  }
}
