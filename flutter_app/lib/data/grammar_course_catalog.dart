import '../models/grammar_course.dart';
import '../models/grammar_course_v2.dart';

GrammarCourseStep _guided(
  String label,
  String prompt,
  String promptEnglish,
  String answer,
  String target,
  String tip,
  List<String> choices, {
  List<String> choiceMeanings = const [],
}) => GrammarCourseStep(
  label: label,
  prompt: prompt,
  promptEnglish: promptEnglish,
  target: target,
  answer: answer,
  choices: choices,
  choiceMeanings: choiceMeanings,
  tokens: const [],
  tip: tip,
);

GrammarCourseStep _complete(
  String label,
  String prompt,
  String promptEnglish,
  String target,
  String tip,
) => GrammarCourseStep(
  label: label,
  prompt: prompt,
  promptEnglish: promptEnglish,
  target: target,
  answer: target,
  choices: const [],
  tokens: _tokens(target),
  tip: tip,
);

GrammarCourseStep _roleplay(
  String label,
  String partnerFrench,
  String partnerEnglish,
  String prompt,
  String promptEnglish,
  String answer,
  String tip,
  List<String> choices, {
  List<String> choiceMeanings = const [],
}) => GrammarCourseStep(
  label: label,
  prompt: prompt,
  promptEnglish: promptEnglish,
  target: answer,
  answer: answer,
  choices: choices,
  choiceMeanings: choiceMeanings,
  tokens: const [],
  tip: tip,
  partnerFrench: partnerFrench,
  partnerEnglish: partnerEnglish,
);

List<String> _tokens(String sentence) => sentence
    .replaceAllMapped(RegExp(r'([,.!?;:])'), (match) => ' ${match.group(1)}')
    .split(RegExp(r'\s+'))
    .where((token) => token.isNotEmpty)
    .toList(growable: false);

GrammarCourseSession _session(
  String id,
  String title,
  String subtitle,
  String focus,
  String icon,
  GrammarV2Mode mode,
  List<GrammarCourseStep> steps,
) => GrammarCourseSession(
  id: id,
  title: title,
  subtitle: subtitle,
  level: 'A1',
  tense: GrammarV2Tenses.present,
  grammarFocus: focus,
  iconKey: icon,
  mode: mode,
  steps: steps,
  goal: 'Use the present tense naturally in one connected situation.',
);

