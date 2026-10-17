// lib/presentation/screens/splash/simple_splash_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

import '../../../core/theme/app_theme.dart';
import '../../../core/services/api_service.dart';

class SimpleAnimatedSplashScreen extends StatefulWidget {
  const SimpleAnimatedSplashScreen({super.key});

  @override
  State<SimpleAnimatedSplashScreen> createState() => _SimpleAnimatedSplashScreenState();
}

class _SimpleAnimatedSplashScreenState extends State<SimpleAnimatedSplashScreen>
    with SingleTickerProviderStateMixin {
  
  late AnimationController _controller;
  bool _showSecondLogo = false;
  double _pulseSize = 1.0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1800),
      vsync: this,
    );
    
    _startAnimation();
  }

  void _startAnimation() async {
    // 0.0s - 0.3s: Fade in
    _controller.forward();
    
    // 0.3s - 0.8s: Transition to second logo
    await Future.delayed(const Duration(milliseconds: 800));
    if (mounted) {
      setState(() => _showSecondLogo = true);
    }
    
    // 0.8s - 1.4s: Pulse effect
    for (int i = 0; i < 2; i++) {
      await Future.delayed(const Duration(milliseconds: 150));
      if (mounted) {
        setState(() => _pulseSize = 1.1);
        await Future.delayed(const Duration(milliseconds: 150));
        setState(() => _pulseSize = 1.0);
      }
    }
    
    // 1.4s - 1.8s: Navigate
    await Future.delayed(const Duration(milliseconds: 400));
    if (mounted) {
      final prefs = await SharedPreferences.getInstance();
      final hasSeenOnboarding = prefs.getBool('hasSeenOnboarding') ?? false;
      final token = await ApiService.getSafeToken();
      final isAuthenticated = token != null && await ApiService.verifyToken();
      
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: _showSecondLogo
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Colors.white, Color(0xFFF5F5F5)],
                )
              : LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppTheme.secondaryColor, AppTheme.primaryColor],
                ),
        ),
        child: Center(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Opacity(
                opacity: _controller.value,
                child: Transform.scale(
                  scale: 0.5 + (_controller.value * 0.5),
                  child: _showSecondLogo ? _buildSecondLogo() : _buildFirstLogo(),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildFirstLogo() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 150,
          height: 150,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 20,
                spreadRadius: 5,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(30),
            child: Image.asset(
              'assets/dabalogo.png',
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                return const Center(
                  child: Text(
                    'D',
                    style: TextStyle(
                      fontSize: 70,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF219C7E),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 30),
        Text(
          'DALABAPAY',
          style: GoogleFonts.inter(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.white,
            letterSpacing: 2,
          ),
        ),
      ],
    );
  }

  Widget _buildSecondLogo() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Transform.scale(
          scale: _pulseSize,
          child: Container(
            width: 180,
            height: 180,
            decoration: BoxDecoration(
              gradient: AppTheme.cardGradient,
              borderRadius: BorderRadius.circular(35),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primaryColor.withOpacity(0.3),
                  blurRadius: 30,
                  spreadRadius: _pulseSize > 1 ? 10 : 0,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(35),
              child: Image.asset(
                'assets/dalabapay2.png',
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return const Center(
                    child: Text(
                      'D',
                      style: TextStyle(
                        fontSize: 80,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: 30),
        RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: 'Dalaba',
                style: GoogleFonts.inter(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.secondaryColor,
                ),
              ),
              TextSpan(
                text: 'pay',
                style: GoogleFonts.inter(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primaryColor,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Secure • Fast • Reliable',
          style: GoogleFonts.inter(
            fontSize: 14,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }
}