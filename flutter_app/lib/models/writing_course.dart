import 'package:flutter/material.dart';

part 'writing_course_seed.dart';

enum WritingCourseMode { guided, complete, roleplay }

enum WritingInputKind { arrange, choice, text }

class WritingCourseStep {
  const WritingCourseStep({
    required this.prompt,
    required this.promptEnglish,
    required this.target,
    this.kind = WritingInputKind.arrange,
    this.tokens = const [],
    this.tokenMeanings = const [],
    this.choices = const [],
    this.choiceMeanings = const [],
    this.partnerFrench,
    this.partnerEnglish,
    this.goal,
    this.starter,
    this.suggestions = const [],
    this.suggestionMeanings = const [],
    this.tip = '',
  });

  final String prompt;
  final String promptEnglish;
  final String target;
  final WritingInputKind kind;
  final List<String> tokens;
  final List<String> tokenMeanings;
  final List<String> choices;
  final List<String> choiceMeanings;
  final String? partnerFrench;
  final String? partnerEnglish;
  final String? goal;
  final String? starter;
  final List<String> suggestions;
  final List<String> suggestionMeanings;
  final String tip;

  Map<String, dynamic> toJson() => {
    'prompt': prompt,
    'prompt_english': promptEnglish,
    'target': target,
    'kind': kind.name,
    'tokens': tokens,
    'token_meanings': tokenMeanings,
    'choices': choices,
    'choice_meanings': choiceMeanings,
    if (partnerFrench != null) 'partner_french': partnerFrench,
    if (partnerEnglish != null) 'partner_english': partnerEnglish,
    if (goal != null) 'goal': goal,
    if (starter != null) 'starter': starter,
    'suggestions': suggestions,
    'suggestion_meanings': suggestionMeanings,
    'tip': tip,
  };

  factory WritingCourseStep.fromJson(Map<String, dynamic> json) {
    final rawKind = json['kind']?.toString();
    final kind = WritingInputKind.values.firstWhere(
      (value) => value.name == rawKind,
      orElse: () => WritingInputKind.arrange,
    );
    final rawTokens = (json['tokens'] as List? ?? const [])
        .map((value) => value.toString())
        .toList(growable: false);
    final rawTokenMeanings = (json['token_meanings'] as List? ?? const [])
        .map((value) => value.toString())
        .toList(growable: false);
    final guidedBank = kind == WritingInputKind.arrange
        ? _cleanGuidedBank(rawTokens, rawTokenMeanings)
        : (tokens: rawTokens, meanings: rawTokenMeanings);
    final rawTarget = json['target']?.toString() ?? '';
    return WritingCourseStep(
      prompt: json['prompt']?.toString() ?? '',
      promptEnglish: json['prompt_english']?.toString() ?? '',
      target: kind == WritingInputKind.arrange
          ? _stripGuidedSentencePunctuation(rawTarget)
          : rawTarget,
      kind: kind,
      tokens: guidedBank.tokens,
      tokenMeanings: guidedBank.meanings,
      choices: (json['choices'] as List? ?? const [])
          .map((value) => value.toString())
          .toList(growable: false),
      choiceMeanings: (json['choice_meanings'] as List? ?? const [])
          .map((value) => value.toString())
          .toList(growable: false),
      partnerFrench: json['partner_french']?.toString(),
      partnerEnglish: json['partner_english']?.toString(),
      goal: json['goal']?.toString(),
      starter: json['starter']?.toString(),
      suggestions: (json['suggestions'] as List? ?? const [])
          .map((value) => value.toString())
          .toList(growable: false),
      suggestionMeanings: (json['suggestion_meanings'] as List? ?? const [])
          .map((value) => value.toString())
          .toList(growable: false),
      tip: json['tip']?.toString() ?? '',
    );
  }

  /// Punctuation belongs to the sentence, not to a selectable word-bank
  /// chip. Older/generated artifacts sometimes returned a comma, period, or
  /// question mark as its own token (or attached to a word). Clean that at
  /// the decoding boundary so legacy rows remain usable and the UI never asks
  /// a learner to select punctuation as if it were vocabulary.
  static ({List<String> tokens, List<String> meanings}) _cleanGuidedBank(
    List<String> rawTokens,
    List<String> rawMeanings,
  ) {
    final tokens = <String>[];
    final meanings = <String>[];
    for (var index = 0; index < rawTokens.length; index++) {
      final token = rawTokens[index]
          .replaceFirst(RegExp(r'^[.,!?;:«»"“”]+'), '')
          .replaceFirst(RegExp(r'[.,!?;:«»"“”]+$'), '')
          .trim();
      if (token.isEmpty) continue;
      tokens.add(token);
      meanings.add(index < rawMeanings.length ? rawMeanings[index] : '');
    }
    return (tokens: tokens, meanings: meanings);
  }

