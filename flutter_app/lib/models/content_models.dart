// All curriculum types — ported from ContentModels.swift

// MARK: - Vocabulary

class VocabPhase {
  VocabPhase({required this.phase, required this.title, required this.themes});

  final int phase;
  final String title;
  final List<VocabTheme> themes;

  int get totalEntries => themes.fold(0, (sum, t) => sum + t.entries.length);

  factory VocabPhase.fromJson(Map<String, dynamic> json) => VocabPhase(
    phase: json['phase'] as int,
    title: json['title'] as String,
    themes: (json['themes'] as List)
        .map((e) => VocabTheme.fromJson(e))
        .toList(),
  );
}

class VocabTheme {
  VocabTheme({required this.id, required this.title, required this.entries});

  final String id;
  final String title;
  final List<VocabEntry> entries;

  factory VocabTheme.fromJson(Map<String, dynamic> json) => VocabTheme(
    id: json['id'] as String,
    title: json['title'] as String,
    entries: (json['entries'] as List)
        .map((e) => VocabEntry.fromJson(e))
        .toList(),
  );
}

class VocabEntry {
  VocabEntry({
    required this.id,
    required this.en,
    required this.fr,
    required this.phonetic,
  });

  final String id;
  final String en;
  final String fr;
  final String phonetic;

  factory VocabEntry.fromJson(Map<String, dynamic> json) => VocabEntry(
    id: json['id'] as String,
    en: json['en'] as String,
    fr: json['fr'] as String,
    phonetic: json['phonetic'] as String,
  );
}

// MARK: - Grammar

class GrammarPack {
  GrammarPack({
    required this.lessons,
    required this.irregularVerbs,
    required this.topics,
  });

  final List<GrammarLesson> lessons;
  final List<IrregularVerb> irregularVerbs;
  final List<GrammarTopic> topics;

  factory GrammarPack.fromJson(Map<String, dynamic> json) => GrammarPack(
    lessons: (json['lessons'] as List)
        .map((e) => GrammarLesson.fromJson(e))
        .toList(),
    irregularVerbs: (json['irregularVerbs'] as List)
        .map((e) => IrregularVerb.fromJson(e))
        .toList(),
    topics: (json['topics'] as List? ?? [])
        .map((e) => GrammarTopic.fromJson(e))
        .toList(),
  );
}

class GrammarLesson {
  GrammarLesson({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.order,
    required this.usage,
    required this.narration,
    required this.conjugations,
    required this.examples,
    required this.drills,
  });

  final String id;
  final String title;
  final String subtitle;
  final int order;
  final List<String> usage;
  final List<String> narration;
  final List<Conjugation> conjugations;
  final List<BilingualExample> examples;
  final List<Drill> drills;

  factory GrammarLesson.fromJson(Map<String, dynamic> json) => GrammarLesson(
    id: json['id'] as String,
    title: json['title'] as String,
    subtitle: json['subtitle'] as String,
    order: json['order'] as int,
    usage: List<String>.from(json['usage']),
    narration: List<String>.from(json['narration']),
    conjugations: (json['conjugations'] as List)
        .map((e) => Conjugation.fromJson(e))
        .toList(),
    examples: (json['examples'] as List)
        .map((e) => BilingualExample.fromJson(e))
        .toList(),
    drills: (json['drills'] as List).map((e) => Drill.fromJson(e)).toList(),
  );
}

class Conjugation {
  Conjugation({required this.verb, required this.group, required this.rows});

  final String verb;
  final String group;
  final List<ConjRow> rows;

  factory Conjugation.fromJson(Map<String, dynamic> json) => Conjugation(
    verb: json['verb'] as String,
    group: json['group'] as String,
    rows: (json['rows'] as List).map((e) => ConjRow.fromJson(e)).toList(),
  );
}

class ConjRow {
  ConjRow({required this.pronoun, required this.form});

  final String pronoun;
  final String form;

  factory ConjRow.fromJson(Map<String, dynamic> json) =>
      ConjRow(pronoun: json['pronoun'] as String, form: json['form'] as String);
}

class BilingualExample {
  BilingualExample({required this.fr, required this.en});

  final String fr;
  final String en;

  factory BilingualExample.fromJson(Map<String, dynamic> json) =>
      BilingualExample(fr: json['fr'] as String, en: json['en'] as String);
}

