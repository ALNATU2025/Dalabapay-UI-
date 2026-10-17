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

    return Scaffold(
      backgroundColor: DP.bg,
      body: SafeArea(
        child: FadeTransition(
          opacity: fadeAnimation,
          child: Column(
            children: [
              DPTopBar(title: 'Welcome back', showBack: canPop),
              Expanded(
                child: SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                  child: AutofillGroup(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildLogo(),
                        const SizedBox(height: 22),
                        const DPHeadline(
                          'Good to see you again.',
                          subtitle: 'Log in to keep your everyday moving.',
                          bottom: 26,
                        ),
                        const DPLabel('Email address or phone number'),
                        _buildEmailField(),
                        const SizedBox(height: 18),
                        const DPLabel('Password'),
                        _buildPasswordField(),
                        const SizedBox(height: 6),
                        Align(
                          alignment: Alignment.centerRight,
                          child: DPTextLink(
                            label: 'Forgot password?',
                            onTap: () => Navigator.pushNamed(
                              context,
                              '/forgot-password',
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        _buildLoginButton(),
                        if (_canUseBiometricQuickLogin) ...[
                          const SizedBox(height: 14),
                          _buildQuickBiometricButton(),
                        ],
                        if (_canUsePinQuickLogin) ...[
                          const SizedBox(height: 4),
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
                        ],
                        const SizedBox(height: 18),
                        _buildTrustStrip(),
                        const SizedBox(height: 36),
                        Center(
                          child: Column(
                            children: [
                              const Text(
                                'New to Dalabapay?',
                                style: DP.caption,
                              ),
                              const SizedBox(height: 4),
                              DPTextLink(
                                label: 'Create an account',
                                onTap: () => Navigator.pushReplacementNamed(
                                  context,
                                  '/register',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
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

  Widget _buildLogo() {
    return const DPWordmark(height: 36);
  }

  Widget _buildEmailField() {
    return DPField(
      controller: _emailController,
      keyboardType: TextInputType.emailAddress,
      hint: 'you@example.com',
      textInputAction: TextInputAction.next,
      autofillHints: const [AutofillHints.email, AutofillHints.telephoneNumber],
      errorText: _emailError.isEmpty ? null : _emailError,
      suffix: Icon(
        _isEmailValid ? DPIcons.checkCircle : DPIcons.mail,
        color: _isEmailValid ? DP.green : DP.muted,
        size: 21,
      ),
    );
  }

  Widget _buildPasswordField() {
    return DPField(
      controller: _passwordController,
      obscureText: _obscurePassword,
      hint: '••••••••••',
      textInputAction: TextInputAction.done,
      autofillHints: const [AutofillHints.password],
      onSubmitted: (_) {
        if (_formValid && !_isLoading) _handleLogin();
      },
      errorText: _passwordError.isEmpty ? null : _passwordError,
      suffix: IconButton(
        tooltip: _obscurePassword ? 'Show password' : 'Hide password',
        icon: Icon(
          _obscurePassword ? DPIcons.eyeOff : DPIcons.eye,
          color: DP.muted,
          size: 21,
        ),
        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
      ),
    );
  }

  Widget _buildLoginButton() {
    return DPButton(
      label: 'Log in',
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
                'Log in with biometrics',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
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
    return const DPBanner(
      'Your details stay private. Never share your password or payment PIN.',
    );
  }
}
