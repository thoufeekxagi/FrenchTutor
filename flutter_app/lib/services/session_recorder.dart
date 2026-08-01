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
    if (autoNote) unawaited(_generateAutoNote());
  }

  /// Best-effort, never blocks or throws to the caller — `finish()` is
  /// commonly called from `dispose()`, which can't await anything.
  Future<void> _generateAutoNote() async {
    try {
      final turns = _storage.getSessionMessages(sessionId: sessionId);
      if (turns.length < 2) return; // too thin to say anything real
      final transcript = turns
          .map((t) => '${t.role == 'user' ? 'Student' : 'Tutor'}: ${t.content}')
          .join('\n');
      final note = await LessonAgentService.shared.summarizeSessionForNotes(
        transcript: transcript,
        topic: topic,
      );
      if (note.isEmpty) return;
      _storage.saveNote(tag: topic, text: note, source: 'ai', sessionId: sessionId);
    } catch (_) {
      // Ambient recap, not the graded path — a failure here is silent.
    }
  }

  static String recentVocabTranscript(
    StorageService storage, {
    int maxCharacters = 120,
  }) {
    final session = storage.mostRecentSession(stage: 'vocab');
    if (session == null) return '';
    final turns = storage.getSessionMessages(sessionId: session.id);
    const navWords = {
      'next',
      'again',
      'back',
      'yes',
      'yeah',
      'ok',
      'okay',
      'oui',
      "d'accord",
    };
    final lastSubstantial = turns.lastWhere(
      (t) =>
          t.role == 'user' &&
          t.content.split(' ').length > 1 &&
          !navWords.contains(t.content.trim().toLowerCase()),
      orElse: () => turns.lastWhere(
        (t) => t.role == 'user',
        orElse: () => turns.isEmpty ? throw StateError('empty') : turns.last,
      ),
    );
    final line = lastSubstantial.content;
    return line.length > maxCharacters
        ? line.substring(0, maxCharacters)
        : line;
  }
}
