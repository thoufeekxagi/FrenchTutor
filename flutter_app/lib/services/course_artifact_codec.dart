import '../data/database/generated_grammar_story_store.dart';
import '../data/database/generated_writing_task_store.dart';
import '../models/grammar_course.dart';
import '../models/content_models.dart';
import '../models/speaking_course.dart';
import '../models/writing_course.dart';

/// Strict decoding boundary for server-prepared Course content.
///
/// A malformed artifact is never treated as ready and never falls back to
/// generation on the device. This keeps Course taps deterministic.
abstract final class CourseArtifactCodec {
  static List<SpeakingCourseLine> speaking(Map<String, dynamic> json) {
    final lines = _maps(json['lines'])
        .map(
          (line) => SpeakingCourseLine(
            french: _requiredString(line, 'fr'),
            english: _requiredString(line, 'en'),
            partnerFrench: line['partnerFr']?.toString(),
            partnerEnglish: line['partnerEn']?.toString(),
            tip: line['tip']?.toString() ?? '',
            hintWords: _strings(line['hintWords']),
            hintWordsEnglish: _strings(line['hintWordsEnglish']),
            openResponse: line['openResponse'] == true,
          ),
        )
        .toList(growable: false);
    if (lines.length < 3) {
      throw const FormatException(
        'Course speaking requires at least three prepared bilingual lines.',
      );
    }
    return lines;
  }

  static String practiceMode(Map<String, dynamic> json, String fallback) {
    final value = json['practiceMode']?.toString().trim() ?? '';
    return value.isEmpty ? fallback : value;
  }

  static WritingCourseLesson writingCourse(Map<String, dynamic> json) {
    final raw = _map(json['lesson']);
    final lesson = WritingCourseLesson.fromJson(raw);
    final validated = WritingCourseValidator.validate(lesson);
    if (practiceMode(json, validated.mode.name) != validated.mode.name) {
      throw const FormatException(
        'Course and Writing Practice modes do not match.',
      );
    }
    return validated;
  }

  static GrammarCourseSession grammarCourse(Map<String, dynamic> json) {
    final raw = _map(json['session']);
    final validated = GrammarCourseValidator.validate(
      GrammarCourseSession.fromJson(raw).copyWith(source: 'generated'),
    );
    if (practiceMode(json, validated.mode.name) != validated.mode.name) {
      throw const FormatException(
        'Course and Grammar Practice modes do not match.',
      );
    }
    return validated;
  }

  static GeneratedVocabularySet vocabulary(Map<String, dynamic> json) {
    final entries = _maps(
      json['entries'],
    ).map(VocabEntry.fromJson).toList(growable: false);
    final rawExamples = json['storyExamples'];
    final examples = rawExamples is Map
        ? {
            for (final entry in rawExamples.entries)
              entry.key.toString(): BilingualExample.fromJson(
                _map(entry.value),
              ),
          }
        : const <String, BilingualExample>{};
    if (entries.length != 5 ||
        entries.any((entry) => !examples.containsKey(entry.id))) {
      throw const FormatException(
        'Course vocabulary requires five words and five prepared examples.',
      );
    }
    return GeneratedVocabularySet(
      id: _requiredString(json, 'id'),
      title: _requiredString(json, 'title'),
      summary: json['summary']?.toString() ?? '',
      topic: _requiredString(json, 'topic'),
      levelBand: _requiredString(json, 'levelBand'),
      entries: entries,
      storyExamples: examples,
      createdAt: _date(json['createdAt']),
      coverUrl: json['coverUrl']?.toString(),
    );
  }

