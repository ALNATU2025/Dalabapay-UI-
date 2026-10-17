// lib/presentation/screens/auth/pin_setup_screen.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/services/api_service.dart';
import '../../../core/services/biometric_service.dart';

class PinSetupScreen extends StatefulWidget {
  final String userId;
  final String fullName;
  final String email;
  final bool isFirstTime;
  final String? currentPin;

  const PinSetupScreen({
    super.key,
    required this.userId,
    required this.fullName,
    required this.email,
    this.isFirstTime = false,
    this.currentPin,
  });

  @override
  State<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends State<PinSetupScreen> {
  // PIN State
  String _pin = '';
  String _confirmPin = '';
  bool _isConfirming = false;
  bool _isLoading = false;
  bool _isSubmitting = false;
  String _errorMessage = '';
  Timer? _debounceTimer;
  bool _isLoadingData = true;

  // Biometric State - Using BiometricService
  bool _biometricAvailable = false;
  bool _isBiometricLoading = false;
  bool _hasExistingPin = false;

  // Colors - matching Dashboard
  final Color _primaryColor = const Color(0xFF102C68);
  final Color _secondaryColor = const Color(0xFF168566);
  final Color _backgroundColor = Colors.white;
  final Color _digitColor = const Color(0xFF14263D);
  final Color _pinDotColor = const Color(0xFF102C68);
  final Color _errorColor = const Color(0xFFC0392B);

  @override
  void initState() {
    super.initState();

    // ✅ Validate userId on entry
    if (widget.userId.isEmpty) {
      debugPrint('❌ ERROR: PinSetupScreen received empty userId!');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showErrorDialog('Error', 'User ID is missing. Please register again.');
        Future.delayed(const Duration(seconds: 2), () {
          _navigateToLogin();
        });
      });
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _saveUserData(); // ✅ Save user data first
      await _checkBiometricSupport();
      await _checkPinStatus();
      setState(() => _isLoadingData = false);
    });

    if (widget.isFirstTime) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showWelcomeDialog();
      });
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  // ==================== INITIALIZATION ====================

  Future<void> _saveUserData() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // ✅ CRITICAL: Save user data to storage
      if (widget.userId.isNotEmpty) {
        await prefs.setString('userId', widget.userId);
        await prefs.setString('fullName', widget.fullName);
        await prefs.setString('email', widget.email);

        // Also save to user object
        final userData = {
          '_id': widget.userId,
          'fullName': widget.fullName,
          'email': widget.email,
          'transactionPinSet': _hasExistingPin,
        };
        await prefs.setString('user', jsonEncode(userData));

        await prefs.reload();
        debugPrint('✅ User data saved: ${widget.fullName} (${widget.userId})');
      }
    } catch (e) {
      debugPrint('⚠️ Error saving user data: $e');
    }
  }

  Future<void> _checkBiometricSupport() async {
    try {
      _biometricAvailable = await biometricService.isBiometricAvailable();
      debugPrint('🔐 Biometric available: $_biometricAvailable');

      if (_biometricAvailable) {
        final types = await biometricService.getAvailableBiometrics();
        debugPrint('🔐 Biometric types: $types');
        final name = await biometricService.getBiometricName();
        debugPrint('🔐 Biometric name: $name');
      }
    } catch (e) {
      debugPrint('⚠️ Error checking biometric support: $e');
      _biometricAvailable = false;
    }

    if (mounted) setState(() {});
  }

  Future<void> _checkPinStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();

      // Check multiple sources for PIN status
      final directPinSet = prefs.getBool('transactionPinSet') ?? false;

      bool userPinSet = false;
      final userString = prefs.getString('user');
      if (userString != null) {
        try {
          final userMap = jsonDecode(userString) as Map<String, dynamic>;
          userPinSet = userMap['transactionPinSet'] == true;
        } catch (e) {
          debugPrint('⚠️ Error parsing user data: $e');
        }
      }

      final pinSet = directPinSet || userPinSet;

      debugPrint(
        '🔍 PIN Status Check: direct=$directPinSet, user=$userPinSet, final=$pinSet',
      );

      setState(() {
        _hasExistingPin = pinSet;
      });

      // If PIN is already set, show the "PIN Already Set" dialog
      if (pinSet && mounted) {
        debugPrint('✅ PIN already set, showing dialog');
        await Future.delayed(const Duration(milliseconds: 300));
        if (mounted) {
          _showPinAlreadySetDialog();
        }
      } else {
        debugPrint('ℹ️ No PIN set, proceeding with PIN setup');
      }
    } catch (e) {
      debugPrint('⚠️ Error checking PIN status: $e');
      setState(() => _isLoadingData = false);
    }
  }

  // ==================== DIALOGS ====================

  void _showWelcomeDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            backgroundColor: Colors.white,
            title: Column(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topRight,
                      end: Alignment.bottomLeft,
                      colors: [Color(0xFF5BB592), Color(0xFF102C68)],
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.security,
                    color: Colors.white,
                    size: 36,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Welcome, ${widget.fullName.split(' ').first}!',
                  style: GoogleFonts.inter(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: _primaryColor,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
            content: Text(
              'Set up your transaction PIN to secure your account and transactions.',
              style: GoogleFonts.inter(
                fontSize: 14,
                color: const Color(0xFF728078),
              ),
              textAlign: TextAlign.center,
            ),
            actions: [
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 12,
                  ),
                ),
                child: Text(
                  'Get Started',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
    );
  }

  void _showPinAlreadySetDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            backgroundColor: Colors.white,
            title: Row(
              children: [
                Icon(Icons.info_outline, color: _primaryColor, size: 28),
                const SizedBox(width: 12),
                Text(
                  'PIN Already Set',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.bold,
                    color: _primaryColor,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'You already have a transaction PIN set up.',
                  style: GoogleFonts.inter(fontSize: 14),
                ),
                const SizedBox(height: 8),
                Text(
                  'You can change it here, or use your existing PIN to login.',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: const Color(0xFF728078),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _primaryColor.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _primaryColor.withValues(alpha: 0.15),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.lightbulb_outline,
                        size: 18,
                        color: _primaryColor,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Tip: You need your current PIN to change it',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: _primaryColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
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
                  _navigateToPinLogin();
                },
                child: Text(
                  'Use Existing PIN',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF728078),
                  ),
                ),
              ),
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
                  setState(() {
                    _pin = '';
                    _confirmPin = '';
                    _isConfirming = false;
                    _errorMessage = '';
                  });
                  // Show hint about needing current PIN
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Enter your CURRENT PIN first, then create a new one',
                        style: GoogleFonts.inter(color: Colors.white),
                      ),
                      backgroundColor: _primaryColor,
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(seconds: 3),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  'Change PIN',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
    );
  }

  void _showSuccessDialog({
    required String message,
    required bool isFirstTime,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            backgroundColor: Colors.white,
            title: Column(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: _secondaryColor.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.check_circle,
                    color: _secondaryColor,
                    size: 40,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  isFirstTime ? 'PIN Set Successfully!' : 'PIN Updated!',
                  style: GoogleFonts.inter(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: _primaryColor,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
            content: Text(
              message,
              style: GoogleFonts.inter(
                fontSize: 14,
                color: const Color(0xFF728078),
              ),
              textAlign: TextAlign.center,
            ),
            actions: [
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 12,
                  ),
                ),
                child: Text(
                  isFirstTime ? 'Continue' : 'Done',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
    );
  }

  void _showBiometricDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            backgroundColor: Colors.white,
            title: Column(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topRight,
                      end: Alignment.bottomLeft,
                      colors: [Color(0xFF5BB592), Color(0xFF102C68)],
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.fingerprint,
                    color: Colors.white,
                    size: 36,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Enable Biometric?',
                  style: GoogleFonts.inter(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: _primaryColor,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Enable fingerprint or Face ID for faster and more secure access.',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: const Color(0xFF728078),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _primaryColor.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _primaryColor.withValues(alpha: 0.1),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.shield_outlined,
                        color: _primaryColor,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Your biometric data stays on your device and is never shared.',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: const Color(0xFF728078),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _navigateToHome();
                },
                child: Text(
                  'Skip',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF728078),
                  ),
                ),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _setupBiometric();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
                child: Text(
                  'Enable',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
    );
  }

  void _showBiometricSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            backgroundColor: Colors.white,
            title: Column(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: _secondaryColor.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.fingerprint,
                    color: Color(0xFF168566),
                    size: 36,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Biometric Enabled!',
                  style: GoogleFonts.inter(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: _primaryColor,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
            content: Text(
              'You can now use fingerprint or Face ID to quickly access your account.',
              style: GoogleFonts.inter(
                fontSize: 14,
                color: const Color(0xFF728078),
              ),
              textAlign: TextAlign.center,
            ),
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
                  _navigateToHome();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 12,
                  ),
                ),
                child: Text(
                  'Go to Home',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
    );
  }

  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            backgroundColor: Colors.white,
            title: Row(
              children: [
                Icon(Icons.error_outline, color: _errorColor, size: 28),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.bold,
                    color: _errorColor,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
            content: Text(message, style: GoogleFonts.inter(fontSize: 14)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'OK',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    color: _primaryColor,
                  ),
                ),
              ),
            ],
          ),
    );
  }

  // ==================== BIOMETRIC - USING BIOMETRIC SERVICE ====================

  Future<void> _setupBiometric() async {
    if (_isBiometricLoading) return;

    setState(() => _isBiometricLoading = true);

    try {
      final authenticated = await biometricService.authenticate(
        reason: 'Setup biometric for faster login',
        biometricOnly: false,
        stickyAuth: true,
      );

      if (authenticated) {
        final biometricKey =
            'biometric_${widget.userId}_${DateTime.now().millisecondsSinceEpoch}';
        final credentialId =
            'cred_${widget.userId}_${DateTime.now().millisecondsSinceEpoch}';

        await ApiService.toggleBiometric(
          userId: widget.userId,
          enable: true,
          biometricKey: biometricKey,
          biometricCredentialId: credentialId,
        );

        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('biometricEnabled', true);

        if (mounted) {
          _showBiometricSuccessDialog();
        }
      } else {
        if (mounted) {
          _showErrorDialog(
            'Biometric Setup',
            'Biometric setup was cancelled. You can enable it later in Settings.',
          );
          _navigateToHome();
        }
      }
    } catch (e) {
      debugPrint('⚠️ Biometric error: $e');
      if (mounted) {
        _showErrorDialog(
          'Biometric Error',
          'Failed to setup biometric. You can enable it later in Settings.',
        );
        _navigateToHome();
      }
    } finally {
      if (mounted) setState(() => _isBiometricLoading = false);
    }
  }

  // ==================== PIN OPERATIONS ====================

  void _onPinDigitPressed(String digit) {
    if (_isLoading || _isSubmitting) return;
    if (_debounceTimer?.isActive == true) return;

    _debounceTimer = Timer(const Duration(milliseconds: 200), () {});

    setState(() {
      if (_isConfirming) {
        if (_confirmPin.length < 6) _confirmPin += digit;
      } else {
        if (_pin.length < 6) _pin += digit;
      }
      _errorMessage = '';
    });

    if (!_isConfirming && _pin.length == 6) {
      setState(() => _isConfirming = true);
    } else if (_isConfirming && _confirmPin.length == 6) {
      _verifyPin();
    }
  }

  void _onBackspacePressed() {
    if (_isLoading || _isSubmitting) return;

    setState(() {
      if (_isConfirming && _confirmPin.isNotEmpty) {
        _confirmPin = _confirmPin.substring(0, _confirmPin.length - 1);
      } else if (_pin.isNotEmpty) {
        _pin = _pin.substring(0, _pin.length - 1);
      }
    });
  }

  String? _validatePin(String pin) {
    if (pin.isEmpty) return 'Please enter a PIN';
    if (pin.length != 6) return 'PIN must be exactly 6 digits';
    if (!RegExp(r'^\d+$').hasMatch(pin)) {
      return 'PIN can only contain numbers';
    }
    if (RegExp(r'^(\d)\1{5}$').hasMatch(pin)) {
      return 'PIN cannot be all repeating numbers';
    }
    if (pin == '123456' || pin == '654321' || pin == '000000') {
      return 'Please choose a more secure PIN';
    }
    return null;
  }

  Future<void> _verifyPin() async {
    if (_isSubmitting) return;

    if (_pin != _confirmPin) {
      setState(() {
        _errorMessage = 'PINs do not match. Please try again';
        _confirmPin = '';
        _isConfirming = false;
      });
      return;
    }

    final error = _validatePin(_pin);
    if (error != null) {
      setState(() {
        _errorMessage = error;
        _confirmPin = '';
        _isConfirming = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _isSubmitting = true;
      _errorMessage = '';
    });

    try {
      final prefs = await SharedPreferences.getInstance();

      // ✅ Validate userId before making API call
      if (widget.userId.isEmpty) {
        throw Exception('User ID is missing. Please register again.');
      }

      // ✅ Ensure we have a token, if not try to get one
      String? token = prefs.getString('token');
      if (token == null || token.isEmpty) {
        debugPrint('⚠️ No token found, attempting to recover...');
        // Try to get token from user object or other sources
        final userString = prefs.getString('user');
        if (userString != null) {
          try {
            final userMap = jsonDecode(userString) as Map<String, dynamic>;
            userMap['transactionPinSet'] = true;
            await prefs.setString('user', jsonEncode(userMap));
          } catch (e) {
            debugPrint('⚠️ Error updating user object: $e');
          }
        } else {
          // Create user object if it doesn't exist
          final newUser = {
            '_id': widget.userId,
            'fullName': widget.fullName,
            'email': widget.email,
            'transactionPinSet': true,
          };
          await prefs.setString('user', jsonEncode(newUser));
        }

        await prefs.reload();
        debugPrint('✅ PIN status saved successfully');

        // If still no token, but we have userId, we can try to set PIN anyway
        // The backend might not require token for first-time PIN setup
        if (token == null || token.isEmpty) {
          debugPrint('⚠️ No token available, but proceeding with PIN setup...');
        }
      }

      // ✅ Save PIN to backend
      if (widget.isFirstTime) {
        debugPrint('🔐 Setting transaction PIN for user: ${widget.userId}');
        final response = await ApiService.setTransactionPin(
          userId: widget.userId,
          pin: _pin,
        );

        if (response['success'] == false) {
          throw Exception(response['message'] ?? 'Failed to set PIN');
        }
      } else {
        debugPrint('🔐 Changing transaction PIN for user: ${widget.userId}');
        final response = await ApiService.changeTransactionPin(
          userId: widget.userId,
          currentPin: widget.currentPin ?? '',
          newPin: _pin,
        );

        if (response['success'] == false) {
          throw Exception(response['message'] ?? 'Failed to change PIN');
        }
      }

      // ✅ Update local storage
      await prefs.setBool('transactionPinSet', true);
      await prefs.setBool('hasPinSet', true); //

      final userString = prefs.getString('user');
      if (userString != null) {
        try {
          final userMap = jsonDecode(userString) as Map<String, dynamic>;
          userMap['transactionPinSet'] = true;
          await prefs.setString('user', jsonEncode(userMap));
        } catch (e) {
          debugPrint('⚠️ Error updating user object: $e');
        }
      } else {
        final newUser = {
          '_id': widget.userId,
          'fullName': widget.fullName,
          'email': widget.email,
          'transactionPinSet': true,
        };
        await prefs.setString('user', jsonEncode(newUser));
      }

      await prefs.reload();

      debugPrint('✅ PIN saved successfully');

      if (mounted) {
        _showSuccessDialog(
          message:
              widget.isFirstTime
                  ? 'Your transaction PIN has been set successfully.'
                  : 'Your transaction PIN has been updated successfully.',
          isFirstTime: widget.isFirstTime,
        );

        if (widget.isFirstTime && _biometricAvailable && mounted) {
          await Future.delayed(const Duration(milliseconds: 500));
          if (mounted) {
            _showBiometricDialog();
          }
        } else if (mounted) {
          await Future.delayed(const Duration(milliseconds: 500));
          if (mounted) {
            _navigateToHome();
          }
        }
      }
    } catch (e) {
      debugPrint('❌ PIN save error: $e');

      final errorStr = e.toString().toLowerCase();

      // ✅ Handle "PIN already set" as success
      if (errorStr.contains('already set') ||
          errorStr.contains('pin already set')) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('transactionPinSet', true);
        await prefs.reload();

        if (mounted) {
          _showSuccessDialog(
            message: 'Your PIN is already set. You can continue to the app.',
            isFirstTime: widget.isFirstTime,
          );
          await Future.delayed(const Duration(milliseconds: 500));
          if (mounted) {
            _navigateToHome();
          }
        }
        return;
      }

      // ✅ Handle authentication errors
      if (errorStr.contains('Authentication token not found') ||
          errorStr.contains('NO_TOKEN') ||
          errorStr.contains('Please log in again')) {
        // Try to recover by navigating to login
        _showErrorDialog(
          'Session Expired',
          'Please login again to set up your PIN.',
        );
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) {
          _navigateToLogin();
        }
        return;
      }

      if (mounted) {
        setState(() {
          _errorMessage = _getUserFriendlyError(e.toString());
          _isLoading = false;
          _pin = '';
          _confirmPin = '';
          _isConfirming = false;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isSubmitting = false;
        });
      }
    }
  }

  String _getUserFriendlyError(String error) {
    final errorLower = error.toLowerCase();

    if (errorLower.contains('network') || errorLower.contains('connection')) {
      return 'Network issue. Please check your internet connection.';
    }
    if (errorLower.contains('invalid request')) {
      return 'Invalid request. Please try again.';
    }
    if (errorLower.contains('biometric')) {
      return 'Biometric setup was skipped. You can enable it later.';
    }
    if (errorLower.contains('already set')) {
      return 'Your PIN is already set. You can continue to the app.';
    }

    return error.replaceAll('Exception: ', '');
  }

  // ==================== NAVIGATION ====================

  void _navigateToHome() {
    if (!mounted) return;

    Navigator.pushNamedAndRemoveUntil(
      context,
      '/dashboard',
      (route) => false,
      arguments: {
        'userId': widget.userId,
        'email': widget.email,
        'fullName': widget.fullName,
      },
    );
  }

  void _navigateToPinLogin() {
    if (!mounted) return;

    Navigator.pushNamedAndRemoveUntil(context, '/pin-login', (route) => false);
  }

  void _navigateToLogin() {
    if (!mounted) return;

    Navigator.pushReplacementNamed(context, '/login');
  }

  // ==================== UI BUILD ====================

  Widget _buildLogo() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20, top: 10),
      child: Image.asset(
        'assets/dalabapay2.png',
        height: 50,
        fit: BoxFit.contain,
        errorBuilder:
            (context, error, stackTrace) => Container(
              width: 100,
              height: 50,
              decoration: BoxDecoration(
                color: _primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.security, size: 30, color: _primaryColor),
            ),
      ),
    );
  }

  Widget _buildPinDots() {
    final activePin = _isConfirming ? _confirmPin : _pin;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(6, (index) {
          final isFilled = index < activePin.length;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: const EdgeInsets.symmetric(horizontal: 6),
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isFilled ? _pinDotColor : Colors.grey.shade200,
              border: Border.all(
                color: isFilled ? _primaryColor : Colors.grey.shade300,
                width: 1.5,
              ),
              boxShadow:
                  isFilled
                      ? [
                        BoxShadow(
                          color: _primaryColor.withValues(alpha: 0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ]
                      : null,
            ),
          );
        }),
      ),
    );
  }

  Widget _buildDigitButton(String digit) {
    return GestureDetector(
      onTap: () => _onPinDigitPressed(digit),
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _backgroundColor,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
          border: Border.all(color: Colors.grey.shade200, width: 1),
        ),
        child: Center(
          child: Text(
            digit,
            style: GoogleFonts.inter(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: _digitColor,
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
      onTap: _isBiometricLoading ? null : _setupBiometric,
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [Color(0xFF5BB592), Color(0xFF102C68)],
          ),
          boxShadow: [
            BoxShadow(
              color: Color(0xFF102C68).withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
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

  Widget _buildNumberPad() {
    return Column(
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
    );
  }

  Widget _buildPinForm() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Title
          Text(
            _hasExistingPin
                ? 'Change PIN'
                : (widget.isFirstTime ? 'Set Transaction PIN' : 'Change PIN'),
            style: GoogleFonts.inter(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: _primaryColor,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),

          // Subtitle
          Text(
            _isConfirming
                ? 'Confirm your 6-digit PIN'
                : (_hasExistingPin
                    ? 'Enter your current PIN and create a new one'
                    : 'Create a secure 6-digit PIN'),
            style: GoogleFonts.inter(
              fontSize: 14,
              color: const Color(0xFF728078),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),

          // User info
          if (widget.fullName.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _primaryColor.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _primaryColor.withValues(alpha: 0.1)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: _primaryColor,
                    child: Text(
                      widget.fullName[0].toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    widget.fullName,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: _primaryColor,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),

          // PIN Dots
          _buildPinDots(),

          // Number Pad
          _buildNumberPad(),

          // Error Message
          if (_errorMessage.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _errorColor.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _errorColor.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: _errorColor, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage,
                        style: GoogleFonts.inter(
                          color: _errorColor,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Loading
          if (_isLoading)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(_primaryColor),
                  strokeWidth: 3,
                ),
              ),
            ),

          // Bottom actions - Show "Use Existing PIN Login" if PIN is already set
          if (_hasExistingPin)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: TextButton(
                onPressed: _navigateToPinLogin,
                child: Text(
                  'Use Existing PIN Login',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: _primaryColor,
                  ),
                ),
              ),
            ),

          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: TextButton(
              onPressed: _navigateToLogin,
              child: Text(
                'Back to Login',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: const Color(0xFF728078),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingData) {
      return Scaffold(
        backgroundColor: _backgroundColor,
        body: const Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF102C68)),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: _backgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Container(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildLogo(),
                _buildPinForm(),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
