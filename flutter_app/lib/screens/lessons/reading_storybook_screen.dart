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
import '../../widgets/learning_card.dart';
import '../../widgets/passeport_card.dart';
import '../../widgets/primary_action_button.dart';
import '../../widgets/report_problem_button.dart';
import '../../widgets/web/web_constrained_view.dart';

enum _ReadingStep { open, read, notice, words, reread, check }

/// A reading-only teaching loop for a generated story.
///
/// It keeps the useful Readle shape—book cover, compact story segments,
/// bilingual support, grammar/keywords/quiz, and Marie—but turns those pieces
/// into a real progression. Listening has its own dedicated screen and is not
/// routed through this lesson.
class ReadingStorybookScreen extends ConsumerStatefulWidget {
  const ReadingStorybookScreen({super.key, required this.story});

  final GeneratedStory story;

  @override
  ConsumerState<ReadingStorybookScreen> createState() =>
      _ReadingStorybookScreenState();
}

class _ReadingStorybookScreenState extends ConsumerState<ReadingStorybookScreen>
    with WidgetsBindingObserver {
  _ReadingStep _step = _ReadingStep.open;
  int _selectedSegment = 0;
  bool _showTranslations = false;
  bool _playing = false;
  int _playingSegment = -1;
  final Map<int, int> _answers = {};

  late final InlineCallController _call;
  late final SessionRecorder _recorder;

  GeneratedStory get _story => widget.story;
  List<ReadingSegment> get _segments => _story.passage.segments;
  ReadingSegment get _focusSegment => _segments[_selectedSegment];

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
    _recorder = SessionRecorder(
      storage: ref.read(storageServiceProvider),
      stage: 'story',
      topic: _story.displayTitle,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(notetakerStateProvider).currentContext = 'Reading story';
    });
  }

  String get _lessonContext =>
      '''
READING STORYBOOK
Title: ${_story.displayTitle}
Summary: ${_story.summary}
Level: ${_story.levelBand}
The learner is working through this story sentence by sentence. Explain a
word, sentence, grammar point, or plot detail in a short learner-friendly way.
Do not invent text that is not in the story. Story text:
${_segments.map((segment) => '- ${segment.fr} — ${segment.en}').join('\n')}
''';

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _call.handleAppLifecycle(state);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _call.dispose();
    LessonSpeechService.shared.stop();
    final score = _score;
    _recorder.finish(
      summary:
          'Read "${_story.displayTitle}"${score == null ? '.' : ' and scored $score.'}',
    );
    super.dispose();
  }

  int? get _score {
    if (_answers.isEmpty || _story.quiz.isEmpty) return null;
    return _answers.entries
        .where(
          (entry) =>
              entry.key < _story.quiz.length &&
              entry.value == _story.quiz[entry.key].answerIndex,
        )
        .length;
  }

  void _next() {
    if (_step == _ReadingStep.check) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _step = _ReadingStep.values[_step.index + 1];
      if (_step == _ReadingStep.notice && _segments.isNotEmpty) {
        _selectedSegment = _selectedSegment.clamp(0, _segments.length - 1);
      }
    });
  }

  void _back() {
    if (_step == _ReadingStep.open) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _step = _ReadingStep.values[_step.index - 1]);
  }

  Future<void> _speakSegment(int index) async {
    if (index < 0 || index >= _segments.length) return;
    await LessonSpeechService.shared.speak(
      items: [
        SpeechItem(
          text: _segments[index].fr,
          language: 'fr-FR',
          contentItemId: _story.segmentContentId(index),
        ),
      ],
      onItemStart: (_) {
        if (mounted) setState(() => _playingSegment = index);
      },
      onFinished: () {
        if (mounted) setState(() => _playingSegment = -1);
      },
    );
  }

  Future<void> _speakStory() async {
    if (_segments.isEmpty) return;
    setState(() => _playing = true);
    await LessonSpeechService.shared.speak(
      items: [
        for (var i = 0; i < _segments.length; i++)
          SpeechItem(
            text: _segments[i].fr,
            language: 'fr-FR',
            contentItemId: _story.segmentContentId(i),
          ),
      ],
      onItemStart: (index) {
        if (mounted) setState(() => _playingSegment = index);
      },
      onFinished: () {
        if (mounted) {
          setState(() {
            _playing = false;
            _playingSegment = -1;
          });
        }
      },
    );
  }

  Future<void> _stopAudio() async {
    await LessonSpeechService.shared.stop();
    if (mounted) {
      setState(() {
        _playing = false;
        _playingSegment = -1;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DesignTokens.canvas,
      appBar: AppBar(
        leading: IconButton(
          onPressed: _back,
          icon: const Icon(CupertinoIcons.chevron_left),
        ),
        title: Text(
          _story.displayTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: DesignTokens.display(16),
        ),
        actions: [
          InlineCallActions(controller: _call),
          ReportProblemButton(sessionType: 'Reading: ${_story.displayTitle}'),
        ],
        backgroundColor: DesignTokens.canvas,
        foregroundColor: DesignTokens.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: WebConstrainedView(
        maxWidth: 760,
        child: Stack(
          children: [
            Column(
              children: [
                if (_call.isLive || _call.error != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: InlineCallStatusCard(
                      controller: _call,
                      listeningLabel: 'Marie is ready to discuss this book.',
                    ),
                  ),
                _ProgressHeader(step: _step),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: DesignTokens.durationMedium,
                    switchInCurve: DesignTokens.curveStandard,
                    child: KeyedSubtree(
                      key: ValueKey(_step),
                      child: _stepView(),
                    ),
                  ),
                ),
                _ActionFooter(
                  step: _step,
                  onNext: _next,
                  onStopAudio: _stopAudio,
                  playing: _playing,
                  score: _score,
                ),
              ],
            ),
            FloatingNotetakerOverlay(state: ref.watch(notetakerStateProvider)),
          ],
        ),
      ),
    );
  }

  Widget _stepView() => switch (_step) {
    _ReadingStep.open => _openView(),
    _ReadingStep.read => _readView(),
    _ReadingStep.notice => _noticeView(),
    _ReadingStep.words => _wordsView(),
    _ReadingStep.reread => _rereadView(),
    _ReadingStep.check => _checkView(),
  };

  Widget _openView() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        _BookHero(story: _story),
        const SizedBox(height: 22),
        Text('A short book for your level', style: DesignTokens.label(11)),
        const SizedBox(height: 8),
        Text(
          _story.summary.isEmpty
              ? 'Read for the main idea first. We will unpack the details together.'
              : _story.summary,
          style: DesignTokens.body(
            16,
          ).copyWith(color: DesignTokens.inkSoft, height: 1.5),
        ),
        const SizedBox(height: 18),
        _ReadingMap(
          labels: const [
            'Read the story',
            'Notice one sentence',
            'Build your word bank',
            'Reread with support',
            'Check your meaning',
          ],
          activeIndex: 0,
        ),
      ],
    );
  }

  Widget _readView() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        _SectionIntro(
          kicker: 'FIRST READ',
          title: 'Catch the story',
          body:
              'Read the French first. Tap a sentence when you want to hear it or choose it for the next lesson.',
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            TextButton.icon(
              onPressed: _playing ? _stopAudio : _speakStory,
              icon: Icon(
                _playing ? CupertinoIcons.stop_fill : CupertinoIcons.play_fill,
              ),
              label: Text(_playing ? 'Stop' : 'Read aloud'),
            ),
            const Spacer(),
            TextButton(
              onPressed: () =>
                  setState(() => _showTranslations = !_showTranslations),
              child: Text(_showTranslations ? 'Hide English' : 'Show English'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        for (var i = 0; i < _segments.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _SentenceCard(
              segment: _segments[i],
              index: i,
              selected: _selectedSegment == i,
              playing: _playingSegment == i,
              showTranslation: _showTranslations,
              onTap: () => setState(() => _selectedSegment = i),
              onPlay: () => _speakSegment(i),
            ),
          ),
      ],
    );
  }

  Widget _noticeView() {
    if (_segments.isEmpty) return const _EmptyReadingBody();
    final segment = _focusSegment;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        _SectionIntro(
          kicker: 'SENTENCE FOCUS',
          title: 'Make one line yours',
          body:
              'This is the sentence to notice today. See what it means, how it works, and how it sounds.',
        ),
        const SizedBox(height: 18),
        LearningCard(
          color: DesignTokens.primaryDeep,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'SENTENCE ${_selectedSegment + 1}',
                style: DesignTokens.label(
                  10,
                ).copyWith(color: Colors.white70, letterSpacing: 1),
              ),
              const SizedBox(height: 12),
              Text(
                segment.fr,
                style: DesignTokens.display(
                  22,
                ).copyWith(color: Colors.white, height: 1.35),
              ),
              const SizedBox(height: 12),
              Text(
                segment.en,
                style: DesignTokens.body(
                  15,
                ).copyWith(color: Colors.white70, height: 1.45),
              ),
              const SizedBox(height: 18),
              OutlinedButton.icon(
                onPressed: () => _speakSegment(_selectedSegment),
                icon: const Icon(CupertinoIcons.volume_up, size: 18),
                label: const Text('Hear this sentence'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white54),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (segment.grammarNote.isNotEmpty)
          _ExplanationCard(
            label: 'GRAMMAR',
            icon: CupertinoIcons.textformat,
            text: segment.grammarNote,
          ),
        if (segment.pronunciationTip.isNotEmpty) ...[
          const SizedBox(height: 10),
          _ExplanationCard(
            label: 'SOUND',
            icon: CupertinoIcons.waveform,
            text: segment.pronunciationTip,
          ),
        ],
        const SizedBox(height: 18),
        Text('Choose another sentence', style: DesignTokens.label(11)),
        const SizedBox(height: 8),
        SizedBox(
          height: 48,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _segments.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) => GestureDetector(
              onTap: () => setState(() => _selectedSegment = index),
              child: Container(
                width: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: index == _selectedSegment
                      ? DesignTokens.primary
                      : DesignTokens.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: DesignTokens.hairline),
                ),
                child: Text(
                  '${index + 1}',
                  style: DesignTokens.body(14, weight: FontWeight.w700)
                      .copyWith(
                        color: index == _selectedSegment
                            ? Colors.white
                            : DesignTokens.ink,
                      ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _wordsView() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        const _SectionIntro(
          kicker: 'WORD BANK',
          title: 'Keep the useful bits',
          body:
              'These words come from the story. Tap one to hear it, then notice it when you reread.',
        ),
        const SizedBox(height: 16),
        if (_story.keywords.isEmpty)
          const _EmptyReadingBody()
        else
          for (final word in _story.keywords)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: ModernCard(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(word.fr, style: DesignTokens.display(17)),
                          const SizedBox(height: 3),
                          Text(
                            word.en,
                            style: DesignTokens.body(
                              13,
                            ).copyWith(color: DesignTokens.primary),
                          ),
                          if (word.phonetic.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(
                              word.phonetic,
                              style: DesignTokens.body(
                                11,
                              ).copyWith(color: DesignTokens.mutedDim),
                            ),
                          ],
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => LessonSpeechService.shared.speak(
                        items: [
                          SpeechItem(
                            text: word.fr,
                            language: 'fr-FR',
                            contentItemId: '${_story.id}_word_${word.id}',
                          ),
                        ],
                      ),
                      icon: const Icon(CupertinoIcons.volume_up),
                      color: DesignTokens.primary,
                      tooltip: 'Hear ${word.fr}',
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }

  Widget _rereadView() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        const _SectionIntro(
          kicker: 'SECOND READ',
          title: 'Read with more confidence',
          body:
              'Now the meaning is available as a support layer. Try to read the French first, then check the English.',
        ),
        const SizedBox(height: 16),
        LearningCard(
          color: DesignTokens.infoSoft,
          child: Row(
            children: [
              const Icon(CupertinoIcons.lightbulb, color: DesignTokens.info),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Look for the sentence you studied and the words from your word bank.',
                  style: DesignTokens.body(13.5).copyWith(height: 1.4),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < _segments.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _SentenceCard(
              segment: _segments[i],
              index: i,
              selected: _selectedSegment == i,
              playing: _playingSegment == i,
              showTranslation: true,
              onTap: () => setState(() => _selectedSegment = i),
              onPlay: () => _speakSegment(i),
            ),
          ),
      ],
    );
  }

  Widget _checkView() {
    if (_story.quiz.isEmpty) return const _EmptyReadingBody();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        const _SectionIntro(
          kicker: 'RECALL',
          title: 'What stayed with you?',
          body:
              'Answer from the story. You can change an answer before you finish.',
        ),
        const SizedBox(height: 16),
        for (var i = 0; i < _story.quiz.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: _QuizCard(
              number: i + 1,
              question: _story.quiz[i],
              selected: _answers[i],
              onSelect: (answer) => setState(() => _answers[i] = answer),
            ),
          ),
      ],
    );
  }
}

