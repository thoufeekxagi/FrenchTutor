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

/// Screen: V3 onboarding. Key prefix: onboarding.
/// User arrived to: a fresh install of the TCF Canada course.
/// They must understand: one course, one TCF goal, four skills, and Marie.
/// Primary action: continue through the short value story and choose a level.
/// Secondary action: skip the optional exam date or reminder setup.
/// Success state: preferences saved, then consent and account gates.
/// Must not contain: extra profile questions, unsupported community claims, fake data.
/// States: default, loading during reminder save, interrupted, completed.
class V3OnboardingFlow extends ConsumerStatefulWidget {
  const V3OnboardingFlow({super.key, required this.onFinished});

  final VoidCallback onFinished;

  @override
  ConsumerState<V3OnboardingFlow> createState() => _V3OnboardingFlowState();
}

class _V3OnboardingFlowState extends ConsumerState<V3OnboardingFlow> {
  static const _greetingPage = 0;
  static const _coursePage = 1;
  static const _practicePage = 3;
  static const _valueStepCount = 4;
  static const _setupStepCount = 3;

  static const _weekdays = [
    ('mon', 'M', 'Monday'),
    ('tue', 'T', 'Tuesday'),
    ('wed', 'W', 'Wednesday'),
    ('thu', 'T', 'Thursday'),
    ('fri', 'F', 'Friday'),
    ('sat', 'S', 'Saturday'),
    ('sun', 'S', 'Sunday'),
  ];

  final _controller = PageController();
  var _page = _greetingPage;
  String? _level;
  DateTime? _examDate;
  TimeOfDay? _reminderTime;
  final _preferredDays = <String>{};
  var _notificationPermissionState = 'not_requested';
  var _savingReminders = false;
  final _tutor = TutorPersona.defaultPersona;

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

  Profile _profile() {
    return ref.read(learningStoreProvider).profile()
      ..goal = 'tef_canada'
      ..level = _level ?? 'a1'
      ..reminderTime = _reminderTime == null
          ? null
          : _wireReminderTime(_reminderTime!)
      ..preferredDays = [
        for (final day in _weekdays)
          if (_preferredDays.contains(day.$1)) day.$1,
      ]
      ..timeZone = _timeZoneValue()
      ..notificationPermissionState = _notificationPermissionState
      ..interests = const ['Listening', 'Speaking', 'Writing', 'Reading']
      ..onboardingVersion = 'v3-tcf-onboarding'
      ..onboardedAt = DateTime.now();
  }

  Future<void> _finish() async {
    final profile = _profile();
    ref.read(learningStoreProvider).saveProfile(profile);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('tcf_target_nclc', 7);
    if (_examDate == null) {
      await prefs.remove('tcf_exam_date');
    } else {
      await prefs.setString('tcf_exam_date', _examDate!.toIso8601String());
    }
    await prefs.setBool('onboarding_trial_pending', true);
    await NotificationSchedulerService.sync(profile);
    ProductAnalytics.capture(
      'onboarding_completed',
      properties: {
        'onboarding_version': profile.onboardingVersion,
        'level': profile.level,
        'has_exam_date': _examDate != null,
        'preferred_days_count': profile.preferredDays.length,
        'notification_permission_state': profile.notificationPermissionState,
      },
    );
    await ActiveTutor.set(_tutor);
    final selectedLevel = profile.level;
    TutorTuning.saveLanguageMix(LearnerLevel.defaultLanguageMix(selectedLevel));
    AlphabetPrewarm.maybeStart(isBeginner: selectedLevel == 'a1');
    widget.onFinished();
  }

