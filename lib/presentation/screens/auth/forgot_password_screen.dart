// lib/presentation/screens/auth/forgot_password_screen.dart
// lib/presentation/screens/auth/forgot_password_screen.dart
import 'package:flutter/material.dart';

import '../../../core/services/api_service.dart';
import '../../../ui/ui.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen>
    with SingleTickerProviderStateMixin {
  final _emailController = TextEditingController();
  bool _isLoading = false;
  String _emailError = '';
  bool _isEmailValid = false;

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;


  @override
  void initState() {
    super.initState();
    _emailController.addListener(_validateEmailLive);

    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    _fadeController.forward();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  void _validateEmailLive() {
    final value = _emailController.text;
    setState(() {
      if (value.isEmpty) {
        _emailError = '';
        _isEmailValid = false;
      } else if (!value.contains('@') || !value.contains('.')) {
        _emailError = 'Enter a valid email address';
        _isEmailValid = false;
      } else {
        final emailRegex = RegExp(
          r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
        );
        if (emailRegex.hasMatch(value)) {
          _emailError = '';
          _isEmailValid = true;
        } else {
          _emailError = 'Enter a valid email address';
          _isEmailValid = false;
        }
      }
    });
  }

  // In forgot_password_screen.dart - Replace the _sendResetLink method with this:
  Future<void> _sendResetLink() async {
    if (!_isEmailValid) return;

    setState(() => _isLoading = true);

    try {
      final response = await ApiService.forgotPassword(
        email: _emailController.text.trim(),
      );

      if (!mounted) return;

      if (response['success'] == true) {
        Navigator.pushNamed(
          context,
          '/otp-verification',
          arguments: {'email': _emailController.text.trim()},
        );
      } else {
        _showError(response['message'] ?? 'Failed to send reset link');
      }
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    dpSnack(context, msg.replaceAll('Exception: ', ''), error: true);
  }

  @override
  Widget build(BuildContext context) {
    return DPPage(
      title: 'Reset password',
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
                  icon: DPIcons.keyRound,
                  bg: DP.greenSoft,
                  fg: DP.green,
                  size: 64,
                  radius: 20,
                ),
              ),
              const DPHeadline(
                'Let’s get you back in.',
                subtitle: 'Enter the email on your account and we’ll send you a 6-digit code.',
                padding: EdgeInsets.only(top: 26, bottom: 26),
              ),
              _buildEmailField(),
              const SizedBox(height: 6),
              _buildSendButton(),
              const SizedBox(height: 18),
              _buildTrustStrip(),
              const SizedBox(height: 28),
              Center(
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('Remembered it?', style: DPText.bodyMuted),
                    DPLinkButton(
                      label: 'Log in',
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEmailField() {
    return DPField(
      label: 'Email address',
      controller: _emailController,
      keyboardType: TextInputType.emailAddress,
      hint: 'you@example.com',
      autofillHints: const [AutofillHints.email],
      errorText: _emailError.isEmpty ? null : _emailError,
      suffixIcon: _isEmailValid ? DPIcons.circleCheck : DPIcons.mail,
      onSubmitted: (_) {
        if (_isEmailValid && !_isLoading) _sendResetLink();
      },
    );
  }

  Widget _buildSendButton() {
    return DPButton(
      label: 'Send code',
      icon: DPIcons.arrowRight,
      loading: _isLoading,
      onPressed: _isEmailValid && !_isLoading ? _sendResetLink : null,
    );
  }

  Widget _buildTrustStrip() {
    return const DPNotice(
      'Our team will never ask for your password, code or payment PIN.',
      margin: EdgeInsets.zero,
    );
  }
}
