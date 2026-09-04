import 'dart:convert';

import 'package:sqlite3/common.dart';

import '../models/profile.dart';
import '../models/speak_curriculum.dart';

/// A normalized read model over the learning data that already exists in the
/// app. Domain stores remain responsible for writing their current payloads.
class UniversalLearningEvidence {
  const UniversalLearningEvidence({
    required this.id,
    required this.source,
    required this.mode,
    required this.topic,
    required this.summary,
    required this.occurredAt,
  });

  final String id;
  final String source;
  final String mode;
  final String topic;
  final String summary;
  final DateTime occurredAt;
}

/// Compact context shared by Course and standalone Practice generation.
///
/// Full history stays in the local stores. Generation receives bounded,
/// labeled evidence so prompts stay useful and the Course can be regenerated
/// whenever recent Practice changes.
class UniversalLearningSnapshot {
  const UniversalLearningSnapshot({
    required this.fingerprint,
    required this.evidence,
    required this.sourceSessionIds,
    required this.recentTopics,
    required this.transcriptExcerpts,
    required this.writingSignals,
    required this.vocabularySignals,
    required this.examSignals,
    required this.performanceSignals,
    required this.repeatedMistakes,
    required this.targetPhrases,
    required this.recentSkills,
    required this.courseSessionCount,
    required this.practiceSessionCount,
  });

  final String fingerprint;
  final List<UniversalLearningEvidence> evidence;
  final List<String> sourceSessionIds;
  final List<String> recentTopics;
  final List<String> transcriptExcerpts;
  final List<String> writingSignals;
  final List<String> vocabularySignals;
  final List<String> examSignals;
  final List<String> performanceSignals;
  final List<String> repeatedMistakes;
  final List<String> targetPhrases;
  final List<SpeakSkill> recentSkills;
  final int courseSessionCount;
  final int practiceSessionCount;

  bool get hasEvidence =>
      evidence.isNotEmpty ||
      transcriptExcerpts.isNotEmpty ||
      writingSignals.isNotEmpty ||
      vocabularySignals.isNotEmpty ||
      examSignals.isNotEmpty ||
      performanceSignals.isNotEmpty ||
      repeatedMistakes.isNotEmpty;

  String get compactContext {
    final lines = <String>[];
    if (recentTopics.isNotEmpty) {
      lines.add('Recent topics: ' + recentTopics.take(5).join('; ') + '.');
    }
    if (targetPhrases.isNotEmpty) {
      lines.add(
        'Learner phrases/targets: ' + targetPhrases.take(8).join('; ') + '.',
      );
    }
    if (repeatedMistakes.isNotEmpty) {
      lines.add(
        'Repeated mistakes: ' + repeatedMistakes.take(5).join('; ') + '.',
      );
    }
    if (vocabularySignals.isNotEmpty) {
      lines.add(
        'Vocabulary evidence: ' + vocabularySignals.take(5).join('; ') + '.',
      );
    }
    if (writingSignals.isNotEmpty) {
      lines.add('Writing evidence: ' + writingSignals.take(3).join('; ') + '.');
    }
    if (examSignals.isNotEmpty) {
      lines.add('Exam evidence: ' + examSignals.take(3).join('; ') + '.');
    }
    if (performanceSignals.isNotEmpty) {
      lines.add(
        'Practice results: ' + performanceSignals.take(5).join('; ') + '.',
      );
    }
    if (transcriptExcerpts.isNotEmpty) {
      final excerpts = transcriptExcerpts
          .take(4)
          .map((value) => '"' + value + '"')
          .join('; ');
      lines.add('Learner transcript excerpts: ' + excerpts + '.');
    }
    return _bounded(lines.join('\n'), 2200);
  }

