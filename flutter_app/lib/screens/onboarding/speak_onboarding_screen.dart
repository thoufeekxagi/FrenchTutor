import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/api_keys.dart';
import '../../design/app_router.dart';
import '../../design/tokens.dart';
import '../../flow/stage_outcome.dart';
import '../../models/profile.dart';
import '../../models/tutor_persona.dart';
import '../../prompts/live_prompts.dart';
import '../../providers/database_provider.dart';
import '../../services/alphabet_prewarm.dart';
import '../../services/trial_call_gate.dart';
import '../../services/tutor_voice_preview.dart';
import '../speak/speak_ui.dart';
import '../session/session_screen.dart';

/// The rebuilt first-run funnel: one question per screen, fast choices, a
/// visible plan preview, and an honest handoff to account creation after the
/// learner understands what they are getting.
class SpeakOnboardingScreen extends ConsumerStatefulWidget {
  const SpeakOnboardingScreen({super.key, required this.onFinished});

  final VoidCallback onFinished;

  @override
  ConsumerState<SpeakOnboardingScreen> createState() =>
      _SpeakOnboardingScreenState();
}

class _SpeakOnboardingScreenState extends ConsumerState<SpeakOnboardingScreen>
    with TickerProviderStateMixin {
  final _controller = PageController();
  late final TutorVoicePreviewer _previewer;
  late final AnimationController _welcomeController;
  late final Animation<double> _welcomeFade;
  late final Animation<double> _welcomeScale;
  var _page = 0;
  String? _goal;
  String? _level;
  String _minutes = '10';
  final _focus = <String>{'Speaking', 'Roleplay'};
  var _tutor = TutorPersona.marie;
  var _preparingStarted = false;
  var _trialAvailable = false;
  var _trialAvailabilityKnown = false;
  var _advancingFromTutor = false;
  var _startingTrial = false;

  static const _tutorPage = 4;
  static const _trialPage = 5;
  static const _preparingPage = 6;
  static const _pageCount = 7;

  @override
  void initState() {
    super.initState();
    _previewer = TutorVoicePreviewer()..addListener(_handlePreviewChanged);
    _welcomeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    )..forward();
    final curve = CurvedAnimation(
      parent: _welcomeController,
      curve: Curves.easeOutCubic,
    );
    _welcomeFade = curve;
    _welcomeScale = Tween<double>(begin: .96, end: 1).animate(curve);
    TrialCallGate.isAvailable().then((available) {
      if (!mounted) return;
      setState(() {
        _trialAvailable = available;
        _trialAvailabilityKnown = true;
      });
    });
  }

  void _handlePreviewChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _previewer.removeListener(_handlePreviewChanged);
    _previewer.dispose();
    _welcomeController.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    if (_page == _pageCount - 1) {
      _finish();
      return;
    }
    if (_page == _tutorPage) {
      unawaited(_advanceAfterTutor());
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    unawaited(_previewer.stop());
    _controller.nextPage(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _advanceAfterTutor() async {
    if (_advancingFromTutor) return;
    _advancingFromTutor = true;
    await _previewer.stop();
    var trialAvailable = _trialAvailable;
    if (!_trialAvailabilityKnown) {
      trialAvailable = await TrialCallGate.isAvailable();
    }
    if (!mounted) return;
    _trialAvailable = trialAvailable;
    _trialAvailabilityKnown = true;
    await _controller.animateToPage(
      trialAvailable ? _trialPage : _preparingPage,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
    _advancingFromTutor = false;
  }

  void _back() {
    if (_page == 0) return;
    _controller.previousPage(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  void _finish() {
    final store = ref.read(learningStoreProvider);
    final profile = store.profile()
      ..goal = _goal ?? 'everyday'
      ..level = _level ?? 'a1'
      ..sessionLength = switch (_minutes) {
        '5' => 'quick',
        '20' => 'deep',
        _ => 'standard',
      }
      ..interests = _focus.toList()
      ..onboardedAt = DateTime.now();
    store.saveProfile(profile);
    ActiveTutor.set(_tutor);
    TutorTuning.saveLanguageMix(LearnerLevel.defaultLanguageMix(profile.level));
    AlphabetPrewarm.maybeStart(isBeginner: profile.level == 'a1');
    widget.onFinished();
  }

  @override
  Widget build(BuildContext context) {
    final isWelcome = _page == 0;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isWelcome ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: isWelcome ? SpeakColors.blue : SpeakColors.background,
        body: SafeArea(
          child: Column(
            children: [
              if (!isWelcome) _topBar(),
              Expanded(
                child: PageView(
                  controller: _controller,
                  physics: const NeverScrollableScrollPhysics(),
                  onPageChanged: (page) {
                    setState(() => _page = page);
                    if (page == _preparingPage) _startPreparing();
                  },
                  children: [
                    _welcome(),
                    _goalStep(),
                    _levelStep(),
                    _focusStep(),
                    _tutorStep(),
                    _trialStep(),
                    _preparing(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 20, 0),
      child: Row(
        children: [
          GestureDetector(
            onTap: _back,
            child: const Icon(
              Icons.arrow_back_rounded,
              color: SpeakColors.inkSoft,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: LinearProgressIndicator(
                minHeight: 6,
                value: _page / (_pageCount - 1),
                backgroundColor: SpeakColors.line,
                color: SpeakColors.blue,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Text(
            '${_page + 1}/$_pageCount',
            style: DesignTokens.body(
              11,
              weight: FontWeight.w700,
            ).copyWith(color: SpeakColors.inkSoft),
          ),
        ],
      ),
    );
  }

  Widget _welcome() {
    return FadeTransition(
      opacity: _welcomeFade,
      child: ScaleTransition(
        scale: _welcomeScale,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxHeight < 680;
            return Padding(
              padding: EdgeInsets.fromLTRB(24, compact ? 18 : 28, 24, 22),
              child: Column(
                children: [
                  // A restrained top anchor keeps the first screen feeling
                  // composed instead of placing every element in one center
                  // stack, as on the reference splash.
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'PARLESPRINT',
                      style: DesignTokens.body(
                        11,
                        weight: FontWeight.w700,
                      ).copyWith(
                        color: Colors.white.withValues(alpha: .72),
                        letterSpacing: 2.2,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Image.asset(
                          'assets/images/parlesprint_logo.png',
                          width: compact ? 112 : 132,
                          height: compact ? 112 : 132,
                          fit: BoxFit.contain,
                        ),
                        SizedBox(height: compact ? 26 : 34),
                        Text(
                          'ParleSprint',
                          textAlign: TextAlign.center,
                          style: DesignTokens.display(compact ? 34 : 40)
                              .copyWith(
                                color: Colors.white,
                                letterSpacing: -1.1,
                              ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'French for real conversations.',
                          textAlign: TextAlign.center,
                          style: DesignTokens.body(
                            compact ? 17 : 19,
                            weight: FontWeight.w700,
                          ).copyWith(color: Colors.white),
                        ),
                        const SizedBox(height: 14),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 330),
                          child: Text(
                            'A clear course from your first words to confident everyday French.',
                            textAlign: TextAlign.center,
                            style: DesignTokens.body(compact ? 15 : 16)
                                .copyWith(
                                  color: Colors.white.withValues(alpha: .78),
                                  height: 1.42,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      'Speak  •  Listen  •  Read  •  Write',
                      textAlign: TextAlign.center,
                      style: DesignTokens.body(
                        12,
                        weight: FontWeight.w600,
                      ).copyWith(
                        color: Colors.white.withValues(alpha: .62),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: double.infinity,
                    height: 60,
                    child: ElevatedButton.icon(
                      onPressed: _next,
                      icon: const Icon(Icons.arrow_forward_rounded),
                      label: const Text('Build my plan'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: SpeakColors.blue,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28),
                        ),
                        textStyle: DesignTokens.body(
                          16,
                          weight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  void _selectTutor(TutorPersona persona) {
    final shouldSwitchPreview =
        _previewer.isBusy && _previewer.playingId != persona.id;
    setState(() => _tutor = persona);
    if (shouldSwitchPreview) {
      unawaited(_previewer.play(persona));
    }
  }

  void _previewTutor(TutorPersona persona) {
    setState(() => _tutor = persona);
    if (_previewer.playingId == persona.id ||
        _previewer.loadingId == persona.id) {
      unawaited(_previewer.stop());
    } else {
      unawaited(_previewer.play(persona));
    }
  }

  Widget _tutorStep() {
    return _question(
      title: 'Who will you practise with?',
      subtitle:
          'Choose a tutor whose voice and French feel right for you. You can change later.',
      buttonLabel: 'Continue',
      options: [for (final persona in TutorPersona.all) _tutorOption(persona)],
    );
  }

  Widget _tutorOption(TutorPersona persona) {
    final selected = _tutor.id == persona.id;
    final isPlaying = _previewer.playingId == persona.id;
    final isLoading = _previewer.loadingId == persona.id;
    final isActive = isPlaying || isLoading;
    return GestureDetector(
      onTap: () => _selectTutor(persona),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(bottom: 11),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? SpeakColors.blueSoft : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? SpeakColors.blue : SpeakColors.line,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: selected ? SpeakColors.blue : SpeakColors.blueSoft,
                shape: BoxShape.circle,
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.asset(
                persona.portraitAsset,
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
                errorBuilder: (context, error, stackTrace) => Center(
                  child: Text(
                    persona.initial,
                    style: DesignTokens.display(23).copyWith(
                      color: selected ? Colors.white : SpeakColors.blue,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          persona.displayName,
                          overflow: TextOverflow.ellipsis,
                          style: DesignTokens.body(16, weight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(width: 7),
                      Text(
                        persona.accent.label,
                        style: DesignTokens.body(
                          11,
                          weight: FontWeight.w600,
                        ).copyWith(color: SpeakColors.inkSoft),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    persona.tagline,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DesignTokens.body(
                      12,
                    ).copyWith(color: SpeakColors.inkSoft),
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () => _previewTutor(persona),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isLoading
                              ? Icons.hourglass_top_rounded
                              : isPlaying
                              ? Icons.stop_circle_outlined
                              : Icons.play_circle_outline_rounded,
                          color: SpeakColors.blue,
                          size: 18,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          isLoading
                              ? 'Preparing voice…'
                              : isPlaying
                              ? 'Stop voice'
                              : 'Play voice',
                          style: DesignTokens.body(
                            11,
                            weight: FontWeight.w700,
                          ).copyWith(color: SpeakColors.blue),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              isActive
                  ? Icons.volume_up_rounded
                  : selected
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: selected || isActive ? SpeakColors.blue : SpeakColors.line,
              size: 21,
            ),
          ],
        ),
      ),
    );
  }

  Widget _trialStep() {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 34, 20, 24),
            children: [
              Text(
                'Your first lesson is on us',
                style: DesignTokens.label(
                  11,
                ).copyWith(color: SpeakColors.blue, letterSpacing: 1.2),
              ),
              const SizedBox(height: 10),
              Text(
                'Try 3 minutes with ${_tutor.displayName}.',
                style: DesignTokens.display(29),
              ),
              const SizedBox(height: 10),
              Text(
                'Speak with your chosen tutor for free, then decide if ParleSprint is right for you. No card. No commitment.',
                style: DesignTokens.body(
                  15,
                ).copyWith(color: SpeakColors.inkSoft, height: 1.45),
              ),
              const SizedBox(height: 28),
              SpeakCard(
                color: SpeakColors.blueSoft,
                child: Column(
                  children: [
                    _trialPoint(
                      Icons.mic_none_rounded,
                      'Speak from the first minute',
                    ),
                    const Divider(height: 24, color: SpeakColors.line),
                    _trialPoint(
                      Icons.timer_outlined,
                      'A focused 3-minute first lesson',
                    ),
                    const Divider(height: 24, color: SpeakColors.line),
                    _trialPoint(
                      Icons.card_giftcard_outlined,
                      'Free to try. No card or commitment.',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 22),
          child: Column(
            children: [
              SpeakPrimaryButton(
                label: _startingTrial
                    ? 'Connecting to ${_tutor.displayName}…'
                    : 'Try it free — 3 minutes',
                icon: Icons.arrow_forward_rounded,
                onTap: _startingTrial ? () {} : () => unawaited(_startTrial()),
              ),
              const SizedBox(height: 4),
              TextButton(
                onPressed: _startingTrial ? null : _skipTrial,
                child: Text(
                  'Skip for now',
                  style: DesignTokens.body(
                    13,
                    weight: FontWeight.w700,
                  ).copyWith(color: SpeakColors.inkSoft),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _trialPoint(IconData icon, String label) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: SpeakColors.blue, size: 19),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: DesignTokens.body(13, weight: FontWeight.w700),
          ),
        ),
      ],
    );
  }

  void _skipTrial() {
    unawaited(
      _controller.animateToPage(
        _preparingPage,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  Future<void> _startTrial() async {
    if (_startingTrial) return;
    setState(() => _startingTrial = true);
    await ActiveTutor.set(_tutor);
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
    setState(() => _startingTrial = false);
    if (result != null && result.connected) {
      await _controller.animateToPage(
        _preparingPage,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    } else {
      _finish();
    }
  }

  Widget _question({
    required String title,
    required String subtitle,
    required List<Widget> options,
    required String buttonLabel,
  }) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 34, 20, 24),
            children: [
              Text(title, style: DesignTokens.display(29)),
              const SizedBox(height: 9),
              Text(
                subtitle,
                style: DesignTokens.body(
                  15,
                ).copyWith(color: SpeakColors.inkSoft, height: 1.4),
              ),
              const SizedBox(height: 28),
              ...options,
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 22),
          child: SpeakPrimaryButton(
            label: buttonLabel,
            icon: Icons.arrow_forward_rounded,
            onTap: _next,
          ),
        ),
      ],
    );
  }

  Widget _goalStep() {
    return _question(
      title: 'What should French unlock for you?',
      subtitle: 'We’ll use this to choose the situations you practise first.',
      buttonLabel: 'Continue',
      options: [
        _option(
          'Everyday French',
          'Feel comfortable in real life',
          'everyday',
          Icons.chat_bubble_outline_rounded,
          _goal,
        ),
        _option(
          'TEF / TCF Canada',
          'Build confidence for your exam',
          'tef_canada',
          Icons.school_outlined,
          _goal,
        ),
        _option(
          'Travel and new places',
          'Order, ask, explore and connect',
          'travel',
          Icons.flight_takeoff_rounded,
          _goal,
        ),
      ],
    );
  }

  Widget _levelStep() {
    return _question(
      title: 'How much French do you know?',
      subtitle:
          'Choose the closest fit and set a daily rhythm. You can change both later.',
      buttonLabel: 'Build my plan',
      options: [
        _levelOption(
          'A1 · Just starting',
          'I’m new to French',
          'a1',
          Icons.eco_rounded,
        ),
        _levelOption(
          'A2 · I know the basics',
          'I know common phrases',
          'a2',
          Icons.spa_rounded,
        ),
        _levelOption(
          'B1',
          'I can have basic conversations',
          'b1',
          Icons.local_florist_rounded,
        ),
        _levelOption(
          'B2',
          'I can discuss most topics',
          'b2',
          Icons.park_rounded,
        ),
        const SizedBox(height: 10),
        Text(
          'Your daily goal',
          style: DesignTokens.body(15, weight: FontWeight.w700),
        ),
        const SizedBox(height: 9),
        _timeOption('5 min / day', 'Casual', '5'),
        _timeOption('10 min / day', 'Regular', '10'),
        _timeOption('15 min / day', 'Serious', '15'),
        _timeOption('20 min / day', 'Intense', '20'),
      ],
    );
  }

  Widget _focusStep() {
    final choices = [
      ('Speaking', 'Use French out loud from day one', Icons.mic_rounded),
      (
        'Roleplay',
        'Practise real situations with ${_tutor.displayName}',
        Icons.forum_outlined,
      ),
      (
        'Stories',
        'Learn through short, memorable scenes',
        Icons.auto_stories_outlined,
      ),
      ('Review', 'Keep useful phrases available', Icons.bolt_rounded),
    ];
    return _question(
      title: 'What do you enjoy?',
      subtitle: 'Pick what should show up most often in your course.',
      buttonLabel: 'Continue',
      options: [
        for (final choice in choices)
          _focusOption(choice.$1, choice.$2, choice.$3),
      ],
    );
  }

  Widget _focusOption(String title, String subtitle, IconData icon) {
    final selected = _focus.contains(title);
    return GestureDetector(
      onTap: () => setState(() {
        if (!_focus.remove(title)) _focus.add(title);
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        margin: const EdgeInsets.only(bottom: 11),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? SpeakColors.blueSoft : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? SpeakColors.blue : SpeakColors.line,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: SpeakColors.blue, size: 21),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: DesignTokens.body(14, weight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: DesignTokens.body(
                      12,
                    ).copyWith(color: SpeakColors.inkSoft),
                  ),
                ],
              ),
            ),
            Icon(
              selected ? Icons.check_circle_rounded : Icons.circle_outlined,
              color: selected ? SpeakColors.blue : SpeakColors.line,
              size: 21,
            ),
          ],
        ),
      ),
    );
  }

  void _startPreparing() {
    if (_preparingStarted) return;
    _preparingStarted = true;
    Future<void>.delayed(const Duration(milliseconds: 3200), () {
      if (mounted && _page == _preparingPage) _finish();
    });
  }

  Widget _preparing() {
    return Column(
      children: [
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 82,
                    height: 82,
                    decoration: const BoxDecoration(
                      color: SpeakColors.blue,
                      shape: BoxShape.circle,
                    ),
                    child: const Padding(
                      padding: EdgeInsets.all(22),
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Creating your first lessons…',
                    textAlign: TextAlign.center,
                    style: DesignTokens.display(27),
                  ),
                  const SizedBox(height: 9),
                  Text(
                    'We’re turning your choices into a route you can actually follow.',
                    textAlign: TextAlign.center,
                    style: DesignTokens.body(
                      15,
                    ).copyWith(color: SpeakColors.inkSoft, height: 1.4),
                  ),
                  const SizedBox(height: 24),
                  SpeakCard(
                    child: Column(
                      children: [
                        _summary(
                          Icons.flag_outlined,
                          'Goal',
                          _goal ?? 'Everyday French',
                        ),
                        const Divider(height: 22, color: SpeakColors.line),
                        _summary(
                          Icons.bar_chart_rounded,
                          'Level',
                          LearnerLevel.displayLabel(_level ?? 'a1'),
                        ),
                        const Divider(height: 22, color: SpeakColors.line),
                        _summary(
                          Icons.mic_rounded,
                          'Focus',
                          _focus.join(' · '),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _option(
    String title,
    String subtitle,
    String value,
    IconData icon,
    String? selected,
  ) {
    final isSelected = selected == value;
    return _selectable(
      selected: isSelected,
      onTap: () => setState(() => _goal = value),
      leading: icon,
      title: title,
      subtitle: subtitle,
    );
  }

  Widget _levelOption(
    String title,
    String subtitle,
    String value,
    IconData icon,
  ) {
    return _selectable(
      selected: _level == value,
      onTap: () => setState(() => _level = value),
      leading: icon,
      title: title,
      subtitle: subtitle,
    );
  }

  Widget _timeOption(String title, String subtitle, String value) {
    return _selectable(
      selected: _minutes == value,
      onTap: () => setState(() => _minutes = value),
      leading: Icons.schedule_rounded,
      title: title,
      subtitle: subtitle,
    );
  }

  Widget _selectable({
    required bool selected,
    required VoidCallback onTap,
    required IconData leading,
    required String title,
    required String subtitle,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(bottom: 11),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? SpeakColors.blueSoft : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? SpeakColors.blue : SpeakColors.line,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: selected ? SpeakColors.blue : SpeakColors.blueSoft,
                shape: BoxShape.circle,
              ),
              child: Icon(
                leading,
                color: selected ? Colors.white : SpeakColors.blue,
                size: 19,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: DesignTokens.body(14, weight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: DesignTokens.body(
                      12,
                    ).copyWith(color: SpeakColors.inkSoft),
                  ),
                ],
              ),
            ),
            Icon(
              selected
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: selected ? SpeakColors.blue : SpeakColors.line,
              size: 21,
            ),
          ],
        ),
      ),
    );
  }

  Widget _summary(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: SpeakColors.blue, size: 21),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: DesignTokens.body(13).copyWith(color: SpeakColors.inkSoft),
          ),
        ),
        Text(value, style: DesignTokens.body(13, weight: FontWeight.w700)),
      ],
    );
  }
}
