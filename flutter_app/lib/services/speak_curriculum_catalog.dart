import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/speak_curriculum.dart';

/// Reads the shared, published curriculum. The bundled catalog is an
/// intentional offline fallback and also gives fresh installs a complete path
/// while a remote catalog is being rolled out.
class SpeakCurriculumRepository {
  const SpeakCurriculumRepository();

  Future<List<SpeakCurriculumItem>> loadPublished(String rawLevel) async {
    final level = _normaliseLevel(rawLevel);
    try {
      final rows = await Supabase.instance.client
          .from('course_sessions')
          .select()
          .eq('level', level)
          .eq('published', true)
          .order('session_index');
      final remote = rows
          .map(
            (row) => SpeakCurriculumItem.fromJson(
              Map<String, dynamic>.from(row as Map),
            ),
          )
          .toList(growable: false);
      if (isValid(remote, level)) return _withA1Foundation(remote, level);
    } catch (_) {
      // A missing table, offline start, or an unauthenticated client should
      // never make the course unusable. The next app update can still ship a
      // new bundled catalog while the migration is deployed.
    }
    try {
      final raw = await rootBundle.loadString(
        'assets/content/speak_course_catalog.json',
      );
      final decoded = jsonDecode(raw);
      final rows = decoded is Map ? decoded['sessions'] : null;
      if (rows is List) {
        final bundledDraft = rows
            .whereType<Map>()
            .map(
              (row) =>
                  SpeakCurriculumItem.fromJson(Map<String, dynamic>.from(row)),
            )
            .where((item) => item.level == level)
            .toList(growable: false);
        if (isValid(bundledDraft, level)) {
          return _withA1Foundation(bundledDraft, level);
        }
      }
    } catch (_) {
      // The generated asset is optional. Keep the deterministic fallback.
    }
    return _withA1Foundation(SpeakCurriculumCatalog.bundled(level), level);
  }

  static bool isValid(List<SpeakCurriculumItem> items, String level) {
    final expectedCount = switch (level) {
      'A1' => 120,
      'A2' => 140,
      'B1' => 160,
      'B2' => 200,
      _ => 0,
    };
    if (items.length != expectedCount) return false;
    final keys = <String>{};
    for (final item in items) {
      if (item.level != level || !keys.add(item.contentKey)) return false;
      if (item.unit < 1 || item.title.trim().isEmpty) return false;
      if (item.sessionKind == SpeakSessionKind.roleplay &&
          item.roleplay == null) {
        return false;
      }
    }
    return true;
  }

  static String _normaliseLevel(String rawLevel) =>
      switch (rawLevel.toLowerCase()) {
        'a1' || 'zero' || 'basics' => 'A1',
        'a2' => 'A2',
        'b1' || 'conversational' => 'B1',
        'b2' => 'B2',
        _ => 'A1',
      };

  /// Keep the first A1 unit aligned even while an older Supabase/catalog
  /// payload is still deployed, and apply lighter pacing to A1/A2. This is
  /// deliberately content-key-preserving: progress remains attached to the
  /// same course sessions.
  static List<SpeakCurriculumItem> _withA1Foundation(
    List<SpeakCurriculumItem> items,
    String level,
  ) {
    return items
        .map((item) {
          final isFoundation =
              level == 'A1' && item.unit == 1 && item.sessionIndex <= 2;
          final foundation = switch (item.sessionIndex) {
            0 => (
              'Meet the French alphabet',
              'Learn the 26 letters and how their names sound.',
            ),
            1 => (
              'Master French vowels',
              'Practise A, E, I, O, U, and Y in simple words.',
            ),
            _ => (
              'Consonants and alphabet review',
              'Revisit tricky consonants, then check your recall.',
            ),
          };
          final pacedMinutes = _pacedMinutes(
            item.estimatedMinutes,
            level,
            item.kind,
          );
          if (!isFoundation && pacedMinutes == item.estimatedMinutes) {
            return item;
          }
          return SpeakCurriculumItem(
            contentKey: item.contentKey,
            level: item.level,
            unit: item.unit,
            unitTitle: item.unitTitle,
            sessionIndex: item.sessionIndex,
            title: isFoundation ? foundation.$1 : item.title,
            subtitle: isFoundation ? foundation.$2 : item.subtitle,
            kind: isFoundation ? 'lesson' : item.kind,
            estimatedMinutes: pacedMinutes,
            targetPhrases: isFoundation
                ? _foundationTargetPhrases(item.sessionIndex)
                : item.targetPhrases,
            roleplay: item.roleplay,
            explicitPrimarySkill: isFoundation
                ? SpeakSkill.alphabet
                : item.explicitPrimarySkill,
            explicitSupportingSkills: item.explicitSupportingSkills,
          );
        })
        .toList(growable: false);
  }

