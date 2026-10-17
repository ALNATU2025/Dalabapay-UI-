// lib/core/services/push_notification_service.dart

import 'dart:async';
import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_app_badger/flutter_app_badger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/widgets.dart'; // ✅ ADD THIS LINE
import 'api_service.dart';

class PushNotificationService {
  static final PushNotificationService _instance =
      PushNotificationService._internal();
  factory PushNotificationService() => _instance;
  PushNotificationService._internal();

  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  final _notificationStream =
      StreamController<Map<String, dynamic>>.broadcast();
  final _unreadCountStream = StreamController<int>.broadcast();

  Stream<Map<String, dynamic>> get notificationStream =>
      _notificationStream.stream;
  Stream<int> get unreadStream => _unreadCountStream.stream;

  List<Map<String, dynamic>> notifications = [];
  int unreadCount = 0;

  Future<void> initialize() async {
    if (kIsWeb) return;

    try {
      await _firebaseMessaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

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

      // ✅ CORRECT: No 'refresh' parameter
      await _localNotifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: (response) {
          _handleTap(response.payload);
        },
      );

      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        'dalabapay_channel',
        'DalabaPay Notifications',
        description: 'DalabaPay app notifications',
        importance: Importance.max,
      );

      await _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(channel);

      _setupListeners();
      await _getToken();
      await loadNotifications();

      debugPrint('✅ PushNotificationService initialized');
    } catch (e) {
      debugPrint('❌ PushNotificationService init error: $e');
    }
  }

  void _setupListeners() {
    FirebaseMessaging.onMessage.listen((message) {
      debugPrint('🔔 Foreground: ${message.notification?.title}');
      _showLocalNotification(message);
      _updateBadge(message.data['badgeCount']);
    });

    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _handleTap(jsonEncode(message.data));
    });

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

  void _handleTap(String? payload) {
    debugPrint('📱 Notification tap: $payload');
    if (payload == null) return;
    try {
      final data = jsonDecode(payload);
      final screen = data['screen'] ?? 'notifications';
      navigatorKey.currentState?.pushNamed('/$screen');
    } catch (e) {
      debugPrint('❌ Tap handling error: $e');
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
