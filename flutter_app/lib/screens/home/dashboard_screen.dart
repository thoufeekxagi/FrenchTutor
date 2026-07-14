import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../config/api_keys.dart';
import '../../config/theme.dart';
import '../../design/app_router.dart';
import '../../models/session.dart';
import '../../providers/database_provider.dart';
import '../../services/lesson_speech_service.dart';
import '../../widgets/adaptive/adaptive.dart';
import '../../widgets/kicker_text.dart';
import '../../widgets/passeport_card.dart';
import '../history/history_screen.dart';
import '../notes/notes_review_screen.dart';
import '../session/session_screen.dart';
import 'daily_pathway_widget.dart';

/// Home (2026-07 redesign): three calm blocks, in this order —
///   1. Marie hero (navy) with topic pills inside it
///   2. Today's French (compact pathway card, the only maroon CTA)
///   3. Journal (recent sessions when they exist + review-notes row)
/// No stat chip in the header, no empty-state filler cards. The eye should
/// land on "Just talk to Marie", then Continue, then nothing else.
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
      (_) => SessionScreen(apiKey: ApiKeys.geminiKey, lessonContext: lessonContext),
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
      backgroundColor: Passeport.parchmentDim,
      body: SafeArea(
        child: PSContentColumn(
          child: RefreshIndicator(
            color: Passeport.maroon,
            onRefresh: () async => _reload(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              children: [
                _header(),
                const SizedBox(height: 18),
                _marieHero(),
                const SizedBox(height: 14),
                DailyPathwayWidget(onProgress: _reload),
                const SizedBox(height: 14),
                _journalCard(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Header — kicker + greeting, nothing else. Stats live on Progress.
  // ---------------------------------------------------------------------------

  Widget _header() {
    final goal = ref.read(learningStoreProvider).profile().goal;
    final goalLabel = switch (goal) {
      'tef_canada' => 'TEF Canada · CLB 7',
      'everyday' => 'Everyday French',
      _ => 'Fundamentals',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        KickerText(goalLabel, color: Passeport.slateDim),
        const SizedBox(height: 4),
        Text('Bonjour !', style: Passeport.display(30, weight: FontWeight.w700)),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Marie hero — the call AND the topics are one thing, one card.
  // ---------------------------------------------------------------------------

  Widget _marieHero() {
    final topics = ref.read(contentServiceProvider).resources()?.speakingTopics ?? [];

    return Container(
      decoration: BoxDecoration(
        color: Passeport.ink,
        borderRadius: BorderRadius.circular(16),
        boxShadow: DesignTokens.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              PSHaptics.light();
              _openSession();
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Passeport.brass.withValues(alpha: 0.18),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(CupertinoIcons.phone_fill, size: 20, color: Passeport.brass),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Just talk to Marie',
                            style: Passeport.display(19, weight: FontWeight.w600)
                                .copyWith(color: Colors.white)),
                        const SizedBox(height: 2),
                        Text('Live conversation, any topic',
                            style: Passeport.body(12.5).copyWith(color: Passeport.slate)),
                      ],
                    ),
                  ),
                  const Icon(CupertinoIcons.chevron_right, size: 16, color: Passeport.slate),
                ],
              ),
            ),
          ),
          if (topics.isNotEmpty) ...[
            Container(height: 1, color: Colors.white.withValues(alpha: 0.08)),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 0, 14),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final topic in topics)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: GestureDetector(
                          onTap: () {
                            PSHaptics.light();
                            _openSession(
                              lessonContext:
                                  ref.read(contentServiceProvider).speakingTopicContext(topic),
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(100),
                            ),
                            child: Text(topic.title,
                                style: Passeport.body(12.5, weight: FontWeight.w500)
                                    .copyWith(color: Passeport.parchment)),
                          ),
                        ),
                      ),
                    const SizedBox(width: 10),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Journal — sessions when they exist; the notes link always, as one row.
  // ---------------------------------------------------------------------------

  Widget _journalCard() {
    return PasseportCard(
      padding: 6,
      child: Column(
        children: [
          for (final session in _sessions.take(3))
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => AppRouter.push(context, (_) => HistoryScreen(session: session)),
              child: _SessionRow(session: session),
            ),
          if (_sessions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Container(height: 1, color: Passeport.hairline),
            ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => AppRouter.push(context, (_) => const NotesReviewScreen()),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
              child: Row(
                children: [
                  const Icon(CupertinoIcons.square_pencil, size: 18, color: Passeport.brass),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('Review notes',
                        style: Passeport.body(14, weight: FontWeight.w500)),
                  ),
                  const Icon(CupertinoIcons.chevron_right, size: 14, color: Passeport.slate),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({required this.session});

  final Session session;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: Passeport.parchmentDim,
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Center(
              child: Icon(CupertinoIcons.chat_bubble_fill, size: 14, color: Passeport.maroon),
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
                  style: Passeport.body(13.5, weight: FontWeight.w500),
                ),
                const SizedBox(height: 1),
                Text(_formatDate(session.startedAt),
                    style: Passeport.body(11.5).copyWith(color: Passeport.slateDim)),
              ],
            ),
          ),
          if (_stageLabel != null)
            Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Passeport.maroon.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(100),
              ),
              child: Text(_stageLabel!,
                  style: Passeport.body(10.5, weight: FontWeight.w500)
                      .copyWith(color: Passeport.maroon)),
            ),
          const Icon(CupertinoIcons.chevron_right, size: 13, color: Passeport.slate),
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
