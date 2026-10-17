// lib/presentation/screens/cabletv/cabletv_screen.dart
import 'dart:async';
import 'dart:convert' show jsonEncode;
import 'dart:io';
import 'package:flutter/foundation.dart';
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
      'color': const Color(0xFFFF9800),
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

  // Plans could not be loaded from the server. Made-up plans are no longer
  // shown (their codes don't exist at VTpass); the UI offers a retry instead.
  void _loadMockCablePlans(String providerId) {
    setState(() {
      _cablePlans[providerId] = [];
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
    dpSnack(context, 'Smartcard verified for ${customerName.toUpperCase()}', success: true);
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 110, child: Text(label, style: DPText.bodyMuted.copyWith(fontSize: 13))),
          Expanded(
            child: Text(value, textAlign: TextAlign.right, style: DPText.value.copyWith(fontSize: 13)),
          ),
        ],
      ),
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
    const values = ['renew', 'change'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const DPFieldLabel('What would you like to do?'),
        DPChipGrid(
          labels: const ['Renew current plan', 'Change plan'],
          columns: 2,
          selectedIndex: _selectedAction == null ? null : values.indexOf(_selectedAction!),
          onSelected: (i) {
            final value = values[i];
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
      ],
    );
  }

  // ==================== AMOUNT INPUT ====================

  Widget _buildAmountInput() {
    final isChange = _selectedAction == 'change';
    return DPField(
      label: 'Amount',
      labelTrailing: Text(
        isChange ? 'Fixed price' : 'Renewal amount',
        style: DPText.small.copyWith(color: isChange ? DP.warn : DP.green),
      ),
      controller: _amountController,
      focusNode: _amountFocusNode,
      enabled: !isChange,
      keyboardType: TextInputType.number,
      prefixText: '₦ ',
      hint: isChange ? 'Choose a plan above' : 'Enter amount to pay',
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
      ],
      onChanged: (value) {
        if (_selectedAction == 'renew') {
          final amount = double.tryParse(value) ?? 0;
          setState(() => _calculatedTotal = amount * _quantity);
        }
      },
    );
  }

  // ==================== QUANTITY SELECTOR ====================

  Widget _buildQuantitySelector() {
    final total = (double.tryParse(_amountController.text) ?? 0) * _quantity;
    Widget stepBtn(DPIconData icon, bool enabled, VoidCallback onTap) => Material(
          color: DP.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DP.rMd),
            side: const BorderSide(color: DP.border),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(DP.rMd),
            onTap: enabled ? onTap : null,
            child: SizedBox(
              width: 46,
              height: 46,
              child: Center(child: DPIcon(icon, size: 20, color: enabled ? DP.ink : DP.faint)),
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const DPFieldLabel('Months'),
          Row(
            children: [
              stepBtn(DPIcons.minus, _quantity > 1, () => setState(() => _quantity--)),
              SizedBox(
                width: 56,
                child: Text('$_quantity',
                    textAlign: TextAlign.center, style: DPText.title.copyWith(fontSize: 22)),
              ),
              stepBtn(DPIcons.plus, _quantity < 12, () => setState(() => _quantity++)),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('Total', style: DPText.small),
                  Text(dpNaira(total), style: DPText.value.copyWith(color: DP.green, fontSize: 16)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text('Up to 12 months at a time', style: DPText.small),
        ],
      ),
    );
  }

  // ==================== PLAN SELECTION ====================

  Widget _buildPlanSection() {
    final plans = _cablePlans[_selectedProvider] ?? [];
    if (_selectedAction != 'change') return const SizedBox.shrink();
    if (_isLoadingPlans) return const DPLoader(message: 'Loading plans…');
    if (plans.isEmpty) {
      return DPCard(
        child: DPEmptyState(
          icon: DPIcons.circleAlert,
          title: 'Couldn’t load plans',
          message: 'Check your connection and try again.',
          actionLabel: 'Retry',
          onAction: _selectedProvider == null ? null : () => _fetchCablePlans(_selectedProvider!),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const DPFieldLabel('Choose your new plan'),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 320),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: plans.length,
            itemBuilder: (context, index) {
              final plan = plans[index];
              return _buildPlanCard(
                plan,
                _selectedPlan == plan['name'],
                plan['variation_code'] == _currentBouquetCode,
              );
            },
          ),
        ),
        const SizedBox(height: 10),
      ],
    );
  }

  Widget _buildPlanCard(
    Map<String, dynamic> plan,
    bool isSelected,
    bool isCurrentPackage,
  ) {
    final amount = plan['variation_amount']?.toString() ?? '0.00';
    final name = plan['name']?.toString() ?? 'Unknown plan';
    final variationCode = plan['variation_code']?.toString() ?? '';
    return DPOptionRow(
      title: name,
      subtitle: isCurrentPackage ? 'Your current plan' : null,
      selected: isSelected,
      trailingText: dpNaira(double.tryParse(amount) ?? 0, decimals: false),
      onTap: () {
        if (isCurrentPackage) {
          _showErrorDialog(
            'Same plan',
            'You’re already on this plan. Choose a different one to change to.',
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
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 26, 22, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const DPIconBadge(icon: DPIcons.refreshCw, bg: DP.warnSoft, fg: DP.warn, size: 56, radius: 28),
              const SizedBox(height: 14),
              Text('Change your plan?', style: DPText.title.copyWith(fontWeight: FontWeight.w500)),
              const SizedBox(height: 14),
              DPSummaryCard(rows: [
                DPSummaryRow('Current plan', currentPackage),
                DPSummaryRow('New plan', newPackage, valueColor: DP.green),
                DPSummaryRow('Amount', dpNaira(totalAmount), emphasize: true),
              ]),
              const DPNotice(
                'Your subscription changes immediately and this can’t be undone.',
                kind: DPNoticeKind.warn,
                margin: EdgeInsets.only(bottom: 18),
              ),
              DPButton(label: 'Confirm change', onPressed: () => Navigator.pop(ctx, true)),
              const SizedBox(height: 10),
              DPButton.secondary(label: 'Cancel', onPressed: () => Navigator.pop(ctx, false)),
            ],
          ),
        ),
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
    final displayMsg = attemptsRemaining != null
        ? '$message ($attemptsRemaining ${attemptsRemaining == 1 ? 'attempt' : 'attempts'} remaining)'
        : message;
    dpSnack(context, displayMsg, error: true);
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
    final provider = _providers.firstWhere(
      (p) => p['id'] == _selectedProvider,
      orElse: () => {'fullName': 'TV'},
    );
    final unit = double.tryParse(_amountController.text) ?? 0;
    final total = unit * _quantity;
    final isChange = _selectedAction == 'change';
    final bool isBiometricSupported = Platform.isAndroid || Platform.isIOS;
    final canBiometric = isBiometricSupported && _biometricEnabled && _biometricAllowed;
    return DPSheetOverlay(
      animation: _sheetAnimation,
      onDismiss: _isProcessingPayment ? null : _closePaymentSheet,
      child: DPPaymentReview(
        icon: DPIcons.tv,
        serviceLabel: '${provider['fullName']} · ${isChange ? 'Change plan' : 'Renewal'}',
        amount: total,
        rows: [
          DPSummaryRow('Customer', _customerName ?? '—'),
          DPSummaryRow('Smartcard', _smartCardController.text.trim()),
          DPSummaryRow('Plan', isChange ? (_selectedPlan ?? '—') : (_currentBouquet ?? 'Current plan')),
          DPSummaryRow('Months', '$_quantity'),
          DPSummaryRow('Phone number', _phoneController.text.trim()),
          DPSummaryRow('Total to pay', dpNaira(total), emphasize: true),
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
          setState(() {
            _useBiometric = false;
            _pinValidationError = null;
          });
          _processPayment();
        },
        onPayWithBiometric: canBiometric
            ? () {
                setState(() {
                  _useBiometric = true;
                  _pinValidationError = null;
                  _pinController.clear();
                });
                _processPayment();
              }
            : null,
        onClose: _closePaymentSheet,
        footnote: 'Your subscription updates on the smartcard above and can’t be reversed.',
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
              primaryColor: DP.navy,
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

  // ==================== PROVIDER LOGO WIDGET ====================


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


  // ==================== PROVIDER DROPDOWN ====================

  Widget _buildProviderDropdown() {
    const values = ['dstv', 'gotv', 'startimes'];
    return DPChipGrid(
      labels: _providers.map((p) => p['fullName'] as String).toList(),
      columns: 3,
      selectedIndex: _selectedProvider == null ? null : values.indexOf(_selectedProvider!),
      onSelected: (i) {
        final value = _providers[i]['id'] as String;
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
    return Stack(
      children: [
        DPPage(
          title: 'Cable TV',
          actionLabel: 'History',
          onAction: () => Navigator.pushNamed(context, '/transactions'),
          bottom: _isLoadingUserData || !_isUserActive || !_cableServiceEnabled
              ? null
              : DPButton(
                  label: 'Review TV payment',
                  icon: DPIcons.arrowRight,
                  loading: _isLoading || _isAuthenticating,
                  onPressed: (_isLoading || _isAuthenticating) ? null : _openPaymentSheet,
                ),
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
    if (!_isUserActive || !_cableServiceEnabled) {
      return _buildServiceUnavailable();
    }
    final smartCardText = _smartCardController.text.trim();
    final bool isSmartCardValidLength = smartCardText.length >= 10 && smartCardText.length <= 11;
    final bool canValidate = _selectedProvider != null && isSmartCardValidLength && !_isValidating;

    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 18),
              child: Text('Keep the shows coming. Renew or change your plan.', style: DPText.bodyMuted),
            ),
            const DPFieldLabel('TV provider'),
            _buildProviderDropdown(),
            DPField(
              label: 'Smartcard / IUC number',
              labelTrailing: DPLinkButton(
                label: _isValidating ? 'Verifying…' : (_isValidated ? 'Verified' : 'Verify'),
                onPressed: canValidate ? _validateSmartCard : null,
                color: canValidate || _isValidated ? DP.green : DP.faint,
              ),
              controller: _smartCardController,
              focusNode: _smartCardFocusNode,
              keyboardType: TextInputType.number,
              hint: '1045 xxx 7890',
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(11),
              ],
              onChanged: (_) => setState(() {}),
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
                detail: [
                  if (_currentBouquet != null && _currentBouquet != 'N/A') 'Current: $_currentBouquet',
                  if (_dueDate != null && _dueDate != 'N/A') 'Due ${_formatDate(_dueDate!)}',
                ].join(' · '),
              ),
            if (_isValidated) _buildActionSelector(),
            if (_selectedAction == 'change') _buildPlanSection(),
            if (_isValidated && _selectedAction != null) _buildAmountInput(),
            if (_isValidated && _selectedAction != null) _buildQuantitySelector(),
            DPField(
              label: 'Phone number',
              controller: _phoneController,
              focusNode: _phoneFocusNode,
              keyboardType: TextInputType.phone,
              hint: '0803 456 7890',
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(11),
              ],
              suffixIcon: DPIcons.phone,
            ),
            DPSummaryCard(rows: [
              DPSummaryRow('Wallet balance', _isBalanceVisible ? dpNaira(_walletBalance) : '₦ ••••'),
              DPSummaryRow(
                'Total to pay',
                dpNaira((double.tryParse(_amountController.text) ?? 0) * _quantity),
                emphasize: true,
              ),
            ]),
            const DPNotice('Please confirm the details above before you continue.', margin: EdgeInsets.zero),
          ],
        ),
      ),
    );
  }


  Widget _buildServiceUnavailable() {
    return const DPServiceUnavailable(
      message: 'Cable TV payments are currently unavailable. Please try again later.',
    );
  }
}
