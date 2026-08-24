import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/tutor_helper_settings.dart';

/// Shared provider for the per-surface tutor-helper settings.
final tutorHelperSettingsProvider = ChangeNotifierProvider<TutorHelperSettings>(
  (ref) {
    final settings = TutorHelperSettings.shared;
    unawaited(settings.load());
    return settings;
  },
);
