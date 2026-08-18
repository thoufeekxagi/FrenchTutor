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
  static const _scheduleWeeksAhead = 4;
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

  /// Replaces the next four weeks of reminders with the learner's current
  /// plan. One-off dates are intentional: a repeating OS notification would
  /// reuse the same copy forever, while this lets each upcoming reminder use
  /// a fresh, useful prompt without requiring a server push.
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

    final now = tz.TZDateTime.now(tz.local);
    final occurrences = <({String day, tz.TZDateTime date})>[];
    for (var week = 0; week < _scheduleWeeksAhead; week++) {
      for (final day in profile.preferredDays) {
        final weekday = _weekday(day);
        if (weekday == null) continue;
        occurrences.add((
          day: day,
          date: _nextOccurrence(weekday, hour, minute, week: week, now: now),
        ));
      }
    }
    occurrences.sort((a, b) => a.date.compareTo(b.date));

    var index = 0;
    for (final occurrence in occurrences) {
      // If the learner already completed today's route, do not interrupt
      // them with a reminder later today. Future reminders remain scheduled.
      if (_isToday(occurrence.date, now) && _completed(summary)) continue;

      final message = _message(profile, summary, occurrence.date);
      await _plugin.zonedSchedule(
        id: _firstNotificationId + index++,
        title: message.title,
        body: message.body,
        scheduledDate: occurrence.date,
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: 'open_practice',
      );
      debugPrint(
        'Scheduled French reminder for ${occurrence.day} at '
        '${occurrence.date} (${tz.local.name}): ${message.title}',
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

  static tz.TZDateTime _nextOccurrence(
    int weekday,
    int hour,
    int minute, {
    required int week,
    required tz.TZDateTime now,
  }) {
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
      now.day + daysUntil + (week * 7),
      hour.clamp(0, 23),
      minute.clamp(0, 59),
    );
  }

  static bool _isToday(tz.TZDateTime value, tz.TZDateTime now) =>
      value.year == now.year &&
      value.month == now.month &&
      value.day == now.day;

  static bool _completed(DailySummary? summary) {
    if (summary == null || !summary.hasActivity) return false;
    return summary.stagesCompleted >= summary.stagesTotal &&
        summary.stagesTotal > 0;
  }

  static _NotificationMessage _message(
    Profile profile,
    DailySummary? summary,
    tz.TZDateTime scheduledDate,
  ) {
    final goal = _goalOutcome(profile);
    final focus = _focus(profile);
    final seed =
        scheduledDate.year * 1000 +
        (scheduledDate.month * 31) +
        scheduledDate.day +
        profile.goal.hashCode.abs();
    final variation = seed % 4;

    if (summary != null && summary.hardWords.isNotEmpty) {
      final count = summary.hardWords.length;
      return switch (variation) {
        0 => _NotificationMessage(
          '🇫🇷 Those tricky words are back',
          'See if today’s quick review feels easier.',
        ),
        1 => _NotificationMessage(
          '🇫🇷 Ready for a second look?',
          'Your quick word review is waiting inside.',
        ),
        2 => _NotificationMessage(
          '🇫🇷 A small French win is waiting',
          'Try the $count ${count == 1 ? 'word' : 'words'} that slowed you down last time.',
        ),
        _ => _NotificationMessage(
          '🇫🇷 Your next phrase is hiding here',
          'Open ParleSprint and give your tricky $goal words another go.',
        ),
      };
    }

    if (summary != null && summary.hasActivity) {
      final total = summary.stagesTotal.clamp(1, 99);
      final completed = summary.stagesCompleted.clamp(0, total);
      final progress = ((completed / total) * 100).round();
      if (completed >= total) {
        return _NotificationMessage(
          '🇫🇷 Keep the thread going',
          'One small $focus review can keep today’s progress warm.',
        );
      }
      return switch (variation) {
        0 => _NotificationMessage(
          '🇫🇷 Your route is still open',
          'One short step can move today’s $goal French forward.',
        ),
        1 => _NotificationMessage(
          '🇫🇷 The next turn is yours',
          'Pick up your $focus practice when you have a minute.',
        ),
        2 => _NotificationMessage(
          '🇫🇷 You’re $progress% of the way there',
          'Open ParleSprint and see what comes next.',
        ),
        _ => _NotificationMessage(
          '🇫🇷 Your next French scene is waiting',
          'A short $focus challenge is ready inside your route.',
        ),
      };
    }

    return switch (variation) {
      0 => const _NotificationMessage(
        '🇫🇷 A new French scene is waiting',
        'Open ParleSprint to discover today’s short challenge.',
      ),
      1 => const _NotificationMessage(
        '🇫🇷 Today’s route has a new turn',
        'Your next phrase is waiting inside.',
      ),
      2 => _NotificationMessage(
        '🇫🇷 One phrase closer',
        'Pick up where you left off with a quick $focus challenge.',
      ),
      _ => const _NotificationMessage(
        '🇫🇷 Something new is ready in French',
        'Open ParleSprint and see what today brings.',
      ),
    };
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

final class _NotificationMessage {
  const _NotificationMessage(this.title, this.body);

  final String title;
  final String body;
}
