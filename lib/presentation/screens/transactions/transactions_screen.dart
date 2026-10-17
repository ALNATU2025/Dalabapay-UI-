// lib/presentation/screens/transactions/transactions_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/services/api_service.dart';
import '../../../core/services/cache_service.dart';
import '../../../core/widgets/receipt_widget.dart';
import 'dart:convert' show utf8;
import 'dart:typed_data';
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
  final List<String> _filters = [
    'All',
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
    'Pending',
    'Failed',
  ];

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
          final endOfDay = DateTime(
            _endDate!.year,
            _endDate!.month,
            _endDate!.day,
            23,
            59,
            59,
          );
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

    // Type / status filter
    if (_selectedFilter != 'All') {
      filtered = filtered.where((tx) {
        if (_selectedFilter == 'Successful') {
          return _getStatusText(tx) == 'Successful';
        } else if (_selectedFilter == 'Commission Credit') {
          return tx['isCommission'] == true ||
              tx['type']?.toString() == 'Commission Credit';
        } else if (_selectedFilter == 'Refund Credit') {
          return tx['type']?.toString() == 'Refund Credit' ||
              tx['description']?.toString().contains('Refund') == true;
        } else if (_selectedFilter == 'Pending') {
          final status = (tx['status'] as String? ?? '').toLowerCase();
          return status == 'pending' || status == 'processing';
        } else if (_selectedFilter == 'Failed') {
          final status = (tx['status'] as String? ?? '').toLowerCase();
          return status == 'failed' ||
              status == 'cancelled' ||
              tx['isFailed'] == true ||
              tx['amountBelowMinimum'] == true;
        } else {
          return _getActualTransactionType(tx) == _selectedFilter;
        }
      }).toList();
    }

    // Newest first (updatedAt so admin status changes bubble up)
    filtered.sort((a, b) {
      final dateA = _parseDateTime(
        a['updatedAt'] ?? a['completedAt'] ?? a['createdAt'],
      );
      final dateB = _parseDateTime(
        b['updatedAt'] ?? b['completedAt'] ?? b['createdAt'],
      );
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

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      if (difference.inHours == 0) {
        if (difference.inMinutes == 0) return 'Just now';
        return '${difference.inMinutes} min ago';
      }
      return '${difference.inHours} hour${difference.inHours > 1 ? 's' : ''} ago';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else {
      return DateFormat('dd/MM/yyyy').format(date);
    }
  }

  Color _getStatusColor(String status, Map<String, dynamic> tx) {
    // ✅ PRIORITY 1: Trust status string
    switch (status.toLowerCase()) {
      case 'completed':
      case 'success':
      case 'successful':
      case 'resolved':
        return const Color(0xFF079A68);
      case 'pending':
      case 'processing':
        return Colors.orange;
      case 'failed':
      case 'cancelled':
        return Colors.red;
      case 'refunded':
        return const Color(0xFF2563EB);
    }

    // ✅ PRIORITY 2: Fall back to flags only if status was unknown
    if (tx['isFailed'] == true ||
        tx['shouldShowAsFailed'] == true ||
        tx['amountBelowMinimum'] == true) {
      return Colors.red;
    }

    return Colors.grey;
  }

  // ✅ USING HUGICONS - Same as dashboard services
  IconData _getTransactionIcon(String type) {
    final t = type.toLowerCase();
    if (t.contains('international')) return DPIcons.globe;
    if (t.contains('airtime')) return DPIcons.phone;
    if (t.contains('data') || t.contains('internet')) return DPIcons.wifi;
    if (t.contains('electric')) return DPIcons.bolt;
    if (t.contains('cable') || t.contains('tv')) return DPIcons.tv;
    if (t.contains('education')) return DPIcons.school;
    if (t.contains('insurance')) return DPIcons.shield;
    if (t.contains('transfer received')) return DPIcons.downLeft;
    if (t.contains('transfer')) return DPIcons.upRight;
    if (t.contains('fund wallet') || t.contains('wallet funding')) {
      return DPIcons.downLeft;
    }
    if (t.contains('commission') || t.contains('bonus')) return DPIcons.sparkle;
    if (t.contains('refund')) return DPIcons.refresh;
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
              primaryColor: const Color(0xFF15368A),
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

    return Scaffold(
      backgroundColor: DP.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            DPTopBar(
              title: 'My Wallet',
              actionLabel: 'Export',
              onAction: _exportCsv,
            ),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
      bottomNavigationBar: DPBottomNav(
        index: 1,
        items: kDPTabs,
        onCenter: () => Navigator.of(context).maybePop('send'),
        // Home owns the tabs: tell it which one to show when we close.
        onTap: (i) {
          if (i == 1) return;
          Navigator.of(context).maybePop(
            const ['home', 'transactions', 'services', 'profile'][i],
          );
        },
      ),
    );
  }

  Future<void> _exportCsv() async {
    if (_filteredTransactions.isEmpty) {
      dpSnack(context, 'There\'s nothing to export yet.');
      return;
    }
    String esc(Object? v) {
      final s = (v ?? '').toString().replaceAll('"', '""');
      return '"$s"';
    }

    final buf = StringBuffer()
      ..writeln('Date,Description,Type,Status,Amount (NGN),Reference');
    for (final raw in _filteredTransactions) {
      final tx = Map<String, dynamic>.from(raw as Map);
      final date = _parseDateTime(tx['createdAt']).toLocal();
      final credit = _isCreditTransaction(tx);
      final amount = (tx['amount'] as num?)?.toDouble() ?? 0;
      buf.writeln([
        esc(DateFormat('yyyy-MM-dd HH:mm').format(date)),
        esc(tx['description']),
        esc(_getActualTransactionType(tx)),
        esc(_getStatusText(tx)),
        esc('${credit ? '' : '-'}${amount.toStringAsFixed(2)}'),
        esc(tx['reference'] ?? tx['transactionId'] ?? ''),
      ].join(','));
    }
    try {
      final bytes = Uint8List.fromList(utf8.encode(buf.toString()));
      await Share.shareXFiles([
        XFile.fromData(
          bytes,
          mimeType: 'text/csv',
          name: 'dalabapay_activity.csv',
        ),
      ], text: 'Dalabapay activity');
    } catch (e) {
      if (mounted) dpSnack(context, 'Couldn\'t export. Please try again.', error: true);
    }
  }

  Widget _buildBody() {
    if (_isLoading && _allTransactions.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null && _allTransactions.isEmpty) {
      return _buildErrorState();
    }

    return RefreshIndicator(
      color: DP.green,
      onRefresh: _refreshData,
      child: CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DPAppear(scaleFrom: 0.97, child: _buildBalanceCard()),
                  const SizedBox(height: 22),
                  const DPSectionHeader('Recent Transactions'),
                  _buildSearchAndFilters(),
                ],
              ),
            ),
          ),
          _buildTransactionsList(),
          const SliverPadding(
            padding: EdgeInsets.fromLTRB(24, 8, 24, 28),
            sliver: SliverToBoxAdapter(
              child: Text(
                'Only completed payments affect your balance.',
                textAlign: TextAlign.center,
                style: DP.caption,
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _balanceHidden = false;

  void _openWallet(String tab) {
    Navigator.pushNamed(
      context,
      '/wallet',
      arguments: {
        'userId': widget.userId,
        'initialTab': tab,
        'onBalanceUpdate': (double v) {
          if (mounted) setState(() => _currentBalance = v);
        },
      },
    ).then((_) => _refreshData());
  }

  /// Green wallet card from the design (balance + Add / Send money).
  Widget _buildBalanceCard() {
    const balanceStyle = TextStyle(
      color: Colors.white,
      fontSize: 28,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.4,
      fontFeatures: [FontFeature.tabularFigures()],
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        gradient: DP.greenGradient,
        borderRadius: BorderRadius.circular(DP.rXl),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33079A68),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Wallet Balance',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.88),
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              InkResponse(
                radius: 20,
                onTap: () => setState(() => _balanceHidden = !_balanceHidden),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    _balanceHidden ? DPIcons.eyeOff : DPIcons.eye,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 38,
            child: Align(
              alignment: Alignment.centerLeft,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: _currentBalance == null
                    ? const Text('₦ —', style: balanceStyle)
                    : _balanceHidden
                        ? const Text('₦ ••••••', style: balanceStyle)
                        : DPCountUp(
                            value: _currentBalance!,
                            format: (v) => DP.naira(v),
                            style: balanceStyle,
                          ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: DPButton(
                  label: 'Add Money',
                  leadingIcon: DPIcons.plus,
                  height: 46,
                  background: Colors.white,
                  foreground: DP.green,
                  onPressed: () => _openWallet('add_money'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DPButton(
                  label: 'Send Money',
                  leadingIcon: DPIcons.plus,
                  height: 46,
                  background: DP.blue,
                  onPressed: () => _openWallet('transfer'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSearchAndFilters() {
    const statusChips = ['All', 'Successful', 'Pending', 'Failed'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _searchController,
          onChanged: (_) => _applyFilter(),
          textInputAction: TextInputAction.search,
          decoration: DPField.decoration(
            hint: 'Search name or reference',
            prefix: const Icon(DPIcons.search, size: 20),
            suffix: _searchController.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(DPIcons.close),
                    onPressed: () {
                      _searchController.clear();
                      _applyFilter();
                    },
                  ),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: DPChipRow(
                options: statusChips,
                selected: statusChips.contains(_selectedFilter)
                    ? _selectedFilter
                    : null,
                spacing: 8,
                height: 40,
                onSelect: (f) => setState(() {
                  _selectedFilter = f;
                  _applyFilter();
                }),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 36,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final f in _filters.where(
                      (f) => !statusChips.contains(f),
                    ))
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: DPChip(
                          label: f
                              .replaceAll(' Purchase', '')
                              .replaceAll(' Credit', ''),
                          selected: _selectedFilter == f,
                          height: 36,
                          onTap: () => setState(() {
                            _selectedFilter =
                                _selectedFilter == f ? 'All' : f;
                            _applyFilter();
                          }),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            DPIconSquare(
              icon: DPIcons.calendar,
              size: 36,
              color: _startDate != null ? DP.green : DP.ink,
              semanticLabel: 'Filter by date',
              onTap: _selectDateRange,
            ),
          ],
        ),
        if (_startDate != null) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${DateFormat('d MMM').format(_startDate!)} – ${DateFormat('d MMM yyyy').format(_endDate ?? _startDate!)}',
                  style: DP.caption,
                ),
              ),
              DPTextLink(label: 'Clear dates', onTap: _clearDateFilter),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildTransactionsList() {
    if (_filteredTransactions.isEmpty) {
      return SliverToBoxAdapter(child: _buildEmptyState());
    }
    final items = [
      for (final raw in _filteredTransactions)
        Map<String, dynamic>.from(raw as Map),
    ];
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, i) => Column(
            children: [
              if (i > 0) const Divider(height: 1, color: DP.borderSoft),
              _buildTransactionItem(items[i]),
            ],
          ),
          childCount: items.length,
        ),
      ),
    );
  }

  Widget _buildTransactionItem(Map<String, dynamic> tx) {
    final type = _getActualTransactionType(tx);
    final isCredit = _isCreditTransaction(tx);
    final amount = (tx['amount'] as num?)?.toDouble() ?? 0;
    final status = _getStatusText(tx);
    final date = _parseDateTime(tx['createdAt']).toLocal();
    final description = (tx['description']?.toString().isNotEmpty == true)
        ? tx['description'].toString()
        : type;
    final failed = status == 'Failed';
    final highlighted = widget.highlightReference != null &&
        widget.highlightReference == tx['reference']?.toString();
    final statusColor = DPStatus.colorFor(status);
    final amountColor = failed ? DP.muted : (isCredit ? DP.green : DP.red);
    return Container(
      decoration: highlighted
          ? BoxDecoration(
              color: DP.mint,
              borderRadius: BorderRadius.circular(DP.rMd),
            )
          : null,
      child: DPListRow(
        onTap: () => _showTransactionDetails(tx),
        padding: const EdgeInsets.symmetric(vertical: 12),
        subtitleMaxLines: 2,
        leading: DPIconBadge(
          _getTransactionIcon(type),
          size: 46,
          iconSize: 21,
          color: failed ? DP.muted : (isCredit ? DP.green : DP.red),
          background: failed ? DP.borderSoft : (isCredit ? DP.mint : DP.redBg),
        ),
        title: description,
        subtitle:
            '$type${status != 'Successful' ? ' · $status' : ''}\n${DateFormat('MMM d, yyyy  •  hh:mm a').format(date)}',
        trailing: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${failed ? '' : (isCredit ? '+ ' : '- ')}${DP.naira(amount)}',
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
                color: amountColor,
                decoration: failed ? TextDecoration.lineThrough : null,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            if (status != 'Successful')
              Text(
                failed ? 'No debit' : status,
                style: TextStyle(fontSize: 11.5, color: statusColor),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final filtering = _selectedFilter != 'All' ||
        _searchController.text.isNotEmpty ||
        _startDate != null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: DPEmptyState(
        icon: DPIcons.receipt,
        title: filtering ? 'No matching transactions' : 'No activity yet',
        message: filtering
            ? 'Try a different search or filter.'
            : 'Your payments and top-ups will show up here.',
        actionLabel: filtering ? 'Clear filters' : null,
        onAction: filtering
            ? () => setState(() {
                  _selectedFilter = 'All';
                  _searchController.clear();
                  _startDate = null;
                  _endDate = null;
                  _applyFilter();
                })
            : null,
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: DPEmptyState(
          icon: DPIcons.alert,
          title: 'Couldn\'t load your activity',
          message: _errorMessage ?? 'Please check your connection and try again.',
          actionLabel: 'Try again',
          onAction: _fetchTransactions,
        ),
      ),
    );
  }
}
