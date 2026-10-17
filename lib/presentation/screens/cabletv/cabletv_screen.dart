// lib/presentation/screens/cabletv/cabletv_screen.dart
import 'dart:async';
import 'dart:convert' show jsonEncode;
import 'dart:io';
import 'package:flutter/foundation.dart';
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
import '../../../ui/ui.dart';
import '../../../core/widgets/commission_estimate.dart';
import '../../../core/services/commission_rates_service.dart';

class CableTVScreen extends StatefulWidget {
  final void Function(double newBalance) onBalanceUpdate;
  final String userId;

  const CableTVScreen({
    super.key,
    required this.onBalanceUpdate,
    required this.userId,
  });

  @override
  State<CableTVScreen> createState() => _CableTVScreenState();
}

class _CableTVScreenState extends State<CableTVScreen>
    with TickerProviderStateMixin {
  // Controllers
  final TextEditingController _smartCardController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _pinController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();

  // Focus Nodes
  final FocusNode _smartCardFocusNode = FocusNode();
  final FocusNode _phoneFocusNode = FocusNode();
  final FocusNode _pinFocusNode = FocusNode();
  final FocusNode _amountFocusNode = FocusNode();

  // State Variables
  String? _selectedProvider;
  String? _selectedPlan;
  String? _selectedPlanVariationCode;
  String? _customerName;
  Map<String, dynamic>? _smartcardDetails;
  final bool _isLoading = false;
  final bool _isAuthenticating = false;
  bool _isValidating = false;
  bool _isValidated = false;
  bool _isLoadingPlans = false;
  bool _isBalanceVisible = true;
  double _walletBalance = 0.0;

  // Validation Response Data
  String? _currentBouquet;
  String? _currentBouquetCode;
  String? _renewalAmount;
  String? _dueDate;

  // Action Selection
  String? _selectedAction;
  final List<String> _actionOptions = [
    'Renew Current Bouquet',
    'Change Bouquet',
  ];

  // Quantity & Amount
  int _quantity = 1;
  bool _isAmountEditable = true;
  double _calculatedTotal = 0.0;

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
  final bool _cableServiceEnabled = true;
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

  // Provider list with logos
  final List<Map<String, dynamic>> _providers = [
    {
      'id': 'dstv',
      'name': 'DSTV',
      'fullName': 'DStv',
      'logo':
          'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcSqeMEueUKcIRTxBWIy3nD1Gi4cyEgZZQqUjsQQ18BSbA&s=10',
      'color': const Color(0xFFE91E63),
    },
    {
      'id': 'gotv',
      'name': 'GOtv',
      'fullName': 'GOtv',
      'logo':
          'https://res.cloudinary.com/paybeta/images/w_300,h_150,dpr_2/f_auto,q_auto/v1689688193/PaybetaBlogAssets/gotv_subscription_akyq5m/gotv_subscription_akyq5m.webp?_i=AA',
      'color': const Color(0xFF4CAF50),
    },
    {
      'id': 'startimes',
      'name': 'StarTimes',
      'fullName': 'StarTimes',
      'logo':
          'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcSb9fjfle26ReF55p8P0f14IjZkg3Y-xToun3qIUxna-A&s=10',
      'color': const Color(0xFFA76B1D),
    },
  ];

  // Data Plans storage
  final Map<String, List<Map<String, dynamic>>> _cablePlans = {};
  String? _selectedPlanAmount;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _initializeData();
    _fetchSecuritySettings();
    _loadWalletBalance();
    _phoneController.text = '';
    // Add listener for live validation
    _smartCardController.addListener(_onSmartCardChanged);
  }

  void _onSmartCardChanged() {
    // Update validation button state live
    setState(() {});
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
      // Silent fail - keep existing balance
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
    _smartCardController.removeListener(_onSmartCardChanged);
    _fadeController.dispose();
    _sheetController.dispose();
    _shakeController.dispose();
    _smartCardController.dispose();
    _phoneController.dispose();
    _pinController.dispose();
    _amountController.dispose();
    _smartCardFocusNode.dispose();
    _phoneFocusNode.dispose();
    _pinFocusNode.dispose();
    _amountFocusNode.dispose();
    super.dispose();
  }

  String? _validateForm() {
    if (_selectedProvider == null) {
      return 'Please select a cable provider';
    }

    final smartCard = _smartCardController.text.trim();
    if (smartCard.isEmpty) {
      return 'Please enter your smart card number';
    }
    if (smartCard.length < 10 || smartCard.length > 11) {
      return 'Smart card number must be 10-11 digits';
    }
    if (!RegExp(r'^[0-9]+$').hasMatch(smartCard)) {
      return 'Smart card number must contain only digits';
    }

    if (!_isValidated) {
      return 'Please validate your smart card first';
    }

    if (_selectedAction == null) {
      return 'Please select what you want to do (Renew or Change)';
    }

    if (_selectedPlan == null && _selectedAction == 'change') {
      return 'Please select a subscription plan to change to';
    }

    // Validate amount
    final amountText = _amountController.text.trim();
    if (amountText.isEmpty) {
      return 'Please enter the amount';
    }
    final amount = double.tryParse(amountText);
    if (amount == null || amount <= 0) {
      return 'Please enter a valid amount';
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
    } else if (errorStr.contains('Invalid smart card') ||
        errorStr.contains('WrongBillersCode')) {
      return 'Invalid smart card number. Please check and try again.';
    } else if (errorStr.contains('AMOUNT_MISMATCH')) {
      return 'Amount mismatch detected. Please pay the exact package amount.';
    } else if (errorStr.contains('429') ||
        errorStr.contains('Too many requests')) {
      return 'Too many attempts. Please wait 5–10 minutes before trying again.';
    }
    return errorStr.length > 100 ? 'An unexpected error occurred.' : errorStr;
  }

  Future<void> _fetchCablePlans(String providerId) async {
    if (_isLoadingPlans) return;

    setState(() => _isLoadingPlans = true);

    try {
      final result = await ApiService.getCableVariationsForProvider(providerId);

      if (result['success'] == true || result['variations'] != null) {
        final plans = List<Map<String, dynamic>>.from(
          result['variations'] ?? [],
        );

        plans.sort((a, b) {
          final amountA =
              double.tryParse(a['variation_amount']?.toString() ?? '0') ?? 0;
          final amountB =
              double.tryParse(b['variation_amount']?.toString() ?? '0') ?? 0;
          return amountA.compareTo(amountB);
        });

        setState(() {
          _cablePlans[providerId] = plans;
          _selectedPlan = null;
          _selectedPlanAmount = null;
          _selectedPlanVariationCode = null;
        });
      } else {
        _loadMockCablePlans(providerId);
      }
    } catch (e) {
      _loadMockCablePlans(providerId);
    } finally {
      setState(() => _isLoadingPlans = false);
    }
  }

  void _log(String message) {
    if (kDebugMode) {
      debugPrint('📺 CABLE TV: $message');
    }
  }

  void _loadMockCablePlans(String providerId) {
    final mockPlans = <Map<String, dynamic>>[];

    switch (providerId) {
      case 'dstv':
        mockPlans.addAll([
          {
            'name': 'DStv Padi',
            'variation_code': 'dstv-padi',
            'variation_amount': '1850.00',
            'fixedPrice': true,
          },
          {
            'name': 'DStv Yanga',
            'variation_code': 'dstv-yanga',
            'variation_amount': '2565.00',
            'fixedPrice': true,
          },
          {
            'name': 'DStv Confam',
            'variation_code': 'dstv-confam',
            'variation_amount': '4615.00',
            'fixedPrice': true,
          },
          {
            'name': 'DStv Compact',
            'variation_code': 'dstv79',
            'variation_amount': '7900.00',
            'fixedPrice': true,
          },
          {
            'name': 'DStv Premium',
            'variation_code': 'dstv3',
            'variation_amount': '18400.00',
            'fixedPrice': true,
          },
          {
            'name': 'DStv Compact Plus',
            'variation_code': 'dstv7',
            'variation_amount': '12400.00',
            'fixedPrice': true,
          },
        ]);
        break;
      case 'gotv':
        mockPlans.addAll([
          {
            'name': 'GOtv Lite',
            'variation_code': 'gotv-lite',
            'variation_amount': '410.00',
            'fixedPrice': true,
          },
          {
            'name': 'GOtv Jinja',
            'variation_code': 'gotv-jinja',
            'variation_amount': '1640.00',
            'fixedPrice': true,
          },
          {
            'name': 'GOtv Jolli',
            'variation_code': 'gotv-jolli',
            'variation_amount': '2460.00',
            'fixedPrice': true,
          },
          {
            'name': 'GOtv Max',
            'variation_code': 'gotv-max',
            'variation_amount': '3600.00',
            'fixedPrice': true,
          },
          {
            'name': 'GOtv Supa Plus',
            'variation_code': 'gotv-supa-plus',
            'variation_amount': '15700.00',
            'fixedPrice': true,
          },
        ]);
        break;
      case 'startimes':
        mockPlans.addAll([
          {
            'name': 'Nova - 1 Month',
            'variation_code': 'nova',
            'variation_amount': '900.00',
            'fixedPrice': true,
          },
          {
            'name': 'Basic - 1 Month',
            'variation_code': 'basic',
            'variation_amount': '1700.00',
            'fixedPrice': true,
          },
          {
            'name': 'Smart - 1 Month',
            'variation_code': 'smart',
            'variation_amount': '2200.00',
            'fixedPrice': true,
          },
          {
            'name': 'Classic - 1 Month',
            'variation_code': 'classic',
            'variation_amount': '2500.00',
            'fixedPrice': true,
          },
          {
            'name': 'Super - 1 Month',
            'variation_code': 'super',
            'variation_amount': '4200.00',
            'fixedPrice': true,
          },
        ]);
        break;
    }

    setState(() {
      _cablePlans[providerId] = mockPlans;
      _selectedPlan = null;
      _selectedPlanAmount = null;
      _selectedPlanVariationCode = null;
    });
  }

  // ==================== VALIDATE SMART CARD ====================

  Future<void> _validateSmartCard() async {
    if (_selectedProvider == null) {
      _showErrorDialog('Provider Required', 'Please select a cable provider.');
      return;
    }

    final smartCard = _smartCardController.text.trim();
    if (smartCard.isEmpty) {
      _showErrorDialog(
        'Invalid Smart Card',
        'Please enter your smart card number.',
      );
      return;
    }
    if (smartCard.length < 10 || smartCard.length > 11) {
      _showErrorDialog(
        'Invalid Smart Card',
        'Smart card number must be 10-11 digits.',
      );
      return;
    }
    if (!RegExp(r'^[0-9]+$').hasMatch(smartCard)) {
      _showErrorDialog(
        'Invalid Smart Card',
        'Smart card number must contain only digits.',
      );
      return;
    }

    setState(() {
      _isValidating = true;
      _isValidated = false;
      _customerName = null;
      _currentBouquet = null;
      _currentBouquetCode = null;
      _renewalAmount = null;
      _dueDate = null;
      _selectedAction = null;
      _selectedPlan = null;
      _amountController.clear();
    });

    try {
      final result = await ApiService.validateCableSmartCard(
        billersCode: smartCard,
        serviceID: _selectedProvider!,
      );

      _log('📦 Validation result: ${jsonEncode(result)}');

      if (result['success'] == true) {
        final customerName = result['customerName'] ?? 'Unknown';
        final smartcardNumber = result['smartcardNumber'] ?? smartCard;
        final service = result['service'] ?? _selectedProvider!;

        final content = result['content'] as Map<String, dynamic>? ?? {};
        final details = result['details'] as Map<String, dynamic>? ?? {};

        final currentBouquet =
            content['Current_Bouquet']?.toString() ??
            details['Current_Bouquet']?.toString() ??
            result['currentBouquet'] ??
            'N/A';

        final renewalAmount =
            content['Renewal_Amount']?.toString() ??
            details['Renewal_Amount']?.toString() ??
            '0';

        final dueDate =
            content['Due_Date']?.toString() ??
            details['Due_Date']?.toString() ??
            'N/A';

        final currentBouquetCode = _mapBouquetToVariationCode(
          currentBouquet,
          _selectedProvider!,
        );

        _log('✅ Smart card validated successfully');
        _log('👤 Customer Name: $customerName');
        _log('📺 Current Bouquet: $currentBouquet');
        _log('🔄 Renewal Amount: ₦$renewalAmount');
        _log('📅 Due Date: $dueDate');
        _log('🆔 Bouquet Code: $currentBouquetCode');

        setState(() {
          _isValidated = true;
          _customerName = customerName;
          _currentBouquet = currentBouquet;
          _currentBouquetCode = currentBouquetCode;
          _renewalAmount = renewalAmount;
          _dueDate = dueDate;
          _smartcardDetails = {
            'Customer Name': customerName,
            'Smartcard Number': smartcardNumber,
            'Service': service,
            'Current Bouquet': currentBouquet,
            'Renewal Amount': renewalAmount,
            'Due Date': dueDate,
            'Bouquet Code': currentBouquetCode,
            'Raw Response': result,
          };
          _amountController.text = renewalAmount;
          _isAmountEditable = true;
          _selectedAction = null;
        });

        _showValidationSuccessDialog(
          customerName,
          smartcardNumber,
          currentBouquet,
          renewalAmount,
          dueDate,
          service,
          currentBouquetCode,
        );
      } else {
        final errorMsg = result['message'] ?? 'Unable to validate smart card.';
        _showErrorDialog('Validation Failed', errorMsg);
      }
    } catch (e) {
      String errorMessage = e.toString().replaceAll('Exception: ', '');

      // ✅ REMOVED rate limit handling (429/Too many requests) for validation
      if (errorMessage.contains('Invalid smart card') ||
          errorMessage.contains('WrongBillersCode')) {
        _showErrorDialog(
          'Invalid Smart Card',
          'The smart card number you entered appears to be invalid.\n\nPlease check and try again.',
        );
      } else {
        _showErrorDialog('Validation Error', errorMessage);
      }
    } finally {
      setState(() => _isValidating = false);
    }
  }

  String _mapBouquetToVariationCode(String bouquetName, String serviceID) {
    final normalized = bouquetName.toLowerCase().trim();

    if (serviceID == 'dstv' || serviceID == 'DStv' || serviceID == 'DSTV') {
      final dstvMappings = {
        'padi': 'dstv-padi',
        'yanga': 'dstv-yanga',
        'confam': 'dstv-confam',
        'compact': 'dstv79',
        'compact plus': 'dstv7',
        'compact+': 'dstv7',
        'premium': 'dstv3',
        'compact extra': 'dstv7',
        'extra view': 'dstv7',
      };
      for (final entry in dstvMappings.entries) {
        if (normalized.contains(entry.key)) {
          return entry.value;
        }
      }
    }

    if (serviceID == 'gotv' || serviceID == 'GOtv' || serviceID == 'GOTV') {
      final gotvMappings = {
        'lite': 'gotv-lite',
        'jinja': 'gotv-jinja',
        'jolli': 'gotv-jolli',
        'max': 'gotv-max',
        'supa plus': 'gotv-supa-plus',
      };
      for (final entry in gotvMappings.entries) {
        if (normalized.contains(entry.key)) {
          return entry.value;
        }
      }
    }

    if (serviceID == 'startimes' ||
        serviceID == 'StarTimes' ||
        serviceID == 'STARTIMES') {
      final startimesMappings = {
        'nova': 'nova',
        'basic': 'basic',
        'smart': 'smart',
        'classic': 'classic',
        'super': 'super',
      };
      for (final entry in startimesMappings.entries) {
        if (normalized.contains(entry.key)) {
          return entry.value;
        }
      }
    }

    return normalized.replaceAll(' ', '-').toLowerCase();
  }

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

  void _showValidationSuccessDialog(
    String customerName,
    String smartcardNumber,
    String currentBouquet,
    String renewalAmount,
    String dueDate,
    String service,
    String bouquetCode,
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
              width: MediaQuery.of(context).size.width * 0.92,
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
                    'Smart Card Validated!',
                    style: GoogleFonts.inter(
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
                      style: GoogleFonts.inter(
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
                  const SizedBox(height: 8),
                  _buildDetailRow('Smartcard Number', smartcardNumber),
                  const SizedBox(height: 8),
                  _buildDetailRow('Current Package', currentBouquet),
                  const SizedBox(height: 8),
                  _buildDetailRow(
                    'Renewal Amount',
                    '₦${double.tryParse(renewalAmount)?.toStringAsFixed(2) ?? renewalAmount}',
                  ),
                  const SizedBox(height: 8),
                  _buildDetailRow('Due Date', _formatDate(dueDate)),
                  const SizedBox(height: 8),
                  _buildDetailRow('Service', service.toUpperCase()),
                  if (bouquetCode != 'N/A') ...[
                    const SizedBox(height: 8),
                    _buildDetailRow('Package Code', bouquetCode),
                  ],
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
                            'Smart card verified. You can now renew or change your package.',
                            style: GoogleFonts.inter(
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
                              _isValidated = false;
                              _customerName = null;
                              _smartcardDetails = null;
                              _currentBouquet = null;
                              _currentBouquetCode = null;
                              _renewalAmount = null;
                              _dueDate = null;
                              _selectedAction = null;
                              _amountController.clear();
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
                            style: GoogleFonts.inter(
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
                            'Proceed',
                            style: GoogleFonts.inter(
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
          width: 130,
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: GoogleFonts.inter(
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

  String _formatDate(String dateStr) {
    if (dateStr == 'N/A') return dateStr;
    try {
      final date = DateTime.parse(dateStr);
      return DateFormat('MMM dd, yyyy').format(date);
    } catch (e) {
      return dateStr;
    }
  }

  // ==================== ACTION SELECTION ====================

  Widget _buildActionSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'What do you want to do?',
          style: GoogleFonts.inter(
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
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedAction,
              isExpanded: true,
              hint: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'Select what to do',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: _hintColor,
                  ),
                ),
              ),
              icon: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: HugeIcon(
                  icon: HugeIcons.strokeRoundedArrowDown01,
                  color: Colors.grey,
                  size: 18,
                ),
              ),
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade800,
              ),
              items:
                  _actionOptions.map((option) {
                    return DropdownMenuItem<String>(
                      value:
                          option == 'Renew Current Bouquet'
                              ? 'renew'
                              : 'change',
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(option),
                      ),
                    );
                  }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedAction = value;
                  _selectedPlan = null;
                  _selectedPlanAmount = null;
                  _selectedPlanVariationCode = null;
                  _quantity = 1;

                  if (value == 'renew') {
                    _isAmountEditable = true;
                    _amountController.text = _renewalAmount ?? '0';
                  } else {
                    _isAmountEditable = false;
                    _amountController.clear();
                  }
                });
              },
            ),
          ),
        ),
      ],
    );
  }

  // ==================== AMOUNT INPUT ====================

  Widget _buildAmountInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Amount',
              style: GoogleFonts.inter(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: _primary,
              ),
            ),
            if (_selectedAction == 'renew')
              Text(
                'Renewal Amount',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _secondary,
                ),
              ),
            if (_selectedAction == 'change')
              Text(
                'Fixed Price',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.orange.shade700,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color:
                _selectedAction == 'change'
                    ? Colors.grey.shade100
                    : Colors.grey.shade50,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color:
                  _selectedAction == 'change'
                      ? Colors.orange.shade200
                      : Colors.grey.shade200,
            ),
          ),
          child: TextField(
            controller: _amountController,
            focusNode: _amountFocusNode,
            enabled: _selectedAction == 'renew',
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            decoration: InputDecoration(
              hintText:
                  _selectedAction == 'renew'
                      ? 'Enter amount to pay'
                      : 'Amount is fixed for package change',
              hintStyle: GoogleFonts.inter(
                color:
                    _selectedAction == 'change'
                        ? Colors.grey.shade500
                        : _hintColor,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              prefixIcon: Container(
                padding: const EdgeInsets.all(12),
                child: HugeIcon(
                  icon: HugeIcons.strokeRoundedMoney01,
                  color:
                      _selectedAction == 'change'
                          ? Colors.orange.shade700
                          : _primary,
                  size: 22,
                ),
              ),
              suffixIcon:
                  _selectedAction == 'change'
                      ? Container(
                        margin: const EdgeInsets.all(8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'FIXED',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: Colors.orange.shade700,
                          ),
                        ),
                      )
                      : null,
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
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight:
                  _selectedAction == 'change'
                      ? FontWeight.w800
                      : FontWeight.w600,
              color:
                  _selectedAction == 'change'
                      ? Colors.orange.shade800
                      : Colors.grey.shade900,
            ),
            onChanged: (value) {
              if (_selectedAction == 'renew') {
                final amount = double.tryParse(value) ?? 0;
                setState(() {
                  _calculatedTotal = amount * _quantity;
                });
              }
            },
          ),
        ),
        if (_selectedAction == 'renew')
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                HugeIcon(
                  icon: HugeIcons.strokeRoundedInformationCircle,
                  color: Colors.blue.shade700,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'You can adjust the amount. Total: ₦${(_calculatedTotal > 0 ? _calculatedTotal : double.tryParse(_amountController.text) ?? 0).toStringAsFixed(2)}',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.blue.shade800,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ==================== QUANTITY SELECTOR ====================

  Widget _buildQuantitySelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Months',
              style: GoogleFonts.inter(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: _primary,
              ),
            ),
            Text(
              'Total: ₦${((double.tryParse(_amountController.text) ?? 0) * _quantity).toStringAsFixed(2)}',
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: _secondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            GestureDetector(
              onTap: () {
                if (_quantity > 1) {
                  setState(() {
                    _quantity--;
                  });
                }
              },
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: HugeIcon(
                  icon: HugeIcons.strokeRoundedMinusSign,
                  color: _quantity > 1 ? _primary : Colors.grey.shade400,
                  size: 20,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Text(
              '$_quantity',
              style: GoogleFonts.inter(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: _primary,
              ),
            ),
            const SizedBox(width: 16),
            GestureDetector(
              onTap: () {
                if (_quantity < 12) {
                  setState(() {
                    _quantity++;
                  });
                }
              },
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: HugeIcon(
                  icon: HugeIcons.strokeRoundedAdd01,
                  color: _quantity < 12 ? _primary : Colors.grey.shade400,
                  size: 20,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: _secondary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Max 12 months',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _secondary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ==================== PLAN SELECTION ====================

  Widget _buildPlanSection() {
    final plans = _cablePlans[_selectedProvider] ?? [];

    if (_selectedAction != 'change') {
      return const SizedBox.shrink();
    }

    if (_isLoadingPlans) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Select New Package',
            style: GoogleFonts.inter(
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
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF102C68)),
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
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade700,
              ),
            ),
            Text(
              'Please try another provider',
              style: GoogleFonts.inter(
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
          'Select New Package',
          style: GoogleFonts.inter(
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
              final isCurrentPackage =
                  plan['variation_code'] == _currentBouquetCode;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: _buildPlanCard(plan, isSelected, isCurrentPackage),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPlanCard(
    Map<String, dynamic> plan,
    bool isSelected,
    bool isCurrentPackage,
  ) {
    final amount = plan['variation_amount']?.toString() ?? '0.00';
    final name = plan['name']?.toString() ?? 'Unknown Plan';
    final variationCode = plan['variation_code']?.toString() ?? '';

    return GestureDetector(
      onTap: () {
        if (isCurrentPackage) {
          _showErrorDialog(
            'Same Package',
            'You are already on this package. Please select a different package to change to.',
          );
          return;
        }
        setState(() {
          _selectedPlan = name;
          _selectedPlanAmount = amount;
          _selectedPlanVariationCode = variationCode;
          _quantity = 1;
          _amountController.text = amount;
          _isAmountEditable = false;
          _calculatedTotal = double.tryParse(amount) ?? 0;
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
              child: Row(
                children: [
                  if (isCurrentPackage)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green.shade100,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'CURRENT',
                        style: GoogleFonts.inter(
                          fontSize: 8,
                          fontWeight: FontWeight.w800,
                          color: Colors.green.shade800,
                        ),
                      ),
                    ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      name,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: isSelected ? Colors.white : _primary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
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
                style: GoogleFonts.inter(
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

  // ==================== PACKAGE CHANGE CONFIRMATION ====================

  Future<bool?> _showPackageChangeConfirmation({
    required String currentPackage,
    required String newPackage,
    required double totalAmount,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
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
                    color: Colors.orange.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: HugeIcon(
                    icon: HugeIcons.strokeRoundedRefresh01,
                    color: Colors.orange.shade700,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Package Change',
                  style: GoogleFonts.inter(
                    color: _primary,
                    fontWeight: FontWeight.w800,
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
                  'You are changing your subscription package:',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Current Package',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            Text(
                              currentPackage,
                              style: GoogleFonts.inter(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: Colors.grey.shade800,
                              ),
                            ),
                          ],
                        ),
                      ),
                      HugeIcon(
                        icon: HugeIcons.strokeRoundedArrowRight01,
                        color: _primary,
                        size: 24,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'New Package',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            Text(
                              newPackage,
                              style: GoogleFonts.inter(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: _secondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Row(
                    children: [
                      HugeIcon(
                        icon: HugeIcons.strokeRoundedInformationCircle,
                        color: Colors.blue.shade700,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Package changes require the exact amount of ₦${totalAmount.toStringAsFixed(2)}.',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.blue.shade800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Row(
                    children: [
                      HugeIcon(
                        icon: HugeIcons.strokeRoundedAlert02,
                        color: Colors.orange.shade700,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'This action cannot be undone. Your subscription will be changed immediately.',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.orange.shade800,
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
                onPressed: () => Navigator.pop(context, false),
                child: Text(
                  'Cancel',
                  style: GoogleFonts.inter(
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  'Confirm Change',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
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

    // Check if this is a package change
    final bool isPackageChange = _selectedAction == 'change';

    if (isPackageChange && _selectedPlan == null) {
      _showErrorDialog(
        'No Plan Selected',
        'Please select a package to change to.',
      );
      return;
    }

    // Show package change confirmation if changing
    if (isPackageChange) {
      _showPackageChangeConfirmation(
        currentPackage: _currentBouquet ?? 'N/A',
        newPackage: _selectedPlan ?? 'N/A',
        totalAmount: double.tryParse(_amountController.text) ?? 0,
      ).then((confirmed) {
        if (confirmed == true) {
          _showPaymentSheetInternal();
        }
      });
    } else {
      _showPaymentSheetInternal();
    }
  }

  void _showPaymentSheetInternal() {
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

  // ==================== EXECUTE TRANSACTION ====================

  // ==================== EXECUTE TRANSACTION WITH LIMIT HANDLING ====================

  Future<void> _executeTransaction() async {
    final provider = _selectedProvider!;
    final smartCard = _smartCardController.text.trim();
    final phone = _phoneController.text.trim();
    final amount = double.tryParse(_amountController.text.trim()) ?? 0;
    final isPackageChange = _selectedAction == 'change';

    final variationCode =
        isPackageChange
            ? _selectedPlanVariationCode ?? ''
            : _currentBouquetCode ?? '';

    if (variationCode.isEmpty) {
      _showErrorDialog(
        'Invalid Package',
        isPackageChange
            ? 'Please select a package to change to.'
            : 'No current package found.',
      );
      _closePaymentSheet();
      return;
    }

    if (amount <= 0) {
      _showErrorDialog('Invalid Amount', 'Please enter a valid amount.');
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

    _log('📺 Executing payment:');
    _log('   Action: $_selectedAction');
    _log('   Provider: $provider');
    _log('   Smart Card: $smartCard');
    _log('   Variation: $variationCode');
    _log('   Amount: $amount');
    _log('   Quantity: $_quantity');
    _log('   Phone: $phone');
    _log('   Package Change: $isPackageChange');

    try {
      // If biometric was selected, authenticate
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

      // ✅ Pass all parameters correctly to makeCablePayment
      final result = await ApiService.makeCablePayment(
        userId: widget.userId,
        serviceID: provider,
        billersCode: smartCard,
        variationCode: variationCode,
        amount: amount,
        phone: phone,
        transactionPin: _useBiometric ? null : _pinController.text.trim(),
        useBiometric: _useBiometric,
        currentPackage: _currentBouquetCode,
        quantity: _quantity,
        action: isPackageChange ? 'change' : 'renew',
        subscriptionType: isPackageChange ? 'change' : 'renew',
      );

      _log('📦 Payment result: ${jsonEncode(result)}');

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
          smartCard: smartCard,
          phone: phone,
          amount: amount,
          result: result,
          isPackageChange: isPackageChange,
          quantity: _quantity,
        );
        _clearForm();
      } else {
        final errorMsg =
            result['vtpassResponse']?['response_description'] ??
            result['message'] ??
            'Transaction failed. Please try again.';
        setState(() {
          _isProcessingPayment = false;
        });

        // ✅ CHECK FOR LIMIT ERRORS
        final errorCode = result['code']?.toString() ?? '';

        if (errorCode == 'PER_TRANSACTION_LIMIT_EXCEEDED' ||
            errorCode == 'DAILY_LIMIT_EXCEEDED' ||
            errorMsg.contains('PER_TRANSACTION_LIMIT_EXCEEDED') ||
            errorMsg.contains('DAILY_LIMIT_EXCEEDED')) {
          // ✅ FIXED: Properly extract limit info with safe type conversion
          final limitValue = result['limit'];
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
          final service = 'cable';

          _showLimitIncreaseDialog(
            service: service,
            limitType: isDaily ? 'dailyCap' : 'perTransaction',
            currentLimit: limit,
            requestedAmount: requested,
          );
          return;
        }

        if (errorMsg.contains('AMOUNT_MISMATCH') ||
            errorMsg.contains('exact amount')) {
          _showErrorDialog('Amount Mismatch', errorMsg);
        } else {
          _showErrorDialog('Purchase Failed', errorMsg);
        }
      }
    } catch (e) {
      setState(() {
        _isProcessingPayment = false;
      });

      final errorStr = e.toString().replaceAll('Exception: ', '');

      // ✅ CHECK FOR LIMIT ERRORS IN CATCH BLOCK TOO
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
          service: 'cable',
          limitType: isDaily ? 'dailyCap' : 'perTransaction',
          currentLimit: limit,
          requestedAmount: amount,
        );
        return;
      }

      if (errorStr.contains('VTpass') || errorStr.contains('vtpass')) {
        _showErrorDialog(
          'Service Error',
          'The service provider returned an error. Please try again later.',
        );
      } else if (errorStr.contains('wallet was debited')) {
        _showErrorDialog(
          'Payment Recorded ⚠️',
          '$errorStr\n\nPlease contact support if service was not delivered.',
        );
      } else if (errorStr.contains('invalid smartcard') ||
          errorStr.contains('INVALID BILLERS')) {
        _showErrorDialog(
          'Invalid Smartcard',
          'The smartcard number you entered appears to be invalid. Please check and try again.',
        );
      } else if (errorStr.contains('DUPLICATE')) {
        _showErrorDialog(
          'Already Processed',
          'This transaction was already processed. Please check your subscription status.',
        );
      } else if (errorStr.contains('LOW WALLET BALANCE') ||
          errorStr.contains('insufficient funds')) {
        _showErrorDialog(
          'Service Issue ⚠️',
          'Your payment has been recorded. The service will be delivered when provider issues are resolved.',
        );
      } else {
        _showErrorDialog('Purchase Failed', _mapExceptionToUserMessage(e));
      }
    }
  }

  // ==================== PROCESS PAYMENT ====================

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
        // ✅ Trigger shake animation on error
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

  void _clearForm() {
    _smartCardController.clear();
    _pinController.clear();
    _amountController.clear();
    setState(() {
      _selectedPlan = null;
      _selectedPlanAmount = null;
      _selectedPlanVariationCode = null;
      _useBiometric = false;
      _pinValidationError = null;
      _isValidated = false;
      _customerName = null;
      _smartcardDetails = null;
      _currentBouquet = null;
      _currentBouquetCode = null;
      _renewalAmount = null;
      _dueDate = null;
      _selectedAction = null;
      _quantity = 1;
      _isAmountEditable = true;
      _calculatedTotal = 0;
    });
  }

  // ==================== PAYMENT SHEET OVERLAY ====================

  Widget _buildPaymentSheetOverlay() {
    final amount = double.tryParse(_amountController.text.trim()) ?? 0;
    final total = amount * _quantity;
    String providerName = '';
    for (final p in _providers) {
      if (p['id'] == _selectedProvider) {
        providerName = (p['fullName'] ?? p['name'] ?? '').toString();
      }
    }
    final isChange = _selectedAction == 'change';
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
            icon: DPIcons.tv,
            title: providerName,
            amount: total,
            rows: [
              DPReviewRow('Customer', _customerName ?? '—'),
              DPReviewRow('Smartcard', _smartCardController.text.trim()),
              DPReviewRow(
                isChange ? 'New package' : 'Package',
                (isChange ? _selectedPlan : _currentBouquet) ?? '—',
              ),
              DPReviewRow('Action', isChange ? 'Change package' : 'Renew'),
              if (_quantity > 1) ...[
                DPReviewRow('Price per month', DP.naira(amount)),
                DPReviewRow('Months', '$_quantity'),
              ],
              DPReviewRow('Total to pay', DP.naira(total), strong: true),
            ],
            walletBalance: _walletBalance,
            totalDebit: total,
            commission: CommissionRatesService.estimate('cable', total),
            pinController: _pinController,
            pinFocusNode: _pinFocusNode,
            pinRequired: _transactionPinSet && !_useBiometric,
            pinError: _pinValidationError,
            processing: _isProcessingPayment,
            onPay: () {
              setState(() => _useBiometric = false);
              _processPayment();
            },
            onClose: _closePaymentSheet,
            biometricAvailable: biometricOk,
            biometricLabel: 'biometrics',
            onBiometric: () {
              setState(() {
                _useBiometric = true;
                _pinValidationError = null;
              });
              _processPayment();
            },
            footnote: 'TV subscriptions can\'t be reversed once activated.',
          ),
        ),
      ),
    );
  }

  // ==================== PAYMENT SHEET DETAILS ====================

  // ==================== PAYMENT SHEET DETAILS ====================



  // ==================== PIN OPTION ====================


  // ==================== BIOMETRIC OPTION ====================


  // ==================== SUCCESS & ERROR DIALOGS ====================

  void _showSuccessDialog({
    required String smartCard,
    required String phone,
    required double amount,
    required Map<String, dynamic> result,
    bool isPackageChange = false,
    int quantity = 1,
  }) {
    final transactionId =
        result['transactionId'] ??
        'TXN_${DateTime.now().millisecondsSinceEpoch}';
    final reference = result['reference'] ?? transactionId;
    final providerName =
        _providers.firstWhere(
              (p) => p['id'] == _selectedProvider,
              orElse: () => {'name': 'Unknown'},
            )['fullName']
            as String;

    final String description =
        isPackageChange
            ? '$providerName - Package Change: ${_currentBouquet ?? 'N/A'} → ${_selectedPlan ?? 'N/A'}'
            : '$providerName - Renew: ${_currentBouquet ?? 'N/A'}${quantity > 1 ? ' × $quantity months' : ''}';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => Dialog(
            backgroundColor: Colors.transparent,
            elevation: 0,
            child: ReceiptWidget(
              transactionType:
                  isPackageChange
                      ? 'Cable TV Package Change'
                      : 'Cable TV Subscription Renewal',
              amount: amount.toStringAsFixed(2),
              status: 'completed',
              transactionId: transactionId,
              reference: reference.toString(),
              date: DateTime.now(),
              phoneNumber: phone,
              smartcardNumber: smartCard,
              description: description,
              customerName: _customerName ?? 'N/A',
              gateway: 'Dalabapay App',
              customMessage:
                  isPackageChange
                      ? 'Package changed successfully!'
                      : 'Subscription renewed successfully!',
              primaryColor: _primary,
              showWatermark: true,
              isCommission: false,
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

  // ==================== PROVIDER LOGO WIDGET ====================

  Widget _buildProviderLogo(
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
        icon: HugeIcons.strokeRoundedTv01,
        color: color,
        size: size * 0.5,
      ),
    );
  }

  // ==================== PROVIDER DROPDOWN ====================

  Widget _buildProviderDropdown() {
    Map<String, dynamic>? current;
    for (final p in _providers) {
      if (p['id'] == _selectedProvider) current = p;
    }
    return DPSelectField(
      value: current?['fullName']?.toString(),
      hint: 'Choose your provider',
      leading: const Icon(DPIcons.tv, color: DP.green, size: 20),
      onTap: () async {
        final picked = await dpPickFromList<Map<String, dynamic>>(
          context,
          title: 'TV provider',
          items: _providers,
          selected: current,
          labelOf: (x) => (x['fullName'] ?? x['name'] ?? '').toString(),
        );
        if (picked == null || !mounted) return;
        final value = picked['id'] as String;
        setState(() {
          _selectedProvider = value;
          _selectedPlan = null;
          _selectedPlanAmount = null;
          _selectedPlanVariationCode = null;
          _isValidated = false;
          _customerName = null;
          _currentBouquet = null;
          _currentBouquetCode = null;
          _renewalAmount = null;
          _dueDate = null;
          _selectedAction = null;
          _quantity = 1;
          _amountController.clear();
        });
        _fetchCablePlans(value);
      },
    );
  }

  // ==================== BUILD ====================

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
                    title: 'Cable TV',
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
        bottomNavigationBar: _showPaymentSheet
            ? null
            : DPBottomAction(
                child: DPButton(
                  label: 'Review TV payment',
                  icon: DPIcons.forward,
                  loading: _isLoading || _isAuthenticating,
                  onPressed: _openPaymentSheet,
                ),
              ),
      ),
    );
  }


  Widget _buildBody() {
    if (_isLoadingUserData) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!_isUserActive || !_cableServiceEnabled) {
      return _buildServiceUnavailable();
    }

    final smartCardText = _smartCardController.text.trim();
    final bool isSmartCardValidLength =
        smartCardText.length >= 10 && smartCardText.length <= 11;
    final bool canValidate =
        _selectedProvider != null && isSmartCardValidLength && !_isValidating;
    final amount = double.tryParse(_amountController.text.trim()) ?? 0;

    return FadeTransition(
      opacity: _fadeAnimation,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your shows, right on time. Renew or change your package.',
              style: DP.body.copyWith(color: DP.muted),
            ),
            const SizedBox(height: 20),
            const DPLabel('TV provider'),
            _buildProviderDropdown(),
            const SizedBox(height: 20),
            DPLabel(
              'Smartcard / IUC number',
              trailing: _isValidated
                  ? null
                  : DPTextLink(
                      label: _isValidating ? 'Checking…' : 'Verify',
                      color: canValidate ? DP.green : DP.faint,
                      onTap: canValidate ? _validateSmartCard : null,
                    ),
            ),
            DPField(
              controller: _smartCardController,
              focusNode: _smartCardFocusNode,
              hint: '10–11 digit number',
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(11),
              ],
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) {
                if (canValidate) _validateSmartCard();
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
                          if (_currentBouquet != null &&
                              _currentBouquet != 'N/A')
                            Text(
                              'Current: $_currentBouquet',
                              style: const TextStyle(
                                color: DP.green,
                                fontSize: 12.5,
                              ),
                            ),
                          if (_dueDate != null && _dueDate != 'N/A')
                            Text(
                              'Due: ${_formatDate(_dueDate!)}',
                              style: const TextStyle(
                                color: DP.green,
                                fontSize: 12.5,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (_isValidated) ...[
              const SizedBox(height: 20),
              _buildActionSelector(),
            ],
            if (_selectedAction == 'change') ...[
              const SizedBox(height: 16),
              _buildPlanSection(),
            ],
            if (_isValidated && _selectedAction != null) ...[
              const SizedBox(height: 16),
              _buildAmountInput(),
              const SizedBox(height: 16),
              _buildQuantitySelector(),
            ],
            const SizedBox(height: 20),
            const DPLabel('Phone number'),
            DPField(
              controller: _phoneController,
              focusNode: _phoneFocusNode,
              hint: '0803 456 7890',
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(11),
              ],
              suffix: const Icon(DPIcons.phone, color: DP.muted),
            ),
            const SizedBox(height: 20),
            WalletCommissionCard(
              walletBalance: _walletBalance,
              amount: amount * _quantity,
              service: 'cable',
              balanceVisible: _isBalanceVisible,
            ),
            const SizedBox(height: 14),
            const DPBanner(
              'Check the smartcard number before paying. Subscriptions can\'t be reversed once activated.',
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildServiceUnavailable() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: DPEmptyState(
          icon: DPIcons.tv,
          title: 'Cable TV is unavailable right now',
          message: 'Please try again in a little while.',
          actionLabel: 'Go back',
          onAction: () => Navigator.pop(context),
        ),
      ),
    );
  }
}
