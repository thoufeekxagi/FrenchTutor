import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../design/app_router.dart';
import '../../design/appearance_colors.dart';
import '../../design/tokens.dart';
import '../../flow/stage_outcome.dart';
import '../../models/profile.dart';
import '../../models/tutor_persona.dart';
import '../../prompts/live_prompts.dart';
import '../../providers/database_provider.dart';
import '../../screens/speak/speaking_practice_screen.dart';
import '../../services/alphabet_prewarm.dart';
import '../../services/notification_permission_service.dart';
import '../../services/notification_scheduler_service.dart';
import '../../services/product_analytics.dart';
import '../../services/trial_call_gate.dart';
import '../ui/v3_ui.dart';

/// V3 first-run flow. Screen contract:
///
/// User arrived to: a fresh install.
/// They must understand: this app is only for the TCF Canada exam.
/// Primary action: one per screen (Get started, Continue, Start, Create).
/// Success state: a saved profile (level, rhythm, tutor) and the account gate.
/// Must not contain: goal or skill questions, centered layouts, fake data.
///
/// Pages: 0 launch, 1 welcome, 2 level, 3 Marie check, 4 rhythm, 5 plan ready.
/// Saving, consent and sign-in order are owned by AuthGate and unchanged.
class V3OnboardingFlow extends ConsumerStatefulWidget {
  const V3OnboardingFlow({super.key, required this.onFinished});

  final VoidCallback onFinished;

  @override
  ConsumerState<V3OnboardingFlow> createState() => _V3OnboardingFlowState();
}

class _V3OnboardingFlowState extends ConsumerState<V3OnboardingFlow> {
  static const _launchPage = 0;
  static const _mariePage = 3;
  static const _planPage = 4;
  static const _readyPage = 5;
  static const _stepCount = 4;

  final _controller = PageController();
  var _page = _launchPage;
  var _level = 'a1';
  var _minutes = '15';
  final _days = <String>{'mon', 'tue', 'wed', 'thu', 'fri'};
  var _reminder = const TimeOfDay(hour: 19, minute: 0);
  DateTime? _examDate;
  var _permissionState = 'not_requested';
  var _startingCheck = false;
  final _tutor = TutorPersona.defaultPersona;

