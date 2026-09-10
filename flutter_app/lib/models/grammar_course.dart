import 'package:flutter/material.dart';

import 'grammar_course_v2.dart';

/// One beat inside a Grammar session. A beat is never shown as a library card
/// on its own; it only makes sense as part of its parent session.
class GrammarCourseStep {
  const GrammarCourseStep({
    required this.label,
    required this.prompt,
    required this.promptEnglish,
    required this.target,
    required this.answer,
    required this.choices,
    this.choiceMeanings = const [],
    required this.tokens,
    required this.tip,
    this.partnerFrench,
    this.partnerEnglish,
  });

  final String label;
  final String prompt;
  final String promptEnglish;
  final String target;
  final String answer;
  final List<String> choices;

  /// English glosses shown under Guided/Roleplay choices when translation is on.
  /// Older saved sessions may omit this field; the French choice remains valid.
  final List<String> choiceMeanings;
  final List<String> tokens;
  final String tip;
  final String? partnerFrench;
  final String? partnerEnglish;

  Map<String, dynamic> toJson() => {
    'label': label,
    'prompt': prompt,
    'prompt_english': promptEnglish,
    'target': target,
    'answer': answer,
    'choices': choices,
    if (choiceMeanings.isNotEmpty) 'choice_meanings': choiceMeanings,
    'tokens': tokens,
    'tip': tip,
    if (partnerFrench != null) 'partner_french': partnerFrench,
    if (partnerEnglish != null) 'partner_english': partnerEnglish,
  };

  factory GrammarCourseStep.fromJson(Map<String, dynamic> json) {
    List<String> values(String key) => (json[key] as List? ?? const [])
        .map((value) => value.toString())
        .where((value) => value.trim().isNotEmpty)
        .toList(growable: false);

    return GrammarCourseStep(
      label: json['label']?.toString() ?? '',
      prompt: json['prompt']?.toString() ?? '',
      promptEnglish: json['prompt_english']?.toString() ?? '',
      target: json['target']?.toString() ?? '',
      answer: json['answer']?.toString() ?? '',
      choices: values('choices'),
      choiceMeanings: values('choice_meanings').isNotEmpty
          ? values('choice_meanings')
          : values('choices_en'),
      tokens: values('tokens'),
      tip: json['tip']?.toString() ?? '',
      partnerFrench: json['partner_french']?.toString(),
      partnerEnglish: json['partner_english']?.toString(),
    );
  }
}

/// The Grammar equivalent of [SpeakingCourseLesson]. The session owns one
/// coherent objective and its complete 4–5 beat progression.
class GrammarCourseSession {
  const GrammarCourseSession({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.level,
    required this.tense,
    required this.grammarFocus,
    required this.iconKey,
    required this.mode,
    required this.steps,
    this.goal = '',
    this.source = 'default',
  });

  final String id;
  final String title;
  final String subtitle;
  final String level;
  final String tense;
  final String grammarFocus;
  final String iconKey;
  final GrammarV2Mode mode;
  final List<GrammarCourseStep> steps;
  final String goal;
  final String source;

  IconData get icon => grammarCourseIconForKey(
    source == 'generated'
        ? (grammarCourseIconKeyForText('$title $subtitle $grammarFocus') ??
              iconKey)
        : iconKey,
  );
  int get stepCount => steps.length;
  String get progressId => 'grammar_course_$id';

  GrammarCourseSession copyWith({String? source}) => GrammarCourseSession(
    id: id,
    title: title,
    subtitle: subtitle,
    level: level,
    tense: tense,
    grammarFocus: grammarFocus,
    iconKey: iconKey,
    mode: mode,
    steps: steps,
    goal: goal,
    source: source ?? this.source,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'subtitle': subtitle,
    'level': level,
    'tense': tense,
    'grammar_focus': grammarFocus,
    'icon_key': iconKey,
    'mode': mode.name,
    'steps': steps.map((step) => step.toJson()).toList(growable: false),
    'goal': goal,
    'source': source,
  };

  factory GrammarCourseSession.fromJson(Map<String, dynamic> json) {
    final rawMode = json['mode']?.toString();
    final mode = GrammarV2Mode.values.firstWhere(
      (value) => value.name == rawMode,
      orElse: () => GrammarV2Mode.guided,
    );
    final steps = (json['steps'] as List? ?? const [])
        .whereType<Map>()
        .map((step) => GrammarCourseStep.fromJson(step.cast<String, dynamic>()))
        .toList(growable: false);
    return GrammarCourseSession(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      subtitle: json['subtitle']?.toString() ?? '',
      level: json['level']?.toString() ?? 'A1',
      tense: json['tense']?.toString() ?? GrammarV2Tenses.present,
      grammarFocus: json['grammar_focus']?.toString() ?? '',
      iconKey: json['icon_key']?.toString() ?? 'sparkles',
      mode: mode,
      steps: steps,
      goal: json['goal']?.toString() ?? '',
      source: json['source']?.toString() ?? 'generated',
    );
  }
}

