// lib/presentation/screens/splash/splash_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  static const Duration _splashDuration = Duration(milliseconds: 2600);

  late AnimationController _mainController;
  late Animation<double> _fade;
  late Animation<double> _rise;
  late Animation<double> _halo;

  @override
  void initState() {
    super.initState();

    _mainController = AnimationController(vsync: this, duration: _splashDuration);

    _fade = CurvedAnimation(
      parent: _mainController,
      curve: const Interval(0.0, 0.35, curve: Curves.easeOut),
    );
    _rise = Tween<double>(begin: 14, end: 0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.0, 0.45, curve: Curves.easeOutCubic),
      ),
    );
    _halo = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.0, 0.7, curve: Curves.easeOutCubic),
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
    // Wait for the splash animation to complete
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

  Widget _dot(bool active) => AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        margin: const EdgeInsets.symmetric(horizontal: 3),
        width: active ? 7 : 6,
        height: active ? 7 : 6,
        decoration: BoxDecoration(
          color: active ? DP.green : DP.greenLine,
          shape: BoxShape.circle,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: DPTheme.overlay,
      child: Scaffold(
        backgroundColor: DP.bg,
        body: SafeArea(
          child: AnimatedBuilder(
            animation: _mainController,
            builder: (context, _) {
              final step = (_mainController.value * 3).floor().clamp(0, 2);
              return Column(
                children: [
                  Expanded(
                    child: Center(
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Transform.scale(
                            scale: _halo.value,
                            child: Container(
                              width: width * 0.62,
                              height: width * 0.62,
                              decoration: const BoxDecoration(
                                color: Color(0xFFF1F3EE),
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                          Opacity(
                            opacity: _fade.value,
                            child: Transform.translate(
                              offset: Offset(0, _rise.value),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const DPLogo(height: 40),
                                  const SizedBox(height: 18),
                                  Text(
                                    'Everyday payments. Extra possibilities.',
                                    style: DPText.bodyMuted.copyWith(fontSize: 14.5),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [_dot(step == 0), _dot(step == 1), _dot(step == 2)],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'YOUR EVERYDAY, SIMPLIFIED',
                    style: DPText.overline.copyWith(color: DP.muted, letterSpacing: 1.1),
                  ),
                  const SizedBox(height: 28),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
