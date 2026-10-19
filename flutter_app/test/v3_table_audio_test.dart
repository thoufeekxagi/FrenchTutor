import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/v3/lesson/v3_lesson.dart';
import 'package:french_tutor/v3/lesson/v3_lesson_player.dart';
import 'package:french_tutor/v3/marie/v3_marie_session.dart';

class _Recording extends V3FakeMarieSession {
  final said = <String>[];
  @override
  Future<bool> speak(
    BuildContext context,
    String text, {
    bool reveal = true,
    String? asset,
  }) async {
    said.add(text);
    return true;
  }
}

/// Numbers, months, minimal pairs and the other reference tables all have
/// audio, saying the French and nothing else.
void main() {
  V3Lesson load(String id) => V3Lesson.fromJson(
    jsonDecode(File('assets/content/tcf/lessons/$id.json').readAsStringSync())
        as Map<String, dynamic>,
  );

  Future<_Recording> pump(
    WidgetTester tester,
    String lessonId,
    int step, {
    Size size = const Size(390, 1600),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final marie = _Recording();
    addTearDown(marie.dispose);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: V3LessonPlayer(
            lesson: load(lessonId),
            startAt: step,
            frontier: step,
            marie: marie,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    return marie;
  }

  testWidgets('0 to 20: a speaker for each of the 21 numbers, in order', (
    tester,
  ) async {
    final marie = await pump(tester, 's0-10', 1);
    for (var i = 0; i < 21; i++) {
      expect(
        find.byKey(ValueKey('table.cell.$i')),
        findsOneWidget,
        reason: '$i',
      );
    }
    expect(find.byKey(const ValueKey('table.cell.21')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('table.cell.0')));
    await tester.tap(find.byKey(const ValueKey('table.cell.11')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(marie.said, ['zéro', 'onze']);
  });

  testWidgets('0 to 20: one per line on a phone, two on an iPad', (
    tester,
  ) async {
    await pump(tester, 's0-10', 1);
    double y(String t) => tester.getCenter(find.text(t).first).dy;
    expect(
      y('un, une') - y('zéro'),
      greaterThan(20),
      reason: 'phone: one a line',
    );

    await pump(tester, 's0-10', 1, size: const Size(1080, 1200));
    expect(
      (y('un, une') - y('zéro')).abs(),
      lessThan(2),
      reason: 'iPad: two a line',
    );
  });

  testWidgets('counting up to 1000 has a speaker on every row', (tester) async {
    final marie = await pump(tester, 's0-11', 1);
    final rows = load('s0-11').steps[1] as V3TableStep;
    for (var i = 0; i < rows.rows.length; i++) {
      expect(
        find.byKey(ValueKey('table.cell.$i')),
        findsOneWidget,
        reason: '$i',
      );
    }
    await tester.tap(find.byKey(const ValueKey('table.cell.1')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(marie.said.single, 'vingt et un');
  });

  testWidgets('the twelve months: twelve speakers, two to a line', (
    tester,
  ) async {
    final marie = await pump(tester, 'a1-u03-phrases', 14);
    for (var i = 0; i < 12; i++) {
      expect(
        find.byKey(ValueKey('table.cell.$i')),
        findsOneWidget,
        reason: '$i',
      );
    }
    double y(String t) => tester.getCenter(find.text(t).first).dy;
    expect((y('janvier') - y('février')).abs(), lessThan(2));
    await tester.tap(find.byKey(const ValueKey('table.cell.7')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(marie.said.single, 'août');
  });

  testWidgets('minimal pairs: tap a word to hear it, the dash is silent', (
    tester,
  ) async {
    final marie = await pump(tester, 's0-05', 1);
    await tester.tap(find.byKey(const ValueKey('table.hear.0.0')));
    await tester.tap(find.byKey(const ValueKey('table.hear.0.1')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(marie.said, ['tu', 'tout']);
    expect(find.byKey(const ValueKey('table.hear.0.2')), findsNothing);
  });

  testWidgets('liaison: the speaker says the written French', (tester) async {
    final semantics = tester.ensureSemantics();
    final marie = await pump(tester, 's0-09', 1);
    await tester.tap(find.bySemanticsLabel('Hear les amis'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(marie.said.single, 'les amis');
    semantics.dispose();
  });

  testWidgets('a conjugation: tap a form, hear it with its pronoun', (
    tester,
  ) async {
    final marie = await pump(tester, 'a1-u04-grammar-c', 0);
    await tester.tap(find.byKey(const ValueKey('table.hear.0.1')));
    await tester.tap(find.byKey(const ValueKey('table.hear.1.1')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(marie.said, ['je parle', 'tu parles']);
  });
}
