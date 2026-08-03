import '../models/tutor_persona.dart';
import '../services/lesson_speech_service.dart';

/// The French alphabet, letter by letter — deliberately STATIC, hand-written
/// content rather than AI-generated: unlike a story or a grammar point, the
/// alphabet doesn't vary by learner or need personalization, and accuracy
/// matters more here than anywhere else in the app (a wrong phonetic hint
/// would teach a genuinely wrong pronunciation). One-time content, meant to
/// be learned in a single sitting (~40-50 minutes) — see AlphabetLabScreen.
class AlphabetLetter {
  const AlphabetLetter({
    required this.letter,
    required this.phonetic,
    required this.note,
    required this.exampleWord,
    required this.exampleMeaning,
    this.confusable,
  });

  final String letter;

  /// How the LETTER'S NAME is said aloud in French (not a word containing
  /// it) — a plain romanized approximation, e.g. "zheh", not IPA.
  final String phonetic;

  /// One plain-English sentence on how to say it / what to watch for.
  final String note;

  final String exampleWord;
  final String exampleMeaning;

  /// The other letter English speakers most often confuse this one with
  /// (e.g. E <-> I, G <-> J) — null if this letter isn't commonly confused.
  final String? confusable;

  bool get isTricky => confusable != null;
}

const List<AlphabetLetter> frenchAlphabet = [
  AlphabetLetter(
    letter: 'A',
    phonetic: 'ah',
    note: 'Like "a" in "father". This one is not confusing.',
    exampleWord: 'ami',
    exampleMeaning: 'friend',
  ),
  AlphabetLetter(
    letter: 'B',
    phonetic: 'beh',
    note: 'Like the English word "bay".',
    exampleWord: 'bonjour',
    exampleMeaning: 'hello',
  ),
  AlphabetLetter(
    letter: 'C',
    phonetic: 'seh',
    note: 'Like the English word "say".',
    exampleWord: 'chat',
    exampleMeaning: 'cat',
  ),
  AlphabetLetter(
    letter: 'D',
    phonetic: 'deh',
    note: 'Like the English word "day".',
    exampleWord: 'demain',
    exampleMeaning: 'tomorrow',
  ),
  AlphabetLetter(
    letter: 'E',
    phonetic: 'euh',
    note:
        'A soft "uh" sound, NOT like the English letter "e" (which sounds like "ee"). '
        'This is the opposite of what an English speaker expects.',
    exampleWord: 'le',
    exampleMeaning: 'the',
    confusable: 'I',
  ),
  AlphabetLetter(
    letter: 'F',
    phonetic: 'eff',
    note: 'Same as the English letter name.',
    exampleWord: 'fromage',
    exampleMeaning: 'cheese',
  ),
  AlphabetLetter(
    letter: 'G',
    phonetic: 'zheh',
    note:
        'NOT like the English "gee" (hard G). It\'s soft, like the "s" in "measure" '
        'or "zh", close to "zhay". English speakers almost always guess this wrong at first.',
    exampleWord: 'garçon',
    exampleMeaning: 'boy',
    confusable: 'J',
  ),
  AlphabetLetter(
    letter: 'H',
    phonetic: 'ahsh',
    note:
        'Like the English word "ash". The letter itself is always silent in French words.',
    exampleWord: 'hôtel',
    exampleMeaning: 'hotel',
  ),
  AlphabetLetter(
    letter: 'I',
    phonetic: 'ee',
    note:
        'Like the English "ee" in "see", NOT like the English letter name "eye". '
        'This is the opposite of what an English speaker expects.',
    exampleWord: 'ici',
    exampleMeaning: 'here',
    confusable: 'E',
  ),
  AlphabetLetter(
    letter: 'J',
    phonetic: 'zhee',
    note:
        'NOT like the English "jay". It\'s soft, closer to "zhee", the same soft '
        '"zh" sound as G, just with an "ee" ending instead of "eh".',
    exampleWord: 'jour',
    exampleMeaning: 'day',
    confusable: 'G',
  ),
  AlphabetLetter(
    letter: 'K',
    phonetic: 'kah',
    note: 'Like the English word "ka".',
    exampleWord: 'kilo',
    exampleMeaning: 'kilo',
  ),
  AlphabetLetter(
    letter: 'L',
    phonetic: 'ell',
    note: 'Same as the English letter name.',
    exampleWord: 'livre',
    exampleMeaning: 'book',
  ),
  AlphabetLetter(
    letter: 'M',
    phonetic: 'emm',
    note: 'Same as the English letter name.',
    exampleWord: 'maison',
    exampleMeaning: 'house',
  ),
  AlphabetLetter(
    letter: 'N',
    phonetic: 'enn',
    note: 'Same as the English letter name.',
    exampleWord: 'nuit',
    exampleMeaning: 'night',
  ),
  AlphabetLetter(
    letter: 'O',
    phonetic: 'oh',
    note: 'Same as the English letter name.',
    exampleWord: 'orange',
    exampleMeaning: 'orange',
  ),
  AlphabetLetter(
    letter: 'P',
    phonetic: 'peh',
    note: 'Like the English word "pay".',
    exampleWord: 'pain',
    exampleMeaning: 'bread',
  ),
  AlphabetLetter(
    letter: 'Q',
    phonetic: 'kew',
    note: 'Like the English word "coo" with a hard K.',
    exampleWord: 'quatre',
    exampleMeaning: 'four',
  ),
  AlphabetLetter(
    letter: 'R',
    phonetic: 'air (throaty)',
    note:
        'The trickiest sound in French, made in the back of the throat, not with the '
        'tip of the tongue like in English. It takes practice, so don\'t worry about getting it perfect yet.',
    exampleWord: 'rouge',
    exampleMeaning: 'red',
  ),
  AlphabetLetter(
    letter: 'S',
    phonetic: 'ess',
    note: 'Same as the English letter name.',
    exampleWord: 'soleil',
    exampleMeaning: 'sun',
  ),
  AlphabetLetter(
    letter: 'T',
    phonetic: 'teh',
    note: 'Like the English word "tay".',
    exampleWord: 'table',
    exampleMeaning: 'table',
  ),
  AlphabetLetter(
    letter: 'U',
    phonetic: 'ew (rounded lips)',
    note:
        'A sound that doesn\'t exist in English. Round your lips like saying "oo" but '
        'try to say "ee". It takes practice; just notice it\'s different from "ou".',
    exampleWord: 'tu',
    exampleMeaning: 'you (informal)',
  ),
  AlphabetLetter(
    letter: 'V',
    phonetic: 'veh',
    note: 'Like the English word "vay".',
    exampleWord: 'ville',
    exampleMeaning: 'city',
  ),
  AlphabetLetter(
    letter: 'W',
    phonetic: 'doo-bluh-veh',
    note: 'Literally "double V". French treats W as two V\'s stuck together.',
    exampleWord: 'wagon',
    exampleMeaning: 'train car',
  ),
  AlphabetLetter(
    letter: 'X',
    phonetic: 'eeks',
    note: 'Same as the English letter name.',
    exampleWord: 'taxi',
    exampleMeaning: 'taxi',
  ),
  AlphabetLetter(
    letter: 'Y',
    phonetic: 'ee-grek',
    note:
        'Literally "Greek i". Its French name is a whole little phrase, not one syllable.',
    exampleWord: 'yaourt',
    exampleMeaning: 'yogurt',
  ),
  AlphabetLetter(
    letter: 'Z',
    phonetic: 'zed',
    note: 'Same as the British English letter name (not American "zee").',
    exampleWord: 'zéro',
    exampleMeaning: 'zero',
  ),
];

