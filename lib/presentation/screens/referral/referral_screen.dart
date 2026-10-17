// lib/presentation/screens/referral/referral_earnings_page.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/services/api_service.dart';
import '../../../core/widgets/receipt_widget.dart';
import 'package:share_plus/share_plus.dart';
import '../../../ui/ui.dart';

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
    if (!mounted) return;
    dpSnack(context, message, error: true);
  }

  void _showSuccessSnackBar(String message) {
    if (!mounted) return;
    dpSnack(context, message, success: true);
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
    if (typeLower.contains('direct')) return const Color(0xFF168566);
    if (typeLower.contains('indirect')) return const Color(0xFFE67E22);
    if (typeLower.contains('welcome')) return const Color(0xFF9B59B6);
    if (typeLower.contains('deposit')) return const Color(0xFF8E44AD);
    if (typeLower.contains('commission')) return const Color(0xFF102C68);
    return const Color(0xFF3498DB);
  }

  DPIconData _getBonusIcon(String type) {
    final typeLower = type.toLowerCase();
    if (typeLower.contains('direct')) return DPIcons.userPlus;
    if (typeLower.contains('indirect')) return DPIcons.users;
    if (typeLower.contains('welcome')) return DPIcons.gift;
    if (typeLower.contains('deposit')) return DPIcons.wallet;
    if (typeLower.contains('commission')) return DPIcons.sparkles;
    return DPIcons.star;
  }

  void _copyReferralCode() {
    if (_referralCode.isNotEmpty && _referralCode != 'N/A') {
      Clipboard.setData(ClipboardData(text: _referralCode));
      _showSuccessSnackBar('Referral code copied to clipboard!');
    }
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
              primaryColor: const Color(0xFF102C68),
              showWatermark: true,
              isAdminTransaction: false,
              isUserAdmin: false,
            ),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DPPage(
      title: 'Referrals',
      onRefresh: _loadReferralData,
      children: [_isLoading ? _buildLoadingState() : _buildBody()],
    );
  }


  Widget _buildLoadingState() {
    return const Padding(padding: EdgeInsets.only(top: 80), child: DPLoader(message: 'Loading referrals…'));
  }

  Widget _buildBody() {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildReferralCodeCard(),
            _buildTotalEarningsCard(),
            _buildGuideCard(),
            _buildBonusBreakdownSection(),
            _buildTransactionsSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildTotalEarningsCard() {
    final totalEarned = ((_referralData['totalEarned'] ?? 0.0) as num).toDouble();
    final totalReferrals = _referralData['referralStats']?['totalReferrals'] ?? 0;
    final tier = _referralData['referralStats']?['referralTier'] ?? 'Bronze';
    return Row(
      children: [
        Expanded(child: _buildStatItem('Earned so far', dpNaira(totalEarned), Icons.star)),
        const SizedBox(width: 12),
        Expanded(child: _buildStatItem('People invited', '$totalReferrals', Icons.people)),
        const SizedBox(width: 12),
        Expanded(child: _buildStatItem('Tier', '$tier', Icons.star)),
      ],
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    return DPCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: DPText.small),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: DPText.value.copyWith(fontSize: 18)),
          ),
        ],
      ),
    );
  }

  Widget _buildBonusBreakdownSection() {
    double v(String k) => ((_referralData[k] ?? 0.0) as num).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const DPSectionHeader('Where it came from'),
        DPSummaryCard(rows: [
          DPSummaryRow('Direct referrals', dpNaira(v('directReferralEarnings'))),
          DPSummaryRow('Indirect referrals', dpNaira(v('indirectReferralEarnings'))),
          DPSummaryRow('Welcome bonus', dpNaira(v('welcomeBonusEarnings'))),
        ]),
      ],
    );
  }


  Widget _buildReferralCodeCard() {
    final ready = _referralCode.isNotEmpty && _referralCode != 'N/A';
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 16),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(color: DP.navy, borderRadius: BorderRadius.circular(DP.rXl)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('INVITE FRIENDS, EARN ₦200',
              style: DPText.overline.copyWith(color: Colors.white.withValues(alpha: 0.7))),
          const SizedBox(height: 10),
          Text('Your referral code', style: DPText.body.copyWith(color: Colors.white.withValues(alpha: 0.8))),
          const SizedBox(height: 4),
          SelectableText(
            ready ? _referralCode : 'Not available yet',
            style: DPText.display.copyWith(color: Colors.white, fontSize: 30, letterSpacing: 1),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: DPButton(
                  label: 'Copy',
                  kind: DPButtonKind.soft,
                  leadingIcon: DPIcons.copy,
                  height: 48,
                  onPressed: ready ? _copyReferralCode : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DPButton(
                  label: 'Share',
                  leadingIcon: DPIcons.share2,
                  height: 48,
                  onPressed: ready ? _shareReferralCode : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const DPSectionHeader('Bonus history'),
        if (_referralTransactions.isEmpty)
          _buildEmptyState()
        else
          for (final t in _referralTransactions) _buildTransactionItem(t),
      ],
    );
  }

  Widget _buildEmptyState() {
    return const DPEmptyState(
      icon: DPIcons.gift,
      title: 'No bonuses yet',
      message: 'Share your code. When a friend funds ₦5,000 or more, you both earn.',
    );
  }

  Widget _buildTransactionItem(Map<String, dynamic> transaction) {
    final amount = ((transaction['amount'] ?? 0.0) as num).toDouble();
    final type = _getBonusType(transaction);
    final date = DateTime.tryParse(transaction['createdAt']?.toString() ?? '')?.toLocal() ?? DateTime.now();
    return DPTransactionTile(
      icon: _getBonusIcon(type),
      title: type,
      subtitle: _formatDate(date),
      amount: '+${dpNaira(amount, decimals: amount % 1 != 0)}',
      credit: true,
      onTap: () => _showTransactionReceipt(transaction),
    );
  }

  Widget _buildGuideCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const DPSectionHeader('How it works'),
        DPCard(
          child: Column(
            children: [
              _buildGuideItem('1', 'Share your referral code with friends'),
              _buildGuideItem('2', 'They sign up and make a first deposit of ₦5,000 or more'),
              _buildGuideItem('3', 'You both earn ₦200 instantly'),
              _buildGuideItem('4', 'Earn ₦20 when the people you invite bring friends'),
              const SizedBox(height: 4),
              Text(
                'Bonuses go to your earnings balance. Move them to your wallet any time from Commission & earnings.',
                style: DPText.small,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGuideItem(String number, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: DP.greenSoft, shape: BoxShape.circle),
            child: Text(number, style: DPText.label.copyWith(color: DP.green)),
          ),
          const SizedBox(width: 12),
          Expanded(child: Padding(padding: const EdgeInsets.only(top: 3), child: Text(text, style: DPText.body))),
        ],
      ),
    );
  }
}
