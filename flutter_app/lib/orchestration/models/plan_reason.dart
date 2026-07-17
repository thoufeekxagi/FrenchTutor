/// Machine-readable reason a task was selected (plan section 8.6). The
/// learner-facing explanation is generated from a fixed template per code;
/// an LLM may rewrite tone only, never the code or the underlying facts.
enum PlanReasonCode {
  dueReview('due_review'),
  recentMistake('recent_mistake'),
  weakestSkill('weakest_skill'),
  crossSkillTransfer('cross_skill_transfer'),
  prerequisiteReady('prerequisite_ready'),
  goalMaintenance('goal_maintenance'),
  examReadiness('exam_readiness'),
  learnerChoice('learner_choice'),
  skillMaintenance('skill_maintenance'),
  insufficientEvidence('insufficient_evidence');

  const PlanReasonCode(this.wireName);

  final String wireName;

  static PlanReasonCode fromWireName(String value) =>
      values.where((item) => item.wireName == value).firstOrNull ??
      (throw FormatException('Unknown plan reason code: $value'));
}
