import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/api_keys.dart';
import '../../design/app_router.dart';
import '../../design/tokens.dart';
import '../../flow/stage_outcome.dart';
import '../../providers/database_provider.dart';
import '../../services/ai_session_gate.dart';
import '../../services/lesson_agent_service.dart';
import '../../widgets/adaptive/adaptive.dart';
import '../../widgets/primary_action_button.dart';
import '../session/session_screen.dart';

enum _MockStep { overview, reading, taskOne, taskTwo, scoring, results }

class _ReadingQuestion {
  const _ReadingQuestion({
    required this.prompt,
    required this.options,
    required this.answer,
  });

  final String prompt;
  final List<String> options;
  final int answer;
}

class SpeakingMockResult {
  const SpeakingMockResult({required this.score, required this.completed});

  final double score;
  final bool completed;
}

class MocksScreen extends ConsumerStatefulWidget {
  const MocksScreen({
    super.key,
    this.examName,
    this.levelBand = 'B1',
    this.includeReadingWarmup = true,
  });

  /// When supplied, this screen is the scored speaking surface launched from
  /// Exam readiness. With no exam name it remains the standalone mock.
  final String? examName;
  final String levelBand;
  final bool includeReadingWarmup;

  @override
  ConsumerState<MocksScreen> createState() => _MocksScreenState();
}

class _MocksScreenState extends ConsumerState<MocksScreen> {
  static const _passage = '''
La médiathèque du quartier sera exceptionnellement fermée mardi matin pour des travaux. Elle ouvrira à 14 h et restera ouverte jusqu'à 20 h. Les documents qui doivent être rendus mardi peuvent être déposés dans la boîte extérieure. L'atelier de conversation française prévu à 18 h aura lieu normalement dans la salle du premier étage.
''';
  static const _questions = [
    _ReadingQuestion(
      prompt: 'Quand la médiathèque ouvrira-t-elle mardi ?',
      options: ['À 8 h', 'À 14 h', 'À 18 h', 'À 20 h'],
      answer: 1,
    ),
    _ReadingQuestion(
      prompt: 'Où peut-on rendre les documents le matin ?',
      options: [
        'Au premier étage',
        'À la mairie',
        'Dans la boîte extérieure',
        'À l’atelier',
      ],
      answer: 2,
    ),
    _ReadingQuestion(
      prompt: 'Quelle activité est maintenue ?',
      options: [
        'Les travaux',
        'L’atelier de conversation',
        'La visite du quartier',
        'Le cours du matin',
      ],
      answer: 1,
    ),
  ];

  _MockStep _step = _MockStep.overview;
  int _questionIndex = 0;
  final List<int> _answers = [];
  String _monologueTranscript = '';
  String _interactionTranscript = '';
  SpeakingMockFeedback? _feedback;
  String _error = '';

  bool get _isExamReadiness => widget.examName != null;

  String get _monologuePrompt {
    final band = widget.levelBand.toUpperCase();
    if (widget.examName?.startsWith('TEF') == true) {
      return band == 'A1' || band == 'A2'
          ? 'Présentez un lieu que vous aimez. Dites où il est et ce que vous y faites.'
          : 'Parlez d’un lieu de votre ville que vous recommandez. Expliquez ce qu’on peut y faire et pourquoi vous l’aimez.';
    }
    return band == 'A1' || band == 'A2'
        ? 'Présentez-vous et dites où vous habitez et ce que vous aimez faire.'
        : 'Présentez un projet ou une activité importante pour vous. Donnez des raisons et un exemple précis.';
  }

