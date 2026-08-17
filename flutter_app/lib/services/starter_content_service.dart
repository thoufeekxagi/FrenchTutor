import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../data/database/generated_grammar_story_store.dart';
import '../data/database/generated_roleplay_store.dart';
import '../data/database/generated_story_store.dart';
import '../data/database/generated_vocabulary_set_store.dart';
import '../data/database/generated_writing_task_store.dart';
import '../models/content_models.dart';
import 'sync_service.dart';

/// The five reusable starter themes. They are assigned into each learner's
/// own generated-content tables at sign-in, rather than being public rows.
class StarterContentCatalog {
  static const seeds = <StarterSeed>[
    StarterSeed(
      key: 'market',
      title: 'Le marché du matin',
      titleEn: 'The morning market',
      topic: 'Food',
      summary: 'A friendly morning at a lively French market.',
      coverAsset: 'assets/starter_covers/market.png',
      sentences: [
        ['Le marché est très animé.', 'The market is very lively.'],
        ['Je choisis des pommes rouges.', 'I choose red apples.'],
        ['La vendeuse me sourit.', 'The seller smiles at me.'],
        ['Nous parlons du prix.', 'We talk about the price.'],
      ],
      words: [
        ['market', 'marché', 'mar-shay'],
        ['apple', 'pomme', 'pom'],
        ['seller', 'vendeur', 'von-duhr'],
        ['price', 'prix', 'pree'],
        ['fresh', 'frais', 'fray'],
      ],
      grammarPoint: 'Présent',
      grammarSummary:
          'Use the present tense for routines and facts happening now.',
      writingTitle: 'Une visite au marché',
      writingFr: 'Écris quatre phrases sur une visite au marché.',
      writingEn: 'Write four sentences about a visit to a market.',
      roleplayTitle: 'Au marché',
    ),
    StarterSeed(
      key: 'station',
      title: 'À la gare',
      titleEn: 'At the station',
      topic: 'Travel',
      summary: 'A simple train journey begins at the station.',
      coverAsset: 'assets/starter_covers/station.png',
      sentences: [
        [
          'J’arrive à la gare à huit heures.',
          'I arrive at the station at eight.',
        ],
        ['Le train part dans dix minutes.', 'The train leaves in ten minutes.'],
        ['Je cherche le quai numéro deux.', 'I look for platform number two.'],
        ['Un agent m’indique le chemin.', 'An agent shows me the way.'],
      ],
      words: [
        ['station', 'gare', 'gahr'],
        ['train', 'train', 'tran'],
        ['platform', 'quai', 'kay'],
        ['ticket', 'billet', 'bee-yay'],
        ['departure', 'départ', 'day-par'],
      ],
      grammarPoint: 'Passé composé',
      grammarSummary: 'Use passé composé for a completed action in the past.',
      writingTitle: 'Mon dernier voyage',
      writingFr: 'Raconte un court voyage que tu as fait.',
      writingEn: 'Describe a short trip you took.',
      roleplayTitle: 'À la gare',
    ),
    StarterSeed(
      key: 'lantern',
      title: 'La lanterne du jardin',
      titleEn: 'The garden lantern',
      topic: 'Home',
      summary: 'A small light helps a gardener find the way home.',
      coverAsset: 'assets/starter_covers/lantern.png',
      sentences: [
        [
          'Le jardin devient calme le soir.',
          'The garden becomes quiet in the evening.',
        ],
        ['Une lanterne éclaire le chemin.', 'A lantern lights the path.'],
        ['Le jardinier entend les oiseaux.', 'The gardener hears the birds.'],
        ['Il ferme doucement la porte.', 'He gently closes the door.'],
      ],
      words: [
        ['garden', 'jardin', 'zhar-dan'],
        ['lantern', 'lanterne', 'lan-tairn'],
        ['path', 'chemin', 'shuh-man'],
        ['evening', 'soir', 'swahr'],
        ['quiet', 'calme', 'kalm'],
      ],
      grammarPoint: 'Imparfait',
      grammarSummary:
          'Use imparfait to describe a past scene, habit, or background.',
      writingTitle: 'Un soir tranquille',
      writingFr: 'Décris une soirée calme chez toi.',
      writingEn: 'Describe a quiet evening at home.',
      roleplayTitle: 'Dans le jardin',
    ),
    StarterSeed(
      key: 'sparrow',
      title: 'Le moineau et la tablette',
      titleEn: 'The sparrow and the tablet',
      topic: 'Technology',
      summary: 'A curious sparrow visits a student studying on campus.',
      coverAsset: 'assets/starter_covers/sparrow.png',
      sentences: [
        [
          'Un moineau arrive près de la fenêtre.',
          'A sparrow arrives near the window.',
        ],
        [
          'L’étudiante travaille sur sa tablette.',
          'The student works on her tablet.',
        ],
        [
          'Elle regarde l’oiseau avec surprise.',
          'She looks at the bird with surprise.',
        ],
        [
          'Le moineau repart dans le jardin.',
          'The sparrow goes back to the garden.',
        ],
      ],
      words: [
        ['sparrow', 'moineau', 'mwa-noh'],
        ['window', 'fenêtre', 'fuh-netr'],
        ['student', 'étudiant', 'ay-tu-dee-an'],
        ['tablet', 'tablette', 'ta-bl air'],
        ['surprise', 'surprise', 'sur-preez'],
      ],
      grammarPoint: 'Futur proche',
      grammarSummary:
          'Use futur proche for a clear plan or near-future action.',
      writingTitle: 'Mon projet de demain',
      writingFr: 'Écris ce que tu vas faire demain.',
      writingEn: 'Write what you are going to do tomorrow.',
      roleplayTitle: 'Une rencontre surprenante',
    ),
    StarterSeed(
      key: 'boat',
      title: 'Le petit bateau en papier',
      titleEn: 'The little paper boat',
      topic: 'Nature',
      summary: 'A paper boat drifts through a quiet coastal village.',
      coverAsset: 'assets/starter_covers/boat.png',
      sentences: [
        ['Je plie une feuille de papier.', 'I fold a sheet of paper.'],
        [
          'Le petit bateau flotte sur l’eau.',
          'The little boat floats on the water.',
        ],
        [
          'Le courant l’emporte doucement.',
          'The current carries it gently away.',
        ],
        [
          'Nous suivons son voyage ensemble.',
          'We follow its journey together.',
        ],
      ],
      words: [
        ['boat', 'bateau', 'ba-toh'],
        ['paper', 'papier', 'pa-pyay'],
        ['water', 'eau', 'oh'],
        ['current', 'courant', 'koo-ran'],
        ['journey', 'voyage', 'vwa-yazh'],
      ],
      grammarPoint: 'Conditionnel',
      grammarSummary:
          'Use the conditional to express a polite wish or possibility.',
      writingTitle: 'Un voyage imaginaire',
      writingFr: 'Imagine un petit voyage près de l’eau.',
      writingEn: 'Imagine a short journey near the water.',
      roleplayTitle: 'Au bord de l’eau',
    ),
  ];
}

