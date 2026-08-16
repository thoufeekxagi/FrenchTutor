import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/content_service.dart';
import '../../design/tokens.dart';
import '../../models/content_models.dart';
import '../../providers/database_provider.dart';
import '../../services/lesson_speech_service.dart';
import '../../services/speak_language_profile.dart';
import 'speak_ui.dart';

/// The first stage of every course session. It is contextual to the selected
/// course item, cached after generation, and intentionally separate from the
/// global SRS vocab lab so a learner sees the words needed for this situation.
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
  List<VocabEntry> _words = const [];
  int _index = 0;
  bool _loading = true;
  bool _finished = false;
  String? _error;

  SpeakLanguageProfile get _language =>
      SpeakLanguageProfile.forLevel(widget.levelBand);

  int get _deckSize => switch (_language.level) {
    'A1' => 1,
    'A2' => 2,
    _ => 3,
  };

  VocabEntry? get _current =>
      _words.isEmpty || _index >= _words.length ? null : _words[_index];

  // v3 intentionally invalidates older phrase-heavy decks. A1 is a true
  // beginner path: one concrete French word, one meaning, one small practice.
  String get _cacheKey => 'course_vocab_${widget.contentKey}_v3';

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
    final prefs = await SharedPreferences.getInstance();
    final cached = _decodeDeck(prefs.getString(_cacheKey));
    if (cached.length >= _deckSize) {
      if (mounted) {
        setState(() {
          _words = cached.take(_deckSize).toList(growable: false);
          _loading = false;
        });
      }
      return;
    }

    try {
      final generated = await ref
          .read(lessonAgentServiceProvider)
          .generateCourseVocabulary(
            levelBand: _language.level,
            unitTitle: widget.topic,
            sessionTitle: widget.sessionTitle,
            contextPrompt: widget.contextPrompt,
            targetPhrases: widget.targetPhrases,
            count: _deckSize,
          );
      final words = _normalizeForLevel(generated);
      if (words.isEmpty) throw StateError('The vocabulary deck was empty.');
      await prefs.setString(
        _cacheKey,
        jsonEncode(words.map((word) => word.toJson()).toList()),
      );
      if (mounted) {
        setState(() {
          _words = words;
          _loading = false;
        });
      }
    } catch (_) {
      final fallback = _fallbackDeck(ref.read(contentServiceProvider));
      if (mounted) {
        setState(() {
          _words = _normalizeForLevel(fallback);
          _loading = false;
          _error = 'Using the offline deck for this situation.';
        });
      }
    }
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
    return singleWords.take(1).toList(growable: false);
  }

  List<VocabEntry> _decodeDeck(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final values = jsonDecode(raw) as List;
      return values
          .whereType<Map>()
          .map((value) => VocabEntry.fromJson(value.cast<String, dynamic>()))
          .where(
            (word) => word.fr.trim().isNotEmpty && word.en.trim().isNotEmpty,
          )
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  List<VocabEntry> _fallbackDeck(ContentService content) {
    final search = '${widget.topic} ${widget.sessionTitle}'.toLowerCase();
    final candidates = <VocabEntry>[];
    for (final phase in content.vocabPhases) {
      for (final theme in phase.themes) {
        final themeMatches =
            search.contains(theme.title.toLowerCase()) ||
            theme.title.toLowerCase().contains(search.split(' ').first);
        if (themeMatches) candidates.addAll(theme.entries);
      }
    }
    for (final phase in content.vocabPhases) {
      for (final theme in phase.themes) {
        candidates.addAll(theme.entries);
      }
    }
    final unique = <String, VocabEntry>{};
    for (final word in candidates) {
      unique.putIfAbsent(word.fr.toLowerCase(), () => word);
    }
    final available = _language.isBeginner
        ? unique.values.where(
            (word) => !word.fr.trim().contains(RegExp(r'\s')),
          )
        : unique.values;
    final selected = available.take(_deckSize).toList();
    if (selected.length == _deckSize) return selected;
    return [
      VocabEntry(
        id: 'offline-billet',
        fr: 'billet',
        en: 'ticket',
        phonetic: 'bee-yay',
      ),
      VocabEntry(
        id: 'offline-gare',
        fr: 'gare',
        en: 'station',
        phonetic: 'gahr',
      ),
      VocabEntry(
        id: 'offline-train',
        fr: 'train',
        en: 'train',
        phonetic: 'trahn',
      ),
      ...selected,
      VocabEntry(
        id: 'offline-ville',
        fr: 'la ville',
        en: 'the city',
        phonetic: 'lah veel',
      ),
      VocabEntry(
        id: 'offline-aller',
        fr: 'aller',
        en: 'to go',
        phonetic: 'ah-lay',
      ),
      VocabEntry(id: 'offline-ou', fr: 'où', en: 'where', phonetic: 'oo'),
      VocabEntry(
        id: 'offline-a-gauche',
        fr: 'à gauche',
        en: 'to the left',
        phonetic: 'ah gosh',
      ),
      VocabEntry(
        id: 'offline-a-droite',
        fr: 'à droite',
        en: 'to the right',
        phonetic: 'ah drwat',
      ),
      VocabEntry(
        id: 'offline-sil-vous-plait',
        fr: "s'il vous plaît",
        en: 'please',
        phonetic: 'seel voo pleh',
      ),
    ].toList(growable: false);
  }

  Future<void> _speakCurrent() async {
    final word = _current;
    if (word == null) return;
    await LessonSpeechService.shared.speak(
      items: [SpeechItem(text: word.fr, language: 'fr-FR')],
    );
  }

  void _next() {
    if (_index >= _words.length - 1) {
      setState(() => _finished = true);
      return;
    }
    setState(() => _index++);
    unawaited(_speakCurrent());
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
                    padding: const EdgeInsets.fromLTRB(22, 26, 22, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(word.fr, style: DesignTokens.display(34)),
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
                          child: OutlinedButton.icon(
                            onPressed: _speakCurrent,
                            icon: const Icon(
                              Icons.volume_up_outlined,
                              size: 18,
                            ),
                            label: const Text('Listen'),
                          ),
                        ),
                      ],
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
