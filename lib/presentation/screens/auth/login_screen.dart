// lib/presentation/screens/auth/login_screen.dart
import 'dart:async';
import 'dart:convert' show jsonDecode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
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
        dpSnack(context, 'Biometric unavailable: ${e.message ?? e.code}. Please enter your password.', error: true);
      }
    } catch (e) {
      if (mounted) {
        dpSnack(context, 'Biometric login failed. Please enter your password.', error: true);
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
              Text('We couldn’t log you in', style: DPText.title.copyWith(fontWeight: FontWeight.w500)),
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

  @override
  Widget build(BuildContext context) {
    final fadeAnimation = _fadeAnimation ?? const AlwaysStoppedAnimation(1.0);
    final canPop = Navigator.of(context).canPop();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: DPTheme.overlay,
      child: Scaffold(
        backgroundColor: DP.bg,
        body: SafeArea(
          child: Column(
            children: [
              DPHeader(title: 'Welcome back', showBack: canPop),
              Expanded(
                child: FadeTransition(
                  opacity: fadeAnimation,
                  child: ListView(
                    physics: const ClampingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(DP.gutter, 10, DP.gutter, 24),
                    children: [
                      const Align(alignment: Alignment.centerLeft, child: DPLogo(height: 30)),
                      const DPHeadline(
                        'Good to see you again.',
                        subtitle: 'Log in to keep your everyday moving.',
                        padding: EdgeInsets.only(top: 22, bottom: 26),
                      ),
                      _buildEmailField(),
                      _buildPasswordField(),
                      Align(
                        alignment: Alignment.centerRight,
                        child: DPLinkButton(
                          label: 'Forgot password?',
                          onPressed: () => Navigator.pushNamed(context, '/forgot-password'),
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
                            onPressed: () => Navigator.pushNamed(context, '/pin-login'),
                            icon: const DPIcon(DPIcons.keyRound, size: 18, color: DP.green),
                            label: const Text('Unlock with PIN'),
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      _buildTrustStrip(),
                      const SizedBox(height: 36),
                      Center(child: Text('New to Dalabapay?', style: DPText.bodyMuted)),
                      const SizedBox(height: 4),
                      Center(
                        child: DPLinkButton(
                          label: 'Create an account',
                          onPressed: () => Navigator.pushReplacementNamed(context, '/register'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmailField() {
    return DPField(
      label: 'Email address',
      controller: _emailController,
      keyboardType: TextInputType.emailAddress,
      hint: 'you@example.com',
      autofillHints: const [AutofillHints.email],
      textInputAction: TextInputAction.next,
      errorText: _emailError.isEmpty ? null : _emailError,
      suffixIcon: _isEmailValid ? DPIcons.circleCheck : DPIcons.mail,
    );
  }

  Widget _buildPasswordField() {
    return DPField(
      label: 'Password',
      controller: _passwordController,
      obscure: _obscurePassword,
      hint: '••••••••',
      autofillHints: const [AutofillHints.password],
      textInputAction: TextInputAction.done,
      onSubmitted: (_) {
        if (_formValid && !_isLoading) _handleLogin();
      },
      errorText: _passwordError.isEmpty ? null : _passwordError,
      margin: const EdgeInsets.only(bottom: 4),
      suffixIcon: _obscurePassword ? DPIcons.eyeOff : DPIcons.eye,
      onSuffixTap: () => setState(() => _obscurePassword = !_obscurePassword),
    );
  }

  Widget _buildLoginButton() {
    return DPButton(
      label: 'Log in',
      loading: _isLoading,
      onPressed: _isLoading || !_formValid ? null : _handleLogin,
    );
  }

  Widget _buildQuickBiometricButton() {
    return Center(
      child: InkWell(
        borderRadius: BorderRadius.circular(DP.rMd),
        onTap: _isBiometricLoading ? null : _handleBiometricQuickLogin,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _isBiometricLoading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const DPIcon(DPIcons.fingerprint, size: 24, color: DP.green),
              const SizedBox(width: 10),
              Text('Log in with biometrics', style: DPText.body.copyWith(color: DP.green)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTrustStrip() {
    return const DPNotice(
      'Your details stay private. Never share your password or payment PIN.',
      margin: EdgeInsets.zero,
    );
  }
}
