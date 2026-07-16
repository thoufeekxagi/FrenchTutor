import '../models/content_descriptor.dart';
import '../models/evidence_event.dart';
import 'twin_updater.dart';

class EvidenceObservationAdapter {
  const EvidenceObservationAdapter();

  List<LearnerObservation> convert({
    required Iterable<EvidenceEvent> evidence,
    required CompetencyFramework framework,
  }) {
    final mappings = {
      for (final mapping in framework.mappings)
        (mapping.contentItemId, mapping.competencyId, mapping.modality):
            mapping,
    };
    final ordered = evidence.toList()
      ..sort((a, b) {
        final occurred = a.occurredAt.compareTo(b.occurredAt);
        if (occurred != 0) return occurred;
        final created = a.createdAt.compareTo(b.createdAt);
        if (created != 0) return created;
        return a.id.compareTo(b.id);
      });
    final previousAt = <(String, Object), DateTime>{};
    final observations = <LearnerObservation>[];
    for (final event in ordered) {
      final correctness = event.correctness ?? event.score;
      if (correctness == null) continue;
      final key = (event.competencyId, event.modality);
      final prior = previousAt[key];
      final elapsed = prior == null
          ? Duration.zero
          : event.occurredAt.difference(prior);
      if (elapsed.isNegative) {
        throw StateError('Evidence ordering produced a negative elapsed time');
      }
      final mapping =
          mappings[(event.contentItemId, event.competencyId, event.modality)];
      if (mapping == null) {
        throw StateError(
          'Evidence ${event.id} has no matching content-competency mapping',
        );
      }
      observations.add(
        LearnerObservation(
          competencyId: event.competencyId,
          modality: event.modality,
          correctness: correctness,
          support: event.supportLevel,
          reliability: _reliability(event),
          evaluatorConfidence: event.evaluatorConfidence,
          genuineLearningOpportunity:
              mapping.role != ContentMappingRole.assesses,
          elapsed: elapsed,
          observedAt: event.occurredAt,
        ),
      );
      previousAt[key] = event.occurredAt;
    }
    return observations;
  }

  double _reliability(EvidenceEvent event) {
    final evaluatorWeight = switch (event.evaluator) {
      EvidenceEvaluator.deterministicExact => 1.0,
      EvidenceEvaluator.deterministicRule => 0.9,
      EvidenceEvaluator.selfReport => 0.2,
      EvidenceEvaluator.speechToTextSignal => 0.35,
      EvidenceEvaluator.llmTextRubric => 0.7,
      EvidenceEvaluator.llmAudioCoaching => 0.6,
      EvidenceEvaluator.humanTeacher => 1.0,
    };
    final attemptWeight = 1 / (1 + (event.attemptNumber - 1) * 0.15);
    return (evaluatorWeight * attemptWeight).clamp(0, 1).toDouble();
  }
}
