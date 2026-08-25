// The legacy detail helpers in this file remain available for existing deep
// links while the dashboard route delegates to the independent catalog.
// ignore_for_file: unused_element

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/app_router.dart';
import '../../design/tokens.dart';
import '../../models/speak_curriculum.dart';
import '../../models/tutor_persona.dart';
import '../../services/review_material_service.dart';
import '../../services/speak_roadmap_service.dart';
import 'speak_course_activity_screen.dart';
import 'speak_free_talk_screen.dart';
import 'speak_quick_practice_screen.dart';
import 'speak_review_screen.dart';
import 'speak_settings_screen.dart';
import 'speaking_practice_screen.dart';
import 'speaking_course_home_screen.dart';
import 'speaking_lesson_flow_screen.dart';

/// The speaking product surface.
///
/// This route stays independent from the app Home and Course roadmap. The
/// preserved catalog owns the beginner speaking lessons and the extra
/// speaking practice entry points; the shared lesson engine remains below.
class SpeakingHubScreen extends ConsumerStatefulWidget {
  const SpeakingHubScreen({super.key, this.initialCourseTab = true});

  /// Kept for source compatibility with older entry points. Speaking no
  /// longer has a top-level Course/Practice switch.
  @Deprecated('Speaking now uses its independent lesson catalog.')
  final bool initialCourseTab;

  @override
  ConsumerState<SpeakingHubScreen> createState() => _SpeakingHubScreenState();
}

class _SpeakingHubScreenState extends ConsumerState<SpeakingHubScreen> {
  String _selectedActivity = 'Tutor lesson';

  @override
  Widget build(BuildContext context) {
    return const SpeakingCourseHomeScreen();
  }

  Widget _topBar(BuildContext context) {
    return Row(
      children: [
        _iconButton(
          icon: Icons.arrow_back_rounded,
          label: 'Back',
          onTap: () => Navigator.of(context).maybePop(),
        ),
        const Spacer(),
        Row(
          children: [
            Icon(
              Icons.local_fire_department_rounded,
              color: DesignTokens.nightAccent,
              size: 18,
            ),
            const SizedBox(width: 5),
            Text('7', style: _body(14, weight: FontWeight.w700)),
          ],
        ),
        const SizedBox(width: 10),
        _iconButton(
          icon: Icons.tune_rounded,
          label: 'Speaking settings',
          onTap: () =>
              AppRouter.push(context, (_) => const SpeakSettingsScreen()),
        ),
      ],
    );
  }

