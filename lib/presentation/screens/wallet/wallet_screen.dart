// lib/presentation/screens/wallet/wallet_screen.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
// ✅ ADD FOUNDATION PACKAGE FOR DEBUG
import 'package:flutter/foundation.dart' show kDebugMode;

import '../../../core/services/api_service.dart';
import '../../../core/services/payment_service.dart';
import '../transactions/transactions_screen.dart';
import '../kyc/kyc_screen.dart';
import '../../../ui/ui.dart';
import 'send_money_screen.dart';

// ==================== CONSTANTS ====================
const String CASHWYRE_BASE_URL = 'https://businessapi.cashwyre.com/api/v1.0';
const String CASHWYRE_BUSINESS_CODE = 'C4B20260307000114';
const String CASHWYRE_SECRET_KEY =
    'secK_0cc3f3c57217673eb0581ba428b4d375d43d991d636303ac9c563ea8b6db2d873fb80586f448578090a1e7495b86f61423cb91121d9e957e6c9751933b3f2f9e';

// ==================== PAYMENT METHOD MODEL ====================
class PaymentMethod {
  final String id;
  final String name;
  final String description;
  final dynamic icon;
  final Color color;
  final bool instant;
  final bool popular;
  final String? badge;

  const PaymentMethod({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.color,
    required this.instant,
    this.popular = false,
    this.badge,
  });
}

// ==================== MAIN WIDGET ====================
class WalletTopUpScreen extends StatefulWidget {
  final String userId;
  final void Function(double newBalance) onBalanceUpdate;
  final String? initialTab;

  const WalletTopUpScreen({
    super.key,
    required this.userId,
    required this.onBalanceUpdate,
    this.initialTab,
  });

  @override
  State<WalletTopUpScreen> createState() => _WalletTopUpScreenState();
}

