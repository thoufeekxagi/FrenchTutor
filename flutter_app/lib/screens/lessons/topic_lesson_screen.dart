import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/theme.dart';
import '../../widgets/passeport_card.dart';
import '../../widgets/kicker_text.dart';
import '../../widgets/passeport_primary_button.dart';
import '../../providers/database_provider.dart';
import '../../models/content_models.dart';
import '../../services/lesson_speech_service.dart';
import '../../widgets/lesson_qa_overlay.dart';

class TopicLessonScreen extends ConsumerStatefulWidget {
  const TopicLessonScreen({super.key, required this.topic});

  final GrammarTopic topic;

  @override
  ConsumerState<TopicLessonScreen> createState() => _TopicLessonScreenState();
}

class _TopicLessonScreenState extends ConsumerState<TopicLessonScreen> {
  // Drill state
  final Map<int, String?> _drillAnswers = {};
  final Map<int, bool> _drillChecked = {};
  bool _drillsSubmitted = false;
  bool _isPlaying = false;

  String get _lessonContext {
    final topic = widget.topic;
    final narration = topic.narration.join(' ');
    return '${topic.title}\n$narration';
  }

  double get _drillScore {
    if (widget.topic.drills.isEmpty) return 1.0;
    int correct = 0;
    for (int i = 0; i < widget.topic.drills.length; i++) {
      if (_drillChecked[i] == true && _drillAnswers[i] == widget.topic.drills[i].answer) {
        correct++;
      }
    }
    return correct / widget.topic.drills.length;
  }

  bool get _allDrillsAnswered {
    return _drillAnswers.length == widget.topic.drills.length &&
        _drillAnswers.values.every((v) => v != null);
  }

  void _submitDrills() {
    setState(() {
      for (int i = 0; i < widget.topic.drills.length; i++) {
        _drillChecked[i] = true;
      }
      _drillsSubmitted = true;
    });

    final store = ref.read(learningStoreProvider);
    final score = _drillScore;
    final status = score >= 0.8 ? 'completed' : 'in_progress';
    store.setLessonStatus(widget.topic.id, status, score: score);
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
        items: LessonSpeechService.speechItemsFromLines(widget.topic.narration),
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
      backgroundColor: Passeport.parchmentDim,
      appBar: AppBar(
        title: Text(widget.topic.title, style: Passeport.display(20)),
        backgroundColor: Passeport.parchmentDim,
        foregroundColor: Passeport.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          IconButton(
            onPressed: () => LessonQAOverlay.show(context, lessonContext: _lessonContext),
            icon: const Icon(Icons.mic, color: Passeport.brass),
          ),
        ],
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
            children: [
              // Topic sections
              ...widget.topic.sections.map((section) => Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: _TopicSectionWidget(section: section),
                  )),

              // Drills
              if (widget.topic.drills.isNotEmpty) ...[
                const SizedBox(height: 4),
                const KickerText('Practice'),
                const SizedBox(height: 8),
                ...List.generate(widget.topic.drills.length, (i) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _DrillWidget(
                      drill: widget.topic.drills[i],
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
        color: Passeport.card,
        boxShadow: [
          BoxShadow(
            color: Passeport.ink.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            InkWell(
              onTap: onToggle,
              borderRadius: BorderRadius.circular(24),
              child: Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  color: Passeport.maroon,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isPlaying ? Icons.pause : Icons.play_arrow,
                  color: Passeport.parchment,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              isPlaying ? 'Narrating…' : 'Play lesson',
              style: Passeport.body(14, weight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}

// -- Topic section widget --

class _TopicSectionWidget extends StatelessWidget {
  const _TopicSectionWidget({required this.section});

  final TopicSection section;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        KickerText(section.heading),
        const SizedBox(height: 8),
        PasseportCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Body text
              Text(
                section.body,
                style: Passeport.body(14).copyWith(height: 1.5),
              ),
              // Examples
              if (section.examples.isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(height: 1, color: Passeport.hairline),
                const SizedBox(height: 12),
                ...section.examples.map((ex) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  ex.fr,
                                  style: Passeport.body(14, weight: FontWeight.w600),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  ex.en,
                                  style: Passeport.body(13).copyWith(color: Passeport.slateDim),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.volume_up, color: Passeport.brass),
                            onPressed: () {
                              LessonSpeechService.shared.speak(
                                items: [SpeechItem(text: ex.fr, language: 'fr-FR')],
                              );
                            },
                          ),
                        ],
                      ),
                    )),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// -- Drill widget (same as GrammarLessonScreen) --

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
      final text = await ref.read(lessonAgentServiceProvider).quizFeedback(
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
            style: Passeport.body(15, weight: FontWeight.w500),
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
                    style: Passeport.mono(10.5, weight: FontWeight.w500).copyWith(color: Passeport.maroon),
                  ),
                ),
              ],
            ),
            if (_explanation != null) ...[
              const SizedBox(height: 2),
              Text(
                _explanation!,
                style: Passeport.body(12).copyWith(color: Passeport.slateDim),
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
                    ? const Color(0xFF3A7D44).withValues(alpha: 0.08)
                    : Passeport.maroon.withValues(alpha: 0.08))
                : Passeport.parchmentDim,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isChecked
                  ? (isCorrect ? const Color(0xFF3A7D44) : Passeport.maroon)
                  : Passeport.hairline,
            ),
          ),
          child: Text(
            selectedAnswer ?? '...',
            style: Passeport.body(14).copyWith(
              color: selectedAnswer != null ? Passeport.text : Passeport.slate,
            ),
          ),
        ),
        if (isWrong) ...[
          const SizedBox(height: 6),
          Text(
            'Correct: ${drill.answer}',
            style: Passeport.body(13, weight: FontWeight.w500).copyWith(
              color: const Color(0xFF3A7D44),
            ),
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

        Color bg = Passeport.parchmentDim;
        Color border = Passeport.hairline;
        Color textColor = Passeport.text;

        if (isChecked) {
          if (isCorrectAnswer) {
            bg = const Color(0xFF3A7D44).withValues(alpha: 0.1);
            border = const Color(0xFF3A7D44);
            textColor = const Color(0xFF3A7D44);
          } else if (isSelected && !isCorrectAnswer) {
            bg = Passeport.maroon.withValues(alpha: 0.1);
            border = Passeport.maroon;
            textColor = Passeport.maroon;
          }
        } else if (isSelected) {
          bg = Passeport.brass.withValues(alpha: 0.12);
          border = Passeport.brass;
        }

        return GestureDetector(
          onTap: widget.onSelect != null ? () => widget.onSelect!(choice) : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: border, width: 1),
            ),
            child: Text(
              choice,
              style: Passeport.body(14, weight: FontWeight.w500).copyWith(color: textColor),
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
            ? const Color(0xFF3A7D44).withValues(alpha: 0.08)
            : Passeport.maroon.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: passed ? const Color(0xFF3A7D44) : Passeport.maroon,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            passed ? Icons.check_circle_rounded : Icons.info_outline_rounded,
            color: passed ? const Color(0xFF3A7D44) : Passeport.maroon,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              passed
                  ? 'Topic complete! $pct% correct.'
                  : '$pct% correct. Need 80% to complete.',
              style: Passeport.body(14, weight: FontWeight.w500).copyWith(
                color: passed ? const Color(0xFF3A7D44) : Passeport.maroon,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
