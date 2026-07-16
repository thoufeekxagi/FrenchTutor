import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../design/tokens.dart';
import '../../widgets/passeport_card.dart';
import '../../widgets/kicker_text.dart';
import '../../widgets/passeport_primary_button.dart';
import '../../providers/database_provider.dart';
import '../../models/content_models.dart';
import '../../services/lesson_speech_service.dart';
import '../../widgets/lesson_qa_overlay.dart';
import '../../widgets/marie_toolbar_button.dart';

class GrammarLessonScreen extends ConsumerStatefulWidget {
  const GrammarLessonScreen({super.key, required this.lesson});

  final GrammarLesson lesson;

  @override
  ConsumerState<GrammarLessonScreen> createState() =>
      _GrammarLessonScreenState();
}

class _GrammarLessonScreenState extends ConsumerState<GrammarLessonScreen> {
  // Drill state
  final Map<int, String?> _drillAnswers = {};
  final Map<int, bool> _drillChecked = {};
  bool _drillsSubmitted = false;
  bool _isPlaying = false;

  String get _lessonContext =>
      ref.read(contentServiceProvider).grammarLessonContext(widget.lesson);

  double get _drillScore {
    if (widget.lesson.drills.isEmpty) return 1.0;
    int correct = 0;
    for (int i = 0; i < widget.lesson.drills.length; i++) {
      if (_drillChecked[i] == true &&
          _drillAnswers[i] == widget.lesson.drills[i].answer) {
        correct++;
      }
    }
    return correct / widget.lesson.drills.length;
  }

  bool get _allDrillsAnswered {
    return _drillAnswers.length == widget.lesson.drills.length &&
        _drillAnswers.values.every((v) => v != null);
  }

  void _submitDrills() {
    setState(() {
      for (int i = 0; i < widget.lesson.drills.length; i++) {
        _drillChecked[i] = true;
      }
      _drillsSubmitted = true;
    });

    final store = ref.read(learningStoreProvider);
    final score = _drillScore;
    final status = score >= 0.8 ? 'completed' : 'in_progress';
    store.setLessonStatus(widget.lesson.id, status, score: score);
  }

  void _togglePlayback() {
    final speech = LessonSpeechService.shared;
    if (speech.isSpeaking) {
      speech.pause();
      setState(() => _isPlaying = false);
    } else if (speech.isPaused) {
      speech.resume();
      setState(() => _isPlaying = true);
    } else {
      speech.speak(
        items: LessonSpeechService.speechItemsFromLines(
          widget.lesson.narration,
        ),
        onFinished: () {
          if (mounted) setState(() => _isPlaying = false);
        },
      );
      setState(() => _isPlaying = true);
    }
  }

