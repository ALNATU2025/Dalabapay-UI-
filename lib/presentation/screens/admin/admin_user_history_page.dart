// lib/presentation/screens/admin/admin_user_history_page.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/services/api_service.dart';

class AdminUserHistoryPage extends StatefulWidget {
  final String userId;
  final String userName;
  final String userEmail;
  final double currentBalance;
  final double commissionBalance;

  const AdminUserHistoryPage({
    super.key,
    required this.userId,
    required this.userName,
    required this.userEmail,
    this.currentBalance = 0.0,
    this.commissionBalance = 0.0,
  });

  @override
  State<AdminUserHistoryPage> createState() => _AdminUserHistoryPageState();
}

class _AdminUserHistoryPageState extends State<AdminUserHistoryPage>
    with SingleTickerProviderStateMixin {
  // ==================== BRAND COLORS ====================
  static const Color primaryColor = Color(0xFF15368A);
  static const Color secondaryColor = Color(0xFF079A68);
  static const Color successColor = Color(0xFF079A68);
  static const Color warningColor = Color(0xFFB7791F);
  static const Color errorColor = Color(0xFFE5484D);
  static const Color infoColor = Color(0xFF2563EB);
  static const Color textPrimary = Color(0xFF10255A);
  static const Color textSecondary = Color(0xFF7B87A1);

  // ==================== STATE ====================
  late TabController _tabController;
  bool _loadingDetails = true;
  bool _isLoadingAll = false;
  String? _error;

  Map<String, dynamic>? _userData;
  String _accountStatus = 'active';
  List<Map<String, dynamic>> _transactions = [];
  List<Map<String, dynamic>> _auditLogs = [];

  // Filter state for the transactions tab
  String _filter = 'all'; // all | successful | pending | failed

  // Balance state — mutable so it updates after refresh
  late double _currentBalance;
  late double _commissionBalance;

  int _currentTxPage = 1;
  int _totalTxPages = 1;
  int _totalTxCount = 0;
  bool _isLoadingMoreTx = false;

  @override
  void initState() {
    super.initState();
    _currentBalance = widget.currentBalance;
    _commissionBalance = widget.commissionBalance;
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ==================== LOAD ALL PAGES ====================
  /// Loads every remaining page one at a time, with UI updates between
  /// each page so the app never freezes.
  Future<void> _loadAllPages() async {
    if (_isLoadingAll) return;
    if (_currentTxPage >= _totalTxPages) return;

    setState(() => _isLoadingAll = true);

    try {
      // Keep fetching until we're at the last page
      while (_currentTxPage < _totalTxPages) {
        if (!mounted) break;
        await _loadData(loadMore: true);
      }
    } catch (e) {
      debugPrint('❌ _loadAllPages error: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoadingAll = false);
      }
    }
  }

  // ==================== PAGINATION STATE ====================

  Future<void> _loadData({bool loadMore = false}) async {
    if (!loadMore) {
      setState(() {
        _loadingDetails = true;
        _error = null;
        _currentTxPage = 1;
      });
    } else {
      if (_isLoadingMoreTx) return;
      if (_currentTxPage >= _totalTxPages) return;
      setState(() => _isLoadingMoreTx = true);
    }

    try {
      final pageToLoad = loadMore ? _currentTxPage + 1 : 1;

      final res = await ApiService.getUserFullDetails(
        widget.userId,
        txPage: pageToLoad,
        txLimit: 100,
      );
      if (!mounted) return;

      if (res['success'] == true) {
        final data = res['data'] as Map<String, dynamic>;
        final user = data['user'] as Map<String, dynamic>? ?? {};
        final transactions = (data['transactions'] as List?) ?? [];
        final auditLogs = (data['auditLogs'] as List?) ?? [];
        final pagination = data['pagination'] as Map<String, dynamic>? ?? {};
        final txPagination =
            pagination['transactions'] as Map<String, dynamic>? ?? {};

        final newTx =
            transactions
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();

        setState(() {
          _userData = user;
          _accountStatus = (data['status'] ?? 'active').toString();

          if (loadMore) {
            _transactions.addAll(newTx);
          } else {
            _transactions = newTx;
          }

          // Only replace audit logs on fresh load (not on load more)
          if (!loadMore) {
            _auditLogs =
                auditLogs
                    .map((e) => Map<String, dynamic>.from(e as Map))
                    .toList();
          }

          _currentTxPage =
              (txPagination['page'] as num?)?.toInt() ?? pageToLoad;
          _totalTxPages = (txPagination['totalPages'] as num?)?.toInt() ?? 1;
          _totalTxCount =
              (txPagination['total'] as num?)?.toInt() ?? _transactions.length;

          // Refresh balances from the fresh user data
          if (user['walletBalance'] != null) {
            _currentBalance = (user['walletBalance'] as num).toDouble();
          }
          if (user['commissionBalance'] != null) {
            _commissionBalance = (user['commissionBalance'] as num).toDouble();
          }

          _loadingDetails = false;
          _isLoadingMoreTx = false;
        });
      } else {
        setState(() {
          _error = res['message']?.toString() ?? 'Failed to load user data';
          _loadingDetails = false;
          _isLoadingMoreTx = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loadingDetails = false;
        _isLoadingMoreTx = false;
      });
    }
  }

  // ==================== TRANSACTION FILTERING ====================
  // ==================== TRANSACTION FILTERING ====================
  /// Classifies a raw status string into one of: successful | pending | failed | other.
  String _classifyStatus(String? rawStatus) {
    final s = (rawStatus ?? '').toString().toLowerCase().trim();
    if (s.isEmpty) return 'pending'; // unknown → treat as pending

    // ✅ SUCCESS
    if (s.contains('success') ||
        s.contains('complete') ||
        s.contains('delivered') ||
        s.contains('resolved') ||
        s.contains('approved')) {
      return 'successful';
    }

    // ❌ FAILED / CANCELLED / REFUNDED
    if (s.contains('fail') ||
        s.contains('cancel') ||
        s.contains('reject') ||
        s.contains('declin') ||
        s.contains('reversed') ||
        s.contains('refunded')) {
      return 'failed';
    }

    // ⏳ PENDING / PROCESSING / AWAITING / INITIATED / UNDER REVIEW
    if (s.contains('pending') ||
        s.contains('process') ||
        s.contains('awaiting') ||
        s.contains('initiat') ||
        s.contains('review') ||
        s.contains('escalat') ||
        s.contains('queue') ||
        s.contains('hold')) {
      return 'pending';
    }

    // Unknown status → treat as pending (safest)
    return 'pending';
  }

  // ==================== CACHED FILTER COUNTS ====================
  /// Status counts for the currently loaded transactions.
  /// Computed once per rebuild instead of 4x per chip.
  Map<String, int> get _filterCounts {
    int successful = 0, pending = 0, failed = 0;
    for (final tx in _transactions) {
      switch (_classifyStatus(tx['status']?.toString())) {
        case 'successful':
          successful++;
          break;
        case 'pending':
          pending++;
          break;
        case 'failed':
          failed++;
          break;
      }
    }
    return {
      'all': _transactions.length,
      'successful': successful,
      'pending': pending,
      'failed': failed,
    };
  }

  List<Map<String, dynamic>> get _filteredTransactions {
    if (_filter == 'all') return _transactions;
    return _transactions.where((tx) {
      final bucket = _classifyStatus(tx['status']?.toString());
      return bucket == _filter;
    }).toList();
  }

  // ==================== COMPUTED TOTALS ====================
  double get _totalCredits {
    return _transactions
        .where((tx) {
          final type = (tx['type'] ?? '').toString().toLowerCase();
          return type.contains('credit') ||
              type.contains('fund') ||
              type.contains('refund') ||
              type.contains('bonus') ||
              type.contains('commission');
        })
        .fold<double>(
          0.0,
          (sum, tx) => sum + ((tx['amount'] as num?)?.toDouble() ?? 0.0),
        );
  }

  double get _totalDebits {
    return _transactions
        .where((tx) {
          final type = (tx['type'] ?? '').toString().toLowerCase();
          return !(type.contains('credit') ||
              type.contains('fund') ||
              type.contains('refund') ||
              type.contains('bonus') ||
              type.contains('commission'));
        })
        .fold<double>(
          0.0,
          (sum, tx) => sum + ((tx['amount'] as num?)?.toDouble() ?? 0.0),
        );
  }

  // ==================== MAIN BUILD ====================
  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(isMobile),
            _buildBalanceSummary(isMobile),
            _buildTabBar(isMobile),
            Expanded(
              child:
                  _loadingDetails
                      ? const Center(child: CircularProgressIndicator())
                      : _error != null
                      ? _buildErrorState()
                      : TabBarView(
                        controller: _tabController,
                        children: [
                          _buildTransactionsTab(isMobile),
                          _buildAuditTab(isMobile),
                        ],
                      ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== HEADER ====================
  Widget _buildHeader(bool isMobile) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 16 : 24,
        vertical: isMobile ? 14 : 18,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFF35C08E), Color(0xFF15368A)],
          stops: [0.06, 0.41],
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
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
                    size: isMobile ? 20 : 22,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'User History',
                  style: GoogleFonts.inter(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontSize: isMobile ? 12 : 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              // Status badge
              _buildStatusBadge(),
              const SizedBox(width: 8),
              // Refresh
              GestureDetector(
                onTap: _loadData,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.refresh_rounded,
                    color: Colors.white,
                    size: isMobile ? 18 : 20,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                width: isMobile ? 48 : 56,
                height: isMobile ? 48 : 56,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    widget.userName.isNotEmpty
                        ? widget.userName[0].toUpperCase()
                        : '?',
                    style: GoogleFonts.inter(
                      color: primaryColor,
                      fontSize: isMobile ? 20 : 24,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.userName,
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: isMobile ? 17 : 20,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      widget.userEmail,
                      style: GoogleFonts.inter(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: isMobile ? 11 : 13,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge() {
    Color color;
    String label;
    IconData icon;

    switch (_accountStatus) {
      case 'pending':
        color = warningColor;
        label = 'PENDING';
        icon = Icons.pending_actions_rounded;
        break;
      case 'rejected':
        color = errorColor;
        label = 'REJECTED';
        icon = Icons.cancel_rounded;
        break;
      case 'suspended':
        color = errorColor;
        label = 'SUSPENDED';
        icon = Icons.block_rounded;
        break;
      case 'inactive':
        color = Colors.grey.shade400;
        label = 'INACTIVE';
        icon = Icons.pause_circle_rounded;
        break;
      default:
        color = successColor;
        label = 'ACTIVE';
        icon = Icons.check_circle_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 12),
          const SizedBox(width: 5),
          Text(
            label,
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  // ==================== BALANCE SUMMARY ====================
  Widget _buildBalanceSummary(bool isMobile) {
    return Container(
      margin: EdgeInsets.all(isMobile ? 16 : 20),
      padding: EdgeInsets.all(isMobile ? 16 : 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(
        children: [
          // Current balance — BIG and prominent
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: secondaryColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.account_balance_wallet_rounded,
                  color: secondaryColor,
                  size: isMobile ? 20 : 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Current Wallet Balance',
                      style: GoogleFonts.inter(
                        fontSize: isMobile ? 11 : 12,
                        color: textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '₦${_currentBalance.toStringAsFixed(2)}',
                      style: GoogleFonts.inter(
                        fontSize: isMobile ? 22 : 26,
                        color: primaryColor,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(height: 1, color: Colors.grey.shade100),
          const SizedBox(height: 14),
          // Commission + totals row
          Row(
            children: [
              Expanded(
                child: _buildMiniStat(
                  label: 'Commission',
                  value: '₦${_commissionBalance.toStringAsFixed(2)}',
                  color: warningColor,
                  icon: Icons.monetization_on_rounded,
                  isMobile: isMobile,
                ),
              ),
              Container(width: 1, height: 32, color: Colors.grey.shade100),
              Expanded(
                child: _buildMiniStat(
                  label: 'Credits',
                  value: '₦${_totalCredits.toStringAsFixed(2)}',
                  color: successColor,
                  icon: Icons.arrow_downward_rounded,
                  isMobile: isMobile,
                ),
              ),
              Container(width: 1, height: 32, color: Colors.grey.shade100),
              Expanded(
                child: _buildMiniStat(
                  label: 'Debits',
                  value: '₦${_totalDebits.toStringAsFixed(2)}',
                  color: errorColor,
                  icon: Icons.arrow_upward_rounded,
                  isMobile: isMobile,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniStat({
    required String label,
    required String value,
    required Color color,
    required IconData icon,
    required bool isMobile,
  }) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: isMobile ? 12 : 14, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: isMobile ? 10 : 11,
                color: textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.inter(
            fontSize: isMobile ? 12 : 14,
            color: primaryColor,
            fontWeight: FontWeight.w700,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  // ==================== TAB BAR ====================
  Widget _buildTabBar(bool isMobile) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 20),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          color: primaryColor,
          borderRadius: BorderRadius.circular(10),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelColor: Colors.white,
        unselectedLabelColor: textSecondary,
        labelStyle: GoogleFonts.inter(
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
        unselectedLabelStyle: GoogleFonts.inter(
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
        tabs: [
          Tab(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.receipt_long_rounded, size: 16),
                const SizedBox(width: 6),
                Text(
                  _totalTxCount > 0
                      ? 'Transactions (${_transactions.length}/$_totalTxCount)'
                      : 'Transactions (${_transactions.length})',
                ),
              ],
            ),
          ),
          Tab(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.history_rounded, size: 16),
                const SizedBox(width: 6),
                Text('Audit (${_auditLogs.length})'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==================== TRANSACTIONS TAB ====================
  Widget _buildTransactionsTab(bool isMobile) {
    final txs = _filteredTransactions;

    return Column(
      children: [
        const SizedBox(height: 12),
        // Filter chips + Load-All button
        Container(
          height: 38,
          margin: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 20),
          child: Row(
            children: [
              Expanded(
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _buildFilterChip(
                      'all',
                      'All',
                      Icons.apps_rounded,
                      isMobile,
                    ),
                    _buildFilterChip(
                      'successful',
                      'Success',
                      Icons.check_circle_rounded,
                      isMobile,
                    ),
                    _buildFilterChip(
                      'pending',
                      'Pending',
                      Icons.schedule_rounded,
                      isMobile,
                    ),
                    _buildFilterChip(
                      'failed',
                      'Failed',
                      Icons.cancel_rounded,
                      isMobile,
                    ),
                  ],
                ),
              ),
              // ✅ Load All button (only if more pages remain)
              if (_currentTxPage < _totalTxPages)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: GestureDetector(
                    onTap: _isLoadingAll ? null : _loadAllPages,
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: isMobile ? 10 : 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color:
                            _isLoadingAll
                                ? Colors.grey.shade300
                                : secondaryColor,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_isLoadingAll)
                            const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          else
                            const Icon(
                              Icons.download_rounded,
                              size: 13,
                              color: Colors.white,
                            ),
                          const SizedBox(width: 5),
                          Text(
                            _isLoadingAll
                                ? 'Loading...'
                                : 'Load All (${_transactions.length}/$_totalTxCount)',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child:
              txs.isEmpty
                  ? _buildEmptyTab('No transactions found')
                  : RefreshIndicator(
                    onRefresh: () => _loadData(),
                    color: primaryColor,
                    child: ListView.builder(
                      padding: EdgeInsets.fromLTRB(
                        isMobile ? 16 : 20,
                        8,
                        isMobile ? 16 : 20,
                        isMobile ? 100 : 24,
                      ),
                      itemCount: txs.length + 1, // +1 for load more button
                      itemBuilder: (context, i) {
                        if (i == txs.length) {
                          // Load More / End of list widget
                          return _buildLoadMoreFooter(isMobile);
                        }
                        return _buildTransactionCard(txs[i], isMobile);
                      },
                    ),
                  ),
        ),
      ],
    );
  }

  // ==================== LOAD MORE FOOTER ====================
  Widget _buildLoadMoreFooter(bool isMobile) {
    // If we've loaded everything
    if (_currentTxPage >= _totalTxPages) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: Column(
            children: [
              Icon(
                Icons.check_circle_outline_rounded,
                color: successColor,
                size: 22,
              ),
              const SizedBox(height: 6),
              Text(
                'All $_totalTxCount transactions loaded',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Load More button
    if (_isLoadingMoreTx) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: primaryColor,
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: OutlinedButton.icon(
          onPressed: () => _loadData(loadMore: true),
          icon: const Icon(Icons.expand_more_rounded, size: 18),
          label: Text(
            'Load More (${_transactions.length}/$_totalTxCount)',
            style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: primaryColor,
            side: BorderSide(color: primaryColor.withValues(alpha: 0.4)),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChip(
    String key,
    String label,
    IconData icon,
    bool isMobile,
  ) {
    final isSelected = _filter == key;

    // ✅ Live count for this bucket (cached across all 4 chips)
    final count = _filterCounts[key] ?? 0;
    final displayLabel = count > 0 ? '$label ($count)' : label;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () {
          setState(() => _filter = key);
        },
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: isMobile ? 12 : 14,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            color: isSelected ? primaryColor : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected ? primaryColor : Colors.grey.shade300,
              width: 1.2,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 13,
                color: isSelected ? Colors.white : textSecondary,
              ),
              const SizedBox(width: 5),
              Text(
                displayLabel,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.white : textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTransactionCard(Map<String, dynamic> tx, bool isMobile) {
    final status = (tx['status'] ?? '').toString().toLowerCase();
    final isSuccess = status.contains('success') || status.contains('complete');
    final isFailed = status.contains('fail') || status.contains('cancel');
    final isPending =
        status.contains('pending') || status.contains('processing');

    final color =
        isSuccess
            ? successColor
            : isFailed
            ? errorColor
            : warningColor;
    final icon =
        isSuccess
            ? Icons.check_circle_rounded
            : isFailed
            ? Icons.cancel_rounded
            : Icons.schedule_rounded;

    final amount = (tx['amount'] as num?)?.toDouble() ?? 0.0;
    final type = (tx['type'] ?? 'Transaction').toString();
    final desc = (tx['description'] ?? '').toString();
    final reference = (tx['reference'] ?? '').toString();
    final createdAt = tx['createdAt']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showReceipt(tx),
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: EdgeInsets.all(isMobile ? 12 : 14),
            child: Row(
              children: [
                // Icon
                Container(
                  width: isMobile ? 42 : 46,
                  height: isMobile ? 42 : 46,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: color, size: isMobile ? 18 : 20),
                ),
                const SizedBox(width: 12),
                // Details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        type,
                        style: GoogleFonts.inter(
                          fontSize: isMobile ? 13 : 14,
                          fontWeight: FontWeight.w700,
                          color: primaryColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (desc.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          desc,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(
                            Icons.access_time_rounded,
                            size: 10,
                            color: textSecondary,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            _formatDateTime(createdAt),
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              color: textSecondary,
                            ),
                          ),
                          if (reference.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                '• ${_shortReference(reference)}',
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  color: textSecondary,
                                  fontStyle: FontStyle.italic,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                // Amount + status
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '₦${amount.toStringAsFixed(2)}',
                      style: GoogleFonts.inter(
                        fontSize: isMobile ? 13 : 14,
                        fontWeight: FontWeight.w800,
                        color: primaryColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        isSuccess
                            ? 'SUCCESS'
                            : isFailed
                            ? 'FAILED'
                            : isPending
                            ? 'PENDING'
                            : status.toUpperCase(),
                        style: GoogleFonts.inter(
                          fontSize: 8,
                          fontWeight: FontWeight.w800,
                          color: color,
                          letterSpacing: 0.5,
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
    );
  }

  // ==================== AUDIT TAB ====================
  Widget _buildAuditTab(bool isMobile) {
    return _auditLogs.isEmpty
        ? _buildEmptyTab('No admin activity yet')
        : RefreshIndicator(
          onRefresh: _loadData,
          color: primaryColor,
          child: ListView.builder(
            padding: EdgeInsets.fromLTRB(
              isMobile ? 16 : 20,
              16,
              isMobile ? 16 : 20,
              isMobile ? 100 : 24,
            ),
            itemCount: _auditLogs.length,
            itemBuilder:
                (context, i) => _buildAuditCard(_auditLogs[i], isMobile),
          ),
        );
  }

  Widget _buildAuditCard(Map<String, dynamic> log, bool isMobile) {
    final action = (log['action'] ?? '').toString();
    final color = _auditColor(action);
    final icon = _auditIcon(action);
    final amount = (log['amount'] as num?)?.toDouble() ?? 0.0;
    final before = (log['balanceBefore'] as num?)?.toDouble() ?? 0.0;
    final after = (log['balanceAfter'] as num?)?.toDouble() ?? 0.0;
    final admin = (log['adminName'] ?? 'Admin').toString();
    final reason = (log['reason'] ?? '').toString();
    final reference = (log['reference'] ?? '').toString();
    final createdAt = log['createdAt']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: EdgeInsets.all(isMobile ? 12 : 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 15),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _humanize(action),
                  style: GoogleFonts.inter(
                    fontSize: isMobile ? 13 : 14,
                    fontWeight: FontWeight.w700,
                    color: primaryColor,
                  ),
                ),
              ),
              Text(
                _formatDateTime(createdAt),
                style: GoogleFonts.inter(fontSize: 10, color: textSecondary),
              ),
            ],
          ),
          if (amount > 0) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.attach_money_rounded, size: 13, color: color),
                      const SizedBox(width: 4),
                      Text(
                        '₦${amount.toStringAsFixed(2)}',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _buildBalanceChip('Before', before, isMobile),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.arrow_forward_rounded,
                        size: 14,
                        color: textSecondary,
                      ),
                      const SizedBox(width: 8),
                      _buildBalanceChip('After', after, isMobile),
                    ],
                  ),
                ],
              ),
            ),
          ],
          if (reason.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.notes_rounded, size: 12, color: textSecondary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    reason,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (reference.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  Icons.confirmation_number_outlined,
                  size: 12,
                  color: textSecondary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    reference,
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      color: textSecondary,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: primaryColor.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.admin_panel_settings_rounded,
                  size: 12,
                  color: primaryColor,
                ),
                const SizedBox(width: 6),
                Text(
                  'By: $admin',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    color: primaryColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBalanceChip(String label, double value, bool isMobile) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Text(
        '$label: ₦${value.toStringAsFixed(2)}',
        style: GoogleFonts.inter(
          fontSize: 10,
          color: textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  // ==================== RECEIPT MODAL ====================
  void _showReceipt(Map<String, dynamic> tx) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    final status = (tx['status'] ?? '').toString().toLowerCase();
    final isSuccess = status.contains('success') || status.contains('complete');
    final isFailed = status.contains('fail') || status.contains('cancel');

    final color =
        isSuccess
            ? successColor
            : isFailed
            ? errorColor
            : warningColor;

    final amount = (tx['amount'] as num?)?.toDouble() ?? 0.0;
    final balanceBefore = (tx['balanceBefore'] as num?)?.toDouble();
    final balanceAfter = (tx['balanceAfter'] as num?)?.toDouble();
    final type = (tx['type'] ?? 'Transaction').toString();
    final desc = (tx['description'] ?? '').toString();
    final reference = (tx['reference'] ?? '').toString();
    final txId = (tx['_id'] ?? '').toString();
    final createdAt = tx['createdAt']?.toString() ?? '';
    final authMethod = (tx['authenticationMethod'] ?? '').toString();
    final metadata = tx['metadata'] as Map<String, dynamic>?;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalContext) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.85,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Handle
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Header
              Padding(
                padding: EdgeInsets.all(isMobile ? 16 : 20),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isSuccess
                            ? Icons.check_circle_rounded
                            : isFailed
                            ? Icons.cancel_rounded
                            : Icons.schedule_rounded,
                        color: color,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Transaction Receipt',
                            style: GoogleFonts.inter(
                              fontSize: isMobile ? 16 : 18,
                              fontWeight: FontWeight.w700,
                              color: primaryColor,
                            ),
                          ),
                          Text(
                            type,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(modalContext),
                      icon: const Icon(Icons.close_rounded),
                      color: textSecondary,
                    ),
                  ],
                ),
              ),
              // Body
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Amount big
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              color.withValues(alpha: 0.08),
                              color.withValues(alpha: 0.02),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: color.withValues(alpha: 0.2),
                            width: 1.2,
                          ),
                        ),
                        child: Column(
                          children: [
                            Text(
                              'Amount',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: textSecondary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '₦${amount.toStringAsFixed(2)}',
                              style: GoogleFonts.inter(
                                fontSize: isMobile ? 28 : 32,
                                fontWeight: FontWeight.w800,
                                color: primaryColor,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: color,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                (tx['status'] ?? 'Unknown')
                                    .toString()
                                    .toUpperCase(),
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Receipt details
                      _buildReceiptSection('Transaction Details', [
                        _receiptRow('Type', type),
                        if (desc.isNotEmpty) _receiptRow('Description', desc),
                        _receiptRow(
                          'Reference',
                          reference.isEmpty ? 'N/A' : reference,
                        ),
                        if (txId.isNotEmpty)
                          _receiptRow('Transaction ID', _shortId(txId)),
                        _receiptRow('Date', _formatFullDate(createdAt)),
                        if (authMethod.isNotEmpty && authMethod != 'none')
                          _receiptRow('Auth Method', authMethod.toUpperCase()),
                      ]),

                      if (balanceBefore != null && balanceAfter != null) ...[
                        const SizedBox(height: 12),
                        _buildReceiptSection('Balance Movement', [
                          _receiptRow(
                            'Before',
                            '₦${balanceBefore.toStringAsFixed(2)}',
                          ),
                          _receiptRow(
                            'After',
                            '₦${balanceAfter.toStringAsFixed(2)}',
                          ),
                          _receiptRow(
                            'Change',
                            '${balanceAfter > balanceBefore ? '+' : ''}₦${(balanceAfter - balanceBefore).toStringAsFixed(2)}',
                            valueColor:
                                balanceAfter > balanceBefore
                                    ? successColor
                                    : errorColor,
                          ),
                        ]),
                      ],

                      // Metadata (if any relevant fields)
                      if (metadata != null && metadata.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        _buildReceiptSection(
                          'Additional Info',
                          _buildMetadataRows(metadata),
                        ),
                      ],

                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
              // Copy + Close buttons
              Padding(
                padding: EdgeInsets.all(isMobile ? 16 : 20),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Clipboard.setData(
                            ClipboardData(text: _buildShareText(tx)),
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Receipt copied to clipboard',
                                style: GoogleFonts.inter(color: Colors.white),
                              ),
                              backgroundColor: secondaryColor,
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.copy_rounded, size: 16),
                        label: Text(
                          'Copy',
                          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          side: BorderSide(color: Colors.grey.shade300),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(modalContext),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          'Close',
                          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildReceiptSection(String title, List<Widget> rows) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: primaryColor,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 10),
          ...rows,
        ],
      ),
    );
  }

  Widget _receiptRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: GoogleFonts.inter(fontSize: 11, color: textSecondary),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: valueColor ?? textPrimary,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildMetadataRows(Map<String, dynamic> metadata) {
    final rows = <Widget>[];
    final importantKeys = [
      'phone',
      'network',
      'plan',
      'planName',
      'meterNumber',
      'billersCode',
      'smartcardNumber',
      'packageName',
      'token',
      'customerName',
      'units',
      'provider',
      'serviceID',
    ];
    for (final key in importantKeys) {
      if (metadata.containsKey(key)) {
        final v = metadata[key];
        if (v != null && v.toString().isNotEmpty) {
          rows.add(_receiptRow(_humanize(key), v.toString()));
        }
      }
    }
    return rows.isEmpty ? [_receiptRow('Info', 'Not available')] : rows;
  }

  String _buildShareText(Map<String, dynamic> tx) {
    final buf = StringBuffer();
    buf.writeln('===== TRANSACTION RECEIPT =====');
    buf.writeln('User: ${widget.userName}');
    buf.writeln('Email: ${widget.userEmail}');
    buf.writeln('Type: ${tx['type'] ?? 'N/A'}');
    buf.writeln(
      'Amount: ₦${((tx['amount'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)}',
    );
    buf.writeln('Status: ${tx['status'] ?? 'N/A'}');
    buf.writeln('Reference: ${tx['reference'] ?? 'N/A'}');
    buf.writeln('Date: ${_formatFullDate(tx['createdAt']?.toString() ?? '')}');
    return buf.toString();
  }

  // ==================== HELPERS ====================
  Widget _buildEmptyTab(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inbox_rounded, size: 60, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(
            message,
            style: GoogleFonts.inter(fontSize: 14, color: textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline_rounded, size: 60, color: errorColor),
            const SizedBox(height: 12),
            Text(
              'Failed to load data',
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: primaryColor,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _error ?? '',
              style: GoogleFonts.inter(fontSize: 13, color: textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
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

  Color _auditColor(String action) {
    if (action.contains('CREDIT')) return successColor;
    if (action.contains('DEBIT')) return errorColor;
    if (action.contains('ACTIVATED')) return successColor;
    if (action.contains('DEACTIVATED')) return errorColor;
    if (action.contains('SUSPENDED')) return warningColor;
    if (action.contains('APPROVED')) return successColor;
    if (action.contains('REJECTED')) return errorColor;
    if (action.contains('PIN')) return warningColor;
    return infoColor;
  }

  IconData _auditIcon(String action) {
    if (action.contains('CREDIT')) return Icons.add_rounded;
    if (action.contains('DEBIT')) return Icons.remove_rounded;
    if (action.contains('ACTIVATED')) return Icons.check_circle_rounded;
    if (action.contains('DEACTIVATED')) return Icons.cancel_rounded;
    if (action.contains('SUSPENDED')) return Icons.block_rounded;
    if (action.contains('APPROVED')) return Icons.verified_rounded;
    if (action.contains('REJECTED')) return Icons.cancel_rounded;
    if (action.contains('PIN')) return Icons.lock_rounded;
    if (action.contains('EDITED')) return Icons.edit_rounded;
    if (action.contains('ROLE')) return Icons.admin_panel_settings_rounded;
    return Icons.history_rounded;
  }

  String _humanize(String s) {
    return s
        .split('_')
        .map(
          (w) =>
              w.isEmpty
                  ? w
                  : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}',
        )
        .join(' ');
  }

  String _shortReference(String ref) {
    if (ref.length <= 16) return ref;
    return '${ref.substring(0, 8)}...${ref.substring(ref.length - 4)}';
  }

  String _shortId(String id) {
    if (id.length <= 12) return id;
    return '${id.substring(0, 6)}...${id.substring(id.length - 4)}';
  }

  String _formatDateTime(String raw) {
    if (raw.isEmpty) return 'N/A';
    try {
      final dt = DateTime.parse(raw).toLocal();
      return DateFormat('dd MMM yyyy • HH:mm').format(dt);
    } catch (_) {
      return raw;
    }
  }

  String _formatFullDate(String raw) {
    if (raw.isEmpty) return 'N/A';
    try {
      final dt = DateTime.parse(raw).toLocal();
      return DateFormat('EEEE, dd MMMM yyyy • HH:mm:ss').format(dt);
    } catch (_) {
      return raw;
    }
  }
}
