// lib/presentation/screens/admin/admin_self_fund_page.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:hugeicons/hugeicons.dart';
import 'dart:developer' as developer;

import '../../../core/services/api_service.dart';
import '../../../core/widgets/custom_drawer.dart';
import '../../../core/widgets/drawer_item.dart';
import '../dashboard/dashboard_screen.dart';

class AdminSelfFundPage extends StatefulWidget {
  const AdminSelfFundPage({super.key});

  @override
  State<AdminSelfFundPage> createState() => _AdminSelfFundPageState();
}

class _AdminSelfFundPageState extends State<AdminSelfFundPage>
    with SingleTickerProviderStateMixin {
  // ==================== BRAND COLORS ====================
  static const Color primaryColor = Color(0xFF15368A);
  static const Color secondaryColor = Color(0xFF079A68);
  static const Color successColor = Color(0xFF079A68);
  static const Color warningColor = Color(0xFFB7791F);
  static const Color errorColor = Color(0xFFE5484D);
  static const Color textPrimary = Color(0xFF10255A);
  static const Color textSecondary = Color(0xFF7B87A1);
  static const Color backgroundLight = Color(0xFFF7F9FC);

  // ==================== CONTROLLERS ====================
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final GlobalKey<RefreshIndicatorState> _refreshIndicatorKey =
      GlobalKey<RefreshIndicatorState>();

  // ==================== STATE ====================
  bool _isLoading = true;
  bool _isProcessing = false;
  bool _isAdmin = false;
  bool _isSuperAdmin = false;
  bool _hasTransactionPin = false;
  bool _useBiometric = false;
  final bool _isInitialLoad = true;
  static const Duration _cacheDuration = Duration(minutes: 5);

  String? _errorMessage;
  String _adminName = '';
  double _currentBalance = 0.0;
  String _selectedPin = '';

  // ==================== TRANSACTIONS ====================
  List<Map<String, dynamic>> _recentTransactions = [];
  bool _isLoadingTransactions = false;

  // ==================== ANIMATION ====================
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  Timer? _searchDebounce;

  // ==================== RESPONSIVE ====================
  bool get isMobile => MediaQuery.of(context).size.width < 600;
  bool get isTablet =>
      MediaQuery.of(context).size.width >= 600 &&
      MediaQuery.of(context).size.width < 1200;
  bool get isDesktop => MediaQuery.of(context).size.width >= 1200;

  // ==================== LIFECYCLE ====================
  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _loadInitialData();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  // ==================== ANIMATION SETUP ====================
  void _setupAnimations() {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 600),
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
  Future<void> _loadInitialData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();

      // Check cached data
      final cachedData = prefs.getString('cached_self_fund');
      if (cachedData != null && _isInitialLoad) {
        try {
          final cached = jsonDecode(cachedData);
          final cacheTime = DateTime.parse(cached['timestamp']);
          if (DateTime.now().difference(cacheTime) < _cacheDuration) {
            setState(() {
              _currentBalance = cached['currentBalance'] ?? 0.0;
              _recentTransactions = cached['transactions'] ?? [];
              _isLoading = false; // ← This sets it false
            });
            developer.log('📦 Loaded self-fund data from cache');
          }
        } catch (e) {
          developer.log('Cache read error: $e');
        }
      }

      final userDataString = prefs.getString('user');

      if (userDataString != null) {
        final userData = jsonDecode(userDataString);
        final bool isAdmin = userData['isAdmin'] == true;
        final String? userId = userData['_id'];
        const String superAdminId = "690088325ca99bed6ab8d4a5";
        final bool isSuperAdmin = userId == superAdminId;

        setState(() {
          _isAdmin = isAdmin || isSuperAdmin;
          _isSuperAdmin = isSuperAdmin;
          _adminName = userData['fullName'] ?? 'Admin';
          _currentBalance = (userData['walletBalance'] ?? 0.0).toDouble();
        });

        if (_isAdmin) {
          await Future.wait([
            _checkTransactionPinStatus(),
            _loadRecentTransactions(),
          ]);
          _animationController.forward();

          // ✅ CRITICAL FIX: Set loading to false after data loads
          setState(() {
            _isLoading = false;
          });
        } else {
          setState(() {
            _isLoading = false;
            _errorMessage = "You don't have permission to access this page.";
          });
        }
      } else {
        setState(() {
          _isAdmin = false;
          _isLoading = false;
          _errorMessage = "User data not found. Please log in again.";
        });
      }
    } catch (e) {
      developer.log("❌ Error loading initial data: $e");
      setState(() {
        _isAdmin = false;
        _isLoading = false;
        _errorMessage = "Error checking permissions: ${e.toString()}";
      });
    }
  }

  Future<void> _checkTransactionPinStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userDataString = prefs.getString('user');
      if (userDataString != null) {
        final userData = jsonDecode(userDataString);
        final userId = userData['_id']?.toString();
        if (userId != null) {
          final pinStatus = await ApiService.checkTransactionPinStatus(
            userId: userId,
          );
          setState(() {
            _hasTransactionPin = pinStatus['hasPin'] ?? false;
          });
        }
      }
    } catch (e) {
      developer.log('❌ Error checking PIN status: $e');
      setState(() => _hasTransactionPin = false);
    }
  }

  Future<void> _loadRecentTransactions() async {
    setState(() => _isLoadingTransactions = true);

    try {
      final allTransactions = await ApiService.getAllAdminTransactions();

      final selfFundTransactions = <Map<String, dynamic>>[];

      for (var tx in allTransactions) {
        if (tx is Map<String, dynamic>) {
          final description =
              (tx['description'] as String?)?.toLowerCase() ?? '';
          final type = (tx['type'] as String?)?.toLowerCase() ?? '';

          final isSelfFund =
              description.contains('self fund') ||
              description.contains('admin funding') ||
              description.contains('admin self-fund') ||
              description.contains('funded by admin') ||
              type.contains('self_fund') ||
              type.contains('admin_fund');

          if (isSelfFund) {
            final amount = (tx['amount'] as num?)?.toDouble() ?? 0.0;
            if (amount > 0) {
              final txCopy = Map<String, dynamic>.from(tx);
              txCopy['user'] = {
                '_id': tx['userId']?.toString() ?? 'admin',
                'fullName': _adminName,
                'email': 'admin@dalabapay.com',
                'isAdmin': true,
              };
              selfFundTransactions.add(txCopy);
            }
          }
        }
      }

      selfFundTransactions.sort((a, b) {
        final dateA = _parseDateTime(a['createdAt']);
        final dateB = _parseDateTime(b['createdAt']);
        return dateB.compareTo(dateA);
      });

      setState(() {
        _recentTransactions =
            selfFundTransactions.take(10).cast<Map<String, dynamic>>().toList();
      });

      // Cache the data
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'cached_self_fund',
        jsonEncode({
          'currentBalance': _currentBalance,
          'transactions': _recentTransactions,
          'timestamp': DateTime.now().toIso8601String(),
        }),
      );
    } catch (e) {
      developer.log('❌ Error loading transactions: $e');
      setState(() {
        _recentTransactions = [];
      });
    } finally {
      // ✅ Ensure this always runs
      setState(() => _isLoadingTransactions = false);
    }
  }

  // ==================== HELPERS ====================
  DateTime _parseDateTime(dynamic dateValue) {
    try {
      if (dateValue == null) return DateTime.now();
      if (dateValue is DateTime) return dateValue;
      if (dateValue is String) return DateTime.parse(dateValue);
      return DateTime.now();
    } catch (e) {
      return DateTime.now();
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) {
      if (diff.inHours == 0) {
        if (diff.inMinutes == 0) return 'Just now';
        return '${diff.inMinutes}m ago';
      }
      return '${diff.inHours}h ago';
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    }
    return DateFormat('dd/MM/yyyy').format(date);
  }

  String _formatCurrency(double amount) {
    return NumberFormat.currency(symbol: '₦', decimalDigits: 2).format(amount);
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle,
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
        backgroundColor: isError ? errorColor : successColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  // ==================== DRAWER ====================
  Widget _buildDrawerHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [primaryColor, primaryColor.withOpacity(0.8)],
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
              color: secondaryColor.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: secondaryColor.withOpacity(0.3)),
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

  // ==================== ADMIN HEADER ====================
  Widget _buildAdminHeader() {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 16 : 24,
        vertical: isMobile ? 16 : 20,
      ),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFF35C08E), Color(0xFF15368A)],
          stops: [0.06, 0.41],
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
        boxShadow: [
          BoxShadow(
            color: secondaryColor.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
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
                  'Admin / Self Fund',
                  style: GoogleFonts.inter(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: isMobile ? 12 : 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (_isSuperAdmin)
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
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.attach_money_rounded,
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
                      'Self Fund',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: isMobile ? 20 : 28,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: isMobile ? 4 : 6),
                    Text(
                      'Fund your admin wallet instantly',
                      style: GoogleFonts.inter(
                        color: Colors.white.withOpacity(0.8),
                        fontSize: isMobile ? 12 : 14,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: _loadInitialData,
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.refresh_rounded,
                    color: Colors.white,
                    size: isMobile ? 22 : 26,
                  ),
                ),
                tooltip: 'Refresh',
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ==================== BALANCE CARD ====================
  Widget _buildBalanceCard() {
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return FadeTransition(
          opacity: _fadeAnimation,
          child: SlideTransition(
            position: _slideAnimation,
            child: Container(
              margin: EdgeInsets.symmetric(
                horizontal: isMobile ? 16 : 24,
                vertical: 16,
              ),
              padding: EdgeInsets.all(isMobile ? 20 : 24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [primaryColor, primaryColor.withOpacity(0.85)],
                ),
                borderRadius: BorderRadius.circular(isMobile ? 16 : 20),
                boxShadow: [
                  BoxShadow(
                    color: primaryColor.withOpacity(0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: HugeIcon(
                          icon: HugeIcons.strokeRoundedWallet01,
                          color: Colors.white,
                          size: isMobile ? 22 : 26,
                        ),
                      ),
                      SizedBox(width: isMobile ? 12 : 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Admin Wallet',
                              style: GoogleFonts.inter(
                                color: Colors.white.withOpacity(0.8),
                                fontSize: isMobile ? 12 : 13,
                              ),
                            ),
                            Text(
                              _adminName,
                              style: GoogleFonts.inter(
                                color: Colors.white,
                                fontSize: isMobile ? 14 : 16,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: isMobile ? 10 : 14,
                          vertical: isMobile ? 4 : 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'ADMIN',
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
                  Text(
                    _formatCurrency(_currentBalance),
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: isMobile ? 32 : 40,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: isMobile ? 4 : 6),
                  Text(
                    'Available Balance',
                    style: GoogleFonts.inter(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: isMobile ? 13 : 14,
                    ),
                  ),
                  if (!_hasTransactionPin) ...[
                    SizedBox(height: isMobile ? 12 : 16),
                    Container(
                      padding: EdgeInsets.all(isMobile ? 10 : 12),
                      decoration: BoxDecoration(
                        color: warningColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: warningColor.withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          HugeIcon(
                            icon: HugeIcons.strokeRoundedAlert02,
                            color: warningColor,
                            size: isMobile ? 16 : 18,
                          ),
                          SizedBox(width: isMobile ? 8 : 10),
                          Expanded(
                            child: Text(
                              'Transaction PIN required. Set up in settings.',
                              style: GoogleFonts.inter(
                                color: warningColor,
                                fontSize: isMobile ? 11 : 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ==================== FUNDING CARD ====================
  Widget _buildFundingCard() {
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return FadeTransition(
          opacity: _fadeAnimation,
          child: SlideTransition(
            position: _slideAnimation,
            child: Container(
              margin: EdgeInsets.symmetric(
                horizontal: isMobile ? 16 : 24,
                vertical: 8,
              ),
              padding: EdgeInsets.all(isMobile ? 16 : 20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(isMobile ? 14 : 16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
                border: Border.all(color: Colors.grey.shade200, width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: secondaryColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: HugeIcon(
                          icon: HugeIcons.strokeRoundedMoneyAdd01,
                          color: secondaryColor,
                          size: isMobile ? 20 : 24,
                        ),
                      ),
                      SizedBox(width: isMobile ? 12 : 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Self-Funding',
                              style: GoogleFonts.inter(
                                fontSize: isMobile ? 16 : 18,
                                fontWeight: FontWeight.bold,
                                color: textPrimary,
                              ),
                            ),
                            Text(
                              'Add funds to your admin wallet instantly',
                              style: GoogleFonts.inter(
                                fontSize: isMobile ? 12 : 13,
                                color: textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: isMobile ? 16 : 20),

                  // Amount Input
                  Text(
                    'Amount to Fund',
                    style: GoogleFonts.inter(
                      fontSize: isMobile ? 13 : 14,
                      fontWeight: FontWeight.w600,
                      color: textPrimary,
                    ),
                  ),
                  SizedBox(height: isMobile ? 6 : 8),
                  TextField(
                    controller: _amountController,
                    keyboardType: TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'^\d+\.?\d{0,2}'),
                      ),
                    ],
                    decoration: InputDecoration(
                      hintText: 'Enter amount (e.g., 5000.00)',
                      hintStyle: GoogleFonts.inter(
                        fontSize: isMobile ? 13 : 14,
                        color: Colors.grey.shade500,
                      ),
                      prefixIcon: Padding(
                        padding: EdgeInsets.all(isMobile ? 12 : 14),
                        child: Text(
                          '₦',
                          style: GoogleFonts.inter(
                            fontSize: isMobile ? 16 : 18,
                            fontWeight: FontWeight.w700,
                            color: textPrimary,
                          ),
                        ),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: primaryColor, width: 2),
                      ),
                      filled: true,
                      fillColor: backgroundLight,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: isMobile ? 12 : 16,
                        vertical: isMobile ? 14 : 16,
                      ),
                    ),
                    style: GoogleFonts.inter(
                      fontSize: isMobile ? 16 : 18,
                      fontWeight: FontWeight.w600,
                      color: textPrimary,
                    ),
                  ),
                  SizedBox(height: isMobile ? 16 : 20),

                  // Quick Amounts
                  Text(
                    'Quick Amounts',
                    style: GoogleFonts.inter(
                      fontSize: isMobile ? 13 : 14,
                      fontWeight: FontWeight.w600,
                      color: textSecondary,
                    ),
                  ),
                  SizedBox(height: isMobile ? 8 : 10),
                  Wrap(
                    spacing: isMobile ? 8 : 10,
                    runSpacing: isMobile ? 8 : 10,
                    children: [
                      _buildQuickAmountButton(1000),
                      _buildQuickAmountButton(5000),
                      _buildQuickAmountButton(10000),
                      _buildQuickAmountButton(20000),
                      _buildQuickAmountButton(50000),
                      _buildQuickAmountButton(100000),
                    ],
                  ),
                  SizedBox(height: isMobile ? 20 : 24),

                  // Fund Button
                  SizedBox(
                    width: double.infinity,
                    height: isMobile ? 48 : 54,
                    child: ElevatedButton(
                      onPressed:
                          _isProcessing || !_hasTransactionPin
                              ? null
                              : _handleSelfFund,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: secondaryColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child:
                          _isProcessing
                              ? SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              )
                              : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  HugeIcon(
                                    icon: HugeIcons.strokeRoundedMoneyAdd01,
                                    color: Colors.white,
                                    size: isMobile ? 18 : 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    _hasTransactionPin
                                        ? 'Fund Wallet'
                                        : 'Set Up PIN First',
                                    style: GoogleFonts.inter(
                                      fontWeight: FontWeight.bold,
                                      fontSize: isMobile ? 15 : 16,
                                    ),
                                  ),
                                ],
                              ),
                    ),
                  ),

                  if (_errorMessage != null) ...[
                    SizedBox(height: isMobile ? 12 : 16),
                    Container(
                      padding: EdgeInsets.all(isMobile ? 10 : 12),
                      decoration: BoxDecoration(
                        color: errorColor.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: errorColor.withOpacity(0.2)),
                      ),
                      child: Row(
                        children: [
                          HugeIcon(
                            icon: HugeIcons.strokeRoundedAlert02,
                            color: errorColor,
                            size: isMobile ? 16 : 18,
                          ),
                          SizedBox(width: isMobile ? 8 : 10),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: GoogleFonts.inter(
                                fontSize: isMobile ? 12 : 13,
                                color: errorColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildQuickAmountButton(double amount) {
    return OutlinedButton(
      onPressed: () => _amountController.text = amount.toStringAsFixed(0),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: primaryColor.withOpacity(0.3)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(isMobile ? 10 : 12),
        ),
        padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 16 : 24,
          vertical: isMobile ? 12 : 16,
        ),
        minimumSize: Size(isMobile ? 60 : 80, isMobile ? 40 : 48),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(
        '₦${amount.toStringAsFixed(0)}',
        style: GoogleFonts.inter(
          color: primaryColor,
          fontWeight: FontWeight.w700,
          fontSize: isMobile ? 14 : 16,
        ),
      ),
    );
  }

  // ==================== RECENT TRANSACTIONS ====================
  Widget _buildRecentTransactions() {
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return FadeTransition(
          opacity: _fadeAnimation,
          child: SlideTransition(
            position: _slideAnimation,
            child: Container(
              margin: EdgeInsets.symmetric(
                horizontal: isMobile ? 16 : 24,
                vertical: 8,
              ),
              padding: EdgeInsets.all(isMobile ? 16 : 20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(isMobile ? 14 : 16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
                border: Border.all(color: Colors.grey.shade200, width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: primaryColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: HugeIcon(
                          icon: HugeIcons.strokeRoundedTransactionHistory,
                          color: primaryColor,
                          size: isMobile ? 20 : 24,
                        ),
                      ),
                      SizedBox(width: isMobile ? 12 : 14),
                      Expanded(
                        child: Text(
                          'Recent Self-Funding',
                          style: GoogleFonts.inter(
                            fontSize: isMobile ? 15 : 17,
                            fontWeight: FontWeight.bold,
                            color: textPrimary,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _loadRecentTransactions,
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Row(
                          children: [
                            HugeIcon(
                              icon: HugeIcons.strokeRoundedRefresh,
                              color: primaryColor,
                              size: isMobile ? 14 : 16,
                            ),
                            SizedBox(width: isMobile ? 2 : 4),
                            Text(
                              'Refresh',
                              style: GoogleFonts.inter(
                                color: primaryColor,
                                fontWeight: FontWeight.w600,
                                fontSize: isMobile ? 12 : 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: isMobile ? 12 : 16),
                  if (_isLoadingTransactions)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  else if (_recentTransactions.isEmpty)
                    _buildEmptyTransactions()
                  else
                    Column(
                      children:
                          _recentTransactions
                              .map((tx) => _buildTransactionItem(tx))
                              .toList(),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTransactionItem(Map<String, dynamic> transaction) {
    final status = (transaction['status'] as String?)?.toLowerCase() ?? '';
    final isSuccess =
        status.contains('success') || status.contains('completed');
    final amount = (transaction['amount'] as num?)?.toDouble() ?? 0.0;
    final date = _parseDateTime(transaction['createdAt']);
    final description = transaction['description'] as String? ?? 'Self-Funding';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.all(isMobile ? 10 : 12),
      decoration: BoxDecoration(
        color: backgroundLight,
        borderRadius: BorderRadius.circular(isMobile ? 10 : 12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: (isSuccess ? successColor : errorColor).withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: HugeIcon(
              icon:
                  isSuccess
                      ? HugeIcons.strokeRoundedCheckmarkCircle01
                      : HugeIcons.strokeRoundedCancelCircle,
              color: isSuccess ? successColor : errorColor,
              size: isMobile ? 16 : 18,
            ),
          ),
          SizedBox(width: isMobile ? 10 : 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _formatCurrency(amount),
                  style: GoogleFonts.inter(
                    fontSize: isMobile ? 14 : 15,
                    fontWeight: FontWeight.bold,
                    color: textPrimary,
                  ),
                ),
                Text(
                  description,
                  style: GoogleFonts.inter(
                    fontSize: isMobile ? 11 : 12,
                    color: textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  _formatDate(date),
                  style: GoogleFonts.inter(
                    fontSize: isMobile ? 10 : 11,
                    color: textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 8 : 10,
              vertical: isMobile ? 3 : 4,
            ),
            decoration: BoxDecoration(
              color: (isSuccess ? successColor : errorColor).withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              isSuccess ? 'Success' : 'Failed',
              style: GoogleFonts.inter(
                fontSize: isMobile ? 9 : 10,
                fontWeight: FontWeight.w600,
                color: isSuccess ? successColor : errorColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyTransactions() {
    return Container(
      padding: EdgeInsets.all(isMobile ? 20 : 24),
      decoration: BoxDecoration(
        color: backgroundLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          HugeIcon(
            icon: HugeIcons.strokeRoundedReceiptText,
            color: textSecondary.withOpacity(0.3),
            size: isMobile ? 40 : 48,
          ),
          SizedBox(height: isMobile ? 12 : 16),
          Text(
            'No Self-Funding History',
            style: GoogleFonts.inter(
              fontSize: isMobile ? 15 : 16,
              fontWeight: FontWeight.w600,
              color: textPrimary,
            ),
          ),
          SizedBox(height: isMobile ? 4 : 6),
          Text(
            'Your self-funding transactions will appear here',
            style: GoogleFonts.inter(
              fontSize: isMobile ? 12 : 13,
              color: textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  // ==================== STATE WIDGETS ====================
  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: isMobile ? 40 : 50,
            height: isMobile ? 40 : 50,
            child: CircularProgressIndicator(
              strokeWidth: isMobile ? 3 : 4,
              valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Loading...',
            style: GoogleFonts.inter(
              fontSize: isMobile ? 14 : 16,
              fontWeight: FontWeight.w500,
              color: textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
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
                color: errorColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: HugeIcon(
                icon: HugeIcons.strokeRoundedAlert02,
                color: errorColor,
                size: isMobile ? 40 : 50,
              ),
            ),
            SizedBox(height: isMobile ? 16 : 24),
            Text(
              'Access Denied',
              style: GoogleFonts.inter(
                fontSize: isMobile ? 22 : 28,
                fontWeight: FontWeight.w700,
                color: errorColor,
              ),
            ),
            SizedBox(height: isMobile ? 8 : 12),
            Text(
              _errorMessage!,
              style: GoogleFonts.inter(
                fontSize: isMobile ? 14 : 16,
                color: textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ==================== BUSINESS LOGIC ====================
  Future<void> _handleSelfFund() async {
    if (!_hasTransactionPin) {
      _showSnackBar(
        'Transaction PIN not set. Please set up a PIN in settings.',
        isError: true,
      );
      return;
    }

    final amountStr = _amountController.text.trim();
    if (amountStr.isEmpty) {
      _showSnackBar('Please enter an amount', isError: true);
      return;
    }

    final amount = double.tryParse(amountStr);
    if (amount == null || amount <= 0) {
      _showSnackBar('Please enter a valid amount', isError: true);
      return;
    }

    if (amount > 1000000) {
      _showSnackBar('Amount cannot exceed ₦1,000,000', isError: true);
      return;
    }

    await _showAuthenticationDialog(amount);
  }

  Future<void> _showAuthenticationDialog(double amount) async {
    setState(() => _selectedPin = '');

    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => _buildPinBottomSheet(amount),
    );

    if (result != null) {
      final String? pin = result['pin'];
      final bool useBiometric = result['useBiometric'] ?? false;
      await _processSelfFund(amount, pin, useBiometric);
    }
  }

  Widget _buildPinBottomSheet(double amount) {
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Padding(
        padding: EdgeInsets.all(isMobile ? 20 : 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),

            // Header
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: primaryColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: HugeIcon(
                icon: HugeIcons.strokeRoundedSecurityLock,
                color: primaryColor,
                size: isMobile ? 28 : 32,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Enter Transaction PIN',
              style: GoogleFonts.inter(
                fontSize: isMobile ? 18 : 20,
                fontWeight: FontWeight.bold,
                color: textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Please enter your 6-digit PIN to confirm',
              style: GoogleFonts.inter(
                fontSize: isMobile ? 12 : 13,
                color: textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _formatCurrency(amount),
              style: GoogleFonts.inter(
                fontSize: isMobile ? 20 : 24,
                fontWeight: FontWeight.bold,
                color: successColor,
              ),
            ),
            const SizedBox(height: 20),

            // PIN Dots
            _buildPinDots(),

            const SizedBox(height: 16),

            // Biometric Option
            if (_hasTransactionPin) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  HugeIcon(
                    icon: HugeIcons.strokeRoundedFingerPrint,
                    color: primaryColor,
                    size: isMobile ? 20 : 24,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Use Biometric Authentication',
                    style: GoogleFonts.inter(
                      fontSize: isMobile ? 13 : 14,
                      color: primaryColor,
                    ),
                  ),
                  Switch(
                    value: _useBiometric,
                    onChanged: (value) => setState(() => _useBiometric = value),
                    activeThumbColor: primaryColor,
                    inactiveThumbColor: Colors.grey[400],
                    activeTrackColor: primaryColor.withOpacity(0.3),
                    inactiveTrackColor: Colors.grey[300],
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],

            // Numeric Keypad
            _buildNumericKeypad(),

            const SizedBox(height: 12),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      setState(() => _selectedPin = '');
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
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.symmetric(
                        vertical: isMobile ? 12 : 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      side: BorderSide(color: Colors.grey.shade300),
                    ),
                    child: Text(
                      'Cancel',
                      style: GoogleFonts.inter(
                        fontSize: isMobile ? 13 : 14,
                        color: textSecondary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed:
                        _selectedPin.length == 6
                            ? () {
                              Navigator.pop(context, {
                                'pin': _selectedPin,
                                'useBiometric': _useBiometric,
                              });
                              setState(() => _selectedPin = '');
                            }
                            : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: secondaryColor,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(
                        vertical: isMobile ? 12 : 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      disabledBackgroundColor: Colors.grey.shade300,
                    ),
                    child: Text(
                      'Confirm',
                      style: GoogleFonts.inter(
                        fontSize: isMobile ? 13 : 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: MediaQuery.of(context).viewInsets.bottom),
          ],
        ),
      ),
    );
  }

  Widget _buildPinDots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(6, (index) {
        final isFilled = index < _selectedPin.length;
        return Container(
          width: isMobile ? 40 : 48,
          height: isMobile ? 48 : 56,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: backgroundLight,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isFilled ? secondaryColor : Colors.grey.shade300,
              width: isFilled ? 2 : 1,
            ),
          ),
          child: Center(
            child:
                isFilled
                    ? Container(
                      width: isMobile ? 16 : 20,
                      height: isMobile ? 16 : 20,
                      decoration: BoxDecoration(
                        color: primaryColor,
                        shape: BoxShape.circle,
                      ),
                    )
                    : null,
          ),
        );
      }),
    );
  }

  Widget _buildNumericKeypad() {
    final buttons = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['clear', '0', 'backspace'],
    ];

    return Column(
      children:
          buttons.map((row) {
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children:
                  row.map((label) {
                    return Expanded(
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            if (label == 'clear') {
                              _selectedPin = '';
                            } else if (label == 'backspace') {
                              if (_selectedPin.isNotEmpty) {
                                _selectedPin = _selectedPin.substring(
                                  0,
                                  _selectedPin.length - 1,
                                );
                              }
                            } else if (_selectedPin.length < 6) {
                              _selectedPin += label;
                            }
                          });
                        },
                        child: Container(
                          margin: const EdgeInsets.all(4),
                          padding: EdgeInsets.symmetric(
                            vertical: isMobile ? 12 : 16,
                          ),
                          decoration: BoxDecoration(
                            color:
                                label == 'clear' || label == 'backspace'
                                    ? Colors.grey.shade100
                                    : Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Center(
                            child:
                                label == 'clear'
                                    ? HugeIcon(
                                      icon: HugeIcons.strokeRoundedCancelCircle,
                                      color: errorColor,
                                      size: isMobile ? 20 : 24,
                                    )
                                    : label == 'backspace'
                                    ? HugeIcon(
                                      icon: HugeIcons.strokeRoundedLinkBackward,
                                      color: textSecondary,
                                      size: isMobile ? 20 : 24,
                                    )
                                    : Text(
                                      label,
                                      style: GoogleFonts.inter(
                                        fontSize: isMobile ? 20 : 24,
                                        fontWeight: FontWeight.w600,
                                        color: textPrimary,
                                      ),
                                    ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
            );
          }).toList(),
    );
  }

  Future<void> _processSelfFund(
    double amount,
    String? pin,
    bool useBiometric,
  ) async {
    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    try {
      final result = await ApiService.adminSelfFund(
        amount: amount,
        transactionPin: pin,
        useBiometric: useBiometric,
      );

      if (result['success'] == true) {
        _showSnackBar('✅ Successfully funded ${_formatCurrency(amount)}');

        setState(() {
          _currentBalance =
              (result['newBalance'] ?? _currentBalance).toDouble();
        });

        _amountController.clear();
        await _loadRecentTransactions();

        _showSuccessDialog(amount, result);
      } else {
        throw Exception(result['message'] ?? 'Funding failed');
      }
    } catch (e) {
      final errorMsg = e.toString();
      if (errorMsg.contains('Authentication required')) {
        _showSnackBar(
          'Please authenticate to complete the transaction.',
          isError: true,
        );
      } else if (errorMsg.contains('Invalid transaction PIN')) {
        _showSnackBar('Invalid PIN. Please try again.', isError: true);
      } else {
        _showSnackBar('Funding failed: $errorMsg', isError: true);
      }
      setState(() => _errorMessage = errorMsg);
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  void _showSuccessDialog(double amount, Map<String, dynamic> result) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: Container(
              padding: EdgeInsets.all(isMobile ? 20 : 24),
              constraints: BoxConstraints(
                maxWidth: isMobile ? double.infinity : 400,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: successColor.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: HugeIcon(
                      icon: HugeIcons.strokeRoundedCheckmarkCircle01,
                      color: successColor,
                      size: isMobile ? 40 : 48,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Funding Successful! ✅',
                    style: GoogleFonts.inter(
                      fontSize: isMobile ? 18 : 20,
                      fontWeight: FontWeight.bold,
                      color: textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _formatCurrency(amount),
                    style: GoogleFonts.inter(
                      fontSize: isMobile ? 22 : 28,
                      fontWeight: FontWeight.bold,
                      color: successColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'added to your wallet',
                    style: GoogleFonts.inter(
                      fontSize: isMobile ? 13 : 14,
                      color: textSecondary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: EdgeInsets.all(isMobile ? 12 : 14),
                    decoration: BoxDecoration(
                      color: backgroundLight,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      children: [
                        _buildDetailRow(
                          'New Balance',
                          _formatCurrency(
                            (result['newBalance'] ?? _currentBalance)
                                .toDouble(),
                          ),
                        ),
                        const Divider(),
                        _buildDetailRow(
                          'Transaction ID',
                          result['transactionId']?.toString() ?? 'N/A',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: isMobile ? 44 : 50,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Text(
                        'Done',
                        style: GoogleFonts.inter(
                          fontSize: isMobile ? 14 : 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              color: textSecondary,
              fontSize: isMobile ? 12 : 13,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w600,
              fontSize: isMobile ? 12 : 13,
              color: textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  // ==================== MAIN BUILD ====================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Colors.grey.shade50,
      drawer: CustomDrawer(
        header: _buildDrawerHeader(),
        items: _drawerItems,
        selectedItem: _drawerItems.firstWhere(
          (item) => item.title == "Self Fund",
          orElse: () => _drawerItems.first,
        ),
        onItemSelected: _onDrawerItemSelected,
        isAdmin: _isAdmin,
      ),
      body: SafeArea(
        child: RefreshIndicator(
          key: _refreshIndicatorKey,
          onRefresh: _loadInitialData,
          color: primaryColor,
          backgroundColor: Colors.white,
          child:
              _isLoading
                  ? _buildLoadingState()
                  : _errorMessage != null && !_isAdmin
                  ? _buildErrorState()
                  : CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverToBoxAdapter(child: _buildAdminHeader()),
                      SliverToBoxAdapter(child: _buildBalanceCard()),
                      SliverToBoxAdapter(child: _buildFundingCard()),
                      SliverToBoxAdapter(child: _buildRecentTransactions()),
                      SliverToBoxAdapter(
                        child: SizedBox(height: isMobile ? 80 : 24),
                      ),
                    ],
                  ),
        ),
      ),
    );
  }
}
