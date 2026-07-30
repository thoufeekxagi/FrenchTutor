// Pure Dart, no Flutter needed — reads a journey log written by
// simulate_journey_test.dart and judges each day with Gemini Flash-Lite
// (same cheap model the app itself uses), flagging CEFR-calibration and
// repetition/variety problems a human wouldn't have time to read 30 days of
// content to spot.
//
// Usage:
//   GEMINI_API_KEY=xxx dart run personalized_test_verification/verify_journey.dart --level=a1
import 'dart:convert';
import 'dart:io';

import 'harness/gemini_text.dart';

Future<void> main(List<String> args) async {
  final level = _argValue(args, 'level') ?? 'a1';
  final apiKey = Platform.environment['GEMINI_API_KEY'];
  if (apiKey == null || apiKey.isEmpty) {
    stderr.writeln(
      'Set GEMINI_API_KEY, e.g.:\n'
      '  GEMINI_API_KEY=xxx dart run personalized_test_verification/verify_journey.dart --level=$level',
    );
    exit(1);
  }

  final journeyPath = 'personalized_test_verification/output/${level}_journey.json';
  final journeyFile = File(journeyPath);
  if (!journeyFile.existsSync()) {
    stderr.writeln('Not found: $journeyPath — run simulate_journey_test.dart first.');
    exit(1);
  }

  final journey = jsonDecode(journeyFile.readAsStringSync()) as Map<String, dynamic>;
  final levelBand = journey['levelBand'] as String? ?? level.toUpperCase();
  final days = (journey['days'] as List).cast<Map<String, dynamic>>();

  final verdictsPath =
      'personalized_test_verification/output/${level}_verdicts.json';
  final verdictsFile = File(verdictsPath);
  final verdicts = <Map<String, dynamic>>[];
  final client = GeminiTextClient(apiKey: apiKey);

  Map<String, dynamic>? previousSummary;
  for (final day in days) {
    final dayNum = day['day'];
    try {
      final verdict = await _judgeDay(
        client: client,
        levelBand: levelBand,
        day: day,
        previousSummary: previousSummary,
      );
      verdicts.add({'day': dayNum, ...verdict});
      // ignore: avoid_print
      print('$level day $dayNum judged: score=${verdict['score']}');
    } catch (e) {
      verdicts.add({
        'day': dayNum,
        'score': null,
        'error': '$e',
      });
      // ignore: avoid_print
      print('$level day $dayNum judge FAILED: $e');
    }
    previousSummary = _summaryFor(day);

    verdictsFile.parent.createSync(recursive: true);
    verdictsFile.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'level': level,
        'levelBand': levelBand,
        'daysJudged': verdicts.length,
        'judgeCallCount': client.callCount,
        'judgeCallErrors': client.errorCount,
        'verdicts': verdicts,
      }),
    );
  }

  // ignore: avoid_print
  print('Wrote $verdictsPath (${verdicts.length} days, ${client.callCount} judge calls)');
}

Map<String, dynamic> _summaryFor(Map<String, dynamic> day) {
  return {
    'vocabWords': ((day['vocab']?['words'] as List?) ?? const [])
        .map((w) => (w as Map)['fr'])
        .toList(),
    'grammarTitle': day['grammar']?['chosenTitle'],
    'storyTitle': day['listening']?['title'],
    'roleplayScenario': day['roleplay']?['scenario'],
    'writingTaskTitle': day['writing']?['taskTitle'],
  };
}

Future<Map<String, dynamic>> _judgeDay({
  required GeminiTextClient client,
  required String levelBand,
  required Map<String, dynamic> day,
  Map<String, dynamic>? previousSummary,
}) async {
  final vocabWords = ((day['vocab']?['words'] as List?) ?? const [])
      .map((w) => '${(w as Map)['fr']} (${w['en']})')
      .join(', ');
  final grammarCards = ((day['grammar']?['practiceCards'] as List?) ?? const [])
      .map((c) => (c as Map)['fr'])
      .join(' / ');

  final contentBlock =
      '''
Day ${day['day']} content for a CEFR $levelBand learner:

VOCAB focus: ${day['vocab']?['focusNote'] ?? '(none/error)'}
VOCAB words: $vocabWords

GRAMMAR topic: ${day['grammar']?['chosenTitle'] ?? '(none/error)'}
GRAMMAR practice sentences: $grammarCards

LISTENING/STORY title: ${day['listening']?['title'] ?? '(none/error)'}
LISTENING/STORY excerpt: ${day['listening']?['excerpt'] ?? ''}

WRITING prompt: ${day['writing']?['promptFr'] ?? '(none/error)'}
WRITING submission: ${day['writing']?['submission'] ?? ''}
WRITING score given by the app: ${day['writing']?['scoreOutOf10'] ?? 'n/a'}/10

ROLEPLAY scenario: ${day['roleplay']?['scenario'] ?? '(none/error)'}
ROLEPLAY title: ${day['roleplay']?['title'] ?? ''}
''';

  final previousBlock = previousSummary == null
      ? ''
      : '\nYesterday for comparison (flag repetition, not just similarity of '
            'genre): ${jsonEncode(previousSummary)}\n';

  final prompt =
      '''
You are a CEFR-fluent French curriculum reviewer. Judge whether the content
below is well-calibrated for a $levelBand learner and appropriately varied
from the previous day.
$contentBlock$previousBlock
Reply with ONLY this JSON object, nothing else, no markdown fences:
{
  "score": <integer 1-5, 5 = excellent day, 1 = seriously miscalibrated or broken>,
  "calibrationFlag": <true if anything here reads as clearly wrong for $levelBand — too easy, too hard, or grammatically incorrect French>,
  "calibrationNote": "<one sentence, empty string if calibrationFlag is false>",
  "repetitionFlag": <true if today's content is suspiciously similar/identical to yesterday's>,
  "repetitionNote": "<one sentence, empty string if repetitionFlag is false>",
  "comment": "<one or two sentence overall comment>"
}
''';

  final raw = await client.generate(prompt);
  final extracted = GeminiTextClient.extractJSON(raw);
  return jsonDecode(extracted) as Map<String, dynamic>;
}

String? _argValue(List<String> args, String name) {
  for (final arg in args) {
    if (arg.startsWith('--$name=')) return arg.substring('--$name='.length);
  }
  return null;
}
