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

  Map<String, dynamic> toJson() => {
    'id': id,
    'en': en,
    'fr': fr,
    'phonetic': phonetic,
  };
}

/// A learner-owned vocabulary set generated for a library card.  Unlike the
/// bundled curriculum phases, this payload is persisted with the signed-in
/// learner so it can be reopened on another device without rebuilding it.
class GeneratedVocabularySet {
  GeneratedVocabularySet({
    required this.id,
    required this.title,
    required this.summary,
    required this.topic,
    required this.levelBand,
    required this.entries,
    required this.createdAt,
    this.coverUrl,
  });

  final String id;
  final String title;
  final String summary;
  final String topic;
  final String levelBand;
  final List<VocabEntry> entries;
  final DateTime createdAt;
  final String? coverUrl;

  VocabTheme get asTheme => VocabTheme(id: id, title: title, entries: entries);

  GeneratedVocabularySet copyWith({String? coverUrl}) => GeneratedVocabularySet(
    id: id,
    title: title,
    summary: summary,
    topic: topic,
    levelBand: levelBand,
    entries: entries,
    createdAt: createdAt,
    coverUrl: coverUrl ?? this.coverUrl,
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

  Map<String, dynamic> toJson() => {
    'verb': verb,
    'group': group,
    'rows': rows.map((r) => r.toJson()).toList(),
  };
}

class ConjRow {
  ConjRow({required this.pronoun, required this.form});

  final String pronoun;
  final String form;

  factory ConjRow.fromJson(Map<String, dynamic> json) =>
      ConjRow(pronoun: json['pronoun'] as String, form: json['form'] as String);

  Map<String, dynamic> toJson() => {'pronoun': pronoun, 'form': form};
}

class BilingualExample {
  BilingualExample({required this.fr, required this.en});

  final String fr;
  final String en;

  factory BilingualExample.fromJson(Map<String, dynamic> json) =>
      BilingualExample(fr: json['fr'] as String, en: json['en'] as String);

  Map<String, dynamic> toJson() => {'fr': fr, 'en': en};
}

/// A dynamically-generated grammar explanation — the "teach the rule first"
/// half of a grammar practice session, grounding the story that follows it
/// (see `LessonAgentService.buildGrammarExplanation`/`buildGrammarStory`) so
/// both agree on the same rules instead of independently reinventing them.
/// Reuses [Conjugation]/[BilingualExample] since the shape (verb table,
/// bilingual examples) is identical to the old static lesson content, just
/// generated fresh per session instead of loaded from JSON.
class GrammarExplanation {
  GrammarExplanation({
    required this.title,
    required this.summary,
    required this.usage,
    required this.tenseContrast,
    required this.conjugations,
    required this.examples,
  });

  final String title;

  /// One short paragraph: what this tense/point is and when it's used.
  final String summary;

  /// Bullet-point usage rules.
  final List<String> usage;

  /// Explicit contrast against related tenses/forms (e.g. "unlike passé
  /// composé, which marks a completed action, imparfait describes an
  /// ongoing or habitual past state") — the "how it changes from present to
  /// past" piece specifically asked for, not left implicit.
  final String tenseContrast;
  final List<Conjugation> conjugations;
  final List<BilingualExample> examples;

