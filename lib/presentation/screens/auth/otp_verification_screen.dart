// lib/presentation/screens/auth/otp_verification_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/services/api_service.dart';

class OTPVerificationScreen extends StatefulWidget {
  final String email;

  const OTPVerificationScreen({super.key, required this.email});

  @override
  State<OTPVerificationScreen> createState() => _OTPVerificationScreenState();
}

class _OTPVerificationScreenState extends State<OTPVerificationScreen>
    with SingleTickerProviderStateMixin {
  final List<TextEditingController> _otpControllers = List.generate(
    6,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _otpFocusNodes = List.generate(6, (_) => FocusNode());

  bool _isLoading = false;
  bool _isResending = false;
  String _errorMessage = '';
  Timer? _resendTimer;
  int _resendCountdown = 60;

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  static const Color _brand = Color(0xFF168566);
  static const Color _brandDark = Color(0xFF14263D);
  static const Color _white = Colors.white;

  @override
  void initState() {
    super.initState();
    _startResendTimer();

    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    _fadeController.forward();

    // Auto-focus first OTP field
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusScope.of(context).requestFocus(_otpFocusNodes[0]);
    });
  }

  @override
  void dispose() {
    for (var controller in _otpControllers) {
      controller.dispose();
    }
    for (var node in _otpFocusNodes) {
      node.dispose();
    }
    _resendTimer?.cancel();
    _fadeController.dispose();
    super.dispose();
  }

  void _startResendTimer() {
    _resendCountdown = 60;
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_resendCountdown > 0) {
        setState(() => _resendCountdown--);
      } else {
        timer.cancel();
      }
    });
  }

  String get _enteredOTP => _otpControllers.map((c) => c.text).join();

  void _moveToNextField(int index, String value) {
    if (value.isNotEmpty && index < 5) {
      FocusScope.of(context).requestFocus(_otpFocusNodes[index + 1]);
    }
    if (index == 5 && value.isNotEmpty && _enteredOTP.length == 6) {
      _verifyOTP();
    }
  }

  // In otp_verification_screen.dart - Replace the _verifyOTP method with this:
  // In otp_verification_screen.dart - Update the _verifyOTP method
  Future<void> _verifyOTP() async {
    if (_isLoading || _enteredOTP.length != 6) return;

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final response = await ApiService.verifyResetOTP(
        email: widget.email,
        otp: _enteredOTP,
      );

      if (!mounted) return;

     if (response['success'] == true) {
  // ✅ Handle both camelCase and snake_case
  final resetToken =
      (response['resetToken'] ?? response['reset_token'] ?? '').toString();

  if (resetToken.isNotEmpty) {
    Navigator.of(context).pushNamedAndRemoveUntil(
      '/reset-password',
      (route) => false,
      arguments: {'resetToken': resetToken},
    );
  } else {
    setState(() => _errorMessage = 'Invalid reset token received');
  }
} else {
        // Show the exact error message from the backend
        setState(
          () =>
              _errorMessage =
                  response['message'] ?? 'Invalid OTP. Please try again.',
        );

        // Clear OTP fields on error
        for (var controller in _otpControllers) {
          controller.clear();
        }
        FocusScope.of(context).requestFocus(_otpFocusNodes[0]);
      }
    } catch (e) {
      setState(
        () => _errorMessage = e.toString().replaceAll('Exception: ', ''),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resendOTP() async {
    if (_isResending || _resendCountdown > 0) return;

    setState(() {
      _isResending = true;
      _errorMessage = '';
    });

    try {
      final response = await ApiService.forgotPassword(email: widget.email);

      if (!mounted) return;

      if (response['success'] == true) {
        _startResendTimer();
        // Clear OTP fields
        for (var controller in _otpControllers) {
          controller.clear();
        }
        FocusScope.of(context).requestFocus(_otpFocusNodes[0]);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'New OTP sent to your email',
              style: GoogleFonts.inter(),
            ),
            backgroundColor: _brand,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        setState(
          () => _errorMessage = response['message'] ?? 'Failed to resend OTP',
        );
      }
    } catch (e) {
      setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _white,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 24),

                  // Back Button
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.arrow_back_rounded, color: _brandDark),
                    padding: EdgeInsets.zero,
                    alignment: Alignment.centerLeft,
                  ),

                  const SizedBox(height: 16),

                  // Logo
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Image.asset(
                      'assets/dalabapay2.png',
                      width: 160,
                      fit: BoxFit.contain,
                    ),
                  ),

                  const SizedBox(height: 2),

                  // Slogan
                  Text(
                    'Smart Life, Fast Pay',
                    style: GoogleFonts.inter(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: _brand,
                      letterSpacing: 0.4,
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Heading
                  Text(
                    'Verify OTP',
                    style: GoogleFonts.inter(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: _brandDark,
                      height: 1.1,
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Subtitle
                  Text(
                    'Enter the 6-digit code sent to your email',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: Colors.grey[500],
                      height: 1.4,
                    ),
                  ),

                  const SizedBox(height: 28),

                  // Thin Divider
                  Container(
                    height: 1,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [_brand.withOpacity(0.35), Colors.transparent],
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // OTP Fields
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: List.generate(
                      6,
                      (index) => _buildOTPField(index),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Error Message
                  if (_errorMessage.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.error_outline,
                            color: Colors.red,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _errorMessage,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: Colors.red,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 24),

                  // Verify Button
                  _buildVerifyButton(),

                  const SizedBox(height: 20),

                  // Resend OTP
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Didn\'t receive the code? ',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: Colors.grey[600],
                        ),
                      ),
                      GestureDetector(
                        onTap:
                            (_resendCountdown == 0 && !_isResending)
                                ? _resendOTP
                                : null,
                        child: Text(
                          _isResending
                              ? 'Sending...'
                              : _resendCountdown > 0
                              ? 'Resend in ${_resendCountdown}s'
                              : 'Resend Code',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color:
                                (_resendCountdown == 0 && !_isResending)
                                    ? _brand
                                    : Colors.grey[400],
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Trust Strip
                  _buildTrustStrip(),

                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOTPField(int index) {
    return Container(
      width: 50,
      height: 60,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _otpFocusNodes[index].hasFocus ? _brand : Colors.grey.shade200,
          width: _otpFocusNodes[index].hasFocus ? 1.6 : 1,
        ),
      ),
      child: TextFormField(
        controller: _otpControllers[index],
        focusNode: _otpFocusNodes[index],
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        maxLength: 1,
        style: GoogleFonts.inter(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: _brandDark,
        ),
        decoration: const InputDecoration(
          counterText: '',
          border: InputBorder.none,
          contentPadding: EdgeInsets.zero,
        ),
        onChanged: (value) => _moveToNextField(index, value),
      ),
    );
  }

  Widget _buildVerifyButton() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
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
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(13),
          onTap: _isLoading ? null : _verifyOTP,
          child: Center(
            child:
                _isLoading
                    ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                    )
                    : Text(
                      'VERIFY OTP',
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: 1.2,
                      ),
                    ),
          ),
        ),
      ),
    );
  }

  Widget _buildTrustStrip() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF8F2),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF168566).withOpacity(0.15)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          const _TrustBadge(icon: Icons.shield_rounded, label: 'Secure'),
          Container(
            width: 1,
            height: 20,
            color: const Color(0xFF168566).withOpacity(0.18),
          ),
          const _TrustBadge(icon: Icons.bolt_rounded, label: 'Fast'),
          Container(
            width: 1,
            height: 20,
            color: const Color(0xFF168566).withOpacity(0.18),
          ),
          const _TrustBadge(icon: Icons.verified_rounded, label: 'Reliable'),
        ],
      ),
    );
  }
}

class _TrustBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  const _TrustBadge({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: const Color(0xFF168566)),
        const SizedBox(width: 6),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF14263D),
          ),
        ),
      ],
    );
  }
}
