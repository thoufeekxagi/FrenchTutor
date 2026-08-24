import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/app_appearance_settings.dart';

final appearanceSettingsProvider =
    ChangeNotifierProvider<AppAppearanceSettings>((ref) {
      final settings = AppAppearanceSettings.shared;
      unawaited(settings.load());
      return settings;
    });
