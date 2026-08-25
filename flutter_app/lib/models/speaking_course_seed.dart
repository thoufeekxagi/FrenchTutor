part of 'speaking_course.dart';

class _FreeTalkHintSet {
  const _FreeTalkHintSet({required this.french, required this.english});

  final List<String> french;
  final List<String> english;
}

const _preparedFreeTalkHints = <String, List<_FreeTalkHintSet>>{
  'speaking_free_a1_weather': [
    _FreeTalkHintSet(
      french: ['chaud', 'froid', 'beau'],
      english: ['hot', 'cold', 'nice'],
    ),
    _FreeTalkHintSet(
      french: ['très chaud', 'un peu froid', 'agréable'],
      english: ['very hot', 'a little cold', 'pleasant'],
    ),
    _FreeTalkHintSet(
      french: ['reste à la maison', 'lis un livre', 'regarde un film'],
      english: ['stay home', 'read a book', 'watch a film'],
    ),
  ],
  'speaking_free_a1_family': [
    _FreeTalkHintSet(
      french: ['grande', 'petite', 'nombreuse'],
      english: ['big', 'small', 'large'],
    ),
    _FreeTalkHintSet(
      french: ['ma mère', 'mon frère', 'une amie'],
      english: ['my mother', 'my brother', 'a friend'],
    ),
    _FreeTalkHintSet(
      french: ['mangeons ensemble', 'regardons un film', 'sortons'],
      english: ['eat together', 'watch a film', 'go out'],
    ),
  ],
  'speaking_free_a1_home': [
    _FreeTalkHintSet(
      french: ['une maison', 'un appartement', 'un studio'],
      english: ['a house', 'an apartment', 'a studio'],
    ),
    _FreeTalkHintSet(
      french: ['la cuisine', 'la chambre', 'le salon'],
      english: ['the kitchen', 'the bedroom', 'the living room'],
    ),
    _FreeTalkHintSet(
      french: ['un parc', 'une école', 'un magasin'],
      english: ['a park', 'a school', 'a shop'],
    ),
  ],
  'speaking_free_a1_hobbies': [
    _FreeTalkHintSet(
      french: ['lire', 'cuisiner', 'faire du sport'],
      english: ['read', 'cook', 'exercise'],
    ),
    _FreeTalkHintSet(
      french: ['le soir', 'le week-end', 'après le travail'],
      english: ['in the evening', 'on weekends', 'after work'],
    ),
    _FreeTalkHintSet(
      french: ['avec un ami', 'avec ma famille', 'seul'],
      english: ['with a friend', 'with my family', 'alone'],
    ),
  ],
  'speaking_free_a1_morning': [
    _FreeTalkHintSet(
      french: ['à sept heures', 'à huit heures', 'à neuf heures'],
      english: ['at seven', 'at eight', 'at nine'],
    ),
    _FreeTalkHintSet(
      french: ['du pain', 'un fruit', 'un yaourt'],
      english: ['bread', 'a fruit', 'a yogurt'],
    ),
    _FreeTalkHintSet(
      french: ['en bus', 'à pied', 'en voiture'],
      english: ['by bus', 'on foot', 'by car'],
    ),
  ],
  'speaking_free_a1_evening': [
    _FreeTalkHintSet(
      french: ['je rentre', 'je me repose', 'je cuisine'],
      english: ['I go home', 'I rest', 'I cook'],
    ),
    _FreeTalkHintSet(
      french: ['un film', 'la télévision', 'de la musique'],
      english: ['a film', 'television', 'music'],
    ),
    _FreeTalkHintSet(
      french: ['à dix heures', 'à onze heures', 'vers minuit'],
      english: ['at ten', 'at eleven', 'around midnight'],
    ),
  ],
  'speaking_free_a1_shopping': [
    _FreeTalkHintSet(
      french: ['du lait', 'des pommes', 'du pain'],
      english: ['milk', 'apples', 'bread'],
    ),
    _FreeTalkHintSet(
      french: ['au marché', 'au supermarché', 'près de chez moi'],
      english: ['at the market', 'at the supermarket', 'near my home'],
    ),
    _FreeTalkHintSet(
      french: ['des légumes', 'du café', 'des œufs'],
      english: ['vegetables', 'coffee', 'eggs'],
    ),
  ],
  'speaking_free_a1_neighborhood': [
    _FreeTalkHintSet(
      french: ['un parc', 'une pharmacie', 'un café'],
      english: ['a park', 'a pharmacy', 'a café'],
    ),
    _FreeTalkHintSet(
      french: ['le parc', 'le marché', 'le café'],
      english: ['the park', 'the market', 'the café'],
    ),
    _FreeTalkHintSet(
      french: ['en bus', 'à pied', 'en métro'],
      english: ['by bus', 'on foot', 'by subway'],
    ),
  ],
  'speaking_free_a1_school': [
    _FreeTalkHintSet(
      french: ['au travail', 'à l’école', 'à l’université'],
      english: ['at work', 'at school', 'at university'],
    ),
    _FreeTalkHintSet(
      french: ['je travaille', 'j’étudie', 'je déjeune'],
      english: ['I work', 'I study', 'I have lunch'],
    ),
    _FreeTalkHintSet(
      french: ['la musique', 'le sport', 'la lecture'],
      english: ['music', 'sport', 'reading'],
    ),
  ],
  'speaking_free_a1_colors': [
    _FreeTalkHintSet(
      french: ['une chemise', 'un pantalon', 'une robe'],
      english: ['a shirt', 'trousers', 'a dress'],
    ),
    _FreeTalkHintSet(
      french: ['le bleu', 'le rouge', 'le vert'],
      english: ['blue', 'red', 'green'],
    ),
    _FreeTalkHintSet(
      french: ['les vêtements', 'les chaussures', 'les magasins'],
      english: ['clothes', 'shoes', 'shops'],
    ),
  ],
  'speaking_free_a1_music': [
    _FreeTalkHintSet(
      french: ['la pop', 'le jazz', 'la musique classique'],
      english: ['pop', 'jazz', 'classical music'],
    ),
    _FreeTalkHintSet(
      french: ['le matin', 'le soir', 'en voiture'],
      english: ['in the morning', 'in the evening', 'in the car'],
    ),
    _FreeTalkHintSet(
      french: ['avec un ami', 'avec ma sœur', 'seul'],
      english: ['with a friend', 'with my sister', 'alone'],
    ),
  ],
  'speaking_free_a1_birthday': [
    _FreeTalkHintSet(
      french: ['en janvier', 'en juin', 'en décembre'],
      english: ['in January', 'in June', 'in December'],
    ),
    _FreeTalkHintSet(
      french: ['je mange un gâteau', 'je fais la fête', 'je vois ma famille'],
      english: ['I eat cake', 'I celebrate', 'I see my family'],
    ),
    _FreeTalkHintSet(
      french: ['un livre', 'un voyage', 'un vêtement'],
      english: ['a book', 'a trip', 'a piece of clothing'],
    ),
  ],
  'speaking_free_a1_breakfast': [
    _FreeTalkHintSet(
      french: ['du pain', 'un œuf', 'des céréales'],
      english: ['bread', 'an egg', 'cereal'],
    ),
    _FreeTalkHintSet(
      french: ['du café', 'du thé', 'de l’eau'],
      english: ['coffee', 'tea', 'water'],
    ),
    _FreeTalkHintSet(
      french: ['à la maison', 'au café', 'au travail'],
      english: ['at home', 'at the café', 'at work'],
    ),
  ],
  'speaking_free_a1_free_time': [
    _FreeTalkHintSet(
      french: ['je lis', 'je marche', 'je regarde un film'],
      english: ['I read', 'I walk', 'I watch a film'],
    ),
    _FreeTalkHintSet(
      french: ['sortir', 'rester chez moi', 'voir des amis'],
      english: ['go out', 'stay home', 'see friends'],
    ),
    _FreeTalkHintSet(
      french: ['c’est amusant', 'c’est calme', 'c’est pratique'],
      english: ['it is fun', 'it is calm', 'it is practical'],
    ),
  ],
  'speaking_free_a1_simple_plans': [
    _FreeTalkHintSet(
      french: ['travailler', 'faire des courses', 'voir un ami'],
      english: ['work', 'go shopping', 'see a friend'],
    ),
    _FreeTalkHintSet(
      french: ['sortir', 'rester chez moi', 'aller au cinéma'],
      english: ['go out', 'stay home', 'go to the cinema'],
    ),
    _FreeTalkHintSet(
      french: ['à huit heures', 'à midi', 'à dix-huit heures'],
      english: ['at eight', 'at noon', 'at six p.m.'],
    ),
  ],
  'speaking_free_a1_transport': [
    _FreeTalkHintSet(
      french: ['en bus', 'en métro', 'à vélo'],
      english: ['by bus', 'by subway', 'by bike'],
    ),
    _FreeTalkHintSet(
      french: ['trente minutes', 'une heure', 'un quart d’heure'],
      english: ['thirty minutes', 'one hour', 'a quarter of an hour'],
    ),
    _FreeTalkHintSet(
      french: ['c’est rapide', 'c’est pratique', 'c’est bon marché'],
      english: ['it is fast', 'it is convenient', 'it is inexpensive'],
    ),
  ],
  'speaking_free_a1_animals': [
    _FreeTalkHintSet(
      french: ['un chien', 'un chat', 'un cheval'],
      english: ['a dog', 'a cat', 'a horse'],
    ),
    _FreeTalkHintSet(
      french: ['un chien', 'un chat', 'un poisson'],
      english: ['a dog', 'a cat', 'a fish'],
    ),
    _FreeTalkHintSet(
      french: ['grand', 'petit', 'très gentil'],
      english: ['big', 'small', 'very kind'],
    ),
  ],
  'speaking_free_a2_last_trip': [
    _FreeTalkHintSet(
      french: ['à Paris', 'à Montréal', 'en France'],
      english: ['to Paris', 'to Montreal', 'in France'],
    ),
    _FreeTalkHintSet(
      french: [
        'j’ai visité un musée',
        'j’ai mangé au restaurant',
        'j’ai marché',
      ],
      english: ['I visited a museum', 'I ate at a restaurant', 'I walked'],
    ),
    _FreeTalkHintSet(
      french: ['la ville', 'la cuisine', 'le paysage'],
      english: ['the city', 'the food', 'the scenery'],
    ),
  ],
  'speaking_free_a2_home_compare': [
    _FreeTalkHintSet(
      french: ['dans une maison', 'à Montréal', 'dans un appartement'],
      english: ['in a house', 'in Montreal', 'in an apartment'],
    ),
    _FreeTalkHintSet(
      french: ['plus grand', 'plus calme', 'plus moderne'],
      english: ['bigger', 'quieter', 'more modern'],
    ),
    _FreeTalkHintSet(
      french: ['ma maison', 'mon appartement', 'le premier logement'],
      english: ['my house', 'my apartment', 'the first home'],
    ),
  ],
  'speaking_free_a2_restaurant': [
    _FreeTalkHintSet(
      french: ['un steak', 'une soupe', 'un plat de poisson'],
      english: ['a steak', 'a soup', 'a fish dish'],
    ),
    _FreeTalkHintSet(
      french: ['très bon', 'un peu salé', 'délicieux'],
      english: ['very good', 'a little salty', 'delicious'],
    ),
    _FreeTalkHintSet(
      french: ['le service', 'la nourriture', 'le prix'],
      english: ['the service', 'the food', 'the price'],
    ),
  ],
  'speaking_free_a2_health': [
    _FreeTalkHintSet(
      french: ['bien dormir', 'faire du sport', 'manger équilibré'],
      english: ['sleep well', 'exercise', 'eat a balanced diet'],
    ),
    _FreeTalkHintSet(
      french: ['je marche', 'je bois de l’eau', 'je cuisine'],
      english: ['I walk', 'I drink water', 'I cook'],
    ),
    _FreeTalkHintSet(
      french: ['faire une pause', 'mieux dormir', 'moins travailler'],
      english: ['take a break', 'sleep better', 'work less'],
    ),
  ],
  'speaking_free_a2_workday': [
    _FreeTalkHintSet(
      french: ['à huit heures', 'avec un café', 'au bureau'],
      english: ['at eight', 'with a coffee', 'at the office'],
    ),
    _FreeTalkHintSet(
      french: ['un projet', 'les clients', 'les réunions'],
      english: ['a project', 'the clients', 'the meetings'],
    ),
    _FreeTalkHintSet(
      french: ['le temps', 'les appels', 'les délais'],
      english: ['the time', 'the calls', 'the deadlines'],
    ),
  ],
  'speaking_free_a2_french': [
    _FreeTalkHintSet(
      french: ['pour le travail', 'pour voyager', 'pour ma famille'],
      english: ['for work', 'for travel', 'for my family'],
    ),
    _FreeTalkHintSet(
      french: ['je lis', 'je parle', 'je pratique'],
      english: ['I read', 'I speak', 'I practise'],
    ),
    _FreeTalkHintSet(
      french: ['parler couramment', 'passer un examen', 'vivre en France'],
      english: ['speak fluently', 'take an exam', 'live in France'],
    ),
  ],
  'speaking_free_a2_trip_plan': [
    _FreeTalkHintSet(
      french: ['au Japon', 'en Italie', 'à Québec'],
      english: ['to Japan', 'to Italy', 'to Quebec City'],
    ),
    _FreeTalkHintSet(
      french: ['en juillet', 'la semaine prochaine', 'au printemps'],
      english: ['in July', 'next week', 'in spring'],
    ),
    _FreeTalkHintSet(
      french: ['un musée', 'la vieille ville', 'un château'],
      english: ['a museum', 'the old town', 'a castle'],
    ),
  ],
  'speaking_free_a2_delivery': [
    _FreeTalkHintSet(
      french: ['mon colis', 'ma commande', 'le produit'],
      english: ['my parcel', 'my order', 'the product'],
    ),
    _FreeTalkHintSet(
      french: ['hier', 'lundi', 'la semaine dernière'],
      english: ['yesterday', 'on Monday', 'last week'],
    ),
    _FreeTalkHintSet(
      french: ['un remboursement', 'une nouvelle livraison', 'de l’aide'],
      english: ['a refund', 'a new delivery', 'help'],
    ),
  ],
  'speaking_free_a2_movie': [
    _FreeTalkHintSet(
      french: ['un film français', 'une comédie', 'un documentaire'],
      english: ['a French film', 'a comedy', 'a documentary'],
    ),
    _FreeTalkHintSet(
      french: ['une histoire', 'une famille', 'un voyage'],
      english: ['a story', 'a family', 'a journey'],
    ),
    _FreeTalkHintSet(
      french: ['les acteurs', 'la musique', 'la fin'],
      english: ['the actors', 'the music', 'the ending'],
    ),
  ],
  'speaking_free_a2_neighborhood_change': [
    _FreeTalkHintSet(
      french: ['une nouvelle ligne', 'un parc', 'une école'],
      english: ['a new line', 'a park', 'a school'],
    ),
    _FreeTalkHintSet(
      french: ['l’année dernière', 'depuis juin', 'récemment'],
      english: ['last year', 'since June', 'recently'],
    ),
    _FreeTalkHintSet(
      french: ['utile', 'pratique', 'important'],
      english: ['useful', 'practical', 'important'],
    ),
  ],
  'speaking_free_a2_childhood': [
    _FreeTalkHintSet(
      french: ['à la campagne', 'en ville', 'près de la mer'],
      english: ['in the countryside', 'in the city', 'near the sea'],
    ),
    _FreeTalkHintSet(
      french: ['jouer dehors', 'lire', 'faire du vélo'],
      english: ['play outside', 'read', 'ride a bike'],
    ),
    _FreeTalkHintSet(
      french: ['mon frère', 'ma sœur', 'mes amis'],
      english: ['my brother', 'my sister', 'my friends'],
    ),
  ],
  'speaking_free_a2_future': [
    _FreeTalkHintSet(
      french: ['apprendre une langue', 'changer de travail', 'voyager'],
      english: ['learn a language', 'change jobs', 'travel'],
    ),
    _FreeTalkHintSet(
      french: ['pour ma famille', 'pour mon travail', 'pour moi'],
      english: ['for my family', 'for my work', 'for me'],
    ),
    _FreeTalkHintSet(
      french: ['faire un plan', 'chercher des informations', 'commencer'],
      english: ['make a plan', 'look for information', 'start'],
    ),
  ],
  'speaking_free_a2_travel_preference': [
    _FreeTalkHintSet(
      french: ['en train', 'en avion', 'en voiture'],
      english: ['by train', 'by plane', 'by car'],
    ),
    _FreeTalkHintSet(
      french: ['c’est confortable', 'c’est rapide', 'c’est moins cher'],
      english: ['it is comfortable', 'it is fast', 'it is cheaper'],
    ),
    _FreeTalkHintSet(
      french: ['le prix', 'le temps', 'les changements'],
      english: ['the price', 'the time', 'the changes'],
    ),
  ],
  'speaking_free_a2_purchase': [
    _FreeTalkHintSet(
      french: ['un ordinateur', 'un téléphone', 'un manteau'],
      english: ['a computer', 'a phone', 'a coat'],
    ),
    _FreeTalkHintSet(
      french: ['la qualité', 'le prix', 'la couleur'],
      english: ['the quality', 'the price', 'the color'],
    ),
    _FreeTalkHintSet(
      french: ['il fonctionne bien', 'il est pratique', 'il est solide'],
      english: ['it works well', 'it is practical', 'it is sturdy'],
    ),
  ],
  'speaking_free_a2_event': [
    _FreeTalkHintSet(
      french: ['un dîner', 'une fête', 'une réunion'],
      english: ['a dinner', 'a party', 'a meeting'],
    ),
    _FreeTalkHintSet(
      french: ['mes amis', 'ma famille', 'mes collègues'],
      english: ['my friends', 'my family', 'my colleagues'],
    ),
    _FreeTalkHintSet(
      french: ['de la nourriture', 'des boissons', 'une salle'],
      english: ['food', 'drinks', 'a room'],
    ),
  ],
  'speaking_free_a2_advice': [
    _FreeTalkHintSet(
      french: ['le travail', 'la santé', 'la famille'],
      english: ['work', 'health', 'family'],
    ),
    _FreeTalkHintSet(
      french: ['de se reposer', 'de parler', 'de demander de l’aide'],
      english: ['to rest', 'to talk', 'to ask for help'],
    ),
    _FreeTalkHintSet(
      french: ['c’est simple', 'c’est pratique', 'c’est important'],
      english: ['it is simple', 'it is practical', 'it is important'],
    ),
  ],
  'speaking_free_a2_decision': [
    _FreeTalkHintSet(
      french: ['un changement', 'un achat', 'un voyage'],
      english: ['a change', 'a purchase', 'a trip'],
    ),
    _FreeTalkHintSet(
      french: ['c’était nécessaire', 'c’était plus simple', 'j’avais le choix'],
      english: ['it was necessary', 'it was simpler', 'I had a choice'],
    ),
    _FreeTalkHintSet(
      french: ['un bon résultat', 'une nouvelle possibilité', 'plus de temps'],
      english: ['a good result', 'a new possibility', 'more time'],
    ),
  ],
};

