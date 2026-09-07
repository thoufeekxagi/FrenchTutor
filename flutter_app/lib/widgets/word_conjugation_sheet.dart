import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../design/tokens.dart';

/// Opens the shared conjugation bottom sheet for one tapped word. Used
/// identically by Reading/Course (story_reader_screen.dart) and Listening
/// (listening_practice_screen.dart) — the same "Conjugate" action from the
/// word-meaning panel always looks and behaves the same.
Future<void> showWordConjugationSheet(
  BuildContext context, {
  required bool darkMode,
  required String word,
  required String translation,
  required Future<Map<String, dynamic>> future,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => WordConjugationSheet(
      darkMode: darkMode,
      word: word,
      translation: translation,
      future: future,
    ),
  );
}

class WordConjugationSheet extends StatelessWidget {
  const WordConjugationSheet({
    super.key,
    required this.future,
    required this.darkMode,
    required this.word,
    required this.translation,
  });

  final Future<Map<String, dynamic>> future;
  final bool darkMode;
  final String word;
  final String translation;

  @override
  Widget build(BuildContext context) {
    final surface = darkMode ? DesignTokens.nightSurfaceRaised : Colors.white;
    final text = darkMode ? DesignTokens.nightText : DesignTokens.ink;
    final muted = darkMode ? DesignTokens.nightMuted : DesignTokens.mutedDim;
    final accent = darkMode ? DesignTokens.nightAccent : DesignTokens.primary;
    return SafeArea(
      child: Container(
        constraints: const BoxConstraints(maxHeight: 620),
        margin: const EdgeInsets.all(10),
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(30),
        ),
        child: FutureBuilder<Map<String, dynamic>>(
          future: future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const SizedBox(
                height: 240,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.hasError || snapshot.data == null) {
              return SizedBox(
                height: 220,
                child: Center(
                  child: Text(
                    'The conjugation is unavailable right now. Try again in a moment.',
                    textAlign: TextAlign.center,
                    style: DesignTokens.body(15).copyWith(color: muted),
                  ),
                ),
              );
            }
            final data = snapshot.data!;
            final conjugation = (data['conjugation'] as List? ?? const [])
                .whereType<Map>()
                .toList();
            final metadata = [
              data['part_of_speech']?.toString() ?? '',
              data['gender']?.toString() ?? '',
              data['number']?.toString() ?? '',
              data['tense']?.toString() ?? '',
            ].where((value) => value.trim().isNotEmpty).join(' · ');
            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 38,
                      height: 4,
                      decoration: BoxDecoration(
                        color: muted.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          data['title']?.toString().trim().isNotEmpty == true
                              ? data['title'].toString()
                              : word,
                          style: DesignTokens.display(24).copyWith(color: text),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: Icon(CupertinoIcons.xmark, color: muted),
                      ),
                    ],
                  ),
                  Text(
                    translation,
                    style: DesignTokens.body(15).copyWith(color: muted),
                  ),
                  if (metadata.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      metadata,
                      style: DesignTokens.mono(11).copyWith(color: accent),
                    ),
                  ],
                  if ((data['summary']?.toString() ?? '').isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text(
                      data['summary'].toString(),
                      style: DesignTokens.body(
                        14,
                      ).copyWith(color: text, height: 1.4),
                    ),
                  ],
                  if (conjugation.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    Text(
                      'CONJUGATION',
                      style: DesignTokens.mono(
                        10.5,
                        weight: FontWeight.w800,
                      ).copyWith(color: accent, letterSpacing: 0.8),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: muted.withValues(alpha: 0.4)),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          for (var i = 0; i < conjugation.length; i++)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: i.isEven
                                    ? muted.withValues(alpha: 0.06)
                                    : Colors.transparent,
                                border: i == conjugation.length - 1
                                    ? null
                                    : Border(
                                        bottom: BorderSide(
                                          color: muted.withValues(alpha: 0.2),
                                        ),
                                      ),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      conjugation[i]['pronoun']?.toString() ??
                                          '',
                                      style: DesignTokens.body(
                                        14,
                                      ).copyWith(color: muted),
                                    ),
                                  ),
                                  Text(
                                    conjugation[i]['form']?.toString() ?? '',
                                    style: DesignTokens.body(
                                      14,
                                      weight: FontWeight.w700,
                                    ).copyWith(color: text),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
