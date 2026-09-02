import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/grammar_curriculum_catalog.dart';
import '../../design/tokens.dart';
import '../../models/grammar_course_v2.dart';
import '../../providers/database_provider.dart';
import '../../prompts/live_prompts.dart';
import '../../services/inline_call_controller.dart';
import '../../services/lesson_speech_service.dart';
import '../../widgets/inline_call_bar.dart';
import '../../widgets/tts_play_button.dart';
import '../../widgets/web/web_constrained_view.dart';

class GrammarV2LessonResult {
  const GrammarV2LessonResult({
    required this.lessonId,
    required this.correct,
    required this.attempted,
  });

  final String lessonId;
  final int correct;
  final int attempted;
}

/// A bounded, no-typing Grammar session. Each mode has one deterministic task
/// for a frozen curriculum card; a new card is selected from the home grid for
/// the next practice turn. Audio is warmed for every visible sentence before
/// the learner reaches the speaker control.
class GrammarV2LessonScreen extends ConsumerStatefulWidget {
  const GrammarV2LessonScreen({
    super.key,
    required this.lesson,
    required this.mode,
    this.warmupLessons = const [],
  });

  final GrammarCurriculumLesson lesson;
  final GrammarV2Mode mode;
  final List<GrammarCurriculumLesson> warmupLessons;

  @override
  ConsumerState<GrammarV2LessonScreen> createState() =>
      _GrammarV2LessonScreenState();
}

