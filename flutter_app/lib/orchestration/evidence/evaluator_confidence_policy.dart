import '../models/evidence_event.dart';

class EvaluatorConfidencePolicy {
  const EvaluatorConfidencePolicy({this.version = 'o2-confidence-v1'});

  final String version;

  double cap(EvidenceEvaluator evaluator, double proposed) {
    if (!proposed.isFinite || proposed < 0 || proposed > 1) {
      throw ArgumentError.value(
        proposed,
        'proposed',
        'must be between 0 and 1',
      );
    }
    final maximum = switch (evaluator) {
      EvidenceEvaluator.deterministicExact => 0.98,
      EvidenceEvaluator.deterministicRule => 0.90,
      EvidenceEvaluator.selfReport => 0.25,
      EvidenceEvaluator.speechToTextSignal => 0.35,
      EvidenceEvaluator.llmTextRubric => 0.65,
      EvidenceEvaluator.llmAudioCoaching => 0.55,
      EvidenceEvaluator.humanTeacher => 0.95,
    };
    return proposed.clamp(0, maximum).toDouble();
  }
}
