import '../../widgets/adaptive/adaptive.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../config/theme.dart';
import '../../design/app_router.dart';
import '../../flow/stage_outcome.dart';
import '../../data/content_service.dart';
import '../../models/content_models.dart';
import '../../providers/database_provider.dart';
import '../../services/lesson_agent_service.dart';
import '../../services/session_recorder.dart';
import '../../widgets/passeport_card.dart';
import '../../widgets/kicker_text.dart';
import '../../widgets/passeport_primary_button.dart';
import 'agent_led_grammar_screen.dart';
import 'agent_led_vocab_screen.dart' show VocabStageResult;

enum _PickerMode { auto, manual }

/// Sits in front of the grammar stage, same role as VocabPickerScreen: Auto (the LLM picks
/// one tense/topic from today's candidates, informed by recurring mistakes — one lightweight
/// planning call, raced against a timeout, never live during teaching) or manual (student
/// picks directly from every tense/topic already authored in assets/content/grammar.json).
/// Ported from GrammarPickerView.swift.
class GrammarPickerScreen extends ConsumerStatefulWidget {
  const GrammarPickerScreen({super.key, this.vocabSummary});

  final VocabStageResult? vocabSummary;

  @override
  ConsumerState<GrammarPickerScreen> createState() => _GrammarPickerScreenState();
}

class _GrammarPickerScreenState extends ConsumerState<GrammarPickerScreen> {
  _PickerMode _mode = _PickerMode.auto;
  bool _isPlanning = false;
  String _planningLabel = "Picking today's focus…";
  String? _focusNote;
  GrammarLesson? _chosenLesson;
  GrammarTopic? _chosenTopic;
  String? _generationFailed;
  final List<String> _debugLog = [];
  final ScrollController _debugScrollController = ScrollController();

  GrammarPack? get _pack => ContentService.shared.grammar();

  List<({String id, String title})> get _candidates {
    final lessons = _pack?.lessons.map((l) => (id: l.id, title: l.title)).toList() ?? <({String id, String title})>[];
    final topics = _pack?.topics.map((t) => (id: t.id, title: t.title)).toList() ?? <({String id, String title})>[];
    return [...lessons, ...topics];
  }

