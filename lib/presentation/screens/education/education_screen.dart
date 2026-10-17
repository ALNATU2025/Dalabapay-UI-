// lib/presentation/screens/education/education_screen.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../core/services/api_service.dart';
import '../../../core/widgets/receipt_widget.dart';
import '../../../core/widgets/request_limit_increase_dialog.dart';
import '../../../ui/ui.dart';

class EducationScreen extends StatefulWidget {
  final void Function(double newBalance) onBalanceUpdate;
  final String userId;

  const EducationScreen({
    super.key,
    required this.onBalanceUpdate,
    required this.userId,
  });

  @override
  State<EducationScreen> createState() => _EducationScreenState();
}

class _EducationScreenState extends State<EducationScreen>
    with TickerProviderStateMixin {
  // Controllers
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _pinController = TextEditingController();
  final TextEditingController _profileIdController = TextEditingController();
  final TextEditingController _quantityController = TextEditingController(
    text: '1',
  );

  // Focus Nodes
  final FocusNode _phoneFocusNode = FocusNode();
  final FocusNode _pinFocusNode = FocusNode();
  final FocusNode _profileFocusNode = FocusNode();

  // State Variables
  String? _selectedService;
  String? _selectedPlan;
  String? _customerName;
  final bool _isLoading = false;
  final bool _isAuthenticating = false;
  bool _isValidating = false;
  bool _isLoadingPlans = false;
  bool _isBalanceVisible = true;
  double _walletBalance = 0.0;
  bool _showProfileIdField = false;

  // Authentication State
  bool _transactionPinSet = false;
  bool _biometricEnabled = false;
  bool _pinRequired = true;
  bool _biometricAllowed = true;
  bool _useBiometric = false;
  bool _pinLocked = false;
  int _lockTimeRemaining = 0;
  String? _pinValidationError;

  // Service State
  final bool _educationServiceEnabled = true;
  bool _isUserActive = true;
  bool _isLoadingUserData = true;

  // Animation
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late AnimationController _sheetController;
  late Animation<double> _sheetAnimation;

  // ✅ ADD SHAKE ANIMATION
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

  // Payment Sheet State
  bool _showPaymentSheet = false;
  bool _isProcessingPayment = false;

  // Color Palette
  static const Color _primary = Color(0xFF102C68);
  static const Color _secondary = Color(0xFF168566);
  static const Color _hintColor = Color(0xFFB6B6B6);

  // Service list with logos
  final List<Map<String, dynamic>> _services = [
    {
      'id': 'waec-registration',
      'name': 'WAEC Registration',
      'fullName': 'WAEC Registration',
      'logo':
          'https://pbs.twimg.com/profile_images/1583839523301195776/0UZ6cUcI_400x400.jpg',
      'color': const Color(0xFF4CAF50),
      'requiresPhone': true,
      'requiresProfileId': false,
      'showQuantity': true,
    },
    {
      'id': 'waec',
      'name': 'WAEC Result Checker',
      'fullName': 'WAEC Result Checker',
      'logo':
          'https://pbs.twimg.com/profile_images/1583839523301195776/0UZ6cUcI_400x400.jpg',
      'color': const Color(0xFFFF9800),
      'requiresPhone': true,
      'requiresProfileId': false,
      'showQuantity': true,
    },
    {
      'id': 'jamb',
      'name': 'JAMB PIN',
      'fullName': 'JAMB PIN',
      'logo':
          'https://upload.wikimedia.org/wikipedia/en/2/2e/Official_JAMB_logo.png',
      'color': const Color(0xFF9C27B0),
      'requiresPhone': true,
      'requiresProfileId': true,
      'showQuantity': false,
    },
  ];

  // Plans storage
  final Map<String, List<Map<String, dynamic>>> _servicePlans = {};

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _initializeData();
    _fetchSecuritySettings();
    _loadWalletBalance();
    _phoneController.text = '';
  }

  void _setupAnimations() {
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeIn,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOutCubic),
    );
    _fadeController.forward();

    _sheetController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _sheetAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _sheetController, curve: Curves.easeOutCubic),
    );

    // ✅ ADD SHAKE ANIMATION FOR PIN ERROR
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

  Future<void> _initializeData() async {
    try {
      final user = await ApiService.getCurrentUser();
      setState(() {
        _isUserActive = user['isActive'] ?? true;
        _isLoadingUserData = false;
        if (user['phone'] != null) {
          _phoneController.text = user['phone'].toString();
        }
      });
    } catch (e) {
      setState(() => _isLoadingUserData = false);
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
      setState(() {
        _transactionPinSet = prefs.getBool('transactionPinSet') ?? false;
        _biometricEnabled = prefs.getBool('biometricEnabled') ?? false;
      });

      final globalSettings = await ApiService.getGlobalSecuritySettings();
      setState(() {
        _pinRequired = globalSettings['pinRequired'] ?? true;
        _biometricAllowed = globalSettings['biometricAllowed'] ?? true;
      });

      final securitySettings = await ApiService.getSecuritySettings();
      setState(() {
        _pinLocked = securitySettings['securitySettings']['pinLocked'] ?? false;
        _lockTimeRemaining =
            securitySettings['securitySettings']['lockTimeRemaining'] ?? 0;
      });
    } catch (e) {
      // Silent fail
    }
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _sheetController.dispose();
    _shakeController.dispose();
    _phoneController.dispose();
    _pinController.dispose();
    _profileIdController.dispose();
    _quantityController.dispose();
    _phoneFocusNode.dispose();
    _pinFocusNode.dispose();
    _profileFocusNode.dispose();
    super.dispose();
  }

  String? _validateForm() {
    if (_selectedService == null) {
      return 'Please select an education service';
    }

    if (_selectedPlan == null) {
      return 'Please select a plan';
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

    if (_showProfileIdField) {
      final profileId = _profileIdController.text.trim();
      if (profileId.isEmpty) {
        return 'Please enter your Profile ID';
      }
      if (_customerName == null) {
        return 'Please validate your Profile ID first';
      }
    }

    final quantity = int.tryParse(_quantityController.text.trim());
    if (quantity == null || quantity < 1) {
      return 'Please enter a valid quantity (minimum 1)';
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
    } else if (errorStr.contains('Invalid profile') ||
        errorStr.contains('WrongBillersCode')) {
      return 'Invalid Profile ID. Please check and try again.';
    }
    return errorStr.length > 100 ? 'An unexpected error occurred.' : errorStr;
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

  void _log(String message) {
    if (kDebugMode) {
      debugPrint('📚 EDUCATION SCREEN: $message');
    }
  }

  Future<void> _fetchServicePlans(String serviceId) async {
    if (_isLoadingPlans) return;

    setState(() => _isLoadingPlans = true);

    try {
      final result = await ApiService.getVtpassVariations(serviceId);

      if (result['success'] == true || result['variations'] != null) {
        final plans = List<Map<String, dynamic>>.from(
          result['variations'] ?? result['content']?['variations'] ?? [],
        );

        plans.sort((a, b) {
          final amountA =
              double.tryParse(a['variation_amount']?.toString() ?? '0') ?? 0;
          final amountB =
              double.tryParse(b['variation_amount']?.toString() ?? '0') ?? 0;
          return amountA.compareTo(amountB);
        });

        setState(() {
          _servicePlans[serviceId] = plans;
          _selectedPlan = null;
        });
      } else {
        _loadMockPlans(serviceId);
      }
    } catch (e) {
      _loadMockPlans(serviceId);
    } finally {
      setState(() => _isLoadingPlans = false);
    }
  }

  // Plans could not be loaded. Made-up plans are no longer shown;
  // the UI offers a retry instead.
  void _loadMockPlans(String serviceId) {
    setState(() {
      _servicePlans[serviceId] = [];
      _selectedPlan = null;
    });
  }

  Map<String, dynamic>? get _selectedServiceData {
    if (_selectedService == null) return null;
    for (final s in _services) {
      if (s['id'] == _selectedService) return s;
    }
    return null;
  }

  Map<String, dynamic>? get _selectedPlanData {
    if (_selectedService == null || _selectedPlan == null) return null;
    for (final p in _servicePlans[_selectedService] ?? const <Map<String, dynamic>>[]) {
      if (p['name'] == _selectedPlan) return p;
    }
    return null;
  }

  double get _totalAmount {
    final plan = _selectedPlanData;
    if (plan == null) return 0;
    final unit = double.tryParse(plan['variation_amount']?.toString() ?? '0') ?? 0;
    final showQty = _selectedServiceData?['showQuantity'] == true;
    final qty = showQty ? (int.tryParse(_quantityController.text.trim()) ?? 1) : 1;
    return unit * (qty < 1 ? 1 : qty);
  }

  Future<void> _validateProfileId() async {
    if (_selectedService != 'jamb') return;

    final profileId = _profileIdController.text.trim();
    if (profileId.isEmpty) {
      _showErrorDialog(
        'Invalid Profile ID',
        'Please enter your JAMB Profile ID.',
      );
      return;
    }

    setState(() {
      _isValidating = true;
      _customerName = null;
    });

    try {
      final result = await ApiService.validateEducationProfile(
        profileId: profileId,
        serviceID: 'jamb',
      );

      if (result['success'] == true) {
        final customerName =
            result['customerName']?.toString().trim() ?? 'Unknown';
        setState(() {
          _customerName = customerName;
        });
        _showValidationSuccessDialog(customerName);
      } else {
        _showErrorDialog(
          'Validation Failed',
          result['message'] ?? 'Invalid Profile ID.',
        );
      }
    } catch (e) {
      String errorMessage = e.toString().replaceAll('Exception: ', '');
      _showErrorDialog('Validation Error', errorMessage);
    } finally {
      setState(() => _isValidating = false);
    }
  }

  void _showValidationSuccessDialog(String customerName) {
    dpSnack(context, 'Profile verified for ${customerName.toUpperCase()}', success: true);
  }

  Widget _buildDetailRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: Colors.grey.shade900,
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  // ==================== OPEN PAYMENT SHEET ====================

  void _openPaymentSheet() {
    final validationError = _validateForm();
    if (validationError != null) {
      _showErrorDialog('Validation Error', validationError);
      return;
    }

    // Security checks
    if (_pinRequired) {
      if (_pinLocked) {
        _showErrorDialog(
          'PIN Locked',
          'Your PIN is locked. Try again in $_lockTimeRemaining minutes.',
        );
        return;
      }
      if (!_transactionPinSet && !_biometricEnabled) {
        _showErrorDialog(
          'Security Setup Required',
          'Please set up a transaction PIN or enable biometric authentication.',
        );
        return;
      }
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
      setState(() {
        _showPaymentSheet = false;
        _isProcessingPayment = false;
        _pinValidationError = null;
      });
    });
  }

  // ==================== PROCESS PAYMENT ====================

  Future<void> _processPayment() async {
    final validationError = _validateForm();
    if (validationError != null) {
      _showErrorDialog('Validation Error', validationError);
      _closePaymentSheet();
      return;
    }

    // ✅ PIN validation
    if (!_useBiometric && _transactionPinSet) {
      final pin = _pinController.text.trim();
      if (pin.isEmpty) {
        setState(() {
          _pinValidationError = 'Please enter your transaction PIN';
        });
        _shakeController.forward(from: 0.0);
        return;
      }
      if (pin.length != 6) {
        setState(() {
          _pinValidationError = 'PIN must be exactly 6 digits';
        });
        _shakeController.forward(from: 0.0);
        return;
      }
      if (!RegExp(r'^[0-9]+$').hasMatch(pin)) {
        setState(() {
          _pinValidationError = 'PIN must contain only numbers';
        });
        _shakeController.forward(from: 0.0);
        return;
      }
      setState(() {
        _pinValidationError = null;
      });
    }

    if (_useBiometric) {
      setState(() {
        _pinValidationError = null;
      });
    }

    // ✅ STEP 1: PRE-VERIFY PIN BEFORE TRANSACTION (Like Airtime)
    if (_transactionPinSet && !_useBiometric) {
      final pin = _pinController.text.trim();

      setState(() {
        _isProcessingPayment = true;
      });

      try {
        _log('🔐 Verifying transaction PIN before payment...');

        final verifyResult = await ApiService.verifyTransactionPin(
          userId: widget.userId,
          transactionPin: pin,
        );

        _log('📡 PIN verification result: ${verifyResult['success']}');

        if (verifyResult['success'] != true) {
          final message =
              verifyResult['message'] ?? 'Incorrect transaction PIN';
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

          // ✅ Show PIN error snackbar with attempts remaining
          _showPinErrorSnackBar(
            message: message,
            attemptsRemaining: attemptsRemaining,
          );
          return;
        }
      } catch (e) {
        setState(() => _isProcessingPayment = false);
        _showErrorDialog(
          'PIN Verification Error',
          _mapExceptionToUserMessage(e),
        );
        return;
      }
    }

    // ✅ STEP 2: PIN VERIFIED SUCCESSFULLY -> EXECUTE TRANSACTION
    await _executeTransaction();
  }

  // ==================== EXECUTE TRANSACTION WITH LIMIT HANDLING ====================

  Future<void> _executeTransaction() async {
    final service = _selectedService!;
    final plan = _selectedPlan!;
    final phone = _phoneController.text.trim();
    final quantity = int.tryParse(_quantityController.text.trim()) ?? 1;
    final serviceDetails = _services.firstWhere((s) => s['id'] == service);
    final planDetails = _servicePlans[service]!.firstWhere(
      (p) => p['name'] == plan,
    );
    final perUnitAmount =
        double.tryParse(planDetails['variation_amount']?.toString() ?? '0') ??
        0;
    final totalAmount = perUnitAmount * quantity;
    final profileId = _profileIdController.text.trim();

    if (perUnitAmount <= 0) {
      _showErrorDialog('Invalid Amount', 'Selected plan has an invalid price.');
      _closePaymentSheet();
      return;
    }

    if (widget.userId.isEmpty) {
      _showErrorDialog(
        'Authentication Error',
        'User ID not found. Please log in again.',
      );
      _closePaymentSheet();
      return;
    }

    _log('📚 Executing transaction:');
    _log('   Service: $service');
    _log('   Plan: $plan');
    _log('   Phone: $phone');
    _log('   Amount: $totalAmount');
    _log('   Quantity: $quantity');
    _log('   Profile ID: $profileId');

    try {
      if (_useBiometric && _biometricEnabled) {
        final biometricSuccess = await ApiService.authenticateWithBiometrics();
        if (!biometricSuccess) {
          setState(() {
            _isProcessingPayment = false;
          });
          _showErrorDialog(
            'Authentication Failed',
            'Biometric authentication failed. Please try again.',
          );
          return;
        }
      }

      final result = await ApiService.purchaseEducationService(
        userId: widget.userId,
        serviceID: serviceDetails['id'],
        variationCode: planDetails['variation_code'] ?? '',
        phone: phone,
        amount: perUnitAmount,
        quantity: quantity,
        profileId: profileId.isNotEmpty ? profileId : null,
        transactionPin: _useBiometric ? null : _pinController.text,
        useBiometric: _useBiometric,
      );

      _log('📡 Raw result: ${result.toString()}');

      final vtpassCode =
          result['vtpassResponse']?['code']?.toString() ??
          result['vtpassResponse']?['vtpassResponse']?['code']?.toString();
      final bool vtpassSuccess = vtpassCode == '000';
      final bool alreadyProcessed = result['alreadyProcessed'] == true;

      if (vtpassSuccess || alreadyProcessed) {
        final newBalance = result['newBalance'] ?? 0.0;

        setState(() {
          _walletBalance = newBalance;
        });
        widget.onBalanceUpdate(newBalance);

        _closePaymentSheet();
        _showSuccessDialog(
          service: service,
          plan: plan,
          amount: totalAmount,
          quantity: quantity,
          result: result,
        );
        _clearForm();
      } else {
        // ✅ CRITICAL FIX: Extract the error code directly from result
        final errorCode = result['code']?.toString() ?? '';
        final errorMsg =
            result['message'] ??
            result['vtpassResponse']?['response_description'] ??
            'Transaction failed. Please try again.';

        _log('📡 Error Code: $errorCode');
        _log('📡 Error Message: $errorMsg');

        // ✅ CHECK FOR LIMIT ERRORS FIRST
        if (errorCode == 'PER_TRANSACTION_LIMIT_EXCEEDED' ||
            errorCode == 'DAILY_LIMIT_EXCEEDED' ||
            errorMsg.contains('PER_TRANSACTION_LIMIT_EXCEEDED') ||
            errorMsg.contains('DAILY_LIMIT_EXCEEDED')) {
          // ✅ FIX: Extract limit info with safe type conversion
          final limitValue = result['limit'];
          final requestedValue = result['requested'] ?? totalAmount;

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
            requested = double.tryParse(requestedValue) ?? totalAmount;
          } else {
            requested = totalAmount;
          }

          final isDaily =
              errorMsg.contains('DAILY_LIMIT_EXCEEDED') ||
              errorCode == 'DAILY_LIMIT_EXCEEDED';
          final serviceName = 'education';

          _log('🎯 Showing limit increase dialog:');
          _log('   Service: $serviceName');
          _log('   Limit: $limit');
          _log('   Requested: $requested');
          _log('   Is Daily: $isDaily');

          // ✅ Reset processing state
          setState(() {
            _isProcessingPayment = false;
          });

          // ✅ SHOW THE LIMIT INCREASE DIALOG
          _showLimitIncreaseDialog(
            service: serviceName,
            limitType: isDaily ? 'dailyCap' : 'perTransaction',
            currentLimit: limit,
            requestedAmount: requested,
          );
          return;
        }

        // ✅ Not a limit error - show generic error
        setState(() {
          _isProcessingPayment = false;
        });
        _showErrorDialog('Purchase Failed', errorMsg);
      }
    } catch (e) {
      setState(() {
        _isProcessingPayment = false;
      });

      final errorStr = e.toString().replaceAll('Exception: ', '');

      // ✅ CHECK FOR LIMIT ERRORS IN CATCH BLOCK TOO
      if (errorStr.contains('PER_TRANSACTION_LIMIT_EXCEEDED') ||
          errorStr.contains('DAILY_LIMIT_EXCEEDED')) {
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
          service: 'education',
          limitType: isDaily ? 'dailyCap' : 'perTransaction',
          currentLimit: limit,
          requestedAmount: totalAmount,
        );
        return;
      }

      _showErrorDialog('Purchase Failed', _mapExceptionToUserMessage(e));
    } finally {
      if (mounted) {
        setState(() {
          _isProcessingPayment = false;
        });
      }
    }
  }

  void _clearForm() {
    _phoneController.clear();
    _pinController.clear();
    _profileIdController.clear();
    _quantityController.text = '1';
    setState(() {
      _selectedService = null;
      _selectedPlan = null;
      _customerName = null;
      _useBiometric = false;
      _pinValidationError = null;
    });
  }

  // ==================== SERVICE LOGO WIDGET ====================

  Widget _buildServiceLogo(
    String imageUrl,
    Color fallbackColor, {
    double size = 28,
  }) {
    return ClipOval(
      child: Container(
        width: size,
        height: size,
        color: Colors.grey.shade100,
        child: FutureBuilder<Uint8List?>(
          future: _loadImage(imageUrl),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.done &&
                snapshot.hasData &&
                snapshot.data != null) {
              return Image.memory(
                snapshot.data!,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return _buildFallbackLogo(fallbackColor, size);
                },
              );
            } else {
              return _buildFallbackLogo(fallbackColor, size);
            }
          },
        ),
      ),
    );
  }

  Future<Uint8List?> _loadImage(String url) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        return response.bodyBytes;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Widget _buildFallbackLogo(Color color, double size) {
    return Container(
      width: size,
      height: size,
      color: color.withOpacity(0.2),
      child: HugeIcon(
        icon: HugeIcons.strokeRoundedMortarboard01,
        color: color,
        size: size * 0.5,
      ),
    );
  }

  // ==================== SERVICE DROPDOWN ====================

  Widget _buildServiceDropdown() {
    final labels = _services.map((s) => s['name'] as String).toList();
    final idx = _services.indexWhere((s) => s['id'] == _selectedService);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const DPFieldLabel('What do you need?'),
        for (var i = 0; i < _services.length; i++)
          DPOptionRow(
            leading: DPIconBadge(
              icon: _services[i]['id'] == 'jamb' ? DPIcons.graduationCap : DPIcons.fileText,
              size: 38,
              radius: 12,
            ),
            title: labels[i],
            subtitle: _services[i]['id'] == 'jamb'
                ? 'UTME / Direct Entry e-PIN'
                : (_services[i]['id'] == 'waec' ? 'Result checker PIN' : 'Exam registration PIN'),
            selected: i == idx,
            onTap: () {
              final value = _services[i]['id'] as String;
              if (value == _selectedService) return;
              setState(() {
                _selectedService = value;
                _selectedPlan = null;
                _customerName = null;
                _showProfileIdField = _services[i]['requiresProfileId'] == true;
              });
              _fetchServicePlans(value);
            },
          ),
        const SizedBox(height: 8),
      ],
    );
  }

  // ==================== PLAN SELECTION ====================

  Widget _buildPlanSelection() {
    final plans = _servicePlans[_selectedService] ?? const <Map<String, dynamic>>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const DPFieldLabel('Choose a plan'),
        if (_isLoadingPlans)
          const DPLoader(message: 'Loading plans…')
        else if (plans.isEmpty)
          DPCard(
            child: DPEmptyState(
              icon: DPIcons.circleAlert,
              title: 'Couldn’t load plans',
              message: 'Check your connection and try again.',
              actionLabel: 'Retry',
              onAction: () => _fetchServicePlans(_selectedService!),
            ),
          )
        else
          for (final p in plans) _buildPlanCard(p, _selectedPlan == p['name']),
        const SizedBox(height: 10),
      ],
    );
  }

  Widget _buildPlanCard(Map<String, dynamic> plan, bool isSelected) {
    final amount = double.tryParse(plan['variation_amount']?.toString() ?? '0') ?? 0;
    final name = plan['name']?.toString() ?? 'Unknown plan';
    return DPOptionRow(
      title: name,
      trailingText: dpNaira(amount),
      selected: isSelected,
      onTap: () => setState(() => _selectedPlan = name),
    );
  }

  // ==================== PAYMENT SHEET OVERLAY ====================

  Widget _buildPaymentSheetOverlay() {
    final service = _selectedServiceData;
    final plan = _selectedPlanData;
    final showQty = service?['showQuantity'] == true;
    final qty = int.tryParse(_quantityController.text.trim()) ?? 1;
    final amount = _totalAmount;
    final bool isBiometricSupported = Platform.isAndroid || Platform.isIOS;
    final canBiometric = isBiometricSupported && _biometricEnabled && _biometricAllowed;
    return DPSheetOverlay(
      animation: _sheetAnimation,
      onDismiss: _isProcessingPayment ? null : _closePaymentSheet,
      child: DPPaymentReview(
        icon: DPIcons.graduationCap,
        serviceLabel: service?['name']?.toString() ?? 'Education',
        amount: amount,
        rows: [
          DPSummaryRow('Plan', plan?['name']?.toString() ?? '—'),
          if (_showProfileIdField) DPSummaryRow('Profile ID', _profileIdController.text.trim()),
          if (_customerName != null) DPSummaryRow('Candidate', _customerName!),
          DPSummaryRow('Phone number', _phoneController.text.trim()),
          if (showQty) DPSummaryRow('Quantity', '$qty'),
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
        onPayWithPin: () {
          setState(() => _useBiometric = false);
          _processPayment();
        },
        onPayWithBiometric: canBiometric
            ? () {
                setState(() {
                  _useBiometric = true;
                  _pinValidationError = null;
                });
                _processPayment();
              }
            : null,
        biometricName: 'biometrics',
        onClose: _closePaymentSheet,
        footnote: 'Your PIN will appear on the receipt. Exam PINs can’t be refunded once issued.',
      ),
    );
  }

  // ==================== PAYMENT SHEET DETAILS ====================



  // ==================== PIN OPTION ====================


  // ==================== BIOMETRIC OPTION ====================


  // ==================== SUCCESS & ERROR DIALOGS ====================

  void _showSuccessDialog({
    required String service,
    required String plan,
    required double amount,
    required int quantity,
    required Map<String, dynamic> result,
  }) {
    final transactionId =
        result['transactionId'] ??
        'TXN_${DateTime.now().millisecondsSinceEpoch}';
    final reference = result['reference'] ?? transactionId;
    final serviceName =
        _services.firstWhere(
              (s) => s['id'] == service,
              orElse: () => {'name': 'Unknown'},
            )['fullName']
            as String;

    // Extract purchased code / tokens / cards
    String customMessage = 'Purchase completed successfully!';
    String? pinCode;
    String? serialNumber;

    final cards = result['cards'] as List<dynamic>?;
    final tokens = result['tokens'] as List<dynamic>?;
    final purchasedCode = result['purchased_code']?.toString();

    if (cards != null && cards.isNotEmpty) {
      final card = cards.first;
      pinCode = card['Pin']?.toString();
      serialNumber = card['Serial']?.toString();
      if (pinCode != null && serialNumber != null) {
        customMessage = 'Serial: $serialNumber\nPIN: $pinCode';
      }
    } else if (tokens != null && tokens.isNotEmpty) {
      customMessage = 'Token: ${tokens.join('\n')}';
    } else if (purchasedCode != null && purchasedCode.isNotEmpty) {
      customMessage = purchasedCode;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => Dialog(
            backgroundColor: Colors.transparent,
            elevation: 0,
            child: ReceiptWidget(
              transactionType: 'Education Service',
              amount: amount.toStringAsFixed(2),
              status: 'completed',
              transactionId: transactionId,
              reference: reference.toString(),
              date: DateTime.now(),
              phoneNumber: _phoneController.text,
              description:
                  '$serviceName - $plan${quantity > 1 ? ' x$quantity' : ''}',
              customerName: _customerName ?? 'N/A',
              gateway: 'Dalabapay App',
              customMessage: customMessage,
              primaryColor: _primary,
              showWatermark: true,
              isCommission: false,
            ),
          ),
    );
    _clearForm();
  }

  void _showErrorDialog(String title, String message) {
    showDPDialog(context, tone: DPDialogTone.error, title: title, message: message);
  }

  // ==================== BUILD ====================

  @override
  Widget build(BuildContext context) {
    final available = !_isLoadingUserData && _isUserActive && _educationServiceEnabled;
    return Stack(
      children: [
        DPPage(
          title: 'Education',
          actionLabel: 'History',
          onAction: () => Navigator.pushNamed(context, '/transactions'),
          bottom: available
              ? DPButton(
                  label: _selectedPlanData != null
                      ? 'Review · ${dpNaira(_totalAmount)}'
                      : 'Continue',
                  icon: DPIcons.arrowRight,
                  loading: _isLoading || _isAuthenticating,
                  onPressed: (_isLoading || _isAuthenticating) ? null : _openPaymentSheet,
                )
              : null,
          children: [_buildBody()],
        ),
        if (_showPaymentSheet) _buildPaymentSheetOverlay(),
      ],
    );
  }


  Widget _buildBody() {
    if (_isLoadingUserData) {
      return const Padding(padding: EdgeInsets.only(top: 80), child: DPLoader());
    }
    if (!_isUserActive || !_educationServiceEnabled) {
      return _buildServiceUnavailable();
    }
    final showQty = _selectedServiceData?['showQuantity'] == true;
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 18),
              child: Text('Exam PINs and result checkers, delivered instantly.',
                  style: DPText.bodyMuted),
            ),
            _buildServiceDropdown(),
            if (_selectedService != null) _buildPlanSelection(),
            if (_showProfileIdField) ...[
              DPField(
                label: 'JAMB profile ID',
                labelTrailing: DPLinkButton(
                  label: _isValidating ? 'Verifying…' : (_customerName != null ? 'Verified' : 'Verify'),
                  onPressed: _isValidating || _profileIdController.text.isEmpty || _customerName != null
                      ? null
                      : _validateProfileId,
                ),
                controller: _profileIdController,
                focusNode: _profileFocusNode,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                hint: 'Enter your profile ID',
                suffixIcon: DPIcons.idCard,
                onChanged: (_) => setState(() => _customerName = null),
                margin: EdgeInsets.only(bottom: _customerName != null ? 10 : 18),
              ),
              if (_customerName != null) DPVerifiedName(name: _customerName!),
            ],
            DPField(
              label: 'Phone number',
              controller: _phoneController,
              focusNode: _phoneFocusNode,
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(11),
              ],
              hint: '0803 456 7890',
              suffixIcon: DPIcons.phone,
            ),
            if (showQty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const DPFieldLabel('Quantity'),
                  Row(
                    children: [
                      _qtyButton(DPIcons.minus, () {
                        final q = int.tryParse(_quantityController.text) ?? 1;
                        if (q > 1) setState(() => _quantityController.text = '${q - 1}');
                      }),
                      Expanded(
                        child: Text(
                          _quantityController.text.isEmpty ? '1' : _quantityController.text,
                          textAlign: TextAlign.center,
                          style: DPText.title,
                        ),
                      ),
                      _qtyButton(DPIcons.plus, () {
                        final q = int.tryParse(_quantityController.text) ?? 1;
                        if (q < 10) setState(() => _quantityController.text = '${q + 1}');
                      }),
                    ],
                  ),
                  const SizedBox(height: 18),
                ],
              ),
            if (_selectedPlanData != null)
              DPSummaryCard(rows: [
                DPSummaryRow('Wallet balance', dpNaira(_walletBalance)),
                const DPSummaryRow('Service fee', '₦0.00'),
                DPSummaryRow('Total to pay', dpNaira(_totalAmount), emphasize: true),
              ]),
            const DPNotice(
              'Confirm the exam and details before you continue. PINs can’t be reversed once issued.',
              kind: DPNoticeKind.info,
              margin: EdgeInsets.zero,
            ),
          ],
        ),
      ),
    );
  }

  Widget _qtyButton(DPIconData icon, VoidCallback onTap) {
    return Material(
      color: DP.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DP.rMd),
        side: const BorderSide(color: DP.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(DP.rMd),
        onTap: onTap,
        child: SizedBox(width: 52, height: 48, child: Center(child: DPIcon(icon, size: 20, color: DP.ink))),
      ),
    );
  }


  Widget _buildServiceUnavailable() {
    return DPServiceUnavailable(
      message: !_isUserActive
          ? 'Your account has been deactivated. Please contact support.'
          : 'Education payments are currently unavailable. Please try again later.',
    );
  }
}
