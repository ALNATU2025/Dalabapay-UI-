// lib/presentation/screens/auth/pin_login_screen.dart
import 'dart:async';
import 'dart:convert';
import 'package:dalabapay/core/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/services/biometric_service.dart';
import '../../../ui/ui.dart';

class PinLoginScreen extends StatefulWidget {
  const PinLoginScreen({super.key});

  @override
  State<PinLoginScreen> createState() => _PinLoginScreenState();
}

class _PinLoginScreenState extends State<PinLoginScreen> {
  String _pin = '';
  bool _isLoading = false;
  bool _isBiometricLoading = false;
  String _errorMessage = '';
  Timer? _lockoutTimer;

  String _userId = '';
  String _fullName = '';
  String _email = '';
  bool _transactionPinSet = false;
  bool _isBiometricProcessing = false;
  bool _isLoadingData = true;
  bool _isAutoLogout = false;
  bool _biometricAvailable = false;


  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _initializeScreen();
    });
    _checkBiometricSupport();
  }

  @override
  void dispose() {
    _lockoutTimer?.cancel();
    super.dispose();
  }

  Future<void> _initializeScreen() async {
    try {
      _isAutoLogout = await AuthService.wasAutoLogout();

      final sessionStatus = await AuthService.getSessionStatus();

      if (sessionStatus == 'unauthenticated') {
        if (mounted) {
          _showErrorDialog(
            'Session Required',
            'Please login with your email and password.',
            onOk: () => _navigateToLogin(),
          );
        }
        setState(() => _isLoadingData = false);
        return;
      }

      await _loadUserData();
      await _checkPinStatus();

      // Auto-prompt biometric only if user explicitly enabled it
      if (_userId.isNotEmpty) {
        final isUserBiometricEnabled =
            await biometricService.isBiometricEnabledForUser(_userId);
        if (isUserBiometricEnabled &&
            _biometricAvailable &&
            !_isBiometricProcessing) {
          _tryBiometricLogin();
        }
      }

      setState(() => _isLoadingData = false);
    } catch (e) {
      debugPrint('Initialization error: $e');
      setState(() => _isLoadingData = false);
      if (mounted) {
        _showErrorDialog(
          'Error',
          'Failed to load. Please login again.',
          onOk: () => _navigateToLogin(),
        );
      }
    }
  }

  Future<void> _loadUserData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();

      _userId = prefs.getString('userId') ?? '';
      final userString = prefs.getString('user');

      if (_userId.isEmpty || userString == null) {
        if (mounted) {
          _showErrorDialog(
            'Session Required',
            'Please login with your email and password.',
            onOk: () => _navigateToLogin(),
          );
        }
        return;
      }

      final userData = jsonDecode(userString) as Map<String, dynamic>;

      setState(() {
        _fullName = userData['fullName']?.toString() ?? 'User';
        _email = userData['email']?.toString() ?? '';
        _transactionPinSet = userData['transactionPinSet'] == true;
      });

      if (_email.isNotEmpty) {
        await prefs.setString('saved_login_email', _email);
      }
    } catch (e) {
      debugPrint('Error loading user data: $e');
      if (mounted) {
        _showErrorDialog(
          'Error',
          'Failed to load user data. Please login again.',
          onOk: () => _navigateToLogin(),
        );
      }
    }
  }

  Future<void> _checkPinStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();

      bool pinSet = prefs.getBool('transactionPinSet') ?? false;

      if (!pinSet) {
        final userString = prefs.getString('user');
        if (userString != null) {
          try {
            final userMap = jsonDecode(userString) as Map<String, dynamic>;
            pinSet = userMap['transactionPinSet'] == true;
          } catch (_) {}
        }
      }

      if (!pinSet) {
        final hasPinHash = prefs.getString('pinHash') != null;
        final hasPinSet = prefs.getBool('hasPinSet') ?? false;
        pinSet = hasPinHash || hasPinSet;
      }

      setState(() => _transactionPinSet = pinSet);

      if (!_transactionPinSet && mounted) {
        if (_userId.isNotEmpty) {
          _showErrorDialog(
            'PIN Not Set',
            'You need to set up a transaction PIN first.',
            onOk: () => _navigateToPinSetup(),
          );
        } else {
          _showErrorDialog(
            'Session Required',
            'Please login with your email and password.',
            onOk: () => _navigateToLogin(),
          );
        }
        return;
      }

      if (_isAutoLogout && _fullName.isNotEmpty && mounted) {
        dpSnack(context, 'Session expired. Enter PIN to continue, ${_fullName.split(' ').first}!', error: true);
      }
    } catch (e) {
      debugPrint('Error checking PIN status: $e');
    }
  }

  Future<void> _checkBiometricSupport() async {
    try {
      _biometricAvailable = await biometricService.isBiometricAvailable();
    } on MissingPluginException {
      _biometricAvailable = false;
    } catch (_) {
      _biometricAvailable = false;
    }
    if (mounted) setState(() {});
  }

  // ==================== DIALOGS ====================

  void _showErrorDialog(String title, String message, {VoidCallback? onOk}) {
    showDPDialog(
      context,
      tone: DPDialogTone.error,
      barrierDismissible: false,
      title: title,
      message: message,
      onPrimary: () {
        Navigator.of(context).pop();
        if (onOk != null) onOk();
      },
    );
  }

  void _showPinErrorDialog(String message, int attemptsRemaining) {
    showDPDialog(
      context,
      tone: DPDialogTone.error,
      barrierDismissible: false,
      title: 'Incorrect PIN',
      message: 'The PIN you entered is incorrect.',
      body: attemptsRemaining > 0
          ? DPNotice(
              '$attemptsRemaining attempts remaining',
              kind: DPNoticeKind.warn,
              margin: EdgeInsets.zero,
            )
          : null,
      primaryLabel: 'Try again',
      onPrimary: () {
        Navigator.of(context).pop();
        setState(() {
          _pin = '';
          _errorMessage = '';
        });
      },
    );
  }

  void _showLockoutDialog(String message, int minutesRemaining) {
    showDPDialog(
      context,
      tone: DPDialogTone.error,
      icon: DPIcons.lock,
      barrierDismissible: false,
      title: 'Account temporarily locked',
      message: message,
      body: DPNotice(
        'Please wait $minutesRemaining minutes before trying again.',
        kind: DPNoticeKind.danger,
        icon: DPIcons.clock,
        margin: EdgeInsets.zero,
      ),
      onPrimary: () {
        Navigator.of(context).pop();
        setState(() {
          _pin = '';
          _errorMessage = '';
        });
      },
    );
  }

  // ==================== AUTHENTICATION ====================

  Future<void> _pinLogin() async {
    if (_pin.length < 6) {
      setState(() => _errorMessage = 'Please enter 6-digit PIN');
      return;
    }
    if (!_transactionPinSet) {
      _showErrorDialog(
        'PIN Not Set',
        'Please set up your transaction PIN first.',
        onOk: () => _navigateToPinSetup(),
      );
      return;
    }
    if (_userId.isEmpty) {
      _showErrorDialog(
        'Authentication Error',
        'User ID not found. Please login with email.',
        onOk: () => _navigateToLogin(),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final response = await AuthService.loginWithPin(
        userId: _userId,
        pin: _pin,
      );

      if (response['success'] == true) {
        await _processSuccessfulLogin();
      } else {
        final message = response['message'] ?? 'Invalid transaction PIN';

        if (response['networkError'] == true) {
          _showErrorDialog('Network Error', message);
          setState(() {
            _isLoading = false;
            _pin = '';
          });
          return;
        }

        if (response['locked'] == true) {
          final lockTime = response['lockTimeRemaining'] ?? 0;
          _showLockoutDialog(message, lockTime);
          setState(() {
            _isLoading = false;
            _pin = '';
          });
          return;
        }

        final attemptsRemaining = response['attemptsRemaining'] ?? 0;
        if (attemptsRemaining > 0) {
          _showPinErrorDialog(message, attemptsRemaining);
        } else {
          _showErrorDialog('Authentication Failed', message);
        }

        setState(() {
          _isLoading = false;
          _pin = '';
        });
      }
    } catch (e) {
      debugPrint('PIN login error: $e');
      _showErrorDialog('Login Error', 'Something went wrong. Please try again.');
      setState(() {
        _isLoading = false;
        _pin = '';
      });
    }
  }

  Future<void> _processSuccessfulLogin() async {
    try {
      await AuthService.updateLastActivity();

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('autoLogout');
      await prefs.reload();

      AuthService.startSessionMonitoring();

      if (mounted) {
        dpSnack(context, _fullName.isNotEmpty
                  ? 'Welcome back, ${_fullName.split(' ').first}!'
                  : 'Login successful!', success: true);
      }

      await Future.delayed(const Duration(milliseconds: 500));

      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(
          context,
          '/dashboard',
          (route) => false,
          arguments: {
            'userId': _userId,
            'fullName': _fullName,
            'email': _email,
          },
        );
      }
    } catch (e) {
      debugPrint('Process login error: $e');
      _showErrorDialog(
        'Login Failed',
        'Something went wrong. Please try again.',
      );
    }
  }

  Future<void> _tryBiometricLogin() async {
    if (!_biometricAvailable || _isBiometricProcessing) return;

    setState(() {
      _isBiometricLoading = true;
      _isBiometricProcessing = true;
      _errorMessage = '';
    });

    try {
      final success = await biometricService.authenticate(
        reason: 'Authenticate to access your account',
        biometricOnly: false,
        stickyAuth: true,
      );

      if (!mounted) return;

      if (success) {
        await _processSuccessfulLogin();
      } else {
        if (mounted) {
          dpSnack(context, 'Biometric cancelled. Please enter your PIN.', error: true);
        }
      }
    } on PlatformException catch (e) {
      debugPrint('Biometric PlatformException: ${e.code} - ${e.message}');
      if (mounted) {
        dpSnack(context, 'Biometric unavailable: ${e.message ?? e.code}. Please use PIN.', error: true);
      }
    } catch (e) {
      debugPrint('Biometric error: $e');
      if (mounted) {
        dpSnack(context, 'Biometric failed. Please enter your PIN.', error: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isBiometricLoading = false;
          _isBiometricProcessing = false;
        });
      }
    }
  }

  // ==================== NAVIGATION ====================

  void _navigateToLogin() {
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/login');
  }

  void _navigateToPinSetup() {
    if (!mounted) return;
    if (_userId.isEmpty) {
      _showErrorDialog(
        'Error',
        'User ID not found. Please login with email first.',
        onOk: () => _navigateToLogin(),
      );
      return;
    }
    Navigator.pushNamed(
      context,
      '/pin-setup',
      arguments: {
        'userId': _userId,
        'fullName': _fullName,
        'email': _email,
        'isFirstTime': true,
      },
    );
  }

  // ==================== PIN INPUT ====================

  void _onPinDigitPressed(String digit) {
    if (_isLoading || _isBiometricLoading) return;
    if (_pin.length >= 6) return;

    setState(() {
      _pin += digit;
      _errorMessage = '';
    });

    if (_pin.length == 6) _pinLogin();
  }

  void _onBackspacePressed() {
    if (_isLoading || _isBiometricLoading) return;
    setState(() {
      _pin = _pin.isNotEmpty ? _pin.substring(0, _pin.length - 1) : '';
    });
  }

  // ==================== BUILD ====================

  @override
  Widget build(BuildContext context) {
    if (_isLoadingData) {
      return const Scaffold(backgroundColor: DP.bg, body: DPLoader());
    }

    final firstName = _fullName.trim().isEmpty ? '' : _fullName.trim().split(' ').first;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: DPTheme.overlay,
      child: Scaffold(
        backgroundColor: DP.bg,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, c) => SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: DP.gutter),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: c.maxHeight),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        const DPLogo(height: 26),
                        const Spacer(),
                        DPLinkButton(label: 'Use email', onPressed: _navigateToLogin),
                      ],
                    ),
                    const SizedBox(height: 30),
                    _buildUserInfo(),
                    DPHeadline(
                      _transactionPinSet
                          ? (firstName.isNotEmpty ? 'Welcome back, $firstName.' : 'Welcome back.')
                          : 'Set up your PIN first.',
                      subtitle: _transactionPinSet
                          ? (_isAutoLogout
                              ? 'Your session timed out. Enter your 6-digit PIN to continue.'
                              : 'Enter your 6-digit PIN to continue.')
                          : 'You need a transaction PIN before you can log in with one.',
                      padding: const EdgeInsets.only(top: 18, bottom: 8),
                    ),
                    if (_transactionPinSet) ...[
                      _buildPinDots(),
                      if (_errorMessage.isNotEmpty)
                        DPNotice(_errorMessage, kind: DPNoticeKind.danger),
                      if (_isLoading)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 12),
                          child: DPLoader(),
                        ),
                      _buildNumberPad(),
                    ] else ...[
                      const SizedBox(height: 16),
                      DPButton(label: 'Set up PIN', onPressed: _navigateToPinSetup),
                    ],
                    const SizedBox(height: 18),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUserInfo() {
    if (_fullName.isEmpty) return const SizedBox.shrink();
    return Row(
      children: [
        DPAvatar(name: _fullName, size: 52),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_fullName, style: DPText.body.copyWith(fontWeight: FontWeight.w500)),
              if (_email.isNotEmpty) Text(_email, style: DPText.small),
            ],
          ),
        ),
        if (_isAutoLogout) const DPStatusPill('Session timed out'),
      ],
    );
  }

  Widget _buildPinDots() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 22),
      child: DPCodeBoxes(
        length: 6,
        value: _pin,
        obscure: true,
        error: _errorMessage.isNotEmpty,
        boxSize: 48,
      ),
    );
  }

  Widget _buildBiometricButton() {
    if (!_biometricAvailable) return const SizedBox();
    return _isBiometricLoading
        ? const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const DPIcon(DPIcons.fingerprint, size: 26, color: DP.green);
  }

  Widget _buildNumberPad() {
    return DPKeypad(
      onDigit: _onPinDigitPressed,
      onBackspace: _onBackspacePressed,
      extraKey: _biometricAvailable
          ? GestureDetector(
              onTap: _isBiometricProcessing ? null : _tryBiometricLogin,
              behavior: HitTestBehavior.opaque,
              child: SizedBox(
                width: double.infinity,
                height: 58,
                child: Center(child: _buildBiometricButton()),
              ),
            )
          : null,
    );
  }
}
