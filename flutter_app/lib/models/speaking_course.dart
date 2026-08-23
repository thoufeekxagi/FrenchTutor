import 'package:flutter/material.dart';

/// The three speaking products currently supported by the dedicated Speaking
/// area. None of these routes into Reading, Writing, Vocabulary, or Grammar.
enum SpeakingCourseMode { guided, freeTalk, roleplay }

class SpeakingCourseLine {
  const SpeakingCourseLine({
    required this.french,
    required this.english,
    this.partnerFrench,
    this.partnerEnglish,
    this.tip = '',
    this.openResponse = false,
  });

  final String french;
  final String english;
  final String? partnerFrench;
  final String? partnerEnglish;
  final String tip;
  final bool openResponse;
}

class SpeakingCourseLesson {
  const SpeakingCourseLesson({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.level,
    required this.icon,
    required this.mode,
    required this.lines,
    this.goal = '',
  });

  final String id;
  final String title;
  final String subtitle;
  final String level;
  final IconData icon;
  final SpeakingCourseMode mode;
  final List<SpeakingCourseLine> lines;
  final String goal;
}

class SpeakingCourseUnit {
  const SpeakingCourseUnit({
    required this.number,
    required this.title,
    required this.subtitle,
    required this.level,
    required this.icon,
    required this.lessons,
  });

  final int number;
  final String title;
  final String subtitle;
  final String level;
  final IconData icon;
  final List<SpeakingCourseLesson> lessons;
}