  factory GrammarExplanation.fromJson(Map<String, dynamic> json) =>
      GrammarExplanation(
        title: json['title'] as String,
        summary: json['summary'] as String,
        usage: List<String>.from(json['usage'] as List),
        tenseContrast: json['tense_contrast'] as String? ?? '',
        conjugations: (json['conjugations'] as List)
            .map((e) => Conjugation.fromJson((e as Map).cast()))
            .toList(),
        examples: (json['examples'] as List)
            .map((e) => BilingualExample.fromJson((e as Map).cast()))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
    'title': title,
    'summary': summary,
    'usage': usage,
    'tense_contrast': tenseContrast,
    'conjugations': conjugations.map((c) => c.toJson()).toList(),
    'examples': examples.map((e) => e.toJson()).toList(),
  };
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
    this.qEn,
    this.choicesEn,
  });

  final String q;
  final List<String> choices;
  final int answerIndex;

  /// Optional English support for beginner listening checks. Older saved
  /// exercises do not have these fields, so the French payload remains valid.
  final String? qEn;
  final List<String>? choicesEn;

  factory MultipleChoiceQuestion.fromJson(Map<String, dynamic> json) =>
      MultipleChoiceQuestion(
        q: json['q'] as String,
        choices: List<String>.from(json['choices']),
        answerIndex: json['answerIndex'] as int,
        qEn: json['q_en'] as String? ?? json['question_en'] as String?,
        choicesEn: (json['choices_en'] as List?)?.cast<String>(),
      );

  Map<String, dynamic> toJson() => {
    'q': q,
    'choices': choices,
    'answerIndex': answerIndex,
    if (qEn != null) 'q_en': qEn,
    if (choicesEn != null) 'choices_en': choicesEn,
  };
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
    fr: (json['fr'] ?? json['text'] ?? json['french'] ?? '').toString().trim(),
    en: (json['en'] ?? json['translation'] ?? json['english'] ?? '')
        .toString()
        .trim(),
    grammarNote: (json['grammarNote'] ?? json['grammar'] ?? '')
        .toString()
        .trim(),
    pronunciationTip: (json['pronunciationTip'] ?? json['pronunciation'] ?? '')
        .toString()
        .trim(),
    characterFr: json['characterFr']?.toString(),
    characterEn: json['characterEn']?.toString(),
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
    this.titleEn,
  });

  final String id;
  final String title;
  final List<ReadingSegment> segments;
  final String fullText;

  /// A short (2-4 word) English gloss of [title], for A1/A2 learners who
  /// can't yet read the French title on sight — shown as "French (English)"
  /// wherever a title appears. Optional: older cached content and any
  /// generation that didn't return one just show the French title alone.
  final String? titleEn;

  factory ReadingPassage.fromJson(Map<String, dynamic> json) {
    final rawSegments = json['segments'] ?? json['sentences'];
    final parsedSegments = rawSegments is List
        ? rawSegments
              .whereType<Map>()
              .map(
                (entry) =>
                    ReadingSegment.fromJson(entry.cast<String, dynamic>()),
              )
              .where((segment) => segment.fr.isNotEmpty)
              .toList()
        : <ReadingSegment>[];
    final rawFullText = (json['fullText'] ?? json['text'] ?? '')
        .toString()
        .trim();
    final segments = parsedSegments.isNotEmpty
        ? parsedSegments
        : _segmentsFromText(rawFullText);
    final fullText = rawFullText.isNotEmpty
        ? rawFullText
        : segments.map((segment) => segment.fr).join(' ');

    return ReadingPassage(
      id: (json['id'] ?? json['passageId'] ?? 'reading-passage').toString(),
      title: (json['title'] ?? json['name'] ?? 'French story').toString(),
      segments: segments,
      fullText: fullText,
      titleEn: json['titleEn']?.toString() ?? json['title_en']?.toString(),
    );
  }

  static List<ReadingSegment> _segmentsFromText(String text) {
    if (text.trim().isEmpty) return const [];
    return text
        .split(RegExp(r'(?<=[.!?])\s+|\n+'))
        .map((sentence) => sentence.trim())
        .where((sentence) => sentence.isNotEmpty)
        .map(
          (sentence) => ReadingSegment(
            fr: sentence,
            en: '',
            grammarNote: '',
            pronunciationTip: '',
          ),
        )
        .toList();
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'segments': segments.map((s) => s.toJson()).toList(),
    'fullText': fullText,
    if (titleEn != null) 'titleEn': titleEn,
  };

  /// "French title (English gloss)" for display, or just the French title
  /// if no gloss is available.
  String get displayTitle =>
      (titleEn != null && titleEn!.isNotEmpty) ? '$title ($titleEn)' : title;
}

/// A learner's own AI-generated story, saved to their personal library —
/// the Story/Grammar tabs read straight off [passage]; [quiz]/[keywords] are
/// generated once alongside it (see LessonAgentService.buildStoryQuizAndKeywords)
/// so every tab is ready the moment the story is created, never regenerated
/// on reopen. Either list may be empty if that generation call failed —
/// callers should show a fallback rather than treat that as an error.
class GeneratedStory {
  GeneratedStory({
    required this.id,
    required this.passage,
    required this.quiz,
    required this.keywords,
    required this.createdAt,
    this.levelBand = 'A2',
    this.summary = '',
    this.topic = '',
    this.readTimeMinutes = 5,
    this.coverUrl,
    this.practiceMode = 'reading',
  });

  final String id;
  final ReadingPassage passage;
  final List<MultipleChoiceQuestion> quiz;
  final List<VocabEntry> keywords;
  final DateTime createdAt;

  /// CEFR band used to generate the story. Kept on the story so the library
  /// can show the same level even if the learner later changes their profile.
  final String levelBand;

  /// One-sentence English synopsis used by the library card and Marie's
  /// context. It is generated once with the story package.
  final String summary;

  /// The learner's chosen theme or topic, for discovery and replay context.
  final String topic;

  /// Approximate reading time shown in the Blinkist-style library.
  final int readTimeMinutes;

