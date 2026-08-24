import 'package:flutter/material.dart';

import '../design/tokens.dart';
import '../models/chat_message.dart';
import '../models/tutor_persona.dart';
import '../screens/speak/speak_ui.dart';

/// A quiet, persistent chat rail for voice conversations.
///
/// Each turn keeps the familiar messenger layout: the tutor stays on the
/// left, the learner stays on the right, and the small avatar sits outside the
/// corresponding message bubble.
class SpeakingTranscriptStrip extends StatelessWidget {
  const SpeakingTranscriptStrip({
    super.key,
    required this.messages,
    required this.controller,
    this.tutorName,
    this.height = 148,
    this.dark = false,
  });

  final List<ChatMessage> messages;
  final ScrollController controller;
  final String? tutorName;
  final double height;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TutorPersona>(
      valueListenable: ActiveTutor.notifier,
      builder: (context, persona, _) =>
          _buildContent(context, tutorName ?? persona.displayName),
    );
  }

  Widget _buildContent(BuildContext context, String resolvedTutorName) {
    // Keep the rail's viewport fixed. Only the ListView inside it may move;
    // otherwise each new turn changes the rail height and pushes the tutor
    // portrait/name downward in the call screen.
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: SizedBox(
        height: height,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
          clipBehavior: Clip.hardEdge,
          decoration: BoxDecoration(
            color: dark
                ? DesignTokens.nightSurface.withValues(alpha: 0.92)
                : Colors.white.withValues(alpha: 0.82),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: dark ? DesignTokens.nightHairline : SpeakColors.line,
            ),
          ),
          child: messages.isEmpty
              ? Center(
                  child: Text(
                    'Your conversation will appear here.',
                    textAlign: TextAlign.center,
                    style: DesignTokens.body(14).copyWith(
                      color: dark
                          ? DesignTokens.nightMuted
                          : SpeakColors.inkSoft,
                    ),
                  ),
                )
              : ListView.separated(
                  controller: controller,
                  physics: const ClampingScrollPhysics(),
                  padding: const EdgeInsets.only(right: 4),
                  itemCount: messages.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 7),
                  itemBuilder: (context, index) => _TranscriptLine(
                    message: messages[index],
                    tutorName: resolvedTutorName,
                    dark: dark,
                  ),
                ),
        ),
      ),
    );
  }
}

class _TranscriptLine extends StatelessWidget {
  const _TranscriptLine({
    required this.message,
    required this.tutorName,
    required this.dark,
  });

  final ChatMessage message;
  final String tutorName;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    final displayText = isUser
        ? _compactUserTranscript(message.content)
        : message.content;
    final accent = isUser
        ? (dark ? DesignTokens.nightAccent : SpeakColors.accent)
        : (dark ? DesignTokens.nightText : SpeakColors.green);
    const avatarGap = 7.0;
    final bubble = Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: isUser
            ? (dark
                  ? DesignTokens.nightAccentSoft
                  : SpeakColors.accentSoft.withValues(alpha: 0.78))
            : (dark
                  ? DesignTokens.nightSurfaceRaised
                  : Colors.white.withValues(alpha: 0.72)),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(15),
          topRight: const Radius.circular(15),
          bottomLeft: Radius.circular(isUser ? 15 : 4),
          bottomRight: Radius.circular(isUser ? 4 : 15),
        ),
        border: Border.all(
          color: isUser
              ? (dark
                    ? DesignTokens.nightAccent.withValues(alpha: 0.32)
                    : SpeakColors.accent.withValues(alpha: 0.20))
              : (dark ? DesignTokens.nightHairline : SpeakColors.line),
        ),
      ),
      child: SelectableText.rich(
        TextSpan(
          text: _quoteFrenchTerms(displayText),
          style: DesignTokens.body(15).copyWith(
            color: dark ? DesignTokens.nightText : SpeakColors.navy,
            height: 1.3,
          ),
        ),
      ),
    );

    return SizedBox(
      width: double.infinity,
      child: Row(
        mainAxisSize: MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: isUser
            ? [
                Flexible(
                  fit: FlexFit.loose,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.sizeOf(context).width * 0.82,
                      ),
                      child: bubble,
                    ),
                  ),
                ),
                const SizedBox(width: avatarGap),
                _avatar(accent, 'Y'),
              ]
            : [
                _avatar(accent, tutorName.isEmpty ? 'T' : tutorName[0]),
                const SizedBox(width: avatarGap),
                Expanded(child: bubble),
              ],
      ),
    );
  }

  /// Live input transcription can arrive with line breaks or repeated spaces
  /// from the streaming provider. Keep the learner bubble to one natural
  /// line-height of spacing instead of showing those invisible empty lines.
  String _compactUserTranscript(String text) {
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  Widget _avatar(Color accent, String initial) {
    return Container(
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Text(
        initial,
        style: DesignTokens.label(10).copyWith(color: accent),
      ),
    );
  }

  /// Keeps the transcript easy to scan when the tutor switches languages.
  /// Existing quoted text is left alone; unquoted French words are marked so a
  /// learner can select the exact French item they want to look up.
  String _quoteFrenchTerms(String text) {
    final wordPattern = RegExp(r"[A-Za-zÀ-ÿŒœÆæ]+(?:['’][A-Za-zÀ-ÿŒœÆæ]+)?");
    final output = StringBuffer();
    var cursor = 0;
    var insideQuotes = false;
    for (final match in wordPattern.allMatches(text)) {
      final before = text.substring(cursor, match.start);
      output.write(before);
      if (before.contains('"')) {
        if ('"'.allMatches(before).length.isOdd) {
          insideQuotes = !insideQuotes;
        }
      }
      final word = match.group(0)!;
      if (!insideQuotes && _looksFrench(word)) {
        output.write('"$word"');
      } else {
        output.write(word);
      }
      cursor = match.end;
    }
    output.write(text.substring(cursor));

    // Adjacent marked words are one lookup phrase: "l'heure" "de"
    // "départ" becomes "l'heure de départ".
    return output.toString().replaceAll('" "', ' ');
  }

  bool _looksFrench(String word) {
    final lower = word.toLowerCase();
    if (RegExp(r'[àâäçéèêëîïôöùûüÿœæ]').hasMatch(lower)) return true;
    return const {
      'à',
      'au',
      'aux',
      'avec',
      'ce',
      'cette',
      'dans',
      'de',
      'des',
      'du',
      'elle',
      'en',
      'est',
      'et',
      'gare',
      'heure',
      'il',
      'j',
      'je',
      'la',
      'le',
      'les',
      'l',
      "l'heure",
      'marche',
      'parfait',
      'pour',
      'que',
      'qui',
      'sur',
      'tu',
      'un',
      'une',
      'vous',
      'voie',
      'ça',
    }.contains(lower);
  }
}