/// A permanent, offline-safe speaking foundation. It is intentionally
/// independent from the mixed-skill adaptive course, so every learner always
/// sees Unit 1 and can start speaking even before generated content exists.
abstract final class SpeakingCourseCatalog {
  static const units = <SpeakingCourseUnit>[
    SpeakingCourseUnit(
      number: 1,
      title: 'The basics',
      subtitle: 'Start with short everyday exchanges.',
      level: 'A1',
      icon: Icons.waving_hand_rounded,
      lessons: [
        SpeakingCourseLesson(
          id: 'speaking_a1_01_introduce',
          title: 'Introduce yourself',
          subtitle: 'Say your name and where you are from.',
          level: 'A1',
          icon: Icons.person_outline_rounded,
          mode: SpeakingCourseMode.guided,
          lines: [
            SpeakingCourseLine(french: 'Bonjour.', english: 'Hello.'),
            SpeakingCourseLine(
              french: 'Je m’appelle Alex.',
              english: 'My name is Alex.',
            ),
            SpeakingCourseLine(
              french: 'Je viens de Toronto.',
              english: 'I am from Toronto.',
            ),
          ],
        ),
        SpeakingCourseLesson(
          id: 'speaking_a1_02_greet',
          title: 'Greet someone',
          subtitle: 'Open and close a friendly exchange.',
          level: 'A1',
          icon: Icons.chat_bubble_outline_rounded,
          mode: SpeakingCourseMode.guided,
          lines: [
            SpeakingCourseLine(
              french: 'Bonjour, ça va ?',
              english: 'Hello, how are you?',
            ),
            SpeakingCourseLine(
              french: 'Ça va bien, merci.',
              english: 'I am well, thank you.',
            ),
            SpeakingCourseLine(french: 'À bientôt !', english: 'See you soon!'),
          ],
        ),
        SpeakingCourseLesson(
          id: 'speaking_a1_03_name',
          title: 'Ask someone’s name',
          subtitle: 'Meet a new person politely.',
          level: 'A1',
          icon: Icons.badge_outlined,
          mode: SpeakingCourseMode.guided,
          lines: [
            SpeakingCourseLine(
              french: 'Comment vous appelez-vous ?',
              english: 'What is your name?',
            ),
            SpeakingCourseLine(
              french: 'Je m’appelle Sam.',
              english: 'My name is Sam.',
            ),
            SpeakingCourseLine(
              french: 'Enchanté de vous rencontrer.',
              english: 'Nice to meet you.',
            ),
          ],
        ),
        SpeakingCourseLesson(
          id: 'speaking_a1_04_origin',
          title: 'Say where you live',
          subtitle: 'Share one simple personal detail.',
          level: 'A1',
          icon: Icons.home_outlined,
          mode: SpeakingCourseMode.guided,
          lines: [
            SpeakingCourseLine(
              french: 'J’habite à Montréal.',
              english: 'I live in Montreal.',
            ),
            SpeakingCourseLine(
              french: 'Et vous, vous habitez où ?',
              english: 'And you, where do you live?',
            ),
            SpeakingCourseLine(
              french: 'J’habite près du centre.',
              english: 'I live near downtown.',
            ),
          ],
        ),
        SpeakingCourseLesson(
          id: 'speaking_a1_05_repeat',
          title: 'Ask for repetition',
          subtitle: 'Repair a conversation without panic.',
          level: 'A1',
          icon: Icons.replay_rounded,
          mode: SpeakingCourseMode.guided,
          lines: [
            SpeakingCourseLine(french: 'Pardon ?', english: 'Sorry?'),
            SpeakingCourseLine(
              french: 'Pouvez-vous répéter ?',
              english: 'Can you repeat?',
            ),
            SpeakingCourseLine(
              french: 'Plus lentement, s’il vous plaît.',
              english: 'More slowly, please.',
            ),
          ],
        ),
        SpeakingCourseLesson(
          id: 'speaking_a1_06_help',
          title: 'Ask for help',
          subtitle: 'Use one clear, polite request.',
          level: 'A1',
          icon: Icons.help_outline_rounded,
          mode: SpeakingCourseMode.guided,
          lines: [
            SpeakingCourseLine(french: 'Excusez-moi.', english: 'Excuse me.'),
            SpeakingCourseLine(
              french: 'Pouvez-vous m’aider ?',
              english: 'Can you help me?',
            ),
            SpeakingCourseLine(
              french: 'Merci beaucoup.',
              english: 'Thank you very much.',
            ),
          ],
        ),
      ],
    ),
    SpeakingCourseUnit(
      number: 2,
      title: 'Food and cafés',
      subtitle: 'Order, ask, and pay with confidence.',
      level: 'A1',
      icon: Icons.local_cafe_outlined,
      lessons: [
        SpeakingCourseLesson(
          id: 'speaking_a1_07_coffee',
          title: 'Order a coffee',
          subtitle: 'Ask for one drink politely.',
          level: 'A1',
          icon: Icons.coffee_rounded,
          mode: SpeakingCourseMode.guided,
          lines: [
            SpeakingCourseLine(
              french: 'Bonjour, je voudrais un café.',
              english: 'Hello, I would like a coffee.',
            ),
            SpeakingCourseLine(
              french: 'Avec du lait, s’il vous plaît.',
              english: 'With milk, please.',
            ),
            SpeakingCourseLine(french: 'Merci.', english: 'Thank you.'),
          ],
        ),
        SpeakingCourseLesson(
          id: 'speaking_a1_08_here',
          title: 'For here or to go',
          subtitle: 'Answer a common café question.',
          level: 'A1',
          icon: Icons.takeout_dining_outlined,
          mode: SpeakingCourseMode.guided,
          lines: [
            SpeakingCourseLine(
              french: 'Sur place ou à emporter ?',
              english: 'For here or to go?',
            ),
            SpeakingCourseLine(
              french: 'Sur place, s’il vous plaît.',
              english: 'For here, please.',
            ),
            SpeakingCourseLine(
              french: 'À emporter, merci.',
              english: 'To go, thank you.',
            ),
          ],
        ),
        SpeakingCourseLesson(
          id: 'speaking_a1_09_menu',
          title: 'Ask for the menu',
          subtitle: 'Get the information you need.',
          level: 'A1',
          icon: Icons.menu_book_outlined,
          mode: SpeakingCourseMode.guided,
          lines: [
            SpeakingCourseLine(
              french: 'La carte, s’il vous plaît.',
              english: 'The menu, please.',
            ),
            SpeakingCourseLine(
              french: 'Qu’est-ce que vous conseillez ?',
              english: 'What do you recommend?',
            ),
            SpeakingCourseLine(
              french: 'Je prends ça.',
              english: 'I will have that.',
            ),
          ],
        ),
        SpeakingCourseLesson(
          id: 'speaking_a1_10_price',
          title: 'Ask the price',
          subtitle: 'Check a price before ordering.',
          level: 'A1',
          icon: Icons.euro_rounded,
          mode: SpeakingCourseMode.guided,
          lines: [
            SpeakingCourseLine(
              french: 'Combien ça coûte ?',
              english: 'How much does it cost?',
            ),
            SpeakingCourseLine(
              french: 'C’est cinq euros.',
              english: 'It is five euros.',
            ),
            SpeakingCourseLine(
              french: 'D’accord, merci.',
              english: 'Okay, thank you.',
            ),
          ],
        ),
        SpeakingCourseLesson(
          id: 'speaking_a1_11_bill',
          title: 'Ask for the bill',
          subtitle: 'Close the café exchange.',
          level: 'A1',
          icon: Icons.receipt_long_outlined,
          mode: SpeakingCourseMode.guided,
          lines: [
            SpeakingCourseLine(
              french: 'L’addition, s’il vous plaît.',
              english: 'The bill, please.',
            ),
            SpeakingCourseLine(
              french: 'Je peux payer par carte ?',
              english: 'Can I pay by card?',
            ),
            SpeakingCourseLine(
              french: 'Merci, bonne journée.',
              english: 'Thank you, have a nice day.',
            ),
          ],
        ),
        SpeakingCourseLesson(
          id: 'speaking_a1_12_cafe_roleplay',
          title: 'At a café',
          subtitle: 'Use the café phrases in a real exchange.',
          level: 'A1',
          icon: Icons.restaurant_rounded,
          mode: SpeakingCourseMode.roleplay,
          goal: 'Order one drink and ask for the bill.',
          lines: [
            SpeakingCourseLine(
              partnerFrench: 'Bonjour, vous désirez ?',
              partnerEnglish: 'Hello, what would you like?',
              french: 'Je voudrais un café, s’il vous plaît.',
              english: 'I would like a coffee, please.',
            ),
            SpeakingCourseLine(
              partnerFrench: 'Sur place ou à emporter ?',
              partnerEnglish: 'For here or to go?',
              french: 'Sur place, s’il vous plaît.',
              english: 'For here, please.',
            ),
            SpeakingCourseLine(
              partnerFrench: 'Voilà votre café.',
              partnerEnglish: 'Here is your coffee.',
              french: 'Merci. L’addition, s’il vous plaît.',
              english: 'Thank you. The bill, please.',
            ),
          ],
        ),
      ],
    ),
    SpeakingCourseUnit(
      number: 3,
      title: 'Getting around',
      subtitle: 'Move through a city with simple French.',
      level: 'A1',
      icon: Icons.train_outlined,
      lessons: [
        SpeakingCourseLesson(
          id: 'speaking_a1_13_where',
          title: 'Ask where something is',
          subtitle: 'Find one place.',
          level: 'A1',
          icon: Icons.place_outlined,
          mode: SpeakingCourseMode.guided,
          lines: [
            SpeakingCourseLine(
              french: 'Excusez-moi, où est la gare ?',
              english: 'Excuse me, where is the station?',
            ),
            SpeakingCourseLine(
              french: 'C’est près d’ici ?',
              english: 'Is it near here?',
            ),
            SpeakingCourseLine(
              french: 'Merci pour votre aide.',
              english: 'Thank you for your help.',
            ),
          ],
        ),
        SpeakingCourseLesson(
          id: 'speaking_a1_14_directions',
          title: 'Follow directions',
          subtitle: 'Understand three useful movements.',
          level: 'A1',
          icon: Icons.directions_outlined,
          mode: SpeakingCourseMode.guided,
          lines: [
            SpeakingCourseLine(
              french: 'Allez tout droit.',
              english: 'Go straight.',
            ),
            SpeakingCourseLine(
              french: 'Tournez à gauche.',
              english: 'Turn left.',
            ),
            SpeakingCourseLine(
              french: 'Tournez à droite.',
              english: 'Turn right.',
            ),
          ],
        ),
        SpeakingCourseLesson(
          id: 'speaking_a1_15_ticket',
          title: 'Buy a ticket',
          subtitle: 'Ask for one simple journey.',
          level: 'A1',
          icon: Icons.confirmation_number_outlined,
          mode: SpeakingCourseMode.guided,
          lines: [
            SpeakingCourseLine(
              french: 'Un billet pour Lyon, s’il vous plaît.',
              english: 'One ticket to Lyon, please.',
            ),
            SpeakingCourseLine(french: 'Aller simple.', english: 'One way.'),
            SpeakingCourseLine(
              french: 'À quelle heure part le train ?',
              english: 'What time does the train leave?',
            ),
          ],
        ),
        SpeakingCourseLesson(
          id: 'speaking_a1_16_platform',
          title: 'Find the platform',
          subtitle: 'Check where your train leaves.',
          level: 'A1',
          icon: Icons.signpost_outlined,
          mode: SpeakingCourseMode.guided,
          lines: [
            SpeakingCourseLine(
              french: 'Quel est le quai ?',
              english: 'Which platform is it?',
            ),
            SpeakingCourseLine(
              french: 'Le quai numéro trois.',
              english: 'Platform number three.',
            ),
            SpeakingCourseLine(
              french: 'Le train est à l’heure ?',
              english: 'Is the train on time?',
            ),
          ],
        ),
        SpeakingCourseLesson(
          id: 'speaking_a1_17_bus',
          title: 'Take the bus',
          subtitle: 'Check the route and stop.',
          level: 'A1',
          icon: Icons.directions_bus_outlined,
          mode: SpeakingCourseMode.guided,
          lines: [
            SpeakingCourseLine(
              french: 'Ce bus va au centre-ville ?',
              english: 'Does this bus go downtown?',
            ),
            SpeakingCourseLine(
              french: 'Où est l’arrêt ?',
              english: 'Where is the stop?',
            ),
            SpeakingCourseLine(
              french: 'Je descends ici.',
              english: 'I get off here.',
            ),
          ],
        ),
        SpeakingCourseLesson(
          id: 'speaking_a1_18_station_roleplay',
          title: 'At the train station',
          subtitle: 'Buy a ticket and find your platform.',
          level: 'A1',
          icon: Icons.train_rounded,
          mode: SpeakingCourseMode.roleplay,
          goal: 'Buy one ticket and confirm the platform.',
          lines: [
            SpeakingCourseLine(
              partnerFrench: 'Bonjour, où allez-vous ?',
              partnerEnglish: 'Hello, where are you going?',
              french: 'Je voudrais un billet pour Lyon.',
              english: 'I would like a ticket to Lyon.',
            ),
            SpeakingCourseLine(
              partnerFrench: 'Aller simple ou aller-retour ?',
              partnerEnglish: 'One way or return?',
              french: 'Aller simple, s’il vous plaît.',
              english: 'One way, please.',
            ),
            SpeakingCourseLine(
              partnerFrench: 'Le train part à dix heures.',
              partnerEnglish: 'The train leaves at ten.',
              french: 'Merci. Quel est le quai ?',
              english: 'Thank you. Which platform is it?',
            ),
          ],
        ),
      ],
    ),
    SpeakingCourseUnit(
      number: 4,
      title: 'Shops and services',
      subtitle: 'Ask for an item, size, and payment.',
      level: 'A2',
      icon: Icons.shopping_bag_outlined,
      lessons: [
        SpeakingCourseLesson(
          id: 'speaking_a2_19_find',
          title: 'Find an item',
          subtitle: 'Explain what you are looking for.',
          level: 'A2',
          icon: Icons.search_rounded,
          mode: SpeakingCourseMode.guided,
          lines: [
            SpeakingCourseLine(
              french: 'Je cherche une chemise bleue.',
              english: 'I am looking for a blue shirt.',
            ),
            SpeakingCourseLine(
              french: 'Vous avez ce modèle ?',
              english: 'Do you have this model?',
            ),
            SpeakingCourseLine(
              french: 'Je peux l’essayer ?',
              english: 'Can I try it on?',
            ),
          ],
        ),
        SpeakingCourseLesson(
          id: 'speaking_a2_20_size',
          title: 'Ask for a size',
          subtitle: 'Find something that fits.',
          level: 'A2',
          icon: Icons.straighten_outlined,
          mode: SpeakingCourseMode.guided,
          lines: [
            SpeakingCourseLine(
              french: 'Vous avez une taille plus grande ?',
              english: 'Do you have a larger size?',
            ),
            SpeakingCourseLine(
              french: 'C’est un peu trop petit.',
              english: 'It is a little too small.',
            ),
            SpeakingCourseLine(
              french: 'Cette taille me va bien.',
              english: 'This size fits me well.',
            ),
          ],
        ),
        SpeakingCourseLesson(
          id: 'speaking_a2_21_compare',
          title: 'Compare two choices',
          subtitle: 'Say which option you prefer.',
          level: 'A2',
          icon: Icons.compare_arrows_rounded,
          mode: SpeakingCourseMode.guided,
          lines: [
            SpeakingCourseLine(
              french: 'Je préfère celui-ci.',
              english: 'I prefer this one.',
            ),
            SpeakingCourseLine(
              french: 'Il est moins cher.',
              english: 'It is less expensive.',
            ),
            SpeakingCourseLine(
              french: 'La couleur me plaît davantage.',
              english: 'I like the color more.',
            ),
          ],
        ),
        SpeakingCourseLesson(
          id: 'speaking_a2_22_return',
          title: 'Return an item',
          subtitle: 'Explain a simple problem.',
          level: 'A2',
          icon: Icons.assignment_return_outlined,
          mode: SpeakingCourseMode.guided,
          lines: [
            SpeakingCourseLine(
              french: 'Je voudrais retourner cet article.',
              english: 'I would like to return this item.',
            ),
            SpeakingCourseLine(
              french: 'Il ne fonctionne pas.',
              english: 'It does not work.',
            ),
            SpeakingCourseLine(
              french: 'J’ai le reçu.',
              english: 'I have the receipt.',
            ),
          ],
        ),
        SpeakingCourseLesson(
          id: 'speaking_a2_23_payment',
          title: 'Pay for a purchase',
          subtitle: 'Choose a payment method.',
          level: 'A2',
          icon: Icons.credit_card_outlined,
          mode: SpeakingCourseMode.guided,
          lines: [
            SpeakingCourseLine(
              french: 'Je vais payer par carte.',
              english: 'I will pay by card.',
            ),
            SpeakingCourseLine(
              french: 'Vous acceptez les espèces ?',
              english: 'Do you accept cash?',
            ),
            SpeakingCourseLine(
              french: 'Je peux avoir le reçu ?',
              english: 'Can I have the receipt?',
            ),
          ],
        ),
        SpeakingCourseLesson(
          id: 'speaking_a2_24_shop_roleplay',
          title: 'At a shop',
          subtitle: 'Find an item and complete the purchase.',
          level: 'A2',
          icon: Icons.storefront_outlined,
          mode: SpeakingCourseMode.roleplay,
          goal: 'Ask for an item, check the size, and pay.',
          lines: [
            SpeakingCourseLine(
              partnerFrench: 'Bonjour, je peux vous aider ?',
              partnerEnglish: 'Hello, can I help you?',
              french: 'Oui, je cherche une chemise bleue.',
              english: 'Yes, I am looking for a blue shirt.',
            ),
            SpeakingCourseLine(
              partnerFrench: 'Quelle taille faites-vous ?',
              partnerEnglish: 'What size are you?',
              french: 'Je fais du médium.',
              english: 'I wear medium.',
            ),
            SpeakingCourseLine(
              partnerFrench: 'Elle coûte trente euros.',
              partnerEnglish: 'It costs thirty euros.',
              french: 'Parfait, je vais payer par carte.',
              english: 'Perfect, I will pay by card.',
            ),
          ],
        ),
      ],
    ),
    SpeakingCourseUnit(
      number: 5,
      title: 'Friends and plans',
      subtitle: 'Talk about your day and make a plan.',
      level: 'A2',
      icon: Icons.people_outline_rounded,
      lessons: [
        SpeakingCourseLesson(
          id: 'speaking_a2_25_day',
          title: 'Talk about your day',
          subtitle: 'Describe three everyday actions.',
          level: 'A2',
          icon: Icons.today_outlined,
          mode: SpeakingCourseMode.guided,
          lines: [
            SpeakingCourseLine(
              french: 'Ce matin, j’ai travaillé.',
              english: 'This morning, I worked.',
            ),
            SpeakingCourseLine(
              french: 'À midi, j’ai déjeuné avec un ami.',
              english: 'At noon, I had lunch with a friend.',
            ),
            SpeakingCourseLine(
              french: 'Ce soir, je vais me reposer.',
              english: 'This evening, I am going to rest.',
            ),
          ],
        ),
        SpeakingCourseLesson(
          id: 'speaking_a2_26_invite',
          title: 'Invite a friend',
          subtitle: 'Suggest one simple activity.',
          level: 'A2',
          icon: Icons.celebration_outlined,
          mode: SpeakingCourseMode.guided,
          lines: [
            SpeakingCourseLine(
              french: 'Tu veux prendre un café ?',
              english: 'Do you want to have a coffee?',
            ),
            SpeakingCourseLine(
              french: 'On peut se retrouver samedi.',
              english: 'We can meet on Saturday.',
            ),
            SpeakingCourseLine(
              french: 'Ça te convient ?',
              english: 'Does that work for you?',
            ),
          ],
        ),
        SpeakingCourseLesson(
          id: 'speaking_a2_27_time',
          title: 'Choose a time',
          subtitle: 'Find a time that works.',
          level: 'A2',
          icon: Icons.schedule_outlined,
          mode: SpeakingCourseMode.guided,
          lines: [
            SpeakingCourseLine(
              french: 'Je suis libre après trois heures.',
              english: 'I am free after three.',
            ),
            SpeakingCourseLine(
              french: 'Quatre heures, c’est parfait.',
              english: 'Four o’clock is perfect.',
            ),
            SpeakingCourseLine(
              french: 'On se retrouve devant le café.',
              english: 'We will meet in front of the café.',
            ),
          ],
        ),
        SpeakingCourseLesson(
          id: 'speaking_a2_28_change',
          title: 'Change a plan',
          subtitle: 'Explain and suggest another time.',
          level: 'A2',
          icon: Icons.event_repeat_outlined,
          mode: SpeakingCourseMode.guided,
          lines: [
            SpeakingCourseLine(
              french: 'Désolé, je ne peux pas venir.',
              english: 'Sorry, I cannot come.',
            ),
            SpeakingCourseLine(
              french: 'Est-ce qu’on peut reporter ?',
              english: 'Can we postpone?',
            ),
            SpeakingCourseLine(
              french: 'Dimanche me convient mieux.',
              english: 'Sunday works better for me.',
            ),
          ],
        ),
        SpeakingCourseLesson(
          id: 'speaking_a2_29_opinion',
          title: 'Share a preference',
          subtitle: 'Give a short reason.',
          level: 'A2',
          icon: Icons.thumb_up_alt_outlined,
          mode: SpeakingCourseMode.guided,
          lines: [
            SpeakingCourseLine(
              french: 'Je préfère ce restaurant.',
              english: 'I prefer this restaurant.',
            ),
            SpeakingCourseLine(
              french: 'L’ambiance est plus calme.',
              english: 'The atmosphere is calmer.',
            ),
            SpeakingCourseLine(
              french: 'Et toi, qu’est-ce que tu préfères ?',
              english: 'And you, what do you prefer?',
            ),
          ],
        ),
        SpeakingCourseLesson(
          id: 'speaking_a2_30_friend_roleplay',
          title: 'Make a plan with a friend',
          subtitle: 'Invite, negotiate, and confirm.',
          level: 'A2',
          icon: Icons.groups_outlined,
          mode: SpeakingCourseMode.roleplay,
          goal: 'Agree on an activity, day, and time.',
          lines: [
            SpeakingCourseLine(
              partnerFrench: 'Tu veux faire quelque chose ce week-end ?',
              partnerEnglish: 'Do you want to do something this weekend?',
              french: 'Oui, on peut prendre un café.',
              english: 'Yes, we can have a coffee.',
            ),
            SpeakingCourseLine(
              partnerFrench: 'Samedi après-midi ?',
              partnerEnglish: 'Saturday afternoon?',
              french: 'Je ne peux pas samedi. Dimanche me convient mieux.',
              english: 'I cannot Saturday. Sunday works better for me.',
            ),
            SpeakingCourseLine(
              partnerFrench: 'D’accord. À quelle heure ?',
              partnerEnglish: 'Okay. What time?',
              french: 'À quatre heures devant le café.',
              english: 'At four in front of the café.',
            ),
          ],
        ),
      ],
    ),
  ];

