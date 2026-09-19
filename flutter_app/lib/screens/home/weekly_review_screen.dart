import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../design/app_router.dart';
import '../../design/tokens.dart';
import '../../providers/database_provider.dart';
import '../../services/free_talk_session_launcher.dart';
import '../../services/speak_language_profile.dart';
import '../../services/weekly_report_service.dart';
import '../../widgets/learning_card.dart';
import '../../widgets/primary_action_button.dart';
import '../../widgets/web/web_constrained_view.dart';
import '../labs/labs_screen.dart';
import '../labs/vocab_lab_screen.dart';
import '../labs/vocabulary_flashcards_screen.dart';
import '../labs/writing_lab_screen.dart';
import '../speak/speak_review_screen.dart';

/// Four short, swipeable views of this learner's actual practice for one
/// Monday–Sunday week. It is intentionally derived from existing local records
/// each time it opens; there is no generated or cached report to become stale.
class WeeklyReviewScreen extends ConsumerStatefulWidget {
  const WeeklyReviewScreen({super.key});

  @override
  ConsumerState<WeeklyReviewScreen> createState() => _WeeklyReviewScreenState();
}

class _WeeklyReviewScreenState extends ConsumerState<WeeklyReviewScreen> {
  static const _pageCount = 4;

  final PageController _pages = PageController();
  WeeklyReport? _report;
  Object? _error;
  int _page = 0;
  int _weekOffset = 0;
  String _wordFilter = 'All';

  static const _titles = [
    'Your French this week',
    'Words from your week',
    'Corrections worth keeping',
    'Your next best step',
  ];

