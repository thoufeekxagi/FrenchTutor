import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../config/api_keys.dart';
import '../../config/theme.dart';
import '../../design/app_router.dart';
import '../../models/session.dart';
import '../../orchestration/models/competency.dart';
import '../../providers/database_provider.dart';
import '../../services/ai_session_gate.dart';
import '../../services/app_tour.dart';
import '../../services/daily_goal_service.dart';
import '../../services/daily_summary_service.dart';
import '../../services/lesson_speech_service.dart';
import '../../widgets/adaptive/adaptive.dart';
import '../../widgets/passeport_card.dart';
import '../../widgets/session_row.dart';
import '../../widgets/web/web_layout.dart';
import '../../widgets/web/web_practice_grid.dart';
import '../history/all_history_screen.dart';
import '../history/history_screen.dart';
import '../labs/grammar_lab_screen.dart';
import '../labs/liaison_lab_screen.dart';
import '../labs/listening_lab_screen.dart';
import '../labs/roleplay_lab_screen.dart';
import '../labs/writing_lab_screen.dart';
import '../notes/notes_review_screen.dart';
import '../pathway/vocab_picker_screen.dart';
import '../session/session_screen.dart';
import '../settings/settings_screen.dart';
import '../subscription/paywall_screen.dart';
import 'today_mission_widget.dart';
import 'daily_summary_card.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key, this.isActive = true});

  /// True while this is the visible tab. `MainTabScreen` keeps every tab
  /// alive forever inside an `IndexedStack`, so this is the only signal this
  /// screen gets that it's been switched back to — without it, completing a
  /// practice session on another tab and returning here showed stale
  /// "recent practice"/momentum data until the next full app restart.
  final bool isActive;

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  List<Session> _sessions = [];
  DailySummary? _summary;

  @override
  void initState() {
    super.initState();
    _reload();
    // First-open walkthrough — after the first frame so every spotlight
    // target is laid out and measurable.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || await AppTour.hasSeenHome()) return;
      if (mounted) AppTour.playHome(context);
    });
  }

  @override
  void didUpdateWidget(covariant DashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) _reload();
  }

  Future<void> _openSession({String? lessonContext}) async {
    if (!await ensureAiSessionQuota(
          context,
          ref.read(pilotAccessServiceProvider),
        ) ||
        !mounted) {
      return;
    }
    LessonSpeechService.shared.deactivate();
    await AppRouter.push(
      context,
      (_) => SessionScreen(
        apiKey: ApiKeys.geminiKey,
        lessonContext: lessonContext,
      ),
      fullscreenDialog: true,
    );
    _reload();
  }

  void _reload() {
    final storage = ref.read(storageServiceProvider);
    Future(() => storage.getAllSessions()).then((loaded) {
      if (mounted) setState(() => _sessions = loaded);
    });
    // Pure local reads (no LLM, no network) — cheap enough to recompute on
    // every reload so the card is always honestly up to date.
    try {
      final summary = DailySummaryService(
        store: ref.read(learningStoreProvider),
      ).compute();
      if (mounted) setState(() => _summary = summary);
    } catch (_) {
      // A summary must never take the dashboard down.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.sizeOf(context).width >= DesignTokens.breakpointExpanded) {
      return _webDashboard();
    }
    return Scaffold(
      backgroundColor: Passeport.parchment,
      body: SafeArea(
        child: PSContentColumn(
          child: RefreshIndicator(
            color: Passeport.maroon,
            onRefresh: () async => _reload(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
              children: [
                _header(),
                const SizedBox(height: 24),
                KeyedSubtree(
                  key: AppTour.missionKey,
                  child: TodayMissionWidget(
                    isActive: widget.isActive,
                    onProgress: _reload,
                  ),
                ),
                if (_summary?.hasActivity == true) ...[
                  const SizedBox(height: 16),
                  DailySummaryCard(summary: _summary!),
                ],
                const SizedBox(height: 28),
                _sectionTitle('Practice with Marie'),
                const SizedBox(height: 10),
                KeyedSubtree(key: AppTour.marieKey, child: _mariePractice()),
                const SizedBox(height: 28),
                _sectionTitle('Today’s study block'),
                const SizedBox(height: 10),
                KeyedSubtree(
                  key: AppTour.keepPractisingKey,
                  child: _keepPractising(),
                ),
                const SizedBox(height: 28),
                _sectionTitle('This week'),
                const SizedBox(height: 10),
                _momentumCard(),
                if (_sessions.isNotEmpty) ...[
                  const SizedBox(height: 28),
                  Row(
                    children: [
                      _sectionTitle('Recent practice'),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => AppRouter.push(
                          context,
                          (_) => const AllHistoryScreen(),
                        ),
                        child: Text(
                          'View all',
                          style: Passeport.body(
                            13.5,
                            weight: FontWeight.w600,
                          ).copyWith(color: Passeport.sky),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _journalCard(),
                ] else ...[
                  const SizedBox(height: 16),
                  _notesRow(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _webDashboard() {
    final goal = ref.read(learningStoreProvider).profile().goal;
    final goalLabel = switch (goal) {
      'tef_canada' => 'TEF Canada · CLB 7',
      'everyday' => 'Everyday French',
      _ => 'French foundations',
    };
    return Scaffold(
      backgroundColor: DesignTokens.canvas,
      body: SafeArea(
        child: WebPage(
          header: WebPageHeader(
            title: 'Bonjour',
            subtitle:
                '${DateFormat('EEEE, MMMM d').format(DateTime.now())} · $goalLabel',
          ),
          children: [
            const WebSectionHeader(title: 'Your next session'),
            KeyedSubtree(
              key: AppTour.missionKey,
              child: TodayMissionWidget(
                isActive: widget.isActive,
                onProgress: _reload,
              ),
            ),
            if (_summary?.hasActivity == true) ...[
              const SizedBox(height: DesignTokens.space4),
              DailySummaryCard(summary: _summary!),
            ],
            const SizedBox(height: DesignTokens.space6),
            KeyedSubtree(
              key: AppTour.keepPractisingKey,
              child: _keepPractising(),
            ),
            const SizedBox(height: DesignTokens.space6),
            const WebSectionHeader(title: 'Practice with Marie'),
            KeyedSubtree(key: AppTour.marieKey, child: _mariePractice()),
            const SizedBox(height: DesignTokens.space6),
            const WebSectionHeader(title: 'Your momentum'),
            _momentumCard(),
            const SizedBox(height: DesignTokens.space6),
            WebSectionHeader(
              title: _sessions.isEmpty ? 'Your notes' : 'Recent practice',
              actionLabel: _sessions.isEmpty ? null : 'View all',
              onAction: _sessions.isEmpty
                  ? null
                  : () => AppRouter.push(
                      context,
                      (_) => const AllHistoryScreen(),
                    ),
            ),
            _sessions.isEmpty ? _notesRow() : _journalCard(),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    final goal = ref.read(learningStoreProvider).profile().goal;
    final goalLabel = switch (goal) {
      'tef_canada' => 'TEF Canada · CLB 7',
      'everyday' => 'Everyday French',
      _ => 'French foundations',
    };

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'TODAY · ${DateFormat('EEEE, MMMM d').format(DateTime.now())}',
                style: DesignTokens.label(
                  10.5,
                ).copyWith(color: DesignTokens.mutedDim, letterSpacing: 0.8),
              ),
              const SizedBox(height: 6),
              Text('Good morning', style: DesignTokens.display(32)),
              const SizedBox(height: 4),
              Text(
                goalLabel,
                style: Passeport.body(
                  14,
                  weight: FontWeight.w500,
                ).copyWith(color: Passeport.slateDim),
              ),
            ],
          ),
        ),
        Semantics(
          button: true,
          label: 'Open settings',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () async {
              await AppRouter.push(context, (_) => const SettingsScreen());
              // Settings' "Replay the walkthrough" row lands back here.
              if (mounted && AppTour.pendingHomeReplay) {
                AppTour.pendingHomeReplay = false;
                if (context.mounted) AppTour.playHome(context);
              }
            },
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Passeport.card,
                shape: BoxShape.circle,
                boxShadow: DesignTokens.cardShadow,
              ),
              child: const Icon(
                CupertinoIcons.person_fill,
                size: 18,
                color: Passeport.ink,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _sectionTitle(String title) {
    return Text(title, style: Passeport.display(20));
  }

  Widget _mariePractice() {
    final topics =
        ref.read(contentServiceProvider).resources()?.speakingTopics ?? [];
    return Container(
      decoration: BoxDecoration(
        color: DesignTokens.infoSoft,
        borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
        border: Border.all(
          color: DesignTokens.secondary.withValues(alpha: 0.22),
        ),
      ),
      child: Column(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              PSHaptics.light();
              _openSession();
            },
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: const BoxDecoration(
                      color: Passeport.sky,
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: Text(
                        'M',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Talk with Marie',
                          style: Passeport.body(16, weight: FontWeight.w700),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Open conversation · choose any topic',
                          style: Passeport.body(
                            13,
                          ).copyWith(color: Passeport.slateDim),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(
                      color: Passeport.card,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      CupertinoIcons.mic_fill,
                      color: Passeport.maroon,
                      size: 19,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (topics.isNotEmpty) ...[
            Container(height: 1, color: Passeport.sky.withValues(alpha: 0.12)),
            SizedBox(
              height: 54,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 9,
                ),
                itemCount: topics.take(5).length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final topic = topics[index];
                  return GestureDetector(
                    onTap: () {
                      PSHaptics.selection();
                      _openSession(
                        lessonContext: ref
                            .read(contentServiceProvider)
                            .speakingTopicContext(topic),
                      );
                    },
                    child: Container(
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 13),
                      decoration: BoxDecoration(
                        color: Passeport.card,
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: Text(
                        topic.title,
                        style: Passeport.body(12.5, weight: FontWeight.w600),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Keep practising — a permanent, mission-independent set of skill chips.
  /// Every skill is always here, every day, regardless of what today's
  /// mission planner picked and regardless of what's been completed. The
  /// mission card above explains the mission; this section is simply "go
  /// practice anything, as much as you want" — and the results still feed
  /// the learner model, so extra practice still shapes what comes next.
  ///
  /// Each skill owns its OWN auto-vs-manual choice, made inside that skill's
  /// screen (e.g. VocabPickerScreen's Auto/category picker), not a single
  /// "Auto" chip out here deciding for every skill at once.
  void _openPractice(PerformanceModality modality) {
    switch (modality) {
      case PerformanceModality.readingRecognition:
        AppRouter.push(context, (_) => const VocabPickerScreen());
      case PerformanceModality.listeningRecognition:
        AppRouter.push(context, (_) => const ListeningLabScreen());
      case PerformanceModality.controlledWriting:
      case PerformanceModality.spontaneousWriting:
        AppRouter.push(context, (_) => const WritingLabScreen());
      case PerformanceModality.pronunciationProduction:
        _openSession(
          lessonContext:
              'Focus this conversation on pronunciation coaching: minimal '
              'pairs, liaison, nasal vowels, and mouth-position tips for '
              'common English-speaker mistakes. Have the learner repeat '
              'words and sentences aloud and correct them gently.',
        );
      case PerformanceModality.controlledSpeaking:
      case PerformanceModality.spontaneousSpeaking:
        _openSession();
    }
  }

  /// Every Keep Practising chip funnels through here — [labId] is the same
  /// identifier `SubscriptionGateService.isLabLocked` and the Practice tab
  /// use, so a locked skill shows the paywall here exactly like it does
  /// everywhere else. `null` means the skill is never lab-gated (Speaking/
  /// Pronunciation are quota-gated by the daily AI-minutes cap instead).
  Future<void> _openGated(String? labId, VoidCallback action) async {
    if (labId != null &&
        ref.read(subscriptionGateServiceProvider).isLabLocked(labId)) {
      final subscribed = await AppRouter.push<bool>(
        context,
        (_) => const PaywallScreen(),
        fullscreenDialog: true,
      );
      if (subscribed != true || !mounted) return;
    }
    action();
  }

  Widget _keepPractising() {
    final gate = ref.watch(subscriptionGateServiceProvider);
    final chips = <WebPracticeShortcut>[
      WebPracticeShortcut(
        icon: CupertinoIcons.square_stack_3d_up,
        label: 'Vocabulary',
        locked: gate.isLabLocked('vocabulary'),
        onTap: () => _openGated(
          'vocabulary',
          () => _openPractice(PerformanceModality.readingRecognition),
        ),
      ),
      WebPracticeShortcut(
        icon: CupertinoIcons.mic_fill,
        label: 'Pronunciation',
        locked: false,
        onTap: () => _openGated(
          null,
          () => _openPractice(PerformanceModality.pronunciationProduction),
        ),
      ),
      WebPracticeShortcut(
        icon: CupertinoIcons.headphones,
        label: 'Listening',
        locked: gate.isLabLocked('listening'),
        onTap: () => _openGated(
          'listening',
          () => _openPractice(PerformanceModality.listeningRecognition),
        ),
      ),
      WebPracticeShortcut(
        icon: CupertinoIcons.book,
        label: 'Reading',
        locked: gate.isLabLocked('listening'),
        onTap: () => _openGated(
          'listening',
          () => AppRouter.push(context, (_) => const ListeningLabScreen()),
        ),
      ),
      WebPracticeShortcut(
        icon: CupertinoIcons.book,
        label: 'Grammar',
        locked: gate.isLabLocked('grammar'),
        onTap: () => _openGated(
          'grammar',
          () => AppRouter.push(context, (_) => const GrammarLabScreen()),
        ),
      ),
      WebPracticeShortcut(
        icon: CupertinoIcons.waveform,
        label: 'Liaison',
        locked: gate.isLabLocked('liaison'),
        onTap: () => _openGated(
          'liaison',
          () => AppRouter.push(context, (_) => const LiaisonLabScreen()),
        ),
      ),
      WebPracticeShortcut(
        icon: CupertinoIcons.bubble_left_bubble_right,
        label: 'Roleplay',
        locked: gate.isLabLocked('roleplay'),
        onTap: () => _openGated(
          'roleplay',
          () => AppRouter.push(context, (_) => const RoleplayLabScreen()),
        ),
      ),
      WebPracticeShortcut(
        icon: CupertinoIcons.pencil,
        label: 'Writing',
        locked: gate.isLabLocked('writing'),
        onTap: () => _openGated(
          'writing',
          () => _openPractice(PerformanceModality.controlledWriting),
        ),
      ),
      WebPracticeShortcut(
        icon: CupertinoIcons.waveform,
        label: 'Speaking',
        locked: false,
        onTap: () => _openGated(
          null,
          () => _openPractice(PerformanceModality.spontaneousSpeaking),
        ),
      ),
    ];
    if (MediaQuery.sizeOf(context).width >= DesignTokens.breakpointExpanded) {
      return WebPracticeGrid(items: chips);
    }

    final focusItems = [
      (
        shortcut: chips[0],
        duration: '8 min',
        state: 'Ready',
        detail: 'Strengthen active recall',
      ),
      (
        shortcut: chips[4],
        duration: '12 min',
        state: 'Building',
        detail: 'Make your sentences more precise',
      ),
      (
        shortcut: chips[8],
        duration: '18 min',
        state: 'Next',
        detail: 'Use today’s language in conversation',
      ),
    ];

    return PasseportCard(
      padding: 0,
      child: Column(
        children: [
          for (var index = 0; index < focusItems.length; index++) ...[
            if (index > 0)
              Padding(
                padding: const EdgeInsets.only(left: 68),
                child: Container(height: 1, color: DesignTokens.hairline),
              ),
            _StudyBlockRow(
              shortcut: focusItems[index].shortcut,
              duration: focusItems[index].duration,
              state: focusItems[index].state,
              detail: focusItems[index].detail,
              onTap: () {
                PSHaptics.light();
                focusItems[index].shortcut.onTap();
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _momentumCard() {
    final doneToday = DailyGoalService.categoriesToday(_sessions).length;
    final goalTotal = DailyGoalService.categories.length;
    final weekStart = DateTime.now().subtract(const Duration(days: 7));
    final sessionsThisWeek = _sessions.where((session) {
      return DateTime.tryParse(session.startedAt)?.isAfter(weekStart) ?? false;
    }).length;

    return PasseportCard(
      padding: 18,
      child: Row(
        children: [
          Expanded(
            child: _Metric(
              value: '$doneToday/$goalTotal',
              label: 'plan items today',
              color: doneToday == goalTotal
                  ? DesignTokens.success
                  : DesignTokens.primary,
            ),
          ),
          Container(width: 1, height: 42, color: DesignTokens.hairline),
          Expanded(
            child: _Metric(
              value: '$sessionsThisWeek',
              label: sessionsThisWeek == 1
                  ? 'session this week'
                  : 'sessions this week',
              color: Passeport.sky,
            ),
          ),
        ],
      ),
    );
  }

  Widget _journalCard() {
    return PasseportCard(
      padding: 6,
      child: Column(
        children: [
          for (final session in _sessions.take(2))
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => AppRouter.push(
                context,
                (_) => HistoryScreen(session: session),
              ),
              child: SessionRow(session: session),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Container(height: 1, color: Passeport.hairline),
          ),
          _notesRow(inCard: true),
        ],
      ),
    );
  }

  Widget _notesRow({bool inCard = false}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => AppRouter.push(context, (_) => const NotesReviewScreen()),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: inCard ? 12 : 16,
          vertical: 13,
        ),
        decoration: inCard
            ? null
            : BoxDecoration(
                color: Passeport.card,
                borderRadius: BorderRadius.circular(16),
                boxShadow: DesignTokens.cardShadow,
              ),
        child: Row(
          children: [
            const Icon(
              CupertinoIcons.square_pencil,
              size: 18,
              color: Passeport.sky,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Review your notes',
                style: Passeport.body(14, weight: FontWeight.w600),
              ),
            ),
            const Icon(
              CupertinoIcons.chevron_right,
              size: 14,
              color: Passeport.slate,
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.value,
    required this.label,
    required this.color,
  });

  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: DesignTokens.display(24).copyWith(color: color)),
        const SizedBox(height: 2),
        Text(
          label,
          textAlign: TextAlign.center,
          style: DesignTokens.body(11.5).copyWith(color: DesignTokens.mutedDim),
        ),
      ],
    );
  }
}

class _StudyBlockRow extends StatelessWidget {
  const _StudyBlockRow({
    required this.shortcut,
    required this.duration,
    required this.state,
    required this.detail,
    required this.onTap,
  });

  final WebPracticeShortcut shortcut;
  final String duration;
  final String state;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final locked = shortcut.locked;
    return Semantics(
      button: true,
      label: locked ? '${shortcut.label} (subscribers only)' : shortcut.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: DesignTokens.space4,
            vertical: DesignTokens.space3,
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: locked
                      ? DesignTokens.canvasDim
                      : DesignTokens.infoSoft,
                  borderRadius: BorderRadius.circular(DesignTokens.radiusSmall),
                ),
                child: Icon(
                  locked ? CupertinoIcons.lock_fill : shortcut.icon,
                  size: 18,
                  color: locked ? DesignTokens.muted : DesignTokens.info,
                ),
              ),
              const SizedBox(width: DesignTokens.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            shortcut.label,
                            style: DesignTokens.body(
                              15,
                              weight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Text(
                          duration,
                          style: DesignTokens.label(
                            11,
                          ).copyWith(color: DesignTokens.mutedDim),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      detail,
                      style: DesignTokens.body(
                        12.5,
                      ).copyWith(color: DesignTokens.mutedDim),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: DesignTokens.space2),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: DesignTokens.space2,
                  vertical: DesignTokens.space1,
                ),
                decoration: BoxDecoration(
                  color: state == 'Next'
                      ? DesignTokens.primarySoft
                      : DesignTokens.canvasDim,
                  borderRadius: BorderRadius.circular(DesignTokens.radiusSmall),
                ),
                child: Text(
                  state,
                  style: DesignTokens.label(10).copyWith(
                    color: state == 'Next'
                        ? DesignTokens.primary
                        : DesignTokens.mutedDim,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
