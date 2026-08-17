import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/app_router.dart';
import '../../design/tokens.dart';
import '../../models/content_models.dart';
import '../../models/srs_state.dart';
import '../../models/tutor_persona.dart';
import '../../providers/database_provider.dart';
import '../../services/gemini_live_audio_service.dart';
import '../../services/lesson_agent_service.dart';
import '../../services/lesson_speech_service.dart';
import '../../services/speak_language_profile.dart';
import '../../widgets/learning_card.dart';
import '../../widgets/floating_notetaker.dart';
import '../../widgets/lesson_stage_rail.dart';
import '../../widgets/primary_action_button.dart';
import '../../widgets/report_problem_button.dart';
import '../../widgets/tts_play_button.dart';
import '../../widgets/web/web_constrained_view.dart';
import '../pathway/agent_led_vocab_screen.dart';

enum _VocabularyStep { preview, learn, recall, context, produce, review }

/// A finite, local-first vocabulary lesson.
///
/// The deck is assembled from the local SRS store before this screen renders.
/// Marie is an optional teaching pass, not a prerequisite for seeing the five
/// words. The rest of the session is deterministic and cheap: recall, context,
/// sentence production, and SRS review all operate on the same frozen deck.
class VocabularyWorkshopScreen extends ConsumerStatefulWidget {
  const VocabularyWorkshopScreen({
    super.key,
    required this.phase,
    required this.theme,
    this.initialDeck,
    this.contentItemPrefix,
    this.focusNote,
  });

  final int phase;
  final VocabTheme theme;
  final List<VocabEntry>? initialDeck;
  final String? contentItemPrefix;
  final String? focusNote;

  @override
  ConsumerState<VocabularyWorkshopScreen> createState() =>
      _VocabularyWorkshopScreenState();
}

