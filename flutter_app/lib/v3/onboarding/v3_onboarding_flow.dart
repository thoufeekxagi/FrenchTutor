import '../v3_cloud_state.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
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
import '../../services/alphabet_prewarm.dart';
import '../../services/notification_permission_service.dart';
import '../../services/notification_scheduler_service.dart';
import '../../services/product_analytics.dart';
import '../../services/trial_call_gate.dart';
import '../marie/v3_call_screen.dart';
import '../marie/v3_marie_session.dart';
import '../tutors/v3_tutor_picker_sheet.dart';
import '../ui/v3_ui.dart';

/// Screen: V3 onboarding. Key prefix: onboarding.
/// User arrived to: a fresh install of the TCF Canada course.
/// They must understand: one guided French course, one TCF Canada goal, four
/// exam skills, and personal speaking practice with the learner's chosen tutor.
/// Primary action: continue through three concise value screens, then choose a
/// level or keep the A1 default and continue through optional study details.
/// Secondary action: skip the optional name, exam date or reminder step from
/// the top-right header.
/// Success state: preferences saved, then consent and account gates.
/// Must not contain: extra profile questions, unsupported community claims,
/// fake data, static decorative motion, nested input outlines, or bottom skips.
/// States: default, loading during reminder save, interrupted, completed.
/// The words on the last onboarding screen. Pure, so every combination of
/// name, exam date and reminder can be tested. It never promises a result: it
/// says ParleSprint will help the learner get ready.
class OnboardingPledgeCopy {
  const OnboardingPledgeCopy({
    required this.title,
    required this.body,
    required this.commitment,
  });

  final String title;
  final String body;
  final String commitment;

  static const _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  static const _dayNames = {
    'mon': 'Monday',
    'tue': 'Tuesday',
    'wed': 'Wednesday',
    'thu': 'Thursday',
    'fri': 'Friday',
    'sat': 'Saturday',
    'sun': 'Sunday',
  };

  static String examDate(DateTime d) =>
      '${_months[d.month - 1]} ${d.day}, ${d.year}';

  /// "every day", "Monday to Friday", or "Mon, Wed, Fri" in week order.
  static String daysLabel(Iterable<String> dayIds) {
    final chosen = [
      for (final id in _dayNames.keys)
        if (dayIds.contains(id)) id,
    ];
    if (chosen.length == 7) return 'every day';
    if (chosen.length == 5 &&
        !chosen.contains('sat') &&
        !chosen.contains('sun')) {
      return 'Monday to Friday';
    }
    return chosen.map((id) => _dayNames[id]!.substring(0, 3)).join(', ');
  }

  static OnboardingPledgeCopy build({
    required String name,
    DateTime? exam,
    String? timeLabel,
    Iterable<String> dayIds = const [],
  }) {
    final who = name.trim();
    final days = dayIds.toSet();
    final hasPlan =
        timeLabel != null && timeLabel.isNotEmpty && days.isNotEmpty;
    return OnboardingPledgeCopy(
      title: who.isEmpty ? 'Welcome,' : 'Dear $who,',
      body: exam == null
          ? 'ParleSprint is proud to help you get ready for the TCF Canada exam.'
          : 'ParleSprint is proud to help you get ready for your TCF Canada exam on ${examDate(exam)}.',
      commitment: hasPlan
          ? 'Your daily commitment: $timeLabel, ${daysLabel(days)}.'
          : 'Your commitment: one lesson at a time, at your own pace.',
    );
  }
}

ThemeData _onboardingPalette(ThemeData theme) => theme.copyWith(
  brightness: Brightness.light,
  primaryColor: AppearanceColors.blueLight,
  scaffoldBackgroundColor: AppearanceColors.lightSurface,
  colorScheme: theme.colorScheme.copyWith(
    brightness: Brightness.light,
    primary: AppearanceColors.blueLight,
    onPrimary: Colors.white,
    secondary: AppearanceColors.blueLight,
    onSecondary: Colors.white,
    surface: AppearanceColors.lightSurface,
    onSurface: AppearanceColors.lightText,
  ),
  textTheme: theme.textTheme.apply(
    bodyColor: AppearanceColors.lightText,
    displayColor: AppearanceColors.lightText,
  ),
);

class V3OnboardingFlow extends ConsumerStatefulWidget {
  const V3OnboardingFlow({super.key, required this.onFinished});

  final VoidCallback onFinished;

  @override
  ConsumerState<V3OnboardingFlow> createState() => _V3OnboardingFlowState();
}

