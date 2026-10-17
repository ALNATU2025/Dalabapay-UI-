// lib/presentation/screens/admin/admin_user_transactions_page.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/services/api_service.dart';

class AdminUserTransactionPage extends StatefulWidget {
  final String userId;
  final String userEmail;

  const AdminUserTransactionPage({
    super.key,
    required this.userId,
    required this.userEmail,
  });

  @override
  State<AdminUserTransactionPage> createState() =>
      _AdminUserTransactionPageState();
}

class _AdminUserTransactionPageState extends State<AdminUserTransactionPage> {
  List<dynamic> transactions = [];
  bool isLoading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    _loadTransactions();
  }

  Future<void> _loadTransactions() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final allTransactions = await ApiService.getTransactions();
      final userTransactions =
          allTransactions
              .where((t) => t['user']?['_id'] == widget.userId)
              .toList();
      setState(() {
        transactions = userTransactions;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        errorMessage = 'Failed to load transactions: $e';
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: const Color(0xFF102C68),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'User Transactions',
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              widget.userEmail,
              style: GoogleFonts.inter(fontSize: 12, color: Colors.white70),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _loadTransactions,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body:
          isLoading
              ? const Center(child: CircularProgressIndicator())
              : errorMessage != null
              ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 64,
                      color: Colors.red.shade400,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      errorMessage!,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _loadTransactions,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF102C68),
                      ),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              )
              : transactions.isEmpty
              ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.receipt_long_rounded,
                      size: 64,
                      color: Colors.grey.shade400,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No Transactions Found',
                      style: GoogleFonts.inter(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'This user has no transactions yet.',
                      style: GoogleFonts.inter(color: Colors.grey.shade500),
                    ),
                  ],
                ),
              )
              : ListView.builder(
                padding: EdgeInsets.all(isMobile ? 12 : 16),
                itemCount: transactions.length,
                itemBuilder: (context, index) {
                  final t = transactions[index];
                  final amount = (t['amount'] ?? 0.0).toDouble();
                  final type = t['type'] ?? 'Unknown';
                  final status = t['status'] ?? 'pending';
                  final date =
                      t['createdAt'] != null
                          ? DateTime.parse(t['createdAt'].toString())
                          : DateTime.now();

                  return Container(
                    margin: EdgeInsets.only(bottom: 8),
                    padding: EdgeInsets.all(isMobile ? 12 : 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color:
                                (t['isCommission'] == true)
                                    ? const Color(
                                      0xFF168566,
                                    ).withValues(alpha: 0.1)
                                    : const Color(
                                      0xFF102C68,
                                    ).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            (t['isCommission'] == true)
                                ? Icons.percent_rounded
                                : (type.contains('Fund') ||
                                    type.contains('Wallet'))
                                ? Icons.account_balance_wallet_rounded
                                : Icons.receipt_rounded,
                            color:
                                (t['isCommission'] == true)
                                    ? const Color(0xFF168566)
                                    : const Color(0xFF102C68),
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                type,
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF102C68),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${date.day}/${date.month}/${date.year}',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '₦${amount.toStringAsFixed(2)}',
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.bold,
                                color:
                                    (t['isCommission'] == true ||
                                            type.contains('Fund') ||
                                            type.contains('Wallet'))
                                        ? const Color(0xFF168566)
                                        : Colors.red.shade700,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color:
                                    status == 'completed'
                                        ? const Color(
                                          0xFF168566,
                                        ).withValues(alpha: 0.1)
                                        : Colors.orange.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                status == 'completed' ? 'Success' : status,
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color:
                                      status == 'completed'
                                          ? const Color(0xFF168566)
                                          : Colors.orange,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
    );
  }
}
