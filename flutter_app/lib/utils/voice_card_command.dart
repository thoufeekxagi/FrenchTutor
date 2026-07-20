/// Voice control for the agent-led stages does exactly ONE thing: advance to
/// the next card. Nothing else is voice-controlled — going back, repeating,
/// and ending the lesson are deliberately button-only, so there is exactly
/// one phrase per screen to get right instead of a growing list of commands
/// that could collide with lesson content.
///
/// [transcript] matches [nextPhrase] if it's near-exact (~90% similarity by
/// edit distance) — tolerant of STT noise ("necks word" for "next word"),
/// never of unrelated phrasing.
bool matchesAdvanceCommand(String transcript, {required String nextPhrase}) {
  final normalized = _normalize(transcript);
  final phrase = _normalize(nextPhrase);
  if (normalized.isEmpty || phrase.isEmpty) return false;
  if (normalized == phrase) return true;
  return _similarity(normalized, phrase) >= 0.9;
}

/// 1.0 = identical, 0.0 = completely different, by normalized edit distance.
double _similarity(String a, String b) {
  if (a == b) return 1.0;
  final maxLen = a.length > b.length ? a.length : b.length;
  if (maxLen == 0) return 1.0;
  return 1 - (_levenshtein(a, b) / maxLen);
}

int _levenshtein(String a, String b) {
  final la = a.length;
  final lb = b.length;
  if (la == 0) return lb;
  if (lb == 0) return la;
  var previous = List<int>.generate(lb + 1, (j) => j);
  var current = List<int>.filled(lb + 1, 0);
  for (var i = 1; i <= la; i++) {
    current[0] = i;
    for (var j = 1; j <= lb; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      current[j] = [
        previous[j] + 1, // deletion
        current[j - 1] + 1, // insertion
        previous[j - 1] + cost, // substitution
      ].reduce((x, y) => x < y ? x : y);
    }
    final tmp = previous;
    previous = current;
    current = tmp;
  }
  return previous[lb];
}

String _normalize(String value) {
  const accents = {
    'à': 'a',
    'â': 'a',
    'ç': 'c',
    'é': 'e',
    'è': 'e',
    'ê': 'e',
    'ë': 'e',
    'î': 'i',
    'ï': 'i',
    'ô': 'o',
    'ö': 'o',
    'ù': 'u',
    'û': 'u',
    'ü': 'u',
  };
  final buffer = StringBuffer();
  for (final rune in value.toLowerCase().runes) {
    final char = String.fromCharCode(rune);
    if (accents.containsKey(char)) {
      buffer.write(accents[char]);
    } else if ((rune >= 97 && rune <= 122) || rune == 32) {
      buffer.write(char);
    } else {
      buffer.write(' ');
    }
  }
  return buffer.toString().trim().replaceAll(RegExp(r'\s+'), ' ');
}