  Widget _unitHeader(SpeakRoadmapSession selected, SpeakRoadmap roadmap) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionLabel('UNIT ${selected.unit}'),
              const SizedBox(height: 5),
              Text(selected.unitTitle, style: _display(22)),
            ],
          ),
        ),
        Text(
          '${roadmap.completedCount}/${roadmap.sessions.length}',
          style: _body(13).copyWith(color: DesignTokens.nightMuted),
        ),
      ],
    );
  }

  Widget _selectedLessonCard(
    BuildContext context,
    SpeakRoadmapSession session,
  ) {
    final tutor = ActiveTutor.current;
    final prompt = session.targetPhrases.isNotEmpty
        ? session.targetPhrases.first
        : session.competency;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: DesignTokens.nightAccentSoft,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: DesignTokens.nightAccent, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 54,
                height: 54,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: DesignTokens.nightAccent,
                  shape: BoxShape.circle,
                ),
                child: ClipOval(
                  child: Image.asset(tutor.portraitAsset, fit: BoxFit.cover),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: _body(17, weight: FontWeight.w800),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${tutor.displayName} · ${session.level} · ${session.estimatedMinutes} min',
                      style: _body(12).copyWith(color: DesignTokens.nightMuted),
                    ),
                  ],
                ),
              ),
              Icon(
                session.completed
                    ? Icons.check_circle_rounded
                    : Icons.more_horiz_rounded,
                color: DesignTokens.nightAccent,
              ),
            ],
          ),
          if (prompt.trim().isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              prompt,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: _body(15, weight: FontWeight.w700),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              for (final activity in const [
                ('Tutor lesson', Icons.play_circle_outline_rounded),
                ('Speaking drill', Icons.mic_none_rounded),
                ('Tutor Q&A', Icons.forum_outlined),
              ]) ...[
                Expanded(
                  child: _activityButton(
                    label: activity.$1,
                    icon: activity.$2,
                    selected: _selectedActivity == activity.$1,
                    onTap: () =>
                        setState(() => _selectedActivity = activity.$1),
                  ),
                ),
                if (activity.$1 != 'Tutor Q&A') const SizedBox(width: 7),
              ],
            ],
          ),
          const SizedBox(height: 14),
          _goldButton(
            label: session.completed ? 'Practise again' : 'Start lesson',
            onTap: () => _startSelectedActivity(context, session),
          ),
        ],
      ),
    );
  }

  Future<void> _startSelectedActivity(
    BuildContext context,
    SpeakRoadmapSession session,
  ) async {
    if (_selectedActivity == 'Speaking drill' &&
        session.primarySkill == SpeakSkill.speaking) {
      await AppRouter.push(
        context,
        (_) => SpeakingLessonFlowScreen(
          title: session.title,
          topic: session.subtitle,
          level: session.level,
          contentKey: session.contentKey,
          steps: speakingStepsForLesson(
            targets: session.targetPhrases,
            title: session.title,
            competency: session.competency,
            level: session.level,
          ),
        ),
        fullscreenDialog: true,
      );
      return;
    }
    if (_selectedActivity == 'Tutor Q&A') {
      await AppRouter.push(
        context,
        (_) => SpeakingPracticeScreen(
          request: SpeakingPracticeRequest(
            mode: SpeakingMode.guidedConversation,
            topic: session.title,
            level: session.level,
            goal: 'Answer one question clearly',
            durationMinutes: session.estimatedMinutes.clamp(5, 12).toInt(),
            lessonContext: session.contextPrompt,
            sessionTopic: session.title,
            contentKey: session.contentKey,
          ),
          autoStart: true,
        ),
        fullscreenDialog: true,
      );
      return;
    }
    await AppRouter.push(
      context,
      (_) => SpeakCourseActivityScreen(session: session),
      fullscreenDialog: true,
    );
  }

  Widget _quickPracticeSection(
    BuildContext context,
    SpeakRoadmapSession? selected,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('QUICK PRACTICE'),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _quickCard(
                icon: Icons.mic_none_rounded,
                title: 'Guided drill',
                subtitle: 'One phrase at a time',
                onTap:
                    selected == null ||
                        selected.primarySkill != SpeakSkill.speaking
                    ? null
                    : () => _startGuided(context, selected),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _quickCard(
                icon: Icons.chat_bubble_outline_rounded,
                title: 'Free talk',
                subtitle: 'Choose a real scene',
                onTap: () => AppRouter.push(
                  context,
                  (_) => const SpeakFreeTalkScreen(),
                  fullscreenDialog: true,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _quickCard(
          icon: Icons.theater_comedy_outlined,
          title: 'Roleplay topics',
          subtitle:
              'Hot · New · Top today · cafés, travel, shops, and everyday scenes',
          onTap: () => AppRouter.push(
            context,
            (_) => const SpeakFreeTalkScreen(),
            fullscreenDialog: true,
          ),
          wide: true,
        ),
        const SizedBox(height: 10),
        _quickCard(
          icon: Icons.bolt_rounded,
          title: 'Quick lessons',
          subtitle: 'Vocabulary and verbs for a focused practice minute',
          onTap: () => AppRouter.push(
            context,
            (_) => const SpeakQuickPracticeScreen(),
            fullscreenDialog: true,
          ),
          wide: true,
        ),
      ],
    );
  }

  Future<void> _startGuided(
    BuildContext context,
    SpeakRoadmapSession session,
  ) async {
    await AppRouter.push(
      context,
      (_) => SpeakingLessonFlowScreen(
        title: session.title,
        topic: session.subtitle,
        level: session.level,
        contentKey: session.contentKey,
        steps: speakingStepsForLesson(
          targets: session.targetPhrases,
          title: session.title,
          competency: session.competency,
          level: session.level,
        ),
      ),
      fullscreenDialog: true,
    );
  }

  Widget _quickCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
    bool wide = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: BoxConstraints(minHeight: wide ? 74 : 112),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: DesignTokens.nightSurface,
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: DesignTokens.nightHairline),
        ),
        child: wide
            ? Row(
                children: [
                  Icon(icon, color: DesignTokens.nightAccent, size: 24),
                  const SizedBox(width: 12),
                  Expanded(child: _quickCopy(title, subtitle)),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: DesignTokens.nightAccent,
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Icon(icon, color: DesignTokens.nightAccent, size: 24),
                  _quickCopy(title, subtitle),
                ],
              ),
      ),
    );
  }

  Widget _quickCopy(String title, String subtitle) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: _body(14, weight: FontWeight.w800)),
      const SizedBox(height: 3),
      Text(
        subtitle,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: _body(11).copyWith(color: DesignTokens.nightMuted),
      ),
    ],
  );

  Widget _activityButton({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 58,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          decoration: BoxDecoration(
            color: selected
                ? DesignTokens.nightAccent
                : DesignTokens.nightSurface,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: selected
                  ? DesignTokens.nightAccent
                  : DesignTokens.nightHairline,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 17,
                color: selected ? Colors.black : DesignTokens.nightAccent,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _body(9, weight: FontWeight.w700).copyWith(
                  color: selected ? Colors.black : DesignTokens.nightText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _lessonCard(
    SpeakRoadmapSession session, {
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? DesignTokens.nightAccentSoft
              : DesignTokens.nightSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? DesignTokens.nightAccent
                : DesignTokens.nightHairline,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: selected
                    ? DesignTokens.nightAccent
                    : DesignTokens.nightSurfaceRaised,
                shape: BoxShape.circle,
              ),
              child: Icon(
                session.completed
                    ? Icons.check_rounded
                    : _speakingSkillIcon(session.primarySkill),
                color: selected ? Colors.black : DesignTokens.nightAccent,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    session.title,
                    style: _body(15, weight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${session.level} · ${session.estimatedMinutes} min',
                    style: _body(12).copyWith(color: DesignTokens.nightMuted),
                  ),
                ],
              ),
            ),
            Icon(
              session.completed
                  ? Icons.check_circle_rounded
                  : Icons.chevron_right_rounded,
              color: selected
                  ? DesignTokens.nightAccent
                  : DesignTokens.nightMuted,
            ),
          ],
        ),
      ),
    );
  }

  Widget _recentRow(BuildContext context, ReviewSessionSummary session) {
    return GestureDetector(
      onTap: () => AppRouter.push(
        context,
        (_) => SavedSpeakingTranscriptScreen(session: session),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: DesignTokens.nightSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: DesignTokens.nightHairline),
        ),
        child: Row(
          children: [
            Icon(Icons.history_rounded, color: DesignTokens.nightAccent),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                session.topic,
                style: _body(14, weight: FontWeight.w700),
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: DesignTokens.nightMuted),
          ],
        ),
      ),
    );
  }

  Widget _emptyPanel(String message) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: DesignTokens.nightSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DesignTokens.nightHairline),
      ),
      child: Text(
        message,
        style: _body(13).copyWith(color: DesignTokens.nightMuted),
      ),
    );
  }

  Widget _sectionLabel(String label) => Text(
    label,
    style: _body(
      12,
      weight: FontWeight.w800,
    ).copyWith(color: DesignTokens.nightAccent, letterSpacing: 1.4),
  );

  Widget _iconButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, color: DesignTokens.nightText, size: 22),
        ),
      ),
    );
  }

  Widget _goldButton({required String label, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: DesignTokens.nightAccent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: _body(
            15,
            weight: FontWeight.w800,
          ).copyWith(color: Colors.black),
        ),
      ),
    );
  }

  TextStyle _display(double size) =>
      DesignTokens.display(size).copyWith(color: DesignTokens.nightText);

  TextStyle _body(double size, {FontWeight weight = FontWeight.w400}) =>
      DesignTokens.body(
        size,
        weight: weight,
      ).copyWith(color: DesignTokens.nightText);
}

