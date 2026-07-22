import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import '../models/content_models.dart';
import '../models/srs_state.dart';
import '../orchestration/models/content_descriptor.dart';
import '../orchestration/models/mission.dart';

class ContentService {
  ContentService._();
  static final ContentService shared = ContentService._();

  VocabPhase? _phase1;
  VocabPhase? _phase2;
  VocabPhase? _phase3;
  Map<String, BilingualExample>? _vocabExamples;
  GrammarPack? _grammar;
  ConnectorsPack? _connectors;
  ListeningPack? _listening;
  WritingPack? _writing;
  Roadmap? _roadmap;
  ResourcePack? _resources;
  CompetencyFramework? _competencyFramework;
  MissionCatalog? _missionCatalog;
  List<GeneratedStory>? _starterStories;
  List<GeneratedRoleplay>? _starterRoleplays;

  Future<void> preload() async {
    await Future.wait([
      _loadPhase(1),
      _loadPhase(2),
      _loadPhase(3),
      _loadVocabExamples(),
      _loadGrammar(),
      _loadConnectors(),
      _loadListening(),
      _loadWriting(),
      _loadRoadmap(),
      _loadResources(),
      _loadCompetencyFramework(),
      _loadMissionCatalog(),
      _loadStarterStories(),
      _loadStarterRoleplays(),
    ]);
  }

  VocabPhase? vocabPhase(int n) {
    switch (n) {
      case 1:
        return _phase1;
      case 2:
        return _phase2;
      case 3:
        return _phase3;
      default:
        return null;
    }
  }

  List<VocabPhase> get vocabPhases =>
      [_phase1, _phase2, _phase3].whereType<VocabPhase>().toList();

  BilingualExample? vocabExamples(String entryId) => _vocabExamples?[entryId];

  Map<String, BilingualExample> vocabExamplesFor(List<VocabEntry> words) {
    final map = <String, BilingualExample>{};
    for (final word in words) {
      final example = _vocabExamples?[word.id];
      if (example != null) map[word.id] = example;
    }
    return map;
  }

  GrammarPack? grammar() => _grammar;
  ConnectorsPack? connectors() => _connectors;
  ListeningPack? listening() => _listening;
  WritingPack? writingTasks() => _writing;
  Roadmap? roadmap() => _roadmap;
  ResourcePack? resources() => _resources;
  CompetencyFramework? competencyFramework() => _competencyFramework;
  MissionCatalog? missionCatalog() => _missionCatalog;

  /// A small pool of ready-made short stories bundled with the app — so a
  /// brand-new learner's story library isn't empty before they've generated
  /// anything themselves. Shown alongside, never mixed into, the learner's
  /// own AI-generated stories (see ListeningLabScreen).
  List<GeneratedStory> starterStories() => _starterStories ?? const [];

  /// A small pool of ready-made roleplay scenes bundled with the app —
  /// same rationale as [starterStories]: a brand-new learner's Roleplay lab
  /// isn't empty before they've generated anything themselves.
  List<GeneratedRoleplay> starterRoleplays() => _starterRoleplays ?? const [];

  Set<String> knownContentIds() {
    final ids = <String>{};
    for (final phase in vocabPhases) {
      for (final theme in phase.themes) {
        ids.addAll(theme.entries.map((entry) => entry.id));
      }
    }
    final grammar = _grammar;
    if (grammar != null) {
      ids.addAll(grammar.lessons.map((lesson) => lesson.id));
      ids.addAll(grammar.topics.map((topic) => topic.id));
    }
    final listening = _listening;
    if (listening != null) {
      ids.addAll(listening.exercises.map((exercise) => exercise.id));
      ids.addAll(
        listening.exercises.map((exercise) => 'reading_${exercise.id}'),
      );
    }
    ids.addAll(
      _writing?.tasks.map((task) => task.id) ?? const Iterable<String>.empty(),
    );
    ids.addAll(
      _resources?.speakingTopics.map((topic) => topic.id) ??
          const Iterable<String>.empty(),
    );
    return ids;
  }