class StarterSeed {
  const StarterSeed({
    required this.key,
    required this.title,
    required this.titleEn,
    required this.topic,
    required this.summary,
    required this.coverAsset,
    required this.sentences,
    required this.words,
    required this.grammarPoint,
    required this.grammarSummary,
    required this.writingTitle,
    required this.writingFr,
    required this.writingEn,
    required this.roleplayTitle,
  });

  final String key;
  final String title;
  final String titleEn;
  final String topic;
  final String summary;
  final String coverAsset;
  final List<List<String>> sentences;
  final List<List<String>> words;
  final String grammarPoint;
  final String grammarSummary;
  final String writingTitle;
  final String writingFr;
  final String writingEn;
  final String roleplayTitle;
}

class StarterContentService {
  StarterContentService({
    required this.stories,
    required this.grammarStories,
    required this.writingTasks,
    required this.roleplays,
    required this.vocabularySets,
    required this.sync,
  });

  final GeneratedStoryStore stories;
  final GeneratedGrammarStoryStore grammarStories;
  final GeneratedWritingTaskStore writingTasks;
  final GeneratedRoleplayStore roleplays;
  final GeneratedVocabularySetStore vocabularySets;
  final SyncService sync;
  Future<void>? _activeSeed;

  static const _uuid = Uuid();

  Future<void> ensureSeededForCurrentUser() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;

