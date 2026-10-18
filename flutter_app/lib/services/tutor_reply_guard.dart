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

  static const _otherLanguageWords = {
    // Spanish
    'los', 'las', 'muy', 'pero', 'está', 'estoy', 'gracias', 'hola', 'buenos',
    'buenas', 'qué', 'cómo', 'dónde', 'usted', 'también', 'porque', 'entiendo',
    'puedo', 'ayudar', 'necesito', 'quiero', 'tengo', 'hablo', 'español',
    'hasta', 'luego', 'adiós', 'señor', 'señora', 'perdón', 'claro', 'vale',
    'por', 'favor', 'días', 'tardes', 'noches', 'eso', 'esto', 'sí',
    // Italian
    'sono', 'grazie', 'ciao', 'buongiorno', 'buonasera', 'prego', 'molto',
    'anche', 'stai', 'sto', 'capisco', 'posso', 'aiutare', 'voglio', 'questo',
    'questa', 'perché', 'italiano', 'parlo', 'scusa', 'hai', 'della', 'degli',
    'nel', 'sul', 'gli', 'cosa', 'dove', 'quando', 'sei', 'siamo', 'dimmi',
    // German
    'ich', 'nicht', 'das', 'ist', 'und', 'ein', 'eine', 'der', 'danke',
    'bitte', 'wieder', 'ja', 'nein', 'hallo', 'guten', 'wie', 'geht',
    'verstehe', 'sprechen', 'deutsch', 'aber', 'auch', 'mit', 'für', 'noch',
    // Portuguese
    'não', 'você', 'obrigado', 'obrigada', 'olá', 'sim', 'muito', 'tudo',
    'entendo', 'ajudar', 'estou', 'português', 'falo', 'desculpe',
    // Dutch
    'niet', 'ik', 'jij', 'het', 'goed', 'nee', 'alstublieft', 'begrijp',
    'dank', 'een',
  };

  static final _enFrWords = {
    ..._fillers,
    'the',
    'is',
    'are',
    'was',
    'be',
    'to',
    'of',
    'in',
    'it',
    'for',
    'on',
    'with',
    'as',
    'this',
    'that',
    'what',
    'how',
    'why',
    'when',
    'where',
    'who',
    'can',
    'could',
    'do',
    'does',
    'did',
    'say',
    'means',
    'mean',
    'word',
    'french',
    'english',
    'me',
    'my',
    'we',
    'he',
    'she',
    'they',
    'your',
    'and',
    'or',
    'not',
    'have',
    'has',
    'will',
    'would',
    'please',
    'hello',
    'bonjour',
    'bonsoir',
    'salut',
    'je',
    'tu',
    'il',
    'elle',
    'nous',
    'vous',
    'ils',
    'est',
    'sont',
    'le',
    'la',
    'les',
    'un',
    'une',
    'des',
    'du',
    'de',
    'et',
    'ou',
    'pas',
    'ne',
    'que',
    'qui',
    'quoi',
    'comment',
    'pourquoi',
    'dans',
    'pour',
    'avec',
    'sur',
    'ce',
    'cette',
    'ces',
    'mon',
    'ma',
    'mes',
    'ton',
    'ta',
    'tes',
    'au',
    'aux',
    'en',
    'y',
    'à',
    'ça',
    'oui',
    'non',
    'très',
    'bien',
    'mais',
    'si',
    'dis',
    'dit',
    'peux',
    'peut',
    'veux',
    'veut',
    'fait',
    'faire',
    'être',
    'avoir',
    'sorry',
    'excuse',
    'pardon',
    'one',
    'two',
    'three',
    'good',
    'morning',
    'evening',
    'night',
    'bonne',
    'nuit',
    'journée',
    'toilettes',
    'où',
  };

  /// True when [text] is clearly Spanish, Italian, German, Portuguese or
  /// Dutch rather than English or French. The tutor only works in English
  /// and French, and a short transcript in another language is almost always
  /// room noise misheard as speech.
  static bool isOtherLatinLanguage(String text) {
    final words = text
        .toLowerCase()
        .replaceAll(RegExp(r"[^a-zà-ÿ\s]"), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return false;
    var other = 0;
    var known = 0;
    for (final w in words) {
      if (_otherLanguageWords.contains(w) && !_enFrWords.contains(w)) {
        other++;
      } else if (_enFrWords.contains(w)) {
        known++;
      }
    }
    if (other == 0) return false;
    if (words.length <= 3) return known == 0;
    return other >= 2 && other > known;
  }

  /// True when [text] is not English or French.
  static bool isUnsupportedLanguage(String text) =>
      hasUnsupportedScript(text) || isOtherLatinLanguage(text);

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