  Future<void> _pickExamDate() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: _examDate ?? today.add(const Duration(days: 60)),
      firstDate: today,
      lastDate: today.add(const Duration(days: 730)),
    );
    if (picked != null && mounted) setState(() => _examDate = picked);
  }

  Future<void> _pickReminderTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _reminderTime ?? const TimeOfDay(hour: 19, minute: 0),
    );
    if (picked != null && mounted) setState(() => _reminderTime = picked);
  }

  Future<void> _saveReminders() async {
    if (_savingReminders || _reminderTime == null || _preferredDays.isEmpty) {
      return;
    }
    setState(() => _savingReminders = true);
    ProductAnalytics.capture('notification_permission_prompted');
    final permission = await NotificationPermissionService.request();
    if (!mounted) return;
    setState(() => _notificationPermissionState = permission);
    ProductAnalytics.capture(
      'notification_permission_result',
      properties: {'state': permission},
    );
    await _finish();
  }

  String _wireReminderTime(TimeOfDay time) =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

  String _timeZoneValue() {
    final now = DateTime.now();
    final offset = now.timeZoneOffset;
    final sign = offset.isNegative ? '-' : '+';
    final hours = offset.inHours.abs().toString().padLeft(2, '0');
    final minutes = (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');
    return '${now.timeZoneName}|UTC$sign$hours:$minutes';
  }

  @override
  Widget build(BuildContext context) {
    final onBlue = _page == _coursePage || _page == _practicePage;
    final lightIcons = onBlue || DesignTokens.isDark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: lightIcons
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: onBlue
            ? AppearanceColors.blueLight
            : AppearanceColors.lightSurface,
        body: V3Width(
          child: PageView(
            controller: _controller,
            physics: const NeverScrollableScrollPhysics(),
            onPageChanged: (page) => setState(() => _page = page),
            children: [
              _helloScreen(),
              _courseScreen(),
              _goalScreen(),
              _practiceScreen(),
              _examDateStep(),
              _levelStep(),
              _remindersStep(),
            ],
          ),
        ),
      ),
    );
  }

  // ---- 1 Animated greeting ---------------------------------------------

  Widget _helloScreen() => _GreetingIntro(onContinue: _next);

  // ---- 2 One clear course ----------------------------------------------

  Widget _courseScreen() {
    return V3Screen(
      background: AppearanceColors.blueLight,
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _OnboardingHeader(
            index: 1,
            count: _valueStepCount,
            color: Colors.white,
            inverted: true,
          ),
          const Spacer(),
          V3FadeIn(
            child: Text(
              'One clear course.',
              style: V3Type.hero(46, color: Colors.white),
            ),
          ),
          const SizedBox(height: 10),
          V3FadeIn(
            delayMs: 100,
            child: Text(
              'A guided French path.',
              style: V3Type.body(19, Colors.white.withValues(alpha: 0.9)),
            ),
          ),
          const Spacer(),
          _courseLevelPath(),
          const Spacer(),
          _OnboardingCTA(
            key: const ValueKey('onboarding.courseContinue'),
            label: 'Continue',
            onTap: _next,
            background: AppearanceColors.blueLight,
            foreground: Colors.white,
          ),
        ],
      ),
    );
  }

  Widget _courseLevelPath() {
    const levels = ['A1', 'A2', 'B1', 'B2'];
    return Row(
      children: [
        for (final level in levels)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Container(
                constraints: const BoxConstraints(minHeight: 58),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text(
                  level,
                  style: V3Type.strong(17, AppearanceColors.blueDeep),
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ---- 3 One goal: TCF Canada ------------------------------------------

  Widget _goalScreen() {
    const skills = [
      (Icons.hearing_rounded, 'Listening'),
      (Icons.record_voice_over_rounded, 'Speaking'),
      (Icons.menu_book_rounded, 'Reading'),
      (Icons.edit_note_rounded, 'Writing'),
    ];
    return V3Screen(
      background: AppearanceColors.lightSurface,
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _OnboardingHeader(
            index: 2,
            count: _valueStepCount,
            color: AppearanceColors.blueDeep,
          ),
          const SizedBox(height: 30),
          V3FadeIn(
            child: Text(
              'One goal:\nTCF Canada.',
              style: V3Type.hero(46, color: AppearanceColors.blueDeep),
            ),
          ),
          const SizedBox(height: 28),
          for (var i = 0; i < skills.length; i++)
            _skillRow(
              icon: skills[i].$1,
              label: skills[i].$2,
              color: AppearanceColors.blueDeep,
              divider: i != skills.length - 1,
            ),
          const Spacer(),
          _OnboardingCTA(
            key: const ValueKey('onboarding.goalContinue'),
            label: 'Continue',
            onTap: _next,
            background: AppearanceColors.blueLight,
            foreground: Colors.white,
          ),
        ],
      ),
    );
  }

  // ---- 4 Practice with Marie -------------------------------------------

  Widget _practiceScreen() {
    return V3Screen(
      background: AppearanceColors.blueLight,
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _OnboardingHeader(
            index: 3,
            count: _valueStepCount,
            color: Colors.white,
            inverted: true,
          ),
          const Spacer(),
          const Center(child: _VoiceWave(color: Colors.white)),
          const SizedBox(height: 40),
          V3FadeIn(
            child: Text(
              'Practice every lesson with Marie.',
              style: V3Type.hero(42, color: Colors.white),
            ),
          ),
          const SizedBox(height: 12),
          V3FadeIn(
            delayMs: 100,
            child: Text(
              'Learn with confidence, guided by Marie.',
              style: V3Type.body(19, Colors.white.withValues(alpha: 0.9)),
            ),
          ),
          const Spacer(),
          _OnboardingCTA(
            key: const ValueKey('onboarding.practiceContinue'),
            label: 'Continue',
            onTap: _next,
            background: Colors.white,
            foreground: AppearanceColors.blueDeep,
          ),
        ],
      ),
    );
  }

  Widget _skillRow({
    required IconData icon,
    required String label,
    required Color color,
    required bool divider,
  }) {
    return Container(
      constraints: const BoxConstraints(minHeight: 54),
      decoration: BoxDecoration(
        border: divider
            ? Border(bottom: BorderSide(color: AppearanceColors.lightHairline))
            : null,
      ),
      child: Row(
        children: [
          Icon(icon, size: 21, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: V3Type.strong(16, AppearanceColors.lightText),
            ),
          ),
        ],
      ),
    );
  }

  // ---- 5 Estimated exam date -------------------------------------------

  Widget _examDateStep() {
    return V3Screen(
      background: AppearanceColors.lightSurface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _stepHeader(0),
          const SizedBox(height: 24),
          Text(
            'When is your TCF Canada exam?',
            style: V3Type.title(34, color: AppearanceColors.lightText),
          ),
          const SizedBox(height: 20),
          V3OptionCard(
            key: const ValueKey('onboarding.examDate'),
            title: _examDate == null
                ? 'Choose an estimated date'
                : MaterialLocalizations.of(
                    context,
                  ).formatMediumDate(_examDate!),
            selected: _examDate != null,
            onTap: _pickExamDate,
          ),
          const Spacer(),
          V3Button(
            key: const ValueKey('onboarding.examDateContinue'),
            label: 'Continue',
            onTap: _next,
          ),
          V3TextAction(
            key: const ValueKey('onboarding.examDateSkip'),
            label: 'Skip for now',
            onTap: () {
              setState(() => _examDate = null);
              _next();
            },
          ),
        ],
      ),
    );
  }

  // ---- 6 Current level --------------------------------------------------

  Widget _levelStep() {
    const levels = [('a1', 'A1'), ('a2', 'A2'), ('b1', 'B1'), ('b2', 'B2')];
    return V3Screen(
      background: AppearanceColors.lightSurface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _stepHeader(1),
          const SizedBox(height: 24),
          Text(
            'What is your current French level?',
            style: V3Type.title(34, color: AppearanceColors.lightText),
          ),
          const SizedBox(height: 22),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                for (final level in levels) ...[
                  V3OptionCard(
                    key: ValueKey('onboarding.level.${level.$1}'),
                    title: level.$2,
                    selected: _level == level.$1,
                    onTap: () => setState(() => _level = level.$1),
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          V3Button(
            key: const ValueKey('onboarding.levelContinue'),
            label: 'Continue',
            onTap: _level == null ? null : _next,
          ),
        ],
      ),
    );
  }

  // ---- 7 Learning reminders --------------------------------------------

  Widget _remindersStep() {
    return V3Screen(
      background: AppearanceColors.lightSurface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _stepHeader(2),
          const SizedBox(height: 24),
          Text(
            'Set a learning reminder',
            style: V3Type.title(34, color: AppearanceColors.lightText),
          ),
          const SizedBox(height: 28),
          Text('DAYS', style: V3Type.eyebrow(AppearanceColors.lightMuted)),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final day in _weekdays)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _weekdayButton(day.$1, day.$2, day.$3),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text('TIME', style: V3Type.eyebrow(AppearanceColors.lightMuted)),
          const SizedBox(height: 10),
          V3OptionCard(
            key: const ValueKey('onboarding.reminderTime'),
            title: _reminderTime?.format(context) ?? 'Choose a time',
            selected: _reminderTime != null,
            onTap: _pickReminderTime,
          ),
          const Spacer(),
          V3Button(
            key: const ValueKey('onboarding.remindersSave'),
            label: 'Save reminders',
            onTap: _reminderTime == null || _preferredDays.isEmpty
                ? null
                : _saveReminders,
            loading: _savingReminders,
          ),
          V3TextAction(
            key: const ValueKey('onboarding.remindersSkip'),
            label: 'Skip for now',
            onTap: _savingReminders
                ? null
                : () {
                    setState(() {
                      _reminderTime = null;
                      _preferredDays.clear();
                      _notificationPermissionState = 'not_requested';
                    });
                    unawaited(_finish());
                  },
          ),
        ],
      ),
    );
  }

  Widget _weekdayButton(String value, String label, String dayName) {
    final selected = _preferredDays.contains(value);
    return V3Pressable(
      key: ValueKey('onboarding.reminderDay.$value'),
      label: dayName,
      onTap: () => setState(() {
        if (selected) {
          _preferredDays.remove(value);
        } else {
          _preferredDays.add(value);
        }
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? AppearanceColors.blueLight : Colors.white,
          border: Border.all(
            color: selected
                ? AppearanceColors.blueLight
                : AppearanceColors.lightHairline,
          ),
        ),
        child: Text(
          label,
          style: V3Type.strong(
            14,
            selected ? Colors.white : AppearanceColors.lightText,
          ),
        ),
      ),
    );
  }

  Widget _stepHeader(int index) {
    return Row(
      children: [
        Expanded(
          child: V3Segments(count: _setupStepCount, current: index),
        ),
        const SizedBox(width: 16),
        Text(
          '${index + 1}/$_setupStepCount',
          style: V3Type.body(13, AppearanceColors.lightMuted),
        ),
      ],
    );
  }
}

