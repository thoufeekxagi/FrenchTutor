import '../models/profile.dart';
import '../models/speak_curriculum.dart';
import '../data/database/adaptive_course_store.dart';
import 'adaptive_curriculum_service.dart';

export '../models/speak_curriculum.dart' show SpeakSessionKind, SpeakSkill;

class SpeakRoadmapSession {
  const SpeakRoadmapSession({
    required this.contentKey,
    this.level = 'A1',
    required this.index,
    required this.unit,
    required this.unitTitle,
    required this.title,
    required this.subtitle,
    this.competency = '',
    required this.kind,
    required this.completed,
    required this.unlocked,
    this.estimatedMinutes = 8,
    this.roleplay,
    this.primarySkill = SpeakSkill.speaking,
    this.supportingSkills = const [],
    this.targetPhrases = const [],
    this.contextPrompt = '',
  });

  final String contentKey;
  final String level;
  final int index;
  final int unit;
  final String unitTitle;
  final String title;
  final String subtitle;
  final String competency;
  final SpeakSessionKind kind;
  final bool completed;
  final bool unlocked;
  final int estimatedMinutes;
  final SpeakRoleplayScene? roleplay;
  final SpeakSkill primarySkill;
  final List<SpeakSkill> supportingSkills;
  final List<String> targetPhrases;
  final String contextPrompt;

  List<SpeakSkill> get activitySkills => [primarySkill, ...supportingSkills];
}

class SpeakRoadmap {
  const SpeakRoadmap({
    required this.level,
    required this.sessions,
    required this.trackLabel,
  });

  final String level;
  final List<SpeakRoadmapSession> sessions;
  final String trackLabel;

  int get completedCount =>
      sessions.where((session) => session.completed).length;
  double get progress =>
      sessions.isEmpty ? 0 : completedCount / sessions.length;
  SpeakRoadmapSession? get nextSession =>
      sessions.cast<SpeakRoadmapSession?>().firstWhere(
        (session) => session != null && !session.completed,
        orElse: () => null,
      );
}

/// Projects the published curriculum into learner progress. The content is
/// stable and unique; only completion/unlock state is learner-specific.
abstract final class SpeakRoadmapService {
  static SpeakRoadmap build(
    Profile profile, {
    Set<String> completedContentKeys = const {},
    required List<AdaptiveCourseSessionSpec> adaptiveSessions,
  }) {
    if (adaptiveSessions.isEmpty) {
      throw StateError(
        'An adaptive course plan is required to build a roadmap.',
      );
    }
    return _buildAdaptive(
      profile,
      sessions: adaptiveSessions,
      completedContentKeys: completedContentKeys,
    );
  }

  static SpeakRoadmap _buildAdaptive(
    Profile profile, {
    required List<AdaptiveCourseSessionSpec> sessions,
    required Set<String> completedContentKeys,
  }) {
    final projected = <SpeakRoadmapSession>[];
    for (var index = 0; index < sessions.length; index++) {
      final spec = sessions[index];
      final completed =
          spec.status == 'completed' ||
          completedContentKeys.contains(spec.contentKey);
      projected.add(
        SpeakRoadmapSession(
          contentKey: spec.contentKey,
          level: spec.level,
          index: index,
          unit: spec.unit,
          unitTitle: spec.unitTitle,
          title: spec.title,
          subtitle: spec.subtitle,
          competency: spec.competency,
          kind: _kindFor(spec.primarySkill),
          completed: completed,
          unlocked: true,
          estimatedMinutes: spec.estimatedMinutes,
          primarySkill: spec.primarySkill,
          supportingSkills: spec.supportingSkills,
          contextPrompt: spec.contextPrompt,
        ),
      );
    }
    return SpeakRoadmap(
      level: SpeakCurriculumLevel.normalise(profile.level),
      sessions: projected,
      trackLabel: AdaptiveCurriculumService.forProfile(profile).label,
    );
  }

  static SpeakSessionKind _kindFor(SpeakSkill skill) => switch (skill) {
    SpeakSkill.reading || SpeakSkill.listening => SpeakSessionKind.story,
    SpeakSkill.roleplay => SpeakSessionKind.roleplay,
    SpeakSkill.review => SpeakSessionKind.review,
    _ => SpeakSessionKind.speaking,
  };
}

abstract final class SpeakCurriculumCatalogLevel {
  static String normalise(String level) => switch (level.toLowerCase()) {
    'a1' || 'zero' || 'basics' => 'A1',
    'a2' => 'A2',
    'b1' || 'conversational' => 'B1',
    'b2' => 'B2',
    _ => 'A1',
  };
}
