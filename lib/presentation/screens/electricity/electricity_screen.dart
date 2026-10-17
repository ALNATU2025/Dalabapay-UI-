// lib/presentation/screens/electricity/electricity_screen.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../core/services/api_service.dart';
import '../../../core/services/biometric_service.dart';
import '../../../core/widgets/receipt_widget.dart';
import '../../../core/widgets/request_limit_increase_dialog.dart';
import '../../../ui/ui.dart';
import '../../../core/widgets/commission_estimate.dart';
import '../../../core/services/commission_rates_service.dart';

class ElectricityScreen extends StatefulWidget {
  final void Function(double newBalance) onBalanceUpdate;
  final String userId;

  const ElectricityScreen({
    super.key,
    required this.onBalanceUpdate,
    required this.userId,
  });

  @override
  State<ElectricityScreen> createState() => _ElectricityScreenState();
}

class _ElectricityScreenState extends State<ElectricityScreen>
    with TickerProviderStateMixin {
  // ==================== CONTROLLERS & FOCUS NODES ====================
  final TextEditingController _meterController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _pinController = TextEditingController();

  final FocusNode _meterFocusNode = FocusNode();
  final FocusNode _amountFocusNode = FocusNode();
  final FocusNode _phoneFocusNode = FocusNode();
  final FocusNode _pinFocusNode = FocusNode();

  // ==================== STATE VARIABLES ====================
  String? _selectedProvider;
  String? _selectedMeterType;
  String? _customerName;
  String? _customerAddress;
  final bool _isLoading = false;
  bool _isAuthenticating = false;
  bool _isValidating = false;
  bool _isValidated = false;
  bool _isBalanceVisible = true;
  double _walletBalance = 0.0;

  // Authentication State
  bool _transactionPinSet = false;
  bool _biometricEnabled = false;
  bool _biometricAllowed = true;
  bool _pinRequired = true;
  bool _useBiometric = false;
  bool _pinLocked = false;
  int _lockTimeRemaining = 0;
  String? _pinValidationError;
  String _biometricName = 'Biometric';

  // Service State
  final bool _electricityServiceEnabled = true;
  bool _isUserActive = true;
  bool _isLoadingUserData = true;

  // Payment Sheet State
  bool _showPaymentSheet = false;
  bool _isProcessingPayment = false;

  // ==================== ANIMATIONS ====================
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late AnimationController _sheetController;
  late Animation<double> _sheetAnimation;

  // Shake Animation for Wrong PIN
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

  // ==================== BRAND COLORS ====================
  static const Color _primaryNavy = Color(0xFF102C68);
  static const Color _secondaryTeal = Color(0xFF168566);
  static const Color _textDark = Color(0xFF14263D);
  static const Color _textMuted = Color(0xFF728078);
  static const Color _bgCanvas = Color(0xFFF8F9F5);

  // Amount quick buttons
  final List<int> _quickAmounts = [2000, 3000, 5000, 10000, 20000];
  int? _selectedQuickAmount;

  // Provider list with logos
  final List<Map<String, dynamic>> _providers = [
    {
      'id': 'ikeja-electric',
      'name': 'IKEDC',
      'fullName': 'Ikeja Electric',
      'logo':
          'https://pbs.twimg.com/profile_images/661968066729738240/mKmGmNm0_400x400.jpg',
      'color': const Color(0xFFFFCB05),
      'textColor': const Color(0xFF14263D),
    },
    {
      'id': 'eko-electric',
      'name': 'EKEDC',
      'fullName': 'Eko Electric',
      'logo':
          'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcQk7KUDhwAe6Qb7KN6uOTg7blCS0Q6f4j0qfzw94ZquItQ4OC5_ayA4h30&s=10',
      'color': const Color(0xFFEF1C25),
      'textColor': Colors.white,
    },
    {
      'id': 'portharcourt-electric',
      'name': 'PHED',
      'fullName': 'Port Harcourt Electric',
      'logo': 'https://upload.wikimedia.org/wikipedia/en/a/aa/PHED.PNG',
      'color': const Color(0xFF00B4D2),
      'textColor': Colors.white,
    },
    {
      'id': 'kano-electric',
      'name': 'KEDCO',
      'fullName': 'Kano Electric',
      'logo': 'https://buypower.ng/img/discos/KEDCO.png',
      'color': const Color(0xFF00843D),
      'textColor': Colors.white,
    },
    {
      'id': 'jos-electric',
      'name': 'JED',
      'fullName': 'Jos Electric',
      'logo':
          'https://pbs.twimg.com/profile_images/898118928404295681/qqSdt2Ir_400x400.jpg',
      'color': const Color(0xFF173D88),
      'textColor': Colors.white,
    },
    {
      'id': 'ibadan-electric',
      'name': 'IBEDC',
      'fullName': 'Ibadan Electric',
      'logo':
          'https://play-lh.googleusercontent.com/7JrrLm9wlgZkMCBeQCvaCPeyOemK6ZUkHfc54S3o4LiTRIQmXZTYF9onD9NNuL7UnLav0am4SiPWDASoMjntcN8',
      'color': const Color(0xFFA76B1D),
      'textColor': Colors.white,
    },
    {
      'id': 'kaduna-electric',
      'name': 'KAEDCO',
      'fullName': 'Kaduna Electric',
      'logo':
          'https://cdn-ikpjekl.nitrocdn.com/ACWcfIwwzfzpnmntQXgCjbWomxYbfaeP/assets/images/optimized/rev-b10b90e/kadunaelectric.com/wp-content/uploads/2024/12/logo_no_bg-1.png',
      'color': const Color(0xFF795548),
      'textColor': Colors.white,
    },
    {
      'id': 'abuja-electric',
      'name': 'AEDC',
      'fullName': 'Abuja Electric',
      'logo':
          'https://i0.wp.com/media.premiumtimesng.com/wp-content/files/2024/02/AEDC_1-e1708370547799.jpeg?fit=1600%2C901&ssl=1',
      'color': const Color(0xFF607D8B),
      'textColor': Colors.white,
    },
    {
      'id': 'enugu-electric',
      'name': 'EEDC',
      'fullName': 'Enugu Electric',
      'logo':
          'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcTgxhNVpkFZgJ9KeRty6P4N4QDI7EkwgGb3mQ&s',
      'color': const Color(0xFF2196F3),
      'textColor': Colors.white,
    },
    {
      'id': 'aba-electric',
      'name': 'ABA',
      'fullName': 'Abia Power',
      'logo':
          'https://play-lh.googleusercontent.com/X2bt3xvD-GCE8TUggJVzyn-N7bgpsaFbJNGUd9szfYiOn8EPzSsLlyxNogkl1KtCmYU=w600-h300-pc0xffffff-pd',
      'color': const Color(0xFF173D88),
      'textColor': Colors.white,
    },
    {
      'id': 'yola-electric',
      'name': 'YEDC',
      'fullName': 'Yola Electric',
      'logo':
          'https://connect-assets.prosple.com/cdn/ff/Q2yIQ_goZmWNC8gilkQTNfbtqQLRPdZSvmSQ_Zx6TO0/1624574186/public/styles/scale_and_crop_center_224x224/public/2021-06/Yola%20Logo.jpg?itok=-tMsq4-v',
      'color': const Color(0xFFFF5722),
      'textColor': Colors.white,
    },
  ];

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _initializeData();
    _fetchSecuritySettings();
    _loadWalletBalance();
    _checkBiometricSupport();
    _phoneController.text = '';
  }

  // ==================== LIMIT INCREASE DIALOG ====================
  void _showLimitIncreaseDialog({
    required String service,
    required String limitType,
    required double currentLimit,
    required double requestedAmount,
  }) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder:
          (context) => RequestLimitIncreaseDialog(
            service: service,
            limitType: limitType,
            currentLimit: currentLimit,
            requestedAmount: requestedAmount,
          ),
    );
  }

  void _setupAnimations() {
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.04),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOutCubic),
    );
    _fadeController.forward();

    _sheetController = AnimationController(
      duration: const Duration(milliseconds: 350),
      vsync: this,
    );
    _sheetAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _sheetController, curve: Curves.easeOutCubic),
    );

    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 450),
      vsync: this,
    );
    _shakeAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -10.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -10.0, end: 10.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 10.0, end: -10.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -10.0, end: 10.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 10.0, end: 0.0), weight: 1),
    ]).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _sheetController.dispose();
    _shakeController.dispose();
    _meterController.dispose();
    _amountController.dispose();
    _phoneController.dispose();
    _pinController.dispose();
    _meterFocusNode.dispose();
    _amountFocusNode.dispose();
    _phoneFocusNode.dispose();
    _pinFocusNode.dispose();
    super.dispose();
  }

  // ==================== BIOMETRIC SUPPORT CHECK ====================
  Future<void> _checkBiometricSupport() async {
    if (kIsWeb) return;
    try {
      final isAvailable = await biometricService.isBiometricAvailable();
      final isEnabled = await biometricService.getBiometricEnabledStatus(
        userId: widget.userId,
      );

      if (isAvailable) {
        final name = await biometricService.getBiometricName();
        if (mounted) {
          setState(() {
            _biometricName = name;
            _biometricEnabled = isEnabled;
          });
        }
      }
    } catch (e) {
      debugPrint('Biometric check error: $e');
    }
  }

  Future<void> _initializeData() async {
    try {
      final user = await ApiService.getCurrentUser();
      if (mounted) {
        setState(() {
          _isUserActive = user['isActive'] ?? true;
          _isLoadingUserData = false;
          if (user['phone'] != null) {
            _phoneController.text = user['phone'].toString();
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingUserData = false);
    }
  }

  Future<void> _loadWalletBalance() async {
    try {
      final balance = await ApiService.getBalance();
      if (mounted) {
        setState(() => _walletBalance = balance);
      }
    } catch (e) {
      // Silent fail
    }
  }

  Future<void> _fetchSecuritySettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isEnabled =
          kIsWeb
              ? false
              : await biometricService.getBiometricEnabledStatus(
                userId: widget.userId,
              );

      final userString = prefs.getString('user');
      bool pinSet = prefs.getBool('transactionPinSet') ?? false;

      if (userString != null) {
        final user = jsonDecode(userString);
        pinSet =
            pinSet ||
            (user['transactionPinSet'] ?? false) ||
            (user['hasTransactionPin'] ?? false) ||
            (user['pinSet'] ?? false) ||
            (user['transactionPin'] != null &&
                user['transactionPin'].toString().isNotEmpty &&
                user['transactionPin'].toString() != 'null');
      }

      if (mounted) {
        setState(() {
          _transactionPinSet = pinSet;
          _biometricEnabled = isEnabled;
        });
      }

      final globalSettings = await ApiService.getGlobalSecuritySettings();
      if (mounted) {
        setState(() {
          _pinRequired = globalSettings['pinRequired'] ?? true;
          _biometricAllowed = globalSettings['biometricAllowed'] ?? true;
        });
      }

      final securitySettings = await ApiService.getSecuritySettings();
      if (mounted && securitySettings['securitySettings'] != null) {
        setState(() {
          _pinLocked =
              securitySettings['securitySettings']['pinLocked'] ?? false;
          _lockTimeRemaining =
              securitySettings['securitySettings']['lockTimeRemaining'] ?? 0;
        });
      }
    } catch (e) {
      debugPrint('Error fetching security settings: $e');
    }
  }

  // ==================== FORM VALIDATION ====================
  String? _validateForm() {
    if (_selectedProvider == null) {
      return 'Please select an electricity provider';
    }
    if (_selectedMeterType == null) {
      return 'Please select meter type';
    }
    final meter = _meterController.text.trim();
    if (meter.isEmpty) {
      return 'Please enter your meter number';
    }
    if (meter.length < 11 || meter.length > 13) {
      return 'Meter number must be 11-13 digits';
    }
    if (!RegExp(r'^[0-9]+$').hasMatch(meter)) {
      return 'Meter number must contain only digits';
    }
    if (!_isValidated) {
      return 'Please validate your meter number first';
    }
    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      return 'Please enter a valid amount';
    }
    if (amount < 2000) {
      return 'Minimum electricity purchase is ₦2,000';
    }
    if (amount > 500000) {
      return 'Maximum electricity purchase is ₦500,000';
    }
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      return 'Please enter your phone number';
    }
    if (phone.length != 11) {
      return 'Phone number must be exactly 11 digits';
    }
    if (!RegExp(r'^[0-9]+$').hasMatch(phone)) {
      return 'Phone number must contain only digits';
    }
    return null;
  }

  String _formatNaira(double amount) {
    final formatCurrency = NumberFormat.currency(locale: "en_NG", symbol: "₦");
    return formatCurrency.format(amount);
  }

  String _mapExceptionToUserMessage(dynamic e) {
    final errorStr = e.toString().replaceAll('Exception: ', '');
    if (errorStr.contains('BELOW MINIMUM AMOUNT ALLOWED')) {
      return 'Amount below minimum. Minimum: ₦2,000';
    } else if (errorStr.contains('Insufficient wallet balance')) {
      return 'Insufficient wallet balance. Please fund your wallet.';
    } else if (errorStr.contains('service is currently disabled')) {
      return 'Service temporarily unavailable. Please try again later.';
    } else if (errorStr.contains('No internet connection')) {
      return 'No internet connection detected.';
    } else if (errorStr.contains('timeout')) {
      return 'Request timed out. Please check your connection.';
    } else if (errorStr.contains('Authentication token not found')) {
      return 'Session expired. Please log in again.';
    } else if (errorStr.contains('Invalid transaction PIN')) {
      return errorStr;
    } else if (errorStr.contains('Invalid meter number') ||
        errorStr.contains('WrongBillersCode')) {
      return 'Invalid meter number. Please check and try again.';
    } else if (errorStr.contains('Biometric authentication failed')) {
      return 'Biometric authentication failed. Please try again or use your PIN.';
    } else if (errorStr.contains('Biometric not available')) {
      return 'Biometric is not available on this device. Please use your PIN.';
    }
    return errorStr.length > 100 ? 'An unexpected error occurred.' : errorStr;
  }

  void _showPinErrorSnackBar({
    required String message,
    int? attemptsRemaining,
  }) {
    if (!mounted) return;

    final displayMsg =
        attemptsRemaining != null
            ? '⚠️ $message ($attemptsRemaining ${attemptsRemaining == 1 ? 'attempt' : 'attempts'} remaining)'
            : '⚠️ $message';

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(
                color: Colors.white24,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.lock_reset_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                displayMsg,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFFC0392B),
        behavior: SnackBarBehavior.floating,
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.only(left: 16, right: 16, bottom: 24),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  // ==================== METER VALIDATION ====================
  Future<void> _validateMeter() async {
    if (_selectedProvider == null) {
      _showErrorDialog(
        'Provider Required',
        'Please select an electricity provider.',
      );
      return;
    }
    if (_selectedMeterType == null) {
      _showErrorDialog('Meter Type Required', 'Please select a meter type.');
      return;
    }

    final meterNumber = _meterController.text.trim();
    if (meterNumber.isEmpty) {
      _showErrorDialog(
        'Invalid Meter Number',
        'Please enter your meter number.',
      );
      return;
    }
    if (meterNumber.length < 11 || meterNumber.length > 13) {
      _showErrorDialog(
        'Invalid Meter Number',
        'Meter number must be between 11 and 13 digits.',
      );
      return;
    }
    if (!RegExp(r'^[0-9]+$').hasMatch(meterNumber)) {
      _showErrorDialog(
        'Invalid Meter Number',
        'Meter number must contain only digits.',
      );
      return;
    }

    HapticFeedback.lightImpact();
    setState(() {
      _isValidating = true;
      _isValidated = false;
      _customerName = null;
      _customerAddress = null;
    });

    try {
      final result = await ApiService.validateElectricityMeter(
        billersCode: meterNumber,
        serviceID: _selectedProvider!,
        type: _selectedMeterType!,
      );

      if (result['serviceUnavailable'] == true) {
        setState(() => _isValidating = false);
        _showErrorDialog(
          'Service Unavailable',
          'The validation service is temporarily unavailable. Please try again in a few minutes.',
        );
        return;
      }

      if (result['validationError'] == true || result['success'] == false) {
        setState(() => _isValidating = false);
        final errorMsg =
            result['message'] ??
            'Unable to validate meter. Please check and try again.';
        _showErrorDialog('Validation Failed', errorMsg);
        return;
      }

      if (result['success'] == true) {
        String customerName =
            result['customerName']?.toString().trim() ?? 'Unknown';
        final details = result['details'] as Map<String, dynamic>?;

        final vtpassResponse = result['vtpassResponse'];
        if (vtpassResponse != null) {
          final content = vtpassResponse['content'];
          if (content != null) {
            if (customerName == 'Unknown' || customerName.isEmpty) {
              if (content['Customer_Name'] != null) {
                customerName = content['Customer_Name'].toString().trim();
              } else if (content['customer_name'] != null) {
                customerName = content['customer_name'].toString().trim();
              } else if (content['Name'] != null) {
                customerName = content['Name'].toString().trim();
              }
            }

            final address =
                content['Address']?.toString().trim() ??
                content['address']?.toString().trim() ??
                content['Customer_Address']?.toString().trim() ??
                'N/A';

            setState(() {
              _isValidated = true;
              _customerName = customerName;
              _customerAddress = address;
              _isValidating = false;
            });

            _showValidationSuccessDialog(
              customerName,
              address,
              meterNumber,
              _selectedMeterType!,
            );
            return;
          }
        }

        final address = details?['Address']?.toString().trim() ?? 'N/A';

        setState(() {
          _isValidated = true;
          _customerName = customerName;
          _customerAddress = address;
          _isValidating = false;
        });

        _showValidationSuccessDialog(
          customerName,
          address,
          meterNumber,
          _selectedMeterType!,
        );
      }
    } catch (e) {
      setState(() => _isValidating = false);

      String errorMessage = e.toString();
      if (errorMessage.startsWith('Exception: ')) {
        errorMessage = errorMessage.substring(11);
      }

      if (errorMessage.contains('temporarily unavailable') ||
          errorMessage.contains('service is currently disabled')) {
        _showErrorDialog(
          'Service Unavailable',
          'The validation service is temporarily unavailable. Please try again in a few minutes.',
        );
        return;
      }

      if (errorMessage.contains('meter') ||
          errorMessage.contains('WrongBillersCode') ||
          errorMessage.contains('not correct')) {
        _showErrorDialog('Validation Failed', errorMessage);
        return;
      }

      _showErrorDialog(
        'Validation Error',
        'Unable to validate meter. Please check your internet connection and try again.',
      );
    }
  }


  // ==================== OPEN PAYMENT SHEET ====================
  void _openPaymentSheet() {
    HapticFeedback.lightImpact();
    final validationError = _validateForm();
    if (validationError != null) {
      _showErrorDialog('Validation Error', validationError);
      return;
    }

    if (!_isValidated || _customerName == null) {
      _showErrorDialog(
        'Validation Required',
        'Please validate your meter number before proceeding to payment.',
      );
      return;
    }

    setState(() {
      _pinValidationError = null;
      _pinController.clear();
      _showPaymentSheet = true;
      _useBiometric = false;
    });
    _sheetController.forward();
  }

  void _closePaymentSheet() {
    _sheetController.reverse().then((_) {
      if (mounted) {
        setState(() {
          _showPaymentSheet = false;
          _isProcessingPayment = false;
          _pinValidationError = null;
        });
      }
    });
  }

  // ==================== PROCESS PAYMENT ====================
  Future<void> _processPaymentWithPIN() async {
    HapticFeedback.mediumImpact();
    if (!_transactionPinSet) {
      _showErrorDialog(
        'PIN Required',
        'Please set up a transaction PIN in Settings.',
      );
      return;
    }

    if (_pinLocked && _lockTimeRemaining > 0) {
      _showErrorDialog(
        'PIN Locked',
        'Your PIN is locked due to too many failed attempts. Try again in $_lockTimeRemaining minutes.',
      );
      return;
    }

    if (!_pinRequired) {
      await _executeTransaction();
      return;
    }

    final pin = _pinController.text.trim();
    if (pin.isEmpty || pin.length < 4 || pin.length > 6) {
      setState(() {
        _pinValidationError = 'Please enter a valid 4-6 digit PIN';
      });
      _shakeController.forward(from: 0.0);
      return;
    }

    setState(() {
      _pinValidationError = null;
      _isProcessingPayment = true;
    });

    try {
      final verifyResult = await ApiService.verifyTransactionPin(
        userId: widget.userId,
        transactionPin: pin,
      );

      if (verifyResult['success'] != true) {
        final message = verifyResult['message'] ?? 'Incorrect transaction PIN';
        final attemptsRemaining = verifyResult['attemptsRemaining'];

        setState(() {
          _isProcessingPayment = false;
          _pinValidationError =
              attemptsRemaining != null
                  ? '$message ($attemptsRemaining ${attemptsRemaining == 1 ? 'attempt' : 'attempts'} left)'
                  : message;
        });

        _pinController.clear();
        _shakeController.forward(from: 0.0);
        _showPinErrorSnackBar(
          message: message,
          attemptsRemaining: attemptsRemaining,
        );
        return;
      }
    } catch (e) {
      setState(() => _isProcessingPayment = false);
      _showErrorDialog('PIN Verification Error', _mapExceptionToUserMessage(e));
      return;
    }

    await _executeTransaction(pin: pin);
  }

  Future<void> _processPaymentWithBiometric() async {
    HapticFeedback.mediumImpact();
    final amount = double.tryParse(_amountController.text.trim()) ?? 0;
    final meterNumber = _meterController.text.trim();

    setState(() {
      _isProcessingPayment = true;
      _isAuthenticating = true;
      _pinValidationError = null;
      _useBiometric = true;
    });

    try {
      final isAvailable = await biometricService.isBiometricAvailable();
      if (!isAvailable) {
        setState(() {
          _isProcessingPayment = false;
          _isAuthenticating = false;
        });
        _showErrorDialog(
          'Biometric Not Available',
          'Biometric authentication is not available on this device.',
        );
        return;
      }

      final isEnabled = await biometricService.getBiometricEnabledStatus(
        userId: widget.userId,
      );
      if (!isEnabled) {
        setState(() {
          _isProcessingPayment = false;
          _isAuthenticating = false;
        });
        _showErrorDialog(
          'Biometric Not Enabled',
          'Biometric authentication is not enabled. Please enable it in Settings.',
        );
        return;
      }

      final bool biometricSuccess = await biometricService.authenticate(
        reason:
            'Authenticate to pay Electricity bill of ₦${amount.toStringAsFixed(2)} for meter $meterNumber',
        biometricOnly: false,
        stickyAuth: true,
      );

      if (!biometricSuccess) {
        setState(() {
          _isProcessingPayment = false;
          _isAuthenticating = false;
        });
        _showErrorDialog(
          'Authentication Cancelled',
          'Biometric authentication was cancelled.',
        );
        return;
      }

      await _executeTransaction(useBiometric: true);
    } catch (e) {
      setState(() {
        _isProcessingPayment = false;
        _isAuthenticating = false;
      });
      _showErrorDialog('Authentication Error', _mapExceptionToUserMessage(e));
    }
  }

  // ==================== EXECUTE TRANSACTION WITH LIMIT HANDLING ====================
  Future<void> _executeTransaction({
    String? pin,
    bool useBiometric = false,
  }) async {
    final meterNumber = _meterController.text.trim();
    final amount = double.tryParse(_amountController.text.trim()) ?? 0;
    final phone = _phoneController.text.trim();

    if (widget.userId.isEmpty) {
      _showErrorDialog(
        'Authentication Error',
        'User ID not found. Please log in again.',
      );
      _closePaymentSheet();
      return;
    }

    try {
      final result = await ApiService.payElectricityBill(
        userId: widget.userId,
        serviceID: _selectedProvider!,
        billersCode: meterNumber,
        variationCode: _selectedMeterType!,
        amount: amount,
        phone: phone,
        transactionPin: pin,
        useBiometric: useBiometric,
      );

      _log('📦 Electricity payment result: ${jsonEncode(result)}');

      if (result['alreadyProcessed'] == true || result['success'] == true) {
        final newBalance = result['newBalance'] ?? 0.0;
        setState(() {
          _walletBalance = newBalance;
        });
        widget.onBalanceUpdate(newBalance);

        String token = 'Check SMS';
        final vtpassResponse = result['vtpassResponse'];
        final content = vtpassResponse?['content'];
        if (content != null) {
          if (content['purchased_code'] != null) {
            token = content['purchased_code'].toString();
          } else if (content['Token'] != null) {
            token = content['Token'].toString();
          } else if (result['token'] != null) {
            token = result['token'].toString();
          }
        }

        if (result['success'] == true || vtpassResponse?['code'] == '000') {
          _closePaymentSheet();
          _showSuccessDialog(
            meterNumber: meterNumber,
            amount: amount,
            result: result,
            token: token,
          );
          _clearForm();
          return;
        }
      }

      // ✅ CHECK FOR LIMIT ERRORS FIRST
      final errorCode = result['code']?.toString() ?? '';
      final errorMsg =
          result['message'] ??
          result['vtpassResponse']?['response_description'] ??
          '';

      if (errorCode == 'PER_TRANSACTION_LIMIT_EXCEEDED' ||
          errorCode == 'DAILY_LIMIT_EXCEEDED' ||
          errorMsg.contains('PER_TRANSACTION_LIMIT_EXCEEDED') ||
          errorMsg.contains('DAILY_LIMIT_EXCEEDED')) {
        setState(() {
          _isProcessingPayment = false;
          _isAuthenticating = false;
        });
        _closePaymentSheet();

        // Extract limit info from error
        final limitValue = result['limit'] ?? 0;
        final requestedValue = result['requested'] ?? amount;

        double limit = 0.0;
        if (limitValue is double) {
          limit = limitValue;
        } else if (limitValue is int) {
          limit = limitValue.toDouble();
        } else if (limitValue is num) {
          limit = limitValue.toDouble();
        } else if (limitValue is String) {
          limit = double.tryParse(limitValue) ?? 0.0;
        }

        double requested = 0.0;
        if (requestedValue is double) {
          requested = requestedValue;
        } else if (requestedValue is int) {
          requested = requestedValue.toDouble();
        } else if (requestedValue is num) {
          requested = requestedValue.toDouble();
        } else if (requestedValue is String) {
          requested = double.tryParse(requestedValue) ?? amount;
        } else {
          requested = amount;
        }

        final isDaily =
            errorMsg.contains('DAILY_LIMIT_EXCEEDED') ||
            errorCode == 'DAILY_LIMIT_EXCEEDED';

        _showLimitIncreaseDialog(
          service: 'electricity',
          limitType: isDaily ? 'dailyCap' : 'perTransaction',
          currentLimit: limit,
          requestedAmount: requested,
        );
        return;
      }

      if (result['validationError'] == true ||
          result['errorType'] == 'meter_validation') {
        setState(() {
          _isProcessingPayment = false;
          _isAuthenticating = false;
        });
        _closePaymentSheet();

        final errorMsg2 =
            result['message'] ??
            'Invalid meter number. Please check and try again.';
        _showErrorDialog('Meter Validation Failed', errorMsg2);
        setState(() {
          _isValidated = false;
          _customerName = null;
          _customerAddress = null;
        });
        return;
      }

      if (result['amountBelowMinimum'] == true) {
        setState(() {
          _isProcessingPayment = false;
          _isAuthenticating = false;
        });
        _closePaymentSheet();
        _showErrorDialog(
          'Amount Too Low',
          'Minimum electricity purchase is ₦2,000.',
        );
        return;
      }

      if (result['isFailed'] == true || result['shouldShowAsFailed'] == true) {
        setState(() {
          _isProcessingPayment = false;
          _isAuthenticating = false;
        });
        _closePaymentSheet();
        final errorMsg2 =
            result['message'] ?? 'Transaction failed. Please try again.';
        _showErrorDialog('Transaction Failed', errorMsg2);
        return;
      }

      final vtpassResponse = result['vtpassResponse'];
      if (vtpassResponse != null) {
        final content = vtpassResponse['content'];
        if (content != null && content['error'] != null) {
          final errorMsg2 = content['error'].toString();
          setState(() {
            _isProcessingPayment = false;
            _isAuthenticating = false;
          });
          _closePaymentSheet();
          _showErrorDialog('Meter Validation Failed', errorMsg2);
          setState(() {
            _isValidated = false;
            _customerName = null;
            _customerAddress = null;
          });
          return;
        }
      }

      final vtpassCode =
          vtpassResponse != null
              ? (vtpassResponse['code']?.toString() ??
                  vtpassResponse['vtpassResponse']?['code']?.toString())
              : null;

      final bool vtpassSuccess = vtpassCode == '000';

      if (vtpassSuccess) {
        final newBalance = result['newBalance'] ?? 0.0;
        setState(() {
          _walletBalance = newBalance;
        });
        widget.onBalanceUpdate(newBalance);

        String token = 'Check SMS';
        final content = vtpassResponse?['content'];
        if (content != null) {
          if (content['purchased_code'] != null) {
            token = content['purchased_code'].toString();
          } else if (content['Token'] != null) {
            token = content['Token'].toString();
          } else if (result['token'] != null) {
            token = result['token'].toString();
          }
        }

        _closePaymentSheet();
        _showSuccessDialog(
          meterNumber: meterNumber,
          amount: amount,
          result: result,
          token: token,
        );
        _clearForm();
      } else {
        final errorMsg2 =
            vtpassResponse?['response_description'] ??
            vtpassResponse?['content']?['error'] ??
            result['message'] ??
            'Transaction failed.';

        setState(() {
          _isProcessingPayment = false;
          _isAuthenticating = false;
        });
        _closePaymentSheet();

        if (errorMsg2.contains('meter') ||
            errorMsg2.contains('WrongBillersCode') ||
            errorMsg2.contains('not correct')) {
          _showErrorDialog('Meter Validation Failed', errorMsg2);
          setState(() {
            _isValidated = false;
            _customerName = null;
            _customerAddress = null;
          });
        } else {
          _showErrorDialog('Purchase Failed', errorMsg2);
        }
      }
    } catch (e) {
      setState(() {
        _isProcessingPayment = false;
        _isAuthenticating = false;
      });
      _closePaymentSheet();

      final errorStr = e.toString();

      // ✅ CHECK FOR LIMIT ERRORS IN CATCH BLOCK
      if (errorStr.contains('PER_TRANSACTION_LIMIT_EXCEEDED') ||
          errorStr.contains('DAILY_LIMIT_EXCEEDED')) {
        // Try to extract limit info from error string
        final limitMatch = RegExp(r'₦(\d+\.?\d*)').firstMatch(errorStr);
        double limit = 0.0;
        if (limitMatch != null) {
          final matchValue = limitMatch.group(1);
          if (matchValue != null) {
            limit = double.tryParse(matchValue) ?? 0.0;
          }
        }
        final isDaily = errorStr.contains('DAILY_LIMIT_EXCEEDED');

        _showLimitIncreaseDialog(
          service: 'electricity',
          limitType: isDaily ? 'dailyCap' : 'perTransaction',
          currentLimit: limit,
          requestedAmount: amount,
        );
        return;
      }

      if (errorStr.contains('BELOW MINIMUM AMOUNT ALLOWED')) {
        _showErrorDialog(
          'Amount Too Low',
          'Minimum electricity purchase is ₦2,000.',
        );
      } else if (errorStr.contains('meter') ||
          errorStr.contains('WrongBillersCode') ||
          errorStr.contains('not correct')) {
        final cleanedError = errorStr
            .replaceAll('Exception: ', '')
            .replaceAll('❌ ', '');
        _showErrorDialog('Meter Validation Failed', cleanedError);
        setState(() {
          _isValidated = false;
          _customerName = null;
          _customerAddress = null;
        });
      } else {
        _showErrorDialog('Purchase Failed', _mapExceptionToUserMessage(e));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessingPayment = false;
          _isAuthenticating = false;
        });
      }
    }
  }

  void _log(String message) {
    if (kDebugMode) {
      debugPrint('⚡ ELECTRICITY: $message');
    }
  }

  void _clearForm() {
    _amountController.clear();
    _pinController.clear();
    if (mounted) {
      setState(() {
        _selectedQuickAmount = null;
        _useBiometric = false;
        _pinValidationError = null;
      });
    }
  }

  void _selectQuickAmount(int amount) {
    HapticFeedback.lightImpact();
    setState(() {
      _selectedQuickAmount = amount;
      _amountController.text = amount.toString();
    });
    _amountFocusNode.unfocus();
  }

  // ==================== DIALOGS ====================
  // Meter details are shown inline under the meter field (design), so a
  // short confirmation is enough here.
  void _showValidationSuccessDialog(
    String customerName,
    String address,
    String meterNumber,
    String meterType,
  ) {
    dpSnack(context, 'Meter found: $customerName', success: true);
  }

  void _showSuccessDialog({
    required String meterNumber,
    required double amount,
    required Map<String, dynamic> result,
    required String token,
  }) {
    final transactionId =
        result['transactionId'] ??
        'TXN_${DateTime.now().millisecondsSinceEpoch}';
    final reference = result['reference'] ?? transactionId;
    final providerName =
        _providers.firstWhere(
              (p) => p['id'] == _selectedProvider,
              orElse: () => {'fullName': 'Unknown'},
            )['fullName']
            as String;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => Dialog(
            backgroundColor: Colors.transparent,
            elevation: 0,
            child: ReceiptWidget(
              transactionType: 'Electricity Purchase',
              amount: amount.toStringAsFixed(2),
              status: 'completed',
              transactionId: transactionId,
              reference: reference.toString(),
              date: DateTime.now(),
              phoneNumber: _phoneController.text,
              description: '$providerName ${_selectedMeterType?.toUpperCase()}',
              meterNumber: meterNumber,
              customerName: _customerName ?? 'N/A',
              customerAddress: _customerAddress ?? 'N/A',
              gateway: 'Dalabapay App',
              customMessage: 'Electricity token has been sent via SMS',
              primaryColor: _primaryNavy,
              showWatermark: true,
              electricityToken: token,
              isCommission: false,
            ),
          ),
    );
  }

  void _showErrorDialog(String title, String message) {
    dpDialog(
      context,
      title: title,
      message: message,
      confirmLabel: 'OK',
      tone: DPTone.error,
    );
  }

  // ==================== BUILD METHODS ====================
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_showPaymentSheet,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _showPaymentSheet && !_isProcessingPayment) {
          _closePaymentSheet();
        }
      },
      child: Scaffold(
        backgroundColor: DP.bg,
        body: Stack(
          children: [
            SafeArea(
              child: Column(
                children: [
                  DPTopBar(
                    title: 'Electricity',
                    actionLabel: 'History',
                    onAction: () => Navigator.pushNamed(
                      context,
                      '/transactions',
                      arguments: {'userId': widget.userId},
                    ),
                  ),
                  Expanded(child: _buildBody()),
                ],
              ),
            ),
            if (_showPaymentSheet) _buildPaymentSheetOverlay(),
          ],
        ),
        bottomNavigationBar: _showPaymentSheet ? null : _buildStickyBottomCTA(),
      ),
    );
  }

  Map<String, dynamic>? get _providerData {
    for (final p in _providers) {
      if (p['id'] == _selectedProvider) return p;
    }
    return null;
  }

  // ==================== HEADER / APP BAR ====================


  // ==================== BODY CONTENT ====================
  Widget _buildBody() {
    if (_isLoadingUserData) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!_isUserActive || !_electricityServiceEnabled) {
      return _buildServiceUnavailable();
    }

    final amount = double.tryParse(_amountController.text.trim()) ?? 0;

    return FadeTransition(
      opacity: _fadeAnimation,
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'A brighter day starts here. Top up your meter.',
              style: DP.body.copyWith(color: DP.muted),
            ),
            const SizedBox(height: 20),
            const DPLabel('Electricity provider'),
            _buildProviderGrid(),
            const SizedBox(height: 14),
            _buildMeterTypeToggle(),
            const SizedBox(height: 20),
            _buildMeterNumberInput(),
            const SizedBox(height: 20),
            const DPLabel('Amount'),
            _buildCustomAmountInput(),
            const DPHelper('Minimum purchase: ₦2,000'),
            const SizedBox(height: 12),
            _buildQuickAmountGrid(),
            const SizedBox(height: 20),
            const DPLabel('Phone number for token'),
            _buildPhoneNumberInput(),
            const SizedBox(height: 20),
            WalletCommissionCard(
              walletBalance: _walletBalance,
              amount: amount,
              service: 'electricity',
              balanceVisible: _isBalanceVisible,
            ),
            const SizedBox(height: 14),
            _buildInfoCard(),
          ],
        ),
      ),
    );
  }

  // ==================== CLEAN BANNER ====================

  // ==================== PROVIDER GRID ====================
  Widget _buildProviderGrid() {
    final p = _providerData;
    return DPSelectField(
      value: p == null ? null : p['fullName'] as String,
      hint: 'Choose your provider',
      leading: const Icon(DPIcons.bolt, color: DP.green, size: 20),
      onTap: () async {
        final picked = await dpPickFromList<Map<String, dynamic>>(
          context,
          title: 'Electricity provider',
          items: _providers,
          selected: p,
          labelOf: (x) => x['fullName'] as String,
          subtitleOf: (x) => x['name'] as String,
        );
        if (picked == null || !mounted) return;
        HapticFeedback.selectionClick();
        setState(() {
          _selectedProvider = picked['id'] as String;
          _selectedMeterType = null;
          _isValidated = false;
          _customerName = null;
          _customerAddress = null;
        });
      },
    );
  }

  // ==================== METER TYPE TOGGLE ====================
  Widget _buildMeterTypeToggle() {
    const labels = {'prepaid': 'Prepaid meter', 'postpaid': 'Postpaid account'};
    return DPChipRow(
      options: labels.values.toList(),
      selected: _selectedMeterType == null ? null : labels[_selectedMeterType],
      height: 46,
      onSelect: (label) {
        final value =
            labels.entries.firstWhere((e) => e.value == label).key;
        HapticFeedback.selectionClick();
        setState(() {
          _selectedMeterType = value;
          _isValidated = false;
          _customerName = null;
          _customerAddress = null;
        });
      },
    );
  }


  // ==================== METER NUMBER INPUT ====================
  Widget _buildMeterNumberInput() {
    final canVerify = !_isValidating &&
        _meterController.text.trim().length >= 11 &&
        _selectedProvider != null &&
        _selectedMeterType != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DPLabel(
          'Meter number',
          trailing: _isValidated
              ? null
              : DPTextLink(
                  label: _isValidating ? 'Checking…' : 'Verify meter',
                  color: canVerify ? DP.green : DP.faint,
                  onTap: canVerify ? _validateMeter : null,
                ),
        ),
        DPField(
          controller: _meterController,
          focusNode: _meterFocusNode,
          hint: '11–13 digit meter number',
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(13),
          ],
          onChanged: (_) {
            setState(() {
              if (_isValidated) {
                _isValidated = false;
                _customerName = null;
                _customerAddress = null;
              }
            });
          },
          onSubmitted: (_) {
            if (canVerify) _validateMeter();
          },
          style: const TextStyle(fontSize: 17, color: DP.ink, letterSpacing: 0.6),
          suffix: _isValidating
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  _isValidated ? DPIcons.checkCircle : DPIcons.scan,
                  color: _isValidated ? DP.green : DP.muted,
                ),
        ),
        if (_isValidated && _customerName != null) ...[
          const SizedBox(height: 12),
          DPCard(
            color: DP.mint,
            borderColor: null,
            radius: DP.rLg,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(DPIcons.checkCircle, color: DP.green, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _customerName!.toUpperCase(),
                        style: const TextStyle(
                          color: DP.green,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      if (_customerAddress != null &&
                          _customerAddress!.isNotEmpty &&
                          _customerAddress != 'N/A')
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(
                            _customerAddress!,
                            style: const TextStyle(
                              color: DP.green,
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // ==================== QUICK AMOUNT GRID ====================
  Widget _buildQuickAmountGrid() {
    final labels =
        _quickAmounts.map((a) => DP.naira(a, decimals: false)).toList();
    return DPChipScroller(
      options: labels,
      selected: _selectedQuickAmount == null
          ? null
          : DP.naira(_selectedQuickAmount, decimals: false),
      onSelect: (l) => _selectQuickAmount(_quickAmounts[labels.indexOf(l)]),
    );
  }

  // ==================== CUSTOM AMOUNT INPUT ====================
  Widget _buildCustomAmountInput() {
    return DPField(
      controller: _amountController,
      focusNode: _amountFocusNode,
      hint: '0.00',
      prefixText: '₦',
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      onChanged: (_) {
        setState(() => _selectedQuickAmount = null);
      },
      style: const TextStyle(fontSize: 17, color: DP.ink),
    );
  }

  // ==================== PHONE NUMBER INPUT ====================
  Widget _buildPhoneNumberInput() {
    return DPField(
      controller: _phoneController,
      focusNode: _phoneFocusNode,
      hint: '0803 456 7890',
      keyboardType: TextInputType.phone,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(11),
      ],
      onChanged: (_) => setState(() {}),
      suffix: const Icon(DPIcons.phone, color: DP.muted),
    );
  }

  // ==================== INFO CARD ====================
  Widget _buildInfoCard() {
    return const DPBanner(
      'Your units are set by your provider\'s tariff. Your token will appear on your receipt and arrive by SMS.',
    );
  }

  // ==================== SECTION TITLE ====================
  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(title, style: DP.section),
    );
  }

  // ==================== STICKY BOTTOM CTA ====================
  Widget _buildStickyBottomCTA() {
    return DPBottomAction(
      child: DPButton(
        label: 'Review electricity payment',
        icon: DPIcons.forward,
        loading: _isProcessingPayment || _isAuthenticating,
        onPressed: _openPaymentSheet,
      ),
    );
  }

  // ==================== PAYMENT SHEET OVERLAY ====================
  Widget _buildPaymentSheetOverlay() {
    final amount = double.tryParse(_amountController.text.trim()) ?? 0;
    final p = _providerData;
    final providerName = (p?['fullName'] ?? '') as String;
    final biometricOk = !kIsWeb &&
        (Platform.isAndroid || Platform.isIOS) &&
        _biometricEnabled &&
        _biometricAllowed;
    return Positioned.fill(
      child: AnimatedBuilder(
        animation: _sheetAnimation,
        builder: (context, child) => FractionalTranslation(
          translation: Offset(0, 1 - _sheetAnimation.value),
          child: child,
        ),
        child: AnimatedBuilder(
          animation: _shakeAnimation,
          builder: (context, child) => Transform.translate(
            offset: Offset(_shakeAnimation.value, 0),
            child: child,
          ),
          child: DPReviewPanel(
            icon: DPIcons.bolt,
            title: providerName,
            amount: amount,
            rows: [
              DPReviewRow('Customer', _customerName ?? '—'),
              DPReviewRow('Meter number', _meterController.text.trim()),
              DPReviewRow(
                'Meter type',
                _selectedMeterType == 'postpaid' ? 'Postpaid' : 'Prepaid',
              ),
              DPReviewRow('Token sent to', _phoneController.text.trim()),
              const DPReviewRow('Service fee', '₦0.00'),
              DPReviewRow('Total to pay', DP.naira(amount), strong: true),
            ],
            walletBalance: _walletBalance,
            totalDebit: amount,
            commission: CommissionRatesService.estimate('electricity', amount),
            pinController: _pinController,
            pinFocusNode: _pinFocusNode,
            pinRequired: _transactionPinSet && _pinRequired,
            pinError: _pinValidationError,
            processing: _isProcessingPayment,
            onPay: _processPaymentWithPIN,
            onClose: _closePaymentSheet,
            biometricAvailable: biometricOk,
            biometricLabel: _biometricName,
            onBiometric: _processPaymentWithBiometric,
            footnote: 'Check the meter number. Electricity tokens can\'t be reversed.',
          ),
        ),
      ),
    );
  }

  // ==================== PAYMENT SHEET DETAILS ====================



  // ==================== PIN OPTION ====================

  // ==================== BIOMETRIC OPTION ====================

  // ==================== SERVICE UNAVAILABLE ====================
  Widget _buildServiceUnavailable() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: DPEmptyState(
          icon: DPIcons.bolt,
          title: 'Electricity is unavailable right now',
          message: 'Please try again in a little while.',
          actionLabel: 'Go back',
          onAction: () => Navigator.pop(context),
        ),
      ),
    );
  }
}