/// The course lesson card that was previously skipped by the auto-start route.
class SpeakingLessonDetailScreen extends ConsumerWidget {
  const SpeakingLessonDetailScreen({
    super.key,
    required this.session,
    this.onStart,
  });

  final SpeakRoadmapSession session;
  final VoidCallback? onStart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tutor = ActiveTutor.current;
    final prompt = session.targetPhrases.isNotEmpty
        ? session.targetPhrases.first
        : session.competency;
    return _SpeakingDarkPage(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
        children: [
          _pageHeader(
            context,
            title: 'Speaking',
            trailing: Icon(
              Icons.bookmark_border_rounded,
              color: DesignTokens.nightText,
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: Container(
              width: 82,
              height: 82,
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: DesignTokens.nightAccent,
                shape: BoxShape.circle,
              ),
              child: ClipOval(
                child: Image.asset(tutor.portraitAsset, fit: BoxFit.cover),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            session.title,
            textAlign: TextAlign.center,
            style: _detailDisplay(28),
          ),
          const SizedBox(height: 5),
          Text(
            '${tutor.displayName} · ${session.level} · ${session.primarySkill.label}',
            textAlign: TextAlign.center,
            style: _detailBody(14).copyWith(color: DesignTokens.nightMuted),
          ),
          const SizedBox(height: 24),
          _quoteCard(prompt),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: DesignTokens.nightSurface,
              borderRadius: BorderRadius.circular(17),
              border: Border.all(color: DesignTokens.nightHairline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'THIS LESSON',
                  style: _detailBody(11, weight: FontWeight.w800).copyWith(
                    color: DesignTokens.nightAccent,
                    letterSpacing: 1.3,
                  ),
                ),
                const SizedBox(height: 10),
                _detailRow(
                  Icons.play_circle_outline_rounded,
                  'Tutor lesson',
                  'Hear the model before you speak.',
                ),
                _detailRow(
                  Icons.mic_none_rounded,
                  'Speaking drill',
                  'Repeat the target, then use it in context.',
                ),
                _detailRow(
                  Icons.forum_outlined,
                  'Tutor Q&A',
                  'Continue the lesson in one live chat.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _goldAction(
            label: 'Start lesson',
            onTap: onStart ?? () => _startLesson(context),
          ),
        ],
      ),
    );
  }

