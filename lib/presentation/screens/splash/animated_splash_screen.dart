// lib/presentation/screens/splash/animated_splash_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/services/api_service.dart';

class AnimatedSplashScreen extends StatefulWidget {
  const AnimatedSplashScreen({super.key});

  @override
  State<AnimatedSplashScreen> createState() => _AnimatedSplashScreenState();
}

class _AnimatedSplashScreenState extends State<AnimatedSplashScreen>
    with SingleTickerProviderStateMixin {
  
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<double> _waveAnimation;
  late Animation<Offset> _slideAnimation;
  
  bool _showSecondScreen = false;
  double _pulseSize = 1.0;
  double _rippleSize = 0;
  double _rippleOpacity = 0;
  
  // Timeline timers
  Timer? _transitionTimer;
  Timer? _pulseTimer;
  Timer? _rippleTimer;
  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _startSplashSequence();
  }

  void _setupAnimations() {
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1800),
      vsync: this,
    );
    
    // Fade animation
    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.3, curve: Curves.easeIn),
    );
    
    // Scale animation for logo
    _scaleAnimation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.3, curve: Curves.elasticOut),
      ),
    );
    
    // Wave animation
    _waveAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.3, 0.8, curve: Curves.easeInOut),
      ),
    );
    
    // Slide animation for second screen
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.3, 0.8, curve: Curves.easeOutCubic),
      ),
    );
  }

  void _startSplashSequence() async {
    // Start animation
    _controller.forward();
    
    // 0.3s - 0.8s: Transition to second screen
    _transitionTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) {
        setState(() {
          _showSecondScreen = true;
        });
      }
    });
    
    // 0.8s - 1.4s: Pulse and ripple effects
    _pulseTimer = Timer(const Duration(milliseconds: 1000), () {
      if (mounted) {
        // Pulse animation
        for (int i = 0; i < 2; i++) {
          Future.delayed(Duration(milliseconds: 150 * i), () {
            if (mounted) setState(() => _pulseSize = 1.15);
            Future.delayed(const Duration(milliseconds: 150), () {
              if (mounted) setState(() => _pulseSize = 1.0);
            });
          });
        }
        
        // Ripple effect
        for (int i = 0; i < 3; i++) {
          Future.delayed(Duration(milliseconds: 200 * i), () {
            if (mounted) {
              setState(() {
                _rippleSize = 1.0;
                _rippleOpacity = 0.5;
              });
              Future.delayed(const Duration(milliseconds: 400), () {
                if (mounted) {
                  setState(() {
                    _rippleSize = 0;
                    _rippleOpacity = 0;
                  });
                }
              });
            }
          });
        }
      }
    });
    
    // 1.4s - 1.8s: Wait and navigate
    _dismissTimer = Timer(const Duration(milliseconds: 2800), () {
      _navigateToNextScreen();
    });
  }

  Future<void> _navigateToNextScreen() async {
    final prefs = await SharedPreferences.getInstance();
    final hasSeenOnboarding = prefs.getBool('hasSeenOnboarding') ?? false;
    final token = await ApiService.getSafeToken();
    final isAuthenticated = token != null && await ApiService.verifyToken();
    
    if (mounted) {
      if (!hasSeenOnboarding) {
        Navigator.pushReplacementNamed(context, '/onboarding');
      } else if (isAuthenticated) {
        Navigator.pushReplacementNamed(context, '/dashboard');
      } else {
        Navigator.pushReplacementNamed(context, '/login');
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _transitionTimer?.cancel();
    _pulseTimer?.cancel();
    _rippleTimer?.cancel();
    _dismissTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // First Splash Screen
          if (!_showSecondScreen)
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Animated Logo
                  ScaleTransition(
                    scale: _scaleAnimation,
                    child: FadeTransition(
                      opacity: _fadeAnimation,
                      child: Container(
                        width: 200,
                        height: 200,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(40),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(40),
                          child: Image.asset(
                            'assets/dabalogo.png',
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                color: Colors.grey[100],
                                child: const Center(
                                  child: Text(
                                    'DALABA',
                                    style: TextStyle(
                                      fontSize: 30,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF219C7E),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                  // Animated Wordmark with letter bounce
                  _buildAnimatedWordmark(),
                  const SizedBox(height: 20),
                  // Animated Wave Effect
                  if (_waveAnimation.value > 0)
                    _buildWaveEffect(),
                ],
              ),
            ),
          
          // Second Splash Screen
          if (_showSecondScreen)
            SlideTransition(
              position: _slideAnimation,
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Ripple Effect Background
                      if (_rippleSize > 0)
                        Positioned.fill(
                          child: Center(
                            child: Container(
                              width: 300 * _rippleSize,
                              height: 300 * _rippleSize,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppTheme.primaryColor.withOpacity(_rippleOpacity),
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                        ),
                      
                      // Animated Logo with Pulse
                      Transform.scale(
                        scale: _pulseSize,
                        child: Container(
                          width: 180,
                          height: 180,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(40),
                            boxShadow: _pulseSize > 1
                                ? [
                                    BoxShadow(
                                      color: AppTheme.primaryColor.withOpacity(0.5),
                                      blurRadius: 30,
                                      spreadRadius: 10,
                                    ),
                                  ]
                                : [],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(40),
                            child: Image.asset(
                              'assets/dalabapay2.png',
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                  color: Colors.grey[100],
                                  child: const Center(
                                    child: Text(
                                      'D',
                                      style: TextStyle(
                                        fontSize: 80,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF219C7E),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 30),
                      // Animated Brand Name
                      TweenAnimationBuilder(
                        tween: Tween<double>(begin: 0, end: 1),
                        duration: const Duration(milliseconds: 500),
                        builder: (context, value, child) {
                          return Opacity(
                            opacity: value,
                            child: Transform.translate(
                              offset: Offset(0, 20 * (1 - value)),
                              child: RichText(
                                text: TextSpan(
                                  children: [
                                    TextSpan(
                                      text: 'Dalaba',
                                      style: GoogleFonts.inter(
                                        fontSize: 32,
                                        fontWeight: FontWeight.w700,
                                        color: AppTheme.secondaryColor,
                                      ),
                                    ),
                                    TextSpan(
                                      text: 'pay',
                                      style: GoogleFonts.inter(
                                        fontSize: 32,
                                        fontWeight: FontWeight.w700,
                                        color: AppTheme.primaryColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      TweenAnimationBuilder(
                        tween: Tween<double>(begin: 0, end: 1),
                        duration: const Duration(milliseconds: 600),
                        builder: (context, value, child) {
                          return Opacity(
                            opacity: value,
                            child: Text(
                              'Secure • Fast • Reliable',
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                color: Colors.grey[500],
                                letterSpacing: 1,
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAnimatedWordmark() {
    const String text = 'DALABAPAY';
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: text.split('').asMap().entries.map((entry) {
        int index = entry.key;
        String letter = entry.value;
        
        return TweenAnimationBuilder(
          tween: Tween<double>(begin: 0, end: 1),
          duration: Duration(milliseconds: 100 + (index * 30)),
          builder: (context, value, child) {
            return Transform.scale(
              scale: value,
              child: Opacity(
                opacity: value,
                child: Text(
                  letter,
                  style: GoogleFonts.inter(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.secondaryColor,
                    letterSpacing: 2,
                  ),
                ),
              ),
            );
          },
        );
      }).toList(),
    );
  }

  Widget _buildWaveEffect() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 100,
      child: Container(
        height: 3,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              AppTheme.primaryColor,
              AppTheme.secondaryColor,
              AppTheme.primaryColor,
            ],
          ),
        ),
        child: AnimatedBuilder(
          animation: _waveAnimation,
          builder: (context, child) {
            return Transform.translate(
              offset: Offset(-300 + (600 * _waveAnimation.value), 0),
              child: Container(
                width: 300,
                height: 3,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.primaryColor.withOpacity(0),
                      AppTheme.primaryColor,
                      AppTheme.primaryColor.withOpacity(0),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}