// lib/presentation/screens/international_airtime/international_airtime_screen.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dalabapay/core/services/biometric_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;

import '../../../core/services/api_service.dart';
import '../../../ui/ui.dart';
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
    final displayMsg = attemptsRemaining != null
        ? '$message ($attemptsRemaining ${attemptsRemaining == 1 ? 'attempt' : 'attempts'} remaining)'
        : message;
    dpSnack(context, displayMsg, error: true);
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

  // Operators could not be loaded. We no longer show made-up operators
  // (their IDs don't exist at VTpass); the UI offers a retry instead.
  List<Map<String, dynamic>> _getFallbackOperators(String countryCode) => [];

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

  // Plans could not be loaded. Made-up plans are no longer shown.
  List<Map<String, dynamic>> _getFallbackVariations(String operatorId) => [];

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
    showDPDialog(
      context,
      tone: DPDialogTone.error,
      title: _sanitizeMessage(title),
      message: _sanitizeMessage(message),
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
    final ready = !(_isLoadingUserData || _isLoadingCountries) &&
        _isUserActive &&
        _airtimeServiceEnabled &&
        _selectedOperator != null;
    return Stack(
      children: [
        DPPage(
          title: 'International airtime',
          bottom: ready ? _buildPurchaseButton() : null,
          children: [_buildBody()],
        ),
        if (_showPaymentSheet) _buildPaymentSheetOverlay(),
      ],
    );
  }


  Widget _buildBody() {
    if (_isLoadingUserData || _isLoadingCountries) return _buildLoadingAnimation();
    if (!_isUserActive || !_airtimeServiceEnabled) return _buildServiceUnavailable();
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const DPHeadline('Send a little connection.',
                subtitle: 'Top up a loved one’s number abroad.'),
            _buildCountrySelector(),
            if (_selectedCountry != null) ...[
              _buildProductTypeSelector(),
              if (_selectedProductType != null) ...[
                _buildOperatorSelector(),
                if (_selectedOperator != null) ...[
                  _buildPhoneInput(),
                  _buildVariationSelector(),
                  _buildAmountInput(),
                  _buildEmailInput(),
                  const DPNotice(
                    'Indicative quote. Rates may change before payment. Confirm the country and network — airtime can’t be reversed once delivered.',
                    kind: DPNoticeKind.warn,
                    margin: EdgeInsets.zero,
                  ),
                ],
              ],
            ],
          ],
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
    return DPSelectField(
      label: label,
      value: selectedValue,
      hint: isLoading ? 'Loading…' : (items.isEmpty ? 'Nothing available' : 'Select'),
      loading: isLoading,
      leading: showImage && selectedValue != null && imageKey != null
          ? _buildOperatorImage(_selectedOperator?['operator_id']?.toString() ?? '', imageKey, size: 28)
          : null,
      onTap: items.isEmpty
          ? null
          : () => showDPSheet(
                context,
                title: label,
                builder: (ctx) => Column(
                  children: [
                    for (final item in items)
                      DPOptionRow(
                        leading: showImage && imageKey != null
                            ? _buildOperatorImage(item[itemIdKey]?.toString() ?? '', imageKey, size: 30)
                            : null,
                        title: item[itemNameKey]?.toString() ?? 'Unknown',
                        selected: (item[itemNameKey]?.toString() ?? '') == selectedValue,
                        onTap: () {
                          Navigator.pop(ctx);
                          onSelected(item);
                        },
                      ),
                  ],
                ),
              ),
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
    final currency = _selectedCountry?['currency'] ?? 'USD';
    final phone = _phoneController.text.trim();
    final amount = double.tryParse(_amountController.text) ?? 0;
    double nairaAmount = 0;
    if (_nairaEstimate.isNotEmpty) {
      nairaAmount = double.tryParse(_nairaEstimate.replaceAll('₦', '').replaceAll(',', '')) ?? 0;
    }
    final bool isBiometricSupported = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
    final canBiometric = isBiometricSupported && _biometricEnabled && _biometricAllowed;
    return DPSheetOverlay(
      animation: _sheetAnimation,
      onDismiss: _isProcessingPayment ? null : _closePaymentSheet,
      child: DPPaymentReview(
        icon: DPIcons.globe,
        serviceLabel: '${_selectedOperator?['name'] ?? 'International'} · ${_selectedCountry?['name'] ?? ''}',
        amount: nairaAmount,
        rows: [
          DPSummaryRow('Recipient', '+${_selectedCountry?['prefix'] ?? ''} $phone'),
          DPSummaryRow('Plan', _selectedVariation?['name']?.toString() ?? '—'),
          DPSummaryRow('Recipient receives', '$currency ${amount.toStringAsFixed(2)}'),
          if (_nairaConversionRate > 0)
            DPSummaryRow('Exchange rate', '$currency 1 = ₦${_nairaConversionRate.toStringAsFixed(2)}'),
          DPSummaryRow('You pay', nairaAmount > 0 ? dpNaira(nairaAmount) : '—', emphasize: true),
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
        footnote: 'Indicative quote. Airtime can’t be reversed once delivered.',
      ),
    );
  }







  Widget _buildLoadingAnimation() {
    return const Padding(
      padding: EdgeInsets.only(top: 80),
      child: DPLoader(message: 'Loading countries…'),
    );
  }

  Widget _buildPurchaseButton() {
    final isFlexible =
        _selectedVariation?['fixedPrice'] == 'No' || _selectedVariation?['fixedPrice'] == false;
    final bool isAmountValid =
        _amountController.text.isNotEmpty && double.tryParse(_amountController.text) != null;
    return DPButton(
      label: _selectedVariation != null
          ? (isFlexible && !isAmountValid ? 'Enter an amount' : 'Review international top-up')
          : 'Choose a plan first',
      icon: DPIcons.arrowRight,
      loading: _isPurchasing || _isAuthenticating,
      onPressed: (_isPurchasing || _isLoadingVariations || _isAuthenticating) ? null : _openPaymentSheet,
    );
  }


  Widget _buildCountrySelector() {
    final sel = _selectedCountry;
    return DPSelectField(
      label: 'Destination country',
      value: sel == null ? null : '${sel['name']} · ${sel['currency'] ?? ''}',
      hint: _countries.isEmpty ? 'No countries available' : 'Choose a country',
      leading: sel == null
          ? null
          : CountryFlagWidget(flagUrl: sel['flag']?.toString() ?? '', size: 26),
      onTap: _countries.isEmpty
          ? null
          : () {
              _filterCountries('');
              showDPSheet(
                context,
                title: 'Destination country',
                scrollable: false,
                builder: (ctx) => StatefulBuilder(
                  builder: (ctx, setSheet) => Flexible(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        DPField(
                          hint: 'Search country',
                          suffixIcon: DPIcons.search,
                          onChanged: (q) {
                            _filterCountries(q);
                            setSheet(() {});
                          },
                        ),
                        Flexible(
                          child: _filteredCountries.isEmpty
                              ? const DPEmptyState(icon: DPIcons.globe, title: 'No countries found')
                              : ListView.builder(
                                  shrinkWrap: true,
                                  itemCount: _filteredCountries.length,
                                  itemBuilder: (_, i) {
                                    final c = _filteredCountries[i];
                                    return DPOptionRow(
                                      leading: CountryFlagWidget(
                                          flagUrl: c['flag']?.toString() ?? '', size: 28),
                                      title: c['name']?.toString() ?? 'Unknown',
                                      subtitle: c['currency']?.toString(),
                                      selected: _selectedCountry?['code'] == c['code'],
                                      onTap: () {
                                        Navigator.pop(ctx);
                                        _selectCountry(c);
                                      },
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
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
    final currency = _selectedCountry?['currency'] ?? '';
    double? parse(dynamic v) => v is num ? v.toDouble() : (v is String ? double.tryParse(v) : null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const DPFieldLabel('Recipient gets'),
        if (_isLoadingVariations)
          const DPLoader()
        else if (_variations.isEmpty)
          DPCard(
            child: DPEmptyState(
              icon: DPIcons.circleAlert,
              title: 'No plans available',
              message: 'This network has no plans right now. Try again or choose another network.',
              actionLabel: 'Retry',
              onAction: () => _fetchVariations(
                _selectedOperator?['operator_id']?.toString() ?? '',
                (_selectedProductType?['product_type_id'] as num?)?.toInt() ?? 1,
              ),
            ),
          )
        else
          ..._variations.map((variation) {
            final isSelected = _selectedVariation?['variation_code'] == variation['variation_code'];
            final isFixed = variation['fixedPrice'] == 'Yes' || variation['fixedPrice'] == true;
            String? sub;
            String? trailing;
            if (isFixed) {
              final amt = parse(variation['variation_amount']);
              trailing = amt != null ? '$currency ${amt.toStringAsFixed(2)}' : null;
              final charged = parse(variation['charged_amount']);
              if (charged != null && charged > 0) sub = 'You pay ${dpNaira(charged)}';
            } else {
              final mn = parse(variation['variation_amount_min']);
              final mx = parse(variation['variation_amount_max']);
              sub = mn != null && mx != null
                  ? 'Any amount: $currency ${mn.toStringAsFixed(2)} – ${mx.toStringAsFixed(2)}'
                  : 'Any amount';
            }
            return DPOptionRow(
              title: variation['name']?.toString() ?? 'Plan',
              subtitle: sub,
              trailingText: trailing,
              selected: isSelected,
              onTap: () => _selectVariation(variation),
            );
          }),
        const SizedBox(height: 10),
      ],
    );
  }

  Widget _buildPhoneInput() {
    final prefix = _selectedCountry?['prefix']?.toString() ?? '';
    return DPField(
      label: 'Recipient’s phone number',
      controller: _phoneController,
      focusNode: _phoneFocusNode,
      keyboardType: TextInputType.phone,
      prefixText: prefix.isNotEmpty ? '+$prefix  ' : null,
      hint: 'Phone number',
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      suffixIcon: DPIcons.contactRound,
    );
  }

  Widget _buildAmountInput() {
    final currency = _selectedCountry?['currency'] ?? 'USD';
    final isFixed = _selectedVariation?['fixedPrice'] == 'Yes' || _selectedVariation?['fixedPrice'] == true;
    String? helper;
    if (!isFixed && (_variationMinAmount != null || _variationMaxAmount != null)) {
      if (_variationMinAmount != null && _variationMaxAmount != null) {
        helper =
            'Allowed: $currency ${_variationMinAmount!.toStringAsFixed(2)} – ${_variationMaxAmount!.toStringAsFixed(2)}';
      } else if (_variationMinAmount != null) {
        helper = 'Minimum: $currency ${_variationMinAmount!.toStringAsFixed(2)}';
      } else {
        helper = 'Maximum: $currency ${_variationMaxAmount!.toStringAsFixed(2)}';
      }
    }
    final amount = double.tryParse(_amountController.text) ?? 0;
    double nairaAmount = 0;
    if (_nairaEstimate.isNotEmpty) {
      nairaAmount = double.tryParse(_nairaEstimate.replaceAll('₦', '').replaceAll(',', '')) ?? 0;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_selectedVariation != null)
          DPField(
            label: isFixed ? 'Amount (fixed)' : 'Amount',
            controller: _amountController,
            focusNode: _amountFocusNode,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            enabled: !isFixed,
            prefixText: '$currency  ',
            hint: isFixed ? 'Filled in for you' : 'Enter amount',
            helper: helper,
            onChanged: _calculateNairaConversion,
          ),
        if (_selectedVariation != null)
          DPSummaryCard(rows: [
            DPSummaryRow('Recipient receives', '$currency ${amount.toStringAsFixed(2)}'),
            if (_nairaConversionRate > 0)
              DPSummaryRow('Estimated exchange rate', '$currency 1 = ₦${_nairaConversionRate.toStringAsFixed(2)}'),
            const DPSummaryRow('Service fee', 'Included'),
            DPSummaryRow('You pay', nairaAmount > 0 ? dpNaira(nairaAmount) : '—', emphasize: true),
          ]),
      ],
    );
  }



  Widget _buildEmailInput() {
    return DPField(
      label: 'Email for receipt (optional)',
      controller: _emailController,
      keyboardType: TextInputType.emailAddress,
      hint: 'name@email.com',
      suffixIcon: DPIcons.mail,
    );
  }

  Widget _buildServiceUnavailable() {
    return DPServiceUnavailable(
      message: !_isUserActive
          ? 'Your account has been deactivated. Please contact support.'
          : 'International airtime is currently unavailable. Please try again later.',
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
