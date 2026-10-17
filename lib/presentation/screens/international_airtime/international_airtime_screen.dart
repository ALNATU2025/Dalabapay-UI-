// lib/presentation/screens/international_airtime/international_airtime_screen.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dalabapay/core/services/biometric_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;

import '../../../core/services/api_service.dart';
import '../../../core/widgets/receipt_widget.dart';
import '../../../core/widgets/request_limit_increase_dialog.dart';
import '../../../core/widgets/country_flag_widget.dart';
import '../../../ui/ui.dart';

class IntlAirtimeScreen extends StatefulWidget {
  final void Function(double newBalance) onBalanceUpdate;
  final String userId;

  const IntlAirtimeScreen({
    super.key,
    required this.onBalanceUpdate,
    required this.userId,
  });

  @override
  State<IntlAirtimeScreen> createState() => _IntlAirtimeScreenState();
}

class _IntlAirtimeScreenState extends State<IntlAirtimeScreen>
    with TickerProviderStateMixin {
  // Controllers
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _pinController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();

  // Focus Nodes
  final FocusNode _phoneFocusNode = FocusNode();
  final FocusNode _amountFocusNode = FocusNode();
  final FocusNode _pinFocusNode = FocusNode();

  // State Variables
  List<Map<String, dynamic>> _countries = [];
  List<Map<String, dynamic>> _productTypes = [];
  List<Map<String, dynamic>> _operators = [];
  List<Map<String, dynamic>> _variations = [];

  Map<String, dynamic>? _selectedCountry;
  Map<String, dynamic>? _selectedProductType;
  Map<String, dynamic>? _selectedOperator;
  Map<String, dynamic>? _selectedVariation;

  bool _isLoadingCountries = false;
  bool _isLoadingProductTypes = false;
  bool _isLoadingOperators = false;
  bool _isLoadingVariations = false;
  final bool _isPurchasing = false;
  bool _isAuthenticating = false;
  bool _isBalanceVisible = true;
  bool _isInitialized = false;
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
  String? _selectedItemId;
  String _biometricName = 'Biometric';

  // Service State
  final bool _airtimeServiceEnabled = true;
  bool _isUserActive = true;
  bool _isLoadingUserData = true;

  // Animation
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late AnimationController _sheetController;
  late Animation<double> _sheetAnimation;
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

  // Search
  String _searchQuery = '';
  List<Map<String, dynamic>> _filteredCountries = [];

  // Receipt Data
  Map<String, dynamic>? _lastTransactionData;

  // Payment Sheet State
  bool _showPaymentSheet = false;
  bool _isProcessingPayment = false;

  // Naira Conversion - Now fetched from backend only
  // Naira Conversion - Now fetched from backend only
  double _nairaConversionRate = 0.0;
  bool _isLoadingConversion = false;
  String _nairaEstimate = '';
  String _currencySymbol = '';

  // ✅ NEW: Variation min/max amounts for validation and display
  double? _variationMinAmount;
  double? _variationMaxAmount;

  // Dropdown states
  bool _isProductTypeDropdownOpen = false;
  bool _isOperatorDropdownOpen = false;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _loadWalletBalance();
    _fetchSecuritySettings();
    _checkBiometricSupport();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeData();
    });
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

  void _log(String message) {
    if (kDebugMode) {
      debugPrint('🌍 INTL AIRTIME: $message');
    }
  }

  Future<void> _checkBiometricSupport() async {
    if (kIsWeb) {
      // Biometric is never supported on web.
      if (mounted) {
        setState(() {
          _biometricEnabled = false;
          _biometricName = 'Biometric';
        });
      }
      return;
    }

    try {
      final isAvailable = await biometricService.isBiometricAvailable();

      if (!isAvailable) {
        if (mounted) {
          setState(() {
            _biometricEnabled = false;
            _biometricName = 'Biometric';
          });
        }
        return;
      }

      // ✅ FIX: Use the SAME per-user check as AirtimeScreen
      final isEnabled = await biometricService.getBiometricEnabledStatus(
        userId: widget.userId,
      );

      // Always fetch the human-readable name (Fingerprint / Face ID / etc.)
      String name = 'Biometric';
      try {
        name = await biometricService.getBiometricName();
      } catch (_) {
        name = 'Biometric';
      }

      if (mounted) {
        setState(() {
          _biometricName = name;
          _biometricEnabled = isEnabled;
        });
      }

      _log('🔐 Biometric: available=$isAvailable, enabled=$isEnabled ($name)');
    } catch (e) {
      debugPrint('Biometric check error: $e');
      if (mounted) {
        setState(() {
          _biometricEnabled = false;
        });
      }
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

  Future<void> _initializeData() async {
    if (_isInitialized) return;

    try {
      setState(() => _isLoadingUserData = true);

      final user = await ApiService.getCurrentUser();
      setState(() {
        _isUserActive = user['isActive'] ?? true;
        _isLoadingUserData = false;
      });

      await _fetchCountries();

      setState(() => _isInitialized = true);
    } catch (e) {
      setState(() => _isLoadingUserData = false);
      _showErrorDialog('Error', 'Failed to load user data: ${e.toString()}');
    }
  }

  Future<void> _fetchSecuritySettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // ✅ FIX: read per-user biometric flag, exactly like AirtimeScreen
      final isBiometricEnabled =
          kIsWeb
              ? false
              : await biometricService.getBiometricEnabledStatus(
                userId: widget.userId,
              );

      // Read local PIN flag, and also cross-check the user blob
      final userString = prefs.getString('user');
      bool pinSet = prefs.getBool('transactionPinSet') ?? false;

      if (userString != null) {
        try {
          final user = jsonDecode(userString);
          pinSet =
              pinSet ||
              (user['transactionPinSet'] ?? false) ||
              (user['hasTransactionPin'] ?? false) ||
              (user['pinSet'] ?? false) ||
              (user['transactionPin'] != null &&
                  user['transactionPin'].toString().isNotEmpty &&
                  user['transactionPin'].toString() != 'null');
        } catch (_) {
          /* ignore malformed blob */
        }
      }

      if (mounted) {
        setState(() {
          _transactionPinSet = pinSet;
          _biometricEnabled = isBiometricEnabled;
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

  Future<void> _fetchCountries() async {
    setState(() => _isLoadingCountries = true);

    try {
      final response = await ApiService.getInternationalCountries();

      if (response['success'] == true) {
        final countries = List<Map<String, dynamic>>.from(
          response['countries'] ?? [],
        );
        setState(() {
          _countries = countries;
          _filteredCountries = countries;
          _isLoadingCountries = false;
        });

        if (countries.isNotEmpty) {
          _selectCountry(countries[0]);
        }
      } else {
        final fallbackCountries = _getFallbackCountries();
        setState(() {
          _countries = fallbackCountries;
          _filteredCountries = fallbackCountries;
          _isLoadingCountries = false;
        });

        if (fallbackCountries.isNotEmpty) {
          _selectCountry(fallbackCountries[0]);
        }
      }
    } catch (e) {
      _log('❌ Error fetching countries: $e');

      final fallbackCountries = _getFallbackCountries();
      setState(() {
        _countries = fallbackCountries;
        _filteredCountries = fallbackCountries;
        _isLoadingCountries = false;
      });

      if (fallbackCountries.isNotEmpty) {
        _selectCountry(fallbackCountries[0]);
      }

      // ✅ Sanitized message
      _showErrorDialog(
        'Connection Issue',
        'We couldn\'t refresh the country list. Showing offline data. Please check your internet.',
      );
    }
  }

  List<Map<String, dynamic>> _getFallbackCountries() {
    return [
      {
        'code': 'NG',
        'name': 'Nigeria',
        'currency': 'NGN',
        'prefix': '234',
        'flag': 'https://flagcdn.com/w40/ng.png',
      },
      {
        'code': 'GH',
        'name': 'Ghana',
        'currency': 'GHS',
        'prefix': '233',
        'flag': 'https://flagcdn.com/w40/gh.png',
      },
      {
        'code': 'US',
        'name': 'United States',
        'currency': 'USD',
        'prefix': '1',
        'flag': 'https://flagcdn.com/w40/us.png',
      },
      {
        'code': 'GB',
        'name': 'United Kingdom',
        'currency': 'GBP',
        'prefix': '44',
        'flag': 'https://flagcdn.com/w40/gb.png',
      },
      {
        'code': 'SL',
        'name': 'Sierra Leone',
        'currency': 'SLE',
        'prefix': '232',
        'flag': 'https://flagcdn.com/w40/sl.png',
      },
    ];
  }

  Future<void> _fetchProductTypes(String countryCode) async {
    setState(() {
      _isLoadingProductTypes = true;
      _productTypes = [];
      _selectedProductType = null;
      _selectedItemId = null;
      _operators = [];
      _selectedOperator = null;
      _variations = [];
      _selectedVariation = null;
      _nairaEstimate = '';
      _nairaConversionRate = 0.0;
      _isProductTypeDropdownOpen = false;
      _isOperatorDropdownOpen = false;
    });

    try {
      final response = await ApiService.getInternationalProductTypes(
        countryCode,
      );

      if (response['success'] == true) {
        final productTypes = List<Map<String, dynamic>>.from(
          response['productTypes'] ?? [],
        );
        setState(() {
          _productTypes = productTypes;
          _isLoadingProductTypes = false;
        });

        if (productTypes.isNotEmpty) {
          _selectProductType(productTypes[0]);
        }
      } else {
        final fallbackTypes = _getFallbackProductTypes();
        setState(() {
          _productTypes = fallbackTypes;
          _isLoadingProductTypes = false;
        });

        if (fallbackTypes.isNotEmpty) {
          _selectProductType(fallbackTypes[0]);
        }
      }
    } catch (e) {
      _log('❌ Error fetching product types: $e');

      final fallbackTypes = _getFallbackProductTypes();
      setState(() {
        _productTypes = fallbackTypes;
        _isLoadingProductTypes = false;
      });

      if (fallbackTypes.isNotEmpty) {
        _selectProductType(fallbackTypes[0]);
      }

      // ✅ Sanitized message
      _showErrorDialog(
        'Unable to Load Options',
        'We couldn\'t load product options right now. Please try again.',
      );
    }
  }

  List<Map<String, dynamic>> _getFallbackProductTypes() {
    return [
      {'product_type_id': 1, 'name': 'Mobile Top Up'},
      {'product_type_id': 4, 'name': 'Mobile Data'},
    ];
  }

  Future<void> _fetchOperators(String countryCode, int productTypeId) async {
    _log(
      '📱 Fetching operators for country: $countryCode, productType: $productTypeId',
    );

    setState(() {
      _isLoadingOperators = true;
      _operators = [];
      _selectedOperator = null;
      _selectedItemId = null;
      _variations = [];
      _selectedVariation = null;
      _nairaEstimate = '';
      _nairaConversionRate = 0.0;
      _isOperatorDropdownOpen = false;
    });

    try {
      final response = await ApiService.getInternationalOperators(
        countryCode: countryCode,
        productTypeId: productTypeId,
      );

      _log('📱 Operators API response: ${response['success']}');
      _log('📱 Operators data: ${response['operators']}');

      if (response['success'] == true) {
        final operators = List<Map<String, dynamic>>.from(
          response['operators'] ?? [],
        );

        _log('📱 Found ${operators.length} operators');

        // Log each operator for debugging
        for (var op in operators) {
          _log('  📌 ${op['name']} - ID: ${op['operator_id']}');
        }

        if (operators.isNotEmpty) {
          setState(() {
            _operators = operators;
            _isLoadingOperators = false;
          });

          // ✅ Select first operator with its REAL ID
          _log(
            '📱 Selecting first operator: ${operators[0]['name']} (ID: ${operators[0]['operator_id']})',
          );
          _selectOperator(operators[0]);
        } else {
          // ✅ No operators - show error, DO NOT use fallback
          setState(() {
            _operators = [];
            _isLoadingOperators = false;
          });

          _showErrorDialog(
            'No Operators',
            'No operators available for this country and product type.',
          );
        }
      } else {
        // ✅ API failed - show error, DO NOT use fallback
        setState(() {
          _operators = [];
          _isLoadingOperators = false;
        });

        _showErrorDialog(
          'Error',
          response['message'] ?? 'Failed to fetch operators. Please try again.',
        );
      }
    } catch (e) {
      // ✅ Error - show error, DO NOT use fallback
      _log('❌ Error fetching operators: $e');
      setState(() {
        _operators = [];
        _isLoadingOperators = false;
      });

      // ✅ Sanitized message — NEVER expose raw exception to user
      _showErrorDialog(
        'Unable to Load Operators',
        'We couldn\'t load operators right now. Please check your internet connection and try again.',
      );
    }
  }

  List<Map<String, dynamic>> _getFallbackOperators(String countryCode) {
    final operators = <Map<String, dynamic>>[];

    switch (countryCode.toUpperCase()) {
      case 'NG':
        operators.addAll([
          {
            'operator_id': '1',
            'name': 'MTN Nigeria',
            'operator_image':
                'https://vtpass.com/resources/images/operators/80.png',
          },
          {
            'operator_id': '2',
            'name': 'Airtel Nigeria',
            'operator_image':
                'https://vtpass.com/resources/images/operators/80.png',
          },
          {
            'operator_id': '3',
            'name': 'Glo Nigeria',
            'operator_image':
                'https://vtpass.com/resources/images/operators/80.png',
          },
          {
            'operator_id': '4',
            'name': '9mobile',
            'operator_image':
                'https://vtpass.com/resources/images/operators/80.png',
          },
        ]);
        break;
      case 'SL':
        operators.addAll([
          {
            'operator_id': '100',
            'name': 'Africell',
            'operator_image':
                'https://vtpass.com/resources/images/operators/80.png',
          },
          {
            'operator_id': '101',
            'name': 'Orange',
            'operator_image':
                'https://vtpass.com/resources/images/operators/80.png',
          },
        ]);
        break;
      default:
        operators.addAll([
          {
            'operator_id': '100',
            'name': 'Operator 1',
            'operator_image':
                'https://vtpass.com/resources/images/operators/80.png',
          },
          {
            'operator_id': '101',
            'name': 'Operator 2',
            'operator_image':
                'https://vtpass.com/resources/images/operators/80.png',
          },
          {
            'operator_id': '102',
            'name': 'Operator 3',
            'operator_image':
                'https://vtpass.com/resources/images/operators/80.png',
          },
        ]);
    }

    return operators;
  }

  Future<void> _fetchVariations(String operatorId, int productTypeId) async {
    setState(() {
      _isLoadingVariations = true;
      _variations = [];
      _selectedVariation = null;
      _nairaEstimate = '';
      _nairaConversionRate = 0.0;
    });

    try {
      final response = await ApiService.getInternationalVariations(
        operatorId: operatorId,
        productTypeId: productTypeId,
      );

      if (response['success'] == true) {
        final variations = List<Map<String, dynamic>>.from(
          response['variations'] ?? [],
        );
        setState(() {
          _variations = variations;
          _isLoadingVariations = false;
        });
      } else {
        final fallbackVariations = _getFallbackVariations(operatorId);
        setState(() {
          _variations = fallbackVariations;
          _isLoadingVariations = false;
        });
      }
    } catch (e) {
      _log('❌ Error fetching variations: $e');

      final fallbackVariations = _getFallbackVariations(operatorId);
      setState(() {
        _variations = fallbackVariations;
        _isLoadingVariations = false;
      });

      // ✅ Sanitized message
      _showErrorDialog(
        'Unable to Load Plans',
        'We couldn\'t load available plans right now. Please try again.',
      );
    }
  }

  List<Map<String, dynamic>> _getFallbackVariations(String operatorId) {
    return [
      {
        'variation_code': 'airtime_1',
        'name': 'Small Top Up',
        'variation_amount': '1.00',
        'fixedPrice': 'Yes',
      },
      {
        'variation_code': 'airtime_5',
        'name': 'Medium Top Up',
        'variation_amount': '5.00',
        'fixedPrice': 'Yes',
      },
      {
        'variation_code': 'airtime_10',
        'name': 'Large Top Up',
        'variation_amount': '10.00',
        'fixedPrice': 'Yes',
      },
    ];
  }

  void _selectCountry(Map<String, dynamic> country) {
    setState(() {
      _selectedCountry = country;
      _phoneController.clear();
      _amountController.clear();
      _selectedProductType = null;
      _selectedItemId = null;
      _selectedOperator = null;
      _selectedVariation = null;
      _operators = [];
      _productTypes = [];
      _variations = [];
      _nairaEstimate = '';
      _nairaConversionRate = 0.0;
      _currencySymbol = country['currency'] ?? 'USD';
      _isProductTypeDropdownOpen = false;
      _isOperatorDropdownOpen = false;
    });
    _fetchProductTypes(country['code']);
  }

  void _selectProductType(Map<String, dynamic> productType) {
    setState(() {
      _selectedProductType = productType;
      _selectedItemId = productType['product_type_id']?.toString();
      _selectedOperator = null;
      _selectedVariation = null;
      _operators = [];
      _variations = [];
      _nairaEstimate = '';
      _nairaConversionRate = 0.0;
      _isProductTypeDropdownOpen = false;
      _isOperatorDropdownOpen = false;
    });
    if (_selectedCountry != null) {
      _fetchOperators(
        _selectedCountry!['code'],
        productType['product_type_id'],
      );
    }
  }

  void _selectOperator(Map<String, dynamic> operator) {
    // ✅ CRITICAL FIX: Log the actual operator data
    _log('📱 _selectOperator called with:');
    _log('  📌 Name: ${operator['name']}');
    _log('  📌 operator_id: ${operator['operator_id']}');
    _log('  📌 Full data: $operator');

    // Get the operator ID as a string
    final operatorId = operator['operator_id']?.toString() ?? '';

    _log('📱 Extracted operator ID: "$operatorId"');

    setState(() {
      _selectedOperator = operator;
      _selectedItemId = operatorId;
      _selectedVariation = null;
      _variations = [];
      _nairaEstimate = '';
      _nairaConversionRate = 0.0;
      _isOperatorDropdownOpen = false;
      // ✅ Reset min/max
      _variationMinAmount = null;
      _variationMaxAmount = null;
    });

    if (_selectedProductType != null && operatorId.isNotEmpty) {
      final productTypeId = _selectedProductType!['product_type_id'];

      _log('📱 Fetching variations for:');
      _log('  📌 Operator ID: $operatorId');
      _log('  📌 Product Type ID: $productTypeId');

      _fetchVariations(operatorId, productTypeId);
    } else {
      _log('❌ Cannot fetch variations - missing operator ID or product type');
      _log('  📌 operatorId: "$operatorId"');
      _log('  📌 _selectedProductType: $_selectedProductType');
    }
  }

  void _selectVariation(Map<String, dynamic> variation) {
    setState(() {
      _selectedVariation = variation;
      final isFixed =
          variation['fixedPrice'] == 'Yes' || variation['fixedPrice'] == true;

      // ✅ Clear previous min/max first
      _variationMinAmount = null;
      _variationMaxAmount = null;

      if (isFixed) {
        // ✅ FIXED PRICE: safe parse of variation_amount
        // NOTE: for fixed prices, `variation_amount` may be a String OR a number
        final rawAmount = variation['variation_amount'];
        String amountStr = '';
        if (rawAmount is num) {
          amountStr = rawAmount.toString();
        } else if (rawAmount is String) {
          amountStr = rawAmount;
        }
        if (amountStr.isNotEmpty && double.tryParse(amountStr) != null) {
          _amountController.text = amountStr;
        }
      } else {
        _amountController.clear();
      }

      // ✅ Calculate Naira amount from variation data (also extracts min/max)
      _updateNairaEstimate(variation);
    });
  }

  // ✅ New method to calculate Naira amount from variation data
  // ALSO extracts min/max amounts for validation
  void _updateNairaEstimate(Map<String, dynamic> variation) {
    final isFixed =
        variation['fixedPrice'] == 'Yes' || variation['fixedPrice'] == true;

    // ✅ CRITICAL: Extract min/max amounts — backend already sends them as
    // double or null, but we keep this defensive so it also handles legacy data.
    double? parseNum(dynamic raw) {
      if (raw == null || raw == false || raw == '') return null;
      if (raw is num) return raw.toDouble();
      if (raw is String) return double.tryParse(raw);
      return null;
    }

    final parsedMin = parseNum(variation['variation_amount_min']);
    final parsedMax = parseNum(variation['variation_amount_max']);

    // ✅ Store min/max in state for UI display and validation
    setState(() {
      _variationMinAmount = parsedMin;
      _variationMaxAmount = parsedMax;
    });

    _log('💰 Variation Min: $parsedMin, Max: $parsedMax');

    if (isFixed) {
      // ✅ For fixed price: extract charged_amount (the exact Naira amount)
      // VTpass sometimes returns `false` here instead of a number — handle safely
      double? parsedCharged;
      final rawCharged = variation['charged_amount'];
      if (rawCharged is num) {
        parsedCharged = rawCharged.toDouble();
      } else if (rawCharged is String) {
        parsedCharged = double.tryParse(rawCharged);
      }
      // Note: `false`, `null`, empty strings → parsedCharged stays null

      // Also extract variation_rate as a fallback
      double? parsedRate;
      final rawRate = variation['variation_rate'];
      if (rawRate is num) {
        parsedRate = rawRate.toDouble();
      } else if (rawRate is String) {
        parsedRate = double.tryParse(rawRate);
      }

      // Determine the Naira amount
      double nairaAmount = 0.0;
      if (parsedCharged != null && parsedCharged > 0) {
        nairaAmount = parsedCharged;
      } else if (parsedRate != null && parsedRate > 0) {
        // Fallback: calculate from variation_amount × rate
        final amountStr = variation['variation_amount']?.toString() ?? '';
        final foreignAmount = double.tryParse(amountStr) ?? 0.0;
        nairaAmount = foreignAmount * parsedRate;
      }

      setState(() {
        _nairaConversionRate = parsedRate ?? 0;
        if (nairaAmount > 0) {
          _nairaEstimate = '₦${nairaAmount.toStringAsFixed(2)}';
        } else {
          _nairaEstimate = '';
        }
        _isLoadingConversion = false;
      });

      _log('💰 Fixed price - Naira amount: ₦${nairaAmount.toStringAsFixed(2)}');
      if (parsedRate != null && parsedRate > 0) {
        _log(
          '📊 Exchange Rate: 1 ${_selectedCountry?['currency']} = ₦$parsedRate',
        );
      }
    } else {
      // ✅ For flexible price: store the rate, calculate when user enters amount
      double? parsedRate;
      final rawRate = variation['variation_rate'];
      if (rawRate is num) {
        parsedRate = rawRate.toDouble();
      } else if (rawRate is String) {
        parsedRate = double.tryParse(rawRate);
      }

      if (parsedRate != null && parsedRate > 0) {
        setState(() {
          _nairaConversionRate = parsedRate!;
          _nairaEstimate = '';
          _isLoadingConversion = false;
        });

        // If amount is already filled, calculate immediately
        if (_amountController.text.isNotEmpty) {
          _calculateNairaConversion(_amountController.text);
        }

        _log(
          '💰 Flexible price - Rate: 1 ${_selectedCountry?['currency']} = ₦$parsedRate',
        );
      }
    }
  }

  // ✅ No client-side conversion - VTpass determines exact Naira amount
  // ✅ Calculate Naira amount from variation rate or charged_amount
  void _calculateNairaConversion(String amountStr) {
    final amount = double.tryParse(amountStr);
    if (amount == null || amount <= 0) {
      setState(() {
        _nairaEstimate = '';
      });
      return;
    }

    final isFixed =
        _selectedVariation?['fixedPrice'] == 'Yes' ||
        _selectedVariation?['fixedPrice'] == true;

    if (isFixed) {
      // For fixed price, use charged_amount from variation
      double? parsedCharged;
      final rawCharged = _selectedVariation?['charged_amount'];
      if (rawCharged is num) {
        parsedCharged = rawCharged.toDouble();
      } else if (rawCharged is String) {
        parsedCharged = double.tryParse(rawCharged);
      }

      if (parsedCharged != null && parsedCharged > 0) {
        setState(() {
          _nairaEstimate = '₦${parsedCharged!.toStringAsFixed(2)}';
        });
      } else if (_nairaConversionRate > 0) {
        // Fallback: calculate from rate
        final nairaAmount = amount * _nairaConversionRate;
        setState(() {
          _nairaEstimate = '₦${nairaAmount.toStringAsFixed(2)}';
        });
      }
    } else {
      // For flexible price, calculate using variation_rate
      if (_nairaConversionRate > 0) {
        final nairaAmount = amount * _nairaConversionRate;
        setState(() {
          _nairaEstimate = '₦${nairaAmount.toStringAsFixed(2)}';
        });

        _log(
          '💰 Flexible amount: $amount × $_nairaConversionRate = ₦${nairaAmount.toStringAsFixed(2)}',
        );
      } else {
        setState(() {
          _nairaEstimate = '';
        });
      }
    }
  }

  void _filterCountries(String query) {
    setState(() {
      _searchQuery = query;
      if (query.isEmpty) {
        _filteredCountries = _countries;
      } else {
        _filteredCountries =
            _countries.where((country) {
              final name = country['name']?.toString().toLowerCase() ?? '';
              final code = country['code']?.toString().toLowerCase() ?? '';
              final search = query.toLowerCase();
              return name.contains(search) || code.contains(search);
            }).toList();
      }
    });
  }

  String? _validateForm() {
    if (_selectedCountry == null) return 'Please select a country';
    if (_selectedProductType == null) return 'Please select a product type';
    if (_selectedOperator == null) return 'Please select an operator';
    if (_selectedVariation == null) return 'Please select a plan';

    final phone = _phoneController.text.trim();
    if (phone.isEmpty) return 'Please enter phone number';
    if (phone.length < 5) return 'Phone number is too short';

    final isFixed =
        _selectedVariation?['fixedPrice'] == 'Yes' ||
        _selectedVariation?['fixedPrice'] == true;

    if (!isFixed) {
      final amount = double.tryParse(_amountController.text) ?? 0;
      if (_amountController.text.isEmpty) return 'Please enter amount';
      if (amount < 1) return 'Amount must be at least 1';

      // ✅ NEW: Validate against VTpass min/max
      final currency = _selectedCountry?['currency'] ?? 'USD';
      if (_variationMinAmount != null && amount < _variationMinAmount!) {
        return 'Minimum amount for this plan is $currency ${_variationMinAmount!.toStringAsFixed(2)}';
      }
      if (_variationMaxAmount != null && amount > _variationMaxAmount!) {
        return 'Maximum amount for this plan is $currency ${_variationMaxAmount!.toStringAsFixed(2)}';
      }
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
    } else if (errorStr.contains('Biometric authentication failed')) {
      return 'Biometric authentication failed. Please try again or use your PIN.';
    } else if (errorStr.contains('Biometric not available')) {
      return 'Biometric is not available on this device. Please use your PIN.';
    }
    return errorStr.length > 100 ? 'An unexpected error occurred.' : errorStr;
  }

  Future<void> _openPaymentSheet() async {
    HapticFeedback.lightImpact();

    final validationError = _validateForm();
    if (validationError != null) {
      _showErrorDialog('Validation Error', validationError);
      return;
    }

    // ✅ FIX: Refresh biometric + PIN status BEFORE opening the sheet,
    // so changes made in Settings are picked up immediately.
    await Future.wait([_checkBiometricSupport(), _fetchSecuritySettings()]);

    if (!mounted) return;

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
      _log('🔐 Verifying transaction PIN before payment...');

      final verifyResult = await ApiService.verifyTransactionPin(
        userId: widget.userId,
        transactionPin: pin,
      );

      _log('📡 PIN verification result: ${verifyResult['success']}');

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
        reason: 'Authenticate to buy International Airtime',
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

      // ✅ EXACT SAME AS AIRTIME: no credential ID, just pass useBiometric: true
      await _executeTransaction(useBiometric: true);
    } catch (e) {
      setState(() {
        _isProcessingPayment = false;
        _isAuthenticating = false;
      });
      _showErrorDialog('Authentication Error', _mapExceptionToUserMessage(e));
    }
  }

  Future<void> _executeTransaction({
    String? pin,
    bool useBiometric = false,
  }) async {
    double amount = 0.0;
    final amountText = _amountController.text.trim();
    if (amountText.isNotEmpty) {
      amount = double.tryParse(amountText) ?? 0.0;
    }

    // ✅ CRITICAL: Get the correct operator ID
    final operatorId = _selectedOperator?['operator_id']?.toString() ?? '';
    final operatorName = _selectedOperator?['name']?.toString() ?? 'Unknown';
    final countryCode = _selectedCountry?['code']?.toString() ?? '';
    final countryName = _selectedCountry?['name']?.toString() ?? 'Unknown';
    final currency = _selectedCountry?['currency']?.toString() ?? 'USD';
    final productTypeId = _selectedProductType?['product_type_id'];
    final variationCode =
        _selectedVariation?['variation_code']?.toString() ?? '';
    final variationName = _selectedVariation?['name']?.toString() ?? 'Unknown';
    final phoneNumber = _phoneController.text.trim();
    final email = _emailController.text.trim();

    // ✅ Enhanced logging for debugging
    _log('🚀 ========== STARTING TRANSACTION ==========');
    _log('📱 Operator: $operatorName (ID: $operatorId)');
    _log('🌍 Country: $countryName ($countryCode)');
    _log('📦 Product Type ID: $productTypeId');
    _log('📋 Plan: $variationName (Code: $variationCode)');
    _log('📞 Phone: $phoneNumber');
    _log('💰 Amount: $currency $amount');
    _log('📧 Email: ${email.isNotEmpty ? email : "Not provided"}');
    _log('🔐 Auth: ${useBiometric ? "Biometric" : "PIN"}');
    _log('🚀 =========================================');

    // ✅ Validate operator ID is not empty
    if (operatorId.isEmpty) {
      _log('❌ CRITICAL: Operator ID is empty!');
      setState(() {
        _isProcessingPayment = false;
      });
      _showErrorDialog('Invalid Operator', 'Please select a valid operator.');
      return;
    }

    try {
      // ✅ CRITICAL: Send the Naira amount so backend can validate BEFORE calling VTpass
      // For FIXED price: use charged_amount directly
      // For FLEXIBLE price: amount × variation_rate
      double estimatedNairaAmount = 0.0;
      double variationRate = 0.0;

      if (_selectedVariation != null) {
        final isFixed =
            _selectedVariation!['fixedPrice'] == 'Yes' ||
            _selectedVariation!['fixedPrice'] == true;

        if (isFixed) {
          // Fixed price: use charged_amount from variation
          final rawCharged = _selectedVariation!['charged_amount'];
          if (rawCharged is num) {
            estimatedNairaAmount = rawCharged.toDouble();
          } else if (rawCharged is String) {
            estimatedNairaAmount = double.tryParse(rawCharged) ?? 0.0;
          }

          // Also get variation_rate as fallback
          final rawRate = _selectedVariation!['variation_rate'];
          if (rawRate is num) {
            variationRate = rawRate.toDouble();
          } else if (rawRate is String) {
            variationRate = double.tryParse(rawRate) ?? 0.0;
          }

          // If charged_amount is 0 but we have rate, calculate
          if (estimatedNairaAmount <= 0 && variationRate > 0) {
            estimatedNairaAmount = amount * variationRate;
          }
        } else {
          // Flexible price: amount × variation_rate
          final rawRate = _selectedVariation!['variation_rate'];
          if (rawRate is num) {
            variationRate = rawRate.toDouble();
          } else if (rawRate is String) {
            variationRate = double.tryParse(rawRate) ?? 0.0;
          }

          if (variationRate > 0) {
            estimatedNairaAmount = amount * variationRate;
          }
        }
      }

      // ✅ If we still can't determine the Naira amount, block BEFORE calling backend
      if (estimatedNairaAmount <= 0) {
        setState(() => _isProcessingPayment = false);
        _showErrorDialog(
          'Unable to Determine Amount',
          'We couldn\'t calculate the Naira amount. Please refresh and select a plan again.',
        );
        return;
      }

      // ✅ Check wallet balance locally BEFORE calling backend (better UX)
      if (_walletBalance < estimatedNairaAmount) {
        setState(() => _isProcessingPayment = false);
        _showErrorDialog(
          'Insufficient Balance',
          'You need ₦${estimatedNairaAmount.toStringAsFixed(2)} but have ₦${_walletBalance.toStringAsFixed(2)}. Please fund your wallet.',
        );
        return;
      }

      final payload = {
        'operatorId': operatorId,
        'countryCode': countryCode,
        'productTypeId': productTypeId,
        'variationCode': variationCode,
        'phoneNumber': phoneNumber,
        'amount': amount,
        'email': email.isNotEmpty ? email : null,
        'currency': currency,
        'customerName': operatorName,
        // ✅ CRITICAL: Send these so backend can validate before calling VTpass
        'estimatedNairaAmount': estimatedNairaAmount,
        'variationRate': variationRate,
        // ✅ NEW: Send min/max for backend validation
        if (_variationMinAmount != null) 'variationMin': _variationMinAmount,
        if (_variationMaxAmount != null) 'variationMax': _variationMaxAmount,
      };

      _log('📦 Final payload being sent:');
      _log(jsonEncode(payload));

      final response = await ApiService.purchaseInternationalAirtime(
        payload: payload,
        transactionPin: useBiometric ? null : pin,
        useBiometric: useBiometric,
      );

      _log('📡 Response received: ${response['success']}');

      if (response['success'] == true) {
        // ✅ Extract ALL amount information from response
        final nairaAmount =
            (response['nairaAmount'] ?? response['amountDebited'] ?? 0.0)
                .toDouble();
        final foreignAmount =
            (response['foreignAmount'] ?? response['amount'] ?? amount)
                .toDouble();
        final exchangeRate = (response['exchangeRate'] ?? 0.0).toDouble();
        final newBalance = response['newBalance'];
        final transactionId = response['transactionId'] ?? 'N/A';
        final reference = response['reference'] ?? 'N/A';
        final vtpassResponse = response['vtpassResponse'];

        _log('✅ ========== TRANSACTION SUCCESSFUL ==========');
        _log(
          '💰 Foreign Amount: $currency ${foreignAmount.toStringAsFixed(2)}',
        );
        _log('💰 Naira Amount: ₦${nairaAmount.toStringAsFixed(2)}');
        if (exchangeRate > 0) {
          _log(
            '📊 Exchange Rate: 1 $currency = ₦${exchangeRate.toStringAsFixed(2)}',
          );
        }
        _log('💳 New Balance: ₦${newBalance?.toStringAsFixed(2) ?? "N/A"}');
        _log('🆔 Transaction ID: $transactionId');
        _log('🔖 Reference: $reference');
        _log('✅ ===========================================');

        // ✅ Store transaction data for receipt
        _lastTransactionData = {
          'transactionId': transactionId,
          'reference': reference,
          'foreignAmount': foreignAmount,
          'nairaAmount': nairaAmount,
          'currency': currency,
          'exchangeRate': exchangeRate,
          'status': 'delivered',
          'phoneNumber': phoneNumber,
          'countryName': countryName,
          'operatorName': operatorName,
          'planName': variationName,
          'newBalance': newBalance,
          'vtpassResponse': vtpassResponse,
        };

        // ✅ Update balance
        if (newBalance != null) {
          final balanceDouble = (newBalance as num).toDouble();
          widget.onBalanceUpdate(balanceDouble);
          setState(() {
            _walletBalance = balanceDouble;
          });
        }

        _closePaymentSheet();
        _showReceiptDialog();
        _clearForm();
      } else {
        // ✅ Failed transaction - log details
        _log('❌ Transaction failed');
        _log('❌ Message: ${response['message']}');
        _log('❌ VTpass Code: ${response['vtpassCode']}');
        _log('❌ VTpass Description: ${response['vtpassDescription']}');
        _log('❌ User Debited: ${response['userDebited']}');

        setState(() {
          _isProcessingPayment = false;
        });

        // ✅ CHECK FOR LIMIT ERRORS
        final errorCode = response['code']?.toString() ?? '';
        final errorMsg = response['message'] ?? '';

        if (errorCode == 'PER_TRANSACTION_LIMIT_EXCEEDED' ||
            errorCode == 'DAILY_LIMIT_EXCEEDED' ||
            errorMsg.contains('PER_TRANSACTION_LIMIT_EXCEEDED') ||
            errorMsg.contains('DAILY_LIMIT_EXCEEDED')) {
          // Extract limit info from error
          final limitValue = response['limit'] ?? 0;
          final requestedValue = response['requested'] ?? amount;

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

          _showLimitIncreaseDialog(
            service: 'international_airtime',
            limitType: isDaily ? 'dailyCap' : 'perTransaction',
            currentLimit: limit,
            requestedAmount: requested,
          );
          return;
        }

        _showErrorDialog(
          'Purchase Failed',
          response['message'] ?? 'Transaction failed',
        );
      }
    } catch (e) {
      _log('❌ Exception during transaction: $e');
      _log('❌ Stack trace: ${StackTrace.current}');

      setState(() {
        _isProcessingPayment = false;
      });

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
          service: 'international_airtime',
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

  void _showReceiptDialog() {
    if (_lastTransactionData == null) return;

    final data = _lastTransactionData!;
    final currency = data['currency'] ?? 'NGN';
    final nairaAmount = data['nairaAmount'] ?? 0.0;
    final foreignAmount = data['foreignAmount'] ?? 0.0;
    final exchangeRate = data['exchangeRate'] ?? 0.0;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => ReceiptWidget(
            transactionType: 'International Airtime',
            amount: '₦${nairaAmount.toStringAsFixed(2)}',
            status: 'delivered',
            transactionId: data['transactionId'] ?? 'N/A',
            reference: data['reference'] ?? 'N/A',
            date: DateTime.now(),
            phoneNumber: data['phoneNumber'] ?? '',
            description:
                '${data['operatorName'] ?? 'International'} Airtime Purchase',
            balanceAfter: data['newBalance']?.toString(),
            customerName: data['operatorName'] ?? 'N/A',
            customerAddress: data['countryName'] ?? 'N/A',
            gateway: 'Dalabapay App',
            recipientName: 'International Airtime',
            mobileOperator: data['operatorName'] ?? 'N/A',
            primaryColor: const Color(0xFF102C68),
            customMessage:
                exchangeRate > 0
                    ? '$currency ${foreignAmount.toStringAsFixed(2)} @ ₦${exchangeRate.toStringAsFixed(2)}/$currency = ₦${nairaAmount.toStringAsFixed(2)}'
                    : 'Charged: ₦${nairaAmount.toStringAsFixed(2)}',
            vtpassResponse: data['vtpassResponse']?.toString(),
            showWatermark: true,
            packageVariationCode: data['planName'] ?? 'N/A',
            isAdminTransaction: false,
            isUserAdmin: false,
          ),
    );
  }

  void _clearForm() {
    _phoneController.clear();
    _amountController.clear();
    _pinController.clear();
    _emailController.clear();
    setState(() {
      _useBiometric = false;
      _pinValidationError = null;
      _nairaEstimate = '';
      _nairaConversionRate = 0.0;
      // ✅ Reset min/max
      _variationMinAmount = null;
      _variationMaxAmount = null;
    });
  }

  void _showErrorDialog(String title, String message) {
    // 🛡️ Final safety net — refuse to display technical junk
    final sanitizedMessage = _sanitizeMessage(message);
    final sanitizedTitle = _sanitizeMessage(title);
    dpDialog(
      context,
      title: sanitizedTitle,
      message: sanitizedMessage,
      confirmLabel: 'OK',
      tone: DPTone.error,
    );
  }

  /// 🛡️ Strips technical noise (URLs, hostnames, exception class names)
  /// so nothing internal ever leaks to the user.
  String _sanitizeMessage(String input) {
    if (input.isEmpty) return 'Something went wrong. Please try again.';

    var s = input;

    // Remove URLs
    s = s.replaceAll(RegExp(r'https?://[^\s]+'), '');
    // Remove uri= / URL params
    s = s.replaceAll(RegExp(r'uri=[^\s]+'), '');
    // Remove hostnames we know
    s = s.replaceAll('.onrender.com', '');
    s = s.replaceAll('.herokuapp.com', '');
    // Remove exception class names
    s = s.replaceAll('ClientException', '');
    s = s.replaceAll('SocketException', '');
    s = s.replaceAll('TimeoutException', '');
    s = s.replaceAll('Exception', '');
    s = s.replaceAll('MongoError', '');
    s = s.replaceAll('XmlHttpRequestError', '');
    // Remove stray symbols
    s = s.replaceAll('❌', '').replaceAll('⚠️', '').replaceAll('🚨', '');
    // Collapse whitespace
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();

    // If after cleaning it's empty or too technical, fall back
    if (s.isEmpty ||
        s.contains('://') ||
        s.contains('/api/') ||
        s.contains('{') ||
        s.contains('}')) {
      return 'Something went wrong. Please try again.';
    }

    return s;
  }

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
                  const DPTopBar(title: 'International airtime'),
                  Expanded(child: _buildBody()),
                ],
              ),
            ),
            if (_showPaymentSheet) _buildPaymentSheetOverlay(),
          ],
        ),
        bottomNavigationBar: _showPaymentSheet ||
                _selectedOperator == null ||
                _isLoadingUserData ||
                _isLoadingCountries
            ? null
            : DPBottomAction(child: _buildPurchaseButton()),
      ),
    );
  }

  bool get _isFixedPlan =>
      _selectedVariation?['fixedPrice'] == 'Yes' ||
      _selectedVariation?['fixedPrice'] == true;

  double get _nairaToPay =>
      double.tryParse(_nairaEstimate.replaceAll(RegExp(r'[₦,\s]'), '')) ?? 0;

  String _money(String currency, double v) =>
      '$currency ${v.toStringAsFixed(v % 1 == 0 ? 0 : 2)}';


  Widget _buildBody() {
    if (_isLoadingUserData || _isLoadingCountries) {
      return _buildLoadingAnimation();
    }

    if (!_isUserActive || !_airtimeServiceEnabled) {
      return _buildServiceUnavailable();
    }

    return FadeTransition(
      opacity: _fadeAnimation,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const DPHeadline(
              'Send a little connection.',
              subtitle: 'Top up a loved one\'s number abroad.',
            ),
            _buildCountrySelector(),
            if (_selectedCountry != null) ...[
              const SizedBox(height: 18),
              _buildProductTypeSelector(),
              if (_selectedProductType != null) ...[
                const SizedBox(height: 18),
                _buildOperatorSelector(),
                if (_selectedOperator != null) ...[
                  const SizedBox(height: 18),
                  _buildPhoneInput(),
                  const SizedBox(height: 18),
                  _buildVariationSelector(),
                  const SizedBox(height: 18),
                  _buildAmountInput(),
                  const SizedBox(height: 18),
                  _buildEmailInput(),
                  const SizedBox(height: 18),
                  _buildQuoteCard(),
                  const SizedBox(height: 14),
                  const DPBanner(
                    'Indicative quote. Rates may change before payment. Confirm the country and network; airtime can\'t be reversed once delivered.',
                    tone: DPTone.warning,
                  ),
                ],
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildQuoteCard() {
    final currency = (_selectedCountry?['currency'] ?? '').toString();
    final foreign = double.tryParse(_amountController.text) ?? 0;
    final rows = <Widget>[];
    if (foreign > 0) {
      rows.add(DPSummaryRow('Recipient receives', _money(currency, foreign)));
    }
    if (_nairaConversionRate > 0) {
      rows.add(
        DPSummaryRow(
          'Estimated exchange rate',
          '$currency 1 = ${DP.naira(_nairaConversionRate)}',
        ),
      );
    }
    if (_nairaEstimate.isNotEmpty) {
      rows.add(DPSummaryRow('Airtime value', DP.naira(_nairaToPay)));
      rows.add(const DPSummaryRow('Service fee', '₦0.00'));
      rows.add(DPSummaryRow('You pay', DP.naira(_nairaToPay), strong: true));
    }
    rows.add(
      DPSummaryRow(
        'Wallet balance',
        _isBalanceVisible ? DP.naira(_walletBalance) : '₦ ••••',
      ),
    );
    return DPCard(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
      child: Column(children: rows),
    );
  }



  Widget _buildPaymentSheetOverlay() {
    final currency = (_selectedCountry?['currency'] ?? '').toString();
    final foreign = double.tryParse(_amountController.text) ?? 0;
    final prefix = (_selectedCountry?['prefix'] ?? '').toString();
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
            icon: DPIcons.globe,
            title:
                '${_selectedOperator?['name'] ?? ''} · ${_selectedCountry?['name'] ?? ''}',
            amount: _nairaToPay,
            rows: [
              DPReviewRow(
                'Phone number',
                '${prefix.isNotEmpty ? '+$prefix ' : ''}${_phoneController.text.trim()}',
              ),
              DPReviewRow('Plan', (_selectedVariation?['name'] ?? '').toString()),
              if (foreign > 0)
                DPReviewRow('Recipient receives', _money(currency, foreign)),
              if (_nairaConversionRate > 0)
                DPReviewRow(
                  'Exchange rate',
                  '$currency 1 = ${DP.naira(_nairaConversionRate)}',
                ),
              const DPReviewRow('Service fee', '₦0.00'),
              DPReviewRow('You pay', DP.naira(_nairaToPay), strong: true),
            ],
            walletBalance: _walletBalance,
            totalDebit: _nairaToPay,
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
            footnote: 'International airtime can\'t be reversed once delivered.',
          ),
        ),
      ),
    );
  }







  Widget _buildLoadingAnimation() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 14),
          Text('Loading countries…', style: DP.caption),
        ],
      ),
    );
  }

  Widget _buildPurchaseButton() {
    return DPButton(
      label: 'Review international top-up',
      icon: DPIcons.forward,
      loading: _isProcessingPayment || _isAuthenticating,
      onPressed: _openPaymentSheet,
    );
  }


  Widget _buildCountrySelector() {
    final c = _selectedCountry;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const DPLabel('Destination country'),
        DPSelectField(
          value: c == null
              ? null
              : '${c['name'] ?? ''}  ·  ${c['currency'] ?? ''}',
          hint: 'Choose a country',
          leading: c == null
              ? const Icon(DPIcons.globe, color: DP.green, size: 20)
              : CountryFlagWidget(flagUrl: c['flag']?.toString(), size: 22),
          onTap: () async {
            final picked = await dpPickFromList<Map<String, dynamic>>(
              context,
              title: 'Destination country',
              items: _countries,
              selected: c,
              searchable: true,
              labelOf: (x) => (x['name'] ?? '').toString(),
              subtitleOf: (x) => (x['currency'] ?? '').toString(),
              leadingOf: (x) =>
                  CountryFlagWidget(flagUrl: x['flag']?.toString(), size: 22),
            );
            if (picked != null && mounted) _selectCountry(picked);
          },
        ),
      ],
    );
  }

  Widget _buildProductTypeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const DPLabel('Top-up type'),
        DPSelectField(
          value: _selectedProductType?['name']?.toString(),
          hint: _isLoadingProductTypes ? 'Loading…' : 'Choose a type',
          enabled: !_isLoadingProductTypes && _productTypes.isNotEmpty,
          onTap: () async {
            final picked = await dpPickFromList<Map<String, dynamic>>(
              context,
              title: 'Top-up type',
              items: _productTypes,
              selected: _selectedProductType,
              labelOf: (x) => (x['name'] ?? '').toString(),
            );
            if (picked != null && mounted) _selectProductType(picked);
          },
        ),
      ],
    );
  }

  Widget _buildOperatorSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const DPLabel('Mobile network'),
        DPSelectField(
          value: _selectedOperator?['name']?.toString(),
          hint: _isLoadingOperators ? 'Loading…' : 'Choose a network',
          enabled: !_isLoadingOperators && _operators.isNotEmpty,
          onTap: () async {
            final picked = await dpPickFromList<Map<String, dynamic>>(
              context,
              title: 'Mobile network',
              items: _operators,
              selected: _selectedOperator,
              labelOf: (x) => (x['name'] ?? '').toString(),
            );
            if (picked != null && mounted) _selectOperator(picked);
          },
        ),
      ],
    );
  }

  Widget _buildVariationSelector() {
    final currency = (_selectedCountry?['currency'] ?? '').toString();
    String labelFor(Map<String, dynamic> v) {
      final fixed = v['fixedPrice'] == 'Yes' || v['fixedPrice'] == true;
      final amt = double.tryParse(v['variation_amount']?.toString() ?? '');
      if (fixed && amt != null && amt > 0) return _money(currency, amt);
      return (v['name'] ?? 'Plan').toString();
    }

    if (_isLoadingVariations) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_variations.isEmpty) {
      return const DPBanner(
        'No plans are available for this network right now.',
        tone: DPTone.warning,
      );
    }

    final labels = _variations.map(labelFor).toList();
    final selectedLabel =
        _selectedVariation == null ? null : labelFor(_selectedVariation!);
    final allFixedShort = _variations.length <= 9 &&
        labels.every((l) => l.length <= 14);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const DPLabel('Recipient gets'),
        if (allFixedShort)
          DPChipGrid(
            options: labels,
            selected: selectedLabel,
            height: 46,
            onSelect: (l) => _selectVariation(_variations[labels.indexOf(l)]),
          )
        else
          DPSelectField(
            value: _selectedVariation?['name']?.toString(),
            hint: 'Choose a plan',
            onTap: () async {
              final picked = await dpPickFromList<Map<String, dynamic>>(
                context,
                title: 'Choose a plan',
                items: _variations,
                selected: _selectedVariation,
                labelOf: (x) => (x['name'] ?? '').toString(),
              );
              if (picked != null && mounted) _selectVariation(picked);
            },
          ),
      ],
    );
  }

  Widget _buildPhoneInput() {
    final prefix = (_selectedCountry?['prefix'] ?? '').toString();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const DPLabel('Recipient\'s phone number'),
        DPField(
          controller: _phoneController,
          focusNode: _phoneFocusNode,
          hint: 'Phone number',
          keyboardType: TextInputType.phone,
          prefixText: prefix.isNotEmpty ? '+$prefix  ' : null,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: (_) => setState(() {}),
          suffix: const Icon(DPIcons.contact, color: DP.muted),
        ),
      ],
    );
  }

  Widget _buildAmountInput() {
    final currency = (_selectedCountry?['currency'] ?? 'USD').toString();
    String? helper;
    if (!_isFixedPlan) {
      if (_variationMinAmount != null && _variationMaxAmount != null) {
        helper =
            'Minimum ${_money(currency, _variationMinAmount!)} · Maximum ${_money(currency, _variationMaxAmount!)}';
      } else if (_variationMinAmount != null) {
        helper = 'Minimum ${_money(currency, _variationMinAmount!)}';
      } else if (_variationMaxAmount != null) {
        helper = 'Maximum ${_money(currency, _variationMaxAmount!)}';
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DPLabel('Amount ($currency)'),
        DPField(
          controller: _amountController,
          focusNode: _amountFocusNode,
          hint: _isFixedPlan ? 'Set by the plan' : 'Enter amount',
          keyboardType: TextInputType.number,
          enabled: !_isFixedPlan,
          prefixText: '$currency  ',
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: (v) {
            _calculateNairaConversion(v);
            setState(() {});
          },
        ),
        if (helper != null) DPHelper(helper),
      ],
    );
  }



  Widget _buildEmailInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const DPLabel('Email for receipt (optional)'),
        DPField(
          controller: _emailController,
          hint: 'you@example.com',
          keyboardType: TextInputType.emailAddress,
          suffix: const Icon(DPIcons.mail, color: DP.muted),
        ),
      ],
    );
  }

  Widget _buildServiceUnavailable() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: DPEmptyState(
          icon: DPIcons.globe,
          title: 'International airtime is unavailable right now',
          message: 'Please try again in a little while.',
          actionLabel: 'Go back',
          onAction: () => Navigator.pop(context),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _amountController.dispose();
    _pinController.dispose();
    _emailController.dispose();
    _phoneFocusNode.dispose();
    _amountFocusNode.dispose();
    _pinFocusNode.dispose();
    _fadeController.dispose();
    _sheetController.dispose();
    _shakeController.dispose();
    super.dispose();
  }
}
