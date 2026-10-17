// lib/presentation/screens/electricity/electricity_screen.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../core/services/api_service.dart';
import '../../../core/services/biometric_service.dart';
import '../../../core/widgets/receipt_widget.dart';
import '../../../core/widgets/request_limit_increase_dialog.dart';
import '../../../ui/ui.dart';

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
    final displayMsg = attemptsRemaining != null
        ? '$message ($attemptsRemaining ${attemptsRemaining == 1 ? 'attempt' : 'attempts'} remaining)'
        : message;
    dpSnack(context, displayMsg, error: true);
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
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 110, child: Text(label, style: DPText.bodyMuted.copyWith(fontSize: 13))),
          Expanded(
            child: Text(
              value,
              style: DPText.value.copyWith(fontSize: 13),
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
    dpSnack(context, 'Meter verified for ${customerName.toUpperCase()}', success: true);
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
              primaryColor: DP.navy,
              showWatermark: true,
              electricityToken: token,
              isCommission: false,
            ),
          ),
    );
  }

  void _showErrorDialog(String title, String message) {
    showDPDialog(context, tone: DPDialogTone.error, title: title, message: message);
  }

  // ==================== BUILD METHODS ====================
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        DPPage(
          title: 'Electricity',
          actionLabel: 'History',
          onAction: () => Navigator.pushNamed(context, '/transactions'),
          bottom: _isLoadingUserData || !_isUserActive || !_electricityServiceEnabled
              ? null
              : _buildStickyBottomCTA(),
          children: [_buildBody()],
        ),
        if (_showPaymentSheet) _buildPaymentSheetOverlay(),
      ],
    );
  }

  // ==================== HEADER / APP BAR ====================


  // ==================== BODY CONTENT ====================
  Widget _buildBody() {
    if (_isLoadingUserData) {
      return const Padding(padding: EdgeInsets.only(top: 80), child: DPLoader());
    }
    if (!_isUserActive || !_electricityServiceEnabled) {
      return _buildServiceUnavailable();
    }
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 18),
              child: Text('A brighter day starts here. Top up your meter.', style: DPText.bodyMuted),
            ),
            _buildProviderGrid(),
            _buildMeterTypeToggle(),
            _buildMeterNumberInput(),
            _buildCustomAmountInput(),
            _buildQuickAmountGrid(),
            _buildPhoneNumberInput(),
            _buildInfoCard(),
          ],
        ),
      ),
    );
  }

  // ==================== CLEAN BANNER ====================

  // ==================== PROVIDER GRID ====================
  Widget _buildProviderGrid() {
    final selected = _providers.firstWhere(
      (p) => p['id'] == _selectedProvider,
      orElse: () => <String, dynamic>{},
    );
    return DPSelectField(
      label: 'Electricity provider',
      value: selected.isEmpty ? null : '${selected['fullName']} (${selected['name']})',
      hint: 'Choose your provider',
      onTap: () {
        showDPSheet(
          context,
          title: 'Electricity provider',
          builder: (ctx) => Column(
            children: [
              for (final provider in _providers)
                DPOptionRow(
                  leading: const DPIcon(DPIcons.zap, size: 20, color: DP.green),
                  title: provider['fullName'] as String,
                  subtitle: provider['name'] as String,
                  selected: _selectedProvider == provider['id'],
                  onTap: () {
                    Navigator.pop(ctx);
                    HapticFeedback.selectionClick();
                    setState(() {
                      _selectedProvider = provider['id'];
                      _selectedMeterType = null;
                      _isValidated = false;
                      _customerName = null;
                      _customerAddress = null;
                    });
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  // ==================== METER TYPE TOGGLE ====================
  Widget _buildMeterTypeToggle() {
    const values = ['prepaid', 'postpaid'];
    return DPChipGrid(
      labels: const ['Prepaid meter', 'Postpaid account'],
      columns: 2,
      selectedIndex: _selectedMeterType == null ? null : values.indexOf(_selectedMeterType!),
      onSelected: (i) {
        HapticFeedback.selectionClick();
        setState(() {
          _selectedMeterType = values[i];
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
        _meterController.text.isNotEmpty &&
        _selectedProvider != null &&
        _selectedMeterType != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DPField(
          label: 'Meter number',
          labelTrailing: DPLinkButton(
            label: _isValidating ? 'Verifying…' : (_isValidated ? 'Verified' : 'Verify meter'),
            onPressed: canVerify && !_isValidated ? _validateMeter : null,
            color: canVerify || _isValidated ? DP.green : DP.faint,
          ),
          controller: _meterController,
          focusNode: _meterFocusNode,
          keyboardType: TextInputType.number,
          hint: '45109839821',
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(13),
          ],
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) {
            if (canVerify) _validateMeter();
          },
          margin: EdgeInsets.only(bottom: _isValidated ? 10 : 18),
          suffix: _isValidating
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : null,
          suffixIcon: DPIcons.scanLine,
        ),
        if (_isValidated && _customerName != null)
          DPVerifiedName(
            name: _customerName!,
            detail: _customerAddress != null && _customerAddress != 'N/A' ? _customerAddress : null,
          ),
      ],
    );
  }

  // ==================== QUICK AMOUNT GRID ====================
  Widget _buildQuickAmountGrid() {
    final idx = _selectedQuickAmount == null ? -1 : _quickAmounts.indexOf(_selectedQuickAmount!);
    return DPChipGrid(
      labels: _quickAmounts.map((a) => dpNaira(a, decimals: false)).toList(),
      columns: 3,
      height: 42,
      selectedIndex: idx < 0 ? null : idx,
      onSelected: (i) => _selectQuickAmount(_quickAmounts[i]),
    );
  }

  // ==================== CUSTOM AMOUNT INPUT ====================
  Widget _buildCustomAmountInput() {
    return DPField(
      label: 'Amount',
      controller: _amountController,
      focusNode: _amountFocusNode,
      keyboardType: TextInputType.number,
      prefixText: '₦ ',
      hint: '0',
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      onChanged: (_) => setState(() => _selectedQuickAmount = null),
      helper: 'Minimum purchase: ₦2,000',
      margin: const EdgeInsets.only(bottom: 12),
    );
  }

  // ==================== PHONE NUMBER INPUT ====================
  Widget _buildPhoneNumberInput() {
    return DPField(
      label: 'Phone number for token',
      controller: _phoneController,
      focusNode: _phoneFocusNode,
      keyboardType: TextInputType.phone,
      hint: '0803 456 7890',
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(11),
      ],
      suffixIcon: DPIcons.phone,
      onChanged: (_) => setState(() {}),
    );
  }

  // ==================== INFO CARD ====================
  Widget _buildInfoCard() {
    final amount = double.tryParse(_amountController.text.trim()) ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DPSummaryCard(rows: [
          DPSummaryRow('Wallet balance',
              _isBalanceVisible ? dpNaira(_walletBalance) : '₦ ••••'),
          const DPSummaryRow('Service fee', '₦0.00'),
          DPSummaryRow('Total to pay', dpNaira(amount), emphasize: true),
        ]),
        const DPNotice(
          'Your units are set by your provider’s tariff. Your token will appear on your receipt and arrive by SMS.',
          margin: EdgeInsets.zero,
        ),
      ],
    );
  }

  // ==================== SECTION TITLE ====================
  Widget _buildSectionTitle(String title) => DPFieldLabel(title);

  // ==================== STICKY BOTTOM CTA ====================
  Widget _buildStickyBottomCTA() {
    return DPButton(
      label: 'Review electricity payment',
      icon: DPIcons.arrowRight,
      loading: _isProcessingPayment || _isAuthenticating,
      onPressed: _isProcessingPayment || _isAuthenticating ? null : _openPaymentSheet,
    );
  }

  // ==================== PAYMENT SHEET OVERLAY ====================
  Widget _buildPaymentSheetOverlay() {
    final provider = _providers.firstWhere(
      (p) => p['id'] == _selectedProvider,
      orElse: () => {'fullName': 'Unknown', 'name': ''},
    );
    final amount = double.tryParse(_amountController.text.trim()) ?? 0;
    final bool isBiometricSupported = Platform.isAndroid || Platform.isIOS;
    final canBiometric = isBiometricSupported && _biometricEnabled && _biometricAllowed;
    return DPSheetOverlay(
      animation: _sheetAnimation,
      onDismiss: _isProcessingPayment ? null : _closePaymentSheet,
      child: DPPaymentReview(
        icon: DPIcons.zap,
        serviceLabel: '${provider['fullName']} · ${(_selectedMeterType ?? '').toLowerCase() == 'prepaid' ? 'Prepaid' : 'Postpaid'}',
        amount: amount,
        rows: [
          DPSummaryRow('Customer', _customerName ?? '—'),
          DPSummaryRow('Meter number', _meterController.text.trim()),
          DPSummaryRow('Phone for token', _phoneController.text.trim()),
          const DPSummaryRow('Service fee', '₦0.00'),
          DPSummaryRow('Total to pay', dpNaira(amount), emphasize: true),
        ],
        walletBalance: _walletBalance,
        showPin: _transactionPinSet,
        pinController: _pinController,
        pinFocusNode: _pinFocusNode,
        pinError: _pinValidationError,
        shake: _shakeAnimation,
        onPinChanged: (_) {
          if (_pinValidationError != null) setState(() => _pinValidationError = null);
        },
        processing: _isProcessingPayment,
        processingBiometric: _useBiometric,
        onPayWithPin: _processPaymentWithPIN,
        onPayWithBiometric: canBiometric ? _processPaymentWithBiometric : null,
        biometricName: _biometricName,
        onClose: _closePaymentSheet,
        footnote: 'Units are delivered to the meter number above and can’t be reversed.',
      ),
    );
  }

  // ==================== PAYMENT SHEET DETAILS ====================



  // ==================== PIN OPTION ====================

  // ==================== BIOMETRIC OPTION ====================

  // ==================== SERVICE UNAVAILABLE ====================
  Widget _buildServiceUnavailable() {
    return const DPServiceUnavailable(
      message: 'Electricity payments are currently unavailable. Please try again later.',
    );
  }
}
