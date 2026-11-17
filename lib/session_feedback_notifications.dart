import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Local, on-device reminders are used so a member can be asked for feedback
/// even when the app is no longer open. A server push service can replace this
/// later when sessions are backed by an API.
class SessionFeedbackNotifications {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static Future<void> initialize() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    tz_data.initializeTimeZones();
    const android = AndroidInitializationSettings('ic_stat_rally');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _notifications.initialize(
      const InitializationSettings(android: android, iOS: ios),
    );
    _ready = true;
  }

  /// Ask only after someone chooses to attend: the permission prompt has clear
  /// context and Android/iOS can then deliver the scheduled local notification.
  static Future<void> scheduleForWeeknightRally() async {
    if (!_ready) return;

    final permitted = await _requestPermission();
    if (!permitted) return;

    final now = DateTime.now();
    // Weeknight Rally finishes at 8pm. Remind the member 30 minutes later.
    final daysUntilWednesday = (DateTime.wednesday - now.weekday + 7) % 7;
    var sessionEnd = DateTime(
      now.year,
      now.month,
      now.day + daysUntilWednesday,
      20,
    );
    if (!sessionEnd.isAfter(now)) {
      sessionEnd = sessionEnd.add(const Duration(days: 7));
    }
    final reminder = sessionEnd.add(const Duration(minutes: 30));

    await _notifications.zonedSchedule(
      1001,
      'How was Weeknight Rally?',
      'Tell us how your session went — it takes less than a minute.',
      tz.TZDateTime.from(reminder, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'session_feedback',
          'Session feedback reminders',
          channelDescription:
              'Reminders to give feedback after a Rally4ever session',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          icon: 'ic_stat_rally',
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: 'session-feedback',
    );
  }

  static Future<bool> _requestPermission() async {
    if (Platform.isIOS) {
      return await _notifications
              .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin
              >()
              ?.requestPermissions(alert: true, badge: true, sound: true) ??
          false;
    }
    if (Platform.isAndroid) {
      return await _notifications
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >()
              ?.requestNotificationsPermission() ??
          false;
    }
    return false;
  }
}
