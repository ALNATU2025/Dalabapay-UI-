// lib/presentation/screens/auth/otp_verification_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/services/api_service.dart';
import '../../../ui/ui.dart';

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
        dpSnack(context, 'New code sent to your email', success: true);
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
    final complete = _enteredOTP.length == 6;
    final mm = (_resendCountdown ~/ 60).toString().padLeft(2, '0');
    final ss = (_resendCountdown % 60).toString().padLeft(2, '0');
    return DPPage(
      title: 'Verify your email',
      children: [
        FadeTransition(
          opacity: _fadeAnimation,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 18),
              const Align(
                alignment: Alignment.centerLeft,
                child: DPIconBadge(
                  icon: DPIcons.mail,
                  bg: DP.greenSoft,
                  fg: DP.green,
                  size: 64,
                  radius: 20,
                ),
              ),
              DPHeadline(
                'One quick check.',
                subtitle: 'Enter the 6-digit code we sent to\n${widget.email}.',
                padding: const EdgeInsets.only(top: 26, bottom: 26),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(6, _buildOTPField),
              ),
              if (_errorMessage.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(_errorMessage, style: DPText.small.copyWith(color: DP.danger)),
              ],
              const SizedBox(height: 18),
              Center(
                child: _resendCountdown > 0
                    ? Text('Resend code in $mm:$ss', style: DPText.bodyMuted.copyWith(fontSize: 13.5))
                    : DPLinkButton(
                        label: _isResending ? 'Sending…' : 'Resend code',
                        onPressed: _isResending ? null : _resendOTP,
                      ),
              ),
              const SizedBox(height: 18),
              _buildVerifyButton(complete),
              const SizedBox(height: 10),
              Center(
                child: DPLinkButton(
                  label: 'Change email address',
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ),
              const SizedBox(height: 14),
              _buildTrustStrip(),
              const SizedBox(height: 48),
              Center(child: Text('Still having trouble?', style: DPText.bodyMuted.copyWith(fontSize: 13))),
              Center(
                child: DPLinkButton(
                  label: 'Get help from our team',
                  onPressed: () => Navigator.pushNamed(context, '/support'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOTPField(int index) {
    return SizedBox(
      width: 48,
      height: 56,
      child: TextField(
        controller: _otpControllers[index],
        focusNode: _otpFocusNodes[index],
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        maxLength: 1,
        style: DPText.title.copyWith(fontSize: 22, fontWeight: FontWeight.w500),
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          counterText: '',
          contentPadding: EdgeInsets.zero,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(DP.rMd),
            borderSide: BorderSide(
              color: _errorMessage.isNotEmpty ? DP.danger : DP.border,
            ),
          ),
        ),
        onChanged: (value) {
          if (value.isEmpty && index > 0) {
            FocusScope.of(context).requestFocus(_otpFocusNodes[index - 1]);
          }
          setState(() {});
          _moveToNextField(index, value);
        },
      ),
    );
  }

  Widget _buildVerifyButton(bool complete) {
    return DPButton(
      label: 'Verify code',
      loading: _isLoading,
      onPressed: complete && !_isLoading ? _verifyOTP : null,
    );
  }

  Widget _buildTrustStrip() {
    return const DPNotice(
      'Can’t find your code? Check your inbox and spam folder, and make sure the email address is correct.',
      margin: EdgeInsets.zero,
    );
  }
}