SpeakingCourseLesson _freeTalkSeed({
  required String id,
  required String title,
  required String subtitle,
  required String level,
  required IconData icon,
  required List<String> questionsFrench,
  required List<String> questionsEnglish,
  required List<String> framesFrench,
  required List<String> framesEnglish,
}) {
  final hintSets = _preparedFreeTalkHints[id];
  if (questionsFrench.length != 3 ||
      questionsEnglish.length != 3 ||
      framesFrench.length != 3 ||
      framesEnglish.length != 3 ||
      hintSets == null ||
      hintSets.length != 3 ||
      hintSets.any(
        (set) =>
            set.french.length < 3 ||
            set.french.length != set.english.length ||
            set.english.any((word) => word.trim().isEmpty),
      )) {
    throw StateError(
      'Every prepared free-talk lesson must have three bilingual hint sets.',
    );
  }
  return SpeakingCourseLesson(
    id: id,
    title: title,
    subtitle: subtitle,
    level: level,
    icon: icon,
    mode: SpeakingCourseMode.freeTalk,
    lines: [
      for (var index = 0; index < 3; index++)
        SpeakingCourseLine(
          partnerFrench: questionsFrench[index],
          partnerEnglish: questionsEnglish[index],
          french: framesFrench[index],
          english: framesEnglish[index],
          hintWords: hintSets[index].french,
          hintWordsEnglish: hintSets[index].english,
          translationAlignment: SpeakingTranslationAlignment.forPhrase(
            framesFrench[index],
            framesEnglish[index],
          ),
          partnerTranslationAlignment: SpeakingTranslationAlignment.forPhrase(
            questionsFrench[index],
            questionsEnglish[index],
          ),
          openResponse: true,
        ),
    ],
  );
}

