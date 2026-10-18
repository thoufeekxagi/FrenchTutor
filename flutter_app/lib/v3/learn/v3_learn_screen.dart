import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../design/app_router.dart';
import '../../design/tokens.dart';
import '../../models/content_models.dart';
import '../../models/profile.dart';
import '../../providers/database_provider.dart';
import '../../screens/labs/labs_screen.dart';
import '../../screens/speak/live_tutor_setup_screen.dart';
import '../../screens/labs/vocabulary_flashcards_screen.dart';
import '../../services/learning_streak_service.dart';
import '../../services/srs_service.dart';
import '../daily_challenge/v3_daily_challenge.dart';
import '../daily_challenge/v3_daily_challenge_repository.dart';
import '../lesson/v3_course.dart';
import '../lesson/v3_lesson.dart';
import '../lesson/v3_lesson_player.dart';
import '../progress/v3_streak_calendar_screen.dart';
import '../review/v3_review_queue.dart';
import '../story/v3_stories_panel.dart';
import '../ui/v3_ui.dart';

/// Learn tab. Screen contract:
///
/// User arrived to: open the app to study.
/// They must understand: the next authored lesson, today's challenge, and the
/// four short ways to practise. Full pathway progress lives in the course
/// path.
/// Primary action: Continue the next course lesson. Exactly one.
/// Secondary: Daily challenge, Marie, review, Stories, and the course path.
/// Success state: the lesson opens at the saved step and moves the pathway on
/// when complete.
/// Must not contain: AI-generated lessons, fake progress, photos, or subtitles.
///
/// Everything comes from the bundled authored course. Progress is local.
class V3LearnScreen extends ConsumerStatefulWidget {
  const V3LearnScreen({super.key});

  @override
  ConsumerState<V3LearnScreen> createState() => _V3LearnScreenState();
}

