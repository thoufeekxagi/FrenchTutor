import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import '../models/content_models.dart';

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
    ]);
  }

  VocabPhase? vocabPhase(int n) {
    switch (n) {
      case 1: return _phase1;
      case 2: return _phase2;
      case 3: return _phase3;
      default: return null;
    }
  }

  List<VocabPhase> get vocabPhases => [_phase1, _phase2, _phase3].whereType<VocabPhase>().toList();

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

  ReadingPassage? readingPassage({required ListeningExercise fromListening}) {
    final segments = fromListening.script.split('\n').where((l) => l.trim().isNotEmpty).map((line) {
      return ReadingSegment(fr: line, en: '', grammarNote: '', pronunciationTip: '');
    }).toList();
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
    buf.writeln('Grammar lesson: ${lesson.title} — ${lesson.subtitle}');
    buf.writeln('Usage: ${lesson.usage.join("; ")}');
    for (final c in lesson.conjugations) {
      buf.writeln('${c.verb} (${c.group}): ${c.rows.map((r) => "${r.pronoun} ${r.form}").join(", ")}');
    }
    buf.writeln('Examples: ${lesson.examples.map((e) => "${e.fr} = ${e.en}").join("; ")}');
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
      buf.writeln('${c.fr} (${c.en}) [${c.category}${c.core ? ", core" : ""}] — e.g. ${c.example.fr}');
    }
    return buf.toString();
  }

  String vocabContext(List<VocabEntry> entries) {
    return entries.map((e) => '${e.fr} (${e.phonetic}) = ${e.en}').join('\n');
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
      case 1: _phase1 = phase;
      case 2: _phase2 = phase;
      case 3: _phase3 = phase;
    }
  }

  Future<void> _loadVocabExamples() async {
    final json = await _loadJson('vocab_examples.json');
    final map = <String, BilingualExample>{};
    for (final entry in json.entries) {
      map[entry.key] = BilingualExample.fromJson(entry.value as Map<String, dynamic>);
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

  Future<Map<String, dynamic>> _loadJson(String filename) async {
    final raw = await rootBundle.loadString('assets/content/$filename');
    return jsonDecode(raw) as Map<String, dynamic>;
  }
}
