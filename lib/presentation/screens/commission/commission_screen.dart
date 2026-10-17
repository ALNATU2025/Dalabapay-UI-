// lib/presentation/screens/commission/commission_screen.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/services/api_service.dart';
import '../../../core/widgets/receipt_widget.dart';
// ✅ Use the correct class from referral_screen.dart - ReferralEarningsPage
import '../referral/referral_screen.dart';
import 'package:share_plus/share_plus.dart';
import '../../../ui/ui.dart';

class CommissionScreen extends StatefulWidget {
  final void Function(double newBalance) onBalanceUpdate;
  final String userId;

  const CommissionScreen({
    super.key,
    required this.onBalanceUpdate,
    required this.userId,
  });

  @override
  State<CommissionScreen> createState() => _CommissionScreenState();
}

class _CommissionScreenState extends State<CommissionScreen>
    with SingleTickerProviderStateMixin {
  // Controllers
  final TextEditingController _pinController = TextEditingController();
  final FocusNode _pinFocusNode = FocusNode();

  // State Variables
  double _commissionBalance = 0.0;
  double _walletBalance = 0.0;
  bool _isLoading = true;
  bool _isWithdrawing = false;
  bool _isBalanceVisible = true;
  bool _isCommissionVisible = true;

  // Authentication State
  final bool _useBiometric = false;

  // Animation
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  // Data
  List<Map<String, dynamic>> _commissionTransactions = [];
  Map<String, dynamic> _referralStats = {};
  String _referralCode = 'N/A';

  // Filters
  String _selectedTimeFilter = 'All';
  final List<String> _timeFilters = ['All', 'Today', 'This Week', 'This Month'];
  String _selectedTypeFilter = 'All';
  final List<String> _typeFilters = ['All', 'Credit', 'Debit'];

  // Cache
  bool _hasLoadedOnce = false;

  @override
  void initState() {
    super.initState();
    debugPrint('🔵 COMMISSION SCREEN INIT - widget.userId: ${widget.userId}');
    _setupAnimations();

    // ✅ Load referral code first
    _loadReferralCode();

    _loadBalances();
    _loadCachedData();
    _fetchCommissionData();
  }

  void _setupAnimations() {
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeIn,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOutCubic),
    );
    _fadeController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _pinController.dispose();
    _pinFocusNode.dispose();
    super.dispose();
  }

  // ==================== REFERRAL CODE - EXACTLY LIKE DASHBOARD ====================
  Future<void> _loadReferralCode() async {
    try {
      debugPrint('🔍 LOADING REFERRAL CODE...');

      final prefs = await SharedPreferences.getInstance();
      final userString = prefs.getString('user');

      String userId = widget.userId;

      // ✅ If widget.userId is empty, try to get userId from the user object
      if (userId.isEmpty || userId == 'N/A') {
        debugPrint(
          '🔍 widget.userId is empty, trying to get userId from user object',
        );
        if (userString != null) {
          final userMap = jsonDecode(userString) as Map<String, dynamic>;
          userId = userMap['_id']?.toString() ?? '';
          debugPrint('🔍 Retrieved userId from user object: $userId');
        }
      }

      if (userString != null) {
        final userMap = jsonDecode(userString) as Map<String, dynamic>;
        debugPrint('🔍 userMap keys: ${userMap.keys}');

        // ✅ Try to get referral code from user object
        final referralCodeFromUser = userMap['referralCode']?.toString();
        if (referralCodeFromUser != null &&
            referralCodeFromUser.isNotEmpty &&
            referralCodeFromUser != 'N/A') {
          setState(() {
            _referralCode = referralCodeFromUser;
          });
          debugPrint('🔍 Referral code found in user object: $_referralCode');
        } else {
          debugPrint('🔍 No referral code in user object');
        }
      }

      // ✅ Try API only if we have a valid userId
      if (userId.isNotEmpty && userId != 'N/A') {
        debugPrint(
          '🔍 Calling ApiService.getStoredReferralCode with userId: $userId',
        );
        try {
          final storedReferralCode = await ApiService.getStoredReferralCode(
            userId,
          );
          debugPrint('🔍 API returned: "$storedReferralCode"');

          if (storedReferralCode.isNotEmpty && storedReferralCode != 'N/A') {
            setState(() {
              _referralCode = storedReferralCode;
            });
            debugPrint('🔍 After API update: _referralCode = $_referralCode');

            // ✅ Save to user object
            if (userString != null) {
              final userMap = jsonDecode(userString) as Map<String, dynamic>;
              userMap['referralCode'] = _referralCode;
              await prefs.setString('user', jsonEncode(userMap));
              debugPrint('🔍 Updated user object with referral code');
            }
          }
        } catch (apiError) {
          debugPrint('🔍 API Error: $apiError');
        }
      } else {
        debugPrint('🔍 SKIPPING API - userId is empty or N/A');
      }

      debugPrint('🔍 FINAL _referralCode: $_referralCode');
    } catch (e) {
      debugPrint('🔍 ERROR in _loadReferralCode: $e');
      setState(() => _referralCode = 'N/A');
    }
  }

  Future<void> _loadBalances() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final balance = prefs.getDouble('walletBalance') ?? 0.0;
      setState(() => _walletBalance = balance);
    } catch (e) {
      debugPrint('Error loading balances: $e');
    }
  }

  Future<void> _loadCachedData() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final cachedBalance = prefs.getDouble('commissionBalance');
      if (cachedBalance != null) {
        setState(() => _commissionBalance = cachedBalance);
      }

      final cachedStats = prefs.getString('referralStats_${widget.userId}');
      if (cachedStats != null) {
        try {
          final stats = jsonDecode(cachedStats) as Map<String, dynamic>;
          setState(() => _referralStats = stats);
        } catch (e) {
          debugPrint('Error parsing cached stats: $e');
        }
      }

      final cachedTransactions = prefs.getString(
        'commissionTransactions_${widget.userId}',
      );
      if (cachedTransactions != null) {
        try {
          final transactions = jsonDecode(cachedTransactions) as List<dynamic>;
          setState(() {
            _commissionTransactions = transactions.cast<Map<String, dynamic>>();
          });
        } catch (e) {
          debugPrint('Error parsing cached transactions: $e');
        }
      }

      if (widget.userId.isNotEmpty) {
        final cachedCode = prefs.getString('referralCode_${widget.userId}');
        if (cachedCode != null && cachedCode.isNotEmpty) {
          setState(() => _referralCode = cachedCode);
          debugPrint('✅ Referral code loaded from cache: $cachedCode');
        }
      }

      _hasLoadedOnce = true;
    } catch (e) {
      debugPrint('Error loading cached data: $e');
    }
  }

  Future<void> _cacheData() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      await prefs.setDouble('commissionBalance', _commissionBalance);

      await prefs.setString(
        'referralStats_${widget.userId}',
        jsonEncode(_referralStats),
      );

      final transactionsToCache = _commissionTransactions.take(50).toList();
      await prefs.setString(
        'commissionTransactions_${widget.userId}',
        jsonEncode(transactionsToCache),
      );

      if (_referralCode != 'N/A' && widget.userId.isNotEmpty) {
        await prefs.setString('referralCode_${widget.userId}', _referralCode);
      }
    } catch (e) {
      debugPrint('Error caching data: $e');
    }
  }

  // ==================== DATA FETCHING ====================

  Future<void> _fetchCommissionData() async {
    setState(() => _isLoading = true);

    try {
      final results = await Future.wait([
        ApiService.getCommissionBalance(),
        ApiService.getReferralEarningsSummary(),
        ApiService.getCommissionTransactions().catchError((e) {
          debugPrint('Error loading transactions: $e');
          return <Map<String, dynamic>>[];
        }),
      ]);

      final balance = results[0] as double;
      final referralEarnings = results[1] as Map<String, dynamic>;
      final allTransactions = results[2] as List<Map<String, dynamic>>;

      final sortedTransactions = List<Map<String, dynamic>>.from(
        allTransactions,
      );
      sortedTransactions.sort((a, b) {
        final dateA =
            DateTime.tryParse(a['createdAt']?.toString() ?? '') ??
            DateTime.now();
        final dateB =
            DateTime.tryParse(b['createdAt']?.toString() ?? '') ??
            DateTime.now();
        return dateB.compareTo(dateA);
      });

      final stats = {
        'totalReferrals':
            referralEarnings['referralStats']?['totalReferrals'] ?? 0,
        'totalEarned': referralEarnings['totalEarned'] ?? 0.0,
        'directBonusEarnings':
            referralEarnings['directReferralEarnings'] ?? 0.0,
        'indirectBonusEarnings':
            referralEarnings['indirectReferralEarnings'] ?? 0.0,
        'welcomeBonusEarnings': referralEarnings['welcomeBonusEarnings'] ?? 0.0,
        'activeReferrals': 0,
        'pendingEarnings': 0.0,
      };

      setState(() {
        _commissionBalance = balance;
        _referralStats = stats;
        _commissionTransactions = sortedTransactions;
      });

      await _cacheData();

      debugPrint('✅ Commission data loaded:');
      debugPrint('   - Balance: ₦$balance');
      debugPrint('   - Total earned: ₦${stats['totalEarned']}');
      debugPrint('   - Transactions: ${sortedTransactions.length}');
    } catch (e) {
      debugPrint('Error fetching commission data: $e');

      if (!_hasLoadedOnce) {
        _showErrorSnackBar('Failed to load commission data. Pull to refresh.');
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // ==================== WITHDRAWAL ====================

  Future<void> _withdrawCommission() async {
    if (_commissionBalance < 500.0) {
      _showErrorSnackBar(
        _commissionBalance <= 0.0
            ? 'No commission available to withdraw'
            : 'Minimum withdrawal amount is ₦500. Available: ₦${_commissionBalance.toStringAsFixed(2)}',
      );
      return;
    }

    // ✅ Ask the user for the amount they want to withdraw
    final double? requestedAmount = await _showAmountInputDialog();
    if (requestedAmount == null) return; // user cancelled

    final confirm = await _showWithdrawalConfirmation(requestedAmount);
    if (confirm != true) return;

    setState(() => _isWithdrawing = true);

    try {
      final result = await ApiService.authenticatedPost(
        '/api/commission/withdraw',
        {'amount': requestedAmount},
        useBiometric: _useBiometric,
      );

      if (result['success'] == true) {
        // ✅ Use balances returned by the backend when available
        final data = result['data'] as Map<String, dynamic>? ?? {};
        final newCommission =
            (data['newCommissionBalance'] as num?)?.toDouble() ??
            (result['newCommissionBalance'] as num?)?.toDouble() ??
            (_commissionBalance - requestedAmount);
        final newWallet =
            (data['newWalletBalance'] as num?)?.toDouble() ??
            (result['newWalletBalance'] as num?)?.toDouble() ??
            _walletBalance;

        setState(() {
          _commissionBalance = newCommission < 0 ? 0.0 : newCommission;
          _walletBalance = newWallet;
        });
        widget.onBalanceUpdate(_walletBalance);

        _showSuccessDialog(result, requestedAmount);
        await _fetchCommissionData();
      } else {
        throw Exception(result['message'] ?? 'Withdrawal failed');
      }
    } catch (e) {
      _showErrorSnackBar(
        'Error withdrawing commission: ${e.toString().replaceAll('Exception: ', '')}',
      );
    } finally {
      if (mounted) setState(() => _isWithdrawing = false);
    }
  }

  // ==================== AMOUNT INPUT DIALOG ====================
  Future<double?> _showAmountInputDialog() async {
    final amountController = TextEditingController();
    String? errorText;
    final result = await showDPSheet<double>(
      context,
      title: 'Move to wallet',
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              DPField(
                label: 'Amount',
                labelTrailing: DPLinkButton(
                  label: 'Move all',
                  onPressed: () {
                    amountController.text = _commissionBalance.toStringAsFixed(2);
                    setSheet(() => errorText = null);
                  },
                ),
                controller: amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
                prefixText: '₦ ',
                hint: '500',
                errorText: errorText,
                helper: errorText == null
                    ? 'Available ${dpNaira(_commissionBalance)} · Minimum ₦500'
                    : null,
                onChanged: (_) {
                  if (errorText != null) setSheet(() => errorText = null);
                },
              ),
              DPButton(
                label: 'Continue',
                icon: DPIcons.arrowRight,
                onPressed: () {
                  final value = double.tryParse(amountController.text.trim());
                  String? err;
                  if (value == null || value <= 0) {
                    err = 'Please enter a valid amount';
                  } else if (value < 500) {
                    err = 'Minimum withdrawal is ₦500';
                  } else if (value > _commissionBalance) {
                    err = 'Amount exceeds your available earnings';
                  }
                  if (err != null) {
                    setSheet(() => errorText = err);
                    return;
                  }
                  Navigator.pop(ctx, value);
                },
              ),
            ],
          ),
        ),
      ),
    );
    return result;
  }

  Future<bool?> _showWithdrawalConfirmation([double? amountOverride]) {
    final amountToShow = amountOverride ?? _commissionBalance;
    return showDPDialog<bool>(
      context,
      title: 'Move ${dpNaira(amountToShow)} to your wallet?',
      message: 'The money will be available in your main wallet straight away.',
      icon: DPIcons.arrowUpRight,
      tone: DPDialogTone.success,
      primaryLabel: 'Confirm',
      onPrimary: () => Navigator.of(context).pop(true),
      secondaryLabel: 'Cancel',
      onSecondary: () => Navigator.of(context).pop(false),
      barrierDismissible: false,
    );
  }


  // ==================== DIALOGS ====================

  void _showSuccessDialog(
    Map<String, dynamic> result, [
    double? amountOverride,
  ]) {
    final amount =
        amountOverride ??
        (result['data']?['amountWithdrawn'] as num?)?.toDouble() ??
        (result['amount'] as num?)?.toDouble() ??
        _commissionBalance;
    final transactionId =
        result['transactionId'] ??
        'TXN_${DateTime.now().millisecondsSinceEpoch}';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => Dialog(
            backgroundColor: Colors.transparent,
            elevation: 0,
            child: ReceiptWidget(
              transactionType: 'Commission Withdrawal',
              amount: amount.toStringAsFixed(2),
              status: 'completed',
              transactionId: transactionId,
              reference: 'REF_${DateTime.now().millisecondsSinceEpoch}',
              date: DateTime.now(),
              phoneNumber: '',
              description: 'Commission transferred to main wallet',
              customMessage:
                  '✓ Withdrawal successful! Commission transferred to wallet.',
              primaryColor: const Color(0xFF102C68),
              showWatermark: true,
              isAdminTransaction: false,
              isUserAdmin: false,
            ),
          ),
    );
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    dpSnack(context, message, error: true);
  }

  void _showSuccessSnackBar(String message) {
    if (!mounted) return;
    dpSnack(context, message, success: true);
  }

  // ==================== HELPERS ====================

  String _getCommissionSource(Map<String, dynamic> transaction) {
    final details = transaction['details'] as Map<String, dynamic>? ?? {};
    final vtpassResponse = details['vtpassResponse'] as Map<String, dynamic>?;

    if (vtpassResponse != null) {
      final serviceId =
          vtpassResponse['serviceID']?.toString().toLowerCase() ?? '';
      if (serviceId.contains('airtime')) return 'Airtime Purchase';
      if (serviceId.contains('data')) return 'Data Purchase';
      if (serviceId.contains('tv')) return 'Cable TV';
      if (serviceId.contains('electric')) return 'Electricity';
    }

    final description =
        transaction['description']?.toString().toLowerCase() ?? '';
    if (description.contains('airtime')) return 'Airtime Purchase';
    if (description.contains('data')) return 'Data Purchase';
    if (description.contains('cable') || description.contains('tv')) {
      return 'Cable TV';
    }
    if (description.contains('electricity') || description.contains('power')) {
      return 'Electricity';
    }
    if (description.contains('referral')) return 'Referral Bonus';
    if (description.contains('withdrawal')) return 'Withdrawal';
    if (description.contains('bonus')) return 'Bonus';

    return transaction['type']?.toString() ?? 'Commission';
  }


  // ==================== NAVIGATION ====================





  void _navigateToReferralPage() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ReferralEarningsPage(userId: widget.userId),
      ),
    );
  }

  // ==================== BUILD METHODS ====================

  @override
  Widget build(BuildContext context) {
    return DPPage(
      title: 'Commission & earnings',
      actionLabel: 'How it works',
      onAction: _showHowItWorks,
      onRefresh: _fetchCommissionData,
      children: [
        if (_isLoading && !_hasLoadedOnce) _buildLoadingState() else _buildBody(),
      ],
    );
  }

  void _showHowItWorks() {
    showDPDialog(
      context,
      title: 'How earnings work',
      icon: DPIcons.sparkles,
      tone: DPDialogTone.success,
      bullets: const [
        'You earn a small commission when an eligible payment succeeds.',
        'Referral bonuses are added when people you invite start using Dalabapay.',
        'Earnings are kept separate from your wallet balance.',
        'Move ₦500 or more to your wallet at any time — there is no fee.',
      ],
      primaryLabel: 'Got it',
    );
  }

  bool _isCreditTx(Map<String, dynamic> t) {
    final type = t['type']?.toString() ?? '';
    final description = t['description']?.toString().toLowerCase() ?? '';
    if (description.contains('withdraw') || type.toLowerCase().contains('withdraw')) return false;
    return type.contains('Bonus') ||
        type.contains('Credit') ||
        description.contains('bonus') ||
        t['isCommission'] == true ||
        type.contains('+');
  }

  double get _lifetimeEarned => _commissionTransactions
      .where(_isCreditTx)
      .fold(0.0, (s, t) => s + ((t['amount'] as num?)?.toDouble() ?? 0));

  double get _movedToWallet => _commissionTransactions
      .where((t) => !_isCreditTx(t))
      .fold(0.0, (s, t) => s + ((t['amount'] as num?)?.toDouble() ?? 0));

  Widget _statCard(String label, double value) => Expanded(
        child: DPCard(
          margin: EdgeInsets.zero,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: DPText.bodyMuted.copyWith(fontSize: 13)),
              const SizedBox(height: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(dpNaira(value, decimals: value % 1 != 0),
                    style: DPText.amount.copyWith(fontSize: 22)),
              ),
            ],
          ),
        ),
      );

  Widget _buildWeekChart() {
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day).subtract(const Duration(days: 6));
    final totals = List<double>.filled(7, 0);
    for (final t in _commissionTransactions) {
      if (!_isCreditTx(t)) continue;
      final d = DateTime.tryParse(t['createdAt']?.toString() ?? '')?.toLocal();
      if (d == null) continue;
      final idx = DateTime(d.year, d.month, d.day).difference(start).inDays;
      if (idx >= 0 && idx < 7) totals[idx] += (t['amount'] as num?)?.toDouble() ?? 0;
    }
    final week = totals.fold(0.0, (a, b) => a + b);
    final maxV = totals.fold(0.0, (a, b) => b > a ? b : a);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 26, bottom: 16),
          child: Row(
            children: [
              Expanded(child: Text('This week', style: DPText.section)),
              Text('${dpNaira(week, decimals: week % 1 != 0)} earned',
                  style: DPText.link.copyWith(color: DP.green)),
            ],
          ),
        ),
        SizedBox(
          height: 150,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Container(
                        width: 22,
                        height: 12 + (maxV <= 0 ? 0 : 98 * totals[i] / maxV),
                        decoration: BoxDecoration(
                          color: i == 6 ? DP.green : DP.green.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(DateFormat('E').format(start.add(Duration(days: i))),
                          style: DPText.small),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }


  Widget _buildLoadingState() {
    return const Padding(
      padding: EdgeInsets.only(top: 80),
      child: DPLoader(message: 'Loading your earnings…'),
    );
  }

  Widget _buildBody() {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildCommissionBalanceCard(),
            Row(children: [
              _statCard('Lifetime earned', _lifetimeEarned),
              const SizedBox(width: 12),
              _statCard('Moved to wallet', _movedToWallet),
            ]),
            _buildWeekChart(),
            _buildReferralStatsSection(),
            _buildFilterSection(),
            _buildTransactionList(),
            Padding(
              padding: const EdgeInsets.only(top: 20),
              child: Text(
                'Commission is credited after an eligible payment succeeds. Rates are shown before you pay.',
                style: DPText.small,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== EXACT SAME GRADIENT AS DASHBOARD ====================
  Widget _buildCommissionBalanceCard() {
    final canMove = _commissionBalance >= 500;
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 16),
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
      decoration: BoxDecoration(
        color: DP.greenSoft,
        borderRadius: BorderRadius.circular(DP.rXl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const DPIcon(DPIcons.sparkles, size: 18, color: DP.green),
              const SizedBox(width: 8),
              Expanded(
                child: Text('AVAILABLE EARNINGS',
                    style: DPText.overline.copyWith(color: DP.green)),
              ),
              GestureDetector(
                onTap: () => setState(() => _isCommissionVisible = !_isCommissionVisible),
                child: DPIcon(_isCommissionVisible ? DPIcons.eye : DPIcons.eyeOff,
                    size: 18, color: DP.green),
              ),
            ],
          ),
          const SizedBox(height: 14),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              _isCommissionVisible ? dpNaira(_commissionBalance) : '₦ ••••••',
              style: DPText.display.copyWith(fontSize: 40, color: DP.green),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            canMove || _commissionBalance <= 0
                ? 'Earned funds are separate from your wallet.'
                : 'You can move earnings once you reach ₦500.',
            style: DPText.body.copyWith(color: DP.green, fontSize: 14),
          ),
          const SizedBox(height: 18),
          DPButton(
            label: 'Move to wallet',
            icon: DPIcons.arrowUpRight,
            loading: _isWithdrawing,
            onPressed: canMove && !_isWithdrawing ? _withdrawCommission : null,
          ),
        ],
      ),
    );
  }

  // ==================== REFERRAL ACTIONS ====================

  void _copyReferralCode() {
    Clipboard.setData(ClipboardData(text: _referralCode));
    _showSuccessSnackBar('Referral code copied to clipboard!');
  }

  void _shareReferralCode() {
    if (_referralCode.isEmpty || _referralCode == 'N/A') {
      _showErrorSnackBar('Your referral code is not available yet.');
      return;
    }
    Share.share(
      'Pay bills, buy airtime and data on Dalabapay. Sign up with my referral code $_referralCode',
      subject: 'Join me on Dalabapay',
    );
  }

  // ==================== REFERRAL STATS ====================

  Widget _buildReferralStatsSection() {
    final total = (_referralStats['totalEarned'] as num?)?.toDouble() ?? 0;
    final count = _referralStats['totalReferrals']?.toString() ?? '0';
    final direct = (_referralStats['directBonusEarnings'] as num?)?.toDouble() ?? 0;
    final welcome = (_referralStats['welcomeBonusEarnings'] as num?)?.toDouble() ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DPSectionHeader('Referrals', actionLabel: 'View details', onAction: _navigateToReferralPage),
        DPCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const DPIconBadge(icon: DPIcons.gift, bg: DP.greenSoft, fg: DP.green),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Referral earnings', style: DPText.bodyMuted.copyWith(fontSize: 13)),
                        const SizedBox(height: 2),
                        Text(dpNaira(total), style: DPText.value.copyWith(fontSize: 18)),
                      ],
                    ),
                  ),
                  Text('$count invited', style: DPText.small),
                ],
              ),
              if (direct > 0 || welcome > 0) ...[
                const SizedBox(height: 12),
                DPSummaryCard(rows: [
                  if (direct > 0) DPSummaryRow('Direct bonus', dpNaira(direct)),
                  if (welcome > 0) DPSummaryRow('Welcome bonus', dpNaira(welcome)),
                ]),
              ],
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
                decoration: BoxDecoration(
                  color: DP.bg,
                  borderRadius: BorderRadius.circular(DP.rMd),
                  border: Border.all(color: DP.border),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Your referral code', style: DPText.small),
                          Text(_referralCode, style: DPText.value),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: _copyReferralCode,
                      icon: const DPIcon(DPIcons.copy, size: 18, color: DP.green),
                    ),
                    IconButton(
                      onPressed: _shareReferralCode,
                      icon: const DPIcon(DPIcons.share2, size: 18, color: DP.green),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }



  // ==================== FILTERS ====================

  Widget _buildFilterSection() {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 6),
      child: Row(
        children: [
          Expanded(child: Text('Latest earnings', style: DPText.section)),
          _buildFilterDropdown(
            value: _selectedTimeFilter,
            items: _timeFilters,
            onChanged: (value) {
              if (value != null) setState(() => _selectedTimeFilter = value);
            },
          ),
          const SizedBox(width: 8),
          _buildFilterDropdown(
            value: _selectedTypeFilter,
            items: _typeFilters,
            onChanged: (value) {
              if (value != null) setState(() => _selectedTypeFilter = value);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFilterDropdown({
    required String value,
    required List<String> items,
    required void Function(String?) onChanged,
  }) {
    return GestureDetector(
      onTap: () => showDPSheet(
        context,
        title: 'Show',
        builder: (ctx) => Column(
          children: [
            for (final item in items)
              DPOptionRow(
                title: item,
                selected: item == value,
                onTap: () {
                  Navigator.pop(ctx);
                  onChanged(item);
                },
              ),
          ],
        ),
      ),
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: DP.surface,
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: DP.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(value, style: DPText.small.copyWith(color: DP.ink2, fontWeight: FontWeight.w500)),
            const SizedBox(width: 4),
            const DPIcon(DPIcons.chevronDown, size: 14, color: DP.ink2),
          ],
        ),
      ),
    );
  }

  List<Map<String, dynamic>> get _visibleTransactions {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return _commissionTransactions.where((t) {
      final d = DateTime.tryParse(t['createdAt']?.toString() ?? '')?.toLocal();
      if (_selectedTimeFilter != 'All' && d == null) return false;
      switch (_selectedTimeFilter) {
        case 'Today':
          if (d!.isBefore(today)) return false;
          break;
        case 'This Week':
          if (d!.isBefore(today.subtract(const Duration(days: 6)))) return false;
          break;
        case 'This Month':
          if (d!.year != now.year || d.month != now.month) return false;
          break;
      }
      if (_selectedTypeFilter == 'Credit' && !_isCreditTx(t)) return false;
      if (_selectedTypeFilter == 'Debit' && _isCreditTx(t)) return false;
      return true;
    }).toList();
  }

  // ==================== TRANSACTION LIST ====================

  Widget _buildTransactionList() {
    final items = _visibleTransactions;
    if (items.isEmpty) {
      return DPEmptyState(
        icon: DPIcons.sparkles,
        title: _commissionTransactions.isEmpty ? 'No earnings yet' : 'Nothing for this filter',
        message: _commissionTransactions.isEmpty
            ? 'Buy airtime, data or pay a bill and your commission will show up here.'
            : 'Try another period or type.',
      );
    }
    return Column(children: [for (final t in items) _buildTransactionItem(t)]);
  }

  Widget _buildTransactionItem(Map<String, dynamic> transaction) {
    final amount = ((transaction['amount'] ?? 0.0) as num).toDouble();
    final date = DateTime.tryParse(transaction['createdAt']?.toString() ?? '')?.toLocal() ??
        DateTime.now();
    final isCredit = _isCreditTx(transaction);
    final source = _getCommissionSource(transaction);
    final ref = transaction['reference']?.toString();
    DPIconData icon = DPIcons.sparkles;
    final s = source.toLowerCase();
    if (s.contains('airtime')) icon = DPIcons.phone;
    if (s.contains('data')) icon = DPIcons.wifi;
    if (s.contains('cable')) icon = DPIcons.tv;
    if (s.contains('electric')) icon = DPIcons.zap;
    if (s.contains('referral') || s.contains('bonus')) icon = DPIcons.gift;
    if (!isCredit) icon = DPIcons.arrowUpRight;
    final title = isCredit
        ? (s.contains('bonus') ? source : '$source commission')
            .replaceAll(' Purchase', '')
        : 'Moved to wallet';
    return DPTransactionTile(
      icon: icon,
      title: title,
      subtitle:
          '${DateFormat('d MMM').format(date)} · ${ref != null && ref.isNotEmpty ? ref : 'Completed'}',
      amount: '${isCredit ? '+' : '−'}${dpNaira(amount, decimals: amount % 1 != 0)}',
      credit: isCredit,
      onTap: () => _showTransactionReceipt(transaction),
    );
  }

  void _showTransactionReceipt(Map<String, dynamic> transaction) {
    final amount = (transaction['amount'] ?? 0.0).toDouble();
    final type = transaction['type'] ?? 'Commission';
    final description = transaction['description'] ?? '';
    final transactionId =
        transaction['_id'] ??
        transaction['transactionId'] ??
        'TXN_${DateTime.now().millisecondsSinceEpoch}';
    final date =
        DateTime.tryParse(transaction['createdAt']?.toString() ?? '') ??
        DateTime.now();
    final isCredit =
        type.toString().contains('Bonus') ||
        type.toString().contains('Credit') ||
        transaction['isCommission'] == true ||
        type.toString().contains('+');

    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => Dialog(
            backgroundColor: Colors.transparent,
            elevation: 0,
            child: ReceiptWidget(
              transactionType: _getCommissionSource(transaction),
              amount: amount.toStringAsFixed(2),
              status: isCredit ? 'completed' : 'delivered',
              transactionId: transactionId,
              reference: 'REF_${DateTime.now().millisecondsSinceEpoch}',
              date: date,
              phoneNumber: '',
              description:
                  description.isNotEmpty
                      ? description
                      : 'Commission transaction',
              customMessage:
                  isCredit
                      ? '✓ Commission credited to your account'
                      : '✓ Commission used for service',
              primaryColor: const Color(0xFF102C68),
              showWatermark: true,
              isAdminTransaction: false,
              isUserAdmin: false,
            ),
          ),
    );
  }
}
