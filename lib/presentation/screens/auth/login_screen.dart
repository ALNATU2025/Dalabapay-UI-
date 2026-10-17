// lib/presentation/screens/auth/login_screen.dart
import 'dart:async';
import 'dart:convert' show jsonDecode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/biometric_service.dart';
import '../../../core/services/secure_storage_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _isBiometricLoading = false;
  bool _obscurePassword = true;
    bool _isDialogLoading = false;
  bool _rememberMe = true;
  bool _canUseBiometricQuickLogin = false;
  bool _canUsePinQuickLogin = false;

  String _emailError = '';
  String _passwordError = '';
  bool _isEmailValid = false;
  bool _isPasswordValid = false;

  AnimationController? _fadeController;
  Animation<double>? _fadeAnimation;
  AnimationController? _pulseController;

  static const Color _primaryLight = Color(0xFF102C68);
  static const Color _secondary = Color(0xFF168566);
  static const Color _white = Colors.white;
  static const Color _darkText = Color(0xFF14263D);
  static const Color _greyText = Color(0xFF728078);

  @override
  void initState() {
    super.initState();
    _emailController.addListener(_validateEmailLive);
    _passwordController.addListener(_validatePasswordLive);

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

    _loadSavedEmailAndBiometrics();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _fadeController?.dispose();
    _pulseController?.dispose();
    super.dispose();
  }

 Future<void> _loadSavedEmailAndBiometrics() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    // ---------- 1. Prefill email ----------
    final savedEmail =
        prefs.getString('saved_login_email') ??
        prefs.getString('email') ??
        '';
    if (savedEmail.isNotEmpty) {
      setState(() {
        _emailController.text = savedEmail;
        _validateEmailLive();
      });
    }

    // ---------- 2. Detect preserved session ----------
    final userId = prefs.getString('userId');
    final preservedToken = prefs.getString('token');

    final hasHardware = await biometricService.isBiometricAvailable();

    // Global biometric flag
    final globalBioFlag = prefs.getBool('biometricEnabled') ?? false;

    // Per-user biometric flag (real source of truth)
    final userBioFlag =
        (userId != null && userId.isNotEmpty)
            ? (prefs.getBool('biometricEnabled_$userId') ?? false)
            : false;

    // Legacy: SecureStorage session
    final hasSecureSession = await SecureStorageService.isLoggedIn();
    final secureBioFlag = await biometricService.getBiometricEnabledStatus();

    final biometricEnabled = userBioFlag || globalBioFlag || secureBioFlag;

    // Show biometric quick login if: hardware + biometric enabled +
    // either a preserved token OR an active SecureStorage session
    final canQuickBio =
        hasHardware &&
        biometricEnabled &&
        ((preservedToken != null && preservedToken.isNotEmpty) ||
            hasSecureSession);

    // ---------- 3. Detect PIN quick login availability ----------
    // PIN login is available if:
    //   - userId exists
    //   - user has set a transaction PIN
    final pinSet = prefs.getBool('transactionPinSet') ?? false;

    // Also check inside the user JSON (in case the bool is stale)
    bool userJsonPinSet = false;
    final userString = prefs.getString('user');
    if (userString != null) {
      try {
        final userMap = jsonDecode(userString) as Map<String, dynamic>;
        userJsonPinSet = userMap['transactionPinSet'] == true;
      } catch (_) {}
    }

    final pinAvailable =
        userId != null &&
        userId.isNotEmpty &&
        (pinSet || userJsonPinSet);

    debugPrint('🔐 LOGIN SCREEN READY-STATE:');
    debugPrint('   userId: $userId');
    debugPrint('   hasPreservedToken: ${preservedToken != null}');
    debugPrint('   hasSecureSession: $hasSecureSession');
    debugPrint('   biometricEnabled: $biometricEnabled');
    debugPrint('   canQuickBio: $canQuickBio');
    debugPrint('   pinSet (global): $pinSet');
    debugPrint('   pinSet (userJson): $userJsonPinSet');
    debugPrint('   pinAvailable: $pinAvailable');

    if (mounted) {
      setState(() {
        _canUseBiometricQuickLogin = canQuickBio;
        _canUsePinQuickLogin = pinAvailable; // ✅ THIS WAS MISSING
      });
    }
  } catch (e) {
    debugPrint('Error loading saved credentials: $e');
  }
}

  void _validateEmailLive() {
    final value = _emailController.text.trim();
    setState(() {
      if (value.isEmpty) {
        _emailError = '';
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

  void _validatePasswordLive() {
    final value = _passwordController.text;
    setState(() {
      if (value.isEmpty) {
        _passwordError = '';
        _isPasswordValid = false;
      } else if (value.length < 6) {
        _passwordError = 'Password must be at least 6 characters';
        _isPasswordValid = false;
      } else {
        _passwordError = '';
        _isPasswordValid = true;
      }
    });
  }

  bool get _formValid => _isEmailValid && _isPasswordValid;

  Future<void> _handleLogin() async {
    if (!_formValid) return;
    setState(() => _isLoading = true);

    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text.trim();
      final authProvider = context.read<AuthProvider>();
      final result = await authProvider.login(email, password);

      if (!mounted) return;

      if (result['success'] == true) {
        final prefs = await SharedPreferences.getInstance();
        if (_rememberMe) {
          await prefs.setString('saved_login_email', email);
        }

        // ✅ Register FCM token so admin/user receives push notifications
        try {
          final fcmToken = await FirebaseMessaging.instance.getToken();
          if (fcmToken != null && fcmToken.isNotEmpty) {
            await ApiService.updateDeviceToken(fcmToken);
            debugPrint('📱 FCM token saved: ${fcmToken.substring(0, 20)}...');
          } else {
            debugPrint('⚠️ No FCM token returned');
          }
        } catch (fcmError) {
          debugPrint('⚠️ FCM token save failed: $fcmError');
          // Don't block login — just log
        }

        Navigator.pushReplacementNamed(context, '/dashboard');
      } else {
        _showUserFriendlyError(result['message'] ?? 'Login failed');
      }
    } catch (e) {
      if (!mounted) return;
      _showUserFriendlyError(e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// After a preserved logout, the token may be gone but userId remains.
  /// Route the user to PIN login so the backend can verify the PIN and
  /// issue a brand-new token — same flow as auto-logout.
  Future<void> _routeToPinLoginIfPossible() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('userId');
    final pinSet = prefs.getBool('transactionPinSet') ?? false;

    if (userId != null && userId.isNotEmpty && pinSet) {
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/pin-login');
      }
    } else {
      _showUserFriendlyError(
        'Your session data is incomplete. Please sign in with your email and password.',
      );
    }
  }

  Future<void> _handleBiometricQuickLogin() async {
    if (!_canUseBiometricQuickLogin) return;
    setState(() => _isBiometricLoading = true);

    try {
      final authenticated = await biometricService.authenticate(
        reason: 'Authenticate to access DalabaPay',
        biometricOnly: true,
        stickyAuth: true,
      );

      if (authenticated && mounted) {
        // Check if we actually have a valid session to navigate into.
        final prefs = await SharedPreferences.getInstance();
        final token = prefs.getString('token');

        if (token == null || token.isEmpty) {
          // ✅ No token → route to PIN login so backend can issue a new one
          debugPrint('⚠️ Biometric OK but no token — routing to PIN login');
          await _routeToPinLoginIfPossible();
          return;
        }

        // Register FCM token
        try {
          final fcmToken = await FirebaseMessaging.instance.getToken();
          if (fcmToken != null && fcmToken.isNotEmpty) {
            await ApiService.updateDeviceToken(fcmToken);
            debugPrint(
              '📱 FCM token saved (biometric): ${fcmToken.substring(0, 20)}...',
            );
          }
        } catch (fcmError) {
          debugPrint('⚠️ FCM token save (biometric) failed: $fcmError');
        }

        Navigator.pushReplacementNamed(context, '/dashboard');
      }
    } on PlatformException catch (e) {
      debugPrint('Biometric PlatformException: ${e.code} - ${e.message}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Biometric unavailable: ${e.message ?? e.code}. Please enter your password.',
              style: GoogleFonts.inter(color: Colors.white),
            ),
            backgroundColor: Colors.orange.shade800,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Biometric login failed. Please enter your password.',
              style: GoogleFonts.inter(color: Colors.white),
            ),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isBiometricLoading = false);
    }
  }

  void _showUserFriendlyError(String error) {
    String userMessage;
    final e = error.toLowerCase();

    if (e.contains('network') ||
        e.contains('connection') ||
        e.contains('socketexception') ||
        e.contains('clientexception')) {
      userMessage =
          'No internet connection. Please check your network and try again.';
    } else if (e.contains('timeout')) {
      userMessage = 'Request timed out. Please try again.';
    } else if (e.contains('invalid credentials') ||
        e.contains('incorrect password') ||
        e.contains('no account found')) {
      userMessage = 'Invalid email or password. Please try again.';
    } else if (e.contains('deactivated')) {
      userMessage =
          'Your account has been deactivated. Please contact support.';
    } else if (e.contains('500') ||
        e.contains('502') ||
        e.contains('503') ||
        e.contains('server')) {
      userMessage =
          'Our service is temporarily unavailable. Please try again later.';
    } else if (e.contains('rate limit') || e.contains('too many')) {
      userMessage =
          'Too many login attempts. Please wait a moment and try again.';
    } else {
      userMessage =
          'Unable to sign in. Please check your credentials and try again.';
    }

    _showErrorDialog(userMessage);
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder:
          (ctx) => Dialog(
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
                    'Sign In Failed',
                    style: GoogleFonts.inter(
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
                        style: GoogleFonts.inter(
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
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 20),
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
                            color: Colors.grey.shade400,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAuroraEffects() {
    return Stack(
      children: [
        Positioned(
          top: -100,
          right: -100,
          child: AnimatedBuilder(
            animation: _pulseController ?? const AlwaysStoppedAnimation(0.0),
            builder: (context, child) {
              final v = _pulseController?.value ?? 0.0;
              return Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFF168566).withOpacity(0.08),
                      const Color(0xFF168566).withOpacity(0.03),
                      Colors.transparent,
                    ],
                    stops: const [0, 0.5, 1],
                  ),
                  shape: BoxShape.circle,
                ),
                transform: Matrix4.identity()..scale(1 + v * 0.1),
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
              final v = _pulseController?.value ?? 0.0;
              return Container(
                width: 250,
                height: 250,
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFF102C68).withOpacity(0.08),
                      const Color(0xFF102C68).withOpacity(0.03),
                      Colors.transparent,
                    ],
                    stops: const [0, 0.5, 1],
                  ),
                  shape: BoxShape.circle,
                ),
                transform: Matrix4.identity()..scale(1 + v * 0.15),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildLogo() {
    return Image.asset(
      'assets/dalabapay2.png',
      height: 48,
      fit: BoxFit.contain,
    );
  }

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
            'Welcome Back!',
            style: GoogleFonts.inter(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: _primaryLight,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Sign in to continue to your account',
            style: GoogleFonts.inter(fontSize: 14, color: _greyText),
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
          const _FieldLabel(label: 'Email Address'),
          const SizedBox(height: 6),
          _buildEmailField(),
          const SizedBox(height: 16),
          const _FieldLabel(label: 'Password'),
          const SizedBox(height: 6),
          _buildPasswordField(),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GestureDetector(
                onTap: () => setState(() => _rememberMe = !_rememberMe),
                child: Row(
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: _rememberMe ? _secondary : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color:
                              _rememberMe ? _secondary : Colors.grey.shade300,
                          width: 1.5,
                        ),
                      ),
                      child:
                          _rememberMe
                              ? const Icon(
                                Icons.check,
                                color: Colors.white,
                                size: 14,
                              )
                              : null,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Remember email',
                      style: GoogleFonts.inter(fontSize: 13, color: _greyText),
                    ),
                  ],
                ),
              ),
                            GestureDetector(
                onTap: () {
                  Navigator.pushNamed(context, '/forgot-password');
                },
                child: Text(
                  'Forgot password?',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: _secondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          Row(
            children: [
              Expanded(child: _buildLoginButton()),
              if (_canUseBiometricQuickLogin) ...[
                const SizedBox(width: 12),
                _buildQuickBiometricButton(),
              ],
            ],
          ),
          if (_canUsePinQuickLogin) ...[
            const SizedBox(height: 16),
            Center(
              child: TextButton.icon(
                onPressed: () => Navigator.pushNamed(context, '/pin-login'),
                icon: Icon(Icons.pin_rounded, size: 18, color: _primaryLight),
                label: Text(
                  'Unlock with PIN',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _primaryLight,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Not a member? ',
                  style: GoogleFonts.inter(fontSize: 14, color: _greyText),
                ),
                GestureDetector(
                  onTap:
                      () =>
                          Navigator.pushReplacementNamed(context, '/register'),
                  child: Text(
                    'Register now',
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

  Widget _buildEmailField() {
    return TextFormField(
      controller: _emailController,
      keyboardType: TextInputType.emailAddress,
      style: GoogleFonts.inter(fontSize: 15, color: _darkText),
      cursorColor: _secondary,
      decoration: _fieldDecoration(
        hint: 'you@example.com',
        icon: Icons.mail_outline_rounded,
        errorText: _emailError.isEmpty ? null : _emailError,
        suffix:
            _isEmailValid
                ? Icon(Icons.check_circle_rounded, color: _secondary, size: 20)
                : null,
      ),
    );
  }

  Widget _buildPasswordField() {
    return TextFormField(
      controller: _passwordController,
      obscureText: _obscurePassword,
      style: GoogleFonts.inter(fontSize: 15, color: _darkText),
      cursorColor: _secondary,
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
          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
        ),
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
      hintStyle: GoogleFonts.inter(fontSize: 14, color: Colors.grey.shade400),
      errorText: errorText,
      errorStyle: GoogleFonts.inter(fontSize: 12, color: Colors.redAccent),
      prefixIcon: Icon(icon, color: _secondary, size: 20),
      suffixIcon: suffix,
      filled: true,
      fillColor: const Color(0xFFF8F9F5),
      contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: _secondary, width: 1.5),
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

  Widget _buildLoginButton() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient:
            _formValid
                ? const LinearGradient(
                  colors: [Color(0xFF168566), Color(0xFF0F6B51)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
                : null,
        color: _formValid ? null : Colors.grey.shade200,
        boxShadow:
            _formValid
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
          onTap: _isLoading || !_formValid ? null : _handleLogin,
          child: Center(
            child:
                _isLoading
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
                          'SIGN IN',
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color:
                                _formValid
                                    ? Colors.white
                                    : Colors.grey.shade400,
                            letterSpacing: 1.5,
                          ),
                        ),
                        if (_formValid) ...[
                          const SizedBox(width: 8),
                          const Icon(
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

  Widget _buildQuickBiometricButton() {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: _primaryLight.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _primaryLight.withOpacity(0.2)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _isBiometricLoading ? null : _handleBiometricQuickLogin,
          child: Center(
            child:
                _isBiometricLoading
                    ? SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        color: _primaryLight,
                        strokeWidth: 2,
                      ),
                    )
                    : Icon(
                      Icons.fingerprint_rounded,
                      color: _primaryLight,
                      size: 28,
                    ),
          ),
        ),
      ),
    );
  }

  Widget _buildTrustStrip() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9F5),
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
