import 'package:flutter/material.dart';

import '../design/tokens.dart';
import '../models/content_models.dart';

/// Displays a French sentence and its English translation as tappable words.
///
/// The selected French word is paired with the matching glossary entry in the
/// translation, so both sides use the same accent color and underline. The
/// optional playback indexes preserve the separate word-by-word narration
/// indicator used by the reading and listening players.
class BilingualWordText extends StatelessWidget {
  const BilingualWordText({
    super.key,
    required this.source,
    required this.translation,
    required this.sourceStyle,
    required this.translationStyle,
    required this.keywords,
    required this.selectedSourceWord,
    required this.onSourceWordTap,
    this.playbackSourceWord,
    this.accentColor = DesignTokens.mastery,
    this.playbackTranslationWord,
    this.showTranslation = true,
    this.underlineSelected = true,
  });

  final String source;
  final String translation;
  final TextStyle sourceStyle;
  final TextStyle translationStyle;
  final List<VocabEntry> keywords;
  final int? selectedSourceWord;
  final ValueChanged<int> onSourceWordTap;
  final int? playbackSourceWord;
  final int? playbackTranslationWord;
  final Color accentColor;
  final bool showTranslation;
  final bool underlineSelected;

  @override
  Widget build(BuildContext context) {
    final sourceWords = _wordParts(source);
    final translationWords = _wordParts(translation);
    final selectedEntry = selectedSourceWord == null
        ? null
        : _entryForWord(sourceWords, selectedSourceWord!);
    final selectedTranslationWords = selectedSourceWord == null
        ? const <int>{}
        : _translationMatches(
            translationWords,
            selectedEntry?.en,
            selectedSourceWord!,
            sourceWords.length,
          );

    return Semantics(
      container: true,
      label: translationWords.isEmpty ? source : '$source $translation',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 0,
            runSpacing: 4,
            children: [
              for (var index = 0; index < sourceWords.length; index++)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onSourceWordTap(index),
                  child: Text(
                    '${sourceWords[index]}${index == sourceWords.length - 1 ? '' : ' '}',
                    style: _wordStyle(
                      sourceStyle,
                      selected: selectedSourceWord == index,
                      playing: playbackSourceWord == index,
                    ),
                  ),
                ),
            ],
          ),
          if (showTranslation && translationWords.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 0,
              runSpacing: 4,
              children: [
                for (var index = 0; index < translationWords.length; index++)
                  Text(
                    '${translationWords[index]}${index == translationWords.length - 1 ? '' : ' '}',
                    style: _wordStyle(
                      translationStyle,
                      selected: selectedTranslationWords.contains(index),
                      playing: playbackTranslationWord == index,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  TextStyle _wordStyle(
    TextStyle base, {
    required bool selected,
    required bool playing,
  }) {
    if (selected || playing) {
      return base.copyWith(
        color: accentColor,
        backgroundColor: accentColor.withValues(alpha: selected ? 0.14 : 0.1),
        decoration: underlineSelected
            ? TextDecoration.underline
            : TextDecoration.none,
        decorationColor: accentColor,
        decorationThickness: 1.5,
      );
    }
    return base;
  }

  VocabEntry? _entryForWord(List<String> words, int index) {
    if (index < 0 || index >= words.length) return null;
    final selected = _fold(words[index]);
    VocabEntry? best;
    var bestLength = 0;
    for (final entry in keywords) {
      final entryWords = _wordParts(entry.fr).map(_fold).toList();
      if (entryWords.isEmpty || !entryWords.contains(selected)) continue;
      if (entryWords.length > bestLength) {
        best = entry;
        bestLength = entryWords.length;
      }
    }
    return best;
  }

  Set<int> _translationMatches(
    List<String> words,
    String? target,
    int sourceIndex,
    int sourceCount,
  ) {
    final foldedWords = words.map(_fold).toList();
    if (foldedWords.isEmpty) return const <int>{};

    final targetWords = target == null
        ? const <String>[]
        : _wordParts(target).map(_fold).toList();

    if (targetWords.isNotEmpty) {
      for (
        var start = 0;
        start <= foldedWords.length - targetWords.length;
        start++
      ) {
        var matches = true;
        for (var offset = 0; offset < targetWords.length; offset++) {
          if (foldedWords[start + offset] != targetWords[offset]) {
            matches = false;
            break;
          }
        }
        if (matches) {
          return {
            for (var offset = 0; offset < targetWords.length; offset++)
              start + offset,
          };
        }
      }

      // When the generated translation is slightly different from the
      // glossary, keep the visual cue useful by matching any glossary words
      // that survive.
      final individual = <int>{};
      for (final targetWord in targetWords) {
        final match = foldedWords.indexOf(targetWord);
        if (match >= 0) individual.add(match);
      }
      if (individual.isNotEmpty) return individual;
    }

    // Last resort for an omitted glossary entry or paraphrase: point to the
    // equivalent position in the English sentence instead of silently
    // dropping the learner's selection. Every tappable source word therefore
    // gets a visible paired cue.
    final mapped = (sourceIndex * foldedWords.length / sourceCount).floor();
    return {mapped.clamp(0, foldedWords.length - 1)};
  }
}

List<String> _wordParts(String text) =>
    text.split(RegExp(r'\s+')).where((word) => word.isNotEmpty).toList();

String _fold(String value) => value
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