  @override
  void dispose() {
    LessonSpeechService.shared.deactivate();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DesignTokens.parchmentDim,
      appBar: AppBar(
        title: Text(widget.lesson.title, style: DesignTokens.display(20)),
        backgroundColor: DesignTokens.parchmentDim,
        foregroundColor: DesignTokens.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          IconButton(
            onPressed: () =>
                LessonQAOverlay.show(context, lessonContext: _lessonContext),
            icon: const Icon(CupertinoIcons.mic_fill, color: DesignTokens.info),
          ),
          MarieToolbarButton(lessonContext: _lessonContext),
        ],
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
            children: [
              // Subtitle
              Text(
                widget.lesson.subtitle,
                style: DesignTokens.body(
                  15,
                ).copyWith(color: DesignTokens.slateDim),
              ),
              const SizedBox(height: 20),

              // Usage card
              if (widget.lesson.usage.isNotEmpty) ...[
                const KickerText('Usage'),
                const SizedBox(height: 8),
                PasseportCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: widget.lesson.usage.map((point) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '  •  ',
                              style: DesignTokens.body(
                                14,
                              ).copyWith(color: DesignTokens.info),
                            ),
                            Expanded(
                              child: Text(point, style: DesignTokens.body(14)),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 24),
              ],

              // Conjugation tables
              if (widget.lesson.conjugations.isNotEmpty) ...[
                const KickerText('Conjugations'),
                const SizedBox(height: 8),
                ...widget.lesson.conjugations.map(
                  (conj) => Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: _ConjugationTable(conjugation: conj),
                  ),
                ),
                const SizedBox(height: 8),
              ],

              // Examples
              if (widget.lesson.examples.isNotEmpty) ...[
                const KickerText('Examples'),
                const SizedBox(height: 8),
                PasseportCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: widget.lesson.examples.map((ex) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    ex.fr,
                                    style: DesignTokens.body(
                                      14,
                                      weight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    ex.en,
                                    style: DesignTokens.body(
                                      13,
                                    ).copyWith(color: DesignTokens.slateDim),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                CupertinoIcons.speaker_2_fill,
                                color: DesignTokens.info,
                              ),
                              onPressed: () {
                                LessonSpeechService.shared.speak(
                                  items: [
                                    SpeechItem(text: ex.fr, language: 'fr-FR'),
                                  ],
                                );
                              },
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 24),
              ],

              // Drills
              if (widget.lesson.drills.isNotEmpty) ...[
                const KickerText('Practice'),
                const SizedBox(height: 8),
                ...List.generate(widget.lesson.drills.length, (i) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _DrillWidget(
                      drill: widget.lesson.drills[i],
                      selectedAnswer: _drillAnswers[i],
                      isChecked: _drillChecked[i] ?? false,
                      lessonContext: _lessonContext,
                      onSelect: _drillsSubmitted
                          ? null
                          : (answer) {
                              setState(() => _drillAnswers[i] = answer);
                            },
                    ),
                  );
                }),
                const SizedBox(height: 8),
                if (!_drillsSubmitted)
                  PasseportPrimaryButton(
                    label: 'Check Answers',
                    onPressed: _allDrillsAnswered ? _submitDrills : null,
                  )
                else
                  _DrillResultBanner(score: _drillScore),
                const SizedBox(height: 32),
              ],
              const SizedBox(height: 64),
            ],
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _NarrationControlBar(
              isPlaying: _isPlaying,
              onToggle: _togglePlayback,
            ),
          ),
        ],
      ),
    );
  }
}

// -- Narration control bar --

class _NarrationControlBar extends StatelessWidget {
  const _NarrationControlBar({required this.isPlaying, required this.onToggle});