class _V3LearnScreenState extends ConsumerState<V3LearnScreen> {
  var _tab = 0;
  int? _reviewCount;
  var _loaded = false;
  List<V3Lesson> _course = const [];
  Set<String> _done = const {};
  Map<String, int> _pos = const {};
  String? _active;
  String? _lastDone;
  String? _openUnit;
  DateTime? _examDate;
  String? _selectedLevel;
  V3DailyChallenge? _dailyChallenge;
  int _streakDays = 0;
  int _activeWeekDays = 0;
  List<bool> _weekActivity = const [
    false,
    false,
    false,
    false,
    false,
    false,
    false,
  ];
  bool _showPath = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    const e2eShell = bool.fromEnvironment('E2E_SHELL');
    const e2eOnly = String.fromEnvironment('E2E_ONLY');
    final profile = ref.read(learningStoreProvider).profile();
    final level = LearnerLevel.cefrValues.contains(profile.level)
        ? profile.level
        : 'a1';
    final lessonPrefixes = kDebugMode && e2eShell && e2eOnly.isNotEmpty
        ? e2eOnly.split(',').map((prefix) => prefix.trim()).toList()
        : <String>['s0', level];
    final course = await V3Course.load(idPrefixes: lessonPrefixes);
    final challenge = await V3DailyChallengeRepository.load(level);
    final done = await V3Progress.completed();
    final pos = await V3Progress.positions();
    final active = await V3Progress.lastActive();
    final lastDone = await V3Progress.lastCompleted();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('tcf_exam_date');
    final sessions = ref.read(storageServiceProvider).getAllSessions();
    final streak = LearningStreakService.summarize(sessions);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final monday = today.subtract(Duration(days: today.weekday - 1));
    final weekActivity = List<bool>.generate(7, (i) {
      final day = monday.add(Duration(days: i));
      return !day.isAfter(today) && streak.isActiveOn(day);
    });
    final activeWeekDays = weekActivity.where((active) => active).length;
    if (!mounted) return;
    setState(() {
      _course = course;
      _done = done;
      _pos = pos;
      _active = active;
      _lastDone = lastDone;
      _examDate = raw == null ? null : DateTime.tryParse(raw);
      _selectedLevel = level;
      _dailyChallenge = challenge;
      _streakDays = streak.currentDays;
      _activeWeekDays = activeWeekDays;
      _weekActivity = weekActivity;
      _loaded = true;
    });
    unawaited(_refreshReviewCount());
  }

  /// Where Resume goes. One rule, kept in [V3Progress.pickNext].
  V3Lesson? get _next => V3Progress.pickNext(
    _course,
    _done,
    _pos,
    active: _active,
    lastCompleted: _lastDone,
  );

  /// [review] opens from the first step to look again. It never lowers real
  /// progress: the furthest step reached is kept and Resume still returns to it.
  Future<void> _openLesson(V3Lesson lesson, {bool review = false}) async {
    final reached = _pos[lesson.id] ?? 0;
    final finished = _done.contains(lesson.id);
    await AppRouter.push<bool>(
      context,
      (_) => V3LessonPlayer(
        lesson: lesson,
        startAt: review || finished ? 0 : reached,
        frontier: reached,
        reviewAll: finished,
      ),
      fullscreenDialog: true,
    );
    if (mounted) unawaited(_load());
  }

  /// A lesson row. Unfinished with progress: resume or look again. Finished:
  /// replay. Not started: start.
  Future<void> _tapLesson(V3Lesson lesson) async {
    final reached = _pos[lesson.id] ?? 0;
    if (_done.contains(lesson.id) || reached == 0) {
      return _openLesson(lesson);
    }
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => V3Width(
        child: Container(
          key: const ValueKey('learn.sheet'),
          padding: EdgeInsets.fromLTRB(
            24,
            12,
            24,
            20 + MediaQuery.paddingOf(context).bottom,
          ),
          decoration: BoxDecoration(
            color: DesignTokens.canvas,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 5,
                  decoration: BoxDecoration(
                    color: DesignTokens.hairline,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(lesson.title, style: V3Type.title(24)),
              const SizedBox(height: 4),
              Text(
                'You reached step ${reached + 1} of ${lesson.steps.length}.',
                style: V3Type.body(15),
              ),
              const SizedBox(height: 18),
              V3Button(
                key: const ValueKey('learn.sheet.resume'),
                label: 'Resume at step ${reached + 1}',
                onTap: () => Navigator.of(context).pop('resume'),
              ),
              const SizedBox(height: 10),
              V3Button(
                key: const ValueKey('learn.sheet.review'),
                label: 'Review from the start',
                kind: V3ButtonKind.ghost,
                trailingArrow: false,
                onTap: () => Navigator.of(context).pop('review'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || choice == null) return;
    await _openLesson(lesson, review: choice == 'review');
  }

  void _say(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// What daily review would show now: only words this learner has met in their
  /// own lessons. Null means they have not met any yet.
  Future<List<VocabEntry>?> _reviewEntries() async {
    final learned = V3ReviewQueue.learnedWords(_course, _done, _pos);
    if (learned.isEmpty) return null;
    final store = ref.read(learningStoreProvider);
    final target = await SRSService.autoQueueSize;
    final cap = await SRSService.newCardsPerDay;
    final budget = (cap - store.newEntriesIntroducedToday())
        .clamp(0, cap)
        .toInt();
    return V3ReviewQueue.build(
      learned: learned,
      states: store.allSRSStates(),
      now: DateTime.now(),
      targetSize: target,
      newBudget: budget,
    );
  }

  Future<void> _refreshReviewCount() async {
    try {
      final entries = await _reviewEntries();
      if (mounted) setState(() => _reviewCount = entries?.length ?? 0);
    } catch (_) {
      if (mounted) setState(() => _reviewCount = null);
    }
  }

  /// Daily review of the words this learner has met in their own lessons. It
  /// grows as they finish lessons, and shows nothing they have not learned.
  Future<void> _openReview() async {
    try {
      final entries = await _reviewEntries();
      if (!mounted) return;
      if (entries == null) {
        _say('Review opens after your first word lesson.');
        return;
      }
      if (entries.isEmpty) {
        _say('Nothing to review right now. Your next words are due later.');
        return;
      }
      final profile = ref.read(learningStoreProvider).profile();
      await AppRouter.push<bool>(
        context,
        (_) => VocabularyFlashcardsScreen(
          title: 'Daily review',
          entries: entries,
          source: 'v3_daily_review',
          topic: 'Daily review',
          levelBand: profile.level.toUpperCase(),
          studyDepth: VocabularyStudyDepth.wordsOnly,
          dailyReviewMode: true,
        ),
        fullscreenDialog: true,
      );
      if (mounted) unawaited(_load());
    } catch (_) {
      if (mounted) _say('Review is unavailable right now.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileLevel = ref.watch(learningStoreProvider).profile().level;
    final level =
        _selectedLevel ??
        (LearnerLevel.cefrValues.contains(profileLevel) ? profileLevel : 'a1');
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final exam = _examDate == null
        ? null
        : DateTime(_examDate!.year, _examDate!.month, _examDate!.day);
    final days = exam?.difference(today).inDays;
    return SafeArea(
      bottom: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: constraints.maxWidth >= 840
                    ? 760
                    : constraints.maxWidth.clamp(0, 680).toDouble(),
              ),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                children: [
                  Text('Bonjour!', style: V3Type.title(31)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _levelSelector(level),
                      const Spacer(),
                      _examCountdown(days),
                    ],
                  ),
                  const SizedBox(height: 18),
                  if (!_loaded)
                    const SizedBox(height: 240)
                  else if (_tab == 0)
                    ...(_showPath ? _pathPage() : _courseHome())
                  else
                    ..._practiceHome(),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _levelSelector(String level) => V3Pressable(
    key: const ValueKey('learn.level'),
    label: 'Change level, ${level.toUpperCase()}',
    onTap: () => unawaited(_pickLevel()),
    child: Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: DesignTokens.primarySoft,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            level.toUpperCase(),
            style: V3Type.strong(15, DesignTokens.primary),
          ),
          const SizedBox(width: 6),
          Icon(
            CupertinoIcons.chevron_down,
            size: 15,
            color: DesignTokens.inkSoft,
          ),
        ],
      ),
    ),
  );

  Widget _examCountdown(int? days) {
    final label = days == null
        ? 'Set exam date'
        : days < 0
        ? 'Exam date passed'
        : days == 0
        ? 'Exam today'
        : days == 1
        ? 'Exam tomorrow'
        : 'Exam in $days days';
    return V3Pressable(
      key: const ValueKey('learn.examDate'),
      label: label,
      onTap: () => unawaited(_pickExamDate()),
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: DesignTokens.primarySoft,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              CupertinoIcons.calendar,
              size: 18,
              color: DesignTokens.primary,
            ),
            const SizedBox(width: 8),
            Text(label, style: V3Type.strong(13, DesignTokens.primary)),
          ],
        ),
      ),
    );
  }

  Future<void> _pickLevel() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => V3Width(
        child: Container(
          padding: EdgeInsets.fromLTRB(
            20,
            18,
            20,
            20 + MediaQuery.paddingOf(context).bottom,
          ),
          decoration: BoxDecoration(
            color: DesignTokens.canvas,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Choose your level', style: V3Type.title(24)),
              const SizedBox(height: 10),
              for (final level in LearnerLevel.cefrValues)
                V3Pressable(
                  key: ValueKey('learn.level.${level.toUpperCase()}'),
                  label: '${level.toUpperCase()} level',
                  selected: level == _selectedLevel,
                  onTap: () => Navigator.of(context).pop(level),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 52),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: DesignTokens.hairline),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            level.toUpperCase(),
                            style: V3Type.strong(16),
                          ),
                        ),
                        if (level == _selectedLevel)
                          Icon(
                            CupertinoIcons.checkmark,
                            color: DesignTokens.primary,
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || selected == null || selected == _selectedLevel) return;
    final profile = ref.read(learningStoreProvider).profile()..level = selected;
    ref.read(learningStoreProvider).saveProfile(profile);
    setState(() {
      _selectedLevel = selected;
      _showPath = false;
      _loaded = false;
    });
    await _load();
  }

  Future<void> _pickExamDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _examDate != null && !_examDate!.isBefore(today)
          ? _examDate!
          : today,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365 * 3)),
    );
    if (picked == null || !mounted) return;
    final value = DateTime(picked.year, picked.month, picked.day);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('tcf_exam_date', value.toIso8601String());
    if (mounted) setState(() => _examDate = value);
  }

  Future<void> _openStreakCalendar() async {
    await AppRouter.push<void>(context, (_) => const V3StreakCalendarScreen());
    if (mounted) unawaited(_load());
  }

  // ---- Course and practice ----------------------------------------------

  /// "A2" from a2-u03-words-1, "Stage 0" from s0-01.
  String _levelOf(V3Lesson l) {
    final head = l.id.split('-').first;
    if (head == 's0') return 'Stage 0';
    return const {'a1', 'a2', 'b1', 'b2'}.contains(head)
        ? head.toUpperCase()
        : '';
  }

  List<Widget> _courseHome() => [
    _streakStrip(),
    const SizedBox(height: 14),
    _continuePathCard(),
    const SizedBox(height: 19),
    _quickPracticeGrid(),
    const SizedBox(height: 13),
    _coursePathCard(),
  ];

  List<Widget> _pathPage() => [
    V3Pressable(
      key: const ValueKey('learn.backToCourse'),
      label: 'Back home',
      onTap: () => setState(() => _showPath = false),
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            Icon(
              CupertinoIcons.chevron_left,
              color: DesignTokens.primary,
              size: 17,
            ),
            const SizedBox(width: 5),
            Text('Home', style: V3Type.strong(14, DesignTokens.primary)),
          ],
        ),
      ),
    ),
    const SizedBox(height: 4),
    Text('Your course path', style: V3Type.title(28)),
    const SizedBox(height: 14),
    ..._path(),
  ];

  List<Widget> _practiceHome() => [
    V3Pressable(
      key: const ValueKey('learn.practiceBack'),
      label: 'Back home',
      onTap: () => setState(() => _tab = 0),
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            Icon(
              CupertinoIcons.chevron_left,
              color: DesignTokens.primary,
              size: 17,
            ),
            const SizedBox(width: 5),
            Text('Home', style: V3Type.strong(14, DesignTokens.primary)),
          ],
        ),
      ),
    ),
    const SizedBox(height: 4),
    Text('Your practice', style: V3Type.title(28)),
    const SizedBox(height: 14),
    Row(
      children: [
        Expanded(
          child: _practiceAction(
            key: const ValueKey('learn.review'),
            icon: CupertinoIcons.arrow_2_circlepath,
            title: _reviewCount == null || _reviewCount == 0
                ? 'Review words'
                : 'Review · $_reviewCount',
            label: 'Review flashcards',
            onTap: _openReview,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _practiceAction(
            key: const ValueKey('learn.practiceLibrary'),
            icon: CupertinoIcons.slider_horizontal_3,
            title: 'Practice library',
            label: 'Explore practice library',
            onTap: () => unawaited(_openPracticeLibrary()),
          ),
        ),
      ],
    ),
    const SizedBox(height: 14),
    V3StoriesPanel(key: const ValueKey('learn.stories')),
  ];

  Widget _practiceAction({
    required Key key,
    required IconData icon,
    required String title,
    required String label,
    required VoidCallback onTap,
  }) => V3Pressable(
    key: key,
    label: label,
    onTap: onTap,
    child: Container(
      constraints: const BoxConstraints(minHeight: 82),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: DesignTokens.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: DesignTokens.hairline),
      ),
      child: Row(
        children: [
          Icon(icon, size: 23, color: DesignTokens.primary),
          const SizedBox(width: 10),
          Expanded(child: Text(title, style: V3Type.strong(14))),
          Icon(
            CupertinoIcons.chevron_right,
            size: 15,
            color: DesignTokens.inkSoft,
          ),
        ],
      ),
    ),
  );

  Widget _quickPracticeGrid() {
    final challenge = _dailyChallenge;
    final challengeSubtitle = challenge == null
        ? 'Being prepared for ${_selectedLevel?.toUpperCase() ?? 'A1'}'
        : challenge.completed
        ? 'Completed today'
        : challenge.title;
    final reviewStatus = _reviewCount == null
        ? 'Checking your words'
        : _reviewCount == 0
        ? 'None due'
        : '$_reviewCount due';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Your practice', style: V3Type.title(22)),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _quickPracticeCard(
                key: const ValueKey('learn.quick.marie'),
                icon: CupertinoIcons.chat_bubble_2,
                title: 'Talk with Marie',
                subtitle: null,
                label: 'Talk with Marie. Conversation practice.',
                onTap: _openMarie,
                accent: DesignTokens.primary,
                tint: DesignTokens.primarySoft,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _quickPracticeCard(
                key: const ValueKey('learn.quick.challenge'),
                icon: CupertinoIcons.sparkles,
                title: 'Daily challenge',
                subtitle: challengeSubtitle,
                label: challenge == null
                    ? 'Daily challenge. $challengeSubtitle.'
                    : challenge.completed
                    ? 'Daily challenge completed today.'
                    : '${challenge.currentStep > 0 ? 'Resume' : 'Start'} challenge. ${challenge.title}.',
                onTap: () => unawaited(_tapDailyChallenge(challenge)),
                accent: DesignTokens.homeChallenge,
                tint: DesignTokens.homeChallengeSoft,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _quickPracticeCard(
                key: const ValueKey('learn.quick.review'),
                icon: CupertinoIcons.arrow_2_circlepath,
                title: 'Review words',
                subtitle: reviewStatus,
                label: 'Review flashcards. $reviewStatus.',
                onTap: _openReview,
                accent: DesignTokens.homeReview,
                tint: DesignTokens.homeReviewSoft,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _quickPracticeCard(
                key: const ValueKey('learn.quick.stories'),
                icon: CupertinoIcons.book,
                title: 'Stories',
                subtitle: 'Read or listen',
                label: 'Open Stories. Read or listen.',
                onTap: () => setState(() {
                  _tab = 1;
                  _showPath = false;
                }),
                accent: DesignTokens.homeStories,
                tint: DesignTokens.homeStoriesSoft,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _quickPracticeCard({
    required Key key,
    required IconData icon,
    required String title,
    String? subtitle,
    required String label,
    required VoidCallback onTap,
    required Color accent,
    required Color tint,
  }) => V3Pressable(
    key: key,
    label: label,
    onTap: onTap,
    child: Container(
      constraints: const BoxConstraints(minHeight: 92),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
      decoration: BoxDecoration(
        color: DesignTokens.surface,
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: DesignTokens.hairline),
        boxShadow: DesignTokens.surfaceShadow,
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tint,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, size: 24, color: accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: V3Type.strong(13.5),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: V3Type.body(11.5),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 3),
          Icon(
            CupertinoIcons.chevron_right,
            size: 15,
            color: DesignTokens.inkSoft,
          ),
        ],
      ),
    ),
  );

  Future<void> _openMarie() async {
    await AppRouter.push<void>(
      context,
      (_) => const LiveTutorSetupScreen(),
      fullscreenDialog: true,
    );
  }

  Widget _streakStrip() => V3Pressable(
    key: const ValueKey('learn.streak'),
    label:
        'Open streak calendar, $_streakDays day streak, $_activeWeekDays days this week',
    onTap: _openStreakCalendar,
    child: Container(
      constraints: const BoxConstraints(minHeight: 62),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: DesignTokens.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: DesignTokens.hairline),
        boxShadow: DesignTokens.surfaceShadow,
      ),
      child: Row(
        children: [
          Icon(
            CupertinoIcons.flame_fill,
            size: 24,
            color: DesignTokens.homeFlame,
          ),
          const SizedBox(width: 9),
          Text('$_streakDays day streak', style: V3Type.strong(14.5)),
          const SizedBox(width: 12),
          Expanded(
            child: Row(
              children: [
                for (var day = 0; day < 7; day++)
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: _weekActivity[day]
                                ? DesignTokens.primary
                                : DesignTokens.canvasDim,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _weekActivity[day]
                                  ? DesignTokens.primary
                                  : DesignTokens.hairline,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          const [
                            'Mon',
                            'Tue',
                            'Wed',
                            'Thu',
                            'Fri',
                            'Sat',
                            'Sun',
                          ][day],
                          maxLines: 1,
                          style: V3Type.body(8.5, DesignTokens.inkSoft),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Future<void> _tapDailyChallenge(V3DailyChallenge? challenge) async {
    if (challenge == null) {
      _say(
        'Today’s challenge is being prepared for '
        '${_selectedLevel?.toUpperCase() ?? 'A1'}.',
      );
      return;
    }
    if (challenge.completed) {
      _say('You completed today’s challenge. Come back tomorrow.');
      return;
    }
    try {
      await _openChallenge(challenge);
    } catch (_) {
      if (mounted) _say('The daily challenge could not open. Try again.');
    }
  }

  Future<void> _openChallenge(V3DailyChallenge source) async {
    final challenge = await V3DailyChallengeRepository.start(source);
    if (!mounted) return;
    await AppRouter.push<bool>(
      context,
      (_) => V3LessonPlayer(
        lesson: challenge.lesson,
        startAt: challenge.currentStep,
        frontier: challenge.currentStep,
        savePathProgress: false,
        completionEyebrow: 'DAILY CHALLENGE COMPLETE',
        completionTitle: 'Challenge complete',
        answerChecker: challenge.remote
            ? (stepId, selectedIndex) async {
                final feedback = await V3DailyChallengeRepository.checkAnswer(
                  challenge,
                  stepId,
                  selectedIndex,
                );
                if (feedback == null) {
                  throw StateError('Remote challenge answer was not checked.');
                }
                return feedback;
              }
            : null,
        onStepChanged: (step) =>
            V3DailyChallengeRepository.saveStep(challenge, step),
        onCompleted: (_) async {
          await V3DailyChallengeRepository.complete(challenge);
        },
      ),
      fullscreenDialog: true,
    );
    if (mounted) await _load();
  }

  Widget _continuePathCard() {
    final next = _next;
    return V3Pressable(
      key: const ValueKey('learn.continuePath'),
      label: next == null
          ? 'Open course path'
          : 'Continue lesson, ${next.title}',
      onTap: next == null
          ? () => setState(() => _showPath = true)
          : () => _openLesson(next),
      child: Container(
        constraints: const BoxConstraints(minHeight: 210),
        decoration: BoxDecoration(
          gradient: DesignTokens.homeHeroGradient,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: DesignTokens.hairline),
          boxShadow: DesignTokens.surfaceShadow,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(25),
          child: Stack(
            children: [
              Positioned(
                right: -20,
                bottom: -25,
                child: Image.asset(
                  'assets/images/learn_home_hero.png',
                  width: 270,
                  height: 170,
                  fit: BoxFit.contain,
                  alignment: Alignment.bottomRight,
                  excludeFromSemantics: true,
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'CONTINUE YOUR COURSE',
                      style: V3Type.eyebrow(DesignTokens.primary),
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.only(right: 70),
                      child: Text(
                        next?.title ??
                            (_course.isEmpty
                                ? 'No lessons found'
                                : 'Path complete'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: V3Type.title(25),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Padding(
                      padding: const EdgeInsets.only(right: 70),
                      child: Text(
                        next == null
                            ? 'Explore your course path'
                            : '${_levelOf(next)} · ${next.minutes} min',
                        style: V3Type.body(14),
                      ),
                    ),
                    const SizedBox(height: 17),
                    Container(
                      constraints: const BoxConstraints(minHeight: 50),
                      padding: const EdgeInsets.symmetric(horizontal: 17),
                      decoration: BoxDecoration(
                        color: DesignTokens.primary,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            next == null
                                ? 'View course path'
                                : 'Continue lesson',
                            style: V3Type.strong(15, DesignTokens.onPrimary),
                          ),
                          const SizedBox(width: 10),
                          Icon(
                            CupertinoIcons.arrow_right,
                            color: DesignTokens.onPrimary,
                            size: 19,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _coursePathCard() => V3Pressable(
    key: const ValueKey('learn.viewPath'),
    label: 'View course path',
    onTap: () => setState(() {
      _tab = 0;
      _showPath = true;
    }),
    child: Container(
      constraints: const BoxConstraints(minHeight: 86),
      decoration: BoxDecoration(
        color: DesignTokens.homePathCanvas,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: DesignTokens.hairline),
        boxShadow: DesignTokens.surfaceShadow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(21),
        child: Stack(
          children: [
            Positioned(
              right: -6,
              bottom: -25,
              child: Image.asset(
                'assets/images/learn_home_path.png',
                width: 205,
                height: 126,
                fit: BoxFit.contain,
                alignment: Alignment.bottomRight,
                excludeFromSemantics: true,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
              child: Row(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: DesignTokens.primarySoft,
                      borderRadius: BorderRadius.circular(17),
                    ),
                    child: Icon(
                      CupertinoIcons.map_fill,
                      size: 28,
                      color: DesignTokens.primary,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text('Your TCF path', style: V3Type.strong(17)),
                  ),
                  Icon(
                    CupertinoIcons.chevron_right,
                    size: 19,
                    color: DesignTokens.inkSoft,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Future<void> _openPracticeLibrary() async {
    await AppRouter.push<void>(context, (_) => const LabsScreen());
    if (mounted) unawaited(_load());
  }

  // ---- Path --------------------------------------------------------------

  List<Widget> _path() {
    final groups = <String, List<V3Lesson>>{};
    for (final l in _course) {
      groups.putIfAbsent(l.unit, () => []).add(l);
    }
    final nextUnit = _next?.unit;
    return [
      for (final entry in groups.entries) ...[
        _unitCard(entry.key, entry.value, entry.key == (_openUnit ?? nextUnit)),
        const SizedBox(height: 10),
      ],
    ];
  }

  Widget _unitCard(String unit, List<V3Lesson> lessons, bool open) {
    final first = lessons.first;
    final done = lessons.where((l) => _done.contains(l.id)).length;
    final finished = done == lessons.length;
    final current = _next?.unit == unit;
    final stateColor = finished
        ? DesignTokens.success
        : current
        ? DesignTokens.primary
        : DesignTokens.hairline;
    final label = unit.isEmpty ? 'Dev' : first.unitLabel;
    final title = unit.isEmpty ? 'Test lessons' : first.unitTitle;
    return Container(
      decoration: BoxDecoration(
        color: DesignTokens.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: DesignTokens.hairline),
        boxShadow: DesignTokens.surfaceShadow,
      ),
      child: Column(
        children: [
          V3Pressable(
            key: ValueKey('learn.unit.$unit'),
            label: '$label, $title',
            onTap: () => setState(() => _openUnit = open ? '' : unit),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Container(
                    width: 6,
                    height: 44,
                    decoration: BoxDecoration(
                      color: stateColor,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label.toUpperCase(),
                          style: V3Type.eyebrow(DesignTokens.inkSoft),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: V3Type.strong(17),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '$done of ${lessons.length} lessons',
                          style: V3Type.body(13),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    open
                        ? CupertinoIcons.chevron_up
                        : CupertinoIcons.chevron_down,
                    size: 18,
                    color: DesignTokens.inkSoft,
                  ),
                ],
              ),
            ),
          ),
          if (open) ...[for (final l in lessons) _lessonRow(l)],
        ],
      ),
    );
  }

  Widget _lessonRow(V3Lesson l) {
    final done = _done.contains(l.id);
    final at = _pos[l.id] ?? 0;
    return V3Pressable(
      key: ValueKey('learn.lesson.${l.id}'),
      label: 'Lesson, ${l.title}',
      onTap: () => _tapLesson(l),
      child: Container(
        padding: const EdgeInsets.fromLTRB(38, 12, 18, 12),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: DesignTokens.hairline)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.title, style: V3Type.strong(15)),
                  const SizedBox(height: 2),
                  Text(
                    done
                        ? '${l.minutes} min  ·  tap to replay'
                        : at > 0
                        ? '${l.minutes} min  ·  in progress, step ${at + 1}'
                        : '${l.minutes} min',
                    style: V3Type.body(12.5),
                  ),
                ],
              ),
            ),
            Icon(
              done
                  ? CupertinoIcons.checkmark_circle_fill
                  : at > 0
                  ? CupertinoIcons.play_circle_fill
                  : CupertinoIcons.play_circle,
              color: done ? DesignTokens.success : DesignTokens.inkSoft,
              size: 24,
            ),
          ],
        ),
      ),
    );
  }
}
