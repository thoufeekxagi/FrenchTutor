import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../models/content_models.dart';
import '../../services/lesson_speech_service.dart';
import '../speak/speak_ui.dart';
import '../../widgets/web/web_constrained_view.dart';

class ExamPracticeResult {
  const ExamPracticeResult({required this.correct, required this.total});

  final int correct;
  final int total;
}

/// A focused exam surface for a generated Reading or Listening attempt.
/// Regular lesson navigation, vocabulary cards, translations, and enrichment
/// tabs are intentionally absent: this route behaves like a mobile QCM.
class ExamPracticeScreen extends StatefulWidget {
  const ExamPracticeScreen({
    super.key,
    required this.story,
    required this.examName,
    required this.levelBand,
    required this.skill,
  });

  final GeneratedStory story;
  final String examName;
  final String levelBand;
  final String skill;

  bool get isListening => skill == 'listening';

  @override
  State<ExamPracticeScreen> createState() => _ExamPracticeScreenState();
}

class _ExamPracticeScreenState extends State<ExamPracticeScreen> {
  final Map<int, int> _answers = {};
  bool _audioStarted = false;
  bool _audioComplete = false;
  bool _audioPlaying = false;
  bool _submitting = false;

  List<MultipleChoiceQuestion> get _questions => widget.story.quiz;

  @override
  void dispose() {
    LessonSpeechService.shared.stop();
    super.dispose();
  }

  Future<void> _startListening() async {
    if (_audioStarted || _audioPlaying || _audioComplete) return;
    final segments = widget.story.passage.segments;
    if (segments.isEmpty) {
      setState(() {
        _audioStarted = true;
        _audioComplete = true;
      });
      return;
    }
    setState(() {
      _audioStarted = true;
      _audioPlaying = true;
    });
    await LessonSpeechService.shared.speak(
      items: [
        for (var i = 0; i < segments.length; i++)
          SpeechItem(
            text: segments[i].fr,
            language: 'fr-FR',
            contentItemId: widget.story.segmentContentId(i),
          ),
      ],
      onFinished: () {
        if (!mounted) return;
        setState(() {
          _audioPlaying = false;
          _audioComplete = true;
        });
      },
    );
  }

  void _submit() {
    if (_submitting || _questions.isEmpty) return;
    if (_answers.length != _questions.length) return;
    if (widget.isListening && !_audioComplete) return;
    var correct = 0;
    for (var i = 0; i < _questions.length; i++) {
      if (_answers[i] == _questions[i].answerIndex) correct++;
    }
    setState(() => _submitting = true);
    Navigator.of(
      context,
    ).pop(ExamPracticeResult(correct: correct, total: _questions.length));
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.isListening
        ? 'Listening comprehension'
        : 'Reading comprehension';
    return Scaffold(
      backgroundColor: DesignTokens.canvasDim,
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Leave practice',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.close_rounded),
        ),
        title: Text(widget.examName, style: DesignTokens.display(18)),
        backgroundColor: DesignTokens.canvasDim,
        foregroundColor: DesignTokens.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: WebConstrainedView(
        maxWidth: 820,
        child: Column(
          children: [
            _ExamHeader(
              title: title,
              levelBand: widget.levelBand,
              questionCount: _questions.length,
              isListening: widget.isListening,
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
                children: [
                  if (widget.isListening) _audioPanel() else _readingPanel(),
                  const SizedBox(height: 18),
                  for (var i = 0; i < _questions.length; i++) ...[
                    _QuestionBlock(
                      index: i,
                      question: _questions[i],
                      selectedIndex: _answers[i],
                      enabled: !widget.isListening || _audioComplete,
                      onSelected: (answer) =>
                          setState(() => _answers[i] = answer),
                    ),
                    const SizedBox(height: 14),
                  ],
                ],
              ),
            ),
            _submitBar(title),
          ],
        ),
      ),
    );
  }

  Widget _readingPanel() {
    return _ExamSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('DOCUMENT', style: _kickerStyle),
          const SizedBox(height: 10),
          Text(widget.story.passage.title, style: DesignTokens.display(23)),
          const SizedBox(height: 14),
          Text(
            widget.story.passage.fullText,
            style: DesignTokens.body(
              18,
            ).copyWith(color: DesignTokens.ink, height: 1.55),
          ),
        ],
      ),
    );
  }

  Widget _audioPanel() {
    return _ExamSurface(
      color: SpeakColors.navy,
      child: Row(
        children: [
          Icon(
            _audioComplete
                ? Icons.check_circle_outline_rounded
                : Icons.headphones_rounded,
            color: Colors.white,
            size: 30,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _audioComplete ? 'Audio completed' : 'Listen once',
                  style: DesignTokens.body(
                    16,
                    weight: FontWeight.w700,
                  ).copyWith(color: Colors.white),
                ),
                const SizedBox(height: 3),
                Text(
                  _audioComplete
                      ? 'Answer the questions below.'
                      : 'The recording plays once, like the exam.',
                  style: DesignTokens.body(12).copyWith(color: Colors.white70),
                ),
              ],
            ),
          ),
          FilledButton(
            onPressed: _audioStarted ? null : _startListening,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: SpeakColors.navy,
              disabledBackgroundColor: Colors.white24,
              disabledForegroundColor: Colors.white70,
            ),
            child: Text(_audioPlaying ? 'Playing…' : 'Start'),
          ),
        ],
      ),
    );
  }

  Widget _submitBar(String title) {
    final ready =
        _answers.length == _questions.length &&
        (!widget.isListening || _audioComplete);
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: DesignTokens.hairline)),
        ),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: ready ? _submit : null,
            icon: const Icon(Icons.arrow_forward_rounded),
            label: Text(_submitting ? 'Saving…' : 'Submit $title'),
            style: FilledButton.styleFrom(
              backgroundColor: SpeakColors.blue,
              foregroundColor: Colors.white,
              disabledBackgroundColor: SpeakColors.blue.withValues(alpha: 0.24),
              disabledForegroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 15),
            ),
          ),
        ),
      ),
    );
  }
}

