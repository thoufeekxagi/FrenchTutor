import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/data/database/learning_store.dart';
import 'package:french_tutor/providers/database_provider.dart';
import 'package:french_tutor/v3/lesson/v3_lesson.dart';
import 'package:french_tutor/v3/lesson/v3_lesson_player.dart';
import 'package:french_tutor/v3/marie/v3_marie_session.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'support/probe.dart';

/// Real-device screenshots of the reference tables with their speakers.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final probe = Probe(binding);

  testWidgets('reference tables with speakers', (tester) async {
    final semantics = tester.ensureSemantics();
    final db = sqlite3.openInMemory();
    addTearDown(db.dispose);
    final store = LearningStore(db);
    final marie = V3FakeMarieSession();
    addTearDown(marie.dispose);

    Future<void> show(String id, int step, String shot) async {
      final raw = await rootBundle.loadString(
        'assets/content/tcf/lessons/$id.json',
      );
      final lesson = V3Lesson.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [learningStoreProvider.overrideWithValue(store)],
          child: MaterialApp(
            key: UniqueKey(),
            home: V3LessonPlayer(
              lesson: lesson,
              startAt: step,
              frontier: step,
              marie: marie,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await probe.capture(tester, shot);
    }

    await show('s0-02', 1, 'tbl_01_letters');
    await show('s0-10', 1, 'tbl_02_zero_to_twenty');
    await show('s0-11', 1, 'tbl_03_counting');
    await show('a1-u03-phrases', 14, 'tbl_04_months');
    await show('s0-05', 1, 'tbl_05_minimal_pairs');
    await show('a1-u04-grammar-c', 0, 'tbl_06_conjugation');
    await show('s0-09', 1, 'tbl_07_liaison');
    semantics.dispose();
  });
}
