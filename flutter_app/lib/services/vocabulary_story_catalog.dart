import '../models/content_models.dart';

/// Starter vocabulary lessons. Most sets have five words; Survival French is
/// the first lesson and introduces ten essential phrases.
class VocabularyStoryCatalog {
  const VocabularyStoryCatalog._();

  static const starterSets = <VocabularyStorySetDefinition>[
    VocabularyStorySetDefinition(
      id: 'survival-french',
      title: 'Survival French',
      subtitle: 'Essential phrases for greetings, help, and everyday questions',
      topic: 'Everyday essentials',
      levelBand: 'A1',
      words: [
        VocabularyStoryWord(
          en: 'Hello / Good morning',
          fr: 'Bonjour',
          phonetic: 'bohn-zhoor',
          sentenceFr: 'Bonjour, madame.',
          sentenceEn: 'Hello, ma’am.',
        ),
        VocabularyStoryWord(
          en: 'Thank you',
          fr: 'Merci',
          phonetic: 'mehr-see',
          sentenceFr: 'Merci beaucoup.',
          sentenceEn: 'Thank you very much.',
        ),
        VocabularyStoryWord(
          en: 'Please',
          fr: 'S’il vous plaît',
          phonetic: 'seel voo pleh',
          sentenceFr: 'Un verre d’eau, s’il vous plaît.',
          sentenceEn: 'A glass of water, please.',
        ),
        VocabularyStoryWord(
          en: 'Yes',
          fr: 'Oui',
          phonetic: 'wee',
          sentenceFr: 'Oui, je comprends.',
          sentenceEn: 'Yes, I understand.',
        ),
        VocabularyStoryWord(
          en: 'No',
          fr: 'Non',
          phonetic: 'nohn',
          sentenceFr: 'Non, merci.',
          sentenceEn: 'No, thank you.',
        ),
        VocabularyStoryWord(
          en: 'Excuse me / Sorry',
          fr: 'Pardon',
          phonetic: 'par-dohn',
          sentenceFr: 'Pardon, je cherche la gare.',
          sentenceEn: 'Excuse me, I’m looking for the station.',
        ),
        VocabularyStoryWord(
          en: 'Help me',
          fr: 'Aidez-moi',
          phonetic: 'eh-day mwah',
          sentenceFr: 'Aidez-moi, s’il vous plaît.',
          sentenceEn: 'Help me, please.',
        ),
        VocabularyStoryWord(
          en: 'Where',
          fr: 'Où',
          phonetic: 'oo',
          sentenceFr: 'Où est la sortie ?',
          sentenceEn: 'Where is the exit?',
        ),
        VocabularyStoryWord(
          en: 'How much / How many',
          fr: 'Combien',
          phonetic: 'kohm-byehn',
          sentenceFr: 'Combien ça coûte ?',
          sentenceEn: 'How much does it cost?',
        ),
        VocabularyStoryWord(
          en: 'Goodbye',
          fr: 'Au revoir',
          phonetic: 'oh ruh-vwahr',
          sentenceFr: 'Au revoir et bonne journée.',
          sentenceEn: 'Goodbye and have a nice day.',
        ),
      ],
    ),
    VocabularyStorySetDefinition(
      id: 'morning-breakfast',
      title: 'Morning breakfast',
      subtitle: 'Breakfast → late for a meeting',
      topic: 'Food & routine',
      levelBand: 'A1',
      words: [
        VocabularyStoryWord(
          en: 'hungry',
          fr: 'faim',
          phonetic: 'fam',
          sentenceFr: 'J’ai faim ce matin.',
          sentenceEn: 'I’m hungry this morning.',
        ),
        VocabularyStoryWord(
          en: 'egg',
          fr: 'œuf',
          phonetic: 'uhf',
          sentenceFr: 'Je casse un œuf.',
          sentenceEn: 'I crack an egg.',
        ),
        VocabularyStoryWord(
          en: 'coffee',
          fr: 'café',
          phonetic: 'ka-fay',
          sentenceFr: 'Je bois un café.',
          sentenceEn: 'I drink a coffee.',
        ),
        VocabularyStoryWord(
          en: 'clock',
          fr: 'horloge',
          phonetic: 'or-lozh',
          sentenceFr: 'Je regarde l’horloge.',
          sentenceEn: 'I look at the clock.',
        ),
        VocabularyStoryWord(
          en: 'meeting',
          fr: 'réunion',
          phonetic: 'ray-u-nyon',
          sentenceFr: 'La réunion commence bientôt.',
          sentenceEn: 'The meeting starts soon.',
        ),
      ],
    ),
    VocabularyStorySetDefinition(
      id: 'at-the-cafe',
      title: 'At the café',
      subtitle: 'Order a simple breakfast in French',
      topic: 'Food & shopping',
      levelBand: 'A1',
      words: [
        VocabularyStoryWord(
          en: 'café',
          fr: 'café',
          phonetic: 'ka-fay',
          sentenceFr: 'Je vais au café du coin.',
          sentenceEn: 'I go to the café nearby.',
        ),
        VocabularyStoryWord(
          en: 'water',
          fr: 'eau',
          phonetic: 'oh',
          sentenceFr: 'Je demande de l’eau.',
          sentenceEn: 'I ask for water.',
        ),
        VocabularyStoryWord(
          en: 'bread',
          fr: 'pain',
          phonetic: 'pan',
          sentenceFr: 'Je prends du pain.',
          sentenceEn: 'I take some bread.',
        ),
        VocabularyStoryWord(
          en: 'menu',
          fr: 'menu',
          phonetic: 'muh-new',
          sentenceFr: 'Je regarde le menu.',
          sentenceEn: 'I look at the menu.',
        ),
        VocabularyStoryWord(
          en: 'bill',
          fr: 'addition',
          phonetic: 'ah-dee-syon',
          sentenceFr: 'Je demande l’addition.',
          sentenceEn: 'I ask for the bill.',
        ),
      ],
    ),
    VocabularyStorySetDefinition(
      id: 'at-the-station',
      title: 'At the station',
      subtitle: 'Catch the next train across town',
      topic: 'Travel',
      levelBand: 'A1',
      words: [
        VocabularyStoryWord(
          en: 'station',
          fr: 'gare',
          phonetic: 'gahr',
          sentenceFr: 'J’arrive à la gare.',
          sentenceEn: 'I arrive at the station.',
        ),
        VocabularyStoryWord(
          en: 'ticket',
          fr: 'billet',
          phonetic: 'bee-yay',
          sentenceFr: 'J’ai mon billet.',
          sentenceEn: 'I have my ticket.',
        ),
        VocabularyStoryWord(
          en: 'train',
          fr: 'train',
          phonetic: 'tran',
          sentenceFr: 'Le train arrive.',
          sentenceEn: 'The train arrives.',
        ),
        VocabularyStoryWord(
          en: 'platform',
          fr: 'quai',
          phonetic: 'kay',
          sentenceFr: 'Je cherche le quai deux.',
          sentenceEn: 'I look for platform two.',
        ),
        VocabularyStoryWord(
          en: 'late',
          fr: 'retard',
          phonetic: 'ruh-tar',
          sentenceFr: 'Le train est en retard.',
          sentenceEn: 'The train is late.',
        ),
      ],
    ),
    VocabularyStorySetDefinition(
      id: 'home-after-work',
      title: 'Home after work',
      subtitle: 'Get home, unlock the door, and eat dinner',
      topic: 'Home & routine',
      levelBand: 'A1',
      words: [
        VocabularyStoryWord(
          en: 'house',
          fr: 'maison',
          phonetic: 'may-zohn',
          sentenceFr: 'Je rentre à la maison.',
          sentenceEn: 'I go home.',
        ),
        VocabularyStoryWord(
          en: 'key',
          fr: 'clé',
          phonetic: 'clay',
          sentenceFr: 'Je cherche ma clé.',
          sentenceEn: 'I look for my key.',
        ),
        VocabularyStoryWord(
          en: 'door',
          fr: 'porte',
          phonetic: 'port',
          sentenceFr: 'J’ouvre la porte.',
          sentenceEn: 'I open the door.',
        ),
        VocabularyStoryWord(
          en: 'dinner',
          fr: 'dîner',
          phonetic: 'dee-nay',
          sentenceFr: 'Le dîner est prêt.',
          sentenceEn: 'Dinner is ready.',
        ),
        VocabularyStoryWord(
          en: 'tired',
          fr: 'fatigué',
          phonetic: 'fa-tee-gay',
          sentenceFr: 'Je suis fatigué ce soir.',
          sentenceEn: 'I’m tired tonight.',
        ),
      ],
    ),
    VocabularyStorySetDefinition(
      id: 'weekend-market',
      title: 'Weekend market',
      subtitle: 'Choose fresh fruit and ask the price',
      topic: 'Food & shopping',
      levelBand: 'A1',
      words: [
        VocabularyStoryWord(
          en: 'market',
          fr: 'marché',
          phonetic: 'mar-shay',
          sentenceFr: 'Je vais au marché.',
          sentenceEn: 'I go to the market.',
        ),
        VocabularyStoryWord(
          en: 'apple',
          fr: 'pomme',
          phonetic: 'pom',
          sentenceFr: 'J’achète une pomme.',
          sentenceEn: 'I buy an apple.',
        ),
        VocabularyStoryWord(
          en: 'seller',
          fr: 'vendeur',
          phonetic: 'von-duhr',
          sentenceFr: 'Le vendeur sourit.',
          sentenceEn: 'The seller smiles.',
        ),
        VocabularyStoryWord(
          en: 'price',
          fr: 'prix',
          phonetic: 'pree',
          sentenceFr: 'Je demande le prix.',
          sentenceEn: 'I ask the price.',
        ),
        VocabularyStoryWord(
          en: 'fresh',
          fr: 'frais',
          phonetic: 'fray',
          sentenceFr: 'Les fruits sont frais.',
          sentenceEn: 'The fruit is fresh.',
        ),
      ],
    ),
  ];
}

class VocabularyStorySetDefinition {
  const VocabularyStorySetDefinition({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.topic,
    required this.levelBand,
    required this.words,
  });

  final String id;
  final String title;
  final String subtitle;
  final String topic;
  final String levelBand;
  final List<VocabularyStoryWord> words;

  List<VocabEntry> get entries => [
    for (var index = 0; index < words.length; index++)
      VocabEntry(
        id: '$id-word-$index',
        en: words[index].en,
        fr: words[index].fr,
        phonetic: words[index].phonetic,
      ),
  ];

  Map<String, BilingualExample> examplesFor(List<VocabEntry> entries) => {
    for (var index = 0; index < entries.length && index < words.length; index++)
      entries[index].id: BilingualExample(
        fr: words[index].sentenceFr,
        en: words[index].sentenceEn,
      ),
  };
}

class VocabularyStoryWord {
  const VocabularyStoryWord({
    required this.en,
    required this.fr,
    required this.phonetic,
    required this.sentenceFr,
    required this.sentenceEn,
  });

  final String en;
  final String fr;
  final String phonetic;
  final String sentenceFr;
  final String sentenceEn;
}
