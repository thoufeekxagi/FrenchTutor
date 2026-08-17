import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/api_keys.dart';
import '../../config/theme.dart';
import '../../design/app_router.dart';
import '../../flow/stage_outcome.dart';
import '../../models/profile.dart';
import '../../models/tutor_persona.dart';
import '../../prompts/live_prompts.dart';
import '../../providers/database_provider.dart';
import '../../services/alphabet_prewarm.dart';
import '../../services/trial_call_gate.dart';
import '../../services/tutor_voice_preview.dart';
import '../../widgets/adaptive/adaptive.dart';
import '../../widgets/web/web_onboarding_question.dart';
import '../../widgets/web/web_onboarding_welcome.dart';
import '../../widgets/web/web_preparing_pane.dart';
import '../session/session_screen.dart';
import 'widgets/apple_goal_view.dart';
import 'widgets/apple_level_view.dart';
import 'widgets/apple_welcome_view.dart';

/// Onboarding funnel — Readle's proven anatomy, ParleSprint's palette:
///   0. gradient social-proof welcome (trust before any question)
///   1-3. goal / level / tutor (the three questions)
///   4. animated "preparing your plan" — circular progress replaying the
///      learner's own choices as checkmarks (the personalization moment)
///   5. the product BEFORE the account: a free 3-minute live call with the
///      chosen tutor (single-use, hard-capped — TrialCallGate)
///   6. recap of what they just spoke — then, and only then, the sign-in gate.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key, required this.onFinished});

  /// Called after the profile is saved. The hosting [AuthGate] re-evaluates
  /// and shows the next gate (sign-in for a fresh learner, home if already
  /// signed in) — onboarding never navigates on its own, so the gate always
  /// stays mounted and in control.
  final VoidCallback onFinished;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen>
    with SingleTickerProviderStateMixin {
  final _pageController = PageController();
  late final AnimationController _brandController;
  late final TutorVoicePreviewer _previewer;
  int _page = 0;
  String? _goal;
  String? _level;
  String _sessionLength = 'standard';
  final Set<String> _interests = {};
  TutorPersona? _tutorChoice;
  bool _trialAvailable = false;
  bool _startingTrial = false;
  SpeakingResult? _trialResult;
  bool _finished = false;

  // Fixed page indices (recap stays in the tree; it is only ever reached
  // after a connected trial call).
  static const _pageGoal = 1;
  static const _pageLevel = 2;
  static const _pageInterests = 3;
  static const _pageTutor = 4;
  static const _pagePreparing = 5;

  @override
  void initState() {
    super.initState();
    _brandController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..forward();
    _previewer = TutorVoicePreviewer()
      ..addListener(() {
        if (mounted) setState(() {});
      });
    TrialCallGate.isAvailable().then((available) {
      if (mounted) setState(() => _trialAvailable = available);
    });
  }

  @override
  void dispose() {
    _brandController.dispose();
    _previewer.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _next() {
    _previewer.stop();
    PSHaptics.selection();
    _pageController.nextPage(
      duration: DesignTokens.durationMedium,
      curve: DesignTokens.curveStandard,
    );
  }

  void _finish() {
    if (_finished) return; // preparing-pane callback + skip can race a tap
    _finished = true;
    final store = ref.read(learningStoreProvider);
    final Profile profile = store.profile()
      ..goal = _goal ?? 'unsure'
      ..level = _level ?? 'unsure'
      ..sessionLength = _sessionLength
      ..interests = _interests.toList()
      ..onboardedAt = DateTime.now();
    store.saveProfile(profile);
    ActiveTutor.set(_tutorChoice ?? TutorPersona.marie);
    // The English/French mix is derived from level instead of being its own
    // question (A1/A2 gentle, B1 balanced, B2 immersion) — adjustable anytime
    // in Settings.
    TutorTuning.saveLanguageMix(
      LearnerLevel.defaultLanguageMix(_level ?? 'a1'),
    );
    // Right here, not when the learner later taps into "Learn the
    // Alphabet" — both the level and the tutor voice are already locked in
    // at this exact moment, so this is the earliest point the alphabet's
    // sounds can be prewarmed for the voice that will actually be used.
    unawaited(AlphabetPrewarm.maybeStart(isBeginner: _level == 'a1'));
    _previewer.stop();
    PSHaptics.success();
    widget.onFinished();
  }

  TutorPersona get _tutor => _tutorChoice ?? TutorPersona.marie;

  List<String> get _preparingCheckpoints => [
    'French',
    if (_level != null) LearnerLevel.displayLabel(_level!),
    switch (_goal) {
      'tef_canada' => 'TEF / TCF Canada',
      'everyday' => 'Everyday French',
      _ => 'Foundations',
    },
    'Tutor ${_tutor.displayName}',
  ];

  void _completePreparing() {
    if (!mounted || _page != _pagePreparing) return;
    if (_trialAvailable) {
      _next();
    } else {
      _finish();
    }
  }

  /// THE web-styling switch for this screen.
  ///
  /// Mobile onboarding is a full-bleed brand gradient with white text and
  /// translucent tiles: correct for a phone, wrong for a browser. The reference
  /// design we match on web (ElevenLabs / shadcn) is a light neutral canvas with
  /// contained white cards, hairline borders and dark text. That is a styling
  /// difference, not a layout one, which is why rearranging gradient-styled
  /// widgets never got there.
  ///
  /// Every web-only visual choice in this file is gated on this one getter, so
  /// the mobile appearance is provably untouched and the web variants are easy
  /// to find. See docs/web_migration/07_web_ui_redesign.md.
  bool get _web =>
      MediaQuery.sizeOf(context).width >= DesignTokens.breakpointExpanded;

  @override
  Widget build(BuildContext context) {
    final showHeader = !_web && _page > _pageLevel && _page <= _pageTutor;
    return Scaffold(
      backgroundColor: DesignTokens.canvas,
      body: DecoratedBox(
        decoration: const BoxDecoration(color: DesignTokens.canvas),
        child: SafeArea(
          child: Column(
            children: [
              if (showHeader) ...[
                // Header gutter must match _wideStep's so the progress bar
                // lines up with the content beneath it on desktop.
                _HeaderGutter(
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                        child: Row(
                          children: [
                            const _BrandWordmark(onLightBackground: true),
                            const Spacer(),
                            Text(
                              'Step $_page of 4',
                              style: DesignTokens.body(
                                12,
                                weight: FontWeight.w600,
                              ).copyWith(color: DesignTokens.mutedDim),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(100),
                          child: Container(
                            height: 4,
                            color: DesignTokens.canvasDim,
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                return Align(
                                  alignment: Alignment.centerLeft,
                                  child: AnimatedContainer(
                                    duration: DesignTokens.durationMedium,
                                    curve: DesignTokens.curveStandard,
                                    width:
                                        constraints.maxWidth *
                                        (_page / 4).clamp(0.0, 1.0),
                                    height: 4,
                                    color: DesignTokens.primary,
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  onPageChanged: (index) => setState(() => _page = index),
                  children: [
                    _welcomeStep(),
                    _goalStep(),
                    _levelStep(),
                    _interestsStep(),
                    _tutorStep(),
                    if (_web)
                      WebPreparingPane(
                        active: _page == _pagePreparing,
                        checkpoints: _preparingCheckpoints,
                        onComplete: _completePreparing,
                      )
                    else
                      _PreparingPane(
                        active: _page == _pagePreparing,
                        checkpoints: _preparingCheckpoints,
                        onComplete: _completePreparing,
                      ),
                    _trialStep(),
                    _recapStep(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- page 0
  /// Apple-standard welcome opener with dual-bubble conversational brand mark,
  /// high-contrast value proposition, TEF/TCF trust badge, and Apple HIG actions.
  Widget _welcomeStep() {
    if (_web) return _webWelcomeStep();
    return AppleWelcomeView(
      onGetStarted: _next,
      onAlreadyHaveAccount: () {
        // Direct jump to completion/auth gate if learner already has an account
        _finish();
      },
    );
  }

  /// Web welcome pane: a split hero. Left is the promise, right is a contained
  /// card with the social proof. Neutral canvas, dark text, one azure action —
  /// the mobile version's full-bleed gradient with white text is kept for
  /// phones only.
  Widget _webWelcomeStep() => WebOnboardingWelcome(onContinue: _next);

  // ------------------------------------------------------------- pages 1-3
  Widget _step({
    required String eyebrow,
    required String title,
    String? subtitle,
    required List<Widget> children,
    required Widget footer,
  }) {
    // A browser window is far wider than it is tall, so the phone layout (hero
    // text stacked above the choices, both in one narrow column) leaves the
    // sides empty and pushes the choices below the fold. Constraining the whole
    // wizard to a phone-width strip instead — which is what was tried first —
    // just reads as a phone screenshot pasted onto a gradient, and clipped
    // content during PageView transitions on top of that.
    //
    // On a wide viewport the hero text and the choices become two columns:
    // the question stays put on the left while the answers sit at a
    // comfortable reading width on the right. Same widgets, same copy, same
    // gradient — only the arrangement changes, and only above the breakpoint.
    final isWide =
        MediaQuery.sizeOf(context).width >= DesignTokens.breakpointExpanded;
    if (isWide) return _wideStep(eyebrow, title, subtitle, children, footer);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 48),
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(top: 24, bottom: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: DesignTokens.infoSoft,
                      borderRadius: BorderRadius.circular(
                        DesignTokens.radiusMedium,
                      ),
                    ),
                    child: Icon(
                      _stepIcon,
                      color: DesignTokens.secondary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    eyebrow.toUpperCase(),
                    style: DesignTokens.label(
                      10.5,
                    ).copyWith(color: DesignTokens.mutedDim, letterSpacing: 1),
                  ),
                  const SizedBox(height: 7),
                  Text(title, style: DesignTokens.display(30)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 9),
                    Text(
                      subtitle,
                      style: DesignTokens.body(
                        15,
                      ).copyWith(color: DesignTokens.inkSoft, height: 1.45),
                    ),
                  ],
                  const SizedBox(height: 26),
                  ...children,
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          footer,
        ],
      ),
    );
  }

  /// Desktop arrangement of [_step], matching the approved welcome/auth frame:
  /// a navy route panel beside a contained neutral question card.
  Widget _wideStep(
    String eyebrow,
    String title,
    String? subtitle,
    List<Widget> children,
    Widget footer,
  ) {
    return WebOnboardingQuestion(
      step: _page,
      icon: _stepIcon,
      eyebrow: eyebrow,
      title: title,
      subtitle: subtitle,
      footer: footer,
      children: children,
    );
  }

  IconData get _stepIcon => switch (_page) {
    _pageGoal => CupertinoIcons.scope,
    _pageLevel => CupertinoIcons.slider_horizontal_3,
    _pageInterests => CupertinoIcons.heart_fill,
    _pageTutor => CupertinoIcons.person_2_fill,
    _ => CupertinoIcons.phone_fill,
  };

  Widget _onboardingButton({
    required String label,
    required VoidCallback? onPressed,
    required IconData icon,
  }) {
    final enabled = onPressed != null;
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: enabled
              ? DesignTokens.primary
              : DesignTokens.canvasDim,
          foregroundColor: enabled ? DesignTokens.surface : DesignTokens.muted,
          disabledBackgroundColor: DesignTokens.canvasDim,
          disabledForegroundColor: DesignTokens.muted,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DesignTokens.radiusMedium),
          ),
          textStyle: DesignTokens.body(15, weight: FontWeight.w700),
        ),
      ),
    );
  }

  Widget _choice({
    required String label,
    String? detail,
    required bool selected,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          PSHaptics.selection();
          onTap();
        },
        child: AnimatedContainer(
          duration: DesignTokens.durationFast,
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 68),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          decoration: BoxDecoration(
            color: selected ? DesignTokens.primarySoft : DesignTokens.surface,
            borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
            border: Border.all(
              color: selected ? DesignTokens.primary : DesignTokens.hairline,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: DesignTokens.body(15, weight: FontWeight.w700)
                          .copyWith(
                            color: selected
                                ? DesignTokens.primaryDeep
                                : DesignTokens.ink,
                          ),
                    ),
                    if (detail != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        detail,
                        style: DesignTokens.body(12.5).copyWith(
                          color: selected
                              ? DesignTokens.primaryDeep.withValues(alpha: 0.82)
                              : DesignTokens.mutedDim,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[trailing, const SizedBox(width: 10)],
              Icon(
                selected
                    ? CupertinoIcons.checkmark_circle_fill
                    : CupertinoIcons.circle,
                color: selected ? DesignTokens.primaryDeep : DesignTokens.muted,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _goalStep() {
    if (_web) {
      return _step(
        eyebrow: 'Your goal',
        title: 'What should French unlock for you?',
        children: [
          _choice(
            label: 'TEF / TCF Canada',
            selected: _goal == 'tef_canada',
            onTap: () => setState(() => _goal = 'tef_canada'),
          ),
          _choice(
            label: 'Everyday French',
            selected: _goal == 'everyday',
            onTap: () => setState(() => _goal = 'everyday'),
          ),
          _choice(
            label: 'Build the foundations',
            selected: _goal == 'unsure',
            onTap: () => setState(() => _goal = 'unsure'),
          ),
        ],
        footer: _onboardingButton(
          label: 'Continue',
          onPressed: _goal == null ? null : _next,
          icon: CupertinoIcons.arrow_right,
        ),
      );
    }
    return AppleGoalView(
      selectedGoal: _goal,
      onGoalSelected: (goal) => setState(() => _goal = goal),
      onContinue: _next,
      onBack: () {
        _pageController.previousPage(
          duration: DesignTokens.durationMedium,
          curve: DesignTokens.curveStandard,
        );
      },
    );
  }

  Widget _levelStep() {
    if (_web) {
      return _step(
        eyebrow: 'Starting point',
        title: 'Where are you today?',
        children: [
          _choice(
            label: 'A1 · Just starting',
            selected: _level == 'a1',
            onTap: () => setState(() => _level = 'a1'),
          ),
          _choice(
            label: 'A2 · I know the basics',
            selected: _level == 'a2',
            onTap: () => setState(() => _level = 'a2'),
          ),
          _choice(
            label: 'B1 · I can hold a conversation',
            selected: _level == 'b1',
            onTap: () => setState(() => _level = 'b1'),
          ),
          _choice(
            label: 'B2 · Polishing',
            selected: _level == 'b2',
            onTap: () => setState(() => _level = 'b2'),
          ),
          const SizedBox(height: 12),
          Text(
            'A comfortable daily session',
            style: DesignTokens.body(
              13,
              weight: FontWeight.w600,
            ).copyWith(color: DesignTokens.mutedDim),
          ),
          const SizedBox(height: 9),
          PSSegmented<String>(
            segments: const [
              (value: 'quick', label: '5 min'),
              (value: 'standard', label: '15 min'),
              (value: 'deep', label: '30 min'),
            ],
            selected: _sessionLength,
            onChanged: (value) => setState(() => _sessionLength = value),
          ),
        ],
        footer: _onboardingButton(
          label: 'Build my plan',
          onPressed: _level == null ? null : _next,
          icon: CupertinoIcons.arrow_right,
        ),
      );
    }
    return AppleLevelView(
      selectedLevel: _level,
      sessionLength: _sessionLength,
      onLevelSelected: (lvl) => setState(() => _level = lvl),
      onSessionLengthChanged: (len) => setState(() => _sessionLength = len),
      onContinue: _next,
      onBack: () {
        _pageController.previousPage(
          duration: DesignTokens.durationMedium,
          curve: DesignTokens.curveStandard,
        );
      },
    );
  }

  static const _interestTopics = [
    'Food',
    'Travel',
    'Movies & TV',
    'Music',
    'Sports',
    'Family',
    'Work',
    'Books',
    'Technology',
    'Nature',
  ];

  /// Optional and short by design — one tap per pick, no descriptions, a
  /// handful of words. Feeds personalized story topics later; skippable, so
  /// it never blocks the funnel for a learner who doesn't care to answer.
  Widget _interestsStep() {
    return _step(
      eyebrow: 'Make it yours',
      title: 'What do you enjoy?',
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: _interestTopics.map((topic) {
            final selected = _interests.contains(topic);
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                PSHaptics.selection();
                setState(() {
                  if (!_interests.remove(topic)) _interests.add(topic);
                });
              },
              child: AnimatedContainer(
                duration: DesignTokens.durationFast,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: selected
                      ? DesignTokens.primarySoft
                      : DesignTokens.canvasDim,
                  borderRadius: BorderRadius.circular(DesignTokens.radiusSmall),
                  border: Border.all(
                    color: selected
                        ? DesignTokens.primary
                        : DesignTokens.hairline,
                    width: selected ? 2 : 1,
                  ),
                ),
                child: Text(
                  topic,
                  style: DesignTokens.body(
                    14,
                    weight: FontWeight.w600,
                  ).copyWith(color: DesignTokens.inkSoft),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 14),
        Text(
          'So lessons match your interests',
          style: DesignTokens.body(
            12.5,
            weight: FontWeight.w500,
          ).copyWith(color: DesignTokens.mutedDim),
        ),
      ],
      footer: _onboardingButton(
        label: 'Continue',
        onPressed: _next,
        icon: CupertinoIcons.arrow_right,
      ),
    );
  }

  /// Round play button on each tutor card — hears the tutor's sample in
  /// their real voice before choosing. A green ring fills in around it over
  /// the sample's exact duration, so there's always a clear sense of when
  /// it will finish; every preview button is disabled for that whole
  /// stretch (see [TutorVoicePreviewer.isBusy]) so a stray second tap can't
  /// cut the sample short or queue up another one.
  Widget _previewButton(TutorPersona p) {
    final loading = _previewer.loadingId == p.id;
    final playing = _previewer.playingId == p.id;
    final busy = _previewer.isBusy;
    return Semantics(
      button: true,
      label: playing
          ? '${p.displayName}\'s voice sample is playing'
          : 'Play ${p.displayName}\'s voice sample',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: busy
            ? null
            : () {
                PSHaptics.selection();
                _previewer.play(p);
              },
        child: SizedBox(
          width: 44,
          height: 44,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (playing && _previewer.playingDurationMs != null)
                TweenAnimationBuilder<double>(
                  key: ValueKey(_previewer.playStartedAt),
                  tween: Tween(begin: 0, end: 1),
                  duration: Duration(
                    milliseconds: _previewer.playingDurationMs!,
                  ),
                  curve: Curves.linear,
                  builder: (context, value, _) => SizedBox(
                    width: 44,
                    height: 44,
                    child: CircularProgressIndicator(
                      value: value,
                      strokeWidth: 3,
                      color: DesignTokens.success,
                      backgroundColor: Colors.white.withValues(alpha: 0.25),
                    ),
                  ),
                ),
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: playing ? DesignTokens.primary : DesignTokens.infoSoft,
                  shape: BoxShape.circle,
                ),
                child: loading
                    ? const Padding(
                        padding: EdgeInsets.all(11),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: DesignTokens.info,
                        ),
                      )
                    : Icon(
                        playing
                            ? CupertinoIcons.speaker_2_fill
                            : CupertinoIcons.play_fill,
                        size: 16,
                        color: playing ? Colors.white : DesignTokens.info,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tutorStep() {
    Widget group(TutorAccent accent) {
      final pair = TutorPersona.byAccent(accent);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${accent.label} French'.toUpperCase(),
            style: DesignTokens.label(
              10.5,
            ).copyWith(color: DesignTokens.mutedDim, letterSpacing: 1),
          ),
          const SizedBox(height: 8),
          for (final p in pair)
            _choice(
              label: p.displayName,
              detail: p.tagline,
              selected: _tutorChoice?.id == p.id,
              onTap: () => setState(() => _tutorChoice = p),
              trailing: _previewButton(p),
            ),
        ],
      );
    }

    return _step(
      eyebrow: 'Your tutor',
      title: 'Who will you practice with?',
      subtitle: 'Tap play to hear them. Switch anytime.',
      children: [
        group(TutorAccent.france),
        const SizedBox(height: 10),
        group(TutorAccent.quebec),
      ],
      footer: _onboardingButton(
        label: 'Continue',
        onPressed: _tutorChoice == null ? null : _next,
        icon: CupertinoIcons.arrow_right,
      ),
    );
  }

  // ---------------------------------------------------------------- page 5
  /// The product before the account: one free 3-minute live call.
  Widget _trialStep() {
    return _step(
      eyebrow: 'Your first lesson',
      title: '3 minutes with ${_tutor.displayName}. On us.',
      subtitle: 'No account, no card.',
      children: [
        _PromiseRow(
          icon: CupertinoIcons.waveform,
          title: 'Speak from the first minute',
        ),
        _PromiseRow(icon: CupertinoIcons.timer, title: 'Exactly 3 minutes'),
        _PromiseRow(
          icon: CupertinoIcons.lock_shield_fill,
          title: 'Nothing saved until you say so',
        ),
      ],
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _onboardingButton(
            label: _startingTrial
                ? 'Calling ${_tutor.displayName}…'
                : 'Start my free 3 minutes',
            onPressed: _startingTrial ? null : _startTrial,
            icon: CupertinoIcons.phone_fill,
          ),
          TextButton(
            onPressed: _startingTrial ? null : _finish,
            child: Text(
              'Skip for now',
              style: DesignTokens.body(
                14,
                weight: FontWeight.w600,
              ).copyWith(color: DesignTokens.primary),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _startTrial() async {
    setState(() => _startingTrial = true);
    // The tutor identity must be live BEFORE dialing — the call captures its
    // persona at construction.
    ActiveTutor.set(_tutor);
    // Burn the trial before the socket opens: force-quitting mid-call never
    // mints a second one.
    await TrialCallGate.markStarted();
    if (!mounted) return;
    final result = await AppRouter.push<SpeakingResult>(
      context,
      (_) => SessionScreen(
        apiKey: ApiKeys.geminiKey,
        lessonContext: LivePrompts.trialLessonContext,
        stage: 'trial',
        kickoffMessage: LivePrompts.trialKickoff,
        durationLimitSeconds: TrialCallGate.maxSeconds,
        wrapUpNote: LivePrompts.trialWrapUpNote,
        wrapUpLeadSeconds: TrialCallGate.wrapUpLeadSeconds,
        popResultImmediately: true,
      ),
      fullscreenDialog: true,
    );
    if (result != null) {
      await TrialCallGate.recordResult(
        durationSeconds: result.durationSeconds,
        learnerUtteranceCount: result.learnerUtteranceCount,
      );
    }
    if (!mounted) return;
    setState(() {
      _startingTrial = false;
      _trialResult = result;
    });
    if (result != null && result.connected) {
      _next(); // recap
    } else {
      // Never strand someone whose call failed — straight to the account gate.
      _finish();
    }
  }

  // ---------------------------------------------------------------- page 6
  /// Recap — the "you already did it" moment, using the same restrained
  /// surface-and-border language as the rest of the current app.
  Widget _recapStep() {
    final result = _trialResult;
    final words = result?.frenchWordsUsed ?? const <String>[];
    return _step(
      eyebrow: 'Your first call',
      title: 'You just spoke French.',
      subtitle:
          'Here is the progress you made with ${_tutor.displayName}. Keep it going from your plan.',
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final cellWidth = (constraints.maxWidth - DesignTokens.space3) / 2;
            return Wrap(
              spacing: DesignTokens.space3,
              runSpacing: DesignTokens.space3,
              children: [
                SizedBox(
                  width: cellWidth,
                  child: _RecapMetric(
                    icon: CupertinoIcons.timer,
                    value: _formatRecapDuration(result?.durationSeconds ?? 0),
                    label: 'practice time',
                    color: DesignTokens.mastery,
                  ),
                ),
                SizedBox(
                  width: cellWidth,
                  child: _RecapMetric(
                    icon: CupertinoIcons.waveform,
                    value: '${result?.learnerUtteranceCount ?? 0}',
                    label: 'times you spoke',
                    color: DesignTokens.info,
                  ),
                ),
                SizedBox(
                  width: constraints.maxWidth,
                  child: _RecapWordsMetric(words: words),
                ),
              ],
            );
          },
        ),
      ],
      footer: _onboardingButton(
        label: 'Continue',
        onPressed: _finish,
        icon: CupertinoIcons.arrow_right,
      ),
    );
  }
}

String _formatRecapDuration(int seconds) {
  final minutes = seconds ~/ 60;
  final remainder = seconds % 60;
  return '$minutes:${remainder.toString().padLeft(2, '0')}';
}

class _RecapMetric extends StatelessWidget {
  const _RecapMetric({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: DesignTokens.surface,
        borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
        border: Border.all(color: DesignTokens.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 17),
          ),
          const SizedBox(height: 12),
          Text(value, style: DesignTokens.display(24)),
          const SizedBox(height: 2),
          Text(
            label,
            style: DesignTokens.body(12).copyWith(color: DesignTokens.mutedDim),
          ),
        ],
      ),
    );
  }
}

class _RecapWordsMetric extends StatelessWidget {
  const _RecapWordsMetric({required this.words});

  final List<String> words;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: DesignTokens.surface,
        borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
        border: Border.all(color: DesignTokens.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: DesignTokens.success.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  CupertinoIcons.textformat,
                  color: DesignTokens.success,
                  size: 17,
                ),
              ),
              const SizedBox(width: 10),
              Text('${words.length}', style: DesignTokens.display(24)),
              const SizedBox(width: 8),
              Text(
                words.length == 1 ? 'French word used' : 'French words used',
                style: DesignTokens.body(
                  12,
                  weight: FontWeight.w600,
                ).copyWith(color: DesignTokens.mutedDim),
              ),
            ],
          ),
          if (words.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                for (final word in words.take(12))
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: DesignTokens.primarySoft,
                      borderRadius: BorderRadius.circular(
                        DesignTokens.radiusPill,
                      ),
                    ),
                    child: Text(
                      word,
                      style: DesignTokens.body(
                        12,
                        weight: FontWeight.w600,
                      ).copyWith(color: DesignTokens.primaryDeep),
                    ),
                  ),
              ],
            ),
          ] else ...[
            const SizedBox(height: 8),
            Text(
              'Your first French words will appear here as you keep practising.',
              style: DesignTokens.body(
                12,
              ).copyWith(color: DesignTokens.mutedDim, height: 1.35),
            ),
          ],
        ],
      ),
    );
  }
}

