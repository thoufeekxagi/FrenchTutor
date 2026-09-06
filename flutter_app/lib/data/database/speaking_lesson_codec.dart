import 'package:flutter/material.dart';

import '../../models/content_models.dart';
import '../../models/speaking_course.dart';
import '../../services/story_variety_service.dart';
import '../../utils/speaking_translation_alignment.dart';

/// The wire format used by the shared Speaking catalog.
///
/// Icons are deliberately not persisted. They are presentation details, and
/// the app can choose a safe mode-specific icon when a row is restored on a
/// different build.
Map<String, dynamic> speakingCourseLessonToJson(SpeakingCourseLesson lesson) {
  return {
    'id': lesson.id,
    'title': lesson.title,
    'subtitle': lesson.subtitle,
    'level': lesson.level,
    'mode': lesson.mode.name,
    'goal': lesson.goal,
    'lines': lesson.lines.map(speakingCourseLineToJson).toList(),
  };
}

Map<String, dynamic> speakingCourseLineToJson(SpeakingCourseLine line) {
  final translationAlignment =
      line.translationAlignment ??
      SpeakingTranslationAlignment.forPhrase(line.french, line.english);
  final partnerTranslationAlignment =
      line.partnerFrench != null && line.partnerEnglish != null
      ? line.partnerTranslationAlignment ??
            SpeakingTranslationAlignment.forPhrase(
              line.partnerFrench!,
              line.partnerEnglish!,
            )
      : null;
  return {
    'french': line.french,
    'english': line.english,
    if (line.partnerFrench != null) 'partnerFrench': line.partnerFrench,
    if (line.partnerEnglish != null) 'partnerEnglish': line.partnerEnglish,
    'tip': line.tip,
    'hintWords': line.hintWords,
    'hintWordsEnglish': line.hintWordsEnglish,
    // Persist the alignment instead of relying on a runtime reconstruction.
    // This keeps bundled, generated, and restored lessons on the same exact
    // word-highlight contract.
    'translationAlignment': translationAlignment,
    if (partnerTranslationAlignment != null)
      'partnerTranslationAlignment': partnerTranslationAlignment,
    'openResponse': line.openResponse,
  };
}

SpeakingCourseLesson speakingCourseLessonFromJson(Map<String, dynamic> json) {
  final mode = SpeakingCourseMode.values.firstWhere(
    (value) => value.name == json['mode']?.toString(),
    orElse: () => throw FormatException('Unknown Speaking mode.'),
  );
  final rawLines = json['lines'];
  if (rawLines is! List || rawLines.isEmpty) {
    throw const FormatException('Speaking lesson has no lines.');
  }
  return SpeakingCourseLesson(
    id: _requiredText(json['id'], 'id'),
    title: _requiredText(json['title'], 'title'),
    subtitle: _requiredText(json['subtitle'], 'subtitle'),
    level: _requiredText(json['level'], 'level'),
    icon: speakingIconForText(
      '${json['title'] ?? ''} ${json['subtitle'] ?? ''}',
      fallback: speakingIconForMode(mode),
    ),
    mode: mode,
    goal: json['goal']?.toString() ?? '',
    lines: rawLines
        .whereType<Map>()
        .map((line) => speakingCourseLineFromJson(line.cast<String, dynamic>()))
        .toList(growable: false),
  );
}

SpeakingCourseLine speakingCourseLineFromJson(Map<String, dynamic> json) {
  final alignment = _alignment(json['translationAlignment']);
  final partnerAlignment = _alignment(json['partnerTranslationAlignment']);
  return SpeakingCourseLine(
    french: _requiredText(json['french'], 'french'),
    english: _requiredText(json['english'], 'english'),
    partnerFrench: _optionalText(json['partnerFrench']),
    partnerEnglish: _optionalText(json['partnerEnglish']),
    tip: json['tip']?.toString() ?? '',
    hintWords: _strings(json['hintWords']),
    hintWordsEnglish: _strings(json['hintWordsEnglish']),
    translationAlignment: alignment,
    partnerTranslationAlignment: partnerAlignment,
    openResponse: json['openResponse'] == true,
  );
}

IconData speakingIconForMode(SpeakingCourseMode mode) => switch (mode) {
  SpeakingCourseMode.guided => Icons.auto_awesome_rounded,
  SpeakingCourseMode.freeTalk => Icons.forum_outlined,
  SpeakingCourseMode.roleplay => Icons.theater_comedy_outlined,
};

IconData speakingIconForText(String rawText, {IconData? fallback}) {
  final text = rawText.toLowerCase();
  if (RegExp(r'café|cafe|coffee|restaurant|food|meal').hasMatch(text)) {
    return Icons.local_cafe_outlined;
  }
  if (RegExp(r'marché|market|shop|shopping|magasin').hasMatch(text)) {
    return Icons.shopping_basket_outlined;
  }
  if (RegExp(r'maison|home|house|logement|room').hasMatch(text)) {
    return Icons.home_outlined;
  }
  if (RegExp(r'train|bus|voyage|travel|town|ville|direction').hasMatch(text)) {
    return Icons.map_outlined;
  }
  if (RegExp(
    r'matin|morning|routine|jour|day|week-end|weekend',
  ).hasMatch(text)) {
    return Icons.wb_sunny_outlined;
  }
  if (RegExp(r'travail|work|school|école|job').hasMatch(text)) {
    return Icons.work_outline_rounded;
  }
  if (RegExp(
    r'ami|friend|family|famille|name|nom|greet|bonjour',
  ).hasMatch(text)) {
    return Icons.people_outline_rounded;
  }
  return fallback ?? Icons.auto_awesome_rounded;
}

