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
  bool _submitted = false;

  List<MultipleChoiceQuestion> get _questions => widget.story.quiz;

  int get _correctAnswers => _questions.asMap().entries.where((entry) {
    return _answers[entry.key] == entry.value.answerIndex;
  }).length;

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
    if (_submitted || _questions.isEmpty) return;
    if (_answers.length != _questions.length) return;
    if (widget.isListening && !_audioComplete) return;
    setState(() {
      _submitted = true;
    });
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
                  if (_submitted) ...[
                    const SizedBox(height: 18),
                    _reviewSummary(),
                  ],
                  const SizedBox(height: 18),
                  for (var i = 0; i < _questions.length; i++) ...[
                    _QuestionBlock(
                      index: i,
                      question: _questions[i],
                      selectedIndex: _answers[i],
                      enabled:
                          !_submitted &&
                          (!widget.isListening || _audioComplete),
                      submitted: _submitted,
                      showEnglishSupport: const {
                        'A1',
                        'A2',
                      }.contains(widget.levelBand.trim().toUpperCase()),
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
          Text(
            widget.story.passage.displayTitle,
            style: DesignTokens.display(23),
          ),
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
      color: DesignTokens.nightSurfaceRaised,
      child: Row(
        children: [
          Icon(
            _audioComplete
                ? Icons.check_circle_outline_rounded
                : Icons.headphones_rounded,
            color: DesignTokens.nightText,
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
                  ).copyWith(color: DesignTokens.nightText),
                ),
                const SizedBox(height: 3),
                Text(
                  _audioComplete
                      ? 'Answer the questions below.'
                      : 'The recording plays once, like the exam.',
                  style: DesignTokens.body(
                    12,
                  ).copyWith(color: DesignTokens.nightMuted),
                ),
              ],
            ),
          ),
          FilledButton(
            onPressed: _audioStarted ? null : _startListening,
            style: FilledButton.styleFrom(
              backgroundColor: DesignTokens.nightAccent,
              foregroundColor: DesignTokens.onPrimary,
              disabledBackgroundColor: DesignTokens.nightHairline,
              disabledForegroundColor: DesignTokens.nightMuted,
            ),
            child: Text(_audioPlaying ? 'Playing…' : 'Start'),
          ),
        ],
      ),
    );
  }

  Widget _submitBar(String title) {
    final ready =
        !_submitted &&
        _answers.length == _questions.length &&
        (!widget.isListening || _audioComplete);
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
        decoration: BoxDecoration(
          color: DesignTokens.surface,
          border: Border(top: BorderSide(color: DesignTokens.hairline)),
        ),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _submitted
                ? () => Navigator.of(context).pop(
                    ExamPracticeResult(
                      correct: _correctAnswers,
                      total: _questions.length,
                    ),
                  )
                : ready
                ? _submit
                : null,
            icon: Icon(
              _submitted ? Icons.check_rounded : Icons.arrow_forward_rounded,
            ),
            label: Text(
              _submitted ? 'Finish and save result' : 'Submit $title',
            ),
            style: FilledButton.styleFrom(
              backgroundColor: DesignTokens.nightAccent,
              foregroundColor: DesignTokens.onPrimary,
              disabledBackgroundColor: DesignTokens.nightHairline,
              disabledForegroundColor: DesignTokens.nightMuted,
              padding: const EdgeInsets.symmetric(vertical: 15),
            ),
          ),
        ),
      ),
    );
  }

  Widget _reviewSummary() {
    final total = _questions.length;
    final percent = total == 0 ? 0 : ((_correctAnswers / total) * 100).round();
    return _ExamSurface(
      color: SpeakColors.accentSoft,
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: SpeakColors.accent,
              borderRadius: BorderRadius.circular(16),
            ),
            alignment: Alignment.center,
            child: Text(
              '$percent%',
              style: DesignTokens.display(
                16,
              ).copyWith(color: DesignTokens.onPrimary),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Exam review',
                  style: DesignTokens.body(16, weight: FontWeight.w800),
                ),
                const SizedBox(height: 3),
                Text(
                  '$_correctAnswers of $total answers correct. Check each item below to see what to keep and what to practise next.',
                  style: DesignTokens.body(
                    13,
                  ).copyWith(color: DesignTokens.mutedDim, height: 1.35),
                ),
              ],
            ),
          ),
        ],
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
              color: SpeakColors.accentSoft,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$levelBand · $questionCount Q',
              style: DesignTokens.body(
                12,
                weight: FontWeight.w700,
              ).copyWith(color: SpeakColors.accent),
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
    required this.submitted,
    required this.showEnglishSupport,
    required this.onSelected,
  });

  final int index;
  final MultipleChoiceQuestion question;
  final int? selectedIndex;
  final bool enabled;
  final bool submitted;
  final bool showEnglishSupport;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return _ExamSurface(
      color: enabled
          ? DesignTokens.surface
          : DesignTokens.surface.withValues(alpha: 0.62),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('QUESTION ${index + 1}', style: _kickerStyle),
          const SizedBox(height: 8),
          Text(
            question.q,
            style: DesignTokens.body(17, weight: FontWeight.w700).copyWith(
              color: enabled || submitted
                  ? DesignTokens.ink
                  : DesignTokens.mutedDim,
              height: 1.35,
            ),
          ),
          if (showEnglishSupport && question.qEn != null) ...[
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
              secondaryLabel:
                  showEnglishSupport &&
                      question.choicesEn != null &&
                      i < question.choicesEn!.length
                  ? question.choicesEn![i]
                  : null,
              selected: selectedIndex == i,
              correct: submitted && i == question.answerIndex,
              incorrect:
                  submitted && selectedIndex == i && i != question.answerIndex,
              enabled: enabled,
              onTap: () => onSelected(i),
            ),
          if (submitted) ...[
            const SizedBox(height: 4),
            _ReviewAnswerLine(
              label: 'Correct answer',
              value: question.choices[question.answerIndex],
              color: DesignTokens.success,
            ),
            if (selectedIndex != null && selectedIndex != question.answerIndex)
              _ReviewAnswerLine(
                label: 'Your answer',
                value: question.choices[selectedIndex!],
                color: DesignTokens.danger,
              ),
          ],
        ],
      ),
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.label,
    this.secondaryLabel,
    required this.selected,
    required this.correct,
    required this.incorrect,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final String? secondaryLabel;
  final bool selected;
  final bool correct;
  final bool incorrect;
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
            color: correct
                ? DesignTokens.success.withValues(alpha: 0.10)
                : incorrect
                ? DesignTokens.danger.withValues(alpha: 0.10)
                : selected
                ? SpeakColors.accentSoft
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: correct
                  ? DesignTokens.success
                  : incorrect
                  ? DesignTokens.danger
                  : selected
                  ? SpeakColors.accent
                  : DesignTokens.hairline,
            ),
          ),
          child: Row(
            children: [
              Icon(
                correct
                    ? Icons.check_circle_rounded
                    : incorrect
                    ? Icons.cancel_rounded
                    : selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 20,
                color: correct
                    ? DesignTokens.success
                    : incorrect
                    ? DesignTokens.danger
                    : selected
                    ? SpeakColors.accent
                    : DesignTokens.mutedDim,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: DesignTokens.body(14).copyWith(
                        color: enabled || correct || incorrect
                            ? DesignTokens.ink
                            : DesignTokens.mutedDim,
                      ),
                    ),
                    if (secondaryLabel != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        secondaryLabel!,
                        style: DesignTokens.body(
                          12,
                        ).copyWith(color: DesignTokens.mutedDim),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReviewAnswerLine extends StatelessWidget {
  const _ReviewAnswerLine({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 7),
      child: RichText(
        text: TextSpan(
          style: DesignTokens.body(13).copyWith(color: DesignTokens.ink),
          children: [
            TextSpan(
              text: '$label: ',
              style: TextStyle(color: color, fontWeight: FontWeight.w800),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }
}

class _ExamSurface extends StatelessWidget {
  const _ExamSurface({required this.child, this.color});

  final Widget child;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color ?? DesignTokens.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: DesignTokens.hairline),
      ),
      child: child,
    );
  }
}

TextStyle get _kickerStyle => DesignTokens.label(
  10,
).copyWith(color: SpeakColors.accent, letterSpacing: 1.1);
