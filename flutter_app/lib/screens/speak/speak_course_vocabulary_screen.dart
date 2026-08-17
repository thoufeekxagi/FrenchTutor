import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../design/tokens.dart';
import '../../models/content_models.dart';
import '../../providers/database_provider.dart';
import '../../models/tutor_persona.dart';
import '../../services/gemini_live_audio_service.dart';
import '../../services/lesson_speech_service.dart';
import '../../services/speak_language_profile.dart';
import 'speak_ui.dart';
import '../../widgets/tts_play_button.dart';

/// The first stage of every course session. It is generated for the selected
/// course item and intentionally separate from the global SRS vocab lab so a
/// learner sees the words needed for this situation.
class SpeakCourseVocabularyScreen extends ConsumerStatefulWidget {
  const SpeakCourseVocabularyScreen({
    super.key,
    required this.topic,
    required this.sessionTitle,
    required this.contextPrompt,
    required this.contentKey,
    required this.levelBand,
    required this.targetPhrases,
  });

  final String topic;
  final String sessionTitle;
  final String contextPrompt;
  final String contentKey;
  final String levelBand;
  final List<String> targetPhrases;

  @override
  ConsumerState<SpeakCourseVocabularyScreen> createState() =>
      _SpeakCourseVocabularyScreenState();
}

