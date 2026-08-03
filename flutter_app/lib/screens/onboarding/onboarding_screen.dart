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
import '../session/session_screen.dart';

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
  late final AnimationController _brandController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..forward();
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
  late final TutorVoicePreviewer _previewer = TutorVoicePreviewer()
    ..addListener(() {
      if (mounted) setState(() {});
    });

  // Fixed page indices (recap stays in the tree; it is only ever reached
  // after a connected trial call).
  static const _pageWelcome = 0;
  static const _pageGoal = 1;
  static const _pageLevel = 2;
  static const _pageInterests = 3;
  static const _pageTutor = 4;
  static const _pagePreparing = 5;

  @override
  void initState() {
    super.initState();
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

  /// The gradient identity — shared with the sign-in and restoring-progress
  /// screens via [DesignTokens.heroGradient] so they never drift apart.
  static const _heroGradient = DesignTokens.heroGradient;

  @override
  Widget build(BuildContext context) {
    final showHeader = _page >= _pageGoal && _page <= _pageTutor;
    return Scaffold(
      backgroundColor: _isGradientPage
          ? DesignTokens.primaryDeep
          : DesignTokens.primary,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: _web ? null : _heroGradient,
          color: _web ? DesignTokens.canvas : null,
        ),
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
                            _BrandWordmark(onLightBackground: _web),
                            const Spacer(),
                            Text(
                              'Step $_page of 4',
                              style: Passeport.body(12, weight: FontWeight.w600)
                                  .copyWith(
                                    color: _web
                                        ? DesignTokens.mutedDim
                                        : Colors.white.withValues(alpha: 0.78),
                                  ),
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
                            color: _web
                                ? DesignTokens.canvasDim
                                : Colors.white.withValues(alpha: 0.28),
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
                                    color: _web
                                        ? DesignTokens.primary
                                        : Colors.white,
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
                    _PreparingPane(
                      active: _page == _pagePreparing,
                      checkpoints: [
                        'French',
                        if (_level != null) LearnerLevel.displayLabel(_level!),
                        switch (_goal) {
                          'tef_canada' => 'TEF / TCF Canada',
                          'everyday' => 'Everyday French',
                          _ => 'Foundations',
                        },
                        'Tutor ${_tutor.displayName}',
                      ],
                      onComplete: () {
                        if (!mounted || _page != _pagePreparing) return;
                        if (_trialAvailable) {
                          _next();
                        } else {
                          _finish();
                        }
                      },
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

  bool get _isGradientPage => _page == _pageWelcome || _page == _pagePreparing;

  // ---------------------------------------------------------------- page 0
  /// Gradient social-proof opener: wordmark, one strong promise inside a
  /// frosted quote card, a laurel trust line, one button. No decisions.
  Widget _welcomeStep() {
    if (_web) return _webWelcomeStep();
    return Container(
      decoration: const BoxDecoration(gradient: _heroGradient),
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
      // A hero column centred at a readable width is the right desktop shape
      // for a splash (unlike the question steps, which get two columns) — but
      // it must be capped, or the quote card and button stretch the full width
      // of a browser window and stop reading as a composed screen.
      child: _CenteredHero(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Spacer(flex: 2),
            _AnimatedBrandMark(animation: _brandController),
            const Spacer(flex: 2),
            Container(
              padding: const EdgeInsets.fromLTRB(26, 32, 26, 36),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
              ),
              child: Column(
                children: [
                  // Quote marks bracket only this sentence — the Stack sizes to
                  // the Text alone, so the closing glyph hugs the end of the
                  // quote rather than floating near the bottom of the whole
                  // card (which used to land under the subtitle instead).
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Text(
                        'The fastest way to speak French is to speak French.',
                        textAlign: TextAlign.center,
                        style: Passeport.display(
                          23,
                        ).copyWith(color: Colors.white, height: 1.35),
                      ),
                      Positioned(
                        left: -8,
                        top: -16,
                        child: _QuoteGlyph(opening: true),
                      ),
                      Positioned(
                        right: -8,
                        bottom: -16,
                        child: _QuoteGlyph(opening: false),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  Text(
                    'A live tutor who talks with you every day, '
                    'not flashcards about someday.',
                    textAlign: TextAlign.center,
                    style: Passeport.body(15).copyWith(
                      color: Colors.white.withValues(alpha: 0.92),
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(flex: 2),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  CupertinoIcons.checkmark_seal_fill,
                  size: 16,
                  color: Colors.white.withValues(alpha: 0.9),
                ),
                const SizedBox(width: 8),
                Text(
                  'Built for TEF / TCF Canada learners',
                  style: Passeport.body(
                    13,
                    weight: FontWeight.w600,
                  ).copyWith(color: Colors.white.withValues(alpha: 0.9)),
                ),
              ],
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _next,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: DesignTokens.primaryDeep,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: Passeport.body(15, weight: FontWeight.w700),
                ),
                child: const Text('Continue'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Web welcome pane: a split hero. Left is the promise, right is a contained
  /// card with the social proof. Neutral canvas, dark text, one azure action —
  /// the mobile version's full-bleed gradient with white text is kept for
  /// phones only.
  Widget _webWelcomeStep() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(32, 32, 32, 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                flex: 5,
                child: Padding(
                  padding: const EdgeInsets.only(right: 56),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _BrandWordmark(onLightBackground: true),
                      const SizedBox(height: DesignTokens.space6),
                      Text(
                        'The fastest way to speak French is to speak French.',
                        style: Passeport.display(40).copyWith(height: 1.12),
                      ),
                      const SizedBox(height: DesignTokens.space4),
                      Text(
                        'A live tutor who talks with you every day, not '
                        'flashcards about someday.',
                        style: Passeport.body(
                          16,
                        ).copyWith(color: DesignTokens.mutedDim, height: 1.55),
                      ),
                      const SizedBox(height: DesignTokens.space6),
                      SizedBox(
                        height: 50,
                        child: ElevatedButton.icon(
                          onPressed: _next,
                          icon: const Icon(
                            CupertinoIcons.arrow_right,
                            size: 17,
                          ),
                          label: const Text('Get started'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: DesignTokens.primary,
                            foregroundColor: DesignTokens.surface,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 28),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                DesignTokens.radiusMedium,
                              ),
                            ),
                            textStyle: Passeport.body(
                              15,
                              weight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: DesignTokens.space5),
                      Row(
                        children: [
                          Icon(
                            CupertinoIcons.checkmark_seal_fill,
                            size: 15,
                            color: DesignTokens.success,
                          ),
                          const SizedBox(width: DesignTokens.space2),
                          Text(
                            'Built for TEF / TCF Canada learners',
                            style: Passeport.body(
                              13,
                              weight: FontWeight.w600,
                            ).copyWith(color: DesignTokens.mutedDim),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                flex: 4,
                child: Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: DesignTokens.surface,
                    borderRadius: BorderRadius.circular(
                      DesignTokens.radiusCard,
                    ),
                    border: Border.all(color: DesignTokens.hairline),
                    boxShadow: DesignTokens.cardShadow,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          gradient: DesignTokens.heroGradient,
                          borderRadius: BorderRadius.circular(
                            DesignTokens.radiusMedium,
                          ),
                        ),
                        child: Icon(
                          CupertinoIcons.mic_fill,
                          size: 20,
                          color: DesignTokens.surface,
                        ),
                      ),
                      const SizedBox(height: DesignTokens.space5),
                      Text(
                        'Three minutes, out loud, every day.',
                        style: Passeport.display(19).copyWith(height: 1.3),
                      ),
                      const SizedBox(height: DesignTokens.space3),
                      Text(
                        'Answer four quick questions and your tutor is ready. '
                        'No account needed to try it.',
                        style: Passeport.body(
                          14,
                        ).copyWith(color: DesignTokens.mutedDim, height: 1.5),
                      ),
                      const SizedBox(height: DesignTokens.space5),
                      Divider(height: 1, color: DesignTokens.hairline),
                      const SizedBox(height: DesignTokens.space4),
                      for (final line in const [
                        'A real conversation, not multiple choice',
                        'Corrections as you speak',
                        'Your own plan, rebuilt daily',
                      ]) ...[
                        Padding(
                          padding: const EdgeInsets.only(
                            bottom: DesignTokens.space3,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                CupertinoIcons.checkmark_alt,
                                size: 15,
                                color: DesignTokens.primary,
                              ),
                              const SizedBox(width: DesignTokens.space3),
                              Expanded(
                                child: Text(
                                  line,
                                  style: Passeport.body(13.5).copyWith(
                                    color: DesignTokens.inkSoft,
                                    height: 1.45,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

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
            // On a short screen (e.g. the level step's 4 choices + session-
            // length picker on an SE-sized phone) this content runs below
            // the fold with zero visual hint that anything follows — the
            // scrollbar makes that discoverable instead of it looking like
            // the step just ends at whatever tile happens to land last.
            child: Scrollbar(
              thumbVisibility: true,
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(top: 24, bottom: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Passeport.infoSoft,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(_stepIcon, color: Passeport.sky, size: 22),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      eyebrow.toUpperCase(),
                      style: Passeport.body(10.5, weight: FontWeight.w800)
                          .copyWith(
                            color: Colors.white.withValues(alpha: 0.8),
                            letterSpacing: 1,
                          ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      title,
                      style: Passeport.display(
                        30,
                      ).copyWith(color: Colors.white),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 9),
                      Text(
                        subtitle,
                        style: Passeport.body(15).copyWith(
                          color: Colors.white.withValues(alpha: 0.86),
                          height: 1.45,
                        ),
                      ),
                    ],
                    const SizedBox(height: 26),
                    ...children,
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          footer,
        ],
      ),
    );
  }

  /// Desktop arrangement of [_step], styled to the web reference rather than
  /// the mobile gradient: a neutral page with one contained white card, hairline
  /// border, dark text, and a single azure action. Question on the left, answers
  /// on the right.
  Widget _wideStep(
    String eyebrow,
    String title,
    String? subtitle,
    List<Widget> children,
    Widget footer,
  ) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(32, 8, 32, 40),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920),
          child: Container(
            padding: const EdgeInsets.all(40),
            decoration: BoxDecoration(
              color: DesignTokens.surface,
              borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
              border: Border.all(color: DesignTokens.hairline),
              boxShadow: DesignTokens.cardShadow,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left: the question. Dark ink on white, not white on gradient.
                Expanded(
                  flex: 5,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 40),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: DesignTokens.primarySoft,
                            borderRadius: BorderRadius.circular(
                              DesignTokens.radiusMedium,
                            ),
                          ),
                          child: Icon(
                            _stepIcon,
                            color: DesignTokens.primary,
                            size: 21,
                          ),
                        ),
                        const SizedBox(height: DesignTokens.space5),
                        Text(
                          eyebrow.toUpperCase(),
                          style: Passeport.mono(
                            11,
                            weight: FontWeight.w600,
                          ).copyWith(color: DesignTokens.muted),
                        ),
                        const SizedBox(height: DesignTokens.space2),
                        Text(title, style: Passeport.display(30)),
                        if (subtitle != null) ...[
                          const SizedBox(height: DesignTokens.space3),
                          Text(
                            subtitle,
                            style: Passeport.body(15).copyWith(
                              color: DesignTokens.mutedDim,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                // Right: the answers, with this step's action beneath them.
                Expanded(
                  flex: 6,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ...children,
                      const SizedBox(height: DesignTokens.space4),
                      footer,
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
          backgroundColor: _web
              ? (enabled ? DesignTokens.primary : DesignTokens.canvasDim)
              : (enabled ? Colors.white : Colors.white.withValues(alpha: 0.28)),
          foregroundColor: _web
              ? (enabled ? DesignTokens.surface : DesignTokens.muted)
              : (enabled
                    ? DesignTokens.primaryDeep
                    : Colors.white.withValues(alpha: 0.52)),
          disabledBackgroundColor: _web
              ? DesignTokens.canvasDim
              : Colors.white.withValues(alpha: 0.28),
          disabledForegroundColor: _web
              ? DesignTokens.muted
              : Colors.white.withValues(alpha: 0.52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DesignTokens.radiusMedium),
          ),
          textStyle: Passeport.body(15, weight: FontWeight.w700),
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
            color: Colors.white.withValues(alpha: selected ? 1 : 0.94),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? DesignTokens.primary
                  : (_web
                        ? DesignTokens.hairline
                        : Colors.white.withValues(alpha: 0.72)),
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
                      style: Passeport.body(15, weight: FontWeight.w700)
                          .copyWith(
                            color: selected
                                ? DesignTokens.primaryDeep
                                : Passeport.ink,
                          ),
                    ),
                    if (detail != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        detail,
                        style: Passeport.body(12.5).copyWith(
                          color: selected
                              ? DesignTokens.primaryDeep.withValues(alpha: 0.82)
                              : Passeport.slateDim,
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
                color: selected ? DesignTokens.primaryDeep : Passeport.slate,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _goalStep() {
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

  Widget _levelStep() {
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
          style: Passeport.body(
            13,
            weight: FontWeight.w600,
          ).copyWith(color: Colors.white),
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
                  color: Colors.white.withValues(alpha: selected ? 1 : 0.16),
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(
                    color: selected
                        ? DesignTokens.primaryDeep
                        : Colors.white.withValues(alpha: 0.4),
                    width: selected ? 2 : 1,
                  ),
                ),
                child: Text(
                  topic,
                  style: Passeport.body(14, weight: FontWeight.w600).copyWith(
                    color: selected ? DesignTokens.primaryDeep : Colors.white,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 14),
        Text(
          'So lessons match your interests',
          style: Passeport.body(
            12.5,
            weight: FontWeight.w500,
          ).copyWith(color: Colors.white.withValues(alpha: 0.72)),
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
                      color: Passeport.sage,
                      backgroundColor: Colors.white.withValues(alpha: 0.25),
                    ),
                  ),
                ),
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: playing ? Passeport.maroon : Passeport.infoSoft,
                  shape: BoxShape.circle,
                ),
                child: loading
                    ? const Padding(
                        padding: EdgeInsets.all(11),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Passeport.sky,
                        ),
                      )
                    : Icon(
                        playing
                            ? CupertinoIcons.speaker_2_fill
                            : CupertinoIcons.play_fill,
                        size: 16,
                        color: playing ? Colors.white : Passeport.sky,
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
            style: Passeport.body(10.5, weight: FontWeight.w800).copyWith(
              color: Colors.white.withValues(alpha: 0.82),
              letterSpacing: 1,
            ),
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
              style: Passeport.body(
                14,
                weight: FontWeight.w600,
              ).copyWith(color: Colors.white.withValues(alpha: 0.78)),
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
  /// Recap — the "you already did it" moment, with animated evidence bars.
  Widget _recapStep() {
    final result = _trialResult;
    final words = result?.frenchWordsUsed ?? const <String>[];
    final minutes = ((result?.durationSeconds ?? 0) / 60).clamp(0, 3);
    return _step(
      eyebrow: 'Your first call',
      title: 'You just spoke French.',
      children: [
        _StatBar(
          label: 'Minutes with ${_tutor.displayName}',
          value: minutes.toStringAsFixed(
            minutes == minutes.roundToDouble() ? 0 : 1,
          ),
          fraction: ((result?.durationSeconds ?? 0) / TrialCallGate.maxSeconds)
              .clamp(0.0, 1.0),
          color: Passeport.mastery,
          delay: Duration.zero,
        ),
        _StatBar(
          label: 'Times you spoke',
          value: '${result?.learnerUtteranceCount ?? 0}',
          fraction: ((result?.learnerUtteranceCount ?? 0) / 10).clamp(0.0, 1.0),
          color: Passeport.info,
          delay: const Duration(milliseconds: 250),
        ),
        _StatBar(
          label: 'French words heard from you',
          value: '${words.length}',
          fraction: (words.length / 8).clamp(0.0, 1.0),
          color: Passeport.success,
          delay: const Duration(milliseconds: 500),
        ),
        if (words.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final word in words.take(12))
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: Passeport.primarySoft,
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(
                    word,
                    style: Passeport.body(
                      13,
                      weight: FontWeight.w600,
                    ).copyWith(color: Passeport.primaryDeep),
                  ),
                ),
            ],
          ),
        ],
      ],
      footer: _onboardingButton(
        label: 'Keep my progress',
        onPressed: _finish,
        icon: CupertinoIcons.arrow_right,
      ),
    );
  }
}

/// Oversized decorative quotation mark, testimonial-style — sits inside the
/// card near its corners, clear of the border, with a small gap before the
/// paragraph text itself begins.
class _QuoteGlyph extends StatelessWidget {
  const _QuoteGlyph({required this.opening});

  final bool opening;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Text(
        opening ? '“' : '”',
        style: Passeport.display(
          38,
        ).copyWith(color: Colors.white.withValues(alpha: 0.55), height: 1),
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
          style: Passeport.body(12.5, weight: FontWeight.w700).copyWith(
            color: onLightBackground ? DesignTokens.ink : Colors.white,
            letterSpacing: 0.1,
          ),
        ),
      ],
    );
  }
}

class _AnimatedBrandMark extends StatelessWidget {
  const _AnimatedBrandMark({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final wordProgress = Curves.easeOutCubic.transform(
          Interval(0, 0.58).transform(animation.value),
        );
        final bubbleProgress = Curves.easeOutCubic.transform(
          Interval(0.42, 1).transform(animation.value),
        );
        return Column(
          children: [
            // Two speech bubbles in conversation: the big one slides in from
            // the left and settles up top; the small one slides in from the
            // right and tucks in below it, overlapping about halfway — a
            // clear big-speaks/small-replies pair, never two same-size
            // shapes blended on top of each other.
            SizedBox(
              width: 104,
              height: 60,
              child: Stack(
                children: [
                  Positioned(
                    left: 18,
                    top: 0,
                    child: Transform.translate(
                      offset: Offset(-60 * (1 - bubbleProgress), 0),
                      child: Opacity(
                        opacity: bubbleProgress,
                        child: const Icon(
                          CupertinoIcons.bubble_left_fill,
                          color: Colors.white,
                          size: 44,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 52,
                    top: 28,
                    child: Transform.translate(
                      offset: Offset(60 * (1 - bubbleProgress), 0),
                      child: Opacity(
                        opacity: bubbleProgress,
                        child: Icon(
                          CupertinoIcons.bubble_right_fill,
                          color: Colors.white.withValues(alpha: 0.85),
                          size: 28,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            ClipRect(
              child: Align(
                alignment: Alignment.centerLeft,
                widthFactor: wordProgress,
                child: Transform.translate(
                  offset: Offset(28 * (1 - wordProgress), 0),
                  child: Text(
                    'ParleSprint',
                    style: Passeport.display(30).copyWith(color: Colors.white),
                  ),
                ),
              ),
            ),
          ],
        );
      },
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
      decoration: const BoxDecoration(
        gradient: _OnboardingScreenState._heroGradient,
      ),
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
                style: Passeport.display(
                  26,
                ).copyWith(color: Colors.white, height: 1.3),
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
                            color: Colors.white,
                            backgroundColor: Colors.white.withValues(
                              alpha: 0.22,
                            ),
                          ),
                        ),
                        Text(
                          '${(t * 100).round()} %',
                          style: Passeport.body(
                            22,
                            weight: FontWeight.w800,
                          ).copyWith(color: Colors.white),
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
                                  color: Colors.white.withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      CupertinoIcons.checkmark_circle_fill,
                                      size: 17,
                                      color: Colors.white,
                                    ),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        widget.checkpoints[i],
                                        style: Passeport.body(
                                          13.5,
                                          weight: FontWeight.w600,
                                        ).copyWith(color: Colors.white),
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
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      'Your plan adapts as you practise',
                      style: Passeport.body(
                        12.5,
                        weight: FontWeight.w600,
                      ).copyWith(color: Colors.white.withValues(alpha: 0.85)),
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

/// One animated horizontal evidence bar on the recap screen — label + value,
/// with the fill growing in after [delay] so the three bars land as a
/// staggered sequence (the Readle "bar moment").
class _StatBar extends StatefulWidget {
  const _StatBar({
    required this.label,
    required this.value,
    required this.fraction,
    required this.color,
    required this.delay,
  });

  final String label;
  final String value;
  final double fraction;
  final Color color;
  final Duration delay;

  @override
  State<_StatBar> createState() => _StatBarState();
}

class _StatBarState extends State<_StatBar> {
  bool _started = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(widget.delay, () {
      if (mounted) setState(() => _started = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.label,
                  style: Passeport.body(
                    13,
                    weight: FontWeight.w600,
                  ).copyWith(color: Colors.white),
                ),
              ),
              Text(
                widget.value,
                style: Passeport.body(
                  15,
                  weight: FontWeight.w800,
                ).copyWith(color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(100),
            child: SizedBox(
              height: 10,
              width: double.infinity,
              child: TweenAnimationBuilder<double>(
                duration: const Duration(milliseconds: 900),
                curve: Curves.easeOutCubic,
                tween: Tween(
                  begin: 0,
                  end: _started ? widget.fraction.clamp(0.02, 1.0) : 0.0,
                ),
                builder: (context, animated, _) => Stack(
                  children: [
                    Container(color: Colors.white.withValues(alpha: 0.24)),
                    FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: animated,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              widget.color,
                              widget.color.withValues(alpha: 0.75),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
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
              color: Passeport.infoSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Passeport.sky, size: 19),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Passeport.body(
                    14,
                    weight: FontWeight.w700,
                  ).copyWith(color: Colors.white),
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

/// Centres a hero/splash column at a readable width on desktop and leaves it
/// untouched on phones. Used by the onboarding welcome pane, where a single
/// centred column is the right desktop shape but an uncapped one is not.
class _CenteredHero extends StatelessWidget {
  const _CenteredHero({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isWide =
        MediaQuery.sizeOf(context).width >= DesignTokens.breakpointExpanded;
    if (!isWide) return child;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: child,
      ),
    );
  }
}