class _V3OnboardingFlowState extends ConsumerState<V3OnboardingFlow>
    with TickerProviderStateMixin {
  static const _greetingPage = 0;
  static const _coursePage = 1;
  static const _practicePage = 3;
  static const _pledgePage = 8;
  static const _pageCount = 9;

  /// Pages drawn in the blue brand colour; the others are white.
  static const _bluePages = {_coursePage, _practicePage, _pledgePage};
  static const _pagePadding = EdgeInsets.fromLTRB(24, 64, 24, 20);

  static const _weekdays = [
    ('mon', 'M', 'Monday'),
    ('tue', 'T', 'Tuesday'),
    ('wed', 'W', 'Wednesday'),
    ('thu', 'T', 'Thursday'),
    ('fri', 'F', 'Friday'),
    ('sat', 'S', 'Saturday'),
    ('sun', 'S', 'Sunday'),
  ];

  final _nameController = TextEditingController();
  final _nameFocusNode = FocusNode();
  late final AnimationController _roadmapMotion;
  late final AnimationController _voiceWaveMotion;
  var _page = _greetingPage;
  var _finishing = false;
  var _nameFocused = false;
  String? _level;
  DateTime? _examDate;
  TimeOfDay? _reminderTime;
  final _preferredDays = <String>{};
  var _notificationPermissionState = 'not_requested';
  var _savingReminders = false;
  late TutorPersona _tutor;

  @override
  void initState() {
    super.initState();
    _tutor = ActiveTutor.current;
    _roadmapMotion = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 7600),
    );
    _voiceWaveMotion = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );
    _nameFocusNode.addListener(_nameFocusChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotionForPage(
      _page,
      reduceMotion: MediaQuery.of(context).disableAnimations,
    );
  }

  void _nameFocusChanged() {
    if (!mounted || _nameFocused == _nameFocusNode.hasFocus) return;
    setState(() => _nameFocused = _nameFocusNode.hasFocus);
  }

  void _syncMotionForPage(int page, {required bool reduceMotion}) {
    void sync(
      AnimationController controller,
      bool active, {
      bool reverse = false,
    }) {
      if (!active || reduceMotion) {
        controller.stop();
        controller.value = 0;
      } else if (!controller.isAnimating) {
        controller.repeat(reverse: reverse);
      }
    }

    sync(_roadmapMotion, page == _coursePage);
    sync(_voiceWaveMotion, page == _practicePage, reverse: true);
  }

  @override
  void dispose() {
    _nameFocusNode.removeListener(_nameFocusChanged);
    _nameFocusNode.dispose();
    _nameController.dispose();
    _roadmapMotion.dispose();
    _voiceWaveMotion.dispose();
    super.dispose();
  }

  void _go(int page) {
    FocusManager.instance.primaryFocus?.unfocus();
    final nextPage = page.clamp(0, _pageCount - 1);
    if (nextPage == _page) return;
    _syncMotionForPage(
      nextPage,
      reduceMotion: MediaQuery.of(context).disableAnimations,
    );
    setState(() => _page = nextPage);
  }

  void _back() => _go(_page - 1);

  void _next() => _go(_page + 1);

  Future<void> _chooseTutor() async {
    final picked = await showV3TutorPickerSheet(
      context: context,
      selected: _tutor,
    );
    if (picked == null || !mounted) return;
    // Saved at once: quitting mid-onboarding must not forget the choice.
    await ActiveTutor.set(picked);
    if (mounted) setState(() => _tutor = picked);
  }

  void _skipName() {
    _nameController.clear();
    _next();
  }

  void _skipExamDate() {
    _examDate = null;
    _next();
  }

  void _skipReminders() {
    if (_savingReminders) return;
    _reminderTime = null;
    _preferredDays.clear();
    _notificationPermissionState = 'not_requested';
    _go(_pledgePage);
  }

  VoidCallback? _skipActionFor(int page) => switch (page) {
    4 => _skipName,
    5 => _skipExamDate,
    7 => _savingReminders ? null : _skipReminders,
    _ => null,
  };

  ValueKey<String>? _skipKeyFor(int page) => switch (page) {
    4 => const ValueKey('onboarding.nameSkip'),
    5 => const ValueKey('onboarding.examDateSkip'),
    7 when !_savingReminders => const ValueKey('onboarding.remindersSkip'),
    _ => null,
  };

  Profile _profile() {
    return ref.read(learningStoreProvider).profile()
      ..goal = 'tef_canada'
      ..level = _level ?? 'a1'
      ..reminderTime = _reminderTime == null
          ? null
          : _wireReminderTime(_reminderTime!)
      ..tcfExamDate = _examDate
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
    if (_finishing) return;
    setState(() => _finishing = true);
    final profile = _profile();
    ref.read(learningStoreProvider).saveProfile(profile);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('tcf_target_nclc', 7);
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      await prefs.remove('learner_name');
    } else {
      await prefs.setString('learner_name', name);
      V3CloudState.push('learner_name');
    }
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
        'tutor_id': _tutor.id,
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
      builder: (context, child) =>
          Theme(data: _onboardingPalette(Theme.of(context)), child: child!),
    );
    if (picked != null && mounted) setState(() => _examDate = picked);
  }

  Future<void> _pickReminderTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _reminderTime ?? const TimeOfDay(hour: 19, minute: 0),
      builder: (context, child) =>
          Theme(data: _onboardingPalette(Theme.of(context)), child: child!),
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
    setState(() {
      _notificationPermissionState = permission;
      _savingReminders = false;
    });
    ProductAnalytics.capture(
      'notification_permission_result',
      properties: {'state': permission},
    );
    _go(_pledgePage);
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

  Widget _pageFor(int page) => switch (page) {
    0 => _helloScreen(),
    1 => _courseScreen(),
    2 => _goalScreen(),
    3 => _practiceScreen(),
    4 => _nameStep(),
    5 => _examDateStep(),
    6 => _levelStep(),
    7 => _remindersStep(),
    _ => _pledgeScreen(),
  };

  @override
  Widget build(BuildContext context) {
    final blue = _bluePages.contains(_page);
    final reduce = MediaQuery.of(context).disableAnimations;
    final fade = reduce ? Duration.zero : const Duration(milliseconds: 460);
    final ink = blue ? Colors.white : AppearanceColors.blueDeep;
    return Theme(
      data: _onboardingPalette(Theme.of(context)),
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: blue ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        child: Scaffold(
          backgroundColor: AppearanceColors.lightSurface,
          resizeToAvoidBottomInset: false,
          body: AnimatedContainer(
            duration: fade,
            curve: Curves.easeOutCubic,
            color: blue
                ? AppearanceColors.blueLight
                : AppearanceColors.lightSurface,
            child: V3Width(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: AnimatedSwitcher(
                      duration: fade,
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0.03, 0),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      ),
                      child: KeyedSubtree(
                        key: ValueKey(_page),
                        child: _pageFor(_page),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: SafeArea(
                      bottom: false,
                      child: _OnboardingChrome(
                        progress: _page == _greetingPage
                            ? 0
                            : (_page + 1) / _pageCount,
                        color: ink,
                        onBack: _page > _greetingPage ? _back : null,
                        onSkip: _skipActionFor(_page),
                        skipKey: _skipKeyFor(_page),
                        showMark: true,
                      ),
                    ),
                  ),
                ],
              ),
            ),
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
      background: Colors.transparent,
      padding: _pagePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Spacer(flex: 5),
          V3FadeIn(
            child: SizedBox(
              width: double.infinity,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  'One clear course.',
                  maxLines: 1,
                  softWrap: false,
                  style: V3Type.hero(46, color: Colors.white),
                ),
              ),
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
          const Spacer(flex: 2),
          Transform.translate(
            offset: const Offset(0, -10),
            child: _courseLevelPath(),
          ),
          const Spacer(flex: 3),
          _OnboardingCTA(
            key: const ValueKey('onboarding.courseContinue'),
            label: 'Continue',
            onTap: _next,
            background: Colors.white,
            foreground: AppearanceColors.blueDeep,
          ),
        ],
      ),
    );
  }

  Widget _courseLevelPath() {
    const levels = ['A1', 'A2', 'B1', 'B2'];
    final pathHeight = MediaQuery.of(context).size.height < 700 ? 245.0 : 338.0;
    return SizedBox(
      height: pathHeight,
      child: LayoutBuilder(
        builder: (context, box) {
          final size = Size(box.maxWidth, box.maxHeight);
          final points = _courseWaypoints(size);
          const labelOffsets = [
            Offset(12, 11),
            Offset(14, 10),
            Offset(-28, -31),
            Offset(13, 10),
          ];
          return AnimatedBuilder(
            animation: _roadmapMotion,
            child: SizedBox.expand(
              child: Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  for (var i = 0; i < levels.length; i++)
                    Positioned(
                      left: (points[i].dx + labelOffsets[i].dx)
                          .clamp(0.0, size.width - 36)
                          .toDouble(),
                      top: (points[i].dy + labelOffsets[i].dy)
                          .clamp(0.0, size.height - 24)
                          .toDouble(),
                      child: Text(
                        levels[i],
                        style: V3Type.strong(15, Colors.white),
                      ),
                    ),
                ],
              ),
            ),
            builder: (context, child) => CustomPaint(
              painter: _CourseRoadmapPainter(
                points: points,
                progress: _roadmapMotion.value,
              ),
              child: child,
            ),
          );
        },
      ),
    );
  }

  List<Offset> _courseWaypoints(Size size) => [
    Offset(size.width * 0.1, size.height * 0.82),
    Offset(size.width * 0.63, size.height * 0.69),
    Offset(size.width * 0.37, size.height * 0.35),
    Offset(size.width * 0.88, size.height * 0.22),
  ];

  // ---- 3 One goal: TCF Canada ------------------------------------------

  Widget _goalScreen() {
    const skills = [
      (Icons.headphones_rounded, 'Listening'),
      (Icons.mic_none_rounded, 'Speaking'),
      (Icons.menu_book_rounded, 'Reading'),
      (Icons.edit_note_rounded, 'Writing'),
    ];
    return V3Screen(
      background: Colors.transparent,
      padding: _pagePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 30),
          V3FadeIn(
            child: Text(
              'One goal:\nTCF Canada.',
              style: V3Type.hero(46, color: AppearanceColors.blueDeep),
            ),
          ),
          const SizedBox(height: 28),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                for (var i = 0; i < skills.length; i++)
                  Padding(
                    padding: EdgeInsets.only(
                      bottom: i == skills.length - 1 ? 0 : 10,
                    ),
                    child: _skillRow(icon: skills[i].$1, label: skills[i].$2),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
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

  // ---- 4 Choose a tutor -------------------------------------------------

  Widget _practiceScreen() {
    return V3Screen(
      background: Colors.transparent,
      padding: _pagePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Spacer(flex: 3),
          V3FadeIn(
            child: Text(
              'Practice every lesson with ${_tutor.displayName}.',
              style: V3Type.hero(42, color: Colors.white),
            ),
          ),
          const SizedBox(height: 12),
          V3FadeIn(
            delayMs: 100,
            child: Text(
              'Pick a voice for your French practice.',
              style: V3Type.body(19, Colors.white.withValues(alpha: 0.9)),
            ),
          ),
          const Spacer(flex: 2),
          V3Pressable(
            key: const ValueKey('onboarding.tutor.choose'),
            label:
                'Choose tutor. Current choice: ${_tutor.displayName}, ${_tutor.accent.label}.',
            onTap: _chooseTutor,
            child: AnimatedContainer(
              duration: DesignTokens.durationFast,
              constraints: const BoxConstraints(minHeight: 76),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
              ),
              child: Row(
                children: [
                  ClipOval(
                    child: Image.asset(
                      _tutor.portraitAsset,
                      width: 50,
                      height: 50,
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _tutor.displayName,
                          style: V3Type.strong(16, Colors.white),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${_tutor.tagline} · ${_tutor.accent.label}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: V3Type.body(
                            12,
                            Colors.white.withValues(alpha: 0.82),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.chevron_right_rounded, color: Colors.white),
                ],
              ),
            ),
          ),
          const Spacer(),
          AnimatedBuilder(
            animation: _voiceWaveMotion,
            builder: (context, _) => Center(
              child: _VoiceWave(
                color: Colors.white,
                phase: Curves.easeInOutSine.transform(_voiceWaveMotion.value),
              ),
            ),
          ),
          const Spacer(flex: 2),
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

  Widget _skillRow({required IconData icon, required String label}) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 60),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: AppearanceColors.blueSoftLight,
        borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
      ),
      child: Row(
        children: [
          Icon(icon, size: 22, color: AppearanceColors.blueDeep),
          const SizedBox(width: 14),
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
      background: Colors.transparent,
      padding: _pagePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Text(
            'When is your TCF Canada exam?',
            style: V3Type.title(34, color: AppearanceColors.lightText),
          ),
          const SizedBox(height: 20),
          _OnboardingChoice(
            key: const ValueKey('onboarding.examDate'),
            title: _examDate == null
                ? 'Choose an estimated date'
                : MaterialLocalizations.of(
                    context,
                  ).formatMediumDate(_examDate!),
            selected: _examDate != null,
            onTap: _pickExamDate,
            trailingIcon: _examDate == null
                ? Icons.calendar_today_rounded
                : Icons.check_rounded,
          ),
          const Spacer(),
          _OnboardingCTA(
            key: const ValueKey('onboarding.examDateContinue'),
            label: 'Continue',
            onTap: _next,
            background: AppearanceColors.blueLight,
            foreground: Colors.white,
          ),
        ],
      ),
    );
  }

  // ---- 6 Current level --------------------------------------------------

  Widget _levelStep() {
    const levels = [('a1', 'A1'), ('a2', 'A2'), ('b1', 'B1'), ('b2', 'B2')];
    return V3Screen(
      background: Colors.transparent,
      padding: _pagePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
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
                  _OnboardingChoice(
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
          _OnboardingCTA(
            key: const ValueKey('onboarding.levelContinue'),
            label: 'Continue',
            // A learner who is unsure can continue; their course starts at A1.
            onTap: _next,
            background: AppearanceColors.blueLight,
            foreground: Colors.white,
          ),
        ],
      ),
    );
  }

  // ---- 7 Learning reminders --------------------------------------------

  Widget _remindersStep() {
    final hasCompleteReminder =
        _reminderTime != null && _preferredDays.isNotEmpty;
    return V3Screen(
      background: Colors.transparent,
      padding: _pagePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
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
          _OnboardingChoice(
            key: const ValueKey('onboarding.reminderTime'),
            title: _reminderTime?.format(context) ?? 'Choose a time',
            selected: _reminderTime != null,
            onTap: _pickReminderTime,
            trailingIcon: Icons.schedule_rounded,
          ),
          const Spacer(),
          _OnboardingCTA(
            key: const ValueKey('onboarding.remindersSave'),
            label: hasCompleteReminder ? 'Save reminders' : 'Continue',
            // Reminders are optional. Incomplete selections are discarded so
            // no partial schedule is persisted and no permission is requested.
            onTap: hasCompleteReminder ? _saveReminders : _skipReminders,
            background: AppearanceColors.blueLight,
            foreground: Colors.white,
            loading: _savingReminders,
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

  // ---- Name -------------------------------------------------------------

  Widget _nameStep() {
    return V3Screen(
      background: Colors.transparent,
      padding: _pagePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Text(
            'What should we call you?',
            style: V3Type.title(34, color: AppearanceColors.lightText),
          ),
          const SizedBox(height: 22),
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            constraints: const BoxConstraints(minHeight: 64),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppearanceColors.lightCanvas,
              borderRadius: BorderRadius.circular(DesignTokens.radiusLarge),
              border: Border.all(
                color: _nameFocused
                    ? AppearanceColors.blueLight
                    : AppearanceColors.lightHairline,
                width: _nameFocused ? 1.6 : 1,
              ),
            ),
            child: TextField(
              key: const ValueKey('onboarding.name'),
              controller: _nameController,
              focusNode: _nameFocusNode,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.givenName],
              inputFormatters: [LengthLimitingTextInputFormatter(30)],
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _next(),
              style: V3Type.strong(18, AppearanceColors.lightText),
              cursorColor: AppearanceColors.blueLight,
              decoration: InputDecoration(
                hintText: 'First name',
                hintStyle: V3Type.body(18, AppearanceColors.lightMuted),
                // AppTheme fills text fields by default. Keep the decoration
                // transparent so it does not draw a second rectangle inside
                // the rounded onboarding field.
                filled: false,
                fillColor: Colors.transparent,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isCollapsed: true,
              ),
            ),
          ),
          const Spacer(),
          _OnboardingCTA(
            key: const ValueKey('onboarding.nameContinue'),
            label: 'Continue',
            onTap: _next,
            background: AppearanceColors.blueLight,
            foreground: Colors.white,
          ),
        ],
      ),
    );
  }

  // ---- Pledge -----------------------------------------------------------

  Widget _pledgeScreen() {
    final copy = OnboardingPledgeCopy.build(
      name: _nameController.text,
      exam: _examDate,
      timeLabel: _reminderTime?.format(context),
      dayIds: _preferredDays,
    );
    return V3Screen(
      background: Colors.transparent,
      padding: _pagePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Spacer(),
          V3FadeIn(
            child: Text(
              copy.title,
              key: const ValueKey('onboarding.pledgeTitle'),
              style: V3Type.hero(46, color: Colors.white),
            ),
          ),
          const SizedBox(height: 18),
          V3FadeIn(
            delayMs: 150,
            child: Text(
              copy.body,
              style: V3Type.title(26, color: Colors.white),
            ),
          ),
          const SizedBox(height: 18),
          V3FadeIn(
            delayMs: 300,
            child: Text(
              copy.commitment,
              style: V3Type.body(18, Colors.white.withValues(alpha: 0.92)),
            ),
          ),
          const Spacer(),
          _OnboardingCTA(
            key: const ValueKey('onboarding.pledgeContinue'),
            label: _finishing ? 'One moment' : 'Start learning',
            onTap: () => unawaited(_finish()),
            background: Colors.white,
            foreground: AppearanceColors.blueDeep,
          ),
        ],
      ),
    );
  }
}