abstract final class GrammarCourseValidator {
  static GrammarCourseSession validate(GrammarCourseSession session) {
    if (session.id.trim().isEmpty ||
        session.title.trim().isEmpty ||
        session.subtitle.trim().isEmpty ||
        session.level.trim().isEmpty ||
        session.tense.trim().isEmpty ||
        session.grammarFocus.trim().isEmpty ||
        session.steps.isEmpty) {
      throw const FormatException('Grammar session metadata is incomplete.');
    }
    final expectedCount = session.mode == GrammarV2Mode.roleplay ? 4 : 5;
    if (session.steps.length != expectedCount) {
      throw FormatException(
        '${session.mode.name} sessions require exactly $expectedCount steps.',
      );
    }
    final labels = <String>{};
    for (final step in session.steps) {
      if (step.label.trim().isEmpty ||
          step.prompt.trim().isEmpty ||
          step.promptEnglish.trim().isEmpty ||
          step.target.trim().isEmpty ||
          step.answer.trim().isEmpty ||
          step.tip.trim().isEmpty ||
          !labels.add(step.label.trim().toLowerCase())) {
        throw const FormatException('A Grammar session step is incomplete.');
      }
      final foldedChoices = step.choices.map(_normaliseChoice).toSet();
      final answerMatches = step.choices
          .map(_normaliseChoice)
          .contains(_normaliseChoice(step.answer));
      if (session.mode == GrammarV2Mode.guided &&
          (step.choices.length != 3 ||
              foldedChoices.length != 3 ||
              !step.prompt.contains('___') ||
              !answerMatches ||
              (step.choiceMeanings.isNotEmpty &&
                  (step.choiceMeanings.length != step.choices.length ||
                      step.choiceMeanings.any(
                        (meaning) => meaning.trim().isEmpty,
                      ))))) {
        throw const FormatException(
          'Guided Grammar steps need one blank and three unique choices.',
        );
      }
      if (session.mode == GrammarV2Mode.complete &&
          (step.tokens.length < 2 ||
              _normalise(step.tokens.join(' ')) != _normalise(step.target))) {
        throw const FormatException(
          'Complete Grammar steps need a word bank that rebuilds the target.',
        );
      }
      if (session.mode == GrammarV2Mode.roleplay &&
          ((step.partnerFrench ?? '').trim().isEmpty ||
              (step.partnerEnglish ?? '').trim().isEmpty ||
              step.choices.length != 3 ||
              foldedChoices.length != 3 ||
              !answerMatches ||
              (step.choiceMeanings.isNotEmpty &&
                  (step.choiceMeanings.length != step.choices.length ||
                      step.choiceMeanings.any(
                        (meaning) => meaning.trim().isEmpty,
                      ))))) {
        throw const FormatException(
          'Roleplay Grammar steps need a translated partner and three replies.',
        );
      }
    }
    return session;
  }

  static String _normalise(String value) => value
      .toLowerCase()
      .replaceAllMapped(RegExp(r'\s+([,.!?;:])'), (match) => match.group(1)!)
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static String _normaliseChoice(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
}

IconData grammarCourseIconForKey(String key) => switch (key) {
  'sun' => Icons.wb_sunny_outlined,
  'coffee' => Icons.local_cafe_outlined,
  'map' => Icons.map_outlined,
  'calendar' => Icons.calendar_month_outlined,
  'market' => Icons.shopping_basket_outlined,
  'train' => Icons.train_outlined,
  'chat' => Icons.chat_bubble_outline_rounded,
  'home' => Icons.home_outlined,
  'health' => Icons.local_pharmacy_outlined,
  // Grammar is a pattern/checking skill. Keep the icon semantic and
  // consistent across Course, Practice, and generated sessions.
  'sparkles' => Icons.spellcheck_rounded,
  _ => Icons.spellcheck_rounded,
};

String? grammarCourseIconKeyForText(String rawText) {
  final text = rawText.toLowerCase();
  if (RegExp(r'café|cafe|coffee|restaurant|repas|food|meal').hasMatch(text)) {
    return 'coffee';
  }
  if (RegExp(r'marché|market|shop|shopping|magasin|courses').hasMatch(text)) {
    return 'market';
  }
  if (RegExp(r'maison|home|house|logement|appartement|room').hasMatch(text)) {
    return 'home';
  }
  if (RegExp(r'train|bus|voyage|travel|town|ville|direction').hasMatch(text)) {
    return 'map';
  }
  if (RegExp(
    r'matin|morning|routine|jour|day|week-end|weekend|calendar',
  ).hasMatch(text)) {
    return 'sun';
  }
  if (RegExp(r'travail|work|school|école|job|bureau').hasMatch(text)) {
    return 'calendar';
  }
  if (RegExp(r'chat|conversation|parler|talk|reply|message').hasMatch(text)) {
    return 'chat';
  }
  if (RegExp(r'santé|health|pharmacy|pharmacie').hasMatch(text)) {
    return 'health';
  }
  return null;
}

String grammarCourseFingerprint(GrammarCourseSession session) {
  final opening = session.steps
      .take(2)
      .map(
        (step) => '${step.partnerFrench ?? ''}|${step.target}|${step.answer}',
      )
      .join('||');
  return '${session.mode.name}|${session.tense}|${session.level}|'
      '${session.title.trim().toLowerCase()}|${opening.trim().toLowerCase()}';
}