    final active = _activeSeed;
    if (active != null) {
      await active;
      return;
    }
    final operation = _seedForUser(uid);
    _activeSeed = operation;
    try {
      await operation;
    } finally {
      if (identical(_activeSeed, operation)) _activeSeed = null;
    }
  }

  Future<void> _seedForUser(String uid) async {
    final existingStories = stories.list();
    final existingGrammar = grammarStories.list();
    final existingWriting = writingTasks.list();
    final existingRoleplays = roleplays.list();
    final existingVocabulary = vocabularySets.list();
    final coverTargets = <String, List<String>>{};

    for (var index = 0; index < StarterContentCatalog.seeds.length; index++) {
      final seed = StarterContentCatalog.seeds[index];
      final createdAt = DateTime.now().toUtc().subtract(Duration(days: index));
      final coverUrl = 'asset:${seed.coverAsset}';
      final storyIds = <String>[];

      for (final mode in ['reading', 'listening']) {
        final id = _id(uid, 'story-${seed.key}-$mode-v1');
        storyIds.add(id);
        if (!existingStories.any((story) => story.id == id)) {
          stories.insert(
            GeneratedStory(
              id: id,
              passage: _passage(id, seed),
              quiz: _quiz(seed),
              keywords: _keywords(seed),
              createdAt: createdAt,
              levelBand: 'A1',
              summary: seed.summary,
              topic: seed.topic,
              readTimeMinutes: 3,
              coverUrl: coverUrl,
              practiceMode: mode,
            ),
          );
        }
      }

      final grammarId = _id(uid, 'grammar-${seed.key}-v1');
      if (!existingGrammar.any((story) => story.id == grammarId)) {
        grammarStories.insert(
          GeneratedGrammarStory(
            id: grammarId,
            grammarPoint: seed.grammarPoint,
            levelBand: 'A1',
            explanation: _explanation(seed),
            passage: _passage(grammarId, seed),
            quiz: _quiz(seed),
            keywords: _keywords(seed),
            createdAt: createdAt,
            coverUrl: coverUrl,
          ),
        );
      }

      final writingId = _id(uid, 'writing-${seed.key}-v1');
      if (!existingWriting.any((task) => task.id == writingId)) {
        writingTasks.insert(
          GeneratedWritingTask(
            task: WritingTask(
              id: writingId,
              type: 'starter',
              title: seed.writingTitle,
              promptFr: seed.writingFr,
              promptEn: seed.writingEn,
              minWords: 8,
              targetConnectors: const ['et', 'mais', 'parce que'],
              rubricHints: const [
                'Use one complete sentence.',
                'Check the verb ending.',
              ],
              levelBand: 'A1',
            ),
            createdAt: createdAt,
            coverUrl: coverUrl,
          ),
        );
      }

      final roleplayId = _id(uid, 'roleplay-${seed.key}-v1');
      if (!existingRoleplays.any((roleplay) => roleplay.id == roleplayId)) {
        roleplays.insert(
          GeneratedRoleplay(
            id: roleplayId,
            passage: ReadingPassage(
              id: roleplayId,
              title: seed.roleplayTitle,
              titleEn: seed.titleEn,
              segments: _passage(roleplayId, seed).segments,
              fullText: seed.sentences.map((line) => line.first).join(' '),
            ),
            createdAt: createdAt,
            coverUrl: coverUrl,
          ),
        );
      }

      final vocabularyId = _id(uid, 'vocabulary-${seed.key}-v1');
      if (!existingVocabulary.any((set) => set.id == vocabularyId)) {
        vocabularySets.insert(
          GeneratedVocabularySet(
            id: vocabularyId,
            title: seed.title,
            summary: seed.summary,
            topic: seed.topic,
            levelBand: 'A1',
            entries: _vocabulary(seed),
            createdAt: createdAt,
            coverUrl: coverUrl,
          ),
        );
      }

      coverTargets[seed.key] = storyIds
        ..add(grammarId)
        ..add(writingId)
        ..add(roleplayId)
        ..add(vocabularyId);
    }

    await _uploadPrivateCovers(coverTargets);
  }

  String _id(String uid, String key) =>
      _uuid.v5(Uuid.NAMESPACE_URL, 'parlesprint:$uid:starter:$key');

  ReadingPassage _passage(String id, StarterSeed seed) {
    final segments = seed.sentences
        .map(
          (line) => ReadingSegment(
            fr: line[0],
            en: line[1],
            grammarNote: seed.grammarPoint,
            pronunciationTip: 'Listen once, then repeat naturally.',
          ),
        )
        .toList();
    return ReadingPassage(
      id: id,
      title: seed.title,
      titleEn: seed.titleEn,
      segments: segments,
      fullText: segments.map((segment) => segment.fr).join(' '),
    );
  }

  List<MultipleChoiceQuestion> _quiz(StarterSeed seed) => [
    MultipleChoiceQuestion(
      q: 'Que décrit cette scène ?',
      qEn: 'What does this scene describe?',
      choices: [
        seed.sentences.first[0],
        seed.sentences.last[0],
        'Une leçon de mathématiques',
      ],
      choicesEn: [
        seed.sentences.first[1],
        seed.sentences.last[1],
        'A maths lesson',
      ],
      answerIndex: 0,
    ),
    MultipleChoiceQuestion(
      q: 'Quel mot est important ?',
      qEn: 'Which word is important?',
      choices: [seed.words.first[1], seed.words[1][1], seed.words.last[1]],
      choicesEn: [seed.words.first[0], seed.words[1][0], seed.words.last[0]],
      answerIndex: 0,
    ),
  ];

  List<VocabEntry> _keywords(StarterSeed seed) =>
      _vocabulary(seed).take(4).toList();

  List<VocabEntry> _vocabulary(StarterSeed seed) => [
    for (var i = 0; i < seed.words.length; i++)
      VocabEntry(
        id: '${seed.key}-word-$i',
        en: seed.words[i][0],
        fr: seed.words[i][1],
        phonetic: seed.words[i][2],
      ),
  ];

  GrammarExplanation _explanation(StarterSeed seed) => GrammarExplanation(
    title: seed.grammarPoint,
    summary: seed.grammarSummary,
    usage: const [
      'Notice the time or intention first.',
      'Repeat the complete phrase aloud.',
    ],
    tenseContrast: 'The form changes the time or attitude of the sentence.',
    conjugations: [
      Conjugation(
        verb: 'parler',
        group: 'regular -er verb',
        rows: [
          ConjRow(pronoun: 'je', form: 'parle'),
          ConjRow(pronoun: 'tu', form: 'parles'),
          ConjRow(pronoun: 'il / elle', form: 'parle'),
        ],
      ),
    ],
    examples: [
      BilingualExample(
        fr: seed.sentences.first[0],
        en: seed.sentences.first[1],
      ),
      BilingualExample(fr: seed.sentences.last[0], en: seed.sentences.last[1]),
    ],
  );

  Future<void> _uploadPrivateCovers(Map<String, List<String>> targets) async {
    for (final seed in StarterContentCatalog.seeds) {
      final targetIds = targets[seed.key] ?? const <String>[];
      if (!targetIds.any(_needsPrivateCover)) continue;
      String? signedUrl;
      try {
        final data = await rootBundle.load(seed.coverAsset);
        final bytes = Uint8List.sublistView(data);
        signedUrl = await sync.uploadStoryCover(
          storyId: 'starter-cover-${seed.key}-v1',
          bytes: bytes,
        );
      } catch (_) {
        // The local asset remains available; retry on the next auth event.
      }
      if (signedUrl == null) continue;
      for (final id in targetIds) {
        final story = stories.list().where((item) => item.id == id).firstOrNull;
        if (story != null) {
          stories.updateCoverUrl(id, signedUrl);
        } else if (grammarStories.list().any((item) => item.id == id)) {
          grammarStories.updateCoverUrl(id, signedUrl);
        } else if (writingTasks.list().any((item) => item.id == id)) {
          writingTasks.updateCoverUrl(id, signedUrl);
        } else if (roleplays.list().any((item) => item.id == id)) {
          roleplays.updateCoverUrl(id, signedUrl);
        } else if (vocabularySets.list().any((item) => item.id == id)) {
          vocabularySets.updateCoverUrl(id, signedUrl);
        }
      }
    }
  }

  bool _needsPrivateCover(String id) {
    final story = stories.list().where((item) => item.id == id).firstOrNull;
    if (story != null) return _isLocalOrMissing(story.coverUrl);
    final grammar = grammarStories
        .list()
        .where((item) => item.id == id)
        .firstOrNull;
    if (grammar != null) return _isLocalOrMissing(grammar.coverUrl);
    final writing = writingTasks
        .list()
        .where((item) => item.id == id)
        .firstOrNull;
    if (writing != null) return _isLocalOrMissing(writing.coverUrl);
    final roleplay = roleplays
        .list()
        .where((item) => item.id == id)
        .firstOrNull;
    if (roleplay != null) return _isLocalOrMissing(roleplay.coverUrl);
    final vocabulary = vocabularySets
        .list()
        .where((item) => item.id == id)
        .firstOrNull;
    return vocabulary != null && _isLocalOrMissing(vocabulary.coverUrl);
  }

  bool _isLocalOrMissing(String? coverUrl) =>
      coverUrl == null || coverUrl.isEmpty || coverUrl.startsWith('asset:');
}