  String get _interactionPrompt {
    final band = widget.levelBand.toUpperCase();
    if (widget.examName?.startsWith('TEF') == true) {
      return band == 'A1' || band == 'A2'
          ? 'Vous téléphonez à un centre de formation. Demandez l’heure et le prix d’un cours de français. L’examinateur joue l’employé.'
          : 'Vous téléphonez à un centre de formation pour demander des renseignements sur un cours de français du soir. L’examinateur joue le rôle de l’employé. Posez des questions sur les horaires, le prix et le niveau requis.';
    }
    return band == 'A1' || band == 'A2'
        ? 'Vous cherchez une activité en français. Posez des questions simples sur le lieu, l’heure et le prix.'
        : 'Vous voulez obtenir des renseignements sur une activité ou un service. Posez des questions précises, réagissez aux réponses et demandez une information supplémentaire.';
  }

  int get _readingScore {
    var score = 0;
    for (var i = 0; i < _answers.length && i < _questions.length; i++) {
      if (_answers[i] == _questions[i].answer) score++;
    }
    return score;
  }

  void _answer(int option) {
    setState(() {
      _answers.add(option);
      if (_questionIndex < _questions.length - 1) {
        _questionIndex++;
      } else {
        _step = _MockStep.taskOne;
      }
    });
  }

  Future<void> _runTask({required bool interaction}) async {
    if (!await ensureAiSessionQuota(
          context,
          ref.read(pilotAccessServiceProvider),
        ) ||
        !mounted) {
      return;
    }
    final stage = interaction
        ? 'mock_speaking_interaction'
        : 'mock_speaking_monologue';
    final languageRule = widget.levelBand == 'A1' || widget.levelBand == 'A2'
        ? 'A1/A2 GUIDED TRAINING: use short French and one brief English clarification only if the learner is clearly blocked; never give an answer.'
        : 'B1/B2 ASSESSMENT: French only. Never translate, coach, correct, or suggest an answer during the timed task.';
    final examContext = interaction
        ? 'INTERACTION TASK\n$languageRule\nSCENARIO: $_interactionPrompt\nYou are the centre employee. Open in French by asking how you can help. Stay in character and make the learner ask for the required information.'
        : 'MONOLOGUE TASK\n$languageRule\nPROMPT: $_monologuePrompt\nState this exact French prompt once, say “Commencez maintenant”, then remain silent.';
    final result = await AppRouter.push<SpeakingResult>(
      context,
      (_) => SessionScreen(
        apiKey: ApiKeys.geminiKey,
        lessonContext: examContext,
        stage: stage,
        examMode: true,
        durationLimitSeconds: interaction ? 180 : 60,
        kickoffMessage:
            '(App instruction, not the learner: begin the assessed task now. Follow the exam role and LESSON CONTEXT exactly. Do not greet, explain, or coach.)',
      ),
      fullscreenDialog: true,
    );
    if (!mounted || result == null) return;
    final storage = ref.read(storageServiceProvider);
    final session = storage.mostRecentSession(stage: stage);
    final transcript = session == null
        ? ''
        : storage
              .getSessionMessages(sessionId: session.id)
              .where((message) => message.isUser)
              .map((message) => message.content)
              .join(' ')
              .trim();
    setState(() {
      if (interaction) {
        _interactionTranscript = transcript;
        _step = _MockStep.scoring;
      } else {
        _monologueTranscript = transcript;
        _step = _MockStep.taskTwo;
      }
    });
    if (interaction) await _score();
  }

