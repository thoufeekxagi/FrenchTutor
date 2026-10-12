import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App-wide appearance state: light (default) or dark.
///
/// `DesignTokens` reads [darkMode] synchronously, so [load] must finish before
/// the first frame (main.dart awaits it) and [setDarkMode] notifies listeners
/// so the app shell can rebuild the whole tree with the new palette.
class AppAppearanceSettings extends ChangeNotifier {
  AppAppearanceSettings._();

  static final shared = AppAppearanceSettings._();

  static const _appearanceKey = 'app_dark_mode';
  static const _legacySessionKey = 'session_dark_mode';

  bool darkMode = false;
  bool _loaded = false;

  bool get loaded => _loaded;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    // Before v3 the app forced dark and always wrote `true`, so a stored
    // value says nothing about the learner's taste. Only an explicit choice
    // made after v3 is honoured, tracked by the v3 marker.
    final chosenInV3 = prefs.getBool(_v3ChoiceKey) ?? false;
    darkMode = chosenInV3 ? (prefs.getBool(_appearanceKey) ?? false) : false;
    _loaded = true;
    notifyListeners();
  }

  static const _v3ChoiceKey = 'app_dark_mode_v3_choice';

  Future<void> setDarkMode(bool value) async {
    if (darkMode == value && _loaded) return;
    darkMode = value;
    _loaded = true;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_appearanceKey, value);
    await prefs.setBool(_legacySessionKey, value);
    await prefs.setBool(_v3ChoiceKey, true);
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
