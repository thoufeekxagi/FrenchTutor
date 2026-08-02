// Not a real test — a headless simulation driver that piggybacks on
// `flutter test` because that's the only way to get a working
// `rootBundle` (ContentService reads assets/content/*.json through it) and
// a mockable SharedPreferences (LessonAgentService's API key, SRSService's
// new-cards-per-day) without a full Flutter engine. Everything it calls
// (ContentService, SRSService, LessonAgentService, LearningStore) is the
// real production code — nothing here reimplements app logic.
//
// Run one level:
//   GEMINI_API_KEY=xxx LEVEL=a1 DAYS=30 flutter test \
//     personalized_test_verification/simulate_journey_test.dart --timeout none
//
// Output: personalized_test_verification/output/<level>_journey.json,
// written after every simulated day so a crash partway through still leaves
// prior days on disk (see README for the resume caveat — this does not
// replay a crashed run from where it left off, it writes-as-it-goes so nothing
// already-generated is lost, but a rerun starts a fresh level from day 1).
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:french_tutor/data/content_service.dart';
import 'package:french_tutor/data/database/learning_store.dart';
import 'package:french_tutor/models/content_models.dart';
import 'package:french_tutor/models/srs_state.dart';
import 'package:french_tutor/services/lesson_agent_service.dart';
import 'package:french_tutor/services/srs_service.dart';

import 'harness/clock_shift.dart';
import 'harness/gemini_text.dart';
import 'harness/synthetic_learner.dart';

const _levels = ['a1', 'a2', 'b1', 'b2'];

void main() {
  final level = (Platform.environment['LEVEL'] ?? 'a1').toLowerCase();
  final days = int.tryParse(Platform.environment['DAYS'] ?? '') ?? 30;
  final apiKey = Platform.environment['GEMINI_API_KEY'];

  test(
    'simulate $days days at $level',
    () async {
      if (apiKey == null || apiKey.isEmpty) {
        fail(
          'Set GEMINI_API_KEY, e.g.:\n'
          '  GEMINI_API_KEY=xxx LEVEL=$level DAYS=$days flutter test '
          'personalized_test_verification/simulate_journey_test.dart --timeout none',
        );
      }
      if (!_levels.contains(level)) {
        fail('LEVEL must be one of $_levels, got "$level"');
      }
      await _runLevel(level: level, days: days, apiKey: apiKey);
    },
    timeout: Timeout.none,
  );
}

