// lib/presentation/screens/commission/commission_screen.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/services/api_service.dart';
import '../../../core/widgets/receipt_widget.dart';
// ✅ Use the correct class from referral_screen.dart - ReferralEarningsPage
import '../referral/referral_screen.dart';
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
    final TextEditingController amountController = TextEditingController();
    String? errorText;

    return showDialog<double>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              backgroundColor: Colors.white,
              title: Text(
                'Withdraw Amount',
                style: GoogleFonts.inter(
                  color: const Color(0xFF15368A),
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Enter amount to move to your main wallet',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amountController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    autofocus: true,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'^\d*\.?\d{0,2}'),
                      ),
                    ],
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF15368A),
                    ),
                    decoration: InputDecoration(
                      prefixText: '₦ ',
                      prefixStyle: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF15368A),
                      ),
                      hintText: '500',
                      hintStyle: GoogleFonts.inter(
                        color: Colors.grey.shade400,
                      ),
                      errorText: errorText,
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade200),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade200),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Color(0xFF15368A),
                          width: 1.5,
                        ),
                      ),
                    ),
                    onChanged: (_) {
                      if (errorText != null) {
                        setDialogState(() => errorText = null);
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Available: ₦${_commissionBalance.toStringAsFixed(2)}',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          amountController.text = _commissionBalance
                              .toStringAsFixed(2);
                          setDialogState(() => errorText = null);
                        },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 0,
                          ),
                          minimumSize: const Size(0, 0),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          'Withdraw All',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF079A68),
                          ),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    'Minimum: ₦500',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, null),
                  child: Text(
                    'Cancel',
                    style: GoogleFonts.inter(color: Colors.grey.shade600),
                  ),
                ),
                ElevatedButton(
                  onPressed: () {
                    final input = amountController.text.trim();
                    final value = double.tryParse(input);

                    if (value == null || value <= 0) {
                      setDialogState(
                        () => errorText = 'Please enter a valid amount',
                      );
                      return;
                    }
                    if (value < 500) {
                      setDialogState(
                        () => errorText = 'Minimum withdrawal is ₦500',
                      );
                      return;
                    }
                    if (value > _commissionBalance) {
                      setDialogState(
                        () =>
                            errorText =
                                'Amount exceeds your commission balance',
                      );
                      return;
                    }

                    Navigator.pop(context, value);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF079A68),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'Continue',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<bool?> _showWithdrawalConfirmation([double? amountOverride]) {
    final amountToShow = amountOverride ?? _commissionBalance;
    final formattedAmount = NumberFormat.currency(
      symbol: '₦',
      decimalDigits: 2,
    ).format(amountToShow);

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            backgroundColor: Colors.white,
            title: Text(
              'Withdraw Commission',
              style: GoogleFonts.inter(
                color: const Color(0xFF15368A),
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildConfirmationRow('Amount', formattedAmount),
                _buildConfirmationRow('To', 'Main Wallet'),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0x0515368A),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline,
                        color: Color(0xFF15368A),
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'All commission will be transferred to your main wallet.',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: const Color(0xFF15368A),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(
                  'Cancel',
                  style: GoogleFonts.inter(color: Colors.grey.shade600),
                ),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF079A68),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  'Confirm',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
    );
  }

  Widget _buildConfirmationRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: GoogleFonts.inter(
                fontSize: 14,
                color: Colors.grey.shade600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF15368A),
              ),
            ),
          ),
        ],
      ),
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
              primaryColor: const Color(0xFF15368A),
              showWatermark: true,
              isAdminTransaction: false,
              isUserAdmin: false,
            ),
          ),
    );
  }

  void _showErrorSnackBar(String message) {
    if (mounted) dpSnack(context, message, error: true);
  }

  void _showSuccessSnackBar(String message) {
    if (mounted) dpSnack(context, message, success: true);
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

  // ==================== NAVIGATION ====================

  void _showCommissionUsageOptions() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          child: SingleChildScrollView(
            child: SafeArea(
              child: Container(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 16,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Center(
                      child: Text(
                        'Use Commission For',
                        style: GoogleFonts.inter(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF15368A),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 200,
                      child: GridView.count(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisCount: 2,
                        childAspectRatio: 1.8,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                        padding: const EdgeInsets.only(bottom: 8),
                        children: [
                          _buildServiceOptionCard(
                            icon: Icons.phone_android,
                            title: 'Airtime',
                            onTap: () => _navigateToAirtimePage(),
                          ),
                          _buildServiceOptionCard(
                            icon: Icons.wifi,
                            title: 'Data',
                            onTap: () => _showComingSoon('Data'),
                          ),
                          _buildServiceOptionCard(
                            icon: Icons.electrical_services,
                            title: 'Electricity',
                            onTap: () => _showComingSoon('Electricity'),
                          ),
                          _buildServiceOptionCard(
                            icon: Icons.tv,
                            title: 'Cable TV',
                            onTap: () => _showComingSoon('Cable TV'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey.shade200,
                        foregroundColor: Colors.grey.shade700,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        minimumSize: const Size(double.infinity, 44),
                      ),
                      child: Text(
                        'Close',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildServiceOptionCard({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: const Color(0xFF15368A), size: 28),
              const SizedBox(height: 8),
              Text(
                title,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey.shade700,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showComingSoon(String service) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Text(
              'Coming Soon',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.bold,
                color: const Color(0xFF15368A),
              ),
            ),
            content: Text(
              '$service commission purchase will be available soon!',
              style: GoogleFonts.inter(fontSize: 14),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'OK',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF079A68),
                  ),
                ),
              ),
            ],
          ),
    );
  }

  void _navigateToAirtimePage() {
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
    Navigator.pushNamed(
      context,
      '/airtime',
      arguments: {
        'userId': widget.userId,
        'onBalanceUpdate': (double newBalance) {
          widget.onBalanceUpdate(newBalance);
        },
        'useCommission': true,
      },
    );
  }

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
    return Scaffold(
      backgroundColor: DP.bg,
      body: SafeArea(
        child: Column(
          children: [
            DPTopBar(
              title: 'Commission & earnings',
              actionLabel: 'How it works',
              onAction: () => dpDialog(
                context,
                title: 'How earnings work',
                message:
                    'You earn a small commission on eligible payments like airtime, data, TV and electricity, plus referral bonuses. Earnings sit in a separate balance — move them to your wallet any time (minimum ₦500).',
                confirmLabel: 'Got it',
                tone: DPTone.info,
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _fetchCommissionData,
                color: DP.green,
                child: _isLoading && !_hasLoadedOnce
                    ? _buildLoadingState()
                    : _buildBody(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _isCreditTx(Map<String, dynamic> t) {
    final type = t['type']?.toString() ?? '';
    final description = t['description']?.toString() ?? '';
    return type.contains('Bonus') ||
        type.contains('Credit') ||
        description.contains('bonus') ||
        t['isCommission'] == true ||
        type.contains('+');
  }

  DateTime _txDate(Map<String, dynamic> t) =>
      (DateTime.tryParse(t['createdAt']?.toString() ?? '') ?? DateTime.now())
          .toLocal();

  double _amountOf(Map<String, dynamic> t) =>
      ((t['amount'] ?? 0) as num).toDouble();


  Widget _buildLoadingState() {
    return ListView(
      children: const [
        SizedBox(height: 160),
        Center(child: CircularProgressIndicator()),
      ],
    );
  }

  Widget _buildBody() {
    double lifetime = 0, moved = 0;
    for (final t in _commissionTransactions) {
      final a = _amountOf(t);
      if (_isCreditTx(t)) {
        lifetime += a;
      } else {
        final d = (t['description']?.toString() ?? '').toLowerCase();
        if (d.contains('wallet') || d.contains('withdraw')) moved += a;
      }
    }
    Widget stat(String label, double v) => Expanded(
          child: DPCard(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: DP.caption.copyWith(fontSize: 12)),
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    DP.naira(v, decimals: v % 1 != 0),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: DP.ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCommissionBalanceCard(),
            const SizedBox(height: 12),
            Row(
              children: [
                stat('Lifetime earned', lifetime),
                const SizedBox(width: 12),
                stat('Moved to wallet', moved),
              ],
            ),
            const SizedBox(height: 24),
            _buildFilterSection(),
            const SizedBox(height: 22),
            _buildReferralStatsSection(),
            const SizedBox(height: 22),
            const DPSectionHeader('Latest earnings'),
            _buildTransactionList(),
            const SizedBox(height: 16),
            const Text(
              'Commission is credited after an eligible payment succeeds. Rates are shown before you pay.',
              style: DP.caption,
            ),
          ],
        ),
      ),
    );
  }

  // ==================== EXACT SAME GRADIENT AS DASHBOARD ====================
  Widget _buildCommissionBalanceCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(
        color: DP.mint,
        borderRadius: BorderRadius.circular(DP.rXl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(DPIcons.sparkle, color: DP.green, size: 18),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'AVAILABLE EARNINGS',
                  style: TextStyle(
                    color: DP.green,
                    fontSize: 12,
                    letterSpacing: 0.6,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              InkResponse(
                radius: 18,
                onTap: () => setState(
                  () => _isCommissionVisible = !_isCommissionVisible,
                ),
                child: Icon(
                  _isCommissionVisible ? DPIcons.eye : DPIcons.eyeOff,
                  color: DP.green,
                  size: 18,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              _isCommissionVisible ? DP.naira(_commissionBalance) : '₦ ••••',
              style: const TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.w500,
                color: DP.green,
                letterSpacing: -0.5,
              ),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Earned funds are separate from your wallet.',
            style: TextStyle(color: DP.green, fontSize: 13.5),
          ),
          const SizedBox(height: 16),
          DPButton(
            label: 'Move to wallet',
            icon: DPIcons.upRight,
            loading: _isWithdrawing,
            onPressed: _isWithdrawing ? null : _withdrawCommission,
          ),
          if (_commissionBalance < 500)
            const DPHelper(
              'You can move earnings once you have ₦500 or more.',
              color: DP.green,
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
    _showSuccessSnackBar('Share dialog opened!');
  }

  // ==================== REFERRAL STATS ====================

  Widget _buildReferralStatsSection() {
    final referrals = _referralStats['totalReferrals'] ?? 0;
    final earned = ((_referralStats['totalEarned'] ?? 0) as num).toDouble();
    return DPCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      onTap: _navigateToReferralPage,
      child: Row(
        children: [
          const DPIconBadge.blue(DPIcons.referral, size: 44),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Invite friends, earn more', style: DP.bodyStrong),
                const SizedBox(height: 2),
                Text(
                  '$referrals referral${referrals == 1 ? '' : 's'} · ${DP.naira(earned)} earned · Code $_referralCode',
                  style: DP.caption,
                  maxLines: 2,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Copy code',
            onPressed: _copyReferralCode,
            icon: const Icon(DPIcons.copy, color: DP.muted, size: 20),
          ),
        ],
      ),
    );
  }



  // ==================== FILTERS ====================

  /// "This week" — commission earned per day for the last 7 days.
  Widget _buildFilterSection() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final days = List.generate(7, (i) => today.subtract(Duration(days: 6 - i)));
    final totals = List<double>.filled(7, 0);
    for (final t in _commissionTransactions) {
      if (!_isCreditTx(t)) continue;
      final d = _txDate(t);
      final day = DateTime(d.year, d.month, d.day);
      final idx = days.indexWhere((x) => x == day);
      if (idx >= 0) totals[idx] += _amountOf(t);
    }
    final weekTotal = totals.fold<double>(0, (a, b) => a + b);
    final maxV = totals.fold<double>(0, (a, b) => a > b ? a : b);
    const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(child: Text('This week', style: DP.section)),
            Text(
              '${DP.naira(weekTotal, decimals: weekTotal % 1 != 0)} earned',
              style: const TextStyle(
                color: DP.green,
                fontWeight: FontWeight.w600,
                fontSize: 13.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 110,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(7, (i) {
              final v = totals[i];
              final h = maxV <= 0 ? 10.0 : 10 + (v / maxV) * 70;
              final isToday = i == 6;
              return Expanded(
                child: Tooltip(
                  message: DP.naira(v),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        width: 22,
                        height: h,
                        decoration: BoxDecoration(
                          color: isToday ? DP.green : DP.mint,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        labels[days[i].weekday - 1],
                        style: DP.caption.copyWith(fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }


  // ==================== TRANSACTION LIST ====================

  Widget _buildTransactionList() {
    if (_commissionTransactions.isEmpty) {
      return const DPEmptyState(
        icon: DPIcons.sparkle,
        title: 'No earnings yet',
        message: 'Pay a bill to start earning commission.',
      );
    }
    final items = _commissionTransactions.take(20).toList();
    return Column(
      children: [for (final t in items) _buildTransactionItem(t)],
    );
  }

  Widget _buildTransactionItem(Map<String, dynamic> transaction) {
    final amount = _amountOf(transaction);
    final description = transaction['description']?.toString() ?? '';
    final date = _txDate(transaction);
    final isCredit = _isCreditTx(transaction);
    final source = _getCommissionSource(transaction);
    final s = source.toLowerCase();
    final IconData icon = s.contains('airtime')
        ? DPIcons.phone
        : s.contains('data')
            ? DPIcons.wifi
            : s.contains('electric')
                ? DPIcons.bolt
                : s.contains('cable') || s.contains('tv')
                    ? DPIcons.tv
                    : s.contains('referral') || s.contains('bonus')
                        ? DPIcons.referral
                        : (isCredit ? DPIcons.sparkle : DPIcons.upRight);
    final ref = transaction['reference']?.toString();
    return DPListRow(
      onTap: () => _showTransactionReceipt(transaction),
      leading: isCredit
          ? DPIconBadge(icon, size: 42, iconSize: 20)
          : DPIconBadge.blue(icon, size: 42, iconSize: 20),
      title: isCredit
          ? (description.isNotEmpty ? description : '$source commission')
          : (description.isNotEmpty ? description : 'Moved to wallet'),
      subtitle:
          '${DateFormat('d MMM').format(date)}${ref != null && ref.isNotEmpty ? ' · $ref' : ''}',
      trailing: Text(
        '${isCredit ? '+' : '−'}${DP.naira(amount, decimals: amount % 1 != 0)}',
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: isCredit ? DP.green : DP.ink,
        ),
      ),
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
              primaryColor: const Color(0xFF15368A),
              showWatermark: true,
              isAdminTransaction: false,
              isUserAdmin: false,
            ),
          ),
    );
  }
}
