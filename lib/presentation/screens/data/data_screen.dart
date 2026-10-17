// lib/presentation/screens/data/data_screen.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/services/api_service.dart';
import '../../../core/widgets/receipt_widget.dart';
import '../../../ui/ui.dart';

class DataScreen extends StatefulWidget {
  final void Function(double newBalance) onBalanceUpdate;
  final String userId;

  const DataScreen({
    super.key,
    required this.onBalanceUpdate,
    required this.userId,
  });

  @override
  State<DataScreen> createState() => _DataScreenState();
}

class _DataScreenState extends State<DataScreen> with TickerProviderStateMixin {
  // Controllers
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _pinController = TextEditingController();

  // Focus Nodes
  final FocusNode _phoneFocusNode = FocusNode();
  final FocusNode _pinFocusNode = FocusNode();

  // State Variables
  String? _selectedNetwork;
  String? _selectedPlan;
  final bool _isLoading = false;
  final bool _isAuthenticating = false;
  bool _isLoadingPlans = false;
  bool _isBalanceVisible = true;
  double _walletBalance = 0.0;

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
  final bool _dataServiceEnabled = true;
  bool _isUserActive = true;
  bool _isLoadingUserData = true;

  // Animation
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late AnimationController _sheetController;
  late Animation<double> _sheetAnimation;

  // Payment Sheet State
  bool _showPaymentSheet = false;
  bool _isProcessingPayment = false;

  // Data Plans
  final Map<String, List<Map<String, dynamic>>> _networkPlans = {};
  final Map<String, String> _networkServiceIds = {
    'MTN': 'mtn-data',
    'Airtel': 'airtel-data',
    'Glo': 'glo-data',
    '9mobile': 'etisalat-data',
  };

  // Quick Amount Options
  final List<int> _quickAmounts = [200, 500, 1000, 2000];

