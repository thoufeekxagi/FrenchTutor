import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/tokens.dart';
import '../../models/content_models.dart';
import '../../providers/database_provider.dart';
import '../../services/lesson_agent_service.dart';
import '../../services/lesson_speech_service.dart';
import '../../services/session_recorder.dart';
import '../../widgets/learning_card.dart';
import '../../widgets/bilingual_word_text.dart';
import '../../widgets/floating_notetaker.dart';
import '../../widgets/primary_action_button.dart';
import '../../widgets/report_problem_button.dart';
import '../../widgets/web/web_constrained_view.dart';
import 'story_reader_screen.dart';

enum _ListeningStage { firstListen, check, focus, dictation, shadow, recap }

class ListeningPracticeScreen extends ConsumerStatefulWidget {
  const ListeningPracticeScreen({
    super.key,
    required this.story,
    this.showFinishButton = false,
  });

  final GeneratedStory story;
  final bool showFinishButton;

  @override
  ConsumerState<ListeningPracticeScreen> createState() =>
      _ListeningPracticeScreenState();
}

class _ListeningPracticeScreenState
    extends ConsumerState<ListeningPracticeScreen> {
  late final SessionRecorder _recorder;
  final TextEditingController _dictationController = TextEditingController();
  final Map<int, int> _quizAnswers = {};

  _ListeningStage _stage = _ListeningStage.firstListen;
  int _currentSegment = 0;
  int _focusSegment = 0;
  int _questionIndex = 0;
  int? _selectedWordIndex;
  int? _dictationSegment;
  bool _isPlaying = false;
  bool _audioLoading = false;
  bool _hasListened = false;
  bool _showTranslation = false;
  bool _dictationCorrect = false;
  bool _dictationSubmitted = false;
  bool _isRecording = false;
  bool _shadowCorrect = false;
  String _shadowTranscript = '';
  String? _shadowFeedback;
  double _rate = 0.42;
  bool _finishedSession = false;
  Timer? _coverRefreshTimer;

  late GeneratedStory _story;
  List<ReadingSegment> get _segments => _story.passage.segments;
  List<MultipleChoiceQuestion> get _questions => _story.quiz.take(2).toList();
  ReadingSegment get _focusLine =>
      _segments[_focusSegment.clamp(0, _segments.length - 1).toInt()];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(notetakerStateProvider).currentContext = 'Listening';
    });
    _story = widget.story;
    _recorder = SessionRecorder(
      storage: ref.read(storageServiceProvider),
      stage: 'reading_listening',
      topic: _story.displayTitle,
    );
    _dictationSegment = _findDictationSegment();
    if (_story.coverUrl == null || _story.coverUrl!.isEmpty) {
      // Covers are generated independently so opening a lesson never waits
      // for artwork. Keep the already-open headphone card in sync when the
      // private upload finishes in the library screen behind this route.
      _coverRefreshTimer = Timer.periodic(
        const Duration(seconds: 2),
        (_) => _refreshCoverFromStore(),
      );
    }
  }

  @override
  void dispose() {
    _coverRefreshTimer?.cancel();
    _dictationController.dispose();
    unawaited(LessonSpeechService.shared.deactivate());
    _finishSession();
    super.dispose();
  }

  void _refreshCoverFromStore() {
    if (!mounted || _story.coverUrl?.isNotEmpty == true) {
      _coverRefreshTimer?.cancel();
      return;
    }
    GeneratedStory? latest;
    for (final candidate
        in ref
            .read(generatedStoryStoreProvider)
            .list(practiceMode: 'listening')) {
      if (candidate.id == _story.id) {
        latest = candidate;
        break;
      }
    }
    final coverUrl = latest?.coverUrl;
    if (coverUrl == null || coverUrl.isEmpty) return;
    setState(() => _story = _story.copyWith(coverUrl: coverUrl));
    _coverRefreshTimer?.cancel();
  }

  int? _findDictationSegment() {
    for (var index = 0; index < _segments.length; index++) {
      final line = _segments[index].fr.toLowerCase();
      if (_story.keywords.any((word) => line.contains(word.fr.toLowerCase()))) {
        return index;
      }
    }
    return _segments.isEmpty ? null : (_segments.length > 1 ? 1 : 0);
  }

  String _dictationTarget() {
    final index = _dictationSegment;
    if (index == null || _segments.isEmpty) return '';
    final line = _segments[index].fr;
    final keyword = _story.keywords.cast<VocabEntry?>().firstWhere(
      (word) =>
          word != null && line.toLowerCase().contains(word.fr.toLowerCase()),
      orElse: () => null,
    );
    if (keyword != null) return keyword.fr;
    final words = _plainWords(line);
    if (words.isEmpty) return '';
    return words.length > 2 ? words[words.length ~/ 2] : words.first;
  }

  String _dictationPrompt() {
    final index = _dictationSegment;
    if (index == null || _segments.isEmpty) return '';
    final target = _dictationTarget();
    final line = _segments[index].fr;
    final start = line.toLowerCase().indexOf(target.toLowerCase());
    if (target.isEmpty || start < 0) return line;
    return '${line.substring(0, start)}_____'
        '${line.substring(start + target.length)}';
  }

  List<String> _plainWords(String text) => text
      .replaceAll(RegExp(r"[^A-Za-zÀ-ÿ0-9'’-]+"), ' ')
      .split(RegExp(r'\s+'))
      .where((word) => word.trim().isNotEmpty)
      .toList();

  String _normalize(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[.,!?;:«»"()]'), '')
        .replaceAll('à', 'a')
        .replaceAll('â', 'a')
        .replaceAll('ä', 'a')
        .replaceAll('é', 'e')
        .replaceAll('è', 'e')
        .replaceAll('ê', 'e')
        .replaceAll('ë', 'e')
        .replaceAll('î', 'i')
        .replaceAll('ï', 'i')
        .replaceAll('ô', 'o')
        .replaceAll('ö', 'o')
        .replaceAll('ù', 'u')
        .replaceAll('û', 'u')
        .replaceAll('ü', 'u')
        .replaceAll('ç', 'c')
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  Future<void> _playStory({int fromIndex = 0}) async {
    if (_segments.isEmpty || _audioLoading) return;
    _audioLoading = true;
    if (mounted) setState(() {});
    try {
      await LessonSpeechService.shared.stop();
      if (!mounted) return;
      setState(() {
        _isPlaying = true;
        _currentSegment = fromIndex;
      });
      await LessonSpeechService.shared.speak(
        items: [
          for (var index = fromIndex; index < _segments.length; index++)
            SpeechItem(
              text: _segments[index].fr,
              language: 'fr-FR',
              contentItemId: _story.segmentContentId(index),
            ),
        ],
        rate: _rate,
        onItemStart: (index) {
          if (!mounted) return;
          setState(() => _currentSegment = fromIndex + index);
        },
        onPlaybackReady: () {
          if (mounted) setState(() => _audioLoading = false);
        },
        onFinished: () {
          if (!mounted) return;
          setState(() {
            _isPlaying = false;
            _audioLoading = false;
            _hasListened = true;
          });
        },
      );
    } finally {
      if (mounted && _audioLoading) setState(() => _audioLoading = false);
    }
  }

  Future<void> _playLine(int index) async {
    if (index < 0 || index >= _segments.length || _audioLoading) return;
    _audioLoading = true;
    if (mounted) setState(() {});
    try {
      await LessonSpeechService.shared.stop();
      if (!mounted) return;
      setState(() {
        _isPlaying = true;
        _currentSegment = index;
      });
      await LessonSpeechService.shared.speak(
        items: [
          SpeechItem(
            text: _segments[index].fr,
            language: 'fr-FR',
            contentItemId: _story.segmentContentId(index),
          ),
        ],
        rate: _rate,
        onPlaybackReady: () {
          if (mounted) setState(() => _audioLoading = false);
        },
        onFinished: () {
          if (mounted) {
            setState(() {
              _isPlaying = false;
              _audioLoading = false;
            });
          }
        },
      );
    } finally {
      if (mounted && _audioLoading) setState(() => _audioLoading = false);
    }
  }

  Future<void> _togglePlayback() async {
    if (_audioLoading) return;
    final speech = LessonSpeechService.shared;
    if (_isPlaying && !speech.isPaused) {
      await speech.pause();
      if (mounted) setState(() => _isPlaying = false);
      return;
    }
    if (speech.isPaused) {
      await speech.resume();
      if (mounted) setState(() => _isPlaying = true);
      return;
    }
    await _playStory(
      fromIndex: _stage == _ListeningStage.firstListen ? 0 : _currentSegment,
    );
  }

  void _cycleRate() {
    setState(() => _rate = _rate <= 0.36 ? 0.55 : 0.32);
  }

  void _selectQuizAnswer(int answerIndex) {
    setState(() => _quizAnswers[_questionIndex] = answerIndex);
  }

  void _advanceFromCheck() {
    if (_questions.isEmpty || _questionIndex >= _questions.length - 1) {
      setState(() => _stage = _ListeningStage.focus);
      return;
    }
    setState(() => _questionIndex += 1);
  }

  Future<void> _moveFocus(int delta) async {
    if (_segments.isEmpty) return;
    final next = (_focusSegment + delta).clamp(0, _segments.length - 1).toInt();
    if (next == _focusSegment) return;

    // Moving between lines must also stop the previous reply. Otherwise a
    // delayed audio callback can make the newly selected line look finished
    // while the old line is still audible.
    await LessonSpeechService.shared.stop();
    if (!mounted) return;
    setState(() {
      _focusSegment = next;
      _selectedWordIndex = null;
      // Keep the learner's Hide/Translate choice for the whole Focus stage.
      // They can turn it off explicitly on any later line; advancing should
      // not make them repeat the same tap for every sentence.
      _isPlaying = false;
      _audioLoading = false;
    });
  }

  Future<void> _advanceFocus() async {
    if (_focusSegment >= _segments.length - 1) {
      await LessonSpeechService.shared.stop();
      if (mounted) setState(() => _stage = _ListeningStage.dictation);
      return;
    }
    await _moveFocus(1);
  }

  void _submitDictation() {
    final target = _normalize(_dictationTarget());
    final answer = _normalize(_dictationController.text);
    if (answer.isEmpty) return;
    setState(() {
      _dictationSubmitted = true;
      _dictationCorrect = answer == target;
      _stage = _ListeningStage.shadow;
    });
    _recorder.logUser(_dictationController.text);
    _recorder.logTutor('${_dictationPrompt()} → ${_dictationTarget()}');
  }

  Future<void> _toggleShadow() async {
    final speech = LessonSpeechService.shared;
    if (_isRecording) {
      await speech.stopListening();
      return;
    }
    await speech.deactivate();
    if (!mounted) return;
    setState(() {
      _isRecording = true;
      _shadowTranscript = '';
      _shadowFeedback = null;
    });
    await speech.startListening(
      locale: 'fr-FR',
      onPartial: (_) {},
      onFinal: _handleShadowTranscript,
    );
    if (mounted && !speech.isListening) setState(() => _isRecording = false);
  }

  Future<void> _handleShadowTranscript(String transcript) async {
    if (!mounted) return;
    final trimmed = transcript.trim();
    setState(() {
      _isRecording = false;
      _shadowTranscript = trimmed;
    });
    if (trimmed.isEmpty) {
      setState(
        () => _shadowFeedback =
            'I could not hear a clear attempt. Try once more.',
      );
      return;
    }
    _recorder.logUser(trimmed);
    try {
      final judgment = await LessonAgentService.shared
          .judgePronunciationAttempt(
            targetWord: _focusLine.fr,
            studentSaid: trimmed,
          );
      if (!mounted) return;
      setState(() {
        _shadowCorrect = judgment.isCorrect;
        _shadowFeedback = judgment.isCorrect
            ? 'Good match. Your version is clear enough to keep moving.'
            : (judgment.description ??
                  'Listen once more, then repeat the whole line.');
      });
    } catch (_) {
      final match = _roughPhraseMatch(_focusLine.fr, trimmed);
      if (!mounted) return;
      setState(() {
        _shadowCorrect = match;
        _shadowFeedback = match
            ? 'Nice repeat. The key words came through clearly.'
            : 'I heard a different phrase. Replay the line and try again.';
      });
    }
  }

  bool _roughPhraseMatch(String target, String heard) {
    final targetWords = _plainWords(_normalize(target));
    final heardWords = _plainWords(_normalize(heard)).toSet();
    if (targetWords.isEmpty) return false;
    final matches = targetWords.where(heardWords.contains).length;
    return matches / targetWords.length >= 0.6;
  }

  void _finishSession() {
    if (_finishedSession) return;
    _finishedSession = true;
    final correct = _quizAnswers.entries
        .where(
          (entry) =>
              entry.key < _questions.length &&
              entry.value == _questions[entry.key].answerIndex,
        )
        .length;
    _recorder.finish(
      summary:
          'Listened to "${_story.displayTitle}" and caught $correct/${_questions.length} details.',
    );
  }

  void _finishAndPop() {
    _finishSession();
    Navigator.of(context).pop(widget.showFinishButton ? true : null);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DesignTokens.canvas,
      appBar: AppBar(
        title: Text('Listening', style: DesignTokens.display(18)),
        backgroundColor: DesignTokens.canvas,
        foregroundColor: DesignTokens.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          ReportProblemButton(sessionType: 'Listening: ${_story.displayTitle}'),
        ],
      ),
      body: Stack(
        children: [
          WebConstrainedView(
            maxWidth: 760,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
              children: [
                _ListeningHeader(story: _story),
                const SizedBox(height: DesignTokens.space5),
                _StageRail(current: _stage),
                const SizedBox(height: DesignTokens.space5),
                AnimatedSwitcher(
                  duration: DesignTokens.durationMedium,
                  switchInCurve: DesignTokens.curveStandard,
                  child: KeyedSubtree(
                    key: ValueKey(_stage),
                    child: _stageBody(),
                  ),
                ),
              ],
            ),
          ),
          FloatingNotetakerOverlay(state: ref.watch(notetakerStateProvider)),
        ],
      ),
    );
  }

  Widget _stageBody() {
    return switch (_stage) {
      _ListeningStage.firstListen => _firstListenView(),
      _ListeningStage.check => _checkView(),
      _ListeningStage.focus => _focusView(),
      _ListeningStage.dictation => _dictationView(),
      _ListeningStage.shadow => _shadowView(),
      _ListeningStage.recap => _recapView(),
    };
  }

  Widget _firstListenView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StageEyebrow(
          label: '01 · First listen',
          detail: '${_story.levelBand} · ${_story.readTimeMinutes} min',
        ),
        const SizedBox(height: 8),
        Text('Catch the meaning first.', style: DesignTokens.display(28)),
        const SizedBox(height: 8),
        Text(
          'The transcript stays hidden. Listen for who, where, and what changes.',
          style: DesignTokens.body(14).copyWith(color: DesignTokens.mutedDim),
        ),
        const SizedBox(height: DesignTokens.space5),
        _AudioPlayerCard(
          story: _story,
          isPlaying: _isPlaying,
          isLoading: _audioLoading,
          currentSegment: _currentSegment,
          totalSegments: _segments.length,
          rate: _rate,
          onToggle: _togglePlayback,
          onReplay: () => _playStory(),
          onCycleRate: _cycleRate,
        ),
        const SizedBox(height: DesignTokens.space4),
        LearningCard(
          color: DesignTokens.primarySoft,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                CupertinoIcons.headphones,
                color: DesignTokens.primary,
              ),
              const SizedBox(width: DesignTokens.space3),
              Expanded(
                child: Text(
                  _hasListened
                      ? 'Nice. You heard the whole story. Now check what stayed with you.'
                      : 'One clean listen is enough. You can replay after the first check.',
                  style: DesignTokens.body(13, weight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: DesignTokens.space5),
        PrimaryActionButton(
          label: 'Check what I caught',
          icon: CupertinoIcons.arrow_right,
          onPressed: _hasListened
              ? () => setState(() => _stage = _ListeningStage.check)
              : null,
        ),
      ],
    );
  }

  Widget _checkView() {
    if (_questions.isEmpty) {
      return _EmptyStage(
        eyebrow: '02 · Quick check',
        title: 'You are ready for the transcript.',
        body:
            'This story has no saved comprehension questions, so we will move to line-by-line listening.',
        buttonLabel: 'Open the lines',
        onPressed: () => setState(() => _stage = _ListeningStage.focus),
      );
    }
    final question = _questions[_questionIndex];
    final selected = _quizAnswers[_questionIndex];
    final answered = selected != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _StageEyebrow(
          label: '02 · Quick check',
          detail: 'No transcript yet',
        ),
        const SizedBox(height: 8),
        Text('What stayed with you?', style: DesignTokens.display(28)),
        const SizedBox(height: 16),
        LearningCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Question ${_questionIndex + 1} of ${_questions.length}',
                style: DesignTokens.label(
                  11,
                ).copyWith(color: DesignTokens.primary),
              ),
              const SizedBox(height: 10),
              Text(question.q, style: DesignTokens.display(19)),
              if (question.qEn != null && question.qEn!.trim().isNotEmpty) ...[
                const SizedBox(height: 5),
                Text(
                  question.qEn!,
                  style: DesignTokens.body(
                    14,
                  ).copyWith(color: DesignTokens.mutedDim),
                ),
              ],
              const SizedBox(height: 15),
              for (var index = 0; index < question.choices.length; index++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _ChoiceButton(
                    label: question.choices[index],
                    secondaryLabel:
                        question.choicesEn != null &&
                            index < question.choicesEn!.length
                        ? question.choicesEn![index]
                        : null,
                    selected: selected == index,
                    correct: answered && index == question.answerIndex,
                    onTap: () => _selectQuizAnswer(index),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        PrimaryActionButton(
          label: _questionIndex == _questions.length - 1
              ? 'Open the transcript'
              : 'Next question',
          icon: CupertinoIcons.arrow_right,
          onPressed: answered ? _advanceFromCheck : null,
        ),
      ],
    );
  }

  Widget _focusView() {
    final line = _focusLine;
    final words = _plainWords(line.fr);
    final selectedWord =
        _selectedWordIndex != null && _selectedWordIndex! < words.length
        ? words[_selectedWordIndex!]
        : null;
    final wordEntry = selectedWord == null
        ? null
        : _story.keywords.cast<VocabEntry?>().firstWhere(
            (entry) =>
                entry != null &&
                _plainWords(
                  _normalize(entry.fr),
                ).contains(_normalize(selectedWord)),
            orElse: () => null,
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StageEyebrow(
          label: '03 · Tune your ear',
          detail: 'Line ${_focusSegment + 1} of ${_segments.length}',
        ),
        const SizedBox(height: 8),
        Text('Hear it. See it. Replay it.', style: DesignTokens.display(28)),
        const SizedBox(height: 8),
        Text(
          'Tap a word for a quick meaning. Translation stays optional.',
          style: DesignTokens.body(14).copyWith(color: DesignTokens.mutedDim),
        ),
        const SizedBox(height: 16),
        LearningCard(
          color: DesignTokens.ink,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'LINE ${(_focusSegment + 1).toString().padLeft(2, '0')}',
                style: DesignTokens.label(
                  10,
                ).copyWith(color: DesignTokens.primarySoft),
              ),
              const SizedBox(height: 12),
              BilingualWordText(
                source: line.fr,
                translation: _showTranslation ? line.en : '',
                sourceStyle: DesignTokens.display(
                  20,
                ).copyWith(color: Colors.white),
                translationStyle: DesignTokens.body(
                  14,
                ).copyWith(color: Colors.white70),
                keywords: _story.keywords,
                selectedSourceWord: _selectedWordIndex,
                onSourceWordTap: (index) => setState(
                  () => _selectedWordIndex = _selectedWordIndex == index
                      ? null
                      : index,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  _DarkAction(
                    icon: CupertinoIcons.repeat,
                    label: 'Replay',
                    onTap: () => _playLine(_focusSegment),
                  ),
                  const SizedBox(width: 8),
                  _DarkAction(
                    icon: CupertinoIcons.speedometer,
                    label: '${_rate.toStringAsFixed(2)}×',
                    onTap: _cycleRate,
                  ),
                  const SizedBox(width: 8),
                  _DarkAction(
                    icon: _showTranslation
                        ? CupertinoIcons.eye_slash
                        : CupertinoIcons.eye,
                    label: _showTranslation ? 'Hide' : 'Translate',
                    onTap: () =>
                        setState(() => _showTranslation = !_showTranslation),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _focusSegment == 0 ? null : () => _moveFocus(-1),
                icon: const Icon(CupertinoIcons.chevron_left, size: 17),
                label: const Text('Previous'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: DesignTokens.ink,
                  disabledForegroundColor: DesignTokens.mutedDim,
                  side: BorderSide(color: DesignTokens.hairline),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      DesignTokens.radiusMedium,
                    ),
                  ),
                  textStyle: DesignTokens.body(13, weight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _focusSegment >= _segments.length - 1
                    ? null
                    : () => _moveFocus(1),
                icon: const Icon(CupertinoIcons.chevron_right, size: 17),
                label: const Text('Next'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: DesignTokens.ink,
                  disabledForegroundColor: DesignTokens.mutedDim,
                  side: BorderSide(color: DesignTokens.hairline),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      DesignTokens.radiusMedium,
                    ),
                  ),
                  textStyle: DesignTokens.body(13, weight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
        if (wordEntry != null) ...[
          const SizedBox(height: 12),
          LearningCard(
            color: DesignTokens.masterySoft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  CupertinoIcons.textformat,
                  color: DesignTokens.mastery,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        wordEntry.fr,
                        style: DesignTokens.body(15, weight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        wordEntry.en,
                        style: DesignTokens.body(
                          13,
                        ).copyWith(color: DesignTokens.mutedDim),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        PrimaryActionButton(
          label: _focusSegment == _segments.length - 1
              ? 'Try a dictation line'
              : 'Next line',
          icon: CupertinoIcons.arrow_right,
          onPressed: _advanceFocus,
        ),
      ],
    );
  }

  Widget _dictationView() {
    final prompt = _dictationPrompt();
    final index = _dictationSegment;
    if (index == null || prompt.isEmpty) {
      return _EmptyStage(
        eyebrow: '04 · Active listening',
        title: 'Now say one line aloud.',
        body:
            'There is no clean cloze target in this story, so we will use shadowing instead.',
        buttonLabel: 'Start shadowing',
        onPressed: () => setState(() => _stage = _ListeningStage.shadow),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _StageEyebrow(
          label: '04 · Active listening',
          detail: 'Dictation',
        ),
        const SizedBox(height: 8),
        Text('Can your ear fill the gap?', style: DesignTokens.display(28)),
        const SizedBox(height: 8),
        Text(
          'Replay the line, then type the missing French word you hear.',
          style: DesignTokens.body(14).copyWith(color: DesignTokens.mutedDim),
        ),
        const SizedBox(height: 16),
        LearningCard(
          color: DesignTokens.ink,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconButton(
                tooltip: 'Play dictation line',
                onPressed: _audioLoading ? null : () => _playLine(index),
                icon: _audioLoading
                    ? const SizedBox(
                        width: 42,
                        height: 42,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      )
                    : const Icon(
                        CupertinoIcons.play_circle_fill,
                        size: 42,
                        color: Colors.white,
                      ),
                padding: EdgeInsets.zero,
                alignment: Alignment.centerLeft,
              ),
              const SizedBox(height: 14),
              Text(
                prompt,
                style: DesignTokens.display(20).copyWith(color: Colors.white),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _dictationController,
                enabled: !_dictationSubmitted,
                style: const TextStyle(color: Colors.white),
                cursorColor: Colors.white,
                textInputAction: TextInputAction.done,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _submitDictation(),
                decoration: InputDecoration(
                  labelText: 'Type the missing word',
                  labelStyle: const TextStyle(color: Colors.white70),
                  hintText: 'écoute…',
                  hintStyle: const TextStyle(color: Colors.white54),
                  filled: true,
                  fillColor: Colors.white10,
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white30),
                    borderRadius: BorderRadius.all(
                      Radius.circular(DesignTokens.radiusMedium),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: DesignTokens.primarySoft),
                    borderRadius: BorderRadius.all(
                      Radius.circular(DesignTokens.radiusMedium),
                    ),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(
                      DesignTokens.radiusMedium,
                    ),
                  ),
                ),
              ),
              if (_dictationSubmitted) ...[
                const SizedBox(height: 12),
                Text(
                  _dictationCorrect
                      ? 'Correct: ${_dictationTarget()}'
                      : 'The word was “${_dictationTarget()}”. Keep it for the next replay.',
                  style: DesignTokens.body(13, weight: FontWeight.w700)
                      .copyWith(
                        color: _dictationCorrect
                            ? DesignTokens.success
                            : DesignTokens.warning,
                      ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        PrimaryActionButton(
          label: 'Check the word',
          icon: CupertinoIcons.checkmark,
          onPressed:
              _dictationController.text.trim().isEmpty || _dictationSubmitted
              ? null
              : _submitDictation,
        ),
      ],
    );
  }

  Widget _shadowView() {
    final line = _focusLine;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _StageEyebrow(
          label: '05 · Shadowing',
          detail: 'Optional voice check',
        ),
        const SizedBox(height: 8),
        Text('Borrow the rhythm.', style: DesignTokens.display(28)),
        const SizedBox(height: 8),
        Text(
          'Listen once, then repeat the whole line. We only judge the attempt, not perfection.',
          style: DesignTokens.body(14).copyWith(color: DesignTokens.mutedDim),
        ),
        const SizedBox(height: 16),
        LearningCard(
          color: DesignTokens.primarySoft,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(line.fr, style: DesignTokens.display(20)),
              const SizedBox(height: 7),
              Text(
                line.en,
                style: DesignTokens.body(
                  13,
                ).copyWith(color: DesignTokens.mutedDim),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  IconButton(
                    tooltip: 'Play target line',
                    onPressed: () => _playLine(_focusSegment),
                    icon: const Icon(
                      CupertinoIcons.play_circle_fill,
                      size: 42,
                      color: DesignTokens.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _isRecording
                          ? 'Listening… tap stop when you finish.'
                          : 'Hear the line, then record your version.',
                      style: DesignTokens.body(12, weight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: _toggleShadow,
                  icon: Icon(
                    _isRecording
                        ? CupertinoIcons.stop_fill
                        : CupertinoIcons.mic_fill,
                  ),
                  label: Text(
                    _isRecording ? 'Stop and check' : 'Record attempt',
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: DesignTokens.primary,
                    side: BorderSide(
                      color: DesignTokens.primary.withValues(alpha: 0.35),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        DesignTokens.radiusMedium,
                      ),
                    ),
                  ),
                ),
              ),
              if (_shadowTranscript.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  'I heard: “$_shadowTranscript”',
                  style: DesignTokens.body(12),
                ),
              ],
              if (_shadowFeedback != null) ...[
                const SizedBox(height: 10),
                Text(
                  _shadowFeedback!,
                  style: DesignTokens.body(13, weight: FontWeight.w700)
                      .copyWith(
                        color: _shadowCorrect
                            ? DesignTokens.success
                            : DesignTokens.warning,
                      ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        PrimaryActionButton(
          label: 'See my listening recap',
          icon: CupertinoIcons.arrow_right,
          onPressed: _shadowTranscript.isNotEmpty || _shadowFeedback != null
              ? () => setState(() => _stage = _ListeningStage.recap)
              : null,
        ),
      ],
    );
  }

  Widget _recapView() {
    final correct = _quizAnswers.entries
        .where(
          (entry) =>
              entry.key < _questions.length &&
              entry.value == _questions[entry.key].answerIndex,
        )
        .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _StageEyebrow(label: 'Complete', detail: 'Listening recap'),
        const SizedBox(height: 8),
        Text('Your ear did the work.', style: DesignTokens.display(28)),
        const SizedBox(height: 8),
        Text(
          'Keep the phrases that were hard. They are the best next lesson.',
          style: DesignTokens.body(14).copyWith(color: DesignTokens.mutedDim),
        ),
        const SizedBox(height: 16),
        LearningCard(
          color: DesignTokens.primarySoft,
          child: Row(
            children: [
              Text(
                '$correct/${_questions.length}',
                style: DesignTokens.display(30),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  'details caught\n${_dictationCorrect ? 'Dictation landed' : 'Dictation needs one more pass'}',
                  style: DesignTokens.body(13, weight: FontWeight.w700),
                ),
              ),
              Icon(
                _shadowCorrect
                    ? CupertinoIcons.checkmark_seal_fill
                    : CupertinoIcons.headphones,
                color: _shadowCorrect
                    ? DesignTokens.success
                    : DesignTokens.primary,
                size: 30,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        LearningCard(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(CupertinoIcons.lightbulb, color: DesignTokens.mastery),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _shadowCorrect
                      ? 'Strong repeat. Next time, try the story once at normal speed before opening the transcript.'
                      : 'Replay the focus line tomorrow at 0.75×, then try it again at normal speed.',
                  style: DesignTokens.body(13, weight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        PrimaryActionButton(
          label: 'Finish listening',
          icon: CupertinoIcons.checkmark,
          onPressed: _finishAndPop,
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => StoryReaderScreen(story: _story),
              ),
            ),
            child: const Text('Open the full transcript'),
          ),
        ),
      ],
    );
  }
}

class _ListeningHeader extends StatelessWidget {
  const _ListeningHeader({required this.story});

  final GeneratedStory story;

  @override
  Widget build(BuildContext context) {
    return LearningCard(
      padding: 0,
      child: Row(
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(DesignTokens.radiusCard),
              bottomLeft: Radius.circular(DesignTokens.radiusCard),
            ),
            child: SizedBox(
              width: 92,
              height: 116,
              child: story.coverUrl == null || story.coverUrl!.isEmpty
                  ? const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: DesignTokens.heroGradient,
                      ),
                      child: Icon(
                        CupertinoIcons.headphones,
                        color: Colors.white,
                        size: 28,
                      ),
                    )
                  : Image.network(
                      story.coverUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: DesignTokens.heroGradient,
                        ),
                        child: Icon(
                          CupertinoIcons.headphones,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                    ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${story.levelBand} · ${story.readTimeMinutes} min',
                    style: DesignTokens.label(
                      10,
                    ).copyWith(color: DesignTokens.primary),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    story.displayTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: DesignTokens.display(18),
                  ),
                  if (story.summary.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      story.summary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: DesignTokens.body(
                        11.5,
                      ).copyWith(color: DesignTokens.mutedDim),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StageRail extends StatelessWidget {
  const _StageRail({required this.current});

  final _ListeningStage current;

  @override
  Widget build(BuildContext context) {
    const labels = ['Listen', 'Check', 'Focus', 'Dictate', 'Shadow', 'Done'];
    final currentIndex = current.index;
    return Row(
      children: [
        for (var index = 0; index < labels.length; index++) ...[
          Expanded(
            child: Column(
              children: [
                AnimatedContainer(
                  duration: DesignTokens.durationFast,
                  height: 4,
                  decoration: BoxDecoration(
                    color: index <= currentIndex
                        ? DesignTokens.primary
                        : DesignTokens.hairline,
                    borderRadius: BorderRadius.circular(
                      DesignTokens.radiusPill,
                    ),
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  labels[index],
                  style: DesignTokens.label(9).copyWith(
                    color: index <= currentIndex
                        ? DesignTokens.primary
                        : DesignTokens.mutedDim,
                  ),
                ),
              ],
            ),
          ),
          if (index != labels.length - 1) const SizedBox(width: 4),
        ],
      ],
    );
  }
}

class _StageEyebrow extends StatelessWidget {
  const _StageEyebrow({required this.label, required this.detail});

  final String label;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: DesignTokens.label(11).copyWith(color: DesignTokens.primary),
        ),
        Text(
          detail,
          style: DesignTokens.label(10).copyWith(color: DesignTokens.mutedDim),
        ),
      ],
    );
  }
}

class _AudioPlayerCard extends StatelessWidget {
  const _AudioPlayerCard({
    required this.story,
    required this.isPlaying,
    required this.isLoading,
    required this.currentSegment,
    required this.totalSegments,
    required this.rate,
    required this.onToggle,
    required this.onReplay,
    required this.onCycleRate,
  });

  final GeneratedStory story;
  final bool isPlaying;
  final bool isLoading;
  final int currentSegment;
  final int totalSegments;
  final double rate;
  final VoidCallback onToggle;
  final VoidCallback onReplay;
  final VoidCallback onCycleRate;

  @override
  Widget build(BuildContext context) {
    final progress = totalSegments == 0
        ? 0.0
        : ((currentSegment + (isPlaying ? 1 : 0)) / totalSegments)
              .clamp(0.0, 1.0)
              .toDouble();
    return LearningCard(
      padding: 0,
      color: DesignTokens.ink,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'NATURAL FRENCH · ${story.levelBand}',
              style: DesignTokens.label(
                10,
              ).copyWith(color: DesignTokens.primarySoft),
            ),
            const SizedBox(height: 10),
            Text(
              story.displayTitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: DesignTokens.display(22).copyWith(color: Colors.white),
            ),
            const SizedBox(height: 18),
            LinearProgressIndicator(
              value: progress,
              minHeight: 5,
              backgroundColor: Colors.white12,
              valueColor: const AlwaysStoppedAnimation<Color>(
                DesignTokens.primarySoft,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                IconButton(
                  tooltip: isPlaying ? 'Pause story' : 'Play story',
                  onPressed: isLoading ? null : onToggle,
                  icon: isLoading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        )
                      : Icon(
                          isPlaying
                              ? CupertinoIcons.pause_fill
                              : CupertinoIcons.play_fill,
                          color: DesignTokens.ink,
                        ),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white,
                    minimumSize: const Size(52, 52),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    totalSegments == 0
                        ? 'No audio lines yet'
                        : 'Line ${currentSegment + 1} of $totalSegments',
                    style: DesignTokens.body(
                      12,
                      weight: FontWeight.w600,
                    ).copyWith(color: Colors.white70),
                  ),
                ),
                _DarkAction(
                  icon: CupertinoIcons.repeat,
                  label: isLoading ? 'Preparing audio' : 'Replay',
                  onTap: isLoading ? () {} : onReplay,
                ),
                const SizedBox(width: 8),
                _DarkAction(
                  icon: CupertinoIcons.speedometer,
                  label: '${rate.toStringAsFixed(2)}×',
                  onTap: onCycleRate,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ChoiceButton extends StatelessWidget {
  const _ChoiceButton({
    required this.label,
    this.secondaryLabel,
    required this.selected,
    required this.correct,
    required this.onTap,
  });

  final String label;
  final String? secondaryLabel;
  final bool selected;
  final bool correct;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final active = selected || correct;
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          foregroundColor: correct ? DesignTokens.success : DesignTokens.ink,
          backgroundColor: correct
              ? DesignTokens.successSoft
              : active
              ? DesignTokens.primarySoft
              : DesignTokens.surface,
          side: BorderSide(
            color: correct
                ? DesignTokens.success
                : selected
                ? DesignTokens.primary
                : DesignTokens.hairline,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DesignTokens.radiusMedium),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: DesignTokens.body(13, weight: FontWeight.w600)),
            if (secondaryLabel != null &&
                secondaryLabel!.trim().isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(
                secondaryLabel!,
                style: DesignTokens.body(
                  11.5,
                ).copyWith(color: DesignTokens.mutedDim),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DarkAction extends StatelessWidget {
  const _DarkAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DesignTokens.radiusMedium),
        child: SizedBox(
          height: 48,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 17, color: Colors.white70),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: DesignTokens.label(9).copyWith(color: Colors.white70),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyStage extends StatelessWidget {
  const _EmptyStage({
    required this.eyebrow,
    required this.title,
    required this.body,
    required this.buttonLabel,
    required this.onPressed,
  });

  final String eyebrow;
  final String title;
  final String body;
  final String buttonLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StageEyebrow(label: eyebrow, detail: 'Continue'),
        const SizedBox(height: 8),
        Text(title, style: DesignTokens.display(28)),
        const SizedBox(height: 8),
        Text(
          body,
          style: DesignTokens.body(14).copyWith(color: DesignTokens.mutedDim),
        ),
        const SizedBox(height: 20),
        PrimaryActionButton(
          label: buttonLabel,
          icon: CupertinoIcons.arrow_right,
          onPressed: onPressed,
        ),
      ],
    );
  }
}