class _CourseRoadmapPainter extends CustomPainter {
  const _CourseRoadmapPainter({required this.points, required this.progress});

  static const _roadEdge = AppearanceColors.lightSurface;
  static const _roadSurface = AppearanceColors.lightRaised;
  static const _roadDash = AppearanceColors.lightSurface;

  final List<Offset> points;

  /// Raw, forward-only cycle progress. The traveler reaches B2, fades, then
  /// starts again at A1; it never travels backwards down the course.
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    // Build a Catmull–Rom style spline through the milestone centers. Each
    // segment derives its handles from the neighboring points, so the curve
    // changes direction gradually instead of forming hand-tuned corners.
    for (var i = 0; i < points.length - 1; i++) {
      final start = points[i];
      final end = points[i + 1];
      final before = i == 0 ? start - (end - start) : points[i - 1];
      final after = i + 2 == points.length
          ? end + (end - start)
          : points[i + 2];
      final control1 = start + (end - before) * (1 / 6);
      final control2 = end - (after - start) * (1 / 6);
      path.cubicTo(
        control1.dx,
        control1.dy,
        control2.dx,
        control2.dy,
        end.dx,
        end.dy,
      );
    }
    canvas.save();
    canvas.clipRect(Offset.zero & size);

    final metrics = path.computeMetrics().toList();
    canvas.drawPath(
      path,
      Paint()
        ..color = _roadEdge.withValues(alpha: 0.86)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 14
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = _roadSurface.withValues(alpha: 0.88)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // The fine center marks keep the route legible without making it read as
    // a wide, heavy pavement graphic.
    for (final metric in metrics) {
      for (var offset = 0.0; offset < metric.length; offset += 13) {
        final end = math.min(offset + 5.5, metric.length);
        canvas.drawPath(
          metric.extractPath(offset, end),
          Paint()
            ..color = _roadDash.withValues(alpha: 0.72)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..strokeCap = StrokeCap.round,
        );
      }
    }

    final finish = points.last;
    canvas.drawLine(
      Offset(finish.dx, finish.dy - 8),
      Offset(finish.dx, finish.dy - 28),
      Paint()
        ..color = Colors.white
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
    final flag = Path()
      ..moveTo(finish.dx + 1, finish.dy - 27)
      ..lineTo(finish.dx + 16, finish.dy - 23)
      ..lineTo(finish.dx + 1, finish.dy - 19)
      ..close();
    canvas.drawPath(flag, Paint()..color = Colors.white);

    for (final point in points) {
      canvas.drawCircle(point, 11, Paint()..color = Colors.white);
    }

    if (metrics.isNotEmpty) {
      final metric = metrics.first;
      final travelProgress = Curves.easeInOutCubic.transform(
        (progress / 0.84).clamp(0.0, 1.0).toDouble(),
      );
      final traveler = metric.getTangentForOffset(
        metric.length * travelProgress,
      );
      if (traveler != null) {
        final green = AppearanceColors.successDark;
        final travelerOpacity = (1 - ((progress - 0.86) / 0.1).clamp(0.0, 1.0))
            .toDouble();
        canvas.drawCircle(
          traveler.position,
          13,
          Paint()..color = green.withValues(alpha: 0.16 * travelerOpacity),
        );
        canvas.drawCircle(
          traveler.position,
          7.5,
          Paint()..color = green.withValues(alpha: travelerOpacity),
        );
        canvas.drawCircle(
          traveler.position,
          7.5,
          Paint()
            ..color = Colors.white.withValues(alpha: travelerOpacity)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
        canvas.drawCircle(
          traveler.position,
          2.2,
          Paint()..color = Colors.white.withValues(alpha: travelerOpacity),
        );
      }
    }

    final burstProgress = ((progress - 0.84) / 0.14).clamp(0.0, 1.0).toDouble();
    final burstOpacity = math.sin(math.pi * burstProgress);
    if (burstOpacity > 0) {
      // A small radial sparkle around the finish flag. Round points and fine
      // strokes feel celebratory while staying quiet against the blue screen.
      const rays = [
        (-2.85, 9.0, 5.0),
        (-2.35, 15.0, 6.0),
        (-1.92, 11.0, 4.0),
        (-1.48, 18.0, 6.0),
        (-1.05, 12.0, 5.0),
        (-0.62, 20.0, 6.0),
        (-0.16, 10.0, 4.0),
        (0.38, 16.0, 5.0),
      ];
      final origin = Offset(finish.dx + 1, finish.dy - 25);
      final spread = Curves.easeOutCubic.transform(burstProgress);
      for (var i = 0; i < rays.length; i++) {
        final (angle, baseRadius, baseLength) = rays[i];
        final startRadius = 2 + baseRadius * spread;
        final endRadius = startRadius + baseLength * spread;
        final direction = Offset(math.cos(angle), math.sin(angle));
        final start = origin + direction * startRadius;
        final end = origin + direction * endRadius;
        final color = i.isEven ? Colors.white : AppearanceColors.successDark;
        canvas.drawLine(
          start,
          end,
          Paint()
            ..color = color.withValues(alpha: 0.78 * burstOpacity)
            ..strokeWidth = 1.6
            ..strokeCap = StrokeCap.round,
        );
        canvas.drawCircle(
          end,
          1.4,
          Paint()..color = color.withValues(alpha: burstOpacity),
        );
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CourseRoadmapPainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.progress != progress;
}

/// First screen, as approved: a white page, the big blue greeting with the
/// next words fading below it, one short line, one button.
class _GreetingIntro extends StatefulWidget {
  const _GreetingIntro({required this.onContinue});

  final VoidCallback onContinue;

  @override
  State<_GreetingIntro> createState() => _GreetingIntroState();
}

class _GreetingIntroState extends State<_GreetingIntro> {
  static const _words = ['Hello', 'Bonjour', 'Salut'];

  Timer? _timer;
  var _lead = 0;
  var _reduce = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduce = MediaQuery.of(context).disableAnimations;
    _timer?.cancel();
    _timer = null;
    if (!_reduce) {
      // After the words have faded in, the bright one moves down the list.
      _timer = Timer.periodic(const Duration(milliseconds: 2400), (_) {
        if (mounted) setState(() => _lead = (_lead + 1) % _words.length);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  double _opacity(int i) {
    final distance = (i - _lead) % _words.length;
    return switch (distance) {
      0 => 1.0,
      1 => 0.3,
      _ => 0.14,
    };
  }

  @override
  Widget build(BuildContext context) {
    final blue = AppearanceColors.blueLight;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 64, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Spacer(flex: 2),
          for (var i = 0; i < _words.length; i++)
            V3FadeIn(
              delayMs: i * 160,
              child: AnimatedOpacity(
                duration: _reduce
                    ? Duration.zero
                    : const Duration(milliseconds: 800),
                curve: Curves.easeInOutCubic,
                opacity: _opacity(i),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _words[i],
                    maxLines: 1,
                    style: V3Type.hero(92, color: blue).copyWith(height: 0.98),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 28),
          V3FadeIn(
            delayMs: 520,
            child: Text(
              'Let’s build your French for TCF Canada.',
              style: V3Type.title(26, color: blue),
            ),
          ),
          const Spacer(flex: 3),
          _OnboardingCTA(
            key: const ValueKey('onboarding.helloContinue'),
            label: 'Continue',
            onTap: widget.onContinue,
            background: blue,
            foreground: Colors.white,
          ),
        ],
      ),
    );
  }
}

/// One header for every screen: the mark, a back arrow once there is a screen
/// to go back to, and a single continuous line that fills as the learner moves
/// through onboarding.
class _OnboardingChrome extends StatelessWidget {
  const _OnboardingChrome({
    required this.progress,
    required this.color,
    required this.onBack,
    required this.onSkip,
    required this.skipKey,
    required this.showMark,
  });

  final double progress;
  final Color color;
  final VoidCallback? onBack;
  final VoidCallback? onSkip;
  final Key? skipKey;
  final bool showMark;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.of(context).disableAnimations;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (onBack != null)
                V3Pressable(
                  key: const ValueKey('onboarding.back'),
                  label: 'Back',
                  onTap: onBack,
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: Icon(
                      CupertinoIcons.chevron_left,
                      size: 22,
                      color: color,
                    ),
                  ),
                )
              else
                const SizedBox(width: 12),
              if (showMark) ...[
                Container(
                  width: 26,
                  height: 26,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: color.withValues(alpha: 0.12)),
                  ),
                  child: Image.asset(
                    'assets/images/parlesprint_app_icon.png',
                    fit: BoxFit.contain,
                    excludeFromSemantics: true,
                  ),
                ),
                const SizedBox(width: 9),
                Text('ParleSprint', style: V3Type.strong(15, color)),
              ],
              if (onSkip != null) ...[
                const Spacer(),
                V3Pressable(
                  key: skipKey,
                  label: 'Skip',
                  onTap: onSkip,
                  child: SizedBox(
                    height: 44,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Center(
                        child: Text('Skip', style: V3Type.strong(15, color)),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: SizedBox(
                height: 3,
                width: double.infinity,
                child: Stack(
                  children: [
                    if (progress > 0)
                      Container(color: color.withValues(alpha: 0.18)),
                    TweenAnimationBuilder<double>(
                      tween: Tween<double>(end: progress),
                      duration: reduce
                          ? Duration.zero
                          : const Duration(milliseconds: 520),
                      curve: Curves.easeOutCubic,
                      builder: (context, value, _) => FractionallySizedBox(
                        widthFactor: value.clamp(0.0, 1.0),
                        alignment: Alignment.centerLeft,
                        child: Container(color: color),
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

class _OnboardingCTA extends StatelessWidget {
  const _OnboardingCTA({
    super.key,
    required this.label,
    required this.onTap,
    required this.background,
    required this.foreground,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onTap;
  final Color background;
  final Color foreground;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null && !loading;
    final contentColor = enabled
        ? foreground
        : foreground.withValues(alpha: 0.72);
    return V3Pressable(
      label: label,
      onTap: enabled ? onTap : null,
      child: Container(
        constraints: const BoxConstraints(minHeight: 62),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(DesignTokens.radiusLarge),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                loading ? 'One moment' : label,
                style: V3Type.strong(16, contentColor),
              ),
            ),
            if (loading)
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: contentColor,
                ),
              )
            else
              Icon(Icons.arrow_forward_rounded, size: 22, color: contentColor),
          ],
        ),
      ),
    );
  }
}

class _OnboardingChoice extends StatelessWidget {
  const _OnboardingChoice({
    super.key,
    required this.title,
    required this.selected,
    required this.onTap,
    this.trailingIcon,
  });

  final String title;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? trailingIcon;

  @override
  Widget build(BuildContext context) {
    return V3Pressable(
      label: title,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        constraints: const BoxConstraints(minHeight: 60),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected
                ? AppearanceColors.blueLight
                : AppearanceColors.lightHairline,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: V3Type.strong(17, AppearanceColors.lightText),
              ),
            ),
            if (trailingIcon != null)
              Icon(
                trailingIcon,
                size: 21,
                color: selected
                    ? AppearanceColors.blueDeep
                    : AppearanceColors.blueLight,
              )
            else
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: selected ? AppearanceColors.blueLight : Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected
                        ? AppearanceColors.blueLight
                        : AppearanceColors.lightHairline,
                    width: 1.5,
                  ),
                ),
                child: selected
                    ? const Icon(
                        Icons.check_rounded,
                        size: 15,
                        color: Colors.white,
                      )
                    : null,
              ),
          ],
        ),
      ),
    );
  }
}