class _ProgressHeader extends StatelessWidget {
  const _ProgressHeader({required this.step});

  final _ReadingStep step;

  @override
  Widget build(BuildContext context) {
    final progress = (step.index + 1) / _ReadingStep.values.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 5,
                backgroundColor: DesignTokens.hairline,
                valueColor: const AlwaysStoppedAnimation(DesignTokens.primary),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '${step.index + 1} / ${_ReadingStep.values.length}',
            style: DesignTokens.label(
              10,
            ).copyWith(color: DesignTokens.mutedDim),
          ),
        ],
      ),
    );
  }
}

class _ActionFooter extends StatelessWidget {
  const _ActionFooter({
    required this.step,
    required this.onNext,
    required this.onStopAudio,
    required this.playing,
    required this.score,
  });

  final _ReadingStep step;
  final VoidCallback onNext;
  final VoidCallback onStopAudio;
  final bool playing;
  final int? score;

  @override
  Widget build(BuildContext context) {
    final label = step == _ReadingStep.check
        ? 'Finish reading'
        : step == _ReadingStep.open
        ? 'Open the story'
        : step == _ReadingStep.read
        ? 'Study a sentence'
        : step == _ReadingStep.notice
        ? 'Build the word bank'
        : step == _ReadingStep.words
        ? 'Reread the book'
        : 'Check my understanding';
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
        decoration: BoxDecoration(
          color: DesignTokens.canvas,
          border: Border(top: BorderSide(color: DesignTokens.hairline)),
        ),
        child: Row(
          children: [
            if (playing)
              IconButton(
                onPressed: onStopAudio,
                icon: const Icon(CupertinoIcons.stop_fill),
                tooltip: 'Stop reading aloud',
              )
            else
              const SizedBox(width: 48),
            Expanded(
              child: PrimaryActionButton(
                label: score == null ? label : '$label · $score correct',
                onPressed: onNext,
                icon: step == _ReadingStep.check
                    ? CupertinoIcons.checkmark
                    : CupertinoIcons.arrow_right,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BookHero extends StatelessWidget {
  const _BookHero({required this.story});

  final GeneratedStory story;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(DesignTokens.radiusLarge),
      child: SizedBox(
        height: 292,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (story.coverUrl != null && story.coverUrl!.isNotEmpty)
              Image.network(
                story.coverUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  decoration: const BoxDecoration(
                    gradient: DesignTokens.heroGradient,
                  ),
                ),
              )
            else
              Container(
                decoration: const BoxDecoration(
                  gradient: DesignTokens.heroGradient,
                ),
              ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      DesignTokens.ink.withValues(alpha: 0.15),
                      DesignTokens.ink.withValues(alpha: 0.86),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              top: -55,
              right: -35,
              child: Container(
                width: 190,
                height: 190,
                decoration: BoxDecoration(
                  color: DesignTokens.secondary.withValues(alpha: 0.55),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  const Icon(
                    CupertinoIcons.book_fill,
                    color: Colors.white,
                    size: 36,
                  ),
                  const SizedBox(height: 18),
                  Text(
                    story.displayTitle,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: DesignTokens.display(
                      27,
                    ).copyWith(color: Colors.white, height: 1.16),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '${story.passage.segments.length} scenes · ${story.readTimeMinutes} min · ${story.levelBand}',
                    style: DesignTokens.body(
                      12,
                    ).copyWith(color: Colors.white70),
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

class _ReadingMap extends StatelessWidget {
  const _ReadingMap({required this.labels, required this.activeIndex});

  final List<String> labels;
  final int activeIndex;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < labels.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: i <= activeIndex
                        ? DesignTokens.primary
                        : DesignTokens.infoSoft,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '${i + 1}',
                    style: DesignTokens.body(12, weight: FontWeight.w700)
                        .copyWith(
                          color: i <= activeIndex
                              ? Colors.white
                              : DesignTokens.info,
                        ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(labels[i], style: DesignTokens.body(13.5)),
              ],
            ),
          ),
      ],
    );
  }
}

class _SectionIntro extends StatelessWidget {
  const _SectionIntro({
    required this.kicker,
    required this.title,
    required this.body,
  });

  final String kicker;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          kicker,
          style: DesignTokens.label(
            10,
          ).copyWith(color: DesignTokens.primary, letterSpacing: 1),
        ),
        const SizedBox(height: 7),
        Text(title, style: DesignTokens.display(24)),
        const SizedBox(height: 7),
        Text(
          body,
          style: DesignTokens.body(
            13.5,
          ).copyWith(color: DesignTokens.inkSoft, height: 1.45),
        ),
      ],
    );
  }
}

class _SentenceCard extends StatelessWidget {
  const _SentenceCard({
    required this.segment,
    required this.index,
    required this.selected,
    required this.playing,
    required this.showTranslation,
    required this.onTap,
    required this.onPlay,
  });

  final ReadingSegment segment;
  final int index;
  final bool selected;
  final bool playing;
  final bool showTranslation;
  final VoidCallback onTap;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: LearningCard(
        color: selected ? DesignTokens.primarySoft : DesignTokens.surface,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '${index + 1}'.padLeft(2, '0'),
                style: DesignTokens.label(
                  10,
                ).copyWith(color: DesignTokens.mutedDim),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    segment.fr,
                    style: DesignTokens.body(
                      16,
                      weight: FontWeight.w600,
                    ).copyWith(height: 1.45),
                  ),
                  if (showTranslation) ...[
                    const SizedBox(height: 6),
                    Text(
                      segment.en,
                      style: DesignTokens.body(
                        13,
                      ).copyWith(color: DesignTokens.primary, height: 1.4),
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              onPressed: onPlay,
              icon: Icon(
                playing ? CupertinoIcons.waveform : CupertinoIcons.play_circle,
              ),
              color: DesignTokens.primary,
              tooltip: 'Hear sentence ${index + 1}',
            ),
          ],
        ),
      ),
    );
  }
}

