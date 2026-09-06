import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/content_service.dart';
import '../../data/database/vocabulary_session_store.dart';
import '../../design/tokens.dart';
import '../../models/content_models.dart';
import '../../models/srs_state.dart';
import '../../prompts/live_prompts.dart';
import '../../providers/database_provider.dart';
import '../../providers/tutor_helper_provider.dart';
import '../../models/tutor_persona.dart';
import '../../services/gemini_live_audio_service.dart';
import '../../services/inline_call_controller.dart';
import '../../services/lesson_speech_service.dart';
import '../../services/srs_service.dart';
import '../../services/tutor_helper_settings.dart';
import '../../widgets/tts_play_button.dart';
import '../../widgets/v3/v3_surface.dart';

enum VocabularyStudyDepth { wordsOnly, wordsAndSentences }

/// A focused vocabulary lesson: one target word is taught before the next
/// word appears. The set's story and sentence data are prepared outside this
/// surface so the learner never gets a multi-word quiz or a cold content wait.
class VocabularyFlashcardsScreen extends ConsumerStatefulWidget {
  const VocabularyFlashcardsScreen({
    super.key,
    required this.title,
    required this.entries,
    required this.source,
    required this.topic,
    required this.levelBand,
    this.studyDepth = VocabularyStudyDepth.wordsAndSentences,
    this.storyExamples = const {},
    this.coverUrl,
    this.prefetchAudio = true,
    this.preparedContentOnly = false,
  });

  final String title;
  final List<VocabEntry> entries;
  final String source;
  final String topic;
  final String levelBand;
  final VocabularyStudyDepth studyDepth;
  final Map<String, BilingualExample> storyExamples;
  final String? coverUrl;

  /// Tests and offline previews can disable network warming. Production
  /// lessons leave this enabled so every word and sentence is cached first.
  final bool prefetchAudio;

  /// Course passes true after its artifact has been hydrated. In that mode
  /// this screen is a renderer only: it never asks the lesson agent to fill
  /// missing examples and never blocks opening on audio warming.
  final bool preparedContentOnly;

  @override
  ConsumerState<VocabularyFlashcardsScreen> createState() =>
      _VocabularyFlashcardsScreenState();
}

