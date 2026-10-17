// lib/presentation/screens/notifications/notifications_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';

import '../../../core/services/socket_service.dart' hide debugPrint;
import '../../../core/services/api_service.dart';
import '../../../ui/ui.dart';

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
    showDPDialog<bool>(
      context,
      title: 'Delete this notification?',
      message: 'This can’t be undone.',
      tone: DPDialogTone.warn,
      icon: DPIcons.trash2,
      primaryLabel: 'Delete',
      onPrimary: () => Navigator.of(context).pop(true),
      secondaryLabel: 'Cancel',
      onSecondary: () => Navigator.of(context).pop(false),
      barrierDismissible: false,
    ).then((confirmed) {
      if (confirmed == true) {
        // Optimistic update first (UI feels faster)
        setState(() {
          _notifications.removeWhere(
            (n) => n['id'] == notificationId || n['_id'] == notificationId,
          );
        });
        ApiService.deleteNotification(notificationId).then((_) {
          debugPrint('✅ Notification deleted successfully');
        }).catchError((e) {
          debugPrint('❌ Error deleting notification: $e');
          if (!mounted) return;
          setState(() => _loadNotifications());
          dpSnack(context, 'Failed to delete notification', error: true);
        });
      }
    });
  }

  // ==================== HELPERS ====================

  Color _getTypeColor(String type) {
    switch (type.toLowerCase()) {
      case 'alert':
        return DP.warn;
      case 'payment_failed':
        return DP.danger;
      case 'update':
      case 'transfer_received':
      case 'payment_success':
      case 'commission_earned':
      case 'wallet_funded':
        return DP.green;
      default:
        return DP.blue;
    }
  }

  Color _getTypeBg(String type) {
    final c = _getTypeColor(type);
    if (c == DP.warn) return DP.warnSoft;
    if (c == DP.danger) return DP.dangerSoft;
    if (c == DP.green) return DP.greenSoft;
    return DP.blueSoft;
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

  DPIconData _getTypeIcon(String type) {
    switch (type.toLowerCase()) {
      case 'alert':
        return DPIcons.triangleAlert;
      case 'update':
        return DPIcons.refreshCw;
      case 'promotion':
        return DPIcons.badgePercent;
      case 'system':
        return DPIcons.settings;
      case 'transfer_sent':
        return DPIcons.arrowUpRight;
      case 'transfer_received':
        return DPIcons.arrowDownLeft;
      case 'payment_success':
        return DPIcons.circleCheck;
      case 'payment_failed':
        return DPIcons.circleX;
      case 'commission_earned':
        return DPIcons.sparkles;
      case 'wallet_funded':
        return DPIcons.wallet;
      default:
        return DPIcons.bell;
    }
  }

  String _relativeTime(DateTime d) {
    final local = d.toLocal();
    final diff = DateTime.now().difference(local);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} h ago';
    if (diff.inDays == 1) return 'Yesterday';
    return DateFormat('d MMM, h:mm a').format(local);
  }

  // ==================== UI BUILDERS ====================

  Widget _buildNotificationItem(Map<String, dynamic> notification) {
    final isRead = notification['isRead'] == true || notification['read'] == true;
    final type = (notification['type'] ?? 'general').toString();
    final title = (notification['title'] ?? 'Notification').toString();
    final message = (notification['message'] ?? '').toString();
    final createdAt = DateTime.tryParse(notification['createdAt']?.toString() ?? '') ?? DateTime.now();
    final id = notification['id'] ?? notification['_id'];

    return InkWell(
      borderRadius: BorderRadius.circular(DP.rMd),
      onTap: () {
        _showNotificationDetails(notification);
        if (!isRead && id != null) _markAsRead(id.toString());
      },
      onLongPress: id == null ? null : () => _deleteNotification(id.toString()),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DPIconBadge(icon: _getTypeIcon(type), bg: _getTypeBg(type), fg: _getTypeColor(type)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: DPText.body.copyWith(
                            fontWeight: isRead ? FontWeight.w400 : FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(_relativeTime(createdAt), style: DPText.small),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(message,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: DPText.bodyMuted.copyWith(fontSize: 13.5)),
                ],
              ),
            ),
            if (!isRead)
              Container(
                margin: const EdgeInsets.only(left: 10, top: 6),
                width: 8,
                height: 8,
                decoration: const BoxDecoration(color: DP.green, shape: BoxShape.circle),
              ),
          ],
        ),
      ),
    );
  }

  void _showNotificationDetails(Map<String, dynamic> notification) {
    final type = (notification['type'] ?? 'general').toString();
    final title = (notification['title'] ?? 'Notification').toString();
    final message = (notification['message'] ?? '').toString();
    final createdAt = DateTime.tryParse(notification['createdAt']?.toString() ?? '') ?? DateTime.now();
    final id = notification['id'] ?? notification['_id'];
    showDPSheet(
      context,
      title: title,
      builder: (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              DPIconBadge(icon: _getTypeIcon(type), bg: _getTypeBg(type), fg: _getTypeColor(type), size: 36, radius: 12),
              const SizedBox(width: 10),
              Text(DateFormat('d MMM yyyy, h:mm a').format(createdAt.toLocal()), style: DPText.small),
            ],
          ),
          const SizedBox(height: 16),
          Text(message, style: DPText.body.copyWith(height: 1.55)),
          const SizedBox(height: 24),
          if (id != null)
            DPButton.secondary(
              label: 'Delete notification',
              onPressed: () {
                Navigator.pop(ctx);
                _deleteNotification(id.toString());
              },
            ),
          const SizedBox(height: 10),
          DPButton(label: 'Done', onPressed: () => Navigator.pop(ctx)),
        ],
      ),
    );
  }

  Widget _buildShimmerItem() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Shimmer.fromColors(
        baseColor: DP.border,
        highlightColor: DP.surface,
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: DP.border, borderRadius: BorderRadius.circular(14)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(width: double.infinity, height: 14, color: DP.border),
                  const SizedBox(height: 8),
                  Container(width: 180, height: 12, color: DP.border),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Padding(
      padding: EdgeInsets.only(top: 60),
      child: DPEmptyState(
        icon: DPIcons.bell,
        title: 'You’re all caught up',
        message: 'Payment updates, reminders and news will show up here.',
      ),
    );
  }

  // ==================== BUILD ====================

  static const Color primaryColor = Color(0xFF102C68);
  static const Color textPrimary = Color(0xFF14263D);
  static const Color textSecondary = Color(0xFF728078);

  @override
  Widget build(BuildContext context) {
    final hasUnread = _notifications.any((n) => n['isRead'] == false || n['read'] == false);
    final List<Widget> body;
    if (_isLoading) {
      body = List.generate(6, (_) => _buildShimmerItem());
    } else if (_errorMessage != null) {
      body = [
        Padding(
          padding: const EdgeInsets.only(top: 60),
          child: DPEmptyState(
            icon: DPIcons.circleAlert,
            title: 'Couldn’t load notifications',
            message: _errorMessage,
            actionLabel: 'Try again',
            onAction: _loadNotifications,
          ),
        ),
      ];
    } else if (_notifications.isEmpty) {
      body = [_buildEmptyState()];
    } else {
      body = [
        if (_unreadCount > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 6),
            child: Text('$_unreadCount unread', style: DPText.small),
          ),
        for (final n in _notifications) _buildNotificationItem(n),
        if (_hasMore)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2, color: DP.green),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text('Tip: press and hold a notification to delete it.',
              style: DPText.small, textAlign: TextAlign.center),
        ),
      ];
    }
    return DPPage(
      title: 'Notifications',
      actionLabel: _notifications.isNotEmpty && hasUnread ? 'Mark all read' : null,
      onAction: _notifications.isNotEmpty && hasUnread ? _markAllAsRead : null,
      controller: _scrollController,
      onRefresh: () async {
        _loadNotifications();
        await Future.delayed(const Duration(seconds: 1));
      },
      children: body,
    );
  }
}