  static List<String> _foundationTargetPhrases(int sessionIndex) =>
      switch (sessionIndex) {
        0 => const ['bonjour', 'ami', 'chat', 'demain', 'fromage'],
        1 => const ['ami', 'papa', 'été', 'ici', 'où', 'lune'],
        _ => const ['chat', 'bonjour', 'fromage', 'demain', 'rue'],
      };

  static int _pacedMinutes(int current, String level, String kind) {
    final cap = switch (level) {
      'A1' => switch (kind.toLowerCase()) {
        'roleplay' => 7,
        'story' => 6,
        'review' => 5,
        _ => 5,
      },
      'A2' => switch (kind.toLowerCase()) {
        'roleplay' => 8,
        'story' => 7,
        'review' => 6,
        _ => 6,
      },
      _ => current,
    };
    return current > cap ? cap : current;
  }
}

/// Curated seed content used until the published Supabase catalog is present.
/// Unlike the old roadmap, titles and scenes are derived from each unit's
/// actual learning focus, so Unit 1 is not copied into Unit 2, Unit 3, etc.
abstract final class SpeakCurriculumCatalog {
  static List<SpeakCurriculumItem> bundled(String level) {
    final cefr = _normaliseLevel(level);
    final units = _units[cefr] ?? _units['A1']!;
    final items = <SpeakCurriculumItem>[];
    var sessionIndex = 0;
    for (var unitIndex = 0; unitIndex < units.length; unitIndex++) {
      final unit = units[unitIndex];
      final sceneA = _scene(
        cefr,
        unitIndex,
        unit,
        variant: 'A',
        title: unit.sceneA,
      );
      final sceneB = _scene(
        cefr,
        unitIndex,
        unit,
        variant: 'B',
        title: unit.sceneB,
      );
      final lessons = [
        _item(
          cefr,
          unitIndex,
          unit,
          0,
          unitIndex == 0 ? 'Meet the French alphabet' : 'Notice ${unit.focus}',
          unitIndex == 0
              ? 'Learn the 26 letters and how their names sound.'
              : 'See the useful language before you speak.',
          unitIndex == 0 ? 'lesson' : 'video',
          primarySkill: unitIndex == 0 ? SpeakSkill.alphabet : null,
        ),
        _item(
          cefr,
          unitIndex,
          unit,
          1,
          unitIndex == 0
              ? 'Master French vowels'
              : '${unit.title}: build your response',
          unitIndex == 0
              ? 'Practise A, E, I, O, U, and Y in simple words.'
              : 'Shape a clear answer for this real moment.',
          unitIndex == 0 ? 'lesson' : 'speaking',
          primarySkill: unitIndex == 0 ? SpeakSkill.alphabet : null,
        ),
        _item(
          cefr,
          unitIndex,
          unit,
          2,
          unitIndex == 0
              ? 'Consonants and alphabet review'
              : '${unit.title}: listen for the detail',
          unitIndex == 0
              ? 'Revisit tricky consonants, then check your recall.'
              : 'Catch the words that change the meaning.',
          unitIndex == 0 ? 'lesson' : 'video',
          primarySkill: unitIndex == 0 ? SpeakSkill.alphabet : null,
        ),
        _item(
          cefr,
          unitIndex,
          unit,
          3,
          '${unit.title}: use it in context',
          'Turn the new language into a natural exchange.',
          'speaking',
        ),
        _item(
          cefr,
          unitIndex,
          unit,
          4,
          '${unit.title}: tell the story',
          'Connect a few ideas in your own words.',
          'story',
        ),
        _item(
          cefr,
          unitIndex,
          unit,
          5,
          '${unit.title}: make the choice',
          'Ask, respond, and move the moment forward.',
          'speaking',
        ),
        _item(
          cefr,
          unitIndex,
          unit,
          6,
          'Roleplay: ${sceneA.title}',
          sceneA.subtitle,
          'roleplay',
          roleplay: sceneA,
        ),
        _item(
          cefr,
          unitIndex,
          unit,
          7,
          'Review ${unit.focus.toLowerCase()} · ${unit.title}',
          'Bring the most useful phrases back.',
          'review',
        ),
        _item(
          cefr,
          unitIndex,
          unit,
          8,
          '${unit.title}: say more about it',
          'Add a reason, example, or personal detail.',
          'speaking',
        ),
        _item(
          cefr,
          unitIndex,
          unit,
          9,
          'Roleplay: ${sceneB.title}',
          sceneB.subtitle,
          'roleplay',
          roleplay: sceneB,
        ),
      ];
      for (final lesson in lessons) {
        items.add(lesson.copyWith(sessionIndex: sessionIndex++));
      }
    }
    return items;
  }

