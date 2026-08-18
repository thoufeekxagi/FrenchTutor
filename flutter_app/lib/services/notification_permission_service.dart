import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:permission_handler/permission_handler.dart';

/// Owns the OS notification permission boundary. Scheduling is handled by
/// [NotificationSchedulerService] after this permission result is recorded.
abstract final class NotificationPermissionService {
  static Future<String> request() async {
    if (kIsWeb) return 'unsupported';
    try {
      final status = await Permission.notification.request();
      return _wireName(status);
    } catch (_) {
      return 'unavailable';
    }
  }

  static String _wireName(PermissionStatus status) => switch (status) {
    PermissionStatus.granted || PermissionStatus.limited => 'granted',
    PermissionStatus.denied => 'denied',
    PermissionStatus.permanentlyDenied => 'permanently_denied',
    PermissionStatus.restricted => 'restricted',
    _ => 'unknown',
  };
}
