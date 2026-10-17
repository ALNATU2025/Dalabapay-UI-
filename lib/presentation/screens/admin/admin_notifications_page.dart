// lib/presentation/screens/admin/admin_notifications_page.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../core/services/api_service.dart';
import '../../../models/admin_notification_model.dart';
import '../../../core/widgets/receipt_widget.dart';

class AdminNotificationsPage extends StatefulWidget {
  const AdminNotificationsPage({super.key});

  @override
  State<AdminNotificationsPage> createState() => _AdminNotificationsPageState();
}

class _AdminNotificationsPageState extends State<AdminNotificationsPage> {
  static const Color primaryColor = Color(0xFF243889);
  static const Color secondaryColor = Color(0xFF219C7E);
  static const Color textPrimary = Color(0xFF1C2D5A);
  static const Color textSecondary = Color(0xFF64748B);

  List<AdminNotificationModel> _notifications = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  String? _errorMessage;
  int _currentPage = 1;
  int _totalPages = 1;
  int _unreadCount = 0;
  String _typeFilter = 'all';
  final String _severityFilter = 'all';
  Timer? _refreshTimer;

  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadNotifications();
    _scrollController.addListener(_onScroll);
    // Auto-refresh every 20 seconds
    _refreshTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) _refreshNotifications();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 300) {
      _loadMore();
    }
  }

  Future<void> _loadNotifications({bool reset = true}) async {
    if (reset) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
        _currentPage = 1;
      });
    }

    final response = await ApiService.getAdminNotifications(
      page: _currentPage,
      limit: 30,
      type: _typeFilter,
      severity: _severityFilter,
    );

    if (!mounted) return;

    if (response['success'] == true) {
      final List raw = response['notifications'] ?? [];
      final items = raw.map((e) => AdminNotificationModel.fromJson(e)).toList();

      setState(() {
        if (reset) {
          _notifications = items;
        } else {
          _notifications.addAll(items);
        }
        _totalPages = response['totalPages'] ?? 1;
        _unreadCount = response['unreadCount'] ?? 0;
        _isLoading = false;
        _isLoadingMore = false;
      });
    } else {
      setState(() {
        _isLoading = false;
        _isLoadingMore = false;
        _errorMessage = response['message'] ?? 'Failed to load notifications';
      });
    }
  }

  Future<void> _refreshNotifications() async {
    final response = await ApiService.getAdminNotifications(
      page: 1,
      limit: 30,
      type: _typeFilter,
      severity: _severityFilter,
    );
    if (!mounted) return;
    if (response['success'] == true) {
      final List raw = response['notifications'] ?? [];
      final items = raw.map((e) => AdminNotificationModel.fromJson(e)).toList();
      setState(() {
        _notifications = items;
        _unreadCount = response['unreadCount'] ?? 0;
        _currentPage = 1;
        _totalPages = response['totalPages'] ?? 1;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore) return;
    if (_currentPage >= _totalPages) return;
    setState(() {
      _isLoadingMore = true;
      _currentPage += 1;
    });
    await _loadNotifications(reset: false);
  }

  Future<void> _markAllRead() async {
    final ok = await ApiService.markAllAdminNotificationsRead();
    if (ok) {
      setState(() {
        _unreadCount = 0;
        _notifications =
            _notifications
                .map(
                  (n) => AdminNotificationModel(
                    id: n.id,
                    type: n.type,
                    title: n.title,
                    message: n.message,
                    severity: n.severity,
                    userId: n.userId,
                    userName: n.userName,
                    userEmail: n.userEmail,
                    userPhone: n.userPhone,
                    transactionId: n.transactionId,
                    transactionReference: n.transactionReference,
                    transactionType: n.transactionType,
                    amount: n.amount,
                    status: n.status,
                    isRead: true,
                    createdAt: n.createdAt,
                  ),
                )
                .toList();
      });
    }
  }

  Future<void> _markRead(AdminNotificationModel n) async {
    if (n.isRead) return;
    await ApiService.markAdminNotificationRead(n.id);
    setState(() {
      final idx = _notifications.indexWhere((x) => x.id == n.id);
      if (idx != -1) {
        _notifications[idx] = AdminNotificationModel(
          id: n.id,
          type: n.type,
          title: n.title,
          message: n.message,
          severity: n.severity,
          userId: n.userId,
          userName: n.userName,
          userEmail: n.userEmail,
          userPhone: n.userPhone,
          transactionId: n.transactionId,
          transactionReference: n.transactionReference,
          transactionType: n.transactionType,
          amount: n.amount,
          status: n.status,
          isRead: true,
          createdAt: n.createdAt,
        );
      }
      if (_unreadCount > 0) _unreadCount -= 1;
    });
  }

  Color _severityColor(String s) {
    switch (s) {
      case 'success':
        return secondaryColor;
      case 'warning':
        return Colors.orange.shade700;
      case 'critical':
        return Colors.red.shade700;
      default:
        return primaryColor;
    }
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'new_user_registration':
        return Icons.person_add_alt_1;
      case 'wallet_funded':
      case 'wallet_funding_success':
        return Icons.account_balance_wallet;
      case 'wallet_funding_failed':
        return Icons.warning_amber_rounded;
      case 'transaction_made':
        return Icons.receipt_long;
      case 'transaction_status_change':
        return Icons.sync_alt;
      case 'duplicate_transaction_attempt':
        return Icons.copy_all;
      case 'suspicious_activity':
        return Icons.security;
      default:
        return Icons.notifications;
    }
  }

  String _humanizeType(String type) {
    switch (type) {
      case 'new_user_registration':
        return 'New User';
      case 'wallet_funded':
        return 'Wallet Funded';
      case 'wallet_funding_success':
        return 'Wallet Funding Successful';
      case 'wallet_funding_failed':
        return 'Wallet Funding Failed';
      case 'transaction_made':
        return 'Transaction';
      case 'transaction_status_change':
        return 'Status Change';
      case 'duplicate_transaction_attempt':
        return 'Duplicate Attempt';
      case 'suspicious_activity':
        return 'Suspicious Activity';
      default:
        return 'Activity';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Row(
          children: [
            Text(
              'Admin Alerts',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
            ),
            const SizedBox(width: 8),
            if (_unreadCount > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$_unreadCount',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshNotifications,
            tooltip: 'Refresh',
          ),
          if (_unreadCount > 0)
            IconButton(
              icon: const Icon(Icons.done_all),
              onPressed: _markAllRead,
              tooltip: 'Mark all read',
            ),
        ],
      ),
      body: Column(
        children: [
          // Filter chips
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _chip('All', _typeFilter == 'all', () => _setFilter('all')),
                  const SizedBox(width: 6),
                  _chip(
                    'New Users',
                    _typeFilter == 'new_user_registration',
                    () => _setFilter('new_user_registration'),
                  ),
                  const SizedBox(width: 6),
                  _chip(
                    'Transactions',
                    _typeFilter == 'transaction_made',
                    () => _setFilter('transaction_made'),
                  ),
                  const SizedBox(width: 6),
                  _chip(
                    'Status',
                    _typeFilter == 'transaction_status_change',
                    () => _setFilter('transaction_status_change'),
                  ),
                  const SizedBox(width: 6),
                  _chip(
                    'Wallet',
                    _typeFilter == 'wallet_funded',
                    () => _setFilter('wallet_funded'),
                  ),
                  const SizedBox(width: 6),
                  _chip(
                    'Duplicates',
                    _typeFilter == 'duplicate_transaction_attempt',
                    () => _setFilter('duplicate_transaction_attempt'),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),

          // List
          Expanded(
            child:
                _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _errorMessage != null
                    ? _buildError()
                    : _notifications.isEmpty
                    ? _buildEmpty()
                    : RefreshIndicator(
                      onRefresh: _refreshNotifications,
                      color: primaryColor,
                      child: ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(12),
                        itemCount:
                            _notifications.length + (_isLoadingMore ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index >= _notifications.length) {
                            return const Padding(
                              padding: EdgeInsets.all(16),
                              child: Center(child: CircularProgressIndicator()),
                            );
                          }
                          return _buildCard(_notifications[index]);
                        },
                      ),
                    ),
          ),
        ],
      ),
    );
  }

  void _setFilter(String v) {
    setState(() => _typeFilter = v);
    _loadNotifications();
  }

  Widget _chip(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? primaryColor : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            color: active ? Colors.white : textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 60, color: Colors.red.shade400),
            const SizedBox(height: 12),
            Text(
              _errorMessage ?? 'Error',
              style: GoogleFonts.inter(color: textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => _loadNotifications(),
              style: ElevatedButton.styleFrom(backgroundColor: primaryColor),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.notifications_none_rounded,
              size: 70,
              color: primaryColor.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 12),
            Text(
              'No notifications yet',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'New activities will appear here',
              style: GoogleFonts.inter(color: textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(AdminNotificationModel n) {
    final color = _severityColor(n.severity);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: n.isRead ? Colors.grey.shade200 : color.withValues(alpha: 0.5),
          width: n.isRead ? 1 : 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            _markRead(n);
            _showDetails(n);
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(_typeIcon(n.type), color: color, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              n.title,
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (!n.isRead)
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        n.message,
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          color: textSecondary,
                          height: 1.35,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              _humanizeType(n.type),
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: color,
                              ),
                            ),
                          ),
                          const Spacer(),
                          Text(
                            _timeAgo(n.createdAt),
                            style: GoogleFonts.inter(
                              fontSize: 10.5,
                              color: textSecondary,
                            ),
                          ),
                        ],
                      ),
                      if (n.amount != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          'NGN ${NumberFormat('#,##0.00').format(n.amount!)}',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: color,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showDetails(AdminNotificationModel n) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      backgroundColor: Colors.white,
      isScrollControlled: true,
      builder:
          (_) => Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
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
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _severityColor(
                          n.severity,
                        ).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        _typeIcon(n.type),
                        color: _severityColor(n.severity),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        n.title,
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  n.message,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: textPrimary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),
                _detailRow('Type', _humanizeType(n.type)),
                if (n.severity.isNotEmpty) _detailRow('Severity', n.severity),
                if (n.userName != null) _detailRow('User', n.userName!),
                if (n.userEmail != null) _detailRow('Email', n.userEmail!),
                if (n.userPhone != null) _detailRow('Phone', n.userPhone!),
                if (n.transactionReference != null)
                  _detailRow('Reference', n.transactionReference!),
                if (n.transactionType != null)
                  _detailRow('Txn Type', n.transactionType!),
                if (n.amount != null)
                  _detailRow(
                    'Amount',
                    'NGN ${NumberFormat('#,##0.00').format(n.amount!)}',
                  ),
                if (n.status != null) _detailRow('Status', n.status!),
                _detailRow(
                  'Time',
                  DateFormat('dd MMM yyyy · HH:mm').format(n.createdAt),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'Close',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.inter(fontSize: 13, color: textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat('dd/MM/yy').format(dt);
  }
}