  final bool isPlaying;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: DesignTokens.card,
        boxShadow: [
          BoxShadow(
            color: DesignTokens.ink.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onToggle,
              child: Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  color: DesignTokens.primary,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isPlaying
                      ? CupertinoIcons.pause_fill
                      : CupertinoIcons.play_fill,
                  color: DesignTokens.parchment,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              isPlaying ? 'Narrating…' : 'Play lesson',
              style: DesignTokens.body(14, weight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}

// -- Conjugation table widget --

class _ConjugationTable extends StatelessWidget {
  const _ConjugationTable({required this.conjugation});

  final Conjugation conjugation;

  @override
  Widget build(BuildContext context) {
    return PasseportCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Verb name + group
          Row(
            children: [
              Text(
                conjugation.verb,
                style: DesignTokens.display(18, weight: FontWeight.w600),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: DesignTokens.info.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  conjugation.group,
                  style: DesignTokens.mono(
                    10,
                    weight: FontWeight.w500,
                  ).copyWith(color: DesignTokens.info),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Rows
          Table(
            columnWidths: const {0: FlexColumnWidth(2), 1: FlexColumnWidth(3)},
            children: conjugation.rows.map((row) {
              return TableRow(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      row.pronoun,
                      style: DesignTokens.body(
                        14,
                        weight: FontWeight.w500,
                      ).copyWith(color: DesignTokens.slateDim),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      row.form,
                      style: DesignTokens.body(14, weight: FontWeight.w500),
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// -- Drill widget --

class _DrillWidget extends ConsumerStatefulWidget {
  const _DrillWidget({
    required this.drill,
    required this.selectedAnswer,
    required this.isChecked,
    required this.lessonContext,
    required this.onSelect,
  });

  final Drill drill;
  final String? selectedAnswer;
  final bool isChecked;
  final String lessonContext;
  final ValueChanged<String>? onSelect;

  @override
  ConsumerState<_DrillWidget> createState() => _DrillWidgetState();
}

class _DrillWidgetState extends ConsumerState<_DrillWidget> {
  String? _explanation;
  bool _isExplaining = false;

  Drill get drill => widget.drill;
  String? get selectedAnswer => widget.selectedAnswer;
  bool get isChecked => widget.isChecked;

  bool get _isWrong => isChecked && selectedAnswer != drill.answer;

  Future<void> _explain() async {
    setState(() => _isExplaining = true);
    try {
      final text = await ref
          .read(lessonAgentServiceProvider)
          .quizFeedback(
            question: drill.prompt,
            correctAnswer: drill.answer,
            studentAnswer: selectedAnswer ?? '',
            lessonContext: widget.lessonContext,
          );
      if (!mounted) return;
      setState(() {
        _explanation = text;
        _isExplaining = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _explanation = e.toString();
        _isExplaining = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PasseportCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            drill.prompt,
            style: DesignTokens.body(15, weight: FontWeight.w500),
          ),
          const SizedBox(height: 12),
          if (drill.type == 'fill' && drill.choices.isEmpty)
            _buildFillIn()
          else
            _buildChoices(),
          if (_isWrong) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Spacer(),
                GestureDetector(
                  onTap: _isExplaining ? null : _explain,
                  child: Text(
                    _isExplaining ? '…' : 'Explain',
                    style: DesignTokens.mono(
                      10.5,
                      weight: FontWeight.w500,
                    ).copyWith(color: DesignTokens.primary),
                  ),
                ),
              ],
            ),
            if (_explanation != null) ...[
              const SizedBox(height: 2),
              Text(
                _explanation!,
                style: DesignTokens.body(
                  12,
                ).copyWith(color: DesignTokens.slateDim),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildFillIn() {
    final isCorrect = isChecked && selectedAnswer == drill.answer;
    final isWrong = isChecked && selectedAnswer != drill.answer;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isChecked
                ? (isCorrect
                      ? DesignTokens.success.withValues(alpha: 0.08)
                      : DesignTokens.primary.withValues(alpha: 0.08))
                : DesignTokens.parchmentDim,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isChecked
                  ? (isCorrect ? DesignTokens.success : DesignTokens.primary)
                  : DesignTokens.hairline,
            ),
          ),
          child: Text(
            selectedAnswer ?? '...',
            style: DesignTokens.body(14).copyWith(
              color: selectedAnswer != null
                  ? DesignTokens.text
                  : DesignTokens.slate,
            ),
          ),
        ),
        if (isWrong) ...[
          const SizedBox(height: 6),
          Text(
            'Correct: ${drill.answer}',
            style: DesignTokens.body(
              13,
              weight: FontWeight.w500,
            ).copyWith(color: DesignTokens.success),
          ),
        ],
      ],
    );
  }

  Widget _buildChoices() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: drill.choices.map((choice) {
        final isSelected = selectedAnswer == choice;
        final isCorrectAnswer = choice == drill.answer;

        Color bg = DesignTokens.parchmentDim;
        Color border = DesignTokens.hairline;
        Color textColor = DesignTokens.text;

        if (isChecked) {
          if (isCorrectAnswer) {
            bg = DesignTokens.success.withValues(alpha: 0.1);
            border = DesignTokens.success;
            textColor = DesignTokens.success;
          } else if (isSelected && !isCorrectAnswer) {
            bg = DesignTokens.primary.withValues(alpha: 0.1);
            border = DesignTokens.primary;
            textColor = DesignTokens.primary;
          }
        } else if (isSelected) {
          bg = DesignTokens.info.withValues(alpha: 0.12);
          border = DesignTokens.info;
        }

        return GestureDetector(
          onTap: widget.onSelect != null
              ? () => widget.onSelect!(choice)
              : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: border, width: 1),
            ),
            child: Text(
              choice,
              style: DesignTokens.body(
                14,
                weight: FontWeight.w500,
              ).copyWith(color: textColor),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// -- Drill result banner --

class _DrillResultBanner extends StatelessWidget {
  const _DrillResultBanner({required this.score});

  final double score;

  @override
  Widget build(BuildContext context) {
    final passed = score >= 0.8;
    final pct = (score * 100).round();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: passed
            ? DesignTokens.success.withValues(alpha: 0.08)
            : DesignTokens.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: passed ? DesignTokens.success : DesignTokens.primary,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            passed
                ? CupertinoIcons.checkmark_circle_fill
                : CupertinoIcons.info_circle,
            color: passed ? DesignTokens.success : DesignTokens.primary,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              passed
                  ? 'Lesson complete! $pct% correct.'
                  : '$pct% correct. Need 80% to complete.',
              style: DesignTokens.body(14, weight: FontWeight.w500).copyWith(
                color: passed ? DesignTokens.success : DesignTokens.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