String speakingModeWireName(SpeakingCourseMode mode) => mode.name;

String speakingLessonFingerprint(SpeakingCourseLesson lesson) {
  final opening = lesson.lines
      .take(2)
      .map(
        (line) => '${line.partnerFrench ?? ''}|${line.french}|${line.english}',
      )
      .join('||');
  return StoryVarietyService.storyFingerprint(
    title: '${lesson.mode.name}:${lesson.level}:${lesson.title}',
    opening: opening,
  );
}

/// Converts a generator response into a lesson only after the complete
/// bilingual contract has passed deterministic validation. Invalid content is
/// rejected before it can be cached locally or published to Supabase.
abstract final class SpeakingCourseLessonValidator {
  static SpeakingCourseLesson fromPassage({
    required ReadingPassage passage,
    required String id,
    required String level,
    required SpeakingCourseMode mode,
  }) {
    final title = passage.title.trim();
    if (title.isEmpty || passage.segments.isEmpty) {
      throw StateError('Generated Speaking lesson is empty.');
    }

    final segments = passage.segments;
    final minimum = mode == SpeakingCourseMode.guided
        ? 3
        : mode == SpeakingCourseMode.freeTalk
        ? 3
        : 4;
    final maximum = mode == SpeakingCourseMode.guided
        ? 5
        : mode == SpeakingCourseMode.freeTalk
        ? 4
        : 6;
    if (segments.length < minimum || segments.length > maximum) {
      throw StateError(
        'Generated ${mode.name} lesson must contain $minimum-$maximum lines.',
      );
    }

    final lines = <SpeakingCourseLine>[];
    for (final segment in segments) {
      final french = segment.fr.trim();
      final english = segment.en.trim();
      if (french.isEmpty || english.isEmpty) {
        throw StateError(
          'Generated ${mode.name} line is missing French or English.',
        );
      }
      // Generated lessons may contain natural paraphrases with no exact
      // one-to-one word mapping. Preserve the playable line and any matches;
      // the authored catalog remains validated with strict alignment.
      final alignment = SpeakingTranslationAlignment.forGeneratedPhrase(
        french,
        english,
      );

      final partnerFrench = segment.characterFr?.trim();
      final partnerEnglish = segment.characterEn?.trim();
      List<List<int>>? partnerAlignment;
      if (mode != SpeakingCourseMode.guided) {
        if (partnerFrench == null ||
            partnerFrench.isEmpty ||
            partnerEnglish == null ||
            partnerEnglish.isEmpty) {
          throw StateError(
            'Generated ${mode.name} line is missing the tutor prompt.',
          );
        }
        partnerAlignment = SpeakingTranslationAlignment.forGeneratedPhrase(
          partnerFrench,
          partnerEnglish,
        );
      }

      final hintWords = segment.hintWords
          .map((word) => word.trim())
          .where((word) => word.isNotEmpty)
          .toList(growable: false);
      final hintWordsEnglish = segment.hintWordsEnglish
          .map((word) => word.trim())
          .where((word) => word.isNotEmpty)
          .toList(growable: false);
      if (mode == SpeakingCourseMode.freeTalk) {
        if (hintWords.length < 3 || hintWords.length > 6) {
          throw StateError(
            'Generated Free Talk line must contain 3-6 hint words.',
          );
        }
        if (hintWords.length != hintWordsEnglish.length) {
          throw StateError(
            'Generated Free Talk hints must have one English meaning each.',
          );
        }
        if (hintWords.any((word) => word.contains(RegExp(r'\s')))) {
          throw StateError(
            'Generated Free Talk hints must be individual words.',
          );
        }
      }

      lines.add(
        SpeakingCourseLine(
          french: french,
          english: english,
          partnerFrench: partnerFrench,
          partnerEnglish: partnerEnglish,
          tip: segment.pronunciationTip.trim(),
          hintWords: hintWords,
          hintWordsEnglish: hintWordsEnglish,
          translationAlignment: alignment,
          partnerTranslationAlignment: partnerAlignment,
          openResponse: mode == SpeakingCourseMode.freeTalk,
        ),
      );
    }

    final lesson = SpeakingCourseLesson(
      id: id,
      title: (passage.titleEn?.trim().isNotEmpty == true
          ? passage.titleEn!.trim()
          : title),
      subtitle: 'A fresh $level conversation matched to your practice.',
      level: level,
      icon: speakingIconForText(
        '${passage.title} ${passage.titleEn ?? ''}',
        fallback: speakingIconForMode(mode),
      ),
      mode: mode,
      lines: lines,
    );
    // Check the final wire object too, so a codec change cannot publish a
    // lesson that is valid only before serialization.
    speakingCourseLessonFromJson(speakingCourseLessonToJson(lesson));
    return lesson;
  }
}

String _requiredText(Object? value, String field) {
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty) throw FormatException('Missing Speaking field: $field.');
  return text;
}

String? _optionalText(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

List<String> _strings(Object? value) => value is List
    ? value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false)
    : const [];

List<List<int>>? _alignment(Object? value) {
  if (value is! List) return null;
  return value
      .map(
        (entry) => entry is List
            ? entry.whereType<num>().map((item) => item.toInt()).toList()
            : <int>[],
      )
      .toList(growable: false);
}