  static SpeakCurriculumItem _item(
    String level,
    int unitIndex,
    _Unit unit,
    int slot,
    String title,
    String subtitle,
    String kind, {
    SpeakRoleplayScene? roleplay,
    SpeakSkill? primarySkill,
    List<SpeakSkill> supportingSkills = const [],
  }) {
    return SpeakCurriculumItem(
      contentKey:
          '${level.toLowerCase()}_u${(unitIndex + 1).toString().padLeft(2, '0')}_s${(slot + 1).toString().padLeft(2, '0')}',
      level: level,
      unit: unitIndex + 1,
      unitTitle: unit.title,
      sessionIndex: slot,
      title: title,
      subtitle: subtitle,
      kind: kind,
      estimatedMinutes: _bundledMinutes(level, kind),
      targetPhrases: unit.phrases,
      roleplay: roleplay,
      explicitPrimarySkill: primarySkill,
      explicitSupportingSkills: supportingSkills,
    );
  }

  static int _bundledMinutes(String level, String kind) {
    final defaultMinutes = switch (kind) {
      'review' => 6,
      'roleplay' => 10,
      'story' => 8,
      _ => 7,
    };
    return _pacedMinutes(defaultMinutes, level, kind);
  }

  static int _pacedMinutes(int current, String level, String kind) {
    final cap = switch (level) {
      'A1' => switch (kind.toLowerCase()) {
        'roleplay' => 7,
        'story' => 6,
        'review' => 5,
        _ => 5,
      },
      'A2' => switch (kind.toLowerCase()) {
        'roleplay' => 8,
        'story' => 7,
        'review' => 6,
        _ => 6,
      },
      _ => current,
    };
    return current > cap ? cap : current;
  }

  static SpeakRoleplayScene _scene(
    String level,
    int unitIndex,
    _Unit unit, {
    required String variant,
    required String title,
  }) {
    final id =
        '${level.toLowerCase()}_u${unitIndex + 1}_roleplay_${variant.toLowerCase()}';
    final role = variant == 'A' ? unit.learnerRoleA : unit.learnerRoleB;
    final tutorRole = variant == 'A' ? unit.tutorRoleA : unit.tutorRoleB;
    final goal = variant == 'A' ? unit.goalA : unit.goalB;
    return SpeakRoleplayScene(
      id: id,
      level: level,
      title: title,
      subtitle: variant == 'A' ? unit.sceneSubtitleA : unit.sceneSubtitleB,
      location: unit.location,
      learnerRole: role,
      tutorRole: tutorRole,
      goal: goal,
      openingLine: variant == 'A' ? unit.openingA : unit.openingB,
      targetPhrases: unit.phrases,
    );
  }

  static String _normaliseLevel(String rawLevel) =>
      switch (rawLevel.toLowerCase()) {
        'a1' || 'zero' || 'basics' => 'A1',
        'a2' => 'A2',
        'b1' || 'conversational' => 'B1',
        'b2' => 'B2',
        _ => 'A1',
      };

