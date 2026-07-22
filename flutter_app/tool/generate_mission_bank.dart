// One-off content-authoring script — NOT part of the shipped app. Run once
// (or re-run to refresh) to expand assets/content/missions.json from its
// original 5 hand-written scenarios to a large bank of LLM-generated
// scenario premises, one batch call per competency (not one call per
// scenario, and never called live during a real lesson) so today's app
// cost/latency profile is completely untouched.
//
// Usage:
//   GEMINI_API_KEY=your-key dart run tool/generate_mission_bank.dart
//
// Reuses the same schema every existing MissionDefinition consumer already
// reads (MissionTaskExecutor, LessonAgentService.buildMissionRoleplay) —
// this only adds MORE entries in that same shape, it doesn't change it.
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

const _geminiTextModel = 'gemini-flash-lite-latest';

// Balanced by CEFR LEVEL, not raw competency count — 200 scenarios per level
// band (A1/A2/B1/B2), split evenly across however many competencies that
// level has. A1/B1/B2 each have 2 competencies (100 each); A2 has 6 (33/34
// split so the 6 sum to 200).
const _targetPerCompetency = {
  'lex_identity_basics_a1': 100,
  'function_introduce_yourself_a1': 100,
  'lex_cafe_requests_a2': 33,
  'function_handle_cafe_order_a2': 33,
  'lex_professional_identity_core': 33,
  'grammar_present_self_description': 34,
  'phonology_french_r_work': 33,
  'function_introduce_professionally': 34,
  'strategy_listening_professional_details': 100,
  'discourse_professional_experience_sequence': 100,
  'discourse_defend_opinion_b2': 100,
  'strategy_manage_counterargument_b2': 100,
};

// The 5 original hand-written missions are kept verbatim — this only adds
// to the bank, it never discards curated content.
const _existingMissionsPath = 'assets/content/missions.json';
const _competencyGraphPath = 'assets/content/competency_graph_v1.json';

// A generated mission's steps reuse EXISTING content ids as evidence-
// tracking anchors (mirroring how a2_handle_a_cafe_order's listening step
// already reuses "l01" today) — `generatedScenario: true` on each step is
// what tells the runtime to show the fresh premise text instead of that
// anchor's own prewritten content, so this is not a hack, it's the
// established pattern extended to many more scenarios.
const _listeningAnchorId = 'l01';

// Only these 4 content ids actually have a `controlled_speaking` mapping in
// competency_graph_v1.json today (MissionCatalogValidator requires the
// (contentItemId, modality) pair to exist there, not just in
// resources.json's broader speakingTopics list) — using any other id here
// fails validation. Mapped per competency id, not "kind", since several
// competencies of the same kind still need different anchors.
const _speakingAnchorByCompetency = {
  'lex_identity_basics_a1': 'introduce_yourself_a1',
  'function_introduce_yourself_a1': 'introduce_yourself_a1',
  'lex_cafe_requests_a2': 'order_at_a_cafe_a2',
  'function_handle_cafe_order_a2': 'order_at_a_cafe_a2',
  'lex_professional_identity_core': 'introduce_yourself',
  'grammar_present_self_description': 'present',
  'phonology_french_r_work': 'present',
  'function_introduce_professionally': 'introduce_yourself',
  'strategy_listening_professional_details': 'introduce_yourself',
  'discourse_professional_experience_sequence': 'introduce_yourself',
  'discourse_defend_opinion_b2': 'present',
  'strategy_manage_counterargument_b2': 'present',
};

