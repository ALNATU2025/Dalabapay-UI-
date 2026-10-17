// lib/presentation/screens/auth/reset_password_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/services/api_service.dart';

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

  static const Color _brand = Color(0xFF079A68);
  static const Color _brandDark = Color(0xFF10255A);
  static const Color _brandLight = Color(0xFFE8F7F3);
  static const Color _white = Colors.white;

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
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            elevation: 24,
            child: Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                color: _white,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Success Animation Icon
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [Color(0xFF079A68), Color(0xFF026C45)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      size: 50,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Title
                  Text(
                    'Password Reset Successfully!',
                    style: GoogleFonts.inter(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: _brandDark,
                      height: 1.2,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  // Message
                  Text(
                    'Your password has been successfully changed.\nYou can now log in with your new password.',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: Colors.grey[600],
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),
                  // Login Button
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        Navigator.of(
                          context,
                        ).pushNamedAndRemoveUntil('/login', (route) => false);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _brand,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        'LOGIN NOW',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
    );
  }

  void _showErrorDialog(String errorMessage) {
    // Extract user-friendly message
    String title = 'Reset Failed';
    String message = errorMessage;
    List<String> suggestions = [];

    if (errorMessage.contains('expired') || errorMessage.contains('Expired')) {
      title = 'Link Expired';
      message = 'Your password reset link has expired.';
      suggestions = [
        'Request a new password reset link',
        'Check your email for the new link',
        'Make sure to reset within 10 minutes',
      ];
    } else if (errorMessage.contains('weak') || errorMessage.contains('Weak')) {
      title = 'Weak Password';
      message = 'Your password is too weak.';
      suggestions = [
        'Use at least 8 characters',
        'Include uppercase and lowercase letters',
        'Add at least one number',
      ];
    } else if (errorMessage.contains('same') ||
        errorMessage.contains('previous')) {
      title = 'Password Already Used';
      message = 'You cannot use a previous password.';
      suggestions = [
        'Try a completely new password',
        'Use a combination of letters and numbers',
        'Make it unique and memorable',
      ];
    } else if (errorMessage.contains('network') ||
        errorMessage.contains('connection')) {
      title = 'Network Error';
      message = 'Unable to connect to the server.';
      suggestions = [
        'Check your internet connection',
        'Try again in a few moments',
        'Ensure you have stable network',
      ];
    } else {
      suggestions = [
        'Check your internet connection',
        'Try again in a few moments',
        'Contact support if issue persists',
      ];
    }

    showDialog(
      context: context,
      builder:
          (context) => Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            elevation: 24,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                color: _white,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Error Icon
                  Container(
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.red.withOpacity(0.1),
                    ),
                    child: const Icon(
                      Icons.error_outline_rounded,
                      size: 40,
                      color: Colors.red,
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Title
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: _brandDark,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  // Error Message
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      message,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: Colors.red.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Suggestions
                  Container(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'What you can do:',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _brandDark,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...suggestions.map(
                    (suggestion) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          Icon(
                            Icons.lightbulb_outline,
                            size: 16,
                            color: _brand,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              suggestion,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: Colors.grey[700],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Action Buttons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: _brand),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: Text(
                            'TRY AGAIN',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: _brand,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            // Close the dialog
                            Navigator.of(context).pop();
                            // Clear entire stack and go back to forgot password
                            Navigator.of(context).pushNamedAndRemoveUntil(
                              '/forgot-password',
                              (route) => false,
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _brand,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: Text(
                            'REQUEST NEW',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
    );
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
                      'assets/images/dalabapay2.png',
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
                    'Create New Password',
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
                    'Enter your new password below',
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

                  const SizedBox(height: 24),

                  // New Password Field
                  const _FieldLabel(label: 'New Password'),
                  const SizedBox(height: 8),
                  _buildPasswordField(),

                  // Password requirements
                  if (_passwordController.text.isNotEmpty && !_isPasswordValid)
                    Padding(
                      padding: const EdgeInsets.only(left: 12, top: 8),
                      child: _buildPasswordRequirements(),
                    ),

                  const SizedBox(height: 20),

                  // Confirm Password Field
                  const _FieldLabel(label: 'Confirm Password'),
                  const SizedBox(height: 8),
                  _buildConfirmPasswordField(),

                  const SizedBox(height: 32),

                  // Reset Password Button
                  _buildResetButton(),

                  const SizedBox(height: 20),

                  // Back to Login Link
                  Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Remember your password? ',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: Colors.grey[600],
                          ),
                        ),
                        GestureDetector(
                          onTap:
                              () => Navigator.pushReplacementNamed(
                                context,
                                '/login',
                              ),
                          child: Text(
                            'Back to Login',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: _brand,
                            ),
                          ),
                        ),
                      ],
                    ),
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

  Widget _buildPasswordField() {
    return TextFormField(
      controller: _passwordController,
      obscureText: _obscurePassword,
      style: GoogleFonts.inter(fontSize: 15, color: _brandDark),
      decoration: _fieldDecoration(
        hint: 'Enter new password',
        icon: Icons.lock_outline,
        errorText: _passwordError.isEmpty ? null : _passwordError,
        suffix: IconButton(
          icon: Icon(
            _obscurePassword
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
            color: Colors.grey[400],
            size: 20,
          ),
          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
        ),
      ),
    );
  }

  Widget _buildConfirmPasswordField() {
    return TextFormField(
      controller: _confirmPasswordController,
      obscureText: _obscureConfirmPassword,
      style: GoogleFonts.inter(fontSize: 15, color: _brandDark),
      decoration: _fieldDecoration(
        hint: 'Confirm new password',
        icon: Icons.lock_outline,
        errorText: _confirmPasswordError.isEmpty ? null : _confirmPasswordError,
        suffix: IconButton(
          icon: Icon(
            _obscureConfirmPassword
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
            color: Colors.grey[400],
            size: 20,
          ),
          onPressed:
              () => setState(
                () => _obscureConfirmPassword = !_obscureConfirmPassword,
              ),
        ),
      ),
    );
  }

  Widget _buildPasswordRequirements() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _brandLight,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Password requirements:',
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: _brandDark,
            ),
          ),
          const SizedBox(height: 8),
          _buildRequirementItem('At least 8 characters', _hasMinLength),
          const SizedBox(height: 4),
          _buildRequirementItem('One uppercase letter', _hasUppercase),
          const SizedBox(height: 4),
          _buildRequirementItem('One lowercase letter', _hasLowercase),
          const SizedBox(height: 4),
          _buildRequirementItem('One number', _hasNumber),
        ],
      ),
    );
  }

  Widget _buildRequirementItem(String text, bool isValid) {
    return Row(
      children: [
        Icon(
          isValid ? Icons.check_circle : Icons.radio_button_unchecked,
          size: 12,
          color: isValid ? _brand : Colors.grey[400],
        ),
        const SizedBox(width: 6),
        Text(
          text,
          style: GoogleFonts.inter(
            fontSize: 10,
            color: isValid ? _brand : Colors.grey[500],
            decoration: isValid ? TextDecoration.lineThrough : null,
          ),
        ),
      ],
    );
  }

  Widget _buildResetButton() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: double.infinity,
      height: 54,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(13),
        gradient:
            _formValid
                ? const LinearGradient(
                  colors: [Color(0xFF079A68), Color(0xFF026C45)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
                : null,
        color: _formValid ? null : Colors.grey.shade200,
        boxShadow:
            _formValid
                ? [
                  BoxShadow(
                    color: _brand.withOpacity(0.35),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ]
                : [],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(13),
          onTap: _isLoading || !_formValid ? null : _resetPassword,
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
                      'RESET PASSWORD',
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: _formValid ? Colors.white : Colors.grey.shade400,
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
        border: Border.all(color: const Color(0xFF079A68).withOpacity(0.15)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          const _TrustBadge(icon: Icons.shield_rounded, label: 'Secure'),
          Container(
            width: 1,
            height: 20,
            color: const Color(0xFF079A68).withOpacity(0.18),
          ),
          const _TrustBadge(icon: Icons.bolt_rounded, label: 'Fast'),
          Container(
            width: 1,
            height: 20,
            color: const Color(0xFF079A68).withOpacity(0.18),
          ),
          const _TrustBadge(icon: Icons.verified_rounded, label: 'Reliable'),
        ],
      ),
    );
  }

  InputDecoration _fieldDecoration({
    required String hint,
    required IconData icon,
    String? errorText,
    Widget? suffix,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.inter(color: Colors.grey[350], fontSize: 14),
      errorText: errorText,
      errorStyle: GoogleFonts.inter(fontSize: 12, color: Colors.redAccent),
      prefixIcon: Icon(icon, color: _brand, size: 20),
      suffixIcon: suffix,
      filled: true,
      fillColor: const Color(0xFFF3FAF6),
      contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _brand, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1.2),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1.6),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String label;
  const _FieldLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: GoogleFonts.inter(
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        color: const Color(0xFF10255A),
        letterSpacing: 0.3,
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
        Icon(icon, size: 16, color: const Color(0xFF079A68)),
        const SizedBox(width: 6),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF10255A),
          ),
        ),
      ],
    );
  }
}
