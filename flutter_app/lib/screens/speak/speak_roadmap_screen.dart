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
import '../../services/subscription_gate_service.dart';
import 'speak_course_activity_screen.dart';
import '../../widgets/v3/v3_surface.dart';

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
    final courseLocked = ref
        .watch(subscriptionGateServiceProvider)
        .isAreaLocked(PremiumArea.course);
    final units =
        roadmap.sessions.map((session) => session.unit).toSet().toList()
          ..sort();
    return V3Scaffold(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 34),
        children: [
          V3Header(
            title: 'Your course',
            subtitle:
                '${roadmap.level.toUpperCase()} · ${roadmap.trackLabel} · ${roadmap.sessions.length} sessions · ${language.shortLabel}',
            leading: embedded ? null : const V3BackButton(),
            trailing: V3IconButton(
              icon: Icons.tune_rounded,
              tooltip: 'Course options',
              onPressed: () => showV3Picker<String>(
                context: context,
                title: 'Course view',
                selected: 'all',
                options: const [
                  V3PickerOption(
                    value: 'all',
                    label: 'All sessions',
                    description: 'See the complete adaptive path.',
                    icon: Icons.route_rounded,
                  ),
                  V3PickerOption(
                    value: 'current',
                    label: 'Current unit',
                    description: 'Keep the next lesson close at hand.',
                    icon: Icons.flag_outlined,
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              language.roadmapHint,
              style: DesignTokens.body(
                12,
              ).copyWith(color: DesignTokens.nightMuted),
            ),
          ),
          const SizedBox(height: 20),
          V3Card(
            raised: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.route_rounded, color: DesignTokens.nightAccent),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${roadmap.completedCount} of ${roadmap.sessions.length} sessions complete · ${units.length} units',
                        style: DesignTokens.body(
                          14,
                          weight: FontWeight.w700,
                        ).copyWith(color: DesignTokens.nightText),
                      ),
                    ),
                    Text(
                      '${(roadmap.progress * 100).round()}%',
                      style: DesignTokens.body(
                        12,
                        weight: FontWeight.w700,
                      ).copyWith(color: DesignTokens.nightAccent),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    value: roadmap.progress,
                    minHeight: 8,
                    backgroundColor: DesignTokens.nightHairline,
                    valueColor: AlwaysStoppedAnimation(
                      DesignTokens.nightAccent,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          for (final unit in units) ...[
            _unitHeader(roadmap, unit),
            const SizedBox(height: 10),
            _unitPath(context, roadmap, unit, locked: courseLocked),
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
          ).copyWith(color: DesignTokens.nightAccent, letterSpacing: 1),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            session.unitTitle,
            style: DesignTokens.display(
              20,
            ).copyWith(color: DesignTokens.nightText),
          ),
        ),
      ],
    );
  }

  Widget _unitPath(
    BuildContext context,
    SpeakRoadmap roadmap,
    int unit, {
    required bool locked,
  }) {
    final sessions = roadmap.sessions
        .where((session) => session.unit == unit)
        .toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = constraints.maxWidth * 0.84;
        return Stack(
          children: [
            Positioned(
              top: 12,
              bottom: 12,
              left: constraints.maxWidth / 2,
              child: Container(width: 1, color: DesignTokens.nightHairline),
            ),
            Column(
              children: [
                for (var index = 0; index < sessions.length; index++) ...[
                  Align(
                    alignment: index.isEven
                        ? Alignment.centerLeft
                        : Alignment.centerRight,
                    child: SizedBox(
                      width: cardWidth,
                      child: _sessionTile(
                        context,
                        sessions[index],
                        featured:
                            sessions[index].index == roadmap.nextSession?.index,
                        locked: locked,
                      ),
                    ),
                  ),
                  if (index != sessions.length - 1) const SizedBox(height: 10),
                ],
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _sessionTile(
    BuildContext context,
    SpeakRoadmapSession session, {
    required bool featured,
    required bool locked,
  }) {
    final active = featured && !session.completed;
    final stateIcon = locked
        ? Icons.lock_outline_rounded
        : session.completed
        ? Icons.check_circle_rounded
        : Icons.arrow_forward_ios_rounded;
    final stateColor = active
        ? DesignTokens.nightAccent
        : DesignTokens.nightMuted;
    return Semantics(
      button: true,
      label:
          '${session.title}, ${session.primarySkill.label}, ${session.completed
              ? 'completed'
              : locked
              ? 'locked'
              : 'available'}',
      child: V3Card(
        raised: active,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        borderColor: active
            ? DesignTokens.nightAccent
            : DesignTokens.nightHairline,
        onTap: () => AppRouter.push(context, (_) => _screenFor(session)),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: active
                    ? DesignTokens.nightAccentSoft
                    : DesignTokens.nightSurfaceRaised,
                shape: BoxShape.circle,
              ),
              child: Icon(
                session.completed
                    ? Icons.check_rounded
                    : _iconFor(session.primarySkill),
                size: 19,
                color: active
                    ? DesignTokens.nightAccent
                    : DesignTokens.nightMuted,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                session.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: DesignTokens.display(
                  15,
                ).copyWith(color: DesignTokens.nightText),
              ),
            ),
            const SizedBox(width: 8),
            Icon(stateIcon, size: 19, color: stateColor),
          ],
        ),
      ),
    );
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
