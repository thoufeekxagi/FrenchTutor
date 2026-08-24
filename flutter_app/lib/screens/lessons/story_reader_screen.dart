import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/tokens.dart';
import '../../data/database/story_favorite_store.dart';
import '../../models/content_models.dart';
import '../../models/tutor_persona.dart';
import '../../prompts/live_prompts.dart';
import '../../providers/database_provider.dart';
import '../../services/inline_call_controller.dart';
import '../../services/lesson_agent_service.dart';
import '../../services/lesson_speech_service.dart';
import '../../services/session_settings.dart';
import '../../widgets/story_cover_image.dart';
import '../../services/session_recorder.dart';
import '../../widgets/bilingual_word_text.dart';
import '../../widgets/floating_notetaker.dart';
import '../../widgets/inline_call_bar.dart';
import '../../widgets/learning_card.dart';
import '../../widgets/report_problem_button.dart';
import '../../widgets/tts_play_button.dart';
import '../../widgets/web/web_constrained_view.dart';

enum _StoryTab { story, grammar, quiz, keywords }

/// Popped by [StoryReaderScreen] when [StoryReaderScreen.showFinishButton] is
/// true — how many of the story's own quiz questions the learner answered
/// correctly, for callers (the mission flow) that need to objectively grade
/// this like the old listening exercises did.
class StoryReaderResult {
  const StoryReaderResult({required this.correct, required this.attempted});

  final int correct;
  final int attempted;
}

/// A short, AI-generated bilingual story presented the way a learner reads
/// it — French line, English line right below it, one paragraph at a time,
/// with sentence-by-sentence audio underneath — split across Story/Grammar/
/// Quiz/Keywords tabs (Readle-style structure; our own palette, never
/// theirs). Quiz and Keywords are generated once alongside the story (see
/// LessonAgentService.buildStoryQuizAndKeywords) and saved with it, so they're
/// ready here rather than regenerated on every open; either can still be
/// empty if that generation call failed, in which case its tab falls back
/// to a placeholder.
class StoryReaderScreen extends ConsumerStatefulWidget {
  const StoryReaderScreen({
    super.key,
    required this.story,
    this.showFinishButton = false,
    this.enrichment,
    this.onEnriched,
    this.grammarExplanation,
    this.grammarTabLabel = 'Grammar',
  });

  final GeneratedStory story;

  /// Present for a grammar- or liaison-practice session (see
  /// `LessonAgentService.buildGrammarExplanation`/`buildLiaisonExplanation`)
  /// — when set, this explanation is shown ABOVE the per-sentence notes on
  /// the Grammar/Liaison tab, and a cue card on the Story tab invites the
  /// learner there: the rule is taught first, the story is the vehicle that
  /// demonstrates it, but the story itself still leads on open.
  final GrammarExplanation? grammarExplanation;

  /// The tab's label when [grammarExplanation] is set — "Grammar" by
  /// default, "Liaison" for a liaison-practice session. Purely cosmetic;
  /// both share the exact same tab/reader/explanation-card machinery.
  final String grammarTabLabel;

  /// True when this screen is a step in a larger flow (e.g. a mission) that
  /// needs the learner to explicitly finish and hand back a graded result —
  /// shows a "Continue" button that pops a [StoryReaderResult]. False (the
  /// default, used by the story library) shows no such button; the learner
  /// just backs out whenever they're done reading.
  final bool showFinishButton;

  /// The story's Quiz/Keywords, still generating when this screen opens —
  /// [story] is shown immediately once its passage is ready rather than
  /// making the learner wait through a second Gemini call first; when this
  /// resolves, the Quiz/Keywords tabs populate in place. Null means the
  /// story was opened from the library, already fully generated.
  final Future<
    ({List<MultipleChoiceQuestion> quiz, List<VocabEntry> keywords})
  >?
  enrichment;

  /// Fires once [enrichment] resolves, so the caller can persist the result
  /// (e.g. `GeneratedStoryStore.updateEnrichment`) — this screen only holds
  /// it in memory for display, it doesn't own storage.
  final void Function(
    List<MultipleChoiceQuestion> quiz,
    List<VocabEntry> keywords,
  )?
  onEnriched;

  @override
  ConsumerState<StoryReaderScreen> createState() => _StoryReaderScreenState();
}

