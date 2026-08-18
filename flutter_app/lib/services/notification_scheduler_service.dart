import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'daily_summary_service.dart';
import '../models/profile.dart';

/// Schedules the learner's recurring study reminders on the device.
///
/// These are intentionally local notifications rather than server push:
/// reminders work offline, follow the device's local timezone, and do not
/// require storing a push token or learner message content on a server.
abstract final class NotificationSchedulerService {
  static const _channelId = 'parlesprint-study-reminders';
  static const _firstNotificationId = 4200;
  static final _plugin = FlutterLocalNotificationsPlugin();
  static Future<void>? _initializing;

  static Future<void> _ensureInitialized() {
    if (kIsWeb) return Future.value();
    return _initializing ??= _initialize();
  }

  static Future<void> _initialize() async {
    tz.initializeTimeZones();
    await _refreshLocalTimezone();

    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestSoundPermission: false,
          requestBadgePermission: false,
        ),
      ),
    );
  }

  /// Replaces the existing weekly reminders with the learner's current plan.
  /// Calling this after onboarding or Settings changes keeps the OS schedule
  /// synchronized with the profile without duplicating notifications.
  static Future<void> sync(Profile profile, {DailySummary? summary}) async {
    try {
      await _sync(profile, summary: summary);
    } catch (error, stackTrace) {
      // Notifications are an optional retention aid; a platform scheduling
      // failure must never block onboarding or settings changes.
      debugPrint('Notification schedule failed: $error\n$stackTrace');
    }
  }

  static Future<void> _sync(Profile profile, {DailySummary? summary}) async {
    if (kIsWeb) return;
    await _ensureInitialized();
    // The learner may travel or change the device timezone while the app is
    // installed. Read the phone's current IANA zone on every reschedule so a
    // chosen 19:00 remains 19:00 local time.
    await _refreshLocalTimezone();
    await _plugin.cancelAll();

    if (profile.reminderTime == null ||
        profile.preferredDays.isEmpty ||
        profile.notificationPermissionState != 'granted') {
      return;
    }

    final parts = profile.reminderTime!.split(':');
    final hour = int.tryParse(parts.first) ?? 19;
    final minute = int.tryParse(parts.last) ?? 0;
    final details = NotificationDetails(
      android: const AndroidNotificationDetails(
        _channelId,
        'French study reminders',
        channelDescription: 'Personalized reminders for French practice.',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        threadIdentifier: _channelId,
      ),
    );

    var index = 0;
    for (final day in profile.preferredDays) {
      final weekday = _weekday(day);
      if (weekday == null) continue;
      final scheduledDate = _nextOccurrence(weekday, hour, minute);
      await _plugin.zonedSchedule(
        id: _firstNotificationId + index++,
        title: _title(profile),
        body: _body(profile, summary),
        scheduledDate: scheduledDate,
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
        payload: 'open_practice',
      );
      debugPrint(
        'Scheduled French reminder for $day at '
        '$scheduledDate (${tz.local.name})',
      );
    }
  }

  static Future<void> _refreshLocalTimezone() async {
    try {
      final zone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zone.identifier));
    } catch (error, stackTrace) {
      debugPrint('Could not read device timezone: $error\n$stackTrace');
      tz.setLocalLocation(tz.getLocation('UTC'));
    }
  }

  static int? _weekday(String value) => switch (value.toLowerCase()) {
    'mon' => DateTime.monday,
    'tue' => DateTime.tuesday,
    'wed' => DateTime.wednesday,
    'thu' => DateTime.thursday,
    'fri' => DateTime.friday,
    'sat' => DateTime.saturday,
    'sun' => DateTime.sunday,
    _ => null,
  };

  static tz.TZDateTime _nextOccurrence(int weekday, int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    final candidate = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour.clamp(0, 23),
      minute.clamp(0, 59),
    );
    var daysUntil = (weekday - now.weekday) % 7;
    if (daysUntil == 0 && !candidate.isAfter(now)) daysUntil = 7;
    // Construct the target using local calendar fields rather than adding a
    // fixed duration. This keeps the reminder at the selected wall-clock
    // time across daylight-saving transitions.
    return tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day + daysUntil,
      hour.clamp(0, 23),
      minute.clamp(0, 59),
    );
  }

  static String _title(Profile profile) {
    return switch (profile.goal) {
      'tef_canada' => '🇫🇷 TEF / TCF practice is ready',
      'work' => '🇫🇷 Your professional French practice',
      'relocation' => '🇫🇷 Your relocation French practice',
      'travel' => '🇫🇷 Your travel French practice',
      _ => '🇫🇷 Your French practice is ready',
    };
  }

  static String _body(Profile profile, DailySummary? summary) {
    final goal = _goalOutcome(profile);
    final focus = _focus(profile);

    if (summary != null && summary.hardWords.isNotEmpty) {
      final count = summary.hardWords.length;
      return 'Review $count tricky ${count == 1 ? 'word' : 'words'} next, then keep building $goal French.';
    }

    if (summary != null && summary.hasActivity) {
      final total = summary.stagesTotal.clamp(1, 99);
      final completed = summary.stagesCompleted.clamp(0, total);
      final progress = ((completed / total) * 100).round();
      if (completed >= total) {
        return 'Nice work — today’s route is complete. A short $focus review keeps your $goal French ready.';
      }
      return 'You’re $progress% through today’s route. Continue with $focus to strengthen your $goal French.';
    }

    final rhythm = switch (profile.sessionLength) {
      'quick' => 'quick',
      'deep' => 'focused',
      _ => 'daily',
    };
    final level = LearnerLevel.displayLabel(profile.level);
    return 'Your personalized $level $focus $rhythm practice is ready. Continue your $goal French route.';
  }

  static String _focus(Profile profile) {
    if (profile.interests.isEmpty) return 'next lesson';
    final value = profile.interests.first.trim().toLowerCase();
    return value.isEmpty ? 'next lesson' : value;
  }

  static String _goalOutcome(Profile profile) => switch (profile.goal) {
    'tef_canada' => 'TEF / TCF',
    'work' => 'professional',
    'relocation' => 'relocation',
    'travel' => 'travel',
    'culture' => 'culture',
    _ => 'everyday',
  };
}
