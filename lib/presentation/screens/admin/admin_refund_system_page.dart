// lib/presentation/screens/admin/admin_refund_system_page.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:shimmer/shimmer.dart';

import '../../../core/services/api_service.dart';
import '../../../core/widgets/custom_drawer.dart';
import '../../../core/widgets/drawer_item.dart';
import '../dashboard/dashboard_screen.dart';

class AdminRefundSystemPage extends StatefulWidget {
  const AdminRefundSystemPage({super.key});

  @override
  State<AdminRefundSystemPage> createState() => _AdminRefundSystemPageState();
}

class _AdminRefundSystemPageState extends State<AdminRefundSystemPage>
    with SingleTickerProviderStateMixin {
  // ==================== BRAND COLORS ====================
  static const Color primaryColor = Color(0xFF243889);
  static const Color secondaryColor = Color(0xFF219C7E);
  static const Color successColor = Color(0xFF219C7E);
  static const Color warningColor = Color(0xFFF59E0B);
  static const Color errorColor = Color(0xFFEF4444);
  static const Color textPrimary = Color(0xFF1C2D5A);
  static const Color textSecondary = Color(0xFF64748B);
  static const Color backgroundLight = Color(0xFFF8FAFC);

  // ==================== STATE ====================
  List<dynamic> _transactions = [];
  List<dynamic> _filteredTransactions = [];
  List<dynamic> _disputes = [];
  List<dynamic> _filteredDisputes = [];
  List<dynamic> _refunds = [];
  List<dynamic> _filteredRefunds = [];

  bool _isLoading = true;
  bool _isAdmin = false;
  bool _isInitialLoad = true;
  static const Duration _cacheDuration = Duration(minutes: 5);

  String? _errorMessage;
  String _selectedTab = 'pending_failed';
  String _selectedFilter = 'all';
  String _searchQuery = '';

  // Stats
  int _pendingCount = 0;
  int _failedCount = 0;
  double _totalPendingAmount = 0;
  int _pendingDisputes = 0;
  int _pendingRefunds = 0;

  // Controllers
  final TextEditingController _searchController = TextEditingController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final GlobalKey<RefreshIndicatorState> _refreshIndicatorKey =
      GlobalKey<RefreshIndicatorState>();

  // Animation
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _loadInitialData();

    _searchController.addListener(() {
      _searchDebounce?.cancel();
      _searchDebounce = Timer(const Duration(milliseconds: 300), () {
        if (mounted) {
          _searchQuery = _searchController.text;
          _applyFilters();
        }
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _animationController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

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
      final cachedData = prefs.getString('cached_refund_data');
      if (cachedData != null && _isInitialLoad) {
        try {
          final cached = jsonDecode(cachedData);
          final cacheTime = DateTime.parse(cached['timestamp']);
          if (DateTime.now().difference(cacheTime) < _cacheDuration) {
            setState(() {
              _transactions = cached['transactions'] ?? [];
              _disputes = cached['disputes'] ?? [];
              _refunds = cached['refunds'] ?? [];
              _pendingCount = cached['pendingCount'] ?? 0;
              _failedCount = cached['failedCount'] ?? 0;
              _totalPendingAmount = cached['totalPendingAmount'] ?? 0;
              _pendingDisputes = cached['pendingDisputes'] ?? 0;
              _pendingRefunds = cached['pendingRefunds'] ?? 0;
              _applyFilters();
              _isLoading = false;
            });
            debugPrint('📦 Loaded refund data from cache');
          }
        } catch (e) {
          debugPrint('Cache read error: $e');
        }
      }

      final userDataString = prefs.getString('user');

      if (userDataString != null) {
        final userData = jsonDecode(userDataString);
        final bool isAdmin = userData['isAdmin'] == true;
        final String? userId = userData['_id'];
        const String specificAdminUserId = "690088325ca99bed6ab8d4a5";
        final bool isAdminById = userId == specificAdminUserId;

        setState(() {
          _isAdmin = isAdmin || isAdminById;
        });

        if (_isAdmin) {
          await _fetchAllData();
          _animationController.forward();
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
      debugPrint("Error loading initial data: $e");
      setState(() {
        _isAdmin = false;
        _isLoading = false;
        _errorMessage = "Error checking permissions: ${e.toString()}";
      });
    }
  }

  Future<void> _fetchAllData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _isInitialLoad = false;
    });

    try {
      await Future.wait([
        _fetchPendingFailedTransactions(),
        _fetchDisputes(),
        _fetchRefunds(),
      ]);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'cached_refund_data',
        jsonEncode({
          'transactions': _transactions,
          'disputes': _disputes,
          'refunds': _refunds,
          'pendingCount': _pendingCount,
          'failedCount': _failedCount,
          'totalPendingAmount': _totalPendingAmount,
          'pendingDisputes': _pendingDisputes,
          'pendingRefunds': _pendingRefunds,
          'timestamp': DateTime.now().toIso8601String(),
        }),
      );
    } catch (e) {
      debugPrint("❌ Error fetching data: $e");
      if (e.toString().contains('Admin access required')) {
        setState(() {
          _errorMessage = "You don't have permission to access admin features.";
          _isAdmin = false;
        });
      } else {
        setState(() {
          _errorMessage = "Failed to load data: ${e.toString()}";
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _fetchPendingFailedTransactions() async {
    try {
      final response = await ApiService.getPendingFailedTransactions();
      if (response['success'] == true) {
        setState(() {
          _transactions = response['transactions'] ?? [];
          _pendingCount = response['stats']['pending'] ?? 0;
          _failedCount = response['stats']['failed'] ?? 0;
          _totalPendingAmount =
              (response['stats']['totalAmount'] ?? 0).toDouble();
        });
      }
    } catch (e) {
      debugPrint('Error loading pending/failed txs: $e');
    }
  }

  Future<void> _fetchDisputes() async {
    try {
      final response = await ApiService.getDisputes(status: 'all');
      if (response['success'] == true) {
        setState(() {
          _disputes = response['disputes'] ?? [];
          _pendingDisputes = response['stats']['pending'] ?? 0;
        });
      }
    } catch (e) {
      debugPrint('Error loading disputes: $e');
    }
  }

  Future<void> _fetchRefunds() async {
    try {
      final response = await ApiService.getRefunds(status: 'all');
      if (response['success'] == true) {
        setState(() {
          _refunds = response['refunds'] ?? [];
          _pendingRefunds = response['stats']['pending'] ?? 0;
        });
      }
    } catch (e) {
      debugPrint('Error loading refunds: $e');
    }
  }

  void _applyFilters() {
    // Filter transactions
    List<dynamic> filteredTxs = List.from(_transactions);
    if (_selectedFilter != 'all') {
      if (_selectedFilter == 'pending') {
        filteredTxs =
            filteredTxs.where((tx) {
              final status = tx['status']?.toString().toLowerCase() ?? '';
              return status == 'pending';
            }).toList();
      } else if (_selectedFilter == 'failed') {
        filteredTxs =
            filteredTxs.where((tx) {
              final status = tx['status']?.toString().toLowerCase() ?? '';
              return status == 'failed';
            }).toList();
      }
    }
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filteredTxs =
          filteredTxs.where((tx) {
            final user = tx['user'] as Map<String, dynamic>?;
            return (tx['reference']?.toString().toLowerCase().contains(query) ??
                    false) ||
                (user?['fullName']?.toString().toLowerCase().contains(query) ??
                    false) ||
                (user?['email']?.toString().toLowerCase().contains(query) ??
                    false);
          }).toList();
    }
    _filteredTransactions = filteredTxs;

    // Filter disputes
    List<dynamic> filteredDisp = List.from(_disputes);
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filteredDisp =
          filteredDisp.where((d) {
            return (d['reason']?.toString().toLowerCase().contains(query) ??
                    false) ||
                (d['userId']?['fullName']?.toString().toLowerCase().contains(
                      query,
                    ) ??
                    false);
          }).toList();
    }
    _filteredDisputes = filteredDisp;

    // Filter refunds
    List<dynamic> filteredRef = List.from(_refunds);
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filteredRef =
          filteredRef.where((r) {
            return (r['reason']?.toString().toLowerCase().contains(query) ??
                    false) ||
                (r['userId']?['fullName']?.toString().toLowerCase().contains(
                      query,
                    ) ??
                    false);
          }).toList();
    }
    _filteredRefunds = filteredRef;

    setState(() {});
  }

  // ==================== HELPERS ====================

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      if (difference.inHours == 0) {
        if (difference.inMinutes == 0) return 'Just now';
        return '${difference.inMinutes}m ago';
      }
      return '${difference.inHours}h ago';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return DateFormat('dd/MM/yyyy').format(date);
    }
  }

  Color _getStatusColor(String status) {
    final lowerStatus = status.toLowerCase();
    if (lowerStatus == 'successful' || lowerStatus == 'completed') {
      return successColor;
    }
    if (lowerStatus == 'pending' || lowerStatus == 'processing') {
      return warningColor;
    }
    if (lowerStatus == 'failed') return errorColor;
    if (lowerStatus == 'refunded') return const Color(0xFF8B5CF6);
    if (lowerStatus == 'resolved') return successColor;
    if (lowerStatus == 'rejected') return errorColor;
    if (lowerStatus == 'under_review') return Colors.orange;
    return Colors.grey;
  }

  String _getStatusText(String status) {
    final lowerStatus = status.toLowerCase();
    if (lowerStatus == 'successful' || lowerStatus == 'completed') {
      return 'Successful';
    }
    if (lowerStatus == 'pending' || lowerStatus == 'processing') {
      return 'Pending';
    }
    if (lowerStatus == 'failed') return 'Failed';
    if (lowerStatus == 'refunded') return 'Refunded';
    if (lowerStatus == 'resolved') return 'Resolved ✓';
    if (lowerStatus == 'rejected') return 'Rejected ✗';
    if (lowerStatus == 'under_review') return 'Under Review';
    return status.toUpperCase();
  }

  dynamic _getStatusIcon(String status) {
    final lowerStatus = status.toLowerCase();
    if (lowerStatus == 'successful' || lowerStatus == 'completed') {
      return HugeIcons.strokeRoundedCheckmarkCircle01;
    }
    if (lowerStatus == 'pending' || lowerStatus == 'processing') {
      return HugeIcons.strokeRoundedClock02;
    }
    if (lowerStatus == 'failed') return HugeIcons.strokeRoundedAlert01;
    if (lowerStatus == 'refunded') return HugeIcons.strokeRoundedMoney02;
    if (lowerStatus == 'resolved') {
      return HugeIcons.strokeRoundedCheckmarkCircle01;
    }
    if (lowerStatus == 'rejected') return HugeIcons.strokeRoundedCancelCircle;
    if (lowerStatus == 'under_review') return HugeIcons.strokeRoundedSearch01;
    return HugeIcons.strokeRoundedCircle;
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

  // ==================== ADMIN HEADER ====================

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
          colors: [const Color(0xFF92D394), const Color(0xFF1E377E)],
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
                  'Admin / Refund System',
                  style: GoogleFonts.inter(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: isMobile ? 12 : 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
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
                  Icons.currency_exchange_rounded,
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
                      'Refund & Dispute',
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: isMobile ? 20 : 28,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: isMobile ? 4 : 6),
                    Text(
                      '${_transactions.length} pending/failed • $_pendingDisputes disputes • $_pendingRefunds refunds',
                      style: GoogleFonts.inter(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: isMobile ? 12 : 14,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: _fetchAllData,
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
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

          SizedBox(height: isMobile ? 16 : 20),

          Container(
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 14 : 18,
              vertical: isMobile ? 4 : 6,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                HugeIcon(
                  icon: HugeIcons.strokeRoundedSearch01,
                  color: primaryColor.withValues(alpha: 0.5),
                  size: isMobile ? 18 : 22,
                ),
                SizedBox(width: isMobile ? 10 : 14),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText:
                          isMobile
                              ? 'Search...'
                              : 'Search transactions, disputes, or refunds...',
                      hintStyle: GoogleFonts.inter(
                        color: primaryColor.withValues(alpha: 0.4),
                        fontSize: isMobile ? 13 : 14,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        vertical: isMobile ? 10 : 14,
                      ),
                    ),
                    style: GoogleFonts.inter(
                      color: primaryColor,
                      fontSize: isMobile ? 14 : 15,
                    ),
                  ),
                ),
                if (_searchQuery.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      _searchController.clear();
                      _searchQuery = '';
                      _applyFilters();
                    },
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: primaryColor.withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.close_rounded,
                        color: primaryColor.withValues(alpha: 0.5),
                        size: isMobile ? 16 : 18,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==================== STATS CARD ====================

  Widget _buildStatsCard() {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: isMobile ? 12 : 16,
        vertical: isMobile ? 8 : 12,
      ),
      padding: EdgeInsets.all(isMobile ? 12 : 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(isMobile ? 12 : 16),
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
        children: [
          // Stats row (wrapped in Flexible for responsiveness)
          LayoutBuilder(
            builder: (context, constraints) {
              final isSmall = constraints.maxWidth < 400;
              return isSmall
                  ? Wrap(
                    spacing: 4,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      SizedBox(
                        width: constraints.maxWidth / 2 - 12,
                        child: _buildStatItem(
                          value: _pendingCount.toString(),
                          label: 'Pending Txs',
                          icon: HugeIcons.strokeRoundedClock02,
                          color: warningColor,
                          isMobile: true,
                        ),
                      ),
                      SizedBox(
                        width: constraints.maxWidth / 2 - 12,
                        child: _buildStatItem(
                          value: _failedCount.toString(),
                          label: 'Failed Txs',
                          icon: HugeIcons.strokeRoundedAlert01,
                          color: errorColor,
                          isMobile: true,
                        ),
                      ),
                      SizedBox(
                        width: constraints.maxWidth / 2 - 12,
                        child: _buildStatItem(
                          value: _pendingDisputes.toString(),
                          label: 'Disputes',
                          icon: HugeIcons.strokeRoundedAuction,
                          color: Colors.orange,
                          isMobile: true,
                        ),
                      ),
                      SizedBox(
                        width: constraints.maxWidth / 2 - 12,
                        child: _buildStatItem(
                          value: _pendingRefunds.toString(),
                          label: 'Refunds',
                          icon: HugeIcons.strokeRoundedMoney02,
                          color: primaryColor,
                          isMobile: true,
                        ),
                      ),
                    ],
                  )
                  : Row(
                    children: [
                      Expanded(
                        child: _buildStatItem(
                          value: _pendingCount.toString(),
                          label: 'Pending Txs',
                          icon: HugeIcons.strokeRoundedClock02,
                          color: warningColor,
                          isMobile: false,
                        ),
                      ),
                      Expanded(
                        child: _buildStatItem(
                          value: _failedCount.toString(),
                          label: 'Failed Txs',
                          icon: HugeIcons.strokeRoundedAlert01,
                          color: errorColor,
                          isMobile: false,
                        ),
                      ),
                      Expanded(
                        child: _buildStatItem(
                          value: _pendingDisputes.toString(),
                          label: 'Disputes',
                          icon: HugeIcons.strokeRoundedAuction,
                          color: Colors.orange,
                          isMobile: false,
                        ),
                      ),
                      Expanded(
                        child: _buildStatItem(
                          value: _pendingRefunds.toString(),
                          label: 'Refunds',
                          icon: HugeIcons.strokeRoundedMoney02,
                          color: primaryColor,
                          isMobile: false,
                        ),
                      ),
                    ],
                  );
            },
          ),
          SizedBox(height: isMobile ? 8 : 12),
          _buildFilterChips(isMobile),
        ],
      ),
    );
  }

  Widget _buildStatItem({
    required String value,
    required String label,
    required dynamic icon,
    required Color color,
    required bool isMobile,
  }) {
    // Format large numbers
    String displayValue = value;
    if (value.length > 6) {
      // Format as thousands
      final numValue = int.tryParse(value.replaceAll(',', ''));
      if (numValue != null) {
        if (numValue >= 1000000) {
          displayValue = '${(numValue / 1000000).toStringAsFixed(1)}M';
        } else if (numValue >= 1000) {
          displayValue = '${(numValue / 1000).toStringAsFixed(1)}K';
        }
      }
    }

    return Column(
      children: [
        Container(
          padding: EdgeInsets.all(isMobile ? 6 : 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: HugeIcon(icon: icon, color: color, size: isMobile ? 18 : 22),
        ),
        SizedBox(height: isMobile ? 4 : 6),
        Text(
          displayValue,
          style: GoogleFonts.inter(
            fontSize: isMobile ? 14 : 16,
            fontWeight: FontWeight.w700,
            color: textPrimary,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        SizedBox(height: isMobile ? 2 : 4),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: isMobile ? 9 : 11,
            color: textSecondary,
            fontWeight: FontWeight.w500,
          ),
          maxLines: 2,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _buildFilterChips(bool isMobile) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        _buildFilterChip('All', 'all', isMobile),
        _buildFilterChip('Pending', 'pending', isMobile),
        _buildFilterChip('Failed', 'failed', isMobile),
      ],
    );
  }

  Widget _buildFilterChip(String label, String value, bool isMobile) {
    final isSelected = _selectedFilter == value;
    return FilterChip(
      label: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: isMobile ? 11 : 12,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
          color: isSelected ? primaryColor : textSecondary,
        ),
      ),
      selected: isSelected,
      onSelected: (_) {
        setState(() {
          _selectedFilter = value;
          _applyFilters();
        });
      },
      backgroundColor: Colors.white,
      selectedColor: primaryColor.withValues(alpha: 0.08),
      showCheckmark: false,
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 8 : 12,
        vertical: isMobile ? 4 : 6,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: isSelected ? primaryColor : Colors.grey.shade300,
          width: isSelected ? 2 : 1,
        ),
      ),
    );
  }

  // ==================== TABS ====================

  // ==================== TABS ====================

  Widget _buildTabs() {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Container(
      margin: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 16, vertical: 8),
      child: Row(
        children: [
          _buildTabButton(
            label: 'Pending/Failed',
            tab: 'pending_failed',
            icon: HugeIcons.strokeRoundedCursorLoading01,
            count: _transactions.length,
            isMobile: isMobile,
          ),
          SizedBox(width: isMobile ? 6 : 8),
          _buildTabButton(
            label: 'Disputes',
            tab: 'disputes',
            icon: HugeIcons.strokeRoundedAuction,
            count: _pendingDisputes,
            isMobile: isMobile,
          ),
          SizedBox(width: isMobile ? 6 : 8),
          _buildTabButton(
            label: 'Refunds',
            tab: 'refunds',
            icon: HugeIcons.strokeRoundedMoney02,
            count: _pendingRefunds,
            isMobile: isMobile,
          ),
        ],
      ),
    );
  }

  Widget _buildTabButton({
    required String label,
    required String tab,
    required dynamic icon,
    required int count,
    required bool isMobile,
  }) {
    final isSelected = _selectedTab == tab;

    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedTab = tab),
        child: Container(
          padding: EdgeInsets.symmetric(
            vertical: isMobile ? 8 : 10,
            horizontal: 4,
          ),
          decoration: BoxDecoration(
            color: isSelected ? primaryColor : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? primaryColor : Colors.grey.shade300,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Main content - always centered
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  HugeIcon(
                    icon: icon,
                    color: isSelected ? Colors.white : textSecondary,
                    size: isMobile ? 16 : 18,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      style: GoogleFonts.inter(
                        color: isSelected ? Colors.white : textSecondary,
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.w400,
                        fontSize: isMobile ? 10 : 12,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                  const SizedBox(width: 4),
                  // Count badge - always visible next to text
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: count > 99 ? 4 : 6,
                      vertical: 1,
                    ),
                    constraints: const BoxConstraints(minWidth: 16),
                    decoration: BoxDecoration(
                      color:
                          isSelected
                              ? Colors.white.withValues(alpha: 0.2)
                              : Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color:
                            isSelected
                                ? Colors.white.withValues(alpha: 0.3)
                                : Colors.red.withValues(alpha: 0.3),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      count > 999 ? '999+' : count.toString(),
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.red.shade700,
                        fontSize: isMobile ? 8 : 10,
                        fontWeight: FontWeight.bold,
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

  // ==================== TRANSACTION LIST ====================

  Widget _buildTransactionList() {
    final isMobile = MediaQuery.of(context).size.width < 600;

    if (_isLoading) {
      return SliverPadding(
        padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 24),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) => _buildShimmerCard(isMobile),
            childCount: 6,
          ),
        ),
      );
    }

    if (_errorMessage != null) {
      return SliverFillRemaining(child: _buildErrorState());
    }

    if (_filteredTransactions.isEmpty) {
      return SliverFillRemaining(child: _buildEmptyState());
    }

    return SliverPadding(
      padding: EdgeInsets.only(
        left: isMobile ? 16 : 24,
        right: isMobile ? 16 : 24,
        bottom: 24,
      ),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) =>
              _buildTransactionCard(_filteredTransactions[index]),
          childCount: _filteredTransactions.length,
        ),
      ),
    );
  }

  Widget _buildShimmerCard(bool isMobile) {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: Container(
        margin: EdgeInsets.only(bottom: 12),
        height: isMobile ? 120 : 140,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(isMobile ? 14 : 16),
        ),
      ),
    );
  }

  Widget _buildTransactionCard(Map<String, dynamic> transaction) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    final status = transaction['status']?.toString().toLowerCase() ?? '';
    final amount = (transaction['amount'] as num?)?.toDouble() ?? 0;
    final user = transaction['user'] as Map<String, dynamic>?;
    final reference = transaction['reference']?.toString() ?? 'N/A';
    final createdAt =
        transaction['createdAt'] != null
            ? DateTime.tryParse(transaction['createdAt'].toString())
            : null;
    final hasDispute =
        transaction['disputes'] != null &&
        (transaction['disputes'] as List).isNotEmpty;
    final hasPendingRefund = transaction['hasPendingRefund'] == true;
    final isResolved = transaction['isResolved'] == true;
    final statusColor = _getStatusColor(status);

    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return FadeTransition(
          opacity: _fadeAnimation,
          child: SlideTransition(position: _slideAnimation, child: child),
        );
      },
      child: Container(
        margin: EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: isResolved ? Colors.grey.shade50 : Colors.white,
          borderRadius: BorderRadius.circular(isMobile ? 14 : 16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
          border: Border.all(
            color: isResolved ? Colors.grey.shade200 : Colors.grey.shade200,
            width: 1,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(isMobile ? 14 : 16),
            onTap: () => _showTransactionDetails(transaction),
            child: Padding(
              padding: EdgeInsets.all(isMobile ? 14 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: EdgeInsets.all(isMobile ? 8 : 10),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: HugeIcon(
                          icon: _getStatusIcon(status),
                          color: statusColor,
                          size: isMobile ? 18 : 22,
                        ),
                      ),
                      SizedBox(width: isMobile ? 12 : 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    transaction['type']?.toString() ??
                                        'Transaction',
                                    style: GoogleFonts.inter(
                                      fontSize: isMobile ? 14 : 15,
                                      fontWeight: FontWeight.w600,
                                      color: textPrimary,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (isResolved) ...[
                                  SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: successColor.withValues(
                                        alpha: 0.1,
                                      ),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      'RESOLVED',
                                      style: GoogleFonts.inter(
                                        fontSize: isMobile ? 8 : 10,
                                        fontWeight: FontWeight.bold,
                                        color: successColor,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            Text(
                              'Ref: ${reference.length > 16 ? '${reference.substring(0, 16)}...' : reference}',
                              style: GoogleFonts.inter(
                                fontSize: isMobile ? 10 : 11,
                                color: textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '₦${amount.toStringAsFixed(2)}',
                            style: GoogleFonts.inter(
                              fontSize: isMobile ? 14 : 16,
                              fontWeight: FontWeight.w700,
                              color: isResolved ? successColor : errorColor,
                            ),
                          ),
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: isMobile ? 6 : 8,
                              vertical: isMobile ? 1 : 2,
                            ),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              _getStatusText(status),
                              style: GoogleFonts.inter(
                                fontSize: isMobile ? 8 : 10,
                                fontWeight: FontWeight.w600,
                                color: statusColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  SizedBox(height: isMobile ? 8 : 10),
                  if (user != null)
                    Row(
                      children: [
                        HugeIcon(
                          icon: HugeIcons.strokeRoundedUser,
                          color: textSecondary,
                          size: isMobile ? 12 : 14,
                        ),
                        SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            user['fullName']?.toString() ?? 'Unknown User',
                            style: GoogleFonts.inter(
                              fontSize: isMobile ? 11 : 12,
                              color: textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (createdAt != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            _formatDate(createdAt),
                            style: GoogleFonts.inter(
                              fontSize: isMobile ? 10 : 11,
                              color: textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  SizedBox(height: isMobile ? 6 : 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      if (hasDispute)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'DISPUTE',
                            style: GoogleFonts.inter(
                              fontSize: isMobile ? 8 : 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.orange,
                            ),
                          ),
                        ),
                      if (hasPendingRefund)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: primaryColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'REFUND PENDING',
                            style: GoogleFonts.inter(
                              fontSize: isMobile ? 8 : 10,
                              fontWeight: FontWeight.bold,
                              color: primaryColor,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ==================== DISPUTES SECTION ====================

  Widget _buildDisputesSection() {
    final isMobile = MediaQuery.of(context).size.width < 600;

    if (_isLoading) {
      return SliverPadding(
        padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 24),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) => _buildShimmerCard(isMobile),
            childCount: 6,
          ),
        ),
      );
    }

    if (_filteredDisputes.isEmpty) {
      return SliverFillRemaining(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              HugeIcon(
                icon: HugeIcons.strokeRoundedAuction,
                color: textSecondary.withValues(alpha: 0.3),
                size: 64,
              ),
              const SizedBox(height: 16),
              Text(
                'No Disputes Found',
                style: GoogleFonts.poppins(
                  fontSize: isMobile ? 18 : 20,
                  fontWeight: FontWeight.w600,
                  color: textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'All disputes have been resolved',
                style: GoogleFonts.inter(
                  fontSize: isMobile ? 13 : 14,
                  color: textSecondary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SliverPadding(
      padding: EdgeInsets.only(
        left: isMobile ? 16 : 24,
        right: isMobile ? 16 : 24,
        bottom: 24,
      ),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) => _buildDisputeCard(_filteredDisputes[index]),
          childCount: _filteredDisputes.length,
        ),
      ),
    );
  }

  Widget _buildDisputeCard(Map<String, dynamic> dispute) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    final status = dispute['status']?.toString() ?? 'pending';
    final amount = (dispute['amount'] as num?)?.toDouble() ?? 0;
    final user = dispute['userId'] as Map<String, dynamic>?;
    final reason = dispute['reason']?.toString() ?? 'No reason provided';
    final evidence = dispute['evidence'] as List<dynamic>?;
    final hasEvidence = evidence != null && evidence.isNotEmpty;
    final statusColor = _getStatusColor(status);

    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return FadeTransition(
          opacity: _fadeAnimation,
          child: SlideTransition(position: _slideAnimation, child: child),
        );
      },
      child: Container(
        margin: EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(isMobile ? 14 : 16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
          border: Border.all(color: Colors.grey.shade200, width: 1),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(isMobile ? 14 : 16),
            onTap: () => _showResolveDisputeDialog(dispute),
            child: Padding(
              padding: EdgeInsets.all(isMobile ? 14 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: EdgeInsets.all(isMobile ? 8 : 10),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: HugeIcon(
                          icon: _getStatusIcon(status),
                          color: statusColor,
                          size: isMobile ? 18 : 22,
                        ),
                      ),
                      SizedBox(width: isMobile ? 12 : 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              dispute['type']?.toString() ?? 'Dispute',
                              style: GoogleFonts.inter(
                                fontSize: isMobile ? 14 : 15,
                                fontWeight: FontWeight.w600,
                                color: textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              reason.length > 40
                                  ? '${reason.substring(0, 40)}...'
                                  : reason,
                              style: GoogleFonts.inter(
                                fontSize: isMobile ? 10 : 11,
                                color: textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '₦${amount.toStringAsFixed(2)}',
                            style: GoogleFonts.inter(
                              fontSize: isMobile ? 14 : 16,
                              fontWeight: FontWeight.w700,
                              color: textPrimary,
                            ),
                          ),
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: isMobile ? 6 : 8,
                              vertical: isMobile ? 1 : 2,
                            ),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              _getStatusText(status),
                              style: GoogleFonts.inter(
                                fontSize: isMobile ? 8 : 10,
                                fontWeight: FontWeight.w600,
                                color: statusColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  SizedBox(height: isMobile ? 8 : 10),
                  if (user != null)
                    Row(
                      children: [
                        HugeIcon(
                          icon: HugeIcons.strokeRoundedUser,
                          color: textSecondary,
                          size: isMobile ? 12 : 14,
                        ),
                        SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            user['fullName']?.toString() ?? 'Unknown User',
                            style: GoogleFonts.inter(
                              fontSize: isMobile ? 11 : 12,
                              color: textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  if (hasEvidence) ...[
                    SizedBox(height: isMobile ? 6 : 8),
                    Row(
                      children: [
                        HugeIcon(
                          icon: HugeIcons.strokeRoundedAttachment01,
                          color: Colors.blue,
                          size: isMobile ? 12 : 14,
                        ),
                        SizedBox(width: 4),
                        Text(
                          '${evidence.length} attachment${evidence.length > 1 ? 's' : ''}',
                          style: GoogleFonts.inter(
                            fontSize: isMobile ? 10 : 11,
                            color: Colors.blue,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'HAS EVIDENCE',
                            style: GoogleFonts.inter(
                              fontSize: isMobile ? 7 : 8,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ==================== REFUNDS SECTION ====================

  Widget _buildRefundsSection() {
    final isMobile = MediaQuery.of(context).size.width < 600;

    if (_isLoading) {
      return SliverPadding(
        padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 24),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) => _buildShimmerCard(isMobile),
            childCount: 6,
          ),
        ),
      );
    }

    if (_filteredRefunds.isEmpty) {
      return SliverFillRemaining(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              HugeIcon(
                icon: HugeIcons.strokeRoundedMoney02,
                color: textSecondary.withValues(alpha: 0.3),
                size: 64,
              ),
              const SizedBox(height: 16),
              Text(
                'No Refunds Found',
                style: GoogleFonts.poppins(
                  fontSize: isMobile ? 18 : 20,
                  fontWeight: FontWeight.w600,
                  color: textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'All refunds have been processed',
                style: GoogleFonts.inter(
                  fontSize: isMobile ? 13 : 14,
                  color: textSecondary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SliverPadding(
      padding: EdgeInsets.only(
        left: isMobile ? 16 : 24,
        right: isMobile ? 16 : 24,
        bottom: 24,
      ),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) => _buildRefundCard(_filteredRefunds[index]),
          childCount: _filteredRefunds.length,
        ),
      ),
    );
  }

  Widget _buildRefundCard(Map<String, dynamic> refund) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    final status = refund['status']?.toString() ?? 'pending';
    final amount = (refund['amount'] as num?)?.toDouble() ?? 0;
    final user = refund['userId'] as Map<String, dynamic>?;
    final reason = refund['reason']?.toString() ?? 'No reason provided';
    final refundTransaction =
        refund['refundTransaction'] as Map<String, dynamic>?;
    final previousBalance =
        (refundTransaction?['balanceBefore'] as num?)?.toDouble() ?? 0;
    final newBalance =
        (refundTransaction?['balanceAfter'] as num?)?.toDouble() ?? 0;
    final statusColor = _getStatusColor(status);

    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return FadeTransition(
          opacity: _fadeAnimation,
          child: SlideTransition(position: _slideAnimation, child: child),
        );
      },
      child: Container(
        margin: EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(isMobile ? 14 : 16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
          border: Border.all(color: Colors.grey.shade200, width: 1),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(isMobile ? 14 : 16),
            onTap: () => _showRefundDetails(refund),
            child: Padding(
              padding: EdgeInsets.all(isMobile ? 14 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: EdgeInsets.all(isMobile ? 8 : 10),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: HugeIcon(
                          icon: HugeIcons.strokeRoundedMoney02,
                          color: statusColor,
                          size: isMobile ? 18 : 22,
                        ),
                      ),
                      SizedBox(width: isMobile ? 12 : 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Refund Request',
                              style: GoogleFonts.inter(
                                fontSize: isMobile ? 14 : 15,
                                fontWeight: FontWeight.w600,
                                color: textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              reason.length > 40
                                  ? '${reason.substring(0, 40)}...'
                                  : reason,
                              style: GoogleFonts.inter(
                                fontSize: isMobile ? 10 : 11,
                                color: textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '₦${amount.toStringAsFixed(2)}',
                            style: GoogleFonts.inter(
                              fontSize: isMobile ? 14 : 16,
                              fontWeight: FontWeight.w700,
                              color: primaryColor,
                            ),
                          ),
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: isMobile ? 6 : 8,
                              vertical: isMobile ? 1 : 2,
                            ),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              _getStatusText(status),
                              style: GoogleFonts.inter(
                                fontSize: isMobile ? 8 : 10,
                                fontWeight: FontWeight.w600,
                                color: statusColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  SizedBox(height: isMobile ? 8 : 10),
                  if (user != null)
                    Row(
                      children: [
                        HugeIcon(
                          icon: HugeIcons.strokeRoundedUser,
                          color: textSecondary,
                          size: isMobile ? 12 : 14,
                        ),
                        SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            user['fullName']?.toString() ?? 'Unknown User',
                            style: GoogleFonts.inter(
                              fontSize: isMobile ? 11 : 12,
                              color: textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  SizedBox(height: isMobile ? 8 : 10),
                  Container(
                    padding: EdgeInsets.all(isMobile ? 8 : 10),
                    decoration: BoxDecoration(
                      color: backgroundLight,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Previous Balance',
                              style: GoogleFonts.inter(
                                fontSize: isMobile ? 9 : 10,
                                color: textSecondary,
                              ),
                            ),
                            Text(
                              '₦${previousBalance.toStringAsFixed(2)}',
                              style: GoogleFonts.inter(
                                fontSize: isMobile ? 12 : 13,
                                fontWeight: FontWeight.w600,
                                color: textPrimary,
                              ),
                            ),
                          ],
                        ),
                        Column(
                          children: [
                            Text(
                              'Refund Amount',
                              style: GoogleFonts.inter(
                                fontSize: isMobile ? 9 : 10,
                                color: successColor,
                              ),
                            ),
                            Text(
                              '+₦${amount.toStringAsFixed(2)}',
                              style: GoogleFonts.inter(
                                fontSize: isMobile ? 12 : 13,
                                fontWeight: FontWeight.bold,
                                color: successColor,
                              ),
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              'New Balance',
                              style: GoogleFonts.inter(
                                fontSize: isMobile ? 9 : 10,
                                color: textSecondary,
                              ),
                            ),
                            Text(
                              '₦${newBalance.toStringAsFixed(2)}',
                              style: GoogleFonts.inter(
                                fontSize: isMobile ? 12 : 13,
                                fontWeight: FontWeight.bold,
                                color: successColor,
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
          ),
        ),
      ),
    );
  }

  // ==================== CONTENT BUILDER ====================

  // ==================== CONTENT BUILDER ====================

  Widget _buildContent() {
    final isMobile = MediaQuery.of(context).size.width < 600;

    switch (_selectedTab) {
      case 'pending_failed':
        return CustomScrollView(
          slivers: [
            // ✅ ADD THIS: Admin Header with gradient
            SliverToBoxAdapter(child: _buildAdminHeader()),
            SliverToBoxAdapter(
              child: Column(children: [_buildStatsCard(), _buildTabs()]),
            ),
            _buildTransactionList(),
          ],
        );
      case 'disputes':
        return CustomScrollView(
          slivers: [
            // ✅ ADD THIS: Admin Header with gradient
            SliverToBoxAdapter(child: _buildAdminHeader()),
            SliverToBoxAdapter(
              child: Column(children: [_buildStatsCard(), _buildTabs()]),
            ),
            _buildDisputesSection(),
          ],
        );
      case 'refunds':
        return CustomScrollView(
          slivers: [
            // ✅ ADD THIS: Admin Header with gradient
            SliverToBoxAdapter(child: _buildAdminHeader()),
            SliverToBoxAdapter(
              child: Column(children: [_buildStatsCard(), _buildTabs()]),
            ),
            _buildRefundsSection(),
          ],
        );
      default:
        return const SizedBox();
    }
  }

  // ==================== DIALOGS ====================

  void _showTransactionDetails(Map<String, dynamic> transaction) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    final user = transaction['user'] as Map<String, dynamic>?;
    final amount = (transaction['amount'] as num?)?.toDouble() ?? 0;
    final isResolved = transaction['isResolved'] == true;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder:
          (ctx) => Dialog(
            insetPadding: EdgeInsets.all(isMobile ? 12 : 24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Container(
              width: isMobile ? double.infinity : 500,
              constraints: BoxConstraints(
                maxWidth: isMobile ? double.infinity : 500,
                maxHeight:
                    isMobile ? MediaQuery.of(context).size.height * 0.85 : 600,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Container(
                    padding: EdgeInsets.all(isMobile ? 16 : 20),
                    decoration: BoxDecoration(
                      color: primaryColor,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(16),
                        topRight: Radius.circular(16),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: HugeIcon(
                            icon: HugeIcons.strokeRoundedReceiptText,
                            color: primaryColor,
                            size: isMobile ? 20 : 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Transaction Details',
                                style: GoogleFonts.inter(
                                  color: Colors.white,
                                  fontSize: isMobile ? 16 : 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                transaction['reference']?.toString() ?? 'N/A',
                                style: GoogleFonts.inter(
                                  color: Colors.white.withValues(alpha: 0.8),
                                  fontSize: isMobile ? 11 : 12,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        if (isResolved)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: successColor,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              'RESOLVED',
                              style: GoogleFonts.inter(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  // Content
                  Expanded(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.all(isMobile ? 16 : 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Customer Info
                          Container(
                            padding: EdgeInsets.all(isMobile ? 12 : 16),
                            decoration: BoxDecoration(
                              color: backgroundLight,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    HugeIcon(
                                      icon: HugeIcons.strokeRoundedUser,
                                      color: primaryColor,
                                      size: isMobile ? 16 : 18,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Customer Information',
                                      style: GoogleFonts.inter(
                                        fontSize: isMobile ? 13 : 14,
                                        fontWeight: FontWeight.w600,
                                        color: textPrimary,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                _buildDetailRow(
                                  'Name',
                                  user?['fullName'] ?? 'N/A',
                                ),
                                _buildDetailRow(
                                  'Email',
                                  user?['email'] ?? 'N/A',
                                ),
                                _buildDetailRow(
                                  'Phone',
                                  user?['phone'] ?? 'N/A',
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          // Transaction Info
                          Container(
                            padding: EdgeInsets.all(isMobile ? 12 : 16),
                            decoration: BoxDecoration(
                              color: backgroundLight,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    HugeIcon(
                                      icon:
                                          HugeIcons
                                              .strokeRoundedInformationCircle,
                                      color: primaryColor,
                                      size: isMobile ? 16 : 18,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Transaction Information',
                                      style: GoogleFonts.inter(
                                        fontSize: isMobile ? 13 : 14,
                                        fontWeight: FontWeight.w600,
                                        color: textPrimary,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                _buildDetailRow(
                                  'Type',
                                  transaction['type'] ?? 'N/A',
                                ),
                                _buildDetailRow(
                                  'Amount',
                                  '₦${amount.toStringAsFixed(2)}',
                                ),
                                _buildDetailRow(
                                  'Status',
                                  transaction['status'] ?? 'N/A',
                                ),
                                _buildDetailRow(
                                  'Reference',
                                  transaction['reference'] ?? 'N/A',
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Actions
                  Container(
                    padding: EdgeInsets.all(isMobile ? 12 : 16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(16),
                        bottomRight: Radius.circular(16),
                      ),
                      border: Border(
                        top: BorderSide(color: Colors.grey.shade200),
                      ),
                    ),
                    child: Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: Text(
                            'Close',
                            style: GoogleFonts.inter(
                              color: textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (!isResolved) ...[
                          SizedBox(
                            width: isMobile ? double.infinity : 120,
                            child: ElevatedButton.icon(
                              onPressed: () {
                                Navigator.pop(ctx);
                                _showProcessRefundDialog(transaction);
                              },
                              icon: HugeIcon(
                                icon: HugeIcons.strokeRoundedMoney02,
                                color: Colors.white,
                                size: 16,
                              ),
                              label: Text(
                                'Refund',
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: successColor,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: isMobile ? double.infinity : 120,
                            child: ElevatedButton.icon(
                              onPressed: () {
                                Navigator.pop(ctx);
                                _showCreateDisputeDialog(transaction);
                              },
                              icon: HugeIcon(
                                icon: HugeIcons.strokeRoundedAuction,
                                color: Colors.white,
                                size: 16,
                              ),
                              label: Text(
                                'Dispute',
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: isMobile ? 80 : 100,
            child: Text(
              '$label:',
              style: GoogleFonts.inter(
                fontSize: isMobile ? 12 : 13,
                fontWeight: FontWeight.w600,
                color: textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.inter(
                fontSize: isMobile ? 12 : 13,
                color: textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== DIALOGS (Dispute, Refund) ====================

  void _showCreateDisputeDialog(Map<String, dynamic> transaction) {
    final TextEditingController reasonController = TextEditingController();
    final TextEditingController descriptionController = TextEditingController();
    String selectedType = 'refund_request';
    final isMobile = MediaQuery.of(context).size.width < 600;

    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: [
                HugeIcon(
                  icon: HugeIcons.strokeRoundedAuction,
                  color: Colors.orange,
                  size: 28,
                ),
                const SizedBox(width: 8),
                Text(
                  'Create Dispute',
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: textPrimary,
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: isMobile ? double.infinity : 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: selectedType,
                    decoration: InputDecoration(
                      labelText: 'Dispute Type',
                      labelStyle: GoogleFonts.inter(color: textSecondary),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'refund_request',
                        child: Text('Refund Request'),
                      ),
                      DropdownMenuItem(
                        value: 'failed_transaction',
                        child: Text('Failed Transaction'),
                      ),
                      DropdownMenuItem(
                        value: 'pending_transaction',
                        child: Text('Pending Transaction'),
                      ),
                      DropdownMenuItem(
                        value: 'incorrect_amount',
                        child: Text('Incorrect Amount'),
                      ),
                      DropdownMenuItem(
                        value: 'service_not_delivered',
                        child: Text('Service Not Delivered'),
                      ),
                      DropdownMenuItem(value: 'other', child: Text('Other')),
                    ],
                    onChanged: (value) {
                      if (value != null) selectedType = value;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: reasonController,
                    decoration: InputDecoration(
                      labelText: 'Reason',
                      hintText: 'Explain why this dispute is being created',
                      hintStyle: GoogleFonts.inter(
                        fontSize: 12,
                        color: textSecondary,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      contentPadding: const EdgeInsets.all(12),
                    ),
                    maxLines: 2,
                    style: GoogleFonts.inter(fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descriptionController,
                    decoration: InputDecoration(
                      labelText: 'Description',
                      hintText: 'Additional details (optional)',
                      hintStyle: GoogleFonts.inter(
                        fontSize: 12,
                        color: textSecondary,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      contentPadding: const EdgeInsets.all(12),
                    ),
                    maxLines: 3,
                    style: GoogleFonts.inter(fontSize: 13),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(
                  'Cancel',
                  style: GoogleFonts.inter(
                    color: textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (reasonController.text.isEmpty) {
                    _showSnackBar('Please enter a reason', true);
                    return;
                  }
                  Navigator.pop(ctx);
                  try {
                    final result = await ApiService.createDispute(
                      transactionId: transaction['_id'].toString(),
                      type: selectedType,
                      reason: reasonController.text,
                      description:
                          descriptionController.text.isNotEmpty
                              ? descriptionController.text
                              : null,
                      amount: (transaction['amount'] as num?)?.toDouble(),
                    );
                    if (result['success'] == true) {
                      _showSnackBar('✅ Dispute created successfully!', false);
                      await _fetchAllData();
                    } else {
                      _showSnackBar(
                        result['message'] ?? 'Failed to create dispute',
                        true,
                      );
                    }
                  } catch (e) {
                    _showSnackBar('Error: $e', true);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(
                  'Create Dispute',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
    );
  }

  void _showResolveDisputeDialog(Map<String, dynamic> dispute) {
    final TextEditingController resolutionController = TextEditingController();
    bool approved = true;
    final isMobile = MediaQuery.of(context).size.width < 600;

    final evidence = dispute['evidence'] as List<dynamic>?;
    final hasEvidence = evidence != null && evidence.isNotEmpty;

    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: [
                HugeIcon(
                  icon: HugeIcons.strokeRoundedAuction,
                  color: Colors.orange,
                  size: 28,
                ),
                const SizedBox(width: 8),
                Text(
                  'Resolve Dispute',
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: textPrimary,
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: isMobile ? double.infinity : 450,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildDetailRow('Type', dispute['type'] ?? 'N/A'),
                    _buildDetailRow('Reason', dispute['reason'] ?? 'N/A'),
                    _buildDetailRow(
                      'Amount',
                      '₦${(dispute['amount'] as num?)?.toStringAsFixed(2) ?? '0.00'}',
                    ),
                    if (hasEvidence) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue.shade200),
                        ),
                        child: Row(
                          children: [
                            HugeIcon(
                              icon: HugeIcons.strokeRoundedAttachment01,
                              color: Colors.blue,
                              size: 16,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                '${evidence.length} attachment(s) available',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: Colors.blue,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 8),
                    Text(
                      'Resolution:',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: resolutionController,
                      decoration: InputDecoration(
                        hintText: 'Enter resolution details',
                        hintStyle: GoogleFonts.inter(
                          fontSize: 12,
                          color: textSecondary,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        contentPadding: const EdgeInsets.all(12),
                      ),
                      maxLines: 3,
                      style: GoogleFonts.inter(fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Text(
                          'Approve Dispute:',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: textPrimary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Switch(
                          value: approved,
                          onChanged: (value) => approved = value,
                          activeThumbColor: primaryColor,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(
                  'Cancel',
                  style: GoogleFonts.inter(
                    color: textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (resolutionController.text.isEmpty) {
                    _showSnackBar('Please enter resolution details', true);
                    return;
                  }
                  Navigator.pop(ctx);
                  try {
                    final result = await ApiService.resolveDispute(
                      disputeId: dispute['_id'].toString(),
                      resolution: resolutionController.text,
                      approved: approved,
                      adminNote:
                          approved
                              ? 'Dispute approved and resolved'
                              : 'Dispute rejected',
                    );
                    if (result['success'] == true) {
                      _showSnackBar('✅ Dispute resolved successfully!', false);
                      await _fetchAllData();
                    } else {
                      _showSnackBar(
                        result['message'] ?? 'Failed to resolve dispute',
                        true,
                      );
                    }
                  } catch (e) {
                    _showSnackBar('Error: $e', true);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(
                  'Resolve',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
    );
  }

  void _showProcessRefundDialog(Map<String, dynamic> transaction) {
    final TextEditingController reasonController = TextEditingController();
    final TextEditingController amountController = TextEditingController(
      text: (transaction['amount'] as num?)?.toStringAsFixed(2) ?? '0.00',
    );
    final TextEditingController adminNoteController = TextEditingController();
    final isMobile = MediaQuery.of(context).size.width < 600;

    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: [
                HugeIcon(
                  icon: HugeIcons.strokeRoundedMoney02,
                  color: successColor,
                  size: 28,
                ),
                const SizedBox(width: 8),
                Text(
                  'Process Refund',
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: textPrimary,
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: isMobile ? double.infinity : 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: amountController,
                    decoration: InputDecoration(
                      labelText: 'Refund Amount',
                      prefixText: '₦',
                      hintStyle: GoogleFonts.inter(
                        fontSize: 12,
                        color: textSecondary,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      contentPadding: const EdgeInsets.all(12),
                    ),
                    keyboardType: TextInputType.number,
                    style: GoogleFonts.inter(fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: reasonController,
                    decoration: InputDecoration(
                      labelText: 'Reason',
                      hintText: 'Why is this refund being processed?',
                      hintStyle: GoogleFonts.inter(
                        fontSize: 12,
                        color: textSecondary,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      contentPadding: const EdgeInsets.all(12),
                    ),
                    maxLines: 2,
                    style: GoogleFonts.inter(fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: adminNoteController,
                    decoration: InputDecoration(
                      labelText: 'Admin Note',
                      hintText: 'Additional notes (optional)',
                      hintStyle: GoogleFonts.inter(
                        fontSize: 12,
                        color: textSecondary,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      contentPadding: const EdgeInsets.all(12),
                    ),
                    maxLines: 2,
                    style: GoogleFonts.inter(fontSize: 13),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(
                  'Cancel',
                  style: GoogleFonts.inter(
                    color: textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (reasonController.text.isEmpty) {
                    _showSnackBar('Please enter a reason', true);
                    return;
                  }
                  final amount = double.tryParse(amountController.text);
                  if (amount == null || amount <= 0) {
                    _showSnackBar('Please enter a valid amount', true);
                    return;
                  }
                  Navigator.pop(ctx);
                  try {
                    final result = await ApiService.processRefund(
                      transactionId: transaction['_id'].toString(),
                      reason: reasonController.text,
                      refundAmount: amount,
                      adminNote:
                          adminNoteController.text.isNotEmpty
                              ? adminNoteController.text
                              : null,
                    );
                    if (result['success'] == true) {
                      _showSnackBar('✅ Refund processed successfully!', false);
                      await _fetchAllData();
                    } else {
                      _showSnackBar(
                        result['message'] ?? 'Failed to process refund',
                        true,
                      );
                    }
                  } catch (e) {
                    _showSnackBar('Error: $e', true);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: successColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(
                  'Process Refund',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
    );
  }

  void _showRefundDetails(Map<String, dynamic> refund) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    final status = refund['status']?.toString() ?? 'pending';

    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: [
                HugeIcon(
                  icon: HugeIcons.strokeRoundedReceiptText,
                  color: primaryColor,
                  size: 28,
                ),
                const SizedBox(width: 8),
                Text(
                  'Refund Details',
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: textPrimary,
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: isMobile ? double.infinity : 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDetailRow(
                    'Amount',
                    '₦${(refund['amount'] as num?)?.toStringAsFixed(2) ?? '0.00'}',
                  ),
                  _buildDetailRow('Reason', refund['reason'] ?? 'N/A'),
                  _buildDetailRow('Status', refund['status'] ?? 'N/A'),
                  _buildDetailRow(
                    'Reference',
                    refund['refundReference'] ?? 'N/A',
                  ),
                  if (refund['refundTransaction'] != null) ...[
                    const Divider(),
                    _buildDetailRow(
                      'Previous Balance',
                      '₦${(refund['refundTransaction']?['balanceBefore'] as num?)?.toStringAsFixed(2) ?? '0.00'}',
                    ),
                    _buildDetailRow(
                      'New Balance',
                      '₦${(refund['refundTransaction']?['balanceAfter'] as num?)?.toStringAsFixed(2) ?? '0.00'}',
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(
                  'Close',
                  style: GoogleFonts.inter(
                    color: textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (status == 'pending')
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _showProcessRefundDialog(
                      refund['originalTransactionId'] ?? {},
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: successColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(
                    'Process Refund',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                  ),
                ),
            ],
          ),
    );
  }

  // ==================== STATE WIDGETS ====================

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
                color: errorColor.withValues(alpha: 0.1),
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
              'Error Loading Data',
              style: GoogleFonts.poppins(
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
            SizedBox(height: isMobile ? 24 : 32),
            SizedBox(
              width: isMobile ? 180 : 200,
              child: ElevatedButton(
                onPressed: _fetchAllData,
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  padding: EdgeInsets.symmetric(vertical: isMobile ? 12 : 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.refresh_rounded, size: isMobile ? 18 : 20),
                    SizedBox(width: isMobile ? 6 : 8),
                    Text(
                      'Try Again',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w600,
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
    );
  }

  Widget _buildEmptyState() {
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
                color: successColor.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: HugeIcon(
                icon: HugeIcons.strokeRoundedCheckmarkCircle01,
                color: successColor,
                size: isMobile ? 40 : 50,
              ),
            ),
            SizedBox(height: isMobile ? 16 : 24),
            Text(
              'No Items Found',
              style: GoogleFonts.poppins(
                fontSize: isMobile ? 20 : 24,
                fontWeight: FontWeight.w700,
                color: textPrimary,
              ),
            ),
            SizedBox(height: isMobile ? 8 : 12),
            Text(
              'Try adjusting your filters or search',
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

  // ==================== MAIN BUILD ====================

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Colors.grey.shade50,
      drawer: CustomDrawer(
        header: _buildDrawerHeader(),
        items: _drawerItems,
        selectedItem: _drawerItems.firstWhere(
          (item) => item.title == "Refund System",
          orElse: () => _drawerItems.first,
        ),
        onItemSelected: _onDrawerItemSelected,
        isAdmin: true,
      ),
      body: SafeArea(
        child: RefreshIndicator(
          key: _refreshIndicatorKey,
          onRefresh: _fetchAllData,
          color: primaryColor,
          backgroundColor: Colors.white,
          child: _buildContent(),
        ),
      ),
    );
  }
}
