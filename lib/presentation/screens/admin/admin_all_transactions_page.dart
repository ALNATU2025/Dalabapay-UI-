// lib/presentation/screens/admin/admin_all_transactions_page.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:excel/excel.dart' as xl;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'dart:typed_data';

import '../../../core/services/api_service.dart';
import '../../../core/widgets/receipt_widget.dart';
import '../../../core/widgets/custom_drawer.dart';
import '../../../core/widgets/drawer_item.dart';
import '../dashboard/dashboard_screen.dart';
import 'admin_notifications_page.dart';

class AdminAllTransactionsPage extends StatefulWidget {
  const AdminAllTransactionsPage({super.key});

  @override
  State<AdminAllTransactionsPage> createState() =>
      _AdminAllTransactionsPageState();
}

class _AdminAllTransactionsPageState extends State<AdminAllTransactionsPage>
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
  bool _isLoading = true;
  bool _isAdmin = false;
  bool _isExportMenuOpen = false;
  String? _errorMessage;

  // ==================== PERIOD STATS (From API) ====================
  Map<String, dynamic> _periodStats = {
    'allTime': {'count': 0, 'amount': 0.0},
    'today': {'count': 0, 'amount': 0.0},
    'week': {'count': 0, 'amount': 0.0},
    'month': {'count': 0, 'amount': 0.0},
    'year': {'count': 0, 'amount': 0.0},
  };

  // ==================== STATUS SUMMARY (From API) ====================
  Map<String, int> _statusSummary = {
    'success': 0,
    'pending': 0,
    'failed': 0,
    'total': 0,
  };

  // ==================== PAGINATION ====================
  Map<String, dynamic> _pagination = {
    'total': 0,
    'page': 1,
    'limit': 50,
    'totalPages': 1,
  };

  bool _isLoadingMore = false;
  int _currentPage = 1;
  static const int _pageSize = 50;

  // ==================== FILTERS ====================
  String _selectedService = 'all';
  String _selectedStatus = 'all';
  String _selectedTimeFilter = 'all';
  String _searchQuery = '';
  String _selectedUserType = 'All';
  String _selectedSortBy = 'Newest';
  bool _showAdvancedFilters = false;

  // Date Range
  DateTimeRange? _selectedDateRange;
  bool _isDateRangeSelected = false;

  // ==================== FILTER OPTIONS ====================
  final List<Map<String, String>> _serviceFilterOptions = [
    {'label': 'All', 'value': 'all'},
    {'label': 'Airtime Purchase', 'value': 'airtime'},
    {'label': 'Data Purchase', 'value': 'data'},
    {'label': 'Electricity Purchase', 'value': 'electricity'},
    {'label': 'Cable TV Purchase', 'value': 'cable'},
    {'label': 'International Airtime', 'value': 'international_airtime'},
    {'label': 'Education Purchase', 'value': 'education'},
    {'label': 'Insurance Purchase', 'value': 'insurance'},
    {'label': 'Transfer', 'value': 'transfer'},
    {'label': 'Fund Wallet', 'value': 'wallet'},
    {'label': 'Commission Credit', 'value': 'commission'},
  ];

  final List<Map<String, String>> _statusFilterOptions = [
    {'label': 'All', 'value': 'all'},
    {'label': 'Success', 'value': 'success'},
    {'label': 'Pending', 'value': 'pending'},
    {'label': 'Failed', 'value': 'failed'},
  ];

  final List<Map<String, String>> _timeFilterOptions = [
    {'label': 'All Time', 'value': 'all'},
    {'label': 'Today', 'value': 'today'},
    {'label': 'This Week', 'value': 'week'},
    {'label': 'This Month', 'value': 'month'},
    {'label': 'This Year', 'value': 'year'},
    {'label': 'Custom Range', 'value': 'custom'},
  ];

  // ==================== CONTROLLERS ====================
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _minAmountController = TextEditingController();
  final TextEditingController _maxAmountController = TextEditingController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // ==================== ANIMATION ====================
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  Timer? _searchDebounce;
  late ScrollController _scrollController;

  // ==================== SNACKBAR OVERLAY ====================
  OverlayEntry? _snackbarOverlay;

  // ==================== FAB VISIBILITY ====================
  bool _isFabVisible = true;

  Timer? _autoRefreshTimer;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _loadData();

    // ✅ Auto-refresh every 15 seconds so new transactions appear without manual pull
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted && !_isLoading) {
        _fetchDashboardData(page: 1);
      }
    });

    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);

    _searchController.addListener(() {
      _searchDebounce?.cancel();
      _searchDebounce = Timer(const Duration(milliseconds: 400), () {
        if (mounted) {
          _searchQuery = _searchController.text;
          _applyFiltersAndFetch(showNotification: false);
        }
      });
    });

    _minAmountController.addListener(() {
      _applyFiltersAndFetch(showNotification: false);
    });
    _maxAmountController.addListener(() {
      _applyFiltersAndFetch(showNotification: false);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _minAmountController.dispose();
    _maxAmountController.dispose();
    _animationController.dispose();
    _searchDebounce?.cancel();
    _scrollController.dispose();
    _removeSnackbarOverlay();
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  void _setupAnimations() {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  // ==================== SCROLL LISTENER FOR FAB ====================
  void _onScroll() {
    if (_scrollController.position.userScrollDirection ==
        ScrollDirection.forward) {
      // Scrolling up - show FAB
      if (!_isFabVisible) {
        setState(() => _isFabVisible = true);
      }
    } else if (_scrollController.position.userScrollDirection ==
        ScrollDirection.reverse) {
      // Scrolling down - hide FAB
      if (_isFabVisible) {
        setState(() => _isFabVisible = false);
        // Also close export menu when scrolling down
        if (_isExportMenuOpen) {
          setState(() => _isExportMenuOpen = false);
        }
      }
    }
  }

  // ==================== CUSTOM TOAST NOTIFICATION ====================
  void _showToastNotification(String message, {bool isError = false}) {
    _removeSnackbarOverlay();

    final overlay = Overlay.of(context);
    final renderBox = context.findRenderObject() as RenderBox?;
    final offset = renderBox?.localToGlobal(Offset.zero) ?? Offset.zero;

    _snackbarOverlay = OverlayEntry(
      builder:
          (context) => Positioned(
            top: offset.dy + 60,
            left: 16,
            right: 16,
            child: Material(
              color: Colors.transparent,
              child: TweenAnimationBuilder<double>(
                duration: const Duration(milliseconds: 300),
                tween: Tween(begin: -100.0, end: 0.0),
                curve: Curves.easeOut,
                builder: (context, value, child) {
                  return Transform.translate(
                    offset: Offset(0, value),
                    child: child,
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: isError ? errorColor : primaryColor,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isError ? Icons.error_outline : Icons.check_rounded,
                          color: isError ? errorColor : primaryColor,
                          size: 16,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          message,
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: _removeSnackbarOverlay,
                        child: const Icon(
                          Icons.close_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
    );

    overlay.insert(_snackbarOverlay!);

    Future.delayed(const Duration(seconds: 3), _removeSnackbarOverlay);
  }

  void _removeSnackbarOverlay() {
    _snackbarOverlay?.remove();
    _snackbarOverlay = null;
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
      final bool isAdmin = userData['isAdmin'] == true;
      const String specificAdminUserId = "690088325ca99bed6ab8d4a5";
      final String? userId = userData['_id'];
      final bool isAdminById = userId == specificAdminUserId;

      setState(() => _isAdmin = isAdmin || isAdminById);

      if (!_isAdmin) {
        setState(() {
          _isLoading = false;
          _errorMessage = "You don't have permission to access this page.";
        });
        return;
      }

      await _fetchDashboardData();
      _animationController.forward();
    } catch (e) {
      debugPrint("❌ Error loading data: $e");
      setState(() {
        _isLoading = false;
        _errorMessage = "Error loading data: ${e.toString()}";
      });
    }
  }

  // ==================== FETCH DASHBOARD DATA ====================
  Future<void> _fetchDashboardData({int page = 1}) async {
    try {
      debugPrint('📊 Fetching admin dashboard data...');

      String? startDate;
      String? endDate;

      if (_selectedTimeFilter == 'custom' &&
          _isDateRangeSelected &&
          _selectedDateRange != null) {
        startDate = _selectedDateRange!.start.toIso8601String().split('T')[0];
        endDate = _selectedDateRange!.end.toIso8601String().split('T')[0];
      }

      final response = await ApiService.getAdminDashboard(
        timeFilter: _selectedTimeFilter,
        status: _selectedStatus,
        service: _selectedService,
        search: _searchQuery,
        page: page,
        limit: _pageSize,
        startDate: startDate,
        endDate: endDate,
      );

      if (response['success'] == true) {
        final periodStats = response['periodStats'] ?? {};
        setState(() {
          _periodStats = {
            'allTime': {
              'count': periodStats['allTime']?['count'] ?? 0,
              'amount': (periodStats['allTime']?['amount'] ?? 0).toDouble(),
            },
            'today': {
              'count': periodStats['today']?['count'] ?? 0,
              'amount': (periodStats['today']?['amount'] ?? 0).toDouble(),
            },
            'week': {
              'count': periodStats['week']?['count'] ?? 0,
              'amount': (periodStats['week']?['amount'] ?? 0).toDouble(),
            },
            'month': {
              'count': periodStats['month']?['count'] ?? 0,
              'amount': (periodStats['month']?['amount'] ?? 0).toDouble(),
            },
            'year': {
              'count': periodStats['year']?['count'] ?? 0,
              'amount': (periodStats['year']?['amount'] ?? 0).toDouble(),
            },
          };
        });

        final statusSummary = response['statusSummary'] ?? {};
        setState(() {
          _statusSummary = {
            'success': statusSummary['success'] ?? 0,
            'pending': statusSummary['pending'] ?? 0,
            'failed': statusSummary['failed'] ?? 0,
            'total': statusSummary['total'] ?? 0,
          };
        });

        final transactions = response['transactions'] ?? [];
        setState(() {
          if (page == 1) {
            _transactions = transactions;
          } else {
            _transactions.addAll(transactions);
          }
          _filteredTransactions = List.from(_transactions);
        });

        final pagination = response['pagination'] ?? {};
        setState(() {
          _pagination = {
            'total': pagination['total'] ?? 0,
            'page': pagination['page'] ?? 1,
            'limit': pagination['limit'] ?? _pageSize,
            'totalPages': pagination['totalPages'] ?? 1,
          };
          _currentPage = pagination['page'] ?? 1;
        });

        debugPrint('✅ Dashboard data loaded successfully!');

        _applySorting();

        setState(() {
          _isLoading = false;
          _isLoadingMore = false;
        });
      } else {
        throw Exception(response['message'] ?? 'Failed to load dashboard data');
      }
    } catch (e) {
      debugPrint("❌ Error fetching dashboard data: $e");
      setState(() {
        _isLoading = false;
        _isLoadingMore = false;
        _errorMessage = "Failed to load data: ${e.toString()}";
      });
    }
  }

  // ==================== LOAD MORE TRANSACTIONS ====================
  Future<void> _loadMoreTransactions() async {
    if (_isLoadingMore) return;
    if (_currentPage >= _pagination['totalPages']) return;

    setState(() {
      _isLoadingMore = true;
    });

    try {
      await _fetchDashboardData(page: _currentPage + 1);
    } catch (e) {
      debugPrint("❌ Error loading more: $e");
    } finally {
      setState(() {
        _isLoadingMore = false;
      });
    }
  }

  // ==================== APPLY FILTERS ====================
  void _applyFiltersAndFetch({bool showNotification = true}) async {
    setState(() {
      _isLoading = true;
      _currentPage = 1;
    });

    try {
      await _fetchDashboardData(page: 1);
      if (showNotification) {
        final filterLabel = _getActiveFilterLabel();
        _showToastNotification('✓ $filterLabel', isError: false);
      }
    } catch (e) {
      debugPrint("❌ Error applying filters: $e");
      _showToastNotification('Error: ${e.toString()}', isError: true);
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  String _getActiveFilterLabel() {
    final timeLabel = _getTimeFilterLabel(_selectedTimeFilter);
    final serviceLabel = _getServiceLabel(_selectedService);
    final statusLabel = _getStatusLabel(_selectedStatus);

    if (_selectedTimeFilter == 'all' &&
        _selectedService == 'all' &&
        _selectedStatus == 'all') {
      return 'All filters cleared';
    }

    String label = 'Filters applied: ';
    List<String> parts = [];
    if (_selectedTimeFilter != 'all') parts.add(timeLabel);
    if (_selectedService != 'all') parts.add(serviceLabel);
    if (_selectedStatus != 'all') parts.add(statusLabel);
    if (_searchQuery.isNotEmpty) parts.add('"$_searchQuery"');

    return label + parts.join(' + ');
  }

  void _clearAllFilters() {
    setState(() {
      _selectedService = 'all';
      _selectedStatus = 'all';
      _selectedTimeFilter = 'all';
      _searchQuery = '';
      _selectedUserType = 'All';
      _selectedSortBy = 'Newest';
      _minAmountController.clear();
      _maxAmountController.clear();
      _isDateRangeSelected = false;
      _selectedDateRange = null;
      _searchController.clear();
      _currentPage = 1;
    });
    _applyFiltersAndFetch();
  }

  bool _hasActiveFilters() {
    return _selectedService != 'all' ||
        _selectedStatus != 'all' ||
        _searchQuery.isNotEmpty ||
        _selectedUserType != 'All' ||
        _selectedSortBy != 'Newest' ||
        _minAmountController.text.isNotEmpty ||
        _maxAmountController.text.isNotEmpty ||
        _isDateRangeSelected ||
        _selectedTimeFilter != 'all';
  }

  // ==================== SORTING ====================
  void _applySorting() {
    List<dynamic> sorted = List.from(_transactions);

    switch (_selectedSortBy) {
      case 'Newest':
        sorted.sort((a, b) {
          final dateA = _parseDateTime((a as Map)['createdAt']);
          final dateB = _parseDateTime((b as Map)['createdAt']);
          return dateB.compareTo(dateA);
        });
        break;
      case 'Oldest':
        sorted.sort((a, b) {
          final dateA = _parseDateTime((a as Map)['createdAt']);
          final dateB = _parseDateTime((b as Map)['createdAt']);
          return dateA.compareTo(dateB);
        });
        break;
      case 'Highest Amount':
        sorted.sort((a, b) {
          final amountA = ((a as Map)['amount'] as num?)?.toDouble() ?? 0;
          final amountB = ((b as Map)['amount'] as num?)?.toDouble() ?? 0;
          return amountB.compareTo(amountA);
        });
        break;
      case 'Lowest Amount':
        sorted.sort((a, b) {
          final amountA = ((a as Map)['amount'] as num?)?.toDouble() ?? 0;
          final amountB = ((b as Map)['amount'] as num?)?.toDouble() ?? 0;
          return amountA.compareTo(amountB);
        });
        break;
    }

    setState(() {
      _filteredTransactions = sorted;
    });
  }

  // ==================== HELPERS ====================

  String _getTransactionType(Map<String, dynamic> tx) {
    final desc = (tx['description'] as String?)?.toLowerCase() ?? '';
    final type = (tx['type'] as String?)?.toLowerCase() ?? '';
    final isCommission = tx['isCommission'] == true;

    if (isCommission || type.contains('commission')) return 'Commission Credit';
    if (desc.contains('international airtime')) return 'International Airtime';
    if (desc.contains('electricity')) return 'Electricity Purchase';
    if (desc.contains('airtime')) return 'Airtime Purchase';
    if (desc.contains('data') || desc.contains('gb')) return 'Data Purchase';
    if (desc.contains('dstv') ||
        desc.contains('gotv') ||
        desc.contains('cable')) {
      return 'Cable TV Purchase';
    }
    if (desc.contains('education')) return 'Education Purchase';
    if (desc.contains('insurance')) return 'Insurance Purchase';
    if (desc.contains('transfer')) return 'Transfer';
    if (desc.contains('fund') || desc.contains('wallet')) return 'Fund Wallet';
    return type.isNotEmpty
        ? type[0].toUpperCase() + type.substring(1)
        : 'Other';
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

  Color _getStatusColor(String status) {
    final s = status.toLowerCase();
    if (s.contains('success') || s.contains('completed')) return successColor;
    if (s.contains('pending') || s.contains('processing')) return warningColor;
    if (s.contains('failed') || s.contains('cancelled')) return errorColor;
    return Colors.grey;
  }

  // ==================== FIXED: Format currency without Naira symbol issues ====================
  String _formatCurrency(double amount) {
    // Use 'NGN' instead of '₦' to avoid font issues
    return 'NGN ${NumberFormat('#,##0.00').format(amount)}';
  }

  String _formatNumber(int count) {
    return NumberFormat('#,##0').format(count);
  }

  String _getServiceLabel(String value) {
    for (var option in _serviceFilterOptions) {
      if (option['value'] == value) {
        return option['label'] ?? value;
      }
    }
    return value;
  }

  String _getStatusLabel(String value) {
    for (var option in _statusFilterOptions) {
      if (option['value'] == value) {
        return option['label'] ?? value;
      }
    }
    return value;
  }

  String _getTimeFilterLabel(String value) {
    for (var option in _timeFilterOptions) {
      if (option['value'] == value) {
        return option['label'] ?? value;
      }
    }
    return value;
  }

  Future<void> _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _selectedDateRange,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
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
      _applyFiltersAndFetch();
    }
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
              'ADMIN PANEL',
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
      title: "Transactions",
      icon: Icons.receipt,
      page: SizedBox.shrink(),
      isAdminOnly: true,
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
        MaterialPageRoute(builder: (_) => const DashboardScreen()),
      );
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

  // ==================== BUILD UI ====================

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    if (_isLoading && _transactions.isEmpty) {
      return _buildShimmerSkeleton(isMobile);
    }

    if (_errorMessage != null && _transactions.isEmpty) {
      return _buildErrorView(isMobile);
    }

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Colors.grey.shade50,
      drawer: CustomDrawer(
        header: _buildDrawerHeader(),
        items: _drawerItems,
        selectedItem: _drawerItems.firstWhere(
          (item) => item.title == "Transactions",
          orElse: () => _drawerItems.first,
        ),
        onItemSelected: _onDrawerItemSelected,
        isAdmin: true,
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadData,
          color: primaryColor,
          child: CustomScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(child: _buildHeader(isMobile)),
              SliverToBoxAdapter(child: _buildStatisticsSection(isMobile)),
              SliverToBoxAdapter(child: _buildStatusSection(isMobile)),
              SliverToBoxAdapter(child: _buildFiltersToggle(isMobile)),
              if (_showAdvancedFilters)
                SliverToBoxAdapter(child: _buildAdvancedFilters(isMobile)),
              if (_filteredTransactions.isEmpty && !_isLoading)
                SliverFillRemaining(
                  hasScrollBody: false,
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
                              color: primaryColor.withValues(alpha: 0.08),
                              shape: BoxShape.circle,
                            ),
                            child: HugeIcon(
                              icon: HugeIcons.strokeRoundedReceiptText,
                              color: primaryColor,
                              size: isMobile ? 40 : 50,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No Transactions Found',
                            style: GoogleFonts.poppins(
                              fontSize: isMobile ? 20 : 24,
                              fontWeight: FontWeight.w700,
                              color: textPrimary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _hasActiveFilters()
                                ? 'Try adjusting your filters or search'
                                : 'No transactions available',
                            style: GoogleFonts.inter(
                              fontSize: isMobile ? 14 : 16,
                              color: textSecondary,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          if (_hasActiveFilters()) ...[
                            const SizedBox(height: 12),
                            TextButton.icon(
                              onPressed: _clearAllFilters,
                              icon: const Icon(
                                Icons.clear_all_rounded,
                                size: 18,
                              ),
                              label: const Text('Clear All Filters'),
                              style: TextButton.styleFrom(
                                foregroundColor: primaryColor,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 10,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  side: BorderSide(
                                    color: primaryColor.withValues(alpha: 0.2),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                )
              else if (_filteredTransactions.isNotEmpty)
                SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    if (index >= _filteredTransactions.length) {
                      return const SizedBox.shrink();
                    }
                    final tx = _filteredTransactions[index];
                    if (tx is! Map<String, dynamic>) {
                      return const SizedBox.shrink();
                    }
                    return _buildTransactionCard(tx, isMobile);
                  }, childCount: _filteredTransactions.length),
                ),
              if (_filteredTransactions.isNotEmpty &&
                  _currentPage < _pagination['totalPages'])
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      vertical: isMobile ? 16 : 24,
                      horizontal: isMobile ? 16 : 24,
                    ),
                    child: Center(
                      child:
                          _isLoadingMore
                              ? const CircularProgressIndicator()
                              : TextButton(
                                onPressed: _loadMoreTransactions,
                                child: const Text('Load More'),
                              ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      // ==================== FIXED: FAB with scroll visibility ====================
      floatingActionButton:
          _filteredTransactions.isNotEmpty && !_isLoading
              ? AnimatedOpacity(
                opacity: _isFabVisible ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Export options (visible when expanded)
                    if (_isExportMenuOpen) ...[
                      _buildFloatingExportOption(
                        icon: HugeIcons.strokeRoundedFile01,
                        label: 'PDF',
                        color: Colors.red.shade700,
                        onTap: () {
                          setState(() => _isExportMenuOpen = false);
                          _exportToPdf();
                        },
                        isMobile: isMobile,
                      ),
                      const SizedBox(height: 8),
                      _buildFloatingExportOption(
                        icon: HugeIcons.strokeRoundedGridTable,
                        label: 'Excel',
                        color: Colors.green.shade700,
                        onTap: () {
                          setState(() => _isExportMenuOpen = false);
                          _exportToExcel();
                        },
                        isMobile: isMobile,
                      ),
                      const SizedBox(height: 12),
                    ],
                    // Main FAB
                    FloatingActionButton(
                      onPressed: () {
                        setState(() {
                          _isExportMenuOpen = !_isExportMenuOpen;
                        });
                      },
                      backgroundColor:
                          _isExportMenuOpen
                              ? Colors.grey.shade700
                              : primaryColor,
                      foregroundColor: Colors.white,
                      elevation: 6,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(isMobile ? 12 : 16),
                      ),
                      child: HugeIcon(
                        icon:
                            _isExportMenuOpen
                                ? HugeIcons.strokeRoundedCancel02
                                : HugeIcons.strokeRoundedDownload01,
                        color: Colors.white,
                        size: isMobile ? 22 : 26,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: primaryColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Export',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              )
              : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  // ==================== FLOATING EXPORT OPTION ====================
  Widget _buildFloatingExportOption({
    required dynamic icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    required bool isMobile,
  }) {
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 250),
      tween: Tween(begin: 0.0, end: 1.0),
      curve: Curves.easeOut,
      builder: (context, value, child) {
        return Transform.scale(
          scale: value,
          child: Opacity(
            opacity: value,
            child: Container(
              width: isMobile ? 48 : 54,
              height: isMobile ? 48 : 54,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(27),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        HugeIcon(
                          icon: icon,
                          color: color,
                          size: isMobile ? 18 : 22,
                        ),
                        Text(
                          label,
                          style: GoogleFonts.inter(
                            fontSize: isMobile ? 7 : 8,
                            fontWeight: FontWeight.w600,
                            color: color,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ==================== UI COMPONENTS ====================

  Widget _buildHeader(bool isMobile) {
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
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Admin / Transactions',
                  style: GoogleFonts.inter(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: isMobile ? 12 : 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              // 🔔 Admin alerts bell
              FutureBuilder<int>(
                future: ApiService.getAdminUnreadCount(),
                builder: (context, snapshot) {
                  final unread = snapshot.data ?? 0;
                  return GestureDetector(
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const AdminNotificationsPage(),
                        ),
                      );
                      setState(() {});
                    },
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.notifications_active_rounded,
                            color: Colors.white,
                            size: isMobile ? 20 : 22,
                          ),
                        ),
                        if (unread > 0)
                          Positioned(
                            right: -2,
                            top: -2,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.red,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: Colors.white,
                                  width: 1.5,
                                ),
                              ),
                              child: Text(
                                unread > 99 ? '99+' : '$unread',
                                style: GoogleFonts.inter(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(width: 8),
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
          const SizedBox(height: 16),
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
                  Icons.receipt_long_rounded,
                  color: primaryColor,
                  size: isMobile ? 28 : 34,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'All Transactions',
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: isMobile ? 20 : 28,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_filteredTransactions.length} of ${_pagination['total']} transactions',
                      style: GoogleFonts.inter(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: isMobile ? 12 : 14,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: _loadData,
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
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Container(
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
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          onSubmitted: (_) {
                            _searchQuery = _searchController.text;
                            _applyFiltersAndFetch();
                          },
                          decoration: InputDecoration(
                            hintText:
                                isMobile
                                    ? 'Search...'
                                    : 'Search by name, email, ID, phone...',
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
                            _applyFiltersAndFetch();
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
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: isMobile ? 44 : 100,
                height: isMobile ? 44 : 48,
                child: ElevatedButton(
                  onPressed: () {
                    _searchQuery = _searchController.text;
                    _applyFiltersAndFetch();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                    minimumSize: Size.zero,
                  ),
                  child:
                      isMobile
                          ? HugeIcon(
                            icon: HugeIcons.strokeRoundedSearch01,
                            color: Colors.white,
                            size: 22,
                          )
                          : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              HugeIcon(
                                icon: HugeIcons.strokeRoundedSearch01,
                                color: Colors.white,
                                size: 18,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Search',
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ==================== STATISTICS SECTION ====================

  Widget _buildStatisticsSection(bool isMobile) {
    final allTime = _periodStats['allTime'] ?? {'count': 0, 'amount': 0.0};
    final today = _periodStats['today'] ?? {'count': 0, 'amount': 0.0};
    final week = _periodStats['week'] ?? {'count': 0, 'amount': 0.0};
    final month = _periodStats['month'] ?? {'count': 0, 'amount': 0.0};
    final year = _periodStats['year'] ?? {'count': 0, 'amount': 0.0};

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 16 : 24,
        vertical: isMobile ? 12 : 16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // All Time Total Card
          Container(
            padding: EdgeInsets.all(isMobile ? 14 : 20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [primaryColor, primaryColor.withValues(alpha: 0.8)],
              ),
              borderRadius: BorderRadius.circular(isMobile ? 14 : 18),
              boxShadow: [
                BoxShadow(
                  color: primaryColor.withValues(alpha: 0.3),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'All Time Total',
                      style: GoogleFonts.inter(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: isMobile ? 12 : 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatCurrency(allTime['amount'] ?? 0.0),
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: isMobile ? 22 : 30,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_formatNumber(allTime['count'] ?? 0)} Transactions',
                      style: GoogleFonts.inter(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: isMobile ? 11 : 13,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: EdgeInsets.all(isMobile ? 8 : 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: HugeIcon(
                    icon: HugeIcons.strokeRoundedMoney01,
                    color: Colors.white,
                    size: isMobile ? 24 : 32,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Period Stats Grid
          LayoutBuilder(
            builder: (context, constraints) {
              final cardWidth =
                  isMobile
                      ? constraints.maxWidth - 4
                      : (constraints.maxWidth - 12) / 2 - 4;
              return Wrap(
                spacing: isMobile ? 0 : 12,
                runSpacing: isMobile ? 8 : 12,
                children: [
                  _buildPeriodCard(
                    title: 'Today',
                    count: today['count'] ?? 0,
                    amount: today['amount'] ?? 0.0,
                    color: primaryColor,
                    icon: HugeIcons.strokeRoundedCalendar01,
                    isMobile: isMobile,
                    width: cardWidth,
                  ),
                  _buildPeriodCard(
                    title: 'This Week',
                    count: week['count'] ?? 0,
                    amount: week['amount'] ?? 0.0,
                    color: secondaryColor,
                    icon: HugeIcons.strokeRoundedCalendar02,
                    isMobile: isMobile,
                    width: cardWidth,
                  ),
                  _buildPeriodCard(
                    title: 'This Month',
                    count: month['count'] ?? 0,
                    amount: month['amount'] ?? 0.0,
                    color: Colors.orange.shade700,
                    icon: HugeIcons.strokeRoundedCalendar03,
                    isMobile: isMobile,
                    width: cardWidth,
                  ),
                  _buildPeriodCard(
                    title: 'This Year',
                    count: year['count'] ?? 0,
                    amount: year['amount'] ?? 0.0,
                    color: Colors.purple.shade700,
                    icon: HugeIcons.strokeRoundedCalendar04,
                    isMobile: isMobile,
                    width: cardWidth,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPeriodCard({
    required String title,
    required int count,
    required double amount,
    required Color color,
    required dynamic icon,
    required bool isMobile,
    required double width,
  }) {
    return SizedBox(
      width: width,
      child: Container(
        padding: EdgeInsets.all(isMobile ? 10 : 14),
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                HugeIcon(icon: icon, color: color, size: isMobile ? 14 : 16),
                const SizedBox(width: 4),
                Text(
                  title,
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
              _formatCurrency(amount),
              style: GoogleFonts.poppins(
                fontSize: isMobile ? 16 : 20,
                fontWeight: FontWeight.w700,
                color: color,
                height: 1.1,
              ),
            ),
            Text(
              '${_formatNumber(count)} transactions',
              style: GoogleFonts.inter(
                fontSize: isMobile ? 10 : 12,
                fontWeight: FontWeight.w500,
                color: textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== STATUS SUMMARY ====================
  Widget _buildStatusSection(bool isMobile) {
    final serviceLabel = _getServiceLabel(_selectedService);
    final isFiltered = _hasActiveFilters();

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
                'Status Summary — $serviceLabel',
                style: GoogleFonts.inter(
                  fontSize: isMobile ? 12 : 14,
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
                  color:
                      isFiltered
                          ? primaryColor.withValues(alpha: 0.1)
                          : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  border:
                      isFiltered
                          ? Border.all(
                            color: primaryColor.withValues(alpha: 0.2),
                          )
                          : null,
                ),
                child: Text(
                  isFiltered ? '• Filtered View' : '• All Time',
                  style: GoogleFonts.inter(
                    fontSize: isMobile ? 9 : 11,
                    fontWeight: FontWeight.w500,
                    color: isFiltered ? primaryColor : textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: EdgeInsets.all(isMobile ? 10 : 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(isMobile ? 10 : 12),
              border: Border.all(color: Colors.grey.shade200),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatusItem(
                  label: 'Success',
                  count: _statusSummary['success'] ?? 0,
                  color: successColor,
                  isMobile: isMobile,
                ),
                _buildStatusItem(
                  label: 'Pending',
                  count: _statusSummary['pending'] ?? 0,
                  color: warningColor,
                  isMobile: isMobile,
                ),
                _buildStatusItem(
                  label: 'Failed',
                  count: _statusSummary['failed'] ?? 0,
                  color: errorColor,
                  isMobile: isMobile,
                ),
                _buildStatusItem(
                  label: 'Total',
                  count: _statusSummary['total'] ?? 0,
                  color: primaryColor,
                  isMobile: isMobile,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusItem({
    required String label,
    required int count,
    required Color color,
    required bool isMobile,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          _formatNumber(count),
          style: GoogleFonts.inter(
            fontSize: isMobile ? 12 : 14,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        Text(
          ' $label',
          style: GoogleFonts.inter(
            fontSize: isMobile ? 10 : 11,
            color: textSecondary,
          ),
        ),
      ],
    );
  }

  // ==================== FILTERS UI ====================

  Widget _buildFiltersToggle(bool isMobile) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 16 : 24,
        vertical: isMobile ? 4 : 8,
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap:
                () => setState(
                  () => _showAdvancedFilters = !_showAdvancedFilters,
                ),
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: isMobile ? 12 : 16,
                vertical: isMobile ? 6 : 10,
              ),
              decoration: BoxDecoration(
                color:
                    _showAdvancedFilters
                        ? primaryColor.withValues(alpha: 0.1)
                        : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color:
                      _showAdvancedFilters ? primaryColor : Colors.transparent,
                ),
              ),
              child: Row(
                children: [
                  HugeIcon(
                    icon: HugeIcons.strokeRoundedFilterHorizontal,
                    color: _showAdvancedFilters ? primaryColor : textSecondary,
                    size: isMobile ? 16 : 18,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Filters',
                    style: GoogleFonts.inter(
                      fontSize: isMobile ? 12 : 13,
                      fontWeight: FontWeight.w500,
                      color:
                          _showAdvancedFilters ? primaryColor : textSecondary,
                    ),
                  ),
                  if (_hasActiveFilters()) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: primaryColor,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '!',
                        style: GoogleFonts.inter(
                          fontSize: 8,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ],
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
                  horizontal: 12,
                  vertical: 6,
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
    );
  }

  Widget _buildAdvancedFilters(bool isMobile) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 24),
      padding: EdgeInsets.all(isMobile ? 12 : 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildDropdown(
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
              _applyFiltersAndFetch();
            },
            isMobile: isMobile,
          ),
          const SizedBox(height: 10),

          Row(
            children: [
              Expanded(
                child: _buildDropdown(
                  label: 'Service',
                  value: _selectedService,
                  items: _serviceFilterOptions,
                  onChanged: (v) {
                    setState(() => _selectedService = v);
                    _applyFiltersAndFetch();
                  },
                  isMobile: isMobile,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildDropdown(
                  label: 'Status',
                  value: _selectedStatus,
                  items: _statusFilterOptions,
                  onChanged: (v) {
                    setState(() => _selectedStatus = v);
                    _applyFiltersAndFetch();
                  },
                  isMobile: isMobile,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          if (_selectedTimeFilter == 'custom') _buildDateRangePicker(isMobile),
          if (_selectedTimeFilter == 'custom') const SizedBox(height: 10),

          Row(
            children: [
              Expanded(
                child: _buildAmountField(
                  controller: _minAmountController,
                  label: 'Min Amount',
                  isMobile: isMobile,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildAmountField(
                  controller: _maxAmountController,
                  label: 'Max Amount',
                  isMobile: isMobile,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          Row(
            children: [
              Expanded(
                child: _buildDropdown(
                  label: 'User Type',
                  value: _selectedUserType,
                  items: const [
                    {'label': 'All', 'value': 'All'},
                    {'label': 'Admin', 'value': 'Admin'},
                    {'label': 'User', 'value': 'User'},
                  ],
                  onChanged: (v) {
                    setState(() => _selectedUserType = v);
                    _applyFiltersAndFetch();
                  },
                  isMobile: isMobile,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildDropdown(
                  label: 'Sort By',
                  value: _selectedSortBy,
                  items: const [
                    {'label': 'Newest', 'value': 'Newest'},
                    {'label': 'Oldest', 'value': 'Oldest'},
                    {'label': 'Highest Amount', 'value': 'Highest Amount'},
                    {'label': 'Lowest Amount', 'value': 'Lowest Amount'},
                  ],
                  onChanged: (v) {
                    setState(() => _selectedSortBy = v);
                    _applyFiltersAndFetch();
                  },
                  isMobile: isMobile,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => _applyFiltersAndFetch(),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  HugeIcon(
                    icon: HugeIcons.strokeRoundedCheckmarkCircle01,
                    color: Colors.white,
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Apply Filters',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w600,
                      fontSize: isMobile ? 12 : 13,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdown({
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
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: textSecondary,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: backgroundLight,
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
                    child: Text(item['label'] ?? item['value'] ?? ''),
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
        Text(
          'Date Range',
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: textSecondary,
          ),
        ),
        const SizedBox(height: 4),
        InkWell(
          onTap: _selectDateRange,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color:
                  _isDateRangeSelected
                      ? primaryColor.withValues(alpha: 0.05)
                      : backgroundLight,
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
                      });
                      _applyFiltersAndFetch();
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

  Widget _buildAmountField({
    required TextEditingController controller,
    required String label,
    required bool isMobile,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: textSecondary,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          decoration: BoxDecoration(
            color: backgroundLight,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              prefixIcon: Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  'NGN',
                  style: GoogleFonts.inter(
                    fontSize: isMobile ? 10 : 12,
                    fontWeight: FontWeight.w600,
                    color: textSecondary,
                  ),
                ),
              ),
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 8,
                vertical: isMobile ? 6 : 8,
              ),
              hintText: '0.00',
              hintStyle: GoogleFonts.inter(
                fontSize: isMobile ? 11 : 12,
                color: Colors.grey.shade400,
              ),
            ),
            style: GoogleFonts.inter(
              fontSize: isMobile ? 12 : 13,
              color: textPrimary,
            ),
          ),
        ),
      ],
    );
  }

  // ==================== TRANSACTION CARD ====================

  Widget _buildTransactionCard(Map<String, dynamic> tx, bool isMobile) {
    final type = _getTransactionType(tx);
    final amount = (tx['amount'] as num?)?.toDouble() ?? 0.0;
    final status = tx['status'] as String? ?? 'N/A';
    final date = _parseDateTime(tx['createdAt']);
    final user = tx['user'] as Map<String, dynamic>?;
    final userName = user?['fullName'] as String? ?? 'Unknown';
    final userEmail = user?['email'] as String? ?? '';
    final ref = tx['reference'] as String? ?? 'N/A';
    final isCredit =
        type == 'Fund Wallet' ||
        type == 'Commission Credit' ||
        tx['isCommission'] == true;

    return FadeTransition(
      opacity: _fadeAnimation,
      child: Container(
        margin: EdgeInsets.symmetric(
          horizontal: isMobile ? 16 : 24,
          vertical: 4,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(isMobile ? 12 : 14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
          border: Border.all(color: Colors.grey.shade100),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(isMobile ? 12 : 14),
            onTap: () => _showTransactionDetails(tx),
            child: Padding(
              padding: EdgeInsets.all(isMobile ? 12 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.only(right: 10),
                        decoration: BoxDecoration(
                          color: _getStatusColor(status),
                          shape: BoxShape.circle,
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              type,
                              style: GoogleFonts.inter(
                                fontSize: isMobile ? 13 : 14,
                                fontWeight: FontWeight.w600,
                                color: textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              'Ref: ${ref.length > 20 ? ref.substring(0, 20) : ref}',
                              style: GoogleFonts.inter(
                                fontSize: isMobile ? 10 : 11,
                                color: textSecondary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
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
                              fontSize: isMobile ? 14 : 16,
                              fontWeight: FontWeight.w700,
                              color: isCredit ? successColor : textPrimary,
                            ),
                          ),
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: isMobile ? 6 : 8,
                              vertical: isMobile ? 1 : 2,
                            ),
                            decoration: BoxDecoration(
                              color: _getStatusColor(
                                status,
                              ).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              status,
                              style: GoogleFonts.inter(
                                fontSize: isMobile ? 8 : 10,
                                fontWeight: FontWeight.w600,
                                color: _getStatusColor(status),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        userName,
                        style: GoogleFonts.inter(
                          fontSize: isMobile ? 11 : 12,
                          color: textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Row(
                        children: [
                          if (userEmail.isNotEmpty)
                            Text(
                              userEmail,
                              style: GoogleFonts.inter(
                                fontSize: isMobile ? 10 : 11,
                                color: textSecondary.withValues(alpha: 0.7),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          const SizedBox(width: 8),
                          Text(
                            DateFormat('dd/MM/yy HH:mm').format(date),
                            style: GoogleFonts.inter(
                              fontSize: isMobile ? 10 : 11,
                              color: textSecondary,
                            ),
                          ),
                        ],
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

  void _showTransactionDetails(Map<String, dynamic> tx) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    final type = _getTransactionType(tx);
    final amount = (tx['amount'] as num?)?.toStringAsFixed(2) ?? '0.00';
    final status = tx['status'] as String? ?? 'N/A';
    final ref = tx['reference'] as String? ?? 'N/A';
    final date = _parseDateTime(tx['createdAt']);
    final desc = tx['description'] as String? ?? 'No description';
    final txId = tx['transactionId'] ?? tx['_id'] ?? 'N/A';
    final user = tx['user'] as Map<String, dynamic>?;
    final userName = user?['fullName'] as String? ?? 'Unknown User';
    final userEmail = user?['email'] as String? ?? 'No email';
    final userPhone = user?['phone'] as String? ?? 'N/A';
    final userId = user?['_id']?.toString() ?? 'N/A';
    final phone = tx['phone'] as String?;
    final metadata = tx['metadata'] as Map<String, dynamic>?;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder:
          (_) => Dialog(
            insetPadding: EdgeInsets.all(isMobile ? 16 : 24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: ReceiptWidget(
              transactionType: type,
              amount: amount,
              status: status,
              transactionId: txId.toString(),
              reference: ref,
              date: date,
              phoneNumber: phone,
              mobileOperator: null,
              isCommission: tx['isCommission'] == true,
              commissionSource: tx['commissionSource'] as String?,
              isService: tx['serviceFee'] != null,
              description: desc,
              balanceBefore: (tx['balanceBefore'] as num?)?.toStringAsFixed(2),
              balanceAfter: (tx['balanceAfter'] as num?)?.toStringAsFixed(2),
              gateway: tx['gateway'] as String?,
              primaryColor: primaryColor,
              showWatermark: false,
              packageVariationCode: metadata?['variation_code'] as String?,
              electricityToken: metadata?['token'] as String?,
              customerName: userName,
              customerAddress: userEmail,
              customerPhone: userPhone,
              customerUserId: userId,
              isAdminTransaction:
                  tx['isAdminPerformed'] == true ||
                  (tx['type'] as String?) == 'Admin Wallet Credit' ||
                  (tx['type'] as String?) == 'Admin Wallet Debit',
              adminNote:
                  tx['isAdminPerformed'] == true
                      ? '🔧 ADMIN TRANSACTION'
                      : null,
              isUserAdmin: user?['isAdmin'] == true,

              // ✅ NEW: Pass the admin action data from metadata
              adminReason: metadata?['reason']?.toString(),
              adminReference:
                  metadata?['reference']?.toString() ??
                  (tx['reference'] as String?),
              adminTransactionNote: metadata?['note']?.toString(),
              adminPerformerName: metadata?['adminName']?.toString(),
              adminPerformerEmail: metadata?['adminEmail']?.toString(),
            ),
          ),
    );
  }

  // ==================== EXPORT FUNCTIONS ====================

  Future<void> _exportToExcel() async {
    try {
      _showToastNotification('📊 Generating Excel...', isError: false);

      final excel = xl.Excel.createExcel();
      excel.rename('Sheet1', 'Transactions');
      final sheet = excel['Transactions'];

      final headers = [
        'S/N',
        'Transaction Type',
        'Amount (NGN)',
        'Status',
        'Reference',
        'User Name',
        'User Email',
        'User Phone',
        'Date',
        'Description',
      ];

      for (int col = 0; col < headers.length; col++) {
        final cellIndex = xl.CellIndex.indexByColumnRow(
          columnIndex: col,
          rowIndex: 0,
        );
        sheet.cell(cellIndex)
          ..value = xl.TextCellValue(headers[col])
          ..cellStyle = xl.CellStyle(
            bold: true,
            backgroundColorHex: xl.ExcelColor.fromHexString('#243889'),
            fontColorHex: xl.ExcelColor.fromHexString('#FFFFFF'),
            horizontalAlign: xl.HorizontalAlign.Center,
          );
      }

      for (int row = 0; row < _filteredTransactions.length; row++) {
        final tx = _filteredTransactions[row];
        if (tx is! Map<String, dynamic>) continue;

        final user = tx['user'] as Map<String, dynamic>?;
        final data = [
          (row + 1).toString(),
          _getTransactionType(tx),
          (tx['amount'] as num?)?.toStringAsFixed(2) ?? '0.00',
          tx['status']?.toString() ?? 'N/A',
          tx['reference']?.toString() ?? 'N/A',
          user?['fullName']?.toString() ?? 'Unknown User',
          user?['email']?.toString() ?? 'N/A',
          user?['phone']?.toString() ?? 'N/A',
          _formatDate(_parseDateTime(tx['createdAt'])),
          tx['description']?.toString() ?? '',
        ];

        for (int col = 0; col < data.length; col++) {
          final cellIndex = xl.CellIndex.indexByColumnRow(
            columnIndex: col,
            rowIndex: row + 1,
          );
          sheet.cell(cellIndex).value = xl.TextCellValue(data[col].toString());
        }
      }

      for (int col = 0; col < headers.length; col++) {
        sheet.setColumnWidth(col, 20);
      }

      final List<int>? fileBytes = excel.save();
      if (fileBytes == null) {
        _showToastNotification('Failed to generate Excel file', isError: true);
        return;
      }

      final Uint8List uint8Bytes = Uint8List.fromList(fileBytes);

      await Share.shareXFiles([
        XFile.fromData(
          uint8Bytes,
          mimeType:
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          name: 'dalabapay_transactions_report.xlsx',
        ),
      ], text: '📊 Dalabapay Transactions Report');

      _showToastNotification('✅ Excel exported successfully!', isError: false);
    } catch (e) {
      _showToastNotification(
        'Error exporting Excel: ${e.toString()}',
        isError: true,
      );
    }
  }

  Future<void> _exportToPdf() async {
    try {
      _showToastNotification('📄 Generating PDF...', isError: false);

      final pdf = pw.Document();

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          build: (pw.Context context) {
            return [
              pw.Header(
                level: 0,
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'Dalabapay',
                          style: pw.TextStyle(
                            fontSize: 24,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColor.fromInt(0xFF243889),
                          ),
                        ),
                        pw.Text(
                          'Transactions Report',
                          style: pw.TextStyle(
                            fontSize: 16,
                            color: PdfColors.grey700,
                          ),
                        ),
                      ],
                    ),
                    pw.Text(
                      DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now()),
                      style: pw.TextStyle(color: PdfColors.grey700),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 20),

              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  color: PdfColor.fromInt(0xFFF8FAFC),
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                  children: [
                    _buildPdfStat(
                      'Total Amount',
                      'NGN ${_periodStats['allTime']?['amount']?.toStringAsFixed(2) ?? '0.00'}',
                    ),
                    _buildPdfStat(
                      'Successful',
                      _statusSummary['success'].toString(),
                    ),
                    _buildPdfStat(
                      'Pending',
                      _statusSummary['pending'].toString(),
                    ),
                    _buildPdfStat(
                      'Failed',
                      _statusSummary['failed'].toString(),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 20),

              pw.Table(
                border: pw.TableBorder.all(
                  color: PdfColors.grey300,
                  width: 0.5,
                ),
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(
                      color: PdfColor.fromInt(0xFF243889),
                    ),
                    children:
                        [
                              '#',
                              'Type',
                              'Amount',
                              'Status',
                              'User',
                              'Reference',
                              'Date',
                            ]
                            .map(
                              (header) => pw.Padding(
                                padding: const pw.EdgeInsets.all(6),
                                child: pw.Text(
                                  header,
                                  style: pw.TextStyle(
                                    fontSize: 9,
                                    fontWeight: pw.FontWeight.bold,
                                    color: PdfColors.white,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                  ),
                  ..._filteredTransactions.map((tx) {
                    if (tx is! Map<String, dynamic>) {
                      return pw.TableRow(children: []);
                    }
                    final user = tx['user'] as Map<String, dynamic>?;
                    final reference = tx['reference']?.toString() ?? 'N/A';
                    final refText =
                        reference.length > 12
                            ? reference.substring(0, 12)
                            : reference;

                    return pw.TableRow(
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text(
                            (_filteredTransactions.indexOf(tx) + 1).toString(),
                            style: const pw.TextStyle(fontSize: 8),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text(
                            _getTransactionType(tx),
                            style: const pw.TextStyle(fontSize: 8),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text(
                            'NGN ${(tx['amount'] as num?)?.toStringAsFixed(2) ?? '0.00'}',
                            style: pw.TextStyle(
                              fontSize: 8,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text(
                            tx['status']?.toString() ?? 'N/A',
                            style: pw.TextStyle(
                              fontSize: 8,
                              color: _getStatusColorPdf(
                                tx['status']?.toString() ?? '',
                              ),
                            ),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text(
                            user?['fullName']?.toString() ?? 'Unknown User',
                            style: const pw.TextStyle(fontSize: 8),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text(
                            refText,
                            style: const pw.TextStyle(fontSize: 8),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text(
                            _formatDate(_parseDateTime(tx['createdAt'])),
                            style: const pw.TextStyle(fontSize: 8),
                          ),
                        ),
                      ],
                    );
                  }),
                ],
              ),
              pw.SizedBox(height: 20),

              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  color: PdfColor.fromInt(0xFFF8FAFC),
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Center(
                  child: pw.Text(
                    'Generated by Dalabapay • ${_filteredTransactions.length} transactions',
                    style: pw.TextStyle(color: PdfColors.grey700, fontSize: 10),
                  ),
                ),
              ),
            ];
          },
        ),
      );

      final pdfBytes = await pdf.save();

      await Share.shareXFiles([
        XFile.fromData(
          pdfBytes,
          mimeType: 'application/pdf',
          name: 'dalabapay_transactions_report.pdf',
        ),
      ], text: '📊 Dalabapay Transactions Report');

      _showToastNotification('✅ PDF exported successfully!', isError: false);
    } catch (e) {
      _showToastNotification(
        'Error exporting PDF: ${e.toString()}',
        isError: true,
      );
    }
  }

  pw.Widget _buildPdfStat(String label, String value) {
    return pw.Column(
      children: [
        pw.Text(
          value,
          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
        ),
        pw.Text(
          label,
          style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
        ),
      ],
    );
  }

  PdfColor _getStatusColorPdf(String status) {
    final statusLower = status.toLowerCase();
    if (statusLower.contains('success') || statusLower.contains('completed')) {
      return PdfColor.fromInt(0xFF219C7E);
    } else if (statusLower.contains('pending') ||
        statusLower.contains('processing')) {
      return PdfColor.fromInt(0xFFF59E0B);
    } else if (statusLower.contains('failed') ||
        statusLower.contains('cancelled')) {
      return PdfColor.fromInt(0xFFEF4444);
    }
    return PdfColors.grey;
  }

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
      return DateFormat('dd/MM/yyyy HH:mm').format(date);
    }
  }

  void _showExportOptions(bool isMobile) {
    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      backgroundColor: Colors.white,
      builder: (context) {
        return SafeArea(
          child: Container(
            padding: EdgeInsets.all(isMobile ? 16 : 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Export Options',
                  style: GoogleFonts.poppins(
                    fontSize: isMobile ? 18 : 20,
                    fontWeight: FontWeight.bold,
                    color: textPrimary,
                  ),
                ),
                const SizedBox(height: 16),
                _buildExportOption(
                  icon: HugeIcons.strokeRoundedFile01,
                  title: 'Export as PDF',
                  subtitle: 'Download all as PDF report',
                  onTap: () {
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
                    _exportToPdf();
                  },
                  isMobile: isMobile,
                ),
                const SizedBox(height: 8),
                _buildExportOption(
                  icon: HugeIcons.strokeRoundedGridTable,
                  title: 'Export as Excel',
                  subtitle: 'Download in Excel/CSV format',
                  onTap: () {
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
                    _exportToExcel();
                  },
                  isMobile: isMobile,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      backgroundColor: Colors.grey[100],
                    ),
                    child: Text(
                      'Cancel',
                      style: GoogleFonts.inter(
                        color: textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildExportOption({
    required dynamic icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required bool isMobile,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: EdgeInsets.all(isMobile ? 12 : 14),
        decoration: BoxDecoration(
          color: backgroundLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(isMobile ? 8 : 10),
              decoration: BoxDecoration(
                color: primaryColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: HugeIcon(
                icon: icon,
                color: primaryColor,
                size: isMobile ? 20 : 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      fontSize: isMobile ? 14 : 15,
                      fontWeight: FontWeight.w600,
                      color: textPrimary,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      fontSize: isMobile ? 12 : 13,
                      color: textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            HugeIcon(
              icon: HugeIcons.strokeRoundedArrowRight01,
              color: textSecondary,
              size: isMobile ? 14 : 16,
            ),
          ],
        ),
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
                    height: isMobile ? 120 : 140,
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
                    height: isMobile ? 90 : 110,
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
                  style: GoogleFonts.poppins(
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
