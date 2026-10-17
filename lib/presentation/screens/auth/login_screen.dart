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
import '../../../ui/ui.dart';

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
        // Nigerian phone: 08031234567, 2348031234567 or +2348031234567
        final phoneRegex = RegExp(r'^(\+?234|0)[789][01]\d{8}$');
        final compact = value.replaceAll(RegExp(r'[\s-]'), '');
        if (emailRegex.hasMatch(value) || phoneRegex.hasMatch(compact)) {
          _emailError = '';
          _isEmailValid = true;
        } else {
          final looksLikePhone = RegExp(r'^\+?\d+$').hasMatch(compact);
          _emailError = looksLikePhone
              ? 'Enter a valid phone number, e.g. 0803 456 7890'
              : 'Enter a valid email address';
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
    dpDialog(
      context,
      title: 'Couldn\'t log you in',
      message: message,
      confirmLabel: 'Try again',
      tone: DPTone.error,
    );
  }

  @override
  Widget build(BuildContext context) {
    final fadeAnimation = _fadeAnimation ?? const AlwaysStoppedAnimation(1.0);
    final canPop = Navigator.of(context).canPop();
    final h = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: DP.surface,
      body: Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: DPWaves(height: h * 0.14),
          ),
          SafeArea(
            child: FadeTransition(
              opacity: fadeAnimation,
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                padding: EdgeInsets.fromLTRB(28, canPop ? 0 : 28, 28, h * 0.16),
                child: AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (canPop)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: DPIconSquare(
                            icon: DPIcons.back,
                            size: 40,
                            background: Colors.transparent,
                            semanticLabel: 'Back',
                            onTap: () => Navigator.of(context).maybePop(),
                          ),
                        ),
                      Center(child: _buildLogo()),
                      const SizedBox(height: 30),
                      const DPAppear(
                        child: Text(
                          'Welcome Back',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: DP.ink,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Login to your Dalabapay account',
                        style: DP.body.copyWith(color: DP.muted),
                      ),
                      const SizedBox(height: 24),
                      _buildEmailField(),
                      const SizedBox(height: 14),
                      _buildPasswordField(),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          SizedBox(
                            width: 24,
                            height: 24,
                            child: Checkbox(
                              value: _rememberMe,
                              activeColor: DP.green,
                              side: const BorderSide(color: DP.faint),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(5),
                              ),
                              onChanged: (v) =>
                                  setState(() => _rememberMe = v ?? false),
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () =>
                                setState(() => _rememberMe = !_rememberMe),
                            child: const Text(
                              'Remember me',
                              style: TextStyle(fontSize: 13.5, color: DP.inkSoft),
                            ),
                          ),
                          const Spacer(),
                          DPTextLink(
                            label: 'Forgot password?',
                            fontSize: 13.5,
                            onTap: () => Navigator.pushNamed(
                              context,
                              '/forgot-password',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      _buildLoginButton(),
                      if (_canUseBiometricQuickLogin) ...[
                        const SizedBox(height: 10),
                        _buildQuickBiometricButton(),
                      ],
                      if (_canUsePinQuickLogin)
                        Center(
                          child: TextButton.icon(
                            onPressed: () =>
                                Navigator.pushNamed(context, '/pin-login'),
                            icon: const Icon(
                              DPIcons.lock,
                              size: 18,
                              color: DP.green,
                            ),
                            label: const Text(
                              'Unlock with PIN',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: DP.green,
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 14),
                      const Row(
                        children: [
                          Expanded(child: Divider(color: DP.border)),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 12),
                            child: Text('or', style: DP.caption),
                          ),
                          Expanded(child: Divider(color: DP.border)),
                        ],
                      ),
                      const SizedBox(height: 14),
                      DPOutlineButton(
                        label: 'Create an Account',
                        onPressed: () => Navigator.pushReplacementNamed(
                          context,
                          '/register',
                        ),
                      ),
                      const SizedBox(height: 26),
                      _buildTrustStrip(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogo() {
    return const DPAppear(
      scaleFrom: 0.9,
      offsetY: 0,
      child: Column(
        children: [
          DPLogoMark(size: 56),
          SizedBox(height: 10),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: 'Dalaba', style: TextStyle(color: DP.navy)),
                TextSpan(text: 'pay', style: TextStyle(color: DP.green)),
              ],
            ),
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmailField() {
    return DPField(
      controller: _emailController,
      keyboardType: TextInputType.emailAddress,
      hint: 'Email or Phone Number',
      textInputAction: TextInputAction.next,
      autofillHints: const [AutofillHints.email, AutofillHints.telephoneNumber],
      errorText: _emailError.isEmpty ? null : _emailError,
      prefix: const Icon(DPIcons.user, size: 20),
      suffix: _isEmailValid
          ? const Icon(DPIcons.checkCircle, color: DP.green, size: 20)
          : null,
    );
  }

  Widget _buildPasswordField() {
    return DPField(
      controller: _passwordController,
      obscureText: _obscurePassword,
      hint: 'Password',
      textInputAction: TextInputAction.done,
      autofillHints: const [AutofillHints.password],
      onSubmitted: (_) {
        if (_formValid && !_isLoading) _handleLogin();
      },
      errorText: _passwordError.isEmpty ? null : _passwordError,
      prefix: const Icon(DPIcons.lock, size: 20),
      suffix: IconButton(
        tooltip: _obscurePassword ? 'Show password' : 'Hide password',
        icon: Icon(
          _obscurePassword ? DPIcons.eyeOff : DPIcons.eye,
          color: DP.muted,
          size: 20,
        ),
        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
      ),
    );
  }

  Widget _buildLoginButton() {
    return DPButton(
      label: 'Login',
      loading: _isLoading,
      onPressed: _formValid ? _handleLogin : null,
    );
  }

  Widget _buildQuickBiometricButton() {
    return Center(
      child: InkWell(
        borderRadius: BorderRadius.circular(DP.rMd),
        onTap: _isBiometricLoading ? null : _handleBiometricQuickLogin,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _isBiometricLoading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: DP.green,
                      ),
                    )
                  : const Icon(DPIcons.fingerprint, color: DP.green, size: 26),
              const SizedBox(width: 10),
              const Text(
                'Login with biometrics',
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: DP.green,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTrustStrip() {
    return const Center(
      child: Text(
        'Safe  •  Secure  •  Fast',
        style: TextStyle(
          fontSize: 12.5,
          color: DP.muted,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
