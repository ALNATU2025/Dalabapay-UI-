// lib/presentation/screens/auth/pin_lock_screen.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
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
    final first = _fullName.trim().split(' ').first;
    return Scaffold(
        backgroundColor: DP.bg,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: DP.gutter),
            child: Column(
              children: [
                const SizedBox(height: 36),
                DPAvatar(name: _fullName.isEmpty ? 'User' : _fullName, size: 64),
                const SizedBox(height: 16),
                Text(first.isEmpty ? 'Welcome back' : 'Welcome back, $first',
                    style: DPText.title, textAlign: TextAlign.center),
                const SizedBox(height: 6),
                Text('Enter your 6-digit PIN to unlock',
                    style: DPText.bodyMuted, textAlign: TextAlign.center),
                const SizedBox(height: 28),
                DPCodeBoxes(
                  length: 6,
                  value: _pin,
                  obscure: true,
                  error: _errorMessage.isNotEmpty,
                  boxSize: 48,
                ),
                SizedBox(
                  height: 40,
                  child: Center(
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: DP.green),
                          )
                        : Text(_errorMessage,
                            style: DPText.small.copyWith(color: DP.danger), textAlign: TextAlign.center),
                  ),
                ),
                const Spacer(),
                DPKeypad(
                  onDigit: _isLoading ? (_) {} : _onDigitPressed,
                  onBackspace: _onBackspacePressed,
                  extraKey: _biometricAvailable ? _buildBiometricButton() : null,
                ),
                const SizedBox(height: 8),
                DPLinkButton(
                  label: 'Not you? Sign out',
                  color: DP.muted,
                  onPressed: () {
                    SharedPreferences.getInstance().then((prefs) => prefs.clear());
                    Navigator.pushReplacementNamed(context, '/login');
                  },
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
    );
  }



  Widget _buildBiometricButton() {
    return GestureDetector(
      onTap: _isBiometricLoading ? null : _tryBiometric,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: double.infinity,
        height: 58,
        child: Center(
          child: _isBiometricLoading
              ? const SizedBox(
                  width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: DP.green))
              : const DPIcon(DPIcons.fingerprint, size: 28, color: DP.green),
        ),
      ),
    );
  }
}