class _VocabularyWorkshopScreenState
    extends ConsumerState<VocabularyWorkshopScreen> {
  static const _deckSize = 5;

  _VocabularyStep _step = _VocabularyStep.preview;
  List<VocabEntry> _deck = const [];
  List<List<VocabEntry>> _contextChoices = const [];
  final Map<String, BilingualExample> _contextExamples = {};
  bool _contextLoading = true;
  bool _loading = true;
  String? _error;
  int _index = 0;
  bool _revealed = false;
  bool _showRecallRating = false;
  int? _selectedContextChoice;
  bool _contextChecked = false;
  final _sentenceController = TextEditingController();
  bool _checkingSentence = false;
  MicroWritingFeedback? _sentenceFeedback;
  final Map<String, SRSGrade> _recallGrades = {};
  final Map<String, bool> _contextResults = {};
  final Map<String, String> _sentenceResults = {};
  late final TutorPersona _tutor = ActiveTutor.current;

  VocabEntry? get _current =>
      _deck.isEmpty || _index >= _deck.length ? null : _deck[_index];

  int get _weakCount => _deck.where((word) {
    final grade = _recallGrades[word.id];
    return grade == SRSGrade.again ||
        grade == SRSGrade.hard ||
        _contextResults[word.id] == false;
  }).length;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(notetakerStateProvider).currentContext = 'Vocabulary';
    });
    unawaited(_loadDeck());
  }

  @override
  void dispose() {
    LessonSpeechService.shared.deactivate();
    _sentenceController.dispose();
    super.dispose();
  }

  Future<void> _loadDeck() async {
    try {
      final supplied = widget.initialDeck;
      late final List<VocabEntry> deck;
      if (supplied != null) {
        deck = supplied.take(_deckSize).toList(growable: false);
      } else {
        final srs = ref.read(srsServiceProvider);
        List<VocabEntry> queued = const [];
        try {
          queued = await srs.buildQueue(
            phase: widget.phase,
            themeId: widget.theme.id,
            limit: _deckSize,
          );
        } catch (_) {
          // A generated library card is valid even before it is enrolled in
          // the global SRS queue.
        }
        final all = srs.allEntries(
          phase: widget.phase,
          themeId: widget.theme.id,
        );
        final seen = queued.map((word) => word.id).toSet();
        deck = [
          ...queued,
          ...all.where((word) => !seen.contains(word.id)),
          ...widget.theme.entries.where((word) => !seen.contains(word.id)),
        ].take(_deckSize).toList(growable: false);
      }
      if (deck.isEmpty) {
        throw StateError('This vocabulary set has no usable words.');
      }
      if (!mounted) return;
      setState(() {
        _deck = deck;
        _contextChoices = _buildContextChoices(deck);
        _contextLoading = true;
        _loading = false;
      });
      unawaited(_warmDeckAudio(deck));
      unawaited(_prepareContextExamples(deck));
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'This word set could not be loaded.';
        });
      }
    }
  }

  List<List<VocabEntry>> _buildContextChoices(List<VocabEntry> deck) {
    return [
      for (var i = 0; i < deck.length; i++)
        () {
          final candidates = [
            deck[i],
            ...deck.where((word) => word.id != deck[i].id).take(2),
          ];
          final offset = (i + 1) % candidates.length;
          return [...candidates.skip(offset), ...candidates.take(offset)];
        }(),
    ];
  }

  Future<void> _prepareContextExamples(List<VocabEntry> deck) async {
    final content = ref.read(contentServiceProvider);
    final profile = ref.read(learningStoreProvider).profile();
    final level = SpeakLanguageProfile.forProfile(profile).level;
    final prepared = <String, BilingualExample>{};

    await Future.wait(
      deck.map((word) async {
        final bundled = content.vocabExamples(word.id);
        if (bundled != null && _appearsInExample(word, bundled)) {
          prepared[word.id] = bundled;
          return;
        }

        try {
          final generated = await LessonAgentService.shared
              .generateVocabularyContext(word: word, levelBand: level);
          if (_appearsInExample(word, generated)) {
            prepared[word.id] = generated;
            return;
          }
        } catch (_) {
          // Keep the lesson usable offline if the live quality check cannot
          // complete; the deterministic fallback still produces a real cloze.
        }
        prepared[word.id] = BilingualExample(
          fr: 'Je vois ${word.fr}.',
          en: 'I see ${word.en}.',
        );
      }),
    );

    if (!mounted) return;
    setState(() {
      _contextExamples
        ..clear()
        ..addAll(prepared);
      _contextLoading = false;
    });
  }

  BilingualExample _exampleFor(VocabEntry word) {
    return ref.read(contentServiceProvider).vocabExamples(word.id) ??
        BilingualExample(
          fr: 'Je découvre ${word.fr}.',
          en: 'I discover ${word.en}.',
        );
  }

  String _audioId(String entryId, [String suffix = 'word']) {
    final prefix = widget.contentItemPrefix ?? 'vocab';
    return '$prefix:$entryId:$suffix';
  }

  Future<void> _warmDeckAudio(List<VocabEntry> deck) {
    final items = <({String text, String contentItemId})>[];
    for (final word in deck) {
      items.add((text: word.fr, contentItemId: _audioId(word.id)));
      final example = _exampleFor(word);
      items.add((
        text: example.fr,
        contentItemId: _audioId(word.id, 'example'),
      ));
    }
    return GeminiLiveAudioService.shared.warmDeck(
      voiceName: _tutor.voiceName,
      items: items,
    );
  }

  bool _appearsInExample(VocabEntry word, BilingualExample example) {
    final sentence = _fold(example.fr).replaceAll(RegExp(r'[^a-z0-9]+'), ' ');
    final target = _fold(word.fr).replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
    return target.isNotEmpty && ' $sentence '.contains(' $target ');
  }

  String _fold(String text) {
    const accents = {
      'é': 'e',
      'è': 'e',
      'ê': 'e',
      'ë': 'e',
      'à': 'a',
      'â': 'a',
      'ç': 'c',
      'î': 'i',
      'ï': 'i',
      'ô': 'o',
      'û': 'u',
      'ù': 'u',
      'œ': 'oe',
    };
    var folded = text.toLowerCase().trim();
    accents.forEach((from, to) => folded = folded.replaceAll(from, to));
    return folded;
  }

  void _startStep(_VocabularyStep step) {
    setState(() {
      _step = step;
      _index = 0;
      _revealed = false;
      _showRecallRating = false;
      _selectedContextChoice = null;
      _contextChecked = false;
      _sentenceController.clear();
      _sentenceFeedback = null;
    });
  }

  void _nextWord({_VocabularyStep? afterLast}) {
    if (_index >= _deck.length - 1) {
      _startStep(afterLast ?? _VocabularyStep.review);
      return;
    }
    setState(() {
      _index++;
      _revealed = false;
      _showRecallRating = false;
      _selectedContextChoice = null;
      _contextChecked = false;
      _sentenceController.clear();
      _sentenceFeedback = null;
    });
  }

  void _gradeRecall(SRSGrade grade) {
    final word = _current;
    if (word == null) return;
    ref
        .read(srsServiceProvider)
        .grade(
          entryId: word.id,
          grade: grade,
          responseType: grade == SRSGrade.good
              ? SRSResponseType.unaided
              : SRSResponseType.hinted,
        );
    setState(() {
      _recallGrades[word.id] = grade;
      _showRecallRating = false;
    });
  }

  void _previousRecallWord() {
    if (_index == 0) return;
    setState(() {
      _index--;
      _revealed = false;
      _showRecallRating = false;
    });
  }

  void _nextRecallWord() {
    _nextWord(afterLast: _VocabularyStep.context);
  }

  void _checkContext() {
    final word = _current;
    final choice = _selectedContextChoice;
    if (word == null || choice == null) return;
    setState(() {
      _contextChecked = true;
      _contextResults[word.id] = _contextChoices[_index][choice].id == word.id;
    });
  }

  Future<void> _checkSentence() async {
    final word = _current;
    final submission = _sentenceController.text.trim();
    if (word == null || submission.isEmpty) return;
    setState(() => _checkingSentence = true);
    try {
      final feedback = await ref
          .read(lessonAgentServiceProvider)
          .gradeMicroWriting(
            prompt:
                'Write one short French sentence using the vocabulary word ${word.fr} (${word.en}).',
            targetWords: [word.fr],
            submission: submission,
          );
      if (!mounted) return;
      setState(() {
        _checkingSentence = false;
        _sentenceFeedback = feedback;
        _sentenceResults[word.id] = submission;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _checkingSentence = false;
          _sentenceFeedback = MicroWritingFeedback(
            scoreOutOf10: 0,
            comment:
                'Your sentence is saved for practice. Keep using the word in context.',
          );
          _sentenceResults[word.id] = submission;
        });
      }
    }
  }

  Future<void> _teachWithMarie() async {
    if (_deck.isEmpty) return;
    final examples = <String, BilingualExample>{
      for (final word in _deck) word.id: _exampleFor(word),
    };
    await AppRouter.push(
      context,
      (_) => AgentLedVocabScreen(
        vocabQueue: _deck,
        focusNote:
            'Teach these five words in context. Keep explanations in English and use the example sentences shown on the cards.',
        examplesByWordId: examples,
      ),
      fullscreenDialog: true,
    );
  }

  void _reviewMissed() {
    final missed = _deck
        .where((word) {
          final recall = _recallGrades[word.id];
          return recall == SRSGrade.again ||
              recall == SRSGrade.hard ||
              _contextResults[word.id] == false;
        })
        .toList(growable: false);
    setState(() {
      if (missed.isNotEmpty) _deck = missed;
      _step = _VocabularyStep.recall;
      _index = 0;
      _revealed = false;
      _showRecallRating = false;
      _selectedContextChoice = null;
      _contextChecked = false;
    });
  }

  void _complete() => Navigator.of(context).pop(true);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DesignTokens.canvas,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(CupertinoIcons.chevron_left),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(widget.theme.title, style: DesignTokens.display(19)),
        backgroundColor: DesignTokens.canvas,
        foregroundColor: DesignTokens.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: Stack(
        children: [
          WebConstrainedView(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? _errorView()
                : ListView(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                    children: [
                      LessonStageRail(
                        labels: const [
                          'Preview',
                          'Learn',
                          'Recall',
                          'Context',
                          'Use',
                          'Done',
                        ],
                        currentIndex: _VocabularyStep.values.indexOf(_step),
                      ),
                      const SizedBox(height: 18),
                      _content(),
                      const SizedBox(height: 22),
                      ReportProblemButton(
                        sessionType: 'Vocabulary: ${widget.theme.title}',
                      ),
                    ],
                  ),
          ),
          FloatingNotetakerOverlay(state: ref.watch(notetakerStateProvider)),
        ],
      ),
    );
  }

  Widget _errorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: LearningCard(child: Text(_error!, style: DesignTokens.body(14))),
      ),
    );
  }

  Widget _content() {
    // A generated card can be opened before its words have been enrolled in
    // the global SRS queue. Keep that transient/empty state inside the page;
    // never let a stale step dereference a missing current word.
    if (_current == null) {
      return LearningCard(
        child: Column(
          children: [
            const Icon(
              CupertinoIcons.exclamationmark_circle,
              color: DesignTokens.primary,
              size: 30,
            ),
            const SizedBox(height: 10),
            Text(
              'This word set is not ready yet.',
              textAlign: TextAlign.center,
              style: DesignTokens.body(16, weight: FontWeight.w700),
            ),
            const SizedBox(height: 5),
            Text(
              'Return to the vocabulary library and choose another set or start a new session.',
              textAlign: TextAlign.center,
              style: DesignTokens.body(13).copyWith(color: DesignTokens.muted),
            ),
          ],
        ),
      );
    }
    return switch (_step) {
      _VocabularyStep.preview => _previewView(),
      _VocabularyStep.learn => _learnView(),
      _VocabularyStep.recall => _recallView(),
      _VocabularyStep.context => _contextView(),
      _VocabularyStep.produce => _produceView(),
      _VocabularyStep.review => _reviewView(),
    };
  }

  Widget _previewView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _StepLabel(number: '01', title: 'Preview'),
        const SizedBox(height: 10),
        Text(
          'Five words. One useful situation.',
          style: DesignTokens.display(28),
        ),
        const SizedBox(height: 8),
        Text(
          widget.focusNote ??
              'Your deck is ready locally. Audio is prepared in the background so the lesson stays fast.',
          style: DesignTokens.body(
            14,
          ).copyWith(color: DesignTokens.inkSoft, height: 1.4),
        ),
        const SizedBox(height: 16),
        for (var i = 0; i < _deck.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: LearningCard(
              padding: 13,
              child: Row(
                children: [
                  _NumberBadge(number: i + 1),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      _deck[i].fr,
                      style: DesignTokens.body(16, weight: FontWeight.w700),
                    ),
                  ),
                  Text(
                    _deck[i].en,
                    style: DesignTokens.body(
                      12.5,
                    ).copyWith(color: DesignTokens.mutedDim),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),
        PrimaryActionButton(
          label: 'Learn the five words',
          icon: CupertinoIcons.arrow_right,
          onPressed: () => _startStep(_VocabularyStep.learn),
        ),
      ],
    );
  }

  Widget _learnView() {
    final word = _current!;
    final example = _exampleFor(word);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _StepLabel(number: '02', title: 'Learn'),
        const SizedBox(height: 10),
        Text('Meet the word in context.', style: DesignTokens.display(27)),
        const SizedBox(height: 8),
        Text(
          'Listen, see the meaning, then ask Marie for a teaching pass over all five.',
          style: DesignTokens.body(
            14,
          ).copyWith(color: DesignTokens.inkSoft, height: 1.4),
        ),
        const SizedBox(height: 16),
        LearningCard(
          color: DesignTokens.primary.withValues(alpha: 0.08),
          borderColor: DesignTokens.primary.withValues(alpha: 0.16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '${_index + 1}/${_deck.length}',
                    style: DesignTokens.mono(
                      11,
                      weight: FontWeight.w700,
                    ).copyWith(color: DesignTokens.primary),
                  ),
                  const Spacer(),
                  TtsPlayButton(
                    text: word.fr,
                    contentItemId: _audioId(word.id),
                    audioResolver: () => GeminiLiveAudioService.shared.resolve(
                      text: word.fr,
                      contentItemId: _audioId(word.id),
                      voiceName: _tutor.voiceName,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(word.fr, style: DesignTokens.display(32)),
              const SizedBox(height: 5),
              Text(
                word.phonetic,
                style: DesignTokens.mono(
                  13,
                ).copyWith(color: DesignTokens.primary),
              ),
              const SizedBox(height: 12),
              Text(
                word.en,
                style: DesignTokens.body(18, weight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              Divider(color: DesignTokens.hairline),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      example.fr,
                      style: DesignTokens.body(
                        15,
                        weight: FontWeight.w600,
                      ).copyWith(height: 1.35),
                    ),
                  ),
                  TtsPlayButton(
                    text: example.fr,
                    size: 36,
                    contentItemId: _audioId(word.id, 'example'),
                    audioResolver: () => GeminiLiveAudioService.shared.resolve(
                      text: example.fr,
                      contentItemId: _audioId(word.id, 'example'),
                      voiceName: _tutor.voiceName,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                example.en,
                style: DesignTokens.body(
                  13,
                ).copyWith(color: DesignTokens.mutedDim),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: _teachWithMarie,
          icon: const Icon(CupertinoIcons.phone_fill, size: 17),
          label: const Text('Teach these five with Marie'),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: _index == 0 ? null : () => setState(() => _index--),
              icon: const Icon(CupertinoIcons.chevron_left, size: 16),
              label: const Text('Back'),
            ),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: _index == _deck.length - 1
                  ? null
                  : () => setState(() => _index++),
              icon: const Icon(CupertinoIcons.chevron_right, size: 16),
              label: const Text('Next word'),
            ),
          ],
        ),
        const SizedBox(height: 18),
        PrimaryActionButton(
          label: 'Test my recall',
          icon: CupertinoIcons.arrow_right,
          onPressed: () => _startStep(_VocabularyStep.recall),
        ),
      ],
    );
  }

  Widget _recallView() {
    final word = _current!;
    final selectedGrade = _recallGrades[word.id];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _StepLabel(number: '03', title: 'Recall'),
        const SizedBox(height: 10),
        Text('Can you retrieve it?', style: DesignTokens.display(27)),
        const SizedBox(height: 8),
        Text(
          'Try from memory first. Reveal the answer only when you need it.',
          style: DesignTokens.body(
            14,
          ).copyWith(color: DesignTokens.inkSoft, height: 1.4),
        ),
        const SizedBox(height: 16),
        LearningCard(
          color: DesignTokens.primary.withValues(alpha: 0.06),
          borderColor: DesignTokens.primary.withValues(alpha: 0.14),
          padding: 28,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 278),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        Text(
                          '${_index + 1}/${_deck.length}',
                          style: DesignTokens.mono(
                            11,
                            weight: FontWeight.w700,
                          ).copyWith(color: DesignTokens.primary),
                        ),
                        const Spacer(),
                        TtsPlayButton(
                          text: word.fr,
                          contentItemId: _audioId(word.id),
                          audioResolver: () =>
                              GeminiLiveAudioService.shared.resolve(
                                text: word.fr,
                                contentItemId: _audioId(word.id),
                                voiceName: _tutor.voiceName,
                              ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      word.fr,
                      textAlign: TextAlign.center,
                      style: DesignTokens.display(38),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      word.phonetic,
                      textAlign: TextAlign.center,
                      style: DesignTokens.mono(
                        13,
                      ).copyWith(color: DesignTokens.primary),
                    ),
                    const SizedBox(height: 24),
                    if (_revealed)
                      Text(
                        word.en,
                        textAlign: TextAlign.center,
                        style: DesignTokens.body(22, weight: FontWeight.w700),
                      )
                    else
                      OutlinedButton.icon(
                        onPressed: () => setState(() => _revealed = true),
                        icon: const Icon(CupertinoIcons.eye, size: 18),
                        label: const Text('Reveal meaning'),
                      ),
                    const Spacer(),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        LearningCard(
          padding: 4,
          child: Column(
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: Icon(
                  selectedGrade == null
                      ? CupertinoIcons.slider_horizontal_3
                      : CupertinoIcons.checkmark_circle,
                  size: 19,
                  color: selectedGrade == null
                      ? DesignTokens.mutedDim
                      : DesignTokens.success,
                ),
                title: Text(
                  selectedGrade == null ? 'How did it feel?' : 'Recall rated',
                  style: DesignTokens.body(13, weight: FontWeight.w700),
                ),
                subtitle: const Text('Optional'),
                trailing: Icon(
                  _showRecallRating
                      ? CupertinoIcons.chevron_up
                      : CupertinoIcons.chevron_down,
                  size: 17,
                  color: DesignTokens.mutedDim,
                ),
                onTap: () =>
                    setState(() => _showRecallRating = !_showRecallRating),
              ),
              if (_showRecallRating) ...[
                const Divider(height: 1),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _GradeButton(
                        label: 'Again',
                        color: DesignTokens.primary,
                        onTap: () => _gradeRecall(SRSGrade.again),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _GradeButton(
                        label: 'Needed help',
                        color: DesignTokens.info,
                        onTap: () => _gradeRecall(SRSGrade.hard),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _GradeButton(
                        label: 'I knew it',
                        color: DesignTokens.success,
                        onTap: () => _gradeRecall(SRSGrade.good),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _index == 0 ? null : _previousRecallWord,
                icon: const Icon(CupertinoIcons.chevron_left, size: 17),
                label: const Text('Back'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: PrimaryActionButton(
                label: _index == _deck.length - 1 ? 'Next step' : 'Next word',
                icon: CupertinoIcons.arrow_right,
                onPressed: _nextRecallWord,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _contextView() {
    final word = _current!;
    if (_contextLoading) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _StepLabel(number: '04', title: 'Context'),
          const SizedBox(height: 10),
          Text('Fill in the blank.', style: DesignTokens.display(27)),
          const SizedBox(height: 8),
          Text(
            'Preparing a sentence that uses each word naturally.',
            style: DesignTokens.body(
              14,
            ).copyWith(color: DesignTokens.inkSoft, height: 1.4),
          ),
          const SizedBox(height: 28),
          const Center(child: CircularProgressIndicator()),
        ],
      );
    }

    final example =
        _contextExamples[word.id] ??
        BilingualExample(fr: 'Je vois ${word.fr}.', en: 'I see ${word.en}.');
    final choices = _contextChoices[_index];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _StepLabel(number: '04', title: 'Context'),
        const SizedBox(height: 10),
        Text('Fill in the blank.', style: DesignTokens.display(27)),
        const SizedBox(height: 8),
        Text(
          'Use the sentence to retrieve the word, then check your choice.',
          style: DesignTokens.body(
            14,
          ).copyWith(color: DesignTokens.inkSoft, height: 1.4),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: LearningCard(
            color: DesignTokens.success.withValues(alpha: 0.07),
            borderColor: DesignTokens.success.withValues(alpha: 0.17),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _maskTarget(example.fr, word.fr),
                  style: DesignTokens.display(21).copyWith(height: 1.35),
                ),
                const SizedBox(height: 6),
                Text(
                  example.en,
                  style: DesignTokens.body(
                    13,
                  ).copyWith(color: DesignTokens.mutedDim),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        for (var i = 0; i < choices.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: _ContextChoice(
              label: choices[i].fr,
              selected: _selectedContextChoice == i,
              correct: _contextChecked && choices[i].id == word.id,
              incorrect:
                  _contextChecked &&
                  _selectedContextChoice == i &&
                  choices[i].id != word.id,
              onTap: _contextChecked
                  ? null
                  : () => setState(() => _selectedContextChoice = i),
            ),
          ),
        if (_contextChecked)
          Text(
            _contextResults[word.id] == true
                ? 'Correct. The sentence gives the word a job, not just a translation.'
                : 'Not quite. Look at the meaning and try to remember the example again.',
            style: DesignTokens.body(13, weight: FontWeight.w600).copyWith(
              color: _contextResults[word.id] == true
                  ? DesignTokens.success
                  : DesignTokens.primary,
            ),
          ),
        const SizedBox(height: 14),
        if (!_contextChecked)
          PrimaryActionButton(
            label: 'Check choice',
            icon: CupertinoIcons.checkmark,
            onPressed: _selectedContextChoice == null ? null : _checkContext,
          )
        else
          PrimaryActionButton(
            label: _index == _deck.length - 1
                ? 'Write with these words'
                : 'Next context',
            icon: CupertinoIcons.arrow_right,
            onPressed: () => _index == _deck.length - 1
                ? _startStep(_VocabularyStep.produce)
                : _nextWord(afterLast: _VocabularyStep.produce),
          ),
      ],
    );
  }

  String _maskTarget(String sentence, String target) {
    final start = sentence.toLowerCase().indexOf(target.toLowerCase());
    if (start < 0) return sentence;
    return '${sentence.substring(0, start)}_____${sentence.substring(start + target.length)}';
  }

  Widget _produceView() {
    final word = _current!;
    final example = _exampleFor(word);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _StepLabel(number: '05', title: 'Produce'),
        const SizedBox(height: 10),
        Text('Make the word yours.', style: DesignTokens.display(27)),
        const SizedBox(height: 8),
        Text(
          'Write one new sentence. It does not need to be perfect before you try.',
          style: DesignTokens.body(
            14,
          ).copyWith(color: DesignTokens.inkSoft, height: 1.4),
        ),
        const SizedBox(height: 16),
        LearningCard(
          child: Row(
            children: [
              Expanded(child: Text(word.fr, style: DesignTokens.display(25))),
              TtsPlayButton(
                text: word.fr,
                contentItemId: 'vocab_${word.id}_produce',
                audioResolver: () => GeminiLiveAudioService.shared.resolve(
                  text: word.fr,
                  contentItemId: 'vocab_${word.id}_produce',
                  voiceName: _tutor.voiceName,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Model: ${example.fr}',
          style: DesignTokens.body(
            12.5,
          ).copyWith(color: DesignTokens.mutedDim, height: 1.3),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _sentenceController,
          minLines: 3,
          maxLines: 5,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            hintText: 'Écris une phrase…',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _checkingSentence ? null : _checkSentence,
          icon: _checkingSentence
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(CupertinoIcons.sparkles),
          label: Text(_checkingSentence ? 'Checking…' : 'Check with AI'),
        ),
        if (_sentenceFeedback != null) ...[
          const SizedBox(height: 10),
          LearningCard(
            child: Text(
              _sentenceFeedback!.comment,
              style: DesignTokens.body(
                13,
              ).copyWith(color: DesignTokens.inkSoft, height: 1.35),
            ),
          ),
        ],
        const SizedBox(height: 16),
        PrimaryActionButton(
          label: _index == _deck.length - 1 ? 'See my review' : 'Next word',
          icon: CupertinoIcons.arrow_right,
          onPressed: () => _index == _deck.length - 1
              ? _startStep(_VocabularyStep.review)
              : _nextWord(afterLast: _VocabularyStep.review),
        ),
      ],
    );
  }

  Widget _reviewView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _StepLabel(number: '06', title: 'Review'),
        const SizedBox(height: 10),
        Text('Your words are now usable.', style: DesignTokens.display(27)),
        const SizedBox(height: 8),
        Text(
          'The SRS schedule is updated from your recall. Missed words can come back immediately without restarting the whole lesson.',
          style: DesignTokens.body(
            14,
          ).copyWith(color: DesignTokens.inkSoft, height: 1.4),
        ),
        const SizedBox(height: 16),
        LearningCard(
          color: DesignTokens.primary.withValues(alpha: 0.08),
          child: Row(
            children: [
              Text(
                '${_deck.length - _weakCount}',
                style: DesignTokens.display(
                  34,
                ).copyWith(color: DesignTokens.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'of ${_deck.length} words feel ready',
                  style: DesignTokens.body(14, weight: FontWeight.w700),
                ),
              ),
              Text(
                '$_weakCount to revisit',
                style: DesignTokens.mono(
                  11,
                ).copyWith(color: DesignTokens.mutedDim),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        for (final word in _deck)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: LearningCard(
              padding: 12,
              child: Row(
                children: [
                  Icon(
                    _isWeak(word)
                        ? CupertinoIcons.refresh
                        : CupertinoIcons.checkmark_circle_fill,
                    size: 19,
                    color: _isWeak(word)
                        ? DesignTokens.primary
                        : DesignTokens.success,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      word.fr,
                      style: DesignTokens.body(14, weight: FontWeight.w700),
                    ),
                  ),
                  Text(
                    word.en,
                    style: DesignTokens.body(
                      12,
                    ).copyWith(color: DesignTokens.mutedDim),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 10),
        if (_weakCount > 0) ...[
          OutlinedButton.icon(
            onPressed: _reviewMissed,
            icon: const Icon(CupertinoIcons.refresh, size: 17),
            label: const Text('Review missed words'),
          ),
          const SizedBox(height: 10),
        ],
        PrimaryActionButton(
          label: 'Complete vocabulary session',
          icon: CupertinoIcons.checkmark,
          onPressed: _complete,
        ),
      ],
    );
  }

  bool _isWeak(VocabEntry word) {
    final grade = _recallGrades[word.id];
    return grade == SRSGrade.again ||
        grade == SRSGrade.hard ||
        _contextResults[word.id] == false;
  }
}

class _StepLabel extends StatelessWidget {
  const _StepLabel({required this.number, required this.title});

  final String number;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          number,
          style: DesignTokens.mono(
            11,
            weight: FontWeight.w800,
          ).copyWith(color: DesignTokens.primary),
        ),
        const SizedBox(width: 8),
        Text(
          title.toUpperCase(),
          style: DesignTokens.mono(
            11,
            weight: FontWeight.w800,
          ).copyWith(color: DesignTokens.mutedDim, letterSpacing: 0.6),
        ),
      ],
    );
  }
}

class _NumberBadge extends StatelessWidget {
  const _NumberBadge({required this.number});

  final int number;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: DesignTokens.primary.withValues(alpha: 0.1),
        shape: BoxShape.circle,
      ),
      child: Text(
        '$number',
        style: DesignTokens.mono(
          11,
          weight: FontWeight.w800,
        ).copyWith(color: DesignTokens.primary),
      ),
    );
  }
}

class _GradeButton extends StatelessWidget {
  const _GradeButton({
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withValues(alpha: 0.45)),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 13),
      ),
      child: Text(label, textAlign: TextAlign.center),
    );
  }
}

class _ContextChoice extends StatelessWidget {
  const _ContextChoice({
    required this.label,
    required this.selected,
    required this.correct,
    required this.incorrect,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool correct;
  final bool incorrect;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = correct
        ? DesignTokens.success
        : incorrect
        ? DesignTokens.primary
        : selected
        ? DesignTokens.primary
        : DesignTokens.hairline;
    return LearningCard(
      padding: 13,
      color: selected ? color.withValues(alpha: 0.08) : null,
      borderColor: color,
      onTap: onTap,
      child: Row(
        children: [
          Icon(
            selected
                ? (correct
                      ? CupertinoIcons.checkmark_circle_fill
                      : CupertinoIcons.xmark_circle_fill)
                : CupertinoIcons.circle,
            size: 20,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: DesignTokens.body(14, weight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