SpeakingCourseLesson _roleplaySeed({
  required String id,
  required String title,
  required String subtitle,
  required String level,
  required String goal,
  required IconData icon,
  required List<String> partnerFrench,
  required List<String> partnerEnglish,
  required List<String> learnerFrench,
  required List<String> learnerEnglish,
}) {
  if (partnerFrench.length != 2 ||
      partnerEnglish.length != 2 ||
      learnerFrench.length != 2 ||
      learnerEnglish.length != 2) {
    throw StateError('Every prepared roleplay must have two turns.');
  }
  return SpeakingCourseLesson(
    id: id,
    title: title,
    subtitle: subtitle,
    level: level,
    icon: icon,
    mode: SpeakingCourseMode.roleplay,
    goal: goal,
    lines: [
      for (var index = 0; index < 2; index++)
        SpeakingCourseLine(
          partnerFrench: partnerFrench[index],
          partnerEnglish: partnerEnglish[index],
          french: learnerFrench[index],
          english: learnerEnglish[index],
        ),
    ],
  );
}

final _preparedFreeTalkLessons = <SpeakingCourseLesson>[
  _freeTalkSeed(
    id: 'speaking_free_a1_weather',
    title: 'The weather',
    subtitle: 'Describe today with three simple sentences.',
    level: 'A1',
    icon: Icons.wb_cloudy_outlined,
    questionsFrench: const [
      'Quel temps fait-il aujourd’hui ?',
      'Il fait chaud ou froid ?',
      'Qu’est-ce que vous faites quand il pleut ?',
    ],
    questionsEnglish: const [
      'What is the weather like today?',
      'Is it hot or cold?',
      'What do you do when it rains?',
    ],
    framesFrench: const [
      'Aujourd’hui, il fait…',
      'Il fait…',
      'Quand il pleut, je…',
    ],
    framesEnglish: const ['Today, it is…', 'It is…', 'When it rains, I…'],
  ),
  _freeTalkSeed(
    id: 'speaking_free_a1_family',
    title: 'My family',
    subtitle: 'Introduce the people in your family.',
    level: 'A1',
    icon: Icons.people_outline_rounded,
    questionsFrench: const [
      'Vous avez une grande famille ?',
      'Avec qui habitez-vous ?',
      'Que faites-vous ensemble ?',
    ],
    questionsEnglish: const [
      'Do you have a big family?',
      'Who do you live with?',
      'What do you do together?',
    ],
    framesFrench: const ['J’ai une famille…', 'J’habite avec…', 'Nous aimons…'],
    framesEnglish: const ['I have a… family.', 'I live with…', 'We like to…'],
  ),
  _freeTalkSeed(
    id: 'speaking_free_a1_home',
    title: 'My home',
    subtitle: 'Describe where you live.',
    level: 'A1',
    icon: Icons.home_outlined,
    questionsFrench: const [
      'Vous habitez dans une maison ou un appartement ?',
      'Quelle est votre pièce préférée ?',
      'Qu’est-ce qu’il y a près de chez vous ?',
    ],
    questionsEnglish: const [
      'Do you live in a house or an apartment?',
      'What is your favorite room?',
      'What is near your home?',
    ],
    framesFrench: const [
      'J’habite dans…',
      'Ma pièce préférée est…',
      'Près de chez moi, il y a…',
    ],
    framesEnglish: const [
      'I live in…',
      'My favorite room is…',
      'Near my home, there is…',
    ],
  ),
  _freeTalkSeed(
    id: 'speaking_free_a1_hobbies',
    title: 'My hobbies',
    subtitle: 'Say what you like doing after work or school.',
    level: 'A1',
    icon: Icons.sports_soccer_outlined,
    questionsFrench: const [
      'Qu’est-ce que vous aimez faire ?',
      'Quand est-ce que vous le faites ?',
      'Vous le faites avec qui ?',
    ],
    questionsEnglish: const [
      'What do you like to do?',
      'When do you do it?',
      'Who do you do it with?',
    ],
    framesFrench: const ['J’aime…', 'Je le fais…', 'Je le fais avec…'],
    framesEnglish: const ['I like…', 'I do it…', 'I do it with…'],
  ),
  _freeTalkSeed(
    id: 'speaking_free_a1_morning',
    title: 'My morning',
    subtitle: 'Talk through three parts of your morning.',
    level: 'A1',
    icon: Icons.wb_sunny_outlined,
    questionsFrench: const [
      'À quelle heure vous levez-vous ?',
      'Que mangez-vous le matin ?',
      'Comment allez-vous au travail ou à l’école ?',
    ],
    questionsEnglish: const [
      'What time do you get up?',
      'What do you eat in the morning?',
      'How do you go to work or school?',
    ],
    framesFrench: const ['Je me lève à…', 'Je mange…', 'Je vais…'],
    framesEnglish: const ['I get up at…', 'I eat…', 'I go…'],
  ),
  _freeTalkSeed(
    id: 'speaking_free_a1_evening',
    title: 'My evening',
    subtitle: 'Say how your day ends.',
    level: 'A1',
    icon: Icons.nightlight_outlined,
    questionsFrench: const [
      'Que faites-vous après le travail ?',
      'Qu’est-ce que vous regardez ou écoutez ?',
      'À quelle heure vous couchez-vous ?',
    ],
    questionsEnglish: const [
      'What do you do after work?',
      'What do you watch or listen to?',
      'What time do you go to bed?',
    ],
    framesFrench: const [
      'Après le travail, je…',
      'Je regarde… / J’écoute…',
      'Je me couche à…',
    ],
    framesEnglish: const [
      'After work, I…',
      'I watch… / I listen to…',
      'I go to bed at…',
    ],
  ),
  _freeTalkSeed(
    id: 'speaking_free_a1_shopping',
    title: 'My shopping list',
    subtitle: 'Name a few things you need to buy.',
    level: 'A1',
    icon: Icons.shopping_bag_outlined,
    questionsFrench: const [
      'Qu’est-ce que vous devez acheter ?',
      'Où faites-vous vos courses ?',
      'Qu’est-ce que vous achetez souvent ?',
    ],
    questionsEnglish: const [
      'What do you need to buy?',
      'Where do you shop?',
      'What do you buy often?',
    ],
    framesFrench: const [
      'Je dois acheter…',
      'Je fais mes courses…',
      'J’achète souvent…',
    ],
    framesEnglish: const ['I need to buy…', 'I shop…', 'I often buy…'],
  ),
  _freeTalkSeed(
    id: 'speaking_free_a1_neighborhood',
    title: 'My neighborhood',
    subtitle: 'Point out useful places near you.',
    level: 'A1',
    icon: Icons.location_on_outlined,
    questionsFrench: const [
      'Qu’est-ce qu’il y a dans votre quartier ?',
      'Quel endroit aimez-vous ?',
      'Comment allez-vous au centre-ville ?',
    ],
    questionsEnglish: const [
      'What is in your neighborhood?',
      'Which place do you like?',
      'How do you get downtown?',
    ],
    framesFrench: const [
      'Dans mon quartier, il y a…',
      'J’aime…',
      'Je vais au centre-ville…',
    ],
    framesEnglish: const [
      'In my neighborhood, there is…',
      'I like…',
      'I go downtown…',
    ],
  ),
  _freeTalkSeed(
    id: 'speaking_free_a1_school',
    title: 'School or work',
    subtitle: 'Say where you spend your day.',
    level: 'A1',
    icon: Icons.school_outlined,
    questionsFrench: const [
      'Vous travaillez ou vous étudiez ?',
      'Que faites-vous pendant la journée ?',
      'Qu’est-ce que vous aimez ?',
    ],
    questionsEnglish: const [
      'Do you work or study?',
      'What do you do during the day?',
      'What do you like?',
    ],
    framesFrench: const [
      'Je travaille… / J’étudie…',
      'Pendant la journée, je…',
      'J’aime…',
    ],
    framesEnglish: const [
      'I work… / I study…',
      'During the day, I…',
      'I like…',
    ],
  ),
  _freeTalkSeed(
    id: 'speaking_free_a1_colors',
    title: 'Colors and clothes',
    subtitle: 'Describe what you are wearing.',
    level: 'A1',
    icon: Icons.checkroom_outlined,
    questionsFrench: const [
      'Qu’est-ce que vous portez aujourd’hui ?',
      'Quelle est votre couleur préférée ?',
      'Vous aimez faire les magasins ?',
    ],
    questionsEnglish: const [
      'What are you wearing today?',
      'What is your favorite color?',
      'Do you like shopping?',
    ],
    framesFrench: const [
      'Aujourd’hui, je porte…',
      'Ma couleur préférée est…',
      'Oui, j’aime… / Non, je n’aime pas…',
    ],
    framesEnglish: const [
      'Today, I am wearing…',
      'My favorite color is…',
      'Yes, I like… / No, I do not like…',
    ],
  ),
  _freeTalkSeed(
    id: 'speaking_free_a1_music',
    title: 'Music I like',
    subtitle: 'Talk about one song or artist.',
    level: 'A1',
    icon: Icons.music_note_outlined,
    questionsFrench: const [
      'Quelle musique aimez-vous ?',
      'Quand est-ce que vous l’écoutez ?',
      'Vous écoutez de la musique avec qui ?',
    ],
    questionsEnglish: const [
      'What music do you like?',
      'When do you listen to it?',
      'Who do you listen to music with?',
    ],
    framesFrench: const ['J’aime…', 'Je l’écoute…', 'Je l’écoute avec…'],
    framesEnglish: const ['I like…', 'I listen to it…', 'I listen to it with…'],
  ),
  _freeTalkSeed(
    id: 'speaking_free_a1_birthday',
    title: 'A birthday',
    subtitle: 'Say when your birthday is and what you do.',
    level: 'A1',
    icon: Icons.cake_outlined,
    questionsFrench: const [
      'Quand est votre anniversaire ?',
      'Qu’est-ce que vous faites ce jour-là ?',
      'Quel cadeau aimez-vous recevoir ?',
    ],
    questionsEnglish: const [
      'When is your birthday?',
      'What do you do on that day?',
      'What gift do you like to receive?',
    ],
    framesFrench: const [
      'Mon anniversaire est le…',
      'Ce jour-là, je…',
      'J’aime recevoir…',
    ],
    framesEnglish: const [
      'My birthday is on…',
      'On that day, I…',
      'I like to receive…',
    ],
  ),
  _freeTalkSeed(
    id: 'speaking_free_a1_breakfast',
    title: 'Breakfast',
    subtitle: 'Order and describe a simple breakfast.',
    level: 'A1',
    icon: Icons.free_breakfast_outlined,
    questionsFrench: const [
      'Qu’est-ce que vous prenez au petit-déjeuner ?',
      'Vous buvez du café ou du thé ?',
      'Vous prenez le petit-déjeuner où ?',
    ],
    questionsEnglish: const [
      'What do you have for breakfast?',
      'Do you drink coffee or tea?',
      'Where do you have breakfast?',
    ],
    framesFrench: const [
      'Au petit-déjeuner, je prends…',
      'Je bois…',
      'Je prends le petit-déjeuner…',
    ],
    framesEnglish: const [
      'For breakfast, I have…',
      'I drink…',
      'I have breakfast…',
    ],
  ),
  _freeTalkSeed(
    id: 'speaking_free_a1_free_time',
    title: 'Free time',
    subtitle: 'Say what you do when you have a free hour.',
    level: 'A1',
    icon: Icons.hourglass_empty_outlined,
    questionsFrench: const [
      'Qu’est-ce que vous faites pendant votre temps libre ?',
      'Vous préférez sortir ou rester chez vous ?',
      'Pourquoi ?',
    ],
    questionsEnglish: const [
      'What do you do in your free time?',
      'Do you prefer going out or staying home?',
      'Why?',
    ],
    framesFrench: const [
      'Pendant mon temps libre, je…',
      'Je préfère…',
      'Parce que…',
    ],
    framesEnglish: const ['In my free time, I…', 'I prefer…', 'Because…'],
  ),
  _freeTalkSeed(
    id: 'speaking_free_a1_simple_plans',
    title: 'Simple plans',
    subtitle: 'Say what you are going to do tomorrow.',
    level: 'A1',
    icon: Icons.event_outlined,
    questionsFrench: const [
      'Qu’est-ce que vous allez faire demain ?',
      'Vous allez sortir ?',
      'À quelle heure ?',
    ],
    questionsEnglish: const [
      'What are you going to do tomorrow?',
      'Are you going out?',
      'At what time?',
    ],
    framesFrench: const [
      'Demain, je vais…',
      'Oui, je vais… / Non, je vais…',
      'À… heures.',
    ],
    framesEnglish: const [
      'Tomorrow, I am going to…',
      'Yes, I am going to… / No, I am going to…',
      'At… o’clock.',
    ],
  ),
  _freeTalkSeed(
    id: 'speaking_free_a1_transport',
    title: 'My transport',
    subtitle: 'Say how you move around your city.',
    level: 'A1',
    icon: Icons.directions_transit_outlined,
    questionsFrench: const [
      'Comment allez-vous en ville ?',
      'Combien de temps dure le trajet ?',
      'Vous aimez ce moyen de transport ?',
    ],
    questionsEnglish: const [
      'How do you get around the city?',
      'How long does the journey take?',
      'Do you like this means of transport?',
    ],
    framesFrench: const [
      'Je vais en ville…',
      'Le trajet dure…',
      'Oui, je l’aime parce que…',
    ],
    framesEnglish: const [
      'I get around the city…',
      'The journey takes…',
      'Yes, I like it because…',
    ],
  ),
  _freeTalkSeed(
    id: 'speaking_free_a1_animals',
    title: 'Animals',
    subtitle: 'Talk about an animal you like.',
    level: 'A1',
    icon: Icons.pets_outlined,
    questionsFrench: const [
      'Quel animal aimez-vous ?',
      'Vous avez un animal chez vous ?',
      'À quoi ressemble-t-il ?',
    ],
    questionsEnglish: const [
      'What animal do you like?',
      'Do you have a pet at home?',
      'What does it look like?',
    ],
    framesFrench: const [
      'J’aime…',
      'Oui, j’ai… / Non, je n’ai pas…',
      'Il est… / Elle est…',
    ],
    framesEnglish: const [
      'I like…',
      'Yes, I have… / No, I do not have…',
      'It is…',
    ],
  ),
  _freeTalkSeed(
    id: 'speaking_free_a2_last_trip',
    title: 'My last trip',
    subtitle: 'Tell a short story about a recent trip.',
    level: 'A2',
    icon: Icons.luggage_outlined,
    questionsFrench: const [
      'Où êtes-vous allé(e) récemment ?',
      'Qu’avez-vous fait sur place ?',
      'Qu’est-ce qui vous a plu ?',
    ],
    questionsEnglish: const [
      'Where did you go recently?',
      'What did you do there?',
      'What did you like?',
    ],
    framesFrench: const [
      'Je suis allé(e) à…',
      'Sur place, j’ai…',
      'J’ai aimé… parce que…',
    ],
    framesEnglish: const ['I went to…', 'There, I…', 'I liked… because…'],
  ),
  _freeTalkSeed(
    id: 'speaking_free_a2_home_compare',
    title: 'Two homes',
    subtitle: 'Compare where you live now and before.',
    level: 'A2',
    icon: Icons.apartment_outlined,
    questionsFrench: const [
      'Où habitiez-vous avant ?',
      'Qu’est-ce qui est différent aujourd’hui ?',
      'Quel logement préférez-vous ?',
    ],
    questionsEnglish: const [
      'Where did you live before?',
      'What is different today?',
      'Which home do you prefer?',
    ],
    framesFrench: const [
      'Avant, j’habitais…',
      'Aujourd’hui, c’est plus…',
      'Je préfère… parce que…',
    ],
    framesEnglish: const [
      'Before, I lived…',
      'Today, it is more…',
      'I prefer… because…',
    ],
  ),
  _freeTalkSeed(
    id: 'speaking_free_a2_restaurant',
    title: 'A restaurant visit',
    subtitle: 'Describe a meal and give a simple opinion.',
    level: 'A2',
    icon: Icons.restaurant_outlined,
    questionsFrench: const [
      'Quel plat avez-vous commandé ?',
      'Comment était le repas ?',
      'Recommanderiez-vous ce restaurant ?',
    ],
    questionsEnglish: const [
      'What dish did you order?',
      'How was the meal?',
      'Would you recommend this restaurant?',
    ],
    framesFrench: const [
      'J’ai commandé…',
      'Le repas était…',
      'Je le recommande parce que…',
    ],
    framesEnglish: const [
      'I ordered…',
      'The meal was…',
      'I recommend it because…',
    ],
  ),
  _freeTalkSeed(
    id: 'speaking_free_a2_health',
    title: 'Healthy habits',
    subtitle: 'Explain one habit you want to improve.',
    level: 'A2',
    icon: Icons.favorite_border_rounded,
    questionsFrench: const [
      'Quelle habitude est importante pour votre santé ?',
      'Qu’est-ce que vous faites déjà ?',
      'Qu’aimeriez-vous changer ?',
    ],
    questionsEnglish: const [
      'Which habit is important for your health?',
      'What do you already do?',
      'What would you like to change?',
    ],
    framesFrench: const [
      'Pour ma santé, il est important de…',
      'Je fais déjà…',
      'J’aimerais…',
    ],
    framesEnglish: const [
      'For my health, it is important to…',
      'I already…',
      'I would like to…',
    ],
  ),
  _freeTalkSeed(
    id: 'speaking_free_a2_workday',
    title: 'A workday',
    subtitle: 'Explain your responsibilities and schedule.',
    level: 'A2',
    icon: Icons.work_outline_rounded,
    questionsFrench: const [
      'À quoi ressemble une journée de travail normale ?',
      'Quelle tâche prenez-vous en charge ?',
      'Qu’est-ce qui est difficile ?',
    ],
    questionsEnglish: const [
      'What is a normal workday like?',
      'Which task are you responsible for?',
      'What is difficult?',
    ],
    framesFrench: const [
      'Une journée normale commence…',
      'Je suis chargé(e) de…',
      'Le plus difficile, c’est…',
    ],
    framesEnglish: const [
      'A normal day starts…',
      'I am responsible for…',
      'The most difficult thing is…',
    ],
  ),
  _freeTalkSeed(
    id: 'speaking_free_a2_french',
    title: 'Learning French',
    subtitle: 'Explain why you are learning French.',
    level: 'A2',
    icon: Icons.menu_book_outlined,
    questionsFrench: const [
      'Pourquoi apprenez-vous le français ?',
      'Qu’est-ce qui vous aide à progresser ?',
      'Quel objectif avez-vous cette année ?',
    ],
    questionsEnglish: const [
      'Why are you learning French?',
      'What helps you improve?',
      'What goal do you have this year?',
    ],
    framesFrench: const [
      'J’apprends le français parce que…',
      'Pour progresser, je…',
      'Cette année, je voudrais…',
    ],
    framesEnglish: const [
      'I am learning French because…',
      'To improve, I…',
      'This year, I would like to…',
    ],
  ),
  _freeTalkSeed(
    id: 'speaking_free_a2_trip_plan',
    title: 'Plan a trip',
    subtitle: 'Choose a destination and explain your plan.',
    level: 'A2',
    icon: Icons.map_outlined,
    questionsFrench: const [
      'Où aimeriez-vous aller ?',
      'Quand partiriez-vous ?',
      'Qu’aimeriez-vous visiter ?',
    ],
    questionsEnglish: const [
      'Where would you like to go?',
      'When would you leave?',
      'What would you like to visit?',
    ],
    framesFrench: const [
      'J’aimerais aller à…',
      'Je partirais…',
      'J’aimerais visiter…',
    ],
    framesEnglish: const [
      'I would like to go to…',
      'I would leave…',
      'I would like to visit…',
    ],
  ),
  _freeTalkSeed(
    id: 'speaking_free_a2_delivery',
    title: 'A delivery problem',
    subtitle: 'Explain a simple problem and ask for a solution.',
    level: 'A2',
    icon: Icons.local_shipping_outlined,
    questionsFrench: const [
      'Quel problème avez-vous avec la livraison ?',
      'Quand deviez-vous recevoir le colis ?',
      'Que demandez-vous au service client ?',
    ],
    questionsEnglish: const [
      'What problem do you have with the delivery?',
      'When were you supposed to receive the parcel?',
      'What do you ask customer service for?',
    ],
    framesFrench: const [
      'Je n’ai pas reçu…',
      'Le colis devait arriver…',
      'Je voudrais…',
    ],
    framesEnglish: const [
      'I did not receive…',
      'The parcel was supposed to arrive…',
      'I would like…',
    ],
  ),
  _freeTalkSeed(
    id: 'speaking_free_a2_movie',
    title: 'A film I saw',
    subtitle: 'Give a short opinion about a film.',
    level: 'A2',
    icon: Icons.movie_outlined,
    questionsFrench: const [
      'Quel film avez-vous vu récemment ?',
      'De quoi parle-t-il ?',
      'Est-ce que vous l’avez aimé ?',
    ],
    questionsEnglish: const [
      'What film did you see recently?',
      'What is it about?',
      'Did you like it?',
    ],
    framesFrench: const ['J’ai vu…', 'Il parle de…', 'Je l’ai aimé parce que…'],
    framesEnglish: const ['I saw…', 'It is about…', 'I liked it because…'],
  ),
  _freeTalkSeed(
    id: 'speaking_free_a2_neighborhood_change',
    title: 'Change in my city',
    subtitle: 'Describe one change and its effect.',
    level: 'A2',
    icon: Icons.construction_outlined,
    questionsFrench: const [
      'Qu’est-ce qui a changé dans votre ville ?',
      'Depuis quand ce changement existe-t-il ?',
      'Est-ce une bonne chose ?',
    ],
    questionsEnglish: const [
      'What has changed in your city?',
      'How long has this change existed?',
      'Is it a good thing?',
    ],
    framesFrench: const [
      'Dans ma ville, on a…',
      'Ce changement existe depuis…',
      'Je pense que c’est… parce que…',
    ],
    framesEnglish: const [
      'In my city, they have…',
      'This change has existed since…',
      'I think it is… because…',
    ],
  ),
  _freeTalkSeed(
    id: 'speaking_free_a2_childhood',
    title: 'When I was young',
    subtitle: 'Tell one memory from your childhood.',
    level: 'A2',
    icon: Icons.toys_outlined,
    questionsFrench: const [
      'Où habitiez-vous quand vous étiez enfant ?',
      'Qu’est-ce que vous aimiez faire ?',
      'Avec qui jouiez-vous ?',
    ],
    questionsEnglish: const [
      'Where did you live when you were a child?',
      'What did you like to do?',
      'Who did you play with?',
    ],
    framesFrench: const [
      'Quand j’étais enfant, j’habitais…',
      'J’aimais…',
      'Je jouais avec…',
    ],
    framesEnglish: const [
      'When I was a child, I lived…',
      'I liked…',
      'I played with…',
    ],
  ),
  _freeTalkSeed(
    id: 'speaking_free_a2_future',
    title: 'A future project',
    subtitle: 'Explain a plan and one next step.',
    level: 'A2',
    icon: Icons.rocket_launch_outlined,
    questionsFrench: const [
      'Quel projet avez-vous pour les prochains mois ?',
      'Pourquoi est-ce important ?',
      'Quelle est la prochaine étape ?',
    ],
    questionsEnglish: const [
      'What project do you have for the next few months?',
      'Why is it important?',
      'What is the next step?',
    ],
    framesFrench: const [
      'Dans les prochains mois, je vais…',
      'C’est important parce que…',
      'La prochaine étape est de…',
    ],
    framesEnglish: const [
      'In the next few months, I am going to…',
      'It is important because…',
      'The next step is to…',
    ],
  ),
  _freeTalkSeed(
    id: 'speaking_free_a2_travel_preference',
    title: 'Travel preferences',
    subtitle: 'Compare two ways to travel.',
    level: 'A2',
    icon: Icons.flight_takeoff_outlined,
    questionsFrench: const [
      'Vous préférez voyager en train ou en avion ?',
      'Quels sont les avantages ?',
      'Qu’est-ce qui est moins pratique ?',
    ],
    questionsEnglish: const [
      'Do you prefer traveling by train or plane?',
      'What are the advantages?',
      'What is less convenient?',
    ],
    framesFrench: const [
      'Je préfère voyager en…',
      'L’avantage, c’est que…',
      'C’est moins pratique parce que…',
    ],
    framesEnglish: const [
      'I prefer traveling by…',
      'The advantage is that…',
      'It is less convenient because…',
    ],
  ),
  _freeTalkSeed(
    id: 'speaking_free_a2_purchase',
    title: 'An important purchase',
    subtitle: 'Explain what you bought and why.',
    level: 'A2',
    icon: Icons.shopping_cart_outlined,
    questionsFrench: const [
      'Qu’avez-vous acheté récemment ?',
      'Pourquoi avez-vous choisi cet article ?',
      'Est-ce que vous en êtes satisfait(e) ?',
    ],
    questionsEnglish: const [
      'What did you buy recently?',
      'Why did you choose this item?',
      'Are you satisfied with it?',
    ],
    framesFrench: const [
      'J’ai acheté…',
      'J’ai choisi cet article parce que…',
      'J’en suis satisfait(e) parce que…',
    ],
    framesEnglish: const [
      'I bought…',
      'I chose this item because…',
      'I am satisfied with it because…',
    ],
  ),
  _freeTalkSeed(
    id: 'speaking_free_a2_event',
    title: 'Organize an event',
    subtitle: 'Plan a small event with another person.',
    level: 'A2',
    icon: Icons.celebration_outlined,
    questionsFrench: const [
      'Quel événement voulez-vous organiser ?',
      'Qui allez-vous inviter ?',
      'De quoi avez-vous besoin ?',
    ],
    questionsEnglish: const [
      'What event do you want to organize?',
      'Who are you going to invite?',
      'What do you need?',
    ],
    framesFrench: const [
      'Je veux organiser…',
      'Je vais inviter…',
      'Nous avons besoin de…',
    ],
    framesEnglish: const [
      'I want to organize…',
      'I am going to invite…',
      'We need…',
    ],
  ),
  _freeTalkSeed(
    id: 'speaking_free_a2_advice',
    title: 'Advice for a friend',
    subtitle: 'Give a kind suggestion about a daily problem.',
    level: 'A2',
    icon: Icons.volunteer_activism_outlined,
    questionsFrench: const [
      'Quel problème votre ami(e) a-t-il ou a-t-elle ?',
      'Quel conseil pouvez-vous donner ?',
      'Pourquoi ce conseil est-il utile ?',
    ],
    questionsEnglish: const [
      'What problem does your friend have?',
      'What advice can you give?',
      'Why is this advice useful?',
    ],
    framesFrench: const [
      'Mon ami(e) a un problème avec…',
      'Je lui conseille de…',
      'Ce conseil est utile parce que…',
    ],
    framesEnglish: const [
      'My friend has a problem with…',
      'I advise them to…',
      'This advice is useful because…',
    ],
  ),
  _freeTalkSeed(
    id: 'speaking_free_a2_decision',
    title: 'A useful decision',
    subtitle: 'Explain a choice and its result.',
    level: 'A2',
    icon: Icons.task_alt_outlined,
    questionsFrench: const [
      'Quelle décision avez-vous prise récemment ?',
      'Pourquoi avez-vous choisi cette solution ?',
      'Quel a été le résultat ?',
    ],
    questionsEnglish: const [
      'What decision did you make recently?',
      'Why did you choose this solution?',
      'What was the result?',
    ],
    framesFrench: const [
      'Récemment, j’ai décidé de…',
      'J’ai choisi cette solution parce que…',
      'Le résultat a été…',
    ],
    framesEnglish: const [
      'Recently, I decided to…',
      'I chose this solution because…',
      'The result was…',
    ],
  ),
];

