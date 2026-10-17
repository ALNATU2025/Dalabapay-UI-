// lib/presentation/screens/admin/admin_dashboard_home.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/services/api_service.dart';

// ==================== DATA MODELS ====================

class ChartData {
  final String x;
  final double y;

  ChartData({required this.x, required this.y});
}

class RevenueChartData {
  final String x;
  final double amount;

  RevenueChartData({required this.x, required this.amount});
}

class TransactionStatusData {
  final String status;
  final int count;
  final Color color;

  TransactionStatusData({
    required this.status,
    required this.count,
    required this.color,
  });
}

class RecentTransaction {
  final String id;
  final String type;
  final double amount;
  final String status;
  final String userName;
  final String userEmail;
  final String reference;
  final DateTime date;

  RecentTransaction({
    required this.id,
    required this.type,
    required this.amount,
    required this.status,
    required this.userName,
    required this.userEmail,
    required this.reference,
    required this.date,
  });
}

// ==================== MAIN WIDGET ====================

class AdminDashboardHome extends StatefulWidget {
  const AdminDashboardHome({super.key});

  @override
  State<AdminDashboardHome> createState() => _AdminDashboardHomeState();
}

class _AdminDashboardHomeState extends State<AdminDashboardHome>
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
  static const String _superAdminId = "690088325ca99bed6ab8d4a5";

  // ==================== STATE ====================
  bool _isLoading = true;
  bool _isRefreshing = false;
  bool _isSuperAdmin = false;
  String? _errorMessage;

  // ==================== STATISTICS ====================
  int _totalUsers = 0;
  int _activeUsers = 0;
  int _totalTransactions = 0;
  double _totalRevenue = 0.0;
  int _pendingCount = 0;
  int _successCount = 0;
  int _failedCount = 0;

  // ==================== PERIOD STATS ====================
  Map<String, dynamic> _periodStats = {
    'today': {'count': 0, 'amount': 0.0},
    'week': {'count': 0, 'amount': 0.0},
    'month': {'count': 0, 'amount': 0.0},
    'year': {'count': 0, 'amount': 0.0},
  };

  // ==================== CHART DATA ====================
  List<ChartData> _userGrowthData = [];
  List<RevenueChartData> _revenueData = [];
  List<TransactionStatusData> _statusData = [];
  List<RecentTransaction> _recentTransactions = [];

  // ==================== PAGINATION ====================
  int _currentPage = 1;
  int _totalPages = 1;
  int _totalItems = 0;
  bool _isLoadingMore = false;

  // ==================== ANIMATION ====================
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  // ==================== SCROLL CONTROLLER ====================
  final ScrollController _scrollController = ScrollController();

  // ==================== MOUNTED TRACKING ====================
  bool _isMounted = false;

  @override
  void initState() {
    super.initState();
    _isMounted = true;
    _setupAnimations();
    _loadCurrentUser();
    _loadDashboardData();

    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 200) {
        _loadMoreTransactions();
      }
    });
  }

  @override
  void dispose() {
    _isMounted = false;
    _animationController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ==================== SAFE SETSTATE ====================
  void _safeSetState(VoidCallback fn) {
    if (_isMounted && mounted) {
      setState(fn);
    }
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
    _animationController.forward();
  }

  // ==================== DATA LOADING ====================

  Future<void> _loadCurrentUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userDataString = prefs.getString('user');

      if (userDataString != null) {
        final userData = jsonDecode(userDataString);

        try {
          final roleResult = await ApiService.getUserRole();
          if (roleResult['success'] == true) {
            final data = roleResult['data'];
            final userRole = data?['role'] ?? 'user';
            final isSuperAdmin =
                data?['isSuperAdmin'] == true ||
                userRole == 'super_admin' ||
                userRole == 'superadmin' ||
                userData['_id'] == _superAdminId;

            _safeSetState(() {
              _isSuperAdmin = isSuperAdmin;
            });
            return;
          }
        } catch (e) {
          debugPrint('⚠️ Could not fetch role from backend: $e');
        }

        // Fallback
        _safeSetState(() {
          _isSuperAdmin = userData['_id'] == _superAdminId;
        });
      }
    } catch (e) {
      debugPrint('❌ Error loading user: $e');
    }
  }

  Future<void> _loadDashboardData() async {
    _safeSetState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Fetch all data in parallel
      final results = await Future.wait([
        ApiService.getAllUsersForAdmin(),
        ApiService.getAdminDashboard(timeFilter: 'all', page: 1, limit: 10),
        ApiService.getTransactions(),
      ]);

      final users = results[0] as List<dynamic>;
      final dashboardData = results[1] as Map<String, dynamic>;
      final transactions = results[2] as List<dynamic>;

      // Process users
      final totalUsers = users.length;
      final activeUsers = users.where((u) => u['isActive'] == true).length;

      // Process dashboard data
      Map<String, dynamic> periodStats = {
        'today': {'count': 0, 'amount': 0.0},
        'week': {'count': 0, 'amount': 0.0},
        'month': {'count': 0, 'amount': 0.0},
        'year': {'count': 0, 'amount': 0.0},
      };
      int successCount = 0;
      int pendingCount = 0;
      int failedCount = 0;
      int totalTransactions = 0;
      int totalPages = 1;
      int totalItems = 0;

      if (dashboardData['success'] == true) {
        final periodStatsRaw = dashboardData['periodStats'] ?? {};
        periodStats = {
          'today': {
            'count': periodStatsRaw['today']?['count'] ?? 0,
            'amount': (periodStatsRaw['today']?['amount'] ?? 0).toDouble(),
          },
          'week': {
            'count': periodStatsRaw['week']?['count'] ?? 0,
            'amount': (periodStatsRaw['week']?['amount'] ?? 0).toDouble(),
          },
          'month': {
            'count': periodStatsRaw['month']?['count'] ?? 0,
            'amount': (periodStatsRaw['month']?['amount'] ?? 0).toDouble(),
          },
          'year': {
            'count': periodStatsRaw['year']?['count'] ?? 0,
            'amount': (periodStatsRaw['year']?['amount'] ?? 0).toDouble(),
          },
        };

        final statusSummary = dashboardData['statusSummary'] ?? {};
        successCount = statusSummary['success'] ?? 0;
        pendingCount = statusSummary['pending'] ?? 0;
        failedCount = statusSummary['failed'] ?? 0;
        totalTransactions = statusSummary['total'] ?? 0;

        final pagination = dashboardData['pagination'] ?? {};
        totalPages = pagination['totalPages'] ?? 1;
        totalItems = pagination['total'] ?? 0;
      }

      // Process transactions for revenue
      double totalRevenue = 0.0;
      for (var tx in transactions) {
        final status = tx['status']?.toString().toLowerCase() ?? '';
        if (status == 'success' ||
            status == 'successful' ||
            status == 'completed') {
          totalRevenue += (tx['amount'] as num?)?.toDouble() ?? 0.0;
        }
      }

      // Generate chart data
      final userGrowthData = _generateChartData(transactions, users);
      final revenueData = _generateRevenueData(transactions);
      final statusData = _generateStatusDataList(
        successCount,
        pendingCount,
        failedCount,
      );
      final recentTransactions = _generateRecentTransactions(
        dashboardData['transactions'] ?? [],
      );

      _safeSetState(() {
        _totalUsers = totalUsers;
        _activeUsers = activeUsers;
        _totalRevenue = totalRevenue;
        _totalTransactions = totalTransactions;
        _successCount = successCount;
        _pendingCount = pendingCount;
        _failedCount = failedCount;
        _periodStats = periodStats;
        _totalPages = totalPages;
        _totalItems = totalItems;
        _userGrowthData = userGrowthData;
        _revenueData = revenueData;
        _statusData = statusData;
        _recentTransactions = recentTransactions;
        _isLoading = false;
      });

      debugPrint('✅ Dashboard data loaded successfully!');
      debugPrint('📊 Total Users: $totalUsers');
      debugPrint('💰 Total Revenue: $totalRevenue');
      debugPrint('📝 Total Transactions: $totalTransactions');
    } catch (e) {
      debugPrint('❌ Error loading dashboard: $e');
      _safeSetState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load dashboard data: ${e.toString()}';
      });
    }
  }

  // ==================== CHART DATA GENERATORS (PURE FUNCTIONS) ====================

  List<ChartData> _generateChartData(
    List<dynamic> transactions,
    List<dynamic> users,
  ) {
    final now = DateTime.now();
    final userGrowth = <ChartData>[];

    for (int i = 6; i >= 0; i--) {
      final date = now.subtract(Duration(days: i));
      final dayStart = DateTime(date.year, date.month, date.day);
      final dayEnd = dayStart.add(const Duration(days: 1));

      final count =
          users.where((user) {
            final createdAt = user['createdAt'];
            if (createdAt == null) return false;
            try {
              final createdDate = DateTime.parse(createdAt.toString());
              return createdDate.isAfter(dayStart) &&
                  createdDate.isBefore(dayEnd);
            } catch (_) {
              return false;
            }
          }).length;

      userGrowth.add(
        ChartData(x: DateFormat('EEE').format(date), y: count.toDouble()),
      );
    }

    return userGrowth;
  }

  List<RevenueChartData> _generateRevenueData(List<dynamic> transactions) {
    final now = DateTime.now();
    final revenueData = <RevenueChartData>[];

    for (int i = 6; i >= 0; i--) {
      final date = now.subtract(Duration(days: i));
      final dayStart = DateTime(date.year, date.month, date.day);
      final dayEnd = dayStart.add(const Duration(days: 1));

      double dayRevenue = 0.0;
      for (var tx in transactions) {
        final createdAt = tx['createdAt'];
        if (createdAt == null) continue;
        try {
          final txDate = DateTime.parse(createdAt.toString());
          if (txDate.isAfter(dayStart) && txDate.isBefore(dayEnd)) {
            final status = tx['status']?.toString().toLowerCase() ?? '';
            if (status == 'success' ||
                status == 'successful' ||
                status == 'completed') {
              dayRevenue += (tx['amount'] as num?)?.toDouble() ?? 0.0;
            }
          }
        } catch (_) {}
      }

      revenueData.add(
        RevenueChartData(x: DateFormat('EEE').format(date), amount: dayRevenue),
      );
    }

    return revenueData;
  }

  List<TransactionStatusData> _generateStatusDataList(
    int success,
    int pending,
    int failed,
  ) {
    return [
      TransactionStatusData(
        status: 'Success',
        count: success,
        color: successColor,
      ),
      TransactionStatusData(
        status: 'Pending',
        count: pending,
        color: warningColor,
      ),
      TransactionStatusData(status: 'Failed', count: failed, color: errorColor),
    ];
  }

  List<RecentTransaction> _generateRecentTransactions(
    List<dynamic> transactions,
  ) {
    return transactions.map((tx) {
      return RecentTransaction(
        id: tx['_id']?.toString() ?? '',
        type: _getTransactionType(tx),
        amount: (tx['amount'] as num?)?.toDouble() ?? 0.0,
        status: tx['status']?.toString() ?? 'pending',
        userName: tx['user']?['fullName']?.toString() ?? 'Unknown',
        userEmail: tx['user']?['email']?.toString() ?? '',
        reference: tx['reference']?.toString() ?? 'N/A',
        date:
            tx['createdAt'] != null
                ? DateTime.parse(tx['createdAt'].toString())
                : DateTime.now(),
      );
    }).toList();
  }

  String _getTransactionType(Map<String, dynamic> tx) {
    final desc = (tx['description'] as String?)?.toLowerCase() ?? '';
    final type = (tx['type'] as String?)?.toLowerCase() ?? '';
    final isCommission = tx['isCommission'] == true;

    if (isCommission || type.contains('commission')) return 'Commission';
    if (desc.contains('international airtime')) return 'Intl Airtime';
    if (desc.contains('electricity')) return 'Electricity';
    if (desc.contains('airtime')) return 'Airtime';
    if (desc.contains('data') || desc.contains('gb')) return 'Data';
    if (desc.contains('dstv') ||
        desc.contains('gotv') ||
        desc.contains('cable')) {
      return 'Cable TV';
    }
    if (desc.contains('education')) return 'Education';
    if (desc.contains('insurance')) return 'Insurance';
    if (desc.contains('transfer')) return 'Transfer';
    if (desc.contains('fund') || desc.contains('wallet')) return 'Fund Wallet';
    return type.isNotEmpty
        ? type[0].toUpperCase() + type.substring(1)
        : 'Other';
  }

  // ==================== LOAD MORE ====================

  Future<void> _loadMoreTransactions() async {
    if (_isLoadingMore || _currentPage >= _totalPages) return;

    _safeSetState(() {
      _isLoadingMore = true;
    });

    try {
      _currentPage++;
      final response = await ApiService.getAdminDashboard(
        timeFilter: 'all',
        page: _currentPage,
        limit: 10,
      );

      if (response['success'] == true) {
        final newTransactions = response['transactions'] ?? [];
        final moreRecent = _generateRecentTransactions(newTransactions);

        _safeSetState(() {
          _recentTransactions.addAll(moreRecent);
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      debugPrint('❌ Error loading more: $e');
      _safeSetState(() {
        _isLoadingMore = false;
      });
    }
  }

  // ==================== REFRESH ====================

  Future<void> _refreshData() async {
    _safeSetState(() => _isRefreshing = true);
    await _loadDashboardData();
    _safeSetState(() => _isRefreshing = false);
  }

  // ==================== UI BUILDERS ====================

  Widget _buildHeader() {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 16 : 24,
        vertical: isMobile ? 16 : 20,
      ),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFF5BB592), Color(0xFF102C68)],
          stops: [0.06, 0.41],
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '👋 Welcome back, Admin!',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: isMobile ? 18 : 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Here\'s what\'s happening with your platform',
                      style: GoogleFonts.inter(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: isMobile ? 12 : 14,
                      ),
                    ),
                  ],
                ),
              ),
              if (_isSuperAdmin)
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: isMobile ? 10 : 14,
                    vertical: isMobile ? 4 : 6,
                  ),
                  decoration: BoxDecoration(
                    color: warningColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.star,
                        color: Colors.white,
                        size: isMobile ? 10 : 12,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'SUPER ADMIN',
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: isMobile ? 8 : 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (_isRefreshing)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              else
                GestureDetector(
                  onTap: _refreshData,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.refresh_rounded,
                          color: Colors.white,
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Refresh',
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              Text(
                DateFormat('HH:mm').format(DateTime.now()),
                style: GoogleFonts.inter(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: isMobile ? 10 : 12,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ==================== STATS CARDS ====================

  Widget _buildStatsGrid() {
    final isMobile = MediaQuery.of(context).size.width < 600;

    final stats = [
      {
        'title': 'Total Users',
        'value': _totalUsers.toString(),
        'icon': HugeIcons.strokeRoundedUserGroup,
        'color': primaryColor,
        'subtitle': '$_activeUsers active',
      },
      {
        'title': 'Total Revenue',
        'value': '₦${_formatNumber(_totalRevenue)}',
        'icon': HugeIcons.strokeRoundedMoney02,
        'color': successColor,
        'subtitle': '$_totalTransactions transactions',
      },
      {
        'title': 'Transactions',
        'value': _totalTransactions.toString(),
        'icon': HugeIcons.strokeRoundedReceiptText,
        'color': infoColor,
        'subtitle': '$_successCount successful',
      },
      {
        'title': 'Pending',
        'value': _pendingCount.toString(),
        'icon': HugeIcons.strokeRoundedClock01,
        'color': warningColor,
        'subtitle': '$_failedCount failed',
      },
    ];

    return Padding(
      padding: EdgeInsets.all(isMobile ? 16 : 24),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: isMobile ? 2 : 4,
          crossAxisSpacing: isMobile ? 10 : 16,
          mainAxisSpacing: isMobile ? 10 : 16,
          childAspectRatio: isMobile ? 1.1 : 1.2,
        ),
        itemCount: stats.length,
        itemBuilder: (context, index) {
          final stat = stats[index];
          return _buildStatCard(
            title: stat['title'] as String,
            value: stat['value'] as String,
            icon: stat['icon'] as dynamic,
            color: stat['color'] as Color,
            subtitle: stat['subtitle'] as String,
            isMobile: isMobile,
          );
        },
      ),
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required dynamic icon,
    required Color color,
    required String subtitle,
    required bool isMobile,
  }) {
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return FadeTransition(
          opacity: _fadeAnimation,
          child: SlideTransition(position: _slideAnimation, child: child),
        );
      },
      child: Container(
        padding: EdgeInsets.all(isMobile ? 12 : 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(isMobile ? 14 : 18),
          border: Border.all(color: color.withValues(alpha: 0.15), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: EdgeInsets.all(isMobile ? 6 : 8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(isMobile ? 8 : 10),
                  ),
                  child: HugeIcon(
                    icon: icon,
                    color: color,
                    size: isMobile ? 18 : 24,
                  ),
                ),
                if (isMobile)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      title,
                      style: GoogleFonts.inter(
                        fontSize: 8,
                        color: color,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!isMobile)
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                Text(
                  value,
                  style: GoogleFonts.inter(
                    fontSize: isMobile ? 18 : 24,
                    fontWeight: FontWeight.w700,
                    color: textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(
                    fontSize: isMobile ? 9 : 11,
                    color: textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ==================== PERIOD STATS ====================

  Widget _buildPeriodStats() {
    final isMobile = MediaQuery.of(context).size.width < 600;

    final periods = [
      {
        'title': 'Today',
        'count': _periodStats['today']?['count'] ?? 0,
        'amount': _periodStats['today']?['amount'] ?? 0.0,
        'icon': HugeIcons.strokeRoundedCalendar01,
        'color': primaryColor,
      },
      {
        'title': 'This Week',
        'count': _periodStats['week']?['count'] ?? 0,
        'amount': _periodStats['week']?['amount'] ?? 0.0,
        'icon': HugeIcons.strokeRoundedCalendar02,
        'color': successColor,
      },
      {
        'title': 'This Month',
        'count': _periodStats['month']?['count'] ?? 0,
        'amount': _periodStats['month']?['amount'] ?? 0.0,
        'icon': HugeIcons.strokeRoundedCalendar03,
        'color': warningColor,
      },
      {
        'title': 'This Year',
        'count': _periodStats['year']?['count'] ?? 0,
        'amount': _periodStats['year']?['amount'] ?? 0.0,
        'icon': HugeIcons.strokeRoundedCalendar04,
        'color': infoColor,
      },
    ];

    return Container(
      margin: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 24),
      padding: EdgeInsets.all(isMobile ? 14 : 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(isMobile ? 14 : 18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              HugeIcon(
                icon: HugeIcons.strokeRoundedAnalytics02,
                color: primaryColor,
                size: isMobile ? 18 : 22,
              ),
              const SizedBox(width: 8),
              Text(
                'Period Performance',
                style: GoogleFonts.inter(
                  fontSize: isMobile ? 14 : 16,
                  fontWeight: FontWeight.w600,
                  color: textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: isMobile ? 2 : 4,
              crossAxisSpacing: isMobile ? 8 : 12,
              mainAxisSpacing: isMobile ? 8 : 12,
              childAspectRatio: 2.5,
            ),
            itemCount: periods.length,
            itemBuilder: (context, index) {
              final period = periods[index];
              return _buildPeriodCard(
                title: period['title'] as String,
                count: period['count'] as int,
                amount: period['amount'] as double,
                icon: period['icon'] as dynamic,
                color: period['color'] as Color,
                isMobile: isMobile,
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
    required dynamic icon,
    required Color color,
    required bool isMobile,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 8 : 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(isMobile ? 4 : 6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: HugeIcon(icon: icon, color: color, size: isMobile ? 14 : 18),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: isMobile ? 9 : 11,
                    color: textSecondary,
                  ),
                ),
                Row(
                  children: [
                    Text(
                      '₦${_formatNumber(amount)}',
                      style: GoogleFonts.inter(
                        fontSize: isMobile ? 11 : 13,
                        fontWeight: FontWeight.w700,
                        color: textPrimary,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '($count)',
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
        ],
      ),
    );
  }

  // ==================== CHARTS ====================

  Widget _buildCharts() {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Container(
      margin: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 24),
      child: Column(
        children: [
          _buildUserGrowthChart(isMobile),
          const SizedBox(height: 16),
          _buildRevenueChart(isMobile),
          const SizedBox(height: 16),
          _buildStatusPieChart(isMobile),
        ],
      ),
    );
  }

  Widget _buildUserGrowthChart(bool isMobile) {
    return Container(
      padding: EdgeInsets.all(isMobile ? 14 : 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(isMobile ? 14 : 18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              HugeIcon(
                icon: HugeIcons.strokeRoundedUserGroup,
                color: primaryColor,
                size: isMobile ? 18 : 22,
              ),
              const SizedBox(width: 8),
              Text(
                'User Growth (Last 7 Days)',
                style: GoogleFonts.inter(
                  fontSize: isMobile ? 14 : 16,
                  fontWeight: FontWeight.w600,
                  color: textPrimary,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: successColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '+$_totalUsers total',
                  style: GoogleFonts.inter(
                    fontSize: isMobile ? 10 : 12,
                    fontWeight: FontWeight.w600,
                    color: successColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: isMobile ? 180 : 220,
            child: SfCartesianChart(
              primaryXAxis: CategoryAxis(
                labelStyle: GoogleFonts.inter(
                  fontSize: isMobile ? 10 : 12,
                  color: textSecondary,
                ),
                majorGridLines: const MajorGridLines(width: 0),
              ),
              primaryYAxis: NumericAxis(
                labelStyle: GoogleFonts.inter(
                  fontSize: isMobile ? 10 : 12,
                  color: textSecondary,
                ),
                majorGridLines: MajorGridLines(
                  color: Colors.grey.shade200,
                  width: 0.5,
                ),
              ),
              series: <CartesianSeries<ChartData, String>>[
                ColumnSeries<ChartData, String>(
                  dataSource: _userGrowthData,
                  xValueMapper: (ChartData data, _) => data.x,
                  yValueMapper: (ChartData data, _) => data.y,
                  color: primaryColor,
                  borderRadius: BorderRadius.circular(4),
                  width: 0.6,
                  dataLabelSettings: const DataLabelSettings(isVisible: true),
                ),
              ],
              tooltipBehavior: TooltipBehavior(
                enable: true,
                header: '',
                canShowMarker: false,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRevenueChart(bool isMobile) {
    return Container(
      padding: EdgeInsets.all(isMobile ? 14 : 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(isMobile ? 14 : 18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              HugeIcon(
                icon: HugeIcons.strokeRoundedMoney02,
                color: successColor,
                size: isMobile ? 18 : 22,
              ),
              const SizedBox(width: 8),
              Text(
                'Revenue Trend (Last 7 Days)',
                style: GoogleFonts.inter(
                  fontSize: isMobile ? 14 : 16,
                  fontWeight: FontWeight.w600,
                  color: textPrimary,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: successColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '₦${_formatNumber(_totalRevenue)}',
                  style: GoogleFonts.inter(
                    fontSize: isMobile ? 10 : 12,
                    fontWeight: FontWeight.w600,
                    color: successColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: isMobile ? 180 : 220,
            child: SfCartesianChart(
              primaryXAxis: CategoryAxis(
                labelStyle: GoogleFonts.inter(
                  fontSize: isMobile ? 10 : 12,
                  color: textSecondary,
                ),
                majorGridLines: const MajorGridLines(width: 0),
              ),
              primaryYAxis: NumericAxis(
                labelStyle: GoogleFonts.inter(
                  fontSize: isMobile ? 10 : 12,
                  color: textSecondary,
                ),
                majorGridLines: MajorGridLines(
                  color: Colors.grey.shade200,
                  width: 0.5,
                ),
                numberFormat: NumberFormat.compact(),
              ),
              series: <CartesianSeries<RevenueChartData, String>>[
                SplineSeries<RevenueChartData, String>(
                  dataSource: _revenueData,
                  xValueMapper: (RevenueChartData data, _) => data.x,
                  yValueMapper: (RevenueChartData data, _) => data.amount,
                  color: successColor,
                  width: 2,
                  markerSettings: const MarkerSettings(
                    isVisible: true,
                    height: 6,
                    width: 6,
                    borderWidth: 2,
                  ),
                  dataLabelSettings: const DataLabelSettings(isVisible: true),
                ),
              ],
              tooltipBehavior: TooltipBehavior(
                enable: true,
                header: '',
                canShowMarker: true,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusPieChart(bool isMobile) {
    return Container(
      padding: EdgeInsets.all(isMobile ? 14 : 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(isMobile ? 14 : 18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              HugeIcon(
                icon: HugeIcons.strokeRoundedPieChart01,
                color: warningColor,
                size: isMobile ? 18 : 22,
              ),
              const SizedBox(width: 8),
              Text(
                'Transaction Status',
                style: GoogleFonts.inter(
                  fontSize: isMobile ? 14 : 16,
                  fontWeight: FontWeight.w600,
                  color: textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                flex: isMobile ? 1 : 2,
                child: SizedBox(
                  height: isMobile ? 160 : 200,
                  child: SfCircularChart(
                    legend: Legend(
                      isVisible: true,
                      position: LegendPosition.bottom,
                      overflowMode: LegendItemOverflowMode.wrap,
                      textStyle: GoogleFonts.inter(
                        fontSize: isMobile ? 10 : 12,
                        color: textPrimary,
                      ),
                    ),
                    series: <CircularSeries<TransactionStatusData, String>>[
                      PieSeries<TransactionStatusData, String>(
                        dataSource: _statusData,
                        xValueMapper:
                            (TransactionStatusData data, _) => data.status,
                        yValueMapper:
                            (TransactionStatusData data, _) => data.count,
                        pointColorMapper:
                            (TransactionStatusData data, _) => data.color,
                        dataLabelSettings: const DataLabelSettings(
                          isVisible: true,
                          labelPosition: ChartDataLabelPosition.inside,
                          useSeriesColor: true,
                        ),
                        dataLabelMapper:
                            (TransactionStatusData data, _) => '${data.count}',
                        enableTooltip: true,
                      ),
                    ],
                    tooltipBehavior: TooltipBehavior(
                      enable: true,
                      header: '',
                      canShowMarker: false,
                    ),
                  ),
                ),
              ),
              if (!isMobile)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children:
                          _statusData.map((data) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                children: [
                                  Container(
                                    width: 12,
                                    height: 12,
                                    decoration: BoxDecoration(
                                      color: data.color,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      data.status,
                                      style: GoogleFonts.inter(
                                        fontSize: 13,
                                        color: textSecondary,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    '${data.count}',
                                    style: GoogleFonts.inter(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ==================== RECENT TRANSACTIONS ====================

  Widget _buildRecentTransactions() {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Container(
      margin: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 24),
      padding: EdgeInsets.all(isMobile ? 14 : 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(isMobile ? 14 : 18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              HugeIcon(
                icon: HugeIcons.strokeRoundedReceiptText,
                color: primaryColor,
                size: isMobile ? 18 : 22,
              ),
              const SizedBox(width: 8),
              Text(
                'Recent Transactions',
                style: GoogleFonts.inter(
                  fontSize: isMobile ? 14 : 16,
                  fontWeight: FontWeight.w600,
                  color: textPrimary,
                ),
              ),
              const Spacer(),
              if (_totalItems > _recentTransactions.length)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_recentTransactions.length}/$_totalItems',
                    style: GoogleFonts.inter(
                      fontSize: isMobile ? 10 : 12,
                      fontWeight: FontWeight.w600,
                      color: primaryColor,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (_recentTransactions.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Column(
                  children: [
                    HugeIcon(
                      icon: HugeIcons.strokeRoundedReceiptText,
                      color: Colors.grey.shade300,
                      size: 48,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No recent transactions',
                      style: GoogleFonts.inter(
                        fontSize: isMobile ? 13 : 14,
                        color: textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Column(
              children:
                  _recentTransactions
                      .take(isMobile ? 5 : 10)
                      .map((tx) => _buildTransactionTile(tx, isMobile))
                      .toList(),
            ),
          if (_isLoadingMore)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTransactionTile(RecentTransaction tx, bool isMobile) {
    final isSuccess =
        tx.status.toLowerCase() == 'success' ||
        tx.status.toLowerCase() == 'successful' ||
        tx.status.toLowerCase() == 'completed';
    final isPending =
        tx.status.toLowerCase() == 'pending' ||
        tx.status.toLowerCase() == 'processing';
    final statusColor =
        isSuccess ? successColor : (isPending ? warningColor : errorColor);

    return Container(
      padding: EdgeInsets.symmetric(vertical: isMobile ? 8 : 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade100, width: 0.5),
        ),
      ),
      child: InkWell(
        onTap: () => _showTransactionDetails(tx),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(isMobile ? 6 : 8),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                isSuccess
                    ? Icons.check_circle_outline
                    : isPending
                    ? Icons.hourglass_empty
                    : Icons.cancel_outlined,
                color: statusColor,
                size: isMobile ? 16 : 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tx.type,
                    style: GoogleFonts.inter(
                      fontSize: isMobile ? 13 : 14,
                      fontWeight: FontWeight.w600,
                      color: textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    tx.userName,
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
                  '₦${_formatNumber(tx.amount)}',
                  style: GoogleFonts.inter(
                    fontSize: isMobile ? 13 : 14,
                    fontWeight: FontWeight.w700,
                    color: isSuccess ? successColor : textPrimary,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    tx.status,
                    style: GoogleFonts.inter(
                      fontSize: isMobile ? 8 : 9,
                      fontWeight: FontWeight.w600,
                      color: statusColor,
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

  // ==================== TRANSACTION DETAILS MODAL ====================

  void _showTransactionDetails(RecentTransaction tx) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (context) => Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 20,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: SafeArea(
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
                    const SizedBox(height: 16),
                    // Title
                    Text(
                      'Transaction Details',
                      style: GoogleFonts.inter(
                        fontSize: isMobile ? 18 : 20,
                        fontWeight: FontWeight.w700,
                        color: textPrimary,
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Status badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _getStatusColor(
                          tx.status,
                        ).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        tx.status.toUpperCase(),
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _getStatusColor(tx.status),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Details
                    _buildDetailRow('Type', tx.type, isMobile),
                    _buildDetailRow(
                      'Amount',
                      '₦${_formatNumber(tx.amount)}',
                      isMobile,
                    ),
                    _buildDetailRow('User', tx.userName, isMobile),
                    _buildDetailRow('Email', tx.userEmail, isMobile),
                    _buildDetailRow('Reference', tx.reference, isMobile),
                    _buildDetailRow(
                      'Date',
                      DateFormat('dd MMM yyyy, HH:mm').format(tx.date),
                      isMobile,
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          'Close',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
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

  Widget _buildDetailRow(String label, String value, bool isMobile) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: isMobile ? 80 : 100,
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontSize: isMobile ? 13 : 14,
                fontWeight: FontWeight.w600,
                color: textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.inter(
                fontSize: isMobile ? 13 : 14,
                color: textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    final s = status.toLowerCase();
    if (s.contains('success') || s.contains('completed')) return successColor;
    if (s.contains('pending') || s.contains('processing')) return warningColor;
    return errorColor;
  }

  // ==================== HELPERS ====================

  String _formatNumber(double number) {
    if (number >= 1000000) {
      return '${(number / 1000000).toStringAsFixed(1)}M';
    } else if (number >= 1000) {
      return '${(number / 1000).toStringAsFixed(1)}K';
    }
    return number.toStringAsFixed(2);
  }

  // ==================== LOADING & ERROR STATES ====================

  Widget _buildLoadingState() {
    return const Center(
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
          Text('Loading dashboard...', style: TextStyle(color: textSecondary)),
        ],
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
            const SizedBox(height: 16),
            Text(
              'Failed to Load Dashboard',
              style: GoogleFonts.inter(
                fontSize: isMobile ? 20 : 24,
                fontWeight: FontWeight.w700,
                color: textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage ?? 'Please try again later',
              style: GoogleFonts.inter(
                fontSize: isMobile ? 14 : 16,
                color: textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _refreshData,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(
                'Retry',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
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

  // ==================== MAIN BUILD ====================

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: _buildLoadingState(),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(backgroundColor: Colors.white, body: _buildErrorState());
    }

    return RefreshIndicator(
      onRefresh: _refreshData,
      color: primaryColor,
      child: SingleChildScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 16),
            _buildStatsGrid(),
            const SizedBox(height: 16),
            _buildPeriodStats(),
            const SizedBox(height: 16),
            _buildCharts(),
            const SizedBox(height: 16),
            _buildRecentTransactions(),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
