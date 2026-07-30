// Pure Dart, no Flutter needed — merges a journey log (simulate_journey_test.dart)
// and its judge verdicts (verify_journey.dart) into one PDF report per level.
//
// Usage:
//   dart run personalized_test_verification/generate_report.dart --level=a1
import 'dart:convert';
import 'dart:io';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

Future<void> main(List<String> args) async {
  final level = _argValue(args, 'level') ?? 'a1';

  final journeyPath = 'personalized_test_verification/output/${level}_journey.json';
  final verdictsPath = 'personalized_test_verification/output/${level}_verdicts.json';
  final journeyFile = File(journeyPath);
  if (!journeyFile.existsSync()) {
    stderr.writeln('Not found: $journeyPath — run simulate_journey_test.dart first.');
    exit(1);
  }
  final journey = jsonDecode(journeyFile.readAsStringSync()) as Map<String, dynamic>;
  final days = (journey['days'] as List).cast<Map<String, dynamic>>();

  final verdictsFile = File(verdictsPath);
  final verdictsByDay = <int, Map<String, dynamic>>{};
  if (verdictsFile.existsSync()) {
    final verdicts = jsonDecode(verdictsFile.readAsStringSync()) as Map<String, dynamic>;
    for (final v in (verdicts['verdicts'] as List).cast<Map<String, dynamic>>()) {
      verdictsByDay[v['day'] as int] = v;
    }
  } else {
    stderr.writeln(
      'Note: $verdictsPath not found — report will have no judge verdicts. '
      'Run verify_journey.dart first for the full report.',
    );
  }

  final doc = pw.Document();
  final levelBand = journey['levelBand'] as String? ?? level.toUpperCase();
  final totalErrors = days.fold<int>(
    0,
    (sum, d) => sum + ((d['errors'] as List?)?.length ?? 0),
  );
  final scored = verdictsByDay.values
      .where((v) => v['score'] != null)
      .map((v) => (v['score'] as num).toDouble())
      .toList();
  final avgScore = scored.isEmpty
      ? null
      : scored.reduce((a, b) => a + b) / scored.length;
  final flaggedDays = verdictsByDay.entries
      .where(
        (e) =>
            e.value['calibrationFlag'] == true || e.value['repetitionFlag'] == true,
      )
      .map((e) => e.key)
      .toList()
    ..sort();

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      build: (context) => [
        pw.Header(level: 0, text: 'Personalized content verification — $levelBand'),
        pw.Paragraph(
          text:
              'Days simulated: ${days.length}/${journey['daysRequested']}   '
              'Errors encountered: $totalErrors   '
              'Average judge score: ${avgScore?.toStringAsFixed(1) ?? 'n/a'}/5   '
              'Flagged days: ${flaggedDays.isEmpty ? 'none' : flaggedDays.join(', ')}',
        ),
        pw.SizedBox(height: 12),
        pw.Header(level: 1, text: 'Vocabulary growth'),
        pw.TableHelper.fromTextArray(
          headers: ['Day', 'Total cards', 'Phase 1 due', 'Phase 1 unseen', 'Phase 1 known'],
          data: [
            for (final d in days)
              [
                '${d['day']}',
                '${d['srsSnapshot']?['totalCards'] ?? '-'}',
                '${d['srsSnapshot']?['phase1Due'] ?? '-'}',
                '${d['srsSnapshot']?['phase1Unseen'] ?? '-'}',
                '${d['srsSnapshot']?['phase1Known'] ?? '-'}',
              ],
          ],
          cellStyle: const pw.TextStyle(fontSize: 8),
          headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 12),
        pw.Header(level: 1, text: 'Day-by-day content log'),
        for (final d in days) ..._daySection(d, verdictsByDay[d['day'] as int]),
      ],
    ),
  );

  final reportsDir = Directory('personalized_test_verification/reports');
  reportsDir.createSync(recursive: true);
  final outPath = '${reportsDir.path}/${levelBand}_report.pdf';
  await File(outPath).writeAsBytes(await doc.save());
  // ignore: avoid_print
  print('Wrote $outPath');
}

List<pw.Widget> _daySection(
  Map<String, dynamic> day,
  Map<String, dynamic>? verdict,
) {
  final vocab = day['vocab'] as Map<String, dynamic>?;
  final grammar = day['grammar'] as Map<String, dynamic>?;
  final listening = day['listening'] as Map<String, dynamic>?;
  final writing = day['writing'] as Map<String, dynamic>?;
  final roleplay = day['roleplay'] as Map<String, dynamic>?;
  final errors = (day['errors'] as List?) ?? const [];

  final vocabWords = ((vocab?['words'] as List?) ?? const [])
      .map((w) => (w as Map)['fr'])
      .join(', ');

  final lines = <String>[
    if (vocab != null)
      'Vocab: ${vocab['focusNote'] ?? vocab['error'] ?? ''} — $vocabWords',
    if (grammar != null)
      'Grammar: ${grammar['chosenTitle'] ?? grammar['error'] ?? grammar['note'] ?? ''}',
    if (listening != null)
      'Story/listening: ${listening['title'] ?? listening['error'] ?? ''}',
    if (writing != null)
      'Writing: ${writing['taskTitle'] ?? writing['error'] ?? ''}'
          '${writing['scoreOutOf10'] != null ? ' (${writing['scoreOutOf10']}/10)' : ''}',
    if (roleplay != null)
      'Roleplay: ${roleplay['scenario'] ?? ''} — ${roleplay['title'] ?? roleplay['error'] ?? ''}',
    if (errors.isNotEmpty) 'Harness errors: ${errors.join('; ')}',
    if (verdict != null)
      'Judge: score ${verdict['score'] ?? 'n/a'}/5 — ${verdict['comment'] ?? ''}'
          '${verdict['calibrationFlag'] == true ? ' [CALIBRATION: ${verdict['calibrationNote']}]' : ''}'
          '${verdict['repetitionFlag'] == true ? ' [REPETITION: ${verdict['repetitionNote']}]' : ''}',
  ];

  return [
    pw.Header(level: 2, text: 'Day ${day['day']} — ${day['simDate']}'),
    pw.Paragraph(text: lines.join('\n')),
  ];
}

String? _argValue(List<String> args, String name) {
  for (final arg in args) {
    if (arg.startsWith('--$name=')) return arg.substring('--$name='.length);
  }
  return null;
}