final _preparedRoleplayLessons = <SpeakingCourseLesson>[
  _roleplaySeed(
    id: 'speaking_roleplay_a1_market',
    title: 'At the market',
    subtitle: 'Buy fruit and ask the price.',
    level: 'A1',
    goal: 'Choose one fruit and pay politely.',
    icon: Icons.local_grocery_store_outlined,
    partnerFrench: const ['Bonjour, vous désirez ?', 'C’est tout ?'],
    partnerEnglish: const ['Hello, what would you like?', 'Is that all?'],
    learnerFrench: const [
      'Je voudrais deux pommes, s’il vous plaît.',
      'Oui, c’est tout. C’est combien ?',
    ],
    learnerEnglish: const [
      'I would like two apples, please.',
      'Yes, that is all. How much is it?',
    ],
  ),
  _roleplaySeed(
    id: 'speaking_roleplay_a1_pharmacy',
    title: 'At the pharmacy',
    subtitle: 'Ask for a basic product.',
    level: 'A1',
    goal: 'Describe one simple need and thank the pharmacist.',
    icon: Icons.local_pharmacy_outlined,
    partnerFrench: const [
      'Bonjour, que cherchez-vous ?',
      'Voilà. Autre chose ?',
    ],
    partnerEnglish: const [
      'Hello, what are you looking for?',
      'Here you are. Anything else?',
    ],
    learnerFrench: const [
      'Je cherche un médicament pour le rhume.',
      'Non, merci. Combien ça coûte ?',
    ],
    learnerEnglish: const [
      'I am looking for medicine for a cold.',
      'No, thank you. How much does it cost?',
    ],
  ),
  _roleplaySeed(
    id: 'speaking_roleplay_a1_bus',
    title: 'On the bus',
    subtitle: 'Ask about a stop and a ticket.',
    level: 'A1',
    goal: 'Confirm the route and where to get off.',
    icon: Icons.directions_bus_outlined,
    partnerFrench: const ['Vous allez où ?', 'Descendez au prochain arrêt.'],
    partnerEnglish: const ['Where are you going?', 'Get off at the next stop.'],
    learnerFrench: const [
      'Je vais au centre-ville, s’il vous plaît.',
      'Merci. Combien coûte le ticket ?',
    ],
    learnerEnglish: const [
      'I am going downtown, please.',
      'Thank you. How much is the ticket?',
    ],
  ),
  _roleplaySeed(
    id: 'speaking_roleplay_a1_library',
    title: 'At the library',
    subtitle: 'Find a simple book.',
    level: 'A1',
    goal: 'Ask for a French beginner book and a library card.',
    icon: Icons.local_library_outlined,
    partnerFrench: const ['Bonjour, je peux vous aider ?', 'Voici le livre.'],
    partnerEnglish: const ['Hello, can I help you?', 'Here is the book.'],
    learnerFrench: const [
      'Je cherche un livre facile en français.',
      'Merci. Je peux l’emprunter ?',
    ],
    learnerEnglish: const [
      'I am looking for an easy book in French.',
      'Thank you. Can I borrow it?',
    ],
  ),
  _roleplaySeed(
    id: 'speaking_roleplay_a1_neighbor',
    title: 'Meet a neighbor',
    subtitle: 'Introduce yourself in the building.',
    level: 'A1',
    goal: 'Say hello and exchange one personal detail.',
    icon: Icons.handshake_outlined,
    partnerFrench: const ['Bonjour, vous habitez ici ?', 'Enchanté !'],
    partnerEnglish: const ['Hello, do you live here?', 'Nice to meet you!'],
    learnerFrench: const [
      'Oui, j’habite au deuxième étage.',
      'Moi aussi. Je m’appelle Alex.',
    ],
    learnerEnglish: const [
      'Yes, I live on the second floor.',
      'Me too. My name is Alex.',
    ],
  ),
  _roleplaySeed(
    id: 'speaking_roleplay_a1_phone',
    title: 'Buy a phone',
    subtitle: 'Ask for a phone and its price.',
    level: 'A1',
    goal: 'Describe what you need and ask how to pay.',
    icon: Icons.smartphone_outlined,
    partnerFrench: const [
      'Quel téléphone cherchez-vous ?',
      'Vous préférez quelle couleur ?',
    ],
    partnerEnglish: const [
      'What phone are you looking for?',
      'Which color do you prefer?',
    ],
    learnerFrench: const [
      'Je cherche un téléphone simple.',
      'Je préfère le noir. Il coûte combien ?',
    ],
    learnerEnglish: const [
      'I am looking for a simple phone.',
      'I prefer black. How much does it cost?',
    ],
  ),
  _roleplaySeed(
    id: 'speaking_roleplay_a1_museum',
    title: 'At the museum',
    subtitle: 'Buy a ticket and find an exhibit.',
    level: 'A1',
    goal: 'Ask for one ticket and the location of a room.',
    icon: Icons.museum_outlined,
    partnerFrench: const [
      'Un billet pour aujourd’hui ?',
      'La salle est au premier étage.',
    ],
    partnerEnglish: const [
      'A ticket for today?',
      'The room is on the first floor.',
    ],
    learnerFrench: const [
      'Oui, un billet pour une personne.',
      'Merci. Où est la salle des tableaux ?',
    ],
    learnerEnglish: const [
      'Yes, one ticket for one person.',
      'Thank you. Where is the paintings room?',
    ],
  ),
  _roleplaySeed(
    id: 'speaking_roleplay_a1_doctor',
    title: 'See a doctor',
    subtitle: 'Describe one simple symptom.',
    level: 'A1',
    goal: 'Say how you feel and understand a basic instruction.',
    icon: Icons.medical_services_outlined,
    partnerFrench: const [
      'Qu’est-ce qui ne va pas ?',
      'Vous devez vous reposer.',
    ],
    partnerEnglish: const ['What is wrong?', 'You need to rest.'],
    learnerFrench: const ['J’ai mal à la tête.', 'D’accord. Merci, docteur.'],
    learnerEnglish: const ['I have a headache.', 'Okay. Thank you, doctor.'],
  ),
  _roleplaySeed(
    id: 'speaking_roleplay_a1_lost_item',
    title: 'Find a lost item',
    subtitle: 'Ask for help after losing something.',
    level: 'A1',
    goal: 'Describe one lost object and where you last saw it.',
    icon: Icons.search_outlined,
    partnerFrench: const ['Qu’avez-vous perdu ?', 'Je vais vérifier.'],
    partnerEnglish: const ['What did you lose?', 'I will check.'],
    learnerFrench: const [
      'J’ai perdu mon sac noir.',
      'Je l’ai vu dans le café.',
    ],
    learnerEnglish: const ['I lost my black bag.', 'I saw it in the café.'],
  ),
  _roleplaySeed(
    id: 'speaking_roleplay_a1_park',
    title: 'At the park',
    subtitle: 'Ask about a place to sit.',
    level: 'A1',
    goal: 'Ask a simple question and respond politely.',
    icon: Icons.park_outlined,
    partnerFrench: const [
      'Vous cherchez quelque chose ?',
      'Le banc est là-bas.',
    ],
    partnerEnglish: const [
      'Are you looking for something?',
      'The bench is over there.',
    ],
    learnerFrench: const [
      'Oui, je cherche un banc.',
      'Merci beaucoup. C’est très gentil.',
    ],
    learnerEnglish: const [
      'Yes, I am looking for a bench.',
      'Thank you very much. That is very kind.',
    ],
  ),
  _roleplaySeed(
    id: 'speaking_roleplay_a1_hairdresser',
    title: 'At the hairdresser',
    subtitle: 'Ask for a simple haircut.',
    level: 'A1',
    goal: 'Say what you want and ask when to return.',
    icon: Icons.content_cut_outlined,
    partnerFrench: const [
      'Comment voulez-vous vos cheveux ?',
      'C’est terminé.',
    ],
    partnerEnglish: const ['How would you like your hair?', 'It is finished.'],
    learnerFrench: const [
      'Je voudrais une coupe courte, s’il vous plaît.',
      'C’est très bien. Combien je vous dois ?',
    ],
    learnerEnglish: const [
      'I would like a short haircut, please.',
      'It is very good. How much do I owe you?',
    ],
  ),
  _roleplaySeed(
    id: 'speaking_roleplay_a1_post',
    title: 'At the post office',
    subtitle: 'Send a small package.',
    level: 'A1',
    goal: 'Say where the package is going and ask the price.',
    icon: Icons.local_post_office_outlined,
    partnerFrench: const ['Vous envoyez le colis où ?', 'Voici le reçu.'],
    partnerEnglish: const [
      'Where are you sending the package?',
      'Here is the receipt.',
    ],
    learnerFrench: const [
      'Je l’envoie à Paris.',
      'Merci. Combien coûte l’envoi ?',
    ],
    learnerEnglish: const [
      'I am sending it to Paris.',
      'Thank you. How much does sending it cost?',
    ],
  ),
  _roleplaySeed(
    id: 'speaking_roleplay_a1_bike',
    title: 'Rent a bike',
    subtitle: 'Rent a bike for one day.',
    level: 'A1',
    goal: 'Ask for a bike and confirm the return time.',
    icon: Icons.pedal_bike_outlined,
    partnerFrench: const [
      'Vous voulez louer un vélo ?',
      'Vous le rendez ce soir.',
    ],
    partnerEnglish: const [
      'Do you want to rent a bike?',
      'You return it this evening.',
    ],
    learnerFrench: const [
      'Oui, pour une journée, s’il vous plaît.',
      'D’accord. Où est le vélo ?',
    ],
    learnerEnglish: const [
      'Yes, for one day, please.',
      'Okay. Where is the bike?',
    ],
  ),
  _roleplaySeed(
    id: 'speaking_roleplay_a1_hours',
    title: 'Ask opening hours',
    subtitle: 'Check when a place opens.',
    level: 'A1',
    goal: 'Ask the opening time and thank the person.',
    icon: Icons.schedule_outlined,
    partnerFrench: const [
      'Bonjour, je peux vous aider ?',
      'Nous ouvrons à neuf heures.',
    ],
    partnerEnglish: const [
      'Hello, can I help you?',
      'We open at nine o’clock.',
    ],
    learnerFrench: const [
      'À quelle heure ouvrez-vous demain ?',
      'Merci pour l’information.',
    ],
    learnerEnglish: const [
      'What time do you open tomorrow?',
      'Thank you for the information.',
    ],
  ),
  _roleplaySeed(
    id: 'speaking_roleplay_a1_appointment',
    title: 'Make an appointment',
    subtitle: 'Choose a simple time for a meeting.',
    level: 'A1',
    goal: 'Ask for an appointment and confirm the day.',
    icon: Icons.event_available_outlined,
    partnerFrench: const [
      'Quel jour vous convient ?',
      'C’est noté pour mardi.',
    ],
    partnerEnglish: const [
      'Which day works for you?',
      'It is noted for Tuesday.',
    ],
    learnerFrench: const [
      'Je voudrais un rendez-vous mardi.',
      'À dix heures, s’il vous plaît.',
    ],
    learnerEnglish: const [
      'I would like an appointment Tuesday.',
      'At ten o’clock, please.',
    ],
  ),
  _roleplaySeed(
    id: 'speaking_roleplay_a2_apartment',
    title: 'Rent an apartment',
    subtitle: 'Ask about a flat and its monthly rent.',
    level: 'A2',
    goal: 'Ask two practical questions before visiting a flat.',
    icon: Icons.domain_outlined,
    partnerFrench: const [
      'Qu’est-ce qui vous intéresse dans cet appartement ?',
      'Le loyer comprend le chauffage.',
    ],
    partnerEnglish: const [
      'What interests you about this apartment?',
      'The rent includes heating.',
    ],
    learnerFrench: const [
      'Je voudrais savoir combien il y a de chambres.',
      'La date de visite me conviendrait vendredi.',
    ],
    learnerEnglish: const [
      'I would like to know how many bedrooms there are.',
      'The viewing date Friday would work for me.',
    ],
  ),
  _roleplaySeed(
    id: 'speaking_roleplay_a2_reservation',
    title: 'Change a reservation',
    subtitle: 'Move a booking to another date.',
    level: 'A2',
    goal: 'Explain the change and confirm the new date.',
    icon: Icons.edit_calendar_outlined,
    partnerFrench: const [
      'Que souhaitez-vous modifier ?',
      'La nouvelle date est confirmée.',
    ],
    partnerEnglish: const [
      'What would you like to change?',
      'The new date is confirmed.',
    ],
    learnerFrench: const [
      'Je voudrais déplacer ma réservation à vendredi.',
      'Parfait, merci de votre aide.',
    ],
    learnerEnglish: const [
      'I would like to move my reservation to Friday.',
      'Perfect, thank you for your help.',
    ],
  ),
  _roleplaySeed(
    id: 'speaking_roleplay_a2_airport',
    title: 'At airport check-in',
    subtitle: 'Check in and ask about your gate.',
    level: 'A2',
    goal: 'Show your documents and confirm where to board.',
    icon: Icons.flight_outlined,
    partnerFrench: const [
      'Puis-je voir votre passeport ?',
      'Votre porte est la douze.',
    ],
    partnerEnglish: const ['May I see your passport?', 'Your gate is twelve.'],
    learnerFrench: const [
      'Bien sûr. Voici mon passeport.',
      'Merci. À quelle heure commence l’embarquement ?',
    ],
    learnerEnglish: const [
      'Of course. Here is my passport.',
      'Thank you. What time does boarding begin?',
    ],
  ),
  _roleplaySeed(
    id: 'speaking_roleplay_a2_complaint',
    title: 'Restaurant problem',
    subtitle: 'Explain a problem with an order politely.',
    level: 'A2',
    goal: 'Describe the problem and ask for a reasonable solution.',
    icon: Icons.report_problem_outlined,
    partnerFrench: const [
      'Quel est le problème avec votre plat ?',
      'Je vais vous en apporter un autre.',
    ],
    partnerEnglish: const [
      'What is the problem with your dish?',
      'I will bring you another one.',
    ],
    learnerFrench: const [
      'Il manque un ingrédient et le plat est froid.',
      'Merci. Je préfère attendre quelques minutes.',
    ],
    learnerEnglish: const [
      'An ingredient is missing and the dish is cold.',
      'Thank you. I prefer to wait a few minutes.',
    ],
  ),
  _roleplaySeed(
    id: 'speaking_roleplay_a2_job',
    title: 'Ask about a job',
    subtitle: 'Ask for information about a position.',
    level: 'A2',
    goal: 'Explain your experience and ask about the schedule.',
    icon: Icons.business_center_outlined,
    partnerFrench: const [
      'Avez-vous déjà fait ce travail ?',
      'Le poste commence lundi.',
    ],
    partnerEnglish: const [
      'Have you done this work before?',
      'The position starts Monday.',
    ],
    learnerFrench: const [
      'Oui, j’ai une expérience dans le service client.',
      'Quels sont les horaires de travail ?',
    ],
    learnerEnglish: const [
      'Yes, I have experience in customer service.',
      'What are the work hours?',
    ],
  ),
  _roleplaySeed(
    id: 'speaking_roleplay_a2_doctor',
    title: 'Doctor appointment',
    subtitle: 'Explain symptoms and ask what to do next.',
    level: 'A2',
    goal: 'Describe a symptom with a duration and follow advice.',
    icon: Icons.health_and_safety_outlined,
    partnerFrench: const [
      'Depuis combien de temps avez-vous ces symptômes ?',
      'Buvez beaucoup d’eau et reposez-vous.',
    ],
    partnerEnglish: const [
      'How long have you had these symptoms?',
      'Drink plenty of water and rest.',
    ],
    learnerFrench: const [
      'J’ai mal à la gorge depuis deux jours.',
      'D’accord. Est-ce que je dois revenir ?',
    ],
    learnerEnglish: const [
      'I have had a sore throat for two days.',
      'Okay. Do I need to come back?',
    ],
  ),
  _roleplaySeed(
    id: 'speaking_roleplay_a2_car',
    title: 'Rent a car',
    subtitle: 'Choose a car and ask about insurance.',
    level: 'A2',
    goal: 'Give your dates and ask one important question.',
    icon: Icons.directions_car_outlined,
    partnerFrench: const [
      'Pour quelles dates avez-vous besoin de la voiture ?',
      'L’assurance de base est comprise.',
    ],
    partnerEnglish: const [
      'For which dates do you need the car?',
      'Basic insurance is included.',
    ],
    learnerFrench: const [
      'Du lundi au jeudi, s’il vous plaît.',
      'Est-ce que l’assurance couvre les dommages ?',
    ],
    learnerEnglish: const [
      'From Monday to Thursday, please.',
      'Does the insurance cover damage?',
    ],
  ),
  _roleplaySeed(
    id: 'speaking_roleplay_a2_interview',
    title: 'A short interview',
    subtitle: 'Answer questions about your experience.',
    level: 'A2',
    goal: 'Introduce your experience and explain one strength.',
    icon: Icons.person_search_outlined,
    partnerFrench: const [
      'Pouvez-vous parler de votre expérience ?',
      'Quelle est votre qualité principale ?',
    ],
    partnerEnglish: const [
      'Can you talk about your experience?',
      'What is your main quality?',
    ],
    learnerFrench: const [
      'J’ai travaillé dans une petite équipe pendant deux ans.',
      'Je suis organisé(e) et j’aime aider les clients.',
    ],
    learnerEnglish: const [
      'I worked in a small team for two years.',
      'I am organized and I like helping customers.',
    ],
  ),
  _roleplaySeed(
    id: 'speaking_roleplay_a2_class',
    title: 'Join a class',
    subtitle: 'Ask about a course and its schedule.',
    level: 'A2',
    goal: 'Explain your level and ask about the next class.',
    icon: Icons.class_outlined,
    partnerFrench: const [
      'Quel est votre niveau de français ?',
      'Le prochain cours commence mardi.',
    ],
    partnerEnglish: const [
      'What is your French level?',
      'The next class starts Tuesday.',
    ],
    learnerFrench: const [
      'Je suis au niveau A2 et je veux parler davantage.',
      'Combien de fois par semaine avez-vous cours ?',
    ],
    learnerEnglish: const [
      'I am at A2 and I want to speak more.',
      'How many times a week do you have class?',
    ],
  ),
  _roleplaySeed(
    id: 'speaking_roleplay_a2_lost_luggage',
    title: 'Lost luggage',
    subtitle: 'Report a missing suitcase at the airport.',
    level: 'A2',
    goal: 'Describe the suitcase and give your contact details.',
    icon: Icons.luggage_outlined,
    partnerFrench: const [
      'À quoi ressemble votre valise ?',
      'Nous vous contacterons demain.',
    ],
    partnerEnglish: const [
      'What does your suitcase look like?',
      'We will contact you tomorrow.',
    ],
    learnerFrench: const [
      'Elle est noire avec une étiquette rouge.',
      'Voici mon numéro de téléphone.',
    ],
    learnerEnglish: const [
      'It is black with a red tag.',
      'Here is my phone number.',
    ],
  ),
  _roleplaySeed(
    id: 'speaking_roleplay_a2_repair',
    title: 'Request a repair',
    subtitle: 'Explain what is broken in your apartment.',
    level: 'A2',
    goal: 'Report the problem and arrange a visit.',
    icon: Icons.build_outlined,
    partnerFrench: const [
      'Qu’est-ce qui ne fonctionne plus ?',
      'Un technicien passera demain.',
    ],
    partnerEnglish: const [
      'What no longer works?',
      'A technician will come tomorrow.',
    ],
    learnerFrench: const [
      'Le chauffage ne fonctionne plus depuis hier.',
      'Demain matin me convient très bien.',
    ],
    learnerEnglish: const [
      'The heating has not worked since yesterday.',
      'Tomorrow morning works very well for me.',
    ],
  ),
  _roleplaySeed(
    id: 'speaking_roleplay_a2_invitation',
    title: 'Invite a friend',
    subtitle: 'Make a plan and suggest an activity.',
    level: 'A2',
    goal: 'Invite someone and agree on a time.',
    icon: Icons.mail_outline_rounded,
    partnerFrench: const [
      'Tu veux faire quelque chose samedi ?',
      'Oui, cette heure me convient.',
    ],
    partnerEnglish: const [
      'Do you want to do something Saturday?',
      'Yes, that time works for me.',
    ],
    learnerFrench: const [
      'Oui, je te propose d’aller au cinéma.',
      'On peut se retrouver à dix-huit heures ?',
    ],
    learnerEnglish: const [
      'Yes, I suggest going to the cinema.',
      'Can we meet at six o’clock?',
    ],
  ),
  _roleplaySeed(
    id: 'speaking_roleplay_a2_bank',
    title: 'At the bank',
    subtitle: 'Ask about a payment or account problem.',
    level: 'A2',
    goal: 'Explain the problem and ask what document is needed.',
    icon: Icons.account_balance_outlined,
    partnerFrench: const [
      'Quel est le problème avec votre compte ?',
      'Avez-vous une pièce d’identité ?',
    ],
    partnerEnglish: const [
      'What is the problem with your account?',
      'Do you have an identity document?',
    ],
    learnerFrench: const [
      'Je ne reconnais pas ce paiement sur mon compte.',
      'Oui, voici ma pièce d’identité.',
    ],
    learnerEnglish: const [
      'I do not recognize this payment on my account.',
      'Yes, here is my identity document.',
    ],
  ),
  _roleplaySeed(
    id: 'speaking_roleplay_a2_hotel_problem',
    title: 'Hotel problem',
    subtitle: 'Ask the reception desk to solve a problem.',
    level: 'A2',
    goal: 'Describe the issue and request a room change.',
    icon: Icons.hotel_outlined,
    partnerFrench: const [
      'Quel est le problème dans votre chambre ?',
      'Nous pouvons vous donner une autre chambre.',
    ],
    partnerEnglish: const [
      'What is the problem in your room?',
      'We can give you another room.',
    ],
    learnerFrench: const [
      'La chambre est très bruyante pendant la nuit.',
      'Merci. Une chambre plus calme serait idéale.',
    ],
    learnerEnglish: const [
      'The room is very noisy at night.',
      'Thank you. A quieter room would be ideal.',
    ],
  ),
  _roleplaySeed(
    id: 'speaking_roleplay_a2_city_event',
    title: 'Choose a city event',
    subtitle: 'Ask for information before going out.',
    level: 'A2',
    goal: 'Ask about the time, place, and price of an event.',
    icon: Icons.festival_outlined,
    partnerFrench: const [
      'Vous cherchez quel type d’événement ?',
      'Le concert commence à vingt heures.',
    ],
    partnerEnglish: const [
      'What type of event are you looking for?',
      'The concert starts at eight p.m.',
    ],
    learnerFrench: const [
      'Je cherche un concert ce soir.',
      'Où a-t-il lieu et combien coûte l’entrée ?',
    ],
    learnerEnglish: const [
      'I am looking for a concert tonight.',
      'Where is it and how much is entry?',
    ],
  ),
];