class _VoiceWave extends StatelessWidget {
  const _VoiceWave({required this.color, required this.phase});

  final Color color;
  final double phase;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox(
        width: math.min(MediaQuery.sizeOf(context).width - 88, 390).toDouble(),
        height: 132,
        child: CustomPaint(
          painter: _VoiceWavePainter(color: color, phase: phase),
        ),
      ),
    );
  }
}

class _VoiceWavePainter extends CustomPainter {
  const _VoiceWavePainter({required this.color, required this.phase});

  final Color color;
  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    const barCount = 27;
    final step = size.width / barCount;
    final barWidth = math.min(5.0, step * 0.34).toDouble();
    final centerY = size.height / 2;
    final peaks = [
      (0.12, 0.42),
      (0.29, 0.78),
      (0.47, 0.57),
      (0.67, 1.0),
      (0.86, 0.48),
    ];

    for (var i = 0; i < barCount; i++) {
      final x = (i + 0.5) / barCount;
      var envelope = 0.0;
      for (final peak in peaks) {
        final width = peak.$1 == 0.67 ? 0.095 : 0.085;
        final distance = (x - peak.$1) / width;
        final shape = peak.$2 * math.exp(-distance * distance * 0.5);
        envelope = math.max(envelope, shape).toDouble();
      }
      final syllable =
          0.56 +
          0.44 *
              (0.5 +
                  0.5 *
                      math.sin((phase * math.pi * 2.6) - (x * math.pi * 2.2)));
      final height = 5 + 78 * envelope * syllable;
      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(step * (i + 0.5), centerY),
          width: barWidth,
          height: height,
        ),
        Radius.circular(barWidth / 2),
      );
      canvas.drawRRect(rect, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant _VoiceWavePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.phase != phase;
}

