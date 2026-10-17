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
import '../../../ui/ui.dart';
import '../../../core/widgets/commission_estimate.dart';
import '../../../core/services/commission_rates_service.dart';

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
                  _buildAppBarRow(),
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

  // ==================== HEADER / APP BAR ====================
  Widget _buildAppBarRow() {
    return DPTopBar(
      title: 'Buy airtime',
      actionLabel: 'History',
      onAction: () => Navigator.pushNamed(
        context,
        '/transactions',
        arguments: {'userId': widget.userId},
      ),
    );
  }


  // ==================== BODY CONTENT ====================
  Widget _buildBody() {
    if (_isLoadingUserData) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!_isUserActive || !_airtimeServiceEnabled) {
      return _buildServiceUnavailable();
    }

    final amount = double.tryParse(_amountController.text) ?? 0;
    final quick = _quickAmounts.map((a) => DP.naira(a, decimals: false)).toList();
    final selectedQuick = _quickAmounts.contains(amount.toInt()) &&
            amount == amount.roundToDouble()
        ? DP.naira(amount.toInt(), decimals: false)
        : null;

    return FadeTransition(
      opacity: _fadeAnimation,
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const DPHeadline(
              'Keep the conversation going.',
              subtitle: 'Top up any Nigerian number in moments.',
            ),
            _buildSectionTitle('Choose network'),
            _buildNetworkSelector(),
            const SizedBox(height: 22),
            _buildPhoneNumberInput(),
            if (_recentRecharges.isNotEmpty) ...[
              const SizedBox(height: 14),
              _buildRecentRechargesSection(),
            ],
            const SizedBox(height: 22),
            _buildSectionTitle('Quick amounts'),
            DPChipGrid(
              options: quick,
              selected: selectedQuick,
              height: 46,
              onSelect: (label) {
                final i = quick.indexOf(label);
                if (i >= 0) _selectQuickAmount(_quickAmounts[i]);
              },
            ),
            const SizedBox(height: 20),
            const DPLabel('Amount'),
            _buildCustomAmountInput(),
            const DPHelper('Minimum ₦50 · Maximum ₦50,000'),
            const SizedBox(height: 20),
            WalletCommissionCard(
              walletBalance: _walletBalance,
              amount: amount,
              service: 'airtime',
              balanceVisible: _isBalanceVisible,
            ),
            const SizedBox(height: 14),
            const DPBanner(
              'Commission goes to your earnings, not your wallet balance. Review the final amount before paying.',
            ),
          ],
        ),
      ),
    );
  }

  // ==================== CLEAN BANNER (WITHOUT TEXT OVERLAY) ====================

  // ==================== RECENT RECHARGES ====================
  Widget _buildRecentRechargesSection() {
    final items = _recentRecharges.take(5).toList();
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) => _buildRecentContactAvatar(items[i]),
      ),
    );
  }

  Widget _buildRecentContactAvatar(Map<String, String> contact) {
    final phone = contact['phone'] ?? '';
    final net = contact['network'] ?? '';
    return Tooltip(
      message: net,
      child: DPChip(
        label: phone,
        selected: _phoneController.text == phone,
        height: 40,
        leading: const Icon(DPIcons.history, size: 16, color: DP.muted),
        onTap: () => _selectRecentRecharge(contact),
      ),
    );
  }

  // ==================== PHONE NUMBER INPUT ====================
  Widget _buildPhoneNumberInput() {
    final phone = _phoneController.text.trim();
    String? helper;
    if (_selectedNetwork != null && phone.length >= 4) {
      helper = '$_selectedNetwork Nigeria';
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const DPLabel('Phone number'),
        DPField(
          controller: _phoneController,
          focusNode: _phoneFocusNode,
          hint: '0803 456 7890',
          keyboardType: TextInputType.phone,
          onChanged: (val) {
            _autoDetectNetwork(val);
            setState(() {});
          },
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(11),
          ],
          style: const TextStyle(
            fontSize: 17,
            color: DP.ink,
            letterSpacing: 0.4,
          ),
          suffix: IconButton(
            tooltip: 'Choose from contacts',
            icon: const Icon(DPIcons.contact, color: DP.muted),
            onPressed: _pickContactFromDevice,
          ),
        ),
        if (helper != null) DPHelper(helper),
      ],
    );
  }

  // ==================== NETWORK SELECTOR ====================
  Widget _buildNetworkSelector() {
    return DPChipRow(
      options: _networks.map((n) => n['name'] as String).toList(),
      selected: _selectedNetwork,
      height: 46,
      onSelect: (name) {
        HapticFeedback.selectionClick();
        setState(() => _selectedNetwork = name);
      },
    );
  }

  // ==================== QUICK AMOUNT GRID ====================

  Widget _buildCustomAmountInput() {
    return DPField(
      controller: _amountController,
      focusNode: _amountFocusNode,
      hint: '0.00',
      prefixText: '₦',
      keyboardType: TextInputType.number,
      onChanged: (_) => setState(() {}),
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      style: const TextStyle(fontSize: 17, color: DP.ink),
    );
  }

  // ==================== STICKY BOTTOM CTA ====================
  Widget _buildStickyBottomCTA() {
    return DPBottomAction(
      child: DPButton(
        label: 'Continue to review',
        icon: DPIcons.forward,
        loading: _isProcessingPayment || _isAuthenticating,
        onPressed: _openPaymentSheet,
      ),
    );
  }

  // ==================== PAYMENT SHEET OVERLAY ====================
  Widget _buildPaymentSheetOverlay() {
    final phone = _phoneController.text.trim();
    final amount = double.tryParse(_amountController.text) ?? 0;
    final network = _selectedNetwork ?? '';
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
            icon: DPIcons.phone,
            title: '$network airtime',
            amount: amount,
            rows: [
              DPReviewRow('Phone number', phone),
              DPReviewRow('Network', '$network Nigeria'),
              DPReviewRow('Amount', DP.naira(amount)),
              const DPReviewRow('Service fee', '₦0.00'),
              DPReviewRow('Total to pay', DP.naira(amount), strong: true),
            ],
            walletBalance: _walletBalance,
            totalDebit: amount,
            commission: CommissionRatesService.estimate('airtime', amount),
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
            footnote: 'Confirm the number. Delivered airtime can\'t be reversed.',
          ),
        ),
      ),
    );
  }



  // ==================== PIN INPUT WITH SHAKE & ERROR UI ====================

  // ==================== BIOMETRIC OPTION ====================

  // ==================== SECTION TITLE ====================
  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(title, style: DP.section),
    );
  }

  Widget _buildServiceUnavailable() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: DPEmptyState(
          icon: DPIcons.phone,
          title: 'Airtime is unavailable right now',
          message: 'Please try again in a little while.',
          actionLabel: 'Go back',
          onAction: () => Navigator.pop(context),
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
    dpDialog(
      context,
      title: title,
      message: message,
      confirmLabel: 'OK',
      tone: DPTone.error,
    );
  }
}
