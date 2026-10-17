// lib/presentation/screens/auth/change_pin_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/services/api_service.dart';

class ChangePinScreen extends StatefulWidget {
  final String userId;
  final String userEmail;
  final String fullName;
  final bool hasExistingPin;

  const ChangePinScreen({
    super.key,
    required this.userId,
    required this.userEmail,
    this.fullName = 'User',
    this.hasExistingPin = false,
  });

  @override
  State<ChangePinScreen> createState() => _ChangePinScreenState();
}

class _ChangePinScreenState extends State<ChangePinScreen> {
  // Change/Set PIN
  final _currentPinController = TextEditingController();
  final _newPinController = TextEditingController();
  final _confirmPinController = TextEditingController();

  bool _isLoading = false;
  String _errorMessage = '';
  bool _obscureCurrentPin = true;
  bool _obscureNewPin = true;
  bool _obscureConfirmPin = true;

  // Reset with Email
  bool _showResetSection = false;
  bool _tokenSent = false;
  bool _tokenVerified = false;
  bool _resetIsLoading = false;
  String _resetErrorMessage = '';
  int _resetCooldown = 0;
  Timer? _cooldownTimer;

  final _resetEmailController = TextEditingController();
  final _resetTokenController = TextEditingController();
  final _resetNewPinController = TextEditingController();
  final _resetConfirmPinController = TextEditingController();
  bool _obscureResetNewPin = true;
  bool _obscureResetConfirmPin = true;

  // Brand Colors
  static const Color _brand = Color(0xFF168566);
  static const Color _brandDark = Color(0xFF14263D);
  static const Color _primaryColor = Color(0xFF102C68);
  static const Color _errorColor = Color(0xFFC0392B);
  static const Color _greyText = Color(0xFF728078);

  @override
  void initState() {
    super.initState();
    _resetEmailController.text = widget.userEmail;
  }

  @override
  void dispose() {
    _currentPinController.dispose();
    _newPinController.dispose();
    _confirmPinController.dispose();
    _resetEmailController.dispose();
    _resetTokenController.dispose();
    _resetNewPinController.dispose();
    _resetConfirmPinController.dispose();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  // ==================== VALIDATION ====================

  String? _validatePin(String pin) {
    if (pin.isEmpty) return 'Please enter a PIN';
    if (pin.length != 6) return 'PIN must be exactly 6 digits';
    if (!RegExp(r'^\d+$').hasMatch(pin)) return 'PIN can only contain numbers';
    if (RegExp(r'^(\d)\1{5}$').hasMatch(pin)) {
      return 'PIN cannot be all repeating numbers';
    }
    if (pin == '123456' || pin == '654321' || pin == '000000') {
      return 'Please choose a more secure PIN';
    }
    return null;
  }

  // ==================== CHANGE / SET PIN ====================

  Future<void> _submitPin() async {
    final newPin = _newPinController.text.trim();
    final confirmPin = _confirmPinController.text.trim();
    final currentPin = _currentPinController.text.trim();

    final validationError = _validatePin(newPin);
    if (validationError != null) {
      setState(() => _errorMessage = validationError);
      return;
    }

    if (newPin != confirmPin) {
      setState(() => _errorMessage = 'PINs do not match');
      return;
    }

    // Only compare with current when user HAS an existing PIN
    if (widget.hasExistingPin) {
      if (currentPin.isEmpty) {
        setState(() => _errorMessage = 'Please enter your current PIN');
        return;
      }
      if (currentPin.length != 6) {
        setState(() => _errorMessage = 'Current PIN must be 6 digits');
        return;
      }
      if (currentPin == newPin) {
        setState(
          () => _errorMessage = 'New PIN must be different from current PIN',
        );
        return;
      }
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final Map<String, dynamic> response;

      if (widget.hasExistingPin) {
        // Change existing PIN
        response = await ApiService.changeTransactionPin(
          userId: widget.userId,
          currentPin: currentPin,
          newPin: newPin,
        );
      } else {
        // First-time set
        response = await ApiService.setTransactionPin(
          userId: widget.userId,
          pin: newPin,
        );
      }

      if (!mounted) return;

      if (response['success'] == true) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('transactionPinSet', true);
        await prefs.setBool('hasTransactionPin_${widget.userId}', true);
        await prefs.reload();

        if (!mounted) return;
        _showSuccessDialog(
          widget.hasExistingPin ? 'PIN Changed Successfully!' : 'PIN Set Successfully!',
          widget.hasExistingPin
              ? 'Your transaction PIN has been updated.'
              : 'Your transaction PIN is now active.',
        );
      } else {
        setState(() {
          _errorMessage = response['message'] ?? 'Failed to update PIN';
        });
      }
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().toLowerCase();
      if (msg.contains('current pin') || msg.contains('incorrect')) {
        setState(() => _errorMessage = 'Current PIN is incorrect.');
      } else if (msg.contains('network') || msg.contains('connection')) {
        setState(() => _errorMessage =
            'Network issue. Please check your internet connection.');
      } else {
        setState(() => _errorMessage =
            'Failed: ${e.toString().replaceAll('Exception: ', '')}');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ==================== EMAIL RESET FLOW ====================

  void _startCooldownTimer() {
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_resetCooldown <= 1) {
        timer.cancel();
        setState(() => _resetCooldown = 0);
      } else {
        setState(() => _resetCooldown--);
      }
    });
  }

