import 'dart:collection';

import 'competency.dart';

enum EvidenceEvaluator {
  deterministicExact('deterministic_exact'),
  deterministicRule('deterministic_rule'),
  selfReport('self_report'),
  speechToTextSignal('speech_to_text_signal'),
  llmTextRubric('llm_text_rubric'),
  llmAudioCoaching('llm_audio_coaching'),
  humanTeacher('human_teacher');

  const EvidenceEvaluator(this.wireName);

  final String wireName;

  static EvidenceEvaluator fromWireName(String value) =>
      values.where((item) => item.wireName == value).firstOrNull ??
      (throw FormatException('Unknown evidence evaluator: $value'));
}

class EvidenceEvent {
  EvidenceEvent({
    required this.id,
    required this.competencyId,
    required this.contentItemId,
    required this.modality,
    required this.supportLevel,
    required this.evaluator,
    required this.evaluatorConfidence,
    required this.occurredAt,
    required this.createdAt,
    this.userId,
    this.planId,
    this.planTaskId,
    this.sessionId,
    this.correctness,
    this.score,
    this.responseTimeMs,
    this.attemptNumber = 1,
    List<String> errorCodes = const [],
    Map<String, Object?>? response,
  }) : errorCodes = UnmodifiableListView(List<String>.of(errorCodes)),
       response = response == null
           ? null
           : UnmodifiableMapView(Map<String, Object?>.of(response)) {
    _requireNonEmpty(id, 'id');
    _requireNonEmpty(competencyId, 'competencyId');
    _requireNonEmpty(contentItemId, 'contentItemId');
    _requireUnitInterval(correctness, 'correctness');
    _requireUnitInterval(score, 'score');
    _requireUnitInterval(evaluatorConfidence, 'evaluatorConfidence');
    if (responseTimeMs != null && responseTimeMs! < 0) {
      throw ArgumentError.value(
        responseTimeMs,
        'responseTimeMs',
        'must be >= 0',
      );
    }
    if (attemptNumber < 1) {
      throw ArgumentError.value(attemptNumber, 'attemptNumber', 'must be >= 1');
    }
    for (final errorCode in errorCodes) {
      _requireNonEmpty(errorCode, 'errorCodes');
    }
  }

  final String id;
  final String? userId;
  final String? planId;
  final String? planTaskId;
  final String? sessionId;
  final String contentItemId;
  final String competencyId;
  final PerformanceModality modality;
  final EvidenceSupportLevel supportLevel;
  final double? correctness;
  final double? score;
  final int? responseTimeMs;
  final int attemptNumber;
  final EvidenceEvaluator evaluator;
  final double evaluatorConfidence;
  final List<String> errorCodes;
  final Map<String, Object?>? response;
  final DateTime occurredAt;
  final DateTime createdAt;
}

void requireUnitInterval(num? value, String name) =>
    _requireUnitInterval(value, name);

void requireNonEmpty(String value, String name) =>
    _requireNonEmpty(value, name);

void _requireUnitInterval(num? value, String name) {
  if (value != null && (!value.isFinite || value < 0 || value > 1)) {
    throw ArgumentError.value(value, name, 'must be between 0 and 1');
  }
}

void _requireNonEmpty(String value, String name) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, name, 'must not be empty');
  }
}