/// Small header wordmark: the logo glyph + "ParleSprint" in small letters —
/// replaces the all-caps text-only brand treatment.
class _BrandWordmark extends StatelessWidget {
  const _BrandWordmark({this.onLightBackground = false});

  /// The onboarding header sits on the brand gradient on phones and on a
  /// neutral canvas on web, so the wordmark needs both an inverted and a
  /// standard treatment. The logo mark itself is a white-on-transparent PNG,
  /// hence the tint rather than a second asset.
  final bool onLightBackground;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          'assets/images/logo_mark.png',
          width: 18,
          height: 22,
          color: onLightBackground ? DesignTokens.ink : null,
        ),
        const SizedBox(width: 6),
        Text(
          'ParleSprint',
          style: DesignTokens.body(12.5, weight: FontWeight.w700).copyWith(
            color: onLightBackground ? DesignTokens.ink : Colors.white,
            letterSpacing: 0.1,
          ),
        ),
      ],
    );
  }
}

/// Readle's "preparing your personalised feed" moment, rebuilt on our
/// gradient: an animated circular percentage that replays the learner's own
/// onboarding answers as checkmarks while it fills, then auto-advances.
/// Pure theater with honest content — every chip is a real choice they made.
class _PreparingPane extends StatefulWidget {
  const _PreparingPane({
    required this.active,
    required this.checkpoints,
    required this.onComplete,
  });

