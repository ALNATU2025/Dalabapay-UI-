import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/services/api_service.dart';
import '../../../core/services/biometric_service.dart';
import '../../../core/widgets/receipt_widget.dart';
import '../../../core/widgets/request_limit_increase_dialog.dart';
import '../../../ui/ui.dart';

class AirtimeScreen extends StatefulWidget {
  final void Function(double newBalance) onBalanceUpdate;
  final String userId;

  const AirtimeScreen({
    super.key,
    required this.onBalanceUpdate,
    required this.userId,
  });

  @override
  State<AirtimeScreen> createState() => _AirtimeScreenState();
}

class _AirtimeScreenState extends State<AirtimeScreen>
    with TickerProviderStateMixin {
  // ==================== CONTROLLERS & FOCUS NODES ====================
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _pinController = TextEditingController();

  final FocusNode _phoneFocusNode = FocusNode();
  final FocusNode _amountFocusNode = FocusNode();
  final FocusNode _pinFocusNode = FocusNode();

  // ==================== STATE VARIABLES ====================
  String? _selectedNetwork;
  bool _isAuthenticating = false;
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
  final bool _airtimeServiceEnabled = true;
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


  // ==================== DATA COLLECTIONS ====================
  final List<Map<String, dynamic>> _networks = [
    {
      'name': 'MTN',
      'apiName': 'mtn',
      'image': 'assets/mtn.jpg',
      'color': const Color(0xFFFFCB05),
    },
    {
      'name': 'Airtel',
      'apiName': 'airtel',
      'image': 'assets/airtel.jpg',
      'color': const Color(0xFFEF1C25),
    },
    {
      'name': 'Glo',
      'apiName': 'glo',
      'image': 'assets/glo.png',
      'color': const Color(0xFF00843D),
    },
    {
      'name': '9mobile',
      'apiName': 'etisalat',
      'image': 'assets/t2.png',
      'color': const Color(0xFFF57C00),
    },
  ];

  final List<int> _quickAmounts = [500, 1000, 2000, 3000, 5000, 10000];

  // Dynamic Recent Recharges (Strictly no dummy data)
  List<Map<String, String>> _recentRecharges = [];

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _initializeData();
    _fetchSecuritySettings();
    _loadWalletBalance();
    _checkBiometricSupport();
    _loadRecentRecharges();
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
    _phoneController.dispose();
    _amountController.dispose();
    _pinController.dispose();
    _phoneFocusNode.dispose();
    _amountFocusNode.dispose();
    _pinFocusNode.dispose();
    super.dispose();
  }

  // ==================== DYNAMIC RECENT RECHARGES STORAGE ====================
  Future<void> _loadRecentRecharges() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? jsonString = prefs.getString('recent_airtime_recharges');
      if (jsonString != null && jsonString.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(jsonString);
        if (mounted) {
          setState(() {
            _recentRecharges =
                decoded
                    .map((item) => Map<String, String>.from(item))
                    .take(5)
                    .toList();
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _recentRecharges = [];
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading recent recharges: $e');
    }
  }

  Future<void> _saveRecentRecharge(String phone, String network) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      _recentRecharges.removeWhere((item) => item['phone'] == phone);

      final name =
          phone.length >= 11
              ? '0${phone.substring(1, 4)}...${phone.substring(7)}'
              : phone;

      _recentRecharges.insert(0, {
        'name': name,
        'phone': phone,
        'network': network,
      });

      if (_recentRecharges.length > 5) {
        _recentRecharges = _recentRecharges.sublist(0, 5);
      }

      await prefs.setString(
        'recent_airtime_recharges',
        jsonEncode(_recentRecharges),
      );

      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Error saving recent recharge: $e');
    }
  }

  // ==================== CONTACT PICKER (WEB & NATIVE HYBRID) ====================
  Future<void> _pickContactFromDevice() async {
    HapticFeedback.lightImpact();

    // 1. WEB PLATFORM TEST MODE
    if (kIsWeb) {
      _showWebContactPicker();
      return;
    }

    // 2. NATIVE ANDROID / IOS METHOD CHANNEL
    try {
      const platform = MethodChannel('com.dalabapay.official/contacts');
      final Map<dynamic, dynamic>? result = await platform.invokeMethod(
        'selectContact',
      );

      if (result != null && result['phone'] != null) {
        final String rawPhone = result['phone'].toString().replaceAll(
          RegExp(r'\D'),
          '',
        );

        String cleanPhone = rawPhone;
        if (cleanPhone.startsWith('234') && cleanPhone.length == 13) {
          cleanPhone = '0${cleanPhone.substring(3)}';
        }
        if (cleanPhone.length > 11) {
          cleanPhone = cleanPhone.substring(cleanPhone.length - 11);
        }

        _phoneController.text = cleanPhone;
        _autoDetectNetwork(cleanPhone);
        setState(() {});
        return;
      }
    } catch (e) {
      debugPrint('Native contact picker unavailable: $e');
      if (mounted) {
        dpSnack(context, 'Please type phone number or select from contacts');
      }
    }
  }

  void _showWebContactPicker() {
    final List<Map<String, String>> webTestContacts = [
      {'name': 'John Doe (MTN)', 'phone': '08031234567'},
      {'name': 'Jane Smith (Airtel)', 'phone': '08129876543'},
      {'name': 'Alex Johnson (Glo)', 'phone': '08051112223'},
      {'name': 'Sarah Williams (9mobile)', 'phone': '08099887766'},
    ];
    showDPSheet(
      context,
      title: 'Choose a contact',
      builder: (ctx) => Column(
        children: [
          for (final contact in webTestContacts)
            DPOptionRow(
              title: contact['name']!,
              subtitle: contact['phone']!,
              onTap: () {
                _phoneController.text = contact['phone']!;
                _autoDetectNetwork(contact['phone']!);
                setState(() {});
                Navigator.pop(ctx);
              },
            ),
        ],
      ),
    );
  }

  // ==================== CARRIER AUTO-DETECTION ====================
  void _autoDetectNetwork(String phone) {
    if (phone.length < 4) return;
    final prefix = phone.substring(0, 4);

    const mtnPrefixes = [
      '0803',
      '0806',
      '0703',
      '0706',
      '0813',
      '0816',
      '0810',
      '0814',
      '0903',
      '0906',
      '0913',
      '0916',
      '0704',
    ];
    const airtelPrefixes = [
      '0802',
      '0808',
      '0708',
      '0812',
      '0701',
      '0902',
      '0907',
      '0901',
      '0912',
      '0911',
    ];
    const gloPrefixes = [
      '0805',
      '0807',
      '0705',
      '0815',
      '0811',
      '0905',
      '0915',
    ];
    const etisalatPrefixes = ['0809', '0817', '0818', '0909', '0908'];

    String? detected;
    if (mtnPrefixes.contains(prefix)) {
      detected = 'MTN';
    } else if (airtelPrefixes.contains(prefix)) {
      detected = 'Airtel';
    } else if (gloPrefixes.contains(prefix)) {
      detected = 'Glo';
    } else if (etisalatPrefixes.contains(prefix)) {
      detected = '9mobile';
    }

    if (detected != null && detected != _selectedNetwork) {
      HapticFeedback.selectionClick();
      setState(() {
        _selectedNetwork = detected;
      });
    }
  }

  // ==================== BIOMETRIC & SECURITY SETUP ====================
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
    if (_selectedNetwork == null) {
      return 'Please select a network provider';
    }

    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      return 'Please enter a phone number';
    }
    if (phone.length != 11) {
      return 'Phone number must be exactly 11 digits';
    }
    if (!RegExp(r'^[0-9]+$').hasMatch(phone)) {
      return 'Phone number must contain only digits';
    }
    if (!phone.startsWith(RegExp(r'^0[789]'))) {
      return 'Phone number must start with 07, 08, or 09';
    }

    final amount = double.tryParse(_amountController.text) ?? 0;
    if (_amountController.text.isEmpty) {
      return 'Please enter or select an amount';
    }
    if (amount < 50) {
      return 'Minimum airtime purchase is ₦50';
    }
    if (amount > 50000) {
      return 'Maximum airtime purchase is ₦50,000';
    }

    return null;
  }

  String _mapExceptionToUserMessage(dynamic e) {
    final errorStr = e.toString().replaceAll('Exception: ', '');
    if (errorStr.contains('Insufficient wallet balance')) {
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

  // ==================== ACTIONS & PAYMENT FLOW ====================
  void _openPaymentSheet() {
    HapticFeedback.lightImpact();
    final validationError = _validateForm();
    if (validationError != null) {
      _showErrorDialog('Validation Error', validationError);
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

    // STEP 1: PRE-VERIFY PIN BEFORE TRANSACTION
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

    // STEP 2: PIN VERIFIED SUCCESSFULLY -> EXECUTE
    await _executeTransaction(pin: pin);
  }

  Future<void> _processPaymentWithBiometric() async {
    HapticFeedback.mediumImpact();
    final amount = double.tryParse(_amountController.text) ?? 0;
    final phone = _phoneController.text.trim();

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
            'Authenticate to buy Airtime of ₦${amount.toStringAsFixed(2)} for $phone',
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
    final network = _selectedNetwork!;
    final phone = _phoneController.text.trim();
    final amount = double.parse(_amountController.text);
    final apiNetwork =
        _networks.firstWhere((n) => n['name'] == network)['apiName'];

    try {
      final result = await ApiService.buyAirtime(
        userId: widget.userId,
        network: apiNetwork,
        phone: phone,
        amount: amount,
        transactionPin: pin,
        useBiometric: useBiometric,
      );

      final vtpassResponse = result['vtpassResponse'] ?? {};
      final vtpassCode =
          vtpassResponse['code']?.toString() ??
          vtpassResponse['vtpassResponse']?['code']?.toString();
      final alreadyProcessed = vtpassResponse['alreadyProcessed'] == true;
      final isSuccess = vtpassCode == '000' || alreadyProcessed;

      if (isSuccess) {
        final double newBalance =
            (vtpassResponse['newBalance'] ??
                    result['newBalance'] ??
                    _walletBalance)
                .toDouble();

        setState(() {
          _walletBalance = newBalance;
        });
        widget.onBalanceUpdate(newBalance);

        // Save to Recent Recharges (max 5 items)
        await _saveRecentRecharge(phone, network);

        _closePaymentSheet();
        _showSuccessDialog(network, phone, amount, result);
        _clearForm();
      } else {
        final errorMsg =
            vtpassResponse['response_description'] ??
            vtpassResponse['vtpassResponse']?['response_description'] ??
            result['message'] ??
            'Transaction failed. Please try again.';
        setState(() => _isProcessingPayment = false);

        // ✅ CHECK FOR LIMIT ERRORS
        final errorCode = result['code']?.toString() ?? '';

        if (errorCode == 'PER_TRANSACTION_LIMIT_EXCEEDED' ||
            errorCode == 'DAILY_LIMIT_EXCEEDED' ||
            errorMsg.contains('PER_TRANSACTION_LIMIT_EXCEEDED') ||
            errorMsg.contains('DAILY_LIMIT_EXCEEDED')) {
          // Extract limit info from error
          final limitValue = result['limit'] ?? 0;
          final requestedValue = result['requested'] ?? amount;

          // Convert to double safely
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
          final service = 'airtime';

          _showLimitIncreaseDialog(
            service: service,
            limitType: isDaily ? 'dailyCap' : 'perTransaction',
            currentLimit: limit,
            requestedAmount: requested,
          );
          return;
        }

        _showErrorDialog('Purchase Failed', errorMsg);
      }
    } catch (e) {
      setState(() => _isProcessingPayment = false);

      final errorStr = e.toString().replaceAll('Exception: ', '');

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
          service: 'airtime',
          limitType: isDaily ? 'dailyCap' : 'perTransaction',
          currentLimit: limit,
          requestedAmount: amount,
        );
        return;
      }

      _showErrorDialog('Purchase Failed', _mapExceptionToUserMessage(e));
    } finally {
      if (mounted) {
        setState(() {
          _isProcessingPayment = false;
          _isAuthenticating = false;
        });
      }
    }
  }

  void _clearForm() {
    _phoneController.clear();
    _amountController.clear();
    _pinController.clear();
    if (mounted) {
      setState(() {
        _selectedNetwork = null;
        _useBiometric = false;
        _pinValidationError = null;
      });
    }
  }

  void _selectQuickAmount(int amount) {
    HapticFeedback.lightImpact();
    _amountController.text = amount.toString();
    _amountFocusNode.unfocus();
    setState(() {});
  }

  void _selectRecentRecharge(Map<String, String> contact) {
    HapticFeedback.lightImpact();
    _phoneController.text = contact['phone']!;
    _autoDetectNetwork(contact['phone']!);
    setState(() {
      _selectedNetwork = contact['network'];
    });
  }

  // ==================== BUILD METHOD ====================
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        DPPage(
          title: 'Buy airtime',
          actionLabel: 'History',
          onAction: () => Navigator.pushNamed(context, '/transactions'),
          bottom: _isLoadingUserData || !_isUserActive || !_airtimeServiceEnabled
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

    if (!_isUserActive || !_airtimeServiceEnabled) {
      return _buildServiceUnavailable();
    }

    final amount = double.tryParse(_amountController.text) ?? 0;
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const DPHeadline('Keep the conversation going.',
                subtitle: 'Top up any Nigerian number in moments.'),
            _buildSectionTitle('Choose network'),
            _buildNetworkSelector(),
            _buildPhoneNumberInput(),
            _buildRecentRechargesSection(),
            _buildSectionTitle('Quick amounts'),
            _buildQuickAmountGrid(),
            _buildCustomAmountInput(),
            DPSummaryCard(rows: [
              DPSummaryRow(
                'Wallet balance',
                _isBalanceVisible ? dpNaira(_walletBalance) : '₦ ••••',
              ),
              if (amount > 0)
                DPSummaryRow(
                  'Balance after top-up',
                  dpNaira(_walletBalance - amount),
                  valueColor: _walletBalance - amount < 0 ? DP.danger : null,
                ),
            ]),
            const DPNotice(
              'Commission on eligible top-ups goes to your earnings, not your wallet balance. Review the final amount before paying.',
              margin: EdgeInsets.zero,
            ),
          ],
        ),
      ),
    );
  }

  // ==================== CLEAN BANNER (WITHOUT TEXT OVERLAY) ====================

  // ==================== RECENT RECHARGES ====================
  Widget _buildRecentRechargesSection() {
    if (_recentRecharges.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: SizedBox(
        height: 40,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _recentRecharges.length > 5 ? 5 : _recentRecharges.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final contact = _recentRecharges[index];
            return DPChip(
              label: '${contact['network'] ?? ''} · ${contact['phone'] ?? ''}',
              selected: _phoneController.text == contact['phone'],
              height: 40,
              dense: true,
              leading: const DPIcon(DPIcons.clockArrowLeft, size: 14, color: DP.muted),
              onTap: () => _selectRecentRecharge(contact),
            );
          },
        ),
      ),
    );
  }


  // ==================== PHONE NUMBER INPUT ====================
  Widget _buildPhoneNumberInput() {
    final phone = _phoneController.text.trim();
    return DPField(
      label: 'Phone number',
      controller: _phoneController,
      focusNode: _phoneFocusNode,
      keyboardType: TextInputType.phone,
      hint: '0803 456 7890',
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(11),
      ],
      onChanged: (val) {
        _autoDetectNetwork(val);
        setState(() {});
      },
      helper: _selectedNetwork != null && phone.length >= 4
          ? '$_selectedNetwork Nigeria'
          : '11 digits, starting with 07, 08 or 09',
      suffixIcon: DPIcons.contactRound,
      onSuffixTap: _pickContactFromDevice,
    );
  }

  // ==================== NETWORK SELECTOR ====================
  Widget _buildNetworkSelector() {
    final names = _networks.map((n) => n['name'] as String).toList();
    return DPChipGrid(
      labels: names,
      columns: 4,
      selectedIndex: _selectedNetwork == null ? null : names.indexOf(_selectedNetwork!),
      onSelected: (i) {
        HapticFeedback.selectionClick();
        setState(() => _selectedNetwork = names[i]);
      },
    );
  }

  // ==================== QUICK AMOUNT GRID ====================
  Widget _buildQuickAmountGrid() {
    final idx = _quickAmounts.indexWhere((a) => _amountController.text == a.toString());
    return DPChipGrid(
      labels: _quickAmounts.map((a) => dpNaira(a, decimals: false)).toList(),
      columns: 3,
      selectedIndex: idx < 0 ? null : idx,
      onSelected: (i) => _selectQuickAmount(_quickAmounts[i]),
    );
  }

  Widget _buildCustomAmountInput() {
    return DPField(
      label: 'Amount',
      controller: _amountController,
      focusNode: _amountFocusNode,
      keyboardType: TextInputType.number,
      prefixText: '₦ ',
      hint: '0',
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      onChanged: (_) => setState(() {}),
      helper: 'Minimum ₦50 · Maximum ₦50,000',
    );
  }

  // ==================== STICKY BOTTOM CTA ====================
  Widget _buildStickyBottomCTA() {
    return DPButton(
      label: 'Continue to review',
      icon: DPIcons.arrowRight,
      loading: _isProcessingPayment || _isAuthenticating,
      onPressed: _isProcessingPayment || _isAuthenticating ? null : _openPaymentSheet,
    );
  }

  // ==================== PAYMENT SHEET OVERLAY ====================
  Widget _buildPaymentSheetOverlay() {
    final phone = _phoneController.text.trim();
    final amount = double.tryParse(_amountController.text) ?? 0;
    final bool isBiometricSupported = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
    final canBiometric = isBiometricSupported && _biometricEnabled && _biometricAllowed;
    return DPSheetOverlay(
      animation: _sheetAnimation,
      onDismiss: _isProcessingPayment ? null : _closePaymentSheet,
      child: DPPaymentReview(
        icon: DPIcons.phone,
        serviceLabel: '${_selectedNetwork ?? ''} airtime',
        amount: amount,
        rows: [
          DPSummaryRow('Phone number', phone.isNotEmpty ? phone : '—'),
          DPSummaryRow('Network', '${_selectedNetwork ?? '—'} Nigeria'),
          DPSummaryRow('Amount', dpNaira(amount)),
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
        footnote: 'Confirm the number. Delivered airtime can’t be reversed.',
      ),
    );
  }



  // ==================== PIN INPUT WITH SHAKE & ERROR UI ====================

  // ==================== BIOMETRIC OPTION ====================

  // ==================== SECTION TITLE ====================
  Widget _buildSectionTitle(String title) => DPFieldLabel(title);

  Widget _buildServiceUnavailable() {
    return const DPServiceUnavailable(
      message: 'Airtime top-up is currently unavailable. Please try again later.',
    );
  }

  void _showSuccessDialog(
    String network,
    String phone,
    double amount,
    Map<String, dynamic> result,
  ) {
    final transactionId =
        result['transactionId'] ?? 'TXN_${DateTime.now().millisecondsSinceEpoch}';
    final reference = result['vtpassResponse']?['requestId'] ?? transactionId;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: ReceiptWidget(
          transactionType: 'Airtime',
          amount: amount.toStringAsFixed(2),
          status: 'delivered',
          transactionId: transactionId,
          reference: reference.toString(),
          date: DateTime.now(),
          phoneNumber: phone,
          description: '$network Airtime',
          customMessage: 'Verified by VTpass',
          primaryColor: DP.navy,
          showWatermark: true,
          isAdminTransaction: false,
          isUserAdmin: false,
        ),
      ),
    );
    _clearForm();
  }

  void _showErrorDialog(String title, String message) {
    showDPDialog(context, tone: DPDialogTone.error, title: title, message: message);
  }
}