  ReadingPassage? readingPassage({required ListeningExercise fromListening}) {
    final segments = fromListening.script
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .map((line) {
          return ReadingSegment(
            fr: line,
            en: '',
            grammarNote: '',
            pronunciationTip: '',
          );
        })
        .toList();
    return ReadingPassage(
      id: 'reading_${fromListening.id}',
      title: fromListening.title,
      segments: segments,
      fullText: fromListening.script,
    );
  }

  // --- Lesson context builders (for AI prompt injection) ---

  String grammarLessonContext(GrammarLesson lesson) {
    final buf = StringBuffer();
    buf.writeln('Grammar lesson: ${lesson.title}, ${lesson.subtitle}');
    buf.writeln('Usage: ${lesson.usage.join("; ")}');
    for (final c in lesson.conjugations) {
      buf.writeln(
        '${c.verb} (${c.group}): ${c.rows.map((r) => "${r.pronoun} ${r.form}").join(", ")}',
      );
    }
    buf.writeln(
      'Examples: ${lesson.examples.map((e) => "${e.fr} = ${e.en}").join("; ")}',
    );
    return buf.toString();
  }

  String grammarTopicContext(GrammarTopic topic) {
    final buf = StringBuffer();
    buf.writeln('Grammar topic: ${topic.title}');
    for (final s in topic.sections) {
      buf.writeln('${s.heading}: ${s.body}');
      for (final e in s.examples) {
        buf.writeln('  ${e.fr} = ${e.en}');
      }
    }
    return buf.toString();
  }

  String connectorsContext() {
    final pack = _connectors;
    if (pack == null) return '';
    final buf = StringBuffer();
    buf.writeln('French connectors (${pack.connectors.length} total):');
    for (final c in pack.connectors) {
      buf.writeln(
        '${c.fr} (${c.en}) [${c.category}${c.core ? ", core" : ""}], e.g. ${c.example.fr}',
      );
    }
    return buf.toString();
  }

  String vocabContext(List<VocabEntry> entries) {
    return entries.map((e) => '${e.fr} (${e.phonetic}) = ${e.en}').join('\n');
  }

  /// French words the learner has actually mastered (`SRSState.isKnown`),
  /// e.g. for seeding a dynamically generated writing task so an A1 learner
  /// is only ever asked to reuse words they already know. Pass
  /// `LearningStore.allSRSStates()` in — this layer knows the word content,
  /// the store owns the review history, neither depends on the other.
  List<String> knownVocabWords(Map<String, SRSState> srsStates) {
    final words = <String>[];
    for (final phase in vocabPhases) {
      for (final theme in phase.themes) {
        for (final entry in theme.entries) {
          if (srsStates[entry.id]?.isKnown == true) words.add(entry.fr);
        }
      }
    }
    return words;
  }

  String writingTaskContext(WritingTask task) {
    return 'Writing task: ${task.title}\nType: ${task.type}\nPrompt (FR): ${task.promptFr}\nPrompt (EN): ${task.promptEn}\nMin words: ${task.minWords}\nTarget connectors: ${task.targetConnectors.join(", ")}\nRubric: ${task.rubricHints.join("; ")}';
  }

  String listeningExerciseContext(ListeningExercise exercise) {
    return 'Listening exercise: ${exercise.title}\nScript: ${exercise.script}\nQuestions: ${exercise.questions.length}\nDictation lines: ${exercise.dictation.length}';
  }

  String speakingTopicContext(SpeakingTopic topic) {
    return 'Speaking topic: ${topic.title}\nPrompt: ${topic.promptFr}\nHints: ${topic.hints.join("; ")}';
  }

  // --- Private loaders ---