  static const _units = <String, List<_Unit>>{
    'A1': [
      _Unit(
        'The first words',
        'Greetings and names',
        'Meet a new neighbour',
        'At the bakery',
        'street corner',
        'new neighbour',
        'shopkeeper',
        'customer',
        'bakery clerk',
        'say hello and introduce yourself',
        'buy one simple item',
        'Bonjour, je m’appelle…',
        'Bonjour, qu’est-ce qu’il vous faut ?',
      ),
      _Unit(
        'About me',
        'Personal information',
        'A new classmate',
        'At the registration desk',
        'community centre',
        'new student',
        'administrator',
        'visitor',
        'receptionist',
        'share your name and where you are from',
        'give your basic details',
        'Enchanté, je suis…',
        'Bienvenue. Comment vous appelez-vous ?',
      ),
      _Unit(
        'Daily routines',
        'Time and everyday actions',
        'Plan a morning together',
        'Call about an appointment',
        'neighbourhood',
        'friend',
        'friend',
        'caller',
        'receptionist',
        'say what you do today',
        'book a simple time',
        'Je commence à…',
        'Bonjour, je peux vous aider ?',
      ),
      _Unit(
        'Food and cafés',
        'Food and polite requests',
        'Order breakfast',
        'Ask about a menu',
        'small café',
        'customer',
        'server',
        'customer',
        'server',
        'order a drink and a pastry',
        'ask what is available',
        'Je voudrais…, s’il vous plaît.',
        'Bonjour, vous désirez ?',
      ),
      _Unit(
        'Getting around',
        'Places and directions',
        'Find the station',
        'Buy a metro ticket',
        'city centre',
        'traveller',
        'local resident',
        'traveller',
        'ticket agent',
        'ask where a place is',
        'buy the right ticket',
        'Où est… ?',
        'Vous allez où ?',
      ),
      _Unit(
        'Shopping basics',
        'Numbers and choices',
        'Choose a gift',
        'Return an item',
        'neighbourhood shop',
        'customer',
        'shop assistant',
        'customer',
        'cashier',
        'ask the price and choose a colour',
        'explain a simple problem',
        'Combien ça coûte ?',
        'Qu’est-ce que vous cherchez ?',
      ),
      _Unit(
        'Home and time',
        'Rooms, objects, and schedules',
        'Show your apartment',
        'Call the building manager',
        'apartment building',
        'new tenant',
        'friend',
        'tenant',
        'manager',
        'describe one room',
        'report a small issue',
        'Il y a…',
        'Bonjour, quel est le problème ?',
      ),
      _Unit(
        'Making plans',
        'Invitations and future plans',
        'Invite a friend out',
        'Change a plan',
        'city neighbourhood',
        'friend',
        'friend',
        'caller',
        'friend',
        'suggest an easy activity',
        'move the meeting to another time',
        'Tu veux venir… ?',
        'D’accord, à quelle heure ?',
      ),
      _Unit(
        'Health and help',
        'Body and basic needs',
        'Ask for help',
        'Speak at a pharmacy',
        'local pharmacy',
        'visitor',
        'pharmacist',
        'customer',
        'pharmacist',
        'explain a simple need',
        'ask for a common product',
        'J’ai besoin de…',
        'Depuis quand ?',
      ),
      _Unit(
        'Work and study',
        'Simple descriptions',
        'Meet a colleague',
        'Ask about a class',
        'school or workplace',
        'new colleague',
        'colleague',
        'student',
        'teacher',
        'say what you do',
        'ask one useful question',
        'Je travaille / j’étudie…',
        'Vous avez une question ?',
      ),
      _Unit(
        'Travel moments',
        'Hotels and transport',
        'Check into a hotel',
        'Ask about the train',
        'travel desk',
        'traveller',
        'hotel clerk',
        'traveller',
        'station agent',
        'give your name and reservation',
        'find the platform',
        'J’ai une réservation.',
        'Vous avez le numéro ?',
      ),
      _Unit(
        'First conversations',
        'Keeping a conversation going',
        'Talk about your weekend',
        'Say goodbye naturally',
        'friendly gathering',
        'guest',
        'new friend',
        'visitor',
        'host',
        'answer two simple questions',
        'close a friendly exchange',
        'C’était très bien.',
        'Vous avez passé un bon week-end ?',
      ),
    ],
    'A2': [
      _Unit(
        'Everyday confidence',
        'Routines and preferences',
        'Plan a busy morning',
        'Choose a breakfast',
        'neighbourhood café',
        'customer',
        'server',
        'friend',
        'server',
        'explain your routine and preference',
        'adapt your order',
        'Je préfère… parce que…',
        'Vous prenez toujours la même chose ?',
      ),
      _Unit(
        'Your routine',
        'Frequency and habits',
        'Compare your weeks',
        'Reschedule an appointment',
        'shared office',
        'colleague',
        'colleague',
        'client',
        'receptionist',
        'describe habits and timing',
        'give a reason for changing plans',
        'D’habitude, je…',
        'Quel horaire vous conviendrait ?',
      ),
      _Unit(
        'People and places',
        'Descriptions and comparisons',
        'Recommend a neighbourhood',
        'Describe a flat',
        'city street',
        'local guide',
        'visitor',
        'tenant',
        'renter',
        'compare two places',
        'explain what you are looking for',
        'C’est plus… que…',
        'Qu’est-ce qui est important pour vous ?',
      ),
      _Unit(
        'Food and choices',
        'Quantities and preferences',
        'Order for a group',
        'Ask about ingredients',
        'restaurant',
        'customer',
        'server',
        'customer',
        'server',
        'order several things politely',
        'check an ingredient',
        'Pour nous, il faudrait…',
        'Vous avez une préférence ?',
      ),
      _Unit(
        'Travel smoothly',
        'Past travel and directions',
        'Solve a travel delay',
        'Ask at a hotel',
        'train station',
        'traveller',
        'agent',
        'guest',
        'hotel clerk',
        'explain what happened',
        'find a practical solution',
        'Le train a été…',
        'Qu’est-ce qui s’est passé ?',
      ),
      _Unit(
        'Plans and invitations',
        'Suggestions and agreement',
        'Organise a day trip',
        'Accept or decline politely',
        'town square',
        'organiser',
        'friend',
        'guest',
        'host',
        'suggest a plan with a reason',
        'respond naturally',
        'On pourrait…',
        'Ça me ferait plaisir.',
      ),
      _Unit(
        'Past moments',
        'Narrating recent events',
        'Tell a funny story',
        'Explain a missed call',
        'friendly café',
        'storyteller',
        'friend',
        'caller',
        'friend',
        'tell events in order',
        'clarify what happened',
        'D’abord…, ensuite…',
        'Pourquoi tu n’as pas répondu ?',
      ),
      _Unit(
        'Future projects',
        'Intentions and predictions',
        'Discuss a weekend project',
        'Make a reservation',
        'community centre',
        'volunteer',
        'coordinator',
        'customer',
        'booking agent',
        'describe an intention',
        'reserve a time and place',
        'J’aimerais…',
        'Pour quelle date ?',
      ),
      _Unit(
        'Work and study',
        'Explaining tasks',
        'Ask for instructions',
        'Give a progress update',
        'workplace',
        'new employee',
        'manager',
        'student',
        'teacher',
        'ask for clarification',
        'say what is finished',
        'Vous pouvez m’expliquer… ?',
        'Où en êtes-vous ?',
      ),
      _Unit(
        'Health and wellbeing',
        'Advice and symptoms',
        'Describe a small problem',
        'Ask for advice',
        'clinic waiting room',
        'patient',
        'nurse',
        'customer',
        'pharmacist',
        'describe how you feel',
        'understand simple advice',
        'Je ne me sens pas…',
        'Il vaut mieux…',
      ),
      _Unit(
        'Social French',
        'Inviting and reacting',
        'Join a conversation',
        'Host a dinner',
        'shared meal',
        'guest',
        'host',
        'host',
        'guest',
        'react to a topic and ask back',
        'welcome someone and offer food',
        'Et toi, qu’est-ce que tu en penses ?',
        'Servez-vous !',
      ),
      _Unit(
        'Independent errands',
        'Problems and solutions',
        'Fix a delivery problem',
        'Exchange a purchase',
        'local shop',
        'customer',
        'clerk',
        'customer',
        'clerk',
        'explain a problem politely',
        'negotiate a simple solution',
        'Il y a un problème avec…',
        'On peut trouver une solution.',
      ),
      _Unit(
        'Opinions',
        'Reasons and preferences',
        'Discuss a film',
        'Recommend a book',
        'small bookshop',
        'reader',
        'friend',
        'customer',
        'bookseller',
        'give a short opinion with a reason',
        'make a recommendation',
        'À mon avis…',
        'Qu’est-ce que vous recommandez ?',
      ),
      _Unit(
        'Stories and memories',
        'Sequencing and detail',
        'Describe a memorable day',
        'Ask a follow-up',
        'family gathering',
        'guest',
        'relative',
        'listener',
        'friend',
        'tell a short personal story',
        'keep someone talking',
        'Je me souviens de…',
        'Et après ?',
      ),
    ],
    'B1': [
      _Unit(
        'Tell your story',
        'Narrative detail',
        'Share a turning point',
        'Interview a neighbour',
        'community event',
        'speaker',
        'listener',
        'interviewer',
        'resident',
        'tell a clear story with context',
        'ask thoughtful follow-ups',
        'Ce qui m’a marqué, c’est…',
        'Qu’est-ce qui vous a amené ici ?',
      ),
      _Unit(
        'Explain your choices',
        'Reasons and trade-offs',
        'Choose between two options',
        'Defend a preference',
        'planning meeting',
        'decision maker',
        'colleague',
        'participant',
        'colleague',
        'compare options and justify one',
        'challenge a reason respectfully',
        'D’un côté…, de l’autre…',
        'Qu’est-ce qui vous fait choisir cela ?',
      ),
      _Unit(
        'Work with others',
        'Collaboration and clarity',
        'Lead a short meeting',
        'Clarify responsibilities',
        'team workspace',
        'team lead',
        'colleague',
        'team member',
        'manager',
        'set an agenda and invite input',
        'confirm responsibilities',
        'L’objectif de la réunion est…',
        'Qui s’occupe de quoi ?',
      ),
      _Unit(
        'Solve real problems',
        'Negotiation and repair',
        'Handle a service issue',
        'Find a compromise',
        'service counter',
        'customer',
        'agent',
        'neighbour',
        'neighbour',
        'describe impact and request action',
        'propose a fair compromise',
        'Ce qui me pose problème, c’est…',
        'Quelle solution vous semblerait acceptable ?',
      ),
      _Unit(
        'Travel with nuance',
        'Unexpected situations',
        'Change a travel plan',
        'Explain a delay',
        'station office',
        'traveller',
        'agent',
        'passenger',
        'staff member',
        'explain a constraint and negotiate',
        'give a precise update',
        'Malheureusement, il faudrait…',
        'Si j’ai bien compris…',
      ),
      _Unit(
        'Media and culture',
        'Summaries and reactions',
        'Discuss a documentary',
        'Recommend an exhibition',
        'museum café',
        'visitor',
        'friend',
        'visitor',
        'curator',
        'summarise an idea and react',
        'recommend something with context',
        'Ce qui ressort du film…',
        'Qu’est-ce qui vous a plu ?',
      ),
      _Unit(
        'Learning and growth',
        'Goals and reflection',
        'Reflect on a challenge',
        'Ask for feedback',
        'language workshop',
        'learner',
        'mentor',
        'colleague',
        'coach',
        'describe progress and next steps',
        'ask for concrete feedback',
        'J’ai eu du mal à…',
        'Sur quoi devrais-je me concentrer ?',
      ),
      _Unit(
        'Relationships and society',
        'Agreement and disagreement',
        'Discuss a local issue',
        'Keep a disagreement calm',
        'community forum',
        'participant',
        'moderator',
        'resident',
        'resident',
        'state a view and acknowledge another',
        'disagree without closing the exchange',
        'Je comprends votre point de vue, mais…',
        'Qu’est-ce qui vous fait dire cela ?',
      ),
      _Unit(
        'The world of work',
        'Professional communication',
        'Give a project update',
        'Handle a customer call',
        'office meeting',
        'project owner',
        'manager',
        'representative',
        'client',
        'explain status, risk, and next step',
        'respond clearly under pressure',
        'Le point principal à retenir…',
        'Quel serait le meilleur moyen de… ?',
      ),
      _Unit(
        'Health and balance',
        'Advice and boundaries',
        'Discuss a healthy habit',
        'Ask for practical advice',
        'wellness centre',
        'client',
        'coach',
        'patient',
        'doctor',
        'describe a goal and constraint',
        'ask for realistic options',
        'J’essaie de… sans…',
        'Qu’est-ce qui serait faisable pour vous ?',
      ),
      _Unit(
        'Ideas and evidence',
        'Examples and explanation',
        'Explain a useful idea',
        'Ask for evidence',
        'study group',
        'presenter',
        'listener',
        'student',
        'teacher',
        'support an idea with examples',
        'ask for clarification and evidence',
        'Par exemple…, ce qui montre que…',
        'Sur quoi vous basez-vous ?',
      ),
      _Unit(
        'Debate with care',
        'Counterarguments',
        'Discuss a policy',
        'Respond to an objection',
        'public discussion',
        'speaker',
        'moderator',
        'participant',
        'participant',
        'make a nuanced argument',
        'answer an objection directly',
        'On pourrait objecter que…',
        'Je vois le risque, cependant…',
      ),
      _Unit(
        'Stories that persuade',
        'Structure and emphasis',
        'Pitch a community project',
        'Tell the origin story',
        'local association',
        'organiser',
        'partner',
        'founder',
        'visitor',
        'make a story lead to a request',
        'explain why the project matters',
        'L’idée est née quand…',
        'Quel changement voulez-vous obtenir ?',
      ),
      _Unit(
        'Change and uncertainty',
        'Hypotheses and conditions',
        'Plan around uncertainty',
        'Discuss a possible move',
        'shared office',
        'planner',
        'colleague',
        'tenant',
        'advisor',
        'describe conditions and consequences',
        'explore a possibility carefully',
        'Si jamais…, il faudrait…',
        'Qu’est-ce qui dépend de vous ?',
      ),
      _Unit(
        'Community and belonging',
        'Identity and inclusion',
        'Welcome a newcomer',
        'Discuss a local tradition',
        'neighbourhood festival',
        'volunteer',
        'new resident',
        'resident',
        'organiser',
        'make someone feel included',
        'explain a practice with context',
        'N’hésitez pas à…',
        'Comment avez-vous vécu votre arrivée ?',
      ),
      _Unit(
        'Your French voice',
        'Fluency and style',
        'Tell a personal opinion',
        'Speak with more precision',
        'recording studio',
        'speaker',
        'coach',
        'speaker',
        'coach',
        'express a personal view naturally',
        'refine tone and precision',
        'Ce que je veux surtout dire, c’est…',
        'Comment pourriez-vous le formuler autrement ?',
      ),
    ],
    'B2': [
      _Unit(
        'Precision and nuance',
        'Subtle distinctions',
        'Refine a proposal',
        'Clarify a delicate point',
        'strategy meeting',
        'lead',
        'advisor',
        'speaker',
        'editor',
        'state a precise position with nuance',
        'challenge wording without derailing',
        'La distinction essentielle serait…',
        'Quelle nuance voulez-vous conserver ?',
      ),
      _Unit(
        'Complex opinions',
        'Qualification and balance',
        'Discuss a contested idea',
        'Moderate a panel',
        'cultural centre',
        'panellist',
        'moderator',
        'moderator',
        'panellist',
        'qualify a strong opinion',
        'keep multiple views visible',
        'Il faut toutefois distinguer…',
        'Comment éviter de simplifier la question ?',
      ),
      _Unit(
        'Professional presence',
        'Tone and authority',
        'Present a recommendation',
        'Push back diplomatically',
        'boardroom',
        'presenter',
        'director',
        'consultant',
        'client',
        'recommend a course of action',
        'disagree while preserving trust',
        'Je recommanderais plutôt de…',
        'Qu’est-ce qui vous ferait changer d’avis ?',
      ),
      _Unit(
        'Negotiation',
        'Interests and concessions',
        'Renegotiate an agreement',
        'Resolve a conflict',
        'contract meeting',
        'negotiator',
        'partner',
        'mediator',
        'colleague',
        'identify interests and propose terms',
        'make a measured concession',
        'À condition que…, nous pourrions…',
        'Quelle marge de manœuvre avez-vous ?',
      ),
      _Unit(
        'Public life',
        'Institutions and impact',
        'Question a public decision',
        'Speak at a town hall',
        'town hall',
        'resident',
        'official',
        'resident',
        'chairperson',
        'explain impact and request accountability',
        'answer public concerns precisely',
        'Les conséquences concrètes seraient…',
        'Comment comptez-vous mesurer cela ?',
      ),
      _Unit(
        'Culture and interpretation',
        'Implicit meaning',
        'Interpret a review',
        'Discuss artistic intent',
        'gallery opening',
        'critic',
        'artist',
        'visitor',
        'artist',
        'infer and defend an interpretation',
        'explain an intention without overclaiming',
        'On peut lire cette œuvre comme…',
        'Qu’est-ce qui vous permet de l’affirmer ?',
      ),
      _Unit(
        'Research and evidence',
        'Synthesis and limits',
        'Summarise competing findings',
        'Question a conclusion',
        'research seminar',
        'researcher',
        'audience member',
        'reviewer',
        'researcher',
        'synthesise evidence and limits',
        'ask a rigorous follow-up',
        'Les données tendent à montrer…',
        'Quelle est la limite principale ?',
      ),
      _Unit(
        'Leadership and feedback',
        'Coaching and candour',
        'Give difficult feedback',
        'Ask for a revision',
        'team review',
        'manager',
        'colleague',
        'author',
        'editor',
        'be direct without being abrupt',
        'request a specific improvement',
        'Ce qui fonctionne, en revanche…',
        'Quelle modification aurait le plus d’impact ?',
      ),
      _Unit(
        'Media literacy',
        'Framing and credibility',
        'Analyse a news claim',
        'Challenge a headline',
        'newsroom',
        'editor',
        'reporter',
        'reader',
        'journalist',
        'separate fact, framing, and inference',
        'question a source responsibly',
        'Il convient de vérifier si…',
        'Qu’est-ce qui manque au contexte ?',
      ),
      _Unit(
        'Ethics in practice',
        'Principles and consequences',
        'Discuss a difficult choice',
        'Explore a trade-off',
        'ethics workshop',
        'participant',
        'facilitator',
        'participant',
        'facilitator',
        'state a principle and its cost',
        'explore consequences without preaching',
        'Le dilemme tient au fait que…',
        'Quel principe privilégiez-vous ici ?',
      ),
      _Unit(
        'Long-form storytelling',
        'Pacing and emphasis',
        'Tell a formative story',
        'Interview a public figure',
        'podcast studio',
        'guest',
        'host',
        'host',
        'guest',
        'structure a compelling account',
        'follow the thread with precision',
        'Avec le recul, je dirais que…',
        'À quel moment votre perspective a-t-elle changé ?',
      ),
      _Unit(
        'Strategic choices',
        'Scenarios and risk',
        'Compare strategic options',
        'Recommend a fallback',
        'planning room',
        'strategist',
        'executive',
        'advisor',
        'client',
        'weigh risk, cost, and opportunity',
        'propose a credible alternative',
        'Le scénario le plus plausible…',
        'Que ferions-nous si cette hypothèse échouait ?',
      ),
      _Unit(
        'Relationships and boundaries',
        'Register and empathy',
        'Handle a sensitive request',
        'Repair a misunderstanding',
        'quiet café',
        'friend',
        'friend',
        'colleague',
        'colleague',
        'set a boundary while staying warm',
        'repair trust with careful language',
        'Je préfère être transparent sur…',
        'Comment puis-je clarifier ce que j’ai voulu dire ?',
      ),
      _Unit(
        'Language and identity',
        'Register and belonging',
        'Discuss how language shifts',
        'Explain a phrase’s tone',
        'language event',
        'speaker',
        'listener',
        'teacher',
        'learner',
        'explain register and identity',
        'make a fine-grained comparison',
        'Cela sonne plus… que…',
        'Dans quel contexte l’emploieriez-vous ?',
      ),
      _Unit(
        'Independent judgement',
        'Synthesis and decision',
        'Make a final recommendation',
        'Defend a measured conclusion',
        'advisory meeting',
        'advisor',
        'client',
        'chair',
        'committee member',
        'synthesise and decide',
        'defend a conclusion with limits',
        'En définitive, je retiendrais…',
        'Quelles réserves devons-nous garder ?',
      ),
      _Unit(
        'French in the wild',
        'Spontaneous adaptation',
        'Navigate an unexpected moment',
        'Keep a complex exchange moving',
        'busy city street',
        'traveller',
        'local',
        'visitor',
        'local guide',
        'adapt naturally to new information',
        'maintain clarity under pressure',
        'Dans ce cas, je vais plutôt…',
        'Très bien, reprenons depuis le début.',
      ),
      _Unit(
        'Professional French',
        'Meetings and decisions',
        'Lead a decision meeting',
        'Write the next step aloud',
        'project office',
        'chairperson',
        'team',
        'project lead',
        'stakeholder',
        'move from discussion to action',
        'confirm ownership and deadlines',
        'Pour avancer, je propose que…',
        'Qui prend le relais et quand ?',
      ),
      _Unit(
        'Culture and context',
        'Allusion and background',
        'Explain a cultural reference',
        'Compare perspectives',
        'book festival',
        'speaker',
        'visitor',
        'visitor',
        'author',
        'make context accessible without flattening it',
        'compare interpretations respectfully',
        'Il faut replacer cela dans…',
        'Quelle lecture vous paraît la plus convaincante ?',
      ),
      _Unit(
        'Independent French',
        'Self-directed fluency',
        'Choose your own topic',
        'Reflect on your progress',
        'recording booth',
        'learner',
        'coach',
        'learner',
        'coach',
        'speak with a clear personal voice',
        'identify one next refinement',
        'Si je devais résumer…',
        'Quel est le prochain détail à travailler ?',
      ),
      _Unit(
        'Long-form speaking',
        'Sustained conversation',
        'Hold a ten-minute exchange',
        'Change direction elegantly',
        'radio studio',
        'guest',
        'host',
        'host',
        'guest',
        'sustain a coherent conversation',
        'signal and handle a topic shift',
        'Pour revenir à votre question…',
        'Avant de conclure, j’aimerais revenir sur…',
      ),
    ],
  };
}

