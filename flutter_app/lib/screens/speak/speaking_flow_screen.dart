import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/app_router.dart';
import '../../design/tokens.dart';
import '../../models/speak_curriculum.dart';
import '../../providers/database_provider.dart';
import '../../services/review_material_service.dart';
import '../../services/speak_curriculum_catalog.dart';
import '../../services/speak_roadmap_service.dart';
import 'speak_course_activity_screen.dart';
import 'speak_review_screen.dart';
import 'speaking_practice_screen.dart';

/// The speaking product surface. Course and Practice are deliberately kept in
/// one route so the learner can move from a lesson, to its drill, to a scene
/// without landing in a second legacy speaking menu.
class SpeakingHubScreen extends ConsumerStatefulWidget {
  const SpeakingHubScreen({super.key, this.initialCourseTab = true});

  final bool initialCourseTab;

  @override
  ConsumerState<SpeakingHubScreen> createState() => _SpeakingHubScreenState();
}

class _SpeakingHubScreenState extends ConsumerState<SpeakingHubScreen> {
  bool _courseTab = true;
  String _practiceMode = 'Roleplay';
  String _filter = 'Hot';

  @override
  void initState() {
    super.initState();
    _courseTab = widget.initialCourseTab;
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(learningStoreProvider).profile();
    final completed = ref.watch(storageServiceProvider).completedContentKeys();
    final plan = ref
        .read(adaptiveCourseStoreProvider)
        .ensureCurrentPlan(profile);
    final roadmap = SpeakRoadmapService.build(
      profile,
      completedContentKeys: completed,
      adaptiveSessions: plan.sessions,
    );
    final speakingLessons = roadmap.sessions
        .where(
          (session) =>
              session.primarySkill == SpeakSkill.speaking ||
              session.primarySkill == SpeakSkill.roleplay ||
              session.primarySkill == SpeakSkill.freeTalk ||
              session.supportingSkills.contains(SpeakSkill.speaking),
        )
        .take(8)
        .toList(growable: false);
    final scenes = SpeakCurriculumCatalog.bundled(roadmap.level)
        .where((item) => item.roleplay != null)
        .map((item) => item.roleplay!)
        .toList(growable: false);
    final recent =
        ReviewMaterialService.recentSessions(
          ref.watch(storageServiceProvider),
        ).where(
          (session) => const {
            'Speaking',
            'Roleplay',
            'Exam speaking',
          }.contains(session.skill),
        );

    return Scaffold(
      backgroundColor: DesignTokens.nightCanvas,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            _topBar(context),
            const SizedBox(height: 26),
            Text('Speaking', style: _display(30)),
            const SizedBox(height: 14),
            _segment(),
            const SizedBox(height: 24),
            if (_courseTab)
              _courseView(context, speakingLessons, roadmap)
            else
              _practiceView(context, scenes, roadmap.level),
            if (recent.isNotEmpty) ...[
              const SizedBox(height: 28),
              _sectionLabel('RECENT SPEAKING'),
              const SizedBox(height: 10),
              ...recent.take(3).map((session) => _recentRow(context, session)),
            ],
          ],
        ),
      ),
    );
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
            const Icon(
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
              AppRouter.push(context, (_) => const SpeakingPracticeScreen()),
        ),
      ],
    );
  }

  Widget _segment() {
    return Container(
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: DesignTokens.nightSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: DesignTokens.nightHairline),
      ),
      child: Row(
        children: [
          _segmentItem('Course', _courseTab),
          _segmentItem('Practice', !_courseTab),
        ],
      ),
    );
  }

  Widget _segmentItem(String label, bool selected) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _courseTab = label == 'Course'),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? DesignTokens.nightAccentSoft : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            style: _body(14, weight: FontWeight.w700).copyWith(
              color: selected
                  ? DesignTokens.nightText
                  : DesignTokens.nightMuted,
            ),
          ),
        ),
      ),
    );
  }

  Widget _courseView(
    BuildContext context,
    List<SpeakRoadmapSession> lessons,
    SpeakRoadmap roadmap,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _sectionLabel('THE BASICS')),
            Text(
              '${roadmap.completedCount}/${roadmap.sessions.length}',
              style: _body(13).copyWith(color: DesignTokens.nightMuted),
            ),
          ],
        ),
        const SizedBox(height: 5),
        Text(
          'Build the phrase, practise the turn, then use it in a real scene.',
          style: _body(13).copyWith(color: DesignTokens.nightMuted),
        ),
        const SizedBox(height: 12),
        if (lessons.isEmpty)
          _emptyPanel('No speaking lessons are available in this course block.')
        else
          ...lessons.map(
            (session) => _lessonRow(
              context,
              session,
              selected: session == roadmap.nextSession,
            ),
          ),
      ],
    );
  }

  Widget _practiceView(
    BuildContext context,
    List<SpeakRoleplayScene> scenes,
    String level,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _modePill('Roleplay', _practiceMode == 'Roleplay'),
            const SizedBox(width: 8),
            _modePill('Free talk', _practiceMode == 'Free talk'),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            for (final label in const ['Hot', 'New', 'Top today']) ...[
              _filterPill(label),
              const SizedBox(width: 8),
            ],
          ],
        ),
        const SizedBox(height: 22),
        if (_practiceMode == 'Free talk')
          _freeTalkPanel(context, level)
        else ...[
          _sectionLabel('YOUR ROLEPLAYS'),
          const SizedBox(height: 10),
          if (scenes.isEmpty)
            _emptyPanel('No published roleplay scenes are available.')
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: scenes.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 0.92,
              ),
              itemBuilder: (context, index) =>
                  _sceneCard(context, scenes[index]),
            ),
        ],
      ],
    );
  }

  Widget _lessonRow(
    BuildContext context,
    SpeakRoadmapSession session, {
    required bool selected,
  }) {
    final skill = session.primarySkill.label;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => AppRouter.push(
        context,
        (_) => SpeakCourseActivityScreen(session: session),
        fullscreenDialog: true,
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
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
                  const SizedBox(height: 4),
                  Text(
                    '$skill · ${session.estimatedMinutes} min',
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

  Widget _sceneCard(BuildContext context, SpeakRoleplayScene scene) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => AppRouter.push(
        context,
        (_) => SpeakingRoleplayDetailScreen(scene: scene),
        fullscreenDialog: true,
      ),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: DesignTokens.nightSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: DesignTokens.nightHairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: const BoxDecoration(
                color: DesignTokens.nightAccentSoft,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.forum_outlined,
                color: DesignTokens.nightAccent,
              ),
            ),
            const Spacer(),
            Text(
              scene.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: _body(15, weight: FontWeight.w700),
            ),
            const SizedBox(height: 5),
            Text(
              '${scene.level} · 4 turns',
              style: _body(12).copyWith(color: DesignTokens.nightMuted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _freeTalkPanel(BuildContext context, String level) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: DesignTokens.nightSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: DesignTokens.nightHairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.people_outline_rounded,
            color: DesignTokens.nightAccent,
            size: 30,
          ),
          const SizedBox(height: 14),
          Text('Talk about anything', style: _display(21)),
          const SizedBox(height: 5),
          Text(
            'Choose a topic and keep a natural conversation at $level.',
            style: _body(13).copyWith(color: DesignTokens.nightMuted),
          ),
          const SizedBox(height: 18),
          _goldButton(
            label: 'Start free talk',
            onTap: () => AppRouter.push(
              context,
              (_) => const SpeakingPracticeScreen(
                request: SpeakingPracticeRequest(mode: SpeakingMode.freeTalk),
              ),
              fullscreenDialog: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _modePill(String label, bool selected) {
    return GestureDetector(
      onTap: () => setState(() => _practiceMode = label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? DesignTokens.nightAccent
              : DesignTokens.nightSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? DesignTokens.nightAccent
                : DesignTokens.nightHairline,
          ),
        ),
        child: Text(
          label,
          style: _body(
            13,
            weight: FontWeight.w700,
          ).copyWith(color: selected ? Colors.black : DesignTokens.nightMuted),
        ),
      ),
    );
  }

  Widget _filterPill(String label) {
    final selected = _filter == label;
    return GestureDetector(
      onTap: () => setState(() => _filter = label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? DesignTokens.nightAccentSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? DesignTokens.nightAccent
                : DesignTokens.nightHairline,
          ),
        ),
        child: Text(
          label,
          style: _body(12, weight: FontWeight.w600).copyWith(
            color: selected
                ? DesignTokens.nightAccent
                : DesignTokens.nightMuted,
          ),
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
            const Icon(Icons.history_rounded, color: DesignTokens.nightAccent),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                session.topic,
                style: _body(14, weight: FontWeight.w700),
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: DesignTokens.nightMuted,
            ),
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
            trailing: const Icon(
              Icons.bookmark_border_rounded,
              color: DesignTokens.nightText,
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: Container(
              width: 68,
              height: 68,
              decoration: const BoxDecoration(
                color: DesignTokens.nightAccentSoft,
                shape: BoxShape.circle,
              ),
              child: Icon(
                _speakingSkillIcon(session.primarySkill),
                color: DesignTokens.nightAccent,
                size: 32,
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
            '${session.level} · ${session.primarySkill.label}',
            textAlign: TextAlign.center,
            style: _detailBody(14).copyWith(color: DesignTokens.nightMuted),
          ),
          const SizedBox(height: 24),
          _quoteCard(prompt),
          const SizedBox(height: 12),
          _detailRow(
            Icons.video_library_outlined,
            'Tutor lesson',
            'See the idea before you speak.',
          ),
          _detailRow(
            Icons.mic_none_rounded,
            'Speaking drill',
            'Repeat the target, then use it in context.',
          ),
          _detailRow(
            Icons.translate_rounded,
            'Translate',
            'Reveal meaning without leaving the lesson.',
          ),
          const SizedBox(height: 18),
          _goldAction(
            label: 'Start lesson',
            onTap: onStart ?? () => _startLesson(context),
          ),
        ],
      ),
    );
  }

  void _startLesson(BuildContext context) {
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
            trailing: const Icon(
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
        child: const SizedBox(
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
      const Text(
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
  decoration: const BoxDecoration(
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
      const Icon(Icons.chevron_right_rounded, color: DesignTokens.nightMuted),
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
      const Text(
        '“',
        style: TextStyle(color: DesignTokens.nightAccent, fontSize: 24),
      ),
      const SizedBox(width: 8),
      Expanded(child: Text(phrase, style: _detailBody(14))),
      const Icon(
        Icons.volume_up_outlined,
        color: DesignTokens.nightMuted,
        size: 19,
      ),
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
