// lib/core/services/socket_service.dart

import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

import 'api_service.dart';

class SocketService {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  IO.Socket? _socket;
  bool _isConnected = false;
  int _unreadCount = 0;
  String? _userId;
  bool _isInitialized = false;

  // ==================== CALLBACKS ====================
  Function(Map<String, dynamic>)? onNotification;
  Function(int)? onBadgeUpdate;
  Function(String)? onError;
  Function(int)? onUnreadCount;
  Function(String)? onNotificationRead;
  Function(Map<String, dynamic>)? onNotificationsList;

  IO.Socket? get socket => _socket;
  bool get isConnected => _isConnected;
  int get unreadCount => _unreadCount;
  bool get isInitialized => _isInitialized;

  // ==================== INITIALIZATION ====================

  Future<void> initialize({String? token}) async {
    if (_isInitialized) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final authToken = token ?? await ApiService.getToken();

      if (authToken == null) {
        debugPrint('❌ No token available for socket connection');
        return;
      }

      // Get user ID
      final userDataString = prefs.getString('user');
      if (userDataString != null) {
        final userData = jsonDecode(userDataString);
        _userId = userData['_id']?.toString();
      }

      // Connect to socket
      _socket = IO.io(
        'https://vtpass-backend.onrender.com',
        IO.OptionBuilder()
            .setTransports(['websocket', 'polling'])
            .setPath('/socket.io')
            .enableForceNew()
            .enableReconnection()
            .setReconnectionAttempts(10)
            .setReconnectionDelay(1000)
            .setTimeout(10000)
            .setAuth({'token': authToken})
            .build(),
      );

      _setupListeners();

      // Connect
      _socket!.connect();

      _isInitialized = true;
      debugPrint('✅ SocketService initialized');
    } catch (e) {
      debugPrint('❌ Socket initialization error: $e');
      if (onError != null) {
        onError!('Failed to initialize socket: ${e.toString()}');
      }
    }
  }

  // ==================== LISTENERS ====================

  void _setupListeners() {
    _socket!.on('badge_update', (data) {
      debugPrint('🔄 Badge update: ${data['count']}');
      _unreadCount = data['count'] as int;
      if (onBadgeUpdate != null) {
        onBadgeUpdate!(_unreadCount);
      }
      if (onUnreadCount != null) {
        onUnreadCount!(_unreadCount);
      }
    });

    _socket!.on('notification_read', (data) {
      debugPrint('📖 Notification read: ${data['notificationId']}');
      if (data['unreadCount'] != null) {
        _unreadCount = data['unreadCount'];
        if (onBadgeUpdate != null) {
          onBadgeUpdate!(_unreadCount);
        }
        if (onUnreadCount != null) {
          onUnreadCount!(_unreadCount);
        }
      }
      if (onNotificationRead != null) {
        onNotificationRead!(data['notificationId']?.toString() ?? '');
      }
    });

    _socket!.on('notifications_list', (data) {
      debugPrint('📋 Notifications list received');
      if (onNotificationsList != null) {
        onNotificationsList!(Map<String, dynamic>.from(data));
      }
    });

    _socket!.on('mark_read_success', (data) {
      debugPrint('✅ Mark read success: $data');
      if (data['unreadCount'] != null) {
        _unreadCount = data['unreadCount'];
        if (onBadgeUpdate != null) {
          onBadgeUpdate!(_unreadCount);
        }
        if (onUnreadCount != null) {
          onUnreadCount!(_unreadCount);
        }
      }
    });

    _socket!.on('mark_all_read_success', (data) {
      debugPrint('✅ Mark all read success: $data');
      if (data['unreadCount'] != null) {
        _unreadCount = data['unreadCount'];
        if (onBadgeUpdate != null) {
          onBadgeUpdate!(_unreadCount);
        }
        if (onUnreadCount != null) {
          onUnreadCount!(_unreadCount);
        }
      }
    });

    _socket!.on('notification_sent', (data) {
      debugPrint('✅ Notification sent: $data');
    });

    _socket!.on('error', (data) {
      debugPrint('❌ Socket error: $data');
      if (onError != null) {
        final message =
            data is Map
                ? data['message']?.toString() ?? 'Socket error'
                : data.toString();
        onError!(message);
      }
    });

    _socket!.on('disconnect', (_) {
      _isConnected = false;
      debugPrint('🔌 Socket disconnected');
    });

    _socket!.on('reconnect', (_) {
      _isConnected = true;
      debugPrint('🔄 Socket reconnected');
      _authenticate();
    });

    _socket!.on('reconnect_error', (data) {
      debugPrint('❌ Socket reconnection error: $data');
    });

    _socket!.on('pong', (_) {
      // Keep-alive response
    });
  }

  // ==================== AUTHENTICATION ====================

  void _authenticate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('userId') ?? _userId;
      final token = await ApiService.getToken();

      if (userId != null && _socket != null && _socket!.connected) {
        _socket!.emit('authenticate', {'userId': userId, 'token': token});
      } else if (_socket != null && _socket!.connected) {
        final userDataString = prefs.getString('user');
        if (userDataString != null) {
          final userData = jsonDecode(userDataString);
          final uid = userData['_id']?.toString();
          if (uid != null) {
            _socket!.emit('authenticate', {'userId': uid, 'token': token});
          }
        }
      }
    } catch (e) {
      debugPrint('❌ Auth emit error: $e');
    }
  }

  // ==================== PUBLIC METHODS ====================

  /// Emit an event to the socket server
  void emit(String event, dynamic data) {
    if (_socket != null && _socket!.connected) {
      _socket!.emit(event, data);
      debugPrint('✅ Emitted event: $event');
    } else {
      debugPrint('⚠️ Cannot emit $event, socket not connected');
    }
  }

  void getBadgeCount() {
    if (_socket != null && _socket!.connected) {
      _socket!.emit('get_badge_count', {});
    }
  }

  void markAsRead(String notificationId) {
    if (_socket != null && _socket!.connected) {
      _socket!.emit('mark_read', {'notificationId': notificationId});
    }
  }

  void markAllAsRead() {
    if (_socket != null && _socket!.connected) {
      _socket!.emit('mark_all_read', {});
    }
  }

  void getNotifications({int page = 1, int limit = 20, String filter = 'all'}) {
    if (_socket != null && _socket!.connected) {
      _socket!.emit('get_notifications', {
        'page': page,
        'limit': limit,
        'filter': filter,
      });
    }
  }

  void sendNotification({
    required String title,
    required String message,
    String? recipientId,
    bool sendToAll = false,
    String type = 'general',
    Map<String, dynamic> metadata = const {},
    String? screen,
  }) {
    if (_socket != null && _socket!.connected) {
      _socket!.emit('send_notification', {
        'title': title,
        'message': message,
        'recipientId': recipientId,
        'sendToAll': sendToAll,
        'type': type,
        'metadata': metadata,
        'screen': screen ?? 'notifications',
      });
    }
  }

  void disconnect() {
    if (_socket != null) {
      _socket!.disconnect();
      _socket!.dispose();
      _socket = null;
      _isConnected = false;
      _isInitialized = false;
    }
  }

  void reconnect() {
    if (_socket != null && !_isConnected) {
      _socket!.connect();
    }
  }

  void ping() {
    if (_socket != null && _socket!.connected) {
      _socket!.emit('ping');
    }
  }
}

// ==================== DEBUG HELPER ====================

void debugPrint(String message) {
  // ignore: avoid_print
  print(message);
}