class _GreetingIntro extends StatefulWidget {
  const _GreetingIntro({required this.onContinue});

  final VoidCallback onContinue;

  @override
  State<_GreetingIntro> createState() => _GreetingIntroState();
}

class _GreetingIntroState extends State<_GreetingIntro> {
  static const _greetings = ['Hello', 'Bonjour', 'Salut', 'Bienvenue'];

  Timer? _timer;
  var _index = 0;
  var _disableAnimations = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _disableAnimations = MediaQuery.of(context).disableAnimations;
    if (_disableAnimations) {
      _timer?.cancel();
      _timer = null;
      _index = 0;
    } else if (_timer == null && _index < _greetings.length - 1) {
      _timer = Timer.periodic(const Duration(milliseconds: 1150), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        setState(() => _index++);
        if (_index == _greetings.length - 1) {
          timer.cancel();
          _timer = null;
        }
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isBlue = _index.isOdd;
    final background = isBlue
        ? AppearanceColors.blueLight
        : AppearanceColors.lightSurface;
    final foreground = isBlue ? Colors.white : AppearanceColors.blueDeep;
    final duration = _disableAnimations
        ? Duration.zero
        : const Duration(milliseconds: 320);

    return Scaffold(
      backgroundColor: background,
      body: AnimatedContainer(
        duration: duration,
        curve: Curves.easeOutCubic,
        color: background,
        child: AnnotatedRegion<SystemUiOverlayStyle>(
          value: isBlue
              ? SystemUiOverlayStyle.light
              : SystemUiOverlayStyle.dark,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _OnboardingHeader(
                    index: 0,
                    count: _valueStepCount,
                    color: foreground,
                    inverted: isBlue,
                  ),
                  const Spacer(),
                  SizedBox(
                    width: double.infinity,
                    height: 112,
                    child: AnimatedSwitcher(
                      duration: duration,
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.08),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      ),
                      child: Align(
                        key: ValueKey(_greetings[_index]),
                        alignment: Alignment.centerLeft,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            _greetings[_index],
                            maxLines: 1,
                            style: V3Type.hero(84, color: foreground),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  _OnboardingCTA(
                    key: const ValueKey('onboarding.helloContinue'),
                    label: 'Continue',
                    onTap: widget.onContinue,
                    background: isBlue
                        ? Colors.white
                        : AppearanceColors.blueLight,
                    foreground: isBlue
                        ? AppearanceColors.blueDeep
                        : Colors.white,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OnboardingHeader extends StatelessWidget {
  const _OnboardingHeader({
    required this.index,
    required this.count,
    required this.color,
    this.inverted = false,
  });

  final int index;
  final int count;
  final Color color;
  final bool inverted;

  @override
  Widget build(BuildContext context) {
    final inactive = color.withValues(alpha: inverted ? 0.32 : 0.14);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 28,
              height: 28,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Image.asset(
                'assets/images/parlesprint_app_icon.png',
                fit: BoxFit.contain,
                excludeFromSemantics: true,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text('ParleSprint', style: V3Type.strong(15, color)),
            ),
            Text(
              '${(index + 1).toString().padLeft(2, '0')} / ${count.toString().padLeft(2, '0')}',
              style: V3Type.eyebrow(color),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            for (var i = 0; i < count; i++) ...[
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 280),
                  height: 3,
                  decoration: BoxDecoration(
                    color: i <= index ? color : inactive,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              if (i < count - 1) const SizedBox(width: 6),
            ],
          ],
        ),
      ],
    );
  }
}

class _OnboardingCTA extends StatelessWidget {
  const _OnboardingCTA({
    super.key,
    required this.label,
    required this.onTap,
    required this.background,
    required this.foreground,
  });

  final String label;
  final VoidCallback onTap;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return V3Pressable(
      label: label,
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 58),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Expanded(child: Text(label, style: V3Type.strong(16, foreground))),
            Icon(Icons.arrow_forward_rounded, size: 22, color: foreground),
          ],
        ),
      ),
    );
  }
}