Future<void> main() async {
  final apiKey = Platform.environment['GEMINI_API_KEY'];
  if (apiKey == null || apiKey.isEmpty) {
    stderr.writeln(
      'Missing GEMINI_API_KEY. Run as: GEMINI_API_KEY=... dart run tool/generate_mission_bank.dart',
    );
    exit(1);
  }

  final existing =
      jsonDecode(await File(_existingMissionsPath).readAsString())
          as Map<String, dynamic>;
  final existingMissions = (existing['missions'] as List).cast<Map<String, dynamic>>();
  final curated = existingMissions.where((m) => !(m['id'] as String).startsWith('gen_')).toList();

  final graph = jsonDecode(await File(_competencyGraphPath).readAsString());
  final competencies = (graph['competencies'] as List).cast<Map<String, dynamic>>();

  // Group already-generated scenarios by competency so a re-run tops up to
  // the target instead of re-generating everything, and so the "avoid
  // repeating these" prompt context actually has something to work with.
  final existingByCompetency = <String, List<Map<String, dynamic>>>{};
  for (final mission in existingMissions) {
    final id = mission['id'] as String;
    if (!id.startsWith('gen_')) continue;
    final competencyId = mission['primaryCompetencyId'] as String;
    existingByCompetency.putIfAbsent(competencyId, () => []).add(mission);
  }

  var nextSeq = existingMissions.length + 1;
  final finalGenerated = <Map<String, dynamic>>[];

  for (final competency in competencies) {
    final id = competency['id'] as String;
    final title = competency['title'] as String;
    final description = competency['description'] as String;
    final levelBand = (competency['difficultyBand'] as String).toUpperCase();
    final target = _targetPerCompetency[id] ?? 50;

    final already = existingByCompetency[id] ?? const [];
    if (already.length > target) {
      // Trim surplus rather than discard-and-regenerate — no API call
      // needed, just keep the first `target` of what's already there.
      stdout.writeln('$id: trimming ${already.length} -> $target (no API call).');
      finalGenerated.addAll(already.take(target));
      continue;
    }
    if (already.length == target) {
      stdout.writeln('$id: already at target ($target), skipping.');
      finalGenerated.addAll(already);
      continue;
    }

    final needed = target - already.length;
    stdout.writeln('Generating $needed more scenarios for $id ($levelBand) -> $target total...');
    List<String> premises;
    try {
      premises = await _generatePremises(
        apiKey: apiKey,
        count: needed,
        competencyTitle: title,
        competencyDescription: description,
        levelBand: levelBand,
        avoid: already.map((m) => m['scenario'] as String).toList(),
      );
    } catch (e) {
      stderr.writeln('  Failed for $id: $e — keeping the ${already.length} already there.');
      finalGenerated.addAll(already);
      continue;
    }
    stdout.writeln('  Got ${premises.length} new distinct premises.');

    final speakingAnchor = _speakingAnchorByCompetency[id] ?? 'introduce_yourself_a1';
    finalGenerated.addAll(already);
    for (final premise in premises) {
      finalGenerated.add({
        'id': 'gen_${id}_${nextSeq++}',
        'title': title,
        'scenario': premise,
        'levelBand': levelBand,
        'primaryCompetencyId': id,
        'supportingCompetencyIds': <String>[],
        'goalIds': ['everyday', 'tef_canada'],
        'promptContext':
            'The learner is practising: $title. Scene: $premise Keep the exchange realistic, '
            'short, and true to this scene. Let the learner speak before offering a correction.',
        'steps': [
          {
            'id': 'understand_the_scene',
            'contentItemId': _listeningAnchorId,
            'modality': 'listening_recognition',
            'estimatedMinutes': 6,
            'evidenceGoal': 'Understand the situation and its key details.',
            'generatedScenario': true,
          },
          {
            'id': 'live_the_scene',
            'contentItemId': speakingAnchor,
            'modality': 'controlled_speaking',
            'estimatedMinutes': 8,
            'evidenceGoal': 'Handle the scene aloud in French.',
            'generatedScenario': true,
          },
        ],
      });
    }
  }

  final output = {
    'missions': [...curated, ...finalGenerated],
  };
  await File(_existingMissionsPath).writeAsString(
    const JsonEncoder.withIndent('  ').convert(output),
  );
  stdout.writeln(
    'Wrote ${curated.length} original + ${finalGenerated.length} generated '
    '= ${curated.length + finalGenerated.length} total missions to $_existingMissionsPath',
  );
}

Future<List<String>> _generatePremises({
  required String apiKey,
  required int count,
  required String competencyTitle,
  required String competencyDescription,
  required String levelBand,
  List<String> avoid = const [],
}) async {
  final avoidClause = avoid.isEmpty
      ? ''
      : '\n\nThese premises already exist — do not repeat any of them or anything too similar:\n'
            '${avoid.map((p) => '- $p').join('\n')}\n';

  final prompt =
      'Generate exactly $count distinct everyday-life scenario premises for a '
      'French learner at CEFR level $levelBand practicing: "$competencyTitle" ($competencyDescription).\n\n'
      'Each premise must be ONE short flowing moment from real life — not a category label, not '
      '"describe your day" or "explain your experience", but something like "You order a coffee '
      'to go, then run into a friend on your way out and chat briefly before you both head off." '
      'Vary the setting, the people involved, and how the moment unfolds — no two premises should '
      'feel like the same scene with different nouns swapped in. Keep each one to 1-2 sentences, '
      'appropriate for $levelBand vocabulary and complexity.$avoidClause\n'
      'Reply with ONLY a JSON array of $count strings, nothing else. No markdown '
      'fences, no commentary.';

  final uri = Uri.parse(
    'https://generativelanguage.googleapis.com/v1beta/models/$_geminiTextModel:generateContent?key=$apiKey',
  );
  final response = await http
      .post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [
            {
              'parts': [
                {'text': prompt},
              ],
            },
          ],
        }),
      )
      .timeout(const Duration(seconds: 60));

  if (response.statusCode < 200 || response.statusCode > 299) {
    throw Exception('HTTP ${response.statusCode}: ${response.body}');
  }
  final json = jsonDecode(response.body) as Map<String, dynamic>;
  final parts =
      ((json['candidates'] as List).first as Map<String, dynamic>)['content']
          as Map<String, dynamic>;
  final text = (parts['parts'] as List)
      .map((p) => (p as Map<String, dynamic>)['text'] as String? ?? '')
      .join();

  final extracted = _extractJSON(text);
  final list = jsonDecode(extracted) as List;
  final premises = list
      .map((e) => e.toString().trim())
      .where((s) => s.isNotEmpty)
      .toSet() // de-dupe within this single response
      .toList();
  if (premises.isEmpty) throw Exception('No premises parsed from response: $text');
  return premises;
}

/// Mirrors LessonAgentService.extractJSON — strips markdown code fences the
/// model sometimes wraps its JSON in despite being told not to.
String _extractJSON(String raw) {
  var s = raw.trim();
  if (s.startsWith('```')) {
    final firstNewline = s.indexOf('\n');
    if (firstNewline != -1) s = s.substring(firstNewline + 1);
    if (s.endsWith('```')) s = s.substring(0, s.length - 3);
  }
  return s.trim();
}
