// lib/presentation/screens/auth/forgot_password_screen.dart
// lib/presentation/screens/auth/forgot_password_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/services/api_service.dart'; // ← ADD THIS LINE

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

  static const Color _brand = Color(0xFF219C7E);
  static const Color _brandDark = Color(0xFF1C2D5A);
  static const Color _white = Colors.white;

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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.inter()),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
                    'Reset Password',
                    style: GoogleFonts.poppins(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: _brandDark,
                      height: 1.1,
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Subtitle
                  Text(
                    'Enter your email to receive a verification code',
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

                  // Email Field
                  const _FieldLabel(label: 'Email Address'),
                  const SizedBox(height: 8),
                  _buildEmailField(),

                  const SizedBox(height: 32),

                  // Send Reset Link Button
                  _buildSendButton(),

                  const SizedBox(height: 20),

                  // Back to Login Link
                  Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Remember your password? ',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            Navigator.pushReplacementNamed(context, '/login');
                          },
                          child: Text(
                            'Back to Login',
                            style: GoogleFonts.inter(
                              fontSize: 14,
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

  Widget _buildEmailField() {
    return TextFormField(
      controller: _emailController,
      keyboardType: TextInputType.emailAddress,
      style: GoogleFonts.inter(fontSize: 15, color: _brandDark),
      decoration: _fieldDecoration(
        hint: 'you@example.com',
        icon: Icons.email_outlined,
        errorText: _emailError.isEmpty ? null : _emailError,
        suffix:
            _isEmailValid
                ? const Icon(
                  Icons.check_circle_rounded,
                  color: Color(0xFF219C7E),
                  size: 20,
                )
                : null,
      ),
    );
  }

  Widget _buildSendButton() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: double.infinity,
      height: 54,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(13),
        gradient:
            _isEmailValid
                ? const LinearGradient(
                  colors: [Color(0xFF27B48F), Color(0xFF1A8A68)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
                : null,
        color: _isEmailValid ? null : Colors.grey.shade200,
        boxShadow:
            _isEmailValid
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
          onTap: _isLoading || !_isEmailValid ? null : _sendResetLink,
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
                      'SEND RESET LINK',
                      style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color:
                            _isEmailValid ? Colors.white : Colors.grey.shade400,
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
        color: const Color(0xFFF0FBF7),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF219C7E).withOpacity(0.15)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          const _TrustBadge(icon: Icons.shield_rounded, label: 'Secure'),
          Container(
            width: 1,
            height: 20,
            color: const Color(0xFF219C7E).withOpacity(0.18),
          ),
          const _TrustBadge(icon: Icons.bolt_rounded, label: 'Fast'),
          Container(
            width: 1,
            height: 20,
            color: const Color(0xFF219C7E).withOpacity(0.18),
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
      fillColor: const Color(0xFFF7FDFB),
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
        color: const Color(0xFF1C2D5A),
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
        Icon(icon, size: 16, color: const Color(0xFF219C7E)),
        const SizedBox(width: 6),
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF1C2D5A),
          ),
        ),
      ],
    );
  }
}
