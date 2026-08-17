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
  }) : _storage = storage, // ignore: prefer_initializing_formals
       sessionId = const Uuid().v4(),
       _startedAt = DateTime.now().toIso8601String();

  final StorageService _storage;
  final String sessionId;
  final String stage;
  final String topic;
  final String _startedAt;

  void logUser(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    _storage.saveMessage(sessionId: sessionId, role: 'user', content: trimmed);
  }

  void logTutor(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    _storage.saveMessage(
      sessionId: sessionId,
      role: 'assistant',
      content: trimmed,
    );
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
    'vocab' => 'Vocabulary',
    'grammar' => 'Grammar',
    'reading_listening' => 'Listening',
    'roleplay' => 'Roleplay',
    'writing' => 'Writing',
    'story' => 'Story',
    'speaking' || 'trial' => 'Speaking',
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
