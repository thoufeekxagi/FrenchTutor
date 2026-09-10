import 'dart:async';

import 'package:uuid/uuid.dart';
import '../data/database/storage_service.dart';
import '../models/session.dart';
import 'lesson_agent_service.dart';

class SessionRecorder {
  SessionRecorder({
    required StorageService storage,
    required this.stage,
    required this.topic,
    this.contentKey,
  }) : _storage = storage, // ignore: prefer_initializing_formals
       sessionId = const Uuid().v4(),
       _startedAt = DateTime.now().toIso8601String();

  final StorageService _storage;
  final String sessionId;
  final String stage;
  final String topic;

  /// Links a practice transcript to its generated Course artifact.  Keeping
  /// this on the session row lets Review/Warm-up recover the bounded lesson
  /// material after reinstall instead of seeing only a title.
  final String? contentKey;
  final String _startedAt;
  static const _maxTurns = 24;
  static const _maxTurnCharacters = 360;
  static const _maxTranscriptCharacters = 6000;
  var _savedTurns = 0;
  var _savedTranscriptCharacters = 0;
  String? _lastSavedUser;
  String? _lastSavedTutor;

  void logUser(String text) {
    _saveTurn(role: 'user', text: text);
  }

  void logTutor(String text) {
    _saveTurn(role: 'assistant', text: text);
  }

  void _saveTurn({required String role, required String text}) {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _savedTurns >= _maxTurns) return;
    final previous = role == 'user' ? _lastSavedUser : _lastSavedTutor;
    if (previous == trimmed) return;
    final bounded = trimmed.length <= _maxTurnCharacters
        ? trimmed
        : '${trimmed.substring(0, _maxTurnCharacters - 1).trimRight()}…';
    if (_savedTranscriptCharacters + bounded.length >
        _maxTranscriptCharacters) {
      return;
    }
    _storage.saveMessage(sessionId: sessionId, role: role, content: bounded);
    _savedTurns++;
    _savedTranscriptCharacters += bounded.length;
    if (role == 'user') {
      _lastSavedUser = trimmed;
    } else {
      _lastSavedTutor = trimmed;
    }
  }

  /// [autoNote] off skips the AI recap (used by non-conversational stages
  /// like typed writing, where the "transcript" is just draft/feedback text,
  /// not a real back-and-forth worth summarizing as vocab learned).
  void finish({required String summary, bool autoNote = true}) {
    final now = DateTime.now().toIso8601String();
    _storage.saveSession(
      Session(
        id: sessionId,
        startedAt: _startedAt,
        endedAt: now,
        summary: summary,
        topic: topic,
        contentKey: contentKey,
        stage: stage,
      ),
    );
    if (autoNote) {
      unawaited(
        generateAutoNote(
          storage: _storage,
          sessionId: sessionId,
          topic: topic,
          stage: stage,
        ),
      );
    }
  }

  /// The clean category a note review filter can actually group by —
  /// distinct from the free-form `topic` (a story's title, a writing task's
  /// title, the specific tense name in a grammar session), which is what
  /// every AI note's tag was set to before this existed. That meant AI notes
  /// almost never matched one of the review screen's fixed filter chips
  /// (Vocabulary/Grammar/Listening/...) — they'd only ever show under "All".
  /// Keeps "Story" distinct from "Listening" (unlike `DailyGoalService`'s
  /// mission categories, which fold story into Listening) since the notes
  /// review screen already has its own icon/color for a separate Story tag.
  static String tagForStage(String? stage) => switch (stage) {
    'vocab' || 'vocabulary' => 'Vocabulary',
    'grammar' => 'Grammar',
    'reading_listening' || 'listening' => 'Listening',
    'reading' => 'Reading',
    'roleplay' => 'Roleplay',
    'writing' => 'Writing',
    'story' => 'Story',
    'speaking' ||
    'speaking_guided' ||
    'free_talk' ||
    'speaking_exam' ||
    'picture_description' ||
    'pronunciation_repair' ||
    'trial' => 'Speaking',
    'alphabet' => 'Alphabet',
    'connectors' => 'Connectors',
    'liaison' => 'Liaison',
    'exam_reading' => 'Reading',
    'exam_listening' => 'Listening',
    'exam_writing' => 'Writing',
    'exam_speaking' => 'Speaking',
    _ => 'General',
  };

  /// Static so screens that don't go through a full [SessionRecorder] (e.g.
  /// `SessionScreen`, which saves its own `Session`/messages directly) can
  /// still generate the same AI recap note — every conversational session
  /// gets one, not just the ones that happen to use this class end-to-end.
  /// Best-effort, never throws — commonly called from `dispose()`, which
  /// can't await anything.
  static Future<void> generateAutoNote({
    required StorageService storage,
    required String sessionId,
    required String topic,
    String? stage,
  }) async {
    try {
      final turns = storage.getSessionMessages(sessionId: sessionId);
      if (turns.length < 2) return; // too thin to say anything real
      final transcript = turns
          .map((t) => '${t.role == 'user' ? 'Student' : 'Tutor'}: ${t.content}')
          .join('\n');
      final note = await LessonAgentService.shared.summarizeSessionForNotes(
        transcript: transcript,
        topic: topic,
      );
      if (note.isEmpty) return;
      storage.saveNote(
        tag: tagForStage(stage),
        text: note,
        source: 'ai',
        sessionId: sessionId,
      );
    } catch (_) {
      // Ambient recap, not the graded path — a failure here is silent.
    }
  }
}