  final bool active;
  final List<String> checkpoints;
  final VoidCallback onComplete;

  @override
  State<_PreparingPane> createState() => _PreparingPaneState();
}

class _PreparingPaneState extends State<_PreparingPane>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 3200),
      )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          // A beat on 100% before moving on — an instant jump reads as fake.
          Future.delayed(const Duration(milliseconds: 450), () {
            if (mounted) widget.onComplete();
          });
        }
      });

  @override
  void initState() {
    super.initState();
    // PageView builds this page lazily — it can be born already active, in
    // which case didUpdateWidget would never fire and the ring would sit at
    // 0% forever.
    if (widget.active) _controller.forward(from: 0);
  }

  @override
  void didUpdateWidget(_PreparingPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active && !_controller.isAnimating) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(color: DesignTokens.canvas),
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = Curves.easeInOutCubic.transform(_controller.value);
          final visibleChips = (t * (widget.checkpoints.length + 0.5)).floor();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(flex: 2),
              Text(
                'Creating your first lessons…',
                textAlign: TextAlign.center,
                style: DesignTokens.display(26).copyWith(height: 1.3),
              ),
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 152,
                    height: 152,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 152,
                          height: 152,
                          child: CircularProgressIndicator(
                            value: t,
                            strokeWidth: 11,
                            strokeCap: StrokeCap.round,
                            color: DesignTokens.primary,
                            backgroundColor: DesignTokens.canvasDim,
                          ),
                        ),
                        Text(
                          '${(t * 100).round()} %',
                          style: DesignTokens.body(
                            22,
                            weight: FontWeight.w800,
                          ).copyWith(color: DesignTokens.primary),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 22),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var i = 0; i < widget.checkpoints.length; i++)
                          AnimatedOpacity(
                            duration: DesignTokens.durationMedium,
                            opacity: i < visibleChips ? 1 : 0,
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: DesignTokens.surface,
                                  borderRadius: BorderRadius.circular(
                                    DesignTokens.radiusSmall,
                                  ),
                                  border: Border.all(
                                    color: DesignTokens.hairline,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      CupertinoIcons.checkmark_circle_fill,
                                      size: 17,
                                      color: DesignTokens.success,
                                    ),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        widget.checkpoints[i],
                                        style: DesignTokens.body(
                                          13.5,
                                          weight: FontWeight.w600,
                                        ).copyWith(color: DesignTokens.ink),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const Spacer(flex: 2),
              Padding(
                padding: const EdgeInsets.only(bottom: 28),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      CupertinoIcons.lock_shield_fill,
                      size: 15,
                      color: DesignTokens.mutedDim,
                    ),
                    const SizedBox(width: 7),
                    Text(
                      'Your plan adapts as you practise',
                      style: DesignTokens.body(
                        12.5,
                        weight: FontWeight.w600,
                      ).copyWith(color: DesignTokens.mutedDim),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PromiseRow extends StatelessWidget {
  const _PromiseRow({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: DesignTokens.infoSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: DesignTokens.info, size: 19),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: DesignTokens.body(
                    14,
                    weight: FontWeight.w700,
                  ).copyWith(color: DesignTokens.ink),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Aligns the onboarding header (wordmark, step counter, progress bar) with the
/// step content below it. On phones that means no change at all; on a wide
/// viewport it applies the same 1000px cap and 48px gutter `_wideStep` uses, so
/// the progress bar starts and ends exactly where the columns do instead of
/// stretching the full width of the browser window.
class _HeaderGutter extends StatelessWidget {
  const _HeaderGutter({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isWide =
        MediaQuery.sizeOf(context).width >= DesignTokens.breakpointExpanded;
    if (!isWide) return child;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: child,
        ),
      ),
    );
  }
}