  /// Adds recent evidence to a stable curriculum context. The stored context
  /// is bounded so old plans do not grow without limit.
  String contextForLesson({
    required int sequence,
    required String baseContext,
  }) {
    if (!hasEvidence) return baseContext;
    final topic = recentTopics.isEmpty
        ? baseContext
        : recentTopics[(sequence - 1) % recentTopics.length];
    final targets = targetPhrases.isEmpty
        ? 'the learner’s recent language'
        : targetPhrases
              .skip((sequence - 1) % targetPhrases.length)
              .take(4)
              .join('; ');
    final repair = repeatedMistakes.isEmpty
        ? ''
        : ' Repair: ' + repeatedMistakes.take(2).join('; ') + '.';
    final results = performanceSignals.isEmpty
        ? ''
        : ' Recent results: ' + performanceSignals.take(2).join('; ') + '.';
    final sourceMaterial = <String>[];
    if (transcriptExcerpts.isNotEmpty) {
      sourceMaterial.add('Transcript: "' + transcriptExcerpts.first + '"');
    }
    if (writingSignals.isNotEmpty) {
      sourceMaterial.add('Writing: ' + writingSignals.first);
    }
    if (vocabularySignals.isNotEmpty) {
      sourceMaterial.add('Vocabulary: ' + vocabularySignals.first);
    }
    if (examSignals.isNotEmpty) {
      sourceMaterial.add('Exam: ' + examSignals.first);
    }
    final summary = evidence
        .map((item) => item.summary)
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');
    if (summary.isNotEmpty) {
      sourceMaterial.add('Summary: ' + summary);
    }
    final material = sourceMaterial.isEmpty
        ? ''
        : ' Learner evidence: ' + sourceMaterial.join(' | ') + '.';
    return _bounded(
      baseContext +
          '. Connect this lesson to the learner’s recent work on ' +
          topic +
          '. Reuse these targets naturally: ' +
          targets +
          '.' +
          repair +
          results +
          material,
      700,
    );
  }

  /// Rotates learner-produced material across a block instead of repeating
  /// the same phrase in every Course session.
  List<String> targetsForLesson({
    required int sequence,
    required List<String> fallback,
  }) {
    if (targetPhrases.isEmpty) return fallback.take(6).toList(growable: false);
    final start = (sequence - 1) % targetPhrases.length;
    final selected = <String>[];
    for (var offset = 0; offset < targetPhrases.length; offset++) {
      final target = targetPhrases[(start + offset) % targetPhrases.length];
      if (!selected.contains(target)) selected.add(target);
      if (selected.length == 6) break;
    }
    return selected;
  }

  String blockFingerprint(Profile profile) {
    final profileInput = <String>[
      profile.goal.trim().toLowerCase(),
      profile.level.trim().toLowerCase(),
      profile.sessionLength.trim().toLowerCase(),
      ...profile.interests.map((value) => value.trim().toLowerCase()),
    ]..sort();
    return UniversalLearningDataService.stableHash(
      profileInput.join('|') + '|' + fingerprint,
    );
  }

  static String _bounded(String value, int maxCharacters) {
    final clean = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean.length <= maxCharacters) return clean;
    return clean.substring(0, maxCharacters - 1).trimRight() + '…';
  }
}

/// Reads persisted Course and Practice evidence into one generation input.
abstract final class UniversalLearningDataService {
  static const defaultSessionLimit = 20;
  static const defaultTranscriptLimit = 12;
  static const defaultWritingLimit = 8;
  static const defaultVocabularyLimit = 24;
  static const defaultExamLimit = 8;
  static const _frenchMarkers = <String>{
    'à',
    'ai',
    'aller',
    'au',
    'aux',
    'avec',
    'bonjour',
    'comment',
    'dans',
    'de',
    'des',
    'du',
    'elle',
    'en',
    'est',
    'et',
    'être',
    'je',
    'la',
    'le',
    'les',
    'mais',
    'merci',
    'mon',
    'ne',
    'nous',
    'on',
    'pas',
    'pour',
    'pouvez',
    'que',
    'qui',
    'suis',
    'tu',
    'un',
    'une',
    'vous',
    'voudrais',
  };