Future<void> _runLevel({
  required String level,
  required int days,
  required String apiKey,
}) async {
  final outPath =
      'personalized_test_verification/output/${level}_journey.json';
  final outFile = File(outPath);
  if (outFile.existsSync()) {
    final existing = jsonDecode(outFile.readAsStringSync()) as Map;
    final existingDays = (existing['days'] as List?) ?? const [];
    if (existingDays.length >= days) {
      // ignore: avoid_print
      print(
        '$level: $outPath already has ${existingDays.length} days — skipping. '
        'Delete the file to force a full rerun.',
      );
      return;
    }
  }

  TestWidgetsFlutterBinding.ensureInitialized();
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({'gemini_api_key': apiKey});
  await ContentService.shared.preload();

  final db = sqlite3.openInMemory();
  final store = LearningStore(db);
  final srs = SRSService(store: store);
  final clockShift = ClockShift(db);
  final judgeClient = GeminiTextClient(apiKey: apiKey);
  final learner = SyntheticLearner(rng: Random(level.hashCode));
  final levelBand = level.toUpperCase();

  final profile = store.profile();
  profile.level = level;
  profile.sessionLength = 'standard';
  store.saveProfile(profile);

  final startDate = DateTime(2026, 1, 1);
  _seedStartingKnowledge(store: store, level: level, startDate: startDate);

  final dayRecords = <Map<String, dynamic>>[];
  final scenarios = [
    'Ordering at a busy café counter',
    'Asking for directions to the train station',
    'Returning a faulty item at a shop',
    'Checking into a small hotel',
    'Making small talk with a new neighbor',
    'Booking a table at a restaurant by phone',
    'Asking a pharmacist for advice on a cold',
  ];
  final storyTopics = [
    'a weekend trip',
    'a family dinner',
    'a first day at a new job',
    'a lost pet found again',
    'a surprise visit from an old friend',
    'a rainy day stuck at home',
    'planning a birthday party',
  ];

  for (var day = 1; day <= days; day++) {
    final simDate = startDate.add(Duration(days: day - 1));
    clockShift.beginDay();
    final record = <String, dynamic>{'day': day, 'simDate': _isoDay(simDate)};
    final errors = <String>[];

    // --- Vocabulary -------------------------------------------------------
    List<VocabEntry> todaysWords = const [];
    try {
      final candidates = await srs.dailyMixedQueue();
      final mistakeTags = store
          .topMistakeTags()
          .map((m) => (tag: m.tag, description: m.description, count: m.count))
          .toList();
      final recentDiary = store
          .recentDiaryEntries()
          .map((d) => '${d.stage}: ${d.summary}')
          .toList();
      final plan = await LessonAgentService.shared.planVocabSession(
        candidateWords: candidates,
        count: candidates.length,
        mistakeTags: mistakeTags,
        recentDiary: recentDiary,
      );
      final orderedIds = plan.prioritizedWordIds;
      final ordered = orderedIds == null
          ? candidates
          : [
              for (final id in orderedIds)
                ...candidates.where((c) => c.id == id),
            ];
      todaysWords = (ordered.isEmpty ? candidates : ordered).take(6).toList();

      final reviewed = <Map<String, String>>[];
      for (final word in todaysWords) {
        final grade = learner.pickGrade();
        srs.grade(entryId: word.id, grade: grade);
        reviewed.add({'fr': word.fr, 'en': word.en, 'grade': grade.name});
      }
      store.saveDiaryEntry(
        stage: 'vocab',
        summary: '${plan.focusNote} (${todaysWords.length} words)',
      );
      record['vocab'] = {
        'focusNote': plan.focusNote,
        'words': reviewed,
      };
    } catch (e) {
      errors.add('vocab: $e');
      record['vocab'] = {'error': '$e'};
    }

    // --- Grammar ------------------------------------------------------
    try {
      final candidates = _grammarCandidates(store);
      if (candidates.isEmpty) {
        record['grammar'] = {'note': 'no remaining grammar candidates'};
      } else {
        final mistakeTags = store
            .topMistakeTags()
            .map(
              (m) => (tag: m.tag, description: m.description, count: m.count),
            )
            .toList();
        final recentDiary = store
            .recentDiaryEntries()
            .map((d) => '${d.stage}: ${d.summary}')
            .toList();
        final plan = await LessonAgentService.shared.planGrammarSession(
          candidates: candidates,
          mistakeTags: mistakeTags,
          recentDiary: recentDiary,
        );
        final usage = _grammarUsageFor(plan.chosenId);
        final chosenTitle = candidates
            .firstWhere(
              (c) => c.id == plan.chosenId,
              orElse: () => candidates.first,
            )
            .title;
        final cards = await LessonAgentService.shared.generateGrammarPracticeCards(
          tenseTitle: chosenTitle,
          tenseUsage: usage,
          vocabWords: todaysWords.map((w) => w.fr).toList(),
          recentVocabTranscript: '',
        );
        store.setLessonStatus(plan.chosenId, 'completed');
        store.saveDiaryEntry(
          stage: 'grammar',
          summary: '${plan.focusNote} — $chosenTitle',
        );
        record['grammar'] = {
          'chosenId': plan.chosenId,
          'chosenTitle': chosenTitle,
          'focusNote': plan.focusNote,
          'practiceCards': cards
              .map((c) => {'fr': c.fr, 'en': c.en, 'note': c.note})
              .toList(),
        };
      }
    } catch (e) {
      errors.add('grammar: $e');
      record['grammar'] = {'error': '$e'};
    }

    // --- Listening / story ----------------------------------------------
    try {
      final passage = day.isOdd
          ? await LessonAgentService.shared.buildReadingPassageFromVocab(
              words: todaysWords.isEmpty
                  ? ContentService.shared.vocabPhases.first.themes.first.entries
                      .take(4)
                      .toList()
                  : todaysWords,
              levelBand: levelBand,
            )
          : await LessonAgentService.shared.buildPersonalStory(
              topic: storyTopics[day % storyTopics.length],
              levelBand: levelBand,
            );
      final quizAndKeywords = await LessonAgentService.shared
          .buildStoryQuizAndKeywords(passage);
      store.saveDiaryEntry(stage: 'listening', summary: passage.title);
      record['listening'] = {
        'title': passage.title,
        'excerpt': passage.fullText.length > 240
            ? '${passage.fullText.substring(0, 240)}…'
            : passage.fullText,
        'quizCount': quizAndKeywords.quiz.length,
        'keywordCount': quizAndKeywords.keywords.length,
      };
    } catch (e) {
      errors.add('listening: $e');
      record['listening'] = {'error': '$e'};
    }

    // --- Writing -----------------------------------------------------
    try {
      final knownVocab = ContentService.shared.knownVocabWords(
        store.allSRSStates(),
      );
      final task = await LessonAgentService.shared.generateWritingTask(
        levelBand: levelBand,
        knownVocab: knownVocab,
      );
      final submission = await learner.writeSubmission(
        client: judgeClient,
        levelBand: levelBand,
        promptFr: task.promptFr,
        minWords: task.minWords,
        targetConnectors: task.targetConnectors,
      );
      final feedback = await LessonAgentService.shared.gradeWriting(
        task: task,
        submission: submission,
        levelBand: levelBand,
      );
      store.saveSubmission(
        taskId: task.id,
        text: submission,
        feedback: '${feedback.scoreOutOf10}/10 — ${feedback.connectorFeedback}',
      );
      store.saveDiaryEntry(
        stage: 'writing',
        summary: '${task.title} (${feedback.scoreOutOf10}/10)',
      );
      record['writing'] = {
        'taskTitle': task.title,
        'promptFr': task.promptFr,
        'submission': submission,
        'scoreOutOf10': feedback.scoreOutOf10,
        'strengths': feedback.strengths,
        'nextSteps': feedback.nextSteps,
      };
    } catch (e) {
      errors.add('writing: $e');
      record['writing'] = {'error': '$e'};
    }

    // --- Roleplay ------------------------------------------------------
    try {
      final scenario = scenarios[day % scenarios.length];
      final passage = await LessonAgentService.shared.buildStandaloneRoleplay(
        scenario: scenario,
        levelBand: levelBand,
      );
      store.saveDiaryEntry(stage: 'roleplay', summary: passage.title);
      record['roleplay'] = {
        'scenario': scenario,
        'title': passage.title,
        'excerpt': passage.fullText.length > 240
            ? '${passage.fullText.substring(0, 240)}…'
            : passage.fullText,
      };
    } catch (e) {
      errors.add('roleplay: $e');
      record['roleplay'] = {'error': '$e'};
    }

    final counts = srs.counts(phase: 1);
    record['srsSnapshot'] = {
      'totalCards': store.allSRSStates().length,
      'phase1Due': counts.due,
      'phase1Unseen': counts.unseen,
      'phase1Known': counts.known,
    };
    record['errors'] = errors;
    dayRecords.add(record);

    clockShift.endDay(simDate);

    outFile.parent.createSync(recursive: true);
    outFile.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'level': level,
        'levelBand': levelBand,
        'daysRequested': days,
        'daysCompleted': dayRecords.length,
        'syntheticLearnerCalls': judgeClient.callCount,
        'syntheticLearnerErrors': judgeClient.errorCount,
        'days': dayRecords,
      }),
    );
    // ignore: avoid_print
    print('$level day $day/$days done (${errors.length} errors)');
  }

  db.dispose();
}