  @override
  void dispose() {
    _debugScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Passeport.parchmentDim,
      appBar: AppBar(
        title: Text('Grammar', style: Passeport.display(18)),
        backgroundColor: Passeport.parchmentDim,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
                child: SegmentedButton<_PickerMode>(
                  segments: const [
                    ButtonSegment(value: _PickerMode.auto, label: Text('Auto')),
                    ButtonSegment(value: _PickerMode.manual, label: Text('Choose')),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (s) => setState(() => _mode = s.first),
                ),
              ),
              Expanded(child: _mode == _PickerMode.auto ? _autoBody() : _manualBody()),
            ],
          ),
          if (_isPlanning || _generationFailed != null)
            Container(
              color: Colors.black.withValues(alpha: 0.15),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(20),
                  constraints: const BoxConstraints(maxWidth: 320),
                  decoration: BoxDecoration(color: Passeport.card, borderRadius: BorderRadius.circular(14)),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_generationFailed != null) ...[
                        const Icon(Icons.warning_amber_rounded, size: 24, color: Passeport.maroon),
                        const SizedBox(height: 8),
                        Text("Couldn't build today's practice", style: Passeport.body(14, weight: FontWeight.w500)),
                        const SizedBox(height: 6),
                        Text(_generationFailed!, style: Passeport.mono(10.5).copyWith(color: Passeport.slateDim), textAlign: TextAlign.center),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: 200,
                          child: PasseportPrimaryButton(label: 'Retry', onPressed: _generateCardsAndStart),
                        ),
                      ] else ...[
                        PSProgressIndicator(),
                        const SizedBox(height: 10),
                        Text(_planningLabel, style: Passeport.mono(11).copyWith(color: Passeport.slateDim)),
                      ],
                      if (_debugLog.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        _debugPanel(),
                      ],
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // MARK: - Practice card generation (once, before the session starts — never live)

  static const _generationTimeout = Duration(seconds: 30);

  /// Runs once after a tense/topic is chosen (either mode) — builds the actual sentence-card
  /// deck AgentLedGrammarScreen teaches from, informed by the vocab words + transcript from the
  /// Vocab stage that just happened. No silent fallback to old static content on failure/timeout
  /// — a failure stops here with the real error visible and a Retry button.
  Future<void> _generateCardsAndStart() async {
    final title = _chosenLesson?.title ?? _chosenTopic?.title ?? 'Grammar';
    final usage = _chosenLesson?.usage ?? _chosenTopic?.sections.map((s) => '${s.heading}: ${s.body}').toList() ?? <String>[];
    final vocabWords = widget.vocabSummary?.wordsCovered.map((e) => e.fr).toList() ?? <String>[];

    setState(() {
      _isPlanning = true;
      _generationFailed = null;
      _debugLog.clear();
      _planningLabel = 'Building today\'s practice…';
    });
    _logDebug('→ tense: "$title", vocab words: ${vocabWords.isEmpty ? "none" : vocabWords.join(", ")}');

    final transcript = SessionRecorder.recentVocabTranscript(ref.read(storageServiceProvider));
    _logDebug(transcript.isEmpty ? '→ no recent vocab transcript found' : '→ vocab transcript: ${transcript.length} chars');
    _logDebug('→ sending request to LLM…');

    List<GrammarPracticeCard>? cards;
    String? failureMessage;
    var timedOut = false;
    try {
      cards = await LessonAgentService.shared
          .generateGrammarPracticeCards(tenseTitle: title, tenseUsage: usage, vocabWords: vocabWords, recentVocabTranscript: transcript)
          .timeout(_generationTimeout);
    } on TimeoutException {
      timedOut = true;
    } catch (e) {
      failureMessage = '$e';
    }

    if (!mounted) return;
    setState(() => _isPlanning = false);

    if (cards != null) {
      _logDebug('→ received ${cards.length} card(s)');
      _openSession(cards, title);
    } else if (timedOut) {
      _logDebug('→ TIMED OUT after ${_generationTimeout.inSeconds}s — no response from the LLM');
      setState(() => _generationFailed =
          'The request timed out after ${_generationTimeout.inSeconds}s with no response. Check your connection and the OpenRouter key in Settings, then retry.');
    } else {
      final rawSnippet = LessonAgentService.shared.lastRawResponse;
      if (rawSnippet.isNotEmpty) {
        _logDebug('→ RAW LLM response: ${rawSnippet.substring(0, rawSnippet.length > 300 ? 300 : rawSnippet.length)}');
      }
      _logDebug('→ ERROR: $failureMessage');
      setState(() => _generationFailed = failureMessage ?? 'Unknown error');
    }
  }

  Future<void> _openSession(List<GrammarPracticeCard> cards, String tenseTitle) async {
    // Await the agent screen's typed outcome and forward it up as this
    // picker's own result — one navigator layer, one pop, no callbacks.
    final outcome = await AppRouter.push<StageOutcome<GrammarStageResult>>(
      context,
      (_) => AgentLedGrammarScreen(
        cards: cards,
        tenseTitle: tenseTitle,
        focusNote: _focusNote,
        vocabSummary: widget.vocabSummary,
      ),
      fullscreenDialog: true,
    );
    if (outcome != null && mounted) Navigator.of(context).pop(outcome);
  }

  void _logDebug(String message) {
    final time = DateFormat.Hms().format(DateTime.now());
    setState(() => _debugLog.add('[$time] $message'));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_debugScrollController.hasClients) return;
      _debugScrollController.animateTo(
        _debugScrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  Widget _debugPanel() {
    return SizedBox(
      height: 90,
      child: ListView.builder(
        controller: _debugScrollController,
        itemCount: _debugLog.length,
        itemBuilder: (context, i) => Text(_debugLog[i], style: Passeport.mono(9).copyWith(color: Passeport.slateDim)),
      ),
    );
  }

  // MARK: - Auto mode

  Widget _autoBody() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      child: Column(
        children: [
          const Spacer(),
          PasseportCard(
            padding: 24,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.auto_awesome, size: 30, color: Passeport.brass),
                const SizedBox(height: 10),
                Text("Let Marie pick today's focus", style: Passeport.display(19, weight: FontWeight.w500)),
                const SizedBox(height: 8),
                Text(
                  "Based on what you've been mixing up recently, or the next tense in the curriculum if nothing stands out.",
                  style: Passeport.body(13).copyWith(color: Passeport.slateDim),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const Spacer(),
          PasseportPrimaryButton(label: 'Start', onPressed: _candidates.isEmpty ? null : _beginAutoSession),
        ],
      ),
    );
  }

  Future<void> _beginAutoSession() async {
    if (_candidates.isEmpty) return;
    setState(() {
      _isPlanning = true;
      _planningLabel = "Picking today's focus…";
    });
    final store = ref.read(learningStoreProvider);
    final mistakeTags = store.topMistakeTags();
    final diary = store.recentDiaryEntries();

    GrammarSessionPlan? plan;
    try {
      plan = await LessonAgentService.shared
          .planGrammarSession(
            candidates: _candidates,
            mistakeTags: mistakeTags.map((m) => (tag: m.tag, description: m.description, count: m.count)).toList(),
            recentDiary: diary.map((d) => d.summary).toList(),
          )
          .timeout(const Duration(seconds: 14));
    } catch (_) {
      plan = null;
    }

    if (!mounted) return;
    final chosenId = plan?.chosenId ?? _incompleteFirst()?.id ?? (_candidates.isNotEmpty ? _candidates.first.id : null);
    setState(() {
      _focusNote = (plan?.focusNote.isNotEmpty ?? false) ? plan!.focusNote : null;
    });
    _selectById(chosenId);
    await _generateCardsAndStart();
  }

  /// Fallback when the planner call fails/times out: pick the next incomplete lesson/topic in
  /// curriculum order rather than always restarting from the first tense.
  ({String id, String title})? _incompleteFirst() {
    final store = ref.read(learningStoreProvider);
    final sortedLessons = [...(_pack?.lessons ?? <GrammarLesson>[])]..sort((a, b) => a.order.compareTo(b.order));
    for (final lesson in sortedLessons) {
      if (store.lessonStatus(lesson.id).status != 'completed') return (id: lesson.id, title: lesson.title);
    }
    for (final topic in _pack?.topics ?? <GrammarTopic>[]) {
      if (store.lessonStatus(topic.id).status != 'completed') return (id: topic.id, title: topic.title);
    }
    return _candidates.isNotEmpty ? _candidates.first : null;
  }

  // MARK: - Manual mode

  Widget _manualBody() {
    final lessons = _pack?.lessons ?? [];
    final topics = _pack?.topics ?? [];
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      children: [
        if (lessons.isNotEmpty) ...[
          const KickerText('Tenses', color: Passeport.slateDim),
          const SizedBox(height: 8),
          for (final lesson in lessons)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _pickRow(title: lesson.title, subtitle: lesson.subtitle, id: lesson.id),
            ),
        ],
        if (topics.isNotEmpty) ...[
          const SizedBox(height: 8),
          const KickerText('Topics', color: Passeport.slateDim),
          const SizedBox(height: 8),
          for (final topic in topics)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _pickRow(title: topic.title, subtitle: null, id: topic.id),
            ),
        ],
      ],
    );
  }

  Widget _pickRow({required String title, String? subtitle, required String id}) {
    final isDone = ref.read(learningStoreProvider).lessonStatus(id).status == 'completed';
    return GestureDetector(
      onTap: () {
        _selectById(id);
        _focusNote = null;
        _generateCardsAndStart();
      },
      child: PasseportCard(
        padding: 14,
        child: Row(
          children: [
            Icon(isDone ? Icons.check_circle : Icons.circle_outlined, color: isDone ? Passeport.brass : Passeport.slate, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Passeport.body(14, weight: FontWeight.w500)),
                  if (subtitle != null) Text(subtitle, style: Passeport.mono(10.5).copyWith(color: Passeport.slateDim)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 16, color: Passeport.slate),
          ],
        ),
      ),
    );
  }

  void _selectById(String? id) {
    if (id == null) return;
    final lesson = _pack?.lessons.where((l) => l.id == id).firstOrNull;
    if (lesson != null) {
      setState(() {
        _chosenLesson = lesson;
        _chosenTopic = null;
      });
      return;
    }
    final topic = _pack?.topics.where((t) => t.id == id).firstOrNull;
    if (topic != null) {
      setState(() {
        _chosenTopic = topic;
        _chosenLesson = null;
      });
    }
  }
}