  /// Learner-scoped signed Supabase Storage URL for the single generated cover
  /// image. A local `asset:` marker is also valid while the private upload is
  /// being completed in the background.
  final String? coverUrl;

  /// Keeps the reading and listening shelves independent while preserving
  /// one shared story payload and cover pipeline.
  final String practiceMode;

  String get title => passage.title;

  /// "French title (English gloss)" for display — see `ReadingPassage.displayTitle`.
  String get displayTitle => passage.displayTitle;

  GeneratedStory copyWith({
    ReadingPassage? passage,
    List<MultipleChoiceQuestion>? quiz,
    List<VocabEntry>? keywords,
    String? levelBand,
    String? summary,
    String? topic,
    int? readTimeMinutes,
    String? coverUrl,
    String? practiceMode,
  }) {
    return GeneratedStory(
      id: id,
      passage: passage ?? this.passage,
      quiz: quiz ?? this.quiz,
      keywords: keywords ?? this.keywords,
      createdAt: createdAt,
      levelBand: levelBand ?? this.levelBand,
      summary: summary ?? this.summary,
      topic: topic ?? this.topic,
      readTimeMinutes: readTimeMinutes ?? this.readTimeMinutes,
      coverUrl: coverUrl ?? this.coverUrl,
      practiceMode: practiceMode ?? this.practiceMode,
    );
  }

  /// The tts_audio_cache `content_item_id` tag for one segment of this
  /// story's narration — shared by the prewarm call made right after
  /// generation and the reader's live playback, so both sides agree on the
  /// same tag (the actual cache hit only depends on voice+rate+text, but a
  /// consistent tag makes the cache traceable back to its story).
  String segmentContentId(int index) => '${id}_seg$index';
}

/// The complete payload returned by the one text-generation call used by the
/// story creator. Quiz and keywords are part of this package, so reopening a
/// story never triggers another model request.
class StoryBookGeneration {
  StoryBookGeneration({
    required this.passage,
    required this.quiz,
    required this.keywords,
    required this.levelBand,
    required this.summary,
    required this.topic,
    required this.readTimeMinutes,
    required this.coverPrompt,
  });

  final ReadingPassage passage;
  final List<MultipleChoiceQuestion> quiz;
  final List<VocabEntry> keywords;
  final String levelBand;
  final String summary;
  final String topic;
  final int readTimeMinutes;
  final String coverPrompt;
}

/// A learner's own AI-generated roleplay scene, saved to their personal
/// library so it can be replayed later exactly like the Story library saves
/// generated stories — walked through live in `AgentLedListeningScreen`,
/// which acts as both the in-character roleplay partner and the tutor
/// coaching each beat, same as any mission roleplay.
class GeneratedRoleplay {
  GeneratedRoleplay({
    required this.id,
    required this.passage,
    required this.createdAt,
    this.coverUrl,
  });

  final String id;
  final ReadingPassage passage;
  final DateTime createdAt;

  /// Learner-scoped signed URL for the generated roleplay artwork. The cover
  /// is optional so a roleplay remains usable while image generation/upload
  /// is still running or unavailable.
  final String? coverUrl;

  String get title => passage.title;

  /// "French title (English gloss)" for display — see `ReadingPassage.displayTitle`.
  String get displayTitle => passage.displayTitle;
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
    this.levelBand = 'A2',
  });

  final String id;
  final String type;
  final String title;
  final String promptFr;
  final String promptEn;
  final int minWords;
  final List<String> targetConnectors;
  final List<String> rubricHints;

  /// CEFR band ("A1"/"A2"/"B1"/"B2") this task is appropriate for — the
  /// static offline bank shouldn't show a B2 essay to an A1 learner, unlike
  /// the "New writing practice" button (which already generates fresh,
  /// level-appropriate content live). Defaults to A2 for any task authored
  /// before this field existed, rather than silently crashing on missing data.
  final String levelBand;

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'title': title,
    'promptFr': promptFr,
    'promptEn': promptEn,
    'minWords': minWords,
    'targetConnectors': targetConnectors,
    'rubricHints': rubricHints,
    'levelBand': levelBand,
  };

  factory WritingTask.fromJson(Map<String, dynamic> json) => WritingTask(
    id: json['id'] as String,
    type: json['type'] as String,
    title: json['title'] as String,
    promptFr: json['promptFr'] as String,
    promptEn: json['promptEn'] as String,
    minWords: json['minWords'] as int,
    targetConnectors: List<String>.from(json['targetConnectors']),
    rubricHints: List<String>.from(json['rubricHints']),
    levelBand: (json['levelBand'] as String?) ?? 'A2',
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
