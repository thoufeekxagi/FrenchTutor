import '../models/competency.dart';
import '../models/plan_reason.dart';
import 'orchestrator.dart';

class PlanExplanation {
  const PlanExplanation({required this.code, required this.text});

  final PlanReasonCode code;
  final String text;
}

/// Turns a [PlanTask]'s numeric score breakdown into a fixed reason code and
/// a learner-readable sentence (plan section 8.6). Every required task must
/// have both; an LLM may only restyle [text], never change [code] or the
/// facts it is built from.
class PlanExplainer {
  const PlanExplainer();

  PlanExplanation explain({
    required PlanTask task,
    required Competency competency,
  }) {
    final code = _codeFor(_dominantReason(task), task);
    return PlanExplanation(code: code, text: _template(code, competency));
  }

  PlanningReason _dominantReason(PlanTask task) {
    final positive = task.reasonTrace
        .where((trace) => trace.contribution > 0)
        .toList()
      ..sort((a, b) => b.contribution.compareTo(a.contribution));
    return positive.isEmpty
        ? PlanningReason.mappingStrength
        : positive.first.reason;
  }

  PlanReasonCode _codeFor(PlanningReason reason, PlanTask task) =>
      switch (reason) {
        PlanningReason.dueReview => PlanReasonCode.dueReview,
        PlanningReason.weakSkill => PlanReasonCode.weakestSkill,
        PlanningReason.uncertainSkill => PlanReasonCode.insufficientEvidence,
        PlanningReason.recentError => PlanReasonCode.recentMistake,
        PlanningReason.transferOpportunity => PlanReasonCode.crossSkillTransfer,
        PlanningReason.prerequisiteReadiness => PlanReasonCode.prerequisiteReady,
        PlanningReason.goalAlignment => PlanReasonCode.goalMaintenance,
        PlanningReason.mappingStrength => task.priority == PlanPriority.bonus
            ? PlanReasonCode.learnerChoice
            : PlanReasonCode.skillMaintenance,
        PlanningReason.contextPenalty => PlanReasonCode.skillMaintenance,
        PlanningReason.costPenalty => PlanReasonCode.skillMaintenance,
      };

  String _template(PlanReasonCode code, Competency competency) =>
      switch (code) {
        PlanReasonCode.dueReview =>
          '${competency.title} is due for review.',
        PlanReasonCode.recentMistake =>
          'A recent mistake with ${competency.title}, this follows it up.',
        PlanReasonCode.weakestSkill =>
          '${competency.title} is one of your weaker skills right now.',
        PlanReasonCode.crossSkillTransfer =>
          'Checks whether ${competency.title} transfers to a new context.',
        PlanReasonCode.prerequisiteReady =>
          'You are ready to build on ${competency.title}.',
        PlanReasonCode.goalMaintenance =>
          '${competency.title} is relevant to your stated goal.',
        PlanReasonCode.examReadiness =>
          '${competency.title} supports your exam readiness.',
        PlanReasonCode.learnerChoice =>
          'Extra depth on ${competency.title}, entirely optional.',
        PlanReasonCode.skillMaintenance =>
          'Keeps ${competency.title} strong.',
        PlanReasonCode.insufficientEvidence =>
          'More evidence is needed on ${competency.title} to know where you stand.',
      };
}
