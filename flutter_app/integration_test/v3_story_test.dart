import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/main.dart' as app;
import 'package:french_tutor/v3/story/v3_story.dart';
import 'package:french_tutor/v3/v3_prefs.dart';
import 'package:french_tutor/v3/story/v3_story_audio.dart';
import 'package:french_tutor/v3/story/v3_story_store.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/probe.dart';

/// Stories end to end on a real device: list, reader, tap-a-word card, the
/// hear-words toggle, translation toggle, playback controls, Words tab, quiz,
/// completion for every story, and Dark mode.
///
/// Run with
///   E2E_DEFINES='--dart-define=E2E_SHELL=true --dart-define=E2E_FAKE_AUDIO=true'
/// E2E_FAKE_AUDIO swaps live Marie for a fake that records requests and never
/// touches the network, so nothing is billed. The real voice is tested by hand.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final probe = Probe(binding);

  Future<List<String>> labels(WidgetTester tester) async =>
      (probe.describe(tester)['tappable']! as List)
          .map((e) => (e as Map)['label'] as String)
          .toList();

  Future<List> texts(WidgetTester tester) async =>
      probe.describe(tester)['texts']! as List;

  Future<void> press(
    WidgetTester tester,
    String label, {
    bool startsWith = false,
  }) async {
    await probe.waitForLabel(tester, label, startsWith: startsWith);
    await probe.tapLabel(tester, label, startsWith: startsWith);
    await tester.pump(const Duration(milliseconds: 650));
  }

  Future<void> waitContains(WidgetTester tester, String text) async {
    final deadline = DateTime.now().add(const Duration(seconds: 25));
    List<String> seen = const [];
    while (DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 150));
      seen = await labels(tester);
      if (seen.any((l) => l.contains(text))) return;
    }
    await probe.capture(tester, 'timeout_contains');
    throw TimeoutException('No tappable containing "$text". Visible: $seen');
  }

  Future<void> openStory(WidgetTester tester, V3Story story) async {
    await waitContains(tester, story.title);
    final all = await labels(tester);
    final label = all.firstWhere(
      (l) =>
          l.contains(story.title) &&
          (l.startsWith('Start ') ||
              l.startsWith('Resume ') ||
              l.startsWith(story.title)),
    );
    await press(tester, label);
    await probe.waitForLabel(tester, 'Play story');
  }

  Future<void> answerQuiz(WidgetTester tester, V3Story story) async {
    await press(tester, 'Quiz');
    for (var i = 0; i < story.quiz.length; i++) {
      final q = story.quiz[i];
      await press(tester, q.options[q.answer]);
      await press(tester, 'Check');
      expect(
        await texts(tester),
        contains('Correct'),
        reason: '${story.id} question ${i + 1}: keyed answer not accepted',
      );
      await press(
        tester,
        i == story.quiz.length - 1 ? 'See result' : 'Next question',
      );
    }
    expect(
      await texts(tester),
      contains('${story.quiz.length}  of ${story.quiz.length} correct'),
    );
  }

  testWidgets('v3 stories: list, reader, word card, audio, quiz, dark', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('dev_force_pro_unlock', true);
    await prefs.setBool('app_dark_mode_v3_choice', true);
    await prefs.setBool('app_dark_mode', false);
    for (final k in [
      'v3_story_done',
      'v3_story_position',
      'v3_story_saved_words',
    ]) {
      await prefs.remove(v3Key(k));
    }
    await prefs.setBool(v3Key('v3_story_hear_words'), true);
    await prefs.setBool('session_translate_sentences', true);
    V3StoryAudio.debugLog.clear();
    final stories = await V3Stories.load();
    expect(stories.length, greaterThanOrEqualTo(4));
    final first = stories.first;

    app.main();

    // ---- Stories list ------------------------------------------------
    await probe.waitForLabel(
      tester,
      'Stories',
      timeout: const Duration(seconds: 60),
    );
    await probe.settle(tester, timeout: const Duration(seconds: 15));
    await press(tester, 'Stories');
    await probe.waitForLabel(tester, 'Start ${first.title}');
    await probe.capture(tester, '01_stories_list');
    var l = await labels(tester);
    expect(l, contains('A1'));
    expect(
      l,
      isNot(contains('A2, coming soon')),
      reason: 'a level with no stories must not be tappable',
    );
    expect(await texts(tester), containsAll(['A1', 'A2', 'B1', 'B2']));
    expect(
      l.any((x) => x.startsWith(stories[1].title)),
      isTrue,
      reason: 'second story card missing',
    );

    // ---- Reader ------------------------------------------------------
    await openStory(tester, first);
    await probe.settle(tester, timeout: const Duration(seconds: 6));
    await probe.capture(tester, '02_reader');
    var t = await texts(tester);
    expect(t, contains(first.title));
    expect(t, contains(first.sentences.first.en));
    l = await labels(tester);
    expect(
      l,
      containsAll([
        'Story',
        'Quiz',
        'Words',
        'Play story',
        'Replay sentence',
        'Translation on',
      ]),
    );

    // ---- Tap a word: small card above the word, and the word is spoken --
    await press(tester, 'Word femme');
    await probe.capture(tester, '03_word_card');
    t = await texts(tester);
    expect(t, contains('woman'), reason: 'meaning card did not appear');
    expect(await labels(tester), contains('Hear word'));
    expect(
      V3StoryAudio.debugLog,
      contains('word:femme'),
      reason: 'hear words is on, so the tap must speak the word',
    );
    await press(tester, 'Word femme'); // tapping again closes the card
    expect(
      await texts(tester),
      isNot(contains('woman')),
      reason: 'card did not close',
    );

    // ---- Turn "Hear words when tapped" off ------------------------------
    await press(tester, 'Story settings');
    await probe.capture(tester, '04_settings');
    await press(tester, 'Hear words when tapped, on');
    expect(
      await labels(tester),
      contains('Hear words when tapped, off'),
      reason: 'toggle did not flip',
    );
    await tester.tapAt(const Offset(200, 90)); // tap outside to close
    await tester.pump(const Duration(milliseconds: 700));
    V3StoryAudio.debugLog.clear();
    await press(tester, 'Word valise');
    expect(await texts(tester), contains('suitcase'));
    expect(
      V3StoryAudio.debugLog,
      isNot(contains('word:valise')),
      reason: 'hear words is off, so the tap must stay silent',
    );
    await press(tester, 'Hear word'); // the card's own speaker still works
    expect(V3StoryAudio.debugLog, contains('word:valise'));
    await press(tester, 'Word valise');

    // ---- Translation toggle ---------------------------------------------
    await press(tester, 'Translation on');
    expect(
      await texts(tester),
      isNot(contains(first.sentences.first.en)),
      reason: 'translation should be hidden',
    );
    await press(tester, 'Translation off');
    expect(await texts(tester), contains(first.sentences.first.en));

    // ---- Playback controls (fake voice) ---------------------------------
    await press(tester, 'Play story');
    await probe.waitForLabel(tester, 'Pause story');
    await probe.capture(tester, '05_playing');
    // Tapping a word selected its sentence, so playback starts from there,
    // the same way the legacy reader reads from the line you picked.
    final from = first.sentences.indexWhere(
      (s) => s.units.any((u) => u.key == 'valise'),
    );
    expect(V3StoryAudio.debugLog, contains('play:$from'));
    await probe.waitForLabel(
      tester,
      'Play story',
      timeout: const Duration(seconds: 60),
    );
    await press(tester, 'Replay sentence');
    expect(
      V3StoryAudio.debugLog.any((e) => e.endsWith(':only')),
      isTrue,
      reason: 'replay must play a single sentence',
    );
    await press(tester, 'Speed 1x');
    expect(await labels(tester), contains('Speed 1.5x'));
    // The speed cycles 1, 1.5, 0.5, 0.75 and back to 1.
    await press(tester, 'Speed 1.5x');
    await press(tester, 'Speed 0.5x');
    await press(tester, 'Speed 0.75x');
    expect(await labels(tester), contains('Speed 1x'));

    // ---- Words tab ------------------------------------------------------
    await press(tester, 'Words');
    await probe.capture(tester, '06_words');
    final kw = first.keywords.first;
    expect(await texts(tester), contains(kw));
    await press(tester, 'Hear $kw');
    expect(V3StoryAudio.debugLog, contains('word:$kw'));
    await press(tester, 'Save $kw');
    expect(await labels(tester), contains('Unsave $kw'));
    expect(
      await V3StoryProgress.savedWords(),
      contains('${first.id}|$kw'),
      reason: 'saved word was not stored',
    );

    // ---- Quiz and completion for every story ----------------------------
    await answerQuiz(tester, first);
    await probe.capture(tester, '07_quiz_result');
    await press(tester, 'Done');
    for (final story in stories.skip(1)) {
      await openStory(tester, story);
      await answerQuiz(tester, story);
      await press(tester, 'Done');
    }
    await waitContains(tester, first.title);
    await probe.settle(tester, timeout: const Duration(seconds: 8));
    await probe.capture(tester, '08_all_read');
    l = await labels(tester);
    for (final story in stories) {
      expect(
        l.any((x) => x.startsWith(story.title) && x.endsWith(', read')),
        isTrue,
        reason: '${story.title} is not marked as read',
      );
    }
    expect(
      await V3StoryProgress.done(),
      containsAll(stories.map((s) => s.id)),
      reason: 'completion was not stored',
    );

    // ---- Dark mode ------------------------------------------------------
    await press(tester, 'Me');
    await press(tester, 'Dark mode');
    await probe.settle(tester, timeout: const Duration(seconds: 8));
    await press(tester, 'Learn');
    await press(tester, 'Stories');
    await waitContains(tester, first.title);
    await probe.capture(tester, '09_dark_list');
    await openStory(tester, first);
    await press(tester, 'Word femme');
    await probe.capture(tester, '10_dark_word_card');
    expect(await texts(tester), contains('woman'));

    // Leave the device in light mode.
    await press(tester, 'Word femme');
    await press(tester, 'Back');
    await press(tester, 'Me');
    await press(tester, 'Dark mode');
    await probe.settle(tester, timeout: const Duration(seconds: 8));
    semantics.dispose();
  });
}