class _StoryReaderScreenState extends ConsumerState<StoryReaderScreen>
    with WidgetsBindingObserver {
  final SessionSettings _settings = SessionSettings.shared;
  // Story always leads, even for a grammar-practice session — the story is
  // the point, grammar is a cue card away, not the landing screen.
  _StoryTab _tab = _StoryTab.story;
  int _currentSegment = 0;
  bool _isPlaying = false;
  bool _isLoadingAudio = false;
  double _rate = 0.42; // matches LessonSpeechService's own default "normal"
  double _textScale = 1;
  bool _translateSentences = true;
  bool _highlightWords = true;
  bool _underlineWords = true;
  bool _autoPlayWordAudio = false;
  bool _darkMode = true;
  bool _isLiked = false;
  bool? _selectedWordConjugatable;
  VocabEntry? _resolvedWordMeaning;
  bool _isMarkedLearned = false;
  final Map<int, GlobalKey> _segmentKeys = {};
  final Map<int, int> _quizAnswers = {};
  final Map<String, GlobalKey<TtsPlayButtonState>> _keywordAudioKeys = {};

  /// The sentence the learner tapped to read from — null means "no pick, play
  /// the whole story from the top". Tapping the same sentence again clears the
  /// pick. The selection controls playback only; sentence cards do not receive
  /// a separate selection highlight.
  /// Distinct from [_currentSegment], which tracks the segment actually
  /// playing right now (for auto-scroll and word-level playback feedback).
  int? _selectedSegment;

  /// The word selected for meaning in the story. Only one word is selected at
  /// a time so its glossary match can be highlighted in the English line too.
  int? _selectedWordSegment;
  int? _selectedWord;

  /// Which word (by index, split on whitespace) within the currently-playing
  /// segment's French text the narration has reached — null when nothing is
  /// playing, or once a segment's estimated timing runs past its last word.
  /// Timing comes from `LessonSpeechService`'s `onWordBoundary`, estimated
  /// from the known playback duration, not exact phoneme timing.
  int? _currentWord;

  /// Artwork is generated independently of the story text so the learner can
  /// enter immediately. Keep the open reader watching the saved story until
  /// the background upload fills in its cover URL.
  Timer? _coverRefreshTimer;

  /// Starts as [StoryReaderScreen.story]; replaced once [StoryReaderScreen.enrichment]
  /// resolves, so the Quiz/Keywords tabs update without navigating away.
  late GeneratedStory _story = widget.story;
  bool _enriching = false;

  ReadingPassage get _passage => _story.passage;

  String get _lessonContext {
    final base = ref.read(contentServiceProvider).storyContext(_passage);
    final explanation = widget.grammarExplanation;
    if (explanation == null) return base;
    // Marie needs the FULL taught explanation, not just the story — this is
    // what lets her actually answer "how does this change from present to
    // past" instead of only being able to talk about the story's sentences.
    final buf = StringBuffer(base)
      ..writeln()
      ..writeln('GRAMMAR POINT BEING TAUGHT: ${explanation.title}')
      ..writeln(explanation.summary)
      ..writeln('Usage rules: ${explanation.usage.join('; ')}')
      ..writeln(
        'How it contrasts with other tenses: ${explanation.tenseContrast}',
      );
    for (final c in explanation.conjugations) {
      buf.writeln(
        '${c.verb} (${c.group}): ${c.rows.map((r) => "${r.pronoun} ${r.form}").join(', ')}',
      );
    }
    return buf.toString();
  }

  GlobalKey _keyFor(int index) =>
      _segmentKeys.putIfAbsent(index, GlobalKey.new);

  late final SessionRecorder _recorder;

  /// Marie's live-call button, inline in the AppBar — same
  /// InlineCallController every other reading/exercise screen uses, so
  /// asking her about the story happens right here without leaving the
  /// page, not in a separate fullscreen call window.
  late final InlineCallController _call;
  late final StoryFavoriteStore _favorites;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _favorites = ref.read(storyFavoriteStoreProvider);
    _call = InlineCallController(
      sessionType: LiveSessionType.labAssistant,
      lessonContext: () => _lessonContext,
      learningStoreForProfile: ref.read(learningStoreProvider),
      onChanged: () {
        if (mounted) setState(() {});
      },
      // Closures, not direct tear-offs — `_recorder` isn't assigned yet at
      // this point in initState, only by the time a call actually connects.
      onUserTranscript: (text) => _recorder.logUser(text),
      onTutorTranscript: (text) => _recorder.logTutor(text),
    );
    _textScale = _settings.textScale;
    _rate = _settings.playbackRate;
    _translateSentences = _settings.translateSentences;
    _highlightWords = _settings.highlightWords;
    _underlineWords = _settings.underlineWords;
    _autoPlayWordAudio = _settings.autoPlayWordAudio;
    _darkMode = _settings.darkMode;
    unawaited(
      _settings.load().then((_) {
        if (!mounted) return;
        setState(() {
          _textScale = _settings.textScale;
          _rate = _settings.playbackRate;
          _translateSentences = _settings.translateSentences;
          _highlightWords = _settings.highlightWords;
          _underlineWords = _settings.underlineWords;
          _autoPlayWordAudio = _settings.autoPlayWordAudio;
          _darkMode = _settings.darkMode;
        });
      }),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(notetakerStateProvider).currentContext = 'Story';
    });
    _recorder = SessionRecorder(
      storage: ref.read(storageServiceProvider),
      stage: 'story',
      topic: _story.displayTitle,
    );
    unawaited(_loadFavorite());
    if (_story.coverUrl == null || _story.coverUrl!.isEmpty) {
      _coverRefreshTimer = Timer.periodic(
        const Duration(seconds: 2),
        (_) => _refreshCoverFromStore(),
      );
    }
    final enrichment = widget.enrichment;
    if (enrichment != null) {
      _enriching = true;
      enrichment.then(
        (result) {
          widget.onEnriched?.call(result.quiz, result.keywords);
          if (!mounted) return;
          setState(() {
            _enriching = false;
            _story = _story.copyWith(
              quiz: result.quiz,
              keywords: result.keywords,
            );
          });
        },
        onError: (_) {
          if (mounted) setState(() => _enriching = false);
        },
      );
    }
  }

  /// P0.4 pocket/lock-screen handling, same contract as every other live
  /// call screen — forwarded straight to the shared controller.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _call.handleAppLifecycle(state);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _coverRefreshTimer?.cancel();
    _call.dispose();
    LessonSpeechService.shared.stop();
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
            .list(practiceMode: 'reading')) {
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

  void _finishSession() {
    if (_quizAnswers.isEmpty) {
      _recorder.finish(summary: 'Read "${_story.displayTitle}".');
      return;
    }
    final quiz = _story.quiz;
    var correct = 0;
    for (final entry in _quizAnswers.entries) {
      if (entry.key < quiz.length &&
          entry.value == quiz[entry.key].answerIndex) {
        correct++;
      }
    }
    _recorder.finish(
      summary:
          'Read "${_story.displayTitle}", scored $correct/${_quizAnswers.length} on the quiz.',
    );
  }

  Future<void> _playAll({int fromIndex = 0}) async {
    final segments = _passage.segments;
    if (segments.isEmpty) return;
    setState(() {
      _isPlaying = true;
      _isLoadingAudio = true;
      _currentSegment = fromIndex;
    });
    await LessonSpeechService.shared.speak(
      items: [
        for (var i = fromIndex; i < segments.length; i++)
          SpeechItem(
            text: segments[i].fr,
            language: 'fr-FR',
            contentItemId: _story.segmentContentId(i),
          ),
      ],
      rate: _rate,
      onItemStart: (i) {
        if (!mounted) return;
        setState(() {
          _currentSegment = fromIndex + i;
          _currentWord = null;
        });
        _scrollToCurrent();
      },
      onPlaybackReady: () {
        if (mounted) setState(() => _isLoadingAudio = false);
      },
      onError: (error) {
        if (!mounted) return;
        setState(() {
          _isPlaying = false;
          _isLoadingAudio = false;
          _currentWord = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Audio is unavailable right now. Please try again.'),
          ),
        );
      },
      onWordBoundary: (_, wordIndex) {
        if (!mounted) return;
        setState(() => _currentWord = wordIndex);
      },
      onFinished: () {
        if (!mounted) return;
        setState(() {
          _isPlaying = false;
          _isLoadingAudio = false;
          _currentWord = null;
        });
      },
    );
  }

  void _scrollToCurrent() {
    final key = _segmentKeys[_currentSegment];
    final ctx = key?.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: DesignTokens.durationMedium,
      curve: DesignTokens.curveStandard,
      alignment: 0.3,
    );
  }

  Future<void> _togglePlayPause() async {
    final speech = LessonSpeechService.shared;
    if (_isLoadingAudio) return;
    if (_isPlaying && !speech.isPaused) {
      await speech.pause();
      if (mounted) setState(() => _isPlaying = false);
    } else if (speech.isPaused) {
      await speech.resume();
      if (mounted) setState(() => _isPlaying = true);
    } else {
      await _playAll(fromIndex: _selectedSegment ?? 0);
    }
  }

  Future<void> _switchTab(_StoryTab tab) async {
    if (_tab == tab) return;
    if (_tab == _StoryTab.story) await _stop();
    if (mounted) setState(() => _tab = tab);
  }

  void _goToStage(int index) {
    switch (index) {
      case 0:
        unawaited(_switchTab(_StoryTab.story));
      case 1:
        unawaited(_switchTab(_StoryTab.quiz));
      case 2:
        unawaited(_switchTab(_StoryTab.keywords));
      case 3:
        unawaited(_switchTab(_StoryTab.grammar));
    }
  }

  void _advanceTab() {
    switch (_tab) {
      case _StoryTab.story:
        unawaited(_switchTab(_StoryTab.quiz));
      case _StoryTab.quiz:
        unawaited(_switchTab(_StoryTab.keywords));
      case _StoryTab.keywords:
        unawaited(_switchTab(_StoryTab.grammar));
      case _StoryTab.grammar:
        if (widget.showFinishButton) {
          _finish();
        } else {
          Navigator.pop(context);
        }
    }
  }

  void _retreatTab() {
    switch (_tab) {
      case _StoryTab.story:
        return;
      case _StoryTab.quiz:
        unawaited(_switchTab(_StoryTab.story));
      case _StoryTab.keywords:
        unawaited(_switchTab(_StoryTab.quiz));
      case _StoryTab.grammar:
        unawaited(_switchTab(_StoryTab.keywords));
    }
  }

  String get _nextTabLabel => switch (_tab) {
    _StoryTab.story => 'Quiz',
    _StoryTab.quiz => 'Keywords',
    _StoryTab.keywords => 'Grammar',
    _StoryTab.grammar => widget.showFinishButton ? 'Finish' : 'Done',
  };

  Future<void> _stop() async {
    await LessonSpeechService.shared.stop();
    if (mounted) {
      setState(() {
        _isPlaying = false;
        _isLoadingAudio = false;
        _currentWord = null;
      });
    }
  }

  void _selectSegment(int index) {
    setState(() {
      final keepsWordSelection = _selectedWordSegment == index;
      _selectedSegment = _selectedSegment == index ? null : index;
      // A word tap is nested inside the sentence gesture. Keep its meaning
      // highlight if the parent recognizer also receives that same tap, so
      // narration never clears or changes the learner's selection.
      if (!keepsWordSelection) {
        _selectedWordSegment = null;
        _selectedWord = null;
      }
    });
  }

  void _selectWord(int segmentIndex, int wordIndex) {
    final sameWord =
        _selectedWordSegment == segmentIndex && _selectedWord == wordIndex;
    setState(() {
      _selectedSegment = segmentIndex;
      if (sameWord) {
        _selectedWordSegment = null;
        _selectedWord = null;
        _resolvedWordMeaning = null;
        _selectedWordConjugatable = null;
      } else {
        _selectedWordSegment = segmentIndex;
        _selectedWord = wordIndex;
        _resolvedWordMeaning = _fallbackWordEntry(segmentIndex, wordIndex);
        _selectedWordConjugatable = _heuristicWordCanConjugate(segmentIndex);
      }
    });
    if (!sameWord) unawaited(_resolveWordMeaning(segmentIndex, wordIndex));
  }

  Future<void> _loadFavorite() async {
    final favorite = _favorites.isFavorite(_story.id);
    if (mounted) setState(() => _isLiked = favorite);
  }

  void _toggleFavorite() {
    final next = !_isLiked;
    setState(() => _isLiked = next);
    _favorites.setFavorite(_story.id, next);
  }

  void _cycleTextSize() {
    final next = _textScale < 0.98
        ? 1.0
        : _textScale < 1.15
        ? 1.25
        : 0.9;
    setState(() => _textScale = next);
    unawaited(_settings.setTextScale(next));
  }

  /// Plays just the one picked sentence (or the current one if nothing is
  /// picked), not the rest of the story — for "let me hear that one line
  /// again" rather than "keep reading from here".
  Future<void> _playSelectedSentence() async {
    if (_isLoadingAudio) return;
    final segments = _passage.segments;
    final index = _selectedSegment ?? _currentSegment;
    if (index < 0 || index >= segments.length) return;
    setState(() {
      _isPlaying = true;
      _isLoadingAudio = true;
      _currentSegment = index;
    });
    await LessonSpeechService.shared.speak(
      items: [
        SpeechItem(
          text: segments[index].fr,
          language: 'fr-FR',
          contentItemId: _story.segmentContentId(index),
        ),
      ],
      rate: _rate,
      onItemStart: (_) {
        if (!mounted) return;
        setState(() => _currentWord = null);
        _scrollToCurrent();
      },
      onPlaybackReady: () {
        if (mounted) setState(() => _isLoadingAudio = false);
      },
      onError: (error) {
        if (!mounted) return;
        setState(() {
          _isPlaying = false;
          _isLoadingAudio = false;
          _currentWord = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Audio is unavailable right now. Please try again.'),
          ),
        );
      },
      onWordBoundary: (_, wordIndex) {
        if (!mounted) return;
        setState(() => _currentWord = wordIndex);
      },
      onFinished: () {
        if (!mounted) return;
        setState(() {
          _isPlaying = false;
          _isLoadingAudio = false;
          _currentWord = null;
        });
      },
    );
  }

  void _cycleRate() {
    setState(() => _rate = _rate <= 0.36 ? 0.55 : 0.32);
    unawaited(_settings.setPlaybackRate(_rate));
  }

  Future<void> _showSettings() async {
    final result = await showModalBottomSheet<_ReaderSettingsResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _StorySettingsSheet(
        textScale: _textScale,
        rate: _rate,
        translateSentences: _translateSentences,
        highlightWords: _highlightWords,
        underlineWords: _underlineWords,
        autoPlayWordAudio: _autoPlayWordAudio,
        darkMode: _darkMode,
      ),
    );
    if (!mounted || result == null) return;
    setState(() {
      _textScale = result.textScale;
      _rate = result.rate;
      _translateSentences = result.translateSentences;
      _highlightWords = result.highlightWords;
      _underlineWords = result.underlineWords;
      _autoPlayWordAudio = result.autoPlayWordAudio;
      _darkMode = result.darkMode;
    });
    unawaited(_settings.setTextScale(_textScale));
    unawaited(_settings.setPlaybackRate(_rate));
    unawaited(_settings.setTranslateSentences(_translateSentences));
    unawaited(_settings.setHighlightWords(_highlightWords));
    unawaited(_settings.setUnderlineWords(_underlineWords));
    unawaited(_settings.setAutoPlayWordAudio(_autoPlayWordAudio));
    unawaited(_settings.setDarkMode(_darkMode));
  }

  void _markAsLearned() {
    setState(() => _isMarkedLearned = true);
    if (widget.showFinishButton) {
      _finish();
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Story marked as learned.')));
  }

  bool get _selectedWordCanConjugate {
    final segmentIndex = _selectedWordSegment;
    if (segmentIndex == null ||
        segmentIndex < 0 ||
        segmentIndex >= _passage.segments.length) {
      return false;
    }
    if (_selectedWordConjugatable == true) return true;
    final note = _passage.segments[segmentIndex].grammarNote.toLowerCase();
    final noteSuggestsVerb = RegExp(
      r'\b(verb|conjugat|tense|present|past|future|imparfait|conditionnel|impératif)\b',
    ).hasMatch(note);
    if (noteSuggestsVerb) return true;
    final word = _selectedWordEntry()?.fr.toLowerCase() ?? '';
    return RegExp(r'(er|ir|re|oir)$').hasMatch(word);
  }

  Future<void> _showConjugation() async {
    final entry = _selectedWordEntry();
    final segmentIndex = _selectedWordSegment;
    if (entry == null || segmentIndex == null) return;
    final segment = _passage.segments[segmentIndex];
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ConjugationSheet(
        darkMode: _darkMode,
        word: entry.fr,
        translation: entry.en,
        future: LessonAgentService.shared.buildWordConjugation(
          word: entry.fr,
          translation: entry.en,
          sentence: segment.fr,
          levelBand: _story.levelBand,
        ),
      ),
    );
  }

  Future<void> _resolveWordMeaning(int segmentIndex, int wordIndex) async {
    if (segmentIndex < 0 || segmentIndex >= _passage.segments.length) return;
    final segment = _passage.segments[segmentIndex];
    final words = _wordParts(segment.fr);
    if (wordIndex < 0 || wordIndex >= words.length) return;
    final selectedWord = _cleanStoryWord(words[wordIndex]);
    if (selectedWord.isEmpty) return;
    try {
      final data = await LessonAgentService.shared.buildWordMeaning(
        word: selectedWord,
        sentence: segment.fr,
        sentenceTranslation: segment.en,
        levelBand: _story.levelBand,
      );
      if (!mounted ||
          _selectedWordSegment != segmentIndex ||
          _selectedWord != wordIndex) {
        return;
      }
      final translation = data['translation']?.toString().trim() ?? '';
      final resolvedTranslation = translation.isNotEmpty
          ? translation
          : _fallbackTranslationForWord(segment, wordIndex);
      final rawWord = data['word']?.toString().trim() ?? '';
      final resolvedWord = rawWord.isNotEmpty ? rawWord : selectedWord;
      final partOfSpeech =
          data['part_of_speech']?.toString().toLowerCase() ?? '';
      setState(() {
        _resolvedWordMeaning = VocabEntry(
          id: 'story:${_story.id}:$segmentIndex:$wordIndex',
          fr: resolvedWord,
          en: resolvedTranslation,
          phonetic: '',
        );
        _selectedWordConjugatable =
            data['can_conjugate'] == true || partOfSpeech.contains('verb');
      });
    } catch (_) {
      // The local positional meaning remains visible if the model is
      // unavailable. Tapping another word can retry independently.
    }
  }

  void _toggleTranslation() {
    setState(() => _translateSentences = !_translateSentences);
    unawaited(_settings.setTranslateSentences(_translateSentences));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _darkMode
          ? DesignTokens.nightCanvas
          : DesignTokens.canvas,
      body: WebConstrainedView(
        maxWidth: 920,
        child: Stack(
          children: [
            Column(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    _StoryBookHeader(
                      story: _story,
                      darkMode: _darkMode,
                      selectedWord: _selectedWordEntry(),
                      learned: _isMarkedLearned,
                      onBack: () => Navigator.maybePop(context),
                      onMarkLearned: _markAsLearned,
                      onSettings: _showSettings,
                      onConjugate: _selectedWordCanConjugate
                          ? _showConjugation
                          : null,
                      callActions: InlineCallActions(
                        controller: _call,
                        accentColor: _darkMode
                            ? DesignTokens.nightAccent
                            : DesignTokens.primary,
                      ),
                    ),
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: -24,
                      child: _StoryStageIsland(
                        labels: const ['Story', 'Quiz', 'Keywords', 'Grammar'],
                        currentIndex: switch (_tab) {
                          _StoryTab.story => 0,
                          _StoryTab.quiz => 1,
                          _StoryTab.keywords => 2,
                          _StoryTab.grammar => 3,
                        },
                        onIndexTap: _goToStage,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                if (_call.isLive || _call.error != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: InlineCallStatusCard(
                      controller: _call,
                      listeningLabel: 'Listening. Ask about the story anytime.',
                    ),
                  ),
                Divider(
                  height: 1,
                  color: _darkMode
                      ? DesignTokens.nightHairline
                      : DesignTokens.hairline,
                ),
                Expanded(
                  child: switch (_tab) {
                    _StoryTab.story => _storyView(),
                    _StoryTab.grammar => _grammarView(),
                    _StoryTab.quiz => _quizView(),
                    _StoryTab.keywords => _keywordsView(),
                  },
                ),
                if (_tab == _StoryTab.story &&
                    widget.grammarExplanation != null)
                  _GrammarCueCard(
                    grammarPoint: widget.grammarExplanation!.title,
                    tabLabel: widget.grammarTabLabel,
                    onTap: () => setState(() => _tab = _StoryTab.grammar),
                  ),
              ],
            ),
            Positioned(
              bottom: 10,
              left: 0,
              right: 0,
              child: SafeArea(
                top: false,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: _tab == _StoryTab.story
                      ? IntrinsicWidth(
                          child: _AudioControlBar(
                            isPlaying: _isPlaying,
                            isLoading: _isLoadingAudio,
                            rate: _rate,
                            onTogglePlayPause: _togglePlayPause,
                            onStop: _stop,
                            onPlaySentence: _playSelectedSentence,
                            onCycleRate: _cycleRate,
                            onNext: _advanceTab,
                            darkMode: _darkMode,
                          ),
                        )
                      : Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: _StoryNextBar(
                            label: _nextTabLabel,
                            onPressed: _advanceTab,
                            onBack: _retreatTab,
                            darkMode: _darkMode,
                          ),
                        ),
                ),
              ),
            ),
            FloatingNotetakerOverlay(state: ref.watch(notetakerStateProvider)),
          ],
        ),
      ),
    );
  }

  void _finish() {
    final quiz = _story.quiz;
    var correct = 0;
    for (var i = 0; i < quiz.length; i++) {
      if (_quizAnswers[i] == quiz[i].answerIndex) correct++;
    }
    Navigator.pop(
      context,
      StoryReaderResult(correct: correct, attempted: quiz.length),
    );
  }

  VocabEntry? _selectedWordEntry() {
    final segmentIndex = _selectedWordSegment;
    final wordIndex = _selectedWord;
    if (segmentIndex == null || wordIndex == null) return null;
    if (segmentIndex < 0 || segmentIndex >= _passage.segments.length) {
      return null;
    }
    final words = _wordParts(_passage.segments[segmentIndex].fr);
    if (wordIndex < 0 || wordIndex >= words.length) return null;
    if (_selectedWordSegment == segmentIndex &&
        _selectedWord == wordIndex &&
        _resolvedWordMeaning != null) {
      return _resolvedWordMeaning;
    }
    return _fallbackWordEntry(segmentIndex, wordIndex);
  }

  VocabEntry _fallbackWordEntry(int segmentIndex, int wordIndex) {
    final segment = _passage.segments[segmentIndex];
    final words = _wordParts(segment.fr);
    final selected = _foldStoryWord(words[wordIndex]);
    for (final entry in _story.keywords) {
      if (_wordParts(entry.fr).map(_foldStoryWord).contains(selected)) {
        return entry;
      }
    }
    return VocabEntry(
      id: 'story:${_story.id}:$segmentIndex:$wordIndex',
      fr: _cleanStoryWord(words[wordIndex]),
      en: _fallbackTranslationForWord(segment, wordIndex),
      phonetic: '',
    );
  }

  String _fallbackTranslationForWord(ReadingSegment segment, int wordIndex) {
    final sourceWords = _wordParts(segment.fr);
    final translationWords = _wordParts(segment.en);
    if (translationWords.isEmpty) return 'Meaning unavailable';
    final mapped = (wordIndex * translationWords.length / sourceWords.length)
        .floor()
        .clamp(0, translationWords.length - 1);
    return _cleanStoryWord(translationWords[mapped]);
  }

  bool _heuristicWordCanConjugate(int segmentIndex) {
    final note = _passage.segments[segmentIndex].grammarNote.toLowerCase();
    return RegExp(
      r'\b(verb|conjugat|tense|present|past|future|imparfait|conditionnel|impératif)\b',
    ).hasMatch(note);
  }

  String _cleanStoryWord(String value) => value
      .replaceAll(RegExp(r'^[.,!?;:«»"“”¿¡()\[\]]+'), '')
      .replaceAll(RegExp(r'[.,!?;:«»"“”¿¡()\[\]]+$'), '')
      .trim();

  Widget _storyView() {
    final segments = _passage.segments;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 140),
      children: [
        _storyIntro(),
        const SizedBox(height: 18),
        if (segments.isEmpty)
          Text(
            _passage.fullText.isNotEmpty
                ? _passage.fullText
                : 'This story is still loading. Reopen it after generation finishes.',
            style: DesignTokens.body(18 * _textScale).copyWith(
              color: _darkMode ? DesignTokens.nightText : DesignTokens.ink,
              height: 1.55,
            ),
          )
        else
          _storyReadingText(segments),
      ],
    );
  }

  Widget _storyReadingText(List<ReadingSegment> segments) {
    final text = _darkMode ? DesignTokens.nightText : DesignTokens.ink;
    final muted = _darkMode ? DesignTokens.nightMuted : DesignTokens.mutedDim;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in segments.asMap().entries) ...[
          if (entry.key > 0) SizedBox(height: _translateSentences ? 22 : 8),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _selectSegment(entry.key),
            child: BilingualWordText(
              key: _keyFor(entry.key),
              source: entry.value.fr,
              translation: entry.value.en,
              sourceStyle: DesignTokens.body(
                18 * _textScale,
              ).copyWith(color: text, height: 1.52),
              translationStyle: DesignTokens.body(
                15 * _textScale,
              ).copyWith(color: muted, height: 1.45),
              keywords: _story.keywords,
              showTranslation: _translateSentences,
              highlightSelected: _highlightWords,
              underlineSelected: _underlineWords,
              accentColor: _darkMode
                  ? DesignTokens.nightAccent
                  : DesignTokens.primary,
              selectedSourceWord: _selectedWordSegment == entry.key
                  ? _selectedWord
                  : null,
              playbackSourceWord: _isPlaying && _currentSegment == entry.key
                  ? _currentWord
                  : null,
              playbackTranslationWord:
                  _isPlaying && _currentSegment == entry.key
                  ? _mappedTranslationWord(
                      currentWord: _currentWord,
                      source: entry.value.fr,
                      translation: entry.value.en,
                    )
                  : null,
              onSourceWordTap: (wordIndex) => _selectWord(entry.key, wordIndex),
            ),
          ),
        ],
      ],
    );
  }

  Widget _storyIntro() {
    final text = _darkMode ? DesignTokens.nightText : DesignTokens.ink;
    final muted = _darkMode ? DesignTokens.nightMuted : DesignTokens.mutedDim;
    final accent = _darkMode ? DesignTokens.nightAccent : DesignTokens.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _story.displayTitle,
          style: DesignTokens.display(29).copyWith(color: text, height: 1.08),
        ),
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.start,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 2,
          runSpacing: 2,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _story.levelBand,
                style: DesignTokens.mono(
                  11,
                  weight: FontWeight.w800,
                ).copyWith(color: accent),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '• ${_story.readTimeMinutes} min read',
              style: DesignTokens.body(
                13,
                weight: FontWeight.w600,
              ).copyWith(color: muted),
            ),
            const SizedBox(width: 4),
            IconButton(
              onPressed: _toggleTranslation,
              tooltip: _translateSentences
                  ? 'Hide translation'
                  : 'Show translation',
              visualDensity: VisualDensity.compact,
              icon: Icon(
                Icons.translate,
                color: _translateSentences ? accent : muted,
                size: 22,
              ),
            ),
            IconButton(
              onPressed: _cycleTextSize,
              tooltip: 'Text size: ${_textSizeLabel(_textScale)}',
              visualDensity: VisualDensity.compact,
              icon: Icon(
                CupertinoIcons.textformat_size,
                color: muted,
                size: 23,
              ),
            ),
            IconButton(
              onPressed: _toggleFavorite,
              tooltip: _isLiked ? 'Unlike story' : 'Like story',
              visualDensity: VisualDensity.compact,
              icon: Icon(
                _isLiked ? CupertinoIcons.heart_fill : CupertinoIcons.heart,
                color: _isLiked ? accent : muted,
                size: 23,
              ),
            ),
            ReportProblemButton(sessionType: 'Story: ${_story.displayTitle}'),
          ],
        ),
      ],
    );
  }

  String _textSizeLabel(double scale) {
    if (scale < 0.98) return 'Small';
    if (scale < 1.15) return 'Medium';
    return 'Large';
  }

  Widget _grammarView() {
    final points = <ReadingSegment>[];
    final seenNotes = <String>{};
    for (final segment in _passage.segments) {
      if (segment.grammarNote.isEmpty) continue;
      if (!seenNotes.add(segment.grammarNote)) continue;
      points.add(segment);
    }
    final explanation = widget.grammarExplanation;
    if (points.isEmpty && explanation == null) {
      return const _ComingSoon(label: 'Grammar');
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 140),
      children: [
        if (explanation != null) ...[
          _GrammarExplanationCard(
            explanation: explanation,
            darkMode: _darkMode,
          ),
          const SizedBox(height: 20),
          if (points.isNotEmpty)
            Text(
              'HOW THE STORY USES IT',
              style: DesignTokens.mono(
                10.5,
                weight: FontWeight.w700,
              ).copyWith(color: DesignTokens.mutedDim, letterSpacing: 0.8),
            ),
          if (points.isNotEmpty) const SizedBox(height: 12),
        ],
        for (var i = 0; i < points.length; i++) ...[
          if (i > 0) const SizedBox(height: 14),
          LearningCard(
            padding: 16,
            color: _darkMode ? DesignTokens.nightSurface : DesignTokens.surface,
            borderColor: _darkMode
                ? DesignTokens.nightHairline
                : DesignTokens.hairline,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'From this story',
                        style: DesignTokens.mono(10.5, weight: FontWeight.w700)
                            .copyWith(
                              color: _darkMode
                                  ? DesignTokens.nightAccent
                                  : DesignTokens.primary,
                              letterSpacing: 0.8,
                            ),
                      ),
                    ),
                    TtsPlayButton(
                      text: points[i].fr,
                      size: DesignTokens.minTapTarget,
                      iconSize: 20,
                      label: 'Listen',
                      contentItemId: _story.segmentContentId(
                        _passage.segments.indexOf(points[i]),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  points[i].fr,
                  style: DesignTokens.body(15, weight: FontWeight.w600)
                      .copyWith(
                        color: _darkMode
                            ? DesignTokens.nightText
                            : DesignTokens.ink,
                      ),
                ),
                const SizedBox(height: 12),
                Text(
                  points[i].grammarNote,
                  style: DesignTokens.body(13.5).copyWith(
                    color: _darkMode
                        ? DesignTokens.nightMuted
                        : DesignTokens.inkSoft,
                    height: 1.4,
                  ),
                ),
                if (points[i].pronunciationTip.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        CupertinoIcons.waveform,
                        size: 15,
                        color: _darkMode
                            ? DesignTokens.nightMuted
                            : DesignTokens.mutedDim,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          points[i].pronunciationTip,
                          style: DesignTokens.body(12.5).copyWith(
                            color: _darkMode
                                ? DesignTokens.nightMuted
                                : DesignTokens.mutedDim,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _quizView() {
    final quiz = _story.quiz;
    if (quiz.isEmpty) {
      return _ComingSoon(label: 'Quiz', generating: _enriching);
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 140),
      itemCount: quiz.length,
      separatorBuilder: (_, _) => const SizedBox(height: 14),
      itemBuilder: (context, index) => _quizCard(index, quiz[index]),
    );
  }

  Widget _quizCard(int index, MultipleChoiceQuestion question) {
    final answered = _quizAnswers[index];
    final beginnerSupport = switch (_story.levelBand.toUpperCase()) {
      'A1' || 'A2' => true,
      _ => false,
    };
    return LearningCard(
      padding: 16,
      color: _darkMode ? DesignTokens.nightSurface : DesignTokens.surface,
      borderColor: _darkMode
          ? DesignTokens.nightHairline
          : DesignTokens.hairline,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            question.q,
            style: DesignTokens.body(15, weight: FontWeight.w600).copyWith(
              color: _darkMode ? DesignTokens.nightText : DesignTokens.ink,
            ),
          ),
          if (beginnerSupport && question.qEn != null) ...[
            const SizedBox(height: 4),
            Text(
              question.qEn!,
              style: DesignTokens.body(13).copyWith(
                color: _darkMode
                    ? DesignTokens.nightMuted
                    : DesignTokens.mutedDim,
                height: 1.3,
              ),
            ),
          ],
          const SizedBox(height: 12),
          for (var ci = 0; ci < question.choices.length; ci++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GestureDetector(
                onTap: answered == null
                    ? () => setState(() => _quizAnswers[index] = ci)
                    : null,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 11,
                  ),
                  decoration: BoxDecoration(
                    color: _darkMode
                        ? DesignTokens.nightSurfaceRaised
                        : DesignTokens.canvasDim,
                    borderRadius: BorderRadius.circular(
                      DesignTokens.radiusMedium,
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              question.choices[ci],
                              style: DesignTokens.body(13.5).copyWith(
                                color: _darkMode
                                    ? DesignTokens.nightText
                                    : DesignTokens.ink,
                              ),
                            ),
                            if (beginnerSupport &&
                                question.choicesEn != null &&
                                ci < question.choicesEn!.length) ...[
                              const SizedBox(height: 2),
                              Text(
                                question.choicesEn![ci],
                                style: DesignTokens.body(11.5).copyWith(
                                  color: _darkMode
                                      ? DesignTokens.nightMuted
                                      : DesignTokens.mutedDim,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (answered != null) ...[
                        if (ci == question.answerIndex)
                          Icon(
                            CupertinoIcons.checkmark_circle_fill,
                            color: DesignTokens.success,
                            size: 18,
                          )
                        else if (ci == answered)
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
      ),
    );
  }

  Widget _keywordsView() {
    final keywords = _story.keywords;
    if (keywords.isEmpty) {
      return _ComingSoon(label: 'Keywords', generating: _enriching);
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 140),
      itemCount: keywords.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final entry = keywords[index];
        final audioKey = _keywordAudioKeys.putIfAbsent(
          entry.id,
          GlobalKey<TtsPlayButtonState>.new,
        );
        return LearningCard(
          padding: 16,
          color: _darkMode ? DesignTokens.nightSurface : DesignTokens.surface,
          borderColor: _darkMode
              ? DesignTokens.nightHairline
              : DesignTokens.hairline,
          child: Semantics(
            button: true,
            label: 'Play pronunciation for ${entry.fr}',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => audioKey.currentState?.trigger(),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.fr,
                          style: DesignTokens.body(15, weight: FontWeight.w600)
                              .copyWith(
                                color: _darkMode
                                    ? DesignTokens.nightText
                                    : DesignTokens.ink,
                              ),
                        ),
                        if (entry.phonetic.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            entry.phonetic,
                            style: DesignTokens.mono(11).copyWith(
                              color: _darkMode
                                  ? DesignTokens.nightMuted
                                  : DesignTokens.mutedDim,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: Text(
                      entry.en,
                      style: DesignTokens.body(13.5).copyWith(
                        color: _darkMode
                            ? DesignTokens.nightAccent
                            : DesignTokens.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IgnorePointer(
                    child: TtsPlayButton(
                      key: audioKey,
                      text: entry.fr,
                      contentItemId: '${widget.story.id}_kw_${entry.id}',
                      audioResolver: () => _loadCachedKeywordAudio(entry),
                      onError: (error) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Audio failed: $error')),
                        );
                      },
                      size: DesignTokens.minTapTarget,
                      iconSize: 20,
                      color: _darkMode
                          ? DesignTokens.nightAccent
                          : DesignTokens.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Use the PCM cache first. If this individual keyword was not prewarmed
  /// yet, resolve the same French tutor voice live and cache the PCM before
  /// playing it. The card never silently does nothing.
  Future<List<int>?> _loadCachedKeywordAudio(VocabEntry entry) async {
    final cached = await LessonSpeechService.shared
        .loadCachedAudio(entry.fr)
        .timeout(const Duration(seconds: 6));
    if (cached != null && cached.isNotEmpty) return cached;
    return LessonSpeechService.shared.synthesize(
      entry.fr,
      voiceName: ActiveTutor.current.voiceName,
      contentItemId: '${widget.story.id}_kw_${entry.id}',
    );
  }
}

class _StoryBookHeader extends StatelessWidget {
  const _StoryBookHeader({
    required this.story,
    required this.darkMode,
    this.selectedWord,
    required this.learned,
    required this.onBack,
    required this.onMarkLearned,
    required this.onSettings,
    required this.onConjugate,
    required this.callActions,
  });

  final GeneratedStory story;
  final bool darkMode;
  final VocabEntry? selectedWord;
  final bool learned;
  final VoidCallback onBack;
  final VoidCallback onMarkLearned;
  final VoidCallback onSettings;
  final VoidCallback? onConjugate;
  final Widget callActions;

  @override
  Widget build(BuildContext context) {
    final accent = darkMode ? DesignTokens.nightAccent : DesignTokens.primary;
    final text = darkMode ? DesignTokens.nightText : DesignTokens.ink;
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
      child: SizedBox(
        height: 246,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(
              color: darkMode ? DesignTokens.nightSurface : DesignTokens.canvas,
              child: StoryCoverImage(
                title: story.title,
                source: story.coverUrl,
                fit: BoxFit.cover,
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.36),
                    Colors.black.withValues(alpha: 0.04),
                    Colors.black.withValues(alpha: 0.9),
                  ],
                ),
              ),
            ),
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _HeroIconButton(
                      icon: CupertinoIcons.chevron_left,
                      tooltip: 'Back',
                      onTap: onBack,
                    ),
                    const Spacer(),
                    Container(
                      height: 42,
                      padding: const EdgeInsets.symmetric(horizontal: 13),
                      decoration: BoxDecoration(
                        color: learned
                            ? accent.withValues(alpha: 0.94)
                            : Colors.black.withValues(alpha: 0.42),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.22),
                        ),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(22),
                        onTap: onMarkLearned,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              learned
                                  ? CupertinoIcons.checkmark
                                  : CupertinoIcons.checkmark,
                              size: 20,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 7),
                            Text(
                              learned ? 'Learned' : 'Mark as learned',
                              style: DesignTokens.body(
                                13,
                                weight: FontWeight.w700,
                              ).copyWith(color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    _HeroIconButton(
                      icon: CupertinoIcons.slider_horizontal_3,
                      tooltip: 'Story settings',
                      onTap: onSettings,
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 14,
              right: selectedWord == null ? 14 : 132,
              bottom: selectedWord == null ? 18 : 8,
              child: selectedWord == null
                  ? const SizedBox.shrink()
                  : _SelectedWordOverlay(
                      word: selectedWord!,
                      accent: accent,
                      darkMode: darkMode,
                      onConjugate: onConjugate,
                    ),
            ),
            Positioned(
              right: 14,
              bottom: 12,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DefaultTextStyle.merge(
                    style: TextStyle(color: text),
                    child: callActions,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroIconButton extends StatelessWidget {
  const _HeroIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tooltip,
      child: IconButton(
        onPressed: onTap,
        tooltip: tooltip,
        visualDensity: VisualDensity.compact,
        icon: Icon(icon, color: Colors.white, size: 24),
        style: IconButton.styleFrom(
          backgroundColor: Colors.black.withValues(alpha: 0.38),
          shape: const CircleBorder(),
        ),
      ),
    );
  }
}

class _SelectedWordOverlay extends StatelessWidget {
  const _SelectedWordOverlay({
    required this.word,
    required this.accent,
    required this.darkMode,
    this.onConjugate,
  });

  final VocabEntry word;
  final Color accent;
  final bool darkMode;
  final VoidCallback? onConjugate;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          word.fr,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: DesignTokens.display(
            24,
          ).copyWith(color: Colors.white, height: 1.05),
        ),
        const SizedBox(height: 3),
        Text(
          word.en,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: DesignTokens.body(
            14,
          ).copyWith(color: Colors.white.withValues(alpha: 0.9), height: 1.25),
        ),
        const SizedBox(height: 8),
        if (onConjugate != null)
          DecoratedBox(
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(18),
            ),
            child: InkWell(
              onTap: onConjugate,
              borderRadius: BorderRadius.circular(18),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                child: Text(
                  'Conjugate  →',
                  style: DesignTokens.body(12, weight: FontWeight.w800)
                      .copyWith(
                        color: darkMode
                            ? DesignTokens.nightCanvas
                            : Colors.white,
                      ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ConjugationSheet extends StatelessWidget {
  const _ConjugationSheet({
    required this.future,
    required this.darkMode,
    required this.word,
    required this.translation,
  });

  final Future<Map<String, dynamic>> future;
  final bool darkMode;
  final String word;
  final String translation;

  @override
  Widget build(BuildContext context) {
    final surface = darkMode ? DesignTokens.nightSurfaceRaised : Colors.white;
    final text = darkMode ? DesignTokens.nightText : DesignTokens.ink;
    final muted = darkMode ? DesignTokens.nightMuted : DesignTokens.mutedDim;
    final accent = darkMode ? DesignTokens.nightAccent : DesignTokens.primary;
    return SafeArea(
      child: Container(
        constraints: const BoxConstraints(maxHeight: 620),
        margin: const EdgeInsets.all(10),
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(30),
        ),
        child: FutureBuilder<Map<String, dynamic>>(
          future: future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const SizedBox(
                height: 240,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.hasError || snapshot.data == null) {
              return SizedBox(
                height: 220,
                child: Center(
                  child: Text(
                    'The conjugation is unavailable right now. Try again in a moment.',
                    textAlign: TextAlign.center,
                    style: DesignTokens.body(15).copyWith(color: muted),
                  ),
                ),
              );
            }
            final data = snapshot.data!;
            final conjugation = (data['conjugation'] as List? ?? const [])
                .whereType<Map>()
                .toList();
            final metadata = [
              data['part_of_speech']?.toString() ?? '',
              data['gender']?.toString() ?? '',
              data['number']?.toString() ?? '',
              data['tense']?.toString() ?? '',
            ].where((value) => value.trim().isNotEmpty).join(' · ');
            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 38,
                      height: 4,
                      decoration: BoxDecoration(
                        color: muted.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          data['title']?.toString().trim().isNotEmpty == true
                              ? data['title'].toString()
                              : word,
                          style: DesignTokens.display(24).copyWith(color: text),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: Icon(CupertinoIcons.xmark, color: muted),
                      ),
                    ],
                  ),
                  Text(
                    translation,
                    style: DesignTokens.body(15).copyWith(color: muted),
                  ),
                  if (metadata.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      metadata,
                      style: DesignTokens.mono(11).copyWith(color: accent),
                    ),
                  ],
                  if ((data['summary']?.toString() ?? '').isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text(
                      data['summary'].toString(),
                      style: DesignTokens.body(
                        14,
                      ).copyWith(color: text, height: 1.4),
                    ),
                  ],
                  if (conjugation.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    Text(
                      'CONJUGATION',
                      style: DesignTokens.mono(
                        10.5,
                        weight: FontWeight.w800,
                      ).copyWith(color: accent, letterSpacing: 0.8),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: muted.withValues(alpha: 0.4)),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          for (var i = 0; i < conjugation.length; i++)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: i.isEven
                                    ? muted.withValues(alpha: 0.06)
                                    : Colors.transparent,
                                border: i == conjugation.length - 1
                                    ? null
                                    : Border(
                                        bottom: BorderSide(
                                          color: muted.withValues(alpha: 0.2),
                                        ),
                                      ),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      conjugation[i]['pronoun']?.toString() ??
                                          '',
                                      style: DesignTokens.body(
                                        14,
                                      ).copyWith(color: muted),
                                    ),
                                  ),
                                  Text(
                                    conjugation[i]['form']?.toString() ?? '',
                                    style: DesignTokens.body(
                                      14,
                                      weight: FontWeight.w700,
                                    ).copyWith(color: text),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Renders a segment's French text with the word at [currentWord] (by index,
/// split on whitespace) highlighted — the word-by-word playback indicator,
/// distinct from the sentence-level "now playing" box the caller already
/// draws around the whole segment. Splitting preserves the original spacing
/// between words (joined back with single spaces) since French narration
/// text here is never pre-formatted with multiple spaces or line breaks.
/// The "teach the rule first" card — summary, explicit tense contrast,
/// conjugation tables, and bilingual examples, all generated before the
/// story existed (see `LessonAgentService.buildGrammarExplanation`). Shown
/// at the top of the Grammar tab, above the per-sentence story notes.
class _GrammarExplanationCard extends StatelessWidget {
  const _GrammarExplanationCard({
    required this.explanation,
    required this.darkMode,
  });

  final GrammarExplanation explanation;
  final bool darkMode;

  @override
  Widget build(BuildContext context) {
    final text = darkMode ? DesignTokens.nightText : DesignTokens.ink;
    final muted = darkMode ? DesignTokens.nightMuted : DesignTokens.mutedDim;
    final accent = darkMode ? DesignTokens.nightAccent : DesignTokens.primary;
    return LearningCard(
      padding: 16,
      color: darkMode ? DesignTokens.nightSurface : DesignTokens.surface,
      borderColor: darkMode
          ? DesignTokens.nightHairline
          : DesignTokens.hairline,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            explanation.title,
            style: DesignTokens.display(
              20,
              weight: FontWeight.w600,
            ).copyWith(color: text),
          ),
          const SizedBox(height: 8),
          Text(
            explanation.summary,
            style: DesignTokens.body(14).copyWith(color: text, height: 1.45),
          ),
          if (explanation.usage.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              'Usage',
              style: DesignTokens.body(
                13,
                weight: FontWeight.w600,
              ).copyWith(color: text),
            ),
            const SizedBox(height: 6),
            for (final rule in explanation.usage)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('•  ', style: TextStyle(color: accent, fontSize: 13)),
                    Expanded(
                      child: Text(
                        rule,
                        style: DesignTokens.body(
                          13.5,
                        ).copyWith(color: text, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          if (explanation.tenseContrast.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: darkMode
                    ? DesignTokens.nightAccentSoft
                    : DesignTokens.infoSoft,
                borderRadius: BorderRadius.circular(DesignTokens.radiusMedium),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'How it changes',
                    style: DesignTokens.body(
                      12.5,
                      weight: FontWeight.w600,
                    ).copyWith(color: accent),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    explanation.tenseContrast,
                    style: DesignTokens.body(
                      13,
                    ).copyWith(color: muted, height: 1.4),
                  ),
                ],
              ),
            ),
          ],
          if (explanation.conjugations.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'Conjugation',
              style: DesignTokens.body(
                13,
                weight: FontWeight.w600,
              ).copyWith(color: text),
            ),
            const SizedBox(height: 8),
            for (final conj in explanation.conjugations)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _ConjugationTable(conjugation: conj, darkMode: darkMode),
              ),
          ],
          if (explanation.examples.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Examples',
              style: DesignTokens.body(13, weight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            for (final ex in explanation.examples)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ex.fr,
                      style: DesignTokens.body(
                        14,
                        weight: FontWeight.w600,
                      ).copyWith(color: text),
                    ),
                    Text(
                      ex.en,
                      style: DesignTokens.body(12.5).copyWith(color: muted),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _ConjugationTable extends StatelessWidget {
  const _ConjugationTable({required this.conjugation, required this.darkMode});

  final Conjugation conjugation;
  final bool darkMode;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: darkMode
            ? DesignTokens.nightSurfaceRaised
            : DesignTokens.canvasDim,
        borderRadius: BorderRadius.circular(DesignTokens.radiusMedium),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                conjugation.verb,
                style: DesignTokens.body(14, weight: FontWeight.w700),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: DesignTokens.info.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  conjugation.group,
                  style: DesignTokens.mono(9.5, weight: FontWeight.w500)
                      .copyWith(
                        color: darkMode
                            ? DesignTokens.nightAccent
                            : DesignTokens.info,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final row in conjugation.rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  SizedBox(
                    width: 64,
                    child: Text(
                      row.pronoun,
                      style: DesignTokens.body(13).copyWith(
                        color: darkMode
                            ? DesignTokens.nightMuted
                            : DesignTokens.mutedDim,
                      ),
                    ),
                  ),
                  Text(
                    row.form,
                    style: DesignTokens.body(13, weight: FontWeight.w500)
                        .copyWith(
                          color: darkMode
                              ? DesignTokens.nightText
                              : DesignTokens.ink,
                        ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Small tappable nudge shown at the bottom of the Story tab, only for a
/// grammar-practice session — the story leads, this is a one-line invite to
/// go read the grammar behind it, not a forced landing on the Grammar tab.
class _GrammarCueCard extends StatelessWidget {
  const _GrammarCueCard({
    required this.grammarPoint,
    required this.onTap,
    this.tabLabel = 'Grammar',
  });

  final String grammarPoint;
  final String tabLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: DesignTokens.infoSoft,
            borderRadius: BorderRadius.circular(DesignTokens.radiusMedium),
          ),
          child: Row(
            children: [
              Icon(
                CupertinoIcons.book_fill,
                size: 18,
                color: DesignTokens.info,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'See how $grammarPoint works in this story',
                  style: DesignTokens.body(
                    13,
                    weight: FontWeight.w500,
                  ).copyWith(color: DesignTokens.inkSoft),
                ),
              ),
              Icon(
                CupertinoIcons.chevron_right,
                size: 16,
                color: DesignTokens.info,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

int? _mappedTranslationWord({
  required int? currentWord,
  required String source,
  required String translation,
}) {
  if (currentWord == null) return null;
  final sourceCount = _wordParts(source).length;
  final translationCount = _wordParts(translation).length;
  if (sourceCount == 0 || translationCount == 0) return null;
  final mapped = (currentWord * translationCount / sourceCount).floor();
  return mapped.clamp(0, translationCount - 1);
}

List<String> _wordParts(String text) =>
    text.split(RegExp(r'\s+')).where((word) => word.isNotEmpty).toList();

String _foldStoryWord(String value) => value
    .toLowerCase()
    .replaceAll(RegExp(r"[.,!?;:«»'()…]"), '')
    .replaceAll('"', '')
    .replaceAll('-', ' ')
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
    .trim();

class _StoryStageIsland extends StatelessWidget {
  const _StoryStageIsland({
    required this.labels,
    required this.currentIndex,
    required this.onIndexTap,
  });

  final List<String> labels;
  final int currentIndex;
  final ValueChanged<int> onIndexTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: DesignTokens.nightSurface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: DesignTokens.nightHairline),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onIndexTap(i),
                child: AnimatedContainer(
                  duration: DesignTokens.durationFast,
                  curve: DesignTokens.curveStandard,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: i == currentIndex
                        ? DesignTokens.nightAccent
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Text(
                    labels[i],
                    style: DesignTokens.body(12, weight: FontWeight.w700)
                        .copyWith(
                          color: i == currentIndex
                              ? DesignTokens.nightCanvas
                              : DesignTokens.nightMuted,
                        ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AudioControlBar extends StatelessWidget {
  const _AudioControlBar({
    required this.isPlaying,
    required this.isLoading,
    required this.rate,
    required this.onTogglePlayPause,
    required this.onStop,
    required this.onPlaySentence,
    required this.onCycleRate,
    required this.onNext,
    required this.darkMode,
  });

  final bool isPlaying;
  final bool isLoading;
  final double rate;
  final VoidCallback onTogglePlayPause;
  final VoidCallback onStop;
  final VoidCallback onPlaySentence;
  final VoidCallback onCycleRate;
  final VoidCallback onNext;
  final bool darkMode;

  @override
  Widget build(BuildContext context) {
    final surface = darkMode ? DesignTokens.nightSurface : Colors.white;
    final text = darkMode ? DesignTokens.nightText : DesignTokens.ink;
    final muted = darkMode ? DesignTokens.nightMuted : DesignTokens.mutedDim;
    final accent = darkMode ? DesignTokens.nightAccent : DesignTokens.primary;
    return ClipRRect(
      borderRadius: BorderRadius.circular(32),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: surface.withValues(alpha: 0.86),
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: muted.withValues(alpha: 0.22)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _circleButton(
                icon: isPlaying
                    ? CupertinoIcons.pause_fill
                    : CupertinoIcons.play_fill,
                loading: isLoading,
                color: accent,
                iconColor: darkMode ? DesignTokens.nightCanvas : Colors.white,
                onTap: isLoading ? () {} : onTogglePlayPause,
              ),
              _separator(muted),
              _compactIconAction(
                icon: CupertinoIcons.stop_fill,
                tooltip: 'Stop audio',
                color: text,
                onTap: onStop,
              ),
              _separator(muted),
              _compactAction(
                label: rate <= 0.36
                    ? '.75x'
                    : rate >= 0.5
                    ? '1.25x'
                    : '1x',
                color: text,
                onTap: onCycleRate,
              ),
              _separator(muted),
              _compactIconAction(
                icon: CupertinoIcons.arrow_counterclockwise,
                tooltip: 'Replay sentence',
                color: text,
                onTap: onPlaySentence,
              ),
              _separator(muted),
              _compactIconAction(
                icon: CupertinoIcons.book_fill,
                tooltip: 'Words',
                color: accent,
                onTap: onNext,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _separator(Color color) => Container(
    width: 1,
    height: 24,
    margin: const EdgeInsets.symmetric(horizontal: 6),
    color: color.withValues(alpha: 0.2),
  );

  Widget _compactAction({
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Text(
          label,
          style: DesignTokens.body(
            12,
            weight: FontWeight.w700,
          ).copyWith(color: color),
        ),
      ),
    );
  }

  Widget _compactIconAction({
    required IconData icon,
    required String tooltip,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, color: color, size: 17),
        ),
      ),
    );
  }

  Widget _circleButton({
    required IconData icon,
    required Color color,
    required Color iconColor,
    required VoidCallback onTap,
    bool loading = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 48,
        height: 48,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: Icon(icon, color: iconColor, size: 17),
            ),
            if (loading)
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.all(1),
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(color),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StoryNextBar extends StatelessWidget {
  const _StoryNextBar({
    required this.label,
    required this.onPressed,
    required this.onBack,
    required this.darkMode,
  });

  final String label;
  final VoidCallback onPressed;
  final VoidCallback onBack;
  final bool darkMode;

  @override
  Widget build(BuildContext context) {
    final surface = darkMode ? DesignTokens.nightSurface : Colors.white;
    final text = darkMode ? DesignTokens.nightText : DesignTokens.ink;
    final accent = darkMode ? DesignTokens.nightAccent : DesignTokens.primary;
    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          height: 60,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: surface.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: accent.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              IconButton(
                onPressed: onBack,
                icon: Icon(CupertinoIcons.arrow_left, color: text),
              ),
              Expanded(
                child: Text(
                  'Next: $label',
                  textAlign: TextAlign.center,
                  style: DesignTokens.body(
                    13,
                    weight: FontWeight.w700,
                  ).copyWith(color: text),
                ),
              ),
              IconButton(
                onPressed: onPressed,
                icon: Icon(CupertinoIcons.arrow_right, color: accent),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReaderSettingsResult {
  const _ReaderSettingsResult({
    required this.textScale,
    required this.rate,
    required this.translateSentences,
    required this.highlightWords,
    required this.underlineWords,
    required this.autoPlayWordAudio,
    required this.darkMode,
  });

  final double textScale;
  final double rate;
  final bool translateSentences;
  final bool highlightWords;
  final bool underlineWords;
  final bool autoPlayWordAudio;
  final bool darkMode;
}

class _StorySettingsSheet extends StatefulWidget {
  const _StorySettingsSheet({
    required this.textScale,
    required this.rate,
    required this.translateSentences,
    required this.highlightWords,
    required this.underlineWords,
    required this.autoPlayWordAudio,
    required this.darkMode,
  });

  final double textScale;
  final double rate;
  final bool translateSentences;
  final bool highlightWords;
  final bool underlineWords;
  final bool autoPlayWordAudio;
  final bool darkMode;

  @override
  State<_StorySettingsSheet> createState() => _StorySettingsSheetState();
}

class _StorySettingsSheetState extends State<_StorySettingsSheet> {
  late double _textScale = widget.textScale;
  late double _rate = widget.rate;
  late bool _translate = widget.translateSentences;
  late bool _highlight = widget.highlightWords;
  late bool _underline = widget.underlineWords;
  late bool _autoPlay = widget.autoPlayWordAudio;
  late bool _dark = widget.darkMode;

  void _close() => Navigator.of(context).pop(
    _ReaderSettingsResult(
      textScale: _textScale,
      rate: _rate,
      translateSentences: _translate,
      highlightWords: _highlight,
      underlineWords: _underline,
      autoPlayWordAudio: _autoPlay,
      darkMode: _dark,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final surface = _dark ? DesignTokens.nightSurfaceRaised : Colors.white;
    final text = _dark ? DesignTokens.nightText : DesignTokens.ink;
    final muted = _dark ? DesignTokens.nightMuted : DesignTokens.mutedDim;
    final accent = _dark ? DesignTokens.nightAccent : DesignTokens.primary;
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(10),
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: accent.withValues(alpha: 0.25)),
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: muted.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Story settings',
                      style: DesignTokens.display(24).copyWith(color: text),
                    ),
                  ),
                  IconButton(
                    onPressed: _close,
                    icon: Icon(CupertinoIcons.xmark, color: muted),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _settingLabel('Text size', text),
              const SizedBox(height: 8),
              Row(
                children: [
                  for (final option in [
                    (0.9, 'Small'),
                    (1.0, 'Medium'),
                    (1.25, 'Large'),
                  ])
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _choice(
                          option.$2,
                          _textScale == option.$1,
                          () => setState(() => _textScale = option.$1),
                          text,
                          accent,
                          muted,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              _settingLabel('Playback speed', text),
              const SizedBox(height: 8),
              Row(
                children: [
                  for (final option in [
                    (0.32, '0.75×'),
                    (0.42, '1.00×'),
                    (0.55, '1.25×'),
                  ])
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _choice(
                          option.$2,
                          _rate == option.$1,
                          () => setState(() => _rate = option.$1),
                          text,
                          accent,
                          muted,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              _switchRow(
                'Translate sentences',
                'Show the English line under French.',
                _translate,
                (v) => setState(() => _translate = v),
                text,
                muted,
                accent,
              ),
              _switchRow(
                'Highlight words',
                'Color the selected or spoken word.',
                _highlight,
                (v) => setState(() => _highlight = v),
                text,
                muted,
                accent,
              ),
              _switchRow(
                'Underline words',
                'Keep vocabulary cues visible in the story.',
                _underline,
                (v) => setState(() => _underline = v),
                text,
                muted,
                accent,
              ),
              _switchRow(
                'Auto-play word audio',
                'Play a word when it is selected.',
                _autoPlay,
                (v) => setState(() => _autoPlay = v),
                text,
                muted,
                accent,
              ),
              _switchRow(
                'Dark mode',
                'Use the focused dark reading canvas.',
                _dark,
                (v) => setState(() => _dark = v),
                text,
                muted,
                accent,
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _close,
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: _dark
                        ? DesignTokens.nightCanvas
                        : Colors.white,
                  ),
                  child: const Text('Done'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _settingLabel(String label, Color color) => Text(
    label,
    style: DesignTokens.body(
      14,
      weight: FontWeight.w700,
    ).copyWith(color: color),
  );

  Widget _choice(
    String label,
    bool selected,
    VoidCallback onTap,
    Color text,
    Color accent,
    Color muted,
  ) => GestureDetector(
    onTap: onTap,
    child: Container(
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected ? accent.withValues(alpha: 0.14) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected ? accent : muted.withValues(alpha: 0.35),
        ),
      ),
      child: Text(
        label,
        style: DesignTokens.body(
          12,
          weight: FontWeight.w700,
        ).copyWith(color: selected ? accent : text),
      ),
    ),
  );

  Widget _switchRow(
    String title,
    String subtitle,
    bool value,
    ValueChanged<bool> onChanged,
    Color text,
    Color muted,
    Color accent,
  ) => Material(
    color: Colors.transparent,
    child: SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      title: Text(
        title,
        style: DesignTokens.body(
          14,
          weight: FontWeight.w600,
        ).copyWith(color: text),
      ),
      subtitle: Text(
        subtitle,
        style: DesignTokens.body(11.5).copyWith(color: muted),
      ),
      value: value,
      activeThumbColor: accent,
      onChanged: onChanged,
    ),
  );
}

class _ComingSoon extends StatelessWidget {
  const _ComingSoon({required this.label, this.generating = false});

  final String label;

  /// True while this story's Quiz/Keywords are still being generated in the
  /// background (see `StoryReaderScreen.enrichment`) — swaps the copy for a
  /// "still working on it" message instead of implying it never will.
  final bool generating;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (generating)
              const SizedBox(
                width: 30,
                height: 30,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(
                CupertinoIcons.hourglass,
                color: DesignTokens.mutedDim,
                size: 30,
              ),
            const SizedBox(height: 12),
            Text(
              generating ? 'Writing your $label…' : '$label is coming soon',
              style: DesignTokens.display(18),
            ),
            const SizedBox(height: 6),
            Text(
              generating
                  ? 'This will be ready in just a moment.'
                  : 'This story\'s $label will appear here in a future update.',
              textAlign: TextAlign.center,
              style: DesignTokens.body(
                13.5,
              ).copyWith(color: DesignTokens.mutedDim, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}
