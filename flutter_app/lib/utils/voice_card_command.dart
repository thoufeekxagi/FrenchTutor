enum VoiceCardCommand { next, previous, repeat, finish }

VoiceCardCommand? exactVoiceCardCommand(String transcript) {
  final normalized = _normalize(transcript);
  return switch (normalized) {
    'next card' ||
    'proceed to next card' ||
    'carte suivante' => VoiceCardCommand.next,
    'previous card' ||
    'go back one card' ||
    'carte precedente' => VoiceCardCommand.previous,
    'repeat card' ||
    'repeat that' ||
    'repete la carte' => VoiceCardCommand.repeat,
    'end lesson' ||
    'finish lesson' ||
    'terminer la lecon' => VoiceCardCommand.finish,
    _ => null,
  };
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