  Future<void> _requestResetToken() async {
    if (_resetCooldown > 0) return;

    setState(() {
      _resetIsLoading = true;
      _resetErrorMessage = '';
    });

    try {
      final response = await ApiService.requestPinReset(
        email: _resetEmailController.text.trim(),
      );

      if (!mounted) return;

      if (response['success'] == true) {
        setState(() {
          _tokenSent = true;
          _resetCooldown = 60;
          _resetErrorMessage = '';
        });
        _startCooldownTimer();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              response['message'] ?? 'Reset code sent to your email',
              style: GoogleFonts.inter(color: Colors.white),
            ),
            backgroundColor: _brand,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        setState(() => _resetErrorMessage =
            response['message'] ?? 'Failed to send reset code');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _resetErrorMessage =
          'Error: ${e.toString().replaceAll('Exception: ', '')}');
    } finally {
      if (mounted) setState(() => _resetIsLoading = false);
    }
  }

  Future<void> _verifyResetToken() async {
    final token = _resetTokenController.text.trim();
    if (token.length != 6) {
      setState(() => _resetErrorMessage = 'Enter the 6-digit reset code');
      return;
    }

    setState(() {
      _resetIsLoading = true;
      _resetErrorMessage = '';
    });

    try {
      final response = await ApiService.verifyPinResetToken(
        email: _resetEmailController.text.trim(),
        token: token,
      );

      if (!mounted) return;

      if (response['success'] == true && response['verified'] == true) {
        setState(() {
          _tokenVerified = true;
          _resetErrorMessage = '';
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Reset code verified successfully',
              style: GoogleFonts.inter(color: Colors.white),
            ),
            backgroundColor: _brand,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        setState(() => _resetErrorMessage =
            response['message'] ?? 'Invalid verification code');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _resetErrorMessage =
          'Error: ${e.toString().replaceAll('Exception: ', '')}');
    } finally {
      if (mounted) setState(() => _resetIsLoading = false);
    }
  }

  Future<void> _submitResetPin() async {
    final newPin = _resetNewPinController.text.trim();
    final confirmPin = _resetConfirmPinController.text.trim();

    if (!_tokenVerified) {
      setState(() => _resetErrorMessage = 'Please verify your reset code first');
      return;
    }

    final validationError = _validatePin(newPin);
    if (validationError != null) {
      setState(() => _resetErrorMessage = validationError);
      return;
    }

    if (newPin != confirmPin) {
      setState(() => _resetErrorMessage = 'PINs do not match');
      return;
    }

    setState(() {
      _resetIsLoading = true;
      _resetErrorMessage = '';
    });

    try {
      final response = await ApiService.resetPinWithToken(
        email: _resetEmailController.text.trim(),
        newPin: newPin,
      );

      if (!mounted) return;

      if (response['success'] == true) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('transactionPinSet', true);
        await prefs.setBool('hasTransactionPin_${widget.userId}', true);
        await prefs.reload();

        if (!mounted) return;
        _showResetSuccessDialog();
      } else {
        setState(() => _resetErrorMessage =
            response['message'] ?? 'Failed to reset PIN');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _resetErrorMessage =
          'Error: ${e.toString().replaceAll('Exception: ', '')}');
    } finally {
      if (mounted) setState(() => _resetIsLoading = false);
    }
  }

  // ==================== DIALOGS ====================

  void _showSuccessDialog(String title, String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: Colors.white,
        title: Column(
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: _brand.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle, color: _brand, size: 40),
            ),
            const SizedBox(height: 16),
            Text(
              title,
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
          style: GoogleFonts.inter(fontSize: 14, color: _greyText),
          textAlign: TextAlign.center,
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(ctx).pop();       // close dialog
                Navigator.of(context).pop(true); // back to Settings with success
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Text(
                'Done',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showResetSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: Colors.white,
        title: Column(
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: _brand.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.lock_reset, color: _brand, size: 40),
            ),
            const SizedBox(height: 16),
            Text(
              'PIN Reset Successful!',
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
          'Your transaction PIN has been reset. You can now use your new PIN.',
          style: GoogleFonts.inter(fontSize: 14, color: _greyText),
          textAlign: TextAlign.center,
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                Navigator.of(context).pop(true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Text(
                'Done',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== BUILD ====================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          _showResetSection
              ? 'Reset PIN'
              : (widget.hasExistingPin ? 'Change PIN' : 'Set PIN'),
          style: GoogleFonts.inter(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: _brandDark,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: _brandDark),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (!_showResetSection && widget.hasExistingPin)
            TextButton(
              onPressed: () {
                setState(() {
                  _showResetSection = true;
                  _errorMessage = '';
                  _resetErrorMessage = '';
                });
              },
              child: Text(
                'Forgot PIN?',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.orange.shade700,
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: _showResetSection
              ? _buildResetPinSection()
              : _buildChangePinSection(),
        ),
      ),
    );
  }

  // ==================== CHANGE / SET SECTION ====================

  Widget _buildChangePinSection() {
    final isSetMode = !widget.hasExistingPin;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [Color(0xFF5BB592), _primaryColor],
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isSetMode ? Icons.lock_outline : Icons.lock_reset,
                  size: 32,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                isSetMode ? 'Set Transaction PIN' : 'Change Transaction PIN',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                isSetMode
                    ? 'Create a 6-digit PIN to secure your transactions'
                    : 'For your security, we require your current PIN',
                style: GoogleFonts.inter(fontSize: 13, color: Colors.white70),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // User info
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _primaryColor.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _primaryColor.withOpacity(0.1)),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: _primaryColor,
                child: Text(
                  widget.fullName.isNotEmpty
                      ? widget.fullName[0].toUpperCase()
                      : 'U',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.fullName,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _primaryColor,
                      ),
                    ),
                    Text(
                      widget.userEmail,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: _greyText,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Current PIN (only when changing)
        if (!isSetMode) ...[
          _fieldLabel('Current PIN'),
          const SizedBox(height: 8),
          _pinField(
            controller: _currentPinController,
            hint: 'Enter your current 6-digit PIN',
            obscure: _obscureCurrentPin,
            onToggle: () =>
                setState(() => _obscureCurrentPin = !_obscureCurrentPin),
          ),
          const SizedBox(height: 20),
        ],

        // New PIN
        _fieldLabel(isSetMode ? 'Transaction PIN' : 'New PIN'),
        const SizedBox(height: 8),
        _pinField(
          controller: _newPinController,
          hint: isSetMode ? 'Enter a 6-digit PIN' : 'Enter new 6-digit PIN',
          obscure: _obscureNewPin,
          onToggle: () => setState(() => _obscureNewPin = !_obscureNewPin),
        ),
        const SizedBox(height: 20),

        // Confirm PIN
        _fieldLabel('Confirm PIN'),
        const SizedBox(height: 8),
        _pinField(
          controller: _confirmPinController,
          hint: 'Re-enter your 6-digit PIN',
          obscure: _obscureConfirmPin,
          onToggle: () =>
              setState(() => _obscureConfirmPin = !_obscureConfirmPin),
        ),
        const SizedBox(height: 8),

        // PIN Requirements Info
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFEEF8F2),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _brand.withOpacity(0.15)),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline, size: 16, color: _brand),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'PIN must be 6 digits. Avoid repeating or sequential numbers.',
                  style: GoogleFonts.inter(fontSize: 11, color: _greyText),
                ),
              ),
            ],
          ),
        ),

        // Error
        if (_errorMessage.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _errorColor.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _errorColor.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline,
                      color: _errorColor, size: 18),
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

        const SizedBox(height: 24),

        // Submit
        _primaryButton(
          label: isSetMode ? 'SET PIN' : 'CHANGE PIN',
          isLoading: _isLoading,
          onTap: _submitPin,
        ),
        const SizedBox(height: 16),

        // Forgot PIN
        if (!isSetMode)
          Center(
            child: TextButton(
              onPressed: () {
                setState(() {
                  _showResetSection = true;
                  _errorMessage = '';
                  _resetErrorMessage = '';
                });
              },
              child: Text(
                'Forgot your PIN? Reset with Email',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Colors.orange.shade700,
                ),
              ),
            ),
          ),

        Center(
          child: TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Back to Settings',
              style: GoogleFonts.inter(fontSize: 13, color: _greyText),
            ),
          ),
        ),
      ],
    );
  }

  // ==================== RESET SECTION ====================

  Widget _buildResetPinSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [Colors.orange.shade400, Colors.orange.shade700],
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.lock_reset,
                    size: 32, color: Colors.white),
              ),
              const SizedBox(height: 12),
              Text(
                'Reset Transaction PIN',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Verify your email to reset your PIN',
                style: GoogleFonts.inter(fontSize: 13, color: Colors.white70),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Email (pre-filled, read-only)
        _fieldLabel('Your Email'),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFFF3FAF6),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(
            children: [
              const Icon(Icons.email_outlined,
                  color: _primaryColor, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _resetEmailController.text,
                  style: GoogleFonts.inter(fontSize: 14, color: _brandDark),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Send Code button
        if (!_tokenSent)
          Container(
            width: double.infinity,
            height: 54,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              gradient: LinearGradient(
                colors: [Colors.orange.shade500, Colors.orange.shade700],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: ElevatedButton(
              onPressed:
                  _resetIsLoading || _resetCooldown > 0
                      ? null
                      : _requestResetToken,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
                elevation: 0,
              ),
              child: _resetIsLoading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _resetCooldown > 0
                              ? 'Wait ${_resetCooldown}s'
                              : 'SEND RESET CODE',
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: 1.2,
                          ),
                        ),
                        if (_resetCooldown > 0) ...[
                          const SizedBox(width: 8),
                          const Icon(Icons.timer,
                              color: Colors.white, size: 18),
                        ],
                      ],
                    ),
            ),
          ),

        // Reset token + verify
        if (_tokenSent) ...[
          const SizedBox(height: 20),
          _fieldLabel('Reset Code'),
          const SizedBox(height: 8),
          _pinField(
            controller: _resetTokenController,
            hint: 'Enter 6-digit code from email',
            obscure: false,
          ),
          const SizedBox(height: 16),

          if (!_tokenVerified)
            Container(
              width: double.infinity,
              height: 50,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _primaryColor, width: 1.5),
              ),
              child: ElevatedButton(
                onPressed: _resetIsLoading ? null : _verifyResetToken,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: _resetIsLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: _primaryColor,
                          strokeWidth: 2.5,
                        ),
                      )
                    : Text(
                        'VERIFY CODE',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: _primaryColor,
                          letterSpacing: 1,
                        ),
                      ),
              ),
            ),
        ],

        // New PIN fields (after verification)
        if (_tokenVerified) ...[
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 16),
          Text(
            'Set New PIN',
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: _primaryColor,
            ),
          ),
          const SizedBox(height: 20),

          _fieldLabel('New PIN'),
          const SizedBox(height: 8),
          _pinField(
            controller: _resetNewPinController,
            hint: 'Enter new 6-digit PIN',
            obscure: _obscureResetNewPin,
            onToggle: () => setState(
                () => _obscureResetNewPin = !_obscureResetNewPin),
          ),
          const SizedBox(height: 16),

          _fieldLabel('Confirm New PIN'),
          const SizedBox(height: 8),
          _pinField(
            controller: _resetConfirmPinController,
            hint: 'Confirm new 6-digit PIN',
            obscure: _obscureResetConfirmPin,
            onToggle: () => setState(
                () => _obscureResetConfirmPin = !_obscureResetConfirmPin),
          ),
          const SizedBox(height: 24),

          _primaryButton(
            label: 'RESET PIN',
            isLoading: _resetIsLoading,
            onTap: _submitResetPin,
          ),
        ],

        // Error
        if (_resetErrorMessage.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _errorColor.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _errorColor.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline,
                      color: _errorColor, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _resetErrorMessage,
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

        const SizedBox(height: 16),
        Center(
          child: TextButton(
            onPressed: () {
              setState(() {
                _showResetSection = false;
                _resetErrorMessage = '';
                _tokenSent = false;
                _tokenVerified = false;
                _resetCooldown = 0;
                _cooldownTimer?.cancel();
              });
            },
            child: Text(
              '← Back to Change PIN',
              style: GoogleFonts.inter(fontSize: 13, color: _primaryColor),
            ),
          ),
        ),
      ],
    );
  }

  // ==================== REUSABLE WIDGETS ====================

  Widget _fieldLabel(String text) {
    return Text(
      text,
      style: GoogleFonts.inter(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: _brandDark,
      ),
    );
  }

  Widget _pinField({
    required TextEditingController controller,
    required String hint,
    required bool obscure,
    VoidCallback? onToggle,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: TextInputType.number,
      maxLength: 6,
      style: GoogleFonts.inter(fontSize: 16, color: _brandDark),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.inter(color: Colors.grey.shade400, fontSize: 14),
        prefixIcon:
            const Icon(Icons.lock_outline, color: _primaryColor, size: 20),
        suffixIcon: onToggle != null
            ? IconButton(
                icon: Icon(
                  obscure ? Icons.visibility_off : Icons.visibility,
                  color: Colors.grey.shade400,
                  size: 20,
                ),
                onPressed: onToggle,
              )
            : null,
        counterText: '',
        filled: true,
        fillColor: const Color(0xFFF3FAF6),
        contentPadding:
            const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _brand, width: 1.6),
        ),
      ),
    );
  }

  Widget _primaryButton({
    required String label,
    required bool isLoading,
    required VoidCallback onTap,
  }) {
    return Container(
      width: double.infinity,
      height: 54,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(13),
        gradient: const LinearGradient(
          colors: [Color(0xFF168566), Color(0xFF0F6B51)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: _brand.withOpacity(0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: isLoading ? null : onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
          ),
          elevation: 0,
        ),
        child: isLoading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.5,
                ),
              )
            : Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: 1.2,
                ),
              ),
      ),
    );
  }
}