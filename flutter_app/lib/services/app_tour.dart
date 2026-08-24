import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';

import '../design/tokens.dart';

/// Route-aware walkthroughs for the current Speak shell and live call.
///
/// The package overlay is configured as a calm spotlight: no pulsing, no
/// elastic zoom, short focus transitions, and a visible skip action. Targets
/// are real controls in the current shell rather than the retired dashboard.
class AppTour {
  AppTour._();

  static const _homeSeenKey = 'app_tour_home_seen_v1';
  static const _practiceSeenKey = 'app_tour_practice_seen_v1';
  static const _callSeenKey = 'app_tour_call_seen_v1';

  /// Set from Settings' "Replay the walkthrough" row; the Home screen checks
  /// it when Settings pops back and starts the tour immediately.
  static bool pendingHomeReplay = false;
  static bool pendingPracticeReplay = false;

  // Current shell targets — attached in MainTabScreen and the dedicated
  // speaking workspace/setup surfaces.
  static final homeTabKey = GlobalKey(debugLabel: 'tour_home_tab');
  static final nextSessionKey = GlobalKey(debugLabel: 'tour_next_session');
  static final courseTabKey = GlobalKey(debugLabel: 'tour_course_tab');
  static final practiceTabKey = GlobalKey(debugLabel: 'tour_practice_tab');
  static final photoTutorTabKey = GlobalKey(debugLabel: 'tour_photo_tutor_tab');
  static final profileTabKey = GlobalKey(debugLabel: 'tour_profile_tab');

  // Retained for the retired dashboard so old routes remain source-compatible.
  static final missionKey = nextSessionKey;
  static final keepPractisingKey = GlobalKey(
    debugLabel: 'tour_keep_practising_legacy',
  );
  static final marieKey = GlobalKey(debugLabel: 'tour_marie_legacy');

  // Call targets — attached in session_screen.dart.
  static final micModeKey = GlobalKey(debugLabel: 'tour_mic_mode');
  static final micButtonKey = GlobalKey(debugLabel: 'tour_mic_button');
  static final endCallKey = GlobalKey(debugLabel: 'tour_end_call');

  // Practice targets — attached to the current practice workspace.
  static final practiceFreeTalkKey = GlobalKey(
    debugLabel: 'tour_practice_free_talk',
  );
  static final practiceReviewKey = GlobalKey(
    debugLabel: 'tour_practice_review',
  );
  static final practiceReadingKey = GlobalKey(
    debugLabel: 'tour_practice_reading',
  );
  static final practiceListeningKey = GlobalKey(
    debugLabel: 'tour_practice_listening',
  );
  static final practiceWritingKey = GlobalKey(
    debugLabel: 'tour_practice_writing',
  );
  static final practiceGrammarKey = GlobalKey(
    debugLabel: 'tour_practice_grammar',
  );
  static final practiceVocabularyKey = GlobalKey(
    debugLabel: 'tour_practice_vocabulary',
  );
  static final practiceRoleplayKey = GlobalKey(
    debugLabel: 'tour_practice_roleplay',
  );
  static final practiceExamKey = GlobalKey(debugLabel: 'tour_practice_exam');

  static Future<bool> hasSeenHome() async =>
      (await SharedPreferences.getInstance()).getBool(_homeSeenKey) == true;

  static Future<bool> hasSeenCall() async =>
      (await SharedPreferences.getInstance()).getBool(_callSeenKey) == true;

  static Future<bool> hasSeenPractice() async =>
      (await SharedPreferences.getInstance()).getBool(_practiceSeenKey) == true;

  static Future<void> _markSeen(String key) async =>
      (await SharedPreferences.getInstance()).setBool(key, true);

