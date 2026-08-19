import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Shared learner preferences used by every focused practice session.
///
/// The reader is the first consumer, but these values intentionally live in a
/// service rather than inside StoryReaderScreen so listening, writing, and
/// future practice surfaces can use the same source of truth.
class SessionSettings extends ChangeNotifier {
  SessionSettings._();

  static final shared = SessionSettings._();

  static const _textScaleKey = 'session_text_scale';
  static const _translationKey = 'session_translate_sentences';
  static const _highlightKey = 'session_highlight_words';
  static const _underlineKey = 'session_underline_words';
  static const _autoPlayKey = 'session_auto_play_word_audio';
  static const _darkModeKey = 'session_dark_mode';
  static const _sentenceModeKey = 'session_sentence_mode';

  double textScale = 1;
  bool translateSentences = true;
  bool highlightWords = true;
  bool underlineWords = true;
  bool autoPlayWordAudio = false;
  bool darkMode = true;
  bool sentenceMode = false;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    textScale = (prefs.getDouble(_textScaleKey) ?? 1).clamp(0.9, 1.35);
    translateSentences = prefs.getBool(_translationKey) ?? true;
    highlightWords = prefs.getBool(_highlightKey) ?? true;
    underlineWords = prefs.getBool(_underlineKey) ?? true;
    autoPlayWordAudio = prefs.getBool(_autoPlayKey) ?? false;
    darkMode = prefs.getBool(_darkModeKey) ?? true;
    sentenceMode = prefs.getBool(_sentenceModeKey) ?? false;
    notifyListeners();
  }

  Future<void> setTextScale(double value) async {
    textScale = value.clamp(0.9, 1.35);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_textScaleKey, textScale);
  }

  Future<void> setTranslateSentences(bool value) async {
    translateSentences = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_translationKey, value);
  }

  Future<void> setHighlightWords(bool value) async {
    highlightWords = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_highlightKey, value);
  }

  Future<void> setUnderlineWords(bool value) async {
    underlineWords = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_underlineKey, value);
  }

  Future<void> setAutoPlayWordAudio(bool value) async {
    autoPlayWordAudio = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoPlayKey, value);
  }

  Future<void> setDarkMode(bool value) async {
    darkMode = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_darkModeKey, value);
  }

  Future<void> setSentenceMode(bool value) async {
    sentenceMode = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_sentenceModeKey, value);
  }
}