  void _startLesson(BuildContext context) {
    if (session.primarySkill == SpeakSkill.speaking) {
      AppRouter.push(
        context,
        (_) => SpeakingLessonFlowScreen(
          title: session.title,
          topic: session.subtitle,
          level: session.level,
          contentKey: session.contentKey,
          steps: speakingStepsForLesson(
            targets: session.targetPhrases,
            title: session.title,
            competency: session.competency,
            level: session.level,
          ),
        ),
        fullscreenDialog: true,
      );
      return;
    }
    AppRouter.push(
      context,
      (_) => SpeakingPracticeScreen(request: _request, autoStart: true),
      fullscreenDialog: true,
    );
  }

  SpeakingPracticeRequest get _request => SpeakingPracticeRequest(
    mode: session.primarySkill == SpeakSkill.roleplay
        ? SpeakingMode.roleplay
        : SpeakingMode.guidedConversation,
    topic: session.title,
    level: session.level,
    goal: 'Fluency',
    durationMinutes: session.estimatedMinutes.clamp(5, 20).toInt(),
    lessonContext: session.contextPrompt,
    sessionTopic: session.title,
    contentKey: session.contentKey,
  );
}

class SpeakingRoleplayDetailScreen extends StatelessWidget {
  const SpeakingRoleplayDetailScreen({super.key, required this.scene});

  final SpeakRoleplayScene scene;

  @override
  Widget build(BuildContext context) {
    return _SpeakingDarkPage(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
        children: [
          _pageHeader(
            context,
            title: 'Roleplay',
            trailing: Icon(
              Icons.favorite_border_rounded,
              color: DesignTokens.nightText,
            ),
          ),
          const SizedBox(height: 24),
          Container(
            height: 170,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: DesignTokens.nightAccentSoft,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  'ROLEPLAY',
                  style: _detailBody(12, weight: FontWeight.w800).copyWith(
                    color: DesignTokens.nightAccent,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 10),
                Text(scene.location, style: _detailDisplay(25)),
              ],
            ),
          ),
          const SizedBox(height: 22),
          Text(scene.title, style: _detailDisplay(30)),
          const SizedBox(height: 6),
          Text(
            scene.subtitle,
            style: _detailBody(15).copyWith(color: DesignTokens.nightMuted),
          ),
          const SizedBox(height: 22),
          Text(
            'IN THIS ROLEPLAY',
            style: _detailBody(
              12,
              weight: FontWeight.w800,
            ).copyWith(color: DesignTokens.nightAccent, letterSpacing: 1.3),
          ),
          const SizedBox(height: 10),
          _roleCard(
            Icons.person_outline_rounded,
            'Your role',
            scene.learnerRole,
          ),
          _roleCard(
            Icons.record_voice_over_outlined,
            'Tutor role',
            scene.tutorRole,
          ),
          _roleCard(Icons.auto_awesome_rounded, 'Your goal', scene.goal),
          const SizedBox(height: 22),
          Text(
            'TRY SAYING',
            style: _detailBody(
              12,
              weight: FontWeight.w800,
            ).copyWith(color: DesignTokens.nightAccent, letterSpacing: 1.3),
          ),
          const SizedBox(height: 10),
          for (final phrase in scene.targetPhrases.take(4)) _phraseRow(phrase),
          const SizedBox(height: 18),
          _goldAction(label: 'Start roleplay', onTap: () => _start(context)),
        ],
      ),
    );
  }

  void _start(BuildContext context) {
    AppRouter.push(
      context,
      (_) => SpeakingPracticeScreen(
        request: SpeakingPracticeRequest(
          mode: SpeakingMode.roleplay,
          topic: scene.title,
          level: scene.level,
          goal: 'Fluency',
          durationMinutes: 10,
          lessonContext: scene.lessonContext,
          sessionTopic: scene.title,
          contentKey: 'roleplay_${scene.id}',
          kickoffMessage: scene.kickoffMessage,
        ),
        autoStart: true,
      ),
      fullscreenDialog: true,
    );
  }
}

