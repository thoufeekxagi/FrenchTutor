import 'dart:convert';
import 'dart:math';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/grammar_curriculum_catalog.dart';
import '../../design/tokens.dart';
import '../../providers/database_provider.dart';
import '../../services/lesson_agent_service.dart';
import '../../widgets/primary_action_button.dart';
import '../../widgets/web/web_constrained_view.dart';

class GrammarCurriculumResult {
  const GrammarCurriculumResult({
    required this.lessonId,
    required this.correct,
    required this.attempted,
  });

  final String lessonId;
  final int correct;
  final int attempted;
}

enum _GrammarFlowStep { preview, pickWord, sentence, repair, write, review }

class GrammarLessonFlowScreen extends ConsumerStatefulWidget {
  const GrammarLessonFlowScreen({
    super.key,
    required this.lesson,
    required this.initialMode,
  });

  final GrammarCurriculumLesson lesson;
  final GrammarPracticeMode initialMode;

  @override
  ConsumerState<GrammarLessonFlowScreen> createState() =>
      _GrammarLessonFlowScreenState();
}

class _GrammarLessonFlowScreenState
    extends ConsumerState<GrammarLessonFlowScreen> {
  late _GrammarFlowStep _step;
  late final List<String> _wordBank;
  final List<String> _builtSentence = [];
  final TextEditingController _writingController = TextEditingController();

  String? _pickedAnswer;
  bool? _pickCorrect;
  bool? _sentenceCorrect;
  String? _repairAnswer;
  bool? _repairCorrect;
  String? _activeMeaning;
  MicroWritingFeedback? _writingFeedback;
  bool _checkingWriting = false;
  String? _writingError;
  bool _restoring = true;

  String get _progressKey => 'grammar_flow_${widget.lesson.id}';

  @override
  void initState() {
    super.initState();
    _step = switch (widget.initialMode) {
      GrammarPracticeMode.pickWord => _GrammarFlowStep.preview,
      GrammarPracticeMode.makeSentence => _GrammarFlowStep.sentence,
      GrammarPracticeMode.writeOwn => _GrammarFlowStep.write,
    };
    _wordBank = [...widget.lesson.sentenceTiles]
      ..shuffle(Random(widget.lesson.id.hashCode));
    _restoreProgress();
  }

  @override
  void dispose() {
    _writingController.dispose();
    super.dispose();
  }

  Future<void> _restoreProgress() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_progressKey);
    if (raw != null) {
      try {
        final map = (jsonDecode(raw) as Map).cast<String, dynamic>();
        final stage = map['step'] as int?;
        if (stage != null &&
            stage >= 0 &&
            stage < _GrammarFlowStep.values.length - 1) {
          _step = _GrammarFlowStep.values[stage];
        }
        _pickCorrect = map['pickCorrect'] as bool?;
        _sentenceCorrect = map['sentenceCorrect'] as bool?;
        _repairCorrect = map['repairCorrect'] as bool?;
        _pickedAnswer = map['pickedAnswer'] as String?;
        _repairAnswer = map['repairAnswer'] as String?;
        final builtSentence = map['builtSentence'];
        if (builtSentence is List) {
          _builtSentence
            ..clear()
            ..addAll(builtSentence.whereType<String>());
        }
        final writing = map['writing'] as String?;
        if (writing != null) _writingController.text = writing;
        final writingScore = map['writingScore'];
        final writingComment = map['writingComment'] as String?;
        if (writingScore is num && writingComment != null) {
          _writingFeedback = MicroWritingFeedback(
            scoreOutOf10: writingScore.toDouble(),
            comment: writingComment,
          );
        }
      } catch (_) {
        // Corrupt local progress is not substituted with exercise data. The
        // frozen lesson still opens normally from its requested entry point.
      }
    }
    if (mounted) setState(() => _restoring = false);
  }

  Future<void> _saveProgress() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _progressKey,
      jsonEncode({
        'step': _step.index,
        'pickCorrect': _pickCorrect,
        'sentenceCorrect': _sentenceCorrect,
        'repairCorrect': _repairCorrect,
        'pickedAnswer': _pickedAnswer,
        'repairAnswer': _repairAnswer,
        'builtSentence': _builtSentence,
        'writing': _writingController.text,
        'writingScore': _writingFeedback?.scoreOutOf10,
        'writingComment': _writingFeedback?.comment,
      }),
    );
  }

  Future<void> _clearProgress() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_progressKey);
  }

  int get _attempted {
    var value = 0;
    if (_pickCorrect != null) value++;
    if (_sentenceCorrect != null) value++;
    if (_repairCorrect != null) value++;
    if (_writingFeedback != null) value++;
    return value;
  }

  int get _correct {
    var value = 0;
    if (_pickCorrect == true) value++;
    if (_sentenceCorrect == true) value++;
    if (_repairCorrect == true) value++;
    if ((_writingFeedback?.scoreOutOf10 ?? 0) >= 7) value++;
    return value;
  }

  double get _progress => (_step.index + 1) / _GrammarFlowStep.values.length;

  Future<void> _goTo(_GrammarFlowStep step) async {
    setState(() {
      _step = step;
      _activeMeaning = null;
    });
    await _saveProgress();
  }

  Future<void> _next() async {
    switch (_step) {
      case _GrammarFlowStep.preview:
        await _goTo(_GrammarFlowStep.pickWord);
        return;
      case _GrammarFlowStep.pickWord:
        await _goTo(_GrammarFlowStep.sentence);
        return;
      case _GrammarFlowStep.sentence:
        await _goTo(_GrammarFlowStep.repair);
        return;
      case _GrammarFlowStep.repair:
        await _goTo(_GrammarFlowStep.write);
        return;
      case _GrammarFlowStep.write:
        await _goTo(_GrammarFlowStep.review);
        return;
      case _GrammarFlowStep.review:
        await _finish();
        return;
    }
  }

  Future<void> _finish() async {
    final attempted = _attempted;
    final score = attempted == 0 ? 0.0 : _correct / attempted;
    ref
        .read(learningStoreProvider)
        .setLessonStatus(
          widget.lesson.progressId,
          score >= 0.75 ? 'completed' : 'in_progress',
          score: score,
        );
    await _clearProgress();
    if (!mounted) return;
    Navigator.of(context).pop(
      GrammarCurriculumResult(
        lessonId: widget.lesson.id,
        correct: _correct,
        attempted: attempted,
      ),
    );
  }

  void _pick(String answer) {
    if (_pickedAnswer != null) return;
    setState(() {
      _pickedAnswer = answer;
      _pickCorrect = answer == widget.lesson.pickAnswer;
    });
    _saveProgress();
  }

  void _addWord(String word) {
    final used = _builtSentence.where((item) => item == word).length;
    final available = _wordBank.where((item) => item == word).length;
    if (used >= available) return;
    setState(() {
      _builtSentence.add(word);
      _activeMeaning = '$word — ${GrammarCurriculumCatalog.wordMeaning(word)}';
      _sentenceCorrect = null;
    });
    _saveProgress();
  }

  void _removeWord(int index) {
    setState(() {
      final word = _builtSentence.removeAt(index);
      _activeMeaning = '$word — ${GrammarCurriculumCatalog.wordMeaning(word)}';
      _sentenceCorrect = null;
    });
    _saveProgress();
  }

  bool _wordIsAvailable(String word) {
    final used = _builtSentence.where((item) => item == word).length;
    final available = _wordBank.where((item) => item == word).length;
    return used < available;
  }

  void _checkSentence() {
    final built = _normalizeSentence(_builtSentence.join(' '));
    final target = _normalizeSentence(widget.lesson.sentence);
    setState(() => _sentenceCorrect = built == target);
    _saveProgress();
  }

  String _normalizeSentence(String text) => text
      .toLowerCase()
      .replaceAllMapped(RegExp(r'\s+([,.!?;:])'), (match) => match.group(1)!)
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  void _repair(String answer) {
    if (_repairAnswer != null) return;
    setState(() {
      _repairAnswer = answer;
      _repairCorrect = answer == widget.lesson.pickAnswer;
    });
    _saveProgress();
  }

  Future<void> _checkWriting() async {
    final submission = _writingController.text.trim();
    if (submission.isEmpty || _checkingWriting) return;
    setState(() {
      _checkingWriting = true;
      _writingError = null;
    });
    try {
      final result = await ref
          .read(lessonAgentServiceProvider)
          .gradeMicroWriting(
            prompt: widget.lesson.writingPrompt,
            targetWords: [widget.lesson.pickAnswer],
            submission: submission,
          );
      if (!mounted) return;
      setState(() {
        _writingFeedback = result;
        _checkingWriting = false;
      });
      await _saveProgress();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _checkingWriting = false;
        _writingError =
            'Your sentence could not be checked. Nothing was substituted or marked complete.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_restoring) {
      return Scaffold(
        backgroundColor: DesignTokens.canvas,
        body: Center(
          child: CircularProgressIndicator(color: DesignTokens.primary),
        ),
      );
    }

    return Scaffold(
      backgroundColor: DesignTokens.canvas,
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Close grammar lesson',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(CupertinoIcons.xmark),
        ),
        title: Text(
          widget.lesson.title,
          style: DesignTokens.display(18),
          overflow: TextOverflow.ellipsis,
        ),
        centerTitle: true,
        backgroundColor: DesignTokens.canvas,
        foregroundColor: DesignTokens.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 18),
              child: Text(
                widget.lesson.level,
                style: DesignTokens.body(
                  13,
                  weight: FontWeight.w800,
                ).copyWith(color: DesignTokens.primary),
              ),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: _progress,
                minHeight: 5,
                backgroundColor: DesignTokens.hairline,
                color: DesignTokens.primary,
              ),
            ),
          ),
        ),
      ),
      body: WebConstrainedView(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 36),
          children: [
            AnimatedSwitcher(
              duration: DesignTokens.durationFast,
              child: KeyedSubtree(key: ValueKey(_step), child: _stepContent()),
            ),
            const SizedBox(height: 22),
            if (_showPrimaryAction)
              PrimaryActionButton(
                label: _primaryLabel,
                icon: _step == _GrammarFlowStep.review
                    ? CupertinoIcons.checkmark_alt
                    : CupertinoIcons.arrow_right,
                onPressed: _canContinue ? _next : null,
              ),
          ],
        ),
      ),
    );
  }

  bool get _showPrimaryAction => switch (_step) {
    _GrammarFlowStep.sentence => _sentenceCorrect != null,
    _GrammarFlowStep.write => _writingFeedback != null,
    _ => true,
  };

  bool get _canContinue => switch (_step) {
    _GrammarFlowStep.preview => true,
    _GrammarFlowStep.pickWord => _pickedAnswer != null,
    _GrammarFlowStep.sentence => _sentenceCorrect != null,
    _GrammarFlowStep.repair => _repairAnswer != null,
    _GrammarFlowStep.write => _writingFeedback != null,
    _GrammarFlowStep.review => true,
  };

  String get _primaryLabel => switch (_step) {
    _GrammarFlowStep.preview => 'Start lesson',
    _GrammarFlowStep.pickWord => 'Make a sentence',
    _GrammarFlowStep.sentence => 'Fix one sentence',
    _GrammarFlowStep.repair => 'Write your own',
    _GrammarFlowStep.write => 'See review',
    _GrammarFlowStep.review => 'Finish',
  };

  Widget _stepContent() => switch (_step) {
    _GrammarFlowStep.preview => _previewView(),
    _GrammarFlowStep.pickWord => _pickWordView(),
    _GrammarFlowStep.sentence => _sentenceView(),
    _GrammarFlowStep.repair => _repairView(),
    _GrammarFlowStep.write => _writeView(),
    _GrammarFlowStep.review => _reviewView(),
  };

  Widget _previewView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StepLabel(label: widget.lesson.collection),
        const SizedBox(height: 10),
        Text(widget.lesson.title, style: DesignTokens.display(32)),
        const SizedBox(height: 8),
        Text(
          widget.lesson.subtitle,
          style: DesignTokens.body(16).copyWith(color: DesignTokens.muted),
        ),
        const SizedBox(height: 22),
        _ExerciseCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(CupertinoIcons.lightbulb, color: DesignTokens.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.lesson.tip,
                      style: DesignTokens.body(
                        16,
                        weight: FontWeight.w700,
                      ).copyWith(height: 1.4),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const _PreviewRow(
                icon: Icons.touch_app_outlined,
                title: 'Pick the right form',
              ),
              const _PreviewRow(
                icon: Icons.grid_view_rounded,
                title: 'Put a sentence in order',
              ),
              const _PreviewRow(
                icon: Icons.edit_note_rounded,
                title: 'Use the grammar yourself',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _pickWordView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _StepLabel(label: 'PICK THE RIGHT WORD'),
        const SizedBox(height: 10),
        Text('Complete the sentence', style: DesignTokens.display(28)),
        const SizedBox(height: 18),
        _ExerciseCard(
          feedback: _pickCorrect,
          feedbackTitle: _pickCorrect == true ? 'Correct' : 'Try this form',
          feedbackBody: _pickCorrect == null
              ? null
              : _pickCorrect == true
              ? widget.lesson.tip
              : '${widget.lesson.pickAnswer} is correct. ${widget.lesson.tip}',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.lesson.pickPrompt,
                textAlign: TextAlign.center,
                style: DesignTokens.display(25),
              ),
              const SizedBox(height: 22),
              for (final choice in widget.lesson.pickChoices) ...[
                _AnswerChoice(
                  label: choice,
                  selected: choice == _pickedAnswer,
                  correct: _pickedAnswer == null
                      ? null
                      : choice == widget.lesson.pickAnswer,
                  onTap: () => _pick(choice),
                ),
                const SizedBox(height: 9),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _sentenceView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _StepLabel(label: 'MAKE A SENTENCE'),
        const SizedBox(height: 10),
        Text('Put the words in order', style: DesignTokens.display(28)),
        const SizedBox(height: 8),
        Text(
          widget.lesson.translation,
          style: DesignTokens.body(15).copyWith(color: DesignTokens.muted),
        ),
        const SizedBox(height: 18),
        _ExerciseCard(
          feedback: _sentenceCorrect,
          feedbackTitle: _sentenceCorrect == true
              ? 'Sentence complete'
              : 'Check the order',
          feedbackBody: _sentenceCorrect == null
              ? null
              : _sentenceCorrect == true
              ? widget.lesson.tip
              : 'Correct sentence: ${widget.lesson.sentence}',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                constraints: const BoxConstraints(minHeight: 92),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: DesignTokens.canvasDim,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: DesignTokens.hairline),
                ),
                child: _builtSentence.isEmpty
                    ? Center(
                        child: Text(
                          'Tap the words below',
                          style: DesignTokens.body(
                            14,
                          ).copyWith(color: DesignTokens.muted),
                        ),
                      )
                    : Wrap(
                        spacing: 7,
                        runSpacing: 7,
                        children: [
                          for (var i = 0; i < _builtSentence.length; i++)
                            _WordTile(
                              word: _builtSentence[i],
                              selected: true,
                              onTap: () => _removeWord(i),
                            ),
                        ],
                      ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  for (final word in _wordBank)
                    if (_wordIsAvailable(word))
                      _WordTile(word: word, onTap: () => _addWord(word)),
                ],
              ),
              if (_activeMeaning != null) ...[
                const SizedBox(height: 14),
                AnimatedContainer(
                  duration: DesignTokens.durationFast,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: DesignTokens.primarySoft,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    _activeMeaning!,
                    style: DesignTokens.body(13, weight: FontWeight.w700),
                  ),
                ),
              ],
              if (_sentenceCorrect == null) ...[
                const SizedBox(height: 18),
                SizedBox(
                  height: 50,
                  child: OutlinedButton(
                    onPressed: _builtSentence.isEmpty ? null : _checkSentence,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: DesignTokens.primary,
                      side: BorderSide(color: DesignTokens.primary),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                    child: const Text('Check sentence'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _repairView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _StepLabel(label: 'FIX ONE PART'),
        const SizedBox(height: 10),
        Text('Repair the sentence', style: DesignTokens.display(28)),
        const SizedBox(height: 18),
        _ExerciseCard(
          feedback: _repairCorrect,
          feedbackTitle: _repairCorrect == true ? 'Fixed' : 'Use this form',
          feedbackBody: _repairCorrect == null
              ? null
              : _repairCorrect == true
              ? widget.lesson.tip
              : 'Correct sentence: ${widget.lesson.sentence}',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: DesignTokens.dangerSoft,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  widget.lesson.incorrectSentence,
                  textAlign: TextAlign.center,
                  style: DesignTokens.body(19, weight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Which form repairs it?',
                style: DesignTokens.body(14, weight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final choice in widget.lesson.pickChoices)
                    _RepairChip(
                      label: choice,
                      selected: choice == _repairAnswer,
                      correct: _repairAnswer == null
                          ? null
                          : choice == widget.lesson.pickAnswer,
                      onTap: () => _repair(choice),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _writeView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _StepLabel(label: 'WRITE YOUR OWN'),
        const SizedBox(height: 10),
        Text('Use it in your sentence', style: DesignTokens.display(28)),
        const SizedBox(height: 8),
        Text(
          widget.lesson.writingPrompt,
          style: DesignTokens.body(
            15,
          ).copyWith(color: DesignTokens.muted, height: 1.4),
        ),
        const SizedBox(height: 18),
        _ExerciseCard(
          feedback: _writingFeedback == null
              ? null
              : _writingFeedback!.scoreOutOf10 >= 7,
          feedbackTitle: _writingFeedback == null
              ? null
              : '${_writingFeedback!.scoreOutOf10.toStringAsFixed(0)}/10',
          feedbackBody: _writingFeedback?.comment,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _writingController,
                enabled: _writingFeedback == null && !_checkingWriting,
                minLines: 4,
                maxLines: 7,
                textCapitalization: TextCapitalization.sentences,
                style: DesignTokens.body(17),
                decoration: InputDecoration(
                  hintText: 'Write one French sentence…',
                  hintStyle: DesignTokens.body(
                    16,
                  ).copyWith(color: DesignTokens.muted),
                  filled: true,
                  fillColor: DesignTokens.canvasDim,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: DesignTokens.hairline),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: DesignTokens.hairline),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: DesignTokens.primary),
                  ),
                ),
              ),
              if (_writingError != null) ...[
                const SizedBox(height: 12),
                Text(
                  _writingError!,
                  style: DesignTokens.body(
                    13,
                    weight: FontWeight.w700,
                  ).copyWith(color: DesignTokens.danger, height: 1.35),
                ),
              ],
              if (_writingFeedback == null) ...[
                const SizedBox(height: 16),
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _checkingWriting ? null : _checkWriting,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: DesignTokens.primary,
                      foregroundColor: DesignTokens.onPrimary,
                      disabledBackgroundColor: DesignTokens.primary.withValues(
                        alpha: 0.5,
                      ),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: _checkingWriting
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: DesignTokens.onPrimary,
                            ),
                          )
                        : Text(
                            'Check my sentence',
                            style: DesignTokens.body(
                              15,
                              weight: FontWeight.w800,
                            ).copyWith(color: DesignTokens.onPrimary),
                          ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _reviewView() {
    final attempted = _attempted;
    final correct = _correct;
    final score = attempted == 0 ? 0 : ((correct / attempted) * 100).round();
    final needsRepair = <String>[
      if (_pickCorrect == false) 'Pick the correct form',
      if (_sentenceCorrect == false) 'Put the sentence in order',
      if (_repairCorrect == false) 'Repair the incorrect form',
      if (_writingFeedback != null && _writingFeedback!.scoreOutOf10 < 7)
        'Use the form in your own sentence',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _StepLabel(label: 'LESSON REVIEW'),
        const SizedBox(height: 10),
        Text(
          score >= 75 ? 'Grammar unlocked' : 'One more pass will help',
          style: DesignTokens.display(30),
        ),
        const SizedBox(height: 18),
        _ExerciseCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: score >= 75
                          ? DesignTokens.successSoft
                          : DesignTokens.primarySoft,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      score >= 75
                          ? CupertinoIcons.checkmark_alt
                          : CupertinoIcons.refresh_thick,
                      color: score >= 75
                          ? DesignTokens.success
                          : DesignTokens.primary,
                      size: 30,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('$score%', style: DesignTokens.display(30)),
                        Text(
                          '$correct of $attempted checks completed',
                          style: DesignTokens.body(
                            13,
                          ).copyWith(color: DesignTokens.muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              _ReviewLine(
                label: 'Right form',
                successful: _pickCorrect != false,
              ),
              _ReviewLine(
                label: 'Sentence order',
                successful: _sentenceCorrect != false,
              ),
              _ReviewLine(
                label: 'Grammar repair',
                successful: _repairCorrect != false,
              ),
              if (needsRepair.isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: DesignTokens.primarySoft,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Next repair',
                        style: DesignTokens.body(13, weight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text(needsRepair.first, style: DesignTokens.body(13)),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ExerciseCard extends StatelessWidget {
  const _ExerciseCard({
    required this.child,
    this.feedback,
    this.feedbackTitle,
    this.feedbackBody,
  });

  final Widget child;
  final bool? feedback;
  final String? feedbackTitle;
  final String? feedbackBody;

  @override
  Widget build(BuildContext context) {
    final feedbackColor = feedback == true
        ? DesignTokens.success
        : feedback == false
        ? DesignTokens.danger
        : DesignTokens.hairline;
    return AnimatedContainer(
      duration: DesignTokens.durationFast,
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: DesignTokens.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: feedback == null ? DesignTokens.hairline : feedbackColor,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          child,
          if (feedback != null && feedbackBody != null) ...[
            const SizedBox(height: 18),
            AnimatedContainer(
              duration: DesignTokens.durationFast,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: feedback == true
                    ? DesignTokens.successSoft
                    : DesignTokens.dangerSoft,
                borderRadius: BorderRadius.circular(15),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    feedback == true
                        ? CupertinoIcons.checkmark_circle_fill
                        : CupertinoIcons.exclamationmark_circle_fill,
                    color: feedbackColor,
                    size: 21,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (feedbackTitle != null)
                          Text(
                            feedbackTitle!,
                            style: DesignTokens.body(
                              14,
                              weight: FontWeight.w800,
                            ),
                          ),
                        const SizedBox(height: 3),
                        Text(
                          feedbackBody!,
                          style: DesignTokens.body(13).copyWith(height: 1.35),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AnswerChoice extends StatelessWidget {
  const _AnswerChoice({
    required this.label,
    required this.selected,
    required this.correct,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool? correct;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = correct == true
        ? DesignTokens.success
        : selected && correct == false
        ? DesignTokens.danger
        : selected
        ? DesignTokens.primary
        : DesignTokens.hairline;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.11)
              : DesignTokens.canvasDim,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: color),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: DesignTokens.body(15, weight: FontWeight.w700),
              ),
            ),
            if (selected)
              Icon(
                correct == true
                    ? CupertinoIcons.checkmark_circle_fill
                    : CupertinoIcons.xmark_circle_fill,
                color: color,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }
}

class _WordTile extends StatelessWidget {
  const _WordTile({
    required this.word,
    required this.onTap,
    this.selected = false,
  });

  final String word;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$word. Tap to ${selected ? 'remove' : 'add'} and hear meaning.',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? DesignTokens.primarySoft : DesignTokens.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? DesignTokens.primary : DesignTokens.hairline,
            ),
          ),
          child: Text(
            word,
            style: DesignTokens.body(14, weight: FontWeight.w700),
          ),
        ),
      ),
    );
  }
}

class _RepairChip extends StatelessWidget {
  const _RepairChip({
    required this.label,
    required this.selected,
    required this.correct,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool? correct;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = correct == true
        ? DesignTokens.success
        : selected && correct == false
        ? DesignTokens.danger
        : DesignTokens.primary;
    return ActionChip(
      label: Text(label),
      onPressed: onTap,
      backgroundColor: selected
          ? color.withValues(alpha: 0.12)
          : DesignTokens.canvasDim,
      side: BorderSide(color: selected ? color : DesignTokens.hairline),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
      labelStyle: DesignTokens.body(14, weight: FontWeight.w700),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
    );
  }
}

class _StepLabel extends StatelessWidget {
  const _StepLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: DesignTokens.label(
        12,
        weight: FontWeight.w800,
      ).copyWith(color: DesignTokens.primary, letterSpacing: 1.2),
    );
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 19, color: DesignTokens.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: DesignTokens.body(14, weight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewLine extends StatelessWidget {
  const _ReviewLine({required this.label, required this.successful});

  final String label;
  final bool successful;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(
            successful
                ? CupertinoIcons.checkmark_circle_fill
                : CupertinoIcons.refresh_thick,
            color: successful ? DesignTokens.success : DesignTokens.primary,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: DesignTokens.body(14, weight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