class _ExamHeader extends StatelessWidget {
  const _ExamHeader({
    required this.title,
    required this.levelBand,
    required this.questionCount,
    required this.isListening,
  });

  final String title;
  final String levelBand;
  final int questionCount;
  final bool isListening;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: DesignTokens.display(22)),
                const SizedBox(height: 3),
                Text(
                  isListening
                      ? 'One-play audio · 4-option QCM'
                      : 'Document · 4-option QCM',
                  style: DesignTokens.body(
                    12,
                  ).copyWith(color: DesignTokens.mutedDim),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            decoration: BoxDecoration(
              color: SpeakColors.blueSoft,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$levelBand · $questionCount Q',
              style: DesignTokens.body(
                12,
                weight: FontWeight.w700,
              ).copyWith(color: SpeakColors.blue),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuestionBlock extends StatelessWidget {
  const _QuestionBlock({
    required this.index,
    required this.question,
    required this.selectedIndex,
    required this.enabled,
    required this.onSelected,
  });

  final int index;
  final MultipleChoiceQuestion question;
  final int? selectedIndex;
  final bool enabled;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return _ExamSurface(
      color: enabled ? Colors.white : Colors.white.withValues(alpha: 0.62),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('QUESTION ${index + 1}', style: _kickerStyle),
          const SizedBox(height: 8),
          Text(
            question.q,
            style: DesignTokens.body(17, weight: FontWeight.w700).copyWith(
              color: enabled ? DesignTokens.ink : DesignTokens.mutedDim,
              height: 1.35,
            ),
          ),
          if (question.qEn != null) ...[
            const SizedBox(height: 4),
            Text(
              question.qEn!,
              style: DesignTokens.body(
                13,
              ).copyWith(color: DesignTokens.mutedDim),
            ),
          ],
          const SizedBox(height: 10),
          for (var i = 0; i < question.choices.length; i++)
            _OptionRow(
              label: question.choices[i],
              selected: selectedIndex == i,
              enabled: enabled,
              onTap: () => onSelected(i),
            ),
        ],
      ),
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? SpeakColors.blueSoft : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? SpeakColors.blue : DesignTokens.hairline,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 20,
                color: selected ? SpeakColors.blue : DesignTokens.mutedDim,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  label,
                  style: DesignTokens.body(14).copyWith(
                    color: enabled ? DesignTokens.ink : DesignTokens.mutedDim,
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

class _ExamSurface extends StatelessWidget {
  const _ExamSurface({required this.child, this.color = Colors.white});

  final Widget child;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: DesignTokens.hairline),
      ),
      child: child,
    );
  }
}

TextStyle get _kickerStyle => DesignTokens.label(
  10,
).copyWith(color: SpeakColors.blue, letterSpacing: 1.1);
