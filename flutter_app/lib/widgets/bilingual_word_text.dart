import 'package:flutter/material.dart';

import '../design/tokens.dart';
import '../models/content_models.dart';

/// Displays a French sentence and its English translation. Only the French
/// side is ever tappable/highlightable, whether by tap-to-select or by the
/// word-by-word narration indicator during playback (Readle's convention):
/// mapping a highlight onto the English line is frequently wrong, since
/// English word order and word count rarely line up with the French
/// original, and a wrong highlight actively misleads a learner. The
/// translation line is plain, non-interactive text.
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
    this.sourceToTranslation,
    this.playbackSourceWord,
    this.accentColor,
    this.playbackTranslationWord,
    this.showTranslation = true,
    this.highlightSelected = true,
    this.underlineSelected = true,
    this.strictAlignment = false,
  });

  final String source;
  final String translation;
  final TextStyle sourceStyle;
  final TextStyle translationStyle;
  final List<VocabEntry> keywords;
  final int? selectedSourceWord;
  final ValueChanged<int> onSourceWordTap;

  /// Optional explicit alignment for authored bilingual lines. Each source
  /// word index maps to the translation word indexes that express it.
  final List<List<int>>? sourceToTranslation;
  final int? playbackSourceWord;
  final int? playbackTranslationWord;
  final Color? accentColor;
  final bool showTranslation;
  final bool highlightSelected;
  final bool underlineSelected;
  final bool strictAlignment;

  @override
  Widget build(BuildContext context) {
    final sourceWords = _wordParts(source);
    final translationWords = _wordParts(translation);
    // Readle-style rule: only the French word itself is ever highlighted,
    // whether tapped or currently narrated. The English line used to mirror
    // a "matching" word (by glossary lookup during selection, or by a mapped
    // index during playback), but that match is frequently wrong — English
    // word order and word count rarely line up with the French original —
    // and a wrong highlight actively misleads a learner about what a word
    // means. The translation line is now purely informational text.

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
            Text(translation, style: translationStyle),
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
    final accent = accentColor ?? DesignTokens.mastery;
    if (selected || playing) {
      return base.copyWith(
        color: highlightSelected ? accent : base.color,
        backgroundColor: highlightSelected
            ? accent.withValues(alpha: selected ? 0.14 : 0.1)
            : null,
        decoration: underlineSelected
            ? TextDecoration.underline
            : TextDecoration.none,
        decorationColor: accent,
        decorationThickness: 1.5,
      );
    }
    return base;
  }

}

List<String> _wordParts(String text) =>
    text.split(RegExp(r'\s+')).where((word) => word.isNotEmpty).toList();