  @override
  void initState() {
    super.initState();
    _loadReport(notify: false);
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _loadReport({bool notify = true}) {
    try {
      final learning = ref.read(learningStoreProvider);
      final report = WeeklyReportService(
        learning: learning,
        storage: ref.read(storageServiceProvider),
        vocabularySessions: ref.read(vocabularySessionStoreProvider),
        content: ref.read(contentServiceProvider),
      ).compute(weekOffset: _weekOffset);
      if (!notify || !mounted) {
        _report = report;
        _error = null;
      } else {
        setState(() {
          _report = report;
          _error = null;
        });
      }
    } catch (error) {
      if (!notify || !mounted) {
        _error = error;
      } else {
        setState(() => _error = error);
      }
    }
  }

  void _changeWeek(int offset) {
    setState(() {
      _weekOffset += offset;
      _wordFilter = 'All';
      _page = 0;
    });
    if (_pages.hasClients) _pages.jumpToPage(0);
    _loadReport();
  }

  Future<void> _openVocabulary({bool revisitOnly = false}) async {
    final report = _report;
    if (report == null || report.words.isEmpty) {
      await AppRouter.push(context, (_) => const VocabLabScreen());
      if (mounted) _loadReport();
      return;
    }

    final words = revisitOnly
        ? report.words.where((word) => word.needsAnotherLook).toList()
        : report.words;
    final entries = (words.isEmpty ? report.words : words)
        .map((word) => word.entry)
        .take(5)
        .toList(growable: false);
    final content = ref.read(contentServiceProvider);
    final profile = SpeakLanguageProfile.forProfile(
      ref.read(learningStoreProvider).profile(),
    );
    await AppRouter.push<bool>(
      context,
      (_) => VocabularyFlashcardsScreen(
        title: 'Your weekly words',
        entries: entries,
        source: 'weekly_review',
        topic: 'French words from your week',
        levelBand: profile.level,
        studyDepth: VocabularyStudyDepth.wordsAndSentences,
        storyExamples: content.vocabExamplesFor(entries),
      ),
      fullscreenDialog: true,
    );
    if (mounted) _loadReport();
  }

  Future<void> _openWriting() async {
    await AppRouter.push(context, (_) => const WritingLabScreen());
    if (mounted) _loadReport();
  }

  Future<void> _openSpeaking() async {
    await openFreeTalkSession(context, ref);
    if (mounted) _loadReport();
  }

  Future<void> _openPersonalisedReview() async {
    await AppRouter.push(
      context,
      (_) => const SpeakReviewScreen(kind: 'review'),
    );
    if (mounted) _loadReport();
  }

  Future<void> _openExplore() async {
    await AppRouter.push(context, (_) => const LabsScreen());
    if (mounted) _loadReport();
  }

  bool _hasReviewEvidence(WeeklyReport report) =>
      report.sessions.isNotEmpty ||
      report.words.isNotEmpty ||
      report.corrections.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final report = _report;
    return Scaffold(
      backgroundColor: DesignTokens.canvas,
      body: SafeArea(
        child: WebConstrainedView(
          child: Column(
            children: [
              _header(report),
              if (_error != null)
                Expanded(child: _errorState())
              else if (report == null)
                const Expanded(
                  child: Center(child: CircularProgressIndicator()),
                )
              else ...[
                Expanded(
                  child: PageView(
                    controller: _pages,
                    onPageChanged: (page) => setState(() => _page = page),
                    children: [
                      _overview(report),
                      _wordsPage(report),
                      _correctionsPage(report),
                      _nextStepPage(report),
                    ],
                  ),
                ),
                _pageControls(report),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(WeeklyReport? report) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Column(
        children: [
          SizedBox(
            height: 48,
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Back',
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back_rounded),
                  color: DesignTokens.ink,
                ),
                Expanded(
                  child: Text(
                    _titles[_page],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: DesignTokens.body(17, weight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 48),
              ],
            ),
          ),
          if (report != null)
            Row(
              children: [
                IconButton(
                  tooltip: 'Previous week',
                  onPressed: () => _changeWeek(-1),
                  icon: const Icon(Icons.chevron_left_rounded),
                  visualDensity: VisualDensity.compact,
                  color: DesignTokens.muted,
                ),
                Expanded(
                  child: Text(
                    '${_rangeLabel(report.weekStart, report.weekEndExclusive)}  ·  '
                    '${_weekOffset == 0 ? 'Updates as you practise' : 'Completed week'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: DesignTokens.body(
                      12,
                      weight: FontWeight.w500,
                    ).copyWith(color: DesignTokens.mutedDim),
                  ),
                ),
                IconButton(
                  tooltip: 'Next week',
                  onPressed: _weekOffset < 0 ? () => _changeWeek(1) : null,
                  icon: const Icon(Icons.chevron_right_rounded),
                  visualDensity: VisualDensity.compact,
                  color: DesignTokens.muted,
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _overview(WeeklyReport report) {
    final headline = switch (report.activeDays) {
      0 => 'Your week starts here.',
      1 => 'You’ve made a start.',
      >= 4 => 'Your French moved forward.',
      _ => 'You showed up for French.',
    };
    final summary =
        '${report.activeDays} active ${report.activeDays == 1 ? 'day' : 'days'}'
        '  ·  ${report.sessions.length} ${report.sessions.length == 1 ? 'session' : 'sessions'}'
        '  ·  ${report.practiceMinutes} min';

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
      children: [
        Text(headline, style: DesignTokens.display(28)),
        const SizedBox(height: 7),
        Text(
          summary,
          style: DesignTokens.body(14).copyWith(color: DesignTokens.mutedDim),
        ),
        const SizedBox(height: 18),
        LearningCard(
          padding: 16,
          child: Column(
            children: [
              Row(
                children: [
                  for (final day in report.days)
                    Expanded(child: _dayMarker(day)),
                ],
              ),
              if (report.activeDays > 0) ...[
                const SizedBox(height: 14),
                Divider(height: 1, color: DesignTokens.hairline),
                const SizedBox(height: 12),
                Text(
                  'A little practice adds up. Keep your rhythm going.',
                  textAlign: TextAlign.center,
                  style: DesignTokens.body(
                    12,
                  ).copyWith(color: DesignTokens.mutedDim),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 22),
        _sectionLabel('YOUR WEEK, AT A GLANCE'),
        const SizedBox(height: 10),
        LearningCard(
          padding: 8,
          child: Column(
            children: [
              _overviewRow(
                icon: Icons.auto_stories_rounded,
                title: 'Words practised',
                value:
                    '${report.words.length} ${report.words.length == 1 ? 'word' : 'words'}',
                onTap: () => _goToPage(1),
                showDivider: true,
              ),
              _overviewRow(
                icon: Icons.replay_rounded,
                title: 'Corrections to revisit',
                value: '${report.corrections.length} saved',
                onTap: () => _goToPage(2),
                showDivider: true,
              ),
              _overviewRow(
                icon: Icons.mic_none_rounded,
                title: 'Speaking practice',
                value:
                    '${report.speakingTurns} learner ${report.speakingTurns == 1 ? 'turn' : 'turns'}',
                onTap: () => _goToPage(2),
              ),
            ],
          ),
        ),
        if (report.latestLearnerLine != null) ...[
          const SizedBox(height: 22),
          _sectionLabel('A LINE FROM YOUR PRACTICE'),
          const SizedBox(height: 10),
          LearningCard(
            padding: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  report.latestLearnerLine!,
                  style: DesignTokens.display(17),
                ),
                const SizedBox(height: 5),
                Text(
                  'From your latest saved speaking session.',
                  style: DesignTokens.body(
                    12,
                  ).copyWith(color: DesignTokens.mutedDim),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 4),
      ],
    );
  }

  Widget _dayMarker(WeeklyReportDay day) {
    final weekday = DateFormat.E().format(day.date).substring(0, 1);
    final fill = day.isActive ? DesignTokens.primary : DesignTokens.canvasDim;
    final foreground = day.isActive
        ? DesignTokens.onPrimary
        : DesignTokens.muted;
    return Column(
      children: [
        Text(
          weekday,
          style: DesignTokens.body(
            11,
            weight: FontWeight.w600,
          ).copyWith(color: DesignTokens.mutedDim),
        ),
        const SizedBox(height: 8),
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: fill,
            shape: BoxShape.circle,
            border: Border.all(
              color: day.isActive
                  ? DesignTokens.primary
                  : DesignTokens.muted.withValues(alpha: 0.55),
            ),
          ),
          child: day.isActive
              ? Icon(Icons.check_rounded, size: 19, color: foreground)
              : day.isFuture
              ? null
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _overviewRow({
    required IconData icon,
    required String title,
    required String value,
    required VoidCallback onTap,
    bool showDivider = false,
  }) {
    return Column(
      children: [
        Semantics(
          button: true,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: DesignTokens.primarySoft,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, size: 17, color: DesignTokens.primary),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: DesignTokens.body(14, weight: FontWeight.w600),
                    ),
                  ),
                  Text(
                    value,
                    style: DesignTokens.body(
                      12,
                    ).copyWith(color: DesignTokens.mutedDim),
                  ),
                  const SizedBox(width: 7),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: DesignTokens.muted,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (showDivider)
          Padding(
            padding: const EdgeInsets.only(left: 55, right: 8),
            child: Divider(height: 1, color: DesignTokens.hairline),
          ),
      ],
    );
  }

  Widget _wordsPage(WeeklyReport report) {
    final words = switch (_wordFilter) {
      'Recalled' => report.words.where((word) => word.wasRecalled).toList(),
      'Review' => report.words.where((word) => word.needsAnotherLook).toList(),
      _ => report.words,
    };
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
      children: [
        Text(
          '${report.words.length} practised  ·  ${report.recalledWords} recalled',
          style: DesignTokens.body(14).copyWith(color: DesignTokens.mutedDim),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final filter in const ['All', 'Recalled', 'Review'])
              Semantics(
                button: true,
                selected: _wordFilter == filter,
                label: filter,
                child: InkWell(
                  onTap: () => setState(() => _wordFilter = filter),
                  borderRadius: BorderRadius.circular(13),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: _wordFilter == filter
                          ? DesignTokens.primary
                          : DesignTokens.surface,
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(
                        color: _wordFilter == filter
                            ? DesignTokens.primary
                            : DesignTokens.hairline,
                      ),
                    ),
                    child: Text(
                      filter,
                      style: DesignTokens.body(12, weight: FontWeight.w600)
                          .copyWith(
                            color: _wordFilter == filter
                                ? DesignTokens.onPrimary
                                : DesignTokens.mutedDim,
                          ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 13),
        if (words.isEmpty)
          _emptyCard(
            icon: Icons.auto_stories_rounded,
            title: report.words.isEmpty
                ? 'Your practised words will appear here.'
                : 'No words in this group yet.',
            body: report.words.isEmpty
                ? 'Words appear after a saved vocabulary or review session.'
                : 'Choose another filter to see the rest of your week.',
          )
        else
          for (final word in words) ...[
            _wordCard(word),
            const SizedBox(height: 9),
          ],
      ],
    );
  }

  Widget _wordCard(WeeklyWordProgress word) {
    final status = word.needsAnotherLook
        ? 'Needs another look'
        : word.wasRecalled
        ? 'Recalled'
        : 'Practised';
    final statusColor = word.needsAnotherLook
        ? DesignTokens.primary
        : word.wasRecalled
        ? DesignTokens.success
        : DesignTokens.mutedDim;
    return LearningCard(
      padding: 15,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(word.entry.fr, style: DesignTokens.display(19)),
                const SizedBox(height: 2),
                Text(
                  word.entry.en,
                  style: DesignTokens.body(
                    13,
                  ).copyWith(color: DesignTokens.mutedDim),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                status,
                style: DesignTokens.body(
                  12,
                  weight: FontWeight.w600,
                ).copyWith(color: statusColor),
              ),
              Text(
                '${word.practiceCount} ${word.practiceCount == 1 ? 'practice' : 'practices'}',
                style: DesignTokens.body(
                  11,
                ).copyWith(color: DesignTokens.mutedDim),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _correctionsPage(WeeklyReport report) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
      children: [
        Text(
          'From writing feedback saved this week.',
          style: DesignTokens.body(14).copyWith(color: DesignTokens.mutedDim),
        ),
        const SizedBox(height: 15),
        if (report.corrections.isEmpty)
          _emptyCard(
            icon: Icons.edit_note_rounded,
            title: 'No saved corrections this week.',
            body:
                'Corrections from writing feedback will show here when you practise.',
          )
        else
          for (final correction in report.corrections) ...[
            _correctionCard(correction),
            const SizedBox(height: 10),
          ],
        if (report.speakingSessions > 0) ...[
          const SizedBox(height: 13),
          _sectionLabel('SPEAKING THIS WEEK'),
          const SizedBox(height: 9),
          LearningCard(
            padding: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.mic_none_rounded, color: DesignTokens.primary),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        '${report.speakingTurns} learner ${report.speakingTurns == 1 ? 'turn' : 'turns'}',
                        style: DesignTokens.body(15, weight: FontWeight.w700),
                      ),
                    ),
                    Text(
                      '${report.speakingSessions} ${report.speakingSessions == 1 ? 'session' : 'sessions'}',
                      style: DesignTokens.body(
                        12,
                      ).copyWith(color: DesignTokens.mutedDim),
                    ),
                  ],
                ),
                if (report.latestLearnerLine != null) ...[
                  const SizedBox(height: 13),
                  Divider(height: 1, color: DesignTokens.hairline),
                  const SizedBox(height: 12),
                  Text(
                    'A line from your practice',
                    style: DesignTokens.body(
                      12,
                    ).copyWith(color: DesignTokens.mutedDim),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    report.latestLearnerLine!,
                    style: DesignTokens.display(17),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _correctionCard(WeeklyCorrection correction) {
    return LearningCard(
      padding: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'You wrote',
            style: DesignTokens.body(12).copyWith(color: DesignTokens.mutedDim),
          ),
          const SizedBox(height: 4),
          Text(
            correction.original,
            style: DesignTokens.body(15).copyWith(
              color: DesignTokens.mutedDim,
              decoration: TextDecoration.lineThrough,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Try this',
            style: DesignTokens.body(
              12,
              weight: FontWeight.w700,
            ).copyWith(color: DesignTokens.primary),
          ),
          const SizedBox(height: 3),
          Text(correction.corrected, style: DesignTokens.display(18)),
          if (correction.explanation.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              correction.explanation,
              style: DesignTokens.body(
                13,
              ).copyWith(color: DesignTokens.mutedDim, height: 1.4),
            ),
          ],
          if (correction.timesSeen > 1) ...[
            const SizedBox(height: 8),
            Text(
              'Saved in ${correction.timesSeen} feedback notes',
              style: DesignTokens.body(
                11,
              ).copyWith(color: DesignTokens.mutedDim),
            ),
          ],
        ],
      ),
    );
  }

  Widget _nextStepPage(WeeklyReport report) {
    final hasNextStep =
        report.wordsToRevisit > 0 ||
        report.corrections.isNotEmpty ||
        report.speakingSessions > 0 ||
        report.mostPractisedSkill != null;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
      children: [
        LearningCard(
          padding: 17,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.track_changes_rounded,
                    color: DesignTokens.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      hasNextStep
                          ? 'Build on this week’s practice'
                          : 'Your next step',
                      style: DesignTokens.body(16, weight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                hasNextStep
                    ? 'A few focused minutes, using what you actually practised.'
                    : 'Your first practice gives us something useful to build on.',
                style: DesignTokens.body(
                  13,
                ).copyWith(color: DesignTokens.mutedDim, height: 1.4),
              ),
              if (report.wordsToRevisit > 0) ...[
                const SizedBox(height: 12),
                _nextStepRow(
                  icon: Icons.replay_rounded,
                  title:
                      'Revisit ${report.wordsToRevisit} ${report.wordsToRevisit == 1 ? 'word' : 'words'}',
                  subtitle: 'From your saved vocabulary practice',
                  onTap: () => _openVocabulary(revisitOnly: true),
                ),
              ],
              if (report.corrections.isNotEmpty) ...[
                const SizedBox(height: 7),
                _nextStepRow(
                  icon: Icons.edit_note_rounded,
                  title: 'Keep building your written French',
                  subtitle:
                      '${report.corrections.length} saved ${report.corrections.length == 1 ? 'correction' : 'corrections'} to learn from',
                  onTap: _openWriting,
                ),
              ],
              if (report.speakingSessions > 0) ...[
                const SizedBox(height: 7),
                _nextStepRow(
                  icon: Icons.mic_none_rounded,
                  title: 'Continue a conversation',
                  subtitle: 'Keep practising with your tutor',
                  onTap: _openSpeaking,
                ),
              ],
              if (report.wordsToRevisit == 0 &&
                  report.corrections.isEmpty &&
                  report.speakingSessions == 0 &&
                  report.mostPractisedSkill != null) ...[
                const SizedBox(height: 12),
                _nextStepRow(
                  icon: Icons.auto_awesome_rounded,
                  title:
                      'Keep going with ${report.mostPractisedSkill!.toLowerCase()}',
                  subtitle: 'Your most-practised skill this week',
                  onTap: _openExplore,
                ),
              ],
              if (!hasNextStep) ...[
                const SizedBox(height: 14),
                Text(
                  'Nothing here is made up: this page will grow as your real practice does.',
                  style: DesignTokens.body(
                    12,
                  ).copyWith(color: DesignTokens.mutedDim, height: 1.4),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Your report updates as new practice is saved. Previous weeks remain available from the arrows above.',
          style: DesignTokens.body(
            12,
          ).copyWith(color: DesignTokens.mutedDim, height: 1.45),
        ),
      ],
    );
  }

  Widget _nextStepRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: DesignTokens.canvasDim,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            children: [
              Icon(icon, color: DesignTokens.primary, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: DesignTokens.body(13, weight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: DesignTokens.body(
                        11,
                      ).copyWith(color: DesignTokens.mutedDim),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: DesignTokens.muted),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyCard({
    required IconData icon,
    required String title,
    required String body,
  }) {
    return LearningCard(
      padding: 18,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: DesignTokens.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: DesignTokens.body(15, weight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: DesignTokens.body(
                    13,
                  ).copyWith(color: DesignTokens.mutedDim, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String value) => Text(
    value,
    style: DesignTokens.label(
      11,
      weight: FontWeight.w800,
    ).copyWith(color: DesignTokens.primary, letterSpacing: 1.35),
  );

  Widget _pageControls(WeeklyReport report) {
    final action = switch (_page) {
      0 => _hasReviewEvidence(report) ? 'Next step' : 'Explore',
      1 => report.words.isEmpty ? 'Explore' : 'Review words',
      2 => 'Try writing',
      _ => _hasReviewEvidence(report) ? 'Start review' : 'Explore',
    };
    final onPressed = switch (_page) {
      0 => _hasReviewEvidence(report) ? () => _goToPage(3) : _openExplore,
      1 => _openVocabulary,
      2 => _openWriting,
      _ => _hasReviewEvidence(report) ? _openPersonalisedReview : _openExplore,
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 7, 20, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var index = 0; index < _pageCount; index++)
                Semantics(
                  button: true,
                  label: 'Page ${index + 1} of $_pageCount',
                  child: GestureDetector(
                    onTap: () => _goToPage(index),
                    child: AnimatedContainer(
                      duration: DesignTokens.durationFast,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: _page == index ? 24 : 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: _page == index
                            ? DesignTokens.primary
                            : DesignTokens.hairline,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 11),
          PrimaryActionButton(
            label: action,
            onPressed: onPressed,
            icon: Icons.arrow_forward_rounded,
          ),
        ],
      ),
    );
  }

  void _goToPage(int index) {
    _pages.animateToPage(
      index,
      duration: DesignTokens.durationMedium,
      curve: DesignTokens.curveStandard,
    );
  }

  Widget _errorState() => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.info_outline_rounded, size: 30),
          const SizedBox(height: 12),
          Text(
            'Your weekly review could not load.',
            textAlign: TextAlign.center,
            style: DesignTokens.body(16, weight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'Your saved practice is safe. Try loading the report again.',
            textAlign: TextAlign.center,
            style: DesignTokens.body(13).copyWith(color: DesignTokens.mutedDim),
          ),
          const SizedBox(height: 15),
          TextButton(onPressed: _loadReport, child: const Text('Try again')),
        ],
      ),
    ),
  );

  static String _rangeLabel(DateTime start, DateTime endExclusive) {
    final end = endExclusive.subtract(const Duration(days: 1));
    final sameYear = start.year == end.year;
    final startLabel = DateFormat(
      sameYear ? 'MMM d' : 'MMM d, y',
    ).format(start);
    final endLabel = DateFormat(sameYear ? 'd' : 'MMM d, y').format(end);
    return '$startLabel–$endLabel';
  }
}
