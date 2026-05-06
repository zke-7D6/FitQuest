import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tzData;

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> init() async {
    if (kIsWeb) return;

    tzData.initializeTimeZones();

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');

    const ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const settings = InitializationSettings(
      android: android,
      iOS: ios,
    );

    await _plugin.initialize(settings);

    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    _initialized = true;
  }

  static const _androidChannel = AndroidNotificationDetails(
    'fitquest_main',
    'FitQuest',
    channelDescription: 'FitQuest notifications',
    importance: Importance.high,
    priority: Priority.high,
    color: Color(0xFF00FF88),
  );

  static const _dailyChannel = AndroidNotificationDetails(
    'fitquest_daily',
    'Daily Reminders',
    channelDescription: 'Daily FitQuest reminders',
    importance: Importance.high,
    priority: Priority.high,
  );

  static Future<void> show({
    required int id,
    required String title,
    required String body,
  }) async {
    if (!_initialized || kIsWeb) return;

    await _plugin.show(
      id,
      title,
      body,
      const NotificationDetails(
        android: _androidChannel,
        iOS: DarwinNotificationDetails(),
      ),
    );
  }

  static Future<void> scheduleAllReminders() async {
    if (!_initialized || kIsWeb) return;

    await cancelAll();

    await _scheduleDaily(
      1,
      8,
      0,
      'FITQUEST ⚡',
      'Good morning! Check your daily quest and get moving.',
    );

    await _scheduleDaily(
      2,
      12,
      0,
      'Step Check 👟',
      'How are your steps looking? Keep moving!',
    );

    await _scheduleDaily(
      3,
      20,
      0,
      'Daily Check-in 📋',
      'Don\'t forget your check-in before bed!',
    );
  }

  static Future<void> _scheduleDaily(
    int id,
    int hour,
    int minute,
    String title,
    String body,
  ) async {
    if (!_initialized || kIsWeb) return;

    await _plugin.zonedSchedule(
      id,
      title,
      body,
      _nextTime(hour, minute),
      NotificationDetails(
        android: _dailyChannel,
        iOS: const DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  static tz.TZDateTime _nextTime(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);

    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    return scheduled;
  }

  static Future<void> questAccepted(String questName) async {
    await show(
      id: 10,
      title: 'Quest Accepted! 🗺️',
      body: '$questName — get outside and complete it!',
    );
  }

  static Future<void> questCompleted(String questName, int xp) async {
    await show(
      id: 11,
      title: 'QUEST COMPLETE! 🏆',
      body: '$questName — +$xp XP earned!',
    );
  }

  static Future<void> stepGoalReached(int steps) async {
    await show(
      id: 12,
      title: 'Goal Reached! 🎉',
      body: 'You hit $steps steps today. Amazing work!',
    );
  }

  static Future<void> highActivityWarning(int steps) async {
    await show(
      id: 13,
      title: 'High Activity Warning ⚠️',
      body:
          'You have walked $steps steps today. Hydrate, rest, and avoid overexertion.',
    );
  }

  static Future<void> extremeActivityWarning(int steps) async {
    await show(
      id: 14,
      title: 'Extreme Activity Alert 🚨',
      body:
          'You have walked $steps steps today. This is very high. Prioritize recovery and stop if you feel pain, dizziness, or unusual fatigue.',
    );
  }

  static Future<void> cancelAll() async {
    if (!_initialized || kIsWeb) return;
    await _plugin.cancelAll();
  }
}