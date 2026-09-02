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
    return WritingCourseStep(
      prompt: json['prompt']?.toString() ?? '',
      promptEnglish: json['prompt_english']?.toString() ?? '',
      target: json['target']?.toString() ?? '',
      kind: WritingInputKind.values.firstWhere(
        (value) => value.name == rawKind,
        orElse: () => WritingInputKind.arrange,
      ),
      tokens: (json['tokens'] as List? ?? const [])
          .map((value) => value.toString())
          .toList(growable: false),
      tokenMeanings: (json['token_meanings'] as List? ?? const [])
          .map((value) => value.toString())
          .toList(growable: false),
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
  });

  final String id;
  final String title;
  final String subtitle;
  final String level;
  final IconData icon;
  final WritingCourseMode mode;
  final List<WritingCourseStep> steps;
  final String goal;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'subtitle': subtitle,
    'level': level,
    'icon_name': mode.name,
    'mode': mode.name,
    'steps': steps.map((step) => step.toJson()).toList(growable: false),
    'goal': goal,
  };

  factory WritingCourseLesson.fromJson(Map<String, dynamic> json) {
    final rawMode = json['mode']?.toString();
    final mode = WritingCourseMode.values.firstWhere(
      (value) => value.name == rawMode,
      orElse: () => WritingCourseMode.guided,
    );
    final icon = switch (mode) {
      WritingCourseMode.guided => Icons.edit_note_rounded,
      WritingCourseMode.complete => Icons.checklist_rounded,
      WritingCourseMode.roleplay => Icons.forum_outlined,
    };
    return WritingCourseLesson(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      subtitle: json['subtitle']?.toString() ?? '',
      level: json['level']?.toString() ?? 'A1',
      icon: icon,
      mode: mode,
      steps: (json['steps'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (step) => WritingCourseStep.fromJson(step.cast<String, dynamic>()),
          )
          .toList(growable: false),
      goal: json['goal']?.toString() ?? '',
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

  static String _normalise(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
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
