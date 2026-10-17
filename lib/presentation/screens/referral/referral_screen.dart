// lib/presentation/screens/referral/referral_earnings_page.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/services/api_service.dart';
import '../../../core/widgets/receipt_widget.dart';

class ReferralEarningsPage extends StatefulWidget {
  final String userId;

  const ReferralEarningsPage({super.key, required this.userId});

  @override
  State<ReferralEarningsPage> createState() => _ReferralEarningsPageState();
}

class _ReferralEarningsPageState extends State<ReferralEarningsPage>
    with SingleTickerProviderStateMixin {
  // State Variables
  Map<String, dynamic> _referralData = {};
  List<Map<String, dynamic>> _referralTransactions = [];
  String _referralCode = 'N/A';
  bool _isLoading = true;
  final bool _isBalanceVisible = true;

  // Animation
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _loadReferralCode();
    _loadReferralData();
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
    super.dispose();
  }

  Future<void> _loadReferralCode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userString = prefs.getString('user');

      String userId = widget.userId;

      // ✅ If widget.userId is empty, try to get userId from the user object
      if (userId.isEmpty || userId == 'N/A') {
        if (userString != null) {
          final userMap = jsonDecode(userString) as Map<String, dynamic>;
          userId = userMap['_id']?.toString() ?? '';
          debugPrint('Retrieved userId from user object: $userId');
        }
      }

      if (userString != null) {
        final userMap = jsonDecode(userString) as Map<String, dynamic>;
        final referralCodeFromUser = userMap['referralCode']?.toString();
        if (referralCodeFromUser != null &&
            referralCodeFromUser.isNotEmpty &&
            referralCodeFromUser != 'N/A') {
          setState(() {
            _referralCode = referralCodeFromUser;
          });
        }
      }

      if (userId.isNotEmpty && userId != 'N/A') {
        final storedReferralCode = await ApiService.getStoredReferralCode(
          userId,
        );
        if (storedReferralCode.isNotEmpty && storedReferralCode != 'N/A') {
          setState(() {
            _referralCode = storedReferralCode;
          });
          if (userString != null) {
            final userMap = jsonDecode(userString) as Map<String, dynamic>;
            userMap['referralCode'] = _referralCode;
            await prefs.setString('user', jsonEncode(userMap));
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading referral code: $e');
      setState(() => _referralCode = 'N/A');
    }
  }

  Future<void> _loadReferralData() async {
    setState(() => _isLoading = true);

    try {
      // Get comprehensive referral earnings data
      final data = await ApiService.getReferralEarningsSummary();

      // Get all commission transactions
      final allTransactions = await ApiService.getCommissionTransactions();

      // Filter for bonus/referral transactions
      final bonusTransactions =
          allTransactions.where((tx) {
            final type = tx['type']?.toString() ?? '';
            final desc = tx['description']?.toString().toLowerCase() ?? '';
            final metadata = tx['metadata'] as Map<String, dynamic>?;

            return type.contains('Bonus') ||
                type.contains('Referral') ||
                desc.contains('bonus') ||
                desc.contains('referral') ||
                (metadata?['bonusType'] != null) ||
                (metadata?['referralType'] != null);
          }).toList();

      setState(() {
        _referralData = data;
        _referralTransactions = bonusTransactions.cast<Map<String, dynamic>>();
      });

      debugPrint('✅ Loaded referral data:');
      debugPrint('   - Total earned: ₦${data['totalEarned'] ?? 0}');
      debugPrint(
        '   - Direct bonuses: ₦${data['directReferralEarnings'] ?? 0}',
      );
      debugPrint(
        '   - Indirect bonuses: ₦${data['indirectReferralEarnings'] ?? 0}',
      );
      debugPrint('   - Welcome bonuses: ₦${data['welcomeBonusEarnings'] ?? 0}');
      debugPrint('   - Bonus transactions: ${bonusTransactions.length}');
    } catch (e) {
      debugPrint('Error loading referral data: $e');
      _showErrorSnackBar('Failed to load referral earnings. Pull to refresh.');
    } finally {
      setState(() => _isLoading = false);
    }
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
        backgroundColor: const Color(0xFF079A68),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
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

  String _getBonusType(Map<String, dynamic> transaction) {
    final type = transaction['type']?.toString() ?? '';
    final desc = transaction['description']?.toString().toLowerCase() ?? '';
    final metadata = transaction['metadata'] as Map<String, dynamic>?;

    if (type.contains('Direct') || desc.contains('direct referral')) {
      return 'Direct Referral';
    }
    if (type.contains('Indirect') || desc.contains('indirect')) {
      return 'Indirect Referral';
    }
    if (type.contains('Welcome') || desc.contains('welcome')) {
      return 'Welcome Bonus';
    }
    if (type.contains('First Deposit') || desc.contains('first deposit')) {
      return 'First Deposit Bonus';
    }
    if (type.contains('Commission')) {
      return 'Commission';
    }
    if (type.contains('Bonus')) {
      return 'Bonus';
    }
    return 'Referral';
  }

  Color _getBonusColor(String type) {
    final typeLower = type.toLowerCase();
    if (typeLower.contains('direct')) return const Color(0xFF079A68);
    if (typeLower.contains('indirect')) return const Color(0xFFB7791F);
    if (typeLower.contains('welcome')) return const Color(0xFF2563EB);
    if (typeLower.contains('deposit')) return const Color(0xFF8E44AD);
    if (typeLower.contains('commission')) return const Color(0xFF15368A);
    return const Color(0xFF2563EB);
  }

  IconData _getBonusIcon(String type) {
    final typeLower = type.toLowerCase();
    if (typeLower.contains('direct')) return Icons.person_add_alt_1;
    if (typeLower.contains('indirect')) return Icons.people_outline;
    if (typeLower.contains('welcome')) return Icons.card_giftcard;
    if (typeLower.contains('deposit')) return Icons.account_balance_wallet;
    if (typeLower.contains('commission')) return Icons.monetization_on;
    return Icons.emoji_events;
  }

  void _copyReferralCode() {
    if (_referralCode.isNotEmpty && _referralCode != 'N/A') {
      Clipboard.setData(ClipboardData(text: _referralCode));
      _showSuccessSnackBar('Referral code copied to clipboard!');
    }
  }

  void _shareReferralCode() {
    // This would use share_plus package in production
    _showSuccessSnackBar('Share dialog would open here');
  }

  void _showTransactionReceipt(Map<String, dynamic> transaction) {
    final amount = (transaction['amount'] ?? 0.0).toDouble();
    final type = _getBonusType(transaction);
    final description = transaction['description'] ?? '';
    final transactionId =
        transaction['_id'] ??
        transaction['transactionId'] ??
        'TXN_${DateTime.now().millisecondsSinceEpoch}';
    final date =
        DateTime.tryParse(transaction['createdAt']?.toString() ?? '') ??
        DateTime.now();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => Dialog(
            backgroundColor: Colors.transparent,
            elevation: 0,
            child: ReceiptWidget(
              transactionType: type,
              amount: amount.toStringAsFixed(2),
              status: 'completed',
              transactionId: transactionId,
              reference: 'REF_${DateTime.now().millisecondsSinceEpoch}',
              date: date,
              phoneNumber: '',
              description:
                  description.isNotEmpty ? description : 'Bonus credited',
              customMessage: '✓ Bonus successfully credited to your account',
              primaryColor: const Color(0xFF15368A),
              showWatermark: true,
              isAdminTransaction: false,
              isUserAdmin: false,
            ),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _buildAppBar(),
      body: RefreshIndicator(
        onRefresh: _loadReferralData,
        color: const Color(0xFF15368A),
        backgroundColor: Colors.white,
        child: _isLoading ? _buildLoadingState() : _buildBody(),
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
          color: Color(0xFF15368A),
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
              color: const Color(0xFF15368A),
              letterSpacing: 0.09,
            ),
          ),
          Text(
            'pay',
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF079A68),
              letterSpacing: 0.09,
            ),
          ),
        ],
      ),
      centerTitle: true,
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh, color: Color(0xFF15368A), size: 22),
          onPressed: _loadReferralData,
          tooltip: 'Refresh',
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: CircularProgressIndicator(
        valueColor: AlwaysStoppedAnimation<Color>(const Color(0xFF15368A)),
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
              // Total Earnings Card
              _buildTotalEarningsCard(),
              const SizedBox(height: 24),

              // Bonus Breakdown
              _buildBonusBreakdownSection(),
              const SizedBox(height: 24),

              // Referral Code Card
              _buildReferralCodeCard(),
              const SizedBox(height: 24),

              // Recent Bonus Transactions
              _buildTransactionsSection(),
              const SizedBox(height: 24),

              // How to Earn Guide
              _buildGuideCard(),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTotalEarningsCard() {
    final totalEarned = _referralData['totalEarned'] ?? 0.0;
    final totalReferrals =
        _referralData['referralStats']?['totalReferrals'] ?? 0;
    final tier = _referralData['referralStats']?['referralTier'] ?? 'Bronze';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFF35C08E), Color(0xFF15368A)],
          stops: [0.06, 0.41],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF079A68).withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            'Total Referral Earnings',
            style: GoogleFonts.inter(
              fontSize: 14,
              color: Colors.white.withValues(alpha: 0.9),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _isBalanceVisible
                ? '₦${totalEarned.toStringAsFixed(2)}'
                : '••••••••',
            style: GoogleFonts.inter(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatItem(
                'Total Referrals',
                totalReferrals.toString(),
                Icons.people_outline,
              ),
              Container(
                width: 1,
                height: 40,
                color: Colors.white.withValues(alpha: 0.3),
              ),
              _buildStatItem('Tier', tier, Icons.emoji_events_outlined),
              Container(
                width: 1,
                height: 40,
                color: Colors.white.withValues(alpha: 0.3),
              ),
              _buildStatItem(
                'Pending',
                '₦${(_referralData['pendingEarnings'] ?? 0.0).toStringAsFixed(2)}',
                Icons.pending_actions,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.white70, size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        Text(
          label,
          style: GoogleFonts.inter(fontSize: 10, color: Colors.white70),
        ),
      ],
    );
  }

  Widget _buildBonusBreakdownSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Bonus Breakdown',
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF15368A),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildBonusCard(
                'Direct Referral',
                _referralData['formatted']?['directReferralEarnings'] ??
                    '₦0.00',
                const Color(0xFF079A68),
                Icons.person_add_alt_1,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildBonusCard(
                'Indirect Referral',
                _referralData['formatted']?['indirectReferralEarnings'] ??
                    '₦0.00',
                const Color(0xFFB7791F),
                Icons.people_outline,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildBonusCard(
                'Welcome Bonus',
                _referralData['formatted']?['welcomeBonusEarnings'] ?? '₦0.00',
                const Color(0xFF2563EB),
                Icons.card_giftcard,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildBonusCard(
                'Commission',
                '₦${((_referralData['totalEarned'] ?? 0.0) - (_referralData['commissionBalance'] ?? 0.0)).toStringAsFixed(2)}',
                const Color(0xFF2563EB),
                Icons.monetization_on,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBonusCard(
    String title,
    String amount,
    Color color,
    IconData icon,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 8),
          Text(
            amount,
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            title,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 10,
              color: Colors.grey.shade600,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildReferralCodeCard() {
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
          Text(
            'Your Referral Code',
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0x0515368A),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0x0A15368A)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _referralCode,
                    style: GoogleFonts.inter(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF15368A),
                      letterSpacing: 2,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: _copyReferralCode,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0x0A15368A),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.copy,
                      color: Color(0xFF15368A),
                      size: 20,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _shareReferralCode,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF079A68).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.share,
                      color: Color(0xFF079A68),
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Share this code with friends. When they join and make their first deposit (₦5000+), you both earn ₦200!',
            style: GoogleFonts.inter(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Recent Bonus Transactions',
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF15368A),
              ),
            ),
            if (_referralTransactions.isNotEmpty)
              TextButton(
                onPressed: () {
                  // Navigate to full history
                  _showSuccessSnackBar('View all transactions');
                },
                child: Text(
                  'See All',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF079A68),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (_referralTransactions.isEmpty)
          _buildEmptyState()
        else
          Column(
            children:
                _referralTransactions
                    .take(5)
                    .map((transaction) => _buildTransactionItem(transaction))
                    .toList(),
          ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(Icons.emoji_events, size: 56, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            'No referral bonuses yet',
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Share your referral code to start earning!',
            style: GoogleFonts.inter(
              fontSize: 13,
              color: Colors.grey.shade500,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionItem(Map<String, dynamic> transaction) {
    final amount = (transaction['amount'] ?? 0.0).toDouble();
    final type = _getBonusType(transaction);
    final description = transaction['description'] ?? '';
    final date =
        DateTime.tryParse(transaction['createdAt']?.toString() ?? '') ??
        DateTime.now();
    final color = _getBonusColor(type);
    final icon = _getBonusIcon(type);

    return GestureDetector(
      onTap: () => _showTransactionReceipt(transaction),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
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
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    type,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF10255A),
                    ),
                  ),
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: Colors.grey.shade500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
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
                  '+₦${amount.toStringAsFixed(2)}',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'BONUS',
                    style: GoogleFonts.inter(
                      fontSize: 8,
                      fontWeight: FontWeight.w700,
                      color: color,
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

  Widget _buildGuideCard() {
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
            children: [
              Icon(
                Icons.info_outline,
                color: const Color(0xFF15368A),
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'How to Earn More',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF15368A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildGuideItem('1', 'Share your referral code with friends'),
          _buildGuideItem('2', 'They sign up and make first deposit (₦5000+)'),
          _buildGuideItem('3', 'You both earn ₦200 instantly'),
          _buildGuideItem('4', 'Earn ₦20 when your referrals invite others'),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0x0515368A),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.lightbulb_outline,
                  color: const Color(0xFF15368A),
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'All bonuses are credited to your commission balance and can be used for payments or withdrawn.',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: const Color(0xFF15368A),
                      fontStyle: FontStyle.italic,
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

  Widget _buildGuideItem(String number, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: const Color(0x0515368A),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                number,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF15368A),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: Colors.grey.shade700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
