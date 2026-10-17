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
  static const Color _primaryNavy = Color(0xFF243889);
  static const Color _secondaryTeal = Color(0xFF219C7E);
  static const Color _textDark = Color(0xFF1C2D5A);
  static const Color _textMuted = Color(0xFF64748B);
  static const Color _bgCanvas = Color(0xFFF8FAFC);

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
      'textColor': const Color(0xFF1A1A2E),
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
      'color': const Color(0xFF9C27B0),
      'textColor': Colors.white,
    },
    {
      'id': 'ibadan-electric',
      'name': 'IBEDC',
      'fullName': 'Ibadan Electric',
      'logo':
          'https://play-lh.googleusercontent.com/7JrrLm9wlgZkMCBeQCvaCPeyOemK6ZUkHfc54S3o4LiTRIQmXZTYF9onD9NNuL7UnLav0am4SiPWDASoMjntcN8',
      'color': const Color(0xFFFF9800),
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
      'color': const Color(0xFF9C27B0),
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
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFFDC2626),
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

  Widget _buildDetailRow(String label, String value, {int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _textMuted,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: _textDark,
              ),
              textAlign: TextAlign.right,
              maxLines: maxLines,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
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
  void _showValidationSuccessDialog(
    String customerName,
    String address,
    String meterNumber,
    String meterType,
  ) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            backgroundColor: Colors.white,
            child: Container(
              padding: const EdgeInsets.all(24),
              width: MediaQuery.of(context).size.width * 0.9,
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.8,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            _secondaryTeal,
                            _secondaryTeal.withOpacity(0.7),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: _secondaryTeal.withOpacity(0.3),
                            blurRadius: 20,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.check_circle_outline,
                        color: Colors.white,
                        size: 40,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Meter Validated Successfully',
                      style: GoogleFonts.poppins(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: _primaryNavy,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: _secondaryTeal.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'Verification Complete',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _secondaryTeal,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Divider(color: Color(0xFFEEEEEE)),
                    const SizedBox(height: 16),
                    _buildDetailRow('Customer Name', customerName),
                    const SizedBox(height: 8),
                    _buildDetailRow('Address', address, maxLines: 3),
                    const SizedBox(height: 8),
                    _buildDetailRow('Meter Number', meterNumber),
                    const SizedBox(height: 8),
                    _buildDetailRow('Meter Type', meterType.toUpperCase()),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _primaryNavy.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _primaryNavy.withOpacity(0.1),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.shield_outlined,
                            color: _primaryNavy,
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'This meter has been verified and is ready for payment.',
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: _primaryNavy,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () {
                              if (Navigator.canPop(context)) {
                                if (Navigator.canPop(context)) {
                                  Navigator.pop(context);
                                } else {
                                  // Navigate to a fallback screen
                                  Navigator.pushReplacementNamed(
                                    context,
                                    '/home',
                                  );
                                }
                              } else {
                                // Navigate to a fallback screen
                                Navigator.pushReplacementNamed(
                                  context,
                                  '/home',
                                );
                              }
                              setState(() {
                                _isValidated = false;
                                _customerName = null;
                                _customerAddress = null;
                              });
                            },
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.grey.shade700,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(color: Colors.grey.shade300),
                              ),
                            ),
                            child: Text(
                              'Retry',
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              if (Navigator.canPop(context)) {
                                if (Navigator.canPop(context)) {
                                  Navigator.pop(context);
                                } else {
                                  // Navigate to a fallback screen
                                  Navigator.pushReplacementNamed(
                                    context,
                                    '/home',
                                  );
                                }
                              } else {
                                // Navigate to a fallback screen
                                Navigator.pushReplacementNamed(
                                  context,
                                  '/home',
                                );
                              }
                              FocusScope.of(
                                context,
                              ).requestFocus(_amountFocusNode);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _primaryNavy,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 2,
                            ),
                            child: Text(
                              'Proceed to Pay',
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
    );
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
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            backgroundColor: Colors.white,
            title: Row(
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  color: Colors.red.shade700,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: GoogleFonts.poppins(
                    color: Colors.red.shade700,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            content: Text(
              message,
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'OK',
                  style: GoogleFonts.poppins(
                    color: _secondaryTeal,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
    );
  }

  // ==================== BUILD METHODS ====================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgCanvas,
      appBar: _buildAppBar(),
      body: Stack(
        children: [
          _buildBody(),
          if (_showPaymentSheet) _buildPaymentSheetOverlay(),
        ],
      ),
      bottomNavigationBar: _showPaymentSheet ? null : _buildStickyBottomCTA(),
    );
  }

  // ==================== HEADER / APP BAR ====================
  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      leading: IconButton(
        icon: const Icon(
          Icons.arrow_back_ios_new_rounded,
          color: _primaryNavy,
          size: 18,
        ),
        onPressed: () => Navigator.pop(context),
      ),
      title: Text(
        'Electricity',
        style: GoogleFonts.poppins(
          color: _primaryNavy,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      centerTitle: true,
      actions: [_buildWalletBalanceBadge(), const SizedBox(width: 16)],
    );
  }

  Widget _buildWalletBalanceBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _primaryNavy.withOpacity(0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _primaryNavy.withOpacity(0.1)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.account_balance_wallet_rounded,
            color: _primaryNavy,
            size: 15,
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _isBalanceVisible = !_isBalanceVisible);
            },
            child: Text(
              _isBalanceVisible
                  ? '₦${_walletBalance.toStringAsFixed(2)}'
                  : '••••••',
              style: GoogleFonts.poppins(
                color: _primaryNavy,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== BODY CONTENT ====================
  Widget _buildBody() {
    if (_isLoadingUserData) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(_primaryNavy),
        ),
      );
    }

    if (!_isUserActive || !_electricityServiceEnabled) {
      return _buildServiceUnavailable();
    }

    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.only(
            left: 20,
            right: 20,
            top: 12,
            bottom: 100,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildCleanBanner(),
              const SizedBox(height: 20),

              // Provider Selection
              _buildSectionTitle('Select Provider'),
              const SizedBox(height: 12),
              _buildProviderGrid(),
              const SizedBox(height: 24),

              // Meter Type
              _buildSectionTitle('Meter Type'),
              const SizedBox(height: 12),
              _buildMeterTypeToggle(),
              const SizedBox(height: 24),

              // Meter Number
              _buildMeterNumberInput(),
              const SizedBox(height: 24),

              // Amount Selection
              _buildSectionTitle('Select Amount'),
              const SizedBox(height: 12),
              _buildQuickAmountGrid(),
              const SizedBox(height: 16),
              _buildCustomAmountInput(),
              const SizedBox(height: 20),

              // Phone Number
              _buildSectionTitle('Phone Number'),
              const SizedBox(height: 8),
              _buildPhoneNumberInput(),
              const SizedBox(height: 24),

              // Info Card
              _buildInfoCard(),
            ],
          ),
        ),
      ),
    );
  }

  // ==================== CLEAN BANNER ====================
  Widget _buildCleanBanner() {
    return Container(
      width: double.infinity,
      height: 120,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        image: const DecorationImage(
          image: AssetImage('assets/electricity_banner.png'),
          fit: BoxFit.cover,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
    );
  }

  // ==================== PROVIDER GRID ====================
  Widget _buildProviderGrid() {
    return SizedBox(
      height: 82,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: _providers.length,
        itemBuilder: (context, index) {
          final provider = _providers[index];
          final isSelected = _selectedProvider == provider['id'];
          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() {
                _selectedProvider = provider['id'];
                _selectedMeterType = null;
                _isValidated = false;
                _customerName = null;
                _customerAddress = null;
              });
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              width: 76,
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isSelected ? provider['color'] : Colors.grey.shade200,
                  width: isSelected ? 2.5 : 1.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color:
                        isSelected
                            ? (provider['color'] as Color).withOpacity(0.25)
                            : Colors.black.withOpacity(0.03),
                    blurRadius: isSelected ? 8 : 4,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      provider['logo'],
                      width: 32,
                      height: 32,
                      fit: BoxFit.contain,
                      errorBuilder:
                          (context, error, stackTrace) => Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: provider['color'].withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              Icons.electrical_services,
                              color: provider['color'],
                              size: 18,
                            ),
                          ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    provider['name'],
                    style: GoogleFonts.poppins(
                      fontSize: 10,
                      fontWeight:
                          isSelected ? FontWeight.w800 : FontWeight.w600,
                      color: _textDark,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ==================== METER TYPE TOGGLE ====================
  Widget _buildMeterTypeToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          _buildTypeOption('Prepaid', 'prepaid'),
          _buildTypeOption('Postpaid', 'postpaid'),
        ],
      ),
    );
  }

  Widget _buildTypeOption(String label, String value) {
    final isSelected = _selectedMeterType == value;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() {
            _selectedMeterType = value;
            _isValidated = false;
            _customerName = null;
            _customerAddress = null;
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? _primaryNavy : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                value == 'prepaid'
                    ? Icons.electrical_services_rounded
                    : Icons.receipt_long_rounded,
                color: isSelected ? Colors.white : Colors.grey.shade600,
                size: 16,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.white : Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==================== METER NUMBER INPUT ====================
  Widget _buildMeterNumberInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Meter Number'),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color:
                        _meterFocusNode.hasFocus
                            ? _primaryNavy
                            : Colors.grey.shade200,
                    width: _meterFocusNode.hasFocus ? 1.5 : 1.0,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.03),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: TextField(
                  controller: _meterController,
                  focusNode: _meterFocusNode,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(13),
                  ],
                  decoration: InputDecoration(
                    hintText: 'Enter 11-13 digit meter number',
                    hintStyle: GoogleFonts.poppins(
                      color: Colors.grey.shade400,
                      fontSize: 14,
                    ),
                    prefixIcon: Container(
                      padding: const EdgeInsets.all(12),
                      child: HugeIcon(
                        icon: HugeIcons.strokeRoundedLeftToRightListNumber,
                        color: _primaryNavy,
                        size: 22,
                      ),
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 14,
                    ),
                  ),
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _textDark,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 90,
              height: 48,
              child: ElevatedButton(
                onPressed:
                    _isValidating ||
                            _meterController.text.isEmpty ||
                            _selectedProvider == null ||
                            _selectedMeterType == null
                        ? null
                        : _validateMeter,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _secondaryTeal,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: EdgeInsets.zero,
                ),
                child:
                    _isValidating
                        ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                        : Text(
                          'Validate',
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Validation Status
        if (_isValidated && _customerName != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _secondaryTeal.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _secondaryTeal.withOpacity(0.2)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: _secondaryTeal.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.check_circle_outline,
                    color: _secondaryTeal,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Meter Validated',
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: _secondaryTeal,
                        ),
                      ),
                      Text(
                        _customerName!,
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: _secondaryTeal,
                        ),
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

  // ==================== QUICK AMOUNT GRID ====================
  Widget _buildQuickAmountGrid() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 2.2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: _quickAmounts.length,
      itemBuilder: (context, index) {
        final amount = _quickAmounts[index];
        final isSelected = _selectedQuickAmount == amount;

        return GestureDetector(
          onTap: () => _selectQuickAmount(amount),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: isSelected ? _primaryNavy : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected ? _primaryNavy : Colors.grey.shade200,
                width: isSelected ? 2 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color:
                      isSelected
                          ? _primaryNavy.withOpacity(0.2)
                          : Colors.black.withOpacity(0.02),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Center(
              child: Text(
                '₦${NumberFormat('#,##0').format(amount)}',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  color: isSelected ? Colors.white : _textDark,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ==================== CUSTOM AMOUNT INPUT ====================
  Widget _buildCustomAmountInput() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color:
              _amountFocusNode.hasFocus ? _primaryNavy : Colors.grey.shade200,
          width: _amountFocusNode.hasFocus ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: TextField(
        controller: _amountController,
        focusNode: _amountFocusNode,
        keyboardType: TextInputType.number,
        onChanged: (_) {
          setState(() => _selectedQuickAmount = null);
        },
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          hintText: 'Enter custom amount (min ₦2,000)',
          hintStyle: GoogleFonts.poppins(
            color: Colors.grey.shade400,
            fontSize: 13,
          ),
          prefixIcon: const Icon(
            Icons.payments_rounded,
            color: _secondaryTeal,
            size: 20,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
        ),
        style: GoogleFonts.poppins(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: _textDark,
        ),
      ),
    );
  }

  // ==================== PHONE NUMBER INPUT ====================
  Widget _buildPhoneNumberInput() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _phoneFocusNode.hasFocus ? _primaryNavy : Colors.grey.shade200,
          width: _phoneFocusNode.hasFocus ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: TextField(
        controller: _phoneController,
        focusNode: _phoneFocusNode,
        keyboardType: TextInputType.phone,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(11),
        ],
        decoration: InputDecoration(
          hintText: 'Enter 11-digit phone number',
          hintStyle: GoogleFonts.poppins(
            color: Colors.grey.shade400,
            fontSize: 14,
          ),
          prefixIcon: Container(
            padding: const EdgeInsets.all(12),
            child: HugeIcon(
              icon: HugeIcons.strokeRoundedSmartPhone01,
              color: _primaryNavy,
              size: 22,
            ),
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 4,
            vertical: 14,
          ),
        ),
        style: GoogleFonts.poppins(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: _textDark,
        ),
      ),
    );
  }

  // ==================== INFO CARD ====================
  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _primaryNavy.withOpacity(0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _primaryNavy.withOpacity(0.08)),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: _primaryNavy.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.info_outline_rounded,
              color: _primaryNavy,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Make sure you enter the correct meter number. Double-check before validating.',
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: _textMuted,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== SECTION TITLE ====================
  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: GoogleFonts.poppins(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: _primaryNavy,
      ),
    );
  }

  // ==================== STICKY BOTTOM CTA ====================
  Widget _buildStickyBottomCTA() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: SizedBox(
          width: double.infinity,
          height: 52,
          child: Container(
            decoration: BoxDecoration(
              color: _secondaryTeal, // ✅ Plain green color
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: _secondaryTeal.withOpacity(0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ElevatedButton(
              onPressed:
                  _isProcessingPayment || _isAuthenticating
                      ? null
                      : _openPaymentSheet,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child:
                  _isProcessingPayment || _isAuthenticating
                      ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.5,
                        ),
                      )
                      : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.bolt_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Proceed to Pay',
                            style: GoogleFonts.poppins(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
            ),
          ),
        ),
      ),
    );
  }

  // ==================== PAYMENT SHEET OVERLAY ====================
  Widget _buildPaymentSheetOverlay() {
    return GestureDetector(
      onTap: _isProcessingPayment ? null : _closePaymentSheet,
      child: AnimatedBuilder(
        animation: _sheetAnimation,
        builder: (context, child) {
          return Opacity(
            opacity: _sheetAnimation.value,
            child: Container(
              color: Colors.black.withOpacity(0.4 * _sheetAnimation.value),
              child: Stack(
                children: [
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Transform.translate(
                      offset: Offset(
                        0,
                        (1 - _sheetAnimation.value) *
                            MediaQuery.of(context).size.height *
                            0.6,
                      ),
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(24),
                          ),
                        ),
                        child: SafeArea(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                margin: const EdgeInsets.only(top: 12),
                                width: 40,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade300,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Stack(
                                children: [
                                  Center(
                                    child: Image.asset(
                                      'assets/dalabapay2.png',
                                      height: 38,
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                  Positioned(
                                    right: 16,
                                    top: 0,
                                    child: GestureDetector(
                                      onTap:
                                          _isProcessingPayment
                                              ? null
                                              : _closePaymentSheet,
                                      child: Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: Colors.grey.shade100,
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.close_rounded,
                                          size: 18,
                                          color: _textMuted,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Confirm Payment',
                                style: GoogleFonts.poppins(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: _textDark,
                                ),
                              ),
                              const SizedBox(height: 16),
                              _buildPaymentSheetDetails(),
                              const SizedBox(height: 16),
                              _buildPaymentSheetBalance(),
                              const SizedBox(height: 20),
                              Divider(color: Colors.grey.shade200, height: 1),
                              const SizedBox(height: 20),

                              if (_transactionPinSet) ...[
                                _buildPinOption(),
                                const SizedBox(height: 12),
                              ],

                              if (_biometricEnabled && _biometricAllowed)
                                _buildBiometricOption(),

                              if (!_transactionPinSet && !_biometricEnabled)
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.shade50,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Colors.orange.shade200,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.warning_amber_rounded,
                                        color: Colors.orange.shade700,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          'Set up a transaction PIN or enable biometric in Settings to make payments.',
                                          style: GoogleFonts.poppins(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.orange.shade800,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              const SizedBox(height: 20),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ==================== PAYMENT SHEET DETAILS ====================
  Widget _buildPaymentSheetDetails() {
    final provider = _providers.firstWhere(
      (p) => p['id'] == _selectedProvider,
      orElse: () => _providers.first,
    );
    final meterNumber = _meterController.text.trim();
    final amount = double.tryParse(_amountController.text.trim()) ?? 0;
    final phone = _phoneController.text.trim();
    final meterType = _selectedMeterType?.toUpperCase() ?? 'N/A';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        children: [
          _buildPaymentRow(
            icon: Icons.electrical_services_rounded,
            iconColor: provider['color'] as Color,
            label: 'Provider',
            value: provider['fullName'] ?? 'N/A',
          ),
          Divider(height: 16, color: Colors.grey.shade200),
          _buildPaymentRow(
            icon: Icons.electrical_services_rounded,
            iconColor: const Color(0xFF8B5CF6),
            label: 'Meter Type',
            value: meterType,
          ),
          Divider(height: 16, color: Colors.grey.shade200),
          _buildPaymentRow(
            icon: Icons.numbers_rounded,
            iconColor: _primaryNavy,
            label: 'Meter Number',
            value: meterNumber,
          ),
          Divider(height: 16, color: Colors.grey.shade200),
          _buildPaymentRow(
            icon: Icons.person_outline_rounded,
            iconColor: _secondaryTeal,
            label: 'Customer',
            value: _customerName ?? 'N/A',
          ),
          Divider(height: 16, color: Colors.grey.shade200),
          _buildPaymentRow(
            icon: Icons.payments_rounded,
            iconColor: _secondaryTeal,
            label: 'Amount',
            value: '₦${amount.toStringAsFixed(2)}',
            isAmount: true,
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentRow({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
    bool isAmount = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: iconColor, size: 18),
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _textMuted,
              ),
            ),
          ],
        ),
        Text(
          value,
          style: GoogleFonts.poppins(
            fontSize: isAmount ? 16 : 14,
            fontWeight: isAmount ? FontWeight.w800 : FontWeight.w700,
            color: isAmount ? _secondaryTeal : _textDark,
          ),
        ),
      ],
    );
  }

  Widget _buildPaymentSheetBalance() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _secondaryTeal.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _secondaryTeal.withOpacity(0.15)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Available Balance',
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _textMuted,
            ),
          ),
          Text(
            '₦${_walletBalance.toStringAsFixed(2)}',
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: _secondaryTeal,
            ),
          ),
        ],
      ),
    );
  }

  // ==================== PIN OPTION ====================
  Widget _buildPinOption() {
    final bool hasError = _pinValidationError != null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: AnimatedBuilder(
        animation: _shakeAnimation,
        builder: (context, child) {
          return Transform.translate(
            offset: Offset(_shakeAnimation.value, 0),
            child: child,
          );
        },
        child: Container(
          decoration: BoxDecoration(
            color:
                hasError
                    ? const Color(0xFFFEF2F2)
                    : _primaryNavy.withOpacity(0.04),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: hasError ? const Color(0xFFEF4444) : _primaryNavy,
              width: hasError ? 2 : 1.5,
            ),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _pinController,
                  focusNode: _pinFocusNode,
                  obscureText: true,
                  decoration: InputDecoration(
                    hintText: 'Enter 6-digit transaction PIN',
                    hintStyle: GoogleFonts.poppins(
                      color:
                          hasError
                              ? const Color(0xFFEF4444).withOpacity(0.7)
                              : Colors.grey.shade600,
                      fontSize: 13,
                    ),
                    prefixIcon: Icon(
                      Icons.lock_outline_rounded,
                      color: hasError ? const Color(0xFFEF4444) : _primaryNavy,
                      size: 20,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: hasError ? const Color(0xFFDC2626) : Colors.black,
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                  onChanged: (_) {
                    if (_pinValidationError != null) {
                      setState(() => _pinValidationError = null);
                    }
                  },
                ),
              ),
              if (hasError)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  color: const Color(0xFFFEE2E2),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        color: Color(0xFFDC2626),
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _pinValidationError!,
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFFDC2626),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed:
                      _isProcessingPayment ? null : _processPaymentWithPIN,
                  style: TextButton.styleFrom(
                    backgroundColor:
                        hasError ? const Color(0xFFDC2626) : _secondaryTeal,
                    foregroundColor: Colors.white,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(
                        bottom: Radius.circular(12),
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child:
                      _isProcessingPayment && !_useBiometric
                          ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                          : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.lock_outline_rounded,
                                color: Colors.white,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Pay with PIN',
                                style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
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

  // ==================== BIOMETRIC OPTION ====================
  Widget _buildBiometricOption() {
    final bool isBiometricSupported =
        !kIsWeb && (Platform.isAndroid || Platform.isIOS);

    if (!isBiometricSupported || !_biometricEnabled) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: GestureDetector(
        onTap: _isProcessingPayment ? null : _processPaymentWithBiometric,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          decoration: BoxDecoration(
            color: _primaryNavy.withOpacity(0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _primaryNavy, width: 1.5),
          ),
          child:
              _isProcessingPayment && _useBiometric
                  ? const Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        color: _primaryNavy,
                        strokeWidth: 2.5,
                      ),
                    ),
                  )
                  : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.fingerprint_rounded,
                        color: _primaryNavy,
                        size: 28,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Pay with $_biometricName',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: _primaryNavy,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: _secondaryTeal,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.check_rounded,
                          color: Colors.white,
                          size: 14,
                        ),
                      ),
                    ],
                  ),
        ),
      ),
    );
  }

  // ==================== SERVICE UNAVAILABLE ====================
  Widget _buildServiceUnavailable() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              !_isUserActive ? Icons.account_circle : Icons.electrical_services,
              color:
                  !_isUserActive ? Colors.red.shade700 : Colors.orange.shade700,
              size: 60,
            ),
            const SizedBox(height: 16),
            Text(
              !_isUserActive ? 'Account Deactivated' : 'Service Unavailable',
              style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color:
                    !_isUserActive
                        ? Colors.red.shade700
                        : Colors.orange.shade700,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              !_isUserActive
                  ? 'Your account has been deactivated. Please contact support.'
                  : 'Electricity service is currently unavailable. Please try again later.',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryNavy,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 12,
                ),
              ),
              child: Text(
                'Go Back',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
