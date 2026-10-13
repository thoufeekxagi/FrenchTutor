import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

import '../v3_prefs.dart';
import 'v3_story.dart';

/// The authored stories, in the order listed by `assets/content/tcf/stories.json`.
abstract final class V3Stories {
  static const indexPath = 'assets/content/tcf/stories.json';
  static const dir = 'assets/content/tcf/stories/';

  static Future<List<V3Story>> load({AssetBundle? bundle}) async {
    final b = bundle ?? rootBundle;
    final index =
        jsonDecode(await b.loadString(indexPath)) as Map<String, dynamic>;
    final files = (index['stories'] as List? ?? const []).cast<String>();
    final stories = <V3Story>[];
    for (final file in files) {
      try {
        final raw = jsonDecode(await b.loadString('$dir$file'));
        stories.add(V3Story.fromJson(raw as Map<String, dynamic>));
      } catch (error) {
        debugPrint('V3Stories: could not load $file: $error');
        if (kDebugMode) rethrow;
      }
    }
    return stories;
  }
}

/// Finished stories, where the learner stopped, saved words, and the
/// story-reader preferences that are not shared with other screens.
abstract final class V3StoryProgress {
  static String get _doneKey => v3Key('v3_story_done');
  static String get _posKey => v3Key('v3_story_position');
  static String get _savedKey => v3Key('v3_story_saved_words');
  static String get _hearKey => v3Key('v3_story_hear_words');

  static final hearWords = ValueNotifier<bool>(true);

  static Future<void> loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    hearWords.value = prefs.getBool(_hearKey) ?? true;
  }

  static Future<void> setHearWords(bool value) async {
    hearWords.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_hearKey, value);
  }

  static Future<Set<String>> done() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_doneKey) ?? const []).toSet();
  }

  static Future<void> markDone(String storyId) async {
    final prefs = await SharedPreferences.getInstance();
    final set = (prefs.getStringList(_doneKey) ?? const []).toSet()
      ..add(storyId);
    await prefs.setStringList(_doneKey, set.toList());
    await savePosition(storyId, 0);
  }

  /// Sentence index to resume from, by story id. Zero means not started.
  static Future<Map<String, int>> positions() async {
    final prefs = await SharedPreferences.getInstance();
    final out = <String, int>{};
    for (final entry in prefs.getStringList(_posKey) ?? const <String>[]) {
      final i = entry.lastIndexOf(':');
      if (i < 0) continue;
      final n = int.tryParse(entry.substring(i + 1));
      if (n != null) out[entry.substring(0, i)] = n;
    }
    return out;
  }

  static Future<void> savePosition(String storyId, int sentence) async {
    final prefs = await SharedPreferences.getInstance();
    final map = await positions()
      ..[storyId] = sentence;
    await prefs.setStringList(_posKey, [
      for (final e in map.entries) '${e.key}:${e.value}',
    ]);
  }

  static Future<Set<String>> savedWords() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_savedKey) ?? const []).toSet();
  }

  static Future<bool> toggleSaved(String storyId, String word) async {
    final prefs = await SharedPreferences.getInstance();
    final set = (prefs.getStringList(_savedKey) ?? const []).toSet();
    final key = '$storyId|$word';
    final nowSaved = !set.remove(key);
    if (nowSaved) set.add(key);
    await prefs.setStringList(_savedKey, set.toList());
    return nowSaved;
  }
}
