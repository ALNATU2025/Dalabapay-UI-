// lib/presentation/screens/onboarding/onboarding_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  final List<OnboardingData> _onboardingData = const [
    OnboardingData(
      art: OnboardingArt.bills,
      eyebrow: 'LESS EFFORT. MORE LIVING.',
      title: 'Your everyday bills, beautifully simple.',
      description:
          'Airtime, data, electricity and more. All the payments you need, in one calm place.',
    ),
    OnboardingData(
      art: OnboardingArt.rewards,
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

  // ✅ Save state and navigate to Login (optionally straight on to sign up)
  Future<void> _finishOnboarding({bool toRegister = false}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hasSeenOnboarding', true);

    if (!mounted) return;

    final navigator = Navigator.of(context);
    navigator.pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 400),
        pageBuilder: (_, __, ___) => const LoginScreen(),
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
    if (toRegister) {
      navigator.pushNamed('/register');
    }
  }

  void _goToNextPage() {
    if (_selectedIndex < _onboardingData.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    } else {
      _finishOnboarding(toRegister: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _selectedIndex == _onboardingData.length - 1;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: DPTheme.overlay,
      child: Scaffold(
        backgroundColor: DP.bg,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(DP.gutter, 14, DP.gutter, 6),
                child: Row(
                  children: [
                    const DPLogo(height: 26),
                    const Spacer(),
                    DPLinkButton(
                      label: isLast ? 'Log in' : 'Skip',
                      onPressed: () => _finishOnboarding(),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: _onboardingData.length,
                  onPageChanged: (index) => setState(() => _selectedIndex = index),
                  itemBuilder: (context, index) => OnboardingContent(
                    data: _onboardingData[index],
                    index: index,
                    count: _onboardingData.length,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(DP.gutter, 8, DP.gutter, 0),
                child: DPButton(
                  label: isLast ? 'Create an account' : 'Continue',
                  icon: DPIcons.arrowRight,
                  onPressed: _goToNextPage,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(DP.gutter, 16, DP.gutter, 20),
                child: isLast
                    ? Text('Clear fees. Easy payments. Your pace.',
                        style: DPText.bodyMuted.copyWith(fontSize: 13.5))
                    : GestureDetector(
                        onTap: () => _finishOnboarding(),
                        child: Text.rich(
                          TextSpan(
                            style: DPText.bodyMuted.copyWith(fontSize: 13.5),
                            children: const [
                              TextSpan(text: 'Already have an account?  '),
                              TextSpan(
                                text: 'Log in',
                                style: TextStyle(color: DP.ink, fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum OnboardingArt { bills, rewards }

// Onboarding Data Model
class OnboardingData {
  final OnboardingArt art;
  final String eyebrow;
  final String title;
  final String description;

  const OnboardingData({
    required this.art,
    required this.eyebrow,
    required this.title,
    required this.description,
  });
}

// Onboarding Content Widget
class OnboardingContent extends StatelessWidget {
  final OnboardingData data;
  final int index;
  final int count;

  const OnboardingContent({
    super.key,
    required this.data,
    required this.index,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final artHeight = (c.maxHeight * 0.56).clamp(220.0, 400.0);
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: DP.gutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 10),
              SizedBox(
                height: artHeight,
                width: double.infinity,
                child: _OnboardingIllustration(art: data.art),
              ),
              const SizedBox(height: 26),
              Text(data.eyebrow, style: DPText.overline),
              const SizedBox(height: 10),
              Text(data.title, style: DPText.display.copyWith(fontSize: 28)),
              const SizedBox(height: 12),
              Text(data.description, style: DPText.bodyMuted.copyWith(fontSize: 15)),
              const SizedBox(height: 20),
              Row(
                children: List.generate(
                  count,
                  (i) => Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: AnimatedDot(isActive: i == index),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Illustration panel drawn in code (no image assets needed).
class _OnboardingIllustration extends StatelessWidget {
  final OnboardingArt art;
  const _OnboardingIllustration({required this.art});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(DP.rXl),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFEFF1EC), Color(0xFFE1E5DE)],
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth, h = c.maxHeight;
        return art == OnboardingArt.bills ? _bills(w, h) : _rewards(w, h);
      }),
    );
  }

  Widget _floatTile(DPIconData icon, Color bg, Color fg, double size) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(size * 0.3),
          boxShadow: const [
            BoxShadow(color: Color(0x1A102C68), blurRadius: 18, offset: Offset(0, 8)),
          ],
        ),
        alignment: Alignment.center,
        child: DPIcon(icon, size: size * 0.48, color: fg, strokeWidth: 2),
      );

  Widget _bills(double w, double h) {
    final phoneW = w * 0.34, phoneH = h * 0.62;
    return Stack(
      children: [
        // orbit ring
        Positioned(
          left: w * 0.12,
          top: h * 0.38,
          child: Container(
            width: w * 0.76,
            height: h * 0.26,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.all(Radius.elliptical(w * 0.38, h * 0.13)),
              border: Border.all(color: const Color(0x55168566), width: 1.4),
            ),
          ),
        ),
        // shadow
        Positioned(
          left: (w - phoneW * 1.1) / 2,
          top: h * 0.12 + phoneH - 6,
          child: Container(
            width: phoneW * 1.1,
            height: 18,
            decoration: BoxDecoration(
              color: const Color(0x22102C68),
              borderRadius: BorderRadius.circular(20),
            ),
          ),
        ),
        // phone
        Positioned(
          left: (w - phoneW) / 2,
          top: h * 0.12,
          child: Container(
            width: phoneW,
            height: phoneH,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(phoneW * 0.2),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF3557B0), Color(0xFF1C3B8E)],
              ),
              boxShadow: const [
                BoxShadow(color: Color(0x33102C68), blurRadius: 30, offset: Offset(0, 14)),
              ],
            ),
            alignment: Alignment.center,
            child: Container(
              width: phoneW * 0.5,
              height: phoneW * 0.5,
              decoration: const BoxDecoration(color: DP.green, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: DPIcon(DPIcons.check, size: phoneW * 0.28, color: Colors.white, strokeWidth: 3),
            ),
          ),
        ),
        Positioned(
          left: w * 0.22,
          top: h * 0.14,
          child: _floatTile(DPIcons.zap, const Color(0xFFDDF4E8), DP.green, w * 0.12),
        ),
        Positioned(
          right: w * 0.16,
          top: h * 0.26,
          child: _floatTile(DPIcons.wifi, const Color(0xFFE6F6EE), DP.green, w * 0.13),
        ),
        Positioned(
          right: w * 0.2,
          top: h * 0.6,
          child: _floatTile(DPIcons.phone, Colors.white, DP.green, w * 0.14),
        ),
        Positioned(
          left: w * 0.14,
          top: h * 0.58,
          child: Container(
            width: 12,
            height: 12,
            decoration: const BoxDecoration(color: Color(0xFF5BB592), shape: BoxShape.circle),
          ),
        ),
      ],
    );
  }

  Widget _rewards(double w, double h) {
    final walletW = w * 0.56, walletH = h * 0.36;
    Widget coin(double s) => Container(
          width: s,
          height: s * 0.42,
          decoration: BoxDecoration(
            color: const Color(0xFF7DC4A6),
            borderRadius: BorderRadius.all(Radius.elliptical(s / 2, s * 0.21)),
            border: Border.all(color: const Color(0xFF4FA584), width: 1.5),
          ),
        );
    return Stack(
      children: [
        // pedestal
        Positioned(
          left: w * 0.18,
          bottom: h * 0.08,
          child: Container(
            width: w * 0.64,
            height: h * 0.16,
            decoration: BoxDecoration(
              color: const Color(0xFFF6F3EC),
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [
                BoxShadow(color: Color(0x14000000), blurRadius: 20, offset: Offset(0, 10)),
              ],
            ),
          ),
        ),
        // wallet
        Positioned(
          left: (w - walletW) / 2,
          bottom: h * 0.18,
          child: Container(
            width: walletW,
            height: walletH,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF3557B0), Color(0xFF1A3684)],
              ),
              boxShadow: const [
                BoxShadow(color: Color(0x33102C68), blurRadius: 26, offset: Offset(0, 12)),
              ],
            ),
            child: Align(
              alignment: const Alignment(0.95, 0),
              child: Container(
                width: walletW * 0.3,
                height: walletH * 0.36,
                decoration: BoxDecoration(
                  color: const Color(0xFF2A4BA2),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0x334C6FC8)),
                ),
                alignment: Alignment.center,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: const BoxDecoration(color: Color(0xFF8DA6E6), shape: BoxShape.circle),
                ),
              ),
            ),
          ),
        ),
        // coins rising out of the wallet
        for (var i = 0; i < 7; i++)
          Positioned(
            left: w * 0.36 + i * w * 0.035,
            bottom: h * 0.44 + i * h * 0.065,
            child: Transform.rotate(angle: -0.35 + i * 0.08, child: coin(w * (0.1 - i * 0.004))),
          ),
        Positioned(
          right: w * 0.2,
          top: h * 0.08,
          child: const DPIcon(DPIcons.sparkles, size: 22, color: DP.green),
        ),
      ],
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
      width: isActive ? 22 : 8,
      decoration: BoxDecoration(
        color: isActive ? DP.green : DP.border,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}
