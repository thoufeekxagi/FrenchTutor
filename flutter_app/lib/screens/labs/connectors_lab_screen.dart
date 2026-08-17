import 'dart:math';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../design/tokens.dart';
import '../../models/content_models.dart';
import '../../prompts/live_prompts.dart';
import '../../providers/database_provider.dart';
import '../../models/tutor_persona.dart';
import '../../services/gemini_live_audio_service.dart';
import '../../services/inline_call_controller.dart';
import '../../services/lesson_speech_service.dart';
import '../../widgets/passeport_card.dart';
import '../../widgets/kicker_text.dart';
import '../../widgets/passeport_primary_button.dart';
import '../../services/session_recorder.dart';
import '../../widgets/inline_call_bar.dart';
import '../../widgets/tts_play_button.dart';
import '../../widgets/web/web_constrained_view.dart';

class ConnectorsLabScreen extends ConsumerStatefulWidget {
  const ConnectorsLabScreen({super.key, this.autoStart = false});

  final bool autoStart;

  @override
  ConsumerState<ConnectorsLabScreen> createState() =>
      _ConnectorsLabScreenState();
}

class _ConnectorsLabScreenState extends ConsumerState<ConnectorsLabScreen>
    with WidgetsBindingObserver {
  /// Marie's live-call button, inline in the AppBar — same
  /// InlineCallController every other reading/exercise screen uses.
  late final InlineCallController _call;

  /// Logs the inline call's transcript so asking Marie about connectors
  /// here contributes to an auto-generated review note, same as every
  /// other screen with a live call — this screen previously had no
  /// SessionRecorder at all, so that conversation went entirely unlogged.
  late final SessionRecorder _recorder;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _recorder = SessionRecorder(
      storage: ref.read(storageServiceProvider),
      stage: 'grammar',
      topic: 'Connectors',
    );
    _call = InlineCallController(
      sessionType: LiveSessionType.labAssistant,
      lessonContext: () => ref.read(contentServiceProvider).connectorsContext(),
      learningStoreForProfile: ref.read(learningStoreProvider),
      onChanged: () {
        if (mounted) setState(() {});
      },
      onUserTranscript: (text) => _recorder.logUser(text),
      onTutorTranscript: (text) => _recorder.logTutor(text),
    );
    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final pack = ref.read(contentServiceProvider).connectors();
        if (mounted && pack != null) _showQuiz(pack.connectors);
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _call.handleAppLifecycle(state);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _call.dispose();
    _recorder.finish(summary: 'Reviewed connectors.');
    LessonSpeechService.shared.deactivate();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pack = ref.watch(contentServiceProvider).connectors();

    return Scaffold(
      backgroundColor: DesignTokens.canvasDim,
      appBar: AppBar(
        title: Text('Connectors', style: DesignTokens.display(20)),
        backgroundColor: DesignTokens.canvasDim,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [InlineCallActions(controller: _call)],
      ),
      body: WebConstrainedView(
        maxWidth: 1080,
        child: Column(
          children: [
            if (_call.isLive || _call.error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
                child: InlineCallStatusCard(
                  controller: _call,
                  listeningLabel: 'Listening. Ask about connectors anytime.',
                ),
              ),
            Expanded(
              child: pack == null
                  ? Center(
                      child: Text(
                        'Connectors content unavailable.',
                        style: DesignTokens.body(
                          13,
                        ).copyWith(color: DesignTokens.mutedDim),
                      ),
                    )
                  : _buildContent(pack),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(ConnectorsPack pack) {
    final categories = _orderedCategories(pack.connectors);

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      children: [
        Text(
          pack.tip,
          style: DesignTokens.body(12.5).copyWith(color: DesignTokens.mutedDim),
        ),
        const SizedBox(height: 16),
        ModernPrimaryButton(
          label: 'Take the 10-question quiz',
          onPressed: () => _showQuiz(pack.connectors),
        ),
        const SizedBox(height: 16),
        for (final category in categories) ...[
          KickerText(category, color: DesignTokens.mutedDim),
          const SizedBox(height: 8),
          ModernCard(
            padding: 10,
            child: Column(
              children: _buildCategoryRows(
                pack.connectors.where((c) => c.category == category).toList(),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  List<String> _orderedCategories(List<Connector> connectors) {
    final seen = <String>[];
    for (final c in connectors) {
      if (!seen.contains(c.category)) seen.add(c.category);
    }
    return seen;
  }

  List<Widget> _buildCategoryRows(List<Connector> items) {
    final widgets = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      widgets.add(_connectorRow(items[i]));
      if (i < items.length - 1) {
        widgets.add(Divider(color: DesignTokens.hairline, height: 1));
      }
    }
    return widgets;
  }

  Widget _connectorRow(Connector connector) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      connector.fr,
                      style: DesignTokens.body(13.5, weight: FontWeight.w500),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      connector.en,
                      style: DesignTokens.mono(
                        10.5,
                      ).copyWith(color: DesignTokens.mutedDim),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  connector.example.fr,
                  style: DesignTokens.body(11.5).copyWith(
                    color: DesignTokens.mutedDim,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          TtsPlayButton(
            text: connector.example.fr,
            size: DesignTokens.minTapTarget,
            iconSize: 20,
            color: DesignTokens.info,
            audioResolver: () => GeminiLiveAudioService.shared.resolve(
              text: connector.example.fr,
              contentItemId: 'connectors:${connector.id}',
              voiceName: ActiveTutor.current.voiceName,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showQuiz(List<Connector> connectors) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => _ConnectorsQuizView(
          connectors: connectors,
          learningStore: ref.read(learningStoreProvider),
        ),
      ),
    );
    if (widget.autoStart && mounted) {
      Navigator.of(context).pop(result == true);
    }
  }
}

// ---------------------------------------------------------------------------
// Connectors Quiz
// ---------------------------------------------------------------------------

class _QuizQuestion {
  final Connector connector;
  final List<String> choices;
  _QuizQuestion({required this.connector, required this.choices});
}

class _ConnectorsQuizView extends StatefulWidget {
  const _ConnectorsQuizView({
    required this.connectors,
    required this.learningStore,
  });

  final List<Connector> connectors;
  final dynamic learningStore; // LearningStore

  @override
  State<_ConnectorsQuizView> createState() => _ConnectorsQuizViewState();
}

class _ConnectorsQuizViewState extends State<_ConnectorsQuizView> {
  late List<_QuizQuestion> _questions;
  int _index = 0;
  int _correctCount = 0;
  String? _selected;
  late List<String?> _answers;

  @override
  void initState() {
    super.initState();
    _buildQuestions();
  }

  void _buildQuestions() {
    final rng = Random();
    final pool = List<Connector>.from(widget.connectors)..shuffle(rng);
    final picked = pool.take(10).toList();
    _questions = picked.map((connector) {
      final distractors =
          widget.connectors.where((c) => c.id != connector.id).toList()
            ..shuffle(rng);
      final choices = distractors.take(2).map((c) => c.fr).toList()
        ..add(connector.fr)
        ..shuffle(rng);
      return _QuizQuestion(connector: connector, choices: choices);
    }).toList();
    _answers = List<String?>.filled(_questions.length, null);
  }

  void _answer(String choice) {
    if (_selected != null) return;
    setState(() {
      _selected = choice;
      _answers[_index] = choice;
      if (choice == _questions[_index].connector.fr) {
        _correctCount++;
      }
    });
  }

  void _next() {
    setState(() {
      _index++;
      _selected = null;
      if (_index == _questions.length) {
        _saveResult();
      }
    });
  }

  void _saveResult() {
    final score = _questions.isEmpty ? 0.0 : _correctCount / _questions.length;
    widget.learningStore.setLessonStatus(
      'connectors_quiz',
      score >= 0.7 ? 'completed' : 'in_progress',
      score: score,
    );
  }

  Color _choiceColor(String choice, _QuizQuestion q) {
    if (_selected != null && choice == q.connector.fr) {
      return DesignTokens.success;
    }
    if (_selected != null && choice == _selected) return DesignTokens.danger;
    return DesignTokens.muted;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: DesignTokens.canvasDim,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Handle bar
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: DesignTokens.muted,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            child: Row(
              children: [
                Text('Connectors quiz', style: DesignTokens.display(18)),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'Close',
                    style: DesignTokens.body(
                      14,
                    ).copyWith(color: DesignTokens.primary),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Body
          Expanded(
            child: _index < _questions.length ? _quizCard() : _resultCard(),
          ),
        ],
      ),
    );
  }

  Widget _quizCard() {
    final q = _questions[_index];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          Center(
            child: Text(
              '${_index + 1} / ${_questions.length}',
              style: DesignTokens.mono(
                11,
              ).copyWith(color: DesignTokens.mutedDim),
            ),
          ),
          const SizedBox(height: 18),
          ModernCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Which connector means:',
                  style: DesignTokens.body(
                    12.5,
                  ).copyWith(color: DesignTokens.mutedDim),
                ),
                const SizedBox(height: 6),
                Text(
                  q.connector.en,
                  style: DesignTokens.display(18, weight: FontWeight.w500),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          ...q.choices.map(
            (choice) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _selected == null ? () => _answer(choice) : null,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _selected == null
                        ? DesignTokens.text
                        : _choiceColor(choice, q),
                    backgroundColor: DesignTokens.surface,
                    side: BorderSide(color: DesignTokens.hairline),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    textStyle: DesignTokens.body(13.5, weight: FontWeight.w500),
                  ),
                  child: Text(choice),
                ),
              ),
            ),
          ),
          if (_selected != null) ...[
            const SizedBox(height: 8),
            ModernPrimaryButton(
              label: _index + 1 < _questions.length ? 'Next' : 'See results',
              onPressed: _next,
            ),
          ],
        ],
      ),
    );
  }

  Widget _resultCard() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 24, 18, 28),
      children: [
        Icon(
          CupertinoIcons.checkmark_seal_fill,
          size: 36,
          color: DesignTokens.info,
        ),
        const SizedBox(height: 14),
        Center(
          child: Text(
            '$_correctCount / ${_questions.length}',
            style: DesignTokens.display(24, weight: FontWeight.w500),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            'Your connector answers',
            style: DesignTokens.body(13).copyWith(color: DesignTokens.mutedDim),
          ),
        ),
        const SizedBox(height: 18),
        for (var i = 0; i < _questions.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _resultRow(i),
          ),
        const SizedBox(height: 12),
        Text(
          'Great connectors score points on TEF writing and speaking tasks.',
          style: DesignTokens.body(13).copyWith(color: DesignTokens.mutedDim),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 42),
          child: ModernPrimaryButton(
            label: 'Done',
            onPressed: () => Navigator.pop(context, true),
          ),
        ),
      ],
    );
  }

  Widget _resultRow(int index) {
    final question = _questions[index];
    final answer = _answers[index];
    final isCorrect = answer == question.connector.fr;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isCorrect ? DesignTokens.successSoft : DesignTokens.dangerSoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isCorrect ? DesignTokens.success : DesignTokens.danger,
          width: 0.8,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isCorrect
                ? CupertinoIcons.checkmark_circle_fill
                : CupertinoIcons.xmark_circle_fill,
            size: 20,
            color: isCorrect ? DesignTokens.success : DesignTokens.danger,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  question.connector.en,
                  style: DesignTokens.body(12, weight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  isCorrect
                      ? 'Correct: ${question.connector.fr}'
                      : 'You chose: ${answer ?? 'No answer'}',
                  style: DesignTokens.body(11.5).copyWith(
                    color: isCorrect
                        ? DesignTokens.success
                        : DesignTokens.danger,
                  ),
                ),
                if (!isCorrect) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Correct answer: ${question.connector.fr}',
                    style: DesignTokens.body(
                      11.5,
                    ).copyWith(color: DesignTokens.mutedDim),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
