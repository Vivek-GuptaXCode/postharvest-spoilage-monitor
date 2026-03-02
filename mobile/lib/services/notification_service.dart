import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Global plugin instance – accessible from main.dart and elsewhere.
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  // ──────────────────────────────────────────────
  // Initialization
  // ──────────────────────────────────────────────

  /// Initialize notification channels, permissions and foreground listener.
  Future<void> initialize() async {
    // 1. Request FCM permission (Android 13+ / iOS)
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    print('Permission status: ${settings.authorizationStatus}');

    // 2. Create the spoilage_alerts notification channel
    const androidChannel = AndroidNotificationChannel(
      'spoilage_alerts', // id
      'Spoilage Alerts', // name
      description: 'High-priority alerts for spoilage risk detection',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(androidChannel);

    // 3. Request Android 13+ notification permission via local notifications
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();

    // 4. Initialize local notifications plugin
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const initSettings = InitializationSettings(android: androidSettings);

    await flutterLocalNotificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        // Handle notification tap
        final payload = response.payload;
        if (payload != null) {
          // Navigate based on payload (implement navigation logic as needed)
          print('Notification tapped with payload: $payload');
        }
      },
    );

    // 5. Listen for foreground FCM messages
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
  }

  // ──────────────────────────────────────────────
  // Token helpers
  // ──────────────────────────────────────────────

  /// Get the FCM token for this device.
  Future<String?> getToken() => _messaging.getToken();

  // ──────────────────────────────────────────────
  // Topic subscription
  // ──────────────────────────────────────────────

  /// Subscribe to a warehouse-specific topic for push notifications.
  Future<void> subscribeToWarehouse(String warehouseId) {
    return _messaging.subscribeToTopic('warehouse_$warehouseId');
  }

  /// Unsubscribe from a warehouse topic.
  Future<void> unsubscribeFromWarehouse(String warehouseId) {
    return _messaging.unsubscribeFromTopic('warehouse_$warehouseId');
  }

  // ──────────────────────────────────────────────
  // Foreground message handler
  // ──────────────────────────────────────────────

  /// Show a local notification when a message arrives while the app is open.
  void _handleForegroundMessage(RemoteMessage message) {
    final notification = message.notification;
    if (notification == null) return;

    flutterLocalNotificationsPlugin.show(
      notification.hashCode,
      notification.title ?? 'PostHarvest Alert',
      notification.body ?? '',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'spoilage_alerts', // channel id
          'Spoilage Alerts', // channel name
          channelDescription: 'Alerts for spoilage risk in warehouses',
          importance: Importance.max,
          priority: Priority.high,
          color: Colors.red,
          icon: '@mipmap/ic_launcher',
        ),
      ),
    );
  }
}
