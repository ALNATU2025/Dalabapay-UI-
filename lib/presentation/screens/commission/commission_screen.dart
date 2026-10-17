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
                  color: const Color(0xFF102C68),
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
                      color: const Color(0xFF102C68),
                    ),
                    decoration: InputDecoration(
                      prefixText: '₦ ',
                      prefixStyle: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF102C68),
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
                          color: Color(0xFF102C68),
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
                            color: const Color(0xFF168566),
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
                    backgroundColor: const Color(0xFF168566),
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
                color: const Color(0xFF102C68),
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
                    color: const Color(0x05102C68),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline,
                        color: Color(0xFF102C68),
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'All commission will be transferred to your main wallet.',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: const Color(0xFF102C68),
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
                  backgroundColor: const Color(0xFF168566),
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
                color: const Color(0xFF102C68),
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
              primaryColor: const Color(0xFF102C68),
              showWatermark: true,
              isAdminTransaction: false,
              isUserAdmin: false,
            ),
          ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: GoogleFonts.inter(fontSize: 13, color: Colors.white),
        ),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: GoogleFonts.inter(fontSize: 13, color: Colors.white),
        ),
        backgroundColor: const Color(0xFF168566),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
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
                          color: const Color(0xFF102C68),
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
              Icon(icon, color: const Color(0xFF102C68), size: 28),
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
                color: const Color(0xFF102C68),
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
                    color: const Color(0xFF168566),
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
      backgroundColor: Colors.white,
      appBar: _buildAppBar(),
      body: RefreshIndicator(
        onRefresh: _fetchCommissionData,
        color: const Color(0xFF102C68),
        backgroundColor: Colors.white,
        child:
            _isLoading && !_hasLoadedOnce ? _buildLoadingState() : _buildBody(),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(
          Icons.arrow_back_ios,
          color: Color(0xFF102C68),
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
              color: const Color(0xFF102C68),
              letterSpacing: 0.09,
            ),
          ),
          Text(
            'pay',
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF168566),
              letterSpacing: 0.09,
            ),
          ),
        ],
      ),
      centerTitle: true,
      actions: [
        Container(
          margin: const EdgeInsets.only(right: 16),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0x05102C68),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.account_balance_wallet_outlined,
                color: Color(0xFF102C68),
                size: 16,
              ),
              const SizedBox(width: 4),
              GestureDetector(
                onTap:
                    () =>
                        setState(() => _isBalanceVisible = !_isBalanceVisible),
                child: Text(
                  _isBalanceVisible
                      ? '₦${_walletBalance.toStringAsFixed(2)}'
                      : '••••',
                  style: GoogleFonts.inter(
                    color: const Color(0xFF102C68),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: CircularProgressIndicator(
        valueColor: AlwaysStoppedAnimation<Color>(const Color(0xFF102C68)),
      ),
    );
  }

  Widget _buildBody() {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildCommissionBalanceCard(),
              const SizedBox(height: 24),
              _buildReferralStatsSection(),
              const SizedBox(height: 24),
              _buildFilterSection(),
              const SizedBox(height: 16),
              _buildTransactionList(),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  // ==================== EXACT SAME GRADIENT AS DASHBOARD ====================
  Widget _buildCommissionBalanceCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFF5BB592), Color(0xFF102C68)],
          stops: [0.06, 0.41],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF168566).withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Commission Balance',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Row(
                  children: [
                    GestureDetector(
                      onTap: _fetchCommissionData,
                      child: const Icon(
                        Icons.refresh,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap:
                          () => setState(
                            () => _isCommissionVisible = !_isCommissionVisible,
                          ),
                      child: Icon(
                        _isCommissionVisible
                            ? Icons.visibility
                            : Icons.visibility_off,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _isCommissionVisible
                  ? '₦${_commissionBalance.toStringAsFixed(2)}'
                  : '••••••••',
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Available Commission',
              style: GoogleFonts.inter(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child:
                      _isWithdrawing
                          ? Container(
                            height: 44,
                            alignment: Alignment.center,
                            child: const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            ),
                          )
                          : ElevatedButton(
                            onPressed:
                                _commissionBalance >= 500
                                    ? _withdrawCommission
                                    : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: const Color(0xFF102C68),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              minimumSize: const Size(double.infinity, 44),
                            ),
                            child: Text(
                              'Withdraw to Wallet',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF102C68),
                              ),
                            ),
                          ),
                ),
                if (_commissionBalance > 0) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _showCommissionUsageOptions,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF168566),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        minimumSize: const Size(double.infinity, 44),
                      ),
                      child: Text(
                        'Use',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF168566),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            if (_commissionBalance < 500.0 && _commissionBalance > 0.0)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  'Minimum withdrawal: ₦500',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: Colors.yellow[200],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    'Referral Code: ${_isCommissionVisible ? _referralCode : '****'}',
                    style: GoogleFonts.inter(color: Colors.white, fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Row(
                  children: [
                    GestureDetector(
                      onTap: _copyReferralCode,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.copy,
                              color: Colors.white,
                              size: 12,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Copy',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _shareReferralCode,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.share,
                              color: Colors.white,
                              size: 12,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Share',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
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
          ],
        ),
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Referral Earnings',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF102C68),
                ),
              ),
              TextButton(
                onPressed: _navigateToReferralPage,
                child: Text(
                  'View Details',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF168566),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0x05102C68),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total Earnings',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '₦${_referralStats['totalEarned']?.toStringAsFixed(2) ?? '0.00'}',
                      style: GoogleFonts.inter(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF102C68),
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF168566).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.emoji_events,
                    color: Color(0xFF168566),
                    size: 32,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatColumn(
                'Referrals',
                _referralStats['totalReferrals']?.toString() ?? '0',
                Icons.people_outline,
              ),
              _buildStatColumn(
                'Direct Bonus',
                '₦${_referralStats['directBonusEarnings']?.toStringAsFixed(2) ?? '0.00'}',
                Icons.person_add_alt_1,
              ),
              _buildStatColumn(
                'Welcome Bonus',
                '₦${_referralStats['welcomeBonusEarnings']?.toStringAsFixed(2) ?? '0.00'}',
                Icons.card_giftcard,
              ),
            ],
          ),
          if ((_referralStats['directBonusEarnings'] ?? 0) > 0 ||
              (_referralStats['indirectBonusEarnings'] ?? 0) > 0 ||
              (_referralStats['welcomeBonusEarnings'] ?? 0) > 0)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if ((_referralStats['directBonusEarnings'] ?? 0) > 0)
                    _buildBonusChip(
                      'Direct: ₦${_referralStats['directBonusEarnings']?.toStringAsFixed(2)}',
                      const Color(0xFF102C68),
                    ),
                  if ((_referralStats['indirectBonusEarnings'] ?? 0) > 0)
                    _buildBonusChip(
                      'Indirect: ₦${_referralStats['indirectBonusEarnings']?.toStringAsFixed(2)}',
                      const Color(0xFF168566),
                    ),
                  if ((_referralStats['welcomeBonusEarnings'] ?? 0) > 0)
                    _buildBonusChip(
                      'Welcome: ₦${_referralStats['welcomeBonusEarnings']?.toStringAsFixed(2)}',
                      const Color(0xFFA76B1D),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatColumn(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: const Color(0xFF102C68), size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF102C68),
          ),
        ),
        Text(
          label,
          style: GoogleFonts.inter(fontSize: 10, color: Colors.grey.shade600),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildBonusChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // ==================== FILTERS ====================

  Widget _buildFilterSection() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _buildFilterDropdown(
          value: _selectedTimeFilter,
          items: _timeFilters,
          onChanged: (value) {
            if (value != null) {
              setState(() => _selectedTimeFilter = value);
              _fetchCommissionData();
            }
          },
        ),
        _buildFilterDropdown(
          value: _selectedTypeFilter,
          items: _typeFilters,
          onChanged: (value) {
            if (value != null) {
              setState(() => _selectedTypeFilter = value);
              _fetchCommissionData();
            }
          },
        ),
      ],
    );
  }

  Widget _buildFilterDropdown({
    required String value,
    required List<String> items,
    required void Function(String?) onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: DropdownButton<String>(
        value: value,
        underline: const SizedBox(),
        style: GoogleFonts.inter(
          fontSize: 12,
          color: const Color(0xFF102C68),
        ),
        items:
            items.map((String item) {
              return DropdownMenuItem<String>(
                value: item,
                child: Text(item, style: GoogleFonts.inter(fontSize: 12)),
              );
            }).toList(),
        onChanged: onChanged,
        icon: Icon(Icons.arrow_drop_down, color: const Color(0xFF102C68)),
      ),
    );
  }

  // ==================== TRANSACTION LIST ====================

  Widget _buildTransactionList() {
    if (_commissionTransactions.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Icon(Icons.history, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              'No Commission Transactions Yet',
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Your commission history will appear here',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _commissionTransactions.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final transaction = _commissionTransactions[index];
        return _buildTransactionItem(transaction);
      },
    );
  }

  Widget _buildTransactionItem(Map<String, dynamic> transaction) {
    final amount = (transaction['amount'] ?? 0.0).toDouble();
    final type = transaction['type']?.toString() ?? '';
    final description = transaction['description']?.toString() ?? '';
    final date =
        DateTime.tryParse(transaction['createdAt']?.toString() ?? '') ??
        DateTime.now();

    final isCredit =
        type.contains('Bonus') ||
        type.contains('Credit') ||
        description.contains('bonus') ||
        transaction['isCommission'] == true ||
        transaction['type']?.toString().contains('+') == true;

    final source = _getCommissionSource(transaction);

    return GestureDetector(
      onTap: () => _showTransactionReceipt(transaction),
      child: Container(
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
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color:
                    isCredit
                        ? const Color(0xFF168566).withValues(alpha: 0.1)
                        : Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                isCredit ? Icons.arrow_downward : Icons.arrow_upward,
                color: isCredit ? const Color(0xFF168566) : Colors.red,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    source,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF14263D),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description.isNotEmpty
                        ? description
                        : 'Commission transaction',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: Colors.grey.shade500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _formatDate(date),
                    style: GoogleFonts.inter(
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
                  '${isCredit ? '+' : '-'}₦${amount.toStringAsFixed(2)}',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isCredit ? const Color(0xFF168566) : Colors.red,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color:
                        isCredit
                            ? const Color(0xFF168566).withValues(alpha: 0.1)
                            : Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    isCredit ? 'CREDIT' : 'DEBIT',
                    style: GoogleFonts.inter(
                      fontSize: 8,
                      fontWeight: FontWeight.w700,
                      color: isCredit ? const Color(0xFF168566) : Colors.red,
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
