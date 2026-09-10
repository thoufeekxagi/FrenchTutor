import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App-wide appearance state.
///
/// The product is dark-only for the current release. The compatibility API
/// remains so older focused-session code can continue to call it without
/// reintroducing a user-facing appearance switch.
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
    // Ignore a legacy light-mode value: this release intentionally has one
    // palette, so an upgraded install must return to dark mode as well.
    darkMode = true;
    await prefs.setBool(_appearanceKey, true);
    await prefs.setBool(_legacySessionKey, true);
    _loaded = true;
    notifyListeners();
  }

  Future<void> setDarkMode(bool value) async {
    if (darkMode && _loaded) return;
    darkMode = true;
    _loaded = true;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_appearanceKey, true);
    await prefs.setBool(_legacySessionKey, true);
  }

  /// Synchronizes the controller when a legacy focused-session control writes
  /// the shared preference directly. The app shell never exposes this as a
  /// setting in the current release, but keeping the adapter functional
  /// preserves isolated light-palette rendering in tests and migrations.
  void adoptDarkMode(bool value) {
    if (darkMode == value && _loaded) return;
    darkMode = value;
    _loaded = true;
    notifyListeners();
  }
}
