// lib/presentation/screens/auth/pin_lock_screen.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/biometric_service.dart';
import '../../../ui/ui.dart';

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
      backgroundColor: DP.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DPAvatar(name: _fullName.isNotEmpty ? _fullName : 'D', size: 56),
              const SizedBox(height: 18),
              Text(
                _fullName.isNotEmpty
                    ? 'Welcome back, ${_fullName.split(' ').first}.'
                    : 'Welcome back.',
                style: DP.display,
              ),
              const SizedBox(height: 8),
              Text(
                'Enter your 6-digit PIN to unlock.',
                style: DP.body.copyWith(color: DP.muted),
              ),
              const SizedBox(height: 20),
              DPPinDots(
                length: 6,
                filled: _pin.length,
                error: _errorMessage.isNotEmpty,
              ),
              if (_errorMessage.isNotEmpty)
                DPHelper(_errorMessage, color: DP.red, icon: DPIcons.alert),
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Center(child: CircularProgressIndicator()),
                ),
              const SizedBox(height: 20),
              DPKeypad(
                onDigit: _onDigitPressed,
                onBackspace: _onBackspacePressed,
                leftAction: _buildBiometricButton(),
              ),
              const SizedBox(height: 12),
              Center(
                child: DPTextLink(
                  label: 'Log out',
                  color: DP.muted,
                  onTap: () {
                    SharedPreferences.getInstance().then(
                      (prefs) => prefs.clear(),
                    );
                    Navigator.pushReplacementNamed(context, '/login');
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }



  Widget _buildBiometricButton() {
    if (!_biometricAvailable) return const SizedBox.shrink();
    return IconButton(
      tooltip: 'Use biometrics',
      onPressed: _isBiometricLoading ? null : _tryBiometric,
      icon: _isBiometricLoading
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(DPIcons.fingerprint, color: DP.green, size: 30),
    );
  }
}
