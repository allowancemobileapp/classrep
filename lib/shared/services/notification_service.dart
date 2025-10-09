// lib/shared/services/notification_service.dart

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'dart:convert'; // For jsonDecode if needed for payload
import 'package:flutter/foundation.dart'; // For debugPrint

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  // Static callback for handling notification taps (set this from your app's main or router)
  static Function(Map<String, dynamic>)? onNotificationTap;

  Future<void> initialize() async {
    // Initialize timezone data
    tz.initializeTimeZones();

    // Android initialization settings
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@drawable/notification_icon');

    // iOS initialization settings
    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings();

    const InitializationSettings initializationSettings =
        InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );

    // ADD THIS: Handle notification taps (for both local and push)
    await _notificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) async {
        // Parse payload (from push data or local payload)
        final String? payloadString = response.payload;
        if (payloadString != null) {
          try {
            final Map<String, dynamic> payload = jsonDecode(payloadString);
            // Call your static callback (set this in main.dart or router)
            onNotificationTap?.call(payload);
            // Example: If payload has 'screen': '/chat', navigate
            // Get.toNamed(payload['screen']); // If using GetX
            // Or: navigatorKey.currentState?.pushNamed(payload['screen']); // If using GlobalKey<NavigatorState>
          } catch (e) {
            debugPrint('Error parsing notification payload: $e');
            // Fallback: Open main screen
            // navigatorKey.currentState?.pushNamed('/main');
          }
        }
      },
    );

    // Request permissions for Android 13+
    final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
        _notificationsPlugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidImplementation?.requestNotificationsPermission();

    // Request permissions for iOS
    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
  }

  Future<void> scheduleEventNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
  }) async {
    // Make sure the scheduled time is in the future
    if (scheduledTime.isBefore(DateTime.now())) {
      return;
    }

    await _notificationsPlugin.zonedSchedule(
      id,
      title,
      body,
      tz.TZDateTime.from(scheduledTime, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'event_reminders_channel',
          'Event Reminders',
          channelDescription: 'Notifications for upcoming events',
          importance: Importance.max,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  Future<void> cancelNotification(int id) async {
    await _notificationsPlugin.cancel(id);
  }

  Future<void> showPushNotification({
    required String title,
    required String body,
    Map<String, dynamic>? payload,
  }) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'push_channel', // A unique ID for the channel
      'Push Notifications',
      channelDescription: 'Notifications from Class Rep',
      importance: Importance.max,
      priority: Priority.high,
      icon: '@drawable/notification_icon', // The safe icon we created
    );
    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails();
    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    // UPDATED: Use jsonEncode for better payload handling on tap
    final String? payloadString = payload != null ? jsonEncode(payload) : null;

    // Use a unique ID (e.g., based on timestamp) to avoid overwriting
    final int notificationId =
        DateTime.now().millisecondsSinceEpoch.remainder(100000);

    await _notificationsPlugin.show(
      notificationId,
      title,
      body,
      details,
      payload: payloadString,
    );
  }
}
