// lib/presentation/screens/auth/pin_login_screen.dart
import 'dart:async';
import 'dart:convert';
import 'package:dalabapay/core/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/services/biometric_service.dart';

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

  final Color _primaryColor = const Color(0xFF243889);
  final Color _secondaryColor = const Color(0xFF219C7E);
  final Color _backgroundColor = Colors.white;
  final Color _digitColor = const Color(0xFF1C2D5A);
  final Color _pinDotColor = const Color(0xFF243889);
  final Color _errorColor = const Color(0xFFE74C3C);

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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Session expired. Enter PIN to continue, ${_fullName.split(' ').first}!',
              style: GoogleFonts.inter(color: Colors.white),
            ),
            backgroundColor: Colors.orange.shade700,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
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
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            backgroundColor: Colors.white,
            title: Row(
              children: [
                Icon(Icons.error_outline, color: _errorColor, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.bold,
                      color: _errorColor,
                      fontSize: 18,
                    ),
                  ),
                ),
              ],
            ),
            content: Text(message, style: GoogleFonts.inter(fontSize: 14)),
            actions: [
              ElevatedButton(
                onPressed: () {
                  if (Navigator.canPop(ctx)) Navigator.pop(ctx);
                  if (onOk != null) onOk();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 10,
                  ),
                ),
                child: Text(
                  'OK',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
    );
  }

  void _showPinErrorDialog(String message, int attemptsRemaining) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            backgroundColor: Colors.white,
            title: Row(
              children: [
                Icon(Icons.cancel_outlined, color: _errorColor, size: 28),
                const SizedBox(width: 12),
                Text(
                  'Invalid PIN',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.bold,
                    color: _errorColor,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'The PIN you entered is incorrect.',
                  style: GoogleFonts.inter(fontSize: 14),
                ),
                if (attemptsRemaining > 0) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.orange.withOpacity(0.2),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.warning_amber_outlined,
                          color: Colors.orange.shade700,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '$attemptsRemaining attempts remaining',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.orange.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  if (Navigator.canPop(ctx)) Navigator.pop(ctx);
                  setState(() {
                    _pin = '';
                    _errorMessage = '';
                  });
                },
                child: Text(
                  'Try Again',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    color: _primaryColor,
                  ),
                ),
              ),
            ],
          ),
    );
  }

  void _showLockoutDialog(String message, int minutesRemaining) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            backgroundColor: Colors.white,
            title: Row(
              children: [
                Icon(Icons.lock_outline, color: Colors.red.shade700, size: 28),
                const SizedBox(width: 12),
                Text(
                  'Account Locked',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.bold,
                    color: Colors.red.shade700,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(message, style: GoogleFonts.inter(fontSize: 14)),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.withOpacity(0.2)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.timer, color: Colors.red.shade700, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Please wait $minutesRemaining minutes before trying again.',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: Colors.red.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              ElevatedButton(
                onPressed: () {
                  if (Navigator.canPop(ctx)) Navigator.pop(ctx);
                  setState(() {
                    _pin = '';
                    _errorMessage = '';
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 10,
                  ),
                ),
                child: Text(
                  'OK',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _fullName.isNotEmpty
                  ? 'Welcome back, ${_fullName.split(' ').first}!'
                  : 'Login successful!',
              style: GoogleFonts.inter(color: Colors.white),
            ),
            backgroundColor: _secondaryColor,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Biometric cancelled. Please enter your PIN.',
                style: GoogleFonts.inter(color: Colors.white),
              ),
              backgroundColor: Colors.orange.shade800,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } on PlatformException catch (e) {
      debugPrint('Biometric PlatformException: ${e.code} - ${e.message}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Biometric unavailable: ${e.message ?? e.code}. Please use PIN.',
              style: GoogleFonts.inter(color: Colors.white),
            ),
            backgroundColor: Colors.orange.shade800,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('Biometric error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Biometric failed. Please enter your PIN.',
              style: GoogleFonts.inter(color: Colors.white),
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
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
      return Scaffold(
        backgroundColor: _backgroundColor,
        body: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(_primaryColor),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: _backgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Container(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildLogo(),
                _buildPinForm(),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20, top: 10),
      child: Image.asset(
        'assets/dalabapay2.png',
        height: 50,
        fit: BoxFit.contain,
        errorBuilder:
            (_, __, ___) => Container(
              width: 100,
              height: 50,
              decoration: BoxDecoration(
                color: _primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.security, size: 30, color: _primaryColor),
            ),
      ),
    );
  }

  Widget _buildUserInfo() {
    if (_fullName.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _primaryColor.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _primaryColor.withOpacity(0.1)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: _primaryColor,
                child: Text(
                  _fullName[0].toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                _fullName,
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: _primaryColor,
                ),
              ),
            ],
          ),
          if (_isAutoLogout) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.timer_outlined,
                    size: 14,
                    color: Colors.orange.shade700,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Session Expired - Enter PIN to continue',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: Colors.orange.shade700,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPinDots() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(6, (index) {
          final isFilled = index < _pin.length;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: const EdgeInsets.symmetric(horizontal: 6),
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isFilled ? _pinDotColor : Colors.grey.shade200,
              border: Border.all(
                color: isFilled ? _primaryColor : Colors.grey.shade300,
                width: 1.5,
              ),
              boxShadow:
                  isFilled
                      ? [
                        BoxShadow(
                          color: _primaryColor.withOpacity(0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ]
                      : null,
            ),
          );
        }),
      ),
    );
  }

  Widget _buildDigitButton(String digit) {
    return GestureDetector(
      onTap: () => _onPinDigitPressed(digit),
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _backgroundColor,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
          border: Border.all(color: Colors.grey.shade200, width: 1),
        ),
        child: Center(
          child: Text(
            digit,
            style: GoogleFonts.poppins(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: _digitColor,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBackspaceButton() {
    return GestureDetector(
      onTap: _onBackspacePressed,
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.grey.shade100,
          border: Border.all(color: Colors.grey.shade300, width: 1),
        ),
        child: const Icon(
          Icons.backspace,
          size: 24,
          color: Color(0xFF1C2D5A),
        ),
      ),
    );
  }

  Widget _buildBiometricButton() {
    if (!_biometricAvailable) {
      return Opacity(
        opacity: 0.3,
        child: Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.grey.shade100,
          ),
          child: const Icon(Icons.fingerprint, size: 28, color: Colors.grey),
        ),
      );
    }

    return GestureDetector(
      onTap: _isBiometricProcessing ? null : _tryBiometricLogin,
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [Color(0xFF92D394), Color(0xFF243889)],
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF243889).withOpacity(0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child:
            _isBiometricLoading
                ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
                : const Icon(Icons.fingerprint, size: 28, color: Colors.white),
      ),
    );
  }

  Widget _buildNumberPad() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: ['1', '2', '3'].map(_buildDigitButton).toList(),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: ['4', '5', '6'].map(_buildDigitButton).toList(),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: ['7', '8', '9'].map(_buildDigitButton).toList(),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildBiometricButton(),
            _buildDigitButton('0'),
            _buildBackspaceButton(),
          ],
        ),
      ],
    );
  }

  Widget _buildPinForm() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _transactionPinSet ? 'Enter Your PIN' : 'PIN Not Set',
            style: GoogleFonts.poppins(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color:
                  _transactionPinSet ? _primaryColor : Colors.orange.shade700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            _transactionPinSet
                ? (_isAutoLogout
                    ? '🔐 Session expired. Enter PIN to continue.'
                    : 'Enter your 6-digit PIN to continue')
                : 'Please set up your transaction PIN first',
            style: GoogleFonts.inter(
              fontSize: 14,
              color:
                  _transactionPinSet
                      ? const Color(0xFF64748B)
                      : Colors.orange.shade700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          _buildUserInfo(),
          if (_transactionPinSet) ...[
            _buildPinDots(),
            _buildNumberPad(),
          ] else ...[
            const SizedBox(height: 32),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.orange.withOpacity(0.2)),
              ),
              child: Column(
                children: [
                  const Icon(
                    Icons.lock_open_outlined,
                    size: 48,
                    color: Colors.orange,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No PIN Set',
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange.shade700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'You need to set up a transaction PIN before you can login with PIN.',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: const Color(0xFF64748B),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _navigateToPinSetup,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primaryColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 12,
                      ),
                    ),
                    child: Text(
                      'Set Up PIN',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (_errorMessage.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _errorColor.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _errorColor.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: _errorColor, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _errorMessage,
                      style: GoogleFonts.inter(
                        color: _errorColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (_isLoading) ...[
            const SizedBox(height: 16),
            Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(_primaryColor),
                strokeWidth: 3,
              ),
            ),
          ],
          if (_transactionPinSet) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: _navigateToLogin,
              child: Text(
                'Login with Email',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: const Color(0xFF64748B),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}