/// Higher starting levels shouldn't begin as blank-slate beginners — seeds
/// enough of the bundled vocab bank as already-known (bypassing grade(), set
/// directly) so a B2 run's vocab lab is mostly review + this app's more
/// advanced generated content, matching what an actual B2 learner would see.
void _seedStartingKnowledge({
  required LearningStore store,
  required String level,
  required DateTime startDate,
}) {
  final phasesToSeed = switch (level) {
    'a1' => 0,
    'a2' => 1,
    'b1' => 2,
    'b2' => 3,
    _ => 0,
  };
  if (phasesToSeed == 0) return;
  final introducedOn =
      '${startDate.year}-${startDate.month.toString().padLeft(2, '0')}-${startDate.day.toString().padLeft(2, '0')}';
  var seeded = 0;
  for (final phase in ContentService.shared.vocabPhases.take(phasesToSeed)) {
    for (final theme in phase.themes) {
      for (final entry in theme.entries) {
        store.upsertSRS(
          SRSState(
            entryId: entry.id,
            ease: 2.5,
            intervalDays: 30,
            reps: 5,
            dueAt: startDate.add(const Duration(days: 30)),
            lastGrade: SRSGrade.good,
            introducedOn: introducedOn,
            lastReviewedAt: startDate,
          ),
        );
        seeded++;
      }
    }
  }
  // ignore: avoid_print
  print('$level: pre-seeded $seeded known words from $phasesToSeed phase(s)');
}

List<({String id, String title})> _grammarCandidates(LearningStore store) {
  final grammar = ContentService.shared.grammar();
  if (grammar == null) return const [];
  final lessons = [...grammar.lessons]..sort((a, b) => a.order.compareTo(b.order));
  final result = <({String id, String title})>[];
  for (final lesson in lessons) {
    if (store.lessonStatus(lesson.id).status != 'completed') {
      result.add((id: lesson.id, title: lesson.title));
    }
  }
  for (final topic in grammar.topics) {
    if (store.lessonStatus(topic.id).status != 'completed') {
      result.add((id: topic.id, title: topic.title));
    }
  }
  return result;
}

List<String> _grammarUsageFor(String id) {
  final grammar = ContentService.shared.grammar();
  if (grammar == null) return const [];
  for (final lesson in grammar.lessons) {
    if (lesson.id == id) return lesson.usage;
  }
  for (final topic in grammar.topics) {
    if (topic.id == id) return topic.narration;
  }
  return const [];
}

String _isoDay(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
