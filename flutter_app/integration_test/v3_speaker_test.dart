import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/main.dart' as app;
import 'package:french_tutor/models/tutor_persona.dart';
import 'package:french_tutor/services/lesson_speech_service.dart';
import 'package:french_tutor/v3/lesson/v3_course.dart';
import 'package:french_tutor/v3/v3_prefs.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/probe.dart';

/// Speaker buttons must play a clip and never open a call or the microphone.
/// REAL audio generation (billable once): needs --dart-define=E2E_GEMINI_API_KEY.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final probe = Probe(binding);
  final clock = Stopwatch()..start();
  void mark(String m) => print('E2E_MARK ${clock.elapsedMilliseconds} $m');

  testWidgets('speaker tap plays a clip without a call', (tester) async {
    final semantics = tester.ensureSemantics();
    final name = ActiveTutor.current.displayName;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('dev_force_pro_unlock', true);
    final all = await V3Course.load();
    await prefs.setStringList(
      v3Key('v3_completed_lessons'),
      all.where((l) => l.id != 'a1-u01-words-1').map((l) => l.id).toList(),
    );
    await prefs.remove(v3Key('v3_lesson_position'));

    app.main();
    await probe.waitForLabel(
      tester,
      'Continue lesson',
      startsWith: true,
      timeout: const Duration(seconds: 60),
    );
    await probe.settle(tester, timeout: const Duration(seconds: 12));
    await probe.tapLabel(tester, 'Continue lesson', startsWith: true);
    await tester.pump(const Duration(milliseconds: 500));
    await probe.waitForLabel(tester, 'Talk to $name');

    Future<List<String>> labels() async =>
        (probe.describe(tester)['tappable']! as List)
            .map((e) => (e as Map)['label'] as String)
            .toList();

    final before = LessonSpeechService.clipEndsAt.value;
    final t1 = Stopwatch()..start();
    await probe.tapLabel(tester, 'Hear bonjour');
    var played = false;
    for (var i = 0; i < 100 && !played; i++) {
      await tester.pump(const Duration(milliseconds: 200));
      played = LessonSpeechService.clipEndsAt.value.isAfter(before);
    }
    mark('FIRST_TAP_PLAYED=$played after ${t1.elapsedMilliseconds}ms');
    expect(played, isTrue, reason: 'the clip must play');
    final l1 = await labels();
    expect(l1, isNot(contains('End call')), reason: 'no call may open');
    expect(l1, contains('Talk to $name'));
    await probe.capture(tester, '30_after_first_tap');

    await tester.pump(const Duration(seconds: 3));
    final mid = LessonSpeechService.clipEndsAt.value;
    final t2 = Stopwatch()..start();
    await probe.tapLabel(tester, 'Hear bonjour');
    var again = false;
    for (var i = 0; i < 50 && !again; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      again = LessonSpeechService.clipEndsAt.value.isAfter(mid);
    }
    mark('SECOND_TAP_PLAYED=$again after ${t2.elapsedMilliseconds}ms');
    expect(again, isTrue);
    expect(
      t2.elapsedMilliseconds,
      lessThan(1500),
      reason: 'a saved clip must replay at once',
    );
    expect(await labels(), isNot(contains('End call')));
    semantics.dispose();
  });
}