class _VocabularyFlashcardsScreenState
    extends ConsumerState<VocabularyFlashcardsScreen>
    with WidgetsBindingObserver {
  late final List<VocabEntry> _entries;
  late final String _sessionId;
  late final SRSService _srs;
  late final VocabularySessionStore _sessions;
  late final InlineCallController _murray;

  final Map<String, String> _grades = {};
  final Map<String, BilingualExample> _examples = {};
  final Set<String> _revealedWordIds = {};
  final Set<String> _completedWordIds = {};

  int _index = 0;
  bool _meaningRevealed = false;
  bool _wordComplete = false;
  bool _preparing = true;
  bool _completed = false;
  bool _sessionCreated = false;
  bool _recording = false;
  String? _pronunciationHint;
  String _preparationStatus = 'Preparing your words…';
  Object? _loadError;

  // Sentence testing is optional (the learner can skip straight to Next);
  // word testing is not.
  bool _sentenceTested = false;
  bool _sentenceRecording = false;
  String? _sentenceHint;

  String? _heard;
  bool _murrayTurnClosing = false;
  bool _murrayGradeReceived = false;
  Timer? _murrayGradeTimeout;
  bool _testingSentence = false;
  final _wordSpeakerKey = GlobalKey<TtsPlayButtonState>();

  static const _diacriticMap = {
    'à': 'a',
    'â': 'a',
    'ä': 'a',
    'ç': 'c',
    'é': 'e',
    'è': 'e',
    'ê': 'e',
    'ë': 'e',
    'î': 'i',
    'ï': 'i',
    'ô': 'o',
    'ö': 'o',
    'û': 'u',
    'ü': 'u',
    'ù': 'u',
    'œ': 'oe',
  };

  String _fold(String text) {
    var result = text.toLowerCase().trim();
    _diacriticMap.forEach((accented, plain) {
      result = result.replaceAll(accented, plain);
    });
    return result.replaceAll(RegExp(r'[^a-z0-9 ]'), '').replaceAll(
      RegExp(r'\s+'),
      ' ',
    );
  }

  VocabEntry get _current => _entries[_index];
  bool get _showsSentences =>
      widget.studyDepth == VocabularyStudyDepth.wordsAndSentences;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _entries = widget.entries
        .where((entry) => entry.fr.trim().isNotEmpty)
        .take(5)
        .toList(growable: false);
    _srs = ref.read(srsServiceProvider);
    _sessions = ref.read(vocabularySessionStoreProvider);
    _sessionId =
        'vocabulary-flashcards-${DateTime.now().microsecondsSinceEpoch}';
    _examples.addAll(widget.storyExamples);
    _murray = InlineCallController(
      sessionType: LiveSessionType.vocabStage,
      lessonContext: _murrayContext,
      learningStoreForProfile: ref.read(learningStoreProvider),
      onChanged: () => mounted ? setState(() {}) : null,
      manualLearnerTurns: true,
      onUserTranscript: _onMurrayTranscript,
      onTurnComplete: _onMurrayTurnComplete,
    );
    if (widget.preparedContentOnly) {
      _preparePersistedSet();
      if (_loadError == null && widget.prefetchAudio) {
        // Course passes a complete persisted set. Warm its word and sentence
        // audio in parallel without regenerating or changing any content.
        unawaited(_prefetchAudioFrom(0));
      }
    } else {
      unawaited(_prepareSet());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_maybeStartMurray());
    });
  }

  /// Wires the same live pronunciation check speaking uses: connect once,
  /// silently, when this word/sentence surface's tutor-helper toggle is on.
  /// A failed or declined connection is not an error — the record button
  /// simply falls back to the plain mic-capture check.
  Future<void> _maybeStartMurray() async {
    final enabled = ref
        .read(tutorHelperSettingsProvider)
        .isEnabled(TutorHelperSurface.vocabulary);
    if (!enabled || !mounted) return;
    await _murray.start(context, sendOpeningPrompt: false);
  }

  String _murrayContext() {
    final entry = _current;
    final example = _examples[entry.id];
    return 'Vocabulary pronunciation check. Word ${_index + 1} of '
        '${_entries.length}: "${entry.fr}" = "${entry.en}".'
        '${example != null ? ' Example sentence: "${example.fr}" = "${example.en}".' : ''} '
        'This is a silent pronunciation check only: never speak unless the '
        'app explicitly asks you to grade an attempt. Do not teach, greet, '
        'or comment.';
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _murray.handleAppLifecycle(state);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _murrayGradeTimeout?.cancel();
    _murray.dispose();
    unawaited(LessonSpeechService.shared.deactivate());
    if (_sessionCreated && !_completed) {
      try {
        _sessions.pause(_sessionId);
      } catch (_) {
        // The session remains useful in memory if the database closes while
        // this route is being dismissed.
      }
    }
    super.dispose();
  }

  /// Only the first word blocks the loading screen. The rest of the set
  /// keeps preparing in the background (`_prepareRemainingWords`) so a
  /// learner reaching word two, three, etc. almost never waits — instead of
  /// this screen sitting on "Preparing…" until the entire five-word deck,
  /// text and audio alike, is generated.
  Future<void> _prepareSet() async {
    if (_entries.isEmpty) {
      if (mounted) setState(() => _preparing = false);
      return;
    }

    await _prepareExampleFor(0);
    if (widget.prefetchAudio) {
      _setPreparationStatus(
        _showsSentences
            ? 'Caching word and sentence audio…'
            : 'Caching pronunciation audio…',
      );
      await _prefetchAudioFor(0);
    }

    _createSession();

    if (mounted) setState(() => _preparing = false);
    unawaited(_prepareRemainingWords());
  }

  Future<void> _prepareRemainingWords() async {
    for (var index = 1; index < _entries.length; index++) {
      await _prepareExampleFor(index);
    }
    if (widget.prefetchAudio) await _prefetchAudioFrom(1);
    if (mounted) setState(() {});
  }

  void _preparePersistedSet() {
    final missingExamples = _showsSentences
        ? _entries.where((entry) => !_examples.containsKey(entry.id)).length
        : 0;
    if (_entries.length != 5 || missingExamples != 0) {
      _loadError = StateError(
        'Prepared vocabulary requires five words and one saved sentence per word.',
      );
    } else {
      _createSession();
    }
    _preparing = false;
  }

  void _createSession() {
    try {
      _sessions.create(
        id: _sessionId,
        title: widget.title,
        source: widget.source,
        topic: widget.topic,
        levelBand: widget.levelBand,
        entries: _entries,
        contextExamples: _examples,
        focusNote:
            'One word at a time. Reveal the meaning, repeat the word, then review its sentence.',
      );
      _sessionCreated = true;
    } catch (error) {
      _loadError = error;
    }
  }

  Future<void> _prepareExampleFor(int index) async {
    if (!_showsSentences) return;
    if (widget.preparedContentOnly) return;
    final entry = _entries[index];
    if (_examples.containsKey(entry.id)) return;
    _setPreparationStatus('Preparing sentence ${index + 1} of ${_entries.length}…');

    final bundled = ContentService.shared.vocabExamples(entry.id);
    if (bundled != null) {
      _examples[entry.id] = bundled;
      return;
    }

    try {
      final agent = ref.read(lessonAgentServiceProvider);
      _examples[entry.id] = await agent.generateVocabularyContext(
        word: entry,
        levelBand: widget.levelBand,
      );
    } catch (error) {
      // A curated story always supplies this. For a custom set, keep the
      // lesson usable and let the sentence card show a recoverable state.
      _loadError = error;
      debugPrint('Vocabulary sentence preparation failed: $error');
    }
  }

  /// Warms just [index]'s own word/sentence audio. Used to unblock the
  /// loading screen on the first word only.
  Future<void> _prefetchAudioFor(int index) => _prefetchAudioItems(
    _audioItemsFor(index, index),
    timeout: const Duration(seconds: 30),
  );

  /// Warms every word from [startIndex] onward, in the background, using
  /// `warmDeck`'s own small parallel worker pool.
  Future<void> _prefetchAudioFrom(int startIndex) => _prefetchAudioItems(
    _audioItemsFor(startIndex, _entries.length - 1),
    timeout: const Duration(seconds: 60),
  );

  List<({String text, String contentItemId})> _audioItemsFor(
    int start,
    int end,
  ) {
    final items = <({String text, String contentItemId})>[];
    for (var i = start; i <= end; i++) {
      final entry = _entries[i];
      items.add((text: entry.fr, contentItemId: _audioId(entry, 'word')));
      final example = _examples[entry.id];
      if (_showsSentences && example != null) {
        items.add((
          text: example.fr,
          contentItemId: _audioId(entry, 'sentence'),
        ));
      }
    }
    return items;
  }

  Future<void> _prefetchAudioItems(
    List<({String text, String contentItemId})> items, {
    required Duration timeout,
  }) async {
    if (items.isEmpty) return;
    try {
      await GeminiLiveAudioService.shared
          .warmDeck(items: items, voiceName: ActiveTutor.current.voiceName)
          .timeout(timeout);
    } catch (error) {
      // Audio warming is best effort. The same persistent resolver remains as
      // a safe fallback if a device is offline or the provider is unavailable.
      _loadError = error;
      debugPrint('Vocabulary audio preparation failed: $error');
    }
  }

  String _audioId(VocabEntry entry, String kind) =>
      'vocabulary:${widget.title}:${entry.id}:$kind';

  void _setPreparationStatus(String value) {
    if (mounted) setState(() => _preparationStatus = value);
  }

  void _revealMeaning() {
    if (_meaningRevealed || _wordComplete) return;
    setState(() {
      _meaningRevealed = true;
      _revealedWordIds.add(_current.id);
    });
    _saveProgress();
  }

  /// Records the learner's attempt and verifies it against the target
  /// (word, or optionally its sentence) live, through the same Gemini Live
  /// connection and hear/repeat/check contract the Speaking Guided flow
  /// uses — not a separate, dumber mechanism. When the tutor helper is off
  /// or the call is unavailable, this falls back to a plain mic capture and
  /// transcript check so the learner is never blocked. A word only becomes
  /// complete once the learner is actually heard saying it — this must
  /// never auto-complete on tap alone.
  Future<void> _toggleRecording({required bool sentence}) async {
    final active = sentence ? _sentenceRecording : _recording;
    if (active) {
      if (_murray.isLive) {
        _murrayTurnClosing = true;
        await _murray.endLearnerTurn();
        _murrayGradeTimeout?.cancel();
        _murrayGradeTimeout = Timer(const Duration(seconds: 12), () {
          if (!mounted || _murrayGradeReceived) return;
          _resolveAttempt(_heard ?? '', sentence: sentence);
        });
      } else {
        await LessonSpeechService.shared.stopListening();
      }
      return;
    }
    if (!sentence && _wordComplete) return;
    final target = sentence ? (_examples[_current.id]?.fr ?? '') : _current.fr;
    if (target.trim().isEmpty) return;
    setState(() {
      _testingSentence = sentence;
      _heard = '';
      _murrayGradeReceived = false;
      if (sentence) {
        _sentenceRecording = true;
        _sentenceHint = null;
      } else {
        _recording = true;
        _pronunciationHint = null;
      }
    });
    if (_murray.isReadyForLearnerTurn) {
      _murrayTurnClosing = false;
      final started = await _murray.startLearnerTurn();
      if (started) return;
    }
    await LessonSpeechService.shared.startListening(
      locale: 'fr-FR',
      onPartial: (_) {},
      onFinal: (transcript) => _resolveAttempt(transcript, sentence: sentence),
    );
  }

  void _onMurrayTranscript(String transcript) {
    if (!mounted) return;
    final cleaned = transcript.trim();
    if (cleaned.isEmpty) return;
    final current = (_heard ?? '').trim();
    _heard = current.isEmpty ? cleaned : '$current $cleaned';
    if (!_murrayTurnClosing || _murrayGradeReceived) return;
    _murrayGradeReceived = true;
    _murrayGradeTimeout?.cancel();
    _resolveAttempt(_heard!, sentence: _testingSentence);
  }

  void _onMurrayTurnComplete() {
    if (!mounted || !_murrayTurnClosing || _murrayGradeReceived) return;
    final transcript = (_heard ?? '').trim();
    if (transcript.isEmpty) return;
    _murrayGradeReceived = true;
    _murrayGradeTimeout?.cancel();
    _resolveAttempt(transcript, sentence: _testingSentence);
  }

  void _resolveAttempt(String transcript, {required bool sentence}) {
    if (!mounted) return;
    final target = sentence ? (_examples[_current.id]?.fr ?? '') : _current.fr;
    final heard = _fold(transcript);
    final wanted = _fold(target);
    final matches =
        heard.isNotEmpty &&
        (heard.contains(wanted) || wanted.contains(heard));
    _murrayTurnClosing = false;
    setState(() {
      if (sentence) {
        _sentenceRecording = false;
        _sentenceHint = matches
            ? null
            : heard.isEmpty
            ? "Didn't catch that — try again."
            : 'Not quite — try saying "$target" again.';
        if (matches) _sentenceTested = true;
      } else {
        _recording = false;
        _pronunciationHint = matches
            ? null
            : heard.isEmpty
            ? "Didn't catch that — tap the mic and try again."
            : 'Not quite — try saying "$target" again.';
        if (matches) _completeWord();
      }
    });
  }

  /// The sentence check is optional: the learner may test it the same live
  /// way as the word, or skip straight to Next.
  Widget _testSentenceControl() {
    return GestureDetector(
      onTap: () => _toggleRecording(sentence: true),
      behavior: HitTestBehavior.opaque,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _sentenceRecording
                  ? DesignTokens.nightAccent.withValues(alpha: 0.18)
                  : DesignTokens.nightAccentSoft,
              border: Border.all(
                color: DesignTokens.nightAccent,
                width: _sentenceRecording ? 2 : 1,
              ),
            ),
            child: Icon(
              _sentenceTested
                  ? Icons.check_rounded
                  : _sentenceRecording
                  ? Icons.graphic_eq_rounded
                  : Icons.mic_none_rounded,
              color: DesignTokens.nightAccent,
              size: 18,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _sentenceRecording
                ? 'Tap to stop'
                : _sentenceTested
                ? 'Sentence checked'
                : 'Test this sentence (optional)',
            style: DesignTokens.body(13).copyWith(color: DesignTokens.muted),
          ),
        ],
      ),
    );
  }

  void _completeWord() {
    if (!_meaningRevealed || _wordComplete) return;
    try {
      _srs.grade(
        entryId: _current.id,
        grade: SRSGrade.good,
        responseType: SRSResponseType.auto,
        sessionId: _sessionId,
      );
      _grades[_current.id] = 'correct';
      _completedWordIds.add(_current.id);
      _saveProgress();
      setState(() => _wordComplete = true);
    } catch (error) {
      if (mounted) setState(() => _loadError = error);
    }
  }

  void _saveProgress() {
    if (!_sessionCreated) return;
    try {
      _sessions.saveProgress(
        id: _sessionId,
        currentStep: 'one-word',
        currentIndex: _index,
        recallGrades: Map<String, String>.of(_grades),
        contextResults: {for (final id in _revealedWordIds) id: true},
        sentenceResults: {for (final id in _completedWordIds) id: 'shown'},
        contextExamples: _examples,
      );
    } catch (error) {
      _loadError = error;
    }
  }

  void _next() {
    if (!_wordComplete) return;
    if (_index >= _entries.length - 1) {
      try {
        _sessions.complete(_sessionId);
      } catch (error) {
        _loadError = error;
      }
      setState(() => _completed = true);
      return;
    }
    setState(() {
      _index += 1;
      _meaningRevealed = false;
      _wordComplete = false;
      _recording = false;
      _pronunciationHint = null;
      _sentenceTested = false;
      _sentenceRecording = false;
      _sentenceHint = null;
      _loadError = null;
    });
    _murray.updateLessonContext();
    _saveProgress();
  }

  void _finish() => Navigator.of(context).pop(true);

  @override
  Widget build(BuildContext context) {
    if (_entries.isEmpty) return _emptyState();
    if (_preparing) return _preparationState();
    if (_completed) return _completedState();

    return V3Scaffold(
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              children: [
                _topBar(),
                const SizedBox(height: 18),
                _progressLine(),
                const SizedBox(height: 26),
                Text(
                  'One word at a time.',
                  style: DesignTokens.display(30).copyWith(height: 1.08),
                ),
                const SizedBox(height: 8),
                Text(
                  _wordComplete
                      ? 'Repeat the sentence, then move to the next word.'
                      : _meaningRevealed
                      ? _recording
                            ? 'Listening…'
                            : 'Say the word out loud, then continue.'
                      : 'Double-tap the word to reveal its meaning.',
                  style: DesignTokens.body(
                    15,
                  ).copyWith(color: DesignTokens.muted, height: 1.35),
                ),
                const SizedBox(height: 22),
                _wordCard(),
                if (_meaningRevealed) ...[
                  const SizedBox(height: 16),
                  _wordFeedbackCard(),
                ],
                if (_wordComplete && _showsSentences) ...[
                  const SizedBox(height: 16),
                  _sentenceCard(),
                ],
                if (_loadError != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Your progress is saved. Some optional content could not be prepared.',
                    style: DesignTokens.body(
                      12,
                    ).copyWith(color: DesignTokens.mutedDim),
                  ),
                ],
              ],
            ),
          ),
          _bottomControls(),
        ],
      ),
    );
  }

  /// Mirrors Speaking Guided's success/attempt card: a neutral prompt before
  /// any attempt, green with a checkmark and "MATCHED" once the word is
  /// heard correctly, or a soft retry state otherwise.
  Widget _wordFeedbackCard() {
    final success = _wordComplete;
    final heard = (_heard ?? '').trim();
    final failed = !success && _pronunciationHint != null;
    final borderColor = success
        ? DesignTokens.success
        : failed
        ? DesignTokens.danger
        : DesignTokens.nightHairline;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: success
            ? DesignTokens.success.withValues(alpha: 0.14)
            : DesignTokens.nightSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor, width: success || failed ? 1.4 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                success
                    ? Icons.check_circle_rounded
                    : Icons.format_quote_rounded,
                color: success
                    ? DesignTokens.success
                    : failed
                    ? DesignTokens.danger
                    : DesignTokens.nightAccent,
              ),
              const SizedBox(width: 8),
              Text(
                success
                    ? 'Nice work'
                    : failed
                    ? 'Try it again'
                    : 'Speak now',
                style: DesignTokens.body(13, weight: FontWeight.w800).copyWith(
                  color: success
                      ? DesignTokens.success
                      : failed
                      ? DesignTokens.danger
                      : DesignTokens.nightAccent,
                ),
              ),
            ],
          ),
          if (heard.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              success ? 'MATCHED' : 'I HEARD',
              style: DesignTokens.label(
                10,
              ).copyWith(color: DesignTokens.muted, letterSpacing: 1),
            ),
            const SizedBox(height: 4),
            Text(
              heard,
              style: DesignTokens.body(14, weight: FontWeight.w700).copyWith(
                color: success ? DesignTokens.success : DesignTokens.nightText,
              ),
            ),
          ] else if (_pronunciationHint != null) ...[
            const SizedBox(height: 10),
            Text(
              _pronunciationHint!,
              style: DesignTokens.body(13).copyWith(color: DesignTokens.muted),
            ),
          ],
        ],
      ),
    );
  }

  /// The same translate / record-stop-next / replay footer layout Speaking
  /// Guided uses, wired to this screen's own word (and, once complete,
  /// sentence-advance) logic.
  Widget _bottomControls() {
    return Container(
      padding: const EdgeInsets.fromLTRB(26, 10, 26, 15),
      decoration: BoxDecoration(
        color: DesignTokens.nightCanvas,
        border: Border(top: BorderSide(color: DesignTokens.nightHairline)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: _smallFooterControl(
              icon: _meaningRevealed
                  ? Icons.translate_rounded
                  : Icons.translate_outlined,
              label: _meaningRevealed ? 'Meaning on' : 'Meaning off',
              selected: _meaningRevealed,
              onTap: _meaningRevealed ? null : _revealMeaning,
            ),
          ),
          _wordRoundAction(),
          Expanded(
            child: _smallFooterControl(
              icon: Icons.volume_up_outlined,
              label: 'Replay word',
              onTap: () => _wordSpeakerKey.currentState?.trigger(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _wordRoundAction() {
    final success = _wordComplete;
    final active = success
        ? DesignTokens.success
        : _recording
        ? DesignTokens.nightAccent
        : DesignTokens.nightAccent;
    final label = success
        ? (_index == _entries.length - 1 ? 'Finish set' : 'Next word')
        : _recording
        ? 'Stop'
        : 'Record';
    final VoidCallback? onTap = !_meaningRevealed
        ? null
        : success
        ? _next
        : () => _toggleRecording(sentence: false);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: onTap == null ? DesignTokens.nightSurfaceRaised : active,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(
              success
                  ? Icons.arrow_forward_rounded
                  : _recording
                  ? Icons.stop_rounded
                  : Icons.mic_none_rounded,
              color: onTap == null ? DesignTokens.muted : Colors.black,
              size: 30,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            label,
            style: DesignTokens.body(11, weight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  Widget _smallFooterControl({
    required IconData icon,
    required String label,
    bool selected = false,
    VoidCallback? onTap,
  }) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Icon(
            icon,
            color: onTap == null
                ? DesignTokens.nightHairline
                : selected
                ? DesignTokens.nightAccent
                : DesignTokens.nightText,
          ),
        ),
      ),
    );
  }

  Widget _topBar() {
    return Row(
      children: [
        V3BackButton(onPressed: () => Navigator.of(context).maybePop()),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            widget.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: DesignTokens.display(21),
          ),
        ),
        Text(
          widget.levelBand,
          style: DesignTokens.label(
            12,
          ).copyWith(color: DesignTokens.nightAccent),
        ),
      ],
    );
  }

  Widget _progressLine() {
    final progress = (_index + (_wordComplete ? 1 : 0)) / _entries.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'WORD ${_index + 1} OF ${_entries.length}',
              style: DesignTokens.label(
                11,
              ).copyWith(color: DesignTokens.nightAccent, letterSpacing: 1.2),
            ),
            Text(
              '${(_index + 1).clamp(1, _entries.length)}/${_entries.length}',
              style: DesignTokens.body(
                12,
              ).copyWith(color: DesignTokens.mutedDim),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            minHeight: 6,
            value: progress.clamp(0.0, 1.0),
            backgroundColor: DesignTokens.nightHairline,
            valueColor: AlwaysStoppedAnimation<Color>(DesignTokens.primary),
          ),
        ),
      ],
    );
  }

  Widget _wordCard() {
    final entry = _current;
    return V3Card(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
      child: Column(
        children: [
          Text(
            'FRENCH WORD',
            style: DesignTokens.label(
              10,
            ).copyWith(color: DesignTokens.nightAccent, letterSpacing: 1.2),
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onDoubleTap: _revealMeaning,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: Text(
                entry.fr,
                textAlign: TextAlign.center,
                style: DesignTokens.display(
                  48,
                ).copyWith(color: DesignTokens.primary, height: 1),
              ),
            ),
          ),
          if (entry.phonetic.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              '/${entry.phonetic}/',
              style: DesignTokens.body(
                16,
              ).copyWith(color: DesignTokens.muted, letterSpacing: 0.4),
            ),
          ],
          const SizedBox(height: 16),
          TtsPlayButton(
            key: _wordSpeakerKey,
            text: entry.fr,
            contentItemId: _audioId(entry, 'word'),
            audioResolver: () => GeminiLiveAudioService.shared.resolve(
              text: entry.fr,
              contentItemId: _audioId(entry, 'word'),
              voiceName: ActiveTutor.current.voiceName,
            ),
            color: DesignTokens.nightAccent,
            size: 44,
            iconSize: 20,
          ),
          if (_meaningRevealed) ...[
            const SizedBox(height: 20),
            Divider(color: DesignTokens.nightHairline),
            const SizedBox(height: 16),
            Text(
              'MEANING',
              style: DesignTokens.label(
                10,
              ).copyWith(color: DesignTokens.muted, letterSpacing: 1.2),
            ),
            const SizedBox(height: 6),
            Text(
              entry.en,
              textAlign: TextAlign.center,
              style: DesignTokens.display(28).copyWith(height: 1.1),
            ),
          ],
          const SizedBox(height: 18),
          if (_wordComplete)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.check_circle_outline_rounded,
                  color: DesignTokens.success,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'WORD COMPLETE',
                  style: DesignTokens.label(
                    11,
                  ).copyWith(color: DesignTokens.success, letterSpacing: 1.1),
                ),
              ],
            )
          else
            Text(
              _meaningRevealed
                  ? 'Repeat it once, then continue.'
                  : 'Double-tap the word when you are ready.',
              textAlign: TextAlign.center,
              style: DesignTokens.body(
                12,
              ).copyWith(color: DesignTokens.mutedDim),
            ),
        ],
      ),
    );
  }

  Widget _sentenceCard() {
    final example = _examples[_current.id];
    return V3Card(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: example == null
          ? Text(
              'The sentence for this word is not available yet.',
              style: DesignTokens.body(13).copyWith(color: DesignTokens.muted),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SENTENCE',
                  style: DesignTokens.label(10).copyWith(
                    color: DesignTokens.nightAccent,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  example.fr,
                  style: DesignTokens.body(19, weight: FontWeight.w700),
                ),
                const SizedBox(height: 5),
                Text(
                  example.en,
                  style: DesignTokens.body(
                    14,
                  ).copyWith(color: DesignTokens.muted, height: 1.3),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    TtsPlayButton(
                      text: example.fr,
                      contentItemId: _audioId(_current, 'sentence'),
                      audioResolver: () =>
                          GeminiLiveAudioService.shared.resolve(
                            text: example.fr,
                            contentItemId: _audioId(_current, 'sentence'),
                            voiceName: ActiveTutor.current.voiceName,
                          ),
                      color: DesignTokens.nightAccent,
                      size: 40,
                      iconSize: 19,
                    ),
                    const SizedBox(width: 4),
                    _testSentenceControl(),
                  ],
                ),
                if (_sentenceHint != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _sentenceHint!,
                    style: DesignTokens.body(
                      12,
                    ).copyWith(color: DesignTokens.muted),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _preparationState() {
    return V3Scaffold(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 44,
                height: 44,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: DesignTokens.primary,
                ),
              ),
              const SizedBox(height: 22),
              Text('Preparing your set', style: DesignTokens.display(27)),
              const SizedBox(height: 8),
              Text(
                _preparationStatus,
                textAlign: TextAlign.center,
                style: DesignTokens.body(
                  14,
                ).copyWith(color: DesignTokens.muted),
              ),
              const SizedBox(height: 8),
              Text(
                'Your words, sentences, and audio will be ready before the first word.',
                textAlign: TextAlign.center,
                style: DesignTokens.body(
                  12,
                ).copyWith(color: DesignTokens.mutedDim, height: 1.35),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _completedState() {
    final correctCount = _grades.values
        .where((grade) => grade == 'correct')
        .length;
    final revisitCount = _entries.length - correctCount;
    return V3Scaffold(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 74,
                height: 74,
                decoration: BoxDecoration(
                  color: DesignTokens.successSoft,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.check_rounded,
                  size: 42,
                  color: DesignTokens.success,
                ),
              ),
              const SizedBox(height: 22),
              Text('Set complete', style: DesignTokens.display(30)),
              const SizedBox(height: 8),
              Text(
                '${_entries.length} words reviewed · $correctCount complete · $revisitCount to revisit.',
                textAlign: TextAlign.center,
                style: DesignTokens.body(
                  15,
                ).copyWith(color: DesignTokens.muted),
              ),
              const SizedBox(height: 28),
              V3PrimaryButton(
                label: 'Done',
                icon: Icons.check_rounded,
                onPressed: _finish,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyState() {
    return V3Scaffold(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('This set is empty', style: DesignTokens.display(26)),
              const SizedBox(height: 8),
              Text(
                'Go back and choose another vocabulary set.',
                textAlign: TextAlign.center,
                style: DesignTokens.body(
                  15,
                ).copyWith(color: DesignTokens.muted),
              ),
              const SizedBox(height: 24),
              V3PrimaryButton(label: 'Go back', onPressed: _finish),
            ],
          ),
        ),
      ),
    );
  }
}