  static String _stripGuidedSentencePunctuation(String value) => value
      .replaceAll(RegExp(r'[.,!?;:«»"“”]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

class WritingCourseLesson {
  const WritingCourseLesson({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.level,
    required this.icon,
    required this.mode,
    required this.steps,
    this.goal = '',
    this.titleEnglish,
  });

  final String id;
  final String title;
  final String subtitle;
  final String level;
  final IconData icon;
  final WritingCourseMode mode;
  final List<WritingCourseStep> steps;
  final String goal;

  /// English learner-facing title returned by the generator. Older bundled
  /// lessons do not have one, so the French title remains a safe fallback.
  final String? titleEnglish;

  String get displayTitle {
    final english =
        titleEnglish?.trim() ?? writingCourseEnglishTitleForText(title) ?? '';
    final band = level.trim().toUpperCase();
    if (english.isEmpty || english == title.trim()) {
      if ((band == 'A1' || band == 'A2') && _looksFrenchOnly(title)) {
        return 'Writing practice';
      }
      return title;
    }
    return band == 'A1' || band == 'A2' ? english : '$title ($english)';
  }

  String get displaySubtitle {
    final value = subtitle.trim();
    if (value.isEmpty) return 'Practice useful French for this situation.';
    final band = level.trim().toUpperCase();
    if ((band == 'A1' || band == 'A2') &&
        _looksFrenchOnly(value) &&
        !RegExp(
          r'\b(the|a|an|about|build|write|say|practice|talk|learn|use|your|with|for)\b',
          caseSensitive: false,
        ).hasMatch(value)) {
      return 'Practice useful French for this situation.';
    }
    return value;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'subtitle': subtitle,
    'level': level,
    'icon_name': mode.name,
    'mode': mode.name,
    'steps': steps.map((step) => step.toJson()).toList(growable: false),
    'goal': goal,
    if (titleEnglish != null && titleEnglish!.trim().isNotEmpty)
      'title_en': titleEnglish,
  };

  factory WritingCourseLesson.fromJson(Map<String, dynamic> json) {
    final rawMode = json['mode']?.toString();
    final mode = WritingCourseMode.values.firstWhere(
      (value) => value.name == rawMode,
      orElse: () => WritingCourseMode.guided,
    );
    return WritingCourseLesson(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      subtitle: json['subtitle']?.toString() ?? '',
      level: json['level']?.toString() ?? 'A1',
      icon: writingCourseIconForText(
        '${json['title'] ?? ''} ${json['subtitle'] ?? ''} ${json['goal'] ?? ''}',
      ),
      mode: mode,
      steps: (json['steps'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (step) => WritingCourseStep.fromJson(step.cast<String, dynamic>()),
          )
          .toList(growable: false),
      goal: json['goal']?.toString() ?? '',
      titleEnglish:
          json['title_en']?.toString() ?? json['titleEnglish']?.toString(),
    );
  }
}

abstract final class WritingCourseValidator {
  static WritingCourseLesson validate(WritingCourseLesson lesson) {
    if (lesson.id.trim().isEmpty ||
        lesson.title.trim().isEmpty ||
        lesson.subtitle.trim().isEmpty ||
        lesson.steps.isEmpty) {
      throw const FormatException('Writing lesson metadata is incomplete.');
    }
    final expectedCount = lesson.mode == WritingCourseMode.roleplay ? 4 : 5;
    if (lesson.steps.length != expectedCount) {
      throw FormatException(
        '${lesson.mode.name} lessons require exactly $expectedCount steps.',
      );
    }
    for (final step in lesson.steps) {
      final expectedKind = switch (lesson.mode) {
        WritingCourseMode.guided => WritingInputKind.arrange,
        WritingCourseMode.complete => WritingInputKind.choice,
        WritingCourseMode.roleplay => WritingInputKind.text,
      };
      if (step.kind != expectedKind) {
        throw FormatException(
          '${lesson.mode.name} lessons require ${expectedKind.name} steps.',
        );
      }
      if (step.prompt.trim().isEmpty ||
          step.promptEnglish.trim().isEmpty ||
          step.target.trim().isEmpty) {
        throw const FormatException('A writing step is incomplete.');
      }
      if (step.kind == WritingInputKind.arrange && step.tokens.length < 2) {
        throw const FormatException('Arrange steps require a word bank.');
      }
      if (step.kind == WritingInputKind.arrange &&
          _normalise(step.tokens.join(' ')) != _normalise(step.target)) {
        throw const FormatException(
          'Arrange word banks must reconstruct the target exactly.',
        );
      }
      if (step.kind == WritingInputKind.arrange &&
          (step.tokenMeanings.length != step.tokens.length ||
              step.tokens.asMap().entries.any(
                (entry) =>
                    entry.value
                        .replaceAll(RegExp(r"[.,!?;:«»’']"), '')
                        .trim()
                        .isNotEmpty &&
                    step.tokenMeanings[entry.key].trim().isEmpty,
              ))) {
        throw const FormatException(
          'Arrange steps require one English meaning per word.',
        );
      }
      if (step.kind == WritingInputKind.choice &&
          (step.choices.length != 3 ||
              !step.choices.contains(step.target) ||
              !step.prompt.contains('___'))) {
        throw const FormatException(
          'Choice steps require one blank and exactly three options.',
        );
      }
      if (step.kind == WritingInputKind.choice &&
          (step.choiceMeanings.length != step.choices.length ||
              step.choiceMeanings.any((meaning) => meaning.trim().isEmpty))) {
        throw const FormatException(
          'Choice steps require one English meaning per option.',
        );
      }
      if (step.kind == WritingInputKind.choice &&
          (step.partnerFrench ?? '').trim().isNotEmpty &&
          (step.partnerEnglish ?? '').trim().isEmpty) {
        throw const FormatException(
          'Choice partner lines require an English translation.',
        );
      }
      if (lesson.mode == WritingCourseMode.roleplay &&
          ((step.partnerFrench ?? '').trim().isEmpty ||
              (step.partnerEnglish ?? '').trim().isEmpty ||
              (step.goal ?? '').trim().isEmpty)) {
        throw const FormatException(
          'Roleplay beats require a translated partner and goal.',
        );
      }
      if (lesson.mode == WritingCourseMode.roleplay &&
          (step.suggestionMeanings.length != step.suggestions.length ||
              step.suggestionMeanings.any(
                (meaning) => meaning.trim().isEmpty,
              ))) {
        throw const FormatException(
          'Roleplay suggestions require one English meaning per phrase.',
        );
      }
    }
    return lesson;
  }

  static String _normalise(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[’‘]'), "'")
      .replaceAll(RegExp(r'[.,!?;:«»"“”]'), '')
      .replaceAll(RegExp(r'\s+'), ' ');
}

String writingLessonFingerprint(WritingCourseLesson lesson) {
  String normalise(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9à-ÿ]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ');

  return [
    lesson.mode.name,
    lesson.level.toUpperCase(),
    normalise(lesson.title),
    for (final step in lesson.steps) normalise(step.target),
  ].join('|');
}

/// Topic-aware presentation icon for generated writing lessons. The mode
/// still controls the activity, but the icon now tells the learner what the
/// lesson is about instead of making every generated row look identical.
IconData writingCourseIconForText(String rawText) {
  final text = rawText.toLowerCase();
  if (RegExp(r'café|cafe|coffee|restaurant|repas|food|meal').hasMatch(text)) {
    return Icons.local_cafe_outlined;
  }
  if (RegExp(r'marché|market|shop|shopping|magasin|courses').hasMatch(text)) {
    return Icons.shopping_basket_outlined;
  }
  if (RegExp(r'maison|home|house|logement|appartement|room').hasMatch(text)) {
    return Icons.home_outlined;
  }
  if (RegExp(r'train|bus|voyage|travel|town|ville|direction').hasMatch(text)) {
    return Icons.map_outlined;
  }
  if (RegExp(
    r'matin|morning|routine|jour|day|week-end|weekend|weather|météo',
  ).hasMatch(text)) {
    return Icons.wb_sunny_outlined;
  }
  if (RegExp(r'travail|work|school|école|job|bureau').hasMatch(text)) {
    return Icons.work_outline_rounded;
  }
  if (RegExp(r'famille|family|ami|friend|person|people').hasMatch(text)) {
    return Icons.groups_outlined;
  }
  if (RegExp(r'message|email|mail|écrire|write|lettre').hasMatch(text)) {
    return Icons.mail_outline_rounded;
  }
  if (RegExp(
    r'tomorrow|demain|plan|appointment|rendez-vous|calendar',
  ).hasMatch(text)) {
    return Icons.calendar_month_outlined;
  }
  return Icons.auto_awesome_rounded;
}

bool _looksFrenchOnly(String value) => RegExp(
  r'(^|\s)(le|la|les|un|une|des|mon|ma|mes|au|aux|du|de|dans|pour|avec|parler|décrire|écrire)\b|[àâçéèêëîïôùûüÿœ]',
  caseSensitive: false,
).hasMatch(value.trim());

String? writingCourseEnglishTitleForText(String rawTitle) {
  final title = rawTitle.toLowerCase();
  if (title.contains('week-end') || title.contains('weekend')) {
    return 'Weekend plans';
  }
  if (title.contains('logement') || title.contains('maison')) {
    return 'Describe my home';
  }
  if (title.contains('magasin') || title.contains('marché')) {
    return 'At the store';
  }
  if (title.contains('routine') || title.contains('matin')) {
    return 'My daily routine';
  }
  if (title.contains('café') || title.contains('cafe')) {
    return 'At the café';
  }
  return null;
}
