// lib/presentation/screens/betting/betting_screen.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:image_network/image_network.dart';

import '../../../core/services/api_service.dart';
import '../../../core/widgets/receipt_widget.dart';

class BettingScreen extends StatefulWidget {
  final void Function(double newBalance) onBalanceUpdate;
  final String userId;

  const BettingScreen({
    super.key,
    required this.onBalanceUpdate,
    required this.userId,
  });

  @override
  State<BettingScreen> createState() => _BettingScreenState();
}

class _BettingScreenState extends State<BettingScreen>
    with TickerProviderStateMixin {
  // Controllers
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _pinController = TextEditingController();

  // Focus Nodes
  final FocusNode _usernameFocusNode = FocusNode();
  final FocusNode _amountFocusNode = FocusNode();
  final FocusNode _pinFocusNode = FocusNode();

  // State Variables
  String? _selectedPlatform;
  bool _isLoading = false;
  bool _isLoadingUserData = true;
  bool _isAuthenticating = false;
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
  String _biometricName = 'Biometric';

  // Service State
  final bool _bettingServiceEnabled = true;
  bool _isUserActive = true;

  // Animation
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late AnimationController _sheetController;
  late Animation<double> _sheetAnimation;

  // Betting Platforms with Logo URLs
  final List<Map<String, dynamic>> _platforms = [
    {
      'name': 'Bet9ja',
      'apiName': 'bet9ja',
      'logoUrl':
          'https://play-lh.googleusercontent.com/mUd4hpLupwlxDYmsFdlKV64DzBLWdux3idYssPzzQkQZ_QVXpQIBqsEVtQDADGiCEtQVVjGdDNkF-zRn1D52Bw',
      'color': const Color(0xFF00843D),
    },
    {
      'name': '1xBet',
      'apiName': '1xbet',
      'logoUrl':
          'https://soutalkuwait.com/wp-content/uploads/2026/07/images-9.jpg',
      'color': const Color(0xFF1A5CFF),
    },
    {
      'name': 'Bet365',
      'apiName': 'bet365',
      'logoUrl':
          'https://upload.wikimedia.org/wikipedia/commons/thumb/d/dc/Bet365_Logo.svg/500px-Bet365_Logo.svg.png?utm_source=commons.wikimedia.org&utm_campaign=index&utm_content=thumbnail',
      'color': const Color(0xFF1D8C45),
    },
    {
      'name': 'SportyBet',
      'apiName': 'sportybet',
      'logoUrl':
          'https://play-lh.googleusercontent.com/IgO7ZtqQTAefBbpPAiUkaxXwJawUp1dqzjW-mCDX4MhiC5X5l0udupzfcoe47wdWaJ_98gWRAwj3mrLwxrui=w240-h480-rw',
      'color': const Color(0xFFC0392B),
    },
    {
      'name': 'NairaBet',
      'apiName': 'nairabet',
      'logoUrl':
          'https://cdn.brandfetch.io/domain/nairabet.com/fallback/lettermark/theme/dark/h/400/w/400/icon?c=1bfwsmEH20zzEfSNTed',
      'color': const Color.fromARGB(255, 9, 49, 210),
    },
    {
      'name': 'BetKing',
      'apiName': 'betking',
      'logoUrl':
          'https://www.toffeeweb.com/ng/wp-content/uploads/mm-business-data/images/brands/2081da9cb33a-500-BetKing.jpg',
      'color': const Color.fromARGB(255, 12, 1, 87),
    },
  ];

  // Quick Amount Options
  final List<int> _quickAmounts = [100, 200, 500, 1000];

  // Payment Sheet State
  bool _showPaymentSheet = false;
  bool _isProcessingPayment = false;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _initializeData();
    _fetchSecuritySettings();
    _loadWalletBalance();
    _loadReferralCode();
    _checkBiometricSupport();
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

  Future<void> _checkBiometricSupport() async {
    try {
      final isAvailable = await ApiService.isBiometricAvailable();
      final prefs = await SharedPreferences.getInstance();
      final isEnabled = prefs.getBool('biometricEnabled') ?? false;

      if (isAvailable && isEnabled) {
        final name = await ApiService.getBiometricName();
        setState(() {
          _biometricName = name;
          _biometricEnabled = true;
        });
      } else if (isAvailable) {
        final name = await ApiService.getBiometricName();
        setState(() {
          _biometricName = name;
          _biometricEnabled = false;
        });
      }
    } catch (e) {
      debugPrint('Biometric check error: $e');
    }
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

  Future<void> _loadReferralCode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userString = prefs.getString('user');
      String userId = widget.userId;

      if (userId.isEmpty || userId == 'N/A') {
        if (userString != null) {
          final userMap = jsonDecode(userString) as Map<String, dynamic>;
          userId = userMap['_id']?.toString() ?? '';
        }
      }
    } catch (e) {
      debugPrint('Error loading referral code: $e');
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
    _usernameController.dispose();
    _amountController.dispose();
    _pinController.dispose();
    _usernameFocusNode.dispose();
    _amountFocusNode.dispose();
    _pinFocusNode.dispose();
    super.dispose();
  }

  String? _validateForm() {
    if (_selectedPlatform == null) {
      return 'Please select a betting platform';
    }

    final username = _usernameController.text.trim();
    if (username.isEmpty) {
      return 'Please enter your username or account ID';
    }
    if (username.length < 4) {
      return 'Username must be at least 4 characters';
    }

    final amount = double.tryParse(_amountController.text) ?? 0;
    if (_amountController.text.isEmpty) {
      return 'Please enter amount';
    }
    if (amount < 100) {
      return 'Minimum deposit is ₦100';
    }
    if (amount > 100000) {
      return 'Maximum deposit is ₦100,000';
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

  // ==================== PROCESS PAYMENT ====================

  Future<void> _processPaymentWithPIN() async {
    // Validate PIN
    if (!_transactionPinSet) {
      _showErrorDialog(
        'PIN Required',
        'Please set up a transaction PIN in Settings.',
      );
      return;
    }

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
      _isProcessingPayment = true;
    });

    await _executeFunding(pin: pin);
  }

  Future<void> _processPaymentWithBiometric() async {
    setState(() {
      _isProcessingPayment = true;
      _isAuthenticating = true;
      _pinValidationError = null;
    });

    try {
      final isAvailable = await ApiService.isBiometricAvailable();
      if (!isAvailable) {
        setState(() {
          _isProcessingPayment = false;
          _isAuthenticating = false;
        });
        _showErrorDialog(
          'Biometric Not Available',
          'Biometric authentication is not available on this device. Please use your PIN.',
        );
        return;
      }

      if (!_biometricEnabled) {
        setState(() {
          _isProcessingPayment = false;
          _isAuthenticating = false;
        });
        _showErrorDialog(
          'Biometric Not Enabled',
          'Biometric authentication is not enabled. Please enable it in Settings or use your PIN.',
        );
        return;
      }

      final biometricSuccess = await ApiService.authenticateWithBiometrics();

      if (!biometricSuccess) {
        setState(() {
          _isProcessingPayment = false;
          _isAuthenticating = false;
        });
        _showErrorDialog(
          'Authentication Failed',
          'Biometric authentication failed. Please try again or use your PIN.',
        );
        return;
      }

      await _executeFunding(useBiometric: true);
    } catch (e) {
      setState(() {
        _isProcessingPayment = false;
        _isAuthenticating = false;
      });
      _showErrorDialog('Authentication Error', _mapExceptionToUserMessage(e));
    }
  }

  // ==================== EXECUTE FUNDING WITH BALANCE CHECK ====================

  Future<void> _executeFunding({String? pin, bool useBiometric = false}) async {
    try {
      setState(() {
        _isLoading = true;
        _isAuthenticating = true;
      });

      final platform = _selectedPlatform!;
      final username = _usernameController.text.trim();
      final amount = double.parse(_amountController.text);

      // ✅ 1. Get current balance from API
      final currentBalance = await ApiService.getBalance();

      // ✅ 2. Check if user has enough balance
      if (currentBalance < amount) {
        setState(() {
          _isProcessingPayment = false;
          _isLoading = false;
          _isAuthenticating = false;
        });
        _showErrorDialog(
          'Insufficient Balance',
          'Your wallet balance (₦${currentBalance.toStringAsFixed(2)}) is insufficient.\n\n'
              'Deposit amount: ₦${amount.toStringAsFixed(2)}\n'
              'Please fund your wallet and try again.',
        );
        _closePaymentSheet();
        return;
      }

      final platformData = _platforms.firstWhere(
        (p) => p['name'] == platform,
        orElse: () => _platforms[0],
      );
      final apiName = platformData['apiName'];

      // ✅ 3. Make API call to fund betting
      final result = await ApiService.authenticatedPost('/api/betting/fund', {
        'userId': widget.userId,
        'platform': apiName,
        'username': username,
        'amount': amount,
        'transactionPin': useBiometric ? null : pin,
        'useBiometric': useBiometric,
      }, useBiometric: useBiometric);

      if (result['success'] == true) {
        final newBalance = result['newBalance'] ?? currentBalance - amount;

        // ✅ 4. Update balance in the app
        widget.onBalanceUpdate(newBalance);
        setState(() {
          _walletBalance = newBalance;
        });

        // ✅ 5. Store the new balance in SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        await prefs.setDouble('walletBalance', newBalance);

        _closePaymentSheet();
        _showSuccessDialog(platform, username, amount, result);
        _clearForm();
      } else {
        setState(() {
          _isProcessingPayment = false;
        });
        _showErrorDialog(
          'Funding Failed',
          result['message'] ?? 'Transaction failed. Please try again.',
        );
      }
    } catch (e) {
      setState(() {
        _isProcessingPayment = false;
      });
      _showErrorDialog('Funding Failed', _mapExceptionToUserMessage(e));
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isAuthenticating = false;
          _isProcessingPayment = false;
        });
      }
    }
  }

  void _showSuccessDialog(
    String platform,
    String username,
    double amount,
    Map<String, dynamic> result,
  ) {
    final transactionId =
        result['transactionId'] ??
        'TXN_${DateTime.now().millisecondsSinceEpoch}';
    final reference = result['reference'] ?? transactionId;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => Dialog(
            backgroundColor: Colors.transparent,
            elevation: 0,
            child: ReceiptWidget(
              transactionType: 'Betting Deposit',
              amount: amount.toStringAsFixed(2),
              status: 'completed',
              transactionId: transactionId,
              reference: reference.toString(),
              date: DateTime.now(),
              phoneNumber: username,
              description: '$platform Account Funding',
              customMessage: '✓ Account funded successfully!',
              primaryColor: const Color(0xFF102C68),
              showWatermark: true,
              isAdminTransaction: false,
              isUserAdmin: false,
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
                Icon(Icons.error_outline, color: Colors.red.shade700, size: 24),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: GoogleFonts.inter(
                    color: Colors.red.shade700,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            content: Text(
              message,
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

  void _clearForm() {
    _usernameController.clear();
    _amountController.clear();
    _pinController.clear();
    setState(() {
      _selectedPlatform = null;
      _useBiometric = false;
      _pinValidationError = null;
    });
  }

  void _selectQuickAmount(int amount) {
    _amountController.text = amount.toString();
    _amountFocusNode.unfocus();
    setState(() {});
  }

  Widget _buildPlatformCard(Map<String, dynamic> platform, bool isSelected) {
    return GestureDetector(
      onTap: () {
        setState(() => _selectedPlatform = platform['name']);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        width: 80,
        height: 80,
        margin: const EdgeInsets.only(right: 8),
        decoration: BoxDecoration(
          color: isSelected ? platform['color'] : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? platform['color'] : Colors.grey.shade200,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color:
                  isSelected
                      ? platform['color'].withOpacity(0.3)
                      : Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Platform Logo using ImageNetwork package
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: ImageNetwork(
                image: platform['logoUrl'],
                height: 40,
                width: 40,
                fitAndroidIos: BoxFit.contain,
                fitWeb: BoxFitWeb.contain,
                duration: 1000,
                curve: Curves.easeIn,
                onLoading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color:
                        isSelected
                            ? Colors.white.withOpacity(0.2)
                            : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          isSelected ? Colors.white : platform['color'],
                        ),
                      ),
                    ),
                  ),
                ),
                onError: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color:
                        isSelected
                            ? Colors.white.withOpacity(0.2)
                            : platform['color'].withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      platform['name'].substring(0, 1).toUpperCase(),
                      style: GoogleFonts.inter(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: isSelected ? Colors.white : platform['color'],
                      ),
                    ),
                  ),
                ),
                onTap: () {
                  debugPrint('${platform['name']} logo tapped');
                },
              ),
            ),
            const SizedBox(height: 6),
            Text(
              platform['name'],
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                color: isSelected ? Colors.white : Colors.grey.shade800,
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
                                'Confirm Deposit',
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

  // ==================== PAYMENT SHEET DETAILS ====================

  Widget _buildPaymentSheetDetails() {
    final platform = _selectedPlatform ?? 'N/A';
    final username = _usernameController.text.trim();
    final amount = double.tryParse(_amountController.text) ?? 0;
    final formattedAmount = NumberFormat.currency(
      symbol: '₦',
      decimalDigits: 2,
    ).format(amount);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        children: [
          // Platform
          Row(
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
                      icon: HugeIcons.strokeRoundedGame,
                      color: const Color(0xFF102C68),
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Platform',
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
                  platform,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF14263D),
                  ),
                  textAlign: TextAlign.right,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          Divider(height: 12, color: Colors.grey.shade200),
          // Username
          Row(
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
                      icon: HugeIcons.strokeRoundedUser,
                      color: const Color(0xFF102C68),
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Username',
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
                  username.isNotEmpty ? username : 'N/A',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF14263D),
                  ),
                  textAlign: TextAlign.right,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          Divider(height: 12, color: Colors.grey.shade200),
          // Amount
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF168566).withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: HugeIcon(
                      icon: HugeIcons.strokeRoundedMoney01,
                      color: const Color(0xFF168566),
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Amount',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF728078),
                    ),
                  ),
                ],
              ),
              Text(
                formattedAmount,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF168566),
                ),
              ),
            ],
          ),
        ],
      ),
    );
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

  // ==================== PIN OPTION ====================

  Widget _buildPinOption() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        decoration: BoxDecoration(
          color:
              _useBiometric
                  ? Colors.grey.shade50
                  : const Color(0xFF102C68).withOpacity(0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color:
                _useBiometric ? Colors.grey.shade300 : const Color(0xFF102C68),
            width: _useBiometric ? 1 : 2,
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
                  hintText: 'Enter 6-digit transaction PIN',
                  hintStyle: GoogleFonts.inter(
                    color:
                        _useBiometric
                            ? Colors.grey.shade400
                            : Colors.grey.shade600,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                  prefixIcon: Icon(
                    Icons.lock_outline,
                    color:
                        _useBiometric
                            ? Colors.grey.shade400
                            : const Color(0xFF102C68),
                    size: 18,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 0,
                    vertical: 12,
                  ),
                  errorText: _pinValidationError,
                  errorStyle: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _useBiometric ? Colors.grey.shade400 : Colors.black,
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                onChanged: (_) => setState(() => _pinValidationError = null),
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
                      _useBiometric
                          ? Colors.transparent
                          : const Color(0xFF168566),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child:
                    _isProcessingPayment && !_useBiometric
                        ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                        : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.lock_outline,
                              color:
                                  _useBiometric
                                      ? Colors.grey.shade400
                                      : Colors.white,
                              size: 16,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _useBiometric ? 'Switch to PIN' : 'Pay with PIN',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color:
                                    _useBiometric
                                        ? Colors.grey.shade400
                                        : Colors.white,
                              ),
                            ),
                          ],
                        ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== BIOMETRIC OPTION ====================

  Widget _buildBiometricOption() {
    final bool isBiometricSupported = Platform.isAndroid || Platform.isIOS;

    if (!isBiometricSupported || !_biometricEnabled) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: GestureDetector(
        onTap: _isProcessingPayment ? null : _processPaymentWithBiometric,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          decoration: BoxDecoration(
            color:
                _useBiometric
                    ? const Color(0xFF102C68).withOpacity(0.08)
                    : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color:
                  _useBiometric
                      ? const Color(0xFF102C68)
                      : Colors.grey.shade300,
              width: _useBiometric ? 2 : 1,
            ),
          ),
          child:
              _isProcessingPayment && _useBiometric
                  ? Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        color: const Color(0xFF102C68),
                        strokeWidth: 2.5,
                      ),
                    ),
                  )
                  : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.fingerprint,
                        color:
                            _useBiometric
                                ? const Color(0xFF102C68)
                                : Colors.grey.shade600,
                        size: 24,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _useBiometric
                              ? 'Tap to authenticate with $_biometricName'
                              : 'Pay with $_biometricName',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color:
                                _useBiometric
                                    ? const Color(0xFF102C68)
                                    : Colors.grey.shade700,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (_useBiometric)
                        Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: const Color(0xFF168566),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.check,
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

  // ==================== MAIN BUILD ====================

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
        'Fund Betting',
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
    if (_isLoadingUserData) {
      return Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(const Color(0xFF102C68)),
        ),
      );
    }

    if (!_isUserActive || !_bettingServiceEnabled) {
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
              _buildPlatformSection(),
              const SizedBox(height: 24),
              _buildUsernameInput(),
              const SizedBox(height: 24),
              _buildAmountInput(),
              const SizedBox(height: 12),
              _buildQuickAmounts(),
              const SizedBox(height: 24),
              _buildInfoCard(),
              const SizedBox(height: 24),
              _buildPurchaseButton(),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlatformSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Select Platform',
          style: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF102C68),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 80,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _platforms.length,
            itemBuilder: (context, index) {
              final platform = _platforms[index];
              return _buildPlatformCard(
                platform,
                _selectedPlatform == platform['name'],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildUsernameInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Username / Account ID',
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
            controller: _usernameController,
            focusNode: _usernameFocusNode,
            decoration: InputDecoration(
              hintText: 'Enter username or account ID',
              hintStyle: GoogleFonts.inter(
                color: Colors.grey.shade400,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              prefixIcon: HugeIcon(
                icon: HugeIcons.strokeRoundedUser,
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

  Widget _buildAmountInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Amount',
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
            controller: _amountController,
            focusNode: _amountFocusNode,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              hintText: 'Enter amount (min ₦100)',
              hintStyle: GoogleFonts.inter(
                color: Colors.grey.shade400,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              prefixIcon: HugeIcon(
                icon: HugeIcons.strokeRoundedMoney01,
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
        if (_amountController.text.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF168566).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                HugeIcon(
                  icon: HugeIcons.strokeRoundedInformationCircle,
                  color: const Color(0xFF168566),
                  size: 14,
                ),
                const SizedBox(width: 4),
                Text(
                  'Minimum: ₦100 | Maximum: ₦100,000',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF168566),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildQuickAmounts() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children:
          _quickAmounts.map((amount) {
            final isSelected = _amountController.text == amount.toString();
            return GestureDetector(
              onTap: () => _selectQuickAmount(amount),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color:
                      isSelected
                          ? const Color(0xFF102C68).withOpacity(0.1)
                          : Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color:
                        isSelected
                            ? const Color(0xFF102C68)
                            : const Color(0x14102C68),
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: Text(
                  '₦$amount',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                    color:
                        isSelected
                            ? const Color(0xFF102C68)
                            : const Color(0xFF102C68).withOpacity(0.7),
                  ),
                ),
              ),
            );
          }).toList(),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0x05102C68),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        children: [
          Container(
            width: 23,
            height: 23,
            decoration: BoxDecoration(
              color: const Color(0xFF102C68).withOpacity(0.1),
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(
              Icons.info_outline,
              color: Color(0xFF102C68),
              size: 16,
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Text(
              'Ensure correct details for instant funding.\nSecure and reliable.',
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF102C68),
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPurchaseButton() {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed:
            (_isLoading || _isAuthenticating || _isProcessingPayment)
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
            _isLoading || _isAuthenticating || _isProcessingPayment
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
      height: 128,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        image: const DecorationImage(
          image: AssetImage('assets/betting_banner.png'),
          fit: BoxFit.cover,
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
            Icon(
              !_isUserActive ? Icons.account_circle : Icons.sports_esports,
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
                  : 'Betting service is currently unavailable. Please try again later.',
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
}
