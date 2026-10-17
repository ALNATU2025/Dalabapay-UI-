// lib/presentation/screens/education/education_screen.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../core/services/api_service.dart';
import '../../../core/widgets/receipt_widget.dart';
import '../../../core/widgets/request_limit_increase_dialog.dart';

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
  static const Color _primary = Color(0xFF243889);
  static const Color _secondary = Color(0xFF219C7E);
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

  void _loadMockPlans(String serviceId) {
    final mockPlans = <Map<String, dynamic>>[];

    switch (serviceId) {
      case 'waec-registration':
        mockPlans.addAll([
          {
            'name': 'WASSCE Private Candidates - Second Series',
            'variation_code': 'waec-registration',
            'variation_amount': '18950.00',
            'fixedPrice': true,
          },
          {
            'name': 'WASSCE Private Candidates - First Series',
            'variation_code': 'waec-registration-2',
            'variation_amount': '18950.00',
            'fixedPrice': true,
          },
        ]);
        break;
      case 'waec':
        mockPlans.addAll([
          {
            'name': 'WASSCE Result Checker',
            'variation_code': 'waecdirect',
            'variation_amount': '1200.00',
            'fixedPrice': true,
          },
          {
            'name': 'WASSCE GCE Result Checker',
            'variation_code': 'waecdirect-2',
            'variation_amount': '1200.00',
            'fixedPrice': true,
          },
        ]);
        break;
      case 'jamb':
        mockPlans.addAll([
          {
            'name': 'UTME PIN (with mock)',
            'variation_code': 'utme-mock',
            'variation_amount': '6300.00',
            'fixedPrice': true,
          },
          {
            'name': 'UTME PIN (without mock)',
            'variation_code': 'utme-no-mock',
            'variation_amount': '4700.00',
            'fixedPrice': true,
          },
          {
            'name': 'Direct Entry PIN',
            'variation_code': 'direct-entry',
            'variation_amount': '5300.00',
            'fixedPrice': true,
          },
        ]);
        break;
    }

    setState(() {
      _servicePlans[serviceId] = mockPlans;
      _selectedPlan = null;
    });
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
              padding: const EdgeInsets.all(28),
              width: MediaQuery.of(context).size.width * 0.9,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [_secondary, _secondary.withOpacity(0.7)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: _secondary.withOpacity(0.3),
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
                    'Profile Validated!',
                    style: GoogleFonts.poppins(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: _primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: _secondary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Verification Complete',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _secondary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Divider(color: Color(0xFFEEEEEE)),
                  const SizedBox(height: 16),
                  _buildDetailRow('Customer Name', customerName),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _primary.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _primary.withOpacity(0.1)),
                    ),
                    child: Row(
                      children: [
                        HugeIcon(
                          icon: HugeIcons.strokeRoundedShield01,
                          color: _primary,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'This profile has been verified and is ready for PIN purchase.',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _primary,
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
                              Navigator.pushReplacementNamed(context, '/home');
                            }
                            setState(() {
                              _customerName = null;
                              _profileIdController.clear();
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
                              fontWeight: FontWeight.w700,
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
                              Navigator.pushReplacementNamed(context, '/home');
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 2,
                          ),
                          child: Text(
                            'Continue',
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
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 13,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: GoogleFonts.poppins(
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedService,
          isExpanded: true,
          hint: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  shape: BoxShape.circle,
                ),
                child: HugeIcon(
                  icon: HugeIcons.strokeRoundedMortarboard01,
                  color: Colors.grey.shade400,
                  size: 16,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Select Service',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: _hintColor,
                ),
              ),
            ],
          ),
          icon: HugeIcon(
            icon: HugeIcons.strokeRoundedArrowDown01,
            color: Colors.grey,
            size: 18,
          ),
          style: GoogleFonts.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade800,
          ),
          items:
              _services.map((service) {
                return DropdownMenuItem<String>(
                  value: service['id'],
                  child: Row(
                    children: [
                      _buildServiceLogo(
                        service['logo'],
                        service['color'],
                        size: 28,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          service['fullName'],
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
          onChanged: (value) {
            setState(() {
              _selectedService = value;
              _selectedPlan = null;
              _customerName = null;
              _showProfileIdField = false;
            });
            final service = _services.firstWhere((s) => s['id'] == value);
            setState(() {
              _showProfileIdField = service['requiresProfileId'] == true;
            });
            _fetchServicePlans(value!);
          },
        ),
      ),
    );
  }

  // ==================== PLAN SELECTION ====================

  Widget _buildPlanSelection() {
    final plans = _servicePlans[_selectedService] ?? [];

    if (_isLoadingPlans) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Select Plan',
            style: GoogleFonts.poppins(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: _primary,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 20),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF243889)),
              ),
            ),
          ),
        ],
      );
    }

    if (plans.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          children: [
            HugeIcon(
              icon: HugeIcons.strokeRoundedAlert02,
              color: Colors.orange.shade700,
              size: 40,
            ),
            const SizedBox(height: 12),
            Text(
              'No plans available',
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade700,
              ),
            ),
            Text(
              'Please try another service',
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Select Plan',
          style: GoogleFonts.poppins(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: _primary,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          constraints: const BoxConstraints(maxHeight: 280),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: ListView.builder(
            shrinkWrap: true,
            physics: const BouncingScrollPhysics(),
            itemCount: plans.length,
            itemBuilder: (context, index) {
              final plan = plans[index];
              final isSelected = _selectedPlan == plan['name'];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: _buildPlanCard(plan, isSelected),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPlanCard(Map<String, dynamic> plan, bool isSelected) {
    final amount = plan['variation_amount']?.toString() ?? '0.00';
    final name = plan['name']?.toString() ?? 'Unknown Plan';

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedPlan = name;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? _primary : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? _primary : Colors.grey.shade200,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color:
                  isSelected
                      ? _primary.withOpacity(0.2)
                      : Colors.black.withOpacity(0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                name,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: isSelected ? Colors.white : _primary,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected ? Colors.white : _secondary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '₦${NumberFormat('#,##0').format(double.tryParse(amount) ?? 0)}',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: isSelected ? _primary : _secondary,
                ),
              ),
            ),
          ],
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

                              // Header: Logo centered, Close button top-right
                              Stack(
                                children: [
                                  Center(
                                    child: Image.asset(
                                      'assets/dalabapay2.png',
                                      height: 40,
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
                                        child: HugeIcon(
                                          icon:
                                              HugeIcons
                                                  .strokeRoundedMultiplicationSign,
                                          size: 18,
                                          color: const Color(0xFF64748B),
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
                                  color: const Color(0xFF1C2D5A),
                                ),
                              ),
                              const SizedBox(height: 16),

                              // Transaction Details
                              _buildPaymentSheetDetails(),
                              const SizedBox(height: 16),

                              // Balance
                              _buildPaymentSheetBalance(),
                              const SizedBox(height: 20),

                              Divider(
                                color: Colors.grey.shade200,
                                thickness: 1,
                              ),
                              const SizedBox(height: 20),

                              // Pay with PIN Option
                              if (_transactionPinSet) ...[
                                _buildPinOption(),
                                const SizedBox(height: 12),
                              ],

                              // Pay with Biometric Option
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
                                      HugeIcon(
                                        icon: HugeIcons.strokeRoundedAlert02,
                                        color: Colors.orange.shade700,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          'Set up a transaction PIN in Settings to make payments.',
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
    final service = _services.firstWhere(
      (s) => s['id'] == _selectedService,
      orElse: () => _services.first,
    );
    final planName = _selectedPlan ?? 'N/A';
    final phone = _phoneController.text.trim();
    final quantity = int.tryParse(_quantityController.text.trim()) ?? 1;
    final profileId = _profileIdController.text.trim();
    final plans = _servicePlans[_selectedService] ?? [];

    final planDetails = plans.firstWhere(
      (p) => p['name'] == _selectedPlan,
      orElse:
          () => {
            'variation_amount': '0',
            'name': 'N/A',
            'variation_code': 'N/A',
          },
    );
    final perUnitAmount =
        double.tryParse(planDetails['variation_amount']?.toString() ?? '0') ??
        0;
    final totalAmount = perUnitAmount * quantity;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        children: [
          // Service Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: service['color'].withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: _buildServiceLogo(
                      service['logo'],
                      service['color'],
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Service',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
              Flexible(
                child: Text(
                  service['fullName'] ?? 'N/A',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF1C2D5A),
                  ),
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          Divider(height: 14, color: Colors.grey.shade200),

          // Plan Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B).withOpacity(0.08),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: HugeIcon(
                      icon: HugeIcons.strokeRoundedTv01,
                      color: const Color(0xFFF59E0B),
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Plan',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
              Flexible(
                child: Text(
                  planName,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF1C2D5A),
                  ),
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          Divider(height: 14, color: Colors.grey.shade200),

          // Phone Number Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: _primary.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: HugeIcon(
                      icon: HugeIcons.strokeRoundedSmartPhone01,
                      color: _primary,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Phone',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
              Text(
                phone.isNotEmpty ? phone : 'N/A',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF1C2D5A),
                ),
              ),
            ],
          ),
          Divider(height: 14, color: Colors.grey.shade200),

          // Profile ID Row (only for JAMB)
          if (_showProfileIdField && profileId.isNotEmpty) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF8B5CF6).withOpacity(0.08),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: HugeIcon(
                        icon: HugeIcons.strokeRoundedUser02,
                        color: const Color(0xFF8B5CF6),
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Profile ID',
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
                Text(
                  profileId,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF1C2D5A),
                  ),
                ),
              ],
            ),
            Divider(height: 14, color: Colors.grey.shade200),
          ],

          // Quantity Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6366F1).withOpacity(0.08),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: HugeIcon(
                      icon: HugeIcons.strokeRoundedCalendar03,
                      color: const Color(0xFF6366F1),
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Quantity',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
              Text(
                '$quantity',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF1C2D5A),
                ),
              ),
            ],
          ),
          Divider(height: 14, color: Colors.grey.shade200),

          // Amount Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: _secondary.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: HugeIcon(
                      icon: HugeIcons.strokeRoundedMoney01,
                      color: _secondary,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Amount',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '₦${totalAmount.toStringAsFixed(2)}',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: _secondary,
                    ),
                  ),
                  if (quantity > 1)
                    Text(
                      '₦${perUnitAmount.toStringAsFixed(2)} × $quantity',
                      style: GoogleFonts.poppins(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade600,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentSheetBalance() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _secondary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _secondary.withOpacity(0.15)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              HugeIcon(
                icon: HugeIcons.strokeRoundedWallet01,
                color: _secondary,
                size: 16,
              ),
              const SizedBox(width: 6),
              Text(
                'Available Balance',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF64748B),
                ),
              ),
            ],
          ),
          Text(
            '₦${_walletBalance.toStringAsFixed(2)}',
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: _secondary,
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
      padding: const EdgeInsets.symmetric(horizontal: 16),
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
                    : (_useBiometric
                        ? Colors.grey.shade50
                        : _primary.withOpacity(0.04)),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color:
                  hasError
                      ? const Color(0xFFEF4444)
                      : (_useBiometric ? Colors.grey.shade300 : _primary),
              width: hasError ? 2 : (_useBiometric ? 1 : 2),
            ),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: TextField(
                  controller: _pinController,
                  focusNode: _pinFocusNode,
                  obscureText: true,
                  enabled: !_useBiometric,
                  decoration: InputDecoration(
                    hintText: 'Enter 6-digit transaction PIN',
                    hintStyle: GoogleFonts.poppins(
                      color:
                          hasError
                              ? const Color(0xFFEF4444).withOpacity(0.7)
                              : (_useBiometric
                                  ? Colors.grey.shade400
                                  : Colors.grey.shade600),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                    prefixIcon: HugeIcon(
                      icon: HugeIcons.strokeRoundedBiometricAccess,
                      color:
                          hasError
                              ? const Color(0xFFEF4444)
                              : (_useBiometric
                                  ? Colors.grey.shade400
                                  : _primary),
                      size: 18,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 0,
                      vertical: 12,
                    ),
                    errorText: _pinValidationError,
                  ),
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color:
                        hasError
                            ? const Color(0xFFDC2626)
                            : (_useBiometric
                                ? Colors.grey.shade400
                                : Colors.black),
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
                    horizontal: 14,
                    vertical: 6,
                  ),
                  color: const Color(0xFFFEE2E2),
                  child: Row(
                    children: [
                      HugeIcon(
                        icon: HugeIcons.strokeRoundedAlert02,
                        color: const Color(0xFFDC2626),
                        size: 14,
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
                      _isProcessingPayment || _useBiometric
                          ? null
                          : _processPayment,
                  style: TextButton.styleFrom(
                    backgroundColor:
                        hasError
                            ? const Color(0xFFDC2626)
                            : (_useBiometric ? Colors.transparent : _secondary),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          hasError
                              ? const BorderRadius.vertical(
                                bottom: Radius.circular(12),
                              )
                              : BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child:
                      _isProcessingPayment && !_useBiometric
                          ? SizedBox(
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
                              HugeIcon(
                                icon: HugeIcons.strokeRoundedBiometricAccess,
                                color:
                                    hasError
                                        ? Colors.white
                                        : (_useBiometric
                                            ? Colors.grey.shade400
                                            : Colors.white),
                                size: 16,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                hasError
                                    ? 'Retry'
                                    : (_useBiometric
                                        ? 'Switch to PIN'
                                        : 'Pay with PIN'),
                                style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color:
                                      hasError
                                          ? Colors.white
                                          : (_useBiometric
                                              ? Colors.grey.shade400
                                              : Colors.white),
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
    final bool isBiometricSupported = Platform.isAndroid || Platform.isIOS;

    if (!isBiometricSupported) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GestureDetector(
        onTap:
            _isProcessingPayment
                ? null
                : () {
                  setState(() {
                    _useBiometric = true;
                    _pinValidationError = null;
                    _pinController.clear();
                  });
                  _processPayment();
                },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
          decoration: BoxDecoration(
            color: _useBiometric ? _primary.withOpacity(0.08) : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _useBiometric ? _primary : Colors.grey.shade300,
              width: _useBiometric ? 2 : 1,
            ),
          ),
          child:
              _isProcessingPayment && _useBiometric
                  ? Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        color: _primary,
                        strokeWidth: 2.5,
                      ),
                    ),
                  )
                  : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.fingerprint,
                        color: _useBiometric ? _primary : Colors.grey.shade600,
                        size: 24,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _useBiometric
                              ? '🔐 Tap to authenticate'
                              : 'Pay with Biometric',
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color:
                                _useBiometric ? _primary : Colors.grey.shade700,
                          ),
                        ),
                      ),
                      if (_useBiometric)
                        Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: _secondary,
                            shape: BoxShape.circle,
                          ),
                          child: HugeIcon(
                            icon: HugeIcons.strokeRoundedCheckmarkCircle01,
                            color: Colors.white,
                            size: 12,
                          ),
                        ),
                    ],
                  ),
        ),
      ),
    );
  }

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
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: HugeIcon(
                    icon: HugeIcons.strokeRoundedAlert02,
                    color: Colors.red.shade700,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: GoogleFonts.poppins(
                      color: Colors.red.shade700,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade800,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(
                    children: [
                      HugeIcon(
                        icon: HugeIcons.strokeRoundedInformationCircle,
                        color: Colors.grey.shade600,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'If this issue persists, please contact support.',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  backgroundColor: _primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(
                  'OK',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
    );
  }

  // ==================== BUILD ====================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _buildAppBar(),
      body: Stack(
        children: [
          _buildBody(),
          if (_showPaymentSheet) _buildPaymentSheetOverlay(),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      leading: IconButton(
        icon: HugeIcon(
          icon: HugeIcons.strokeRoundedArrowLeft01,
          color: _primary,
          size: 20,
        ),
        onPressed: () => Navigator.pop(context),
      ),
      title: Text(
        'Education',
        style: GoogleFonts.poppins(
          color: _primary,
          fontSize: 18,
          fontWeight: FontWeight.w800,
        ),
      ),
      centerTitle: true,
      actions: [
        Container(
          margin: const EdgeInsets.only(right: 16),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: _primary.withOpacity(0.05),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              HugeIcon(
                icon: HugeIcons.strokeRoundedWallet01,
                color: _primary,
                size: 16,
              ),
              const SizedBox(width: 4),
              GestureDetector(
                onTap:
                    () =>
                        setState(() => _isBalanceVisible = !_isBalanceVisible),
                child: Text(
                  _isBalanceVisible
                      ? '₦${_walletBalance.toStringAsFixed(2)}'
                      : '••••',
                  style: GoogleFonts.poppins(
                    color: _primary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBody() {
    if (_isLoadingUserData) {
      return Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(_primary),
        ),
      );
    }

    if (!_isUserActive || !_educationServiceEnabled) {
      return _buildServiceUnavailable();
    }

    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildBanner(),
              const SizedBox(height: 24),

              // Select Service
              Text(
                'Select Service',
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: _primary,
                ),
              ),
              const SizedBox(height: 8),
              _buildServiceDropdown(),
              const SizedBox(height: 20),

              // Plan Selection
              if (_selectedService != null) _buildPlanSelection(),
              const SizedBox(height: 20),

              // Profile ID (for JAMB)
              if (_showProfileIdField) ...[
                Text(
                  'Profile ID',
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: _primary,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: TextField(
                          controller: _profileIdController,
                          focusNode: _profileFocusNode,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: InputDecoration(
                            hintText: 'Enter your Profile ID',
                            hintStyle: GoogleFonts.poppins(
                              color: _hintColor,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                            prefixIcon: Container(
                              padding: const EdgeInsets.all(12),
                              child: HugeIcon(
                                icon: HugeIcons.strokeRoundedUser02,
                                color: _primary,
                                size: 22,
                              ),
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),
                            filled: true,
                            fillColor: Colors.transparent,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 14,
                            ),
                          ),
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                          onChanged: (_) {
                            setState(() => _customerName = null);
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 90,
                      height: 52,
                      child: ElevatedButton(
                        onPressed:
                            _isValidating || _profileIdController.text.isEmpty
                                ? null
                                : _validateProfileId,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: EdgeInsets.zero,
                        ),
                        child:
                            _isValidating
                                ? SizedBox(
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
                if (_customerName != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _secondary.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _secondary.withOpacity(0.2)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: _secondary.withOpacity(0.15),
                            shape: BoxShape.circle,
                          ),
                          child: HugeIcon(
                            icon: HugeIcons.strokeRoundedCheckmarkCircle01,
                            color: _secondary,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Profile Validated',
                                style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: _secondary,
                                ),
                              ),
                              Text(
                                _customerName!,
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: _secondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 20),
              ],

              // Phone Number
              Text(
                'Phone Number',
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: _primary,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.grey.shade200),
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
                      color: _hintColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    prefixIcon: Container(
                      padding: const EdgeInsets.all(12),
                      child: HugeIcon(
                        icon: HugeIcons.strokeRoundedSmartPhone01,
                        color: _primary,
                        size: 22,
                      ),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: Colors.transparent,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 14,
                    ),
                  ),
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Quantity
              if (_selectedService != null &&
                  _services.firstWhere(
                        (s) => s['id'] == _selectedService,
                      )['showQuantity'] ==
                      true) ...[
                Text(
                  'Quantity',
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: _primary,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: TextField(
                    controller: _quantityController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      hintText: 'Enter quantity (min 1)',
                      hintStyle: GoogleFonts.poppins(
                        color: _hintColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      prefixIcon: Container(
                        padding: const EdgeInsets.all(12),
                        child: HugeIcon(
                          icon: HugeIcons.strokeRoundedLeftToRightListNumber,
                          color: _primary,
                          size: 22,
                        ),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.transparent,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 14,
                      ),
                    ),
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],

              // Info Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _primary.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 23,
                      height: 23,
                      decoration: BoxDecoration(
                        color: _primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: HugeIcon(
                        icon: HugeIcons.strokeRoundedInformationCircle,
                        color: _primary,
                        size: 16,
                      ),
                    ),
                    const SizedBox(width: 15),
                    Expanded(
                      child: Text(
                        'Confirm the details before proceeding.',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: _primary,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Continue Button
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed:
                      (_isLoading || _isAuthenticating)
                          ? null
                          : _openPaymentSheet,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _secondary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child:
                      _isLoading || _isAuthenticating
                          ? SizedBox(
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
                              HugeIcon(
                                icon: HugeIcons.strokeRoundedArrowUp01,
                                color: Colors.white,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Continue',
                                style: GoogleFonts.poppins(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                ),
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBanner() {
    final screenWidth = MediaQuery.of(context).size.width;
    final bannerHeight = screenWidth < 400 ? 100.0 : 128.0;

    return Container(
      width: double.infinity,
      height: bannerHeight,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        image: const DecorationImage(
          image: AssetImage('assets/education_banner.png'),
          fit: BoxFit.cover,
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              _primary.withOpacity(0.3),
              _secondary.withOpacity(0.15),
              Colors.transparent,
            ],
            stops: const [0.0, 0.4, 0.7],
          ),
        ),
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
            HugeIcon(
              icon:
                  !_isUserActive
                      ? HugeIcons.strokeRoundedUser02
                      : HugeIcons.strokeRoundedMortarboard02,
              color:
                  !_isUserActive ? Colors.red.shade700 : Colors.orange.shade700,
              size: 60,
            ),
            const SizedBox(height: 16),
            Text(
              !_isUserActive ? 'Account Deactivated' : 'Service Unavailable',
              style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.w800,
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
                  : 'Education service is currently unavailable. Please try again later.',
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
                backgroundColor: _primary,
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
