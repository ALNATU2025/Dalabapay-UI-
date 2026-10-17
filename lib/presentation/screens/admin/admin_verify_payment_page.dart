// lib/presentation/screens/admin/admin_verify_payment_page.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:http/http.dart' as http;

import '../../../core/widgets/custom_drawer.dart';
import '../../../core/widgets/drawer_item.dart';
import '../dashboard/dashboard_screen.dart';

class AdminVerifyPaymentPage extends StatefulWidget {
  const AdminVerifyPaymentPage({super.key});

  @override
  State<AdminVerifyPaymentPage> createState() => _AdminVerifyPaymentPageState();
}

class _AdminVerifyPaymentPageState extends State<AdminVerifyPaymentPage>
    with SingleTickerProviderStateMixin {
  // ==================== BRAND COLORS ====================
  static const Color primaryColor = Color(0xFF102C68);
  static const Color secondaryColor = Color(0xFF168566);
  static const Color successColor = Color(0xFF168566);
  static const Color warningColor = Color(0xFFA76B1D);
  static const Color errorColor = Color(0xFFC0392B);
  static const Color infoColor = Color(0xFF173D88);
  static const Color textPrimary = Color(0xFF14263D);
  static const Color textSecondary = Color(0xFF728078);
  static const Color backgroundLight = Color(0xFFF8F9F5);

  // ==================== CONTROLLERS ====================
  final TextEditingController _transactionIdController =
      TextEditingController();
  final TextEditingController _referenceController = TextEditingController();
  final TextEditingController _userIdController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();

  // ==================== STATE ====================
  bool _isLoading = false;
  bool _isCheckingAdmin = true;
  bool _isAdmin = false;
  bool _isSpecificAdmin = false;
  String _adminName = '';
  String _errorMessage = '';
  Map<String, dynamic>? _transactionDetails;
  List<String> _verificationLogs = [];
  bool _showAdvancedOptions = false;
  bool _verificationSuccess = false;
  bool _transactionAlreadyProcessed = false;
  bool _isVirtualAccountPayment = false;
  String _currentStep = '';
  Map<String, dynamic>? _lastBackendResponse;

  // ==================== STATS ====================
  int _totalVerifiedToday = 0;
  int _totalPending = 0;
  double _totalAmountToday = 0.0;
  int _totalTransactions = 0;

  // ==================== ANIMATION ====================
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  Timer? _searchDebounce;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _loadAdminData();
  }

  @override
  void dispose() {
    _transactionIdController.dispose();
    _referenceController.dispose();
    _userIdController.dispose();
    _amountController.dispose();
    _descriptionController.dispose();
    _animationController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _setupAnimations() {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );
  }

  // ==================== DATA LOADING ====================

  Future<void> _loadAdminData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userDataString = prefs.getString('user');

      if (userDataString != null) {
        final userData = jsonDecode(userDataString);
        final bool isAdmin = userData['isAdmin'] == true;
        final String? userId = userData['_id'];
        const String specificAdminUserId = "690088325ca99bed6ab8d4a5";
        final bool isAdminById = userId == specificAdminUserId;

        setState(() {
          _isAdmin = isAdmin || isAdminById;
          _isSpecificAdmin = isAdminById;
          _adminName = userData['fullName'] ?? 'Admin';
          _isCheckingAdmin = false;
        });

        if (_isAdmin) {
          _loadStats();
          _animationController.forward();
        } else {
          setState(() {
            _isCheckingAdmin = false;
            _errorMessage =
                "You don't have permission to access admin features.";
          });
        }
      } else {
        setState(() {
          _isCheckingAdmin = false;
          _errorMessage = "User data not found. Please log in again.";
        });
      }
    } catch (e) {
      setState(() {
        _isCheckingAdmin = false;
        _errorMessage = "Error loading admin data: $e";
      });
    }
  }

  Future<void> _loadStats() async {
    try {
      // In production, fetch from API
      // For now, simulate loading
      await Future.delayed(const Duration(milliseconds: 500));
      setState(() {
        _totalVerifiedToday = 24;
        _totalPending = 8;
        _totalAmountToday = 125000.50;
        _totalTransactions = 156;
      });
    } catch (e) {
      debugPrint('Error loading stats: $e');
    }
  }

  // ==================== PAYMENT VERIFICATION ====================

  Future<void> _verifyTransaction() async {
    final reference =
        _transactionIdController.text.isNotEmpty
            ? _transactionIdController.text.trim()
            : _referenceController.text.trim();

    if (reference.isEmpty) {
      _showSnackBar('Please enter Transaction ID or Reference', true);
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
      _transactionDetails = null;
      _verificationSuccess = false;
      _transactionAlreadyProcessed = false;
      _isVirtualAccountPayment = false;
      _verificationLogs = [];
      _currentStep = '';
    });

    try {
      _addLog('🔍 [START] Transaction verification initiated');
      _addLog('📋 Reference: $reference');
      _addLog('👤 Admin: $_adminName');

      _updateStep('Validating reference format...');

      // Validate reference format
      if (!_isValidReferenceFormat(reference)) {
        throw Exception(
          'Invalid reference format. Please check your transaction reference.',
        );
      }

      _addLog('✅ Reference format validated');
      _updateStep('Verifying with payment service...');

      // Call the verification API
      // Using your existing PaymentService or API call
      final result = await _callVerificationAPI(reference);
      _lastBackendResponse = result;

      _addLog('📦 [BACKEND RESPONSE] Received response');

      if (result['success'] == true) {
        final amount = result['amount'] ?? 0.0;
        final newBalance = result['newBalance'] ?? 0.0;
        final userId = result['userId'] ?? 'N/A';

        _addLog('✅ [SUCCESS] Payment verified!');
        _addLog('💰 Amount: ₦${amount.toStringAsFixed(2)}');
        _addLog('💳 New Balance: ₦${newBalance.toStringAsFixed(2)}');

        setState(() {
          _transactionDetails = {
            '_id': reference,
            'reference': reference,
            'amount': amount,
            'userId': userId,
            'type': 'credit',
            'status': 'successful',
            'description': 'Payment verification by $_adminName',
            'createdAt': DateTime.now().toIso8601String(),
            'user': {
              'fullName': result['userFullName'] ?? 'Verified User',
              'email': result['userEmail'] ?? 'user@verified.com',
              'phone': result['userPhone'] ?? 'N/A',
            },
            'newBalance': newBalance,
            'alreadyProcessed': false,
            'balanceCredited': true,
          };
          _verificationSuccess = true;
        });

        _updateStep('✅ Verification complete!');
        _showSnackBar('✅ Transaction Verified Successfully!', false);

        // Update stats
        _updateStats(amount);
      } else {
        final errorMessage = result['message'] ?? 'Verification failed.';
        _addLog('❌ [FAILURE] $errorMessage');
        _handleVerificationError(errorMessage);
      }
    } catch (e) {
      _addLog('❌ [EXCEPTION] ${e.toString()}');
      _handleVerificationError(e.toString());
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _currentStep = '';
        });
      }
    }
  }

  Future<Map<String, dynamic>> _callVerificationAPI(String reference) async {
    try {
      // This should call your actual API endpoint
      // Using the existing PaymentService or direct API call

      // Example API call - replace with your actual implementation
      final response = await http
          .post(
            Uri.parse('https://your-api.com/api/admin/verify-transaction'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${await _getToken()}',
            },
            body: jsonEncode({'reference': reference}),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        return {
          'success': false,
          'message': 'API Error: ${response.statusCode}',
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Network Error: ${e.toString()}'};
    }
  }

  Future<String> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token') ?? '';
  }

  bool _isValidReferenceFormat(String reference) {
    if (reference.isEmpty) {
      throw Exception('Please enter a transaction reference');
    }
    if (reference.length < 8) {
      throw Exception('Reference seems too short (minimum 8 characters)');
    }
    if (reference.length > 50) {
      throw Exception('Reference seems too long (maximum 50 characters)');
    }
    return true;
  }

  void _handleVerificationError(String error) {
    setState(() {
      _errorMessage = error;
      _verificationSuccess = false;
    });
    _showSnackBar('❌ $error', true);
  }

  // ==================== MANUAL VERIFICATION ====================

  Future<void> _manualVerification() async {
    if (_userIdController.text.isEmpty || _amountController.text.isEmpty) {
      _showSnackBar('Please enter User ID and Amount', true);
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
      _verificationLogs = [];
      _currentStep = '';
    });

    try {
      final userId = _userIdController.text.trim();
      final amount = double.tryParse(_amountController.text) ?? 0.0;

      if (amount <= 0) {
        throw Exception('Please enter a valid amount greater than 0');
      }

      _addLog('🔧 [MANUAL] Starting manual verification...');
      _updateStep('Processing manual top-up...');

      // Call your manual verification API
      final result = await _callManualVerificationAPI(userId, amount);

      if (result['success'] == true) {
        _addLog('✅ Manual verification successful');
        setState(() {
          _transactionDetails = {
            '_id': 'manual_${DateTime.now().millisecondsSinceEpoch}',
            'reference': 'MANUAL_${DateTime.now().millisecondsSinceEpoch}',
            'userId': userId,
            'amount': amount,
            'type': 'credit',
            'status': 'successful',
            'description':
                _descriptionController.text.isNotEmpty
                    ? _descriptionController.text
                    : 'Manual verification by $_adminName',
            'createdAt': DateTime.now().toIso8601String(),
            'user': {
              'fullName': 'Manual User',
              'email': 'manual@verification.com',
              'phone': 'N/A',
            },
          };
          _verificationSuccess = true;
        });

        _updateStep('✅ Manual verification complete!');
        _showSnackBar('✅ Manual verification successful!', false);
        _updateStats(amount);
      } else {
        throw Exception(result['message'] ?? 'Manual verification failed');
      }
    } catch (e) {
      _addLog('❌ [ERROR] ${e.toString()}');
      _showSnackBar('❌ ${e.toString()}', true);
    } finally {
      setState(() {
        _isLoading = false;
        _currentStep = '';
      });
    }
  }

  Future<Map<String, dynamic>> _callManualVerificationAPI(
    String userId,
    double amount,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse('https://your-api.com/api/admin/manual-topup'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${await _getToken()}',
            },
            body: jsonEncode({
              'userId': userId,
              'amount': amount,
              'reference': 'MANUAL_${DateTime.now().millisecondsSinceEpoch}',
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        return {
          'success': false,
          'message': 'API Error: ${response.statusCode}',
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Network Error: ${e.toString()}'};
    }
  }

  // ==================== HELPERS ====================

  void _addLog(String message) {
    if (mounted) {
      setState(() {
        _verificationLogs.insert(
          0,
          '${DateFormat('HH:mm:ss').format(DateTime.now())} - $message',
        );
        if (_verificationLogs.length > 50) {
          _verificationLogs.removeLast();
        }
      });
    }
  }

  void _updateStep(String step) {
    if (mounted) {
      setState(() {
        _currentStep = step;
      });
    }
  }

  void _updateStats(double amount) {
    setState(() {
      _totalVerifiedToday++;
      _totalAmountToday += amount;
      _totalTransactions++;
    });
  }

  void _clearForm() {
    _transactionIdController.clear();
    _referenceController.clear();
    _userIdController.clear();
    _amountController.clear();
    _descriptionController.clear();

    setState(() {
      _transactionDetails = null;
      _errorMessage = '';
      _verificationSuccess = false;
      _transactionAlreadyProcessed = false;
      _isVirtualAccountPayment = false;
      _verificationLogs = [];
      _currentStep = '';
    });
  }

  void _toggleAdvancedOptions() {
    setState(() {
      _showAdvancedOptions = !_showAdvancedOptions;
    });
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    _showSnackBar('📋 Copied to clipboard', false);
  }

  void _showSnackBar(String message, bool isError) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError
                  ? Icons.error_outline_rounded
                  : Icons.check_circle_rounded,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: GoogleFonts.inter(color: Colors.white),
              ),
            ),
          ],
        ),
        backgroundColor: isError ? errorColor : secondaryColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  String _formatDate(dynamic date) {
    try {
      if (date == null) return 'N/A';
      if (date is String) {
        return DateFormat('MMM dd, yyyy HH:mm:ss').format(DateTime.parse(date));
      }
      return 'N/A';
    } catch (e) {
      return 'N/A';
    }
  }

  String _formatCurrency(double amount) {
    return '₦${NumberFormat('#,##0.00').format(amount)}';
  }

  String _formatAmount(double amount) {
    if (amount >= 1000000) {
      return '${(amount / 1000000).toStringAsFixed(1)}M';
    } else if (amount >= 1000) {
      return '${(amount / 1000).toStringAsFixed(1)}K';
    }
    return amount.toStringAsFixed(0);
  }

  // ==================== DRAWER ====================

  Widget _buildDrawerHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [primaryColor, primaryColor.withValues(alpha: 0.8)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Dalaba',
                style: GoogleFonts.inter(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: 0.09,
                ),
              ),
              Text(
                'pay',
                style: GoogleFonts.inter(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: secondaryColor,
                  letterSpacing: 0.09,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: secondaryColor.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: secondaryColor.withValues(alpha: 0.3)),
            ),
            child: Text(
              'ADMIN PANEL',
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: secondaryColor,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<DrawerItem> get _drawerItems => [
    const DrawerItem(
      title: "Admin Dashboard",
      icon: Icons.dashboard,
      badge: "ADMIN",
      page: SizedBox.shrink(),
      isAdminOnly: true,
    ),
    const DrawerItem(
      title: "All Services",
      icon: Icons.apps,
      page: DashboardScreen(),
      isUserOnly: false,
    ),
    const DrawerItem(
      title: "Manage Users",
      icon: Icons.people_alt,
      page: SizedBox.shrink(),
      isAdminOnly: true,
    ),
    const DrawerItem(
      title: "Transactions",
      icon: Icons.receipt,
      page: SizedBox.shrink(),
      isAdminOnly: true,
    ),
    const DrawerItem(
      title: "Status Update",
      icon: Icons.update,
      page: SizedBox.shrink(),
      isAdminOnly: true,
    ),
    const DrawerItem(
      title: "Refund System",
      icon: Icons.currency_exchange,
      page: SizedBox.shrink(),
      isAdminOnly: true,
    ),
    const DrawerItem(
      title: "Fund Wallet",
      icon: Icons.account_balance_wallet,
      page: SizedBox.shrink(),
      isAdminOnly: true,
    ),
    const DrawerItem(
      title: "VTpass Settings",
      icon: Icons.api,
      page: SizedBox.shrink(),
      isAdminOnly: true,
    ),
    const DrawerItem(
      title: "Self Fund",
      icon: Icons.attach_money,
      page: SizedBox.shrink(),
      isAdminOnly: true,
    ),
    const DrawerItem(
      title: "Verify Payments",
      icon: Icons.verified,
      page: SizedBox.shrink(),
      isAdminOnly: true,
    ),
    const DrawerItem(
      title: "Notifications",
      icon: Icons.notifications_active,
      page: SizedBox.shrink(),
      isAdminOnly: true,
    ),
    const DrawerItem(
      title: "Admin Control",
      icon: Icons.settings_applications,
      page: SizedBox.shrink(),
      isAdminOnly: true,
    ),
    const DrawerItem(
      title: "Transaction Validation",
      icon: Icons.verified_user,
      page: SizedBox.shrink(),
      isUserOnly: true,
    ),
    const DrawerItem(
      title: "My Disputes",
      icon: Icons.gavel,
      page: SizedBox.shrink(),
      isUserOnly: true,
    ),
    const DrawerItem(
      title: "App Settings",
      icon: Icons.settings,
      page: SizedBox.shrink(),
    ),
    const DrawerItem(
      title: "Logout",
      icon: Icons.logout,
      page: SizedBox.shrink(),
    ),
  ];

  void _onDrawerItemSelected(DrawerItem item) {
    if (item.title == "Logout") {
      _showLogoutConfirmation();
      return;
    }
    if (item.title == "All Services") {
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
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const DashboardScreen()),
      );
      return;
    }
    if (item.page is! SizedBox) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => item.page),
      );
    }
  }

  void _showLogoutConfirmation() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Text('Logout'),
            content: const Text('Are you sure you want to logout?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
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
                  Navigator.pushReplacementNamed(context, '/login');
                },
                child: const Text(
                  'Logout',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
    );
  }

  // ==================== UI BUILDERS ====================

  Widget _buildAdminHeader() {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 16 : 24,
        vertical: isMobile ? 16 : 20,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [const Color(0xFF5BB592), const Color(0xFF102C68)],
          stops: const [0.06, 0.41],
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
        boxShadow: [
          BoxShadow(
            color: secondaryColor.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row
          Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.arrow_back_rounded,
                    color: Colors.white,
                    size: isMobile ? 20 : 24,
                  ),
                ),
              ),
              SizedBox(width: isMobile ? 12 : 16),
              Expanded(
                child: Text(
                  'Admin / Verify Payment',
                  style: GoogleFonts.inter(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: isMobile ? 12 : 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (_isSpecificAdmin)
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: isMobile ? 10 : 14,
                    vertical: isMobile ? 4 : 6,
                  ),
                  decoration: BoxDecoration(
                    color: secondaryColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'SUPER ADMIN',
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: isMobile ? 8 : 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
            ],
          ),

          SizedBox(height: isMobile ? 16 : 20),

          // Main header
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: isMobile ? 56 : 64,
                height: isMobile ? 56 : 64,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.verified_rounded,
                  color: primaryColor,
                  size: isMobile ? 28 : 34,
                ),
              ),
              SizedBox(width: isMobile ? 14 : 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Verify Payment',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: isMobile ? 20 : 28,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: isMobile ? 4 : 6),
                    Text(
                      'Verify and validate payment transactions',
                      style: GoogleFonts.inter(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: isMobile ? 12 : 14,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          SizedBox(height: isMobile ? 16 : 20),

          // Welcome text
          Container(
            padding: EdgeInsets.all(isMobile ? 12 : 16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.admin_panel_settings_rounded,
                  color: Colors.white.withValues(alpha: 0.8),
                  size: isMobile ? 18 : 22,
                ),
                SizedBox(width: isMobile ? 10 : 14),
                Expanded(
                  child: Text(
                    'Welcome, $_adminName',
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: isMobile ? 13 : 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: isMobile ? 8 : 12,
                    vertical: isMobile ? 4 : 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.circle_rounded,
                        color: successColor,
                        size: isMobile ? 8 : 10,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'Active',
                        style: GoogleFonts.inter(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: isMobile ? 10 : 12,
                          fontWeight: FontWeight.w500,
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
    );
  }

  Widget _buildStatsSection() {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 16 : 24,
        vertical: isMobile ? 8 : 12,
      ),
      child: Wrap(
        spacing: isMobile ? 8 : 12,
        runSpacing: isMobile ? 8 : 12,
        children: [
          _buildStatCard(
            title: 'Verified Today',
            value: _totalVerifiedToday.toString(),
            icon: HugeIcons.strokeRoundedCheckmarkCircle01,
            color: primaryColor,
            isMobile: isMobile,
          ),
          _buildStatCard(
            title: 'Pending',
            value: _totalPending.toString(),
            icon: HugeIcons.strokeRoundedTime01,
            color: warningColor,
            isMobile: isMobile,
          ),
          _buildStatCard(
            title: 'Amount Today',
            value: _formatAmount(_totalAmountToday),
            icon: HugeIcons.strokeRoundedMoney01,
            color: secondaryColor,
            isMobile: isMobile,
          ),
          _buildStatCard(
            title: 'Total Transactions',
            value: _totalTransactions.toString(),
            icon: HugeIcons.strokeRoundedReceiptText,
            color: infoColor,
            isMobile: isMobile,
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required dynamic icon,
    required Color color,
    required bool isMobile,
  }) {
    final cardWidth =
        isMobile
            ? (MediaQuery.of(context).size.width - 48) / 2
            : (MediaQuery.of(context).size.width - 72) / 4;

    return SizedBox(
      width: cardWidth,
      child: Container(
        padding: EdgeInsets.all(isMobile ? 12 : 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(isMobile ? 12 : 14),
          border: Border.all(color: color.withValues(alpha: 0.15)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(isMobile ? 6 : 8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: HugeIcon(
                icon: icon,
                color: color,
                size: isMobile ? 16 : 20,
              ),
            ),
            SizedBox(width: isMobile ? 8 : 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: GoogleFonts.inter(
                      fontSize: isMobile ? 16 : 20,
                      fontWeight: FontWeight.w700,
                      color: textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      fontSize: isMobile ? 9 : 11,
                      color: textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVerificationCard() {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Container(
      margin: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 24, vertical: 8),
      padding: EdgeInsets.all(isMobile ? 16 : 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(isMobile ? 16 : 20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.grey.shade100, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(isMobile ? 8 : 10),
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(isMobile ? 10 : 12),
                ),
                child: HugeIcon(
                  icon: HugeIcons.strokeRoundedAward04,
                  color: primaryColor,
                  size: isMobile ? 20 : 24,
                ),
              ),
              SizedBox(width: isMobile ? 10 : 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Transaction Verification',
                      style: GoogleFonts.inter(
                        fontSize: isMobile ? 16 : 18,
                        fontWeight: FontWeight.w600,
                        color: textPrimary,
                      ),
                    ),
                    Text(
                      'Verify transaction using ID, reference, or manual entry',
                      style: GoogleFonts.inter(
                        fontSize: isMobile ? 12 : 13,
                        color: textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (_verificationSuccess)
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: isMobile ? 8 : 12,
                    vertical: isMobile ? 4 : 6,
                  ),
                  decoration: BoxDecoration(
                    color: successColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: successColor.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.check_circle_rounded,
                        color: successColor,
                        size: isMobile ? 14 : 16,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'Verified',
                        style: GoogleFonts.inter(
                          color: successColor,
                          fontSize: isMobile ? 10 : 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),

          SizedBox(height: isMobile ? 16 : 20),

          // Transaction ID Field
          _buildTextField(
            controller: _transactionIdController,
            label: 'Transaction ID',
            hint: 'Enter transaction ID',
            icon: HugeIcons.strokeRoundedReceiptText,
            isMobile: isMobile,
          ),

          SizedBox(height: isMobile ? 10 : 12),

          // Reference Field
          _buildTextField(
            controller: _referenceController,
            label: 'Reference (Optional)',
            hint: 'Enter payment reference',
            icon: HugeIcons.strokeRoundedTag01,
            isMobile: isMobile,
          ),

          SizedBox(height: isMobile ? 14 : 16),

          // Action Buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _toggleAdvancedOptions,
                  icon: HugeIcon(
                    icon:
                        _showAdvancedOptions
                            ? HugeIcons.strokeRoundedMinusSignCircle
                            : HugeIcons.strokeRoundedAddCircle,
                    color: primaryColor,
                    size: isMobile ? 18 : 20,
                  ),
                  label: Text(
                    _showAdvancedOptions ? 'Hide Advanced' : 'Advanced Options',
                    style: GoogleFonts.inter(
                      color: primaryColor,
                      fontWeight: FontWeight.w500,
                      fontSize: isMobile ? 12 : 14,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.symmetric(vertical: isMobile ? 10 : 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    side: BorderSide(
                      color: primaryColor.withValues(alpha: 0.3),
                    ),
                  ),
                ),
              ),
              SizedBox(width: isMobile ? 8 : 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _verifyTransaction,
                  icon:
                      _isLoading
                          ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                          : HugeIcon(
                            icon: HugeIcons.strokeRoundedSearch01,
                            color: Colors.white,
                            size: isMobile ? 18 : 20,
                          ),
                  label: Text(
                    _isLoading ? 'Verifying...' : 'Verify',
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: isMobile ? 12 : 14,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    padding: EdgeInsets.symmetric(vertical: isMobile ? 10 : 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),

          // Advanced Options
          if (_showAdvancedOptions) ...[
            SizedBox(height: isMobile ? 16 : 20),
            _buildAdvancedOptions(),
          ],
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required dynamic icon,
    required bool isMobile,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: backgroundLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: TextField(
        controller: controller,
        style: GoogleFonts.inter(
          fontSize: isMobile ? 14 : 15,
          color: textPrimary,
        ),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          labelStyle: GoogleFonts.inter(
            color: textSecondary,
            fontSize: isMobile ? 12 : 13,
          ),
          hintStyle: GoogleFonts.inter(
            color: Colors.grey.shade400,
            fontSize: isMobile ? 13 : 14,
          ),
          prefixIcon: Padding(
            padding: EdgeInsets.all(isMobile ? 10 : 12),
            child: HugeIcon(
              icon: icon,
              color: primaryColor.withValues(alpha: 0.5),
              size: isMobile ? 18 : 20,
            ),
          ),
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(
            horizontal: isMobile ? 12 : 16,
            vertical: isMobile ? 14 : 16,
          ),
        ),
      ),
    );
  }

  Widget _buildAdvancedOptions() {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Container(
      padding: EdgeInsets.all(isMobile ? 14 : 18),
      decoration: BoxDecoration(
        color: primaryColor.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: primaryColor.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.build_rounded,
                color: primaryColor,
                size: isMobile ? 18 : 20,
              ),
              SizedBox(width: isMobile ? 8 : 10),
              Text(
                'Manual Verification',
                style: GoogleFonts.inter(
                  fontSize: isMobile ? 14 : 16,
                  fontWeight: FontWeight.w600,
                  color: textPrimary,
                ),
              ),
            ],
          ),
          SizedBox(height: isMobile ? 12 : 14),

          // User ID Field
          _buildManualTextField(
            controller: _userIdController,
            label: 'User ID',
            hint: 'Enter user ID',
            icon: HugeIcons.strokeRoundedUser,
            isMobile: isMobile,
          ),

          SizedBox(height: isMobile ? 10 : 12),

          // Amount Field
          _buildManualTextField(
            controller: _amountController,
            label: 'Amount',
            hint: 'Enter amount',
            icon: HugeIcons.strokeRoundedMoney01,
            keyboardType: TextInputType.number,
            isMobile: isMobile,
          ),

          SizedBox(height: isMobile ? 10 : 12),

          // Description Field
          _buildManualTextField(
            controller: _descriptionController,
            label: 'Description (Optional)',
            hint: 'Enter verification description',
            icon: HugeIcons.strokeRoundedFile01,
            maxLines: 2,
            isMobile: isMobile,
          ),

          SizedBox(height: isMobile ? 12 : 14),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _manualVerification,
              icon: HugeIcon(
                icon: HugeIcons.strokeRoundedUserIdVerification,
                color: Colors.white,
                size: isMobile ? 18 : 20,
              ),
              label: Text(
                'Manual Verify',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: isMobile ? 13 : 14,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: secondaryColor,
                padding: EdgeInsets.symmetric(vertical: isMobile ? 12 : 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildManualTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required dynamic icon,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
    required bool isMobile,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        maxLines: maxLines,
        style: GoogleFonts.inter(
          fontSize: isMobile ? 14 : 15,
          color: textPrimary,
        ),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          labelStyle: GoogleFonts.inter(
            color: textSecondary,
            fontSize: isMobile ? 12 : 13,
          ),
          hintStyle: GoogleFonts.inter(
            color: Colors.grey.shade400,
            fontSize: isMobile ? 13 : 14,
          ),
          prefixIcon: Padding(
            padding: EdgeInsets.all(isMobile ? 10 : 12),
            child: HugeIcon(
              icon: icon,
              color: primaryColor.withValues(alpha: 0.5),
              size: isMobile ? 16 : 18,
            ),
          ),
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(
            horizontal: isMobile ? 12 : 14,
            vertical: isMobile ? 12 : 14,
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentStep() {
    if (_currentStep.isEmpty) return const SizedBox();

    final isMobile = MediaQuery.of(context).size.width < 600;

    return Container(
      margin: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 24, vertical: 8),
      padding: EdgeInsets.all(isMobile ? 12 : 16),
      decoration: BoxDecoration(
        color: infoColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: infoColor.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(infoColor),
            ),
          ),
          SizedBox(width: isMobile ? 10 : 14),
          Expanded(
            child: Text(
              _currentStep,
              style: GoogleFonts.inter(
                fontSize: isMobile ? 13 : 14,
                fontWeight: FontWeight.w600,
                color: infoColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVerificationLog() {
    if (_verificationLogs.isEmpty) return const SizedBox();

    final isMobile = MediaQuery.of(context).size.width < 600;

    return Container(
      margin: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 24, vertical: 8),
      padding: EdgeInsets.all(isMobile ? 12 : 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(isMobile ? 12 : 16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              HugeIcon(
                icon: HugeIcons.strokeRoundedDocumentValidation,
                color: primaryColor,
                size: isMobile ? 18 : 20,
              ),
              SizedBox(width: isMobile ? 8 : 10),
              Text(
                'Verification Log',
                style: GoogleFonts.inter(
                  fontSize: isMobile ? 14 : 16,
                  fontWeight: FontWeight.w600,
                  color: textPrimary,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () {
                  setState(() => _verificationLogs.clear());
                },
                child: Text(
                  'Clear',
                  style: GoogleFonts.inter(
                    color: errorColor,
                    fontSize: isMobile ? 11 : 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: isMobile ? 8 : 10),
          Container(
            height: 200,
            decoration: BoxDecoration(
              color: backgroundLight,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: ListView.builder(
              reverse: true,
              padding: EdgeInsets.all(isMobile ? 8 : 10),
              itemCount: _verificationLogs.length,
              itemBuilder: (context, index) {
                final log = _verificationLogs[index];
                final color = _getLogColor(log);

                return Container(
                  margin: EdgeInsets.only(bottom: 6),
                  padding: EdgeInsets.all(isMobile ? 8 : 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade100),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 3,
                        height: 20,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      SizedBox(width: isMobile ? 8 : 10),
                      Expanded(
                        child: Text(
                          log,
                          style: GoogleFonts.inter(
                            fontSize: isMobile ? 11 : 12,
                            color: textPrimary,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Color _getLogColor(String log) {
    if (log.contains('✅') ||
        log.contains('SUCCESS') ||
        log.contains('successful')) {
      return successColor;
    } else if (log.contains('❌') ||
        log.contains('ERROR') ||
        log.contains('FAILURE')) {
      return errorColor;
    } else if (log.contains('⚠️') || log.contains('WARNING')) {
      return warningColor;
    } else if (log.contains('ℹ️') || log.contains('INFO')) {
      return infoColor;
    } else if (log.contains('🔍') || log.contains('START')) {
      return primaryColor;
    } else {
      return Colors.grey;
    }
  }

  Widget _buildVerificationResult() {
    if (_transactionDetails == null) return const SizedBox();

    final isMobile = MediaQuery.of(context).size.width < 600;
    final tx = _transactionDetails!;
    final isSuccess = tx['status'] == 'successful';
    final amount = tx['amount'] ?? 0.0;

    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return FadeTransition(
          opacity: _fadeAnimation,
          child: SlideTransition(position: _slideAnimation, child: child),
        );
      },
      child: Container(
        margin: EdgeInsets.symmetric(
          horizontal: isMobile ? 16 : 24,
          vertical: 8,
        ),
        padding: EdgeInsets.all(isMobile ? 16 : 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(isMobile ? 16 : 20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(
            color:
                isSuccess
                    ? successColor.withValues(alpha: 0.3)
                    : errorColor.withValues(alpha: 0.3),
            width: 2,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color:
                        isSuccess
                            ? successColor.withValues(alpha: 0.1)
                            : errorColor.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isSuccess
                        ? Icons.verified_rounded
                        : Icons.error_outline_rounded,
                    color: isSuccess ? successColor : errorColor,
                    size: 28,
                  ),
                ),
                SizedBox(width: isMobile ? 12 : 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isSuccess
                            ? 'Transaction Verified!'
                            : 'Verification Failed',
                        style: GoogleFonts.inter(
                          fontSize: isMobile ? 16 : 18,
                          fontWeight: FontWeight.w700,
                          color: isSuccess ? successColor : errorColor,
                        ),
                      ),
                      Text(
                        'ID: ${tx['_id']?.toString().substring(0, 8) ?? 'N/A'}',
                        style: GoogleFonts.inter(
                          fontSize: isMobile ? 11 : 12,
                          color: textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: isMobile ? 8 : 12,
                    vertical: isMobile ? 4 : 6,
                  ),
                  decoration: BoxDecoration(
                    color:
                        isSuccess
                            ? successColor.withValues(alpha: 0.1)
                            : errorColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color:
                          isSuccess
                              ? successColor.withValues(alpha: 0.2)
                              : errorColor.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Text(
                    isSuccess ? 'SUCCESS' : 'FAILED',
                    style: GoogleFonts.inter(
                      color: isSuccess ? successColor : errorColor,
                      fontSize: isMobile ? 9 : 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),

            SizedBox(height: isMobile ? 16 : 20),

            // Details Grid
            GridView.count(
              shrinkWrap: true,
              crossAxisCount: isMobile ? 2 : 3,
              childAspectRatio: isMobile ? 2.5 : 3,
              crossAxisSpacing: isMobile ? 8 : 12,
              mainAxisSpacing: isMobile ? 8 : 12,
              children: [
                _buildDetailItem(
                  label: 'Amount',
                  value: _formatCurrency(amount),
                  icon: HugeIcons.strokeRoundedMoney01,
                  isMobile: isMobile,
                ),
                _buildDetailItem(
                  label: 'Reference',
                  value: tx['reference']?.toString() ?? 'N/A',
                  icon: HugeIcons.strokeRoundedTag01,
                  isMobile: isMobile,
                ),
                _buildDetailItem(
                  label: 'User ID',
                  value: tx['userId']?.toString() ?? 'N/A',
                  icon: HugeIcons.strokeRoundedUser,
                  isMobile: isMobile,
                ),
                _buildDetailItem(
                  label: 'Date',
                  value: _formatDate(tx['createdAt']),
                  icon: HugeIcons.strokeRoundedCalendar01,
                  isMobile: isMobile,
                ),
                if (tx['newBalance'] != null)
                  _buildDetailItem(
                    label: 'New Balance',
                    value: _formatCurrency(tx['newBalance'] as double),
                    icon: HugeIcons.strokeRoundedWallet01,
                    isMobile: isMobile,
                  ),
                if (tx['user'] != null)
                  _buildDetailItem(
                    label: 'User',
                    value: tx['user']['fullName'] ?? 'Unknown',
                    icon: HugeIcons.strokeRoundedUserCircle,
                    isMobile: isMobile,
                  ),
              ],
            ),

            SizedBox(height: isMobile ? 12 : 16),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showTransactionDetailsDialog(tx),
                    icon: HugeIcon(
                      icon: HugeIcons.strokeRoundedEye,
                      color: primaryColor,
                      size: isMobile ? 16 : 18,
                    ),
                    label: Text(
                      'Details',
                      style: GoogleFonts.inter(
                        color: primaryColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.symmetric(
                        vertical: isMobile ? 10 : 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      side: BorderSide(
                        color: primaryColor.withValues(alpha: 0.3),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: isMobile ? 8 : 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _clearForm,
                    icon: HugeIcon(
                      icon: HugeIcons.strokeRoundedDesert,
                      color: textSecondary,
                      size: isMobile ? 16 : 18,
                    ),
                    label: Text(
                      'Clear',
                      style: GoogleFonts.inter(
                        color: textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.symmetric(
                        vertical: isMobile ? 10 : 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      side: BorderSide(color: Colors.grey.shade300),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailItem({
    required String label,
    required String value,
    required dynamic icon,
    required bool isMobile,
  }) {
    return Container(
      padding: EdgeInsets.all(isMobile ? 8 : 10),
      decoration: BoxDecoration(
        color: backgroundLight,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          HugeIcon(
            icon: icon,
            color: primaryColor.withValues(alpha: 0.5),
            size: isMobile ? 14 : 16,
          ),
          SizedBox(height: isMobile ? 2 : 4),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: isMobile ? 12 : 14,
              fontWeight: FontWeight.w600,
              color: textPrimary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: isMobile ? 8 : 10,
              color: textSecondary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  void _showTransactionDetailsDialog(Map<String, dynamic> tx) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    showDialog(
      context: context,
      builder:
          (context) => Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: Container(
              padding: EdgeInsets.all(isMobile ? 16 : 20),
              constraints: BoxConstraints(
                maxWidth: isMobile ? double.infinity : 500,
                maxHeight: isMobile ? double.infinity : 600,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: primaryColor.withValues(alpha: 0.08),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.receipt_long_rounded,
                          color: primaryColor,
                          size: 24,
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Transaction Details',
                          style: GoogleFonts.inter(
                            fontSize: isMobile ? 16 : 18,
                            fontWeight: FontWeight.w700,
                            color: textPrimary,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: Icon(
                          Icons.close_rounded,
                          color: Colors.grey.shade400,
                        ),
                      ),
                    ],
                  ),
                  Divider(color: Colors.grey.shade200),

                  // Content
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildDetailRow('Reference', tx['reference']),
                          _buildDetailRow('Transaction ID', tx['_id']),
                          _buildDetailRow(
                            'Amount',
                            _formatCurrency(tx['amount'] ?? 0.0),
                          ),
                          _buildDetailRow('Status', tx['status'] ?? 'N/A'),
                          _buildDetailRow('Type', tx['type'] ?? 'N/A'),
                          _buildDetailRow('User ID', tx['userId'] ?? 'N/A'),
                          _buildDetailRow('Date', _formatDate(tx['createdAt'])),
                          if (tx['newBalance'] != null)
                            _buildDetailRow(
                              'New Balance',
                              _formatCurrency(tx['newBalance'] as double),
                            ),
                          if (tx['description'] != null)
                            _buildDetailRow('Description', tx['description']),
                        ],
                      ),
                    ),
                  ),

                  Divider(color: Colors.grey.shade200),

                  // Actions
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(
                            'Close',
                            style: GoogleFonts.inter(
                              color: textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed:
                              () =>
                                  _copyToClipboard(tx['_id']?.toString() ?? ''),
                          icon: Icon(Icons.copy_rounded, size: 16),
                          label: Text(
                            'Copy ID',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryColor,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
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

  Widget _buildDetailRow(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: GoogleFonts.inter(
                color: textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value?.toString() ?? 'N/A',
              style: GoogleFonts.inter(
                color: textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Center(
      child: Padding(
        padding: EdgeInsets.all(isMobile ? 24 : 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: isMobile ? 80 : 100,
              height: isMobile ? 80 : 100,
              decoration: BoxDecoration(
                color: primaryColor.withValues(alpha: 0.06),
                shape: BoxShape.circle,
              ),
              child: HugeIcon(
                icon: HugeIcons.strokeRoundedSearch02,
                color: primaryColor.withValues(alpha: 0.3),
                size: isMobile ? 40 : 50,
              ),
            ),
            SizedBox(height: isMobile ? 16 : 20),
            Text(
              'No Transaction Found',
              style: GoogleFonts.inter(
                fontSize: isMobile ? 18 : 22,
                fontWeight: FontWeight.w700,
                color: textPrimary,
              ),
            ),
            SizedBox(height: isMobile ? 8 : 12),
            Text(
              'Enter a transaction ID or reference to start verification.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: isMobile ? 13 : 15,
                color: textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Center(
      child: Padding(
        padding: EdgeInsets.all(isMobile ? 20 : 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: isMobile ? 80 : 100,
              height: isMobile ? 80 : 100,
              decoration: BoxDecoration(
                color: errorColor.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.error_outline_rounded,
                color: errorColor,
                size: isMobile ? 40 : 50,
              ),
            ),
            SizedBox(height: isMobile ? 16 : 20),
            Text(
              'Access Denied',
              style: GoogleFonts.inter(
                fontSize: isMobile ? 20 : 24,
                fontWeight: FontWeight.w700,
                color: errorColor,
              ),
            ),
            SizedBox(height: isMobile ? 8 : 12),
            Text(
              _errorMessage,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: isMobile ? 14 : 16,
                color: textSecondary,
              ),
            ),
            SizedBox(height: isMobile ? 20 : 24),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back_rounded, size: 18),
              label: Text(
                'Go Back',
                style: GoogleFonts.inter(fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                padding: EdgeInsets.symmetric(
                  horizontal: isMobile ? 20 : 24,
                  vertical: isMobile ? 12 : 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingOverlay() {
    return Container(
      color: Colors.black.withValues(alpha: 0.3),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 40,
                height: 40,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                ),
              ),
              SizedBox(height: 12),
              Text(
                'Verifying...',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: textPrimary,
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
    final isMobile = MediaQuery.of(context).size.width < 600;

    if (_isCheckingAdmin) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 40,
                height: 40,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                ),
              ),
              SizedBox(height: 16),
              Text(
                'Loading admin panel...',
                style: GoogleFonts.inter(color: textSecondary, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    if (!_isAdmin) {
      return Scaffold(backgroundColor: Colors.white, body: _buildErrorState());
    }

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Colors.grey.shade50,
      drawer: CustomDrawer(
        header: _buildDrawerHeader(),
        items: _drawerItems,
        selectedItem: _drawerItems.firstWhere(
          (item) => item.title == "Verify Payments",
          orElse: () => _drawerItems.first,
        ),
        onItemSelected: _onDrawerItemSelected,
        isAdmin: true,
      ),
      body: SafeArea(
        child: Stack(
          children: [
            // Main Content
            CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(child: _buildAdminHeader()),
                SliverToBoxAdapter(child: _buildStatsSection()),
                SliverToBoxAdapter(child: _buildVerificationCard()),
                if (_currentStep.isNotEmpty)
                  SliverToBoxAdapter(child: _buildCurrentStep()),
                if (_verificationLogs.isNotEmpty)
                  SliverToBoxAdapter(child: _buildVerificationLog()),
                if (_transactionDetails == null && !_isLoading)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _buildEmptyState(),
                  ),
                if (_transactionDetails != null && !_isLoading)
                  SliverToBoxAdapter(child: _buildVerificationResult()),
                SliverToBoxAdapter(child: SizedBox(height: isMobile ? 80 : 40)),
              ],
            ),

            // Loading Overlay
            if (_isLoading) _buildLoadingOverlay(),
          ],
        ),
      ),
    );
  }
}