class _VoiceWave extends StatelessWidget {
  const _VoiceWave({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    const heights = [18.0, 30.0, 42.0, 26.0, 36.0, 20.0, 32.0];
    return ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (final height in heights)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Container(
                width: 4,
                height: height,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Screen: post-sign-in Marie practice. Key prefix: onboarding.trial.
/// User arrived to: a new account after TCF onboarding and AI consent.
/// They must understand: a short voice practice is optional and uses audio.
/// Primary action: start the three-minute practice with Marie.
/// Secondary action: continue to the course without the practice.
/// Success state: trial ends and the learner enters the course.
/// Must not contain: score promises, pressure, or hidden audio use.
/// States: default, connecting, interrupted, completed.
class V3OnboardingTrialOffer extends ConsumerStatefulWidget {
  const V3OnboardingTrialOffer({super.key, required this.onComplete});

  final VoidCallback onComplete;

  @override
  ConsumerState<V3OnboardingTrialOffer> createState() =>
      _V3OnboardingTrialOfferState();
}

class _V3OnboardingTrialOfferState
    extends ConsumerState<V3OnboardingTrialOffer> {
  final _tutor = TutorPersona.defaultPersona;
  var _starting = false;

  Future<void> _startPractice() async {
    if (_starting) return;
    setState(() => _starting = true);
    final profile = ref.read(learningStoreProvider).profile();
    final level = profile.level;
    final goal = profile.goal;
    await ActiveTutor.set(_tutor);
    await TrialCallGate.markStarted();
    if (!mounted) {
      await TrialCallGate.releaseIfNeverConnected(connected: false);
      return;
    }

    SpeakingResult? result;
    try {
      result = await AppRouter.push<SpeakingResult>(
        context,
        (_) => SpeakingPracticeScreen(
          autoStart: true,
          request: SpeakingPracticeRequest(
            mode: SpeakingMode.freeTalk,
            topic: 'Onboarding calibration',
            level: LivePrompts.normalizeLevel(level),
            goal: goal,
            durationMinutes: 3,
            lessonContext: LivePrompts.trialLessonContextFor(
              goal: goal,
              level: level,
              focus: const ['Speaking', 'Listening'],
              tutorName: _tutor.displayName,
            ),
            stage: 'trial',
            sessionTopic: 'Onboarding calibration · $goal',
            kickoffMessage: LivePrompts.trialKickoffFor(
              goal: goal,
              level: level,
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
    } catch (_) {
      await TrialCallGate.releaseIfNeverConnected(connected: false);
      if (mounted) setState(() => _starting = false);
      return;
    }

    if (result != null) {
      await TrialCallGate.recordResult(
        durationSeconds: result.durationSeconds,
        learnerUtteranceCount: result.learnerUtteranceCount,
      );
    }
    if (result == null || !result.connected) {
      await TrialCallGate.releaseIfNeverConnected(connected: false);
    }
    if (mounted) widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    return V3Screen(
      background: AppearanceColors.lightSurface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Image.asset(
                  'assets/images/parlesprint_app_icon.png',
                  excludeFromSemantics: true,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'ParleSprint',
                style: V3Type.strong(16, AppearanceColors.blueDeep),
              ),
            ],
          ),
          const Spacer(),
          const Center(child: _VoiceWave(color: AppearanceColors.blueLight)),
          const SizedBox(height: 36),
          Text(
            'Try Marie for 3 minutes.',
            style: V3Type.title(36, color: AppearanceColors.lightText),
          ),
          const SizedBox(height: 10),
          Text('Speak with confidence.', style: V3Type.body(18)),
          const SizedBox(height: 22),
          Text(
            'Your voice is sent to Google for this practice.',
            style: V3Type.body(13, AppearanceColors.lightMuted),
          ),
          const Spacer(),
          V3Button(
            key: const ValueKey('onboarding.trial.start'),
            label: 'Start 3-minute practice',
            loading: _starting,
            onTap: _starting ? null : _startPractice,
          ),
          V3TextAction(
            key: const ValueKey('onboarding.trial.skip'),
            label: 'Start learning',
            onTap: _starting ? null : widget.onComplete,
          ),
        ],
      ),
    );
  }
}