  static UniversalLearningSnapshot buildSnapshot(
    CommonDatabase db,
    Profile profile, {
    int sessionLimit = defaultSessionLimit,
  }) {
    final evidence = <UniversalLearningEvidence>[];
    final sourceIds = <String>[];
    final topics = <String>[];
    final transcripts = <String>[];
    final writings = <String>[];
    final vocabulary = <String>[];
    final exams = <String>[];
    final performance = <String>[];
    final mistakes = <String>[];
    final targets = <String>[];
    final skills = <SpeakSkill>[];
    var courseCount = 0;
    var practiceCount = 0;

    final sessions = _safeSelect(
      db,
      '''SELECT id, started_at, ended_at, summary, topic, content_key, stage,
                vocabulary
         FROM sessions
         WHERE deleted_at IS NULL AND ended_at IS NOT NULL
         ORDER BY COALESCE(ended_at, started_at) DESC
         LIMIT ?''',
      [sessionLimit],
    );
    for (final row in sessions) {
      final id = _text(row['id']);
      if (id.isEmpty) continue;
      final stage = _text(row['stage']).toLowerCase();
      final topic = _clean(_text(row['topic']));
      final summary = _clean(_text(row['summary']));
      final source = _text(row['content_key']).startsWith('adaptive_')
          ? 'course'
          : 'practice';
      sourceIds.add(id);
      evidence.add(
        UniversalLearningEvidence(
          id: id,
          source: source,
          mode: _modeForStage(stage),
          topic: topic,
          summary: summary,
          occurredAt: _date(row['ended_at'] ?? row['started_at']),
        ),
      );
      if (source == 'course') {
        courseCount++;
      } else {
        practiceCount++;
      }
      _addUnique(topics, topic, limit: 12);
      _addSkill(skills, _skillForStage(stage));
      _extractVocabulary(row['vocabulary'], targets);
    }

    final userMessages = _safeSelect(
      db,
      '''SELECT session_id, content
         FROM messages
         WHERE role = 'user'
         ORDER BY id DESC
         LIMIT ?''',
      [defaultTranscriptLimit * 4],
    );
    for (final row in userMessages) {
      final content = _bounded(_text(row['content']), 180);
      if (content.isEmpty) continue;
      _addUnique(transcripts, content, limit: defaultTranscriptLimit);
      _extractPhrases(content, targets);
      _addUnique(sourceIds, _text(row['session_id']), limit: 40);
    }

    final aiSessions = _safeSelect(
      db,
      '''SELECT id, stage, topic, transcript_json, ended_at, created_at
         FROM ai_sessions
         WHERE transcript_json IS NOT NULL AND deleted_at IS NULL
         ORDER BY COALESCE(ended_at, created_at) DESC
         LIMIT ?''',
      [defaultTranscriptLimit],
    );
    for (final row in aiSessions) {
      _addUnique(sourceIds, _text(row['id']), limit: 40);
      _addUnique(topics, _clean(_text(row['topic'])), limit: 12);
      _addSkill(skills, _skillForStage(_text(row['stage'])));
      for (final turn in _decodeList(row['transcript_json'])) {
        if (turn is! Map) continue;
        final role = _text(turn['role']).toLowerCase();
        if (role != 'user' && role != 'learner') continue;
        final content = _bounded(_text(turn['content']), 180);
        if (content.isEmpty) continue;
        _addUnique(transcripts, content, limit: defaultTranscriptLimit);
        _extractPhrases(content, targets);
      }
    }

    for (final row in _safeSelect(
      db,
      '''SELECT task_id, text, feedback
         FROM writing_submissions
         ORDER BY submitted_at DESC
         LIMIT ?''',
      [defaultWritingLimit],
    )) {
      final text = _bounded(_text(row['text']), 220);
      final feedback = _bounded(_text(row['feedback']), 260);
      if (text.isNotEmpty) {
        _addUnique(
          writings,
          'Task ' + _text(row['task_id']) + ': ' + text,
          limit: 6,
        );
        _extractPhrases(text, targets);
      }
      if (feedback.isNotEmpty) {
        _addUnique(writings, 'Feedback: ' + feedback, limit: 6);
        _extractMistakePhrases(feedback, mistakes);
      }
    }

    // The current lesson-progress table is intentionally small, but it is
    // still the only durable score for several generated reading/listening
    // flows. Pull it into the same snapshot instead of treating completion as
    // proof of mastery.
    for (final row in _safeSelect(db, '''SELECT lesson_id, status, score
         FROM lesson_progress
         WHERE status IS NOT NULL AND status != 'not_started'
         LIMIT 24''')) {
      final lessonId = _text(row['lesson_id']);
      if (lessonId.isEmpty) continue;
      final score = row['score'];
      final scoreText = score == null ? '' : ', score ' + score.toString();
      _addUnique(
        performance,
        'lesson $lessonId: ' + _text(row['status']) + scoreText,
        limit: 24,
      );
    }

    // Daily Path stores per-stage results as JSON. Preserve the compact
    // result signal so Course can see a weak listening/reading/writing stage
    // even when that stage did not create a standalone session row.
    for (final row in _safeSelect(db, '''SELECT local_date, stages_json
         FROM daily_sessions
         WHERE deleted_at IS NULL
         ORDER BY updated_at DESC
         LIMIT 8''')) {
      final stages = _decodeMap(row['stages_json']);
      for (final entry in stages.entries) {
        if (entry.value is! Map) continue;
        final record = (entry.value as Map).cast<String, dynamic>();
        final status = _text(record['status']);
        final result = record['result'];
        final resultText = result is Map ? _scalarMap(result) : '';
        if (status.isEmpty && resultText.isEmpty) continue;
        _addUnique(
          performance,
          'daily ' +
              _text(row['local_date']) +
              ' ' +
              entry.key +
              ': ' +
              status +
              (resultText.isEmpty ? '' : ' ($resultText)'),
          limit: 24,
        );
      }
    }

    // Vocabulary workshops contain the most useful structured cross-skill
    // result: recall, context, and sentence production. Their frozen deck is
    // also a reliable source of French targets for future theme packs.
    for (final row in _safeSelect(
      db,
      '''SELECT topic, entries_json, recall_grades_json,
                context_results_json, sentence_results_json, status
         FROM vocabulary_sessions
         WHERE deleted_at IS NULL
         ORDER BY updated_at DESC
         LIMIT 8''',
    )) {
      _extractVocabulary(row['entries_json'], targets);
      final recall = _decodeMap(row['recall_grades_json']);
      final context = _decodeMap(row['context_results_json']);
      final sentences = _decodeMap(row['sentence_results_json']);
      _addUnique(
        performance,
        'vocabulary workshop ' +
            _text(row['topic']) +
            ': recall ' +
            _successCount(recall).toString() +
            '/' +
            recall.length.toString() +
            ', context ' +
            _successCount(context).toString() +
            '/' +
            context.length.toString() +
            ', sentences ' +
            _successCount(sentences).toString() +
            '/' +
            sentences.length.toString() +
            ', ' +
            _text(row['status']),
        limit: 12,
      );
      for (final entry in recall.entries) {
        final grade = _text(entry.value).toLowerCase();
        if (grade == 'again' || grade == 'hard') {
          _addUnique(
            mistakes,
            'vocabulary workshop target ${entry.key} ($grade)',
            limit: 8,
          );
        }
      }
    }

    // Competency states are a compact read model built from the existing
    // evidence ledger. They are useful as signals, never as a replacement
    // for the raw transcript/session evidence above.
    for (final row in _safeSelect(
      db,
      '''SELECT competency_id, modality, mastery_estimate, confidence,
                retention_strength, evidence_count, transfer_status,
                next_review_at
         FROM learner_competency_states
         WHERE deleted_at IS NULL
         ORDER BY updated_at DESC
         LIMIT 40''',
    )) {
      final competency = _text(row['competency_id']);
      final modality = _text(row['modality']);
      if (competency.isEmpty) continue;
      final mastery = _number(row['mastery_estimate']);
      final retention = _number(row['retention_strength']);
      _addUnique(
        performance,
        competency +
            ' [' +
            modality +
            ']: mastery ' +
            mastery.toStringAsFixed(2) +
            ', retention ' +
            retention.toStringAsFixed(2) +
            ', transfer ' +
            _text(row['transfer_status']) +
            ', evidence ' +
            _text(row['evidence_count']),
        limit: 32,
      );
      _addSkill(skills, _skillForStage(modality));
      if (retention < 0.45 || _text(row['transfer_status']) == 'not_observed') {
        _addUnique(
          mistakes,
          'weak competency $competency in $modality',
          limit: 8,
        );
      }
    }

    // Grammar practice already stores its quiz score in its generated lesson
    // row. Keep it as a performance signal even when the screen did not also
    // write a generic lesson_progress row.
    for (final row in _safeSelect(db, '''SELECT grammar_point, level_band, score
         FROM generated_grammar_stories
         WHERE deleted_at IS NULL AND score IS NOT NULL
         ORDER BY updated_at DESC
         LIMIT 8''')) {
      _addUnique(
        performance,
        'grammar ' +
            _text(row['grammar_point']) +
            ' ' +
            _text(row['level_band']) +
            ': score ' +
            _text(row['score']),
        limit: 24,
      );
    }

    for (final row in _safeSelect(
      db,
      '''SELECT entry_id, grade, response_type
         FROM vocab_reviews
         ORDER BY reviewed_at DESC
         LIMIT ?''',
      [defaultVocabularyLimit],
    )) {
      final entry = _text(row['entry_id']);
      final grade = _text(row['grade']);
      if (entry.isEmpty) continue;
      _addUnique(
        vocabulary,
        entry + ' (' + grade + ', ' + _text(row['response_type']) + ')',
        limit: defaultVocabularyLimit,
      );
      if (_looksLikeUsefulTarget(entry)) {
        _addUnique(targets, entry, limit: 24);
      }
      if (grade == 'again' || grade == 'hard') {
        _addUnique(
          mistakes,
          'vocabulary target ' + entry + ' (' + grade + ')',
          limit: 8,
        );
      }
    }

    for (final row in _safeSelect(
      db,
      '''SELECT entry_id
         FROM vocab_cards
         WHERE deleted_at IS NULL AND due_at IS NOT NULL
         ORDER BY due_at ASC
         LIMIT ?''',
      [defaultVocabularyLimit],
    )) {
      final entry = _text(row['entry_id']);
      if (entry.isEmpty) continue;
      _addUnique(vocabulary, entry + ' (due)', limit: defaultVocabularyLimit);
      if (_looksLikeUsefulTarget(entry)) {
        _addUnique(targets, entry, limit: 24);
      }
    }

    for (final row in _safeSelect(db, '''SELECT tag, description
         FROM mistake_tags
         WHERE resolved = 0
         ORDER BY count DESC
         LIMIT 8''')) {
      final tag = _clean(_text(row['tag']));
      final description = _clean(_text(row['description']));
      final value = description.isEmpty ? tag : tag + ': ' + description;
      _addUnique(mistakes, value, limit: 8);
    }

    for (final row in _safeSelect(
      db,
      '''SELECT id, exam_name, level_band, skill, score, total
         FROM exam_practice_attempts
         WHERE deleted_at IS NULL
         ORDER BY created_at DESC
         LIMIT ?''',
      [defaultExamLimit],
    )) {
      final score = row['score'];
      final total = row['total'];
      final result = score == null || total == null
          ? 'in progress'
          : score.toString() + '/' + total.toString();
      _addUnique(
        exams,
        _text(row['exam_name']) +
            ' ' +
            _text(row['level_band']) +
            ' ' +
            _text(row['skill']) +
            ': ' +
            result,
        limit: defaultExamLimit,
      );
      _addUnique(sourceIds, _text(row['id']), limit: 40);
      _addSkill(skills, _skillForStage('exam_' + _text(row['skill'])));
    }

    final fingerprintInput = <String>[
      profile.goal,
      profile.level,
      profile.sessionLength,
      ...profile.interests,
      ...sourceIds,
      ...topics,
      ...transcripts,
      ...writings,
      ...vocabulary,
      ...exams,
      ...performance,
      ...mistakes,
    ].join('|');
    return UniversalLearningSnapshot(
      fingerprint: stableHash(fingerprintInput),
      evidence: evidence,
      sourceSessionIds: sourceIds,
      recentTopics: topics,
      transcriptExcerpts: transcripts,
      writingSignals: writings,
      vocabularySignals: vocabulary,
      examSignals: exams,
      performanceSignals: performance,
      repeatedMistakes: mistakes,
      targetPhrases: targets.take(24).toList(growable: false),
      recentSkills: skills,
      courseSessionCount: courseCount,
      practiceSessionCount: practiceCount,
    );
  }

