// lib/core/widgets/auth_guard.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';

class AuthGuard extends StatefulWidget {
  final Widget child;
  final Widget? loadingWidget;

  const AuthGuard({super.key, required this.child, this.loadingWidget});

  @override
  State<AuthGuard> createState() => _AuthGuardState();
}

class _AuthGuardState extends State<AuthGuard> {
  bool _isLoading = true;
  bool _isAuthenticated = false;

  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    try {
      // ✅ First check if AuthService says we're authenticated
      if (AuthService.isAuthenticated) {
        _isAuthenticated = true;
        _isLoading = false;
        if (mounted) setState(() {});
        return;
      }

      // ✅ Check storage directly
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      final userId = prefs.getString('userId');

      if (token != null &&
          token.isNotEmpty &&
          userId != null &&
          userId.isNotEmpty) {
        // Try to validate token
        final authState = await ApiService.checkAuthState();
        if (authState['isAuthenticated'] == true) {
          _isAuthenticated = true;
          _isLoading = false;
          if (mounted) setState(() {});
          return;
        }
      }

      // ✅ Not authenticated - redirect to login
      _isAuthenticated = false;
      _isLoading = false;

      if (mounted) {
        setState(() {});
        _navigateToLogin('Please login to continue');
      }
    } catch (e) {
      debugPrint('❌ Auth guard error: $e');
      _isAuthenticated = false;
      _isLoading = false;

      if (mounted) {
        setState(() {});
        _navigateToLogin('Authentication error. Please login again.');
      }
    }
  }

  void _navigateToLogin(String message) {
    if (!mounted) return;

    // Show professional session expired dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: [
                Icon(Icons.lock_outline, color: Colors.orange.shade700),
                const SizedBox(width: 8),
                const Text('Session Expired'),
              ],
            ),
            content: Text(message),
            actions: [
              ElevatedButton(
                onPressed: () {
                  if (Navigator.canPop(context)) {
                    if (Navigator.canPop(context)) {
                      Navigator.pop(context);
                    } else {
                      // Navigate to a fallback screen
                      Navigator.pushReplacementNamed(context, '/home');
                    }
                  } else {
                    // Navigate to a fallback screen
                    Navigator.pushReplacementNamed(context, '/home');
                  }
                  Navigator.pushNamedAndRemoveUntil(
                    context,
                    '/login',
                    (route) => false,
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF15368A),
                  foregroundColor: Colors.white,
                ),
                child: const Text('Login'),
              ),
            ],
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return widget.loadingWidget ??
          const Scaffold(
            body: Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF15368A)),
              ),
            ),
          );
    }

    if (!_isAuthenticated) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return widget.child;
  }
}
