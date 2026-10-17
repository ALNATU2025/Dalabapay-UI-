// lib/presentation/screens/transactions/transactions_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/services/api_service.dart';
import '../../../core/services/cache_service.dart';
import '../../../core/widgets/receipt_widget.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../../ui/ui.dart';

class TransactionsScreen extends StatefulWidget {
  final String userId;
  final String? highlightReference;

  const TransactionsScreen({
    super.key,
    required this.userId,
    this.highlightReference,
  });

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen>
    with
        SingleTickerProviderStateMixin,
        AutomaticKeepAliveClientMixin,
        WidgetsBindingObserver {
  // State Variables
  List<dynamic> _allTransactions = [];
  List<dynamic> _filteredTransactions = [];
  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _errorMessage;
  double? _currentBalance;
  bool _isBalanceLoading = true;
  String _selectedFilter = 'All';
  DateTime? _startDate;
  DateTime? _endDate;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  // Animation
  late AnimationController _fadeController;

  // Filters
  // Status chips shown at the top (design). The service filter lives in
  // a separate picker so all the old type filters still work.
  final List<String> _filters = ['All', 'Successful', 'Pending', 'Failed'];
  String _typeFilter = 'All services';
  final List<String> _typeFilters = const [
    'All services',
    'Airtime Purchase',
    'Data Purchase',
    'Cable TV Purchase',
    'Electricity Purchase',
    'Education Purchase',
    'Insurance Purchase',
    'Transfer',
    'Fund Wallet',
    'Commission Credit',
    'Refund Credit',
  ];
  bool _exporting = false;

  // Verification tracking
  final Map<String, bool> _verifyingTransactions = {};
  Timer? _silentRefreshTimer;
  Timer? _balanceRefreshTimer;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); // ✅ ADD THIS
    _setupAnimations();
    _initializePage();
    _startSilentRefresh();
    _startBalanceRefresh();
  }

  // ✅ ADD THIS METHOD to refresh when user returns to app
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('📱 App resumed — refreshing transactions');
      _fetchTransactions();
      _fetchBalance();
    }
  }

  void _setupAnimations() {
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _fadeController.forward();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this); // ✅ ADD THIS
    _fadeController.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    _silentRefreshTimer?.cancel();
    _balanceRefreshTimer?.cancel();
    super.dispose();
  }
  // ==================== INITIALIZATION ====================

  Future<void> _initializePage() async {
    try {
      // Load from cache first
      final cachedTransactions = await CacheService.getCachedTransactions();
      if (cachedTransactions.isNotEmpty) {
        debugPrint(
          '📦 Loading ${cachedTransactions.length} transactions from cache',
        );
        setState(() {
          _allTransactions = cachedTransactions;
          _applyFilter();
          _isLoading = false;
        });
      }

      // Fetch fresh data
      await _fetchTransactions();
      await _fetchBalance();
    } catch (e) {
      debugPrint('Error initializing page: $e');
      setState(() {
        _isLoading = false;
        _errorMessage = 'Unable to load transactions. Please try again.';
      });
    }
  }

  // ==================== DATA FETCHING ====================

  Future<void> _fetchTransactions() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final fetchedTransactions = await ApiService.getTransactions();

      if (mounted) {
        debugPrint(
          '✅ Successfully loaded ${fetchedTransactions.length} transactions',
        );
        setState(() {
          _allTransactions = fetchedTransactions;
          _applyFilter();
          _isLoading = false;
          _isRefreshing = false;
        });
        // Cache transactions
        await CacheService.cacheTransactions(fetchedTransactions);
      }
    } catch (e) {
      debugPrint('❌ Error fetching transactions: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isRefreshing = false;
          if (_allTransactions.isEmpty) {
            _errorMessage = 'Unable to load transactions. Please try again.';
          }
        });
      }
    }
  }

  Future<void> _fetchBalance() async {
    try {
      final balance = await ApiService.getBalance();
      if (mounted) {
        setState(() {
          _currentBalance = balance;
          _isBalanceLoading = false;
        });
        await CacheService.cacheBalance(balance);
      }
    } catch (e) {
      debugPrint('Error fetching balance: $e');
      if (mounted) {
        setState(() => _isBalanceLoading = false);
      }
    }
  }

  void _startSilentRefresh() {
    _silentRefreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted && !_isRefreshing) {
        _fetchTransactionsSilently();
      }
    });
  }

  void _startBalanceRefresh() {
    _balanceRefreshTimer = Timer.periodic(const Duration(minutes: 2), (timer) {
      if (mounted) {
        _fetchBalance();
      }
    });
  }

  Future<void> _refreshData() async {
    setState(() => _isRefreshing = true);
    await Future.wait([_fetchTransactions(), _fetchBalance()]);
    if (mounted) {
      setState(() => _isRefreshing = false);
    }
  }

  Future<void> _fetchTransactionsSilently() async {
    try {
      final fetchedTransactions = await ApiService.getTransactions();

      // ✅ ALWAYS update if we got a valid response (even empty list is valid)
      if (mounted && fetchedTransactions.isNotEmpty) {
        // Detect if anything actually changed by comparing statuses
        bool changed = false;
        if (fetchedTransactions.length != _allTransactions.length) {
          changed = true;
        } else {
          for (int i = 0; i < fetchedTransactions.length; i++) {
            final a = fetchedTransactions[i];
            final b = _allTransactions[i];
            if (a['_id']?.toString() != b['_id']?.toString() ||
                a['status']?.toString() != b['status']?.toString()) {
              changed = true;
              break;
            }
          }
        }

        setState(() {
          _allTransactions = fetchedTransactions;
          _applyFilter();
        });

        await CacheService.cacheTransactions(fetchedTransactions);

        debugPrint(
          '🔄 Silent refresh: ${fetchedTransactions.length} transactions'
          '${changed ? " (DATA CHANGED)" : ""}',
        );
      }
    } catch (e) {
      debugPrint('⚠️ Silent refresh failed: $e');
    }
  }

  // ==================== FILTERS ====================

  void _applyFilter() {
    if (!mounted) return;

    List<dynamic> filtered = List.from(_allTransactions);

    // Date range filter
    if (_startDate != null || _endDate != null) {
      filtered = filtered.where((tx) {
        final date = _parseDateTime(tx['createdAt']);
        if (_startDate != null && date.isBefore(_startDate!)) return false;
        if (_endDate != null) {
          final endOfDay = DateTime(_endDate!.year, _endDate!.month, _endDate!.day, 23, 59, 59);
          if (date.isAfter(endOfDay)) return false;
        }
        return true;
      }).toList();
    }

    // Search filter
    final searchTerm = _searchController.text.toLowerCase();
    if (searchTerm.isNotEmpty) {
      filtered = filtered.where((tx) {
        final description = (tx['description']?.toString().toLowerCase() ?? '');
        final type = (tx['type']?.toString().toLowerCase() ?? '');
        final status = (tx['status']?.toString().toLowerCase() ?? '');
        final reference = (tx['reference']?.toString().toLowerCase() ?? '');
        return description.contains(searchTerm) ||
            type.contains(searchTerm) ||
            status.contains(searchTerm) ||
            reference.contains(searchTerm);
      }).toList();
    }

    // Status filter
    if (_selectedFilter != 'All') {
      filtered = filtered.where((tx) {
        final s = _getStatusText(tx);
        if (_selectedFilter == 'Successful') return s == 'Successful' || s == 'Resolved';
        if (_selectedFilter == 'Pending') return s == 'Pending';
        if (_selectedFilter == 'Failed') {
          return s == 'Failed' || s == 'Refunded' || tx['amountBelowMinimum'] == true;
        }
        return true;
      }).toList();
    }

    // Service (type) filter
    if (_typeFilter != 'All services') {
      filtered = filtered.where((tx) {
        if (_typeFilter == 'Commission Credit') {
          return tx['isCommission'] == true || tx['type']?.toString() == 'Commission Credit';
        } else if (_typeFilter == 'Refund Credit') {
          return tx['type']?.toString() == 'Refund Credit' ||
              tx['description']?.toString().contains('Refund') == true;
        } else if (_typeFilter == 'Transfer') {
          return _getActualTransactionType(tx).startsWith('Transfer');
        }
        return _getActualTransactionType(tx) == _typeFilter;
      }).toList();
    }

    // Newest first: updatedAt first (so admin status changes bubble up),
    // then completedAt/createdAt.
    filtered.sort((a, b) {
      final dateA = _parseDateTime(a['updatedAt'] ?? a['completedAt'] ?? a['createdAt']);
      final dateB = _parseDateTime(b['updatedAt'] ?? b['completedAt'] ?? b['createdAt']);
      return dateB.compareTo(dateA);
    });

    setState(() {
      _filteredTransactions = filtered;
    });
  }

  // ==================== HELPERS ====================

  String _getActualTransactionType(Map<String, dynamic> tx) {
    final type = tx['type']?.toString() ?? '';
    final description = tx['description']?.toString() ?? '';
    final isCommission = tx['isCommission'] == true;

    if (type == 'Refund Credit' ||
        description.toLowerCase().contains('refund')) {
      return 'Refund Credit';
    }

    if (isCommission || type.contains('Commission')) {
      final descLower = description.toLowerCase();
      if (descLower.contains('indirect referral')) {
        return 'Indirect Referral Bonus';
      }
      if (descLower.contains('direct referral')) return 'Direct Referral Bonus';
      if (descLower.contains('welcome bonus')) return 'Welcome Bonus';
      if (descLower.contains('first deposit')) return 'First Deposit Bonus';
      if (descLower.contains('airtime')) return 'Airtime Commission Credit';
      if (descLower.contains('data')) return 'Data Commission Credit';
      if (descLower.contains('electricity')) {
        return 'Electricity Commission Credit';
      }
      if (descLower.contains('cable')) return 'Cable TV Commission Credit';
      return 'Service Commission Credit';
    }

    switch (type) {
      case 'Airtime Purchase':
        return 'Airtime Purchase';
      case 'Data Purchase':
        return 'Data Purchase';
      case 'Cable TV Subscription':
        return 'Cable TV Purchase';
      case 'Electricity Payment':
        return 'Electricity Purchase';
      case 'Education Payment':
        return 'Education Purchase';
      case 'Insurance Purchase':
        return 'Insurance Purchase';
      case 'Wallet Funding':
        return 'Fund Wallet';
      case 'Transfer Sent':
        return 'Transfer Sent';
      case 'Transfer Received':
        return 'Transfer Received';
      default:
        final descLower = description.toLowerCase();
        if (descLower.contains('airtime')) return 'Airtime Purchase';
        if (descLower.contains('data')) return 'Data Purchase';
        if (descLower.contains('electricity') || descLower.contains('meter')) {
          return 'Electricity Purchase';
        }
        if (descLower.contains('cable') || descLower.contains('tv')) {
          return 'Cable TV Purchase';
        }
        if (descLower.contains('fund') || descLower.contains('wallet')) {
          return 'Fund Wallet';
        }
        if (descLower.contains('transfer')) return 'Transfer';
        return type.isNotEmpty ? type : 'Other';
    }
  }

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



  // ✅ USING HUGICONS - Same as dashboard services
  DPIconData _getTransactionIcon(String type) {
    final typeLower = type.toLowerCase();
    if (typeLower.contains('international')) return DPIcons.globe;
    if (typeLower.contains('airtime')) return DPIcons.phone;
    if (typeLower.contains('data')) return DPIcons.wifi;
    if (typeLower.contains('electricity')) return DPIcons.zap;
    if (typeLower.contains('cable') || typeLower.contains('tv')) return DPIcons.tv;
    if (typeLower.contains('education')) return DPIcons.graduationCap;
    if (typeLower.contains('insurance')) return DPIcons.umbrella;
    if (typeLower.contains('internet')) return DPIcons.router;
    if (typeLower.contains('transfer received')) return DPIcons.arrowDownLeft;
    if (typeLower.contains('transfer')) return DPIcons.arrowUpRight;
    if (typeLower.contains('commission') || typeLower.contains('bonus')) return DPIcons.sparkles;
    if (typeLower.contains('refund')) return DPIcons.rotateCcw;
    if (typeLower.contains('fund wallet') || typeLower.contains('wallet funding')) {
      return DPIcons.arrowDownLeft;
    }
    return DPIcons.receipt;
  }

  // ✅ Color mapping - Same as dashboard

  String _getCommissionSource(String description) {
    final descLower = description.toLowerCase();
    if (descLower.contains('indirect referral bonus')) {
      return 'Indirect Referral';
    }
    if (descLower.contains('direct referral bonus')) return 'Referral';
    if (descLower.contains('welcome bonus')) return 'Welcome Bonus';
    if (descLower.contains('first deposit bonus')) return 'First Deposit';
    if (descLower.contains('airtime')) return 'Airtime';
    if (descLower.contains('data')) return 'Data';
    if (descLower.contains('electricity')) return 'Electricity';
    if (descLower.contains('cable')) return 'Cable TV';
    return 'Service';
  }

  bool _isCreditTransaction(Map<String, dynamic> tx) {
    final type = _getActualTransactionType(tx);
    return type == 'Refund Credit' ||
        type == 'Fund Wallet' ||
        type == 'Transfer Received' ||
        tx['isCommission'] == true ||
        type.contains('Commission');
  }

  String _getStatusText(Map<String, dynamic> tx) {
    // ✅ PRIORITY 1: Trust the actual `status` field from DB first.
    // The DB is the source of truth. When admin updates status,
    // backend saves it — so we must show that.
    final status = (tx['status'] as String? ?? '').trim();

    if (status.isNotEmpty) {
      switch (status.toLowerCase()) {
        case 'completed':
        case 'success':
        case 'successful':
          return 'Successful';
        case 'pending':
        case 'processing':
          return 'Pending';
        case 'failed':
        case 'cancelled':
          return 'Failed';
        case 'refunded':
          return 'Refunded';
        case 'resolved':
          return 'Resolved';
        default:
          // If status is unknown but non-empty, trust it
          return status;
      }
    }

    // ✅ PRIORITY 2: Only fall back to isFailed flags when status is empty/missing
    if (tx['isFailed'] == true ||
        tx['shouldShowAsFailed'] == true ||
        tx['amountBelowMinimum'] == true) {
      return 'Failed';
    }

    return 'Pending';
  }

  // ==================== UI METHODS ====================

  Future<void> _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      initialDateRange:
          _startDate != null && _endDate != null
              ? DateTimeRange(start: _startDate!, end: _endDate!)
              : null,
    );
    if (picked != null && mounted) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
        _applyFilter();
      });
    }
  }

  void _clearDateFilter() {
    setState(() {
      _startDate = null;
      _endDate = null;
      _applyFilter();
    });
  }

  void _showTransactionDetails(Map<String, dynamic> tx) {
    final type = _getActualTransactionType(tx);
    final amount = (tx['amount'] as num?)?.toStringAsFixed(2) ?? '0.00';
    final status = _getStatusText(tx);
    final transactionId = tx['_id'] ?? tx['transactionId'] ?? 'N/A';
    final reference = tx['reference'] ?? 'N/A';
    final date = _parseDateTime(tx['createdAt']);
    final description = tx['description'] ?? '';
    final isCommission = tx['isCommission'] == true;
    final phone =
        tx['phone']?.toString() ?? tx['metadata']?['phone']?.toString();

    // ✅ Extract balance before and after
    String? balanceBefore;
    String? balanceAfter;

    // Try to get from transaction directly
    final beforeRaw =
        tx['balanceBefore'] ??
        tx['previousBalance'] ??
        tx['oldBalance'] ??
        tx['metadata']?['balanceBefore'] ??
        tx['metadata']?['previousBalance'];

    if (beforeRaw != null) {
      try {
        final numValue =
            beforeRaw is num ? beforeRaw : double.parse(beforeRaw.toString());
        balanceBefore = numValue.toStringAsFixed(2);
      } catch (e) {
        balanceBefore = beforeRaw.toString();
      }
    }

    final afterRaw =
        tx['newBalance'] ??
        tx['balanceAfter'] ??
        tx['metadata']?['newBalance'] ??
        tx['metadata']?['balanceAfter'];

    if (afterRaw != null) {
      try {
        final numValue =
            afterRaw is num ? afterRaw : double.parse(afterRaw.toString());
        balanceAfter = numValue.toStringAsFixed(2);
      } catch (e) {
        balanceAfter = afterRaw.toString();
      }
    }

    // ✅ Extract customer info
    String? customerName;
    String? customerEmail;
    String? customerPhone;
    String? customerUserId;

    if (tx['user'] != null) {
      final user = tx['user'];
      customerName = user['fullName']?.toString();
      customerEmail = user['email']?.toString();
      customerPhone = user['phone']?.toString();
      customerUserId = user['_id']?.toString();
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => Dialog(
            backgroundColor: Colors.transparent,
            elevation: 0,
            child: ReceiptWidget(
              transactionType: type,
              amount: amount,
              status: status,
              transactionId: transactionId,
              reference: reference,
              date: date,
              phoneNumber: phone,
              description: description,
              balanceBefore: balanceBefore, // ✅ Pass balance before
              balanceAfter: balanceAfter, // ✅ Pass balance after
              isCommission: isCommission,
              commissionSource:
                  isCommission ? _getCommissionSource(description) : null,
              primaryColor: const Color(0xFF102C68),
              showWatermark: true,
              isAdminTransaction: false,
              isUserAdmin: false,
              customerName: customerName,
              customerAddress: customerEmail,
              customerPhone: customerPhone,
              customerUserId: customerUserId,
            ),
          ),
    );
  }

  // ==================== BUILD METHODS ====================

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_isLoading && _allTransactions.isEmpty) {
      return const DPPage(
        title: 'Your activity',
        children: [Padding(padding: EdgeInsets.only(top: 80), child: DPLoader(message: 'Loading your activity…'))],
      );
    }

    return DPPage(
      title: 'Your activity',
      actionLabel: _exporting ? 'Exporting…' : 'Export',
      onAction: _exporting || _filteredTransactions.isEmpty ? null : _exportCsv,
      onRefresh: _refreshData,
      controller: _scrollController,
      children: [_buildBody()],
    );
  }


  Widget _buildBody() {
    if (_errorMessage != null && _allTransactions.isEmpty) {
      return _buildErrorState();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildBalanceCard(),
        _buildSearchAndFilters(),
        _buildTransactionsList(),
      ],
    );
  }

  /// Money in / money out for the current month (completed transactions only).
  Widget _buildBalanceCard() {
    final now = DateTime.now();
    double moneyIn = 0, moneyOut = 0;
    for (final raw in _allTransactions) {
      if (raw is! Map<String, dynamic>) continue;
      final d = _parseDateTime(raw['createdAt']).toLocal();
      if (d.year != now.year || d.month != now.month) continue;
      final s = _getStatusText(raw);
      if (s != 'Successful' && s != 'Resolved') continue;
      final amt = (raw['amount'] as num?)?.toDouble() ?? 0;
      if (_isCreditTransaction(raw)) {
        moneyIn += amt;
      } else {
        moneyOut += amt;
      }
    }
    Widget figure(String label, double v, Color c) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: DPText.bodyMuted.copyWith(fontSize: 13)),
              const SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(dpNaira(v, decimals: v % 1 != 0),
                    style: DPText.amount.copyWith(fontSize: 26, color: c)),
              ),
            ],
          ),
        );
    return DPCard(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'THIS MONTH · ${DateFormat('MMMM yyyy').format(now).toUpperCase()}',
                  style: DPText.overline,
                ),
              ),
              if (!_isBalanceLoading && _currentBalance != null)
                Text('Balance ${dpNaira(_currentBalance!)}', style: DPText.small),
            ],
          ),
          const SizedBox(height: 16),
          Row(children: [
            figure('Money in', moneyIn, DP.green),
            const SizedBox(width: 12),
            figure('Money out', moneyOut, DP.ink),
          ]),
        ],
      ),
    );
  }

  Widget _buildSearchAndFilters() {
    final hasRange = _startDate != null && _endDate != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DPField(
          label: 'Find a transaction',
          controller: _searchController,
          hint: 'Search name or reference',
          suffixIcon: _searchController.text.isNotEmpty ? DPIcons.x : DPIcons.search,
          onSuffixTap: _searchController.text.isNotEmpty
              ? () {
                  _searchController.clear();
                  _applyFilter();
                }
              : null,
          onChanged: (_) => _applyFilter(),
          margin: const EdgeInsets.only(bottom: 14),
        ),
        DPChipGrid(
          labels: _filters.map((f) => f == 'Successful' ? 'Success' : f).toList(),
          columns: 4,
          height: 40,
          spacing: 8,
          selectedIndex: _filters.indexOf(_selectedFilter),
          onSelected: (i) {
            _selectedFilter = _filters[i];
            _applyFilter();
          },
          margin: const EdgeInsets.only(bottom: 10),
        ),
        Row(
          children: [
            Expanded(
              child: DPChip(
                label: _typeFilter,
                selected: _typeFilter != 'All services',
                dense: true,
                height: 38,
                leading: const DPIcon(DPIcons.listFilter, size: 16, color: DP.ink2),
                onTap: _pickTypeFilter,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DPChip(
                label: hasRange
                    ? '${DateFormat('d MMM').format(_startDate!)} – ${DateFormat('d MMM').format(_endDate!)}'
                    : 'Any date',
                selected: hasRange,
                dense: true,
                height: 38,
                leading: const DPIcon(DPIcons.calendar, size: 16, color: DP.ink2),
                onTap: hasRange ? _clearDateFilter : _selectDateRange,
              ),
            ),
          ],
        ),
        if (hasRange)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('Tap the date again to clear it.', style: DPText.small),
          ),
      ],
    );
  }

  void _pickTypeFilter() {
    showDPSheet(
      context,
      title: 'Filter by service',
      builder: (ctx) => Column(
        children: [
          for (final t in _typeFilters)
            DPOptionRow(
              leading: DPIcon(t == 'All services' ? DPIcons.layoutGrid : _getTransactionIcon(t),
                  size: 20, color: DP.blue),
              title: t.replaceAll(' Purchase', '').replaceAll('Fund Wallet', 'Wallet top-up'),
              selected: _typeFilter == t,
              onTap: () {
                Navigator.pop(ctx);
                _typeFilter = t;
                _applyFilter();
              },
            ),
        ],
      ),
    );
  }

  String _dayLabel(DateTime d) {
    final local = d.toLocal();
    final today = DateTime.now();
    final day = DateTime(local.year, local.month, local.day);
    final t0 = DateTime(today.year, today.month, today.day);
    final diff = t0.difference(day).inDays;
    final base = DateFormat('d MMMM').format(local);
    if (diff == 0) return 'Today, $base';
    if (diff == 1) return 'Yesterday, $base';
    if (local.year != today.year) return DateFormat('EEEE, d MMMM yyyy').format(local);
    return DateFormat('EEEE, d MMMM').format(local);
  }

  String _displayTitle(Map<String, dynamic> tx, String type) {
    final description = (tx['description'] ?? '').toString().trim();
    if (description.isNotEmpty && description.length <= 42) return description;
    switch (type) {
      case 'Fund Wallet':
        return 'Wallet top-up';
      case 'Transfer Sent':
        return 'Money sent';
      case 'Transfer Received':
        return 'Money received';
      default:
        return type.replaceAll(' Purchase', '');
    }
  }

  Future<void> _exportCsv() async {
    setState(() => _exporting = true);
    try {
      String esc(Object? v) => '"${(v ?? '').toString().replaceAll('"', '""')}"';
      final b = StringBuffer('Date,Type,Description,Amount,Direction,Status,Reference\n');
      for (final raw in _filteredTransactions) {
        if (raw is! Map<String, dynamic>) continue;
        final d = _parseDateTime(raw['createdAt']).toLocal();
        b.writeln([
          esc(DateFormat('yyyy-MM-dd HH:mm').format(d)),
          esc(_getActualTransactionType(raw)),
          esc(raw['description']),
          esc((raw['amount'] as num?)?.toStringAsFixed(2) ?? '0.00'),
          esc(_isCreditTransaction(raw) ? 'In' : 'Out'),
          esc(_getStatusText(raw)),
          esc(raw['reference']),
        ].join(','));
      }
      final dir = await getTemporaryDirectory();
      final file = File(
          '${dir.path}/dalabapay-activity-${DateFormat('yyyyMMdd-HHmm').format(DateTime.now())}.csv');
      await file.writeAsString(b.toString());
      await Share.shareXFiles([XFile(file.path, mimeType: 'text/csv')],
          subject: 'Dalabapay activity');
    } catch (e) {
      if (mounted) dpSnack(context, 'Could not export your activity. Please try again.', error: true);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Widget _buildTransactionsList() {
    if (_isRefreshing && _filteredTransactions.isEmpty) {
      return const Padding(padding: EdgeInsets.only(top: 40), child: DPLoader());
    }
    if (_filteredTransactions.isEmpty) return _buildEmptyState();

    final children = <Widget>[];
    String? lastDay;
    for (final raw in _filteredTransactions) {
      if (raw is! Map<String, dynamic>) continue;
      final date = _parseDateTime(raw['updatedAt'] ?? raw['completedAt'] ?? raw['createdAt']);
      final label = _dayLabel(date);
      if (label != lastDay) {
        children.add(DPSectionHeader(label,
            padding: EdgeInsets.only(top: lastDay == null ? 22 : 18, bottom: 6)));
        lastDay = label;
      }
      children.add(_buildTransactionItem(raw));
    }
    children.add(Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Text('Only completed payments affect your balance.',
          style: DPText.small, textAlign: TextAlign.center),
    ));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }

  Widget _buildTransactionItem(Map<String, dynamic> tx) {
    final type = _getActualTransactionType(tx);
    final amount = (tx['amount'] as num?)?.toDouble() ?? 0;
    final status = _getStatusText(tx);
    final date = _parseDateTime(tx['createdAt']).toLocal();
    final isCredit = _isCreditTransaction(tx);
    final failed = status == 'Failed';
    final refunded = status == 'Refunded';
    final when = DateFormat('h:mm a').format(date);
    String sub = '$when · $status';
    if (failed || refunded) sub += ' · No debit';
    if (type == 'Fund Wallet' && status == 'Successful') sub = '$when · Bank transfer';
    final amountText = dpNaira(amount, decimals: amount % 1 != 0);
    return DPTransactionTile(
      icon: _getTransactionIcon(type),
      title: _displayTitle(tx, type),
      subtitle: sub,
      amount: failed || refunded ? amountText : '${isCredit ? '+' : '−'}$amountText',
      credit: isCredit && !failed,
      failed: failed || refunded,
      onTap: () => _showTransactionDetails(tx),
    );
  }

  Widget _buildEmptyState() {
    final filtered = _allTransactions.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: DPEmptyState(
        icon: filtered ? DPIcons.search : DPIcons.receipt,
        title: filtered ? 'No matching transactions' : 'No transactions yet',
        message: filtered
            ? 'Try a different search, status or date.'
            : 'Your payments, top-ups and transfers will appear here.',
        actionLabel: filtered ? 'Clear filters' : null,
        onAction: filtered
            ? () {
                _searchController.clear();
                _selectedFilter = 'All';
                _typeFilter = 'All services';
                _startDate = null;
                _endDate = null;
                _applyFilter();
              }
            : null,
      ),
    );
  }

  Widget _buildErrorState() {
    return Padding(
      padding: const EdgeInsets.only(top: 40),
      child: DPEmptyState(
        icon: DPIcons.circleAlert,
        title: 'Something went wrong',
        message: _errorMessage ?? 'Unable to load transactions',
        actionLabel: 'Try again',
        onAction: _refreshData,
      ),
    );
  }
}
