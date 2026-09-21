import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/api_keys.dart';
import '../../design/app_router.dart';
import '../../design/tokens.dart';
import '../../providers/database_provider.dart';
import '../../services/ai_session_gate.dart';
import '../../widgets/live_tutor_mascot.dart';
import '../session/session_screen.dart';

/// Minimal setup for the new Live tutor experience. The existing free-talk
/// launcher remains available elsewhere; Home's quick-start card enters here.
class LiveTutorSetupScreen extends ConsumerStatefulWidget {
  const LiveTutorSetupScreen({super.key});

  @override
  ConsumerState<LiveTutorSetupScreen> createState() =>
      _LiveTutorSetupScreenState();
}

class _LiveTutorSetupScreenState extends ConsumerState<LiveTutorSetupScreen> {
  static const _styles = ['Light tease', 'Sharp', 'Theatrical'];
  static const _topics = ['French vocabulary', 'Daily life', 'Travel'];

  late String _level;
  var _style = 'Sharp';
  var _topic = 'French vocabulary';
  var _starting = false;

  @override
  void initState() {
    super.initState();
    final stored = ref
        .read(learningStoreProvider)
        .profile()
        .level
        .toUpperCase();
    _level = const {'A1', 'A2', 'B1', 'B2'}.contains(stored) ? stored : 'A2';
  }

  Future<void> _start() async {
    if (_starting) return;
    setState(() => _starting = true);

    final allowed = await ensureAiSessionQuota(
      context,
      ref.read(pilotAccessServiceProvider),
    );
    if (!allowed || !mounted) {
      if (mounted) setState(() => _starting = false);
      return;
    }

    final profile = ref.read(learningStoreProvider).profile();
    final courseStore = ref.read(adaptiveCourseStoreProvider);
    final coursePlan =
        courseStore.currentPlan(profile) ??
        courseStore.ensureCurrentPlan(profile);
    final currentCourseLesson = coursePlan.nextSession;

    String compact(String value, int maxCharacters) {
      final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (normalized.length <= maxCharacters) return normalized;
      return '${normalized.substring(0, maxCharacters - 1)}…';
    }

    final courseBridge = currentCourseLesson == null
        ? 'No current course bridge is available.'
        : [
            'Current course focus: ${compact(currentCourseLesson.title, 80)}.',
            'Skill: ${compact(currentCourseLesson.competency, 120)}.',
            if (currentCourseLesson.targetPhrases.isNotEmpty)
              'Optional phrase anchors: ${currentCourseLesson.targetPhrases.take(2).map((phrase) => compact(phrase, 44)).join('; ')}.',
            if (currentCourseLesson.grammarFocus.isNotEmpty)
              'Optional pattern: ${compact(currentCourseLesson.grammarFocus.first, 80)}.',
          ].join(' ');

    final contextNote =
        '''
LIVE TUTOR SETUP
Selected CEFR level: $_level.
Selected delivery style: $_style.
Starting topic: $_topic.

OPTIONAL CURRENT COURSE BRIDGE
$courseBridge

This is independent open conversation. Use the course bridge only when it fits
naturally; do not force it or turn the call into a scripted lesson. Follow the
learner's questions and direction, create new useful vocabulary when helpful,
and let them change topics freely. Keep corrections short, playful, and never
insult the learner, intelligence, identity, accent, or personal traits.
'''
            .trim();

    await AppRouter.push(
      context,
      (_) => SessionScreen(
        apiKey: ApiKeys.geminiKey,
        stage: 'live_tutor',
        sessionTopic: _topic,
        levelOverride: _level,
        lessonContext: contextNote,
        lessonContextCharacterLimit: 1400,
        kickoffMessage:
            '(START NOW. Speak first without waiting for the learner. Open in '
            'French with a brief natural introduction such as "Bonjour, je suis '
            'Marie, ta tutrice de français. Aujourd\'hui, on va pratiquer '
            '$_topic." Then ask one short, level-matched question about $_topic. '
            'Use the selected $_style delivery. Stop after that first turn and '
            'wait for the learner.)',
        liveTutorMode: true,
        liveTutorLessonTitle: _topic,
      ),
      fullscreenDialog: true,
    );

    if (mounted) setState(() => _starting = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DesignTokens.nightCanvas,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 20, 0),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Back',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: Icon(
                      Icons.arrow_back_rounded,
                      color: DesignTokens.nightText,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'Live tutor',
                    style: DesignTokens.label(11, weight: FontWeight.w800)
                        .copyWith(
                          color: DesignTokens.nightAccent,
                          letterSpacing: 1.3,
                        ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: Column(
                  children: [
                    const SizedBox(height: 8),
                    const LiveTutorMascot(size: 172),
                    const SizedBox(height: 28),
                    _selector(
                      label: 'Level',
                      value: _level,
                      options: const ['A1', 'A2', 'B1', 'B2'],
                      onSelected: (value) => setState(() => _level = value),
                    ),
                    const SizedBox(height: 10),
                    _selector(
                      label: 'Style',
                      value: _style,
                      options: _styles,
                      onSelected: (value) => setState(() => _style = value),
                    ),
                    const SizedBox(height: 10),
                    _selector(
                      label: 'Topic',
                      value: _topic,
                      options: _topics,
                      onSelected: (value) => setState(() => _topic = value),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: _starting ? null : _start,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: DesignTokens.nightAccent,
                    foregroundColor: DesignTokens.onPrimary,
                    disabledBackgroundColor: DesignTokens.nightAccent
                        .withValues(alpha: 0.45),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    elevation: 0,
                  ),
                  child: _starting
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: DesignTokens.onPrimary,
                          ),
                        )
                      : Text(
                          'Start',
                          style: DesignTokens.body(
                            16,
                            weight: FontWeight.w800,
                          ).copyWith(color: DesignTokens.onPrimary),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _selector({
    required String label,
    required String value,
    required List<String> options,
    required ValueChanged<String> onSelected,
  }) {
    return PopupMenuButton<String>(
      onSelected: onSelected,
      color: DesignTokens.nightSurfaceRaised,
      position: PopupMenuPosition.over,
      itemBuilder: (context) => [
        for (final option in options)
          PopupMenuItem<String>(
            value: option,
            child: Text(
              option,
              style: DesignTokens.body(
                14,
              ).copyWith(color: DesignTokens.nightText),
            ),
          ),
      ],
      child: Container(
        height: 54,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: DesignTokens.nightCanvas,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: DesignTokens.nightAccent.withValues(alpha: 0.7),
          ),
        ),
        child: Row(
          children: [
            Text(
              label,
              style: DesignTokens.body(
                14,
              ).copyWith(color: DesignTokens.nightMuted),
            ),
            const Spacer(),
            Text(
              value,
              style: DesignTokens.body(
                14,
                weight: FontWeight.w700,
              ).copyWith(color: DesignTokens.nightText),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 20,
              color: DesignTokens.nightAccent,
            ),
          ],
        ),
      ),
    );
  }
}