  static const _skipPrompt = bool.fromEnvironment('SKIP_NOTIFICATION_PROMPT');

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 1700), () {
      if (mounted && _page == _launchPage) _go(1);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _go(int page) {
    FocusManager.instance.primaryFocus?.unfocus();
    unawaited(
      _controller.animateToPage(
        page,
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  void _next() => _go(_page + 1);

  String get _reminderWire =>
      '${_reminder.hour.toString().padLeft(2, '0')}:${_reminder.minute.toString().padLeft(2, '0')}';

  String _timeZoneValue() {
    final now = DateTime.now();
    final offset = now.timeZoneOffset;
    final sign = offset.isNegative ? '-' : '+';
    final hours = offset.inHours.abs().toString().padLeft(2, '0');
    final minutes = (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');
    return '${now.timeZoneName}|UTC$sign$hours:$minutes';
  }

  Profile _profile() {
    return ref.read(learningStoreProvider).profile()
      ..goal = 'tef_canada'
      ..level = _level
      ..sessionLength = switch (_minutes) {
        '5' => 'quick',
        '20' => 'deep',
        _ => 'standard',
      }
      ..interests = const [
        'Speaking',
        'Listening',
        'Writing',
        'Grammar',
        'Vocabulary',
        'Review',
      ]
      ..reminderTime = _reminderWire
      ..preferredDays = _days.toList()
      ..timeZone = _timeZoneValue()
      ..notificationPermissionState = _permissionState
      ..onboardingVersion = 'v3-tcf-onboarding'
      ..onboardedAt = DateTime.now();
  }

  Future<void> _requestNotifications() async {
    if (_skipPrompt) return;
    ProductAnalytics.capture('notification_permission_prompted');
    final state = await NotificationPermissionService.request();
    if (!mounted) return;
    setState(() => _permissionState = state);
    ProductAnalytics.capture(
      'notification_permission_result',
      properties: {'state': state},
    );
  }

  Future<void> _startCheck() async {
    if (_startingCheck) return;
    setState(() => _startingCheck = true);
    ref.read(learningStoreProvider).saveProfile(_profile());
    await ActiveTutor.set(_tutor);
    await TrialCallGate.markStarted();
    if (!mounted) {
      await TrialCallGate.releaseIfNeverConnected(connected: false);
      return;
    }
    final result = await AppRouter.push<SpeakingResult>(
      context,
      (_) => SpeakingPracticeScreen(
        autoStart: true,
        request: SpeakingPracticeRequest(
          mode: SpeakingMode.freeTalk,
          topic: 'Onboarding calibration',
          level: LivePrompts.normalizeLevel(_level),
          goal: 'tef_canada',
          durationMinutes: 3,
          lessonContext: LivePrompts.trialLessonContextFor(
            goal: 'tef_canada',
            level: _level,
            focus: const ['Speaking', 'Listening'],
            tutorName: _tutor.displayName,
          ),
          stage: 'trial',
          sessionTopic: 'Onboarding calibration · tef_canada',
          kickoffMessage: LivePrompts.trialKickoffFor(
            goal: 'tef_canada',
            level: _level,
          ),
          durationLimitSeconds: TrialCallGate.maxSeconds,
          wrapUpNote: LivePrompts.trialWrapUpNote,
          wrapUpLeadSeconds: TrialCallGate.wrapUpLeadSeconds,
          popResultImmediately: true,
          skipQuota: true,
        ),
      ),
      fullscreenDialog: true,
    );
    if (result != null) {
      await TrialCallGate.recordResult(
        durationSeconds: result.durationSeconds,
        learnerUtteranceCount: result.learnerUtteranceCount,
      );
    }
    if (result == null || !result.connected) {
      await TrialCallGate.releaseIfNeverConnected(connected: false);
    }
    if (!mounted) return;
    setState(() => _startingCheck = false);
    _go(_planPage);
  }

  Future<void> _pickReminder() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _reminder,
    );
    if (picked != null && mounted) setState(() => _reminder = picked);
  }

  Future<void> _pickExamDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _examDate ?? now.add(const Duration(days: 60)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 730)),
    );
    if (picked != null && mounted) setState(() => _examDate = picked);
  }

  Future<void> _continueFromPlan() async {
    await _requestNotifications();
    if (mounted) _go(_readyPage);
  }

  Future<void> _finish() async {
    final profile = _profile();
    ref.read(learningStoreProvider).saveProfile(profile);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('tcf_target_nclc', 7);
    if (_examDate != null) {
      await prefs.setString('tcf_exam_date', _examDate!.toIso8601String());
    } else {
      await prefs.remove('tcf_exam_date');
    }
    unawaited(NotificationSchedulerService.sync(profile));
    ProductAnalytics.capture(
      'onboarding_completed',
      properties: {
        'onboarding_version': profile.onboardingVersion,
        'level': profile.level,
        'session_length': profile.sessionLength,
        'preferred_days_count': profile.preferredDays.length,
        'has_exam_date': _examDate != null,
        'notification_permission_state': profile.notificationPermissionState,
      },
    );
    await ActiveTutor.set(_tutor);
    TutorTuning.saveLanguageMix(LearnerLevel.defaultLanguageMix(profile.level));
    AlphabetPrewarm.maybeStart(isBeginner: profile.level == 'a1');
    widget.onFinished();
  }

  @override
  Widget build(BuildContext context) {
    final onBlue = _page == _launchPage;
    final lightIcons = onBlue || DesignTokens.isDark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: lightIcons
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: onBlue
            ? AppearanceColors.blueLight
            : DesignTokens.canvas,
        body: V3Width(
          child: PageView(
            controller: _controller,
            physics: const NeverScrollableScrollPhysics(),
            onPageChanged: (page) => setState(() => _page = page),
            children: [
              _launch(),
              _welcome(),
              _levelStep(),
              _marieStep(),
              _planStep(),
              _readyStep(),
            ],
          ),
        ),
      ),
    );
  }

  // ---- 0 Launch ---------------------------------------------------------

  Widget _launch() {
    const ink = Colors.white;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppearanceColors.blueLight,
            Color.lerp(AppearanceColors.blueLight, Colors.black, 0.35)!,
          ],
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 20, 28, 36),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              V3FadeIn(
                child: Text(
                  'TCF CANADA PREP',
                  style: V3Type.eyebrow(ink.withValues(alpha: 0.85)),
                ),
              ),
              const Spacer(),
              V3FadeIn(
                delayMs: 200,
                child: Text(
                  'Parle\nSprint.',
                  style: V3Type.hero(92, color: ink),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---- 1 Welcome --------------------------------------------------------

  Widget _welcome() {
    const tests = [
      ('01', 'Listening', '39 questions · 35 min'),
      ('02', 'Reading', '39 questions · 60 min'),
      ('03', 'Writing', '3 tasks · 60 min'),
      ('04', 'Speaking', '3 tasks · 12 min'),
    ];
    return V3Screen(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ParleSprint', style: V3Type.strong(16)),
          const Spacer(),
          V3FadeIn(
            child: Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: 'Pass the\n'),
                  TextSpan(
                    text: 'TCF Canada.',
                    style: TextStyle(color: DesignTokens.primary),
                  ),
                ],
              ),
              style: V3Type.hero(60),
            ),
          ),
          const SizedBox(height: 18),
          V3FadeIn(
            delayMs: 120,
            child: Text(
              'A clear daily plan from your first French word to exam day.',
              style: V3Type.body(18),
            ),
          ),
          const SizedBox(height: 28),
          V3FadeIn(
            delayMs: 240,
            child: Column(
              children: [
                for (final t in tests)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(color: DesignTokens.hairline),
                      ),
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 36,
                          child: Text(
                            t.$1,
                            style: V3Type.strong(13, DesignTokens.primary),
                          ),
                        ),
                        Expanded(child: Text(t.$2, style: V3Type.strong(16))),
                        Text(t.$3, style: V3Type.body(13)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          V3Button(
            key: const ValueKey('onboarding.getStarted'),
            label: 'Get started',
            onTap: _next,
          ),
        ],
      ),
    );
  }

  // ---- 2 Level ----------------------------------------------------------

  Widget _levelStep() {
    const levels = [
      ('a1', 'A1', 'Starting from zero', 'I can say hello and a few words'),
      ('a2', 'A2', 'I know the basics', 'Simple phrases and daily needs'),
      (
        'b1',
        'B1',
        'I can hold a conversation',
        'Familiar topics, some mistakes',
      ),
      ('b2', 'B2', 'Close to exam level', 'I need TCF practice and speed'),
    ];
    return V3Screen(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _stepHeader(0),
          const SizedBox(height: 28),
          Text('How much French\ndo you know?', style: V3Type.title(36)),
          const SizedBox(height: 10),
          Text('We will start you in the right place.', style: V3Type.body(16)),
          const SizedBox(height: 22),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                for (final l in levels) ...[
                  V3OptionCard(
                    key: ValueKey('onboarding.level.${l.$1}'),
                    leading: l.$2,
                    title: l.$3,
                    subtitle: l.$4,
                    selected: _level == l.$1,
                    onTap: () => setState(() => _level = l.$1),
                  ),
                  const SizedBox(height: 10),
                ],
                V3TextAction(
                  key: const ValueKey('onboarding.notSure'),
                  label: 'Not sure? Let Marie check',
                  onTap: () {
                    setState(() => _level = 'a1');
                    _go(_mariePage);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          V3Button(
            key: const ValueKey('onboarding.levelContinue'),
            label: 'Continue',
            onTap: _next,
          ),
        ],
      ),
    );
  }

  // ---- 3 Marie ----------------------------------------------------------

  Widget _marieStep() {
    return V3Screen(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _stepHeader(1),
          const SizedBox(height: 28),
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: DesignTokens.primarySoft,
              borderRadius: BorderRadius.circular(22),
            ),
            alignment: Alignment.center,
            child: Text(
              _tutor.displayName.substring(0, 1),
              style: V3Type.title(30, color: DesignTokens.primary),
            ),
          ),
          const SizedBox(height: 22),
          Text(
            'Meet ${_tutor.displayName},\nyour tutor.',
            style: V3Type.title(36),
          ),
          const SizedBox(height: 12),
          Text(
            'A 3-minute chat helps ${_tutor.displayName} find your real starting point. It is free and optional.',
            style: V3Type.body(17),
          ),
          const SizedBox(height: 24),
          for (final line in const [
            'Speak out loud. No pressure, no grade.',
            'Stop any time.',
            'Your voice is sent to Google to run the conversation.',
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 7, right: 12),
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: DesignTokens.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  Expanded(child: Text(line, style: V3Type.body(15))),
                ],
              ),
            ),
          const Spacer(),
          V3Button(
            key: const ValueKey('onboarding.marieStart'),
            label: _startingCheck
                ? 'Connecting to ${_tutor.displayName}'
                : 'Start 3-minute check',
            loading: _startingCheck,
            onTap: _startCheck,
          ),
          const SizedBox(height: 4),
          V3TextAction(
            key: const ValueKey('onboarding.marieSkip'),
            label: 'Skip for now',
            onTap: _startingCheck ? null : () => _go(_planPage),
          ),
        ],
      ),
    );
  }

  // ---- 4 Rhythm ---------------------------------------------------------

  Widget _planStep() {
    const dayList = [
      ('mon', 'M'),
      ('tue', 'T'),
      ('wed', 'W'),
      ('thu', 'T'),
      ('fri', 'F'),
      ('sat', 'S'),
      ('sun', 'S'),
    ];
    final examLabel = _examDate == null
        ? 'Add date'
        : '${_examDate!.year}-${_examDate!.month.toString().padLeft(2, '0')}-${_examDate!.day.toString().padLeft(2, '0')}';
    return V3Screen(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _stepHeader(2),
          const SizedBox(height: 28),
          Text('Set your\nstudy rhythm.', style: V3Type.title(36)),
          const SizedBox(height: 10),
          Text(
            'Short and regular beats long and rare.',
            style: V3Type.body(16),
          ),
          const SizedBox(height: 26),
          Text('MINUTES PER DAY', style: V3Type.eyebrow(DesignTokens.inkSoft)),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final m in const ['5', '10', '15', '20']) ...[
                Expanded(
                  child: V3Pressable(
                    key: ValueKey('onboarding.minutes.$m'),
                    label: '$m minutes',
                    onTap: () => setState(() => _minutes = m),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      height: 52,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _minutes == m
                            ? DesignTokens.primary
                            : DesignTokens.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: _minutes == m
                              ? DesignTokens.primary
                              : DesignTokens.hairline,
                        ),
                      ),
                      child: Text(
                        m,
                        style: V3Type.strong(
                          17,
                          _minutes == m
                              ? DesignTokens.onPrimary
                              : DesignTokens.ink,
                        ),
                      ),
                    ),
                  ),
                ),
                if (m != '20') const SizedBox(width: 8),
              ],
            ],
          ),
          const SizedBox(height: 24),
          Text('DAYS', style: V3Type.eyebrow(DesignTokens.inkSoft)),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final d in dayList)
                V3Pressable(
                  key: ValueKey('onboarding.day.${d.$1}'),
                  label: d.$1,
                  onTap: () => setState(() {
                    if (!_days.remove(d.$1)) _days.add(d.$1);
                  }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _days.contains(d.$1)
                          ? DesignTokens.primary
                          : DesignTokens.surface,
                      border: Border.all(
                        color: _days.contains(d.$1)
                            ? DesignTokens.primary
                            : DesignTokens.hairline,
                      ),
                    ),
                    child: Text(
                      d.$2,
                      style: V3Type.strong(
                        14,
                        _days.contains(d.$1)
                            ? DesignTokens.onPrimary
                            : DesignTokens.ink,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),
          _valueRow(
            key: const ValueKey('onboarding.reminder'),
            label: 'Reminder',
            value: _reminder.format(context),
            onTap: _pickReminder,
          ),
          _valueRow(
            key: const ValueKey('onboarding.examDate'),
            label: 'Exam date (optional)',
            value: examLabel,
            onTap: _pickExamDate,
          ),
          const Spacer(),
          V3Button(
            key: const ValueKey('onboarding.planContinue'),
            label: 'Continue',
            onTap: _days.isEmpty ? null : _continueFromPlan,
          ),
        ],
      ),
    );
  }

  Widget _valueRow({
    required Key key,
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return V3Pressable(
      key: key,
      label: '$label, $value',
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: DesignTokens.hairline)),
        ),
        child: Row(
          children: [
            Expanded(child: Text(label, style: V3Type.strong(16))),
            Text(value, style: V3Type.body(16, DesignTokens.primary)),
            const SizedBox(width: 6),
            Icon(
              Icons.chevron_right_rounded,
              color: DesignTokens.inkSoft,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  // ---- 5 Plan ready -----------------------------------------------------

  Widget _readyStep() {
    final levelLabel = LearnerLevel.displayLabel(_level);
    return V3Screen(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _stepHeader(3),
          const SizedBox(height: 28),
          Text('Your plan\nis ready.', style: V3Type.hero(48)),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
            decoration: BoxDecoration(
              color: DesignTokens.surface,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: DesignTokens.hairline),
              boxShadow: DesignTokens.surfaceShadow,
            ),
            child: Column(
              children: [
                _fact('Starting level', levelLabel),
                _fact('Exam target', 'NCLC 7', color: DesignTokens.mastery),
                _fact('Study rhythm', '$_minutes min · ${_days.length} days'),
                _fact('Reminder', _reminder.format(context), last: true),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Everything is in a fixed order, so you always know what comes next.',
            style: V3Type.body(15),
          ),
          const Spacer(),
          V3Button(
            key: const ValueKey('onboarding.finish'),
            label: 'Create my account',
            onTap: _finish,
          ),
        ],
      ),
    );
  }

  Widget _fact(String label, String value, {Color? color, bool last = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        border: last
            ? null
            : Border(bottom: BorderSide(color: DesignTokens.hairline)),
      ),
      child: Row(
        children: [
          Expanded(child: Text(label, style: V3Type.body(15))),
          Text(value, style: V3Type.strong(16, color)),
        ],
      ),
    );
  }

  Widget _stepHeader(int index) {
    return Row(
      children: [
        Expanded(
          child: V3Segments(count: _stepCount, current: index),
        ),
        const SizedBox(width: 16),
        Text('${index + 1}/$_stepCount', style: V3Type.body(13)),
      ],
    );
  }
}
