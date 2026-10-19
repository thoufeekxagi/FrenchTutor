import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/models/tutor_persona.dart';
import 'package:french_tutor/v3/lesson/v3_lesson.dart';
import 'package:french_tutor/v3/lesson/v3_lesson_player.dart';
import 'package:french_tutor/v3/marie/v3_marie_session.dart';

class _Recording extends V3FakeMarieSession {
  final taps = <(String, String?)>[];
  @override
  Future<bool> speak(
    BuildContext context,
    String text, {
    bool reveal = true,
    String? asset,
  }) async {
    taps.add((text, asset));
    return true;
  }
}

/// The alphabet table: every letter bold, a speaker on every letter, two to a
/// line, played from the bundled recordings of the chosen tutor.
void main() {
  final lesson = V3Lesson.fromJson(
    jsonDecode(File('assets/content/tcf/lessons/s0-02.json').readAsStringSync())
        as Map<String, dynamic>,
  );
  final letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.split('');

  Future<_Recording> pump(WidgetTester tester, {Size? size}) async {
    tester.view.physicalSize = size ?? const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final marie = _Recording();
    addTearDown(marie.dispose);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: V3LessonPlayer(lesson: lesson, startAt: 1, marie: marie),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    return marie;
  }

  setUp(() => ActiveTutor.notifier.value = TutorPersona.marie);

  test('the recordings exist for all 26 letters for all four tutors', () {
    for (final tutor in TutorPersona.all) {
      for (final l in letters) {
        final f = File(
          'assets/audio/alphabet/${tutor.id}/alphabet_letter_$l.pcm',
        );
        expect(f.existsSync(), isTrue, reason: '${tutor.id} $l');
        expect(f.lengthSync(), greaterThan(2000), reason: '${tutor.id} $l');
        expect(f.lengthSync().isEven, isTrue);
      }
    }
  });

  testWidgets('every letter has a speaker and is bold', (tester) async {
    await pump(tester);
    for (final l in letters) {
      expect(
        find.byKey(ValueKey('table.letter.$l')),
        findsOneWidget,
        reason: l,
      );
      final text = tester.widget<Text>(find.text(l).first);
      expect(
        text.style!.fontWeight!.index,
        greaterThanOrEqualTo(FontWeight.w700.index),
        reason: '$l is bold',
      );
    }
  });

  testWidgets('two letters to a line on a phone', (tester) async {
    await pump(tester);
    double y(String l) => tester.getCenter(find.text(l).first).dy;
    expect((y('A') - y('B')).abs(), lessThan(2));
    expect((y('C') - y('D')).abs(), lessThan(2));
    expect(y('C') - y('A'), greaterThan(20), reason: 'C starts the next line');
    expect(
      (tester.getCenter(find.text('A').first).dx -
              tester.getCenter(find.text('B').first).dx)
          .abs(),
      greaterThan(100),
    );
  });

  testWidgets('one to a line on a very narrow screen or large text', (
    tester,
  ) async {
    await pump(tester, size: const Size(280, 1400));
    double y(String l) => tester.getCenter(find.text(l).first).dy;
    expect(y('B') - y('A'), greaterThan(20));
  });

  testWidgets('a tap plays the chosen tutor\'s bundled recording', (
    tester,
  ) async {
    final marie = await pump(tester);
    await tester.tap(find.byKey(const ValueKey('table.letter.G')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(marie.taps.single, (
      'G',
      'assets/audio/alphabet/marie/alphabet_letter_G.pcm',
    ));
  });

  testWidgets('another tutor plays their own recording', (tester) async {
    ActiveTutor.notifier.value = TutorPersona.byId('mathieu');
    final marie = await pump(tester);
    await tester.tap(find.byKey(const ValueKey('table.letter.Q')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      marie.taps.single.$2,
      'assets/audio/alphabet/mathieu/alphabet_letter_Q.pcm',
    );
  });
}
