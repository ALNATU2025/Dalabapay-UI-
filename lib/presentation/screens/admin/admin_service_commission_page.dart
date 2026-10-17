// lib/presentation/screens/admin/admin_service_commission_page.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../core/services/api_service.dart';
import '../../../core/widgets/custom_drawer.dart';
import '../../../core/widgets/drawer_item.dart';
import '../dashboard/dashboard_screen.dart';

class AdminServiceCommissionPage extends StatefulWidget {
  const AdminServiceCommissionPage({super.key});

  @override
  State<AdminServiceCommissionPage> createState() =>
      _AdminServiceCommissionPageState();
}

class _AdminServiceCommissionPageState extends State<AdminServiceCommissionPage>
    with SingleTickerProviderStateMixin {
  // ==================== BRAND COLORS ====================
  static const Color primaryColor = Color(0xFF15368A);
  static const Color secondaryColor = Color(0xFF079A68);
  static const Color successColor = Color(0xFF079A68);
  static const Color errorColor = Color(0xFFE5484D);
  static const Color textPrimary = Color(0xFF10255A);
  static const Color textSecondary = Color(0xFF7B87A1);
  static const Color cardShadow = Color(0x1A000000);
  static const String _superAdminId = "690088325ca99bed6ab8d4a5";

  // ==================== SERVICE COLORS & ICONS ====================
  static const Map<String, Color> serviceColors = {
    'airtime': Color(0xFF2563EB),
    'international_airtime': Color(0xFF2563EB),
    'cable': Color(0xFF079A68),
    'data': Color(0xFF079A68),
    'electricity': Color(0xFFB7791F),
    'education': Color(0xFFE5484D),
    'ticket': Color(0xFF2563EB),
  };

  static const Map<String, String> serviceIcons = {
    'airtime': '📱',
    'international_airtime': '🌍',
    'cable': '📺',
    'data': '📶',
    'electricity': '⚡',
    'education': '🎓',
    'ticket': '🎫',
  };

  static const Map<String, String> serviceLabels = {
    'airtime': 'Airtime',
    'international_airtime': 'International Airtime',
    'cable': 'Cable TV',
    'data': 'Data',
    'electricity': 'Electricity',
    'education': 'Education',
    'ticket': 'Ticket',
  };

  // ==================== STATE ====================
  bool _isLoading = true;
  bool _isSuperAdmin = false;
  String? _errorMessage;

  // ==================== DATA ====================
  // In the state initialization, add default commission rates
  // ==================== DATA ====================
  Map<String, dynamic> _commissionData = {};
  Map<String, dynamic> _periodStats = {};
  Map<String, dynamic> _serviceBreakdownByPeriod = {};
  Map<String, dynamic> _commissionRates = {
    'international_airtime': {
      'label': 'International Airtime',
      'icon': '🌍',
      'color': '#7C3AED',
    },
    'airtime': {'label': 'Airtime', 'icon': '📱', 'color': '#4F46E5'},
    'cable': {'label': 'Cable TV', 'icon': '📺', 'color': '#059669'},
    'data': {'label': 'Data', 'icon': '📶', 'color': '#0891B2'},
    'electricity': {'label': 'Electricity', 'icon': '⚡', 'color': '#D97706'},
    'education': {'label': 'Education', 'icon': '🎓', 'color': '#DC2626'},
    'ticket': {'label': 'Ticket', 'icon': '🎫', 'color': '#2563EB'},
  };

  List<dynamic> _transactions = [];
  Map<String, dynamic> _pagination = {};
  List<dynamic> _serviceSummary = [];

  // ==================== FILTERS ====================
  String _selectedTimeFilter = 'all';
  String _selectedService = 'all';
  DateTimeRange? _selectedDateRange;
  bool _isDateRangeSelected = false;
  int _currentPage = 1;
  final int _itemsPerPage = 50;

  // ==================== FILTER OPTIONS ====================
  final List<Map<String, String>> _timeFilterOptions = [
    {'label': 'All Time', 'value': 'all'},
    {'label': 'Today', 'value': 'today'},
    {'label': 'This Week', 'value': 'week'},
    {'label': 'This Month', 'value': 'month'},
    {'label': 'This Year', 'value': 'year'},
    {'label': 'Custom Range', 'value': 'custom'},
  ];

  final List<Map<String, String>> _serviceFilterOptions = [
    {'label': 'All Services', 'value': 'all'},
    {'label': '📱 Airtime', 'value': 'airtime'},
    {'label': '🌍 International Airtime', 'value': 'international_airtime'},
    {'label': '📺 Cable TV', 'value': 'cable'},
    {'label': '📶 Data', 'value': 'data'},
    {'label': '⚡ Electricity', 'value': 'electricity'},
    {'label': '🎓 Education', 'value': 'education'},
    {'label': '🎫 Ticket', 'value': 'ticket'},
  ];

  // ==================== CONTROLLERS ====================
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late AnimationController _animationController;
  late ScrollController _scrollController;
  bool _isFabVisible = true;

  // ==================== DRAWER ITEMS ====================
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
      title: "Service Commission",
      icon: Icons.trending_up,
      page: SizedBox.shrink(),
      isAdminOnly: true,
    ),
    const DrawerItem(
      title: "Logout",
      icon: Icons.logout,
      page: SizedBox.shrink(),
    ),
  ];

  // ==================== INIT ====================
  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _loadData();

    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _animationController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _setupAnimations() {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
  }

  void _onScroll() {
    if (_scrollController.position.userScrollDirection ==
        ScrollDirection.forward) {
      if (!_isFabVisible) {
        setState(() => _isFabVisible = true);
      }
    } else if (_scrollController.position.userScrollDirection ==
        ScrollDirection.reverse) {
      if (_isFabVisible) {
        setState(() => _isFabVisible = false);
      }
    }
  }

  // ==================== DATA LOADING ====================
  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final userDataString = prefs.getString('user');

      if (userDataString == null) {
        setState(() {
          _isLoading = false;
          _errorMessage = "User data not found. Please log in again.";
        });
        return;
      }

      final userData = jsonDecode(userDataString);
      debugPrint("User Data from SharedPreferences: $userData");

      // Get fresh user role
      try {
        final roleResult = await ApiService.getUserRole();
        debugPrint('🔍 Service Commission - Role API Response: $roleResult');

        if (roleResult['success'] == true) {
          final data = roleResult['data'];
          final userRole = data?['role'] ?? 'user';

          // ✅ Trust backend only — no hardcoded ID
          final bool isSuperAdmin =
              data?['isSuperAdmin'] == true ||
              userRole == 'super_admin' ||
              userRole == 'superadmin';

          debugPrint('👤 User Role: $userRole');
          debugPrint('⭐ Is Super Admin: $isSuperAdmin');

          setState(() {
            _isSuperAdmin = isSuperAdmin;
          });

          await prefs.setString('role', userRole);
          await prefs.setBool('isSuperAdmin', isSuperAdmin);
        } else {
          _loadCurrentUserFromCache(userData);
        }
      } catch (e) {
        debugPrint('⚠️ Could not fetch role from backend: $e');
        _loadCurrentUserFromCache(userData);
      }

      if (!_isSuperAdmin) {
        setState(() {
          _isLoading = false;
          _errorMessage = "Super Admin access required for this page.";
        });
        return;
      }

      await _fetchCommissionData();
      _animationController.forward();
    } catch (e) {
      debugPrint('❌ Error loading data: $e');
      setState(() {
        _isLoading = false;
        _errorMessage = "Error loading data: ${e.toString()}";
      });
    }
  }

  void _loadCurrentUserFromCache(Map<String, dynamic> userData) {
    // ✅ Trust stored role from backend — no hardcoded ID
    final storedRole = userData['role']?.toString() ?? 'user';
    final bool isSuperAdmin =
        userData['isSuperAdmin'] == true || storedRole == 'super_admin';

    debugPrint('⭐ Fallback - Is Super Admin: $isSuperAdmin');

    setState(() {
      _isSuperAdmin = isSuperAdmin;
    });
  }

  Future<void> _fetchCommissionData() async {
    try {
      debugPrint('📊 Fetching commission data...');
      debugPrint('📄 Current Page: $_currentPage'); // ← ADD THIS

      String? startDate;
      String? endDate;

            if (_selectedTimeFilter == 'custom' &&
          _isDateRangeSelected &&
          _selectedDateRange != null) {
        // ✅ FIX: Build YYYY-MM-DD from LOCAL date parts.
        // Never use toIso8601String().split('T')[0] — it converts to UTC
        // and can shift the date back by one day for users in UTC+ timezones.
        final start = _selectedDateRange!.start;
        final end = _selectedDateRange!.end;

        startDate =
            '${start.year.toString().padLeft(4, '0')}-'
            '${start.month.toString().padLeft(2, '0')}-'
            '${start.day.toString().padLeft(2, '0')}';

        endDate =
            '${end.year.toString().padLeft(4, '0')}-'
            '${end.month.toString().padLeft(2, '0')}-'
            '${end.day.toString().padLeft(2, '0')}';

        debugPrint('📅 Custom range sent to backend: $startDate → $endDate');
      }

      final data = await ApiService.getAdminServiceCommissionStats(
        timeFilter: _selectedTimeFilter,
        service: _selectedService,
        startDate: startDate,
        endDate: endDate,
        page: _currentPage,
        limit: _itemsPerPage,
      );

      // ✅ SAFETY: Ensure data is a Map and has the expected structure
      final safeData = data;

      debugPrint('📊 Raw data summary:');
      debugPrint('   summary: ${safeData['summary']}');
      debugPrint(
        '   periodStats keys: ${(safeData['periodStats'] as Map?)?.keys}',
      );

      setState(() {
        _commissionData = Map<String, dynamic>.from(safeData);

        // ✅ FIXED: Extract summary correctly
        final summaryData = safeData['summary'] ?? {};
        _commissionData['totalCommission'] =
            summaryData['totalCommission'] ?? 0.0;
        _commissionData['totalTransactions'] =
            summaryData['totalTransactions'] ?? 0;
        _commissionData['totalVolume'] = summaryData['totalVolume'] ?? 0.0;

        // ✅ FIXED: Extract periodStats with correct casting
        final periodStatsData = safeData['periodStats'];
        if (periodStatsData is Map) {
          _periodStats = Map<String, dynamic>.from(periodStatsData);
          debugPrint('   periodStats loaded: ${_periodStats.keys}');
        } else {
          _periodStats = {};
        }

        // ✅ FIXED: Extract serviceBreakdownByPeriod
        final breakdownByPeriod = safeData['serviceBreakdownByPeriod'];
        if (breakdownByPeriod is Map) {
          _serviceBreakdownByPeriod = Map<String, dynamic>.from(
            breakdownByPeriod,
          );
        } else {
          _serviceBreakdownByPeriod = {};
        }

        // ✅ FIXED: Extract transactions
        final transactions = safeData['transactions'];
        _transactions = transactions is List ? transactions : [];

        // ✅ FIXED: Extract pagination
        final pagination = safeData['pagination'];
        _pagination =
            pagination is Map ? Map<String, dynamic>.from(pagination) : {};

        // ✅ FIXED: Extract commissionRates
        final rates = safeData['commissionRates'];
        _commissionRates = rates is Map ? Map<String, dynamic>.from(rates) : {};

        // ✅ FIXED: Extract serviceSummary (no duplicate variable)
        final serviceSummaryData = safeData['serviceSummary'];
        _serviceSummary = serviceSummaryData is List ? serviceSummaryData : [];

        _isLoading = false;
      });

      debugPrint('✅ Commission data loaded successfully');
      debugPrint('   Total Commission: ${_commissionData['totalCommission']}');
      debugPrint(
        '   Total Transactions: ${_commissionData['totalTransactions']}',
      );
      debugPrint('   Services: ${_serviceSummary.length}');
    } catch (e) {
      debugPrint('❌ Error fetching commission data: $e');
      setState(() {
        _isLoading = false;
        _errorMessage = "Failed to fetch commission data: ${e.toString()}";
        _periodStats = {};
        _serviceBreakdownByPeriod = {};
        _transactions = [];
        _pagination = {};
        _commissionRates = {};
        _serviceSummary = [];
      });
    }
  }

  // ==================== FILTERS ====================
  // ==================== FILTERS ====================
  // ==================== FILTERS ====================
  void _applyFilters({bool resetPage = true}) async {
    setState(() {
      _isLoading = true;
      if (resetPage) {
        _currentPage = 1;
      }
      // ✅ ADD THIS: Clear existing transactions to show loading state
      _transactions = [];
    });

    try {
      await _fetchCommissionData();
    } catch (e) {
      debugPrint('❌ Error applying filters: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _clearAllFilters() {
    setState(() {
      _selectedTimeFilter = 'all';
      _selectedService = 'all';
      _isDateRangeSelected = false;
      _selectedDateRange = null;
    });
    _applyFilters(resetPage: true);
  }

  bool _hasActiveFilters() {
    return _selectedTimeFilter != 'all' ||
        _selectedService != 'all' ||
        _isDateRangeSelected;
  }

  Future<void> _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      initialDateRange: _selectedDateRange,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: primaryColor,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _selectedDateRange = picked;
        _isDateRangeSelected = true;
        _selectedTimeFilter = 'custom';
      });
      _applyFilters(resetPage: true);
    }
  }

  // ==================== NAVIGATION ====================
  void _goBack() {
    if (Navigator.canPop(context)) {
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
    } else {
      Navigator.pushReplacementNamed(context, '/admin-dashboard');
    }
  }

  // ==================== FORMAT HELPERS ====================
  String _formatCurrency(double amount) {
    return '₦${NumberFormat('#,##0.00').format(amount)}';
  }

  String _formatNumber(int count) {
    return NumberFormat('#,##0').format(count);
  }

  Color _getServiceColor(String service) {
    return serviceColors[service] ?? Colors.grey;
  }

  String _getServiceLabel(String service) {
    return serviceLabels[service] ?? service;
  }

  DateTime _parseDateTime(dynamic value) {
    try {
      if (value == null) return DateTime.now();
      if (value is DateTime) return value;
      if (value is String) return DateTime.parse(value);
      return DateTime.now();
    } catch (_) {
      return DateTime.now();
    }
  }

  // ==================== BUILD UI ====================
  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    if (_isLoading && _commissionData.isEmpty) {
      return _buildShimmerSkeleton(isMobile);
    }

    if (_errorMessage != null && _commissionData.isEmpty) {
      return _buildErrorView(isMobile);
    }

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Colors.grey.shade50,
      drawer: CustomDrawer(
        header: _buildDrawerHeader(),
        items: _drawerItems,
        selectedItem: _drawerItems.firstWhere(
          (item) => item.title == "Service Commission",
          orElse: () => _drawerItems.first,
        ),
        onItemSelected: _onDrawerItemSelected,
        isAdmin: true,
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _fetchCommissionData,
          color: primaryColor,
          child: CustomScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(child: _buildHeader(isMobile)),
              SliverToBoxAdapter(child: _buildCommissionSummary(isMobile)),
              SliverToBoxAdapter(child: _buildFilterSection(isMobile)),
              SliverToBoxAdapter(child: _buildPeriodStats(isMobile)),
              SliverToBoxAdapter(
                child: _buildServiceBreakdownByPeriod(isMobile),
              ),
              SliverToBoxAdapter(child: _buildBestPerforming(isMobile)),
              SliverToBoxAdapter(child: _buildTransactionsList(isMobile)),
              SliverToBoxAdapter(child: _buildCommissionRates(isMobile)),
              const SliverToBoxAdapter(child: SizedBox(height: 80)),
            ],
          ),
        ),
      ),
      floatingActionButton:
          _isFabVisible
              ? FloatingActionButton(
                onPressed: _fetchCommissionData,
                backgroundColor: primaryColor,
                child: const Icon(Icons.refresh_rounded, color: Colors.white),
              )
              : null,
    );
  }

  // ==================== DRAWER HEADER ====================
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
                ),
              ),
              Text(
                'pay',
                style: GoogleFonts.inter(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: secondaryColor,
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
              _isSuperAdmin ? 'SUPER ADMIN' : 'ADMIN PANEL',
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: secondaryColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

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
        MaterialPageRoute(builder: (_) => const DashboardScreen()),
      );
      return;
    }
    if (item.title == "Admin Dashboard") {
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
      Navigator.pushReplacementNamed(context, '/admin-dashboard');
      return;
    }
    if (item.title == "Service Commission") {
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
      return;
    }
  }

  void _showLogoutConfirmation() {
    showDialog(
      context: context,
      builder:
          (_) => AlertDialog(
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

  // ==================== HEADER ====================
  // ==================== HEADER - FIXED ====================
  // ==================== HEADER - IMPROVED UX ====================
  Widget _buildHeader(bool isMobile) {
    final totalCommission =
        (_commissionData['totalCommission'] ?? 0).toDouble();
    final totalTransactions = _commissionData['totalTransactions'] ?? 0;
    final totalVolume = (_commissionData['totalVolume'] ?? 0).toDouble();

    final avgCommission =
        totalTransactions > 0 ? totalCommission / totalTransactions : 0.0;
    final avgRate =
        totalVolume > 0 ? (totalCommission / totalVolume * 100) : 0.0;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 16 : 24,
        vertical: isMobile ? 16 : 20,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [secondaryColor, primaryColor],
          stops: const [0.0, 0.6],
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
        boxShadow: [
          BoxShadow(
            color: primaryColor.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            children: [
              GestureDetector(
                onTap: _goBack,
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
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Admin / Service Commission',
                      style: GoogleFonts.inter(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: isMobile ? 11 : 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      'Revenue Tracker',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: isMobile ? 18 : 24,
                        fontWeight: FontWeight.w700,
                      ),
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
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  _isSuperAdmin ? 'SUPER ADMIN' : 'ADMIN',
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
          const SizedBox(height: 16),

          // Stats Cards Row
          Row(
            children: [
              Expanded(
                flex: 2,
                child: Container(
                  padding: EdgeInsets.all(isMobile ? 16 : 20),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(isMobile ? 12 : 16),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.trending_up_rounded,
                            color: Colors.green.shade300,
                            size: isMobile ? 16 : 20,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Platform Revenue',
                            style: GoogleFonts.inter(
                              color: Colors.white.withValues(alpha: 0.7),
                              fontSize: isMobile ? 10 : 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _formatCurrency(totalCommission),
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: isMobile ? 20 : 28,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'from ${_formatNumber(totalTransactions)} transactions · ${avgRate.toStringAsFixed(2)}% avg rate',
                        style: GoogleFonts.inter(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: isMobile ? 9 : 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 1,
                child: Container(
                  padding: EdgeInsets.all(isMobile ? 12 : 14),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(isMobile ? 12 : 16),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.1),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Avg per Txn',
                        style: GoogleFonts.inter(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: isMobile ? 9 : 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _formatCurrency(avgCommission),
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: isMobile ? 16 : 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$totalTransactions txns',
                        style: GoogleFonts.inter(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: isMobile ? 8 : 10,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // Helper text - explain the numbers
          const SizedBox(height: 8),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 12 : 16,
              vertical: isMobile ? 6 : 8,
            ),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.amber.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  color: Colors.amber.shade200,
                  size: isMobile ? 14 : 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Revenue is calculated from service commissions. '
                    'Total volume: ${_formatCurrency(totalVolume)}',
                    style: GoogleFonts.inter(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: isMobile ? 9 : 11,
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

  // ==================== COMMISSION SUMMARY ====================
  // ==================== COMMISSION SUMMARY - FIXED ====================
  // ==================== COMMISSION SUMMARY - IMPROVED ====================
  Widget _buildCommissionSummary(bool isMobile) {
    final totalCommission =
        (_commissionData['totalCommission'] ?? 0).toDouble();
    final totalTransactions = _commissionData['totalTransactions'] ?? 0;
    final totalVolume = (_commissionData['totalVolume'] ?? 0).toDouble();

    final avgCommission =
        totalTransactions > 0 ? totalCommission / totalTransactions : 0.0;
    final avgRate =
        totalVolume > 0 ? (totalCommission / totalVolume * 100) : 0.0;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 16 : 24,
        vertical: isMobile ? 8 : 12,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Revenue Summary',
                style: GoogleFonts.inter(
                  fontSize: isMobile ? 14 : 16,
                  fontWeight: FontWeight.w600,
                  color: textPrimary,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: isMobile ? 6 : 8,
                  vertical: isMobile ? 2 : 4,
                ),
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${avgRate.toStringAsFixed(2)}% avg rate',
                  style: GoogleFonts.inter(
                    fontSize: isMobile ? 9 : 11,
                    fontWeight: FontWeight.w600,
                    color: primaryColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildSummaryCard(
                  label: 'Platform Revenue',
                  value: _formatCurrency(totalCommission),
                  subtitle: 'From ${_formatNumber(totalTransactions)} txns',
                  icon: HugeIcons.strokeRoundedMoney01,
                  color: primaryColor,
                  isMobile: isMobile,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildSummaryCard(
                  label: 'Avg Revenue',
                  value: _formatCurrency(avgCommission),
                  subtitle: 'Per transaction',
                  icon: HugeIcons.strokeRoundedCalculator,
                  color: secondaryColor,
                  isMobile: isMobile,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Container(
            padding: EdgeInsets.all(isMobile ? 8 : 10),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Total Transaction Volume',
                  style: GoogleFonts.inter(
                    fontSize: isMobile ? 10 : 12,
                    color: textSecondary,
                  ),
                ),
                Text(
                  _formatCurrency(totalVolume),
                  style: GoogleFonts.inter(
                    fontSize: isMobile ? 12 : 14,
                    fontWeight: FontWeight.w600,
                    color: textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard({
    required String label,
    required String value,
    required String subtitle,
    required dynamic icon,
    required Color color,
    required bool isMobile,
  }) {
    return Container(
      padding: EdgeInsets.all(isMobile ? 12 : 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(isMobile ? 12 : 14),
        border: Border.all(color: color.withValues(alpha: 0.15)),
        boxShadow: [
          BoxShadow(
            color: cardShadow,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(isMobile ? 4 : 6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: HugeIcon(
                  icon: icon,
                  color: color,
                  size: isMobile ? 14 : 18,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: isMobile ? 10 : 12,
                  color: textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: isMobile ? 14 : 18,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: GoogleFonts.inter(
              fontSize: isMobile ? 9 : 10,
              color: textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // ==================== FILTER SECTION ====================
  Widget _buildFilterSection(bool isMobile) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 16 : 24,
        vertical: isMobile ? 8 : 12,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Filters',
                style: GoogleFonts.inter(
                  fontSize: isMobile ? 14 : 16,
                  fontWeight: FontWeight.w600,
                  color: textPrimary,
                ),
              ),
              const SizedBox(width: 8),
              if (_hasActiveFilters())
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: isMobile ? 8 : 10,
                    vertical: isMobile ? 2 : 4,
                  ),
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Active',
                    style: GoogleFonts.inter(
                      fontSize: isMobile ? 9 : 11,
                      fontWeight: FontWeight.w600,
                      color: primaryColor,
                    ),
                  ),
                ),
              const Spacer(),
              if (_hasActiveFilters())
                TextButton(
                  onPressed: _clearAllFilters,
                  style: TextButton.styleFrom(
                    foregroundColor: errorColor,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    'Clear All',
                    style: GoogleFonts.inter(
                      fontSize: isMobile ? 11 : 12,
                      fontWeight: FontWeight.w600,
                      color: errorColor,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),

          Row(
            children: [
              Expanded(
                child: _buildFilterDropdown(
                  label: 'Time Period',
                  value: _selectedTimeFilter,
                  items: _timeFilterOptions,
                  onChanged: (v) {
                    setState(() {
                      _selectedTimeFilter = v;
                      if (v != 'custom') {
                        _isDateRangeSelected = false;
                        _selectedDateRange = null;
                      }
                    });
                    _applyFilters(resetPage: true); // ← CHANGE THIS LINE
                  },
                  isMobile: isMobile,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildFilterDropdown(
                  label: 'Service',
                  value: _selectedService,
                  items: _serviceFilterOptions,
                  onChanged: (v) {
                    setState(() {
                      _selectedService = v;
                    });
                    _applyFilters(resetPage: true); // ← CHANGE THIS LINE
                  },
                  isMobile: isMobile,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          if (_selectedTimeFilter == 'custom') _buildDateRangePicker(isMobile),
        ],
      ),
    );
  }

  Widget _buildFilterDropdown({
    required String label,
    required String value,
    required List<Map<String, String>> items,
    required ValueChanged<String> onChanged,
    required bool isMobile,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: isMobile ? 10 : 12,
            fontWeight: FontWeight.w600,
            color: textSecondary,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: DropdownButton<String>(
            value: value,
            onChanged: (newValue) => onChanged(newValue!),
            items:
                items.map((item) {
                  return DropdownMenuItem<String>(
                    value: item['value'],
                    child: Text(
                      item['label'] ?? item['value'] ?? '',
                      style: GoogleFonts.inter(fontSize: isMobile ? 12 : 13),
                    ),
                  );
                }).toList(),
            underline: const SizedBox(),
            isExpanded: true,
            icon: HugeIcon(
              icon: HugeIcons.strokeRoundedArrowDown01,
              color: primaryColor,
              size: 16,
            ),
            dropdownColor: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildDateRangePicker(bool isMobile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        InkWell(
          onTap: _selectDateRange,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color:
                  _isDateRangeSelected
                      ? primaryColor.withValues(alpha: 0.05)
                      : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color:
                    _isDateRangeSelected ? primaryColor : Colors.grey.shade200,
                width: _isDateRangeSelected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                HugeIcon(
                  icon: HugeIcons.strokeRoundedCalendar01,
                  color: _isDateRangeSelected ? primaryColor : textSecondary,
                  size: isMobile ? 14 : 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _isDateRangeSelected && _selectedDateRange != null
                        ? '${DateFormat('dd MMM yy').format(_selectedDateRange!.start)} - ${DateFormat('dd MMM yy').format(_selectedDateRange!.end)}'
                        : 'Select custom date range',
                    style: GoogleFonts.inter(
                      fontSize: isMobile ? 11 : 12,
                      color: _isDateRangeSelected ? textPrimary : textSecondary,
                      fontWeight:
                          _isDateRangeSelected
                              ? FontWeight.w500
                              : FontWeight.w400,
                    ),
                  ),
                ),
                if (_isDateRangeSelected)
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _isDateRangeSelected = false;
                        _selectedDateRange = null;
                        _selectedTimeFilter = 'all';
                        _currentPage = 1;
                      });
                      _applyFilters();
                    },
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.close_rounded,
                        size: isMobile ? 12 : 14,
                        color: textSecondary,
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

  // ==================== PERIOD STATS ====================
  // ==================== PERIOD STATS - FIXED ====================
  // ==================== PERIOD STATS - IMPROVED ====================
  Widget _buildPeriodStats(bool isMobile) {
    final periodStats = _periodStats;

    if (periodStats.isEmpty) {
      return const SizedBox.shrink();
    }

    final periods = [
      {
        'key': 'today',
        'label': 'Today',
        'icon': HugeIcons.strokeRoundedCalendar01,
      },
      {
        'key': 'week',
        'label': 'This Week',
        'icon': HugeIcons.strokeRoundedCalendar02,
      },
      {
        'key': 'month',
        'label': 'This Month',
        'icon': HugeIcons.strokeRoundedCalendar03,
      },
      {
        'key': 'year',
        'label': 'This Year',
        'icon': HugeIcons.strokeRoundedCalendar04,
      },
      {
        'key': 'allTime',
        'label': 'All Time',
        'icon': HugeIcons.strokeRoundedCalendar05,
      },
    ];

    final String selectedServiceLabel =
        _selectedService == 'all'
            ? 'All Services'
            : (_serviceFilterOptions.firstWhere(
                  (opt) => opt['value'] == _selectedService,
                  orElse: () => {'label': 'All Services'},
                )['label'] ??
                'All Services');

    // Get the total volume for reference
    final totalVolume = (_commissionData['totalVolume'] ?? 0).toDouble();

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 16 : 24,
        vertical: isMobile ? 8 : 12,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Revenue by Period',
                style: GoogleFonts.inter(
                  fontSize: isMobile ? 14 : 16,
                  fontWeight: FontWeight.w600,
                  color: textPrimary,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: isMobile ? 6 : 8,
                  vertical: isMobile ? 2 : 4,
                ),
                decoration: BoxDecoration(
                  color: secondaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  selectedServiceLabel,
                  style: GoogleFonts.inter(
                    fontSize: isMobile ? 9 : 11,
                    fontWeight: FontWeight.w600,
                    color: secondaryColor,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                'Volume: ${_formatCurrency(totalVolume)}',
                style: GoogleFonts.inter(
                  fontSize: isMobile ? 9 : 11,
                  color: textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final cardWidth =
                  isMobile
                      ? (constraints.maxWidth - 8) / 2 - 4
                      : (constraints.maxWidth - 16) / 3 - 4;
              return Wrap(
                spacing: isMobile ? 4 : 8,
                runSpacing: isMobile ? 8 : 12,
                children:
                    periods.map((period) {
                      final key = period['key'] as String;
                      final stats = periodStats[key] ?? {};
                      final count = stats['count'] ?? 0;
                      final commission = (stats['commission'] ?? 0).toDouble();
                      final amount = (stats['amount'] ?? 0).toDouble();

                      final colorMap = {
                        'today': primaryColor,
                        'week': secondaryColor,
                        'month': Colors.orange.shade700,
                        'year': Colors.purple.shade700,
                        'allTime': Colors.indigo.shade700,
                      };
                      final color = colorMap[key] ?? primaryColor;

                      final isAllTime = key == 'allTime';

                      return SizedBox(
                        width: cardWidth,
                        child: Container(
                          padding: EdgeInsets.all(isMobile ? 10 : 14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(
                              isMobile ? 12 : 14,
                            ),
                            border: Border.all(
                              color:
                                  isAllTime
                                      ? color
                                      : color.withValues(alpha: 0.15),
                              width: isAllTime ? 2 : 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: cardShadow,
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: EdgeInsets.all(isMobile ? 3 : 5),
                                    decoration: BoxDecoration(
                                      color: color.withValues(alpha: 0.1),
                                      shape: BoxShape.circle,
                                    ),
                                    child: HugeIcon(
                                      icon: period['icon'] as dynamic,
                                      color: color,
                                      size: isMobile ? 12 : 16,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      period['label'] as String,
                                      style: GoogleFonts.inter(
                                        fontSize: isMobile ? 9 : 11,
                                        color:
                                            isAllTime
                                                ? textPrimary
                                                : textSecondary,
                                        fontWeight:
                                            isAllTime
                                                ? FontWeight.w600
                                                : FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  if (isAllTime)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                        vertical: 1,
                                      ),
                                      decoration: BoxDecoration(
                                        color: color.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        'TOTAL',
                                        style: GoogleFonts.inter(
                                          fontSize: isMobile ? 7 : 8,
                                          fontWeight: FontWeight.w700,
                                          color: color,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      _formatCurrency(commission),
                                      style: GoogleFonts.inter(
                                        fontSize: isMobile ? 14 : 18,
                                        fontWeight: FontWeight.w700,
                                        color: color,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${_formatNumber(count)} txns',
                                    style: GoogleFonts.inter(
                                      fontSize: isMobile ? 8 : 9,
                                      color: textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                              if (amount > 0)
                                Text(
                                  'Volume: ${_formatCurrency(amount)}',
                                  style: GoogleFonts.inter(
                                    fontSize: isMobile ? 7 : 8,
                                    color: textSecondary,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  // ==================== SERVICE BREAKDOWN BY PERIOD ====================
  // ==================== SERVICE BREAKDOWN BY PERIOD - FIXED ====================
  // ==================== SERVICE BREAKDOWN BY PERIOD - FIXED ====================
  Widget _buildServiceBreakdownByPeriod(bool isMobile) {
    final breakdownByPeriod = _serviceBreakdownByPeriod;

    if (breakdownByPeriod.isEmpty) {
      return const SizedBox.shrink();
    }

    // ✅ FIXED: Get all services including zero counts
    final allServices = _commissionRates.keys.toList();

    final periods = [
      {'key': 'today', 'label': 'Today', 'color': primaryColor},
      {'key': 'week', 'label': 'This Week', 'color': secondaryColor},
      {'key': 'month', 'label': 'This Month', 'color': Colors.orange.shade700},
      {'key': 'year', 'label': 'This Year', 'color': Colors.purple.shade700},
      {'key': 'allTime', 'label': 'All Time', 'color': Colors.indigo.shade700},
    ];

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 16 : 24,
        vertical: isMobile ? 8 : 12,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Service Performance',
                style: GoogleFonts.inter(
                  fontSize: isMobile ? 14 : 16,
                  fontWeight: FontWeight.w600,
                  color: textPrimary,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: isMobile ? 6 : 8,
                  vertical: isMobile ? 2 : 4,
                ),
                decoration: BoxDecoration(
                  color: secondaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'By Service & Period',
                  style: GoogleFonts.inter(
                    fontSize: isMobile ? 9 : 11,
                    fontWeight: FontWeight.w600,
                    color: secondaryColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...periods.map((period) {
            final key = period['key'] as String;
            final label = period['label'] as String;
            final color = period['color'] as Color;

            final rawData = breakdownByPeriod[key];
            final Map<String, dynamic> periodData;
            if (rawData is Map) {
              periodData = Map<String, dynamic>.from(rawData);
            } else {
              periodData = {};
            }

            // ✅ FIXED: Include ALL services, even those with zero count
            final entries =
                allServices.map((serviceKey) {
                  final serviceData = periodData[serviceKey] ?? {};
                  return MapEntry(serviceKey, serviceData);
                }).toList();

            // Sort by commission (highest first), but keep zero at the end
            entries.sort((a, b) {
              final aCommission =
                  (a.value['commission'] as num?)?.toDouble() ?? 0;
              final bCommission =
                  (b.value['commission'] as num?)?.toDouble() ?? 0;
              return bCommission.compareTo(aCommission);
            });

            // Show top services, but always show at least the top ones
            final topServices = entries.take(4).toList();

            if (topServices.isEmpty) return const SizedBox.shrink();

            return Container(
              margin: EdgeInsets.only(bottom: isMobile ? 8 : 12),
              padding: EdgeInsets.all(isMobile ? 12 : 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(isMobile ? 12 : 14),
                border: Border.all(color: color.withValues(alpha: 0.15)),
                boxShadow: [
                  BoxShadow(
                    color: cardShadow,
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 4,
                        height: 16,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        label,
                        style: GoogleFonts.inter(
                          fontSize: isMobile ? 13 : 15,
                          fontWeight: FontWeight.w600,
                          color: textPrimary,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${_formatNumber(entries.length)} services',
                        style: GoogleFonts.inter(
                          fontSize: isMobile ? 9 : 11,
                          color: textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...topServices.map((entry) {
                    final service = entry.value;
                    final serviceKey = entry.key;
                    final icon = service['icon']?.toString() ?? '📦';
                    final count = (service['count'] as num?)?.toInt() ?? 0;
                    final commission =
                        (service['commission'] as num?)?.toDouble() ?? 0.0;
                    final amount =
                        (service['amount'] as num?)?.toDouble() ?? 0.0;
                    final serviceColor = _getServiceColor(serviceKey);
                    final label = _getServiceLabel(serviceKey);

                    // ✅ FIXED: Show zero-count services with grayed out style
                    final hasData = count > 0;

                    // ✅ FIXED: Use Opacity widget instead of Container opacity
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: GestureDetector(
                        onTap: () {
                          if (hasData) {
                            setState(() {
                              _selectedService = serviceKey;
                              _currentPage = 1;
                            });
                            _applyFilters();
                          }
                        },
                        child: Opacity(
                          opacity: hasData ? 1.0 : 0.6,
                          child: Container(
                            padding: EdgeInsets.all(isMobile ? 8 : 10),
                            decoration: BoxDecoration(
                              color:
                                  hasData
                                      ? serviceColor.withValues(alpha: 0.05)
                                      : Colors.grey.withValues(alpha: 0.03),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color:
                                    hasData
                                        ? serviceColor.withValues(alpha: 0.1)
                                        : Colors.grey.withValues(alpha: 0.2),
                              ),
                            ),
                            child: Row(
                              children: [
                                Text(
                                  icon,
                                  style: TextStyle(
                                    fontSize: isMobile ? 16 : 20,
                                    color: hasData ? null : Colors.grey,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        label,
                                        style: GoogleFonts.inter(
                                          fontSize: isMobile ? 12 : 13,
                                          fontWeight: FontWeight.w600,
                                          color:
                                              hasData
                                                  ? textPrimary
                                                  : textSecondary,
                                        ),
                                      ),
                                      Row(
                                        children: [
                                          Text(
                                            '${_formatNumber(count)} txns',
                                            style: GoogleFonts.inter(
                                              fontSize: isMobile ? 9 : 10,
                                              color:
                                                  hasData
                                                      ? textSecondary
                                                      : Colors.grey.shade400,
                                            ),
                                          ),
                                          if (hasData) ...[
                                            const SizedBox(width: 8),
                                            Text(
                                              '· ₦${(count > 0 ? (amount / count) : 0).toStringAsFixed(0)} avg',
                                              style: GoogleFonts.inter(
                                                fontSize: isMobile ? 9 : 10,
                                                color: textSecondary,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      _formatCurrency(commission),
                                      style: GoogleFonts.inter(
                                        fontSize: isMobile ? 13 : 16,
                                        fontWeight: FontWeight.w700,
                                        color:
                                            hasData
                                                ? serviceColor
                                                : Colors.grey.shade400,
                                      ),
                                    ),
                                    if (hasData)
                                      Text(
                                        '${(count > 0 ? (commission / amount * 100) : 0).toStringAsFixed(1)}%',
                                        style: GoogleFonts.inter(
                                          fontSize: isMobile ? 8 : 10,
                                          color: textSecondary,
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // ==================== BEST PERFORMING SERVICES ====================
  Widget _buildBestPerforming(bool isMobile) {
    final serviceSummary = _serviceSummary;

    if (serviceSummary.isEmpty) {
      return const SizedBox.shrink();
    }

    // ✅ SAFETY CHECK: Filter out invalid entries
    final validServices =
        serviceSummary
            .where((s) => s != null && s is Map && s['commission'] != null)
            .cast<Map<String, dynamic>>()
            .toList();

    if (validServices.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 16 : 24,
        vertical: isMobile ? 8 : 12,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '🏆 Best Performing Services',
                style: GoogleFonts.inter(
                  fontSize: isMobile ? 14 : 16,
                  fontWeight: FontWeight.w600,
                  color: textPrimary,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: isMobile ? 6 : 8,
                  vertical: isMobile ? 2 : 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'By Commission',
                  style: GoogleFonts.inter(
                    fontSize: isMobile ? 9 : 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.amber.shade700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: EdgeInsets.all(isMobile ? 12 : 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(isMobile ? 12 : 14),
              border: Border.all(color: Colors.grey.shade200),
              boxShadow: [
                BoxShadow(
                  color: cardShadow,
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children:
                  validServices.take(5).map((service) {
                    // ✅ SAFETY: Use default values if fields are missing
                    final label = service['label']?.toString() ?? 'Unknown';
                    final icon = service['icon']?.toString() ?? '📦';
                    final colorHex = service['color']?.toString() ?? '#6B7280';
                    final color = Color(
                      int.parse(colorHex.replaceFirst('#', '0xFF')),
                    );
                    final count = (service['count'] as num?)?.toInt() ?? 0;
                    final commission =
                        (service['commission'] as num?)?.toDouble() ?? 0.0;
                    final volume =
                        (service['volume'] as num?)?.toDouble() ?? 0.0;
                    final rate = service['rate']?.toString() ?? '0%';

                    final maxCommission =
                        validServices.isNotEmpty
                            ? ((validServices[0]['commission'] as num?)
                                    ?.toDouble() ??
                                1.0)
                            : 1.0;
                    final percentage =
                        maxCommission > 0
                            ? (commission / maxCommission) * 100
                            : 0;

                    final medals = ['🥇', '🥈', '🥉', '4️⃣', '5️⃣'];
                    final index = validServices.indexOf(service);

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Container(
                        padding: EdgeInsets.all(isMobile ? 10 : 12),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Text(
                              medals[index % medals.length],
                              style: TextStyle(fontSize: isMobile ? 20 : 24),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        icon,
                                        style: TextStyle(
                                          fontSize: isMobile ? 16 : 18,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        label,
                                        style: GoogleFonts.inter(
                                          fontSize: isMobile ? 13 : 15,
                                          fontWeight: FontWeight.w600,
                                          color: textPrimary,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: color.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: Text(
                                          rate,
                                          style: GoogleFonts.inter(
                                            fontSize: isMobile ? 8 : 10,
                                            fontWeight: FontWeight.w700,
                                            color: color,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  Row(
                                    children: [
                                      Text(
                                        '${_formatNumber(count)} txns',
                                        style: GoogleFonts.inter(
                                          fontSize: isMobile ? 9 : 10,
                                          color: textSecondary,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        '₦${(volume).toStringAsFixed(0)} volume',
                                        style: GoogleFonts.inter(
                                          fontSize: isMobile ? 9 : 10,
                                          color: textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Container(
                                    height: 4,
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade200,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                    child: FractionallySizedBox(
                                      widthFactor: percentage / 100,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: color,
                                          borderRadius: BorderRadius.circular(
                                            2,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  _formatCurrency(commission),
                                  style: GoogleFonts.inter(
                                    fontSize: isMobile ? 14 : 18,
                                    fontWeight: FontWeight.w700,
                                    color: color,
                                  ),
                                ),
                                Text(
                                  '${percentage.toStringAsFixed(0)}%',
                                  style: GoogleFonts.inter(
                                    fontSize: isMobile ? 9 : 10,
                                    color: textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== TRANSACTIONS LIST ====================
  Widget _buildTransactionsList(bool isMobile) {
    final transactions = _transactions;

    if (transactions.isEmpty) {
      return Container(
        padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 16 : 24,
          vertical: isMobile ? 12 : 16,
        ),
        child: Container(
          padding: EdgeInsets.all(isMobile ? 24 : 32),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(isMobile ? 12 : 14),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            children: [
              Icon(
                Icons.inbox_outlined,
                size: isMobile ? 40 : 56,
                color: Colors.grey.shade400,
              ),
              const SizedBox(height: 8),
              Text(
                'No transactions found',
                style: GoogleFonts.inter(
                  fontSize: isMobile ? 14 : 16,
                  fontWeight: FontWeight.w500,
                  color: textSecondary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Try adjusting your filters',
                style: GoogleFonts.inter(
                  fontSize: isMobile ? 12 : 14,
                  color: Colors.grey.shade400,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 16 : 24,
        vertical: isMobile ? 8 : 12,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Commission Transactions',
                style: GoogleFonts.inter(
                  fontSize: isMobile ? 14 : 16,
                  fontWeight: FontWeight.w600,
                  color: textPrimary,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: isMobile ? 6 : 8,
                  vertical: isMobile ? 2 : 4,
                ),
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${transactions.length} shown',
                  style: GoogleFonts.inter(
                    fontSize: isMobile ? 9 : 11,
                    fontWeight: FontWeight.w600,
                    color: primaryColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...transactions.map((tx) {
            if (tx is! Map<String, dynamic>) return const SizedBox.shrink();

            final amount = (tx['amount'] as num?)?.toDouble() ?? 0.0;
            final commission =
                (tx['commissionEarned'] as num?)?.toDouble() ?? 0.0;
            final serviceLabel = tx['serviceLabel']?.toString() ?? 'Other';
            final serviceIcon = tx['serviceIcon']?.toString() ?? '📦';
            final serviceColorHex = tx['serviceColor']?.toString() ?? '#6B7280';
            final serviceColor = Color(
              int.parse(serviceColorHex.replaceFirst('#', '0xFF')),
            );
            final rate = (tx['commissionRate'] as num?)?.toDouble() ?? 0.0;
            final rateType = tx['rateType']?.toString() ?? 'percentage';
            final type = tx['type']?.toString() ?? 'Transaction';
            final status = tx['status']?.toString() ?? 'Successful';
            final date = _parseDateTime(tx['createdAt']);

            // Extract user info
            final user = tx['user'] as Map<String, dynamic>?;
            final userName =
                user?['fullName']?.toString() ??
                tx['userName']?.toString() ??
                'Unknown User';

            final rateDisplay =
                rateType == 'flat'
                    ? '₦${rate.toStringAsFixed(0)} flat'
                    : '${(rate * 100).toStringAsFixed(1)}%';

            final isSuccess =
                status.toLowerCase().contains('success') ||
                status.toLowerCase() == 'completed' ||
                status.toLowerCase() == 'successful';

            return GestureDetector(
              onTap: () {
                _showTransactionDetail(context, tx, isMobile);
              },
              child: Container(
                margin: EdgeInsets.only(bottom: isMobile ? 6 : 8),
                padding: EdgeInsets.all(isMobile ? 12 : 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(isMobile ? 12 : 14),
                  border: Border.all(
                    color:
                        isSuccess
                            ? Colors.grey.shade100
                            : errorColor.withValues(alpha: 0.2),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: cardShadow,
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: EdgeInsets.all(isMobile ? 6 : 8),
                          decoration: BoxDecoration(
                            color: serviceColor.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            serviceIcon,
                            style: TextStyle(fontSize: isMobile ? 16 : 20),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                serviceLabel,
                                style: GoogleFonts.inter(
                                  fontSize: isMobile ? 13 : 15,
                                  fontWeight: FontWeight.w600,
                                  color: textPrimary,
                                ),
                              ),
                              Text(
                                type,
                                style: GoogleFonts.inter(
                                  fontSize: isMobile ? 9 : 11,
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
                              _formatCurrency(amount),
                              style: GoogleFonts.inter(
                                fontSize: isMobile ? 13 : 15,
                                fontWeight: FontWeight.w600,
                                color: textPrimary,
                              ),
                            ),
                            Text(
                              'Commission: ${_formatCurrency(commission)}',
                              style: GoogleFonts.inter(
                                fontSize: isMobile ? 10 : 11,
                                fontWeight: FontWeight.w600,
                                color: serviceColor,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: isMobile ? 6 : 8,
                            vertical: isMobile ? 1 : 2,
                          ),
                          decoration: BoxDecoration(
                            color: serviceColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Rate: $rateDisplay',
                            style: GoogleFonts.inter(
                              fontSize: isMobile ? 8 : 9,
                              color: serviceColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: isMobile ? 6 : 8,
                            vertical: isMobile ? 1 : 2,
                          ),
                          decoration: BoxDecoration(
                            color:
                                isSuccess
                                    ? successColor.withValues(alpha: 0.1)
                                    : errorColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            status,
                            style: GoogleFonts.inter(
                              fontSize: isMobile ? 8 : 9,
                              color: isSuccess ? successColor : errorColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const Spacer(),
                        Icon(
                          Icons.person_outline_rounded,
                          size: isMobile ? 12 : 14,
                          color: textSecondary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          userName,
                          style: GoogleFonts.inter(
                            fontSize: isMobile ? 9 : 10,
                            color: textSecondary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          Icons.calendar_today_rounded,
                          size: isMobile ? 10 : 12,
                          color: textSecondary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          DateFormat('dd/MM/yy HH:mm').format(date),
                          style: GoogleFonts.inter(
                            fontSize: isMobile ? 9 : 10,
                            color: textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),
          if ((_pagination['totalPages'] ?? 0) > 1)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    onPressed: _currentPage > 1 ? _goToPreviousPage : null,
                    icon: const Icon(Icons.chevron_left_rounded),
                  ),
                  if (_isLoading)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Text(
                      'Page $_currentPage of ${_pagination['totalPages'] ?? 1}',
                      style: GoogleFonts.inter(
                        fontSize: isMobile ? 12 : 14,
                        color: textSecondary,
                      ),
                    ),
                  IconButton(
                    onPressed:
                        _currentPage < (_pagination['totalPages'] ?? 1)
                            ? _goToNextPage
                            : null,
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _goToNextPage() {
    final totalPages = _pagination['totalPages'] ?? 1;
    if (_currentPage < totalPages) {
      setState(() {
        _currentPage++;
      });
      // ✅ DON'T reset page, just fetch next page
      _fetchCommissionData(); // ← Call this directly instead of _applyFilters
    }
  }

  void _goToPreviousPage() {
    if (_currentPage > 1) {
      setState(() {
        _currentPage--;
      });
      // ✅ DON'T reset page, just fetch previous page
      _fetchCommissionData(); // ← Call this directly instead of _applyFilters
    }
  }

  // ==================== TRANSACTION DETAIL MODAL ====================
  void _showTransactionDetail(
    BuildContext context,
    Map<String, dynamic> tx,
    bool isMobile,
  ) {
    final amount = (tx['amount'] as num?)?.toDouble() ?? 0.0;
    final commission = (tx['commissionEarned'] as num?)?.toDouble() ?? 0.0;
    final serviceLabel = tx['serviceLabel']?.toString() ?? 'Other';
    final serviceIcon = tx['serviceIcon']?.toString() ?? '📦';
    final serviceColorHex = tx['serviceColor']?.toString() ?? '#6B7280';
    final serviceColor = Color(
      int.parse(serviceColorHex.replaceFirst('#', '0xFF')),
    );
    final rate = (tx['commissionRate'] as num?)?.toDouble() ?? 0.0;
    final rateType = tx['rateType']?.toString() ?? 'percentage';
    final type = tx['type']?.toString() ?? 'Transaction';
    final status = tx['status']?.toString() ?? 'Successful';
    final date = _parseDateTime(tx['createdAt']);
    final reference = tx['reference']?.toString() ?? 'N/A';
    final description = tx['description']?.toString() ?? 'No description';

    final user = tx['user'] as Map<String, dynamic>?;
    final userName =
        user?['fullName']?.toString() ??
        tx['userName']?.toString() ??
        'Unknown User';
    final userEmail = user?['email']?.toString() ?? 'N/A';
    final userPhone = user?['phone']?.toString() ?? 'N/A';
    final userId =
        user?['_id']?.toString() ?? tx['userId']?.toString() ?? 'N/A';

    final rateDisplay =
        rateType == 'flat'
            ? '₦${rate.toStringAsFixed(0)} flat'
            : '${(rate * 100).toStringAsFixed(1)}%';

    final isSuccess =
        status.toLowerCase().contains('success') ||
        status.toLowerCase() == 'completed' ||
        status.toLowerCase() == 'successful';

    showDialog(
      context: context,
      builder:
          (context) => Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Container(
              padding: EdgeInsets.all(isMobile ? 16 : 24),
              width: isMobile ? double.infinity : 500,
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.85,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: serviceColor.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            serviceIcon,
                            style: const TextStyle(fontSize: 24),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                serviceLabel,
                                style: GoogleFonts.inter(
                                  fontSize: isMobile ? 16 : 20,
                                  fontWeight: FontWeight.w700,
                                  color: textPrimary,
                                ),
                              ),
                              Text(
                                'Transaction Details',
                                style: GoogleFonts.inter(
                                  fontSize: isMobile ? 12 : 14,
                                  color: textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    const Divider(),
                    const SizedBox(height: 8),
                    _buildDetailRow('Type', type, isMobile),
                    _buildDetailRow(
                      'Status',
                      status,
                      isMobile,
                      color: isSuccess ? successColor : errorColor,
                    ),
                    _buildDetailRow(
                      'Amount',
                      _formatCurrency(amount),
                      isMobile,
                    ),
                    _buildDetailRow(
                      'Commission',
                      _formatCurrency(commission),
                      isMobile,
                      color: serviceColor,
                      bold: true,
                    ),
                    _buildDetailRow('Rate', rateDisplay, isMobile),
                    _buildDetailRow('Reference', reference, isMobile),
                    if (description.isNotEmpty &&
                        description != 'No description')
                      _buildDetailRow('Description', description, isMobile),
                    const Divider(),
                    const SizedBox(height: 4),
                    Text(
                      'User Information',
                      style: GoogleFonts.inter(
                        fontSize: isMobile ? 12 : 13,
                        fontWeight: FontWeight.w600,
                        color: textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _buildDetailRow('Name', userName, isMobile),
                    _buildDetailRow('Email', userEmail, isMobile),
                    _buildDetailRow('Phone', userPhone, isMobile),
                    _buildDetailRow(
                      'User ID',
                      userId,
                      isMobile,
                      fontSize: isMobile ? 10 : 11,
                    ),
                    _buildDetailRow(
                      'Date',
                      DateFormat('dd MMM yyyy, HH:mm:ss').format(date),
                      isMobile,
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Text(
                          'Close',
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
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

  Widget _buildDetailRow(
    String label,
    String value,
    bool isMobile, {
    Color? color,
    bool bold = false,
    double? fontSize,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: isMobile ? 80 : 100,
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontSize: isMobile ? 11 : 12,
                color: textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.inter(
                fontSize: fontSize ?? (isMobile ? 12 : 13),
                color: color ?? textPrimary,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== COMMISSION RATES ====================
  Widget _buildCommissionRates(bool isMobile) {
    final rates = _commissionRates;

    if (rates.isEmpty) {
      return const SizedBox.shrink();
    }

    final keys = rates.keys.toList();

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 16 : 24,
        vertical: isMobile ? 8 : 12,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Commission Rates',
                style: GoogleFonts.inter(
                  fontSize: isMobile ? 14 : 16,
                  fontWeight: FontWeight.w600,
                  color: textPrimary,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: isMobile ? 6 : 8,
                  vertical: isMobile ? 2 : 4,
                ),
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${keys.length} Services',
                  style: GoogleFonts.inter(
                    fontSize: isMobile ? 9 : 11,
                    fontWeight: FontWeight.w600,
                    color: primaryColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: EdgeInsets.all(isMobile ? 12 : 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(isMobile ? 12 : 14),
              border: Border.all(color: Colors.grey.shade200),
              boxShadow: [
                BoxShadow(
                  color: cardShadow,
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Wrap(
              spacing: isMobile ? 4 : 8,
              runSpacing: isMobile ? 4 : 8,
              children:
                  keys.map((key) {
                    final rate = rates[key] ?? {};
                    final label = rate['label']?.toString() ?? key;
                    final rateValue = (rate['rate'] ?? 0).toDouble();
                    final type = rate['type']?.toString() ?? 'percentage';
                    final icon = rate['icon']?.toString() ?? '📦';
                    final color = _getServiceColor(key);

                    String displayRate;
                    if (type == 'flat') {
                      displayRate = '₦${rateValue.toStringAsFixed(0)} flat';
                    } else {
                      displayRate = '${(rateValue * 100).toStringAsFixed(1)}%';
                    }

                    return Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: isMobile ? 8 : 12,
                        vertical: isMobile ? 4 : 6,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: color.withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            icon,
                            style: TextStyle(fontSize: isMobile ? 12 : 14),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            label,
                            style: GoogleFonts.inter(
                              fontSize: isMobile ? 9 : 11,
                              fontWeight: FontWeight.w500,
                              color: textPrimary,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              displayRate,
                              style: GoogleFonts.inter(
                                fontSize: isMobile ? 8 : 10,
                                fontWeight: FontWeight.w700,
                                color: color,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== SHIMMER SKELETON ====================
  Widget _buildShimmerSkeleton(bool isMobile) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: SafeArea(
        child: CustomScrollView(
          physics: const NeverScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Container(
                height: isMobile ? 180 : 220,
                margin: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Shimmer.fromColors(
                  baseColor: Colors.grey[300]!,
                  highlightColor: Colors.grey[100]!,
                  child: Container(
                    height: double.infinity,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Shimmer.fromColors(
                  baseColor: Colors.grey[300]!,
                  highlightColor: Colors.grey[100]!,
                  child: Container(
                    height: isMobile ? 70 : 90,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Shimmer.fromColors(
                  baseColor: Colors.grey[300]!,
                  highlightColor: Colors.grey[100]!,
                  child: Container(
                    height: 50,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: Shimmer.fromColors(
                  baseColor: Colors.grey[300]!,
                  highlightColor: Colors.grey[100]!,
                  child: Container(
                    height: isMobile ? 100 : 120,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => Shimmer.fromColors(
                  baseColor: Colors.grey[300]!,
                  highlightColor: Colors.grey[100]!,
                  child: Container(
                    margin: EdgeInsets.symmetric(
                      horizontal: isMobile ? 16 : 24,
                      vertical: 4,
                    ),
                    height: isMobile ? 65 : 80,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(isMobile ? 12 : 14),
                    ),
                  ),
                ),
                childCount: 6,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== ERROR VIEW ====================
  Widget _buildErrorView(bool isMobile) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
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
                  child: Icon(
                    Icons.error_outline_rounded,
                    color: errorColor,
                    size: isMobile ? 40 : 50,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Something went wrong',
                  style: GoogleFonts.inter(
                    fontSize: isMobile ? 20 : 24,
                    fontWeight: FontWeight.w700,
                    color: errorColor,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _errorMessage ?? 'Unknown error occurred',
                  style: GoogleFonts.inter(
                    fontSize: isMobile ? 14 : 16,
                    color: textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: isMobile ? 180 : 200,
                  child: ElevatedButton(
                    onPressed: _loadData,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      padding: EdgeInsets.symmetric(
                        vertical: isMobile ? 12 : 16,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.refresh_rounded,
                          size: 18,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 8),
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
        ),
      ),
    );
  }
}