class Drill {
  Drill({
    required this.type,
    required this.prompt,
    required this.answer,
    required this.choices,
  });

  final String type;
  final String prompt;
  final String answer;
  final List<String> choices;

  factory Drill.fromJson(Map<String, dynamic> json) => Drill(
    type: json['type'] as String,
    prompt: json['prompt'] as String,
    answer: json['answer'] as String,
    choices: List<String>.from(json['choices']),
  );
}

class IrregularVerb {
  IrregularVerb({
    required this.verb,
    required this.en,
    required this.present,
    required this.passeCompose,
    required this.examples,
  });

  final String verb;
  final String en;
  final List<String> present;
  final String passeCompose;
  final List<BilingualExample> examples;

  factory IrregularVerb.fromJson(Map<String, dynamic> json) => IrregularVerb(
    verb: json['verb'] as String,
    en: json['en'] as String,
    present: List<String>.from(json['present']),
    passeCompose: json['passeCompose'] as String,
    examples: (json['examples'] as List)
        .map((e) => BilingualExample.fromJson(e))
        .toList(),
  );
}

class GrammarTopic {
  GrammarTopic({
    required this.id,
    required this.title,
    required this.narration,
    required this.sections,
    required this.drills,
  });

  final String id;
  final String title;
  final List<String> narration;
  final List<TopicSection> sections;
  final List<Drill> drills;

  factory GrammarTopic.fromJson(Map<String, dynamic> json) => GrammarTopic(
    id: json['id'] as String,
    title: json['title'] as String,
    narration: List<String>.from(json['narration']),
    sections: (json['sections'] as List)
        .map((e) => TopicSection.fromJson(e))
        .toList(),
    drills: (json['drills'] as List).map((e) => Drill.fromJson(e)).toList(),
  );
}

class TopicSection {
  TopicSection({
    required this.heading,
    required this.body,
    required this.examples,
  });

  final String heading;
  final String body;
  final List<BilingualExample> examples;

  factory TopicSection.fromJson(Map<String, dynamic> json) => TopicSection(
    heading: json['heading'] as String,
    body: json['body'] as String,
    examples: (json['examples'] as List)
        .map((e) => BilingualExample.fromJson(e))
        .toList(),
  );
}

// MARK: - Connectors

class ConnectorsPack {
  ConnectorsPack({required this.tip, required this.connectors});

  final String tip;
  final List<Connector> connectors;

  factory ConnectorsPack.fromJson(Map<String, dynamic> json) => ConnectorsPack(
    tip: json['tip'] as String,
    connectors: (json['connectors'] as List)
        .map((e) => Connector.fromJson(e))
        .toList(),
  );
}

class Connector {
  Connector({
    required this.id,
    required this.fr,
    required this.en,
    required this.category,
    required this.core,
    required this.example,
  });

  final String id;
  final String fr;
  final String en;
  final String category;
  final bool core;
  final BilingualExample example;

  factory Connector.fromJson(Map<String, dynamic> json) => Connector(
    id: json['id'] as String,
    fr: json['fr'] as String,
    en: json['en'] as String,
    category: json['category'] as String,
    core: json['core'] as bool,
    example: BilingualExample.fromJson(json['example']),
  );
}

// MARK: - Grammar practice cards (generated per session)

class GrammarPracticeCard {
  GrammarPracticeCard({
    required this.id,
    required this.fr,
    required this.en,
    required this.note,
  });

  final String id;
  final String fr;
  final String en;
  final String note;

  factory GrammarPracticeCard.fromJson(Map<String, dynamic> json) =>
      GrammarPracticeCard(
        id: json['id'] as String,
        fr: json['fr'] as String,
        en: json['en'] as String,
        note: json['note'] as String,
      );
}

// MARK: - Listening

class ListeningPack {
  ListeningPack({required this.exercises});

  final List<ListeningExercise> exercises;

  factory ListeningPack.fromJson(Map<String, dynamic> json) => ListeningPack(
    exercises: (json['exercises'] as List)
        .map((e) => ListeningExercise.fromJson(e))
        .toList(),
  );
}

class ListeningExercise {
  ListeningExercise({
    required this.id,
    required this.title,
    required this.phase,
    required this.script,
    required this.questions,
    required this.dictation,
  });

  final String id;
  final String title;
  final int phase;
  final String script;
  final List<MultipleChoiceQuestion> questions;
  final List<String> dictation;

