// lib/presentation/screens/auth/register_screen.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/services/api_service.dart';
import '../../../ui/ui.dart';

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
        insetPadding: const EdgeInsets.symmetric(horizontal: 28),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const DPIconBadge(
                icon: DPIcons.circleAlert,
                bg: DP.dangerSoft,
                fg: DP.danger,
                size: 60,
                radius: 30,
              ),
              const SizedBox(height: 16),
              Text('We couldn’t create your account',
                  textAlign: TextAlign.center,
                  style: DPText.title.copyWith(fontWeight: FontWeight.w500)),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center, style: DPText.bodyMuted),
              const SizedBox(height: 22),
              DPButton(label: 'Try again', onPressed: () => Navigator.pop(ctx)),
            ],
          ),
        ),
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    dpSnack(context, message, success: true);
  }

  // ==================== BUILD ====================
  @override
  Widget build(BuildContext context) {
    final fadeAnimation = _fadeAnimation ?? const AlwaysStoppedAnimation(1.0);
    return DPPage(
      title: 'Create your account',
      onBack: () {
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        } else {
          Navigator.pushReplacementNamed(context, '/login');
        }
      },
      formKey: _formKey,
      children: [
        FadeTransition(
          opacity: fadeAnimation,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const DPHeadline(
                'Make room for simpler.',
                subtitle: 'Your bills, wallet and rewards. Together.',
              ),
              _buildFullNameField(),
              _buildEmailField(),
              _buildEmailVerificationBlock(),
              const SizedBox(height: 18),
              _buildPhoneField(),
              _buildPasswordField(),
              _buildPasswordRequirements(),
              const SizedBox(height: 18),
              _buildConfirmPasswordField(),
              _buildReferralField(),
              _buildTermsCheckbox(),
              const SizedBox(height: 22),
              _buildRegisterButton(),
              const SizedBox(height: 18),
              Center(
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('Already have an account?', style: DPText.bodyMuted),
                    DPLinkButton(
                      label: 'Log in',
                      onPressed: () => Navigator.pushReplacementNamed(context, '/login'),
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

  // ==================== EMAIL VERIFICATION BLOCK ====================
  Widget _buildEmailVerificationBlock() {
    // ── STATE 1: VERIFIED ──────────────────────────────────────
    if (_isOtpVerified) {
      return DPVerifiedName(
        name: 'Email verified',
        detail: _emailController.text.trim(),
        margin: EdgeInsets.zero,
      );
    }

    // ── STATE 2: OTP SENT — WAITING FOR CODE ──────────────────
    if (_isOtpSent) {
      return DPCard(
        margin: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const DPIconBadge(
                  icon: DPIcons.mail,
                  bg: DP.greenSoft,
                  fg: DP.green,
                  size: 40,
                  radius: 12,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('One quick check',
                      style: DPText.body.copyWith(fontWeight: FontWeight.w500)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              _otpInfoMessage.isNotEmpty
                  ? _otpInfoMessage
                  : 'Enter the 6-digit code we sent to your email.',
              style: DPText.small.copyWith(fontSize: 13),
            ),
            const SizedBox(height: 16),
            DPCodeInput(
              controller: _otpController,
              length: 6,
              autofocus: true,
              error: _otpError.isNotEmpty,
              onCompleted: (_) {
                if (!_isVerifyingOtp) _verifyOtp();
              },
            ),
            if (_otpError.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(_otpError, style: DPText.small.copyWith(color: DP.danger)),
            ],
            const SizedBox(height: 16),
            DPButton(
              label: 'Verify email',
              loading: _isVerifyingOtp,
              onPressed: _isVerifyingOtp ? null : _verifyOtp,
              height: 50,
            ),
            const SizedBox(height: 6),
            Center(
              child: DPLinkButton(
                label: _isSendingOtp ? 'Sending…' : 'Resend code',
                onPressed: _isSendingOtp ? null : _sendOtp,
              ),
            ),
            const SizedBox(height: 4),
            const DPNotice(
              'Can’t find your code? Check your spam folder and make sure the email address is correct.',
              margin: EdgeInsets.zero,
            ),
          ],
        ),
      );
    }

    // ── STATE 3: NO OTP SENT YET — SHOW BUTTON ────────────────
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DPButton(
          kind: DPButtonKind.soft,
          label: _isSendingOtp ? 'Sending code…' : 'Verify email address',
          leadingIcon: DPIcons.mail,
          loading: _isSendingOtp,
          height: 48,
          onPressed: (_isEmailValid && !_isSendingOtp) ? _sendOtp : null,
        ),
        if (_otpError.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_otpError, style: DPText.small.copyWith(color: DP.danger)),
          ),
      ],
    );
  }

  // ==================== FORM FIELDS ====================
  Widget _buildFullNameField() {
    return DPField(
      label: 'Full name',
      controller: _fullNameController,
      hint: 'Adaeze Okafor',
      textCapitalization: TextCapitalization.words,
      autofillHints: const [AutofillHints.name],
      errorText: _fullNameError.isEmpty ? null : _fullNameError,
      suffixIcon: _isFullNameValid ? DPIcons.circleCheck : DPIcons.user,
    );
  }

  Widget _buildEmailField() {
    return DPField(
      label: 'Email address',
      controller: _emailController,
      keyboardType: TextInputType.emailAddress,
      hint: 'you@example.com',
      autofillHints: const [AutofillHints.email],
      enabled: !_isOtpVerified,
      margin: const EdgeInsets.only(bottom: 10),
      errorText: _emailError.isEmpty ? null : _emailError,
      suffixIcon: _isEmailValid ? DPIcons.circleCheck : DPIcons.mail,
    );
  }

  Widget _buildPhoneField() {
    return DPField(
      label: 'Phone number',
      controller: _phoneController,
      keyboardType: TextInputType.phone,
      maxLength: 11,
      hint: '0803 456 7890',
      autofillHints: const [AutofillHints.telephoneNumber],
      errorText: _phoneError.isEmpty ? null : _phoneError,
      suffixIcon: _isPhoneValid ? DPIcons.circleCheck : DPIcons.phone,
    );
  }

  Widget _buildPasswordField() {
    return DPField(
      label: 'Create password',
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
      label: 'Confirm password',
      controller: _confirmPasswordController,
      obscure: _obscureConfirmPassword,
      hint: '••••••••',
      errorText: _confirmPasswordError.isEmpty ? null : _confirmPasswordError,
      suffixIcon: _obscureConfirmPassword ? DPIcons.eyeOff : DPIcons.eye,
      onSuffixTap: () => setState(
        () => _obscureConfirmPassword = !_obscureConfirmPassword,
      ),
    );
  }

  Widget _buildReferralField() {
    return DPField(
      label: 'Referral code (optional)',
      controller: _referralCodeController,
      hint: 'Enter a referral code',
      textCapitalization: TextCapitalization.characters,
      errorText: _referralError.isEmpty ? null : _referralError,
      helper: _referrerName != null ? 'Referred by $_referrerName' : null,
      helperColor: DP.green,
      suffix: _isValidatingReferral
          ? const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : null,
      suffixIcon: _referrerName != null ? DPIcons.badgeCheck : DPIcons.gift,
    );
  }

  // ==================== PASSWORD REQUIREMENTS ====================
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
        DPIcon(
          isValid ? DPIcons.circleCheck : DPIcons.circleX,
          size: 15,
          color: isValid ? DP.green : DP.faint,
        ),
        const SizedBox(width: 5),
        Text(
          text,
          style: DPText.small.copyWith(color: isValid ? DP.green : DP.muted),
        ),
      ],
    );
  }

  // ==================== TERMS CHECKBOX ====================
  Widget _buildTermsCheckbox() {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => setState(() => _agreedToTerms = !_agreedToTerms),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: Checkbox(
                value: _agreedToTerms,
                onChanged: (value) => setState(() => _agreedToTerms = value ?? false),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text.rich(
                TextSpan(
                  style: DPText.small.copyWith(fontSize: 13),
                  children: const [
                    TextSpan(text: 'By creating an account, you agree to our '),
                    TextSpan(text: 'Terms of use', style: TextStyle(color: DP.ink, fontWeight: FontWeight.w500)),
                    TextSpan(text: ' and '),
                    TextSpan(text: 'Privacy policy', style: TextStyle(color: DP.ink, fontWeight: FontWeight.w500)),
                    TextSpan(text: '.'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== REGISTER BUTTON ====================
  Widget _buildRegisterButton() {
    return DPButton(
      label: 'Create account',
      icon: DPIcons.arrowRight,
      loading: _isLoading,
      onPressed: _isLoading || !_formValid ? null : _handleRegister,
    );
  }
}