class _SpeakingDarkPage extends StatelessWidget {
  const _SpeakingDarkPage({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DesignTokens.nightCanvas,
      body: SafeArea(child: child),
    );
  }
}

Widget _pageHeader(
  BuildContext context, {
  required String title,
  Widget? trailing,
}) {
  return Row(
    children: [
      GestureDetector(
        onTap: () => Navigator.of(context).maybePop(),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(Icons.arrow_back_rounded, color: DesignTokens.nightText),
        ),
      ),
      Expanded(
        child: Text(
          title,
          style: _detailDisplay(17),
          textAlign: TextAlign.center,
        ),
      ),
      SizedBox(width: 44, height: 44, child: Center(child: trailing)),
    ],
  );
}

Widget _quoteCard(String text) => Container(
  padding: const EdgeInsets.all(18),
  decoration: BoxDecoration(
    color: DesignTokens.nightSurface,
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: DesignTokens.nightHairline),
  ),
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        '“',
        style: TextStyle(
          color: DesignTokens.nightAccent,
          fontSize: 32,
          height: 0.8,
        ),
      ),
      const SizedBox(width: 10),
      Expanded(child: Text(text, style: _detailDisplay(20))),
    ],
  ),
);

Widget _detailRow(IconData icon, String title, String subtitle) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
  decoration: BoxDecoration(
    color: DesignTokens.nightSurface,
    border: Border(bottom: BorderSide(color: DesignTokens.nightHairline)),
  ),
  child: Row(
    children: [
      Icon(icon, color: DesignTokens.nightAccent, size: 22),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: _detailBody(14, weight: FontWeight.w700)),
            const SizedBox(height: 3),
            Text(
              subtitle,
              style: _detailBody(12).copyWith(color: DesignTokens.nightMuted),
            ),
          ],
        ),
      ),
      Icon(Icons.chevron_right_rounded, color: DesignTokens.nightMuted),
    ],
  ),
);

Widget _roleCard(IconData icon, String title, String value) => Container(
  margin: const EdgeInsets.only(bottom: 8),
  padding: const EdgeInsets.all(14),
  decoration: BoxDecoration(
    color: DesignTokens.nightSurface,
    borderRadius: BorderRadius.circular(15),
    border: Border.all(color: DesignTokens.nightHairline),
  ),
  child: Row(
    children: [
      Icon(icon, color: DesignTokens.nightAccent, size: 22),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: _detailBody(
                12,
                weight: FontWeight.w700,
              ).copyWith(color: DesignTokens.nightMuted),
            ),
            const SizedBox(height: 3),
            Text(value, style: _detailBody(15)),
          ],
        ),
      ),
    ],
  ),
);

Widget _phraseRow(String phrase) => Container(
  margin: const EdgeInsets.only(bottom: 8),
  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
  decoration: BoxDecoration(
    color: DesignTokens.nightSurface,
    borderRadius: BorderRadius.circular(13),
    border: Border.all(color: DesignTokens.nightHairline),
  ),
  child: Row(
    children: [
      Text(
        '“',
        style: TextStyle(color: DesignTokens.nightAccent, fontSize: 24),
      ),
      const SizedBox(width: 8),
      Expanded(child: Text(phrase, style: _detailBody(14))),
      Icon(Icons.volume_up_outlined, color: DesignTokens.nightMuted, size: 19),
    ],
  ),
);

Widget _goldAction({required String label, required VoidCallback onTap}) =>
    GestureDetector(
      onTap: onTap,
      child: Container(
        height: 54,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: DesignTokens.nightAccent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: _detailBody(
            15,
            weight: FontWeight.w800,
          ).copyWith(color: Colors.black),
        ),
      ),
    );

TextStyle _detailDisplay(double size) =>
    DesignTokens.display(size).copyWith(color: DesignTokens.nightText);

TextStyle _detailBody(double size, {FontWeight weight = FontWeight.w400}) =>
    DesignTokens.body(
      size,
      weight: weight,
    ).copyWith(color: DesignTokens.nightText);

IconData _speakingSkillIcon(SpeakSkill skill) => switch (skill) {
  SpeakSkill.roleplay => Icons.forum_outlined,
  SpeakSkill.freeTalk => Icons.people_outline_rounded,
  _ => Icons.mic_none_rounded,
};