  factory ListeningExercise.fromJson(Map<String, dynamic> json) =>
      ListeningExercise(
        id: json['id'] as String,
        title: json['title'] as String,
        phase: json['phase'] as int,
        script: json['script'] as String,
        questions: (json['questions'] as List)
            .map((e) => MultipleChoiceQuestion.fromJson(e))
            .toList(),
        dictation: List<String>.from(json['dictation']),
      );
}

class MultipleChoiceQuestion {
  MultipleChoiceQuestion({
    required this.q,
    required this.choices,
    required this.answerIndex,
  });

  final String q;
  final List<String> choices;
  final int answerIndex;

  factory MultipleChoiceQuestion.fromJson(Map<String, dynamic> json) =>
      MultipleChoiceQuestion(
        q: json['q'] as String,
        choices: List<String>.from(json['choices']),
        answerIndex: json['answerIndex'] as int,
      );
}

// MARK: - Reading passage

/// One beat of a scene (or one segment of a legacy passage). `fr`/`en` are the
/// LEARNER's line; `characterFr`/`characterEn`, when present, are the other
/// role's line that prompts it — the full two-role script beat, so the app can
/// direct the scene deterministically instead of trusting a live model to
/// improvise structure. Legacy passages without character lines still load.
class ReadingSegment {
  ReadingSegment({
    required this.fr,
    required this.en,
    required this.grammarNote,
    required this.pronunciationTip,
    this.characterFr,
    this.characterEn,
  });

  final String fr;
  final String en;
  final String grammarNote;
  final String pronunciationTip;
  final String? characterFr;
  final String? characterEn;

  factory ReadingSegment.fromJson(Map<String, dynamic> json) => ReadingSegment(
    fr: json['fr'] as String,
    en: json['en'] as String,
    grammarNote: json['grammarNote'] as String,
    pronunciationTip: json['pronunciationTip'] as String,
    characterFr: json['characterFr'] as String?,
    characterEn: json['characterEn'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'fr': fr,
    'en': en,
    'grammarNote': grammarNote,
    'pronunciationTip': pronunciationTip,
    if (characterFr != null) 'characterFr': characterFr,
    if (characterEn != null) 'characterEn': characterEn,
  };
}

class ReadingPassage {
  ReadingPassage({
    required this.id,
    required this.title,
    required this.segments,
    required this.fullText,
  });

  final String id;
  final String title;
  final List<ReadingSegment> segments;
  final String fullText;

  factory ReadingPassage.fromJson(Map<String, dynamic> json) => ReadingPassage(
    id: json['id'] as String,
    title: json['title'] as String,
    segments: (json['segments'] as List)
        .map((e) => ReadingSegment.fromJson(e))
        .toList(),
    fullText: json['fullText'] as String,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'segments': segments.map((s) => s.toJson()).toList(),
    'fullText': fullText,
  };
}

// MARK: - Writing

class WritingPack {
  WritingPack({required this.tasks});

  final List<WritingTask> tasks;

  factory WritingPack.fromJson(Map<String, dynamic> json) => WritingPack(
    tasks: (json['tasks'] as List).map((e) => WritingTask.fromJson(e)).toList(),
  );
}

class WritingTask {
  WritingTask({
    required this.id,
    required this.type,
    required this.title,
    required this.promptFr,
    required this.promptEn,
    required this.minWords,
    required this.targetConnectors,
    required this.rubricHints,
  });

  final String id;
  final String type;
  final String title;
  final String promptFr;
  final String promptEn;
  final int minWords;
  final List<String> targetConnectors;
  final List<String> rubricHints;

  factory WritingTask.fromJson(Map<String, dynamic> json) => WritingTask(
    id: json['id'] as String,
    type: json['type'] as String,
    title: json['title'] as String,
    promptFr: json['promptFr'] as String,
    promptEn: json['promptEn'] as String,
    minWords: json['minWords'] as int,
    targetConnectors: List<String>.from(json['targetConnectors']),
    rubricHints: List<String>.from(json['rubricHints']),
  );
}

// MARK: - Roadmap

class Roadmap {
  Roadmap({
    required this.target,
    required this.months,
    required this.dailyHabits,
    required this.vocabularyBreakdown,
  });

  final String target;
  final List<RoadmapMonth> months;
  final List<DailyHabit> dailyHabits;
  final String vocabularyBreakdown;

