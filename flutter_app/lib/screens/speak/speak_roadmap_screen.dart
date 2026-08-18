import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/adaptive_course_store.dart';
import '../../design/app_router.dart';
import '../../design/tokens.dart';
import '../../models/profile.dart';
import '../../models/speak_curriculum.dart';
import '../../providers/database_provider.dart';
import '../../services/speak_language_profile.dart';
import '../../services/speak_roadmap_service.dart';
import 'speak_course_activity_screen.dart';
import 'speak_ui.dart';

class SpeakRoadmapScreen extends ConsumerWidget {
  const SpeakRoadmapScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(learningStoreProvider).profile();
    final completedContentKeys = ref
        .watch(storageServiceProvider)
        .completedContentKeys();
    final adaptivePlan = ref
        .read(adaptiveCourseStoreProvider)
        .ensureCurrentPlan(profile);
    return _buildRoadmap(
      context,
      ref,
      profile,
      completedContentKeys,
      adaptivePlan.sessions,
    );
  }

  Widget _buildRoadmap(
    BuildContext context,
    WidgetRef ref,
    Profile profile,
    Set<String> completedContentKeys,
    List<AdaptiveCourseSessionSpec> adaptiveSessions,
  ) {
    final roadmap = SpeakRoadmapService.build(
      profile,
      // History includes free talk, onboarding demos, and legacy sessions.
      // Only stable course content keys are allowed to unlock this path.
      // There is no safe legacy index fallback: keys from another level
      // must not unlock this level's path.
      completedContentKeys: completedContentKeys,
      adaptiveSessions: adaptiveSessions,
    );
    final language = SpeakLanguageProfile.forLevel(roadmap.level);
    final units =
        roadmap.sessions.map((session) => session.unit).toSet().toList()
          ..sort();
    return SpeakScaffold(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 34),
        children: [
          SpeakHeader(
            title: 'Your course',
            subtitle:
                '${roadmap.level.toUpperCase()} · ${roadmap.trackLabel} · ${roadmap.sessions.length} sessions · ${language.shortLabel}',
            leading: embedded
                ? null
                : GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: const Icon(
                      Icons.arrow_back_rounded,
                      color: SpeakColors.inkSoft,
                    ),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              language.roadmapHint,
              style: DesignTokens.body(12).copyWith(color: SpeakColors.inkSoft),
            ),
          ),
          const SizedBox(height: 20),
          SpeakCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.route_rounded, color: SpeakColors.blue),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${roadmap.completedCount} of ${roadmap.sessions.length} sessions complete · ${units.length} units',
                        style: DesignTokens.body(14, weight: FontWeight.w700),
                      ),
                    ),
                    Text(
                      '${(roadmap.progress * 100).round()}%',
                      style: DesignTokens.body(
                        12,
                        weight: FontWeight.w700,
                      ).copyWith(color: SpeakColors.blue),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SpeakProgressBar(value: roadmap.progress),
              ],
            ),
          ),
          const SizedBox(height: 24),
          for (final unit in units) ...[
            _unitHeader(roadmap, unit),
            const SizedBox(height: 10),
            for (final session in roadmap.sessions.where(
              (session) => session.unit == unit,
            )) ...[
              _sessionTile(
                context,
                session,
                featured: session.index == roadmap.nextSession?.index,
              ),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 14),
          ],
        ],
      ),
    );
  }

  Widget _unitHeader(SpeakRoadmap roadmap, int unit) {
    final session = roadmap.sessions.firstWhere((item) => item.unit == unit);
    return Row(
      children: [
        Text(
          'UNIT $unit',
          style: DesignTokens.label(
            10,
          ).copyWith(color: SpeakColors.inkSoft, letterSpacing: 1),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(session.unitTitle, style: DesignTokens.display(20)),
        ),
      ],
    );
  }

  Widget _sessionTile(
    BuildContext context,
    SpeakRoadmapSession session, {
    required bool featured,
  }) {
    final active = featured && !session.completed;
    final lessonSubtitle = _lessonSubtitle(session.subtitle);
    return GestureDetector(
      onTap: () => AppRouter.push(context, (_) => _screenFor(session)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: active ? SpeakColors.blue : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: active ? SpeakColors.blue : SpeakColors.line,
          ),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: DesignTokens.primary.withValues(alpha: 0.1),
                    blurRadius: 14,
                    offset: Offset(0, 5),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: active ? Colors.white24 : SpeakColors.blueSoft,
                shape: BoxShape.circle,
              ),
              child: Icon(
                session.completed
                    ? Icons.check_rounded
                    : _iconFor(session.primarySkill),
                size: 18,
                color: active ? Colors.white : SpeakColors.blue,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    session.title,
                    style: DesignTokens.body(
                      14,
                      weight: FontWeight.w700,
                    ).copyWith(color: active ? Colors.white : SpeakColors.navy),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${session.primarySkill.label} · $lessonSubtitle',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DesignTokens.body(11).copyWith(
                      color: active ? Colors.white70 : SpeakColors.inkSoft,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              session.completed
                  ? Icons.check_circle_rounded
                  : Icons.arrow_forward_ios_rounded,
              size: 18,
              color: active ? Colors.white : SpeakColors.inkSoft,
            ),
          ],
        ),
      ),
    );
  }

  String _lessonSubtitle(String subtitle) {
    // The route stores the track label in the first segment for generation
    // context, but course cards should show the human lesson purpose first.
    final separator = subtitle.indexOf(' · ');
    return separator == -1 ? subtitle : subtitle.substring(separator + 3);
  }

  Widget _screenFor(SpeakRoadmapSession session) =>
      SpeakCourseActivityScreen(session: session);

  IconData _iconFor(SpeakSkill skill) => switch (skill) {
    SpeakSkill.alphabet => Icons.abc_rounded,
    SpeakSkill.vocabulary => Icons.style_outlined,
    SpeakSkill.reading => Icons.menu_book_outlined,
    SpeakSkill.listening => Icons.headphones_outlined,
    SpeakSkill.grammar => Icons.auto_fix_high_outlined,
    SpeakSkill.connectors => Icons.link_rounded,
    SpeakSkill.liaison => Icons.record_voice_over_outlined,
    SpeakSkill.writing => Icons.edit_note_rounded,
    SpeakSkill.speaking => Icons.mic_none_rounded,
    SpeakSkill.roleplay => Icons.forum_outlined,
    SpeakSkill.review => Icons.replay_rounded,
    SpeakSkill.freeTalk => Icons.people_alt_outlined,
  };
}
