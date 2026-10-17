// lib/presentation/screens/auth/pin_setup_screen.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/services/api_service.dart';
import '../../../core/services/biometric_service.dart';
import '../../../ui/ui.dart';

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
    final first = widget.fullName.trim().isEmpty ? '' : widget.fullName.trim().split(' ').first;
    showDPDialog(
      context,
      tone: DPDialogTone.success,
      icon: DPIcons.shieldCheck,
      barrierDismissible: false,
      title: first.isEmpty ? 'Welcome!' : 'Welcome, $first!',
      message: 'Set up your transaction PIN to secure your account and payments.',
      primaryLabel: 'Get started',
    );
  }

  void _showPinAlreadySetDialog() {
    showDPDialog(
      context,
      tone: DPDialogTone.info,
      barrierDismissible: false,
      title: 'You already have a PIN',
      message: 'You can change it here, or use your existing PIN to log in.',
      body: const DPNotice(
        'You’ll need your current PIN to change it.',
        kind: DPNoticeKind.info,
        margin: EdgeInsets.zero,
      ),
      primaryLabel: 'Change PIN',
      onPrimary: () {
        Navigator.of(context).pop();
        setState(() {
          _pin = '';
          _confirmPin = '';
          _isConfirming = false;
          _errorMessage = '';
        });
        dpSnack(context, 'Enter your current PIN first, then create a new one');
      },
      secondaryLabel: 'Use existing PIN',
      onSecondary: () {
        Navigator.of(context).pop();
        _navigateToPinLogin();
      },
    );
  }

  void _showSuccessDialog({
    required String message,
    required bool isFirstTime,
  }) {
    showDPDialog(
      context,
      tone: DPDialogTone.success,
      barrierDismissible: false,
      title: isFirstTime ? 'Your PIN is set' : 'PIN updated',
      message: message,
      primaryLabel: isFirstTime ? 'Continue' : 'Done',
    );
  }

  void _showBiometricDialog() {
    showDPDialog(
      context,
      tone: DPDialogTone.success,
      icon: DPIcons.fingerprint,
      barrierDismissible: false,
      title: 'Turn on biometric login?',
      message: 'Use your fingerprint or face to log in faster.',
      body: const DPNotice(
        'Your biometric data stays on your device and is never shared.',
        margin: EdgeInsets.zero,
      ),
      primaryLabel: 'Turn on',
      onPrimary: () {
        Navigator.of(context).pop();
        _setupBiometric();
      },
      secondaryLabel: 'Not now',
      onSecondary: () {
        Navigator.of(context).pop();
        _navigateToHome();
      },
    );
  }

  void _showBiometricSuccessDialog() {
    showDPDialog(
      context,
      tone: DPDialogTone.success,
      icon: DPIcons.fingerprint,
      barrierDismissible: false,
      title: 'Biometric login is on',
      message: 'You can now use your fingerprint or face to open Dalabapay.',
      primaryLabel: 'Go to home',
      onPrimary: () {
        Navigator.of(context).pop();
        _navigateToHome();
      },
    );
  }

  void _showErrorDialog(String title, String message) {
    showDPDialog(
      context,
      tone: DPDialogTone.error,
      title: title,
      message: message,
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

  Widget _buildPinDots() {
    final activePin = _isConfirming ? _confirmPin : _pin;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 22),
      child: DPCodeBoxes(
        length: 6,
        value: activePin,
        obscure: true,
        error: _errorMessage.isNotEmpty,
        boxSize: 48,
      ),
    );
  }

  Widget _buildNumberPad() {
    return DPKeypad(
      onDigit: _onPinDigitPressed,
      onBackspace: _onBackspacePressed,
    );
  }

  Widget _buildPinForm() {
    final title = _isConfirming
        ? 'Confirm your PIN.'
        : (_hasExistingPin
            ? 'Change your PIN.'
            : (widget.isFirstTime ? 'Create your payment PIN.' : 'Change your PIN.'));
    final subtitle = _isConfirming
        ? 'Enter the same 6 digits again.'
        : (_hasExistingPin
            ? 'Enter your current PIN, then create a new one.'
            : 'You’ll use these 6 digits to approve every payment.');
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.fullName.isNotEmpty)
          Row(
            children: [
              DPAvatar(name: widget.fullName, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Text(widget.fullName,
                    style: DPText.body.copyWith(fontWeight: FontWeight.w500)),
              ),
              DPStatusPill(_isConfirming ? 'Step 2 of 2' : 'Step 1 of 2'),
            ],
          ),
        DPHeadline(title, subtitle: subtitle, padding: const EdgeInsets.only(top: 22, bottom: 4)),
        _buildPinDots(),
        if (_errorMessage.isNotEmpty) DPNotice(_errorMessage, kind: DPNoticeKind.danger),
        if (_isLoading)
          const Padding(padding: EdgeInsets.only(bottom: 8), child: DPLoader()),
        _buildNumberPad(),
        const SizedBox(height: 10),
        if (_hasExistingPin)
          Center(child: DPLinkButton(label: 'Use existing PIN to log in', onPressed: _navigateToPinLogin)),
        Center(
          child: DPLinkButton(label: 'Back to login', color: DP.muted, onPressed: _navigateToLogin),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingData) {
      return const Scaffold(backgroundColor: DP.bg, body: DPLoader());
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: DPTheme.overlay,
      child: Scaffold(
        backgroundColor: DP.bg,
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(DP.gutter, 18, DP.gutter, 24),
            children: [
              const Align(alignment: Alignment.centerLeft, child: DPLogo(height: 26)),
              const SizedBox(height: 26),
              _buildPinForm(),
            ],
          ),
        ),
      ),
    );
  }
}
