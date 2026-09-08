/// Small, deterministic helpers for keeping a story's visible word in step
/// with Gemini Live's incremental output transcription.
///
/// Live transcription is not guaranteed to arrive as one complete word per
/// event. A provider can send a partial token (`"mar"`), replace it with a
/// longer token (`"marché"`), or send a cumulative transcript instead of a
/// delta. Keeping those details here means the reader can treat the stream as
/// one monotonically growing sentence and never advance because of a partial
/// prefix.
abstract final class NarrationAlignment {
  /// Merges either a delta or a cumulative transcription update into [current].
  /// The overlap pass removes repeated partial tokens without removing real
  /// repeated words in the sentence.
  static String appendTranscriptDelta(String current, String delta) {
    if (delta.isEmpty) return current;
    if (current.isEmpty) return delta;

    // Some Live transports occasionally resend the whole accumulated value.
    if (delta.startsWith(current)) return delta;
    if (current.endsWith(delta)) return current;

    final maxOverlap = current.length < delta.length
        ? current.length
        : delta.length;
    for (var length = maxOverlap; length > 0; length--) {
      if (current.substring(current.length - length) ==
          delta.substring(0, length)) {
        return current + delta.substring(length);
      }
    }
    return current + delta;
  }

  /// Returns the source word currently being spoken, or null until the
  /// transcript has a usable prefix of [sentence]. The comparison is made on
  /// a punctuation-free character stream rather than raw whitespace tokens.
  /// That handles French elisions (`l'information` vs `l information`),
  /// apostrophe variants, and punctuation without shifting every later word.
  static int? currentWordIndex(String sentence, String transcript) {
    final expected = words(sentence);
    final actual = words(transcript);
    if (expected.isEmpty || actual.isEmpty) return null;

    final expectedCanonical = expected.map(_canonical).join();
    final actualCanonical = actual.map(_canonical).join();
    if (expectedCanonical.isEmpty || actualCanonical.isEmpty) return null;

    var common = 0;
    final limit = expectedCanonical.length < actualCanonical.length
        ? expectedCanonical.length
        : actualCanonical.length;
    while (common < limit &&
        expectedCanonical.codeUnitAt(common) ==
            actualCanonical.codeUnitAt(common)) {
      common++;
    }
    if (common == 0) return null;

    var cumulative = 0;
    for (var index = 0; index < expected.length; index++) {
      cumulative += _canonical(expected[index]).length;
      // A fully heard word remains highlighted until the next word has
      // actually appeared in the Live transcript. This avoids a one-frame
      // flash on the following word while the server is closing the token.
      if (common <= cumulative) return index;
    }
    return expected.length - 1;
  }

  /// Deliberately mirrors the tokenization used by [BilingualWordText], so a
  /// returned index always addresses the same rendered word.
  static List<String> words(String text) => text
      .split(RegExp(r'\s+'))
      .where((word) => word.trim().isNotEmpty)
      .toList(growable: false);

  static String _canonical(String value) => value
      .toLowerCase()
      .replaceAll('œ', 'oe')
      .replaceAll('æ', 'ae')
      .replaceAll('à', 'a')
      .replaceAll('â', 'a')
      .replaceAll('ä', 'a')
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('è', 'e')
      .replaceAll('ê', 'e')
      .replaceAll('ë', 'e')
      .replaceAll('î', 'i')
      .replaceAll('ï', 'i')
      .replaceAll('í', 'i')
      .replaceAll('ô', 'o')
      .replaceAll('ö', 'o')
      .replaceAll('ó', 'o')
      .replaceAll('ù', 'u')
      .replaceAll('û', 'u')
      .replaceAll('ü', 'u')
      .replaceAll('ú', 'u')
      .replaceAll('ç', 'c')
      .replaceAll('’', "'")
      .replaceAll(RegExp(r'[^a-z0-9]+'), '');
}
