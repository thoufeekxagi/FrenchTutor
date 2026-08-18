import '../models/content_models.dart';

/// Presentation copy for learner-generated vocabulary cards.
///
/// Older records were saved with generic titles such as "Today's Words".
/// Keep those records useful by promoting their already-stored focus sentence
/// to the visible title, then fall back to the actual word meanings.
abstract final class VocabularySetCopy {
  static String title(GeneratedVocabularySet set) {
    final saved = set.title.trim();
    if (!_isGeneric(saved)) return saved;

    final summary = _firstSentence(set.summary);
    if (summary.isNotEmpty && !_isGeneric(summary)) return summary;

    final words = set.entries
        .map((entry) => entry.en.trim())
        .where((word) => word.isNotEmpty)
        .take(3)
        .join(', ');
    if (words.isNotEmpty) {
      return words[0].toUpperCase() + words.substring(1);
    }
    return 'A useful French set';
  }

  static String? summary(GeneratedVocabularySet set, {String? displayedTitle}) {
    final value = _firstSentence(set.summary);
    if (value.isEmpty || value == (displayedTitle ?? title(set))) return null;
    if (_isGeneric(value)) return null;
    return value;
  }

  static bool _isGeneric(String value) {
    final normalized = value
        .toLowerCase()
        .replaceAll(RegExp(r'[’‘]'), "'")
        .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return normalized == "today's words" ||
        normalized == 'todays words' ||
        normalized == 'today s words' ||
        normalized == 'today s vocabulary' ||
        normalized == 'recommended vocabulary' ||
        normalized == 'course vocabulary' ||
        normalized == 'vocabulary session' ||
        normalized == 'new words' ||
        normalized == 'a useful french set' ||
        normalized.startsWith('a saved vocabulary practice set built');
  }

  static String _firstSentence(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '';
    final match = RegExp(r'^(.+?[.!?])(?:\s|$)').firstMatch(trimmed);
    final sentence = match?.group(1) ?? trimmed;
    return sentence.trim().replaceFirst(RegExp(r'[.!?]+$'), '');
  }
}