/// The letters worth a quick review quiz — only the genuinely confusable
/// ones, not all 26 (a beginner doesn't need to be tested on "same as
/// English" letters like B/D/F/L/M/N/O/S/X).
List<AlphabetLetter> get trickyAlphabetLetters => frenchAlphabet
    .where((l) => l.isTricky || l.letter == 'U' || l.letter == 'R')
    .toList();

/// The 6 vowels, split out as their own short lesson — French vowel sounds
/// (E, I, U especially) are where English speakers get the most backwards,
/// so a beginner benefits from drilling just these before wading through
/// all 26 letters at once.
List<AlphabetLetter> get vowelLetters =>
    frenchAlphabet.where((l) => 'AEIOUY'.contains(l.letter)).toList();

/// The 20 consonants, as their own lesson.
List<AlphabetLetter> get consonantLetters =>
    frenchAlphabet.where((l) => !'AEIOUY'.contains(l.letter)).toList();

/// Accent marks aren't separate letters, but a total-beginner reading their
/// first French word needs to know they exist and what each one does —
/// otherwise "é" just looks like a typo of "e". Static content for the same
/// reason as [frenchAlphabet]: accuracy over personalization.
const List<AlphabetLetter> frenchAccents = [
  AlphabetLetter(
    letter: 'É',
    phonetic: 'accent aigu',
    note:
        'Makes an "e" sound like "ay", never the soft "uh" of a plain "e". '
        'Only ever appears on top of e.',
    exampleWord: 'été',
    exampleMeaning: 'summer',
  ),
  AlphabetLetter(
    letter: 'È',
    phonetic: 'accent grave',
    note:
        'Opens the "e" sound, like "eh" in "bet". On a, u, or i it usually '
        'doesn\'t change the sound at all, it just tells two similar-looking '
        'words apart (e.g. "ou" meaning "or" versus "où" meaning "where").',
    exampleWord: 'père',
    exampleMeaning: 'father',
  ),
  AlphabetLetter(
    letter: 'Ê',
    phonetic: 'accent circonflexe',
    note:
        'Sounds the same as è, an open "eh". Often marks a letter (usually '
        '"s") that used to sit right after it centuries ago and was later '
        'dropped, which is why "forêt" looks like the English "forest".',
    exampleWord: 'forêt',
    exampleMeaning: 'forest',
  ),
  AlphabetLetter(
    letter: 'Ç',
    phonetic: 'cédille',
    note:
        'Only ever sits under a C. Forces that C to sound soft, like "s", '
        'right before a, o, or u, where a plain C there would sound hard, '
        'like "k".',
    exampleWord: 'garçon',
    exampleMeaning: 'boy',
  ),
  AlphabetLetter(
    letter: 'Ë',
    phonetic: 'tréma',
    note:
        'Also written ï. Says "read this vowel on its own, don\'t blend it '
        'with the vowel right before it." Without it, "Noël" would blend '
        'into one sound instead of "no-el".',
    exampleWord: 'Noël',
    exampleMeaning: 'Christmas',
  ),
];

