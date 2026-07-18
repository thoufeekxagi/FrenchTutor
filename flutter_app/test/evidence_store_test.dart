import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/data/database/evidence_store.dart';
import 'package:french_tutor/orchestration/models/competency.dart';
import 'package:french_tutor/orchestration/models/error_event.dart';
import 'package:french_tutor/orchestration/models/evidence_event.dart';
import 'package:french_tutor/orchestration/models/task_result.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  final occurredAt = DateTime.utc(2026, 3, 10, 12, 30);
  final createdAt = DateTime.utc(2026, 3, 10, 12, 31);

  EvidenceEvent evidence(String id) => EvidenceEvent(
    id: id,
    userId: 'user-1',
    planId: 'plan-1',
    planTaskId: 'task-1',
    sessionId: 'session-1',
    contentItemId: 'content-1',
    competencyId: 'competency-1',
    modality: PerformanceModality.controlledSpeaking,
    supportLevel: EvidenceSupportLevel.hintedProduction,
    correctness: 0.75,
    score: 0.8,
    responseTimeMs: 1250,
    attemptNumber: 2,
    evaluator: EvidenceEvaluator.llmAudioCoaching,
    evaluatorConfidence: 0.65,
    errorCodes: const ['agreement.gender'],
    response: const {
      'transcript': 'une petit maison',
      'signals': [0.7, 0.8],
    },
    occurredAt: occurredAt,
    createdAt: createdAt,
  );

  EvidenceEvent evidenceWith({
    double? correctness = 0.5,
    double? score = 0.5,
    int? responseTimeMs = 100,
    int attemptNumber = 1,
    double evaluatorConfidence = 0.5,
  }) => EvidenceEvent(
    id: 'evidence-bounds',
    contentItemId: 'content-1',
    competencyId: 'competency-1',
    modality: PerformanceModality.readingRecognition,
    supportLevel: EvidenceSupportLevel.recognition,
    correctness: correctness,
    score: score,
    responseTimeMs: responseTimeMs,
    attemptNumber: attemptNumber,
    evaluator: EvidenceEvaluator.deterministicExact,
    evaluatorConfidence: evaluatorConfidence,
    occurredAt: occurredAt,
    createdAt: createdAt,
  );

  group('EvidenceStore', () {
    late Database db;
    late EvidenceStore store;

    setUp(() {
      db = sqlite3.openInMemory();
      store = EvidenceStore(db);
    });

    tearDown(() => db.dispose());

    test('round-trips evidence and error provenance and resolution', () {
      final source = evidence('evidence-1');
      final resolution = evidence('evidence-2');
      store.insertEvidence(source);
      store.insertEvidence(resolution);
      store.insertError(
        ErrorEvent(
          id: 'error-1',
          userId: 'user-1',
          competencyId: 'competency-1',
          sourceEvidenceId: source.id,
          errorCode: 'agreement.gender',
          observedForm: 'une petit maison',
          expectedForm: 'une petite maison',
          explanation: 'Adjective agreement',
          severity: 0.6,
          evaluator: EvidenceEvaluator.llmTextRubric,
          evaluatorConfidence: 0.7,
          resolvedByEvidenceId: resolution.id,
          occurredAt: occurredAt,
          createdAt: createdAt,
        ),
      );

      final restored = store.evidenceEvents(sessionId: 'session-1').first;
      expect(restored.id, source.id);
      expect(restored.modality, PerformanceModality.controlledSpeaking);
      expect(restored.supportLevel, EvidenceSupportLevel.hintedProduction);
      expect(restored.evaluator, EvidenceEvaluator.llmAudioCoaching);
      expect(restored.errorCodes, ['agreement.gender']);
      expect(restored.response, source.response);
      expect(restored.occurredAt, occurredAt);
      expect(() => restored.errorCodes.add('new'), throwsUnsupportedError);
      expect(() => restored.response!['new'] = true, throwsUnsupportedError);

      final error = store.errorEvents(sourceEvidenceId: source.id).single;
      expect(error.errorCode, 'agreement.gender');
      expect(error.observedForm, 'une petit maison');
      expect(error.resolvedByEvidenceId, resolution.id);
      expect(error.evaluator, EvidenceEvaluator.llmTextRubric);
    });

    test('rejects duplicate UUIDs instead of treating them as idempotent', () {
      store.insertEvidence(evidence('evidence-1'));

      expect(
        () => store.insertEvidence(evidence('evidence-1')),
        throwsA(isA<DuplicateEventIdException>()),
      );
      expect(store.evidenceEvents(), hasLength(1));
    });

    test('task-result insertion rolls back atomically on invalid evidence', () {
      expect(
        () => store.insertTaskResult(
          TaskResult(
            status: TaskResultStatus.completed,
            attempts: 2,
            learnerVisibleFeedback: 'Recorded.',
            competencyEvidence: [evidence('duplicate'), evidence('duplicate')],
          ),
        ),
        throwsA(isA<DuplicateEventIdException>()),
      );
      expect(store.evidenceEvents(), isEmpty);
    });

    test('database prevents updates and deletes from append-only tables', () {
      store.insertEvidence(evidence('evidence-1'));
      store.insertError(
        ErrorEvent(
          id: 'error-1',
          competencyId: 'competency-1',
          sourceEvidenceId: 'evidence-1',
          errorCode: 'agreement.gender',
          severity: 0.5,
          evaluator: EvidenceEvaluator.deterministicRule,
          evaluatorConfidence: 1,
          occurredAt: occurredAt,
          createdAt: createdAt,
        ),
      );

      expect(
        () => db.execute(
          "UPDATE evidence_events SET score = 1 WHERE id = 'evidence-1'",
        ),
        throwsA(isA<SqliteException>()),
      );
      expect(
        () => db.execute("DELETE FROM error_events WHERE id = 'error-1'"),
        throwsA(isA<SqliteException>()),
      );
      expect(store.evidenceEvents().single.score, 0.8);
      expect(store.errorEvents(), hasLength(1));
    });

    test('runs forward-only migrations through version 6 once', () {
      EvidenceStore(db);

      expect(
        db
            .select('SELECT version FROM schema_migrations ORDER BY version')
            .map((row) => row['version']),
        [1, 2, 3, 4, 5, 6],
      );
    });
  });

  group('Evidence contracts', () {
    test('rejects probability, duration, attempt, and severity bounds', () {
      expect(
        () => evidenceWith(evaluatorConfidence: 1.01),
        throwsArgumentError,
      );
      expect(() => evidenceWith(score: -0.01), throwsArgumentError);
      expect(() => evidenceWith(correctness: double.nan), throwsArgumentError);
      expect(() => evidenceWith(responseTimeMs: -1), throwsArgumentError);
      expect(() => evidenceWith(attemptNumber: 0), throwsArgumentError);
      expect(
        () => ErrorEvent(
          id: 'error-1',
          competencyId: 'competency-1',
          sourceEvidenceId: 'evidence-1',
          errorCode: 'code',
          severity: 1.1,
          evaluator: EvidenceEvaluator.humanTeacher,
          evaluatorConfidence: 1,
          occurredAt: occurredAt,
          createdAt: createdAt,
        ),
        throwsArgumentError,
      );
    });

    test('task results preserve typed immutable evidence and errors', () {
      final event = evidence('evidence-1');
      final result = TaskResult(
        status: TaskResultStatus.completed,
        attempts: 2,
        learnerVisibleFeedback: 'Try adjective agreement again.',
        competencyEvidence: [event],
        technicalMetadata: const {'adapter': 'speaking_v1'},
      );

      expect(result.competencyEvidence.single, same(event));
      expect(() => result.competencyEvidence.clear(), throwsUnsupportedError);
      expect(
        () => result.technicalMetadata['adapter'] = 'changed',
        throwsUnsupportedError,
      );
    });
  });
}
