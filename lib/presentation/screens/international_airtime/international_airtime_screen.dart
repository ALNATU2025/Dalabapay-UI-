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
                Icon(Icons.error_outline, color: Colors.red.shade700, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    sanitizedTitle,
                    style: GoogleFonts.inter(
                      color: Colors.red.shade700,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
            content: Text(
              sanitizedMessage,
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
                    color: const Color(0xFF168566),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
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
        icon: const Icon(
          Icons.arrow_back_ios,
          color: Color(0xFF102C68),
          size: 20,
        ),
        onPressed: () => Navigator.pop(context),
      ),
      title: Text(
        'Intl Airtime',
        style: GoogleFonts.inter(
          color: const Color(0xFF102C68),
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
            color: const Color(0x05102C68),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.account_balance_wallet_outlined,
                color: Color(0xFF102C68),
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
                  style: GoogleFonts.inter(
                    color: const Color(0xFF102C68),
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
    if (_isLoadingUserData || _isLoadingCountries) {
      return _buildLoadingAnimation();
    }

    if (!_isUserActive || !_airtimeServiceEnabled) {
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
              _buildCountrySelector(),
              const SizedBox(height: 20),
              if (_selectedCountry != null) ...[
                _buildProductTypeSelector(),
                const SizedBox(height: 20),
                if (_selectedProductType != null) ...[
                  _buildOperatorSelector(),
                  const SizedBox(height: 20),
                  if (_selectedOperator != null) ...[
                    _buildVariationSelector(),
                    const SizedBox(height: 20),
                    _buildPhoneInput(),
                    const SizedBox(height: 20),
                    _buildAmountInput(),
                    const SizedBox(height: 20),
                    _buildEmailInput(),
                    const SizedBox(height: 24),
                    _buildPurchaseButton(),
                  ],
                ],
              ],
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDropdownButton({
    required String label,
    required String? selectedValue,
    required List<Map<String, dynamic>> items,
    required String itemIdKey,
    required String itemNameKey,
    required Function(Map<String, dynamic>) onSelected,
    required bool isLoading,
    bool showImage = false,
    String? imageKey,
    required bool isOpen,
    required void Function(bool) onOpenChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF102C68),
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () {
            if (!isLoading && items.isNotEmpty) {
              onOpenChanged(!isOpen);
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isOpen ? const Color(0xFF102C68) : Colors.grey.shade200,
                width: isOpen ? 2 : 1,
              ),
              boxShadow:
                  isOpen
                      ? [
                        BoxShadow(
                          color: const Color(0xFF102C68).withOpacity(0.1),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ]
                      : null,
            ),
            child: Row(
              children: [
                if (showImage && selectedValue != null && imageKey != null) ...[
                  _buildOperatorImage(
                    _selectedOperator?['operator_id']?.toString() ?? '',
                    imageKey,
                    size: 32,
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        selectedValue ??
                            (isLoading ? 'Loading...' : 'Select...'),
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color:
                              selectedValue != null
                                  ? Colors.black87
                                  : Colors.grey.shade500,
                        ),
                      ),
                      if (isLoading)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                const Color(0xFF102C68),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Icon(
                  isOpen
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: const Color(0xFF102C68),
                  size: 24,
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          child:
              (isOpen && !isLoading && items.isNotEmpty)
                  ? Container(
                    margin: const EdgeInsets.only(top: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.grey.shade200),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.shade200.withOpacity(0.5),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 220),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final item = items[index];
                          final itemId = item[itemIdKey]?.toString() ?? '';
                          final isSelected = _selectedItemId == itemId;

                          return ListTile(
                            leading:
                                showImage && imageKey != null
                                    ? _buildOperatorImage(
                                      item[itemIdKey]?.toString() ?? '',
                                      imageKey,
                                      size: 32,
                                    )
                                    : (itemIdKey == 'product_type_id')
                                    ? Container(
                                      width: 32,
                                      height: 32,
                                      decoration: BoxDecoration(
                                        color: const Color(
                                          0xFF102C68,
                                        ).withOpacity(0.08),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Icon(
                                        item['product_type_id'] == 4
                                            ? Icons.wifi_rounded
                                            : Icons.smartphone_rounded,
                                        color: const Color(0xFF102C68),
                                        size: 18,
                                      ),
                                    )
                                    : null,
                            title: Text(
                              item[itemNameKey] ?? 'Unknown',
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight:
                                    isSelected
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                color:
                                    isSelected
                                        ? const Color(0xFF102C68)
                                        : Colors.black87,
                              ),
                            ),
                            trailing:
                                isSelected
                                    ? Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: const BoxDecoration(
                                        color: Color(0xFF168566),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.check_rounded,
                                        color: Colors.white,
                                        size: 14,
                                      ),
                                    )
                                    : null,
                            onTap: () => onSelected(item),
                            dense: false,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                          );
                        },
                      ),
                    ),
                  )
                  : const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _buildOperatorImage(
    String operatorId,
    String imageKey, {
    double size = 24,
  }) {
    // ✅ Look up the operator safely
    Map<String, dynamic> operator = {};
    try {
      operator = _operators.firstWhere(
        (op) => op['operator_id']?.toString() == operatorId,
        orElse: () => {},
      );
    } catch (_) {
      operator = {};
    }

    // ✅ Try multiple possible image keys
    final rawUrl =
        (operator[imageKey] ??
                operator['operator_image'] ??
                operator['image'] ??
                operator['logo'] ??
                '')
            .toString()
            .trim();

    // ✅ Route the image through OUR backend to bypass network blocks
    // The backend already validates that only vtpass.com/.../operators/ URLs pass through.
    final String proxiedUrl =
        (rawUrl.isNotEmpty && rawUrl.startsWith('https://vtpass.com/'))
            ? '${ApiService.baseUrl}/api/operator-logo?url=${Uri.encodeComponent(rawUrl)}'
            : rawUrl;

    debugPrint('🖼️ Operator image [$operatorId]: "$proxiedUrl"');

    if (proxiedUrl.isNotEmpty && proxiedUrl.startsWith('http')) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(6),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.network(
            proxiedUrl,
            width: size,
            height: size,
            fit: BoxFit.contain,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return Center(
                child: SizedBox(
                  width: size * 0.5,
                  height: size * 0.5,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      const Color(0xFF102C68),
                    ),
                  ),
                ),
              );
            },
            errorBuilder: (context, error, stackTrace) {
              debugPrint('❌ Image load failed for $operatorId: $error');
              return Icon(
                Icons.business_center,
                size: size * 0.7,
                color: const Color(0xFF102C68),
              );
            },
          ),
        ),
      );
    }

    // ✅ No URL — show fallback icon
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFF102C68).withOpacity(0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(
        Icons.business_center,
        size: size * 0.7,
        color: const Color(0xFF102C68),
      ),
    );
  }

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
                                        child: const Icon(
                                          Icons.close,
                                          size: 18,
                                          color: Color(0xFF728078),
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
                                  color: const Color(0xFF14263D),
                                ),
                              ),
                              const SizedBox(height: 16),
                              _buildPaymentSheetDetails(),
                              const SizedBox(height: 16),
                              _buildPaymentSheetBalance(),
                              const SizedBox(height: 20),
                              Divider(
                                color: Colors.grey.shade200,
                                thickness: 1,
                              ),
                              const SizedBox(height: 20),
                              if (_transactionPinSet) ...[
                                _buildPinOption(),
                                const SizedBox(height: 12),
                              ],
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
                                      Icon(
                                        Icons.warning_amber,
                                        color: Colors.orange.shade700,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          'Set up a transaction PIN or enable biometric in Settings to make payments.',
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
    final currency = _selectedCountry?['currency'] ?? 'USD';
    final phone = _phoneController.text.trim();
    final amount = double.tryParse(_amountController.text) ?? 0;

    // ✅ Get Naira amount from variation or calculation
    double nairaAmount = 0;
    if (_nairaEstimate.isNotEmpty) {
      nairaAmount =
          double.tryParse(
            _nairaEstimate.replaceAll('₦', '').replaceAll(',', ''),
          ) ??
          0;
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          _buildPaymentRow(
            icon: HugeIcons.strokeRoundedGlobal,
            label: 'Country',
            value: _selectedCountry?['name'] ?? 'N/A',
          ),
          _buildPaymentDivider(),
          _buildPaymentRow(
            icon: HugeIcons.strokeRoundedUser,
            label: 'Operator',
            value: _selectedOperator?['name'] ?? 'N/A',
          ),
          _buildPaymentDivider(),
          _buildPaymentRow(
            icon: HugeIcons.strokeRoundedCertificate01,
            label: 'Plan',
            value: _selectedVariation?['name'] ?? 'N/A',
          ),
          _buildPaymentDivider(),
          _buildPaymentRow(
            icon: HugeIcons.strokeRoundedSmartPhone01,
            label: 'Phone',
            value: phone.isNotEmpty ? phone : 'N/A',
          ),
          _buildPaymentDivider(),
          _buildPaymentRow(
            icon: HugeIcons.strokeRoundedMoney01,
            label: 'Amount',
            value: '$currency ${amount.toStringAsFixed(2)}',
            valueColor: const Color(0xFF102C68),
          ),
          // ✅ Show Naira amount prominently
          if (nairaAmount > 0) ...[
            _buildPaymentDivider(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: [Color(0xFF5BB592), Color(0xFF102C68)],
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  HugeIcon(
                    icon: HugeIcons.strokeRoundedMoney03,
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'You will pay',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: Colors.white70,
                        ),
                      ),
                      Text(
                        '₦${nairaAmount.toStringAsFixed(2)}',
                        style: GoogleFonts.inter(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPaymentRow({
    required dynamic icon,
    required String label,
    required String value,
    Color? valueColor,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF102C68).withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: HugeIcon(
                icon: icon,
                color: const Color(0xFF102C68),
                size: 18,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF728078),
              ),
            ),
          ],
        ),
        Flexible(
          child: Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: valueColor ?? const Color(0xFF14263D),
            ),
            textAlign: TextAlign.right,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildPaymentDivider() {
    return const Divider(height: 12, color: Color(0xFFE2E8F0));
  }

  Widget _buildPaymentSheetBalance() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF168566).withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF168566).withOpacity(0.15)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                HugeIcon(
                  icon: HugeIcons.strokeRoundedWallet01,
                  color: const Color(0xFF168566),
                  size: 16,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'Available Balance',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF728078),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              '₦${_walletBalance.toStringAsFixed(2)}',
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF168566),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

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
                    : (_useBiometric
                        ? Colors.grey.shade50
                        : const Color(0xFF102C68).withOpacity(0.04)),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color:
                  hasError
                      ? const Color(0xFFC0392B)
                      : (_useBiometric
                          ? Colors.grey.shade300
                          : const Color(0xFF102C68)),
              width: hasError ? 2 : (_useBiometric ? 1 : 2),
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
                  enabled: !_useBiometric,
                  decoration: InputDecoration(
                    hintText: 'Enter transaction PIN',
                    hintStyle: GoogleFonts.inter(
                      color:
                          hasError
                              ? const Color(0xFFC0392B).withOpacity(0.7)
                              : (_useBiometric
                                  ? Colors.grey.shade400
                                  : Colors.grey.shade600),
                      fontSize: 13,
                    ),
                    prefixIcon: Icon(
                      Icons.lock_outline_rounded,
                      color:
                          hasError
                              ? const Color(0xFFC0392B)
                              : (_useBiometric
                                  ? Colors.grey.shade400
                                  : const Color(0xFF102C68)),
                      size: 20,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color:
                        hasError
                            ? const Color(0xFFC0392B)
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
                      _isProcessingPayment || _useBiometric
                          ? null
                          : _processPaymentWithPIN,
                  style: TextButton.styleFrom(
                    backgroundColor:
                        hasError
                            ? const Color(0xFFC0392B)
                            : (_useBiometric
                                ? Colors.transparent
                                : const Color(0xFF168566)),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          hasError
                              ? const BorderRadius.vertical(
                                bottom: Radius.circular(12),
                              )
                              : BorderRadius.circular(12),
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
                                hasError
                                    ? 'Retry'
                                    : (_useBiometric
                                        ? 'Switch to PIN'
                                        : 'Pay with PIN'),
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
            color: const Color(0xFF102C68).withOpacity(0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF102C68), width: 1.5),
          ),
          child:
              _isProcessingPayment && _useBiometric
                  ? const Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        color: Color(0xFF102C68),
                        strokeWidth: 2.5,
                      ),
                    ),
                  )
                  : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.fingerprint_rounded,
                        color: Color(0xFF102C68),
                        size: 28,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Pay with $_biometricName',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF102C68),
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Color(0xFF168566),
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

  Widget _buildLoadingAnimation() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(shape: BoxShape.circle),
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(
                const Color(0xFF102C68),
              ),
              strokeWidth: 3,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _isLoadingCountries ? 'Loading countries...' : 'Loading...',
            style: GoogleFonts.inter(
              color: const Color(0xFF102C68),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _isLoadingCountries
                ? 'Please wait while we fetch available countries'
                : 'Please wait...',
            style: GoogleFonts.inter(
              color: Colors.grey.shade500,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPurchaseButton() {
    final isFlexible =
        _selectedVariation?['fixedPrice'] == 'No' ||
        _selectedVariation?['fixedPrice'] == false;
    final bool isAmountValid =
        _amountController.text.isNotEmpty &&
        double.tryParse(_amountController.text) != null;

    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed:
            (_isPurchasing || _isLoadingVariations || _isAuthenticating)
                ? null
                : _openPaymentSheet,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF168566),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 0,
          disabledBackgroundColor: Colors.grey.shade300,
        ),
        child:
            _isPurchasing || _isAuthenticating
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
                      _selectedVariation != null
                          ? (isFlexible && !isAmountValid
                              ? 'Enter amount above'
                              : 'Continue')
                          : 'Select a Plan First',
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
      ),
    );
  }

  Widget _buildBanner() {
    return Container(
      width: double.infinity,
      height: 140,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF102C68).withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Image.asset(
          'assets/int_airtime_banner.png',
          width: double.infinity,
          height: 140,
          fit: BoxFit.cover,
          // ✅ Fallback if asset fails to load (e.g. forgot pubspec, wrong path)
          errorBuilder: (context, error, stackTrace) {
            debugPrint('❌ Banner asset load failed: $error');
            return Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF102C68),
                    Color(0xFF102C68),
                    Color(0xFF168566),
                  ],
                ),
              ),
              child: Center(
                child: Text(
                  'International Airtime',
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildCountrySelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Select Country',
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF102C68),
              ),
            ),
            if (_countries.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF102C68).withOpacity(0.08),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${_countries.length} countries',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF102C68),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  onChanged: _filterCountries,
                  decoration: InputDecoration(
                    hintText: 'Search country...',
                    hintStyle: GoogleFonts.inter(
                      color: Colors.grey.shade400,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                    prefixIcon: HugeIcon(
                      icon: HugeIcons.strokeRoundedSearch01,
                      color: const Color(0xFF102C68),
                      size: 20,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  style: GoogleFonts.inter(fontSize: 14),
                ),
              ),
              const Divider(height: 1),
              _filteredCountries.isEmpty
                  ? Padding(
                    padding: const EdgeInsets.all(20),
                    child: Center(
                      child: Text(
                        'No countries found',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  )
                  : SizedBox(
                    height: 180,
                    child: ListView.builder(
                      itemCount: _filteredCountries.length,
                      itemBuilder: (context, index) {
                        final country = _filteredCountries[index];
                        final isSelected =
                            _selectedCountry?['code'] == country['code'];
                        final flagUrl = country['flag']?.toString() ?? '';
                        final countryName =
                            country['name']?.toString() ?? 'Unknown';
                        final countryCode = country['code']?.toString() ?? '';

                        return ListTile(
                          leading: CountryFlagWidget(
                            flagUrl: flagUrl,
                            size: 36,
                          ),
                          title: Text(
                            countryName,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight:
                                  isSelected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                              color:
                                  isSelected
                                      ? const Color(0xFF102C68)
                                      : Colors.black87,
                            ),
                          ),
                          subtitle: Text(
                            countryCode,
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          trailing:
                              isSelected
                                  ? Icon(
                                    Icons.check_circle,
                                    color: const Color(0xFF168566),
                                    size: 20,
                                  )
                                  : null,
                          onTap: () => _selectCountry(country),
                          dense: true,
                        );
                      },
                    ),
                  ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProductTypeSelector() {
    return _buildDropdownButton(
      label: 'Product Type',
      selectedValue: _selectedProductType?['name']?.toString(),
      items: _productTypes,
      itemIdKey: 'product_type_id',
      itemNameKey: 'name',
      onSelected: (item) => _selectProductType(item),
      isLoading: _isLoadingProductTypes,
      isOpen: _isProductTypeDropdownOpen,
      onOpenChanged: (value) {
        setState(() {
          _isProductTypeDropdownOpen = value;
          if (value) _isOperatorDropdownOpen = false;
        });
      },
    );
  }

  Widget _buildOperatorSelector() {
    _log('📱 Building operator selector');
    _log('📱 Operators count: ${_operators.length}');

    // Log all operators
    for (var op in _operators) {
      _log('  📌 Available: ${op['name']} (ID: ${op['operator_id']})');
    }

    _log('📱 Selected operator: ${_selectedOperator?['name']}');
    _log('📱 Selected operator ID: ${_selectedOperator?['operator_id']}');

    return _buildDropdownButton(
      label: 'Operator',
      selectedValue: _selectedOperator?['name']?.toString(),
      items: _operators,
      itemIdKey: 'operator_id',
      itemNameKey: 'name',
      onSelected: (item) {
        _log('📱 Operator selected from dropdown:');
        _log('  📌 Name: ${item['name']}');
        _log('  📌 ID: ${item['operator_id']}');
        _selectOperator(item);
      },
      isLoading: _isLoadingOperators,
      showImage: true,
      imageKey: 'operator_image',
      isOpen: _isOperatorDropdownOpen,
      onOpenChanged: (value) {
        setState(() {
          _isOperatorDropdownOpen = value;
          if (value) _isProductTypeDropdownOpen = false;
        });
      },
    );
  }

  Widget _buildVariationSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Select Plan',
          style: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF102C68),
          ),
        ),
        const SizedBox(height: 8),
        _isLoadingVariations
            ? Center(
              child: Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(shape: BoxShape.circle),
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    const Color(0xFF102C68),
                  ),
                ),
              ),
            )
            : _variations.isEmpty
            ? Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Center(
                child: Text(
                  'No plans available for this operator',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            )
            : Container(
              height: 220,
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: ListView.builder(
                itemCount: _variations.length,
                itemBuilder: (context, index) {
                  final variation = _variations[index];
                  final isSelected =
                      _selectedVariation?['variation_code'] ==
                      variation['variation_code'];
                  final isFixed =
                      variation['fixedPrice'] == 'Yes' ||
                      variation['fixedPrice'] == true;

                  String amountDisplay = '';
                  String nairaDisplay = '';

                  // ✅ Safely parse variation_amount (may be bool/string/number/null)
                  final rawAmount = variation['variation_amount'];
                  double? parsedAmount;
                  if (rawAmount is num) {
                    parsedAmount = rawAmount.toDouble();
                  } else if (rawAmount is String) {
                    parsedAmount = double.tryParse(rawAmount);
                  }

                  if (isFixed) {
                    amountDisplay =
                        parsedAmount != null
                            ? '${_selectedCountry?['currency'] ?? 'USD'} ${parsedAmount.toStringAsFixed(2)}'
                            : '${_selectedCountry?['currency'] ?? 'USD'} 0.00';

                    // ✅ Safely parse charged_amount (VTpass sometimes returns `false` here)
                    final rawCharged = variation['charged_amount'];
                    double? parsedCharged;
                    if (rawCharged is num) {
                      parsedCharged = rawCharged.toDouble();
                    } else if (rawCharged is String) {
                      parsedCharged = double.tryParse(rawCharged);
                    }
                    // Note: `false`, `null`, empty strings → parsedCharged stays null

                    if (parsedCharged != null && parsedCharged > 0) {
                      nairaDisplay = '₦${parsedCharged.toStringAsFixed(2)}';
                    }
                  } else {
                    amountDisplay = 'Flexible amount';

                    // ✅ Extract min/max from VTpass response
                    double? parsedMin;
                    final rawMin = variation['variation_amount_min'];
                    if (rawMin is num) {
                      parsedMin = rawMin.toDouble();
                    } else if (rawMin is String) {
                      parsedMin = double.tryParse(rawMin);
                    }

                    double? parsedMax;
                    final rawMax = variation['variation_amount_max'];
                    if (rawMax is num) {
                      parsedMax = rawMax.toDouble();
                    } else if (rawMax is String) {
                      parsedMax = double.tryParse(rawMax);
                    }

                    // ✅ Build min/max display text
                    final currency = _selectedCountry?['currency'] ?? '';
                    if (parsedMin != null && parsedMax != null) {
                      amountDisplay =
                          'Flexible: $currency ${parsedMin.toStringAsFixed(2)} - $currency ${parsedMax.toStringAsFixed(2)}';
                    } else if (parsedMin != null) {
                      amountDisplay =
                          'Flexible: Min $currency ${parsedMin.toStringAsFixed(2)}';
                    } else if (parsedMax != null) {
                      amountDisplay =
                          'Flexible: Max $currency ${parsedMax.toStringAsFixed(2)}';
                    } else {
                      amountDisplay = 'Flexible amount';
                    }

                    // ✅ Also show the rate if available
                    final rawRate = variation['variation_rate'];
                    double? parsedRate;
                    if (rawRate is num) {
                      parsedRate = rawRate.toDouble();
                    } else if (rawRate is String) {
                      parsedRate = double.tryParse(rawRate);
                    }

                    if (parsedRate != null && parsedRate > 0) {
                      nairaDisplay =
                          'Rate: ₦${parsedRate.toStringAsFixed(2)}/$currency';
                    }
                  }

                  return ListTile(
                    title: Text(
                      variation['name'] ?? 'Unknown Plan',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight:
                            isSelected ? FontWeight.w700 : FontWeight.w500,
                        color:
                            isSelected
                                ? const Color(0xFF102C68)
                                : Colors.black87,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          amountDisplay,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color:
                                isFixed
                                    ? Colors.grey.shade700
                                    : Colors.blue.shade600,
                          ),
                        ),
                        if (nairaDisplay.isNotEmpty)
                          Text(
                            nairaDisplay,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF168566),
                            ),
                          ),
                      ],
                    ),
                    trailing:
                        isSelected
                            ? Icon(
                              Icons.check_circle,
                              color: const Color(0xFF168566),
                              size: 20,
                            )
                            : null,
                    onTap: () => _selectVariation(variation),
                    dense: false,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                  );
                },
              ),
            ),
      ],
    );
  }

  Widget _buildPhoneInput() {
    final prefix = _selectedCountry?['prefix'] ?? '';
    final prefixDisplay = prefix.isNotEmpty ? '+$prefix' : '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Phone Number',
          style: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF102C68),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(
            children: [
              if (prefixDisplay.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(14),
                      bottomLeft: Radius.circular(14),
                    ),
                  ),
                  child: Text(
                    prefixDisplay,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF102C68),
                    ),
                  ),
                ),
              Expanded(
                child: TextField(
                  controller: _phoneController,
                  focusNode: _phoneFocusNode,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    hintText: 'Enter phone number',
                    hintStyle: GoogleFonts.inter(
                      color: Colors.grey.shade400,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    border: OutlineInputBorder(
                      borderRadius:
                          prefixDisplay.isNotEmpty
                              ? const BorderRadius.only(
                                topRight: Radius.circular(14),
                                bottomRight: Radius.circular(14),
                              )
                              : BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    prefixIcon:
                        prefixDisplay.isEmpty
                            ? HugeIcon(
                              icon: HugeIcons.strokeRoundedSmartPhone01,
                              color: const Color(0xFF102C68),
                              size: 22,
                            )
                            : null,
                    filled: true,
                    fillColor: Colors.transparent,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                  ),
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAmountInput() {
    final currency = _selectedCountry?['currency'] ?? 'USD';
    final isFixed =
        _selectedVariation?['fixedPrice'] == 'Yes' ||
        _selectedVariation?['fixedPrice'] == true;

    // ✅ Build dynamic hint text with min/max
    String hintText;
    if (isFixed) {
      hintText = 'Fixed amount (auto-filled)';
    } else if (_variationMinAmount != null && _variationMaxAmount != null) {
      hintText =
          'Enter $currency ${_variationMinAmount!.toStringAsFixed(2)} - ${_variationMaxAmount!.toStringAsFixed(2)}';
    } else if (_variationMinAmount != null) {
      hintText =
          'Minimum: $currency ${_variationMinAmount!.toStringAsFixed(2)}';
    } else if (_variationMaxAmount != null) {
      hintText =
          'Maximum: $currency ${_variationMaxAmount!.toStringAsFixed(2)}';
    } else {
      hintText = 'Enter amount';
    }

    // ✅ Build helper text for display below field
    String? helperText;
    if (!isFixed &&
        (_variationMinAmount != null || _variationMaxAmount != null)) {
      if (_variationMinAmount != null && _variationMaxAmount != null) {
        helperText =
            'Allowed range: $currency ${_variationMinAmount!.toStringAsFixed(2)} - ${_variationMaxAmount!.toStringAsFixed(2)}';
      } else if (_variationMinAmount != null) {
        helperText =
            'Minimum amount: $currency ${_variationMinAmount!.toStringAsFixed(2)}';
      } else if (_variationMaxAmount != null) {
        helperText =
            'Maximum amount: $currency ${_variationMaxAmount!.toStringAsFixed(2)}';
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          isFixed ? 'Amount (Fixed)' : 'Amount',
          style: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF102C68),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: isFixed ? Colors.grey.shade100 : Colors.grey.shade50,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: TextField(
            controller: _amountController,
            focusNode: _amountFocusNode,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            enabled: !isFixed,
            decoration: InputDecoration(
              hintText: hintText,
              hintStyle: GoogleFonts.inter(
                color: isFixed ? Colors.grey.shade500 : Colors.grey.shade400,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              prefixIcon: Container(
                padding: const EdgeInsets.only(left: 16, right: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      currency,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF102C68),
                      ),
                    ),
                  ],
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
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
            onChanged: _calculateNairaConversion,
          ),
        ),
        // ✅ NEW: Beautiful range card for flexible plans
        if (!isFixed &&
            (_variationMinAmount != null || _variationMaxAmount != null))
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: _buildRangeCard(
              currency: currency,
              min: _variationMinAmount,
              max: _variationMaxAmount,
            ),
          ),
        // ✅ Show Naira amount prominently
        if (_nairaEstimate.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: [Color(0xFF5BB592), Color(0xFF102C68)],
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF102C68).withValues(alpha: 0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: HugeIcon(
                      icon: HugeIcons.strokeRoundedMoney03,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'You will pay',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: Colors.white70,
                          ),
                        ),
                        Text(
                          _nairaEstimate,
                          style: GoogleFonts.inter(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_nairaConversionRate > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '1 ${_selectedCountry?['currency'] ?? ''} = ₦${_nairaConversionRate.toStringAsFixed(2)}',
                        style: GoogleFonts.inter(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  /// ✅ Beautiful min/max range card for flexible international airtime plans.
  /// Matches the visual style of the "You will pay" gradient card.
  Widget _buildRangeCard({
    required String currency,
    required double? min,
    required double? max,
  }) {
    final bool hasBoth = min != null && max != null;
    final bool hasOnlyMin = min != null && max == null;
    final bool hasOnlyMax = min == null && max != null;

    if (!hasBoth && !hasOnlyMin && !hasOnlyMax) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        // Soft blue tint — matches the app's info-card style
        color: const Color(0xFF102C68).withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF102C68).withOpacity(0.15),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          // Icon chip
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: const Color(0xFF102C68).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.tune_rounded,
              color: Color(0xFF102C68),
              size: 16,
            ),
          ),
          const SizedBox(width: 12),

          // Main content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasBoth
                      ? 'Allowed range'
                      : hasOnlyMin
                      ? 'Minimum amount'
                      : 'Maximum amount',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF728078),
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 2),

                // Value pills row
                Row(
                  children: [
                    if (min != null) ...[
                      _buildRangePill(
                        label: hasBoth ? 'Min' : 'Minimum',
                        value: '$currency ${min.toStringAsFixed(2)}',
                        isMin: true,
                      ),
                    ],
                    if (hasBoth) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Icon(
                          Icons.arrow_forward_rounded,
                          size: 14,
                          color: const Color(0xFF728078).withOpacity(0.6),
                        ),
                      ),
                    ],
                    if (max != null)
                      _buildRangePill(
                        label: hasBoth ? 'Max' : 'Maximum',
                        value: '$currency ${max.toStringAsFixed(2)}',
                        isMin: false,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRangePill({
    required String label,
    required String value,
    required bool isMin,
  }) {
    // Green for min (start), navy for max (ceiling)
    final pillColor = isMin ? const Color(0xFF168566) : const Color(0xFF102C68);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: pillColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: pillColor.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: pillColor.withOpacity(0.7),
            ),
          ),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: pillColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmailInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Email (Optional)',
          style: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF102C68),
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
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              hintText: 'Enter email for receipt',
              hintStyle: GoogleFonts.inter(
                color: Colors.grey.shade400,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              prefixIcon: HugeIcon(
                icon: HugeIcons.strokeRoundedMail01,
                color: const Color(0xFF102C68),
                size: 22,
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
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildServiceUnavailable() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              !_isUserActive ? Icons.account_circle : Icons.phone_disabled,
              color:
                  !_isUserActive ? Colors.red.shade700 : Colors.orange.shade700,
              size: 60,
            ),
            const SizedBox(height: 16),
            Text(
              !_isUserActive ? 'Account Deactivated' : 'Service Unavailable',
              style: GoogleFonts.inter(
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
                  : 'International airtime service is currently unavailable. Please try again later.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF102C68),
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
                style: GoogleFonts.inter(
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