  static const freeTalkLessons = <SpeakingCourseLesson>[
    SpeakingCourseLesson(
      id: 'speaking_free_day',
      title: 'My day',
      subtitle: 'Answer three short questions about today.',
      level: 'A1',
      icon: Icons.wb_sunny_outlined,
      mode: SpeakingCourseMode.freeTalk,
      lines: [
        SpeakingCourseLine(
          partnerFrench: 'Comment ça va aujourd’hui ?',
          partnerEnglish: 'How are you today?',
          french: 'Aujourd’hui, ça va…',
          english: 'Today, I feel…',
          openResponse: true,
        ),
        SpeakingCourseLine(
          partnerFrench: 'Qu’est-ce que vous faites ce matin ?',
          partnerEnglish: 'What are you doing this morning?',
          french: 'Ce matin, je…',
          english: 'This morning, I…',
          openResponse: true,
        ),
        SpeakingCourseLine(
          partnerFrench: 'Et ce soir ?',
          partnerEnglish: 'And this evening?',
          french: 'Ce soir, je vais…',
          english: 'This evening, I am going to…',
          openResponse: true,
        ),
      ],
    ),
    SpeakingCourseLesson(
      id: 'speaking_free_food',
      title: 'Food I like',
      subtitle: 'Talk about a meal or drink you enjoy.',
      level: 'A1',
      icon: Icons.restaurant_menu_rounded,
      mode: SpeakingCourseMode.freeTalk,
      lines: [
        SpeakingCourseLine(
          partnerFrench: 'Qu’est-ce que vous aimez manger ?',
          partnerEnglish: 'What do you like to eat?',
          french: 'J’aime manger…',
          english: 'I like to eat…',
          openResponse: true,
        ),
        SpeakingCourseLine(
          partnerFrench: 'Pourquoi ?',
          partnerEnglish: 'Why?',
          french: 'Parce que c’est…',
          english: 'Because it is…',
          openResponse: true,
        ),
        SpeakingCourseLine(
          partnerFrench: 'Vous cuisinez souvent ?',
          partnerEnglish: 'Do you cook often?',
          french: 'Je cuisine…',
          english: 'I cook…',
          openResponse: true,
        ),
      ],
    ),
    SpeakingCourseLesson(
      id: 'speaking_free_weekend',
      title: 'Weekend plans',
      subtitle: 'Say what you want to do next.',
      level: 'A2',
      icon: Icons.weekend_outlined,
      mode: SpeakingCourseMode.freeTalk,
      lines: [
        SpeakingCourseLine(
          partnerFrench: 'Qu’est-ce que vous allez faire ce week-end ?',
          partnerEnglish: 'What are you going to do this weekend?',
          french: 'Ce week-end, je vais…',
          english: 'This weekend, I am going to…',
          openResponse: true,
        ),
        SpeakingCourseLine(
          partnerFrench: 'Avec qui ?',
          partnerEnglish: 'With whom?',
          french: 'Je vais y aller avec…',
          english: 'I am going with…',
          openResponse: true,
        ),
        SpeakingCourseLine(
          partnerFrench: 'Pourquoi cette activité ?',
          partnerEnglish: 'Why this activity?',
          french: 'J’ai choisi cette activité parce que…',
          english: 'I chose this activity because…',
          openResponse: true,
        ),
      ],
    ),
    SpeakingCourseLesson(
      id: 'speaking_free_city',
      title: 'My city',
      subtitle: 'Describe one place you know.',
      level: 'A2',
      icon: Icons.location_city_outlined,
      mode: SpeakingCourseMode.freeTalk,
      lines: [
        SpeakingCourseLine(
          partnerFrench: 'Où habitez-vous ?',
          partnerEnglish: 'Where do you live?',
          french: 'J’habite à…',
          english: 'I live in…',
          openResponse: true,
        ),
        SpeakingCourseLine(
          partnerFrench: 'Qu’est-ce que vous aimez dans votre ville ?',
          partnerEnglish: 'What do you like about your city?',
          french: 'J’aime…',
          english: 'I like…',
          openResponse: true,
        ),
        SpeakingCourseLine(
          partnerFrench: 'Quel endroit conseillez-vous ?',
          partnerEnglish: 'What place do you recommend?',
          french: 'Je conseille…',
          english: 'I recommend…',
          openResponse: true,
        ),
      ],
    ),
  ];

  static List<SpeakingCourseLesson> get roleplays => [
    for (final unit in units)
      for (final lesson in unit.lessons)
        if (lesson.mode == SpeakingCourseMode.roleplay) lesson,
  ];
}
