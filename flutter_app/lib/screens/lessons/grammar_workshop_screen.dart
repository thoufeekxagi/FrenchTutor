import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/generated_grammar_story_store.dart';
import '../../design/tokens.dart';
import '../../models/content_models.dart';
import '../../providers/database_provider.dart';
import '../../services/lesson_agent_service.dart';
import '../../services/lesson_speech_service.dart';
import '../../widgets/learning_card.dart';
import '../../widgets/lesson_stage_rail.dart';
import '../../widgets/primary_action_button.dart';
import '../../widgets/report_problem_button.dart';
import '../../widgets/tts_play_button.dart';
import '../../widgets/web/web_constrained_view.dart';

/// The result returned to a caller that needs to record grammar mastery.
class GrammarWorkshopResult {
  const GrammarWorkshopResult({required this.correct, required this.attempted});

  final int correct;
  final int attempted;
}

enum _GrammarWorkshopStep { rule, notice, choose, use, review }

/// A deliberate, card-by-card grammar lesson.
///
/// The generated payload is already frozen in [GeneratedGrammarStory], so this
/// screen never makes another model call just to move between teaching steps:
/// rule -> notice -> choose -> produce -> review. That keeps the experience
/// quick and makes reopening a saved lesson deterministic.
class GrammarWorkshopScreen extends ConsumerStatefulWidget {
  const GrammarWorkshopScreen({
    super.key,
    required this.story,
    this.showFinishButton = false,
  });

  final GeneratedGrammarStory story;
  final bool showFinishButton;

  @override
  ConsumerState<GrammarWorkshopScreen> createState() =>
      _GrammarWorkshopScreenState();
}

class _GrammarWorkshopScreenState extends ConsumerState<GrammarWorkshopScreen> {
  _GrammarWorkshopStep _step = _GrammarWorkshopStep.rule;
  int _storyIndex = 0;
  int _quizIndex = 0;
  final Map<int, int> _answers = {};
  final _transferController = TextEditingController();
  MicroWritingFeedback? _transferFeedback;
  bool _checkingTransfer = false;

  GrammarExplanation get _explanation => widget.story.explanation;
  List<ReadingSegment> get _segments => widget.story.passage.segments;
  List<MultipleChoiceQuestion> get _quiz => widget.story.quiz;
  MultipleChoiceQuestion? get _currentQuestion =>
      _quizIndex < _quiz.length ? _quiz[_quizIndex] : null;

  int get _correctAnswers => _answers.entries
      .where((entry) => entry.value == _quiz[entry.key].answerIndex)
      .length;

  int get _attemptedAnswers => _answers.length;

  @override
  void initState() {
    super.initState();
    // Grammar sentences use the same persistent TTS cache as reading and
    // listening. Warm them as soon as a generated lesson is opened so the
    // speaker is normally ready before the learner reaches the notice step.
    unawaited(_prewarmAudio());
  }

  Future<void> _prewarmAudio() {
    return LessonSpeechService.shared.prewarmNarration([
      for (var index = 0; index < _segments.length; index++)
        SpeechItem(
          text: _segments[index].fr,
          language: 'fr-FR',
          contentItemId: widget.story.segmentContentId(index),
        ),
    ]);
  }

  @override
  void dispose() {
    _transferController.dispose();
    super.dispose();
  }

  void _next() {
    if (_step == _GrammarWorkshopStep.rule) {
      setState(() => _step = _GrammarWorkshopStep.notice);
    } else if (_step == _GrammarWorkshopStep.notice) {
      setState(() => _step = _GrammarWorkshopStep.choose);
    } else if (_step == _GrammarWorkshopStep.choose) {
      setState(() => _step = _GrammarWorkshopStep.use);
    } else if (_step == _GrammarWorkshopStep.use) {
      setState(() => _step = _GrammarWorkshopStep.review);
    } else {
      _finish();
    }
  }

