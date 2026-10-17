// lib/presentation/screens/auth/pin_lock_screen.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/biometric_service.dart';

class PinLockScreen extends StatefulWidget {
  const PinLockScreen({super.key});

  @override
  State<PinLockScreen> createState() => _PinLockScreenState();
}

class _PinLockScreenState extends State<PinLockScreen> {
  String _pin = '';
  bool _isLoading = false;
  bool _isBiometricLoading = false;
  String _errorMessage = '';
  String _fullName = '';
  String _userId = '';
  bool _biometricAvailable = false;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _checkBiometric();
  }

  Future<void> _loadUserData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _userId = prefs.getString('userId') ?? '';

      final userString = prefs.getString('user');
      if (userString != null) {
        final userData = jsonDecode(userString) as Map<String, dynamic>;
        _fullName = userData['fullName']?.toString() ?? 'User';
      }

      setState(() {});
    } catch (e) {
      debugPrint('⚠️ Load user error: $e');
    }
  }

  Future<void> _checkBiometric() async {
    try {
      _biometricAvailable = await biometricService.isBiometricAvailable();
      setState(() {});
    } catch (_) {}
  }

  void _onDigitPressed(String digit) {
    if (_pin.length >= 6) return;
    setState(() {
      _pin += digit;
      _errorMessage = '';
    });
    if (_pin.length == 6) _verifyPin();
  }

  void _onBackspacePressed() {
    setState(() {
      _pin = _pin.isNotEmpty ? _pin.substring(0, _pin.length - 1) : '';
    });
  }

  Future<void> _verifyPin() async {
    if (_pin.length != 6) return;

    setState(() => _isLoading = true);

    try {
      final response = await AuthService.loginWithPin(
        userId: _userId,
        pin: _pin,
      );

      if (!mounted) return;

      if (response['success'] == true) {
        // ✅ PIN correct - go back
        await AuthService.updateLastActivity();
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('autoLogout');
        await prefs.reload();

        if (mounted) {
          Navigator.pop(context, true);
        }
      } else {
        setState(() {
          _errorMessage = response['message'] ?? 'Invalid PIN';
          _pin = '';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error: ${e.toString()}';
        _pin = '';
        _isLoading = false;
      });
    }
  }

  Future<void> _tryBiometric() async {
    if (!_biometricAvailable || _isBiometricLoading) return;

    setState(() => _isBiometricLoading = true);

    try {
      final success = await biometricService.authenticate(
        reason: 'Unlock your account',
        biometricOnly: false,
      );

      if (success && mounted) {
        await AuthService.updateLastActivity();
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('autoLogout');
        if (mounted) Navigator.pop(context, true);
      }
    } catch (_) {}

    if (mounted) setState(() => _isBiometricLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 40,
                backgroundColor: const Color(0xFF102C68),
                child: Text(
                  _fullName.isNotEmpty ? _fullName[0].toUpperCase() : 'U',
                  style: const TextStyle(fontSize: 30, color: Colors.white),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _fullName.isNotEmpty
                    ? 'Welcome back, $_fullName'
                    : 'Welcome back',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF14263D),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Enter your PIN to unlock',
                style: TextStyle(
                  fontSize: 14,
                  color: const Color(0xFF728078),
                ),
              ),

              const SizedBox(height: 32),

              // PIN Dots
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(6, (index) {
                  final isFilled = index < _pin.length;
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color:
                          isFilled
                              ? const Color(0xFF102C68)
                              : Colors.grey.shade200,
                      border: Border.all(
                        color:
                            isFilled
                                ? const Color(0xFF102C68)
                                : Colors.grey.shade300,
                        width: 1.5,
                      ),
                    ),
                  );
                }),
              ),

              const SizedBox(height: 8),

              if (_errorMessage.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    _errorMessage,
                    style: TextStyle(
                      color: Colors.red.shade600,
                      fontSize: 13,
                    ),
                  ),
                ),

              const SizedBox(height: 24),

              // Number Pad
              Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: ['1', '2', '3'].map(_buildDigitButton).toList(),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: ['4', '5', '6'].map(_buildDigitButton).toList(),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: ['7', '8', '9'].map(_buildDigitButton).toList(),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildBiometricButton(),
                      _buildDigitButton('0'),
                      _buildBackspaceButton(),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 24),

              TextButton(
                onPressed: () {
                  SharedPreferences.getInstance().then(
                    (prefs) => prefs.clear(),
                  );
                  Navigator.pushReplacementNamed(context, '/login');
                },
                child: Text(
                  'Logout',
                  style: TextStyle(
                    color: Colors.grey.shade400,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDigitButton(String digit) {
    return GestureDetector(
      onTap: () => _onDigitPressed(digit),
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(color: Colors.grey.shade200, width: 1),
        ),
        child: Center(
          child: Text(
            digit,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF14263D),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBackspaceButton() {
    return GestureDetector(
      onTap: _onBackspacePressed,
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.grey.shade100,
          border: Border.all(color: Colors.grey.shade300, width: 1),
        ),
        child: const Icon(Icons.backspace, size: 24, color: Color(0xFF14263D)),
      ),
    );
  }

  Widget _buildBiometricButton() {
    if (!_biometricAvailable) {
      return Opacity(
        opacity: 0.3,
        child: Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.grey.shade100,
          ),
          child: const Icon(Icons.fingerprint, size: 28, color: Colors.grey),
        ),
      );
    }

    return GestureDetector(
      onTap: _tryBiometric,
      child: Container(
        width: 64,
        height: 64,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [Color(0xFF5BB592), Color(0xFF102C68)],
          ),
        ),
        child:
            _isBiometricLoading
                ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
                : const Icon(Icons.fingerprint, size: 28, color: Colors.white),
      ),
    );
  }
}
