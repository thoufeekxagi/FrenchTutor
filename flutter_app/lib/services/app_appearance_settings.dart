import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App-wide appearance state.
///
/// The setting is deliberately independent from per-session controls such as
/// translation and playback rate, but it shares the existing session-dark-mode
/// key so returning learners keep the appearance they already chose.
class AppAppearanceSettings extends ChangeNotifier {
  AppAppearanceSettings._();

  static final shared = AppAppearanceSettings._();

  static const _appearanceKey = 'app_dark_mode';
  static const _legacySessionKey = 'session_dark_mode';

  bool darkMode = true;
  bool _loaded = false;

  bool get loaded => _loaded;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    darkMode =
        prefs.getBool(_appearanceKey) ??
        prefs.getBool(_legacySessionKey) ??
        true;
    _loaded = true;
    notifyListeners();
  }

  Future<void> setDarkMode(bool value) async {
    if (darkMode == value && _loaded) return;
    darkMode = value;
    _loaded = true;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_appearanceKey, value);
    // Keep focused reader/listener sessions and the app shell on the same
    // persisted choice while those screens finish migrating to this source.
    await prefs.setBool(_legacySessionKey, value);
  }

  /// Synchronizes the controller when a legacy focused-session control writes
  /// the shared preference directly.
  void adoptDarkMode(bool value) {
    if (darkMode == value && _loaded) return;
    darkMode = value;
    _loaded = true;
    notifyListeners();
  }
}
