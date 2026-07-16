import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../config/api_keys.dart';
import '../../config/theme.dart';
import '../../design/app_router.dart';
import '../../models/daily_session.dart';
import '../../models/session.dart';
import '../../providers/database_provider.dart';
import '../../services/lesson_speech_service.dart';
import '../../widgets/adaptive/adaptive.dart';
import '../../widgets/passeport_card.dart';
import '../history/history_screen.dart';
import '../notes/notes_review_screen.dart';
import '../session/session_screen.dart';
import '../settings/settings_screen.dart';
import 'daily_pathway_widget.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  List<Session> _sessions = [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _openSession({String? lessonContext}) async {
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
  }

  @override
  Widget build(BuildContext context) {
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
                const SizedBox(height: 22),
                DailyPathwayWidget(onProgress: _reload),
                const SizedBox(height: 28),
                _sectionTitle('Practice your way'),
                const SizedBox(height: 10),
                _mariePractice(),
                const SizedBox(height: 28),
                _sectionTitle('Your momentum'),
                const SizedBox(height: 10),
                _momentumCard(),
                if (_sessions.isNotEmpty) ...[
                  const SizedBox(height: 28),
                  _sectionTitle('Recent practice'),
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
                DateFormat('EEEE, MMMM d').format(DateTime.now()).toUpperCase(),
                style: Passeport.body(
                  10.5,
                  weight: FontWeight.w700,
                ).copyWith(color: Passeport.slateDim, letterSpacing: 1),
              ),
              const SizedBox(height: 5),
              Text('Bonjour', style: Passeport.display(32)),
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
            onTap: () => AppRouter.push(context, (_) => const SettingsScreen()),
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
        color: Passeport.infoSoft,
        borderRadius: BorderRadius.circular(18),
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

  Widget _momentumCard() {
    final today = ref.read(learningStoreProvider).dailySession();
    final completed = PathwayStage.values.where((stage) {
      final status = today.stages[stage]!.status;
      return status == StageStatus.completed || status == StageStatus.skipped;
    }).length;
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
              value: '$completed/5',
              label: 'steps today',
              color: completed == 5 ? Passeport.sage : Passeport.maroon,
            ),
          ),
          Container(width: 1, height: 42, color: Passeport.hairline),
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
              child: _SessionRow(session: session),
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
        Text(value, style: Passeport.display(24).copyWith(color: color)),
        const SizedBox(height: 2),
        Text(
          label,
          textAlign: TextAlign.center,
          style: Passeport.body(11.5).copyWith(color: Passeport.slateDim),
        ),
      ],
    );
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({required this.session});

  final Session session;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Passeport.primarySoft,
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(
              CupertinoIcons.chat_bubble_fill,
              size: 16,
              color: Passeport.maroon,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.topic ?? 'French practice',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Passeport.body(13.5, weight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  _formatDate(session.startedAt),
                  style: Passeport.body(
                    11.5,
                  ).copyWith(color: Passeport.slateDim),
                ),
              ],
            ),
          ),
          if (_stageLabel != null)
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: Passeport.infoSoft,
                borderRadius: BorderRadius.circular(100),
              ),
              child: Text(
                _stageLabel!,
                style: Passeport.body(
                  10.5,
                  weight: FontWeight.w600,
                ).copyWith(color: Passeport.sky),
              ),
            ),
          const Icon(
            CupertinoIcons.chevron_right,
            size: 13,
            color: Passeport.slate,
          ),
        ],
      ),
    );
  }

  String? get _stageLabel {
    switch (session.stage) {
      case 'vocab':
        return 'Vocab';
      case 'grammar':
        return 'Grammar';
      case 'reading_listening':
        return 'Reading';
      case 'writing':
        return 'Writing';
      case 'speaking':
        return 'Speaking';
      default:
        return null;
    }
  }

  String _formatDate(String iso) {
    try {
      return DateFormat('MMM d').format(DateTime.parse(iso));
    } catch (_) {
      return iso;
    }
  }
}
