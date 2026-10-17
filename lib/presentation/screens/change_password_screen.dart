// lib/presentation/screens/settings/change_password_screen.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/services/api_service.dart';
import '../../ui/ui.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final TextEditingController _currentPasswordController =
      TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  bool _isLoading = false;
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  String? _errorMessage;
  String? _successMessage;

  // Password validation
  bool _hasMinLength = false;
  bool _hasUppercase = false;
  bool _hasLowercase = false;
  bool _hasNumber = false;
  bool _hasSpecialChar = false;

  final Color _primaryColor = const Color(0xFF102C68);
  final Color _secondaryColor = const Color(0xFF168566);
  final Color _textColor = const Color(0xFF14263D);
  final Color _hintColor = const Color(0xFFA9B2AC);
  final Color _successColor = const Color(0xFF168566);
  final Color _errorColor = const Color(0xFFEF4444);

  void _validatePassword(String password) {
    setState(() {
      _hasMinLength = password.length >= 8;
      _hasUppercase = password.contains(RegExp(r'[A-Z]'));
      _hasLowercase = password.contains(RegExp(r'[a-z]'));
      _hasNumber = password.contains(RegExp(r'[0-9]'));
      _hasSpecialChar = password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'));
    });
  }

  bool get _isPasswordValid {
    return _hasMinLength &&
        _hasUppercase &&
        _hasLowercase &&
        _hasNumber &&
        _hasSpecialChar;
  }

  @override
  Widget build(BuildContext context) {
    return DPPage(
      title: 'Change password',
      bottom: DPButton(
        label: 'Change password',
        loading: _isLoading,
        onPressed: _isLoading ? null : _changePassword,
      ),
      children: [
        const DPHeadline(
          'Choose a strong password.',
          subtitle: 'You’ll use it to sign in on new devices.',
        ),
        if (_errorMessage != null) DPNotice(_errorMessage!, kind: DPNoticeKind.danger),
        if (_successMessage != null) DPNotice(_successMessage!, kind: DPNoticeKind.success),
        _buildPasswordField(
          controller: _currentPasswordController,
          label: 'Current password',
          hint: 'Enter your current password',
          obscure: _obscureCurrent,
          onToggle: () => setState(() => _obscureCurrent = !_obscureCurrent),
        ),
        _buildPasswordField(
          controller: _newPasswordController,
          label: 'New password',
          hint: 'At least 8 characters',
          obscure: _obscureNew,
          onToggle: () => setState(() => _obscureNew = !_obscureNew),
          onChanged: _validatePassword,
        ),
        DPCard(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Your password needs', style: DPText.label),
              const SizedBox(height: 8),
              _buildRequirement('At least 8 characters', _hasMinLength),
              _buildRequirement('An uppercase letter', _hasUppercase),
              _buildRequirement('A lowercase letter', _hasLowercase),
              _buildRequirement('A number', _hasNumber),
              _buildRequirement('A symbol, like ! @ # or ?', _hasSpecialChar),
            ],
          ),
        ),
        _buildPasswordField(
          controller: _confirmPasswordController,
          label: 'Confirm new password',
          hint: 'Type it again',
          obscure: _obscureConfirm,
          onToggle: () => setState(() => _obscureConfirm = !_obscureConfirm),
        ),
      ],
    );
  }

  Widget _buildPasswordField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required bool obscure,
    required VoidCallback onToggle,
    ValueChanged<String>? onChanged,
  }) {
    return DPField(
      label: label,
      controller: controller,
      hint: hint,
      obscure: obscure,
      suffixIcon: obscure ? DPIcons.eye : DPIcons.eyeOff,
      onSuffixTap: onToggle,
      onChanged: (v) {
        if (_errorMessage != null) setState(() => _errorMessage = null);
        onChanged?.call(v);
      },
    );
  }

  Widget _buildRequirement(String text, bool isMet) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          DPIcon(isMet ? DPIcons.circleCheck : DPIcons.circleX,
              size: 16, color: isMet ? DP.green : DP.faint),
          const SizedBox(width: 8),
          Text(text, style: DPText.small.copyWith(color: isMet ? DP.green : DP.muted, fontSize: 13)),
        ],
      ),
    );
  }

  Future<void> _changePassword() async {
    final current = _currentPasswordController.text.trim();
    final newPass = _newPasswordController.text.trim();
    final confirm = _confirmPasswordController.text.trim();

    if (current.isEmpty) {
      setState(() => _errorMessage = 'Please enter your current password');
      return;
    }

    if (newPass.isEmpty) {
      setState(() => _errorMessage = 'Please enter a new password');
      return;
    }

    if (newPass.length < 8) {
      setState(() => _errorMessage = 'Password must be at least 8 characters');
      return;
    }

    if (!_isPasswordValid) {
      setState(() => _errorMessage = 'Please meet all password requirements');
      return;
    }

    if (newPass != confirm) {
      setState(() => _errorMessage = 'Passwords do not match');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('userId');

      if (userId == null) {
        setState(() {
          _errorMessage = 'User not found. Please login again.';
          _isLoading = false;
        });
        return;
      }

      final result = await ApiService.changePassword(
        userId: userId,
        currentPassword: current,
        newPassword: newPass,
      );

      if (result['success'] == true) {
        setState(() {
          _successMessage =
              result['message'] ?? 'Password changed successfully!';
          _currentPasswordController.clear();
          _newPasswordController.clear();
          _confirmPasswordController.clear();
          _validatePassword('');
        });
        Future.delayed(const Duration(seconds: 2), () {
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
        });
      } else {
        setState(() {
          _errorMessage = result['message'] ?? 'Failed to change password.';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }
}
