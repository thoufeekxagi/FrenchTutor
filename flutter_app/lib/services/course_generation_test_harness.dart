import 'package:flutter/foundation.dart';

import '../models/speak_curriculum.dart';

/// The one development-only course lane currently under verification.
///
/// This is intentionally a compile-time switch rather than a persisted user
/// setting. Release builds can never activate it, and changing the selected
/// skill for the next verification pass does not require another harness or a
/// second course schema.
enum CourseGenerationHarnessSkill {
  speaking,
  vocabulary,
  reading,
  listening,
  writing,
}

extension CourseGenerationHarnessSkillValues on CourseGenerationHarnessSkill {
  SpeakSkill get speakSkill => switch (this) {
    CourseGenerationHarnessSkill.speaking => SpeakSkill.speaking,
    CourseGenerationHarnessSkill.vocabulary => SpeakSkill.vocabulary,
    CourseGenerationHarnessSkill.reading => SpeakSkill.reading,
    CourseGenerationHarnessSkill.listening => SpeakSkill.listening,
    CourseGenerationHarnessSkill.writing => SpeakSkill.writing,
  };

  String get wireName => speakSkill.wireName;

  static CourseGenerationHarnessSkill parse(String value) =>
      switch (value.trim().toLowerCase().replaceAll('-', '_')) {
        'vocabulary' || 'vocab' => CourseGenerationHarnessSkill.vocabulary,
        'reading' => CourseGenerationHarnessSkill.reading,
        'listening' => CourseGenerationHarnessSkill.listening,
        'writing' || 'write' => CourseGenerationHarnessSkill.writing,
        _ => CourseGenerationHarnessSkill.speaking,
      };
}

/// Development-only policy for serial Course generation verification.
///
/// Enable a debug build to test one skill with the default lane. The next lane
/// can be selected without creating another implementation:
///
/// `--dart-define=PARLESPRINT_COURSE_HARNESS_SKILL=vocabulary`
/// `--dart-define=PARLESPRINT_COURSE_HARNESS_ENABLED=false`
class CourseGenerationTestHarness {
  const CourseGenerationTestHarness({
    required this.enabled,
    required this.skill,
  });

  static const disabled = CourseGenerationTestHarness(
    enabled: false,
    skill: CourseGenerationHarnessSkill.speaking,
  );

  /// The app's current development configuration. `kDebugMode` is checked in
  /// [active] as the second guard, so a release/profile build cannot turn this
  /// path on accidentally even if a dart-define is left in a build script.
  static final current = CourseGenerationTestHarness(
    // Development verification must not depend on an Xcode-generated
    // DART_DEFINES entry surviving a device reinstall. Keep the lane on for
    // every Debug run, while [active] still prevents it from ever running in
    // Profile or Release. The define remains available for documentation and
    // future lane selection.
    enabled:
        kDebugMode ||
        bool.fromEnvironment(
          'PARLESPRINT_COURSE_HARNESS_ENABLED',
          defaultValue: false,
        ),
    skill: CourseGenerationHarnessSkillValues.parse(
      String.fromEnvironment(
        'PARLESPRINT_COURSE_HARNESS_SKILL',
        // Speaking, Vocabulary, and Writing have completed their verification
        // passes. Reading is the active development-only lane now; an
        // explicit dart-define can still select any supported skill when the
        // build tool preserves it.
        defaultValue: 'reading',
      ),
    ),
  );

  final bool enabled;
  final CourseGenerationHarnessSkill skill;

  bool get active => kDebugMode && enabled;

  SpeakSkill get targetSkill => skill.speakSkill;

  String get targetWireName => skill.wireName;

  /// Unit 1 is the foundation and Unit 2 is the authored five-skill block.
  /// The harness begins only after the authored boundary, but its trigger is
  /// the selected Unit 2 skill rather than completion of unrelated activities.
  bool shouldAdvanceAfter({
    required int sequence,
    required SpeakSkill primarySkill,
  }) => active && sequence > 5 && primarySkill == targetSkill;

  bool shouldForcePersonalizedSkill(int sequence) => active && sequence > 10;

  /// Existing non-target personalized rows are hidden from the development
  /// roadmap. They are never deleted or rewritten; this only keeps the test
  /// lane focused while the general course remains intact.
  bool includeInRoadmap({
    required int sequence,
    required SpeakSkill primarySkill,
  }) => !active || sequence <= 10 || primarySkill == targetSkill;
}
