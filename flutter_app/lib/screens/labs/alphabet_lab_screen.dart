import 'dart:async';
import 'dart:math';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;
import 'package:uuid/uuid.dart';

import '../../data/alphabet_data.dart';
import '../../design/tokens.dart';
import '../../models/session.dart';
import '../../models/tutor_persona.dart';
import '../../prompts/live_prompts.dart';
import '../../providers/database_provider.dart';
import '../../services/inline_call_controller.dart';
import '../../services/lesson_speech_service.dart';
import '../../services/session_recorder.dart';
import '../../widgets/inline_call_bar.dart';
import '../../widgets/tts_play_button.dart';
import '../speak/speak_ui.dart';

/// One-time, static (not AI-generated — accuracy matters more here than
/// personalization) alphabet lesson, split into four short decks (the full
/// Alphabet, then Consonants, Vowels, and Accents on their own) instead of
/// one 26-card sitting, so a total beginner can do one deck at a time. The
/// course supplies a deck id when it needs a focused foundation lesson; the
/// general alphabet entry opens the full alphabet directly instead of adding
/// a second picker screen.
class AlphabetLabScreen extends StatelessWidget {
  const AlphabetLabScreen({super.key, this.deckId});

  final String? deckId;

  @override
  Widget build(BuildContext context) {
    final deckId = this.deckId ?? 'learn_alphabet';
    final deck = _decks.firstWhere(
      (candidate) => candidate.id == deckId,
      orElse: () => _decks.first,
    );
    return _AlphabetDeckScreen(deck: deck);
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
  Map<String, String> _remoteStoragePaths = const {};
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
    unawaited(_loadRemoteAudioCatalog());
  }

  Future<void> _loadRemoteAudioCatalog() async {
    try {
      final rows = await Supabase.instance.client
          .from('alphabet_audio_catalog')
          .select('letter, storage_path')
          .eq('persona_id', ActiveTutor.current.id);
      final paths = <String, String>{};
      for (final row in rows.whereType<Map>()) {
        final letter = row['letter']?.toString().trim();
        final storagePath = row['storage_path']?.toString().trim();
        if (letter != null &&
            letter.isNotEmpty &&
            storagePath != null &&
            storagePath.isNotEmpty) {
          paths[letter] = storagePath;
        }
      }
      if (mounted) setState(() => _remoteStoragePaths = paths);
    } catch (_) {
      // The bundled PCM catalog remains the immediate offline fallback.
    }
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
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return SpeakScaffold(
      child: Column(
        children: [
          SpeakHeader(
            title: widget.deck.title,
            subtitle: '${_letters.length} sounds · tap any letter to hear it',
            leading: GestureDetector(
              onTap: () => Navigator.of(context).pop(false),
              child: const Icon(
                Icons.close_rounded,
                color: SpeakColors.inkSoft,
              ),
            ),
            trailing: InlineCallActions(controller: _call),
          ),
          Expanded(
            child: _inQuiz
                ? _AlphabetQuiz(
                    pool: widget.deck.quizPoolOf(_letters),
                    onFinished: _finishQuiz,
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
                    children: [
                      Text(
                        'Learn the sound, see it in a word, then check your recall.',
                        style: DesignTokens.body(
                          15,
                        ).copyWith(color: SpeakColors.inkSoft, height: 1.35),
                      ),
                      if (_call.isLive || _call.error != null) ...[
                        const SizedBox(height: 14),
                        InlineCallStatusCard(
                          controller: _call,
                          listeningLabel:
                              'Listening. Ask about any letter anytime.',
                        ),
                      ],
                      const SizedBox(height: 20),
                      for (final letter in _letters) ...[
                        _CompactLetterCard(
                          letter: letter,
                          contentItemId: alphabetAudioId(letter),
                          remoteStoragePath: _remoteStoragePaths[letter.letter],
                        ),
                        const SizedBox(height: 10),
                      ],
                    ],
                  ),
          ),
          if (!_inQuiz)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: SpeakPrimaryButton(
                label: 'Take the quick review',
                icon: Icons.verified_outlined,
                onTap: _startQuiz,
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
  const _CompactLetterCard({
    required this.letter,
    required this.contentItemId,
    this.remoteStoragePath,
  });

  final AlphabetLetter letter;
  final String contentItemId;
  final String? remoteStoragePath;

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
    return SpeakCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 15),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => _ttsKey.currentState?.trigger(),
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: SpeakColors.blueSoft,
                borderRadius: BorderRadius.circular(16),
              ),
              alignment: Alignment.center,
              child: Text(letter.letter, style: DesignTokens.display(28)),
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
                      text: alphabetSpokenText(letter),
                      contentItemId: widget.contentItemId,
                      remoteStoragePath: widget.remoteStoragePath,
                      bundledAssetPath: alphabetAudioAssetPath(
                        letter,
                        ActiveTutor.current,
                      ),
                      color: SpeakColors.blue,
                      size: 28,
                      iconSize: 15,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      '"${letter.phonetic}"',
                      style: DesignTokens.body(
                        14,
                        weight: FontWeight.w600,
                      ).copyWith(color: SpeakColors.blue),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  letter.note,
                  style: DesignTokens.body(
                    12.5,
                  ).copyWith(color: SpeakColors.inkSoft, height: 1.35),
                ),
                const SizedBox(height: 6),
                Text(
                  '${letter.exampleWord}: ${letter.exampleMeaning}',
                  style: DesignTokens.body(
                    12.5,
                    weight: FontWeight.w500,
                  ).copyWith(color: SpeakColors.inkSoft),
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
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
      children: [
        Text('Quick review', style: DesignTokens.display(22)),
        const SizedBox(height: 4),
        Text(
          'Just the ones worth double-checking.',
          style: DesignTokens.body(14).copyWith(color: SpeakColors.inkSoft),
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
          SpeakPrimaryButton(
            label: 'Check answers',
            onTap: allAnswered ? () => setState(() => _submitted = true) : null,
          )
        else ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: SpeakColors.blueSoft,
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
          SpeakPrimaryButton(
            label: 'Done',
            icon: CupertinoIcons.checkmark,
            onTap: () => widget.onFinished(_score),
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
    return SpeakCard(
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
              Color bg = SpeakColors.line;
              Color border = SpeakColors.line;
              if (checked) {
                if (isCorrect) {
                  bg = SpeakColors.blueSoft;
                  border = SpeakColors.blue;
                } else if (isSelected) {
                  bg = SpeakColors.blueSoft;
                  border = SpeakColors.blue;
                }
              } else if (isSelected) {
                bg = SpeakColors.blueSoft;
                border = SpeakColors.blue;
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
