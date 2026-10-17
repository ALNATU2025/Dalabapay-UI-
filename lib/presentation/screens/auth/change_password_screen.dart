// lib/presentation/screens/auth/change_password_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/services/api_service.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isLoading = false;
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  // Live password requirement flags
  bool _hasMinLength = false;
  bool _hasUppercase = false;
  bool _hasLowercase = false;
  bool _hasNumber = false;
  bool _hasSpecialChar = false;
  bool _isNewPasswordValid = false;
  bool _passwordsMatch = false;

  String _currentPasswordError = '';
  String _confirmPasswordError = '';

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  static const Color _brand = Color(0xFF168566);
  static const Color _brandDark = Color(0xFF14263D);
  static const Color _brandLight = Color(0xFFE8F7F3);
  static const Color _white = Colors.white;

  @override
  void initState() {
    super.initState();

    _newPasswordController.addListener(_validateNewPasswordLive);
    _confirmPasswordController.addListener(_validateConfirmLive);

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
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────
  // LIVE VALIDATION
  // ─────────────────────────────────────────────────────────────

  void _validateNewPasswordLive() {
    final value = _newPasswordController.text;
    setState(() {
      _hasMinLength = value.length >= 8;
      _hasUppercase = value.contains(RegExp(r'[A-Z]'));
      _hasLowercase = value.contains(RegExp(r'[a-z]'));
      _hasNumber = value.contains(RegExp(r'[0-9]'));
      _hasSpecialChar = value.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'));

      _isNewPasswordValid = _hasMinLength &&
          _hasUppercase &&
          _hasLowercase &&
          _hasNumber &&
          _hasSpecialChar;

      // Re-check confirm match if it has content
      if (_confirmPasswordController.text.isNotEmpty) {
        _validateConfirmLive();
      }
    });
  }

  void _validateConfirmLive() {
    final confirm = _confirmPasswordController.text;
    final newPass = _newPasswordController.text;
    setState(() {
      if (confirm.isEmpty) {
        _confirmPasswordError = '';
        _passwordsMatch = false;
      } else if (confirm != newPass) {
        _confirmPasswordError = 'Passwords do not match';
        _passwordsMatch = false;
      } else {
        _confirmPasswordError = '';
        _passwordsMatch = true;
      }
    });
  }

  bool get _formValid =>
      _currentPasswordController.text.isNotEmpty &&
      _isNewPasswordValid &&
      _passwordsMatch;

  // ─────────────────────────────────────────────────────────────
  // API CALL
  // ─────────────────────────────────────────────────────────────

  Future<void> _changePassword() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_isNewPasswordValid) {
      _showError('Please meet all password requirements');
      return;
    }
    if (!_passwordsMatch) {
      _showError('Passwords do not match');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('userId');

      if (userId == null) {
        _showError('User not logged in. Please log in again.');
        return;
      }

      final response = await ApiService.changePassword(
        userId: userId,
        currentPassword: _currentPasswordController.text,
        newPassword: _newPasswordController.text,
      );

      if (!mounted) return;

      if (response['success'] == true) {
        _showSuccessDialog(
          response['message'] ?? 'Password changed successfully!',
        );
        _clearForm();
      } else {
        _showError(response['message'] ?? 'Failed to change password');
      }
    } catch (e) {
      // Map common errors
      String msg = e.toString();
      if (msg.contains('current password') || msg.contains('incorrect')) {
        msg = 'Your current password is incorrect.';
      } else if (msg.contains('No internet')) {
        msg = 'No internet connection. Please check your network.';
      } else if (msg.contains('timeout')) {
        msg = 'Request timed out. Please try again.';
      }
      _showError(msg);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _clearForm() {
    _currentPasswordController.clear();
    _newPasswordController.clear();
    _confirmPasswordController.clear();
    setState(() {
      _hasMinLength = false;
      _hasUppercase = false;
      _hasLowercase = false;
      _hasNumber = false;
      _hasSpecialChar = false;
      _isNewPasswordValid = false;
      _passwordsMatch = false;
      _currentPasswordError = '';
      _confirmPasswordError = '';
    });
  }

  // ─────────────────────────────────────────────────────────────
  // FEEDBACK
  // ─────────────────────────────────────────────────────────────

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.inter()),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _showSuccessDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
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
              Container(
                width: 80,
                height: 80,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [Color(0xFF168566), Color(0xFF0F6B51)],
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
              Text(
                'Password Changed!',
                style: GoogleFonts.inter(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: _brandDark,
                  height: 1.2,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                message,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: Colors.grey[600],
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    // Return to wherever the user came from
                    if (Navigator.canPop(context)) {
                      Navigator.pop(context);
                    } else {
                      Navigator.pushReplacementNamed(context, '/login');
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _brand,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    'DONE',
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

  // ─────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────

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
              child: Form(
                key: _formKey,
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
                      'Change Password',
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
                      'Enter your current password and choose a new one',
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
                          colors: [
                            _brand.withOpacity(0.35),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Current Password
                    const _FieldLabel(label: 'Current Password'),
                    const SizedBox(height: 8),
                    _buildCurrentPasswordField(),

                    const SizedBox(height: 20),

                    // New Password
                    const _FieldLabel(label: 'New Password'),
                    const SizedBox(height: 8),
                    _buildNewPasswordField(),

                    // Password requirements (only when typing)
                    if (_newPasswordController.text.isNotEmpty &&
                        !_isNewPasswordValid)
                      Padding(
                        padding: const EdgeInsets.only(left: 12, top: 8),
                        child: _buildPasswordRequirements(),
                      ),

                    const SizedBox(height: 20),

                    // Confirm Password
                    const _FieldLabel(label: 'Confirm New Password'),
                    const SizedBox(height: 8),
                    _buildConfirmPasswordField(),

                    const SizedBox(height: 32),

                    // Submit Button
                    _buildSubmitButton(),

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
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // FIELD BUILDERS
  // ─────────────────────────────────────────────────────────────

  Widget _buildCurrentPasswordField() {
    return TextFormField(
      controller: _currentPasswordController,
      obscureText: _obscureCurrent,
      style: GoogleFonts.inter(fontSize: 15, color: _brandDark),
      onChanged: (_) => setState(() {}),
      decoration: _fieldDecoration(
        hint: 'Enter current password',
        icon: Icons.lock_outline,
        errorText:
            _currentPasswordError.isEmpty ? null : _currentPasswordError,
        suffix: IconButton(
          icon: Icon(
            _obscureCurrent
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
            color: Colors.grey[400],
            size: 20,
          ),
          onPressed: () => setState(() => _obscureCurrent = !_obscureCurrent),
        ),
      ),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Please enter your current password';
        }
        return null;
      },
    );
  }

  Widget _buildNewPasswordField() {
    return TextFormField(
      controller: _newPasswordController,
      obscureText: _obscureNew,
      style: GoogleFonts.inter(fontSize: 15, color: _brandDark),
      decoration: _fieldDecoration(
        hint: 'Enter new password',
        icon: Icons.lock_open_outlined,
        suffix: IconButton(
          icon: Icon(
            _obscureNew
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
            color: Colors.grey[400],
            size: 20,
          ),
          onPressed: () => setState(() => _obscureNew = !_obscureNew),
        ),
      ),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Please enter a new password';
        }
        return null;
      },
    );
  }

  Widget _buildConfirmPasswordField() {
    return TextFormField(
      controller: _confirmPasswordController,
      obscureText: _obscureConfirm,
      style: GoogleFonts.inter(fontSize: 15, color: _brandDark),
      decoration: _fieldDecoration(
        hint: 'Confirm new password',
        icon: Icons.lock_reset_outlined,
        errorText:
            _confirmPasswordError.isEmpty ? null : _confirmPasswordError,
        suffix: IconButton(
          icon: Icon(
            _obscureConfirm
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
            color: Colors.grey[400],
            size: 20,
          ),
          onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
        ),
      ),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Please confirm your new password';
        }
        if (value != _newPasswordController.text) {
          return 'Passwords do not match';
        }
        return null;
      },
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
          const SizedBox(height: 4),
          _buildRequirementItem('One special character', _hasSpecialChar),
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

  Widget _buildSubmitButton() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: double.infinity,
      height: 54,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(13),
        gradient: _formValid
            ? const LinearGradient(
                colors: [Color(0xFF168566), Color(0xFF0F6B51)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: _formValid ? null : Colors.grey.shade200,
        boxShadow: _formValid
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
          onTap: _isLoading || !_formValid ? null : _changePassword,
          child: Center(
            child: _isLoading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.5,
                    ),
                  )
                : Text(
                    'CHANGE PASSWORD',
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color:
                          _formValid ? Colors.white : Colors.grey.shade400,
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
        border: Border.all(color: _brand.withOpacity(0.15)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          const _TrustBadge(icon: Icons.shield_rounded, label: 'Secure'),
          Container(
            width: 1,
            height: 20,
            color: _brand.withOpacity(0.18),
          ),
          const _TrustBadge(icon: Icons.bolt_rounded, label: 'Fast'),
          Container(
            width: 1,
            height: 20,
            color: _brand.withOpacity(0.18),
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

// ─────────────────────────────────────────────────────────────
// REUSABLE WIDGETS
// ─────────────────────────────────────────────────────────────

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
        color: const Color(0xFF14263D),
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