  static List<Map<String, dynamic>> _safeSelect(
    CommonDatabase db,
    String sql, [
    List<Object?> parameters = const [],
  ]) {
    try {
      return db
          .select(sql, parameters)
          .map((row) => Map<String, dynamic>.from(row))
          .toList(growable: false);
    } catch (_) {
      // Optional legacy sources must not make Course unavailable.
      return const [];
    }
  }

  static List<dynamic> _decodeList(Object? raw) {
    if (raw is List) return raw;
    if (raw is! String || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      return decoded is List ? decoded : const [];
    } catch (_) {
      return const [];
    }
  }

  static Map<String, dynamic> _decodeMap(Object? raw) {
    if (raw is Map) return raw.cast<String, dynamic>();
    if (raw is! String || raw.trim().isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map
          ? decoded.cast<String, dynamic>()
          : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  static String _scalarMap(Map value) => value.entries
      .where((entry) => entry.value is! Map && entry.value is! List)
      .take(4)
      .map((entry) => '${entry.key}: ${entry.value}')
      .join(', ');

  static int _successCount(Map value) => value.values.where((item) {
    final normalized = _text(item).toLowerCase();
    return item == true ||
        normalized == 'good' ||
        normalized == 'easy' ||
        normalized == 'correct' ||
        normalized == 'pass' ||
        normalized == 'passed';
  }).length;

  static double _number(Object? raw) =>
      raw is num ? raw.toDouble() : double.tryParse(_text(raw)) ?? 0;

  static void _extractVocabulary(Object? raw, List<String> targets) {
    for (final item in _decodeList(raw)) {
      if (item is String) {
        _addUnique(targets, _clean(item), limit: 24);
      } else if (item is Map) {
        for (final key in const ['fr', 'french', 'phrase', 'word', 'term']) {
          final value = _clean(_text(item[key]));
          if (value.isNotEmpty) {
            _addUnique(targets, value, limit: 24);
            break;
          }
        }
      }
    }
  }

  static void _extractPhrases(String raw, List<String> targets) {
    for (final piece
        in _clean(raw)
            .split(RegExp(r'[.!?;|]'))
            .map(_clean)
            .where((value) => value.length >= 3 && value.length <= 90)) {
      if (_looksLikeUsefulTarget(piece)) _addUnique(targets, piece, limit: 24);
    }
  }

  static void _extractMistakePhrases(String raw, List<String> mistakes) {
    for (final piece
        in _clean(raw)
            .split(RegExp(r'[.!?;|]'))
            .map(_clean)
            .where((value) => value.length >= 4 && value.length <= 120)) {
      final lower = piece.toLowerCase();
      if (lower.contains('error') ||
          lower.contains('correct') ||
          lower.contains('instead') ||
          lower.contains('should') ||
          lower.contains('agreement') ||
          lower.contains('verb')) {
        _addUnique(mistakes, piece, limit: 8);
      }
    }
  }

  static bool _looksLikeUsefulTarget(String value) {
    final words = value.split(' ');
    if (words.length > 12) return false;
    if (value.contains(RegExp(r'[àâçéèêëîïôùûüÿœæ]'))) return true;
    return words.any(
      (word) => _frenchMarkers.contains(
        word.toLowerCase().replaceAll(RegExp(r"[^a-zàâçéèêëîïôùûüÿœæ]"), ''),
      ),
    );
  }

  static void _addUnique(
    List<String> values,
    String value, {
    required int limit,
  }) {
    final clean = _clean(value);
    if (clean.isEmpty || values.length >= limit || values.contains(clean)) {
      return;
    }
    values.add(clean);
  }

  static void _addSkill(List<SpeakSkill> values, SpeakSkill? skill) {
    if (skill != null && !values.contains(skill)) values.add(skill);
  }

  static SpeakSkill? _skillForStage(String stage) =>
      switch (stage.toLowerCase().replaceAll('-', '_')) {
        'vocab' || 'vocabulary' => SpeakSkill.vocabulary,
        'reading' || 'story' || 'exam_reading' => SpeakSkill.reading,
        'reading_listening' ||
        'listening' ||
        'exam_listening' ||
        'listening_recognition' => SpeakSkill.listening,
        'reading_recognition' => SpeakSkill.reading,
        'writing' || 'exam_writing' => SpeakSkill.writing,
        'controlled_writing' || 'spontaneous_writing' => SpeakSkill.writing,
        'grammar' => SpeakSkill.grammar,
        'controlled_speaking' || 'spontaneous_speaking' => SpeakSkill.speaking,
        'pronunciation_production' => SpeakSkill.liaison,
        'pronunciation' ||
        'pronunciation_repair' ||
        'liaison' => SpeakSkill.liaison,
        'roleplay' => SpeakSkill.roleplay,
        'speaking' ||
        'speaking_guided' ||
        'free_talk' ||
        'exam_speaking' => SpeakSkill.speaking,
        'alphabet' => SpeakSkill.alphabet,
        'connectors' => SpeakSkill.connectors,
        _ => null,
      };

  static String _modeForStage(String stage) =>
      _skillForStage(stage)?.wireName ?? (stage.isEmpty ? 'practice' : stage);

  static DateTime _date(Object? raw) =>
      DateTime.tryParse(_text(raw)) ?? DateTime.fromMillisecondsSinceEpoch(0);

  static String _bounded(String value, int maxCharacters) {
    final clean = _clean(value);
    if (clean.length <= maxCharacters) return clean;
    return clean.substring(0, maxCharacters - 1).trimRight() + '…';
  }

  static String _text(Object? value) => value?.toString() ?? '';

  static String _clean(String value) =>
      value.replaceAll(RegExp(r'\s+'), ' ').trim();

  static String stableHash(String value) {
    var hash = 17;
    for (final unit in value.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return hash.toRadixString(16);
  }
}