class _Unit {
  const _Unit(
    this.title,
    this.focus,
    this.sceneA,
    this.sceneB,
    this.location,
    this.learnerRoleA,
    this.tutorRoleA,
    this.learnerRoleB,
    this.tutorRoleB,
    this.goalA,
    this.goalB,
    this.openingA,
    this.openingB,
  );

  final String title;
  final String focus;
  final String sceneA;
  final String sceneB;
  final String location;
  final String learnerRoleA;
  final String tutorRoleA;
  final String learnerRoleB;
  final String tutorRoleB;
  final String goalA;
  final String goalB;
  final String openingA;
  final String openingB;

  List<String> get phrases => const ['Pouvez-vous répéter ?', 'Je voudrais…'];

  String get sceneSubtitleA =>
      'Practise ${focus.toLowerCase()} in a real moment.';
  String get sceneSubtitleB =>
      'Use ${focus.toLowerCase()} to keep the exchange moving.';
}

extension on SpeakCurriculumItem {
  SpeakCurriculumItem copyWith({int? sessionIndex}) => SpeakCurriculumItem(
    contentKey: contentKey,
    level: level,
    unit: unit,
    unitTitle: unitTitle,
    sessionIndex: sessionIndex ?? this.sessionIndex,
    title: title,
    subtitle: subtitle,
    kind: kind,
    estimatedMinutes: estimatedMinutes,
    targetPhrases: targetPhrases,
    roleplay: roleplay,
    explicitPrimarySkill: explicitPrimarySkill,
    explicitSupportingSkills: explicitSupportingSkills,
  );
}