  Future<void> _loadPhase(int n) async {
    final json = await _loadJson('vocab_phase$n.json');
    final phase = VocabPhase.fromJson(json);
    switch (n) {
      case 1:
        _phase1 = phase;
      case 2:
        _phase2 = phase;
      case 3:
        _phase3 = phase;
    }
  }

  Future<void> _loadVocabExamples() async {
    final json = await _loadJson('vocab_examples.json');
    final map = <String, BilingualExample>{};
    for (final entry in json.entries) {
      map[entry.key] = BilingualExample.fromJson(
        entry.value as Map<String, dynamic>,
      );
    }
    _vocabExamples = map;
  }

  Future<void> _loadGrammar() async {
    _grammar = GrammarPack.fromJson(await _loadJson('grammar.json'));
  }

  Future<void> _loadConnectors() async {
    _connectors = ConnectorsPack.fromJson(await _loadJson('connectors.json'));
  }

  Future<void> _loadListening() async {
    _listening = ListeningPack.fromJson(await _loadJson('listening.json'));
  }

  Future<void> _loadWriting() async {
    _writing = WritingPack.fromJson(await _loadJson('writing_tasks.json'));
  }

  Future<void> _loadRoadmap() async {
    _roadmap = Roadmap.fromJson(await _loadJson('roadmap.json'));
  }

  Future<void> _loadResources() async {
    _resources = ResourcePack.fromJson(await _loadJson('resources.json'));
  }

  Future<void> _loadCompetencyFramework() async {
    _competencyFramework = CompetencyFramework.fromJson(
      await _loadJson('competency_graph_v1.json'),
    );
  }

  Future<void> _loadMissionCatalog() async {
    _missionCatalog = MissionCatalog.fromJson(await _loadJson('missions.json'));
  }

  Future<void> _loadStarterStories() async {
    final json = await _loadJson('starter_stories.json');
    final storiesRaw = (json['stories'] as List?) ?? [];
    _starterStories = storiesRaw.map((raw) {
      final map = (raw as Map).cast<String, dynamic>();
      final segmentsRaw = (map['segments'] as List)
          .map((s) => ReadingSegment.fromJson((s as Map).cast()))
          .toList();
      final passage = ReadingPassage(
        id: map['id'] as String,
        title: map['title'] as String,
        titleEn: map['titleEn'] as String?,
        segments: segmentsRaw,
        fullText: segmentsRaw.map((s) => s.fr).join(' '),
      );
      final quiz = ((map['quiz'] as List?) ?? [])
          .map((q) => MultipleChoiceQuestion.fromJson((q as Map).cast()))
          .toList();
      final keywords = ((map['keywords'] as List?) ?? [])
          .map((k) => VocabEntry.fromJson((k as Map).cast()))
          .toList();
      return GeneratedStory(
        id: map['id'] as String,
        passage: passage,
        quiz: quiz,
        keywords: keywords,
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
      );
    }).toList();
  }

  Future<void> _loadStarterRoleplays() async {
    final json = await _loadJson('starter_roleplays.json');
    final roleplaysRaw = (json['roleplays'] as List?) ?? [];
    _starterRoleplays = roleplaysRaw.map((raw) {
      final map = (raw as Map).cast<String, dynamic>();
      final segmentsRaw = (map['segments'] as List)
          .map((s) => ReadingSegment.fromJson((s as Map).cast()))
          .toList();
      final passage = ReadingPassage(
        id: map['id'] as String,
        title: map['title'] as String,
        titleEn: map['titleEn'] as String?,
        segments: segmentsRaw,
        fullText: segmentsRaw.map((s) => s.fr).join(' '),
      );
      return GeneratedRoleplay(
        id: map['id'] as String,
        passage: passage,
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
      );
    }).toList();
  }

  Future<Map<String, dynamic>> _loadJson(String filename) async {
    final raw = await rootBundle.loadString('assets/content/$filename');
    return jsonDecode(raw) as Map<String, dynamic>;
  }
}