class _WalletTopUpScreenState extends State<WalletTopUpScreen>
    with TickerProviderStateMixin {
  // ==================== STATE VARIABLES ====================
  late TabController _tabController;
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _pinController = TextEditingController();

  bool _isLoading = false;
  bool _isBalanceLoading = true;
  bool _isBalanceVisible = true;
  bool _useBiometric = false;
  bool _biometricEnabled = false;
  bool _pinRequired = true;
  bool _transactionPinSet = false;
  bool _isAuthenticating = false;

  String? _selectedPaymentMethod;
  String _statusMessage = '';
  Color _statusColor = Colors.black87;

  double _currentBalance = 0.0;
  double _commissionBalance = 0.0;

  // ==================== DEDICATED ACCOUNT STATE ====================
  bool _hasDedicatedAccount = false;
  String? _dedicatedAccountNumber;
  String? _dedicatedAccountName;
  String? _dedicatedBankName;
  bool _isCheckingAccount = false;
  final bool _isKYCComplete = false;
  bool _dedicatedAccountLoaded = false;

  // ==================== COLORS ====================
  final Color _primaryColor = const Color(0xFF102C68);
  final Color _secondaryColor = const Color(0xFF168566);
  final Color _white = Colors.white;
  final Color _textColor = const Color(0xFF14263D);
  final Color _hintColor = const Color(0xFFA9B2AC);
  final Color _successColor = const Color(0xFF168566);
  final Color _errorColor = const Color(0xFFC0392B);
  final Color _warningColor = const Color(0xFFA76B1D);
  final Color _accentColor = const Color(0xFF173D88);

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  // ==================== PAYMENT METHODS ====================
  List<PaymentMethod> _paymentMethods = [];

  // ==================== LOGGING ====================
  void _log(String message) {
    if (kDebugMode) {
      debugPrint('💰 WALLET: $message');
    }
  }

  @override
  void initState() {
    super.initState();
    _log('🔄 INIT: WalletTopUpScreen initialized');
    _setupAnimations();
    _initializeData();
    _loadSecuritySettings();
    _checkDedicatedAccount();
  }

  void _setupAnimations() {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );

    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTab == 'transfer' ? 1 : 0,
    );

    _animationController.forward();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _amountController.dispose();
    _pinController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  // ==================== INITIALIZATION ====================
  Future<void> _initializeData() async {
    await _loadBalances();
  }

  Future<void> _loadBalances() async {
    setState(() => _isBalanceLoading = true);
    try {
      final balance = await ApiService.getBalance();
      final commission = await ApiService.getCommissionBalance();
      setState(() {
        _currentBalance = balance;
        _commissionBalance = commission;
        _isBalanceLoading = false;
      });
      _log('💰 Balance loaded: ₦$balance, Commission: ₦$commission');
    } catch (e) {
      _log('❌ Error loading balances: $e');
      setState(() => _isBalanceLoading = false);
    }
  }

  Future<void> _loadSecuritySettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();

      final pinSet = prefs.getBool('transactionPinSet') ?? false;
      final biometricEnabled = prefs.getBool('biometricEnabled') ?? false;

      setState(() {
        _transactionPinSet = pinSet;
        _biometricEnabled = biometricEnabled;
        _useBiometric = biometricEnabled;
      });

      _log('🔐 Security: PIN Set=$pinSet, Biometric=$biometricEnabled');

      final globalSettings = await ApiService.getGlobalSecuritySettings();
      setState(() {
        _pinRequired = globalSettings['pinRequired'] ?? true;
      });
    } catch (e) {
      _log('❌ Error loading security settings: $e');
    }
  }

  // ==================== DEDICATED ACCOUNT CHECK - FIXED ====================
  // In wallet_screen.dart - Fixed _checkDedicatedAccount method

  // In wallet_screen.dart - _checkDedicatedAccount method

  // ==================== DEDICATED ACCOUNT CHECK - FIXED ====================
  // ==================== DEDICATED ACCOUNT CHECK - SAME AS DASHBOARD ====================
  Future<void> _checkDedicatedAccount() async {
    if (widget.userId.isEmpty) {
      _log('⚠️ User ID is empty, cannot check dedicated account');
      return;
    }

    setState(() {
      _isCheckingAccount = true;
      _dedicatedAccountLoaded = false;
    });

    try {
      _log('🔍 Checking dedicated account for user: ${widget.userId}');

      // 🔥 SAME AS DASHBOARD: CLEAR CACHE FIRST
      final prefs = await SharedPreferences.getInstance();

      // Remove specific cache for this user
      await prefs.remove('cashwyre_reserve_account_${widget.userId}');

      // Also clear from user object
      final userString = prefs.getString('user');
      if (userString != null) {
        try {
          final userMap = jsonDecode(userString);
          if (userMap['virtualAccount'] != null) {
            userMap['virtualAccount'] = null;
            await prefs.setString('user', jsonEncode(userMap));
          }
        } catch (e) {
          _log('⚠️ Error clearing user cache: $e');
        }
      }

      // ✅ Now fetch fresh from backend - SAME API as dashboard
      final result = await PaymentService.checkDedicatedAccount(
        userId: widget.userId,
      );

      _log('📦 Dedicated account check result: $result');

      if (mounted) {
        if (result['hasAccount'] == true) {
          // Get account details from response
          final accountNumber = result['accountNumber']?.toString();
          final accountName = result['accountName']?.toString();
          final bankName = result['bankName']?.toString();

          _log('📝 Account Number from backend: $accountNumber');
          _log('📝 Account Name from backend: $accountName');
          _log('📝 Bank Name from backend: $bankName');

          setState(() {
            _hasDedicatedAccount = true;
            _dedicatedAccountNumber = accountNumber ?? 'N/A';
            _dedicatedAccountName = accountName ?? 'User';
            _dedicatedBankName = bankName ?? 'Moniepoint MFB';
            _isCheckingAccount = false;
            _dedicatedAccountLoaded = true;
          });

          // Cache the CORRECT account details
          if (userString != null) {
            try {
              final userMap = jsonDecode(userString);
              userMap['virtualAccount'] = {
                'assigned': true,
                'accountNumber': _dedicatedAccountNumber,
                'accountName': _dedicatedAccountName,
                'bankName': _dedicatedBankName,
              };
              userMap['kycVerified'] = true;
              await prefs.setString('user', jsonEncode(userMap));
            } catch (e) {
              _log('⚠️ Error caching account data: $e');
            }
          }

          // Also store in separate cache
          await prefs.setString(
            'cashwyre_reserve_account_${widget.userId}',
            jsonEncode({
              'accountNumber': _dedicatedAccountNumber,
              'accountName': _dedicatedAccountName,
              'bankName': _dedicatedBankName,
            }),
          );

          _log('Dedicated account loaded: $_dedicatedAccountNumber');
          _log('Account Name: $_dedicatedAccountName');

          _updatePaymentMethods(true);
        } else {
          setState(() {
            _hasDedicatedAccount = false;
            _isCheckingAccount = false;
            _dedicatedAccountLoaded = true;
          });
          _log('ℹ️ No dedicated account found for user');
          _updatePaymentMethods(false);
        }
      }
    } catch (e) {
      _log('❌ Error checking dedicated account: $e');
      setState(() {
        _isCheckingAccount = false;
        _dedicatedAccountLoaded = true;
        _hasDedicatedAccount = false;
      });
      _updatePaymentMethods(false);
    }
  }

  void _updatePaymentMethods(bool hasDedicatedAccount) {
    final methods = <PaymentMethod>[];

    // 1. Dedicated Account - Static account (1.5% fee)
    methods.add(
      PaymentMethod(
        id: 'dedicated_account',
        name: 'Dedicated Account',
        description:
            hasDedicatedAccount
                ? 'Your static account • 1.5% fee per transaction'
                : 'Complete KYC to get your dedicated account',
        icon: HugeIcons.strokeRoundedBank,
        color: _primaryColor,
        instant: true,
        popular: true,
        badge: hasDedicatedAccount ? '1.5% Fee' : 'KYC Required',
      ),
    );

    // 2. Virtual Account - Dynamic account with 1.5% fee
    methods.add(
      const PaymentMethod(
        id: 'virtual_account',
        name: 'Virtual Account',
        description: 'Generate a one-time account with 1.5% fee',
        icon: HugeIcons.strokeRoundedAtm02,
        color: Color(0xFF173D88),
        instant: true,
        popular: false,
        badge: '1.5% Fee',
      ),
    );

    // 3. Manual Funding
    methods.add(
      const PaymentMethod(
        id: 'manual',
        name: 'Manual Funding',
        description: 'Contact admin for assistance',
        icon: HugeIcons.strokeRoundedCustomerService,
        color: Color(0xFFA76B1D),
        instant: false,
        badge: 'Admin',
      ),
    );

    setState(() {
      _paymentMethods = methods;
      // Auto-select dedicated account if available
      if (hasDedicatedAccount && _selectedPaymentMethod == null) {
        _selectedPaymentMethod = 'dedicated_account';
      }
    });
    _log(
      '📋 Payment methods updated, hasDedicatedAccount: $hasDedicatedAccount',
    );
  }

  // ==================== UI HELPERS ====================
  void _showErrorDialog(String title, String message) {
    dpDialog(
      context,
      title: title,
      message: message,
      confirmLabel: 'OK',
      tone: DPTone.error,
    );
  }

  void _showSuccessDialog(String title, String message) {
    dpDialog(context, title: title, message: message, confirmLabel: 'Done');
  }

  String _formatBalance(double balance) {
    return NumberFormat('#,##0.00').format(balance);
  }

  // ==================== KYC MODAL ====================
  void _showKYCModal() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            backgroundColor: Colors.white,
            insetPadding: const EdgeInsets.symmetric(horizontal: 20),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 400,
                minWidth: MediaQuery.of(context).size.width * 0.9,
              ),
              child: Container(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topRight,
                          end: Alignment.bottomLeft,
                          colors: [Color(0xFF5BB592), Color(0xFF102C68)],
                        ),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.account_balance_wallet,
                        color: Colors.white,
                        size: 36,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Get Your Dedicated Account',
                      style: GoogleFonts.inter(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF102C68),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'You don\'t have a dedicated account yet. '
                      'Complete your KYC to get your personal static account for seamless transactions.',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: const Color(0xFF728078),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF102C68).withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFF102C68).withValues(alpha: 0.1),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.security,
                            color: const Color(0xFF168566),
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Your account details are secure and private.',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: const Color(0xFF168566),
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
                          child: OutlinedButton(
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
                                Navigator.pushReplacementNamed(
                                  context,
                                  '/home',
                                );
                              }
                              _navigateToKYC();
                            },
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Color(0xFF102C68)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: Text(
                              'Complete KYC',
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF102C68),
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
                                Navigator.pushReplacementNamed(
                                  context,
                                  '/home',
                                );
                              }
                              _navigateToKYC();
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF102C68),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: Text(
                              'Get Started',
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(
                        'Remind Me Later',
                        style: GoogleFonts.inter(
                          color: const Color(0xFF728078),
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
    );
  }

  void _navigateToKYC() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const KYCScreen()),
    ).then((result) {
      _checkDedicatedAccount();
    });
  }

  // ==================== PAYMENT PROCESSING WITH PIN VERIFICATION ====================
  // ==================== PAYMENT PROCESSING WITH PIN VERIFICATION ====================
  Future<void> _processPayment() async {
    final amountText = _amountController.text.trim();
    final amount = double.tryParse(amountText);

    // Validation
    if (amount == null || amount <= 0) {
      _showErrorDialog(
        'Invalid Amount',
        'Please enter a valid amount to fund.',
      );
      return;
    }

    if (amount < 100) {
      _showErrorDialog('Amount Too Low', 'Minimum funding amount is ₦100.');
      return;
    }

    if (amount > 1000000) {
      _showErrorDialog(
        'Amount Too High',
        'Maximum funding amount is ₦1,000,000.',
      );
      return;
    }

    if (_selectedPaymentMethod == null) {
      _showErrorDialog('No Payment Method', 'Please select a payment method.');
      return;
    }

    // Check if dedicated account is selected but not available
    if (_selectedPaymentMethod == 'dedicated_account' &&
        !_hasDedicatedAccount) {
      _showKYCModal();
      return;
    }

    // ✅ STEP 1: PIN VERIFICATION - MATCHES AIRTIME PAGE
    final pin = _pinController.text.trim();

    if (_pinRequired && !_useBiometric) {
      if (pin.isEmpty) {
        _showErrorDialog('PIN Required', 'Please enter your transaction PIN.');
        return;
      }

      if (pin.length != 6) {
        _showErrorDialog('Invalid PIN', 'PIN must be exactly 6 digits.');
        return;
      }

      if (!_transactionPinSet) {
        _showErrorDialog(
          'PIN Not Set',
          'Please set up a transaction PIN in Settings first.',
        );
        return;
      }

      setState(() {
        _isAuthenticating = true;
        _statusMessage = 'Verifying PIN...';
        _statusColor = _primaryColor;
      });

      try {
        final pinResult = await ApiService.verifyTransactionPin(
          userId: widget.userId,
          transactionPin: pin,
        );

        if (pinResult['success'] != true) {
          _log('❌ PIN verification failed: ${pinResult['message']}');
          setState(() {
            _isAuthenticating = false;
            _statusMessage = pinResult['message'] ?? 'Invalid transaction PIN.';
            _statusColor = _errorColor;
          });
          return;
        }

        _log('PIN verified successfully');
        setState(() {
          _isAuthenticating = false;
        });
      } catch (e) {
        _log('❌ PIN verification error: $e');
        setState(() {
          _isAuthenticating = false;
          _statusMessage = e.toString().replaceAll('Exception: ', '');
          _statusColor = _errorColor;
        });
        _showErrorDialog(
          'PIN Verification Failed',
          e.toString().replaceAll('Exception: ', ''),
        );
        return;
      }
    }

    // ✅ STEP 2: Biometric authentication
    if (_useBiometric && _biometricEnabled) {
      try {
        setState(() {
          _isAuthenticating = true;
          _statusMessage = 'Authenticating with biometric...';
          _statusColor = _primaryColor;
        });

        final biometricSuccess = await _triggerBiometricAuthentication();

        if (!biometricSuccess) {
          setState(() {
            _isAuthenticating = false;
            _statusMessage = 'Biometric authentication failed. Please use PIN.';
            _statusColor = _errorColor;
          });
          return;
        }

        _log('Biometric authentication successful');
        setState(() {
          _isAuthenticating = false;
        });
      } catch (e) {
        _log('❌ Biometric error: $e');
        setState(() {
          _isAuthenticating = false;
          _statusMessage = e.toString().replaceAll('Exception: ', '');
          _statusColor = _errorColor;
        });
        return;
      }
    }

    // ✅ STEP 3: Process payment
    setState(() {
      _isLoading = true;
      _statusMessage = 'Processing your request...';
      _statusColor = _primaryColor;
    });

    try {
      switch (_selectedPaymentMethod) {
        case 'dedicated_account':
          await _processDedicatedAccount(amount);
          break;
        case 'virtual_account':
          await _processVirtualAccount(amount);
          break;
        case 'manual':
          await _processManualFunding(amount);
          break;
        default:
          throw Exception('Invalid payment method');
      }
    } catch (e) {
      final errorStr = e.toString().toLowerCase();
      setState(() {
        _isLoading = false;
        _statusMessage = 'Error: ${e.toString()}';
        _statusColor = _errorColor;
      });

      // ✅ Show appropriate dialog based on error type
      if (errorStr.contains('bank is currently not available') ||
          errorStr.contains('unavailable') ||
          errorStr.contains('temporarily unavailable') ||
          errorStr.contains('service unavailable')) {
        _showServiceUnavailableDialog(amount);
      } else {
        _showErrorDialog(
          'Payment Failed',
          e.toString().replaceAll('Exception: ', ''),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
        _isAuthenticating = false;
      });
    }
  }

  // ==================== BIOMETRIC AUTHENTICATION ====================
  Future<bool> _triggerBiometricAuthentication() async {
    try {
      // Check if biometric is available
      final isAvailable = await ApiService.checkBiometricAvailability();
      if (!isAvailable) {
        _showErrorDialog(
          'Biometric Unavailable',
          'Biometric authentication is not supported on this device.',
        );
        return false;
      }

      // Check if user has enrolled biometrics
      final hasEnrolled = await ApiService.hasEnrolledBiometrics();
      if (!hasEnrolled) {
        _showErrorDialog(
          'Biometric Not Set Up',
          'No biometric credentials enrolled on this device.',
        );
        return false;
      }

      // Trigger biometric authentication
      final result = await ApiService.authenticateWithBiometricsEnhanced();
      return result;
    } catch (e) {
      _log('Biometric error: $e');
      _showErrorDialog(
        'Biometric Error',
        e.toString().replaceAll('Exception: ', ''),
      );
      return false;
    }
  }

  // ==================== DEDICATED ACCOUNT ====================
  // ==================== DEDICATED ACCOUNT ====================
  Future<void> _processDedicatedAccount(double amount) async {
    try {
      _log('🏦 Processing dedicated account for: ₦$amount');

      if (!_hasDedicatedAccount) {
        _showKYCModal();
        setState(() => _isLoading = false);
        return;
      }

      final userId = await PaymentService.getCurrentUserId();
      if (userId == null) {
        throw Exception('User not authenticated. Please log in again.');
      }

      // ✅ 1.5% flat fee — deducted from the funded amount
      // User transfers `amount`, we keep 1.5% as fee, and credit (amount - fee)
      final fee = amount * 0.015;
      final totalPayable = amount;

      _log(
        '💰 Amount: ₦$amount, Fee (1.5%): ₦$fee, You receive: ₦${amount - fee}',
      );

      final reference = 'DA_${DateTime.now().millisecondsSinceEpoch}';

      await _storePendingTransaction(
        reference: reference,
        accountNumber: _dedicatedAccountNumber!,
        amount: amount,
        totalPayable: totalPayable,
        fee: fee,
        userId: userId,
        method: 'dedicated_account',
      );

      setState(() {
        _isLoading = false;
        _statusMessage = 'Dedicated account ready!';
        _statusColor = _successColor;
      });

      _showVirtualAccountDialog(
        accountNumber: _dedicatedAccountNumber!,
        accountName: _dedicatedAccountName ?? 'User',
        bankName: _dedicatedBankName ?? 'Moniepoint Microfinance Bank',
        amount: amount,
        totalPayable: totalPayable,
        fee: fee,
        reference: reference,
        expiresIn: 10,
        userId: userId,
        method: 'Dedicated Account',
        isDedicated: true,
      );
    } catch (e) {
      setState(() => _isLoading = false);
      rethrow;
    }
  }

  // ==================== VIRTUAL ACCOUNT ====================
  // In wallet_screen.dart - _processVirtualAccount method

  // In wallet_screen.dart - Replace the _processVirtualAccount method with this:

  Future<void> _processVirtualAccount(double amount) async {
    try {
      _log('🏦 Creating virtual account for: ₦$amount');

      final userId = await PaymentService.getCurrentUserId();
      if (userId == null) {
        throw Exception('User not authenticated. Please log in again.');
      }

      // ✅ STEP 1: Get the user's email for the virtual account
      final user = await ApiService.getCurrentUser();
      final email = user['email'] ?? 'user@dalabapay.com';
      final fullName = user['fullName'] ?? 'DalabaPay User';

      _log('👤 Creating virtual account for: $fullName ($email)');

      // ✅ STEP 2: Call the backend to create a dynamic virtual account
      final result = await PaymentService.createDynamicVirtualAccount(
        userId: userId,
        amount: amount,
      );

      _log('📦 Virtual account result: ${result['success']}');
      _log('📦 Virtual account details: $result');

      // ✅ STEP 3: Check if the result indicates a fallback or bank unavailable
      final isFallback = result['isFallback'] == true;
      final fallbackMessage = result['message'] ?? '';

      if (result['success'] == true) {
        final accountNumber = result['accountNumber'] ?? 'N/A';
        final accountName = result['accountName'] ?? fullName;
        final bankName = result['bankName'] ?? 'Moniepoint MFB';

        // Calculate fee (1.5%)
        final fee = amount * 0.015;
        final totalPayable = amount + fee;

        _log('Virtual account created: $accountNumber');
        _log('💰 Amount: ₦$amount, Fee: ₦$fee, Total: ₦$totalPayable');
        _log('📌 isFallback: $isFallback');

        final reference = 'VA_${DateTime.now().millisecondsSinceEpoch}';

        await _storePendingTransaction(
          reference: reference,
          accountNumber: accountNumber,
          amount: amount,
          totalPayable: totalPayable,
          fee: fee,
          userId: userId,
          method: 'virtual_account',
        );

        // ✅ If it's a fallback account (bank unavailable), show a warning
        // ✅ If it's a fallback account (bank unavailable), show a warning
        if (isFallback) {
          _log('⚠️ Using fallback virtual account - bank service unavailable');

          setState(() {
            _isLoading = false;
            _statusMessage =
                '⚠️ Bank service temporarily unavailable. Using fallback account.';
            _statusColor = _warningColor;
          });

          // ✅ Show the service unavailable dialog instead
          _showServiceUnavailableDialog(amount);
        } else {
          setState(() {
            _isLoading = false;
            _statusMessage = 'Virtual account generated!';
            _statusColor = _successColor;
          });

          _showVirtualAccountDialog(
            accountNumber: accountNumber,
            accountName: accountName,
            bankName: bankName,
            amount: amount,
            totalPayable: totalPayable,
            fee: fee,
            reference: reference,
            expiresIn: 10,
            userId: userId,
            method: 'Virtual Account',
            isDedicated: false,
          );
        }
      } else {
        // ✅ STEP 4: Virtual account creation failed - prompt for KYC
        _log('❌ Virtual account creation failed: ${result['message']}');

        setState(() {
          _isLoading = false;
          _statusMessage =
              '⚠️ Virtual account service unavailable. Please complete KYC for a dedicated account.';
          _statusColor = _warningColor;
        });

        // Show dialog suggesting KYC for dedicated account
        _showVirtualAccountUnavailableDialog(amount);
      }
    } catch (e) {
      final errorStr = e.toString().toLowerCase();
      _log('❌ Virtual account error: $e');

      setState(() {
        _isLoading = false;
      });

      // ✅ STEP 5: Handle all errors with the smart dialog
      // Check if it's a bank unavailable error or generic
      final isBankError =
          errorStr.contains('bank is currently not available') ||
          errorStr.contains('unavailable') ||
          errorStr.contains('temporarily unavailable') ||
          errorStr.contains('service unavailable');

      // Show the smart dialog with options
      _showVirtualAccountActionDialog(
        amount: amount,
        errorMessage: e.toString().replaceAll('Exception: ', ''),
        isBankError: isBankError,
      );
    }
  }

  Future<void> _storePendingTransaction({
    required String reference,
    required String accountNumber,
    required double amount,
    required double totalPayable,
    required double fee,
    required String userId,
    required String method,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final transactions =
          prefs.getStringList('pending_cashwyre_transactions') ?? [];

      final transactionData = {
        'reference': reference,
        'transactionReference':
            '${DateTime.now().millisecondsSinceEpoch}${DateTime.now().microsecond}',
        'userId': userId,
        'amount': amount,
        'totalPayable': totalPayable,
        'fee': fee,
        'accountNumber': accountNumber,
        'accountName': 'DalabaPay User',
        'bankName': 'Moniepoint MFB',
        'bankCode': '50515',
        'status': 'pending',
        'createdAt': DateTime.now().toIso8601String(),
        'expiresIn': 10,
        'paymentMethod': method,
        'source': method == 'dedicated_account' ? 'dedicated' : 'cashwyre',
      };

      transactions.add(jsonEncode(transactionData));
      await prefs.setStringList('pending_cashwyre_transactions', transactions);
      _log('Transaction stored: $reference');
    } catch (e) {
      _log('❌ Failed to store transaction: $e');
    }
  }

  // ==================== MANUAL FUNDING ====================
  Future<void> _processManualFunding(double amount) async {
    setState(() {
      _isLoading = false;
      _statusMessage =
          '📋 Contact admin for manual funding. Amount: ₦${amount.toStringAsFixed(2)}';
      _statusColor = _warningColor;
    });

    _showManualFundingDialog(amount);
  }

  /// Show dialog when virtual account is unavailable - offer KYC and Manual Funding
  void _showServiceUnavailableDialog(double amount) {
    final formattedAmount = '₦${amount.toStringAsFixed(2)}';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            backgroundColor: _white,
            title: Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: _warningColor,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Service Unavailable',
                    style: GoogleFonts.inter(
                      color: _warningColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
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
                  'The virtual account service is currently unavailable for $formattedAmount.',
                  style: GoogleFonts.inter(fontSize: 14, color: _textColor),
                ),
                const SizedBox(height: 16),

                // ✅ Option 1: Dedicated Account (if KYC available)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _primaryColor.withAlpha(12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _primaryColor.withAlpha(50)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.account_balance,
                            color: _primaryColor,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            _hasDedicatedAccount
                                ? 'Use Dedicated Account'
                                : 'Get a Dedicated Account',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: _primaryColor,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _hasDedicatedAccount
                            ? 'You already have a dedicated account with 1.5% fee per transaction. Use it now!'
                            : 'Complete your KYC to get a personal dedicated account with 1.5% fee per transaction, static account number, and instant funding.',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: _textColor,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.pop(ctx);
                            if (_hasDedicatedAccount) {
                              // Use dedicated account
                              setState(() {
                                _selectedPaymentMethod = 'dedicated_account';
                                _statusMessage = '';
                              });
                              _processPayment();
                            } else {
                              // Go to KYC
                              _navigateToKYC();
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _primaryColor,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: Text(
                            _hasDedicatedAccount
                                ? 'Use Dedicated Account'
                                : 'Complete KYC',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // ✅ Option 2: Manual Funding
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _warningColor.withAlpha(12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _warningColor.withAlpha(50)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.support_agent,
                            color: _warningColor,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Manual Funding',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: _warningColor,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Contact admin for manual funding assistance.',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: _textColor,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const FaIcon(
                            FontAwesomeIcons.whatsapp,
                            color: Colors.white,
                            size: 16,
                          ),
                          label: Text(
                            'Contact Admin',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          onPressed: () {
                            Navigator.pop(ctx);
                            // Switch to manual funding
                            setState(() {
                              _selectedPaymentMethod = 'manual';
                              _statusMessage = '';
                            });
                            _processPayment();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF25D366),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // ✅ Option 3: Retry
                Center(
                  child: TextButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _processPayment();
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: _secondaryColor,
                    ),
                    child: Text(
                      'Retry Virtual Account',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  setState(() {
                    _statusMessage = '';
                  });
                },
                style: TextButton.styleFrom(
                  foregroundColor: Colors.grey.shade600,
                ),
                child: Text(
                  'Cancel',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
    );
  }

  /// Show smart dialog with actions when virtual account fails
  void _showVirtualAccountActionDialog({
    required double amount,
    required String errorMessage,
    required bool isBankError,
  }) {
    final formattedAmount = '₦${amount.toStringAsFixed(2)}';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            backgroundColor: _white,
            title: Row(
              children: [
                Icon(
                  isBankError
                      ? Icons.warning_amber_rounded
                      : Icons.error_outline,
                  color: isBankError ? _warningColor : _errorColor,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    isBankError
                        ? 'Service Unavailable'
                        : 'Virtual Account Failed',
                    style: GoogleFonts.inter(
                      color: isBankError ? _warningColor : _errorColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
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
                  isBankError
                      ? 'The virtual account service is currently unavailable for $formattedAmount.'
                      : 'Unable to generate virtual account for $formattedAmount.',
                  style: GoogleFonts.inter(fontSize: 14, color: _textColor),
                ),
                const SizedBox(height: 16),

                // ✅ Option 1: Dedicated Account
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _primaryColor.withAlpha(12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _primaryColor.withAlpha(50)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.account_balance,
                            color: _primaryColor,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _hasDedicatedAccount
                                  ? 'Use Your Dedicated Account'
                                  : 'Get a Dedicated Account',
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: _primaryColor,
                              ),
                            ),
                          ),
                          if (_hasDedicatedAccount)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: _successColor.withAlpha(20),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '1.5% Fee',
                                style: GoogleFonts.inter(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: _accentColor,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _hasDedicatedAccount
                            ? 'Use your existing dedicated account with 1.5% fee per transaction. Funds are credited instantly.'
                            : 'Complete your KYC to get a personal dedicated account with 1.5% fee per transaction, static account number, and instant funding.',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: _textColor,
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.pop(ctx);
                            if (_hasDedicatedAccount) {
                              // Use dedicated account
                              setState(() {
                                _selectedPaymentMethod = 'dedicated_account';
                                _statusMessage = '';
                              });
                              _processPayment();
                            } else {
                              // Go to KYC
                              _navigateToKYC();
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _primaryColor,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            minimumSize: const Size(double.infinity, 40),
                          ),
                          child: Text(
                            _hasDedicatedAccount
                                ? 'Use Dedicated Account'
                                : 'Complete KYC',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // ✅ Option 2: Manual Funding
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _warningColor.withAlpha(12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _warningColor.withAlpha(50)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.support_agent,
                            color: _warningColor,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Manual Funding',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: _warningColor,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Contact admin for manual funding assistance.',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: _textColor,
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const FaIcon(
                            FontAwesomeIcons.whatsapp,
                            color: Colors.white,
                            size: 16,
                          ),
                          label: Text(
                            'Contact Admin',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          onPressed: () {
                            Navigator.pop(ctx);
                            setState(() {
                              _selectedPaymentMethod = 'manual';
                              _statusMessage = '';
                            });
                            _processPayment();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF25D366),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            minimumSize: const Size(double.infinity, 40),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // ✅ Option 3: Retry (with note about bank error)
                if (isBankError) ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: Colors.blue.shade700,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'This is a temporary issue. You can retry or use one of the options above.',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: Colors.blue.shade700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],

                Center(
                  child: TextButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _processPayment();
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: _secondaryColor,
                    ),
                    child: Text(
                      'Retry Virtual Account',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  setState(() {
                    _statusMessage = '';
                  });
                },
                style: TextButton.styleFrom(
                  foregroundColor: Colors.grey.shade600,
                ),
                child: Text(
                  'Cancel',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
    );
  }

  /// Show dialog when virtual account is unavailable - prompt for KYC
  void _showVirtualAccountUnavailableDialog(double amount) {
    final formattedAmount = '₦${amount.toStringAsFixed(2)}';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            backgroundColor: _white,
            title: Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: _warningColor,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Text(
                  'Service Unavailable',
                  style: GoogleFonts.inter(
                    color: _warningColor,
                    fontWeight: FontWeight.bold,
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
                  'The virtual account service is currently unavailable for $formattedAmount.',
                  style: GoogleFonts.inter(fontSize: 14, color: _textColor),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _primaryColor.withAlpha(12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _primaryColor.withAlpha(50)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.account_balance,
                            color: _primaryColor,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Get a Dedicated Account',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: _primaryColor,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Complete your KYC to get a personal dedicated account with:',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: _textColor,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(
                            Icons.check_circle,
                            color: _accentColor,
                            size: 14,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '1.5% service fee per transaction',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: _accentColor,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Icon(
                            Icons.check_circle,
                            color: _successColor,
                            size: 14,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Static account number (always the same)',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: _successColor,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Icon(
                            Icons.check_circle,
                            color: _successColor,
                            size: 14,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Instant funding anytime',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: _successColor,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  // Navigate to KYC
                  _navigateToKYC();
                },
                style: TextButton.styleFrom(foregroundColor: _primaryColor),
                child: Text(
                  'Complete KYC',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                ),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  // Retry virtual account
                  _processPayment();
                },
                style: TextButton.styleFrom(foregroundColor: _secondaryColor),
                child: Text(
                  'Retry',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                ),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  setState(() {
                    _statusMessage = '';
                  });
                },
                style: TextButton.styleFrom(
                  foregroundColor: Colors.grey.shade600,
                ),
                child: Text(
                  'Cancel',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
    );
  }

  /// Helper: Build detail row for dialog
  Widget _buildDetailRowCompact(
    IconData icon,
    String label,
    String value, {
    bool isCopyable = false,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: _primaryColor.withAlpha(12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: _primaryColor, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  value,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: Colors.black87,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (isCopyable)
            IconButton(
              icon: Icon(Icons.copy, size: 14, color: _primaryColor),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: value));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Copied to clipboard!'),
                    duration: Duration(seconds: 1),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28),
            ),
        ],
      ),
    );
  }

  // ==================== DIALOGS ====================
  void _showVirtualAccountDialog({
    required String accountNumber,
    required String accountName,
    required String bankName,
    required double amount,
    required double totalPayable,
    required double fee,
    required String reference,
    required int expiresIn,
    required String userId,
    required String method,
    required bool isDedicated,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (ctx) => _VirtualAccountDialog(
            accountNumber: accountNumber,
            accountName: accountName,
            bankName: bankName,
            amount: amount,
            totalPayable: totalPayable,
            fee: fee,
            reference: reference,
            expiresIn: expiresIn,
            userId: userId,
            onBalanceUpdate: widget.onBalanceUpdate,
            primaryColor: _primaryColor,
            method: method,
            isDedicated: isDedicated,
          ),
    );
  }

  void _showManualFundingDialog(double amount) {
    final formattedAmount = '₦${amount.toStringAsFixed(2)}';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            backgroundColor: _white,
            title: Row(
              children: [
                Icon(Icons.support_agent, color: _warningColor, size: 28),
                const SizedBox(width: 12),
                Text(
                  'Manual Funding Request',
                  style: GoogleFonts.inter(
                    color: _primaryColor,
                    fontWeight: FontWeight.bold,
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
                  'Your funding request for $formattedAmount has been submitted.',
                  style: GoogleFonts.inter(fontSize: 14, color: _textColor),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _warningColor.withAlpha(25),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _warningColor.withAlpha(50)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '📌 Next Steps:',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.bold,
                          color: _warningColor,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '1. An admin will review your request\n'
                        '2. You will receive bank details via notification\n'
                        '3. Transfer the amount to the provided account\n'
                        '4. Your wallet will be credited automatically',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: _textColor,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const FaIcon(
                      FontAwesomeIcons.whatsapp,
                      color: Colors.white,
                      size: 18,
                    ),
                    label: Text(
                      'Contact Admin via WhatsApp',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onPressed: () async {
                      Navigator.pop(ctx);
                      final message =
                          'Hello DalabaPay Support,\n\n'
                          'I would like to fund my wallet manually.\n'
                          'Requested Amount: $formattedAmount\n\n'
                          'Please provide your account details for the transfer.\n\n'
                          'Thank you.';

                      final encodedMessage = Uri.encodeComponent(message);
                      final whatsappUrl =
                          'https://wa.me/2349163207050?text=$encodedMessage';

                      try {
                        if (await canLaunchUrl(Uri.parse(whatsappUrl))) {
                          await launchUrl(
                            Uri.parse(whatsappUrl),
                            mode: LaunchMode.externalApplication,
                          );
                        } else {
                          _showErrorDialog(
                            'WhatsApp Not Found',
                            'Please install WhatsApp or contact support directly.',
                          );
                        }
                      } catch (e) {
                        _showErrorDialog(
                          'Error',
                          'Failed to open WhatsApp: ${e.toString()}',
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF25D366),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                style: TextButton.styleFrom(foregroundColor: _primaryColor),
                child: Text(
                  'Close',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
    );
  }

  // ==================== BUILD METHODS ====================
  @override
  Widget build(BuildContext context) {
    // Send money (wallet → wallet) shares this route via initialTab.
    if (widget.initialTab == 'transfer') {
      return SendMoneyView(
        userId: widget.userId,
        onBalanceUpdate: widget.onBalanceUpdate,
      );
    }
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    return Scaffold(
      backgroundColor: DP.bg,
      body: SafeArea(
        child: Column(
          children: [
            DPTopBar(
              title: 'Add money',
              actionLabel: 'History',
              onAction: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => TransactionsScreen(userId: widget.userId),
                ),
              ),
            ),
            Expanded(child: _buildBody(isMobile)),
          ],
        ),
      ),
    );
  }


  Widget _buildBody(bool isMobile) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: _buildAddMoneyTab(isMobile),
    );
  }

  static const Map<String, String> _methodLabels = {
    'dedicated_account': 'Bank transfer',
    'virtual_account': 'One-time account',
    'manual': 'Assisted',
  };

  // ==================== ADD MONEY TAB ====================
  Widget _buildAddMoneyTab(bool isMobile) {
    final method = _selectedPaymentMethod ?? 'dedicated_account';
    final showForm = method != 'dedicated_account';
    return RefreshIndicator(
      color: DP.green,
      onRefresh: () async {
        await Future.wait([_loadBalances(), _checkDedicatedAccount()]);
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const DPHeadline(
              'Ready for your everyday.',
              subtitle: 'Fund your wallet with a bank transfer.',
              bottom: 18,
            ),
            _buildPaymentMethodsSection(isMobile),
            const SizedBox(height: 18),
            if (!showForm) ...[
              _buildDedicatedAccountStatus(isMobile),
              const SizedBox(height: 14),
              _buildBalanceCard(isMobile),
              const SizedBox(height: 14),
              const DPBanner(
                'Send money from any Nigerian bank app to the account above. Your bank may charge a transfer fee.',
              ),
            ] else ...[
              Text(
                method == 'virtual_account'
                    ? 'Get a one-time account for an exact amount. Pay it within the time shown and your wallet is credited automatically.'
                    : 'Our team will help you fund your wallet manually. Enter the amount you want to add.',
                style: DP.body.copyWith(color: DP.muted, fontSize: 14),
              ),
              const SizedBox(height: 18),
              _buildAmountInput(isMobile),
              const SizedBox(height: 18),
              _buildAuthenticationSection(isMobile),
              const SizedBox(height: 18),
              _buildBalanceCard(isMobile),
              const SizedBox(height: 18),
              _buildProceedButton(isMobile),
              if (_statusMessage.isNotEmpty) ...[
                const SizedBox(height: 12),
                _buildStatusMessage(),
              ],
            ],
            const SizedBox(height: 18),
            DPCard(
              padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
              child: DPListRow(
                leading: const DPIconBadge.blue(DPIcons.help, size: 40, iconSize: 20),
                title: 'Transfer hasn\'t arrived?',
                subtitle: 'Find a transfer with its bank reference',
                trailing: const Icon(DPIcons.chevronRight, color: DP.muted),
                onTap: () => Navigator.pushNamed(context, '/transaction-validation'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== DEDICATED ACCOUNT STATUS - FIXED ====================
  Widget _buildDedicatedAccountStatus(bool isMobile) {
    if (_isCheckingAccount) {
      return Container(
        height: 168,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: DP.navy,
          borderRadius: BorderRadius.circular(DP.rXl),
        ),
        child: const CircularProgressIndicator(color: Colors.white),
      );
    }

    if (_hasDedicatedAccount &&
        _dedicatedAccountNumber != null &&
        _dedicatedAccountNumber != 'N/A') {
      final accountName = _dedicatedAccountName != null &&
              _dedicatedAccountName!.isNotEmpty &&
              _dedicatedAccountName != 'User'
          ? _dedicatedAccountName!
          : 'Dalabapay';
      return Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
            decoration: BoxDecoration(
              color: DP.navy,
              borderRadius: BorderRadius.circular(DP.rXl),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      DPIcons.bank,
                      color: Colors.white.withValues(alpha: 0.85),
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'YOUR WALLET FUNDING ACCOUNT',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 12,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                    InkResponse(
                      onTap: _checkDedicatedAccount,
                      radius: 18,
                      child: Icon(
                        DPIcons.refresh,
                        color: Colors.white.withValues(alpha: 0.7),
                        size: 18,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: SelectableText(
                    _dedicatedAccountNumber!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  accountName,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                ),
                const SizedBox(height: 10),
                Text(
                  _dedicatedBankName ?? '',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          DPButton(
            label: 'Copy account number',
            icon: DPIcons.copy,
            onPressed: () {
              Clipboard.setData(
                ClipboardData(text: _dedicatedAccountNumber ?? ''),
              );
              HapticFeedback.lightImpact();
              dpSnack(context, 'Account number copied', success: true);
            },
          ),
        ],
      );
    }

    // No dedicated account - show KYC prompt
    return DPCard(
      padding: const EdgeInsets.fromLTRB(18, 18, 14, 18),
      onTap: _navigateToKYC,
      child: Row(
        children: [
          const DPIconBadge(DPIcons.badge, size: 48),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Get your funding account', style: DP.bodyStrong),
                const SizedBox(height: 4),
                Text(
                  'Verify your details to get a personal account number for bank transfers.',
                  style: DP.caption.copyWith(fontSize: 12.5),
                ),
              ],
            ),
          ),
          const Icon(DPIcons.chevronRight, color: DP.muted),
        ],
      ),
    );
  }

  Widget _buildAmountInput(bool isMobile) {
    const quick = [1000.0, 2000.0, 5000.0, 10000.0, 20000.0, 50000.0];
    final labels = quick.map((a) => DP.naira(a, decimals: false)).toList();
    final current = double.tryParse(_amountController.text.trim());
    final sel = current == null || !quick.contains(current)
        ? null
        : DP.naira(current, decimals: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const DPLabel('Amount'),
        DPField(
          controller: _amountController,
          hint: '0.00',
          prefixText: '₦',
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: (_) => setState(() {}),
          style: const TextStyle(fontSize: 17, color: DP.ink),
        ),
        const DPHelper('Minimum ₦100 · Maximum ₦1,000,000'),
        const SizedBox(height: 12),
        DPChipGrid(
          options: labels,
          selected: sel,
          onSelect: (l) => setState(
            () => _amountController.text =
                quick[labels.indexOf(l)].toStringAsFixed(0),
          ),
        ),
      ],
    );
  }


  // ==================== PAYMENT METHODS SECTION ====================
  Widget _buildPaymentMethodsSection(bool isMobile) {
    final method = _selectedPaymentMethod ?? 'dedicated_account';
    return DPChipRow(
      options: _methodLabels.values.toList(),
      selected: _methodLabels[method],
      height: 44,
      spacing: 8,
      onSelect: (label) {
        final id = _methodLabels.entries.firstWhere((e) => e.value == label).key;
        setState(() {
          _selectedPaymentMethod = id;
          _statusMessage = '';
        });
      },
    );
  }


  // ==================== AUTHENTICATION SECTION - MATCHES AIRTIME PAGE ====================
  Widget _buildAuthenticationSection(bool isMobile) {
    if (!_pinRequired) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_biometricEnabled)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                const Icon(DPIcons.fingerprint, color: DP.green),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('Confirm with biometrics', style: DP.body),
                ),
                Switch(
                  value: _useBiometric,
                  onChanged: (value) {
                    setState(() {
                      _useBiometric = value;
                      if (value) _pinController.clear();
                    });
                  },
                ),
              ],
            ),
          ),
        if (!_useBiometric) ...[
          const Text('Enter your payment PIN', style: DP.section),
          const SizedBox(height: 12),
          DPCodeInput(controller: _pinController, length: 6),
        ],
      ],
    );
  }

  Widget _buildProceedButton(bool isMobile) {
    final isLoading = _isLoading || _isAuthenticating;
    final label = _selectedPaymentMethod == 'manual'
        ? 'Request assisted funding'
        : 'Get account details';
    return DPButton(
      label: label,
      icon: DPIcons.forward,
      loading: isLoading,
      onPressed: isLoading ? null : _processPayment,
    );
  }

  Widget _buildStatusMessage() {
    final isError = _statusColor == _errorColor;
    final isOk = _statusColor == _successColor;
    return DPBanner(
      _statusMessage,
      tone: isError ? DPTone.error : (isOk ? DPTone.success : DPTone.info),
    );
  }

  Widget _buildBalanceCard(bool isMobile) {
    final isDedicated =
        (_selectedPaymentMethod ?? 'dedicated_account') == 'dedicated_account';
    return DPCard(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
      child: Column(
        children: [
          if (isDedicated)
            const DPSummaryRow('Transfer processing', 'Usually within minutes'),
          if (_selectedPaymentMethod != 'manual')
            const DPSummaryRow('Dalabapay funding fee', '1.5% per transfer'),
          DPSummaryRow(
            'Wallet balance',
            _isBalanceLoading
                ? '…'
                : (_isBalanceVisible
                    ? DP.naira(_currentBalance)
                    : '₦ ••••'),
          ),
        ],
      ),
    );
  }

  // ==================== TRANSFER TAB ====================
  Widget _buildTransferTab(bool isMobile) {
    return SendMoneyView(
      userId: widget.userId,
      onBalanceUpdate: widget.onBalanceUpdate,
    );
  }
}

// ==================== VIRTUAL ACCOUNT DIALOG ====================
class _VirtualAccountDialog extends StatefulWidget {
  final String accountNumber;
  final String accountName;
  final String bankName;
  final double amount;
  final double totalPayable;
  final double fee;
  final String reference;
  final int expiresIn;
  final String userId;
  final Function(double) onBalanceUpdate;
  final Color primaryColor;
  final String method;
  final bool isDedicated;

  const _VirtualAccountDialog({
    required this.accountNumber,
    required this.accountName,
    required this.bankName,
    required this.amount,
    required this.totalPayable,
    required this.fee,
    required this.reference,
    required this.expiresIn,
    required this.userId,
    required this.onBalanceUpdate,
    required this.primaryColor,
    required this.method,
    required this.isDedicated,
  });

  @override
  State<_VirtualAccountDialog> createState() => _VirtualAccountDialogState();
}

class _VirtualAccountDialogState extends State<_VirtualAccountDialog>
    with TickerProviderStateMixin {
  int _timeRemaining = 0;
  Timer? _countdownTimer;
  bool _showVerification = false;
  final Color _secondaryColor = const Color(0xFF168566);

  @override
  void initState() {
    super.initState();
    _timeRemaining = widget.expiresIn * 60;
    _startCountdown();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_timeRemaining > 0) {
        setState(() => _timeRemaining--);
      } else {
        timer.cancel();
      }
    });
  }

  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Copied to clipboard!'),
        duration: Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isExpiringSoon = _timeRemaining < 300;
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    if (_showVerification) {
      return _VerificationDialog(
        accountNumber: widget.accountNumber,
        amount: widget.amount,
        userId: widget.userId,
        onBalanceUpdate: widget.onBalanceUpdate,
        primaryColor: widget.primaryColor,
        reference: widget.reference,
      );
    }

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: isMobile ? double.infinity : 480,
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 16, 12),
              decoration: BoxDecoration(
                color: widget.primaryColor.withAlpha(12),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Text(
                          widget.isDedicated
                              ? 'Dedicated Account'
                              : 'Virtual Account',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.bold,
                            fontSize: isMobile ? 16 : 18,
                            color: widget.primaryColor,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF173D88).withAlpha(25),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '1.5% Fee',
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF173D88),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.close,
                      color: Colors.grey.shade600,
                      size: 22,
                    ),
                    onPressed: () {
                      _countdownTimer?.cancel();
                      if (Navigator.canPop(context)) {
                        if (Navigator.canPop(context)) {
                          Navigator.pop(context);
                        } else {
                          // Navigate to a fallback screen
                          Navigator.pushReplacementNamed(context, '/home');
                        }
                      } else {
                        // Navigate to a fallback screen
                        Navigator.pushReplacementNamed(context, '/home');
                      }
                    },
                    padding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),

            // Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    _buildDetailRow(
                      icon: Icons.account_balance,
                      label: 'Bank',
                      value: widget.bankName,
                      isCopyable: true,
                      primaryColor: widget.primaryColor,
                    ),
                    const SizedBox(height: 12),
                    _buildDetailRow(
                      icon: Icons.credit_card,
                      label: 'Account Number',
                      value: widget.accountNumber,
                      isCopyable: true,
                      primaryColor: widget.primaryColor,
                      isHighlighted: true,
                    ),
                    const SizedBox(height: 12),
                    _buildDetailRow(
                      icon: Icons.person,
                      label: 'Account Name',
                      value: widget.accountName,
                      isCopyable: true,
                      primaryColor: widget.primaryColor,
                    ),
                    const Divider(height: 24),
                    _buildDetailRow(
                      icon: Icons.money,
                      label: 'Amount to Pay',
                      value: '₦${widget.totalPayable.toStringAsFixed(2)}',
                      primaryColor: widget.primaryColor,
                    ),
                    const SizedBox(height: 12),
                    if (widget.fee > 0)
                      _buildDetailRow(
                        icon: Icons.receipt,
                        label: 'Service Fee (1.5%)',
                        value: '₦${widget.fee.toStringAsFixed(2)}',
                        primaryColor: widget.primaryColor,
                      ),
                    if (widget.fee > 0)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF173D88).withAlpha(12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFF173D88).withAlpha(25),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.info_outline,
                              color: Color(0xFF173D88),
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '1.5% of ₦${widget.totalPayable.toStringAsFixed(2)} (₦${widget.fee.toStringAsFixed(2)}) will be deducted from your funding. You will receive ₦${(widget.totalPayable - widget.fee).toStringAsFixed(2)} in your wallet.',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: const Color(0xFF173D88),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color:
                            isExpiringSoon
                                ? Colors.red.shade50
                                : Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color:
                              isExpiringSoon
                                  ? Colors.red.shade200
                                  : Colors.grey.shade200,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: widget.primaryColor.withAlpha(25),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.timer,
                              color:
                                  isExpiringSoon
                                      ? Colors.red.shade700
                                      : widget.primaryColor,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Expires In',
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    Text(
                                      'Time remaining:',
                                      style: GoogleFonts.inter(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                        color:
                                            isExpiringSoon
                                                ? Colors.red.shade700
                                                : Colors.black87,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color:
                                            isExpiringSoon
                                                ? Colors.red.shade100
                                                : Colors.orange.shade100,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        _formatTime(_timeRemaining),
                                        style: GoogleFonts.inter(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color:
                                              isExpiringSoon
                                                  ? Colors.red.shade800
                                                  : Colors.orange.shade800,
                                        ),
                                      ),
                                    ),
                                  ],
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
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Column(
                        children: [
                          Text(
                            '⚠️ Important',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Transfer exactly ₦${widget.totalPayable.toStringAsFixed(2)} to this account.\n'
                            '⚠️ A 1.5% service fee (₦${widget.fee.toStringAsFixed(2)}) will be deducted from the amount funded.\n'
                            'Your wallet will be credited automatically when payment is received.\n'
                            '⏰ This account expires in ${widget.expiresIn} minutes.',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: Colors.blue.shade700,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Bottom buttons
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: () {
                      _countdownTimer?.cancel();
                      if (Navigator.canPop(context)) {
                        if (Navigator.canPop(context)) {
                          Navigator.pop(context);
                        } else {
                          // Navigate to a fallback screen
                          Navigator.pushReplacementNamed(context, '/home');
                        }
                      } else {
                        // Navigate to a fallback screen
                        Navigator.pushReplacementNamed(context, '/home');
                      }
                    },
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    child: Text(
                      'Cancel',
                      style: GoogleFonts.inter(
                        color: Colors.grey.shade600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  Flexible(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () {
                            _countdownTimer?.cancel();
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
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder:
                                    (context) => TransactionsScreen(
                                      userId: widget.userId,
                                    ),
                              ),
                            );
                          },
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                          ),
                          child: Text(
                            'History',
                            style: GoogleFonts.inter(
                              color: widget.primaryColor,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Container(
                          constraints: const BoxConstraints(
                            minWidth: 120,
                            maxWidth: 200,
                          ),
                          child: ElevatedButton(
                            onPressed: () {
                              setState(() {
                                _showVerification = true;
                              });
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _secondaryColor,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              minimumSize: const Size(0, 40),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(
                              'I\'ve Made Payment',
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow({
    required IconData icon,
    required String label,
    required String value,
    bool isCopyable = false,
    required Color primaryColor,
    bool isHighlighted = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isHighlighted ? primaryColor.withAlpha(12) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color:
              isHighlighted ? primaryColor.withAlpha(50) : Colors.grey.shade200,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: primaryColor.withAlpha(25),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: primaryColor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: GoogleFonts.inter(
                    fontSize: isHighlighted ? 16 : 14,
                    fontWeight:
                        isHighlighted ? FontWeight.bold : FontWeight.w600,
                    color: isHighlighted ? primaryColor : Colors.black87,
                  ),
                ),
              ],
            ),
          ),
          if (isCopyable)
            IconButton(
              icon: Icon(Icons.copy, size: 18, color: primaryColor),
              onPressed: () => _copyToClipboard(value),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32),
            ),
        ],
      ),
    );
  }
}

// ==================== VERIFICATION DIALOG ====================
class _VerificationDialog extends StatefulWidget {
  final String accountNumber;
  final double amount;
  final String userId;
  final Function(double) onBalanceUpdate;
  final Color primaryColor;
  final String reference;

  const _VerificationDialog({
    required this.accountNumber,
    required this.amount,
    required this.userId,
    required this.onBalanceUpdate,
    required this.primaryColor,
    required this.reference,
  });

  @override
  State<_VerificationDialog> createState() => _VerificationDialogState();
}

class _VerificationDialogState extends State<_VerificationDialog>
    with TickerProviderStateMixin {
  int _attempts = 0;
  int _timeRemaining = 60;
  bool _isComplete = false;
  bool _isSuccess = false;
  bool _isTimeout = false;
  double _creditedAmount = 0;
  double _oldBalance = 0;
  double _newBalance = 0;
  String _statusMessage = 'Verifying payment status...';
  Timer? _timer;
  Timer? _countdownTimer;

  late AnimationController _spinController;
  late Animation<double> _spinAnimation;

  @override
  void initState() {
    super.initState();
    _spinController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();
    _spinAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(_spinController);
    _startVerification();
  }

  @override
  void dispose() {
    _spinController.dispose();
    _timer?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<double> _fetchUserBalance() async {
    try {
      final response = await http
          .get(
            Uri.parse(
              'https://virtual-account-backend.onrender.com/api/wallet/balance/${widget.userId}',
            ),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['walletBalance'] != null) {
          return (data['walletBalance'] as num).toDouble();
        }
      }
      return 0.0;
    } catch (e) {
      debugPrint('Balance fetch error: $e');
      return 0.0;
    }
  }

  void _startVerification() async {
    _oldBalance = await _fetchUserBalance();
    debugPrint('💰 Initial balance: ₦$_oldBalance');

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_isComplete && _timeRemaining > 0) {
        setState(() => _timeRemaining--);
      }
    });

    _timer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      _attempts++;

      try {
        final result = await ApiService.checkTransactionStatus(
          reference: widget.reference,
        );

        if (result['success'] == true && result['status'] == 'completed') {
          _countdownTimer?.cancel();
          timer.cancel();

          _creditedAmount = widget.amount;
          _newBalance = await _fetchUserBalance();

          setState(() {
            _isSuccess = true;
            _isComplete = true;
            _statusMessage =
                'Payment Successful! ₦${_creditedAmount.toStringAsFixed(2)} added to your wallet.';
          });

          widget.onBalanceUpdate(_newBalance);
          return;
        }

        final currentBalance = await _fetchUserBalance();
        if (currentBalance > _oldBalance) {
          _countdownTimer?.cancel();
          timer.cancel();

          _creditedAmount = widget.amount;
          _newBalance = currentBalance;

          setState(() {
            _isSuccess = true;
            _isComplete = true;
            _statusMessage =
                'Payment Successful! ₦${_creditedAmount.toStringAsFixed(2)} added to your wallet.';
          });

          widget.onBalanceUpdate(currentBalance);
          return;
        }

        if (_attempts >= 20) {
          _countdownTimer?.cancel();
          timer.cancel();
          setState(() {
            _isTimeout = true;
            _isComplete = true;
            _statusMessage =
                '⏰ Verification Timeout. Please check Transaction History.';
          });
        } else if (_attempts % 3 == 0) {
          setState(() {
            _statusMessage =
                'Checking payment status... (${60 - (_attempts * 3)}s remaining)';
          });
        }
      } catch (e) {
        debugPrint('Status check error: $e');
        if (_attempts >= 20) {
          _countdownTimer?.cancel();
          timer.cancel();
          setState(() {
            _isTimeout = true;
            _isComplete = true;
            _statusMessage =
                '⚠️ Unable to verify payment. Please check Transaction History.';
          });
        }
      }
    });
  }

  void _navigateToTransactionHistory() {
    if (Navigator.canPop(context)) {
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      } else {
        // Navigate to a fallback screen
        Navigator.pushReplacementNamed(context, '/home');
      }
    } else {
      // Navigate to a fallback screen
      Navigator.pushReplacementNamed(context, '/home');
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (context) => TransactionsScreen(
              userId: widget.userId,
              highlightReference: widget.reference,
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: Colors.white,
      child: Container(
        constraints: BoxConstraints(maxWidth: isMobile ? double.infinity : 400),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!_isComplete)
              AnimatedBuilder(
                animation: _spinController,
                builder: (context, child) {
                  return Transform.rotate(
                    angle: _spinAnimation.value * 2 * 3.14159,
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: widget.primaryColor.withAlpha(25),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.autorenew,
                        size: 48,
                        color: widget.primaryColor,
                      ),
                    ),
                  );
                },
              ),
            if (_isSuccess)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF168566).withAlpha(25),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle,
                  size: 48,
                  color: Color(0xFF168566),
                ),
              ),
            if (_isTimeout)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.timer_off,
                  size: 48,
                  color: Colors.orange,
                ),
              ),
            const SizedBox(height: 20),
            Text(
              _statusMessage,
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color:
                    _isSuccess
                        ? const Color(0xFF168566)
                        : (_isTimeout
                            ? Colors.orange.shade700
                            : widget.primaryColor),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            if (!_isComplete) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: widget.primaryColor.withAlpha(25),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.timer, size: 18, color: widget.primaryColor),
                    const SizedBox(width: 8),
                    Text(
                      '${_timeRemaining ~/ 60}:${(_timeRemaining % 60).toString().padLeft(2, '0')}',
                      style: GoogleFonts.inter(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: widget.primaryColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              LinearProgressIndicator(
                value: (60 - _timeRemaining) / 60,
                backgroundColor: Colors.grey.shade200,
                color: widget.primaryColor,
                borderRadius: BorderRadius.circular(4),
              ),
              const SizedBox(height: 12),
              Text(
                'Attempt $_attempts/20',
                style: GoogleFonts.inter(fontSize: 12, color: Colors.grey),
              ),
            ],
            if (_isSuccess) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF168566).withAlpha(12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFF168566).withAlpha(25),
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      'Amount Credited',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: const Color(0xFF168566),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '₦${_creditedAmount.toStringAsFixed(2)}',
                      style: GoogleFonts.inter(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF168566),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Previous Balance',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ),
                        Text(
                          '₦${_oldBalance.toStringAsFixed(2)}',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'New Balance',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF168566),
                            ),
                          ),
                        ),
                        Text(
                          '₦${_newBalance.toStringAsFixed(2)}',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF168566),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            if (_isSuccess || _isTimeout)
              ElevatedButton.icon(
                onPressed: _navigateToTransactionHistory,
                icon: Icon(
                  _isSuccess ? Icons.receipt : Icons.history,
                  size: 18,
                  color: Colors.white,
                ),
                label: Text(
                  _isSuccess ? 'View Receipt' : 'View Transaction History',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      _isSuccess
                          ? const Color(0xFF168566)
                          : widget.primaryColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
              ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                _timer?.cancel();
                _countdownTimer?.cancel();
                if (Navigator.canPop(context)) {
                  if (Navigator.canPop(context)) {
                    Navigator.pop(context);
                  } else {
                    // Navigate to a fallback screen
                    Navigator.pushReplacementNamed(context, '/home');
                  }
                } else {
                  // Navigate to a fallback screen
                  Navigator.pushReplacementNamed(context, '/home');
                }
              },
              child: Text(
                _isComplete ? 'Close' : 'Cancel',
                style: GoogleFonts.inter(color: Colors.grey.shade600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