/// Screen: onboarding tutor practice. Key prefix: onboarding.trial.
/// User arrived to: finish onboarding after choosing a tutor and accepting
/// the AI audio consent.
/// They must understand: the optional voice practice lasts three minutes and
/// sends audio to Google.
/// Primary action: start the three-minute practice with the chosen tutor.
/// Secondary action: skip practice and continue to save progress with an
/// account.
/// Success state: practice ends and an unsigned learner is asked to create an
/// account before entering the course.
/// Must not contain: score promises, pressure, or hidden audio use.
/// States: default, connecting, interrupted, completed.
class V3OnboardingTrialOffer extends ConsumerStatefulWidget {
  const V3OnboardingTrialOffer({super.key, required this.onComplete});

  final VoidCallback onComplete;

  @override
  ConsumerState<V3OnboardingTrialOffer> createState() =>
      _V3OnboardingTrialOfferState();
}

class _V3OnboardingTrialOfferState extends ConsumerState<V3OnboardingTrialOffer>
    with SingleTickerProviderStateMixin {
  late final TutorPersona _tutor;
  late final AnimationController _waveMotion;
  var _starting = false;

  @override
  void initState() {
    super.initState();
    _tutor = ActiveTutor.current;
    _waveMotion = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncWaveMotion();
  }

  void _syncWaveMotion() {
    if (_starting || MediaQuery.of(context).disableAnimations) {
      _waveMotion.stop();
      _waveMotion.value = 0;
    } else if (!_waveMotion.isAnimating) {
      _waveMotion.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _waveMotion.dispose();
    super.dispose();
  }

  void _skipPractice() {
    if (_starting) return;
    _waveMotion.stop();
    widget.onComplete();
  }

  Future<void> _startPractice() async {
    if (_starting) return;
    setState(() => _starting = true);
    _syncWaveMotion();
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
      final store = ref.read(learningStoreProvider);
      final trialContext = LivePrompts.trialLessonContextFor(
        goal: goal,
        level: level,
        focus: const ['Speaking', 'Listening'],
        tutorName: _tutor.displayName,
      );
      result = await AppRouter.push<SpeakingResult>(
        context,
        (_) => V3CallScreen(
          keyPrefix: 'onboarding.trial',
          title: 'Practice with ${_tutor.displayName}',
          subtitle: 'A three-minute check of where you are',
          stage: 'trial',
          topic: 'Onboarding calibration · $goal',
          limitSeconds: TrialCallGate.maxSeconds,
          wrapUpNote: LivePrompts.trialWrapUpNote,
          wrapUpLeadSeconds: TrialCallGate.wrapUpLeadSeconds,
          createSession: () => V3MarieSession.createCall(
            store: () => store,
            context: () => trialContext,
            opening: LivePrompts.trialKickoffFor(goal: goal, level: level),
            isTrial: true,
            idleLimit: const Duration(seconds: 60),
          ),
        ),
        fullscreenDialog: true,
      );
    } catch (_) {
      await TrialCallGate.releaseIfNeverConnected(connected: false);
      if (mounted) {
        setState(() => _starting = false);
        _syncWaveMotion();
      }
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
    if (mounted) {
      _waveMotion.stop();
      widget.onComplete();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: _onboardingPalette(Theme.of(context)),
      child: V3Width(
        child: V3Screen(
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
                  const Spacer(),
                  V3Pressable(
                    key: const ValueKey('onboarding.trial.skip'),
                    label: 'Skip practice',
                    onTap: _starting ? null : _skipPractice,
                    child: SizedBox(
                      height: 48,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Center(
                          child: Text(
                            'Skip practice',
                            style: V3Type.strong(14, AppearanceColors.blueDeep),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              AnimatedBuilder(
                animation: _waveMotion,
                builder: (context, _) => Center(
                  child: _VoiceWave(
                    color: AppearanceColors.blueLight,
                    phase: Curves.easeInOutSine.transform(_waveMotion.value),
                  ),
                ),
              ),
              const SizedBox(height: 36),
              Text(
                'Try ${_tutor.displayName} for 3 minutes.',
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
              _OnboardingCTA(
                key: const ValueKey('onboarding.trial.start'),
                label: 'Start 3-minute practice',
                loading: _starting,
                onTap: _starting ? null : _startPractice,
                background: AppearanceColors.blueLight,
                foreground: Colors.white,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
