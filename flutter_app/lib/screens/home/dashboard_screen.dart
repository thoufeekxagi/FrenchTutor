import '../../widgets/adaptive/adaptive.dart';
import '../../design/app_router.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../config/theme.dart';
import '../../widgets/passeport_card.dart';
import '../../widgets/kicker_text.dart';
import '../../providers/database_provider.dart';
import '../../models/session.dart';
import '../../models/content_models.dart';
import '../../config/api_keys.dart';
import '../../services/lesson_speech_service.dart';
import '../session/session_screen.dart';
import '../notes/notes_review_screen.dart';
import '../history/history_screen.dart';
import 'daily_pathway_widget.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  List<Session> _sessions = [];
  bool _loading = true;
  int _activeDaysThisMonth = 0;
  RoadmapMonth? _currentMonth;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _openSession({String? lessonContext}) async {
    LessonSpeechService.shared.deactivate();
    await Navigator.of(context).push(
      AppRouter.route(fullscreenDialog: true, builder: (_) => SessionScreen(apiKey: ApiKeys.geminiKey, lessonContext: lessonContext),
      ),
    );
    _reload();
  }

  void _reload() {
    final progress = ref.read(progressServiceProvider);
    final storage = ref.read(storageServiceProvider);

    final store = ref.read(learningStoreProvider);
    final monthPrefix = store.dayString(DateTime.now()).substring(0, 7);
    setState(() {
      _activeDaysThisMonth = store.activeDays().where((d) => d.startsWith(monthPrefix)).length;
      _loading = true;
    });

    progress.currentMonth().then((month) {
      if (mounted) setState(() => _currentMonth = month);
    });

    // Load sessions off the main isolate-style, but StorageService is sync
    // so just wrap in a future to keep the UI responsive.
    Future(() => storage.getAllSessions()).then((loaded) {
      if (mounted) {
        setState(() {
          _sessions = loaded;
          _loading = false;
        });
      }
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
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
            children: [
              _buildHeader(),
              const SizedBox(height: 14),
              DailyPathwayWidget(onProgress: _reload),
              const SizedBox(height: 14),
              _buildCallMarieCard(),
              const SizedBox(height: 14),
              _buildSpeakingTopics(),
              const SizedBox(height: 14),
              _buildRecentSessions(),
              const SizedBox(height: 14),
              _buildReviewNotesCard(),
            ],
          ),
        ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Header
  // ---------------------------------------------------------------------------

  Widget _buildHeader() {
    final goal = ref.read(learningStoreProvider).profile().goal;
    final goalLabel = switch (goal) {
      'tef_canada' => 'CLB 7 · TEF Canada',
      'everyday' => 'Everyday French',
      _ => 'Fundamentals',
    };
    final kickerParts = <String>[];
    if (_currentMonth != null) kickerParts.add('Month ${_currentMonth!.month}');
    kickerParts.add(goalLabel);

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                KickerText(kickerParts.join(' · '), color: Passeport.slateDim),
                const SizedBox(height: 3),
                Text(
                  'Bonjour !',
                  style: Passeport.display(32, weight: FontWeight.w600)
                      .copyWith(color: Passeport.text),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Passeport.card,
              borderRadius: BorderRadius.circular(100),
              border: Border.all(color: Passeport.hairline, width: 1),
            ),
            child: Text(
              '$_activeDaysThisMonth day${_activeDaysThisMonth == 1 ? '' : 's'} this month',
              style: Passeport.mono(11, weight: FontWeight.w500)
                  .copyWith(color: Passeport.text),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Call Marie card
  // ---------------------------------------------------------------------------

  Widget _buildCallMarieCard() {
    return GestureDetector(
      onTap: () => _openSession(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
        decoration: BoxDecoration(
          color: Passeport.ink,
          borderRadius: BorderRadius.circular(16),
          boxShadow: DesignTokens.cardShadow,
        ),
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
                  Text(
                    'Just talk to Marie',
                    style: Passeport.display(22, weight: FontWeight.w600)
                        .copyWith(color: Passeport.parchment),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Unstructured practice, any topic',
                    style: Passeport.body(12.5).copyWith(color: Passeport.slate),
                  ),
                ],
              ),
            ),
            const Icon(CupertinoIcons.chevron_right, size: 16, color: Passeport.slate),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Speaking topics
  // ---------------------------------------------------------------------------

  Widget _buildSpeakingTopics() {
    final content = ref.read(contentServiceProvider);
    final topics = content.resources()?.speakingTopics ?? [];
    if (topics.isEmpty) return const SizedBox.shrink();

    return PasseportCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Discuss a topic with Marie',
            style: Passeport.display(15, weight: FontWeight.w500)
                .copyWith(color: Passeport.text),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: topics.map((topic) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => _openSession(
                      lessonContext: ref.read(contentServiceProvider).speakingTopicContext(topic),
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                      decoration: BoxDecoration(
                        color: Passeport.maroon,
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: Text(
                        topic.title,
                        style: Passeport.body(13, weight: FontWeight.w500)
                            .copyWith(color: Colors.white),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Review notes
  // ---------------------------------------------------------------------------

  Widget _buildReviewNotesCard() {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        AppRouter.route(builder: (_) => const NotesReviewScreen()),
      ),
      child: PasseportCard(
        child: Row(
          children: [
            Icon(CupertinoIcons.square_pencil, size: 20, color: Passeport.brass),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Review notes',
                    style: Passeport.body(13.5, weight: FontWeight.w500).copyWith(color: Passeport.text),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    'Everything you jotted down, by lesson',
                    style: Passeport.mono(10).copyWith(color: Passeport.slateDim),
                  ),
                ],
              ),
            ),
            Icon(CupertinoIcons.chevron_right, size: 16, color: Passeport.slate),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Recent sessions
  // ---------------------------------------------------------------------------

  Widget _buildRecentSessions() {
    return PasseportCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Recent sessions',
            style: Passeport.display(16, weight: FontWeight.w500)
                .copyWith(color: Passeport.text),
          ),
          const SizedBox(height: 10),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: PSProgressIndicator()),
            )
          else if (_sessions.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  'No calls yet. Start your first French conversation!',
                  style: Passeport.body(13).copyWith(color: Passeport.slateDim),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          else
            ..._sessions.take(5).map((session) => GestureDetector(
                  onTap: () => Navigator.of(context).push(
                    AppRouter.route(builder: (_) => HistoryScreen(session: session)),
                  ),
                  child: _SessionCard(session: session),
                )),
        ],
      ),
    );
  }
}

// =============================================================================
// SessionCard
// =============================================================================

class _SessionCard extends StatelessWidget {
  const _SessionCard({required this.session});

  final Session session;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Passeport.parchmentDim,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Center(
              child: Icon(CupertinoIcons.chat_bubble_fill, size: 15, color: Passeport.maroon),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.topic ?? 'French practice',
                  style: Passeport.body(13.5, weight: FontWeight.w500)
                      .copyWith(color: Passeport.text),
                ),
                const SizedBox(height: 2),
                Text(
                  _formatDate(session.startedAt),
                  style: Passeport.mono(11).copyWith(color: Passeport.slateDim),
                ),
              ],
            ),
          ),
          if (_stageLabel != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Passeport.maroon.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(100),
              ),
              child: Text(
                _stageLabel!,
                style: Passeport.mono(9, weight: FontWeight.w500)
                    .copyWith(color: Passeport.maroon),
              ),
            ),
            const SizedBox(width: 4),
          ],
          Icon(CupertinoIcons.chevron_right, size: 12, color: Passeport.slate),
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
      final date = DateTime.parse(iso);
      return DateFormat('MMM d, y').format(date);
    } catch (_) {
      return iso;
    }
  }
}