class _SpeakCourseVocabularyScreenState
    extends ConsumerState<SpeakCourseVocabularyScreen> {
  static final _uuid = Uuid();

  late final TutorPersona _tutor = ActiveTutor.current;
  List<VocabEntry> _words = const [];
  int _index = 0;
  bool _loading = true;
  bool _finished = false;
  String? _error;

  SpeakLanguageProfile get _language =>
      SpeakLanguageProfile.forLevel(widget.levelBand);

  bool get _isFoundationDeck {
    final search = '${widget.topic} ${widget.sessionTitle} ${widget.contentKey}'
        .toLowerCase();
    return search.contains('alphabet') ||
        search.contains('vowel') ||
        search.contains('voyelle');
  }

  int get _deckSize {
    if (_isFoundationDeck) {
      // Foundation sessions need enough examples to connect sound training
      // to the speaking step. They remain single-word, A1-safe cards.
      return switch (_language.level) {
        'A1' || 'A2' => 5,
        _ => 6,
      };
    }
    return switch (_language.level) {
      'A1' => 1,
      'A2' => 2,
      _ => 3,
    };
  }

  VocabEntry? get _current =>
      _words.isEmpty || _index >= _words.length ? null : _words[_index];

  @override
  void initState() {
    super.initState();
    unawaited(_loadDeck());
  }

  @override
  void dispose() {
    unawaited(LessonSpeechService.shared.stop());
    super.dispose();
  }

  Future<void> _loadDeck() async {
    try {
      // Capture the provider value before the await. The screen can be popped
      // while generation is in flight; reading `ref` after disposal would
      // reproduce the production StateError seen in the writing workshop.
      final lessonAgent = ref.read(lessonAgentServiceProvider);
      List<VocabEntry> words;
      var generatedLive = false;
      try {
        final generated = await lessonAgent.generateCourseVocabulary(
          levelBand: _language.level,
          unitTitle: widget.topic,
          sessionTitle: widget.sessionTitle,
          contextPrompt: widget.contextPrompt,
          targetPhrases: widget.targetPhrases,
          count: _deckSize,
        );
        words = _normalizeForLevel(generated);
        if (words.length < _deckSize) {
          throw StateError(
            'The vocabulary generator returned ${words.length} of $_deckSize words.',
          );
        }
        generatedLive = true;
      } catch (_) {
        // Live generation remains the primary source. If its text response is
        // unavailable, use the learner's assigned private vocabulary library
        // for the card content. Audio never falls back from Gemini Live.
        words = _libraryWords();
        if (words.length < _deckSize) rethrow;
      }
      if (generatedLive) {
        ref
            .read(generatedVocabularySetStoreProvider)
            .insert(
              GeneratedVocabularySet(
                id: _uuid.v4(),
                title: widget.sessionTitle,
                summary: 'Contextual vocabulary for ${widget.topic}.',
                topic: widget.topic,
                levelBand: _language.level,
                entries: words,
                createdAt: DateTime.now(),
              ),
            );
      }
      if (mounted) {
        setState(() {
          _words = words;
          _loading = false;
        });
        unawaited(_warmDeck(words));
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _words = const [];
          _loading = false;
          _error =
              'We could not generate this live vocabulary set. Check your connection and try again.';
        });
      }
    }
  }

  List<VocabEntry> _libraryWords() {
    final query =
        '${widget.topic} ${widget.sessionTitle} ${widget.contextPrompt}'
            .toLowerCase();
    final sets = ref.read(generatedVocabularySetStoreProvider).list();
    final matching = sets
        .where((set) {
          final haystack = '${set.title} ${set.summary} ${set.topic}'
              .toLowerCase();
          return query
              .split(RegExp(r'\s+'))
              .where((token) => token.length > 2)
              .any(haystack.contains);
        })
        .toList(growable: false);
    final orderedSets = [
      ...matching,
      ...sets.where((set) => !matching.contains(set)),
    ];
    final entries = <VocabEntry>[];
    final seen = <String>{};
    for (final set in orderedSets) {
      for (final entry in _normalizeForLevel(set.entries)) {
        final key = entry.fr.trim().toLowerCase();
        if (key.isNotEmpty && seen.add(key)) entries.add(entry);
        if (entries.length == _deckSize) return entries;
      }
    }
    return entries;
  }

  List<VocabEntry> _normalizeForLevel(List<VocabEntry> words) {
    if (!_language.isBeginner) {
      return words.take(_deckSize).toList(growable: false);
    }
    // A1 should not receive chunks such as "à gauche" as its vocabulary
    // card. Keep one orthographic word; the sentence/context stages can teach
    // phrases later, after the learner has a usable base word.
    final singleWords = words
        .where((word) => !word.fr.trim().contains(RegExp(r'\s')))
        .toList(growable: false);
    return singleWords.take(_deckSize).toList(growable: false);
  }

  void _retry() {
    setState(() {
      _loading = true;
      _error = null;
      _words = const [];
      _index = 0;
      _finished = false;
    });
    unawaited(_loadDeck());
  }

  Future<void> _warmDeck(List<VocabEntry> words) {
    return GeminiLiveAudioService.shared.warmDeck(
      voiceName: _tutor.voiceName,
      items: [
        for (final word in words)
          (
            text: word.fr,
            contentItemId: '${widget.contentKey}:vocabulary:${word.id}',
          ),
      ],
    );
  }

  void _next() {
    if (_index >= _words.length - 1) {
      setState(() => _finished = true);
      return;
    }
    setState(() => _index++);
    unawaited(_warmCurrent());
  }

  Future<void> _warmCurrent() async {
    final word = _current;
    if (word == null) return;
    await GeminiLiveAudioService.shared.resolve(
      text: word.fr,
      contentItemId: '${widget.contentKey}:vocabulary:${word.id}',
      voiceName: _tutor.voiceName,
    );
  }

  @override
  Widget build(BuildContext context) {
    final word = _current;
    return SpeakScaffold(
      child: Column(
        children: [
          SpeakHeader(
            title: 'Vocabulary',
            subtitle: '${widget.sessionTitle} · ${_language.level}',
            leading: GestureDetector(
              onTap: () => Navigator.of(context).pop(false),
              child: const Icon(
                Icons.close_rounded,
                color: SpeakColors.inkSoft,
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
              children: [
                if (_loading) ...[
                  const SizedBox(height: 80),
                  const Center(child: CircularProgressIndicator()),
                  const SizedBox(height: 16),
                  Center(
                    child: Text(
                      'Building the words for this situation…',
                      style: DesignTokens.body(
                        14,
                      ).copyWith(color: SpeakColors.inkSoft),
                    ),
                  ),
                ] else if (_finished) ...[
                  const SizedBox(height: 48),
                  const Icon(
                    Icons.check_circle_outline_rounded,
                    color: SpeakColors.green,
                    size: 56,
                  ),
                  const SizedBox(height: 18),
                  Text(
                    _deckSize == 1 ? 'Word ready to use' : 'Words ready to use',
                    style: DesignTokens.display(28),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _deckSize == 1
                        ? 'Next, say this word in the situation. Then you will write with it.'
                        : 'Next, say these words in the situation. Then you will write with them.',
                    style: DesignTokens.body(
                      15,
                    ).copyWith(color: SpeakColors.inkSoft, height: 1.35),
                  ),
                ] else if (_error != null) ...[
                  const SizedBox(height: 48),
                  const Icon(
                    Icons.cloud_off_rounded,
                    color: SpeakColors.blue,
                    size: 56,
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Live vocabulary unavailable',
                    style: DesignTokens.display(26),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    style: DesignTokens.body(
                      15,
                    ).copyWith(color: SpeakColors.inkSoft, height: 1.35),
                  ),
                  const SizedBox(height: 22),
                  SpeakPrimaryButton(
                    label: 'Try again',
                    icon: Icons.refresh_rounded,
                    onTap: _retry,
                  ),
                ] else if (word != null) ...[
                  Text(
                    _deckSize == 1 ? 'ONE WORD' : '$_deckSize WORDS',
                    style: DesignTokens.label(
                      10,
                    ).copyWith(color: SpeakColors.blue, letterSpacing: 1.2),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    _language.isBeginner
                        ? (_deckSize == 1
                              ? 'Learn the one word you will use next.'
                              : 'Learn the words you will use next.')
                        : 'Build the language for this situation.',
                    style: DesignTokens.display(27),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _language.sessionHint,
                    style: DesignTokens.body(
                      15,
                    ).copyWith(color: SpeakColors.inkSoft, height: 1.35),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: DesignTokens.body(
                        12,
                      ).copyWith(color: SpeakColors.inkSoft),
                    ),
                  ],
                  const SizedBox(height: 24),
                  SpeakProgressBar(value: (_index + 1) / _words.length),
                  const SizedBox(height: 10),
                  Text(
                    '${_index + 1} of ${_words.length}',
                    style: DesignTokens.body(
                      12,
                      weight: FontWeight.w600,
                    ).copyWith(color: SpeakColors.inkSoft),
                  ),
                  const SizedBox(height: 18),
                  SpeakCard(
                    color: SpeakColors.blueSoft,
                    padding: const EdgeInsets.fromLTRB(24, 30, 24, 26),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 250),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(word.fr, style: DesignTokens.display(42)),
                          const SizedBox(height: 8),
                          Text(
                            word.en,
                            style: DesignTokens.body(
                              22,
                              weight: FontWeight.w700,
                            ).copyWith(color: SpeakColors.blue),
                          ),
                          if (word.phonetic.trim().isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              word.phonetic,
                              style: DesignTokens.body(
                                14,
                              ).copyWith(color: SpeakColors.inkSoft),
                            ),
                          ],
                          const SizedBox(height: 18),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TtsPlayButton(
                              text: word.fr,
                              label: 'Listen',
                              size: 50,
                              iconSize: 18,
                              color: SpeakColors.blue,
                              contentItemId:
                                  '${widget.contentKey}:vocabulary:${word.id}',
                              audioResolver: () =>
                                  GeminiLiveAudioService.shared.resolve(
                                    text: word.fr,
                                    contentItemId:
                                        '${widget.contentKey}:vocabulary:${word.id}',
                                    voiceName: _tutor.voiceName,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    _deckSize == 1
                        ? 'Use this word in speaking, then apply it in writing.'
                        : 'Use these words in speaking, then apply them in writing.',
                    style: DesignTokens.body(
                      13,
                    ).copyWith(color: SpeakColors.inkSoft, height: 1.35),
                  ),
                ],
              ],
            ),
          ),
          if (!_loading)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: SpeakPrimaryButton(
                label: _finished
                    ? 'Continue to speaking'
                    : (_deckSize == 1 ? 'I know this word' : 'Next word'),
                icon: Icons.arrow_forward_rounded,
                onTap: _finished
                    ? () => Navigator.of(context).pop(true)
                    : _next,
              ),
            ),
        ],
      ),
    );
  }
}