  Future<void> _score() async {
    setState(() {
      _step = _MockStep.scoring;
      _error = '';
    });
    try {
      final feedback = await ref
          .read(lessonAgentServiceProvider)
          .gradeSpeakingMock(
            monologuePrompt: _monologuePrompt,
            monologueTranscript: _monologueTranscript,
            interactionPrompt: _interactionPrompt,
            interactionTranscript: _interactionTranscript,
            examName: widget.examName ?? 'TEF / TCF Canada',
            levelBand: widget.levelBand,
          );
      if (!mounted) return;
      ref
          .read(learningStoreProvider)
          .setLessonStatus(
            'mock_speaking',
            'completed',
            score: feedback.overallScore,
          );
      setState(() {
        _feedback = feedback;
        _step = _MockStep.results;
      });
    } on AgentError catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _error = 'Scoring failed. Your recordings are saved; try again.',
      );
    }
  }

  void _restart() {
    setState(() {
      _step = _MockStep.overview;
      _questionIndex = 0;
      _answers.clear();
      _monologueTranscript = '';
      _interactionTranscript = '';
      _feedback = null;
      _error = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DesignTokens.canvas,
      appBar: AppBar(
        title: Text('Speaking mock', style: DesignTokens.display(20)),
        backgroundColor: DesignTokens.canvas,
        foregroundColor: DesignTokens.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: SafeArea(
        top: false,
        child: PSContentColumn(
          child: AnimatedSwitcher(
            duration: DesignTokens.durationMedium,
            child: KeyedSubtree(
              key: ValueKey(_step),
              child: switch (_step) {
                _MockStep.overview => _overview(),
                _MockStep.reading => _reading(),
                _MockStep.taskOne => _taskReady(interaction: false),
                _MockStep.taskTwo => _taskReady(interaction: true),
                _MockStep.scoring => _scoring(),
                _MockStep.results => _results(),
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _page(List<Widget> children) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        DesignTokens.screenMargin,
        DesignTokens.space4,
        DesignTokens.screenMargin,
        40,
      ),
      children: children,
    );
  }

  Widget _overview() {
    return _page([
      _eyebrow(widget.examName ?? 'TEF / TCF CANADA'),
      const SizedBox(height: DesignTokens.space2),
      Text(
        'Measure the French you can produce',
        style: DesignTokens.display(28),
      ),
      const SizedBox(height: DesignTokens.space3),
      Text(
        _isExamReadiness
            ? '${widget.examName} speaking practice at ${widget.levelBand}. Two timed tasks are scored after you finish with feedback on completion, fluency, grammar, and vocabulary.'
            : 'A short reading warm-up followed by two timed speaking tasks. There is no coaching during the assessment; feedback comes after you finish.',
        style: DesignTokens.body(
          16,
        ).copyWith(color: DesignTokens.mutedDim, height: 1.5),
      ),
      const SizedBox(height: 28),
      if (widget.includeReadingWarmup)
        _stageRow(
          CupertinoIcons.book,
          'Reading warm-up',
          '3 questions · untimed',
        ),
      _stageRow(CupertinoIcons.mic, 'Task 1 · Monologue', 'Speak for 1 minute'),
      _stageRow(
        CupertinoIcons.person_2,
        'Task 2 · Interaction',
        'Role-play for 3 minutes',
      ),
      const SizedBox(height: 28),
      Container(
        padding: const EdgeInsets.all(DesignTokens.space4),
        decoration: BoxDecoration(
          color: DesignTokens.infoSoft,
          borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
        ),
        child: Text(
          'Scored after both tasks: completion, fluency, grammar, and vocabulary, with a conservative CLB estimate.',
          style: DesignTokens.body(14).copyWith(height: 1.45),
        ),
      ),
      const SizedBox(height: 32),
      PrimaryActionButton(
        label: 'Begin mock',
        icon: CupertinoIcons.play_fill,
        onPressed: () => setState(
          () => _step = widget.includeReadingWarmup
              ? _MockStep.reading
              : _MockStep.taskOne,
        ),
      ),
    ]);
  }

  Widget _reading() {
    final question = _questions[_questionIndex];
    return _page([
      _eyebrow('READING · ${_questionIndex + 1} OF ${_questions.length}'),
      const SizedBox(height: DesignTokens.space3),
      Text('Read for meaning', style: DesignTokens.display(27)),
      const SizedBox(height: DesignTokens.space4),
      Container(
        padding: const EdgeInsets.all(DesignTokens.space5),
        decoration: BoxDecoration(
          color: DesignTokens.surface,
          borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
          border: Border.all(color: DesignTokens.hairline),
        ),
        child: Text(
          _passage.trim(),
          style: DesignTokens.body(17).copyWith(height: 1.6),
        ),
      ),
      const SizedBox(height: DesignTokens.space5),
      Text(
        question.prompt,
        style: DesignTokens.body(17, weight: FontWeight.w700),
      ),
      const SizedBox(height: DesignTokens.space4),
      for (var i = 0; i < question.options.length; i++)
        _option(question.options[i], () => _answer(i)),
    ]);
  }

  Widget _taskReady({required bool interaction}) {
    final taskNumber = interaction ? 2 : 1;
    final prompt = interaction ? _interactionPrompt : _monologuePrompt;
    return _page([
      _eyebrow('SPEAKING · TASK $taskNumber OF 2'),
      const SizedBox(height: DesignTokens.space2),
      Text(
        interaction ? 'Handle a real interaction' : 'Develop your answer',
        style: DesignTokens.display(27),
      ),
      const SizedBox(height: DesignTokens.space3),
      Text(
        interaction
            ? 'The agent plays the centre employee and speaks first in French. Ask for the information in the prompt.'
            : 'The examiner reads the prompt once, then stays silent. Keep speaking until the timer ends.',
        style: DesignTokens.body(
          15,
        ).copyWith(color: DesignTokens.mutedDim, height: 1.45),
      ),
      const SizedBox(height: DesignTokens.space5),
      Container(
        padding: const EdgeInsets.all(DesignTokens.space5),
        decoration: BoxDecoration(
          color: DesignTokens.infoSoft,
          borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
        ),
        child: Text(
          prompt,
          style: DesignTokens.body(
            17,
            weight: FontWeight.w600,
          ).copyWith(height: 1.5),
        ),
      ),
      const SizedBox(height: DesignTokens.space4),
      Row(
        children: [
          Icon(CupertinoIcons.timer, color: DesignTokens.mutedDim, size: 20),
          const SizedBox(width: DesignTokens.space2),
          Text(
            interaction ? '3:00 · no coaching' : '1:00 · no coaching',
            style: DesignTokens.body(
              14,
              weight: FontWeight.w600,
            ).copyWith(color: DesignTokens.mutedDim),
          ),
        ],
      ),
      const SizedBox(height: 32),
      PrimaryActionButton(
        label: 'Start task $taskNumber',
        icon: CupertinoIcons.mic_fill,
        onPressed: () => _runTask(interaction: interaction),
      ),
    ]);
  }

  Widget _scoring() {
    return _page([
      const SizedBox(height: 80),
      const Center(child: PSProgressIndicator()),
      const SizedBox(height: DesignTokens.space5),
      Text(
        'Assessing your speaking',
        textAlign: TextAlign.center,
        style: DesignTokens.display(25),
      ),
      const SizedBox(height: DesignTokens.space2),
      Text(
        'Comparing both transcripts with the speaking rubric.',
        textAlign: TextAlign.center,
        style: DesignTokens.body(15).copyWith(color: DesignTokens.mutedDim),
      ),
      if (_error.isNotEmpty) ...[
        const SizedBox(height: DesignTokens.space5),
        Text(
          _error,
          textAlign: TextAlign.center,
          style: DesignTokens.body(14).copyWith(color: DesignTokens.danger),
        ),
        const SizedBox(height: DesignTokens.space4),
        PrimaryActionButton(label: 'Retry scoring', onPressed: _score),
      ],
    ]);
  }

  Widget _results() {
    final feedback = _feedback!;
    return _page([
      _eyebrow('ASSESSMENT COMPLETE'),
      const SizedBox(height: DesignTokens.space2),
      Text('Your speaking progress', style: DesignTokens.display(28)),
      const SizedBox(height: DesignTokens.space5),
      Container(
        padding: const EdgeInsets.all(DesignTokens.space5),
        decoration: BoxDecoration(
          color: DesignTokens.infoSoft,
          borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Estimated level',
                    style: DesignTokens.body(
                      13,
                    ).copyWith(color: DesignTokens.mutedDim),
                  ),
                  const SizedBox(height: DesignTokens.space1),
                  Text(feedback.clbEstimate, style: DesignTokens.display(25)),
                ],
              ),
            ),
            Text(
              '${feedback.overallScore.toStringAsFixed(1)}/10',
              style: DesignTokens.mono(
                20,
                weight: FontWeight.w700,
              ).copyWith(color: DesignTokens.primary),
            ),
          ],
        ),
      ),
      const SizedBox(height: DesignTokens.space5),
      _scoreRow('Task completion', feedback.taskCompletion),
      _scoreRow('Fluency & coherence', feedback.fluency),
      _scoreRow('Grammar', feedback.grammar),
      _scoreRow('Vocabulary', feedback.vocabulary),
      const SizedBox(height: DesignTokens.space5),
      Text('What worked', style: DesignTokens.display(20)),
      const SizedBox(height: DesignTokens.space3),
      ...feedback.strengths.map(
        (item) => _feedbackRow(
          CupertinoIcons.check_mark_circled_solid,
          item,
          DesignTokens.success,
        ),
      ),
      const SizedBox(height: DesignTokens.space4),
      Text('Next practice', style: DesignTokens.display(20)),
      const SizedBox(height: DesignTokens.space3),
      ...feedback.nextSteps.map(
        (item) => _feedbackRow(
          CupertinoIcons.arrow_right_circle_fill,
          item,
          DesignTokens.info,
        ),
      ),
      const SizedBox(height: DesignTokens.space4),
      if (widget.includeReadingWarmup)
        Text(
          'Reading warm-up: $_readingScore/${_questions.length}',
          style: DesignTokens.body(
            14,
            weight: FontWeight.w600,
          ).copyWith(color: DesignTokens.mutedDim),
        ),
      const SizedBox(height: 28),
      PrimaryActionButton(
        label: _isExamReadiness ? 'Finish and save result' : 'Retake mock',
        onPressed: _isExamReadiness
            ? () => Navigator.of(context).pop(
                SpeakingMockResult(
                  score: feedback.overallScore,
                  completed: true,
                ),
              )
            : _restart,
      ),
    ]);
  }

  Widget _eyebrow(String text) {
    return Text(
      text,
      style: DesignTokens.body(
        11,
        weight: FontWeight.w800,
      ).copyWith(color: DesignTokens.info, letterSpacing: 0.8),
    );
  }

  Widget _stageRow(IconData icon, String title, String detail) {
    return Padding(
      padding: const EdgeInsets.only(bottom: DesignTokens.space4),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: DesignTokens.infoSoft,
              borderRadius: BorderRadius.circular(DesignTokens.radiusMedium),
            ),
            child: Icon(icon, color: DesignTokens.info, size: 21),
          ),
          const SizedBox(width: DesignTokens.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: DesignTokens.body(15, weight: FontWeight.w600),
                ),
                const SizedBox(height: DesignTokens.space1),
                Text(
                  detail,
                  style: DesignTokens.body(
                    13,
                  ).copyWith(color: DesignTokens.mutedDim),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _option(String text, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: DesignTokens.space3),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(
            minHeight: DesignTokens.minTapTarget,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: DesignTokens.space4,
            vertical: DesignTokens.space3,
          ),
          decoration: BoxDecoration(
            color: DesignTokens.surface,
            borderRadius: BorderRadius.circular(DesignTokens.radiusMedium),
            border: Border.all(color: DesignTokens.hairline),
          ),
          child: Text(text, style: DesignTokens.body(15)),
        ),
      ),
    );
  }

  Widget _scoreRow(String label, double score) {
    return Padding(
      padding: const EdgeInsets.only(bottom: DesignTokens.space3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: DesignTokens.body(15, weight: FontWeight.w600),
            ),
          ),
          Text(
            '${score.toStringAsFixed(1)}/10',
            style: DesignTokens.mono(14, weight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _feedbackRow(IconData icon, String text, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: DesignTokens.space3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: DesignTokens.space3),
          Expanded(
            child: Text(
              text,
              style: DesignTokens.body(14).copyWith(height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
