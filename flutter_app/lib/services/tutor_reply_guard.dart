/// Deterministic guard for the voice tutor. The Live model answers any speech
/// it hears, so the app drops replies that a good human tutor would not give.
class TutorReplyGuard {
  const TutorReplyGuard._();

  static const _fillers = {
    'hmm',
    'hm',
    'mm',
    'mhm',
    'ham',
    'hum',
    'uh',
    'um',
    'er',
    'ah',
    'oh',
    'euh',
    'ben',
    'bon',
    'okay',
    'ok',
    'alright',
    'right',
    'sure',
    'yes',
    'yeah',
    'yep',
    'yup',
    'oui',
    'merci',
    'thanks',
    'thank',
    'you',
    'cool',
    'good',
    'great',
    'nice',
    'got',
    'it',
    'i',
    'see',
    'understood',
    'perfect',
    'super',
    'dac',
    'accord',
    'd',
    'thats',
    'that',
    's',
    'all',
    'well',
    'so',
    'then',
    'the',
    'a',
    'marie',
    'camille',
    'julien',
    'mathieu',
    'murray',
    'bye',
    'goodbye',
    'later',
  };

  /// True when [text] contains letters outside the Latin script (Malayalam,
  /// Arabic, Cyrillic, CJK, ...). The tutor only teaches English and French,
  /// so a transcript in another script is noise misheard as speech.
  static bool hasUnsupportedScript(String text) {
    for (final rune in text.runes) {
      if (rune > 0x024F &&
          !(rune >= 0x2000 && rune <= 0x2BFF) &&
          !(rune >= 0x1E00 && rune <= 0x1EFF) &&
          !(rune >= 0xFE00 && rune <= 0xFE0F) &&
          rune < 0x1F000) {
        return true;
      }
    }
    return false;
  }

  /// True when the learner's turn is only a filler, acknowledgement or thanks.
  static bool isFillerTurn(String learnerTranscript) {
    final words = learnerTranscript
        .toLowerCase()
        .replaceAll(RegExp(r"[^a-zà-ÿ\s']"), ' ')
        .replaceAll("'", ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty || words.length > 7) return false;
    return words.every(_fillers.contains);
  }

  static final _chatter = RegExp(
    r"(let me know if|is there anything|anything else|how can i help|"
    r"what else can i|feel free to ask|do you have any other|"
    r"would you like to (learn|practi[cs]e|try)|"
    r"comment puis-je|y a-t-il autre chose|autre chose que|"
    r"n'hésitez pas|si vous avez (d'autres|besoin)|have a (great|wonderful|nice) day)",
    caseSensitive: false,
  );

  /// Index in [tutorTranscript] where a generic chatbot offer starts, or -1.
  static int chatterStart(String tutorTranscript) =>
      _chatter.firstMatch(tutorTranscript)?.start ?? -1;
}
