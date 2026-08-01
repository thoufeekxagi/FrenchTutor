import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/tokens.dart';
import '../../models/content_models.dart';
import '../../prompts/live_prompts.dart';
import '../../providers/database_provider.dart';
import '../../services/inline_call_controller.dart';
import '../../services/lesson_speech_service.dart';
import '../../services/session_recorder.dart';
import '../../widgets/floating_notetaker.dart';
import '../../widgets/inline_call_bar.dart';
import '../../widgets/passeport_card.dart';
import '../../widgets/report_problem_button.dart';

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
  });

  final GeneratedStory story;

  /// Present only for a grammar-practice session (see
  /// `LessonAgentService.buildGrammarExplanation`) — when set, this screen
  /// opens on the Grammar tab instead of Story, and shows this explanation
  /// ABOVE the per-sentence notes: grammar has to teach the rule first, the
  /// story is the vehicle that demonstrates it, not the other way around.
  final GrammarExplanation? grammarExplanation;

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
  final Future<({List<MultipleChoiceQuestion> quiz, List<VocabEntry> keywords})>?
  enrichment;

  /// Fires once [enrichment] resolves, so the caller can persist the result
  /// (e.g. `GeneratedStoryStore.updateEnrichment`) — this screen only holds
  /// it in memory for display, it doesn't own storage.
  final void Function(List<MultipleChoiceQuestion> quiz, List<VocabEntry> keywords)?
  onEnriched;

  @override
  ConsumerState<StoryReaderScreen> createState() => _StoryReaderScreenState();
}

