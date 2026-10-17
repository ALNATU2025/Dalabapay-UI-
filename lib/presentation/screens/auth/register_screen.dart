// lib/presentation/screens/auth/register_screen.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/services/api_service.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _referralCodeController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _agreedToTerms = false;

  // ==================== EMAIL OTP VERIFICATION STATE ====================
  final _otpController = TextEditingController();
  bool _isOtpSent = false;
  bool _isOtpVerified = false;
  bool _isSendingOtp = false;
  bool _isVerifyingOtp = false;
  String _otpError = '';
  String _otpInfoMessage = '';

  // Live validation states
  String _fullNameError = '';
  String _emailError = '';
  String _phoneError = '';
  String _passwordError = '';
  String _confirmPasswordError = '';
  String _generalError = '';
  String _referralError = '';

  bool _isFullNameValid = false;
  bool _isEmailValid = false;
  bool _isPhoneValid = false;
  bool _isPasswordValid = false;
  bool _isConfirmPasswordValid = false;

  // Password requirements
  bool _hasMinLength = false;
  bool _hasUppercase = false;
  bool _hasLowercase = false;
  bool _hasNumber = false;

  // Referral validation
  final bool _isValidatingReferral = false;
  String? _referrerName;

  // ==================== ANIMATION ====================
  AnimationController? _fadeController;
  Animation<double>? _fadeAnimation;
  AnimationController? _pulseController;

  // ==================== BRAND COLORS ====================
  static const Color _primary = Color(0xFF1E377E);
  static const Color _primaryLight = Color(0xFF243889);
  static const Color _secondary = Color(0xFF219C7E);
  static const Color _secondaryLight = Color(0xFF92D394);
  static const Color _dark = Color(0xFF0A1628);
  static const Color _white = Colors.white;
  static const Color _greyText = Color(0xFF64748B);

  @override
  void initState() {
    super.initState();
    _fullNameController.addListener(_validateFullNameLive);
    _emailController.addListener(_validateEmailLive);
    _phoneController.addListener(_validatePhoneLive);
    _passwordController.addListener(_validatePasswordLive);
    _confirmPasswordController.addListener(_validateConfirmPasswordLive);
    _referralCodeController.addListener(_validateReferralLive);

    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController!,
      curve: Curves.easeOut,
    );
    _fadeController!.forward();

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _referralCodeController.dispose();
    _otpController.dispose();
    _fadeController?.dispose();
    _pulseController?.dispose();
    super.dispose();
  }

  // ==================== VALIDATION ====================
  void _validateFullNameLive() {
    final value = _fullNameController.text;
    setState(() {
      if (value.isEmpty) {
        _fullNameError = '';
        _isFullNameValid = false;
      } else if (value.length < 3) {
        _fullNameError = 'Full name must be at least 3 characters';
        _isFullNameValid = false;
      } else if (!RegExp(r"^[a-zA-ZÀ-ÿ\s'-]+$").hasMatch(value)) {
        _fullNameError =
            'Only letters, spaces, hyphens, and apostrophes allowed';
        _isFullNameValid = false;
      } else {
        _fullNameError = '';
        _isFullNameValid = true;
      }
    });
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

  void _validatePhoneLive() {
    final value = _phoneController.text;
    setState(() {
      if (value.isEmpty) {
        _phoneError = '';
        _isPhoneValid = false;
      } else if (value.length != 11) {
        _phoneError = 'Phone number must be exactly 11 digits';
        _isPhoneValid = false;
      } else if (!RegExp(r'^0\d{10}$').hasMatch(value)) {
        _phoneError = 'Must start with 0 and contain only digits';
        _isPhoneValid = false;
      } else {
        final prefix = value.substring(0, 3);
        const validPrefixes = ['070', '080', '081', '090', '091'];
        if (!validPrefixes.contains(prefix)) {
          _phoneError = 'Enter a valid Nigerian phone number';
          _isPhoneValid = false;
        } else {
          _phoneError = '';
          _isPhoneValid = true;
        }
      }
    });
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
        _passwordError = 'Password missing required characters';
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

  void _validateReferralLive() {
    final value = _referralCodeController.text;
    setState(() {
      if (value.isEmpty) {
        _referralError = '';
        _referrerName = null;
      } else if (value.length < 8) {
        _referralError = 'Referral code must be at least 8 characters';
        _referrerName = null;
      } else {
        _referralError = '';
      }
    });
  }

  bool get _formValid =>
      _isFullNameValid &&
      _isEmailValid &&
      _isPhoneValid &&
      _isPasswordValid &&
      _isConfirmPasswordValid &&
      _agreedToTerms &&
      _isOtpVerified;

  // ==================== OTP SEND & VERIFY ====================
  Future<void> _sendOtp() async {
    if (!_isEmailValid) {
      setState(() => _otpError = 'Enter a valid email address first');
      return;
    }

    setState(() {
      _isSendingOtp = true;
      _otpError = '';
      _otpInfoMessage = '';
    });

    try {
      final response = await ApiService.sendEmailVerificationOtp(
        email: _emailController.text.trim().toLowerCase(),
      );

      if (!mounted) return;

      if (response['success'] == true) {
        setState(() {
          _isOtpSent = true;
          _otpInfoMessage =
              'A 6-digit code has been sent to ${_emailController.text.trim()}. '
              'Check your inbox (and spam folder).';
        });
      } else {
        setState(() {
          _otpError = response['message']?.toString() ?? 'Failed to send code';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _otpError = e.toString().replaceAll('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _isSendingOtp = false);
    }
  }

  Future<void> _verifyOtp() async {
    final otp = _otpController.text.trim();
    if (otp.length != 6) {
      setState(() => _otpError = 'Enter the 6-digit code from your email');
      return;
    }

    setState(() {
      _isVerifyingOtp = true;
      _otpError = '';
    });

    try {
      final response = await ApiService.verifyEmailWithOTP(
        email: _emailController.text.trim().toLowerCase(),
        otp: otp,
      );

      if (!mounted) return;

      if (response['success'] == true) {
        setState(() {
          _isOtpVerified = true;
          _otpInfoMessage = 'Email verified successfully';
          _otpError = '';
        });
      } else {
        setState(() {
          _isOtpVerified = false;
          _otpError =
              response['message']?.toString() ?? 'Invalid or expired code';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isOtpVerified = false;
        _otpError = e.toString().replaceAll('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _isVerifyingOtp = false);
    }
  }

  // ==================== REGISTRATION HANDLER ====================
  Future<void> _handleRegister() async {
    if (!_formValid) return;

    if (!_isOtpVerified) {
      _showUserFriendlyError(
        'Please verify your email address before creating an account.',
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _generalError = '';
    });

    try {
      final response = await ApiService.registerUser(
        fullName: _fullNameController.text.trim(),
        email: _emailController.text.trim(),
        phone: _phoneController.text.trim(),
        password: _passwordController.text,
        otp: _otpController.text.trim(), // ✅ REAL OTP
        referralCode: _referralCodeController.text.trim().isEmpty
            ? null
            : _referralCodeController.text.trim(),
      );

      if (!mounted) return;

      if (response['success'] == true) {
        await _handleRegistrationSuccess(response);
      } else {
        _showUserFriendlyError(response['message']);
      }
    } catch (e) {
      if (!mounted) return;
      _showUserFriendlyError(e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleRegistrationSuccess(Map<String, dynamic> response) async {
    try {
      await Future.delayed(const Duration(milliseconds: 300));

      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();

      String userId = prefs.getString('userId') ?? '';

      if (userId.isEmpty) {
        final userData = response['user'] ?? response['data'] ?? {};
        userId = userData['_id']?.toString() ??
            userData['id']?.toString() ??
            userData['userId']?.toString() ??
            response['userId']?.toString() ??
            '';
      }

      final fullName = _fullNameController.text.trim();
      final email = _emailController.text.trim();

      if (userId.isEmpty) {
        _showUserFriendlyError(
          'Registration completed but we couldn\'t retrieve your account ID. '
          'Please try logging in manually.',
        );
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) {
          Navigator.pushReplacementNamed(context, '/login');
        }
        return;
      }

      await prefs.setString('userId', userId);
      await prefs.setString('fullName', fullName);
      await prefs.setString('email', email);

      final userObject = {
        '_id': userId,
        'fullName': fullName,
        'email': email,
        'transactionPinSet': false,
      };
      await prefs.setString('user', jsonEncode(userObject));
      await prefs.reload();

      _showSuccessSnackBar('Account created successfully! Set up your PIN.');

      Navigator.pushReplacementNamed(
        context,
        '/pin-setup',
        arguments: {
          'userId': userId,
          'fullName': fullName,
          'email': email,
          'isFirstTime': true,
        },
      );
    } catch (e) {
      debugPrint('❌ Registration success handling error: $e');
      _showUserFriendlyError(
        'Account created but setup failed. Please try logging in.',
      );
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/login');
      }
    }
  }

  // ==================== USER-FRIENDLY ERROR HANDLING ====================
  void _showUserFriendlyError(String error) {
    String userMessage;
    final cleanError = _cleanErrorMessage(error);

    if (cleanError.contains('Network') ||
        cleanError.contains('connection') ||
        cleanError.contains('internet') ||
        cleanError.contains('Failed to fetch') ||
        cleanError.contains('SocketException') ||
        cleanError.contains('ClientException')) {
      userMessage =
          'No internet connection. Please check your network and try again.';
    } else if (cleanError.contains('timeout') ||
        cleanError.contains('timed out')) {
      userMessage = 'Request timed out. Please try again.';
    } else if (cleanError.contains('already registered') ||
        cleanError.contains('already exists') ||
        cleanError.contains('duplicate') ||
        cleanError.contains('Email already')) {
      userMessage =
          'This email or phone number is already registered. Please use a different one or login.';
    } else if (cleanError.contains('OTP') ||
        cleanError.contains('verification')) {
      userMessage = 'Verification failed. Please try again.';
    } else if (cleanError.contains('server') ||
        cleanError.contains('500') ||
        cleanError.contains('502') ||
        cleanError.contains('503')) {
      userMessage =
          'Registration service is temporarily unavailable. Please try again later.';
    } else if (cleanError.contains('rate limit') ||
        cleanError.contains('too many')) {
      userMessage = 'Too many attempts. Please wait a moment and try again.';
    } else if (cleanError.contains('referral') ||
        cleanError.contains('invalid code')) {
      userMessage = 'Invalid referral code. Please check and try again.';
    } else {
      userMessage = cleanError.isNotEmpty
          ? cleanError
          : 'Unable to create account. Please try again.';
    }

    _showErrorDialog(userMessage);
  }

  String _cleanErrorMessage(String error) {
    String cleaned = error.replaceAll(RegExp(r'https?://[^\s]+'), '');
    cleaned = cleaned.replaceAll(RegExp(r'http://[^\s]+'), '');
    cleaned = cleaned.replaceAll(
      RegExp(r'[A-Za-z0-9.-]+\.[A-Za-z]{2,}(/\S*)?'),
      '',
    );
    cleaned = cleaned.replaceAll('Exception:', '');
    cleaned = cleaned.replaceAll('ClientException:', '');
    cleaned = cleaned.replaceAll('SocketException:', '');
    cleaned = cleaned.replaceAll('DioError:', '');
    cleaned = cleaned.trim();

    return cleaned.isEmpty
        ? 'Unable to create account. Please try again.'
        : cleaned;
  }

  // ==================== DIALOGS & SNACKBARS ====================
  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 30,
                spreadRadius: 5,
                offset: const Offset(0, 15),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.error_outline_rounded,
                  color: Colors.red.shade400,
                  size: 36,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Registration Failed',
                style: GoogleFonts.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: _primaryLight,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: _greyText,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _secondary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    'Try Again',
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
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

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle_rounded, color: _secondary, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text(message, style: GoogleFonts.inter())),
          ],
        ),
        backgroundColor: const Color(0xFFF8FAFC),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ==================== BUILD ====================
  @override
  Widget build(BuildContext context) {
    final fadeAnimation = _fadeAnimation ?? const AlwaysStoppedAnimation(1.0);

    return Scaffold(
      backgroundColor: _white,
      body: SafeArea(
        child: Stack(
          children: [
            _buildAuroraEffects(),
            FadeTransition(
              opacity: fadeAnimation,
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLogo(),
                    const SizedBox(height: 8),
                    Text(
                      'Smart Life, Fast Pay',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _secondary,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 32),
                    _buildGlassCard(),
                    const SizedBox(height: 20),
                    _buildTrustStrip(),
                    const SizedBox(height: 20),
                    Center(
                      child: Text(
                        'Version 1.5.0',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: Colors.grey.shade300,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== AURORA EFFECTS ====================
  Widget _buildAuroraEffects() {
    final pulseValue = _pulseController?.value ?? 0.0;

    return Stack(
      children: [
        Positioned(
          top: -100,
          right: -100,
          child: AnimatedBuilder(
            animation: _pulseController ?? const AlwaysStoppedAnimation(0.0),
            builder: (context, child) {
              return Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFF219C7E).withOpacity(0.08),
                      const Color(0xFF219C7E).withOpacity(0.03),
                      Colors.transparent,
                    ],
                    stops: const [0, 0.5, 1],
                  ),
                  shape: BoxShape.circle,
                ),
                transform: Matrix4.identity()..scale(1 + pulseValue * 0.1),
              );
            },
          ),
        ),
        Positioned(
          bottom: -150,
          left: -100,
          child: AnimatedBuilder(
            animation: _pulseController ?? const AlwaysStoppedAnimation(0.0),
            builder: (context, child) {
              return Container(
                width: 250,
                height: 250,
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFF1E377E).withOpacity(0.08),
                      const Color(0xFF1E377E).withOpacity(0.03),
                      Colors.transparent,
                    ],
                    stops: const [0, 0.5, 1],
                  ),
                  shape: BoxShape.circle,
                ),
                transform: Matrix4.identity()..scale(1 + pulseValue * 0.15),
              );
            },
          ),
        ),
        ...List.generate(8, (index) {
          return Positioned(
            top: 30 + (index * 50) % 500,
            left: 10 + (index * 35) % 350,
            child: Container(
              width: 2 + (index % 3).toDouble(),
              height: 2 + (index % 3).toDouble(),
              decoration: BoxDecoration(
                color: const Color(0xFF219C7E).withOpacity(0.08),
                shape: BoxShape.circle,
              ),
            ),
          );
        }),
      ],
    );
  }

  // ==================== LOGO ====================
  Widget _buildLogo() {
    return Row(
      children: [
        Image.asset('assets/dalabapay2.png', height: 48, fit: BoxFit.contain),
      ],
    );
  }

  // ==================== GLASS CARD ====================
  Widget _buildGlassCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withOpacity(0.9),
            Colors.white.withOpacity(0.7),
          ],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withOpacity(0.3), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 40,
            spreadRadius: 5,
            offset: const Offset(0, 20),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Create Account',
            style: GoogleFonts.poppins(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: _primaryLight,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Join us and start your journey',
            style: GoogleFonts.inter(
              fontSize: 14,
              color: _greyText,
              height: 1.4,
            ),
          ),

          const SizedBox(height: 24),

          Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.grey.shade200, Colors.grey.shade100],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // ── FULL NAME ──────────────────────────────────────────
          const _FieldLabel(label: 'Full Name'),
          const SizedBox(height: 6),
          _buildFullNameField(),

          const SizedBox(height: 18),

          // ── EMAIL ─────────────────────────────────────────────
          const _FieldLabel(label: 'Email Address'),
          const SizedBox(height: 6),
          _buildEmailField(),

          const SizedBox(height: 10),

          // ── EMAIL VERIFICATION BLOCK ─────────────────────────
          _buildEmailVerificationBlock(),

          const SizedBox(height: 18),

          // ── PHONE ─────────────────────────────────────────────
          const _FieldLabel(label: 'Phone Number'),
          const SizedBox(height: 6),
          _buildPhoneField(),

          const SizedBox(height: 18),

          // ── PASSWORD ──────────────────────────────────────────
          const _FieldLabel(label: 'Password'),
          const SizedBox(height: 6),
          _buildPasswordField(),

          if (_passwordController.text.isNotEmpty && !_isPasswordValid)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _buildPasswordRequirements(),
            ),

          const SizedBox(height: 18),

          // ── CONFIRM PASSWORD ─────────────────────────────────
          const _FieldLabel(label: 'Confirm Password'),
          const SizedBox(height: 6),
          _buildConfirmPasswordField(),

          const SizedBox(height: 18),

          // ── REFERRAL ──────────────────────────────────────────
          const _FieldLabel(label: 'Referral Code (Optional)'),
          const SizedBox(height: 6),
          _buildReferralField(),

          const SizedBox(height: 18),

          // ── TERMS ─────────────────────────────────────────────
          _buildTermsCheckbox(),

          const SizedBox(height: 24),

          // ── REGISTER BUTTON ──────────────────────────────────
          _buildRegisterButton(),

          const SizedBox(height: 16),

          // ── LOGIN LINK ────────────────────────────────────────
          Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Already have an account? ',
                  style: GoogleFonts.inter(fontSize: 14, color: _greyText),
                ),
                GestureDetector(
                  onTap: () {
                    Navigator.pushReplacementNamed(context, '/login');
                  },
                  child: Text(
                    'Sign In',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _secondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==================== EMAIL VERIFICATION BLOCK ====================
  Widget _buildEmailVerificationBlock() {
    // ── STATE 1: VERIFIED ──────────────────────────────────────
    if (_isOtpVerified) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFE8F9F2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _secondary.withOpacity(0.4)),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.verified_rounded,
              color: Color(0xFF219C7E),
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Email verified successfully',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF1E377E),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // ── STATE 2: OTP SENT — WAITING FOR CODE ──────────────────
    if (_isOtpSent) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FBF7),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _secondary.withOpacity(0.2)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.mark_email_read_rounded,
                  color: Color(0xFF219C7E),
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _otpInfoMessage.isNotEmpty
                        ? _otpInfoMessage
                        : 'Check your email for the 6-digit code.',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: const Color(0xFF1E377E),
                      height: 1.4,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _isSendingOtp ? null : _sendOtp,
                  child: Text(
                    'Resend',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _secondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const _FieldLabel(label: 'Enter 6-Digit Code'),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _build3DField(
                  child: TextFormField(
                    controller: _otpController,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 8,
                      color: _primaryLight,
                    ),
                    decoration: _fieldDecoration(
                      hint: '••••••',
                      icon: Icons.password_rounded,
                      counterText: '',
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 54,
                child: ElevatedButton(
                  onPressed: _isVerifyingOtp ? null : _verifyOtp,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _secondary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    elevation: 0,
                  ),
                  child: _isVerifyingOtp
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          'Verify',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
            ],
          ),
          if (_otpError.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _otpError,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: Colors.redAccent,
                ),
              ),
            ),
        ],
      );
    }

    // ── STATE 3: NO OTP SENT YET — SHOW BUTTON ────────────────
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton.icon(
            onPressed: (_isEmailValid && !_isSendingOtp) ? _sendOtp : null,
            icon: _isSendingOtp
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF219C7E),
                    ),
                  )
                : const Icon(Icons.mail_outline_rounded, size: 18),
            label: Text(
              _isSendingOtp ? 'Sending code...' : 'Verify Email Address',
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: _secondary,
              side: BorderSide(
                color: _isEmailValid ? _secondary : Colors.grey.shade300,
                width: 1.4,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
        if (_otpError.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _otpError,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: Colors.redAccent,
              ),
            ),
          ),
      ],
    );
  }

  // ==================== FORM FIELDS ====================
  Widget _buildFullNameField() {
    return _build3DField(
      child: TextFormField(
        controller: _fullNameController,
        style: GoogleFonts.inter(fontSize: 15, color: _primaryLight),
        decoration: _fieldDecoration(
          hint: 'John Doe',
          icon: Icons.person_outline_rounded,
          errorText: _fullNameError.isEmpty ? null : _fullNameError,
          suffix: _isFullNameValid
              ? Icon(Icons.check_circle_rounded, color: _secondary, size: 20)
              : null,
        ),
      ),
    );
  }

  Widget _buildEmailField() {
    return _build3DField(
      child: TextFormField(
        controller: _emailController,
        keyboardType: TextInputType.emailAddress,
        style: GoogleFonts.inter(fontSize: 15, color: _primaryLight),
        decoration: _fieldDecoration(
          hint: 'you@example.com',
          icon: Icons.mail_outline_rounded,
          errorText: _emailError.isEmpty ? null : _emailError,
          suffix: _isEmailValid
              ? Icon(Icons.check_circle_rounded, color: _secondary, size: 20)
              : null,
        ),
      ),
    );
  }

  Widget _buildPhoneField() {
    return _build3DField(
      child: TextFormField(
        controller: _phoneController,
        keyboardType: TextInputType.phone,
        style: GoogleFonts.inter(fontSize: 15, color: _primaryLight),
        maxLength: 11,
        decoration: _fieldDecoration(
          hint: '09012345678',
          icon: Icons.phone_outlined,
          errorText: _phoneError.isEmpty ? null : _phoneError,
          suffix: _isPhoneValid
              ? Icon(Icons.check_circle_rounded, color: _secondary, size: 20)
              : null,
          counterText: '',
        ),
      ),
    );
  }

  Widget _buildPasswordField() {
    return _build3DField(
      child: TextFormField(
        controller: _passwordController,
        obscureText: _obscurePassword,
        style: GoogleFonts.inter(fontSize: 15, color: _primaryLight),
        decoration: _fieldDecoration(
          hint: '••••••••',
          icon: Icons.lock_outline_rounded,
          errorText: _passwordError.isEmpty ? null : _passwordError,
          suffix: IconButton(
            icon: Icon(
              _obscurePassword
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              color: Colors.grey.shade400,
              size: 20,
            ),
            onPressed: () =>
                setState(() => _obscurePassword = !_obscurePassword),
          ),
        ),
      ),
    );
  }

  Widget _buildConfirmPasswordField() {
    return _build3DField(
      child: TextFormField(
        controller: _confirmPasswordController,
        obscureText: _obscureConfirmPassword,
        style: GoogleFonts.inter(fontSize: 15, color: _primaryLight),
        decoration: _fieldDecoration(
          hint: '••••••••',
          icon: Icons.lock_outline_rounded,
          errorText:
              _confirmPasswordError.isEmpty ? null : _confirmPasswordError,
          suffix: IconButton(
            icon: Icon(
              _obscureConfirmPassword
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              color: Colors.grey.shade400,
              size: 20,
            ),
            onPressed: () => setState(
              () => _obscureConfirmPassword = !_obscureConfirmPassword,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReferralField() {
    return _build3DField(
      child: TextFormField(
        controller: _referralCodeController,
        style: GoogleFonts.inter(fontSize: 15, color: _primaryLight),
        decoration: _fieldDecoration(
          hint: 'Enter referral code (optional)',
          icon: Icons.card_giftcard_outlined,
          errorText: _referralError.isEmpty ? null : _referralError,
          suffix: _isValidatingReferral
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : (_referrerName != null
                  ? Icon(Icons.verified_rounded, color: _secondary, size: 20)
                  : null),
        ),
      ),
    );
  }

  // ==================== 3D FIELD WRAPPER ====================
  Widget _build3DField({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
            spreadRadius: 1,
          ),
          BoxShadow(
            color: Colors.white.withOpacity(0.6),
            blurRadius: 2,
            offset: const Offset(0, -1),
            spreadRadius: 0,
          ),
        ],
      ),
      child: child,
    );
  }

  // ==================== FIELD DECORATION ====================
  InputDecoration _fieldDecoration({
    required String hint,
    required IconData icon,
    String? errorText,
    Widget? suffix,
    String? counterText,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.inter(color: Colors.grey.shade400, fontSize: 14),
      errorText: errorText,
      errorStyle: GoogleFonts.inter(fontSize: 11, color: Colors.redAccent),
      prefixIcon: Icon(icon, color: _secondary, size: 20),
      suffixIcon: suffix,
      counterText: counterText,
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: _secondary, width: 1.8),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1.2),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1.6),
      ),
    );
  }

  // ==================== PASSWORD REQUIREMENTS ====================
  Widget _buildPasswordRequirements() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FBF7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _secondary.withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Password requirements:',
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: _primaryLight,
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
          color: isValid ? _secondary : Colors.grey.shade400,
        ),
        const SizedBox(width: 6),
        Text(
          text,
          style: GoogleFonts.inter(
            fontSize: 10,
            color: isValid ? _secondary : Colors.grey.shade500,
            decoration: isValid ? TextDecoration.lineThrough : null,
          ),
        ),
      ],
    );
  }

  // ==================== TERMS CHECKBOX ====================
  Widget _buildTermsCheckbox() {
    return Row(
      children: [
        SizedBox(
          width: 20,
          height: 20,
          child: Checkbox(
            value: _agreedToTerms,
            onChanged: (value) =>
                setState(() => _agreedToTerms = value ?? false),
            activeColor: _secondary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text.rich(
            TextSpan(
              text: 'I agree to the ',
              style: GoogleFonts.inter(fontSize: 12, color: _greyText),
              children: [
                TextSpan(
                  text: 'Terms of Service',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _secondary,
                  ),
                ),
                TextSpan(
                  text: ' and ',
                  style: GoogleFonts.inter(fontSize: 12, color: _greyText),
                ),
                TextSpan(
                  text: 'Privacy Policy',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _secondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ==================== REGISTER BUTTON ====================
  Widget _buildRegisterButton() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: _formValid
            ? const LinearGradient(
                colors: [Color(0xFF219C7E), Color(0xFF1A8A68)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: _formValid ? null : Colors.grey.shade200,
        boxShadow: _formValid
            ? [
                BoxShadow(
                  color: _secondary.withOpacity(0.35),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ]
            : [],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _isLoading || !_formValid ? null : _handleRegister,
          child: Center(
            child: _isLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.5,
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'CREATE ACCOUNT',
                        style: GoogleFonts.poppins(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: _formValid
                              ? Colors.white
                              : Colors.grey.shade400,
                          letterSpacing: 1.5,
                        ),
                      ),
                      if (_formValid) ...[
                        const SizedBox(width: 8),
                        Icon(
                          Icons.arrow_forward_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                      ],
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  // ==================== TRUST STRIP ====================
  Widget _buildTrustStrip() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200, width: 1),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          const _TrustBadge(icon: Icons.shield_rounded, label: 'Secure'),
          Container(width: 1, height: 20, color: Colors.grey.shade200),
          const _TrustBadge(icon: Icons.bolt_rounded, label: 'Fast'),
          Container(width: 1, height: 20, color: Colors.grey.shade200),
          const _TrustBadge(icon: Icons.verified_rounded, label: 'Reliable'),
        ],
      ),
    );
  }
}

// ==================== REUSABLE WIDGETS ====================

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