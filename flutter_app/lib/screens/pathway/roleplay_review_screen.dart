import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../models/content_models.dart';
import '../../widgets/primary_action_button.dart';
import '../../widgets/tts_play_button.dart';

/// A quiet post-scene landing page for roleplay. The live scene is the lesson;
/// this page is deliberately optional, so a learner can finish after speaking
/// or stay for a small, low-friction recall pass.
class RoleplayReviewScreen extends StatefulWidget {
  const RoleplayReviewScreen({super.key, required this.roleplay});

  final GeneratedRoleplay roleplay;

  @override
  State<RoleplayReviewScreen> createState() => _RoleplayReviewScreenState();
}

class _RoleplayReviewScreenState extends State<RoleplayReviewScreen> {
  var _showQuiz = false;
  var _quizIndex = 0;
  var _score = 0;
  int? _selectedAnswer;

  List<ReadingSegment> get _segments => widget.roleplay.passage.segments;

  void _chooseAnswer(int index) {
    if (_selectedAnswer != null) return;
    setState(() {
      _selectedAnswer = index;
      if (index == 0) _score++;
    });
  }

  void _nextQuestion() {
    if (_quizIndex >= _segments.length - 1) return;
    setState(() {
      _quizIndex++;
      _selectedAnswer = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DesignTokens.canvas,
      appBar: AppBar(
        title: Text(
          _showQuiz ? 'Quick recall' : 'Scene complete',
          style: DesignTokens.display(19),
        ),
        backgroundColor: DesignTokens.canvas,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          tooltip: 'Close',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(CupertinoIcons.xmark, size: 19),
        ),
      ),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 240),
          child: _showQuiz ? _quiz(context) : _recap(context),
        ),
      ),
    );
  }

  Widget _recap(BuildContext context) {
    return ListView(
      key: const ValueKey('recap'),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
      children: [
        Text(widget.roleplay.displayTitle, style: DesignTokens.display(28)),
        const SizedBox(height: 8),
        Text(
          'You completed ${_segments.length} guided turns. Keep the useful lines close, then try them again in a different scene later.',
          style: DesignTokens.body(
            14,
          ).copyWith(color: DesignTokens.mutedDim, height: 1.45),
        ),
        const SizedBox(height: 22),
        _SectionLabel('Useful lines'),
        const SizedBox(height: 8),
        for (var i = 0; i < _segments.length; i++) _lineRow(_segments[i], i),
        const SizedBox(height: 18),
        OutlinedButton.icon(
          onPressed: _segments.isEmpty
              ? null
              : () => setState(() {
                  _showQuiz = true;
                  _quizIndex = 0;
                  _score = 0;
                  _selectedAnswer = null;
                }),
          icon: const Icon(CupertinoIcons.lightbulb, size: 18),
          label: const Text('Try the optional recall quiz'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            foregroundColor: DesignTokens.primary,
            side: BorderSide(color: DesignTokens.primary.withValues(alpha: .3)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        const SizedBox(height: 12),
        PrimaryActionButton(
          label: 'Done',
          icon: CupertinoIcons.checkmark,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  Widget _lineRow(ReadingSegment segment, int index) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            (index + 1).toString().padLeft(2, '0'),
            style: DesignTokens.mono(
              11,
              weight: FontWeight.w700,
            ).copyWith(color: DesignTokens.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  segment.fr,
                  style: DesignTokens.body(15, weight: FontWeight.w600),
                ),
                const SizedBox(height: 3),
                Text(
                  segment.en,
                  style: DesignTokens.body(
                    12,
                  ).copyWith(color: DesignTokens.mutedDim),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TtsPlayButton(
            text: segment.fr,
            size: 36,
            contentItemId: '${widget.roleplay.id}_review_$index',
          ),
        ],
      ),
    );
  }

  Widget _quiz(BuildContext context) {
    final segment = _segments[_quizIndex];
    final choices = _choicesFor(_quizIndex);
    final isLast = _quizIndex == _segments.length - 1;
    return ListView(
      key: const ValueKey('quiz'),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
      children: [
        Text(
          '${_quizIndex + 1}/${_segments.length}',
          style: DesignTokens.mono(
            12,
            weight: FontWeight.w700,
          ).copyWith(color: DesignTokens.primary),
        ),
        const SizedBox(height: 10),
        Text('What could you say next?', style: DesignTokens.display(28)),
        const SizedBox(height: 8),
        Text(
          segment.characterEn ?? segment.characterFr ?? 'Continue the scene.',
          style: DesignTokens.body(
            14,
          ).copyWith(color: DesignTokens.mutedDim, height: 1.4),
        ),
        const SizedBox(height: 22),
        for (var i = 0; i < choices.length; i++)
          _answerButton(choices[i], i, selected: _selectedAnswer == i),
        if (_selectedAnswer != null) ...[
          const SizedBox(height: 14),
          Text(
            _selectedAnswer == 0
                ? 'Good recall — that line fits this turn.'
                : 'The scene line to remember is: ${segment.fr}',
            style: DesignTokens.body(13, weight: FontWeight.w600).copyWith(
              color: _selectedAnswer == 0
                  ? DesignTokens.success
                  : DesignTokens.warning,
            ),
          ),
          const SizedBox(height: 18),
          if (isLast)
            PrimaryActionButton(
              label: 'Finish · $_score/${_segments.length}',
              icon: CupertinoIcons.checkmark,
              onPressed: () => Navigator.of(context).maybePop(),
            )
          else
            PrimaryActionButton(
              label: 'Next',
              icon: CupertinoIcons.arrow_right,
              onPressed: _nextQuestion,
            ),
        ],
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => setState(() => _showQuiz = false),
          child: const Text('Skip quiz'),
        ),
      ],
    );
  }

  List<String> _choicesFor(int index) {
    if (_segments.length < 3) {
      return [
        _segments[index].fr,
        'Je peux vous aider, s’il vous plaît ?',
        'Je voudrais regarder le menu.',
      ];
    }
    return [
      _segments[index].fr,
      _segments[(index + 1) % _segments.length].fr,
      _segments[(index + 2) % _segments.length].fr,
    ];
  }

  Widget _answerButton(String text, int index, {required bool selected}) {
    final answered = _selectedAnswer != null;
    final correct = index == 0;
    final color = !answered
        ? DesignTokens.surface
        : correct
        ? DesignTokens.successSoft
        : selected
        ? DesignTokens.warningSoft
        : DesignTokens.surface;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: !answered
                ? DesignTokens.hairline
                : correct
                ? DesignTokens.success
                : selected
                ? DesignTokens.warning
                : DesignTokens.hairline,
          ),
        ),
        child: InkWell(
          onTap: answered ? null : () => _chooseAnswer(index),
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(text, style: DesignTokens.body(14)),
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: DesignTokens.mono(
      11,
      weight: FontWeight.w700,
    ).copyWith(color: DesignTokens.mutedDim, letterSpacing: 1.1),
  );
}
