import '../data/grammar_curriculum_catalog.dart';

/// Grammar V2 keeps the learner-facing practice modes parallel with Writing.
/// The underlying curriculum lesson remains frozen and deterministic; the
/// mode only changes the interaction used to practise that lesson.
enum GrammarV2Mode { guided, complete, roleplay }

extension GrammarV2ModeCopy on GrammarV2Mode {
  String get label => switch (this) {
    GrammarV2Mode.guided => 'Guided',
    GrammarV2Mode.complete => 'Complete',
    GrammarV2Mode.roleplay => 'Roleplay',
  };

  String get subtitle => switch (this) {
    GrammarV2Mode.guided => 'Fix one form',
    GrammarV2Mode.complete => 'Build the pattern',
    GrammarV2Mode.roleplay => 'Choose it in context',
  };

  String get description => switch (this) {
    GrammarV2Mode.guided => 'Choose the form that makes the sentence correct.',
    GrammarV2Mode.complete => 'Put a real French sentence in order.',
    GrammarV2Mode.roleplay => 'Select a prepared reply that fits the scene.',
  };
}

/// A small, stable filter vocabulary used by the Grammar home and generator.
abstract final class GrammarV2Tenses {
  static const all = 'All';
  static const present = 'Present';
  static const past = 'Past';
  static const future = 'Future';
  static const mixed = 'Mixed';

  static const values = [all, present, past, future, mixed];

  static bool matches(GrammarCurriculumLesson lesson, String filter) {
    if (filter == all || filter == mixed) return true;
    final point = lesson.generationPoint.toLowerCase();
    return switch (filter) {
      present =>
        point.contains('présent') &&
            !point.contains('conditionnel') &&
            !point.contains('subjonctif'),
      past => point.contains('passé') || point.contains('imparfait'),
      future => point.contains('futur'),
      _ => true,
    };
  }

  static String labelFor(GrammarCurriculumLesson lesson) {
    final point = lesson.generationPoint.toLowerCase();
    if (point.contains('passé') || point.contains('imparfait')) {
      return past;
    }
    if (point.contains('futur')) return future;
    if (point.contains('conditionnel') || point.contains('subjonctif')) {
      return mixed;
    }
    return present;
  }
}

