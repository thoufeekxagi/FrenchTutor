import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:french_tutor/models/speak_curriculum.dart';
import 'package:french_tutor/services/speak_curriculum_catalog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bundled curriculum has unique, level-specific content keys', () {
    for (final entry in const {
      'A1': 120,
      'A2': 140,
      'B1': 160,
      'B2': 200,
    }.entries) {
      final items = SpeakCurriculumCatalog.bundled(entry.key);
      expect(items, hasLength(entry.value));
      expect(
        items.map((item) => item.contentKey).toSet(),
        hasLength(items.length),
      );
      expect(items.map((item) => item.title).toSet(), hasLength(items.length));
      expect(items.every((item) => item.level == entry.key), isTrue);
    }
  });

  test('every bundled roleplay has a complete scene contract', () {
    final items = SpeakCurriculumCatalog.bundled('A1');
    final roleplays = items.where(
      (item) => item.sessionKind == SpeakSessionKind.roleplay,
    );

    expect(roleplays, isNotEmpty);
    expect(
      roleplays.every(
        (item) =>
            item.roleplay != null &&
            item.roleplay!.lessonContext.contains(item.roleplay!.title),
      ),
      isTrue,
    );
  });

  test('A1 starts with the alphabet foundation sequence', () {
    final first = SpeakCurriculumCatalog.bundled('A1').take(5).toList();

    expect(first.map((item) => item.title), [
      'Meet the French alphabet',
      'Master French vowels',
      'Consonants and alphabet review',
      'Recognize core accent marks',
      'Connect sound to meaning',
    ]);
    expect(
      first.take(4).every((item) => item.primarySkill == SpeakSkill.alphabet),
      isTrue,
    );
    expect(first[4].primarySkill, SpeakSkill.vocabulary);
    expect(
      first
          .take(4)
          .every(
            (item) =>
                item.activitySkills.length == 2 &&
                item.activitySkills[0] == SpeakSkill.alphabet &&
                item.activitySkills[1] == SpeakSkill.vocabulary,
          ),
      isTrue,
    );
    expect(first[3].activitySkills, [
      SpeakSkill.alphabet,
      SpeakSkill.vocabulary,
    ]);
    expect(first[4].activitySkills, [
      SpeakSkill.vocabulary,
      SpeakSkill.alphabet,
      SpeakSkill.speaking,
    ]);
    expect(
      first.every(
        (item) =>
            !item.contextPrompt.contains('Arriving at the Station') &&
            !item.contextPrompt.contains('Use the course situation'),
      ),
      isTrue,
    );
  });

  test('legacy foundation rows cannot reintroduce generic speaking', () {
    final item = SpeakCurriculumItem.fromJson({
      'content_key': 'a1-unit-1-session-1',
      'level': 'A1',
      'unit_number': 1,
      'unit_title': 'Arriving at the Station',
      'session_index': 0,
      'title': 'Meet the French alphabet',
      'subtitle': 'Learn the letter names',
      'kind': 'speaking',
      'primary_skill': 'speaking',
      'supporting_skills': ['speaking', 'liaison'],
      'target_phrases': ['bonjour'],
    });

    expect(item.primarySkill, SpeakSkill.alphabet);
    expect(item.activitySkills, [SpeakSkill.alphabet, SpeakSkill.vocabulary]);
    expect(item.contextPrompt, isNot(contains('Arriving at the Station')));
  });

  test(
    'generated catalog asset parses and keeps every level complete',
    () async {
      final raw = await rootBundle.loadString(
        'assets/content/speak_course_catalog.json',
      );
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final rows = decoded['sessions'] as List<dynamic>;
      final items = rows
          .map(
            (row) => SpeakCurriculumItem.fromJson(
              Map<String, dynamic>.from(row as Map),
            ),
          )
          .toList(growable: false);

      for (final level in const ['A1', 'A2', 'B1', 'B2']) {
        final levelItems = items.where((item) => item.level == level).toList();
        expect(
          SpeakCurriculumRepository.isValid(levelItems, level),
          isTrue,
          reason: 'Generated $level catalog is incomplete or invalid.',
        );
      }
    },
  );
}
