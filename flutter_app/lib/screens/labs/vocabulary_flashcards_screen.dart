import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/content_service.dart';
import '../../data/database/vocabulary_session_store.dart';
import '../../design/tokens.dart';
import '../../models/content_models.dart';
import '../../models/srs_state.dart';
import '../../providers/database_provider.dart';
import '../../models/tutor_persona.dart';
import '../../services/gemini_live_audio_service.dart';
import '../../services/lesson_speech_service.dart';
import '../../services/srs_service.dart';
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
    extends ConsumerState<VocabularyFlashcardsScreen> {
  late final List<VocabEntry> _entries;
  late final String _sessionId;
  late final SRSService _srs;
  late final VocabularySessionStore _sessions;

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
  String _preparationStatus = 'Preparing your words…';
  Object? _loadError;

  VocabEntry get _current => _entries[_index];
  bool get _showsSentences =>
      widget.studyDepth == VocabularyStudyDepth.wordsAndSentences;

  @override
  void initState() {
    super.initState();
    _entries = widget.entries
        .where((entry) => entry.fr.trim().isNotEmpty)
        .take(5)
        .toList(growable: false);
    _srs = ref.read(srsServiceProvider);
    _sessions = ref.read(vocabularySessionStoreProvider);
    _sessionId =
        'vocabulary-flashcards-${DateTime.now().microsecondsSinceEpoch}';
    _examples.addAll(widget.storyExamples);
    if (widget.preparedContentOnly) {
      _preparePersistedSet();
      if (_loadError == null && widget.prefetchAudio) {
        // Course passes a complete persisted set. Warm its word and sentence
        // audio in parallel without regenerating or changing any content.
        unawaited(_prefetchAudio());
      }
    } else {
      unawaited(_prepareSet());
    }
  }

  @override
  void dispose() {
    unawaited(LessonSpeechService.shared.stop());
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

  Future<void> _prepareSet() async {
    if (_entries.isEmpty) {
      if (mounted) setState(() => _preparing = false);
      return;
    }

    await _prepareExamples();
    if (widget.prefetchAudio) {
      _setPreparationStatus(
        _showsSentences
            ? 'Caching word and sentence audio…'
            : 'Caching pronunciation audio…',
      );
      await _prefetchAudio();
    }

    _createSession();

    if (mounted) setState(() => _preparing = false);
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

  Future<void> _prepareExamples() async {
    if (!_showsSentences) return;
    if (widget.preparedContentOnly) return;
    final agent = ref.read(lessonAgentServiceProvider);
    for (var index = 0; index < _entries.length; index++) {
      final entry = _entries[index];
      if (_examples.containsKey(entry.id)) continue;
      _setPreparationStatus(
        'Preparing sentence ${index + 1} of ${_entries.length}…',
      );

      final bundled = ContentService.shared.vocabExamples(entry.id);
      if (bundled != null) {
        _examples[entry.id] = bundled;
        continue;
      }

      try {
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
  }

  Future<void> _prefetchAudio() async {
    final items = <({String text, String contentItemId})>[];
    for (final entry in _entries) {
      items.add((text: entry.fr, contentItemId: _audioId(entry, 'word')));
      final example = _examples[entry.id];
      if (_showsSentences && example != null) {
        items.add((
          text: example.fr,
          contentItemId: _audioId(entry, 'sentence'),
        ));
      }
    }
    if (items.isEmpty) return;

    try {
      await GeminiLiveAudioService.shared
          .warmDeck(items: items, voiceName: ActiveTutor.current.voiceName)
          .timeout(const Duration(seconds: 60));
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
      _loadError = null;
    });
    _saveProgress();
  }

  void _finish() => Navigator.of(context).pop(true);

  @override
  Widget build(BuildContext context) {
    if (_entries.isEmpty) return _emptyState();
    if (_preparing) return _preparationState();
    if (_completed) return _completedState();

    return V3Scaffold(
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
                ? 'Say the word out loud, then continue.'
                : 'Double-tap the word to reveal its meaning.',
            style: DesignTokens.body(
              15,
            ).copyWith(color: DesignTokens.muted, height: 1.35),
          ),
          const SizedBox(height: 22),
          _wordCard(),
          if (!_wordComplete && _meaningRevealed) ...[
            const SizedBox(height: 16),
            V3PrimaryButton(
              label: 'Repeat word',
              icon: Icons.record_voice_over_rounded,
              onPressed: _completeWord,
            ),
          ],
          if (_wordComplete && _showsSentences) ...[
            const SizedBox(height: 16),
            _sentenceCard(),
            const SizedBox(height: 18),
            _nextButton(),
          ],
          if (_wordComplete && !_showsSentences) ...[
            const SizedBox(height: 18),
            _nextButton(),
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
    );
  }

  Widget _nextButton() => V3PrimaryButton(
    label: _index == _entries.length - 1 ? 'Finish set' : 'Next word',
    icon: _index == _entries.length - 1
        ? Icons.check_rounded
        : Icons.arrow_forward_rounded,
    onPressed: _next,
  );

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
            text: entry.fr,
            label: 'Listen to word',
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
                Align(
                  alignment: Alignment.centerLeft,
                  child: TtsPlayButton(
                    text: example.fr,
                    label: 'Repeat sentence',
                    contentItemId: _audioId(_current, 'sentence'),
                    audioResolver: () => GeminiLiveAudioService.shared.resolve(
                      text: example.fr,
                      contentItemId: _audioId(_current, 'sentence'),
                      voiceName: ActiveTutor.current.voiceName,
                    ),
                    color: DesignTokens.nightAccent,
                    size: 40,
                    iconSize: 19,
                  ),
                ),
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
