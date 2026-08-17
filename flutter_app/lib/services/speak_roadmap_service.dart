import '../models/profile.dart';
import '../models/speak_curriculum.dart';
import 'speak_curriculum_catalog.dart';

export '../models/speak_curriculum.dart' show SpeakSessionKind, SpeakSkill;

class SpeakRoadmapSession {
  const SpeakRoadmapSession({
    required this.contentKey,
    required this.index,
    required this.unit,
    required this.unitTitle,
    required this.title,
    required this.subtitle,
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
  final int index;
  final int unit;
  final String unitTitle;
  final String title;
  final String subtitle;
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
  const SpeakRoadmap({required this.level, required this.sessions});

  final String level;
  final List<SpeakRoadmapSession> sessions;

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
    int completedSessions = 0,
    Set<String> completedContentKeys = const {},
    List<SpeakCurriculumItem>? catalog,
  }) {
    final level = SpeakCurriculumCatalogLevel.normalise(profile.level);
    final items = [...(catalog ?? SpeakCurriculumCatalog.bundled(level))]
      ..sort((a, b) {
        final unitOrder = a.unit.compareTo(b.unit);
        if (unitOrder != 0) return unitOrder;
        return a.sessionIndex.compareTo(b.sessionIndex);
      });
    final sessions = <SpeakRoadmapSession>[];
    for (var index = 0; index < items.length; index++) {
      final item = items[index];
      final completed =
          completedContentKeys.contains(item.contentKey) ||
          index < completedSessions;
      sessions.add(
        SpeakRoadmapSession(
          contentKey: item.contentKey,
          index: index,
          unit: item.unit,
          unitTitle: item.unitTitle,
          title: item.title,
          subtitle: item.subtitle,
          kind: item.sessionKind,
          completed: completed,
          // The course is a library, not a gate. Learners may revisit a later
          // session whenever they want; progress recommends the next one but
          // never hides or locks the rest of the curriculum.
          unlocked: true,
          estimatedMinutes: item.estimatedMinutes,
          roleplay: item.roleplay,
          primarySkill: item.primarySkill,
          supportingSkills: item.supportingSkills,
          targetPhrases: item.targetPhrases,
          contextPrompt: item.contextPrompt,
        ),
      );
    }
    return SpeakRoadmap(level: level, sessions: sessions);
  }
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
