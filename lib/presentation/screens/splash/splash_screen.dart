// lib/presentation/screens/splash/splash_screen.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../ui/ui.dart';
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
  late Animation<double> _fade;
  late Animation<double> _scale;

  static const _splashDuration = Duration(milliseconds: 2600);

  @override
  void initState() {
    super.initState();
    _mainController = AnimationController(
      vsync: this,
      duration: _splashDuration,
    );
    _fade = CurvedAnimation(
      parent: _mainController,
      curve: const Interval(0.0, 0.35, curve: Curves.easeOut),
    );
    _scale = Tween<double>(begin: 0.94, end: 1.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.0, 0.45, curve: Curves.easeOutCubic),
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
    await Future.delayed(_splashDuration);

    if (!mounted) return;

    final prefs = await SharedPreferences.getInstance();
    final bool hasSeenOnboarding = prefs.getBool('hasSeenOnboarding') ?? false;

    if (!mounted) return;

    // First Launch: Splash -> Onboarding -> Login -> Home
    // Later Launches: Splash -> Login (or Home if already logged in)
    if (!hasSeenOnboarding) {
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 500),
          pageBuilder: (_, __, ___) => const OnboardingScreen(),
          transitionsBuilder: (_, animation, __, child) =>
              FadeTransition(opacity: animation, child: child),
        ),
      );
    } else {
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 500),
          pageBuilder: (_, __, ___) => const LoginScreen(),
          transitionsBuilder: (_, animation, __, child) =>
              FadeTransition(opacity: animation, child: child),
        ),
      );
    }
  }

  /// Loader from the design: navy dot · green pill · light-green dot,
  /// the pill travelling between them.
  Widget _dots() {
    return AnimatedBuilder(
      animation: _mainController,
      builder: (context, _) {
        final active = ((_mainController.value * 6).floor() % 3);
        const colors = [DP.navy, DP.green, DP.greenSoft];
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final on = i == active;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: on ? 30 : 10,
              height: 10,
              decoration: BoxDecoration(
                color: colors[i],
                borderRadius: BorderRadius.circular(5),
              ),
            );
          }),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    return Scaffold(
      backgroundColor: DP.surface,
      body: Stack(
        children: [
          Positioned(
            top: 0,
            right: 0,
            width: MediaQuery.of(context).size.width * 0.75,
            child: DPWaves(top: true, height: h * 0.18),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: DPWaves(height: h * 0.28),
          ),
          SafeArea(
            child: Column(
              children: [
                const Spacer(flex: 5),
                FadeTransition(
                  opacity: _fade,
                  child: ScaleTransition(
                    scale: _scale,
                    child: Column(
                      children: [
                        const DPLogoMark(size: 110),
                        const SizedBox(height: 20),
                        const Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: 'Dalaba',
                                style: TextStyle(color: DP.navy),
                              ),
                              TextSpan(
                                text: 'pay',
                                style: TextStyle(color: DP.green),
                              ),
                            ],
                          ),
                          style: TextStyle(
                            fontSize: 44,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -1,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Smart Life Fast Pay',
                          style: DP.body.copyWith(
                            color: DP.navy,
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 40),
                _dots(),
                const Spacer(flex: 6),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
