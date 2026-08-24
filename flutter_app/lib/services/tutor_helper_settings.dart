import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Practice surfaces that can independently use the in-lesson tutor helper.
///
/// The preference is intentionally separate from the selected tutor persona:
/// a learner can keep one tutor selected while deciding where that tutor is
/// useful. Every screen reads this same service instead of keeping a local
/// boolean that can drift from Settings.
enum TutorHelperSurface { speaking, listening, vocabulary, reading, writing }

extension TutorHelperSurfaceDetails on TutorHelperSurface {
  String get storageKey => 'tutor_helper_enabled_$name';

  String get label => switch (this) {
    TutorHelperSurface.speaking => 'Speaking',
    TutorHelperSurface.listening => 'Listening',
    TutorHelperSurface.vocabulary => 'Vocabulary',
    TutorHelperSurface.reading => 'Reading',
    TutorHelperSurface.writing => 'Writing',
  };

  String get description => switch (this) {
    TutorHelperSurface.speaking =>
      'Get a short hint without leaving the speaking lesson',
    TutorHelperSurface.listening =>
      'Ask for context while you listen and follow the transcript',
    TutorHelperSurface.vocabulary =>
      'Get help with the current word and its example',
    TutorHelperSurface.reading =>
      'Keep reading focused; turn tutor help on when you need it',
    TutorHelperSurface.writing =>
      'Keep writing focused; turn tutor help on when you need it',
  };

  /// Defaults reflect the intended first-run experience: active coaching in
  /// interactive/audio practice, optional coaching in reading and writing.
  bool get defaultEnabled => switch (this) {
    TutorHelperSurface.speaking => true,
    TutorHelperSurface.listening => true,
    TutorHelperSurface.vocabulary => true,
    TutorHelperSurface.reading => false,
    TutorHelperSurface.writing => false,
  };
}

/// Single source of truth for helper availability across every practice area.
///
/// Values are optimistic in memory so a surface has the correct first-run
/// default before preferences finish loading. Once loaded, persisted values
/// replace only the surfaces the learner has explicitly changed.
class TutorHelperSettings extends ChangeNotifier {
  TutorHelperSettings._();

  static final shared = TutorHelperSettings._();

  final Map<TutorHelperSurface, bool> _values = {};
  Future<void>? _loadFuture;

  bool isEnabled(TutorHelperSurface surface) =>
      _values[surface] ?? surface.defaultEnabled;

  Future<void> load() {
    return _loadFuture ??= _loadPersistedValues();
  }

  Future<void> _loadPersistedValues() async {
    final prefs = await SharedPreferences.getInstance();
    for (final surface in TutorHelperSurface.values) {
      final saved = prefs.getBool(surface.storageKey);
      if (saved != null) _values[surface] = saved;
    }
    notifyListeners();
  }

  Future<void> setEnabled(TutorHelperSurface surface, bool enabled) async {
    await load();
    _values[surface] = enabled;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(surface.storageKey, enabled);
  }

  Future<void> reset(TutorHelperSurface surface) async {
    await load();
    _values.remove(surface);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(surface.storageKey);
  }
}