/// The first reserve is intentionally small and authored: three coherent
/// sessions per mode, not a flat stream of sentence cards. Generated sessions
/// use this exact shape and replace/extend it after validation.
final grammarCourseStarterSessions = <GrammarCourseSession>[
  _session(
    'grammar_present_guided_morning',
    'My morning rhythm',
    'Talk through a simple morning using present-tense verbs.',
    'Present-tense everyday verbs',
    'sun',
    GrammarV2Mode.guided,
    [
      _guided(
        'Start the day',
        'Je ___ à sept heures.',
        'I get up at seven.',
        'me lève',
        'Je me lève à sept heures.',
        'With je, use the present form me lève.',
        ['me lève', 'me lèves', 'me lever'],
      ),
      _guided(
        'Make a drink',
        'Tu ___ un café le matin.',
        'You drink a coffee in the morning.',
        'bois',
        'Tu bois un café le matin.',
        'With tu, boire becomes bois.',
        ['bois', 'boit', 'boire'],
      ),
      _guided(
        'Say where he lives',
        'Il ___ à Toronto.',
        'He lives in Toronto.',
        'habite',
        'Il habite à Toronto.',
        'A regular -er verb uses -e with il.',
        ['habite', 'habites', 'habiter'],
      ),
      _guided(
        'Practise together',
        'Nous ___ français ensemble.',
        'We speak French together.',
        'parlons',
        'Nous parlons français ensemble.',
        'With nous, parler becomes parlons.',
        ['parlons', 'parlez', 'parler'],
      ),
      _guided(
        'Arrive at work',
        'Elles ___ au travail.',
        'They arrive at work.',
        'arrivent',
        'Elles arrivent au travail.',
        'With elles, arriver ends in -ent.',
        ['arrivent', 'arrive', 'arriver'],
      ),
    ],
  ),
  _session(
    'grammar_present_guided_cafe',
    'At the café',
    'Order, eat, and pay with present-tense forms.',
    'Present-tense café verbs',
    'coffee',
    GrammarV2Mode.guided,
    [
      _guided(
        'Choose a drink',
        'Je ___ un café.',
        'I am having a coffee.',
        'prends',
        'Je prends un café.',
        'Prendre becomes prends with je.',
        ['prends', 'prend', 'prendre'],
      ),
      _guided(
        'Ask about milk',
        'Vous ___ du lait ?',
        'Do you take milk?',
        'prenez',
        'Vous prenez du lait ?',
        'With vous, prendre becomes prenez.',
        ['prenez', 'prend', 'prendre'],
      ),
      _guided(
        'Eat inside',
        'Nous ___ à l’intérieur.',
        'We eat inside.',
        'mangeons',
        'Nous mangeons à l’intérieur.',
        'With nous, manger becomes mangeons.',
        ['mangeons', 'mange', 'manger'],
      ),
      _guided(
        'Pay by card',
        'On ___ par carte.',
        'We pay by card.',
        'paie',
        'On paie par carte.',
        'On takes the same verb form as il or elle.',
        ['paie', 'paient', 'payer'],
      ),
      _guided(
        'Bring the bill',
        'Le serveur ___ l’addition.',
        'The server brings the bill.',
        'apporte',
        'Le serveur apporte l’addition.',
        'A singular subject uses apporte.',
        ['apporte', 'apportent', 'apporter'],
      ),
    ],
  ),
  _session(
    'grammar_present_guided_city',
    'Around town',
    'Ask, move, and find places around your city.',
    'Present-tense movement verbs',
    'map',
    GrammarV2Mode.guided,
    [
      _guided(
        'Find the station',
        'Je ___ la gare.',
        'I am looking for the station.',
        'cherche',
        'Je cherche la gare.',
        'Chercher takes -e with je.',
        ['cherche', 'cherches', 'chercher'],
      ),
      _guided(
        'Take the bus',
        'Tu ___ le bus.',
        'You take the bus.',
        'prends',
        'Tu prends le bus.',
        'With tu, prendre becomes prends.',
        ['prends', 'prend', 'prendre'],
      ),
      _guided(
        'Walk outside',
        'Elle ___ dans la rue.',
        'She walks in the street.',
        'marche',
        'Elle marche dans la rue.',
        'A singular feminine subject uses marche.',
        ['marche', 'marchent', 'marcher'],
      ),
      _guided(
        'Cross downtown',
        'Nous ___ le centre-ville.',
        'We cross downtown.',
        'traversons',
        'Nous traversons le centre-ville.',
        'With nous, traverser becomes traversons.',
        ['traversons', 'traverse', 'traverser'],
      ),
      _guided(
        'Turn left',
        'Vous ___ à gauche.',
        'You turn left.',
        'tournez',
        'Vous tournez à gauche.',
        'With vous, tourner becomes tournez.',
        ['tournez', 'tourne', 'tourner'],
      ),
    ],
  ),
  _session(
    'grammar_present_complete_weekday',
    'My weekday',
    'Build five short sentences about an ordinary day.',
    'Present-tense sentence order',
    'calendar',
    GrammarV2Mode.complete,
    [
      _complete(
        'Start work',
        'Build the sentence',
        'I start work at nine.',
        'Je commence le travail à neuf heures.',
        'The subject comes before the present-tense verb.',
      ),
      _complete(
        'Have coffee',
        'Build the sentence',
        'I have a coffee in the morning.',
        'Je prends un café le matin.',
        'Keep the time phrase at the end.',
      ),
      _complete(
        'Eat together',
        'Build the sentence',
        'We eat lunch together.',
        'Nous déjeunons ensemble.',
        'Nous comes before the -ons verb.',
      ),
      _complete(
        'Go home',
        'Build the sentence',
        'I go home.',
        'Je rentre à la maison.',
        'Rentre is the present form for je.',
      ),
      _complete(
        'Read at night',
        'Build the sentence',
        'I read a book in the evening.',
        'Je lis un livre le soir.',
        'The object follows the present-tense verb.',
      ),
    ],
  ),
  _session(
    'grammar_present_complete_market',
    'At the market',
    'Build a small shopping exchange from start to finish.',
    'Present-tense shopping verbs',
    'market',
    GrammarV2Mode.complete,
    [
      _complete(
        'Enter the market',
        'Build the sentence',
        'I enter the market.',
        'J’entre dans le marché.',
        'Use j’entre before a vowel sound.',
      ),
      _complete(
        'Choose fruit',
        'Build the sentence',
        'I choose three apples.',
        'Je choisis trois pommes.',
        'Choisir uses -is with je.',
      ),
      _complete(
        'Ask the price',
        'Build the sentence',
        'You ask the price.',
        'Tu demandes le prix.',
        'The verb agrees with tu.',
      ),
      _complete(
        'Pay the seller',
        'Build the sentence',
        'We pay the seller.',
        'Nous payons le vendeur.',
        'Payons is the nous form of payer.',
      ),
      _complete(
        'Leave together',
        'Build the sentence',
        'We leave together.',
        'Nous sortons ensemble.',
        'Sortons is the present nous form.',
      ),
    ],
  ),
  _session(
    'grammar_present_complete_weekend',
    'A calm weekend',
    'Build sentences that describe what you do on the weekend.',
    'Present-tense routine phrases',
    'home',
    GrammarV2Mode.complete,
    [
      _complete(
        'Sleep late',
        'Build the sentence',
        'I sleep late on Saturday.',
        'Je dors tard samedi.',
        'Dors is the present form for je.',
      ),
      _complete(
        'Visit a friend',
        'Build the sentence',
        'I visit a friend.',
        'Je visite un ami.',
        'The regular -er verb follows je.',
      ),
      _complete(
        'Cook dinner',
        'Build the sentence',
        'We cook dinner together.',
        'Nous cuisinons ensemble le dîner.',
        'Cuisinons is the nous form.',
      ),
      _complete(
        'Watch a film',
        'Build the sentence',
        'They watch a film.',
        'Ils regardent un film.',
        'Ils takes the -ent ending.',
      ),
      _complete(
        'Rest at home',
        'Build the sentence',
        'We rest at home.',
        'Nous nous reposons à la maison.',
        'Keep the reflexive pronoun before the verb.',
      ),
    ],
  ),
  _session(
    'grammar_present_roleplay_cafe',
    'Order at the café',
    'Use the present tense through one short café conversation.',
    'Present-tense café conversation',
    'coffee',
    GrammarV2Mode.roleplay,
    [
      _roleplay(
        'Choose a drink',
        'Bonjour, vous désirez ?',
        'Hello, what would you like?',
        'Reply with a present-tense order.',
        'I am having a coffee, please.',
        'Je prends un café, s’il vous plaît.',
        'Use prends with je.',
        [
          'Je prends un café, s’il vous plaît.',
          'Je prendre un café, s’il vous plaît.',
          'Je prend un café, s’il vous plaît.',
        ],
      ),
      _roleplay(
        'Choose a seat',
        'Vous mangez ici ?',
        'Are you eating here?',
        'Reply that you are eating here.',
        'Yes, I am eating here.',
        'Oui, je mange ici.',
        'Mange takes -e with je.',
        ['Oui, je mange ici.', 'Oui, je manger ici.', 'Oui, je manges ici.'],
      ),
      _roleplay(
        'Choose payment',
        'Vous payez comment ?',
        'How are you paying?',
        'Reply that you are paying by card.',
        'I am paying by card.',
        'Je paie par carte.',
        'On and je use paie here.',
        ['Je paie par carte.', 'Je payer par carte.', 'Je paies par carte.'],
      ),
      _roleplay(
        'Close the exchange',
        'Bonne journée !',
        'Have a nice day!',
        'Reply politely and close the café exchange.',
        'Thank you, see you soon.',
        'Merci, à bientôt.',
        'A short present-tense reply is enough.',
        ['Merci, à bientôt.', 'Merci, à bientôtes.', 'Merci, à bientôt aller.'],
      ),
    ],
  ),
  _session(
    'grammar_present_roleplay_neighbor',
    'Meet a neighbor',
    'Greet someone, share where you live, and ask a simple question.',
    'Present-tense introductions',
    'chat',
    GrammarV2Mode.roleplay,
    [
      _roleplay(
        'Say hello',
        'Bonjour, vous êtes nouveau ici ?',
        'Hello, are you new here?',
        'Answer with a simple introduction.',
        'Yes, I am new here.',
        'Oui, je suis nouveau ici.',
        'Je suis is the present form of être.',
        [
          'Oui, je suis nouveau ici.',
          'Oui, je être nouveau ici.',
          'Oui, je es nouveau ici.',
        ],
      ),
      _roleplay(
        'Say your name',
        'Comment vous appelez-vous ?',
        'What is your name?',
        'Say your name politely.',
        'My name is Alex.',
        'Je m’appelle Alex.',
        'The reflexive form is m’appelle with je.',
        ['Je m’appelle Alex.', 'Je m’appeler Alex.', 'Je m’appelles Alex.'],
      ),
      _roleplay(
        'Say where you live',
        'Vous habitez dans le quartier ?',
        'Do you live in the neighborhood?',
        'Say that you live nearby.',
        'I live nearby.',
        'J’habite près d’ici.',
        'Habiter takes -e with je.',
        [
          'J’habite près d’ici.',
          'J’habites près d’ici.',
          'J’habiter près d’ici.',
        ],
      ),
      _roleplay(
        'Ask a question',
        'Vous aimez le quartier ?',
        'Do you like the neighborhood?',
        'Ask the neighbor the same question.',
        'Do you like the neighborhood?',
        'Vous aimez le quartier ?',
        'With vous, aimer becomes aimez.',
        [
          'Vous aimez le quartier ?',
          'Vous aimer le quartier ?',
          'Vous aime le quartier ?',
        ],
      ),
    ],
  ),
  _session(
    'grammar_present_roleplay_pharmacy',
    'At the pharmacy',
    'Make a clear present-tense request when you need help.',
    'Present-tense requests',
    'health',
    GrammarV2Mode.roleplay,
    [
      _roleplay(
        'Explain the problem',
        'Bonjour, qu’est-ce qu’il vous faut ?',
        'Hello, what do you need?',
        'Explain that you have a headache.',
        'I have a headache.',
        'J’ai mal à la tête.',
        'J’ai is the present form of avoir.',
        [
          'J’ai mal à la tête.',
          'Je ai mal à la tête.',
          'J’avais mal à la tête.',
        ],
      ),
      _roleplay(
        'Ask for advice',
        'Vous avez besoin d’un conseil ?',
        'Do you need advice?',
        'Ask if the pharmacist has a simple remedy.',
        'Do you have something for this?',
        'Vous avez quelque chose pour ça ?',
        'Use avez with vous.',
        [
          'Vous avez quelque chose pour ça ?',
          'Vous avoir quelque chose pour ça ?',
          'Vous a quelque chose pour ça ?',
        ],
      ),
      _roleplay(
        'Ask the price',
        'C’est tout ?',
        'Is that all?',
        'Ask how much it costs.',
        'How much does it cost?',
        'Combien ça coûte ?',
        'Ça coûte is a present-tense price question.',
        ['Combien ça coûte ?', 'Combien ça coûter ?', 'Combien ça coûtent ?'],
      ),
      _roleplay(
        'Thank the pharmacist',
        'Voici votre produit.',
        'Here is your product.',
        'Thank the pharmacist politely.',
        'Thank you very much.',
        'Merci beaucoup.',
        'Use a short, natural closing.',
        ['Merci beaucoup.', 'Merci beaucoupes.', 'Merci beaucoup aller.'],
      ),
    ],
  ),
];

abstract final class GrammarCourseCatalog {
  static List<GrammarCourseSession> forMode(
    GrammarV2Mode mode, {
    String? level,
    String? tense,
  }) => grammarCourseStarterSessions
      .where(
        (session) =>
            session.mode == mode &&
            (level == null || session.level == level) &&
            (tense == null || session.tense == tense),
      )
      .toList(growable: false);

  static List<GrammarCourseSession> forTense(String tense, {String? level}) =>
      grammarCourseStarterSessions
          .where(
            (session) =>
                session.tense == tense &&
                (level == null || session.level == level),
          )
          .toList(growable: false);
}

abstract final class GrammarCourseCatalogLevel {
  static String normalize(String raw) => switch (raw.toLowerCase()) {
    'a2' => 'A2',
    'b1' || 'conversational' => 'B1',
    'b2' => 'B2',
    _ => 'A1',
  };
}
