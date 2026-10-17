import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/services/api_service.dart';
import '../../../core/services/biometric_service.dart';
import '../../../core/widgets/receipt_widget.dart';
import '../../../core/widgets/request_limit_increase_dialog.dart';

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

  // ==================== BRAND COLORS ====================
  static const Color _primaryNavy = Color(0xFF102C68);
  static const Color _secondaryTeal = Color(0xFF168566);
  static const Color _textDark = Color(0xFF14263D);
  static const Color _textMuted = Color(0xFF728078);
  static const Color _bgCanvas = Color(0xFFF8F9F5);

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
      'color': const Color(0xFFA76B1D),
    },
  ];

  final List<int> _quickAmounts = [100, 200, 500, 1000, 2000, 5000];

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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Please type phone number or select from contacts',
              style: GoogleFonts.inter(fontSize: 13),
            ),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
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

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.contacts_rounded, color: _primaryNavy),
                      const SizedBox(width: 8),
                      Text(
                        'Select Contact (Web Test Mode)',
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: _primaryNavy,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: _textMuted),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Note: On native Android builds, your device\'s native phonebook will open automatically.',
                style: GoogleFonts.inter(fontSize: 12, color: _textMuted),
              ),
              const SizedBox(height: 16),
              ...webTestContacts.map((contact) {
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  leading: CircleAvatar(
                    backgroundColor: _primaryNavy.withValues(alpha: 0.08),
                    child: Text(
                      contact['name']![0],
                      style: GoogleFonts.inter(
                        color: _primaryNavy,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  title: Text(
                    contact['name']!,
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: _textDark,
                    ),
                  ),
                  subtitle: Text(
                    contact['phone']!,
                    style: GoogleFonts.inter(fontSize: 12, color: _textMuted),
                  ),
                  onTap: () {
                    _phoneController.text = contact['phone']!;
                    _autoDetectNetwork(contact['phone']!);
                    setState(() {});
                    Navigator.pop(context);
                  },
                );
              }),
            ],
          ),
        );
      },
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
    return Scaffold(
      backgroundColor: _bgCanvas,
      appBar: _buildAppBar(),
      body: Stack(
        children: [
          _buildBody(),
          if (_showPaymentSheet) _buildPaymentSheetOverlay(),
        ],
      ),
      // HIDE BOTTOM CTA BUTTON WHEN PAYMENT SHEET SLIDES UP
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
        'Airtime Top-Up',
        style: GoogleFonts.inter(
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
        color: _primaryNavy.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _primaryNavy.withValues(alpha: 0.1)),
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
              style: GoogleFonts.inter(
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

    if (!_isUserActive || !_airtimeServiceEnabled) {
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

              // Dynamic Recent Recharges (Shows max 5 or empty state)
              _buildRecentRechargesSection(),
              const SizedBox(height: 24),

              // Phone Input Field with Native Contact Picker
              _buildPhoneNumberInput(),
              const SizedBox(height: 24),

              // Network Selection Bar
              _buildSectionTitle('Network Operator'),
              const SizedBox(height: 12),
              _buildNetworkSelector(),
              const SizedBox(height: 24),

              // Amount Selection Grid
              _buildSectionTitle('Select Amount'),
              const SizedBox(height: 12),
              _buildQuickAmountGrid(),
              const SizedBox(height: 16),
              _buildCustomAmountInput(),
            ],
          ),
        ),
      ),
    );
  }

  // ==================== CLEAN BANNER (WITHOUT TEXT OVERLAY) ====================
  Widget _buildCleanBanner() {
    return Container(
      width: double.infinity,
      height: 120,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        image: const DecorationImage(
          image: AssetImage('assets/airtime_banner.png'),
          fit: BoxFit.cover,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
    );
  }

  // ==================== RECENT RECHARGES ====================
  Widget _buildRecentRechargesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Recent Recharges'),
        const SizedBox(height: 10),
        if (_recentRecharges.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.history_rounded,
                  size: 18,
                  color: Colors.grey.shade400,
                ),
                const SizedBox(width: 8),
                Text(
                  'No recent recharges yet',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: _textMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          )
        else
          SizedBox(
            height: 82,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount:
                  _recentRecharges.length > 5 ? 5 : _recentRecharges.length,
              itemBuilder: (context, index) {
                final contact = _recentRecharges[index];
                return _buildRecentContactAvatar(contact);
              },
            ),
          ),
      ],
    );
  }

  Widget _buildRecentContactAvatar(Map<String, String> contact) {
    return GestureDetector(
      onTap: () => _selectRecentRecharge(contact),
      child: Container(
        margin: const EdgeInsets.only(right: 14),
        child: Column(
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 25,
                  backgroundColor: _primaryNavy.withValues(alpha: 0.08),
                  child: Text(
                    (contact['name'] ?? 'U')[0].toUpperCase(),
                    style: GoogleFonts.inter(
                      color: _primaryNavy,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: CircleAvatar(
                      radius: 8,
                      backgroundColor: Colors.grey.shade200,
                      child: Text(
                        (contact['network'] ?? 'M')[0].toUpperCase(),
                        style: const TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                          color: _primaryNavy,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              contact['name'] ?? '',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: _textDark,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== PHONE NUMBER INPUT ====================
  Widget _buildPhoneNumberInput() {
    final selectedNetworkData = _networks.firstWhere(
      (n) => n['name'] == _selectedNetwork,
      orElse: () => {},
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Phone Number'),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color:
                  _phoneFocusNode.hasFocus
                      ? _primaryNavy
                      : Colors.grey.shade200,
              width: _phoneFocusNode.hasFocus ? 1.5 : 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: TextField(
            controller: _phoneController,
            focusNode: _phoneFocusNode,
            keyboardType: TextInputType.phone,
            onChanged: (val) {
              _autoDetectNetwork(val);
              setState(() {});
            },
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(11),
            ],
            decoration: InputDecoration(
              hintText: 'Enter 11-digit phone number',
              hintStyle: GoogleFonts.inter(
                color: Colors.grey.shade400,
                fontSize: 14,
              ),
              prefixIcon: Padding(
                padding: const EdgeInsets.all(12),
                child:
                    selectedNetworkData.isNotEmpty &&
                            selectedNetworkData['image'] != null
                        ? AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          child: ClipRRect(
                            key: ValueKey(selectedNetworkData['name']),
                            borderRadius: BorderRadius.circular(6),
                            child: Image.asset(
                              selectedNetworkData['image'],
                              width: 26,
                              height: 26,
                              fit: BoxFit.cover,
                            ),
                          ),
                        )
                        : const Icon(
                          Icons.phone_android_rounded,
                          color: _primaryNavy,
                          size: 22,
                        ),
              ),
              suffixIcon: IconButton(
                icon: const Icon(
                  Icons.contacts_rounded,
                  color: _primaryNavy,
                  size: 22,
                ),
                onPressed: _pickContactFromDevice,
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 16,
              ),
            ),
            style: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: _textDark,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ],
    );
  }

  // ==================== NETWORK SELECTOR ====================
  Widget _buildNetworkSelector() {
    return SizedBox(
      height: 72,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: _networks.length,
        itemBuilder: (context, index) {
          final network = _networks[index];
          final isSelected = _selectedNetwork == network['name'];
          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _selectedNetwork = network['name']);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              width: 82,
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isSelected ? network['color'] : Colors.grey.shade200,
                  width: isSelected ? 2.5 : 1.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color:
                        isSelected
                            ? (network['color'] as Color).withValues(
                              alpha: 0.25,
                            )
                            : Colors.black.withValues(alpha: 0.03),
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
                    child: Image.asset(
                      network['image'],
                      width: 32,
                      height: 32,
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    network['name'],
                    style: GoogleFonts.inter(
                      fontSize: 11,
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
        final isSelected = _amountController.text == amount.toString();

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
                          ? _primaryNavy.withValues(alpha: 0.2)
                          : Colors.black.withValues(alpha: 0.02),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Center(
              child: Text(
                '₦$amount',
                style: GoogleFonts.inter(
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
      ),
      child: TextField(
        controller: _amountController,
        focusNode: _amountFocusNode,
        keyboardType: TextInputType.number,
        onChanged: (_) => setState(() {}),
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          hintText: 'Or enter custom amount (e.g. ₦150)',
          hintStyle: GoogleFonts.inter(
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
        style: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: _textDark,
        ),
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
            color: Colors.black.withValues(alpha: 0.05),
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
              color: _secondaryTeal,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: _secondaryTeal.withValues(alpha: 0.3),
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
                            style: GoogleFonts.inter(
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
              color: Colors.black.withValues(
                alpha: 0.4 * _sheetAnimation.value,
              ),
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
                                style: GoogleFonts.inter(
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

  Widget _buildPaymentSheetDetails() {
    final network = _networks.firstWhere(
      (n) => n['name'] == _selectedNetwork,
      orElse: () => _networks.first,
    );
    final phone = _phoneController.text.trim();
    final amount = double.tryParse(_amountController.text) ?? 0;

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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Network',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _textMuted,
                ),
              ),
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Image.asset(
                      network['image'],
                      width: 20,
                      height: 20,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _selectedNetwork ?? 'N/A',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: _textDark,
                    ),
                  ),
                ],
              ),
            ],
          ),
          Divider(height: 16, color: Colors.grey.shade200),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Phone Number',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _textMuted,
                ),
              ),
              Text(
                phone.isNotEmpty ? phone : 'N/A',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: _textDark,
                ),
              ),
            ],
          ),
          Divider(height: 16, color: Colors.grey.shade200),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Amount',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _textMuted,
                ),
              ),
              Text(
                '₦${amount.toStringAsFixed(2)}',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: _secondaryTeal,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentSheetBalance() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _secondaryTeal.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _secondaryTeal.withValues(alpha: 0.15)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Available Balance',
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _textMuted,
            ),
          ),
          Text(
            '₦${_walletBalance.toStringAsFixed(2)}',
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: _secondaryTeal,
            ),
          ),
        ],
      ),
    );
  }

  // ==================== PIN INPUT WITH SHAKE & ERROR UI ====================
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
                    ? const Color(0xFFFDECEA)
                    : _primaryNavy.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: hasError ? const Color(0xFFC0392B) : _primaryNavy,
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
                    hintText: 'Enter transaction PIN',
                    hintStyle: GoogleFonts.inter(
                      color:
                          hasError
                              ? const Color(0xFFC0392B).withValues(alpha: 0.7)
                              : Colors.grey.shade600,
                      fontSize: 13,
                    ),
                    prefixIcon: Icon(
                      Icons.lock_outline_rounded,
                      color: hasError ? const Color(0xFFC0392B) : _primaryNavy,
                      size: 20,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: hasError ? const Color(0xFFC0392B) : Colors.black,
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
                  color: const Color(0xFFFDECEA),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        color: Color(0xFFC0392B),
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _pinValidationError!,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFFC0392B),
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
                        hasError ? const Color(0xFFC0392B) : _secondaryTeal,
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
                                style: GoogleFonts.inter(
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
            color: _primaryNavy.withValues(alpha: 0.08),
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
                          style: GoogleFonts.inter(
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

  // ==================== SECTION TITLE ====================
  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: _primaryNavy,
      ),
    );
  }

  Widget _buildServiceUnavailable() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.phone_disabled_rounded,
              color: Colors.orange,
              size: 60,
            ),
            const SizedBox(height: 16),
            Text(
              'Service Unavailable',
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: _textDark,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Airtime service is currently unavailable. Please try again later.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 14, color: _textMuted),
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
                style: GoogleFonts.inter(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSuccessDialog(
    String network,
    String phone,
    double amount,
    Map<String, dynamic> result,
  ) {
    final transactionId =
        result['transactionId'] ??
        'TXN_${DateTime.now().millisecondsSinceEpoch}';
    final reference = result['vtpassResponse']?['requestId'] ?? transactionId;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => Dialog(
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
              description: '${network.toUpperCase()} Airtime Purchase',
              customMessage: '✓ Verified by VTpass Payment Gateway',
              primaryColor: _primaryNavy,
              showWatermark: true,
              isAdminTransaction: false,
              isUserAdmin: false,
            ),
          ),
    );
    _clearForm();
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
                  style: GoogleFonts.inter(
                    color: Colors.red.shade700,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            content: Text(
              message,
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'OK',
                  style: GoogleFonts.inter(
                    color: _secondaryTeal,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
    );
  }
}