  // Network Providers with image assets
  final List<Map<String, dynamic>> _networks = [
    {
      'name': 'MTN',
      'apiName': 'mtn',
      'image': 'assets/mtn.jpg',
      'color': const Color(0xFFFFCB05),
      'textColor': const Color(0xFF1A1A2E),
    },
    {
      'name': 'Airtel',
      'apiName': 'airtel',
      'image': 'assets/airtel.jpg',
      'color': const Color(0xFFEF1C25),
      'textColor': Colors.white,
    },
    {
      'name': 'Glo',
      'apiName': 'glo',
      'image': 'assets/glo.png',
      'color': const Color(0xFF00843D),
      'textColor': Colors.white,
    },
    {
      'name': '9mobile',
      'apiName': 'etisalat',
      'image': 'assets/t2.png',
      'color': const Color(0xFFF57C00),
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
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _sheetController.dispose();
    _phoneController.dispose();
    _pinController.dispose();
    _phoneFocusNode.dispose();
    _pinFocusNode.dispose();
    super.dispose();
  }

  Future<void> _initializeData() async {
    try {
      final user = await ApiService.getCurrentUser();
      setState(() {
        _isUserActive = user['isActive'] ?? true;
        _isLoadingUserData = false;
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

  Future<void> _fetchDataPlans(String networkName) async {
    if (!_networkServiceIds.containsKey(networkName)) {
      return;
    }

    if (_isLoadingPlans) return;

    setState(() => _isLoadingPlans = true);

    try {
      final serviceID = _networkServiceIds[networkName]!;
      final result = await ApiService.getDataPlans(serviceID);

      if (result['success'] == true) {
        final plans = List<Map<String, dynamic>>.from(result['plans'] ?? []);
        final processedPlans = _processPlans(plans);

        setState(() {
          _networkPlans[networkName] = processedPlans;
          _selectedPlan = null;
        });
      } else {
        _loadMockDataPlans(networkName);
      }
    } catch (e) {
      _loadMockDataPlans(networkName);
    } finally {
      setState(() => _isLoadingPlans = false);
    }
  }

  List<Map<String, dynamic>> _processPlans(List<Map<String, dynamic>> plans) {
    plans.sort((a, b) {
      final amountA = double.tryParse(a['amount']?.toString() ?? '0') ?? 0;
      final amountB = double.tryParse(b['amount']?.toString() ?? '0') ?? 0;
      return amountA.compareTo(amountB);
    });
    return plans;
  }

  // Plans could not be loaded from the server. We no longer show made-up
  // plans (their codes don't exist at VTpass); the UI offers a retry instead.
  void _loadMockDataPlans(String networkName) {
    setState(() {
      _networkPlans[networkName] = [];
      _selectedPlan = null;
    });
  }

  String _planFilter = 'All plans';

  String _planBucket(Map<String, dynamic> plan) {
    final v = '${plan['validity'] ?? ''} ${plan['name'] ?? ''}'.toLowerCase();
    final m = RegExp(r'(\d+)\s*(day|days|hr|hrs|hour|hours)').firstMatch(v);
    if (v.contains('daily') || v.contains('24') || (m != null && (m.group(2)!.startsWith('h') || int.parse(m.group(1)!) <= 3))) {
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

  Map<String, dynamic>? get _selectedPlanDetails {
    if (_selectedNetwork == null || _selectedPlan == null) return null;
    final plans = _networkPlans[_selectedNetwork] ?? const [];
    for (final p in plans) {
      if (p['name'] == _selectedPlan) return p;
    }
    return null;
  }

  String? _validateForm() {
    if (_selectedNetwork == null) {
      return 'Please select a network provider';
    }

    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      return 'Please enter phone number';
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

    if (_selectedPlan == null) {
      return 'Please select a data plan';
    }

    final plans = _networkPlans[_selectedNetwork];
    if (plans == null || plans.isEmpty) {
      return 'No data plans available for $_selectedNetwork. Please try another network.';
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

  // ==================== OPEN PAYMENT SHEET ====================

  void _openPaymentSheet() {
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
      setState(() {
        _showPaymentSheet = false;
        _isProcessingPayment = false;
        _pinValidationError = null;
      });
    });
  }

  Future<void> _processPayment() async {
    final validationError = _validateForm();
    if (validationError != null) {
      _showErrorDialog('Validation Error', validationError);
      _closePaymentSheet();
      return;
    }

    // PIN validation - only when biometric is NOT selected
    if (!_useBiometric && _transactionPinSet) {
      final pin = _pinController.text.trim();
      if (pin.isEmpty) {
        setState(() {
          _pinValidationError = 'Please enter your transaction PIN';
        });
        return;
      }
      if (pin.length != 6) {
        setState(() {
          _pinValidationError = 'PIN must be exactly 6 digits';
        });
        return;
      }
      if (!RegExp(r'^[0-9]+$').hasMatch(pin)) {
        setState(() {
          _pinValidationError = 'PIN must contain only numbers';
        });
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

    setState(() {
      _isProcessingPayment = true;
    });

    final network = _selectedNetwork!;
    final plan = _selectedPlan!;
    final phone = _phoneController.text.trim();

    final plans = _networkPlans[network];
    if (plans == null) {
      _showErrorDialog('Error', 'No plans available for $network.');
      _closePaymentSheet();
      return;
    }

    final planDetails = plans.firstWhere((p) => p['name'] == plan);
    final amount =
        double.tryParse(planDetails['amount']?.toString() ?? '0') ?? 0;

    if (amount <= 0) {
      _showErrorDialog(
        'Invalid Amount',
        'Selected data plan has an invalid price.',
      );
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

      final result = await ApiService.buyData(
        userId: widget.userId,
        network: network.toLowerCase(),
        phone: phone,
        variationCode: planDetails['variation_code'],
        planName: plan,
        amount: amount,
        transactionPin: _useBiometric ? null : _pinController.text,
        useBiometric: _useBiometric,
      );

      final vtpassCode =
          result['vtpassResponse']?['code']?.toString() ??
          result['vtpassResponse']?['vtpassResponse']?['code']?.toString();
      final bool vtpassSuccess = vtpassCode == '000';
      final bool alreadyProcessed = result['alreadyProcessed'] == true;

      if (vtpassSuccess || alreadyProcessed) {
        final newBalance = result['newBalance'] ?? 0.0;
        widget.onBalanceUpdate(newBalance);
        _closePaymentSheet();
        _showSuccessDialog(network, phone, plan, planDetails, amount, result);
        _clearForm();
      } else {
        final errorMsg =
            result['vtpassResponse']?['response_description'] ??
            result['message'] ??
            'Transaction failed. Please try again.';
        setState(() {
          _isProcessingPayment = false;
        });
        _showErrorDialog('Purchase Failed', errorMsg);
      }
    } catch (e) {
      setState(() {
        _isProcessingPayment = false;
      });
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
    setState(() {
      _selectedNetwork = null;
      _selectedPlan = null;
      _useBiometric = false;
      _pinValidationError = null;
    });
  }

  // ==================== UI BUILDERS ====================

  @override
  Widget build(BuildContext context) {
    final sel = _selectedPlanDetails;
    final busy = _isLoading || _isAuthenticating;
    return Stack(
      children: [
        DPPage(
          title: 'Buy data',
          actionLabel: 'History',
          onAction: () => Navigator.pushNamed(context, '/transactions'),
          bottom: _isLoadingUserData || !_isUserActive || !_dataServiceEnabled
              ? null
              : DPButton(
                  label: sel != null ? 'Continue with ${_planSize(sel['name'].toString())}' : 'Continue',
                  icon: DPIcons.arrowRight,
                  loading: busy,
                  onPressed: busy ? null : _openPaymentSheet,
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
    if (!_isUserActive || !_dataServiceEnabled) {
      return _buildServiceUnavailable();
    }
    final names = _networks.map((n) => n['name'] as String).toList();
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
            DPChipGrid(
              labels: names,
              columns: 4,
              selectedIndex: _selectedNetwork == null ? null : names.indexOf(_selectedNetwork!),
              onSelected: (i) {
                setState(() {
                  _selectedNetwork = names[i];
                  _selectedPlan = null;
                });
                _fetchDataPlans(names[i]);
              },
            ),
            DPField(
              label: 'Phone number',
              controller: _phoneController,
              focusNode: _phoneFocusNode,
              keyboardType: TextInputType.phone,
              hint: '0802 321 4567',
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(11),
              ],
              suffixIcon: DPIcons.contactRound,
            ),
            _buildPlanSection(),
            if (sel != null) ...[
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
            ],
            const DPNotice(
              'Plans activate on the number entered. Double-check before continuing.',
              kind: DPNoticeKind.info,
              margin: EdgeInsets.zero,
            ),
          ],
        ),
      ),
    );
  }

  // ==================== DATA PLANS SECTION ====================

  Widget _buildPlanSection() {
    if (_selectedNetwork == null) {
      return const DPCard(
        child: DPEmptyState(
          icon: DPIcons.wifi,
          title: 'Choose a network',
          message: 'Pick a network above to see its data plans.',
        ),
      );
    }

    final plans = _networkPlans[_selectedNetwork] ?? [];
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
        else if (plans.isEmpty)
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
                ? plans
                : plans.where((p) => _planBucket(p) == _planFilter).toList();
            if (shown.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('No plans in this group.', textAlign: TextAlign.center),
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
                      Expanded(child: _buildPlanCard(shown[i], _selectedPlan == shown[i]['name'])),
                      const SizedBox(width: 12),
                      Expanded(
                        child: i + 1 < shown.length
                            ? _buildPlanCard(shown[i + 1], _selectedPlan == shown[i + 1]['name'])
                            : const SizedBox(),
                      ),
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

  Widget _buildPlanCard(Map<String, dynamic> plan, bool isSelected) {
    final name = plan['name']?.toString() ?? '';
    final size = _planSize(name);
    final price = double.tryParse(plan['amount']?.toString() ?? '0') ?? 0;
    return Material(
      color: isSelected ? DP.greenSoft : DP.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DP.rLg - 2),
        side: BorderSide(color: isSelected ? DP.green : DP.border, width: isSelected ? 1.4 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(DP.rLg - 2),
        onTap: () => setState(() => _selectedPlan = plan['name']),
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
                size == name ? (plan['validity']?.toString() ?? '') : '${plan['validity'] ?? ''} · $name',
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

  // ==================== PAYMENT SHEET OVERLAY ====================

  Widget _buildPaymentSheetOverlay() {
    final plan = _selectedPlanDetails;
    final amount = double.tryParse(plan?['amount']?.toString() ?? '0') ?? 0;
    final bool isBiometricSupported = Platform.isAndroid || Platform.isIOS;
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
        onPinChanged: (_) => setState(() => _pinValidationError = null),
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
        biometricName: 'biometrics',
        onClose: _closePaymentSheet,
        footnote: 'Plans activate on the number entered and can’t be reversed.',
      ),
    );
  }

  // ==================== PAYMENT SHEET DETAILS ====================



  // ==================== PIN OPTION ====================


  // ==================== BIOMETRIC OPTION ====================


  // ==================== NETWORK CARD ====================


  // ==================== BANNER ====================


  Widget _buildServiceUnavailable() {
    return const DPServiceUnavailable(
      message: 'Data purchase is currently unavailable. Please try again later.',
    );
  }

  // ==================== SUCCESS & ERROR DIALOGS ====================

  void _showSuccessDialog(
    String network,
    String phone,
    String plan,
    Map<String, dynamic> planDetails,
    double amount,
    Map<String, dynamic> result,
  ) {
    final transactionId =
        result['vtpassResponse']?['transactionId'] ??
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
              description: '$plan (${planDetails['validity']})',
              customMessage: 'Verified by VTpass',
              mobileOperator: network,
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