/// Small A1-friendly reserve for tense filters that had fewer than five cards
/// in the older curriculum bank. These are frozen like the main catalog and
/// keep Past/Future useful on the first open without an online generation wait.
const grammarV2FallbackLessons = <GrammarCurriculumLesson>[
  GrammarCurriculumLesson(
    id: 'grammar_v2_a1_past_manger',
    level: 'A1',
    collection: 'Past tense',
    title: 'Talk about yesterday',
    subtitle: 'Use passé composé with avoir',
    tip: 'Use ai plus the past participle for a completed action with je.',
    pickPrompt: "J'___ une pomme.",
    pickChoices: ['ai mangé', 'mange', 'manger'],
    pickAnswer: 'ai mangé',
    sentence: "J'ai mangé une pomme.",
    translation: 'I ate an apple.',
    incorrectSentence: "J'ai mange une pomme.",
    generationPoint: 'Passé composé',
  ),
  GrammarCurriculumLesson(
    id: 'grammar_v2_a1_past_regarder',
    level: 'A1',
    collection: 'Past tense',
    title: 'Remember a film',
    subtitle: 'Use avoir with a past participle',
    tip: 'The completed action uses avons regardé after nous.',
    pickPrompt: 'Nous ___ un film hier.',
    pickChoices: ['avons regardé', 'regardons', 'regarderons'],
    pickAnswer: 'avons regardé',
    sentence: 'Nous avons regardé un film hier.',
    translation: 'We watched a film yesterday.',
    incorrectSentence: 'Nous sommes regardé un film hier.',
    generationPoint: 'Passé composé',
  ),
  GrammarCurriculumLesson(
    id: 'grammar_v2_a1_past_arriver',
    level: 'A1',
    collection: 'Past tense',
    title: 'Say when you arrived',
    subtitle: 'Use être with arriver',
    tip: 'Movement verbs can use est plus the feminine past participle.',
    pickPrompt: 'Elle ___ hier.',
    pickChoices: ['est arrivée', 'a arrivé', 'arrive'],
    pickAnswer: 'est arrivée',
    sentence: 'Elle est arrivée hier.',
    translation: 'She arrived yesterday.',
    incorrectSentence: 'Elle a arrivé hier.',
    generationPoint: 'Passé composé',
  ),
  GrammarCurriculumLesson(
    id: 'grammar_v2_a1_past_ecrire',
    level: 'A1',
    collection: 'Past tense',
    title: 'Share a message',
    subtitle: 'Use avoir with écrire',
    tip: 'Use ai écrit for a completed action with je.',
    pickPrompt: "J'___ un message.",
    pickChoices: ['ai écrit', 'écris', 'écrirai'],
    pickAnswer: 'ai écrit',
    sentence: "J'ai écrit un message.",
    translation: 'I wrote a message.',
    incorrectSentence: "J'ai ecrit un message.",
    generationPoint: 'Passé composé',
  ),
  GrammarCurriculumLesson(
    id: 'grammar_v2_a1_past_partir',
    level: 'A1',
    collection: 'Past tense',
    title: 'Say who left',
    subtitle: 'Use être with partir',
    tip: 'Partir takes être in the passé composé: ils sont partis.',
    pickPrompt: 'Ils ___ tôt.',
    pickChoices: ['sont partis', 'ont parti', 'partent'],
    pickAnswer: 'sont partis',
    sentence: 'Ils sont partis tôt.',
    translation: 'They left early.',
    incorrectSentence: 'Ils ont parti tôt.',
    generationPoint: 'Passé composé',
  ),
  GrammarCurriculumLesson(
    id: 'grammar_v2_a1_future_appeler',
    level: 'A1',
    collection: 'Future tense',
    title: 'Make a plan',
    subtitle: 'Use aller plus an infinitive',
    tip: 'Futur proche uses vais before the infinitive appeler.',
    pickPrompt: 'Je vais ___ demain.',
    pickChoices: ['appeler', 'appelle', 'appelé'],
    pickAnswer: 'appeler',
    sentence: 'Je vais appeler demain.',
    translation: 'I am going to call tomorrow.',
    incorrectSentence: 'Je vais appelle demain.',
    generationPoint: 'Futur proche',
  ),
  GrammarCurriculumLesson(
    id: 'grammar_v2_a1_future_partir',
    level: 'A1',
    collection: 'Future tense',
    title: 'Plan a trip',
    subtitle: 'Keep the verb in the infinitive',
    tip: 'After allons, use the infinitive partir.',
    pickPrompt: 'Nous allons ___ demain.',
    pickChoices: ['partir', 'partons', 'parti'],
    pickAnswer: 'partir',
    sentence: 'Nous allons partir demain.',
    translation: 'We are going to leave tomorrow.',
    incorrectSentence: 'Nous allons partons demain.',
    generationPoint: 'Futur proche',
  ),
  GrammarCurriculumLesson(
    id: 'grammar_v2_a1_future_fera',
    level: 'A1',
    collection: 'Future tense',
    title: 'Predict the weather',
    subtitle: 'Use a simple future form',
    tip: 'The future form of faire with il is fera.',
    pickPrompt: 'Il ___ beau demain.',
    pickChoices: ['fera', 'fait', 'faisait'],
    pickAnswer: 'fera',
    sentence: 'Il fera beau demain.',
    translation: 'The weather will be nice tomorrow.',
    incorrectSentence: 'Il fait beau demain hier.',
    generationPoint: 'Futur simple',
  ),
  GrammarCurriculumLesson(
    id: 'grammar_v2_a1_future_preparer',
    level: 'A1',
    collection: 'Future tense',
    title: 'Plan dinner',
    subtitle: 'Use aller plus an infinitive',
    tip: 'After vas, keep préparer in the infinitive.',
    pickPrompt: 'Tu vas ___ le dîner.',
    pickChoices: ['préparer', 'prépares', 'préparé'],
    pickAnswer: 'préparer',
    sentence: 'Tu vas préparer le dîner.',
    translation: 'You are going to prepare dinner.',
    incorrectSentence: 'Tu vas prépares le dîner.',
    generationPoint: 'Futur proche',
  ),
  GrammarCurriculumLesson(
    id: 'grammar_v2_a1_future_viendra',
    level: 'A1',
    collection: 'Future tense',
    title: 'Make a promise',
    subtitle: 'Use venir in the future',
    tip: 'The simple future of venir with elle is viendra.',
    pickPrompt: 'Elle ___ demain.',
    pickChoices: ['viendra', 'vient', 'venait'],
    pickAnswer: 'viendra',
    sentence: 'Elle viendra demain.',
    translation: 'She will come tomorrow.',
    incorrectSentence: 'Elle vient demain hier.',
    generationPoint: 'Futur simple',
  ),
];
