import '../models/content_models.dart';
import '../widgets/word_meaning_overlay.dart';
import 'lesson_agent_service.dart';

/// Result of resolving one tapped word's contextual meaning.
class WordMeaningResult {
  const WordMeaningResult({
    required this.entry,
    required this.canConjugate,
    required this.examples,
  });

  final VocabEntry entry;
  final bool canConjugate;
  final List<WordMeaningExample> examples;
}

/// Shared "what does this tapped word mean" lookup used identically by
/// Reading/Course (story_reader_screen.dart) and Listening
/// (listening_practice_screen.dart), so a tapped word means the same thing,
/// looks the same, and is billed the same (once, ever, across every
/// learner — see LessonAgentService.buildWordMeaning's shared cache) in
/// both places.
class WordMeaningResolver {
  WordMeaningResolver._();

  static Future<WordMeaningResult> resolve({
    required String word,
    required String sentence,
    required String sentenceTranslation,
    required String levelBand,
  }) async {
    final data = await LessonAgentService.shared.buildWordMeaning(
      word: word,
      sentence: sentence,
      sentenceTranslation: sentenceTranslation,
      levelBand: levelBand,
    );
    final translation = data['translation']?.toString().trim() ?? '';
    final rawWord = data['word']?.toString().trim() ?? '';
    final partOfSpeech = data['part_of_speech']?.toString().toLowerCase() ?? '';
    final examples = <WordMeaningExample>[];
    final examplesRaw = data['examples'];
    if (examplesRaw is List) {
      for (final rawExample in examplesRaw) {
        if (rawExample is Map) {
          final fr = rawExample['fr']?.toString().trim() ?? '';
          final en = rawExample['en']?.toString().trim() ?? '';
          if (fr.isNotEmpty) examples.add((fr: fr, en: en));
        }
      }
    }
    return WordMeaningResult(
      entry: VocabEntry(
        id: 'word-meaning:${word.trim().toLowerCase()}',
        fr: rawWord.isNotEmpty ? rawWord : word,
        en: translation,
        phonetic: '',
      ),
      canConjugate:
          data['can_conjugate'] == true || partOfSpeech.contains('verb'),
      examples: examples,
    );
  }
}
