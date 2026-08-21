import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/app_router.dart';
import '../../design/tokens.dart';
import '../../models/speak_curriculum.dart';
import '../../providers/database_provider.dart';
import '../../services/speak_roadmap_service.dart';
import '../../services/starter_cover_resolver.dart';
import '../labs/roleplay_lab_screen.dart';
import 'speak_course_activity_screen.dart';
import 'speak_free_talk_screen.dart';

/// The actual speaking destination behind Home's Speaking rail and Practice's
/// Speaking row. It hands the learner into the existing Scene Brief and live
/// tutor engine instead of showing the Home dashboard a second time.
class SpeakingPracticeScreen extends ConsumerWidget {
  const SpeakingPracticeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(learningStoreProvider).profile();
    final completedContentKeys = ref
        .watch(storageServiceProvider)
        .completedContentKeys();
    final adaptivePlan = ref
        .read(adaptiveCourseStoreProvider)
        .ensureCurrentPlan(profile);
    final roadmap = SpeakRoadmapService.build(
      profile,
      completedContentKeys: completedContentKeys,
      adaptiveSessions: adaptivePlan.sessions,
    );
    final next = roadmap.nextSession ?? roadmap.sessions.first;
    final session = _nextSpeakingSession(roadmap, fallback: next);

    return Scaffold(
      backgroundColor: DesignTokens.nightCanvas,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            _header(context),
            const SizedBox(height: 30),
            Text('GUIDED SPEAKING', style: _eyebrow()),
            const SizedBox(height: 6),
            Text(
              'Make the next move',
              style: DesignTokens.display(
                29,
              ).copyWith(color: DesignTokens.nightText),
            ),
            const SizedBox(height: 8),
            Text(
              'See the situation, hear the goal, then speak with Marcus in a '
              'real scene.',
              style: _body(14, color: DesignTokens.nightMuted),
            ),
            const SizedBox(height: 18),
            _sceneCard(context, session),
            const SizedBox(height: 24),
            Text('OTHER WAYS TO SPEAK', style: _eyebrow()),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _actionCard(
                    icon: Icons.phone_in_talk_rounded,
                    title: 'Free talk',
                    detail: 'Choose a topic',
                    onTap: () => AppRouter.push(
                      context,
                      (_) => const SpeakFreeTalkScreen(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _actionCard(
                    icon: Icons.forum_outlined,
                    title: 'Roleplay',
                    detail: 'Enter a scene',
                    onTap: () => AppRouter.push(
                      context,
                      (_) => const RoleplayLabScreen(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: DesignTokens.nightSurface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: DesignTokens.nightHairline),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    color: DesignTokens.nightAccent,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'The next screen shows your role and goal before the '
                      'microphone opens.',
                      style: _body(12, color: DesignTokens.nightMuted),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Row(
      children: [
        IconButton(
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(
            Icons.arrow_back_rounded,
            color: DesignTokens.nightText,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          'Speaking practice',
          style: DesignTokens.display(
            21,
          ).copyWith(color: DesignTokens.nightText),
        ),
      ],
    );
  }

  Widget _sceneCard(BuildContext context, SpeakRoadmapSession session) {
    final goal = session.subtitle.trim().isEmpty
        ? session.primarySkill.description
        : session.subtitle;
    return Semantics(
      button: true,
      label: 'Start speaking ${session.title}',
      child: GestureDetector(
        onTap: () => AppRouter.push(
          context,
          (_) => SpeakCourseActivityScreen(session: session),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: SizedBox(
            height: 250,
            child: Stack(
              fit: StackFit.expand,
              children: [
                DecoratedBox(
                  decoration: const BoxDecoration(
                    color: DesignTokens.nightSurface,
                  ),
                  child: Image.asset(_coverAsset(session), fit: BoxFit.cover),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.12),
                        Colors.black.withValues(alpha: 0.9),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text('SCENE BRIEF', style: _eyebrow()),
                          const Spacer(),
                          Text(
                            '${session.estimatedMinutes} MIN',
                            style: _body(
                              11,
                              color: DesignTokens.nightText,
                              weight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      Text(
                        session.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: DesignTokens.display(
                          25,
                        ).copyWith(color: DesignTokens.nightText),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        goal,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: _body(
                          13,
                          color: DesignTokens.nightText.withValues(alpha: 0.86),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Text(
                            '${session.level}  ·  ${session.primarySkill.label}',
                            style: _body(12, color: DesignTokens.nightMuted),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 13,
                              vertical: 9,
                            ),
                            decoration: BoxDecoration(
                              color: DesignTokens.nightAccent,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Text(
                              'Start speaking  →',
                              style: _body(
                                12,
                                color: Colors.black,
                                weight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _actionCard({
    required IconData icon,
    required String title,
    required String detail,
    required VoidCallback onTap,
  }) {
    return Semantics(
      button: true,
      label: '$title, $detail',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 104),
          padding: const EdgeInsets.fromLTRB(13, 13, 10, 12),
          decoration: BoxDecoration(
            color: DesignTokens.nightSurface,
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: DesignTokens.nightHairline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: DesignTokens.nightAccent, size: 21),
              const Spacer(),
              Text(title, style: _body(13, weight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text(detail, style: _body(11, color: DesignTokens.nightMuted)),
            ],
          ),
        ),
      ),
    );
  }

  TextStyle _eyebrow() => DesignTokens.body(
    11,
    weight: FontWeight.w700,
  ).copyWith(color: DesignTokens.nightAccent, letterSpacing: 1.2);

  TextStyle _body(
    double size, {
    Color? color,
    FontWeight weight = FontWeight.w400,
  }) => DesignTokens.body(
    size,
    weight: weight,
  ).copyWith(color: color ?? DesignTokens.nightText);
}

SpeakRoadmapSession _nextSpeakingSession(
  SpeakRoadmap roadmap, {
  required SpeakRoadmapSession fallback,
}) {
  for (final session in roadmap.sessions) {
    if (session.primarySkill == SpeakSkill.speaking ||
        session.primarySkill == SpeakSkill.roleplay ||
        session.primarySkill == SpeakSkill.freeTalk) {
      return session;
    }
  }
  return fallback;
}

String _coverAsset(SpeakRoadmapSession session) {
  final resolved = StarterCoverResolver.resolve(title: session.title);
  if (resolved != null && resolved.startsWith('asset:')) {
    return resolved.substring('asset:'.length);
  }
  return switch (session.index % 4) {
    0 => 'assets/starter_covers/market.png',
    1 => 'assets/starter_covers/station.png',
    2 => 'assets/starter_covers/lantern.png',
    _ => 'assets/starter_covers/boat.png',
  };
}