  static GeneratedStory story(Map<String, dynamic> json) {
    final passage = ReadingPassage.fromJson(_map(json['passage']));
    final quiz = _maps(
      json['quiz'],
    ).map(MultipleChoiceQuestion.fromJson).toList(growable: false);
    final keywords = _maps(
      json['keywords'],
    ).map(VocabEntry.fromJson).toList(growable: false);
    if (passage.segments.isEmpty || quiz.isEmpty) {
      throw const FormatException(
        'Course story requires a passage and prepared comprehension checks.',
      );
    }
    return GeneratedStory(
      id: _requiredString(json, 'id'),
      passage: passage,
      quiz: quiz,
      keywords: keywords,
      createdAt: _date(json['createdAt']),
      levelBand: _requiredString(json, 'levelBand'),
      summary: json['summary']?.toString() ?? '',
      topic: json['topic']?.toString() ?? '',
      readTimeMinutes: (json['readTimeMinutes'] as num?)?.toInt() ?? 5,
      coverUrl: json['coverUrl']?.toString(),
      musicBackgroundUrl: json['musicBackgroundUrl']?.toString(),
      audioPath: json['audioPath']?.toString(),
      audioMode: json['audioMode']?.toString(),
      practiceMode: json['practiceMode']?.toString() ?? 'reading',
    );
  }

  static GeneratedStory listening(Map<String, dynamic> json) {
    // The worker's artifact kind already identifies this as Listening. Stamp
    // the shared story object accordingly so the sentence deck can be reused
    // by both the Course activity and the Practice listening screen.
    final decoded = CourseArtifactCodec.story({
      ...json,
      'practiceMode': 'listening',
    });
    // Repair the short-lived marker written by the broken Unit 2 client. The
    // authored lesson has one shared Storage WAV; normalizing at the decode
    // boundary lets existing cloud rows recover without a data migration or
    // any provider call.
    final story =
        decoded.id == 'unit-two-listening' &&
            decoded.audioPath == 'pcm-deck-v1:unit-two-listening'
        ? decoded.copyWith(
            audioPath: 'course-shared/unit-two-listening.wav',
            audioMode: 'gemini_flash_tts',
          )
        : decoded;
    if (story.audioPath?.trim().isEmpty ?? true) {
      throw const FormatException(
        'Course listening requires a sentence-audio marker.',
      );
    }
    return story;
  }

  static GeneratedWritingTask writing(Map<String, dynamic> json) {
    return GeneratedWritingTask(
      task: WritingTask.fromJson(_map(json['task'])),
      createdAt: _date(json['createdAt']),
      coverUrl: json['coverUrl']?.toString(),
    );
  }

  static GeneratedGrammarStory grammar(Map<String, dynamic> json) {
    final passage = ReadingPassage.fromJson(_map(json['passage']));
    final quiz = _maps(
      json['quiz'],
    ).map(MultipleChoiceQuestion.fromJson).toList(growable: false);
    if (passage.segments.isEmpty || quiz.isEmpty) {
      throw const FormatException(
        'Course grammar requires a prepared explanation, story, and quiz.',
      );
    }
    return GeneratedGrammarStory(
      id: _requiredString(json, 'id'),
      grammarPoint: _requiredString(json, 'grammarPoint'),
      levelBand: _requiredString(json, 'levelBand'),
      explanation: GrammarExplanation.fromJson(_map(json['explanation'])),
      passage: passage,
      quiz: quiz,
      keywords: _maps(
        json['keywords'],
      ).map(VocabEntry.fromJson).toList(growable: false),
      createdAt: _date(json['createdAt']),
      coverUrl: json['coverUrl']?.toString(),
    );
  }

  static Map<String, dynamic> _map(Object? value) {
    if (value is! Map) throw const FormatException('Expected an object.');
    return value.cast<String, dynamic>();
  }

  static List<Map<String, dynamic>> _maps(Object? value) {
    if (value is! List) throw const FormatException('Expected a list.');
    return value.map(_map).toList(growable: false);
  }

  static List<String> _strings(Object? value) => value is List
      ? value
            .map((item) => item.toString().trim())
            .where((item) => item.isNotEmpty)
            .toList(growable: false)
      : const <String>[];

  static String _requiredString(Map<String, dynamic> json, String key) {
    final value = json[key]?.toString().trim() ?? '';
    if (value.isEmpty) throw FormatException('Missing $key.');
    return value;
  }

  static DateTime _date(Object? value) =>
      DateTime.tryParse(value?.toString() ?? '')?.toUtc() ??
      DateTime.now().toUtc();
}