  /// Marks both tours unseen so they play again — used by Settings' replay
  /// row (the call tour then re-plays on the next call too).
  static Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_homeSeenKey);
    await prefs.remove(_practiceSeenKey);
    await prefs.remove(_callSeenKey);
  }

  static Future<void> resetPractice() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_practiceSeenKey);
  }

  static Future<void> playPracticeIfNeeded(BuildContext context) async {
    final replayRequested = pendingPracticeReplay;
    pendingPracticeReplay = false;
    if (!replayRequested && await hasSeenPractice()) return;
    if (!context.mounted) return;
    playPractice(context);
  }

  static void playHome(BuildContext context) {
    _play(
      context,
      seenKey: _homeSeenKey,
      targets: [
        _target(
          key: homeTabKey,
          step: 1,
          align: ContentAlign.top,
          title: 'Home',
          body:
              'Start here each day. Home brings together your next lesson, '
              'roadmap, streak, and the fastest way back into French.',
        ),
        _target(
          key: nextSessionKey,
          step: 2,
          align: ContentAlign.top,
          title: 'Continue your course',
          body:
              'Your next lesson is ready here. Open it when you want to keep '
              'moving through the course.',
        ),
        _target(
          key: courseTabKey,
          step: 3,
          align: ContentAlign.top,
          title: 'Course',
          body:
              'See the full level-by-level path, with speaking, listening, '
              'reading, writing, grammar, and review together.',
        ),
        _target(
          key: practiceTabKey,
          step: 4,
          align: ContentAlign.top,
          title: 'Practice',
          body:
              'Repeat a skill, start Free Talk, review recent learning, or '
              'try the tutor stage whenever you need extra practice.',
        ),
        _target(
          key: photoTutorTabKey,
          step: 5,
          align: ContentAlign.top,
          title: 'Photo tutor',
          body:
              'Take a photo or upload a document and ask about the French '
              'you see in the real world.',
        ),
        _target(
          key: profileTabKey,
          step: 6,
          align: ContentAlign.top,
          title: 'Profile',
          body:
              'Change your tutor, language preferences, and account settings '
              'here.',
        ),
      ],
    );
  }

  static void playCall(BuildContext context) {
    _play(
      context,
      seenKey: _callSeenKey,
      targets: [
        _target(
          key: micModeKey,
          step: 1,
          align: ContentAlign.top,
          title: 'Auto or Hold',
          body:
              'Auto keeps the mic open, your tutor hears you as you speak. '
              'Hold is push-to-talk: press, speak, release.',
        ),
        _target(
          key: micButtonKey,
          step: 2,
          align: ContentAlign.top,
          title: 'The mic button',
          body:
              'Auto mode: tap to mute or unmute. Hold mode: press and hold '
              'this to speak.',
        ),
        _target(
          key: endCallKey,
          step: 3,
          align: ContentAlign.top,
          title: 'End the call',
          body:
              'Hang up whenever you are done. Your progress is saved '
              'automatically.',
        ),
      ],
    );
  }

  static void playPractice(BuildContext context) {
    _play(
      context,
      seenKey: _practiceSeenKey,
      targets: [
        _target(
          key: practiceFreeTalkKey,
          step: 1,
          align: _practiceAlign(
            context,
            practiceFreeTalkKey,
            preferred: ContentAlign.bottom,
          ),
          title: 'Free Talk',
          body:
              'Start an open conversation with your tutor. Choose what you '
              'want to practise without following a fixed lesson.',
        ),
        _target(
          key: practiceReviewKey,
          step: 2,
          align: _practiceAlign(
            context,
            practiceReviewKey,
            preferred: ContentAlign.bottom,
          ),
          title: 'Review',
          body:
              'Bring back recent speaking, listening, reading, writing, and '
              'roleplay learning when you want a focused refresher.',
        ),
        _target(
          key: practiceReadingKey,
          step: 3,
          align: _practiceAlign(
            context,
            practiceReadingKey,
            preferred: ContentAlign.top,
          ),
          title: 'Reading',
          body:
              'Read short stories and real-world text. New words and '
              'comprehension practice stay connected to the story.',
        ),
        _target(
          key: practiceListeningKey,
          step: 4,
          align: _practiceAlign(
            context,
            practiceListeningKey,
            preferred: ContentAlign.top,
          ),
          title: 'Listening',
          body:
              'Train your ear with spoken French, then check what you heard '
              'with guided questions and replayable audio.',
        ),
        _target(
          key: practiceWritingKey,
          step: 5,
          align: _practiceAlign(
            context,
            practiceWritingKey,
            preferred: ContentAlign.top,
          ),
          title: 'Writing',
          body:
              'Write useful French for your level and goal. The review shows '
              'what you wrote, what to improve, and what to reuse.',
        ),
        _target(
          key: practiceGrammarKey,
          step: 6,
          align: _practiceAlign(
            context,
            practiceGrammarKey,
            preferred: ContentAlign.top,
          ),
          title: 'Grammar',
          body:
              'Learn a pattern inside a small story, choose the right form, '
              'and use it in a sentence of your own.',
        ),
        _target(
          key: practiceVocabularyKey,
          step: 7,
          align: _practiceAlign(
            context,
            practiceVocabularyKey,
            preferred: ContentAlign.top,
          ),
          title: 'Vocabulary',
          body:
              'Practise level-appropriate words with pronunciation, meaning, '
              'examples, and spaced review.',
        ),
        _target(
          key: practiceRoleplayKey,
          step: 8,
          align: _practiceAlign(
            context,
            practiceRoleplayKey,
            preferred: ContentAlign.top,
          ),
          title: 'Roleplay',
          body:
              'Rehearse a real moment—at work, while travelling, or in daily '
              'life—with one turn at a time.',
        ),
        _target(
          key: practiceExamKey,
          step: 9,
          align: _practiceAlign(
            context,
            practiceExamKey,
            preferred: ContentAlign.top,
          ),
          title: 'Exam readiness',
          body:
              'Try level-aware TEF and TCF tasks. Finish first, then review '
              'your answers and feedback.',
        ),
      ],
    );
  }

  /// Chooses the side of the highlighted control that can actually contain
  /// the coachmark. The practice list has targets both near the top and near
  /// the bottom of the viewport, so one fixed alignment makes some steps
  /// render behind the status bar or below the screen.
  static ContentAlign _practiceAlign(
    BuildContext context,
    GlobalKey key, {
    required ContentAlign preferred,
  }) {
    final targetContext = key.currentContext;
    final renderObject = targetContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return preferred;
    }

    final targetOrigin = renderObject.localToGlobal(Offset.zero);
    final targetRect = targetOrigin & renderObject.size;
    final mediaQuery = MediaQuery.of(context);
    const edgeGap = 16.0;
    const estimatedCoachmarkHeight = 250.0;
    final topSpace = targetRect.top - mediaQuery.padding.top - edgeGap;
    final bottomSpace =
        mediaQuery.size.height -
        mediaQuery.padding.bottom -
        targetRect.bottom -
        edgeGap;
    final preferredSpace = preferred == ContentAlign.bottom
        ? bottomSpace
        : topSpace;
    final oppositeSpace = preferred == ContentAlign.bottom
        ? topSpace
        : bottomSpace;

    if (preferredSpace >= estimatedCoachmarkHeight ||
        preferredSpace >= oppositeSpace) {
      return preferred;
    }
    return preferred == ContentAlign.bottom
        ? ContentAlign.top
        : ContentAlign.bottom;
  }

  static void _play(
    BuildContext context, {
    required String seenKey,
    required List<TargetFocus> targets,
  }) {
    TutorialCoachMark(
      targets: targets,
      colorShadow: DesignTokens.ink,
      opacityShadow: 0.68,
      paddingFocus: 6,
      hideSkip: false,
      textSkip: 'Skip',
      focusAnimationDuration: Duration.zero,
      unFocusAnimationDuration: Duration.zero,
      pulseEnable: false,
      onFinish: () => _markSeen(seenKey),
      onSkip: () {
        _markSeen(seenKey);
        return true;
      },
    ).show(context: context);
  }

  static TargetFocus _target({
    required GlobalKey key,
    required int step,
    required String title,
    required String body,
    ContentAlign align = ContentAlign.bottom,
  }) {
    return TargetFocus(
      identify: 'step_$step',
      keyTarget: key,
      shape: ShapeLightFocus.RRect,
      radius: 18,
      enableOverlayTab: true,
      contents: [
        TargetContent(
          align: align,
          builder: (context, controller) => _TourCard(
            step: step,
            title: title,
            body: body,
            onNext: controller.next,
            onSkip: () => controller.skip(),
          ),
        ),
      ],
    );
  }
}

class _TourCard extends StatelessWidget {
  const _TourCard({
    required this.step,
    required this.title,
    required this.body,
    required this.onNext,
    required this.onSkip,
  });

  final int step;
  final String title;
  final String body;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(16),
      constraints: const BoxConstraints(maxWidth: 320),
      decoration: BoxDecoration(
        color: DesignTokens.surface,
        borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [DesignTokens.primaryDeep, DesignTokens.primary],
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  '$step',
                  style: DesignTokens.body(
                    13,
                    weight: FontWeight.w700,
                  ).copyWith(color: Colors.white),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: DesignTokens.display(17))),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: DesignTokens.body(
              13.5,
            ).copyWith(color: DesignTokens.inkSoft, height: 1.4),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: onSkip,
                child: Text(
                  'Skip tour',
                  style: DesignTokens.body(
                    13,
                    weight: FontWeight.w500,
                  ).copyWith(color: DesignTokens.mutedDim),
                ),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: DesignTokens.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(100),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                ),
                onPressed: onNext,
                child: Text(
                  'Next',
                  style: DesignTokens.body(
                    13.5,
                    weight: FontWeight.w600,
                  ).copyWith(color: Colors.white),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
