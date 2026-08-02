import 'dart:async';
import 'dart:math';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/alphabet_data.dart';
import '../../design/tokens.dart';
import '../../models/session.dart';
import '../../prompts/live_prompts.dart';
import '../../providers/database_provider.dart';
import '../../services/inline_call_controller.dart';
import '../../services/lesson_speech_service.dart';
import '../../services/session_recorder.dart';
import '../../widgets/adaptive/adaptive.dart';
import '../../widgets/inline_call_bar.dart';
import '../../widgets/passeport_card.dart';
import '../../widgets/passeport_primary_button.dart';
import '../../widgets/tts_play_button.dart';

/// One-time, static (not AI-generated — accuracy matters more here than
/// personalization) alphabet lesson, split into four short decks (the full
/// Alphabet, then Consonants, Vowels, and Accents on their own) instead of
/// one 26-card sitting, so a total beginner can do one deck at a time.
/// Deliberately NOT wired into Keep Practising or the 6 mission categories,
/// just a one-off foundational lesson living at the top of the Practice tab.
class AlphabetLabScreen extends ConsumerStatefulWidget {
  const AlphabetLabScreen({super.key});

  @override
  ConsumerState<AlphabetLabScreen> createState() => _AlphabetLabScreenState();
}

class _AlphabetLabScreenState extends ConsumerState<AlphabetLabScreen> {
  @override
  void initState() {
    super.initState();
    // This is the very first thing a brand-new user opens, so it can't feel
    // slow: every letter and accent name gets synthesized and cached to the
    // local database right away, in the background, the moment this screen
    // opens — by the time the student actually taps into a deck, every
    // speaker button just plays instantly from cache instead of waiting on
    // a live Gemini round-trip. One-time cost per install; after that this
    // never calls Gemini for these sounds again, same as any other cached
    // narration in the app.
    // Bounded concurrency, not one-at-a-time — this screen's whole point is
    // to be the fast, ready-to-go landing spot for a brand-new user, and by
    // now onboarding has likely already prewarmed most of this anyway (see
    // AlphabetPrewarm), so this mostly just mops up whatever a rushed
    // onboarding didn't finish before the user got here.
    unawaited(
      LessonSpeechService.shared.prewarmNarrationBounded(
        alphabetPrewarmItems(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(learningStoreProvider);
    return Scaffold(
      backgroundColor: DesignTokens.parchmentDim,
      appBar: AppBar(
        title: Text('Learn the Alphabet', style: DesignTokens.display(18)),
        backgroundColor: DesignTokens.parchmentDim,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Start with the full alphabet, then drill consonants, vowels, '
              'or accents on their own. Each deck takes about 10-15 minutes.',
              style: DesignTokens.body(
                13.5,
              ).copyWith(color: DesignTokens.slateDim, height: 1.4),
            ),
            const SizedBox(height: 20),
            for (final deck in _decks) ...[
              _DeckTile(
                deck: deck,
                completed: store.lessonStatus(deck.id).status == 'completed',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => _AlphabetDeckScreen(deck: deck),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}

final List<_AlphabetDeck> _decks = [
  _AlphabetDeck(
    id: 'learn_alphabet',
    title: 'Alphabet',
    subtitle: 'All 26 letters, start to finish',
    icon: CupertinoIcons.textformat_abc_dottedunderline,
    lettersOf: () => frenchAlphabet,
    quizPoolOf: (letters) => trickyAlphabetLetters,
  ),
  _AlphabetDeck(
    id: 'learn_consonants',
    title: 'Consonants',
    subtitle: 'The 20 non-vowels, and how a French mouth actually says them',
    icon: CupertinoIcons.textformat_abc,
    lettersOf: () => consonantLetters,
    quizPoolOf: (letters) =>
        letters.where((l) => l.isTricky || l.letter == 'R').toList(),
  ),
  _AlphabetDeck(
    id: 'learn_vowels',
    title: 'Vowels',
    subtitle:
        'A, E, I, O, U, Y: the sounds English speakers get backwards most',
    icon: CupertinoIcons.waveform_circle,
    lettersOf: () => vowelLetters,
    quizPoolOf: (letters) =>
        letters.where((l) => l.isTricky || l.letter == 'U').toList(),
  ),
  _AlphabetDeck(
    id: 'learn_accents',
    title: 'Accents',
    subtitle: 'É, È, Ê, Ç, Ë: the marks that change how a word sounds',
    icon: CupertinoIcons.textformat,
    lettersOf: () => frenchAccents,
    quizPoolOf: (letters) => letters,
  ),
];

class _AlphabetDeck {
  const _AlphabetDeck({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.lettersOf,
    required this.quizPoolOf,
  });

  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final List<AlphabetLetter> Function() lettersOf;
  final List<AlphabetLetter> Function(List<AlphabetLetter> letters) quizPoolOf;
}

class _DeckTile extends StatelessWidget {
  const _DeckTile({
    required this.deck,
    required this.completed,
    required this.onTap,
  });

  final _AlphabetDeck deck;
  final bool completed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        PSHaptics.light();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: DesignTokens.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: DesignTokens.hairline, width: 1),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: DesignTokens.info.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(deck.icon, color: DesignTokens.info, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        deck.title,
                        style: DesignTokens.body(15, weight: FontWeight.w500),
                      ),
                      if (completed) ...[
                        const SizedBox(width: 6),
                        Icon(
                          CupertinoIcons.checkmark_seal_fill,
                          size: 15,
                          color: DesignTokens.success,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    deck.subtitle,
                    style: DesignTokens.body(
                      12,
                    ).copyWith(color: DesignTokens.slateDim),
                  ),
                ],
              ),
            ),
            Icon(
              CupertinoIcons.chevron_right,
              color: DesignTokens.slate,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}

class _AlphabetDeckScreen extends ConsumerStatefulWidget {
  const _AlphabetDeckScreen({required this.deck});

  final _AlphabetDeck deck;

  @override
  ConsumerState<_AlphabetDeckScreen> createState() =>
      _AlphabetDeckScreenState();
}

class _AlphabetDeckScreenState extends ConsumerState<_AlphabetDeckScreen>
    with WidgetsBindingObserver {
  late final List<AlphabetLetter> _letters = widget.deck.lettersOf();
  bool _inQuiz = false;
  final DateTime _startedAt = DateTime.now();

  /// Marie's live-call button, inline in the AppBar — same InlineCallController
  /// every other reading/exercise screen uses, so the student can ask her
  /// about a letter or accent right here without leaving the page.
  late final InlineCallController _call;
  late final SessionRecorder _recorder;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _recorder = SessionRecorder(
      storage: ref.read(storageServiceProvider),
      stage: 'alphabet',
      topic: widget.deck.title,
    );
    _call = InlineCallController(
      sessionType: LiveSessionType.labAssistant,
      lessonContext: () => _lessonContext,
      learningStoreForProfile: ref.read(learningStoreProvider),
      onChanged: () {
        if (mounted) setState(() {});
      },
      onUserTranscript: (text) => _recorder.logUser(text),
      onTutorTranscript: (text) => _recorder.logTutor(text),
    );
  }

  String get _lessonContext {
    final buf = StringBuffer()
      ..writeln(
        'The student is learning: ${widget.deck.title} (French alphabet basics).',
      )
      ..writeln('Letters/marks in this deck and how each is said:');
    for (final l in _letters) {
      buf.writeln('${l.letter}: said "${l.phonetic}". ${l.note}');
    }
    return buf.toString();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _call.handleAppLifecycle(state);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _call.dispose();
    LessonSpeechService.shared.deactivate();
    if (!_inQuiz) {
      _recorder.finish(summary: 'Reviewed ${widget.deck.title.toLowerCase()}.');
    }
    super.dispose();
  }

  void _startQuiz() {
    LessonSpeechService.shared.deactivate();
    setState(() => _inQuiz = true);
  }

  void _finishQuiz(double score) {
    final passed = score >= 0.8;
    ref
        .read(learningStoreProvider)
        .setLessonStatus(
          widget.deck.id,
          passed ? 'completed' : 'in_progress',
          score: score,
        );
    final now = DateTime.now();
    _recorder.finish(
      summary:
          '${widget.deck.title}: scored ${(score * 100).round()}% on the review.',
    );
    ref
        .read(storageServiceProvider)
        .saveSession(
          Session(
            id: const Uuid().v4(),
            startedAt: _startedAt.toIso8601String(),
            endedAt: now.toIso8601String(),
            summary:
                '${widget.deck.title}: scored ${(score * 100).round()}% on the review.',
            topic: 'Alphabet: ${widget.deck.title}',
            stage: 'alphabet',
          ),
        );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DesignTokens.canvas,
      appBar: AppBar(
        title: Text(widget.deck.title, style: DesignTokens.display(18)),
        backgroundColor: DesignTokens.canvas,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [InlineCallActions(controller: _call)],
      ),
      body: _inQuiz
          ? _AlphabetQuiz(
              pool: widget.deck.quizPoolOf(_letters),
              onFinished: _finishQuiz,
            )
          : Column(
              children: [
                if (_call.isLive || _call.error != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: InlineCallStatusCard(
                      controller: _call,
                      listeningLabel:
                          'Listening. Ask about any letter anytime.',
                    ),
                  ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    itemCount: _letters.length,
                    itemBuilder: (context, i) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _CompactLetterCard(
                        letter: _letters[i],
                        contentItemId: alphabetAudioId(_letters[i]),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: PasseportPrimaryButton(
                    label: 'Take the quick review',
                    icon: CupertinoIcons.checkmark_seal,
                    onPressed: _startQuiz,
                  ),
                ),
              ],
            ),
    );
  }
}

/// A compact letter/accent card — deliberately short (fixed-height single
/// card used to be a whole empty screen) so 2-3 fit on one screen at once
/// and the whole deck is one continuous scroll, not a swipe-per-letter.
class _CompactLetterCard extends StatefulWidget {
  const _CompactLetterCard({required this.letter, required this.contentItemId});

  final AlphabetLetter letter;
  final String contentItemId;

  @override
  State<_CompactLetterCard> createState() => _CompactLetterCardState();
}

class _CompactLetterCardState extends State<_CompactLetterCard> {
  /// Both the big letter badge and the speaker icon must play the exact
  /// same sound with the exact same debounce — this key lets the badge's
  /// tap drive the same TtsPlayButton instance the speaker icon uses,
  /// instead of duplicating its cache/generating/playing state.
  final _ttsKey = GlobalKey<TtsPlayButtonState>();

  @override
  Widget build(BuildContext context) {
    final letter = widget.letter;
    return PasseportCard(
      padding: 14,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => _ttsKey.currentState?.trigger(),
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: DesignTokens.infoSoft,
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: Text(letter.letter, style: DesignTokens.display(26)),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // TtsPlayButton already debounces (disabled while
                    // generating/playing, so a second tap mid-playback is
                    // ignored until the sound finishes) and plays from the
                    // prewarmed cache instantly once it's been synthesized
                    // once, exactly what a fast, no-double-trigger button
                    // needs here. The letter badge above triggers this same
                    // instance via `_ttsKey`.
                    TtsPlayButton(
                      key: _ttsKey,
                      text: letter.letter,
                      contentItemId: widget.contentItemId,
                      size: 28,
                      iconSize: 15,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      '"${letter.phonetic}"',
                      style: DesignTokens.body(
                        14,
                        weight: FontWeight.w600,
                      ).copyWith(color: DesignTokens.primary),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  letter.note,
                  style: DesignTokens.body(
                    12.5,
                  ).copyWith(color: DesignTokens.inkSoft, height: 1.35),
                ),
                const SizedBox(height: 6),
                Text(
                  '${letter.exampleWord}: ${letter.exampleMeaning}',
                  style: DesignTokens.body(
                    12.5,
                    weight: FontWeight.w500,
                  ).copyWith(color: DesignTokens.slateDim),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A short, deterministic multiple-choice review over just this deck's
/// pool — no AI needed, this content never changes.
class _AlphabetQuiz extends StatefulWidget {
  const _AlphabetQuiz({required this.pool, required this.onFinished});

  final List<AlphabetLetter> pool;
  final ValueChanged<double> onFinished;

  @override
  State<_AlphabetQuiz> createState() => _AlphabetQuizState();
}

class _AlphabetQuizState extends State<_AlphabetQuiz> {
  late final List<_Question> _questions = _buildQuestions();
  final Map<int, String> _answers = {};
  bool _submitted = false;

  List<_Question> _buildQuestions() {
    final pool = widget.pool.isEmpty ? const <AlphabetLetter>[] : widget.pool;
    final random = Random();
    return pool.map((letter) {
      final distractors = pool.where((l) => l.letter != letter.letter).toList()
        ..shuffle(random);
      final choices = [letter, ...distractors.take(2)]..shuffle(random);
      return _Question(
        prompt: 'Which one is said like "${letter.phonetic}"?',
        choices: choices.map((c) => c.letter).toList(),
        answer: letter.letter,
      );
    }).toList()..shuffle(random);
  }

  double get _score {
    if (_questions.isEmpty) return 1.0;
    var correct = 0;
    for (var i = 0; i < _questions.length; i++) {
      if (_answers[i] == _questions[i].answer) correct++;
    }
    return correct / _questions.length;
  }

  @override
  Widget build(BuildContext context) {
    final allAnswered = _answers.length == _questions.length;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Quick review', style: DesignTokens.display(22)),
        const SizedBox(height: 4),
        Text(
          'Just the ones worth double-checking.',
          style: DesignTokens.body(14).copyWith(color: DesignTokens.slateDim),
        ),
        const SizedBox(height: 20),
        for (var i = 0; i < _questions.length; i++) ...[
          _QuestionCard(
            question: _questions[i],
            selected: _answers[i],
            checked: _submitted,
            onSelect: _submitted
                ? null
                : (choice) => setState(() => _answers[i] = choice),
          ),
          const SizedBox(height: 12),
        ],
        const SizedBox(height: 8),
        if (!_submitted)
          PasseportPrimaryButton(
            label: 'Check answers',
            onPressed: allAnswered
                ? () => setState(() => _submitted = true)
                : null,
          )
        else ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _score >= 0.8
                  ? DesignTokens.successSoft
                  : DesignTokens.primarySoft,
              borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
            ),
            child: Text(
              _score >= 0.8
                  ? '${(_score * 100).round()}%. Nicely done, this deck is marked complete.'
                  : '${(_score * 100).round()}%. Worth another look, but you can always come back to this later.',
              style: DesignTokens.body(14, weight: FontWeight.w500),
            ),
          ),
          const SizedBox(height: 12),
          PasseportPrimaryButton(
            label: 'Done',
            icon: CupertinoIcons.checkmark,
            onPressed: () => widget.onFinished(_score),
          ),
        ],
      ],
    );
  }
}

class _Question {
  const _Question({
    required this.prompt,
    required this.choices,
    required this.answer,
  });

  final String prompt;
  final List<String> choices;
  final String answer;
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({
    required this.question,
    required this.selected,
    required this.checked,
    required this.onSelect,
  });

  final _Question question;
  final String? selected;
  final bool checked;
  final ValueChanged<String>? onSelect;

  @override
  Widget build(BuildContext context) {
    return PasseportCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            question.prompt,
            style: DesignTokens.body(14.5, weight: FontWeight.w500),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: question.choices.map((choice) {
              final isSelected = selected == choice;
              final isCorrect = choice == question.answer;
              Color bg = DesignTokens.parchmentDim;
              Color border = DesignTokens.hairline;
              if (checked) {
                if (isCorrect) {
                  bg = DesignTokens.success.withValues(alpha: 0.12);
                  border = DesignTokens.success;
                } else if (isSelected) {
                  bg = DesignTokens.primary.withValues(alpha: 0.1);
                  border = DesignTokens.primary;
                }
              } else if (isSelected) {
                bg = DesignTokens.info.withValues(alpha: 0.12);
                border = DesignTokens.info;
              }
              return GestureDetector(
                onTap: onSelect == null ? null : () => onSelect!(choice),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: border),
                  ),
                  child: Text(
                    choice,
                    style: DesignTokens.body(14, weight: FontWeight.w600),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
