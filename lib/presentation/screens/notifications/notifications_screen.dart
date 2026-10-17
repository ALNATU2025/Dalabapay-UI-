// lib/presentation/screens/notifications/notifications_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../core/services/socket_service.dart' hide debugPrint;
import '../../../core/services/api_service.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  // ==================== STATE ====================
  List<Map<String, dynamic>> _notifications = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  int _currentPage = 1;
  int _totalPages = 1;
  bool _hasMore = true;
  int _unreadCount = 0;
  String? _errorMessage;
  bool _useSocket = true;
  Timer? _timeoutTimer;

  // ==================== CONTROLLERS ====================
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadNotifications();
    _scrollController.addListener(_onScroll);

    // Listen for new notifications via socket
    SocketService().onNotification = (notification) {
      if (mounted) {
        setState(() {
          _notifications.insert(0, notification);
          _unreadCount++;
        });
      }
    };

    // Listen for badge updates
    SocketService().onBadgeUpdate = (count) {
      if (mounted) {
        setState(() {
          _unreadCount = count;
        });
      }
    };

    // Listen for socket errors
    SocketService().onError = (error) {
      if (mounted) {
        setState(() {
          _useSocket = false;
        });
        // Fallback to API
        _loadNotificationsFromApi();
      }
    };
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _timeoutTimer?.cancel();
    super.dispose();
  }

  // ==================== DATA LOADING ====================

  void _loadNotifications({bool loadMore = false}) {
    if (loadMore && _isLoadingMore) return;
    if (loadMore && !_hasMore) return;

    setState(() {
      if (loadMore) {
        _isLoadingMore = true;
      } else {
        _isLoading = true;
        _errorMessage = null;
      }
    });

    final page = loadMore ? _currentPage + 1 : 1;

    // Set a timeout - if socket doesn't respond in 5 seconds, fallback to API
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && _isLoading) {
        debugPrint('⚠️ Socket timeout, falling back to API');
        setState(() {
          _useSocket = false;
        });
        _loadNotificationsFromApi(loadMore: loadMore, page: page);
      }
    });

    if (_useSocket && SocketService().isConnected) {
      // Use Socket
      SocketService().onNotificationsList = (data) {
        _timeoutTimer?.cancel();
        if (!mounted) return;

        final notifications = data['notifications'] ?? [];
        final pagination = data;

        setState(() {
          if (loadMore) {
            _notifications.addAll(notifications.cast<Map<String, dynamic>>());
          } else {
            _notifications = notifications.cast<Map<String, dynamic>>();
          }
          _currentPage = pagination['page'] ?? 1;
          _totalPages = pagination['totalPages'] ?? 1;
          _hasMore = _currentPage < _totalPages;
          _unreadCount = pagination['unreadCount'] ?? 0;
          _isLoading = false;
          _isLoadingMore = false;
          _useSocket = true;
        });
      };

      SocketService().getNotifications(page: page, limit: 20);
    } else {
      // Fallback to API
      _loadNotificationsFromApi(loadMore: loadMore, page: page);
    }
  }

  Future<void> _loadNotificationsFromApi({
    bool loadMore = false,
    int page = 1,
  }) async {
    try {
      final response = await ApiService.getNotifications();

      if (mounted) {
        // ✅ FIX: Cast List<dynamic> to List<Map<String, dynamic>>
        final List<Map<String, dynamic>> notifications =
            (response).cast<Map<String, dynamic>>();

        setState(() {
          if (loadMore) {
            _notifications.addAll(notifications);
          } else {
            _notifications = notifications;
          }
          _currentPage = page;
          _totalPages = 1;
          _hasMore = false;
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isLoadingMore = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      if (_hasMore && !_isLoadingMore) {
        _loadNotifications(loadMore: true);
      }
    }
  }

  // ==================== ACTIONS ====================

  void _markAsRead(String notificationId) {
    if (_useSocket && SocketService().isConnected) {
      SocketService().markAsRead(notificationId);
    } else {
      // Fallback to API
      ApiService.markNotificationAsRead(notificationId)
          .then((_) {
            setState(() {
              final index = _notifications.indexWhere(
                (n) => n['id'] == notificationId || n['_id'] == notificationId,
              );
              if (index != -1) {
                _notifications[index]['isRead'] = true;
                _notifications[index]['read'] = true;
              }
            });
          })
          .catchError((e) {
            debugPrint('❌ Error marking as read: $e');
          });
    }

    // Optimistic update
    setState(() {
      final index = _notifications.indexWhere(
        (n) => n['id'] == notificationId || n['_id'] == notificationId,
      );
      if (index != -1) {
        _notifications[index]['isRead'] = true;
        _notifications[index]['read'] = true;
      }
    });
  }

  void _markAllAsRead() {
    if (_useSocket && SocketService().isConnected) {
      SocketService().markAllAsRead();
    } else {
      // Fallback to API
      ApiService.markAllNotificationsAsRead()
          .then((_) {
            setState(() {
              for (var notification in _notifications) {
                notification['isRead'] = true;
                notification['read'] = true;
              }
            });
          })
          .catchError((e) {
            debugPrint('❌ Error marking all as read: $e');
          });
    }

    // Optimistic update
    setState(() {
      for (var notification in _notifications) {
        notification['isRead'] = true;
        notification['read'] = true;
      }
    });
  }

  void _deleteNotification(String notificationId) {
    // Show confirmation dialog first
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            backgroundColor: Colors.white,
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.delete_outline_rounded,
                    color: Colors.red.shade600,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Delete Notification',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF14263D),
                    fontSize: 18,
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Are you sure you want to delete this notification?',
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    color: const Color(0xFF14263D),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.amber.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: Colors.amber.shade700,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'This action cannot be undone.',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: Colors.amber.shade700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              // Cancel button
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
                child: Text(
                  'Cancel',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF728078),
                  ),
                ),
              ),
              // Delete button
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context, true);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade600,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                ),
                child: Text(
                  'Delete',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
    ).then((confirmed) {
      if (confirmed == true) {
        // Optimistic update first (UI feels faster)
        setState(() {
          _notifications.removeWhere(
            (n) => n['id'] == notificationId || n['_id'] == notificationId,
          );
        });

        // Call API to delete
        ApiService.deleteNotification(notificationId)
            .then((_) {
              debugPrint('✅ Notification deleted successfully');
            })
            .catchError((e) {
              debugPrint('❌ Error deleting notification: $e');
              // Revert optimistic update if failed
              setState(() {
                // You might want to reload notifications here
                _loadNotifications();
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Failed to delete notification'),
                  backgroundColor: Colors.red.shade600,
                ),
              );
            });
      }
    });
  }

  // ==================== HELPERS ====================

  Color _getTypeColor(String type) {
    switch (type.toLowerCase()) {
      case 'alert':
        return Colors.orange.shade700;
      case 'update':
        return Colors.green.shade700;
      case 'promotion':
        return Colors.purple.shade700;
      case 'system':
        return Colors.grey.shade700;
      case 'transfer_sent':
        return Colors.blue.shade700;
      case 'transfer_received':
        return Colors.green.shade700;
      case 'payment_success':
        return Colors.green.shade700;
      case 'payment_failed':
        return Colors.red.shade700;
      case 'commission_earned':
        return Colors.amber.shade700;
      case 'wallet_funded':
        return Colors.teal.shade700;
      default:
        return primaryColor;
    }
  }

  String _getTypeLabel(String type) {
    switch (type.toLowerCase()) {
      case 'alert':
        return 'Alert';
      case 'update':
        return 'Update';
      case 'promotion':
        return 'Promotion';
      case 'system':
        return 'System';
      case 'transfer_sent':
        return 'Transfer Sent';
      case 'transfer_received':
        return 'Transfer Received';
      case 'payment_success':
        return 'Payment Success';
      case 'payment_failed':
        return 'Payment Failed';
      case 'commission_earned':
        return 'Commission Earned';
      case 'wallet_funded':
        return 'Wallet Funded';
      default:
        return 'General';
    }
  }

  dynamic _getTypeIcon(String type) {
    switch (type.toLowerCase()) {
      case 'alert':
        return HugeIcons.strokeRoundedAlert02;
      case 'update':
        return HugeIcons.strokeRoundedSystemUpdate01;
      case 'promotion':
        return HugeIcons.strokeRoundedPercent;
      case 'system':
        return HugeIcons.strokeRoundedSetting06;
      case 'transfer_sent':
        return HugeIcons.strokeRoundedSent02;
      case 'transfer_received':
        return HugeIcons.strokeRoundedDownload03;
      case 'payment_success':
        return HugeIcons.strokeRoundedCheckmarkCircle01;
      case 'payment_failed':
        return HugeIcons.strokeRoundedCancelCircle;
      case 'commission_earned':
        return HugeIcons.strokeRoundedMoney01;
      case 'wallet_funded':
        return HugeIcons.strokeRoundedWallet01;
      default:
        return HugeIcons.strokeRoundedNotification01;
    }
  }

  // ==================== UI BUILDERS ====================

  Widget _buildNotificationItem(Map<String, dynamic> notification) {
    final isRead =
        notification['isRead'] == true || notification['read'] == true;
    final type = notification['type'] ?? 'general';
    final title = notification['title'] ?? 'Notification';
    final message = notification['message'] ?? '';
    final createdAt =
        notification['createdAt'] != null
            ? DateTime.parse(notification['createdAt'].toString())
            : DateTime.now();

    final id = notification['id'] ?? notification['_id'];

    return GestureDetector(
      onTap: () {
        _showNotificationDetails(notification);
        if (!isRead && id != null) {
          _markAsRead(id.toString());
        }
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isRead ? Colors.white : primaryColor.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color:
                isRead
                    ? Colors.grey.shade100
                    : primaryColor.withValues(alpha: 0.1),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
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
                color: _getTypeColor(type).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: HugeIcon(
                  icon: _getTypeIcon(type),
                  color: _getTypeColor(type),
                  size: 20,
                ),
              ),
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
                          title,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight:
                                isRead ? FontWeight.w500 : FontWeight.w700,
                            color: textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (!isRead)
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: primaryColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    message,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: textSecondary,
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        _getTypeLabel(type),
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: _getTypeColor(type),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 3,
                        height: 3,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade400,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        DateFormat('MMM dd, HH:mm').format(createdAt),
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (id != null)
              GestureDetector(
                onTap: () => _deleteNotification(id.toString()),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.delete_outline_rounded,
                    color: Colors.red.shade400,
                    size: 18,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showNotificationDetails(Map<String, dynamic> notification) {
    final isRead =
        notification['isRead'] == true || notification['read'] == true;
    final type = notification['type'] ?? 'general';
    final title = notification['title'] ?? 'Notification';
    final message = notification['message'] ?? '';
    final createdAt =
        notification['createdAt'] != null
            ? DateTime.parse(notification['createdAt'].toString())
            : DateTime.now();

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            backgroundColor: Colors.white,
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color:
                        isRead
                            ? Colors.grey.shade100
                            : primaryColor.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isRead
                        ? Icons.notifications_off_rounded
                        : Icons.notifications_active_rounded,
                    color: isRead ? Colors.grey.shade600 : primaryColor,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: textPrimary,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        DateFormat('MMM dd, yyyy HH:mm').format(createdAt),
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Divider(color: Colors.grey),
                const SizedBox(height: 8),
                Text(
                  message,
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    color: textPrimary,
                    height: 1.6,
                  ),
                ),
                if (type != 'general') ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _getTypeColor(type).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _getTypeColor(type).withValues(alpha: 0.2),
                      ),
                    ),
                    child: Text(
                      _getTypeLabel(type).toUpperCase(),
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: _getTypeColor(type),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'Close',
                  style: GoogleFonts.inter(
                    color: textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (!isRead)
                ElevatedButton(
                  onPressed: () {
                    final id = notification['id'] ?? notification['_id'];
                    if (id != null) {
                      _markAsRead(id.toString());
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
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(
                    'Mark as Read',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
    );
  }

  Widget _buildShimmerItem() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Shimmer.fromColors(
        baseColor: Colors.grey.shade300,
        highlightColor: Colors.grey.shade100,
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    height: 16,
                    color: Colors.grey.shade300,
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: MediaQuery.of(context).size.width * 0.6,
                    height: 14,
                    color: Colors.grey.shade300,
                  ),
                  const SizedBox(height: 6),
                  Container(width: 80, height: 12, color: Colors.grey.shade300),
                ],
              ),
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
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: primaryColor.withValues(alpha: 0.06),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.notifications_off_rounded,
                color: primaryColor.withValues(alpha: 0.3),
                size: 40,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No notifications yet',
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your notifications will appear here',
              style: GoogleFonts.inter(fontSize: 14, color: textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== BUILD ====================

  static const Color primaryColor = Color(0xFF102C68);
  static const Color textPrimary = Color(0xFF14263D);
  static const Color textSecondary = Color(0xFF728078);

  @override
  Widget build(BuildContext context) {
    final hasUnread = _notifications.any(
      (n) => n['isRead'] == false || n['read'] == false,
    );

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: primaryColor, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Notifications',
          style: GoogleFonts.inter(
            color: primaryColor,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
        actions: [
          if (_notifications.isNotEmpty) ...[
            if (hasUnread)
              TextButton(
                onPressed: _markAllAsRead,
                child: Text(
                  'Mark all read',
                  style: GoogleFonts.inter(
                    color: primaryColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
            const SizedBox(width: 8),
          ],
        ],
      ),
      body:
          _isLoading
              ? ListView.builder(
                itemCount: 8,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemBuilder: (context, index) => _buildShimmerItem(),
              )
              : _errorMessage != null
              ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.error_outline_rounded,
                        color: Colors.red.shade400,
                        size: 48,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Failed to load notifications',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _errorMessage!,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: textSecondary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadNotifications,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text('Try Again'),
                      ),
                    ],
                  ),
                ),
              )
              : _notifications.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                onRefresh: () async {
                  final completer = Completer<void>();
                  _loadNotifications();
                  Future.delayed(const Duration(seconds: 1), () {
                    if (!completer.isCompleted) {
                      completer.complete();
                    }
                  });
                  return completer.future;
                },
                color: primaryColor,
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _notifications.length + (_hasMore ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index >= _notifications.length) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Center(
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                primaryColor,
                              ),
                            ),
                          ),
                        ),
                      );
                    }
                    return _buildNotificationItem(_notifications[index]);
                  },
                ),
              ),
    );
  }
}