  factory Roadmap.fromJson(Map<String, dynamic> json) => Roadmap(
    target: json['target'] as String,
    months: (json['months'] as List)
        .map((e) => RoadmapMonth.fromJson(e))
        .toList(),
    dailyHabits: (json['dailyHabits'] as List)
        .map((e) => DailyHabit.fromJson(e))
        .toList(),
    vocabularyBreakdown: json['vocabularyBreakdown'] as String,
  );
}

class RoadmapMonth {
  RoadmapMonth({
    required this.month,
    required this.title,
    required this.goals,
    required this.grammarChecklist,
  });

  final int month;
  final String title;
  final List<String> goals;
  final List<String> grammarChecklist;

  factory RoadmapMonth.fromJson(Map<String, dynamic> json) => RoadmapMonth(
    month: json['month'] as int,
    title: json['title'] as String,
    goals: List<String>.from(json['goals']),
    grammarChecklist: List<String>.from(json['grammarChecklist']),
  );
}

class DailyHabit {
  DailyHabit({
    required this.id,
    required this.title,
    required this.detail,
    required this.minutes,
    required this.lab,
  });

  final String id;
  final String title;
  final String detail;
  final int minutes;
  final String lab;

  factory DailyHabit.fromJson(Map<String, dynamic> json) => DailyHabit(
    id: json['id'] as String,
    title: json['title'] as String,
    detail: json['detail'] as String,
    minutes: json['minutes'] as int,
    lab: json['lab'] as String,
  );
}

// MARK: - Resources

class ResourcePack {
  ResourcePack({
    required this.readingProgression,
    required this.listeningTargets,
    required this.speakingTopics,
    required this.writingGuidance,
    required this.externalResources,
  });

  final List<ReadingStage> readingProgression;
  final List<ListeningTarget> listeningTargets;
  final List<SpeakingTopic> speakingTopics;
  final List<String> writingGuidance;
  final List<ExternalResource> externalResources;

  factory ResourcePack.fromJson(Map<String, dynamic> json) => ResourcePack(
    readingProgression: (json['readingProgression'] as List)
        .map((e) => ReadingStage.fromJson(e))
        .toList(),
    listeningTargets: (json['listeningTargets'] as List)
        .map((e) => ListeningTarget.fromJson(e))
        .toList(),
    speakingTopics: (json['speakingTopics'] as List)
        .map((e) => SpeakingTopic.fromJson(e))
        .toList(),
    writingGuidance: List<String>.from(json['writingGuidance']),
    externalResources: (json['externalResources'] as List)
        .map((e) => ExternalResource.fromJson(e))
        .toList(),
  );
}

class ReadingStage {
  ReadingStage({
    required this.stage,
    required this.title,
    required this.detail,
  });

  final int stage;
  final String title;
  final String detail;

  factory ReadingStage.fromJson(Map<String, dynamic> json) => ReadingStage(
    stage: json['stage'] as int,
    title: json['title'] as String,
    detail: json['detail'] as String,
  );
}

class ListeningTarget {
  ListeningTarget({
    required this.id,
    required this.title,
    required this.minutes,
    required this.detail,
  });

  final String id;
  final String title;
  final int minutes;
  final String detail;

  factory ListeningTarget.fromJson(Map<String, dynamic> json) =>
      ListeningTarget(
        id: json['id'] as String,
        title: json['title'] as String,
        minutes: json['minutes'] as int,
        detail: json['detail'] as String,
      );
}

class SpeakingTopic {
  SpeakingTopic({
    required this.id,
    required this.title,
    required this.promptFr,
    required this.hints,
  });

  final String id;
  final String title;
  final String promptFr;
  final List<String> hints;

  factory SpeakingTopic.fromJson(Map<String, dynamic> json) => SpeakingTopic(
    id: json['id'] as String,
    title: json['title'] as String,
    promptFr: json['promptFr'] as String,
    hints: List<String>.from(json['hints']),
  );
}

class ExternalResource {
  ExternalResource({
    required this.name,
    required this.bestFor,
    required this.free,
  });

  final String name;
  final String bestFor;
  final bool free;

  factory ExternalResource.fromJson(Map<String, dynamic> json) =>
      ExternalResource(
        name: json['name'] as String,
        bestFor: json['bestFor'] as String,
        free: json['free'] as bool,
      );
}
