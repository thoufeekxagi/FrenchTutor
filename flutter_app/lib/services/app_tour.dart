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
  static const _callSeenKey = 'app_tour_call_seen_v1';

  /// Set from Settings' "Replay the walkthrough" row; the Home screen checks
  /// it when Settings pops back and starts the tour immediately.
  static bool pendingHomeReplay = false;

  // Current shell targets — attached in MainTabScreen and SpeakHomeScreen.
  static final nextSessionKey = GlobalKey(debugLabel: 'tour_next_session');
  static final courseTabKey = GlobalKey(debugLabel: 'tour_course_tab');
  static final practiceTabKey = GlobalKey(debugLabel: 'tour_practice_tab');
  static final progressTabKey = GlobalKey(debugLabel: 'tour_progress_tab');
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

  static Future<bool> hasSeenHome() async =>
      (await SharedPreferences.getInstance()).getBool(_homeSeenKey) == true;

  static Future<bool> hasSeenCall() async =>
      (await SharedPreferences.getInstance()).getBool(_callSeenKey) == true;

  static Future<void> _markSeen(String key) async =>
      (await SharedPreferences.getInstance()).setBool(key, true);

  /// Marks both tours unseen so they play again — used by Settings' replay
  /// row (the call tour then re-plays on the next call too).
  static Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_homeSeenKey);
    await prefs.remove(_callSeenKey);
  }

  static void playHome(BuildContext context) {
    _play(
      context,
      seenKey: _homeSeenKey,
      targets: [
        _target(
          key: nextSessionKey,
          step: 1,
          align: ContentAlign.top,
          title: 'Continue your course',
          body:
              'Your next lesson is ready here. Open it when you want to keep '
              'moving through the course.',
        ),
        _target(
          key: courseTabKey,
          step: 2,
          align: ContentAlign.top,
          title: 'Course',
          body:
              'See the full level-by-level path, with speaking, listening, '
              'reading, writing, grammar, and review together.',
        ),
        _target(
          key: practiceTabKey,
          step: 3,
          align: ContentAlign.top,
          title: 'Practice',
          body:
              'Repeat a skill, start Free Talk, review recent learning, or '
              'try the tutor stage whenever you need extra practice.',
        ),
        _target(
          key: progressTabKey,
          step: 4,
          align: ContentAlign.top,
          title: 'Progress',
          body:
              'See what you have completed and where your course is taking '
              'you next.',
        ),
        _target(
          key: profileTabKey,
          step: 5,
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
                decoration: const BoxDecoration(
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
