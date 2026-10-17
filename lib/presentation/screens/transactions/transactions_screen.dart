// lib/presentation/screens/transactions/transactions_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../core/services/api_service.dart';
import '../../../core/services/cache_service.dart';
import '../../../core/widgets/receipt_widget.dart';

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
      filtered =
          filtered.where((tx) {
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
      filtered =
          filtered.where((tx) {
            final description =
                (tx['description']?.toString().toLowerCase() ?? '');
            final type = (tx['type']?.toString().toLowerCase() ?? '');
            final status = (tx['status']?.toString().toLowerCase() ?? '');
            final reference = (tx['reference']?.toString().toLowerCase() ?? '');
            return description.contains(searchTerm) ||
                type.contains(searchTerm) ||
                status.contains(searchTerm) ||
                reference.contains(searchTerm);
          }).toList();
    }

    // Type filter
    if (_selectedFilter != 'All') {
      filtered =
          filtered.where((tx) {
            if (_selectedFilter == 'Commission Credit') {
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

    // Sort by date (newest first)
    // ✅ Sort by updatedAt first (so admin status changes bubble up),
    // then fall back to completedAt/createdAt
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

    debugPrint(
      '📊 Filter applied: ${_filteredTransactions.length} transactions (total: ${_allTransactions.length})',
    );
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
        return const Color(0xFF219C7E);
      case 'pending':
      case 'processing':
        return Colors.orange;
      case 'failed':
      case 'cancelled':
        return Colors.red;
      case 'refunded':
        return const Color(0xFF8B5CF6);
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
  dynamic _getTransactionIcon(String type) {
    final typeLower = type.toLowerCase();

    // Airtime - matches dashboard "Airtime" service icon
    if (typeLower.contains('airtime')) {
      return HugeIcons.strokeRoundedSmartPhone01;
    }
    // Data - matches dashboard "Data" service icon
    if (typeLower.contains('data')) {
      return HugeIcons.strokeRoundedWifi01;
    }
    // Electricity - matches dashboard "Electricity" service icon
    if (typeLower.contains('electricity')) {
      return HugeIcons.strokeRoundedBulb;
    }
    // Cable TV - matches dashboard "Cable TV" service icon
    if (typeLower.contains('cable') || typeLower.contains('tv')) {
      return HugeIcons.strokeRoundedTv01;
    }
    // Education - matches dashboard "Education" service icon
    if (typeLower.contains('education')) {
      return HugeIcons.strokeRoundedMortarboard01;
    }
    // Insurance - matches dashboard "Insurance" service icon
    if (typeLower.contains('insurance')) {
      return HugeIcons.strokeRoundedShield01;
    }
    // Transfer - matches dashboard "Wallet Transfer" service icon
    if (typeLower.contains('transfer sent')) {
      return HugeIcons.strokeRoundedTelegram;
    }
    if (typeLower.contains('transfer received')) {
      return HugeIcons.strokeRoundedDownload03;
    }
    if (typeLower.contains('transfer')) {
      return HugeIcons.strokeRoundedSquareArrowDataTransferHorizontal;
    }
    // Fund Wallet - matches dashboard wallet icon
    if (typeLower.contains('fund wallet') ||
        typeLower.contains('wallet funding')) {
      return HugeIcons.strokeRoundedWallet01;
    }
    // Commission - matches dashboard "Commission" service icon
    if (typeLower.contains('commission')) {
      return HugeIcons.strokeRoundedPercent;
    }
    // Refund
    if (typeLower.contains('refund')) {
      return HugeIcons.strokeRoundedCash01;
    }
    // Default - matches dashboard receipt icon
    return HugeIcons.strokeRoundedReceiptText;
  }

  // ✅ Color mapping - Same as dashboard
  Color _getTransactionColor(String type) {
    final typeLower = type.toLowerCase();

    if (typeLower.contains('commission')) {
      return const Color(0xFF219C7E);
    }
    if (typeLower.contains('fund wallet') ||
        typeLower.contains('wallet funding')) {
      return const Color(0xFF219C7E);
    }
    if (typeLower.contains('transfer received')) return const Color(0xFF219C7E);
    if (typeLower.contains('refund')) return const Color(0xFF219C7E);
    if (typeLower.contains('airtime')) return const Color(0xFF4A90E2);
    if (typeLower.contains('data')) return const Color(0xFF9B59B6);
    if (typeLower.contains('electricity')) return const Color(0xFFF39C12);
    if (typeLower.contains('cable') || typeLower.contains('tv')) {
      return const Color(0xFFE74C3C);
    }
    if (typeLower.contains('education')) return const Color(0xFF2ECC71);
    if (typeLower.contains('insurance')) return const Color(0xFF1ABC9C);
    if (typeLower.contains('transfer sent')) return Colors.orange;
    if (typeLower.contains('transfer')) return Colors.orange;
    if (typeLower.contains('failed')) return Colors.red;

    return const Color(0xFF243889);
  }

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
              primaryColor: const Color(0xFF243889),
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
      backgroundColor: Colors.white,
      appBar: _buildAppBar(),
      body: _buildBody(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(
          Icons.arrow_back_ios,
          color: Color(0xFF243889),
          size: 20,
        ),
        onPressed: () => Navigator.pop(context),
      ),
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Dalaba',
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF243889),
              letterSpacing: 0.09,
            ),
          ),
          Text(
            'pay',
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF219C7E),
              letterSpacing: 0.09,
            ),
          ),
        ],
      ),
      centerTitle: true,
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh, color: Color(0xFF243889), size: 22),
          onPressed: _refreshData,
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF243889)),
        ),
      );
    }

    if (_errorMessage != null && _allTransactions.isEmpty) {
      return _buildErrorState();
    }

    return Column(
      children: [
        _buildBalanceCard(),
        _buildSearchAndFilters(),
        Expanded(child: _buildTransactionsList()),
      ],
    );
  }

  Widget _buildBalanceCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFF92D394), Color(0xFF1E377E)],
          stops: [0.06, 0.41],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF219C7E).withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.account_balance_wallet_rounded,
                color: Colors.white,
                size: 28,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Available Balance',
                    style: GoogleFonts.inter(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (_isBalanceLoading)
                    SizedBox(
                      width: 120,
                      height: 24,
                      child: LinearProgressIndicator(
                        backgroundColor: Colors.white24,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Colors.white,
                        ),
                      ),
                    )
                  else
                    Text(
                      '₦${_currentBalance?.toStringAsFixed(2) ?? '0.00'}',
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white, size: 20),
              onPressed: _fetchBalance,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchAndFilters() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search transactions...',
              hintStyle: GoogleFonts.poppins(
                color: Colors.grey.shade400,
                fontSize: 14,
              ),
              prefixIcon: const Icon(
                Icons.search,
                color: Color(0xFF243889),
                size: 20,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: Colors.grey.shade50,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              suffixIcon:
                  _searchController.text.isNotEmpty
                      ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          _applyFilter();
                        },
                      )
                      : null,
            ),
            style: GoogleFonts.poppins(fontSize: 14),
            onChanged: (_) => _applyFilter(),
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: _selectDateRange,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.calendar_today,
                          color: const Color(0xFF243889),
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _startDate != null && _endDate != null
                                ? '${DateFormat('MMM dd').format(_startDate!)} - ${DateFormat('MMM dd, yyyy').format(_endDate!)}'
                                : 'Select Date Range',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              color:
                                  (_startDate != null && _endDate != null)
                                      ? const Color(0xFF243889)
                                      : Colors.grey.shade400,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (_startDate != null && _endDate != null)
                          IconButton(
                            icon: const Icon(Icons.close, size: 16),
                            onPressed: _clearDateFilter,
                            padding: EdgeInsets.zero,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          SizedBox(
            height: 38,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _filters.length,
              itemBuilder: (context, index) {
                final filter = _filters[index];
                final isSelected = _selectedFilter == filter;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(
                      filter,
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() {
                        _selectedFilter = selected ? filter : 'All';
                        _applyFilter();
                      });
                    },
                    backgroundColor: Colors.white,
                    selectedColor: const Color(
                      0xFF243889,
                    ).withValues(alpha: 0.1),
                    checkmarkColor: const Color(0xFF243889),
                    labelStyle: TextStyle(
                      color:
                          isSelected
                              ? const Color(0xFF243889)
                              : Colors.grey.shade600,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: BorderSide(
                        color:
                            isSelected
                                ? const Color(0xFF243889)
                                : Colors.grey.shade300,
                      ),
                    ),
                    elevation: 0,
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildTransactionsList() {
    if (_isRefreshing) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF243889)),
            strokeWidth: 2,
          ),
        ),
      );
    }

    if (_filteredTransactions.isEmpty) {
      return _buildEmptyState();
    }

    return RefreshIndicator(
      onRefresh: _refreshData,
      color: const Color(0xFF243889),
      backgroundColor: Colors.white,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.only(bottom: 16),
        itemCount: _filteredTransactions.length,
        itemBuilder: (context, index) {
          final tx = _filteredTransactions[index];
          return _buildTransactionItem(tx);
        },
      ),
    );
  }

  Widget _buildTransactionItem(Map<String, dynamic> tx) {
    final type = _getActualTransactionType(tx);
    final amount = (tx['amount'] as num?)?.toStringAsFixed(2) ?? '0.00';
    final status = _getStatusText(tx);
    final date = _parseDateTime(tx['createdAt']);
    final description = tx['description'] ?? '';
    final isCredit = _isCreditTransaction(tx);
    final isPending = status == 'Pending';
    final isFailed = status == 'Failed';
    final icon = _getTransactionIcon(type);
    final iconColor = _getTransactionColor(type);
    final statusColor = _getStatusColor(status, tx);

    return GestureDetector(
      onTap: () => _showTransactionDetails(tx),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // ✅ Using HugeIcon - Same as dashboard
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: HugeIcon(icon: icon, size: 24, color: iconColor),
            ),
            const SizedBox(width: 12),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    type,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF1C2D5A),
                    ),
                  ),
                  if (description.isNotEmpty)
                    Text(
                      description.length > 40
                          ? '${description.substring(0, 40)}...'
                          : description,
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        color: Colors.grey.shade500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  const SizedBox(height: 2),
                  Text(
                    _formatDate(date),
                    style: GoogleFonts.poppins(
                      fontSize: 10,
                      color: Colors.grey.shade400,
                    ),
                  ),
                ],
              ),
            ),

            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${isCredit ? '+' : '-'}₦$amount',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isCredit ? const Color(0xFF219C7E) : Colors.red,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isPending)
                        SizedBox(
                          width: 8,
                          height: 8,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              statusColor,
                            ),
                          ),
                        )
                      else if (isFailed)
                        Icon(Icons.error_outline, color: statusColor, size: 10)
                      else
                        Icon(
                          Icons.check_circle_outline,
                          color: statusColor,
                          size: 10,
                        ),
                      const SizedBox(width: 4),
                      Text(
                        status,
                        style: GoogleFonts.poppins(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: statusColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            HugeIcon(
              icon: HugeIcons.strokeRoundedReceiptText,
              size: 64,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 16),
            Text(
              'No Transactions Yet',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF243889),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your transactions will appear here',
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: Colors.grey.shade500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red.shade300),
            const SizedBox(height: 16),
            Text(
              'Something went wrong',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF243889),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage ?? 'Unable to load transactions',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: Colors.grey.shade500,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _refreshData,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF243889),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                'Try Again',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
