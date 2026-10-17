// lib/core/widgets/notification_dialog.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

class NotificationDialog extends StatefulWidget {
  final List<Map<String, dynamic>> notifications;
  final int unreadCount;
  final Future<bool> Function(String) onMarkRead;
  final Future<bool> Function() onMarkAllRead;
  final Future<void> Function({bool refresh}) onLoadMore;
  final bool hasMore;
  final bool isLoading;

  const NotificationDialog({
    super.key,
    required this.notifications,
    required this.unreadCount,
    required this.onMarkRead,
    required this.onMarkAllRead,
    required this.onLoadMore,
    required this.hasMore,
    required this.isLoading,
  });

  @override
  State<NotificationDialog> createState() => _NotificationDialogState();
}

class _NotificationDialogState extends State<NotificationDialog> {
  final ScrollController _scrollController = ScrollController();
  bool _isLoadingMore = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 100) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !widget.hasMore || widget.isLoading) return;
    _isLoadingMore = true;
    await widget.onLoadMore(refresh: false);
    _isLoadingMore = false;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.75,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(25),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          children: [_buildHeader(), Expanded(child: _buildBody())],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Color(0xFF15368A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(50),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              widget.unreadCount > 0
                  ? Icons.notifications_active
                  : Icons.notifications,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Notifications',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (widget.unreadCount > 0)
                  Text(
                    '${widget.unreadCount} unread',
                    style: GoogleFonts.inter(
                      color: Colors.white.withAlpha(180),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            ),
          ),
          if (widget.unreadCount > 0)
            TextButton(
              onPressed: () async {
                final success = await widget.onMarkAllRead();
                if (success && mounted) setState(() {});
              },
              style: TextButton.styleFrom(
                backgroundColor: Colors.white.withAlpha(38),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
              ),
              child: Text(
                'Mark all read',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(38),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, color: Colors.white, size: 18),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (widget.isLoading && widget.notifications.isEmpty) {
      return _buildLoadingState();
    }
    if (widget.notifications.isEmpty) {
      return _buildEmptyState();
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: widget.notifications.length + (widget.hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == widget.notifications.length) {
          return _buildLoadMoreIndicator();
        }
        return _buildNotificationItem(widget.notifications[index]);
      },
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF15368A)),
          ),
          const SizedBox(height: 16),
          Text(
            'Loading notifications...',
            style: GoogleFonts.inter(
              color: Colors.grey.shade600,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.notifications_off, color: Colors.grey.shade300, size: 64),
          const SizedBox(height: 16),
          Text(
            'No Notifications',
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'You\'re all caught up!',
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade400,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadMoreIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child:
            _isLoadingMore
                ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Color(0xFF15368A),
                    ),
                  ),
                )
                : Text(
                  'Loading more...',
                  style: GoogleFonts.inter(
                    color: Colors.grey.shade500,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
      ),
    );
  }

  Widget _buildNotificationItem(Map<String, dynamic> notification) {
    final isUnread = !(notification['isRead'] as bool? ?? true);
    final createdAt =
        notification['createdAt'] != null
            ? DateTime.parse(notification['createdAt'])
            : DateTime.now();
    final timeAgo = _getTimeAgo(createdAt);
    final type = notification['type'] as String? ?? 'general';

    return GestureDetector(
      onTap: () async {
        if (isUnread) {
          final success = await widget.onMarkRead(notification['_id']);
          if (success && mounted) setState(() {});
        }
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
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color:
              isUnread ? const Color(0xFF15368A).withAlpha(13) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color:
                isUnread
                    ? const Color(0xFF15368A).withAlpha(25)
                    : Colors.grey.shade100,
            width: 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _getIconColor(type).withAlpha(25),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(_getIcon(type), color: _getIconColor(type), size: 18),
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
                          notification['title'] as String? ?? 'Notification',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight:
                                isUnread ? FontWeight.w700 : FontWeight.w600,
                            color:
                                isUnread
                                    ? const Color(0xFF10255A)
                                    : Colors.grey.shade700,
                          ),
                        ),
                      ),
                      if (isUnread)
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Color(0xFF079A68),
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    notification['message'] as String? ?? '',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey.shade600,
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        Icons.access_time,
                        size: 12,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        timeAgo,
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey.shade400,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getTimeAgo(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays >= 7) {
      return DateFormat('MMM d, yyyy').format(date);
    } else if (difference.inDays >= 1) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours >= 1) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes >= 1) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }

  IconData _getIcon(String type) {
    switch (type) {
      case 'transaction':
        return Icons.receipt_long;
      case 'commission_earned':
        return Icons.monetization_on;
      case 'account':
        return Icons.person;
      case 'announcement':
        return Icons.campaign;
      case 'referral_bonus':
        return Icons.people;
      case 'deposit_bonus':
        return Icons.emoji_events;
      default:
        return Icons.notifications;
    }
  }

  Color _getIconColor(String type) {
    switch (type) {
      case 'transaction':
        return Colors.blue;
      case 'commission_earned':
        return Colors.green;
      case 'account':
        return Colors.purple;
      case 'announcement':
        return Colors.orange;
      case 'referral_bonus':
        return Colors.teal;
      case 'deposit_bonus':
        return Colors.amber;
      default:
        return Colors.grey;
    }
  }
}