  void _back() {
    if (_step == _GrammarWorkshopStep.rule) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() {
      _step = _GrammarWorkshopStep
          .values[_GrammarWorkshopStep.values.indexOf(_step) - 1];
    });
  }

  void _finish() {
    Navigator.of(context).pop(
      GrammarWorkshopResult(
        correct: _correctAnswers,
        attempted: _attemptedAnswers,
      ),
    );
  }

  Future<void> _checkTransfer() async {
    final submission = _transferController.text.trim();
    if (submission.isEmpty) return;
    setState(() => _checkingTransfer = true);
    try {
      final target = <String>[
        widget.story.grammarPoint,
        ...widget.story.keywords.take(3).map((word) => word.fr),
      ];
      final result = await ref
          .read(lessonAgentServiceProvider)
          .gradeMicroWriting(
            prompt:
                'Write one fresh French sentence using ${widget.story.grammarPoint}. '
                'Reuse one idea from the story if helpful.',
            targetWords: target,
            submission: submission,
          );
      if (!mounted) return;
      setState(() {
        _transferFeedback = result;
        _checkingTransfer = false;
      });
    } catch (_) {
      if (mounted) setState(() => _checkingTransfer = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final stepIndex = _GrammarWorkshopStep.values.indexOf(_step);
    return Scaffold(
      backgroundColor: DesignTokens.canvas,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(CupertinoIcons.chevron_left),
          onPressed: _back,
        ),
        title: Text(
          widget.story.grammarPoint,
          style: DesignTokens.display(19),
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: DesignTokens.canvas,
        foregroundColor: DesignTokens.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          ReportProblemButton(
            sessionType: 'Grammar: ${widget.story.grammarPoint}',
          ),
        ],
      ),
      body: WebConstrainedView(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
          children: [
            Text(
              widget.story.passage.displayTitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: DesignTokens.body(
                18,
                weight: FontWeight.w700,
              ).copyWith(color: DesignTokens.mutedDim),
            ),
            const SizedBox(height: 12),
            LessonStageRail(
              labels: const ['Rule', 'Notice', 'Choose', 'Use', 'Done'],
              currentIndex: stepIndex,
            ),
            const SizedBox(height: 18),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: KeyedSubtree(
                key: ValueKey(_step),
                child: _contentForStep(),
              ),
            ),
            const SizedBox(height: 22),
            if (_step != _GrammarWorkshopStep.review)
              PrimaryActionButton(
                label: _primaryLabel,
                icon: CupertinoIcons.arrow_right,
                onPressed: _canAdvance ? _next : null,
              )
            else
              _ReviewActions(
                onFinish: _finish,
                showFinishButton: widget.showFinishButton,
              ),
          ],
        ),
      ),
    );
  }

  String get _primaryLabel => switch (_step) {
    _GrammarWorkshopStep.rule => 'Notice it in a story',
    _GrammarWorkshopStep.notice => 'Practice the form',
    _GrammarWorkshopStep.choose => 'Write one of your own',
    _GrammarWorkshopStep.use => 'See my recap',
    _GrammarWorkshopStep.review => 'Finish',
  };

  bool get _canAdvance => switch (_step) {
    _GrammarWorkshopStep.rule => true,
    _GrammarWorkshopStep.notice => true,
    _GrammarWorkshopStep.choose =>
      _quiz.isEmpty || _answers.length == _quiz.length,
    _GrammarWorkshopStep.use => true,
    _GrammarWorkshopStep.review => true,
  };

  Widget _contentForStep() => switch (_step) {
    _GrammarWorkshopStep.rule => _ruleView(),
    _GrammarWorkshopStep.notice => _noticeView(),
    _GrammarWorkshopStep.choose => _chooseView(),
    _GrammarWorkshopStep.use => _useView(),
    _GrammarWorkshopStep.review => _reviewView(),
  };

  Widget _ruleView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _StepKicker(number: '01', label: 'Understand the pattern'),
        const SizedBox(height: 10),
        Text('Start with the rule.', style: DesignTokens.display(28)),
        const SizedBox(height: 8),
        Text(
          _explanation.summary,
          style: DesignTokens.body(
            18,
          ).copyWith(color: DesignTokens.inkSoft, height: 1.45),
        ),
        const SizedBox(height: 16),
        LearningCard(
          color: DesignTokens.primary.withValues(alpha: 0.08),
          borderColor: DesignTokens.primary.withValues(alpha: 0.16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Remember this',
                style: DesignTokens.body(18, weight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              for (final rule in _explanation.usage.take(4))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '•  ',
                        style: TextStyle(color: DesignTokens.primary),
                      ),
                      Expanded(
                        child: Text(
                          rule,
                          style: DesignTokens.body(17).copyWith(height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        if (_explanation.tenseContrast.trim().isNotEmpty) ...[
          const SizedBox(height: 12),
          LearningCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  CupertinoIcons.arrow_left_right,
                  size: 18,
                  color: DesignTokens.info,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _explanation.tenseContrast,
                    style: DesignTokens.body(
                      17,
                    ).copyWith(color: DesignTokens.inkSoft, height: 1.35),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (_explanation.conjugations.isNotEmpty) ...[
          const SizedBox(height: 18),
          Text(
            'The shape',
            style: DesignTokens.body(18, weight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          _ConjugationCard(conjugation: _explanation.conjugations.first),
        ],
      ],
    );
  }

  Widget _noticeView() {
    if (_segments.isEmpty) {
      return const _EmptyState(message: 'This story has no sentences yet.');
    }
    final segment = _segments[_storyIndex.clamp(0, _segments.length - 1)];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _StepKicker(number: '02', label: 'Notice it in context'),
        const SizedBox(height: 10),
        Text('Find the pattern in the story.', style: DesignTokens.display(28)),
        const SizedBox(height: 8),
        Text(
          'Read the French, listen once, then use the English support to confirm it.',
          style: DesignTokens.body(
            18,
          ).copyWith(color: DesignTokens.inkSoft, height: 1.4),
        ),
        const SizedBox(height: 16),
        LearningCard(
          color: DesignTokens.ink,
          borderColor: DesignTokens.ink,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '${_storyIndex + 1}/${_segments.length}',
                    style: DesignTokens.mono(
                      12,
                      weight: FontWeight.w700,
                    ).copyWith(color: Colors.white70),
                  ),
                  const Spacer(),
                  TtsPlayButton(
                    text: segment.fr,
                    size: 44,
                    iconSize: 22,
                    color: Colors.white,
                    contentItemId: widget.story.segmentContentId(_storyIndex),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                segment.fr,
                style: DesignTokens.display(
                  28,
                ).copyWith(color: Colors.white, height: 1.22),
              ),
              const SizedBox(height: 16),
              Container(height: 1, color: Colors.white24),
              const SizedBox(height: 14),
              Text(
                segment.en,
                style: DesignTokens.body(
                  19,
                  weight: FontWeight.w600,
                ).copyWith(color: Colors.white, height: 1.35),
              ),
              if (segment.grammarNote.trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  segment.grammarNote,
                  style: DesignTokens.body(
                    17,
                  ).copyWith(color: Colors.white70, height: 1.4),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: _storyIndex == 0
                  ? null
                  : () => setState(() => _storyIndex--),
              icon: const Icon(CupertinoIcons.chevron_left, size: 16),
              label: Text('Previous', style: DesignTokens.body(16)),
            ),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: _storyIndex >= _segments.length - 1
                  ? null
                  : () => setState(() => _storyIndex++),
              icon: const Icon(CupertinoIcons.chevron_right, size: 16),
              label: Text('Next sentence', style: DesignTokens.body(16)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _chooseView() {
    if (_quiz.isEmpty) {
      return const _EmptyState(
        message: 'The grammar quiz is still being prepared.',
      );
    }
    final question = _currentQuestion!;
    final selected = _answers[_quizIndex];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _StepKicker(number: '03', label: 'Choose the form'),
        const SizedBox(height: 10),
        Text('Make the grammar decision.', style: DesignTokens.display(28)),
        const SizedBox(height: 8),
        Text(
          '${_quizIndex + 1} of ${_quiz.length} · Choose before you check.',
          style: DesignTokens.body(18).copyWith(color: DesignTokens.inkSoft),
        ),
        const SizedBox(height: 16),
        LearningCard(
          child: Text(
            question.q,
            style: DesignTokens.display(22).copyWith(height: 1.3),
          ),
        ),
        const SizedBox(height: 12),
        for (var index = 0; index < question.choices.length; index++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _ChoiceTile(
              label: question.choices[index],
              selected: selected == index,
              correct: selected != null && index == question.answerIndex,
              incorrect: selected == index && index != question.answerIndex,
              onTap: selected != null ? null : () => _selectAnswer(index),
            ),
          ),
        if (selected != null) ...[
          const SizedBox(height: 2),
          Text(
            selected == question.answerIndex
                ? 'Correct — keep that pattern.'
                : 'Not this time. Compare the subject and the verb ending, then keep going.',
            style: DesignTokens.body(17, weight: FontWeight.w600).copyWith(
              color: selected == question.answerIndex
                  ? DesignTokens.success
                  : DesignTokens.primary,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _quizIndex == 0
                    ? null
                    : () => setState(() => _quizIndex--),
                icon: const Icon(CupertinoIcons.chevron_left, size: 16),
                label: const Text('Back'),
              ),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: _quizIndex >= _quiz.length - 1
                    ? null
                    : () => setState(() => _quizIndex++),
                icon: const Icon(CupertinoIcons.chevron_right, size: 16),
                label: const Text('Next question'),
              ),
            ],
          ),
        ],
      ],
    );
  }

  void _selectAnswer(int index) {
    setState(() => _answers[_quizIndex] = index);
  }

  Widget _useView() {
    final keyword = widget.story.keywords.isEmpty
        ? null
        : widget.story.keywords.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _StepKicker(number: '04', label: 'Use it yourself'),
        const SizedBox(height: 10),
        Text('Make one fresh sentence.', style: DesignTokens.display(28)),
        const SizedBox(height: 8),
        Text(
          'Recall the rule, then produce something new. Marie checks it only when you ask.',
          style: DesignTokens.body(
            18,
          ).copyWith(color: DesignTokens.inkSoft, height: 1.4),
        ),
        const SizedBox(height: 16),
        LearningCard(
          color: DesignTokens.success.withValues(alpha: 0.08),
          borderColor: DesignTokens.success.withValues(alpha: 0.18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                CupertinoIcons.lightbulb,
                size: 19,
                color: DesignTokens.success,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Prompt: use ${widget.story.grammarPoint} in a sentence about the story or your own day.',
                  style: DesignTokens.body(17).copyWith(height: 1.4),
                ),
              ),
            ],
          ),
        ),
        if (keyword != null) ...[
          const SizedBox(height: 10),
          Text(
            'Optional word support',
            style: DesignTokens.mono(
              10.5,
              weight: FontWeight.w700,
            ).copyWith(color: DesignTokens.mutedDim),
          ),
          const SizedBox(height: 6),
          InputChip(
            label: Text('${keyword.fr} · ${keyword.en}'),
            onPressed: () => _insertKeyword(keyword.fr),
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: _transferController,
          minLines: 3,
          maxLines: 5,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            hintText: 'Écris une phrase…',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _checkingTransfer ? null : _checkTransfer,
          icon: _checkingTransfer
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(CupertinoIcons.checkmark_seal),
          label: Text(_checkingTransfer ? 'Checking…' : 'Check my sentence'),
        ),
        if (_transferFeedback != null) ...[
          const SizedBox(height: 10),
          LearningCard(
            child: Text(
              _transferFeedback!.comment,
              style: DesignTokens.body(
                16,
              ).copyWith(color: DesignTokens.inkSoft, height: 1.35),
            ),
          ),
        ],
      ],
    );
  }

  void _insertKeyword(String word) {
    final current = _transferController.text.trimRight();
    _transferController.text = current.isEmpty ? '$word ' : '$current $word ';
    _transferController.selection = TextSelection.fromPosition(
      TextPosition(offset: _transferController.text.length),
    );
  }

  Widget _reviewView() {
    final score = _quiz.isEmpty
        ? 0
        : (_correctAnswers / _quiz.length * 100).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _StepKicker(number: '05', label: 'Lock it in'),
        const SizedBox(height: 10),
        Text('Good work. Keep the pattern.', style: DesignTokens.display(28)),
        const SizedBox(height: 8),
        Text(
          'You moved from explanation to recognition to production. That sequence is what makes the rule usable later.',
          style: DesignTokens.body(
            18,
          ).copyWith(color: DesignTokens.inkSoft, height: 1.4),
        ),
        const SizedBox(height: 16),
        LearningCard(
          color: DesignTokens.primary.withValues(alpha: 0.08),
          child: Row(
            children: [
              Text(
                '$score%',
                style: DesignTokens.display(
                  34,
                ).copyWith(color: DesignTokens.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  '$_correctAnswers of ${_quiz.length} grammar choices correct',
                  style: DesignTokens.body(18, weight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
        if (_explanation.examples.isNotEmpty) ...[
          const SizedBox(height: 18),
          Text(
            'One last example',
            style: DesignTokens.body(16, weight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          LearningCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _explanation.examples.first.fr,
                  style: DesignTokens.display(19),
                ),
                const SizedBox(height: 6),
                Text(
                  _explanation.examples.first.en,
                  style: DesignTokens.body(
                    16,
                  ).copyWith(color: DesignTokens.mutedDim),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _StepKicker extends StatelessWidget {
  const _StepKicker({required this.number, required this.label});

  final String number;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          number,
          style: DesignTokens.mono(
            11,
            weight: FontWeight.w800,
          ).copyWith(color: DesignTokens.primary),
        ),
        const SizedBox(width: 8),
        Text(
          label.toUpperCase(),
          style: DesignTokens.mono(
            11,
            weight: FontWeight.w800,
          ).copyWith(color: DesignTokens.mutedDim, letterSpacing: 0.6),
        ),
      ],
    );
  }
}

class _ConjugationCard extends StatelessWidget {
  const _ConjugationCard({required this.conjugation});

  final Conjugation conjugation;

  @override
  Widget build(BuildContext context) {
    return LearningCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            conjugation.verb,
            style: DesignTokens.body(17, weight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 14,
            runSpacing: 7,
            children: [
              for (final row in conjugation.rows.take(6))
                Text(
                  '${row.pronoun} ${row.form}',
                  style: DesignTokens.mono(
                    13,
                  ).copyWith(color: DesignTokens.inkSoft),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.label,
    required this.selected,
    required this.correct,
    required this.incorrect,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool correct;
  final bool incorrect;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = correct
        ? DesignTokens.success
        : incorrect
        ? DesignTokens.primary
        : selected
        ? DesignTokens.primary
        : DesignTokens.hairline;
    return LearningCard(
      padding: 14,
      color: selected ? color.withValues(alpha: 0.08) : null,
      borderColor: color,
      onTap: onTap,
      child: Row(
        children: [
          Icon(
            selected
                ? (correct
                      ? CupertinoIcons.checkmark_circle_fill
                      : CupertinoIcons.xmark_circle_fill)
                : CupertinoIcons.circle,
            size: 20,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: DesignTokens.body(17, weight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewActions extends StatelessWidget {
  const _ReviewActions({
    required this.onFinish,
    required this.showFinishButton,
  });

  final VoidCallback onFinish;
  final bool showFinishButton;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        PrimaryActionButton(
          label: showFinishButton ? 'Complete grammar session' : 'Close lesson',
          icon: CupertinoIcons.checkmark,
          onPressed: onFinish,
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return LearningCard(
      child: Text(
        message,
        style: DesignTokens.body(16).copyWith(color: DesignTokens.mutedDim),
      ),
    );
  }
}