class _GrammarV2LessonScreenState extends ConsumerState<GrammarV2LessonScreen>
    with WidgetsBindingObserver {
  late final List<String> _wordBank;
  late final List<String> _choiceBank;
  final List<String> _builtSentence = [];
  String? _selectedChoice;
  bool _showTranslations = true;
  bool _showHint = false;
  bool? _correct;
  InlineCallController? _call;

  bool get _isCompleteMode => widget.mode == GrammarV2Mode.complete;
  bool get _isRoleplayMode => widget.mode == GrammarV2Mode.roleplay;
  String get _target => widget.lesson.sentence;

  List<String> get _roleplayChoices {
    // Keep Roleplay bounded to the same validated forms as Guided. A choice
    // such as “ne / pas” is not always a literal substring of the finished
    // sentence, so replacing text would create a misleading distractor.
    final choices = _choiceBank.take(3).toList();
    if (!choices.contains(widget.lesson.pickAnswer) && choices.isNotEmpty) {
      choices[choices.length - 1] = widget.lesson.pickAnswer;
    }
    return choices;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _wordBank = [...widget.lesson.sentenceTiles]
      ..shuffle(math.Random(widget.lesson.id.hashCode));
    _choiceBank = [...widget.lesson.pickChoices]
      ..shuffle(math.Random('${widget.lesson.id}:choices'.hashCode));
    _call = InlineCallController(
      sessionType: LiveSessionType.grammarStage,
      lessonContext: _lessonContext,
      learningStoreForProfile: ref.read(learningStoreProvider),
      onChanged: () {
        if (mounted) setState(() {});
      },
      manualLearnerTurns: false,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_prewarmAudio());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _call?.handleAppLifecycle(state);
  }

  @override
  void dispose() {
    unawaited(LessonSpeechService.shared.stop());
    WidgetsBinding.instance.removeObserver(this);
    _call?.dispose();
    super.dispose();
  }

  String _lessonContext() {
    final selected = _selectedChoice ?? '(none)';
    final built = _builtSentence.isEmpty ? '(empty)' : _builtSentence.join(' ');
    return '''Grammar V2 lesson: ${widget.lesson.title}
LEVEL: ${widget.lesson.level}
FOCUS: ${widget.lesson.generationPoint}
MODE: ${widget.mode.label}
PROMPT: ${widget.lesson.pickPrompt}
TARGET SENTENCE: ${widget.lesson.sentence}
CURRENT CHOICE: $selected
CURRENT BUILT SENTENCE: $built
The learner is selecting a frozen answer. Keep help short and grounded in this exact lesson; do not invent a different sentence.''';
  }

  Future<void> _prewarmAudio() async {
    final lessons = <GrammarCurriculumLesson>[
      widget.lesson,
      for (final lesson in widget.warmupLessons)
        if (lesson.id != widget.lesson.id) lesson,
    ];
    final items = <SpeechItem>[];
    for (final lesson in lessons) {
      if (lesson.sentence.trim().isNotEmpty) {
        items.add(
          SpeechItem(
            text: lesson.sentence,
            language: 'fr-FR',
            contentItemId: _audioId(lesson, 'target'),
          ),
        );
      }
      if (lesson.incorrectSentence.trim().isNotEmpty) {
        items.add(
          SpeechItem(
            text: lesson.incorrectSentence,
            language: 'fr-FR',
            contentItemId: _audioId(lesson, 'partner'),
          ),
        );
      }
      if (_isRoleplayMode) {
        for (var index = 0; index < lesson.pickChoices.length; index++) {
          final choice = lesson.pickChoices[index];
          if (choice.trim().isEmpty) continue;
          items.add(
            SpeechItem(
              text: choice,
              language: 'fr-FR',
              contentItemId: _audioId(lesson, 'choice-$index'),
            ),
          );
        }
      }
    }
    if (items.isEmpty) return;
    try {
      await LessonSpeechService.shared.prewarmNarration(items);
    } catch (error) {
      debugPrint('Grammar V2 audio prewarm skipped: $error');
    }
  }

  String _audioId(GrammarCurriculumLesson lesson, String role) =>
      'grammar-v2:${lesson.id}:$role';

  void _selectChoice(String choice) {
    if (_correct != null) return;
    setState(() {
      _selectedChoice = choice;
      _correct = null;
    });
  }

  void _addWord(String word) {
    if (_correct != null) return;
    final used = _builtSentence.where((item) => item == word).length;
    final available = _wordBank.where((item) => item == word).length;
    if (used >= available) return;
    setState(() => _builtSentence.add(word));
  }

  void _removeWord(int index) {
    if (_correct != null) return;
    setState(() {
      _builtSentence.removeAt(index);
      _correct = null;
    });
  }

  bool _wordIsAvailable(String word) {
    final used = _builtSentence.where((item) => item == word).length;
    final available = _wordBank.where((item) => item == word).length;
    return used < available;
  }

  void _check() {
    final answer = _normalise(
      _isCompleteMode ? _builtSentence.join(' ') : _selectedChoice ?? '',
    );
    final target = _isCompleteMode
        ? _normalise(_target)
        : _normalise(widget.lesson.pickAnswer);
    setState(() => _correct = answer == target);
  }

  String _normalise(String value) => value
      .toLowerCase()
      .replaceAllMapped(RegExp(r'\s+([,.!?;:])'), (match) => match.group(1)!)
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  Future<void> _finish() async {
    final attempted = _correct == null ? 0 : 1;
    final score = _correct == true ? 1.0 : 0.0;
    ref
        .read(learningStoreProvider)
        .setLessonStatus(
          widget.lesson.progressId,
          _correct == true ? 'completed' : 'in_progress',
          score: score,
        );
    if (!mounted) return;
    Navigator.of(context).pop(
      GrammarV2LessonResult(
        lessonId: widget.lesson.id,
        correct: _correct == true ? 1 : 0,
        attempted: attempted,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DesignTokens.canvas,
      body: SafeArea(
        child: WebConstrainedView(
          child: Column(
            children: [
              _header(context),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 22, 20, 26),
                  children: [
                    _modeLabel(),
                    const SizedBox(height: 11),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            _heading,
                            style: DesignTokens.display(31),
                          ),
                        ),
                        const SizedBox(width: 6),
                        if (_call != null)
                          InlineCallActions(
                            controller: _call!,
                            accentColor: DesignTokens.primary,
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _subheading,
                      style: DesignTokens.body(
                        16,
                      ).copyWith(color: DesignTokens.muted, height: 1.4),
                    ),
                    const SizedBox(height: 20),
                    _exercise(),
                    const SizedBox(height: 20),
                    _supportRow(),
                    if (_showHint) ...[const SizedBox(height: 12), _hintCard()],
                    if (_correct != null) ...[
                      const SizedBox(height: 16),
                      _feedbackCard(),
                    ],
                  ],
                ),
              ),
              _bottomAction(),
            ],
          ),
        ),
      ),
    );
  }

  String get _heading => switch (widget.mode) {
    GrammarV2Mode.guided => 'Fix the form',
    GrammarV2Mode.complete => 'Build the sentence',
    GrammarV2Mode.roleplay => 'Choose your reply',
  };

  String get _subheading => switch (widget.mode) {
    GrammarV2Mode.guided => widget.lesson.pickPrompt,
    GrammarV2Mode.complete => widget.lesson.translation,
    GrammarV2Mode.roleplay => 'Use the right grammar in this short exchange.',
  };

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 12, 0),
      child: Column(
        children: [
          SizedBox(
            height: 54,
            child: Row(
              children: [
                Semantics(
                  button: true,
                  label: 'Close grammar lesson',
                  child: IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(CupertinoIcons.xmark),
                    color: DesignTokens.ink,
                  ),
                ),
                Expanded(
                  child: Text(
                    widget.lesson.title,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    style: DesignTokens.display(18),
                  ),
                ),
                SizedBox(
                  width: 58,
                  child: Text(
                    widget.lesson.level,
                    textAlign: TextAlign.end,
                    style: DesignTokens.label(12),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(DesignTokens.radiusPill),
              child: LinearProgressIndicator(
                minHeight: 5,
                value: _correct == null ? 0.35 : 1,
                backgroundColor: DesignTokens.hairline,
                valueColor: AlwaysStoppedAnimation(DesignTokens.primary),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _modeLabel() => Text(
    '${widget.mode.label.toUpperCase()} · ${GrammarV2Tenses.labelFor(widget.lesson).toUpperCase()}',
    style: DesignTokens.label(
      12,
      weight: FontWeight.w800,
    ).copyWith(color: DesignTokens.primary, letterSpacing: 1.1),
  );

  Widget _exercise() => switch (widget.mode) {
    GrammarV2Mode.guided => _guidedExercise(),
    GrammarV2Mode.complete => _completeExercise(),
    GrammarV2Mode.roleplay => _roleplayExercise(),
  };

  Widget _guidedExercise() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PromptCard(
          prompt: widget.lesson.pickPrompt,
          translation: widget.lesson.translation,
          showTranslation: _showTranslations,
          audioText: widget.lesson.sentence,
          contentItemId: _audioId(widget.lesson, 'target'),
        ),
        const SizedBox(height: 18),
        _sectionLabel('CHOOSE THE FORM'),
        const SizedBox(height: 10),
        for (final choice in _choiceBank) ...[
          _ChoiceTile(
            key: ValueKey(
              'grammar-v2-guided-choice-${widget.lesson.id}-$choice',
            ),
            text: choice,
            meaning: GrammarCurriculumCatalog.wordMeaning(choice),
            showMeaning: _showTranslations,
            selected: choice == _selectedChoice,
            correct: _correct == null
                ? null
                : choice == widget.lesson.pickAnswer,
            onTap: () => _selectChoice(choice),
          ),
          const SizedBox(height: 9),
        ],
      ],
    );
  }

  Widget _completeExercise() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AnswerTray(
          words: _builtSentence,
          showTranslations: false,
          onRemove: _removeWord,
          audioText: widget.lesson.sentence,
          contentItemId: _audioId(widget.lesson, 'target'),
        ),
        const SizedBox(height: 18),
        _sectionLabel('WORD BANK'),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 9, children: [..._wordBankChips()]),
        const SizedBox(height: 10),
        Text(
          'Tap the words in the right order.',
          style: DesignTokens.body(14).copyWith(color: DesignTokens.muted),
        ),
      ],
    );
  }

  List<Widget> _wordBankChips() {
    final chips = <Widget>[];
    for (var index = 0; index < _wordBank.length; index++) {
      final word = _wordBank[index];
      if (!_wordIsAvailable(word)) continue;
      chips.add(
        _WordChip(
          key: ValueKey('grammar-v2-word-bank-${widget.lesson.id}-$index'),
          word: word,
          meaning: GrammarCurriculumCatalog.wordMeaning(word),
          showMeaning: _showTranslations,
          onTap: () => _addWord(word),
        ),
      );
    }
    return chips;
  }

  Widget _roleplayExercise() {
    final choices = _roleplayChoices;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PartnerCard(
          french: widget.lesson.incorrectSentence,
          english: widget.lesson.translation,
          showTranslation: _showTranslations,
          audioText: widget.lesson.incorrectSentence,
          contentItemId: _audioId(widget.lesson, 'partner'),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: DesignTokens.primarySoft,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: DesignTokens.primary.withValues(alpha: 0.36),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.track_changes_rounded, color: DesignTokens.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Choose the reply with: ${widget.lesson.tip}',
                  style: DesignTokens.body(14, weight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        for (final choice in choices) ...[
          _ChoiceTile(
            key: ValueKey(
              'grammar-v2-roleplay-choice-${widget.lesson.id}-$choice',
            ),
            text: choice,
            meaning: GrammarCurriculumCatalog.wordMeaning(choice),
            showMeaning: _showTranslations,
            selected: choice == _selectedChoice,
            correct: _correct == null
                ? null
                : choice == widget.lesson.pickAnswer,
            onTap: () => _selectChoice(choice),
          ),
          const SizedBox(height: 9),
        ],
      ],
    );
  }

  Widget _supportRow() {
    return Row(
      children: [
        Expanded(child: _listenAction()),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => setState(() => _showHint = !_showHint),
            icon: Icon(Icons.lightbulb_outline_rounded, size: 20),
            label: const Text('Hint'),
            style: OutlinedButton.styleFrom(
              foregroundColor: DesignTokens.ink,
              side: BorderSide(color: DesignTokens.hairline),
              minimumSize: const Size(0, 50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () =>
                setState(() => _showTranslations = !_showTranslations),
            icon: const Icon(Icons.translate_rounded, size: 20),
            label: Text(_showTranslations ? 'Translate on' : 'Translate'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _showTranslations
                  ? DesignTokens.primary
                  : DesignTokens.ink,
              side: BorderSide(
                color: _showTranslations
                    ? DesignTokens.primary
                    : DesignTokens.hairline,
              ),
              minimumSize: const Size(0, 50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _listenAction() {
    return Container(
      height: 50,
      decoration: BoxDecoration(
        border: Border.all(color: DesignTokens.hairline),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TtsPlayButton(
            text: _isRoleplayMode
                ? widget.lesson.incorrectSentence
                : widget.lesson.sentence,
            contentItemId: _audioId(
              widget.lesson,
              _isRoleplayMode ? 'partner' : 'target',
            ),
            label: 'Listen to the grammar example',
            size: 42,
            iconSize: 20,
            color: DesignTokens.primary,
          ),
          Text('Listen', style: DesignTokens.body(14, weight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _hintCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: DesignTokens.primarySoft,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.tips_and_updates_outlined, color: DesignTokens.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              widget.lesson.tip,
              style: DesignTokens.body(
                14,
                weight: FontWeight.w700,
              ).copyWith(height: 1.35),
            ),
          ),
        ],
      ),
    );
  }

  Widget _feedbackCard() {
    final correct = _correct == true;
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: correct ? DesignTokens.successSoft : DesignTokens.primarySoft,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            correct
                ? Icons.check_circle_outline_rounded
                : Icons.refresh_rounded,
            color: correct ? DesignTokens.success : DesignTokens.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              correct
                  ? 'Correct. ${widget.lesson.tip}'
                  : 'The right sentence is ${widget.lesson.sentence}',
              style: DesignTokens.body(
                14,
                weight: FontWeight.w700,
              ).copyWith(height: 1.35),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bottomAction() {
    final checked = _correct != null;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
      decoration: BoxDecoration(
        color: DesignTokens.canvas,
        border: Border(top: BorderSide(color: DesignTokens.hairline)),
      ),
      child: Row(
        children: [
          if (checked) ...[
            Expanded(
              child: OutlinedButton(
                onPressed: () => setState(() {
                  _correct = null;
                  _selectedChoice = null;
                  _builtSentence.clear();
                }),
                style: OutlinedButton.styleFrom(
                  foregroundColor: DesignTokens.primary,
                  minimumSize: const Size(0, 56),
                  side: BorderSide(color: DesignTokens.primary),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(17),
                  ),
                ),
                child: const Text('Redo'),
              ),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            flex: checked ? 2 : 1,
            child: ElevatedButton(
              onPressed: checked
                  ? _finish
                  : _canCheck
                  ? _check
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: DesignTokens.primary,
                foregroundColor: DesignTokens.onPrimary,
                disabledBackgroundColor: DesignTokens.hairline,
                elevation: 0,
                minimumSize: const Size(0, 56),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(17),
                ),
              ),
              child: Text(
                checked ? 'Next lesson' : _checkLabel,
                style: DesignTokens.body(15, weight: FontWeight.w800).copyWith(
                  color: checked
                      ? DesignTokens.onPrimary
                      : _canCheck
                      ? DesignTokens.onPrimary
                      : DesignTokens.muted,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool get _canCheck =>
      _isCompleteMode ? _builtSentence.isNotEmpty : _selectedChoice != null;

  String get _checkLabel => switch (widget.mode) {
    GrammarV2Mode.guided => 'Check form',
    GrammarV2Mode.complete => 'Check sentence',
    GrammarV2Mode.roleplay => 'Check reply',
  };

  Widget _sectionLabel(String value) => Text(
    value,
    style: DesignTokens.label(
      12,
      weight: FontWeight.w800,
    ).copyWith(color: DesignTokens.primary, letterSpacing: 1.15),
  );
}

class _PromptCard extends StatelessWidget {
  const _PromptCard({
    required this.prompt,
    required this.translation,
    required this.showTranslation,
    required this.audioText,
    required this.contentItemId,
  });

  final String prompt;
  final String translation;
  final bool showTranslation;
  final String audioText;
  final String contentItemId;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 13, 18),
      decoration: BoxDecoration(
        color: DesignTokens.surface,
        borderRadius: BorderRadius.circular(21),
        border: Border.all(color: DesignTokens.hairline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(prompt, style: DesignTokens.display(24)),
                if (showTranslation) ...[
                  const SizedBox(height: 8),
                  Text(
                    translation,
                    style: DesignTokens.body(
                      14,
                    ).copyWith(color: DesignTokens.muted, height: 1.35),
                  ),
                ],
              ],
            ),
          ),
          TtsPlayButton(
            text: audioText,
            contentItemId: contentItemId,
            label: 'Listen to the grammar example',
            color: DesignTokens.primary,
          ),
        ],
      ),
    );
  }
}

class _PartnerCard extends StatelessWidget {
  const _PartnerCard({
    required this.french,
    required this.english,
    required this.showTranslation,
    required this.audioText,
    required this.contentItemId,
  });

  final String french;
  final String english;
  final bool showTranslation;
  final String audioText;
  final String contentItemId;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(17, 15, 12, 15),
      decoration: BoxDecoration(
        color: DesignTokens.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: DesignTokens.hairline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'PARTNER',
                  style: DesignTokens.label(
                    11,
                    weight: FontWeight.w800,
                  ).copyWith(color: DesignTokens.primary, letterSpacing: 1),
                ),
                const SizedBox(height: 8),
                Text(
                  french,
                  style: DesignTokens.body(18, weight: FontWeight.w700),
                ),
                if (showTranslation) ...[
                  const SizedBox(height: 5),
                  Text(
                    english,
                    style: DesignTokens.body(
                      14,
                    ).copyWith(color: DesignTokens.muted),
                  ),
                ],
              ],
            ),
          ),
          TtsPlayButton(
            text: audioText,
            contentItemId: contentItemId,
            label: 'Listen to the partner line',
            color: DesignTokens.primary,
          ),
        ],
      ),
    );
  }
}

