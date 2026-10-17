// lib/presentation/screens/internet/internet_screen.dart
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
import '../../../ui/ui.dart';
import '../../../core/widgets/request_limit_increase_dialog.dart'; // ✅ ADD THIS

class InternetScreen extends StatefulWidget {
  final void Function(double newBalance) onBalanceUpdate;
  final String userId;

  const InternetScreen({
    super.key,
    required this.onBalanceUpdate,
    required this.userId,
  });

  @override
  State<InternetScreen> createState() => _InternetScreenState();
}

class _InternetScreenState extends State<InternetScreen>
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
  String? _selectedPlan;
  Map<String, dynamic>? _selectedPlanDetails;
  bool _isLoadingPlans = false;
  bool _isAuthenticating = false;
  bool _isBalanceVisible = true;
  double _walletBalance = 0.0;
  List<Map<String, dynamic>> _dataPlans = [];

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
  final bool _internetServiceEnabled = true;
  bool _isUserActive = true;
  bool _isLoadingUserData = true;

  // Payment Sheet State
  bool _showPaymentSheet = false;
  bool _isProcessingPayment = false;

  // Dynamic Recent Data Purchases
  List<Map<String, String>> _recentRecharges = [];

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

  // Network Providers
  final List<Map<String, dynamic>> _networks = [
    {
      'name': 'MTN',
      'apiName': 'mtn',
      'image': 'assets/mtn.jpg',
      'color': const Color(0xFFFFCB05),
      'serviceId': 'mtn-data',
    },
    {
      'name': 'Airtel',
      'apiName': 'airtel',
      'image': 'assets/airtel.jpg',
      'color': const Color(0xFFEF1C25),
      'serviceId': 'airtel-data',
    },
    {
      'name': 'Glo',
      'apiName': 'glo',
      'image': 'assets/glo.png',
      'color': const Color(0xFF00843D),
      'serviceId': 'glo-data',
    },
    {
      'name': '9mobile',
      'apiName': 'etisalat',
      'image': 'assets/t2.png',
      'color': const Color(0xFFF57C00),
      'serviceId': 'etisalat-data',
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
      final String? jsonString = prefs.getString('recent_data_recharges');
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
      debugPrint('Error loading recent data recharges: $e');
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
        'recent_data_recharges',
        jsonEncode(_recentRecharges),
      );

      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Error saving recent data recharge: $e');
    }
  }

  // ==================== CONTACT PICKER ====================
  Future<void> _pickContactFromDevice() async {
    HapticFeedback.lightImpact();

    if (kIsWeb) {
      _showWebContactPicker();
      return;
    }

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
                        style: TextStyle(
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
                style: TextStyle(fontSize: 12, color: _textMuted),
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
                      style: TextStyle(
                        color: _primaryNavy,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  title: Text(
                    contact['name']!,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: _textDark,
                    ),
                  ),
                  subtitle: Text(
                    contact['phone']!,
                    style: TextStyle(fontSize: 12, color: _textMuted),
                  ),
                  onTap: () {
                    _phoneController.text = contact['phone']!;
                    _autoDetectNetwork(contact['phone']!);
                    setState(() {});
                    if (Navigator.canPop(context)) {
                      Navigator.pop(context);
                    } else {
                      Navigator.pushReplacementNamed(context, '/home');
                    }
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
        _dataPlans = [];
        _selectedPlan = null;
        _selectedPlanDetails = null;
        _amountController.text = '';
      });
      _fetchDataPlans(detected);
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

  Future<void> _fetchDataPlans(String network) async {
    setState(() => _isLoadingPlans = true);

    try {
      final networkData = _networks.firstWhere(
        (n) => n['name'] == network,
        orElse: () => _networks[0],
      );
      final serviceId = networkData['serviceId'];

      final result = await ApiService.getDataPlans(serviceId);

      if (result['success'] == true) {
        final plans = result['plans'] ?? [];
        plans.sort((a, b) {
          final amountA = double.tryParse(a['amount']?.toString() ?? '0') ?? 0;
          final amountB = double.tryParse(b['amount']?.toString() ?? '0') ?? 0;
          return amountA.compareTo(amountB);
        });
        if (mounted) {
          setState(() {
            _dataPlans = List<Map<String, dynamic>>.from(plans);
            _selectedPlan = null;
            _selectedPlanDetails = null;
            _amountController.text = '';
          });
        }
      } else {
        if (mounted) _dataPlans = _getMockDataPlans(network);
      }
    } catch (e) {
      debugPrint('Error fetching data plans: $e');
      if (mounted) _dataPlans = _getMockDataPlans(network);
    } finally {
      if (mounted) setState(() => _isLoadingPlans = false);
    }
  }

  // Plans could not be loaded. Made-up plans are no longer shown because
  // their variation codes don't exist at VTpass; the UI offers a retry.
  List<Map<String, dynamic>> _getMockDataPlans(String network) => [];

  String _planFilter = 'All plans';

  String _planBucket(Map<String, dynamic> plan) {
    final v = '${plan['validity'] ?? ''} ${plan['name'] ?? ''}'.toLowerCase();
    final m = RegExp(r'(\d+)\s*(day|days|hr|hrs|hour|hours)').firstMatch(v);
    if (v.contains('daily') ||
        v.contains('24') ||
        (m != null && (m.group(2)!.startsWith('h') || int.parse(m.group(1)!) <= 3))) {
      return 'Daily';
    }
    if (v.contains('week') || (m != null && int.parse(m.group(1)!) <= 14)) return 'Weekly';
    return 'Monthly';
  }

  String _planSize(String name) {
    final m = RegExp(r'(\d+(?:\.\d+)?)\s*(GB|MB|TB)', caseSensitive: false).firstMatch(name);
    if (m == null) return name;
    return '${m.group(1)} ${m.group(2)!.toUpperCase()}';
  }

  // ==================== FORM VALIDATION ====================
  String? _validateForm() {
    if (_selectedNetwork == null) {
      return 'Please select a network provider';
    }

    if (_selectedPlan == null) {
      return 'Please select a data plan';
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
    final planName = _selectedPlanDetails?['name'] ?? 'Data Plan';

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
            'Authenticate to buy $planName of ₦${amount.toStringAsFixed(2)} for $phone',
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
    final planName = _selectedPlanDetails?['name'] ?? 'Data Plan';
    final variationCode = _selectedPlanDetails?['variation_code'] ?? '';

    try {
      final result = await ApiService.buyData(
        userId: widget.userId,
        network: network.toLowerCase(),
        phone: phone,
        variationCode: variationCode,
        planName: planName,
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

        // Save to Recent Data Recharges (max 5 items)
        await _saveRecentRecharge(phone, network);

        _closePaymentSheet();
        _showSuccessDialog(network, phone, amount, planName, result);
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
          final service = 'data';

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
          service: 'data',
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
        _selectedPlan = null;
        _selectedPlanDetails = null;
        _dataPlans = [];
        _useBiometric = false;
        _pinValidationError = null;
      });
    }
  }

  void _selectPlan(String planName, Map<String, dynamic> planDetails) {
    HapticFeedback.lightImpact();
    setState(() {
      _selectedPlan = planName;
      _selectedPlanDetails = planDetails;
      _amountController.text = planDetails['amount']?.toString() ?? '';
    });
    _amountFocusNode.unfocus();
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
    final available = !_isLoadingUserData && _isUserActive && _internetServiceEnabled;
    return Stack(
      children: [
        DPPage(
          title: 'Buy data',
          actionLabel: 'History',
          onAction: () => Navigator.pushNamed(context, '/transactions'),
          bottom: available ? _buildStickyBottomCTA() : null,
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
    if (!_isUserActive || !_internetServiceEnabled) {
      return _buildServiceUnavailable();
    }
    final sel = _selectedPlanDetails;
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 18),
              child: Text('More streaming, scrolling and staying close.', style: DPText.bodyMuted),
            ),
            _buildNetworkSelector(),
            _buildPhoneNumberInput(),
            _buildRecentRechargesSection(),
            if (_selectedNetwork != null) _buildPlanSection() else _buildSelectNetworkPrompt(),
            if (sel != null)
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 12),
                child: Row(
                  children: [
                    Text('Selected plan', style: DPText.bodyMuted),
                    const Spacer(),
                    Text(
                      '${_planSize(sel['name'].toString())} · ${dpNaira(double.tryParse(sel['amount'].toString()) ?? 0)}',
                      style: DPText.value,
                    ),
                  ],
                ),
              ),
            Text(
              'Plans activate on the number entered. Double-check before continuing.',
              style: DPText.bodyMuted.copyWith(fontSize: 13.5),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== CLEAN BANNER ====================

  // ==================== RECENT RECHARGES ====================
  Widget _buildRecentRechargesSection() {
    if (_recentRecharges.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 0, bottom: 14),
      child: SizedBox(
        height: 36,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _recentRecharges.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) => _buildRecentContactAvatar(_recentRecharges[i]),
        ),
      ),
    );
  }

  Widget _buildRecentContactAvatar(Map<String, String> contact) {
    final phone = contact['phone'] ?? '';
    final net = contact['network'] ?? '';
    return DPChip(
      label: '$net · $phone',
      selected: _phoneController.text == phone,
      dense: true,
      height: 36,
      leading: const DPIcon(DPIcons.history, size: 14, color: DP.ink2),
      onTap: () => _selectRecentRecharge(contact),
    );
  }

  // ==================== PHONE NUMBER INPUT ====================
  Widget _buildPhoneNumberInput() {
    return DPField(
      label: 'Phone number',
      controller: _phoneController,
      focusNode: _phoneFocusNode,
      keyboardType: TextInputType.phone,
      hint: '0802 321 4567',
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(11),
      ],
      onChanged: (val) {
        _autoDetectNetwork(val);
        setState(() {});
      },
      suffixIcon: DPIcons.contactRound,
      onSuffixTap: _pickContactFromDevice,
      margin: const EdgeInsets.only(bottom: 12),
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
        setState(() {
          _selectedNetwork = names[i];
          _dataPlans = [];
          _selectedPlan = null;
          _selectedPlanDetails = null;
          _amountController.text = '';
        });
        _fetchDataPlans(names[i]);
      },
    );
  }

  // ==================== PROMPT TO SELECT NETWORK ====================
  Widget _buildSelectNetworkPrompt() {
    return const DPCard(
      child: DPEmptyState(
        icon: DPIcons.wifi,
        title: 'Choose a network',
        message: 'Pick a network above, or type the number and we’ll detect it.',
      ),
    );
  }

  // ==================== DATA PLANS SECTION ====================
  Widget _buildPlanSection() {
    const filters = ['All plans', 'Daily', 'Weekly', 'Monthly'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const DPSectionHeader('Find your perfect plan', padding: EdgeInsets.only(top: 6, bottom: 12)),
        DPChipGrid(
          labels: filters,
          columns: 4,
          height: 40,
          selectedIndex: filters.indexOf(_planFilter),
          onSelected: (i) => setState(() => _planFilter = filters[i]),
        ),
        if (_isLoadingPlans)
          const DPLoader(message: 'Loading plans…')
        else if (_dataPlans.isEmpty)
          DPCard(
            child: DPEmptyState(
              icon: DPIcons.circleAlert,
              title: 'Couldn’t load plans',
              message: 'Check your connection and try again.',
              actionLabel: 'Retry',
              onAction: () => _fetchDataPlans(_selectedNetwork!),
            ),
          )
        else
          Builder(builder: (context) {
            final shown = _planFilter == 'All plans'
                ? _dataPlans
                : _dataPlans.where((p) => _planBucket(p) == _planFilter).toList();
            if (shown.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text('No plans in this group.', textAlign: TextAlign.center, style: DPText.bodyMuted),
              );
            }
            final rows = <Widget>[];
            for (var i = 0; i < shown.length; i += 2) {
              rows.add(Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: _buildPlanCard(shown[i])),
                      const SizedBox(width: 12),
                      Expanded(child: i + 1 < shown.length ? _buildPlanCard(shown[i + 1]) : const SizedBox()),
                    ],
                  ),
                ),
              ));
            }
            return Column(children: rows);
          }),
      ],
    );
  }

  Widget _buildPlanCard(Map<String, dynamic> plan) {
    final name = plan['name']?.toString() ?? '';
    final isSelected = _selectedPlan == name &&
        _selectedPlanDetails?['variation_code'] == plan['variation_code'];
    final size = _planSize(name);
    final price = double.tryParse(plan['amount']?.toString() ?? '0') ?? 0;
    final validity = plan['validity']?.toString() ?? '';
    return Material(
      color: isSelected ? DP.greenSoft : DP.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DP.rLg - 2),
        side: BorderSide(color: isSelected ? DP.green : DP.border, width: isSelected ? 1.4 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(DP.rLg - 2),
        onTap: () => _selectPlan(name, plan),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(size,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: DPText.title.copyWith(fontSize: size == name ? 14 : 20)),
                  ),
                  Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: DP.green, width: 1.5),
                    ),
                    alignment: Alignment.center,
                    child: isSelected
                        ? Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(color: DP.green, shape: BoxShape.circle),
                          )
                        : null,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                size == name ? validity : [if (validity.isNotEmpty) validity, name].join(' · '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: DPText.small.copyWith(fontSize: 11.5),
              ),
              const SizedBox(height: 8),
              Text(dpNaira(price, decimals: price % 1 != 0),
                  style: DPText.value.copyWith(color: DP.green, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }

  // ==================== STICKY BOTTOM CTA ====================
  Widget _buildStickyBottomCTA() {
    final sel = _selectedPlanDetails;
    final busy = _isProcessingPayment || _isAuthenticating;
    return DPButton(
      label: sel != null ? 'Continue with ${_planSize(sel['name'].toString())}' : 'Continue',
      icon: DPIcons.arrowRight,
      loading: busy,
      onPressed: busy ? null : _openPaymentSheet,
    );
  }

  // ==================== PAYMENT SHEET OVERLAY ====================
  Widget _buildPaymentSheetOverlay() {
    final plan = _selectedPlanDetails;
    final amount = double.tryParse(_amountController.text) ??
        double.tryParse(plan?['amount']?.toString() ?? '0') ??
        0;
    final bool isBiometricSupported = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
    final canBiometric = isBiometricSupported && _biometricEnabled && _biometricAllowed;
    return DPSheetOverlay(
      animation: _sheetAnimation,
      onDismiss: _isProcessingPayment ? null : _closePaymentSheet,
      child: DPPaymentReview(
        icon: DPIcons.wifi,
        serviceLabel: '${_selectedNetwork ?? ''} data',
        amount: amount,
        rows: [
          DPSummaryRow('Phone number', _phoneController.text.trim()),
          DPSummaryRow('Network', '${_selectedNetwork ?? '—'} Nigeria'),
          DPSummaryRow('Plan', plan?['name']?.toString() ?? '—'),
          if ((plan?['validity'] ?? '').toString().isNotEmpty)
            DPSummaryRow('Validity', plan!['validity'].toString()),
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
        footnote: 'Plans activate on the number entered and can’t be reversed.',
      ),
    );
  }



  // ==================== PIN INPUT WITH SHAKE & ERROR UI ====================

  // ==================== BIOMETRIC OPTION ====================

  // ==================== SECTION TITLE ====================
  Widget _buildSectionTitle(String title) => DPFieldLabel(title);

  Widget _buildServiceUnavailable() {
    return DPServiceUnavailable(
      message: !_isUserActive
          ? 'Your account has been deactivated. Please contact support.'
          : 'Data purchase is currently unavailable. Please try again later.',
    );
  }

  void _showSuccessDialog(
    String network,
    String phone,
    double amount,
    String planName,
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
              transactionType: 'Data Purchase',
              amount: amount.toStringAsFixed(2),
              status: 'delivered',
              transactionId: transactionId,
              reference: reference.toString(),
              date: DateTime.now(),
              phoneNumber: phone,
              description: '${network.toUpperCase()} - $planName',
              customMessage: '✓ Data bundle activated successfully!',
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
    showDPDialog(context, tone: DPDialogTone.error, title: title, message: message);
  }
}
