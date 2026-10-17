import 'dart:async';
import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_app_badger/flutter_app_badger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/widgets.dart';

import 'api_service.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  late final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  // ✅ Initialize streams EARLY (not in constructor)
  final _notificationStream =
      StreamController<Map<String, dynamic>>.broadcast();
  final _unreadCountStream = StreamController<int>.broadcast();

  Stream<Map<String, dynamic>> get notificationStream =>
      _notificationStream.stream;
  Stream<int> get unreadStream => _unreadCountStream.stream;

  List<Map<String, dynamic>> notifications = [];
  int unreadCount = 0;
  bool _isInitialized = false;

  // ✅ Add getter for initialization status
  bool get isInitialized => _isInitialized;

  Future<void> initialize() async {
    // ✅ Prevent double initialization
    if (_isInitialized) {
      debugPrint('ℹ️ NotificationService already initialized');
      return;
    }
    if (kIsWeb) return;

    try {
      // Request permissions
      await _firebaseMessaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      // Initialize local notifications
      const AndroidInitializationSettings androidInit =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const DarwinInitializationSettings iosInit = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      const InitializationSettings initSettings = InitializationSettings(
        android: androidInit,
        iOS: iosInit,
      );

      await _localNotifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: (response) {
          _handleTap(response.payload);
        },
      );

      // Setup FCM listeners
      _setupListeners();

      // Get token
      await _getToken();

      // Load notifications
      await loadNotifications();

      // ✅ Mark as initialized
      _isInitialized = true;
      debugPrint('✅ NotificationService initialized');
    } catch (e) {
      debugPrint('❌ NotificationService init error: $e');
    }
  }

  void _setupListeners() {
    // Foreground
    FirebaseMessaging.onMessage.listen((message) {
      debugPrint('🔔 Foreground: ${message.notification?.title}');
      _showLocalNotification(message);
      _updateBadge(message.data['badgeCount']);
    });

    // Background tap
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _handleTap(jsonEncode(message.data));
    });

    // Token refresh
    _firebaseMessaging.onTokenRefresh.listen((token) async {
      await _saveToken(token);
    });
  }

  Future<void> _getToken() async {
    try {
      final token = await _firebaseMessaging.getToken();
      if (token != null) {
        await _saveToken(token);
      }
    } catch (e) {
      debugPrint('❌ Get token error: $e');
    }
  }

  Future<void> _saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('fcm_token', token);
    try {
      await ApiService.updateDeviceToken(token);
    } catch (e) {
      debugPrint('❌ Save token error: $e');
    }
  }

  void _showLocalNotification(RemoteMessage message) {
    final notification = message.notification;
    if (notification == null) return;

    _localNotifications.show(
      notification.hashCode,
      notification.title,
      notification.body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'dalabapay_channel',
          'DalabaPay Notifications',
          channelDescription: 'DalabaPay app notifications',
          importance: Importance.max,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: jsonEncode(message.data),
    );
  }

  Future<void> _updateBadge(dynamic count) async {
    if (count == null) return;
    try {
      final badgeCount = int.tryParse(count.toString()) ?? 0;
      if (badgeCount > 0) {
        await FlutterAppBadger.updateBadgeCount(badgeCount);
      } else {
        await FlutterAppBadger.removeBadge();
      }
      unreadCount = badgeCount;
      _unreadCountStream.add(badgeCount);
    } catch (e) {
      debugPrint('❌ Badge error: $e');
    }
  }

  // ✅ Pending route — for taps that arrive before the navigator is ready
  String? _pendingRoute;

  void _handleTap(String? payload) {
    debugPrint('📱 Notification tap: $payload');
    if (payload == null) return;
    try {
      final data = jsonDecode(payload);
      final screen = data['screen'] ?? 'notifications';
      final route = '/$screen';

      // If navigator is ready — navigate immediately
      if (navigatorKey.currentState != null) {
        navigatorKey.currentState?.pushNamed(route);
      } else {
        // Cold-start: queue it and flush later
        _pendingRoute = route;
        debugPrint('🕓 Navigator not ready — queued route: $route');
      }
    } catch (e) {
      debugPrint('❌ Tap handling error: $e');
    }
  }

  /// Call this after the first frame so a queued tap navigates correctly.
  void flushPendingNavigation() {
    if (_pendingRoute != null && navigatorKey.currentState != null) {
      final route = _pendingRoute!;
      _pendingRoute = null;
      debugPrint('🚀 Flushing queued route: $route');
      navigatorKey.currentState?.pushNamed(route);
    }
  }

  Future<void> loadNotifications() async {
    try {
      final response = await ApiService.getNotifications();
      notifications = List<Map<String, dynamic>>.from(response);
      unreadCount = notifications.where((n) => n['isRead'] == false).length;
      _unreadCountStream.add(unreadCount);
    } catch (e) {
      debugPrint('❌ Load notifications error: $e');
    }
  }

  Future<int> getUnreadCount() async {
    try {
      final count = await ApiService.getUnreadNotificationCount();
      unreadCount = count;
      _unreadCountStream.add(count);
      return count;
    } catch (e) {
      return unreadCount;
    }
  }

  void dispose() {
    _notificationStream.close();
    _unreadCountStream.close();
  }
}

// Global navigator key
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