class _AnswerTray extends StatelessWidget {
  const _AnswerTray({
    required this.words,
    required this.showTranslations,
    required this.onRemove,
    required this.audioText,
    required this.contentItemId,
  });

  final List<String> words;
  final bool showTranslations;
  final ValueChanged<int> onRemove;
  final String audioText;
  final String contentItemId;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: DesignTokens.durationFast,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: words.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 17),
                    child: Text(
                      'Tap a word to begin.',
                      style: DesignTokens.body(
                        15,
                      ).copyWith(color: DesignTokens.muted),
                    ),
                  )
                : Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (var index = 0; index < words.length; index++)
                        GestureDetector(
                          onTap: () => onRemove(index),
                          child: _AnswerChip(word: words[index]),
                        ),
                    ],
                  ),
          ),
          TtsPlayButton(
            text: audioText,
            contentItemId: contentItemId,
            label: 'Listen to the target sentence',
            color: DesignTokens.primary,
          ),
        ],
      ),
    );
  }
}

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    super.key,
    required this.text,
    required this.meaning,
    required this.showMeaning,
    required this.selected,
    required this.correct,
    required this.onTap,
  });

  final String text;
  final String meaning;
  final bool showMeaning;
  final bool selected;
  final bool? correct;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isCorrect = correct == true && selected;
    final isWrong = correct == false && selected;
    return Semantics(
      button: true,
      selected: selected,
      label: showMeaning ? '$text, $meaning' : text,
      child: InkWell(
        onTap: correct == null ? onTap : null,
        borderRadius: BorderRadius.circular(17),
        child: AnimatedContainer(
          duration: DesignTokens.durationFast,
          padding: const EdgeInsets.fromLTRB(16, 12, 14, 11),
          decoration: BoxDecoration(
            color: isCorrect
                ? DesignTokens.successSoft
                : isWrong
                ? DesignTokens.dangerSoft
                : DesignTokens.surface,
            borderRadius: BorderRadius.circular(17),
            border: Border.all(
              color: isCorrect
                  ? DesignTokens.success
                  : isWrong
                  ? DesignTokens.danger
                  : selected
                  ? DesignTokens.primary
                  : DesignTokens.hairline,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      text,
                      style: DesignTokens.body(17, weight: FontWeight.w700),
                    ),
                    if (showMeaning) ...[
                      const SizedBox(height: 4),
                      Text(
                        '($meaning)',
                        style: DesignTokens.body(
                          13,
                        ).copyWith(color: DesignTokens.muted),
                      ),
                    ],
                  ],
                ),
              ),
              if (isCorrect)
                Icon(Icons.check_circle_outline, color: DesignTokens.success)
              else if (isWrong)
                Icon(Icons.refresh_rounded, color: DesignTokens.danger),
            ],
          ),
        ),
      ),
    );
  }
}

class _WordChip extends StatelessWidget {
  const _WordChip({
    super.key,
    required this.word,
    required this.meaning,
    required this.showMeaning,
    required this.onTap,
  });

  final String word;
  final String meaning;
  final bool showMeaning;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: showMeaning ? '$word, $meaning' : word,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Container(
          padding: EdgeInsets.fromLTRB(15, 10, 15, showMeaning ? 8 : 10),
          decoration: BoxDecoration(
            color: DesignTokens.surface,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: DesignTokens.hairline),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(word, style: DesignTokens.body(16, weight: FontWeight.w700)),
              if (showMeaning) ...[
                const SizedBox(height: 2),
                Text(
                  '($meaning)',
                  style: DesignTokens.body(
                    12,
                  ).copyWith(color: DesignTokens.muted),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AnswerChip extends StatelessWidget {
  const _AnswerChip({required this.word});

  final String word;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: DesignTokens.primarySoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: DesignTokens.primary.withValues(alpha: 0.5)),
      ),
      child: Text(word, style: DesignTokens.body(16, weight: FontWeight.w700)),
    );
  }
}
