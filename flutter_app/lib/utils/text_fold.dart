/// Diacritic-insensitive, lowercased fold — Dart has no built-in equivalent to Swift's
/// `String.folding(options: .diacriticInsensitive, locale:)`, so this is a manual accent
/// map covering French. Used by the gate systems (vocab/grammar/listening) to match spoken
/// intent keywords and target words regardless of accents.
const Map<String, String> frenchDiacriticMap = {
  'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
  'à': 'a', 'â': 'a', 'ä': 'a',
  'ç': 'c',
  'î': 'i', 'ï': 'i',
  'ô': 'o', 'ö': 'o',
  'û': 'u', 'ù': 'u', 'ü': 'u',
  'œ': 'oe', 'æ': 'ae',
  'ñ': 'n',
};

String foldFrench(String text) {
  var result = text.toLowerCase().trim();
  frenchDiacriticMap.forEach((accented, plain) {
    result = result.replaceAll(accented, plain);
  });
  return result;
}

/// Deterministic echo detector for the live-session gates: on speaker (no headphones) the
/// mic can pick up the tutor's own voice, which comes back transcribed as if the STUDENT
/// said it — and if she just said "ready for the next word?", that phantom utterance would
/// advance the card without any consent. The LLM judge is told about echoes but measurably
/// still misses this case, so the app checks it directly: an utterance of 3+ words where
/// nearly every word appears in the tutor's last line is her voice, not the student's.
/// Short replies ("yes", "next word") stay under the length floor, so genuine answers to
/// her questions are never suppressed.
bool looksLikeTutorEcho(String utterance, String tutorLastLine) {
  if (tutorLastLine.isEmpty) return false;
  final utteranceWords = foldFrench(utterance)
      .replaceAll(RegExp(r'[.!?,;:—-]'), ' ')
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (utteranceWords.length < 3) return false;
  final tutorWords = foldFrench(tutorLastLine)
      .replaceAll(RegExp(r'[.!?,;:—-]'), ' ')
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toSet();
  final overlap = utteranceWords.where(tutorWords.contains).length;
  return overlap / utteranceWords.length >= 0.8;
}