/// Text used to create the shipped clip. These are French letter names, not
/// the English-looking one-character strings that made Gemini sometimes say
/// "Q" as the English name "cue". The generation prompt also explicitly
/// requires French, but keeping this mapping here makes the intended source
/// pronunciation auditable and stable.
const _alphabetAudioSlugs = {
  'É': 'e_acute',
  'È': 'e_grave',
  'Ê': 'e_circumflex',
  'Ç': 'c_cedilla',
  'Ë': 'e_diaeresis',
};

const _frenchSpokenNames = {
  'A': 'a',
  'B': 'bé',
  'C': 'cé',
  'D': 'dé',
  'E': 'e',
  'F': 'effe',
  'G': 'gé',
  'H': 'ache',
  'I': 'i',
  'J': 'ji',
  'K': 'ka',
  'L': 'elle',
  'M': 'emme',
  'N': 'enne',
  'O': 'o',
  'P': 'pé',
  'Q': 'ku',
  'R': 'ère',
  'S': 'esse',
  'T': 'té',
  'U': 'u',
  'V': 'vé',
  'W': 'double vé',
  'X': 'ixe',
  'Y': 'i grec',
  'Z': 'zède',
  'É': 'accent aigu',
  'È': 'accent grave',
  'Ê': 'accent circonflexe',
  'Ç': 'cédille',
  'Ë': 'tréma',
};

String alphabetSpokenText(AlphabetLetter letter) =>
    _frenchSpokenNames[letter.letter] ?? letter.letter;

/// The cache id every screen must use for a given letter/accent's spoken
/// name, so the same sound is never synthesized under two different keys —
/// shared by [AlphabetLabScreen]'s own decks and [alphabetPrewarmItems]
/// below.
String alphabetAudioId(AlphabetLetter letter) => frenchAccents.contains(letter)
    ? 'alphabet_accent_${_alphabetAudioSlugs[letter.letter] ?? letter.letter}'
    : 'alphabet_letter_${letter.letter}';

String alphabetAudioAssetPath(AlphabetLetter letter, TutorPersona persona) =>
    'assets/audio/alphabet/${persona.id}/${alphabetAudioId(letter)}.pcm';

/// Every distinct sound the "Learn the Alphabet" decks ever play (all 26
/// letters plus the 5 accent marks — Consonants/Vowels are just subsets of
/// the same 26, so nothing extra is needed for them). Every one of the four
/// tutor voices is included so changing tutors never triggers live generation.
List<SpeechItem> alphabetPrewarmItems() => [
  for (final persona in TutorPersona.all)
    for (final letter in [...frenchAlphabet, ...frenchAccents])
      SpeechItem(
        text: alphabetSpokenText(letter),
        language: 'fr-FR',
        contentItemId: alphabetAudioId(letter),
        voiceName: persona.voiceName,
        assetPath: alphabetAudioAssetPath(letter, persona),
      ),
];
