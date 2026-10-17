// lib/presentation/screens/auth/reset_password_screen.dart
import 'package:flutter/material.dart';

import '../../../core/services/api_service.dart';
import '../../../ui/ui.dart';

class ResetPasswordScreen extends StatefulWidget {
  final String resetToken;

  const ResetPasswordScreen({super.key, required this.resetToken});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen>
    with SingleTickerProviderStateMixin {
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  // Password requirements
  bool _hasMinLength = false;
  bool _hasUppercase = false;
  bool _hasLowercase = false;
  bool _hasNumber = false;
  bool _isPasswordValid = false;
  bool _isConfirmPasswordValid = false;
  String _passwordError = '';
  String _confirmPasswordError = '';

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;


  @override
  void initState() {
    super.initState();
    _passwordController.addListener(_validatePasswordLive);
    _confirmPasswordController.addListener(_validateConfirmPasswordLive);

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
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  void _validatePasswordLive() {
    final value = _passwordController.text;
    setState(() {
      _hasMinLength = value.length >= 8;
      _hasUppercase = value.contains(RegExp(r'[A-Z]'));
      _hasLowercase = value.contains(RegExp(r'[a-z]'));
      _hasNumber = value.contains(RegExp(r'[0-9]'));

      if (value.isEmpty) {
        _passwordError = '';
        _isPasswordValid = false;
      } else if (!_hasMinLength) {
        _passwordError = 'Password must be at least 8 characters';
        _isPasswordValid = false;
      } else if (!_hasUppercase || !_hasLowercase || !_hasNumber) {
        _passwordError = 'Password must contain uppercase, lowercase & number';
        _isPasswordValid = false;
      } else {
        _passwordError = '';
        _isPasswordValid = true;
      }

      if (_confirmPasswordController.text.isNotEmpty) {
        _validateConfirmPasswordLive();
      }
    });
  }

  void _validateConfirmPasswordLive() {
    final value = _confirmPasswordController.text;
    final password = _passwordController.text;
    setState(() {
      if (value.isEmpty) {
        _confirmPasswordError = '';
        _isConfirmPasswordValid = false;
      } else if (value != password) {
        _confirmPasswordError = 'Passwords do not match';
        _isConfirmPasswordValid = false;
      } else {
        _confirmPasswordError = '';
        _isConfirmPasswordValid = true;
      }
    });
  }

  bool get _formValid => _isPasswordValid && _isConfirmPasswordValid;

  Future<void> _resetPassword() async {
    if (!_formValid) return;

    setState(() => _isLoading = true);

    try {
      final response = await ApiService.resetPasswordWithToken(
        resetToken: widget.resetToken,
        newPassword: _passwordController.text,
      );

      if (!mounted) return;

      if (response['success'] == true) {
        // Show success modal dialog
        _showSuccessDialog();
      } else {
        // Show error dialog with suggestions
        _showErrorDialog(response['message'] ?? 'Failed to reset password');
      }
    } catch (e) {
      _showErrorDialog(e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSuccessDialog() {
    showDPDialog(
      context,
      tone: DPDialogTone.success,
      barrierDismissible: false,
      title: 'Password updated',
      message: 'Your password has been changed. You can now log in with your new password.',
      primaryLabel: 'Log in',
      onPrimary: () {
        Navigator.of(context).pop();
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
      },
    );
  }

  void _showErrorDialog(String errorMessage) {
    String title = 'We couldn’t reset your password';
    String message = errorMessage.replaceAll('Exception: ', '');
    List<String> suggestions = [];

    if (errorMessage.contains('expired') || errorMessage.contains('Expired')) {
      title = 'Code expired';
      message = 'Your reset code has expired.';
      suggestions = [
        'Request a new code',
        'Check your email for the new code',
        'Reset within 10 minutes of receiving it',
      ];
    } else if (errorMessage.contains('weak') || errorMessage.contains('Weak')) {
      title = 'Password too weak';
      message = 'Please choose a stronger password.';
      suggestions = [
        'Use at least 8 characters',
        'Include uppercase and lowercase letters',
        'Add at least one number',
      ];
    } else if (errorMessage.contains('same') || errorMessage.contains('previous')) {
      title = 'Password already used';
      message = 'You can’t reuse a previous password.';
      suggestions = [
        'Try a completely new password',
        'Use a mix of letters and numbers',
      ];
    } else if (errorMessage.contains('network') || errorMessage.contains('connection')) {
      title = 'Connection problem';
      message = 'We couldn’t reach the server.';
      suggestions = [
        'Check your internet connection',
        'Try again in a few moments',
      ];
    } else {
      suggestions = [
        'Try again in a few moments',
        'Contact support if this keeps happening',
      ];
    }

    showDPDialog(
      context,
      tone: DPDialogTone.error,
      title: title,
      message: message,
      bullets: suggestions,
      primaryLabel: 'Request a new code',
      onPrimary: () {
        Navigator.of(context).pop();
        Navigator.of(context).pushNamedAndRemoveUntil('/forgot-password', (route) => false);
      },
      secondaryLabel: 'Try again',
    );
  }

  @override
  Widget build(BuildContext context) {
    return DPPage(
      title: 'New password',
      onBack: () => Navigator.of(context).pushNamedAndRemoveUntil('/login', (r) => false),
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
                  icon: DPIcons.lockKeyhole,
                  bg: DP.greenSoft,
                  fg: DP.green,
                  size: 64,
                  radius: 20,
                ),
              ),
              const DPHeadline(
                'Choose a new password.',
                subtitle: 'Make it something only you would know.',
                padding: EdgeInsets.only(top: 26, bottom: 26),
              ),
              _buildPasswordField(),
              _buildPasswordRequirements(),
              const SizedBox(height: 18),
              _buildConfirmPasswordField(),
              const SizedBox(height: 6),
              _buildResetButton(),
              const SizedBox(height: 18),
              _buildTrustStrip(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPasswordField() {
    return DPField(
      label: 'New password',
      controller: _passwordController,
      obscure: _obscurePassword,
      hint: '••••••••',
      autofillHints: const [AutofillHints.newPassword],
      margin: const EdgeInsets.only(bottom: 10),
      errorText: _passwordError.isEmpty ? null : _passwordError,
      suffixIcon: _obscurePassword ? DPIcons.eyeOff : DPIcons.eye,
      onSuffixTap: () => setState(() => _obscurePassword = !_obscurePassword),
    );
  }

  Widget _buildConfirmPasswordField() {
    return DPField(
      label: 'Confirm new password',
      controller: _confirmPasswordController,
      obscure: _obscureConfirmPassword,
      hint: '••••••••',
      errorText: _confirmPasswordError.isEmpty ? null : _confirmPasswordError,
      suffixIcon: _obscureConfirmPassword ? DPIcons.eyeOff : DPIcons.eye,
      onSuffixTap: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
    );
  }

  Widget _buildPasswordRequirements() {
    return Wrap(
      spacing: 14,
      runSpacing: 6,
      children: [
        _buildRequirementItem('8+ characters', _hasMinLength),
        _buildRequirementItem('Uppercase', _hasUppercase),
        _buildRequirementItem('Lowercase', _hasLowercase),
        _buildRequirementItem('A number', _hasNumber),
      ],
    );
  }

  Widget _buildRequirementItem(String text, bool isValid) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DPIcon(isValid ? DPIcons.circleCheck : DPIcons.circleX,
            size: 15, color: isValid ? DP.green : DP.faint),
        const SizedBox(width: 5),
        Text(text, style: DPText.small.copyWith(color: isValid ? DP.green : DP.muted)),
      ],
    );
  }

  Widget _buildResetButton() {
    return DPButton(
      label: 'Update password',
      loading: _isLoading,
      onPressed: _formValid && !_isLoading ? _resetPassword : null,
    );
  }

  Widget _buildTrustStrip() {
    return const DPNotice(
      'For your security, you’ll be asked to log in again on all your devices.',
      margin: EdgeInsets.zero,
    );
  }
}
