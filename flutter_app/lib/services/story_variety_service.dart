/// Shared variety and duplicate guards for learner-generated stories.
///
/// Surprise mode is a product promise: a new request must not silently turn
/// into another copy of the last story. The language model still creates the
/// prose, but this class gives it a changing concrete direction and provides
/// a deterministic guard before content is shown or saved.
abstract final class StoryVarietyService {
  static const surpriseSeeds = <String>[
    'a lost library card found inside a returned book',
    'a community garden deciding where to plant one empty pot',
    'a baker testing a new bread recipe before opening time',
    'a bicycle bell that helps someone find a missed turn',
    'a handwritten note tucked under a café table',
    'a neighbour sharing a tool during a small home repair',
    'a bus passenger returning a scarf left on a seat',
    'a morning market stall preparing for an unexpected delivery',
    'a museum visitor noticing a small detail in a painting',
    'a paper boat drifting beside a city bridge after rain',
    'a student solving a timetable mix-up before class',
    'a balcony plant recovering after a windy night',
    'a parcel arriving at the wrong apartment and finding its owner',
    'a public announcement that changes an afternoon plan',
    'a musician tuning an old instrument in a quiet hallway',
    'a reusable lunch box exchanged by mistake at work',
    'a street photographer waiting for the right reflection',
    'a small charity shelf receiving an unusual donation',
    'a train platform clock that is a few minutes behind',
    'a recipe card translated for a family dinner',
    'a rainy bus stop where strangers share an umbrella',
    'a missing key discovered beside a pair of garden gloves',
    'a local shop displaying an object from its neighbourhood history',
    'a free workshop where one person teaches a practical skill',
    'a notebook passed between coworkers during a busy day',
    'a quiet park bench with a message carved by a former visitor',
    'a small office choosing a thoughtful welcome for a new colleague',
    'a coastal path where the tide changes the planned walk',
    'a library noticeboard connecting two people with the same hobby',
    'a lantern helping someone read an address after sunset',
    'a forgotten umbrella reunited with its owner at a reception desk',
    'a community kitchen adapting a meal for one unexpected guest',
  ];

  static int _sequence = 0;

  /// Chooses a seed that is not already represented in the learner's recent
  /// story text. The sequence makes two calls made in the same microsecond
  /// choose different starting points as well.
  static String chooseSeed({Iterable<String> avoidTexts = const []}) {
    final blocked = avoidTexts.map(normalize).where((text) => text.isNotEmpty);
    final available = surpriseSeeds
        .where(
          (seed) =>
              !blocked.any((text) => _meaningfulWords(seed).any(text.contains)),
        )
        .toList(growable: false);
    final pool = available.isEmpty ? surpriseSeeds : available;
    final index =
        (DateTime.now().microsecondsSinceEpoch + _sequence++) % pool.length;
    return pool[index];
  }

  static bool isDuplicate({
    required String title,
    required String opening,
    Iterable<String> avoidTitles = const [],
    Iterable<String> avoidOpenings = const [],
  }) {
    final normalizedTitle = normalize(title);
    final normalizedOpening = normalize(opening);
    if (normalizedTitle.isEmpty && normalizedOpening.isEmpty) return true;

    final titleMatch =
        normalizedTitle.isNotEmpty &&
        avoidTitles.map(normalize).any((prior) => prior == normalizedTitle);
    final openingMatch =
        normalizedOpening.isNotEmpty &&
        avoidOpenings.map(normalize).any((prior) => prior == normalizedOpening);
    return titleMatch || openingMatch;
  }

  /// One compact fingerprint for suppressing already-saved duplicate cards.
  static String storyFingerprint({
    required String title,
    required String opening,
  }) => '${normalize(title)}|${normalize(opening)}';

  static String exclusionPrompt({
    Iterable<String> titles = const [],
    Iterable<String> openings = const [],
  }) {
    final values = <String>[];
    for (final title in titles) {
      final value = title.trim();
      if (value.isNotEmpty && !values.contains(value)) values.add(value);
      if (values.length == 12) break;
    }
    for (final opening in openings) {
      final value = opening.trim();
      if (value.isNotEmpty && !values.contains(value)) values.add(value);
      if (values.length == 18) break;
    }
    if (values.isEmpty) {
      return 'There are no prior stories to exclude. Do not use a cat or kitten as the default surprise premise.';
    }
    return '''RECENT STORIES TO AVOID:
${values.map((value) => '- $value').join('\n')}
Do not reuse any listed title, opening sentence, main premise, character, or dominant image. Do not use a cat or kitten as a default surprise premise.''';
  }

  static String normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r"[^\p{L}\p{N}]+", unicode: true), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static Iterable<String> _meaningfulWords(String value) =>
      normalize(value).split(' ').where((word) => word.length >= 5);
}
