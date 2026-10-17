// lib/presentation/screens/onboarding/onboarding_screen.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../ui/ui.dart';
import '../auth/login_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _selectedIndex = 0;
  final PageController _pageController = PageController();

  final List<OnboardingData> _onboardingData = [
    OnboardingData(
      image: 'assets/images/onboarding_bills.jpg',
      eyebrow: 'LESS EFFORT. MORE LIVING.',
      title: 'Your everyday bills, beautifully simple.',
      description:
          'Airtime, data, electricity and more. All the payments you need, in one calm place.',
    ),
    OnboardingData(
      image: 'assets/images/onboarding_earn.jpg',
      eyebrow: 'SMALL PAYMENTS. EXTRA VALUE.',
      title: 'A little more back, every time.',
      description:
          'Earn commission on eligible payments. Track your earnings and move them to your wallet.',
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _markSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hasSeenOnboarding', true);
  }

  // ✅ Save state and navigate to Login
  Future<void> _finishOnboarding() async {
    await _markSeen();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 400),
        pageBuilder: (_, __, ___) => const LoginScreen(),
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  // Save state and go straight to sign-up
  Future<void> _createAccount() async {
    await _markSeen();
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/register');
  }

  void _goToNextPage() {
    if (_selectedIndex < _onboardingData.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _createAccount();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _selectedIndex == _onboardingData.length - 1;
    return Scaffold(
      backgroundColor: DP.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 16, 4),
              child: Row(
                children: [
                  const DPWordmark(height: 30),
                  const Spacer(),
                  DPTextLink(
                    label: isLast ? 'Log in' : 'Skip',
                    onTap: _finishOnboarding,
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _onboardingData.length,
                onPageChanged: (index) {
                  setState(() {
                    _selectedIndex = index;
                  });
                },
                itemBuilder: (context, index) {
                  return OnboardingContent(data: _onboardingData[index]);
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
              child: Row(
                children: List.generate(
                  _onboardingData.length,
                  (index) => Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: AnimatedDot(isActive: _selectedIndex == index),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: DPButton(
                label: isLast ? 'Create an account' : 'Continue',
                icon: DPIcons.forward,
                onPressed: _goToNextPage,
              ),
            ),
            const SizedBox(height: 18),
            if (isLast)
              const Text(
                'Clear fees. Easy payments. Your pace.',
                style: DP.caption,
              )
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Already have an account? ', style: DP.caption),
                  GestureDetector(
                    onTap: _finishOnboarding,
                    child: Text(
                      'Log in',
                      style: DP.caption.copyWith(
                        color: DP.green,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

// Onboarding Data Model
class OnboardingData {
  final String image;
  final String eyebrow;
  final String title;
  final String description;

  OnboardingData({
    required this.image,
    required this.eyebrow,
    required this.title,
    required this.description,
  });
}

// Onboarding Content Widget
class OnboardingContent extends StatelessWidget {
  final OnboardingData data;

  const OnboardingContent({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(DP.rXl),
            child: AspectRatio(
              aspectRatio: 708 / 660,
              child: Image.asset(
                data.image,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  color: DP.mint,
                  alignment: Alignment.center,
                  child: const DPLogoMark(size: 96),
                ),
              ),
            ),
          ),
          const SizedBox(height: 28),
          Text(
            data.eyebrow,
            style: DP.tiny.copyWith(color: DP.green, fontSize: 12),
          ),
          const SizedBox(height: 10),
          Text(data.title, style: DP.display.copyWith(fontSize: 30)),
          const SizedBox(height: 12),
          Text(
            data.description,
            style: DP.body.copyWith(color: DP.muted, height: 1.5),
          ),
        ],
      ),
    );
  }
}

// Animated Dot Widget
class AnimatedDot extends StatelessWidget {
  final bool isActive;

  const AnimatedDot({super.key, required this.isActive});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      height: 4,
      width: isActive ? 24 : 6,
      decoration: BoxDecoration(
        color: isActive ? DP.green : DP.border,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}
