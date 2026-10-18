import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/data/database/learning_store.dart';
import 'package:french_tutor/v3/story/v3_story_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Directory dir;
  late String path;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('v3_persist_');
    path = '${dir.path}/app.db';
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('lesson progress survives closing and reopening the database', () {
    final first = LearningStore(sqlite3.open(path));
    first.saveV3CourseProgress('s0-01', currentStep: 0, completed: true);
    first.saveV3CourseProgress(
      'a1-u01-words-1',
      currentStep: 4,
      completed: false,
    );

    final reopened = LearningStore(sqlite3.open(path));
    final progress = reopened.v3CourseProgress();
    expect(progress['s0-01']!.status, 'completed');
    expect(progress['a1-u01-words-1']!.status, 'in_progress');
    expect(progress['a1-u01-words-1']!.currentStep, 4);
    expect(reopened.lastV3ActiveLesson(), 'a1-u01-words-1');
    expect(reopened.lastV3CompletedLesson(), 's0-01');
  });

  test('a replay or going back never undoes saved progress', () {
    final store = LearningStore(sqlite3.open(path));
    store.saveV3CourseProgress('s0-01', currentStep: 0, completed: true);
    store.saveV3CourseProgress('s0-01', currentStep: 2, completed: false);
    store.saveV3CourseProgress(
      'a1-u01-words-1',
      currentStep: 5,
      completed: false,
    );
    store.saveV3CourseProgress(
      'a1-u01-words-1',
      currentStep: 2,
      completed: false,
    );

    final progress = LearningStore(sqlite3.open(path)).v3CourseProgress();
    expect(progress['s0-01']!.status, 'completed');
    expect(progress['a1-u01-words-1']!.currentStep, 5);
  });

  test('level and exam date survive closing and reopening', () {
    final first = LearningStore(sqlite3.open(path));
    final profile = first.profile()
      ..level = 'a2'
      ..tcfExamDate = DateTime(2027, 2, 14);
    first.saveProfile(profile);

    final back = LearningStore(sqlite3.open(path)).profile();
    expect(back.level, 'a2');
    expect(back.tcfExamDate, DateTime(2027, 2, 14));
  });

  test('story progress and saved words survive an app restart', () async {
    SharedPreferences.setMockInitialValues({});
    await V3StoryProgress.markDone('story-1');
    await V3StoryProgress.savePosition('story-2', 7);
    await V3StoryProgress.toggleSaved('story-2', 'boulangerie');
    await V3StoryProgress.setHearWords(false);

    // A restart reads the same preferences again.
    expect(await V3StoryProgress.done(), {'story-1'});
    expect((await V3StoryProgress.positions())['story-2'], 7);
    expect(await V3StoryProgress.savedWords(), {'story-2|boulangerie'});
    V3StoryProgress.hearWords.value = true;
    await V3StoryProgress.loadPrefs();
    expect(V3StoryProgress.hearWords.value, isFalse);
  });
}