class _ExplanationCard extends StatelessWidget {
  const _ExplanationCard({
    required this.label,
    required this.icon,
    required this.text,
  });

  final String label;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return ModernCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: DesignTokens.info, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: DesignTokens.label(
                    10,
                  ).copyWith(color: DesignTokens.info, letterSpacing: 0.8),
                ),
                const SizedBox(height: 5),
                Text(
                  text,
                  style: DesignTokens.body(13.5).copyWith(height: 1.45),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuizCard extends StatelessWidget {
  const _QuizCard({
    required this.number,
    required this.question,
    required this.selected,
    required this.onSelect,
  });

  final int number;
  final MultipleChoiceQuestion question;
  final int? selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return ModernCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'QUESTION $number',
            style: DesignTokens.label(
              10,
            ).copyWith(color: DesignTokens.primary, letterSpacing: 0.8),
          ),
          const SizedBox(height: 8),
          Text(
            question.q,
            style: DesignTokens.display(16).copyWith(height: 1.35),
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < question.choices.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                onTap: () => onSelect(i),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 48),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: selected == i
                        ? DesignTokens.primarySoft
                        : DesignTokens.canvas,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selected == i
                          ? DesignTokens.primary
                          : DesignTokens.hairline,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        selected == i
                            ? CupertinoIcons.checkmark_circle_fill
                            : CupertinoIcons.circle,
                        size: 19,
                        color: selected == i
                            ? DesignTokens.primary
                            : DesignTokens.mutedDim,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          question.choices[i],
                          style: DesignTokens.body(13.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyReadingBody extends StatelessWidget {
  const _EmptyReadingBody();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          'This book does not have enough saved content for this step yet.',
          textAlign: TextAlign.center,
          style: DesignTokens.body(14).copyWith(color: DesignTokens.mutedDim),
        ),
      ),
    );
  }
}
