import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../design/tokens.dart';
import '../../models/content_models.dart';
import '../../providers/database_provider.dart';
import '../../widgets/passeport_card.dart';
import '../../widgets/kicker_text.dart';
import '../../widgets/passeport_primary_button.dart';
import '../../services/lesson_speech_service.dart';
import '../../widgets/lesson_qa_overlay.dart';
import '../../widgets/marie_toolbar_button.dart';

class ListeningExerciseScreen extends ConsumerStatefulWidget {
  const ListeningExerciseScreen({super.key, required this.exercise});

  final ListeningExercise exercise;

  @override
  ConsumerState<ListeningExerciseScreen> createState() =>
      _ListeningExerciseScreenState();
}

class _ListeningExerciseScreenState
    extends ConsumerState<ListeningExerciseScreen> {
  bool _showScript = false;
  final Map<int, int> _answers = {};
  final Map<int, String> _dictationInputs = {};
  final Map<int, String> _dictationFeedback = {};
  final Set<int> _dictationChecking = {};
  late DateTime _sessionStart;

  ListeningExercise get exercise => widget.exercise;

  String get _lessonContext =>
      ref.read(contentServiceProvider).listeningExerciseContext(exercise);

  double get _score {
    if (exercise.questions.isEmpty) return 0;
    final correct = exercise.questions.asMap().entries.where((e) {
      return _answers[e.key] == e.value.answerIndex;
    }).length;
    return correct / exercise.questions.length;
  }

  bool get _allQuestionsAnswered {
    return exercise.questions.isNotEmpty &&
        _answers.length == exercise.questions.length;
  }

  @override
  void initState() {
    super.initState();
    _sessionStart = DateTime.now();
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
        title: Text(exercise.title, style: DesignTokens.display(18)),
        backgroundColor: DesignTokens.parchmentDim,
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
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        children: [
          _playbackCard(),
          if (exercise.questions.isNotEmpty) ...[
            const SizedBox(height: 16),
            _questionsCard(),
          ],
          if (exercise.dictation.isNotEmpty) ...[
            const SizedBox(height: 16),
            _dictationCard(),
          ],
          if (_allQuestionsAnswered) ...[
            const SizedBox(height: 16),
            PasseportPrimaryButton(
              label: 'Finish exercise',
              onPressed: _finish,
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // -- Playback card --

  Widget _playbackCard() {
    return PasseportCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const KickerText('Listen', color: DesignTokens.slateDim),
          const SizedBox(height: 10),
          Row(
            children: [
              _speedButton('Slow', CupertinoIcons.speedometer, 0.32),
              const SizedBox(width: 12),
              _speedButton('Normal', CupertinoIcons.play_fill, 0.48),
            ],
          ),
          const SizedBox(height: 8),
          if (_showScript)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(exercise.script, style: DesignTokens.body(13)),
            )
          else
            TextButton(
              onPressed: () => setState(() => _showScript = true),
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
              child: Text(
                'Show script',
                style: DesignTokens.mono(
                  11,
                  weight: FontWeight.w500,
                ).copyWith(color: DesignTokens.primary),
              ),
            ),
        ],
      ),
    );
  }

  Widget _speedButton(String label, IconData icon, double rate) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        LessonSpeechService.shared.speak(
          items: [SpeechItem(text: exercise.script, language: 'fr-FR')],
          rate: rate,
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: DesignTokens.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: DesignTokens.primary),
            const SizedBox(width: 6),
            Text(
              label,
              style: DesignTokens.body(
                12.5,
                weight: FontWeight.w500,
              ).copyWith(color: DesignTokens.primary),
            ),
          ],
        ),
      ),
    );
  }

  // -- Questions card --

  Widget _questionsCard() {
    return PasseportCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const KickerText('Comprehension', color: DesignTokens.slateDim),
          const SizedBox(height: 14),
          for (var qi = 0; qi < exercise.questions.length; qi++) ...[
            _questionBlock(qi, exercise.questions[qi]),
            if (qi < exercise.questions.length - 1)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Divider(color: DesignTokens.hairline, height: 1),
              ),
          ],
        ],
      ),
    );
  }

  Widget _questionBlock(int qi, MultipleChoiceQuestion question) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          question.q,
          style: DesignTokens.body(13.5, weight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        for (var ci = 0; ci < question.choices.length; ci++)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: GestureDetector(
              onTap: _answers[qi] == null
                  ? () => setState(() => _answers[qi] = ci)
                  : null,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: DesignTokens.parchmentDim,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        question.choices[ci],
                        style: DesignTokens.body(12.5),
                      ),
                    ),
                    if (_answers[qi] != null) ...[
                      if (ci == question.answerIndex)
                        const Icon(
                          CupertinoIcons.checkmark_circle_fill,
                          color: DesignTokens.success,
                          size: 18,
                        )
                      else if (ci == _answers[qi])
                        Icon(
                          CupertinoIcons.xmark_circle_fill,
                          color: DesignTokens.primary,
                          size: 18,
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  // -- Dictation card --

  Widget _dictationCard() {
    return PasseportCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const KickerText('Dictation', color: DesignTokens.slateDim),
          const SizedBox(height: 14),
          for (var i = 0; i < exercise.dictation.length; i++) ...[
            _dictationBlock(i, exercise.dictation[i]),
            if (i < exercise.dictation.length - 1)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Divider(color: DesignTokens.hairline, height: 1),
              ),
          ],
        ],
      ),
    );
  }

  Widget _dictationBlock(int i, String sentence) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Play sentence button (no-op for now)
        GestureDetector(
          onTap: () {
            LessonSpeechService.shared.speak(
              items: [SpeechItem(text: sentence, language: 'fr-FR')],
            );
          },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                CupertinoIcons.speaker_2_fill,
                size: 14,
                color: DesignTokens.info,
              ),
              const SizedBox(width: 6),
              Text(
                'Play sentence ${i + 1}',
                style: DesignTokens.mono(
                  11,
                  weight: FontWeight.w500,
                ).copyWith(color: DesignTokens.info),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          onChanged: (val) => _dictationInputs[i] = val,
          style: DesignTokens.body(13),
          cursorColor: DesignTokens.primary,
          decoration: InputDecoration(
            hintText: 'Type what you hear...',
            hintStyle: DesignTokens.body(
              13,
            ).copyWith(color: DesignTokens.slate),
            filled: true,
            fillColor: DesignTokens.parchmentDim,
            contentPadding: const EdgeInsets.all(10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: _dictationChecking.contains(i)
              ? null
              : () => _checkDictation(i, sentence),
          child: _dictationChecking.contains(i)
              ? const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: DesignTokens.primary,
                  ),
                )
              : Text(
                  'Check',
                  style: DesignTokens.mono(
                    10.5,
                    weight: FontWeight.w500,
                  ).copyWith(color: DesignTokens.primary),
                ),
        ),
        if (_dictationFeedback[i] != null) ...[
          const SizedBox(height: 4),
          Text(
            _dictationFeedback[i]!,
            style: DesignTokens.body(12).copyWith(color: DesignTokens.slateDim),
          ),
        ],
      ],
    );
  }

  // -- Dictation check (AI feedback via OpenRouter, falls back to a plain match check) --

  Future<void> _checkDictation(int index, String expected) async {
    final submitted = _dictationInputs[index] ?? '';
    if (submitted.trim().isEmpty) {
      setState(
        () => _dictationFeedback[index] = 'Type your answer, then tap Check.',
      );
      return;
    }
    if (_normalize(expected) == _normalize(submitted)) {
      setState(() => _dictationFeedback[index] = 'Perfect match!');
      return;
    }

    setState(() => _dictationChecking.add(index));
    try {
      final feedback = await ref
          .read(lessonAgentServiceProvider)
          .checkDictation(expected: expected, submitted: submitted);
      if (!mounted) return;
      setState(() {
        _dictationFeedback[index] = feedback;
        _dictationChecking.remove(index);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _dictationFeedback[index] = 'Not quite, expected: "$expected"';
        _dictationChecking.remove(index);
      });
    }
  }

  String _normalize(String text) {
    // Remove diacritics via decomposition, lowercase, strip punctuation
    final decomposed = text.toLowerCase().trim();
    final noPunctuation = decomposed.replaceAll(RegExp(r'[.!?,;]'), '');
    return noPunctuation.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  // -- Finish --

  void _finish() {
    final store = ref.read(learningStoreProvider);
    final minutes = DateTime.now()
        .difference(_sessionStart)
        .inMinutes
        .clamp(1, 999);
    store.markHabit('listening', done: true, minutes: minutes);
    store.setLessonStatus(
      'listening_${exercise.id}',
      _score >= 0.6 ? 'completed' : 'in_progress',
      score: _score,
    );
    Navigator.pop(context);
  }
}
