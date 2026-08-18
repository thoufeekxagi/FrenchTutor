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
import '../../services/notification_permission_service.dart';
import '../../services/notification_scheduler_service.dart';
import '../../services/product_analytics.dart';
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
  late final FixedExtentScrollController _reminderHourController;
  late final FixedExtentScrollController _reminderMinuteController;
  var _page = 0;
  String? _goal;
  String? _level;
  String _minutes = '10';
  // The course includes every practice mode. These choices decide which
  // skills receive the strongest early weighting in the generated route.
  final _focus = <String>{
    'Speaking',
    'Listening',
    'Writing',
    'Grammar',
    'Vocabulary',
    'Review',
  };
  final _preferredDays = <String>{'mon', 'tue', 'wed', 'thu', 'fri'};
  String _reminderTime = '19:00';
  var _reminderHour = 19;
  var _reminderMinute = 0;
  var _remindersEnabled = true;
  var _requestingNotificationPermission = false;
  String _notificationPermissionState = 'not_requested';
  var _tutor = TutorPersona.marie;
  var _preparingStarted = false;
  var _trialAvailable = false;
  var _trialAvailabilityKnown = false;
  var _advancingFromTutor = false;
  var _startingTrial = false;

  static const _tutorPage = 5;
  static const _trialPage = 6;
  static const _preparingPage = 7;
  static const _pageCount = 8;

  @override
  void initState() {
    super.initState();
    _reminderHourController = FixedExtentScrollController(initialItem: 19);
    _reminderMinuteController = FixedExtentScrollController(initialItem: 0);
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
    _reminderHourController.dispose();
    _reminderMinuteController.dispose();
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
      ..reminderTime = _remindersEnabled ? _reminderTime : null
      ..preferredDays = _preferredDays.toList()
      ..timeZone = _localTimeZoneValue()
      ..notificationPermissionState = _notificationPermissionState
      ..onboardingVersion = 'v3-personal-study-plan'
      ..onboardedAt = DateTime.now();
    store.saveProfile(profile);
    // The OS schedule is local and survives app termination. If permission
    // was declined, sync() simply clears any older reminders.
    unawaited(NotificationSchedulerService.sync(profile));
    // Materialize the first adaptive route before the account gate closes so
    // Home/Course can render immediately after sign-in. These are lightweight
    // session specifications; rich story/audio/art generation remains on the
    // practice path and can run independently for the first lesson.
    ref.read(adaptiveCourseStoreProvider).ensureCurrentPlan(profile);
    ProductAnalytics.capture(
      'onboarding_completed',
      properties: {
        'onboarding_version': profile.onboardingVersion,
        'goal': profile.goal,
        'level': profile.level,
        'session_length': profile.sessionLength,
        'preferred_days_count': profile.preferredDays.length,
        'reminders_enabled': _remindersEnabled,
        'notification_permission_state': profile.notificationPermissionState,
      },
    );
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
                    if (page == 4 &&
                        _remindersEnabled &&
                        _notificationPermissionState == 'not_requested') {
                      // Ask in the same context where the learner chooses
                      // reminder days and time, rather than surprising them
                      // on the first app launch.
                      unawaited(_requestNotificationPermission());
                    }
                    if (page == _preparingPage) _startPreparing();
                  },
                  children: [
                    _welcome(),
                    _goalStep(),
                    _interestStep(),
                    _levelStep(),
                    _scheduleStep(),
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
                      style: DesignTokens.body(11, weight: FontWeight.w700)
                          .copyWith(
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
                          style: DesignTokens.display(
                            compact ? 34 : 40,
                          ).copyWith(color: Colors.white, letterSpacing: -1.1),
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
                      ).copyWith(color: Colors.white.withValues(alpha: .62)),
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
          'Work and professional life',
          'Meetings, messages, interviews and workplace confidence',
          'work',
          Icons.work_outline_rounded,
          _goal,
        ),
        _option(
          'Move and settle in a French-speaking place',
          'Housing, healthcare, administration and daily life',
          'relocation',
          Icons.home_work_outlined,
          _goal,
        ),
        _option(
          'Travel and new places',
          'Order, ask, explore and connect',
          'travel',
          Icons.flight_takeoff_rounded,
          _goal,
        ),
        _option(
          'Culture, family and connection',
          'Understand more and take part in conversations',
          'culture',
          Icons.people_outline_rounded,
          _goal,
        ),
      ],
    );
  }

  Widget _levelStep() {
    return _question(
      title: 'How much French do you know?',
      subtitle:
          'Choose the closest fit. We’ll calibrate the language and feedback to you.',
      buttonLabel: 'Continue',
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
      ],
    );
  }

  Widget _interestStep() {
    return _question(
      title: 'What should your lessons focus on?',
      subtitle:
          'Your course includes the complete learning loop. Choose the skills you want to emphasize most.',
      buttonLabel: 'Continue',
      options: [
        _focusActions(),
        _focusCount(),
        for (final choice in _focusChoices())
          _focusOption(choice.$1, choice.$2, choice.$3),
      ],
    );
  }

  Widget _focusActions() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _selectAllFocus,
              icon: const Icon(Icons.done_all_rounded, size: 18),
              label: const Text('Select all six'),
            ),
          ),
          const SizedBox(width: 10),
          TextButton(
            onPressed: _focus.length > 1 ? _clearFocus : null,
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  Widget _focusCount() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        '${_focus.length} of 6 selected',
        style: DesignTokens.body(
          13,
          weight: FontWeight.w700,
        ).copyWith(color: SpeakColors.inkSoft),
      ),
    );
  }

  void _selectAllFocus() {
    setState(() {
      _focus
        ..clear()
        ..addAll(_focusChoices().map((choice) => choice.$1));
    });
  }

  void _clearFocus() {
    setState(() {
      _focus
        ..clear()
        ..add('Listening');
    });
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

  Widget _scheduleStep() {
    final goal = _goal ?? 'everyday';
    final recommended = _recommendedMinutesForGoal(goal);
    return _question(
      title: 'When will French fit your life?',
      subtitle:
          'A realistic plan is easier to keep. Choose your session length, study days, and local reminder time.',
      buttonLabel: 'Continue',
      options: [
        Text(
          'Daily practice time',
          style: DesignTokens.body(15, weight: FontWeight.w700),
        ),
        const SizedBox(height: 9),
        for (final option in const [
          ('5', '5 minutes', 'A quick habit for busy days'),
          ('10', '10 minutes', 'A steady daily rhythm'),
          ('15', '15 minutes', 'More room for practice and feedback'),
          ('20', '20 minutes', 'A focused route for bigger goals'),
        ])
          _timeOption(
            option.$2,
            option.$1 == recommended
                ? '${option.$3} · Recommended for your goal'
                : option.$3,
            option.$1,
          ),
        const SizedBox(height: 8),
        Text(
          'Study days',
          style: DesignTokens.body(15, weight: FontWeight.w700),
        ),
        const SizedBox(height: 9),
        _dayChoices(),
        const SizedBox(height: 16),
        SpeakCard(
          color: SpeakColors.blueSoft,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Your reminder time',
                style: DesignTokens.body(14, weight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                '${_formatReminderTime(_reminderTime)} · ${_timeZoneLabel()}',
                style: DesignTokens.body(
                  12,
                ).copyWith(color: SpeakColors.inkSoft),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Reminders',
                    style: DesignTokens.body(13, weight: FontWeight.w700),
                  ),
                  Switch.adaptive(
                    value: _remindersEnabled,
                    onChanged: (enabled) {
                      setState(() => _remindersEnabled = enabled);
                      if (enabled &&
                          _notificationPermissionState == 'not_requested') {
                        unawaited(_requestNotificationPermission());
                      }
                    },
                    activeThumbColor: SpeakColors.blue,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: _reminderWheel(
                      key: const ValueKey('reminder-hour-wheel'),
                      label: 'Hour',
                      controller: _reminderHourController,
                      itemCount: 24,
                      selectedValue: _reminderHour,
                      onChanged: (hour) => _setReminderTime(hour: hour),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 28),
                    child: Text(
                      ':',
                      style: DesignTokens.display(
                        27,
                      ).copyWith(color: DesignTokens.ink),
                    ),
                  ),
                  Expanded(
                    child: _reminderWheel(
                      key: const ValueKey('reminder-minute-wheel'),
                      label: 'Minute',
                      controller: _reminderMinuteController,
                      itemCount: 60,
                      selectedValue: _reminderMinute,
                      onChanged: (minute) => _setReminderTime(minute: minute),
                    ),
                  ),
                ],
              ),
              if (_remindersEnabled &&
                  _notificationPermissionState != 'granted') ...[
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  child: TextButton.icon(
                    onPressed: _requestingNotificationPermission
                        ? null
                        : _requestNotificationPermission,
                    icon: const Icon(Icons.notifications_active_outlined),
                    label: Text(
                      _requestingNotificationPermission
                          ? 'Checking notification access…'
                          : 'Turn on reminders',
                    ),
                  ),
                ),
              ],
              Text(
                _remindersEnabled
                    ? _notificationPermissionState == 'granted'
                          ? 'Reminders are scheduled for your selected days and time.'
                          : 'Turn on reminders for your chosen days and time.'
                    : 'You can turn reminders on later in Settings.',
                style: DesignTokens.body(
                  11.5,
                ).copyWith(color: SpeakColors.inkSoft, height: 1.35),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _reminderWheel({
    required Key key,
    required String label,
    required FixedExtentScrollController controller,
    required int itemCount,
    required int selectedValue,
    required ValueChanged<int> onChanged,
  }) {
    return Column(
      key: key,
      children: [
        Text(
          label,
          style: DesignTokens.body(
            11,
            weight: FontWeight.w700,
          ).copyWith(color: SpeakColors.inkSoft),
        ),
        const SizedBox(height: 5),
        SizedBox(
          height: 138,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: SpeakColors.line),
            ),
            child: ListWheelScrollView.useDelegate(
              controller: controller,
              itemExtent: 42,
              diameterRatio: 1.35,
              perspective: 0.003,
              physics: const FixedExtentScrollPhysics(),
              onSelectedItemChanged: onChanged,
              childDelegate: ListWheelChildBuilderDelegate(
                childCount: itemCount,
                builder: (context, index) {
                  final selected = index == selectedValue;
                  return Center(
                    child: Text(
                      index.toString().padLeft(2, '0'),
                      style: DesignTokens.display(selected ? 25 : 19).copyWith(
                        color: selected
                            ? SpeakColors.blue
                            : SpeakColors.inkSoft.withValues(alpha: .58),
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _setReminderTime({int? hour, int? minute}) {
    setState(() {
      if (hour != null) _reminderHour = hour;
      if (minute != null) _reminderMinute = minute;
      _reminderTime = _wireReminderTime(_reminderHour, _reminderMinute);
    });
  }

  String _wireReminderTime(int hour, int minute) =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  Widget _dayChoices() {
    const days = [
      ('mon', 'M'),
      ('tue', 'T'),
      ('wed', 'W'),
      ('thu', 'T'),
      ('fri', 'F'),
      ('sat', 'S'),
      ('sun', 'S'),
    ];
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (final day in days)
          GestureDetector(
            onTap: () => setState(() {
              if (!_preferredDays.remove(day.$1)) {
                _preferredDays.add(day.$1);
              }
            }),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _preferredDays.contains(day.$1)
                    ? SpeakColors.blue
                    : Colors.white,
                shape: BoxShape.circle,
                border: Border.all(
                  color: _preferredDays.contains(day.$1)
                      ? SpeakColors.blue
                      : SpeakColors.line,
                ),
              ),
              child: Text(
                day.$2,
                style: DesignTokens.body(13, weight: FontWeight.w800).copyWith(
                  color: _preferredDays.contains(day.$1)
                      ? Colors.white
                      : SpeakColors.inkSoft,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _requestNotificationPermission() async {
    if (_requestingNotificationPermission) return;
    _requestingNotificationPermission = true;
    ProductAnalytics.capture('notification_permission_prompted');
    final state = await NotificationPermissionService.request();
    if (!mounted) return;
    setState(() {
      _notificationPermissionState = state;
      _requestingNotificationPermission = false;
    });
    ProductAnalytics.capture(
      'notification_permission_result',
      properties: {'state': state},
    );
  }

  String _localTimeZoneValue() {
    final now = DateTime.now();
    final offset = now.timeZoneOffset;
    final sign = offset.isNegative ? '-' : '+';
    final hours = offset.inHours.abs().toString().padLeft(2, '0');
    final minutes = (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');
    return '${now.timeZoneName}|UTC$sign$hours:$minutes';
  }

  String _timeZoneLabel() => _localTimeZoneValue().replaceFirst('|', ' · ');

  String _formatReminderTime(String value) {
    final parts = value.split(':');
    final hour = int.tryParse(parts.first) ?? 19;
    final minute = int.tryParse(parts.last) ?? 0;
    return _wireReminderTime(hour.clamp(0, 23), minute.clamp(0, 59));
  }

  String _goalLabel(String value) => switch (value) {
    'tef_canada' => 'TEF / TCF Canada',
    'work' => 'Work and professional life',
    'relocation' => 'Move and settle in a French-speaking place',
    'travel' => 'Travel and new places',
    'culture' => 'Culture, family and connection',
    _ => 'Everyday French',
  };

  String _focusSummary() =>
      _focus.length == 6 ? 'All six skills' : _focus.join(' · ');

  String _recommendedMinutesForGoal(String goal) => switch (goal) {
    'tef_canada' => '15',
    'work' || 'relocation' => '10',
    'travel' || 'culture' => '10',
    _ => '10',
  };

  List<(String, String, IconData)> _focusChoices() => const [
    ('Speaking', 'Say useful French in short guided turns', Icons.mic_rounded),
    (
      'Listening',
      'Catch the meaning and the important details',
      Icons.headphones_rounded,
    ),
    (
      'Writing',
      'Build clear messages and short answers',
      Icons.edit_note_rounded,
    ),
    ('Grammar', 'Notice the pattern and use it naturally', Icons.rule_rounded),
    (
      'Vocabulary',
      'Build the words that make each situation useful',
      Icons.menu_book_rounded,
    ),
    (
      'Review',
      'Bring difficult language back at the right time',
      Icons.bolt_rounded,
    ),
  ];

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
                          _goalLabel(_goal ?? 'everyday'),
                        ),
                        const Divider(height: 22, color: SpeakColors.line),
                        _summary(
                          Icons.bar_chart_rounded,
                          'Level',
                          LearnerLevel.displayLabel(_level ?? 'a1'),
                        ),
                        const Divider(height: 22, color: SpeakColors.line),
                        _summary(Icons.mic_rounded, 'Focus', _focusSummary()),
                        const Divider(height: 22, color: SpeakColors.line),
                        _summary(
                          Icons.schedule_rounded,
                          'Plan',
                          '$_minutes min · ${_preferredDays.length} days · ${_formatReminderTime(_reminderTime)}',
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
      onTap: () => _selectGoal(value),
      leading: icon,
      title: title,
      subtitle: subtitle,
    );
  }

  void _selectGoal(String value) {
    setState(() {
      _goal = value;
      _minutes = _recommendedMinutesForGoal(value);
    });
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