class _StoryReaderScreenState extends ConsumerState<StoryReaderScreen>
    with WidgetsBindingObserver {
  late _StoryTab _tab = widget.grammarExplanation != null
      ? _StoryTab.grammar
      : _StoryTab.story;
  int _currentSegment = 0;
  bool _isPlaying = false;
  double _rate = 0.42; // matches LessonSpeechService's own default "normal"
  final Map<int, GlobalKey> _segmentKeys = {};
  final Map<int, int> _quizAnswers = {};

  /// The sentence the learner tapped to read from, highlighted so they can
  /// see what pressing play will do — null means "no pick, play the whole
  /// story from the top". Tapping the same sentence again clears the pick.
  /// Distinct from [_currentSegment], which tracks the segment actually
  /// playing right now (for auto-scroll and the "now playing" highlight).
  int? _selectedSegment;

  /// Which word (by index, split on whitespace) within the currently-playing
  /// segment's French text the narration has reached — null when nothing is
  /// playing, or once a segment's estimated timing runs past its last word.
  /// Timing comes from `LessonSpeechService`'s `onWordBoundary`, estimated
  /// from the known playback duration, not exact phoneme timing.
  int? _currentWord;

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
      ..writeln('How it contrasts with other tenses: ${explanation.tenseContrast}');
    for (final c in explanation.conjugations) {
      buf.writeln(
        '${c.verb} (${c.group}): ${c.rows.map((r) => "${r.pronoun} ${r.form}").join(', ')}',
      );
    }
    return buf.toString();
  }

  GlobalKey _keyFor(int index) => _segmentKeys.putIfAbsent(index, GlobalKey.new);

  late final SessionRecorder _recorder;

  /// Marie's live-call button, inline in the AppBar — same
  /// InlineCallController every other reading/exercise screen uses, so
  /// asking her about the story happens right here without leaving the
  /// page, not in a separate fullscreen call window.
  late final InlineCallController _call;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _call = InlineCallController(
      sessionType: LiveSessionType.labAssistant,
      lessonContext: () => _lessonContext,
      learningStoreForProfile: ref.read(learningStoreProvider),
      onChanged: () {
        if (mounted) setState(() {});
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(notetakerStateProvider).currentContext = 'Story';
    });
    _recorder = SessionRecorder(
      storage: ref.read(storageServiceProvider),
      stage: 'story',
      topic: _story.displayTitle,
    );
    final enrichment = widget.enrichment;
    if (enrichment != null) {
      _enriching = true;
      enrichment.then((result) {
        widget.onEnriched?.call(result.quiz, result.keywords);
        if (!mounted) return;
        setState(() {
          _enriching = false;
          _story = GeneratedStory(
            id: _story.id,
            passage: _story.passage,
            quiz: result.quiz,
            keywords: result.keywords,
            createdAt: _story.createdAt,
          );
        });
      }, onError: (_) {
        if (mounted) setState(() => _enriching = false);
      });
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
    _call.dispose();
    LessonSpeechService.shared.stop();
    _finishSession();
    super.dispose();
  }

  void _finishSession() {
    if (_quizAnswers.isEmpty) {
      _recorder.finish(summary: 'Read "${_story.displayTitle}".');
      return;
    }
    final quiz = _story.quiz;
    var correct = 0;
    for (final entry in _quizAnswers.entries) {
      if (entry.key < quiz.length && entry.value == quiz[entry.key].answerIndex) {
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
      onWordBoundary: (_, wordIndex) {
        if (!mounted) return;
        setState(() => _currentWord = wordIndex);
      },
      onFinished: () {
        if (!mounted) return;
        setState(() {
          _isPlaying = false;
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
    if (_isPlaying && !speech.isPaused) {
      await speech.pause();
      if (mounted) setState(() => _isPlaying = false);
    } else if (speech.isPaused) {
      await speech.resume();
      if (mounted) setState(() => _isPlaying = true);
    } else {
      // Fresh start (not a resume): play from the sentence the learner
      // picked, or the whole story from the top if nothing is picked.
      await _playAll(fromIndex: _selectedSegment ?? 0);
    }
  }

  Future<void> _stop() async {
    await LessonSpeechService.shared.stop();
    if (mounted) setState(() => _isPlaying = false);
  }

  void _selectSegment(int index) {
    setState(() => _selectedSegment = _selectedSegment == index ? null : index);
  }

  /// Plays just the one picked sentence (or the current one if nothing is
  /// picked), not the rest of the story — for "let me hear that one line
  /// again" rather than "keep reading from here".
  Future<void> _playSelectedSentence() async {
    final segments = _passage.segments;
    final index = _selectedSegment ?? _currentSegment;
    if (index < 0 || index >= segments.length) return;
    setState(() {
      _isPlaying = true;
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
      onWordBoundary: (_, wordIndex) {
        if (!mounted) return;
        setState(() => _currentWord = wordIndex);
      },
      onFinished: () {
        if (!mounted) return;
        setState(() {
          _isPlaying = false;
          _currentWord = null;
        });
      },
    );
  }

  void _cycleRate() {
    setState(() => _rate = _rate <= 0.36 ? 0.55 : 0.32);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DesignTokens.canvas,
      appBar: AppBar(
        title: Text(
          _passage.displayTitle,
          style: DesignTokens.display(16),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: DesignTokens.canvas,
        foregroundColor: DesignTokens.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          InlineCallActions(controller: _call),
          ReportProblemButton(sessionType: 'Story: ${_passage.displayTitle}'),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              if (_call.isLive || _call.error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: InlineCallStatusCard(
                    controller: _call,
                    listeningLabel: 'Listening. Ask about the story anytime.',
                  ),
                ),
              _TabRow(
                selected: _tab,
                onSelect: (tab) => setState(() => _tab = tab),
              ),
              Divider(height: 1, color: DesignTokens.hairline),
              Expanded(
                child: switch (_tab) {
                  _StoryTab.story => _storyView(),
                  _StoryTab.grammar => _grammarView(),
                  _StoryTab.quiz => _quizView(),
                  _StoryTab.keywords => _keywordsView(),
                },
              ),
              if (_tab == _StoryTab.story)
                _AudioControlBar(
                  isPlaying: _isPlaying,
                  rate: _rate,
                  onTogglePlayPause: _togglePlayPause,
                  onStop: _stop,
                  onPlaySentence: _playSelectedSentence,
                  onCycleRate: _cycleRate,
                  onContinue: widget.showFinishButton ? _finish : null,
                ),
            ],
          ),
          FloatingNotetakerOverlay(state: ref.watch(notetakerStateProvider)),
        ],
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

  Widget _storyView() {
    final segments = _passage.segments;
    String? lastCharacter;
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      itemCount: segments.length,
      itemBuilder: (context, index) {
        final segment = segments[index];
        final showCharacter =
            segment.characterFr != null && segment.characterFr != lastCharacter;
        lastCharacter = segment.characterFr ?? lastCharacter;
        // Highlighted either because it's actively playing right now, or
        // because the learner picked it as where the next play should
        // start from — see `_selectedSegment`.
        final isPlayingNow = index == _currentSegment && _isPlaying;
        final isPicked = !_isPlaying && index == _selectedSegment;
        final isHighlighted = isPlayingNow || isPicked;
        return Padding(
          key: _keyFor(index),
          padding: const EdgeInsets.only(bottom: 18),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _selectSegment(index),
            child: Container(
              padding: isHighlighted
                  ? const EdgeInsets.symmetric(horizontal: 12, vertical: 8)
                  : EdgeInsets.zero,
              decoration: isHighlighted
                  ? BoxDecoration(
                      color: DesignTokens.primarySoft,
                      borderRadius: BorderRadius.circular(DesignTokens.radiusMedium),
                    )
                  : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showCharacter) ...[
                    Text(
                      segment.characterFr!,
                      style: DesignTokens.mono(
                        11,
                        weight: FontWeight.w700,
                      ).copyWith(color: DesignTokens.slateDim, letterSpacing: 0.8),
                    ),
                    const SizedBox(height: 6),
                  ],
                  isPlayingNow
                      ? _WordHighlightText(
                          text: segment.fr,
                          currentWord: _currentWord,
                          style: DesignTokens.body(
                            17,
                            weight: FontWeight.w600,
                          ).copyWith(height: 1.4),
                        )
                      : Text(
                          segment.fr,
                          style: DesignTokens.body(
                            17,
                            weight: FontWeight.w600,
                          ).copyWith(height: 1.4),
                        ),
                  const SizedBox(height: 4),
                  Text(
                    segment.en,
                    style: DesignTokens.body(
                      14.5,
                    ).copyWith(color: DesignTokens.primary, height: 1.4),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
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
      padding: const EdgeInsets.all(20),
      children: [
        if (explanation != null) ...[
          _GrammarExplanationCard(explanation: explanation),
          const SizedBox(height: 20),
          if (points.isNotEmpty)
            Text(
              'HOW THE STORY USES IT',
              style: DesignTokens.mono(
                10.5,
                weight: FontWeight.w700,
              ).copyWith(color: DesignTokens.slateDim, letterSpacing: 0.8),
            ),
          if (points.isNotEmpty) const SizedBox(height: 12),
        ],
        for (var i = 0; i < points.length; i++) ...[
          if (i > 0) const SizedBox(height: 14),
          PasseportCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'From this story',
                  style: DesignTokens.mono(
                    10.5,
                    weight: FontWeight.w700,
                  ).copyWith(color: DesignTokens.primary, letterSpacing: 0.8),
                ),
                const SizedBox(height: 8),
                Text(
                  points[i].fr,
                  style: DesignTokens.body(15, weight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                Text(
                  points[i].grammarNote,
                  style: DesignTokens.body(
                    13.5,
                  ).copyWith(color: DesignTokens.inkSoft, height: 1.4),
                ),
                if (points[i].pronunciationTip.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        CupertinoIcons.waveform,
                        size: 15,
                        color: DesignTokens.slateDim,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          points[i].pronunciationTip,
                          style: DesignTokens.body(12.5).copyWith(
                            color: DesignTokens.slateDim,
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
      padding: const EdgeInsets.all(20),
      itemCount: quiz.length,
      separatorBuilder: (_, _) => const SizedBox(height: 14),
      itemBuilder: (context, index) => _quizCard(index, quiz[index]),
    );
  }

  Widget _quizCard(int index, MultipleChoiceQuestion question) {
    final answered = _quizAnswers[index];
    return PasseportCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(question.q, style: DesignTokens.body(15, weight: FontWeight.w600)),
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
                    color: DesignTokens.canvasDim,
                    borderRadius: BorderRadius.circular(DesignTokens.radiusMedium),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          question.choices[ci],
                          style: DesignTokens.body(13.5),
                        ),
                      ),
                      if (answered != null) ...[
                        if (ci == question.answerIndex)
                          const Icon(
                            CupertinoIcons.checkmark_circle_fill,
                            color: DesignTokens.success,
                            size: 18,
                          )
                        else if (ci == answered)
                          const Icon(
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
      padding: const EdgeInsets.all(20),
      itemCount: keywords.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final entry = keywords[index];
        return PasseportCard(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.fr,
                      style: DesignTokens.body(15, weight: FontWeight.w600),
                    ),
                    if (entry.phonetic.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        entry.phonetic,
                        style: DesignTokens.mono(
                          11,
                        ).copyWith(color: DesignTokens.slateDim),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                entry.en,
                style: DesignTokens.body(13.5).copyWith(color: DesignTokens.primary),
              ),
            ],
          ),
        );
      },
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
  const _GrammarExplanationCard({required this.explanation});

  final GrammarExplanation explanation;

  @override
  Widget build(BuildContext context) {
    return PasseportCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            explanation.title,
            style: DesignTokens.display(20, weight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            explanation.summary,
            style: DesignTokens.body(14).copyWith(height: 1.45),
          ),
          if (explanation.usage.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              'Usage',
              style: DesignTokens.body(13, weight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            for (final rule in explanation.usage)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '•  ',
                      style: TextStyle(color: DesignTokens.info, fontSize: 13),
                    ),
                    Expanded(
                      child: Text(
                        rule,
                        style: DesignTokens.body(
                          13.5,
                        ).copyWith(height: 1.4),
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
                color: DesignTokens.infoSoft,
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
                    ).copyWith(color: DesignTokens.info),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    explanation.tenseContrast,
                    style: DesignTokens.body(
                      13,
                    ).copyWith(color: DesignTokens.inkSoft, height: 1.4),
                  ),
                ],
              ),
            ),
          ],
          if (explanation.conjugations.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'Conjugation',
              style: DesignTokens.body(13, weight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            for (final conj in explanation.conjugations)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _ConjugationTable(conjugation: conj),
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
                      style: DesignTokens.body(14, weight: FontWeight.w600),
                    ),
                    Text(
                      ex.en,
                      style: DesignTokens.body(
                        12.5,
                      ).copyWith(color: DesignTokens.slateDim),
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
  const _ConjugationTable({required this.conjugation});

  final Conjugation conjugation;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: DesignTokens.parchmentDim,
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
                  style: DesignTokens.mono(
                    9.5,
                    weight: FontWeight.w500,
                  ).copyWith(color: DesignTokens.info),
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
                      style: DesignTokens.body(
                        13,
                      ).copyWith(color: DesignTokens.slateDim),
                    ),
                  ),
                  Text(
                    row.form,
                    style: DesignTokens.body(13, weight: FontWeight.w500),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _WordHighlightText extends StatelessWidget {
  const _WordHighlightText({
    required this.text,
    required this.currentWord,
    required this.style,
  });

  final String text;
  final int? currentWord;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final words = text.split(RegExp(r'\s+'));
    return Text.rich(
      TextSpan(
        children: [
          for (var i = 0; i < words.length; i++) ...[
            if (i > 0) const TextSpan(text: ' '),
            TextSpan(
              text: words[i],
              style: i == currentWord
                  ? style.copyWith(
                      backgroundColor: DesignTokens.primary.withValues(alpha: 0.22),
                      color: DesignTokens.primaryDeep,
                    )
                  : style,
            ),
          ],
        ],
      ),
      style: style,
    );
  }
}

class _TabRow extends StatelessWidget {
  const _TabRow({required this.selected, required this.onSelect});

  final _StoryTab selected;
  final ValueChanged<_StoryTab> onSelect;

  static const _labels = {
    _StoryTab.story: 'Story',
    _StoryTab.quiz: 'Quiz',
    _StoryTab.keywords: 'Keywords',
    _StoryTab.grammar: 'Grammar',
  };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: _labels.entries.map((entry) {
          final isSelected = entry.key == selected;
          return Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onSelect(entry.key),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  color: isSelected ? DesignTokens.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(DesignTokens.radiusPill),
                ),
                alignment: Alignment.center,
                child: Text(
                  entry.value,
                  style: DesignTokens.body(13, weight: FontWeight.w600).copyWith(
                    color: isSelected ? Colors.white : DesignTokens.slateDim,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _AudioControlBar extends StatelessWidget {
  const _AudioControlBar({
    required this.isPlaying,
    required this.rate,
    required this.onTogglePlayPause,
    required this.onStop,
    required this.onPlaySentence,
    required this.onCycleRate,
    required this.onContinue,
  });

  final bool isPlaying;
  final double rate;
  final VoidCallback onTogglePlayPause;
  final VoidCallback onStop;
  final VoidCallback onPlaySentence;
  final VoidCallback onCycleRate;
  final VoidCallback? onContinue;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: DesignTokens.surface,
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
            _circleButton(
              icon: isPlaying ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill,
              onTap: onTogglePlayPause,
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onCycleRate,
              child: Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  color: DesignTokens.primary,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  rate <= 0.36 ? '.75x' : '1x',
                  style: DesignTokens.body(
                    11,
                    weight: FontWeight.w700,
                  ).copyWith(color: Colors.white),
                ),
              ),
            ),
            const SizedBox(width: 8),
            _circleButton(icon: CupertinoIcons.stop_fill, onTap: onStop),
            const SizedBox(width: 8),
            Expanded(
              child: TextButton.icon(
                onPressed: onPlaySentence,
                icon: const Icon(
                  CupertinoIcons.play_circle,
                  size: 18,
                  color: DesignTokens.primary,
                ),
                label: Text(
                  'sentence',
                  style: DesignTokens.body(
                    12.5,
                    weight: FontWeight.w600,
                  ).copyWith(color: DesignTokens.primary),
                ),
              ),
            ),
            if (onContinue != null)
              ElevatedButton(
                onPressed: onContinue,
                style: ElevatedButton.styleFrom(
                  backgroundColor: DesignTokens.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(DesignTokens.radiusPill),
                  ),
                ),
                child: Text(
                  'Continue',
                  style: DesignTokens.body(13.5, weight: FontWeight.w600),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _circleButton({required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: const BoxDecoration(
          color: DesignTokens.primary,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    );
  }
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
              const Icon(
                CupertinoIcons.hourglass,
                color: DesignTokens.slateDim,
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
              ).copyWith(color: DesignTokens.slateDim, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}
