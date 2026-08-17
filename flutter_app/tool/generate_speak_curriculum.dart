// Batch authoring tool for the shared Speak-style course catalog.
//
// Draft locally:
//   GEMINI_API_KEY=... dart run tool/generate_speak_curriculum.dart
//
// Publish only after review:
//   GEMINI_API_KEY=... SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... \
//   SPEAK_CURRICULUM_PUBLISH=1 dart run tool/generate_speak_curriculum.dart --publish
//
// The service-role key is intentionally read only from the shell. It must
// never be put in Flutter assets, dart-defines, or a mobile build.
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

const _geminiModel = 'gemini-flash-lite-latest';
const _levels = <String, int>{'A1': 12, 'A2': 14, 'B1': 16, 'B2': 20};
const _beginnerLevels = <String, int>{'A1': 12, 'A2': 14};
const _a2Levels = <String, int>{'A2': 14};
const _outputPath = 'assets/content/speak_course_catalog.json';
const _checkpointPath = 'assets/content/speak_course_catalog.draft.json';

Future<void> main(List<String> args) async {
  final apiKey = Platform.environment['GEMINI_API_KEY'];
  if (apiKey == null || apiKey.isEmpty) {
    stderr.writeln('Missing GEMINI_API_KEY.');
    exitCode = 1;
    return;
  }

  final publish = args.contains('--publish');
  final finalize = args.contains('--finalize');
  final relocalize = args.contains('--relocalize');
  final relocalizeBeginners = args.contains('--relocalize-beginners');
  final relocalizeA2 = args.contains('--relocalize-a2');
  if (publish && Platform.environment['SPEAK_CURRICULUM_PUBLISH'] != '1') {
    stderr.writeln(
      'Refusing to publish. Set SPEAK_CURRICULUM_PUBLISH=1 explicitly.',
    );
    exitCode = 1;
    return;
  }

  final rows = <Map<String, dynamic>>[];
  final checkpoint = File(_checkpointPath);
  if (checkpoint.existsSync()) {
    final decoded = jsonDecode(await checkpoint.readAsString());
    if (decoded is Map && decoded['sessions'] is List) {
      rows.addAll(
        (decoded['sessions'] as List).map(
          (row) => Map<String, dynamic>.from(row as Map),
        ),
      );
      stdout.writeln('Resuming from ${rows.length} checkpointed sessions.');
    }
  }
  if (finalize) {
    _addSkillMetadata(rows);
    _deduplicateTitles(rows);
    _validate(rows);
    final file = File(_outputPath);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert({'sessions': rows}),
    );
    stdout.writeln('Wrote ${rows.length} validated sessions to ${file.path}.');
    return;
  }
  if (relocalize) {
    await _relocalizeCatalog(
      rows,
      apiKey: apiKey,
      checkpoint: checkpoint,
      levels: relocalizeA2
          ? _a2Levels
          : relocalizeBeginners
          ? _beginnerLevels
          : _levels,
    );
    _addSkillMetadata(rows);
    _deduplicateTitles(rows);
    _validate(rows);
    final file = File(_outputPath);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert({'sessions': rows}),
    );
    stdout.writeln(
      'Wrote ${rows.length} relocalized sessions to ${file.path}.',
    );
    if (publish) {
      await _publish(rows);
      stdout.writeln('Published ${rows.length} sessions to course_sessions.');
    }
    return;
  }
  for (final entry in _levels.entries) {
    final level = entry.key;
    final unitCount = entry.value;
    for (var unit = 1; unit <= unitCount; unit++) {
      stdout.writeln('Generating $level unit $unit/$unitCount...');
      final prefix =
          '${level.toLowerCase()}_u${unit.toString().padLeft(2, '0')}_';
      if (rows
              .where(
                (row) =>
                    (row['content_key'] as String?)?.startsWith(prefix) == true,
              )
              .length ==
          10) {
        stdout.writeln('  already checkpointed; skipping.');
        continue;
      }
      final generated = await _generateUnitWithRetry(
        apiKey: apiKey,
        level: level,
        unit: unit,
      );
      rows.removeWhere(
        (row) => (row['content_key'] as String?)?.startsWith(prefix) == true,
      );
      rows.addAll(_normaliseUnit(generated, level: level, unit: unit));
      await checkpoint.writeAsString(
        const JsonEncoder.withIndent('  ').convert({'sessions': rows}),
      );
    }
  }

  await _repairDuplicateTitles(rows, apiKey: apiKey, checkpoint: checkpoint);
  _addSkillMetadata(rows);
  _validate(rows);
  final file = File(_outputPath);
  await file.writeAsString(
    const JsonEncoder.withIndent('  ').convert({'sessions': rows}),
  );
  stdout.writeln('Wrote ${rows.length} validated sessions to ${file.path}.');

  if (publish) {
    await _publish(rows);
    stdout.writeln('Published ${rows.length} sessions to course_sessions.');
  }
}

/// Rewrites only the copy shown in the course UI. The generated French
/// practice phrases remain untouched, so a beginner gets English guidance
/// without losing the actual language they need to practise.
Future<void> _relocalizeCatalog(
  List<Map<String, dynamic>> rows, {
  required String apiKey,
  required File checkpoint,
  required Map<String, int> levels,
}) async {
  if (rows.length != 620) {
    throw StateError(
      'Relocalization requires the complete 620-row catalog; found ${rows.length}.',
    );
  }
  for (final level in levels.keys) {
    final unitCount = levels[level]!;
    for (var unit = 1; unit <= unitCount; unit++) {
      final prefix =
          '${level.toLowerCase()}_u${unit.toString().padLeft(2, '0')}_';
      final unitRows = rows
          .where(
            (row) =>
                (row['content_key'] as String?)?.startsWith(prefix) == true,
          )
          .toList(growable: false);
      stdout.writeln('Relocalizing $level unit $unit/$unitCount...');
      final copy = await _relocalizeUnitWithRetry(
        apiKey: apiKey,
        level: level,
        unit: unit,
        rows: unitRows,
      );
      final generatedSessions = (copy['sessions'] as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList(growable: false);
      if (generatedSessions.length != unitRows.length) {
        throw StateError(
          'Relocalization returned the wrong number of sessions in $level unit $unit.',
        );
      }
      final relocalizedUnitTitle = _requiredCopy(copy, 'unit_title');
      final replacement = unitRows
          .asMap()
          .entries
          .map((entry) {
            final original = entry.value;
            // Pair by the stable catalog order. The source content_key is
            // always copied from the original row; an LLM is never trusted to
            // invent or mutate database identity fields.
            final generated = generatedSessions[entry.key];
            final merged = <String, dynamic>{
              ...original,
              'unit_title': relocalizedUnitTitle,
              'title': _requiredCopy(generated, 'title'),
              'subtitle': _requiredCopy(generated, 'subtitle'),
            };
            final originalScene = original['roleplay_scene'];
            final generatedScene = generated['roleplay_scene'];
            if (originalScene is Map && generatedScene is Map) {
              // Keep the actual tutor contract and French phrases stable. Only
              // the scene labels around that contract are translated/reframed.
              final scene = Map<String, dynamic>.from(originalScene);
              for (final field in [
                'title',
                'subtitle',
                'location',
                'learner_role',
                'tutor_role',
                'goal',
              ]) {
                final value = generatedScene[field];
                if (value is String && value.trim().isNotEmpty) {
                  scene[field] = value;
                }
              }
              merged['roleplay_scene'] = scene;
            }
            return merged;
          })
          .toList(growable: false);
      rows.removeWhere(
        (row) => (row['content_key'] as String?)?.startsWith(prefix) == true,
      );
      rows.addAll(replacement);
      await checkpoint.writeAsString(
        const JsonEncoder.withIndent('  ').convert({'sessions': rows}),
      );
    }
  }
}

Future<Map<String, dynamic>> _relocalizeUnitWithRetry({
  required String apiKey,
  required String level,
  required int unit,
  required List<Map<String, dynamic>> rows,
}) async {
  Object? lastError;
  for (var attempt = 1; attempt <= 3; attempt++) {
    try {
      final generated = await _relocalizeUnit(
        apiKey: apiKey,
        level: level,
        unit: unit,
        rows: rows,
      );
      final sessions = generated['sessions'];
      if (sessions is! List || sessions.length != rows.length) {
        throw StateError(
          '$level unit $unit returned ${sessions is List ? sessions.length : 0} copies, expected ${rows.length}.',
        );
      }
      return generated;
    } catch (error) {
      lastError = error;
      stderr.writeln('  relocalization attempt $attempt failed: $error');
      if (attempt < 3) await Future<void>.delayed(const Duration(seconds: 1));
    }
  }
  throw StateError(
    'Unable to relocalize $level unit $unit after 3 attempts: $lastError',
  );
}

Future<Map<String, dynamic>> _relocalizeUnit({
  required String apiKey,
  required String level,
  required int unit,
  required List<Map<String, dynamic>> rows,
}) async {
  final mix = switch (level) {
    'A1' => '85% English / 15% French',
    'A2' => '60% English / 40% French',
    'B1' => '40% English / 60% French',
    _ => '20% English / 80% French',
  };
  final source = rows
      .map(
        (row) => {
          'content_key': row['content_key'],
          'kind': row['kind'],
          'primary_skill': row['primary_skill'],
          'original_unit_title': row['unit_title'],
          'original_title': row['title'],
          'original_subtitle': row['subtitle'],
          if (row['roleplay_scene'] is Map)
            'roleplay_scene': {
              for (final field in [
                'id',
                'title',
                'subtitle',
                'location',
                'learner_role',
                'tutor_role',
                'goal',
              ].where((field) => (row['roleplay_scene'] as Map)[field] != null))
                field: (row['roleplay_scene'] as Map)[field],
            },
        },
      )
      .toList(growable: false);
  final prompt =
      '''
You are editing the learner-facing copy for Unit $unit of a serious French course.
Level: $level
Required presentation mix: $mix

Return ONLY valid JSON in this exact shape:
{"unit_title":"...","sessions":[{"content_key":"...","title":"...","subtitle":"...","roleplay_scene":null}]}

Return exactly one session copy for every input content_key, in the same order.
Never change a content_key. Never change the kind or primary skill. Do not add
scores, mastery claims, UI instructions, or fake grammar terminology.

Language policy:
- A1: the unit title, session titles, subtitles, and roleplay labels are clear
  English. This is a hard rule: do not copy the French source unit title. Include
  at most one short French phrase in a title/subtitle when it helps the learner
  recognise the target language. French target phrases are supplied separately
  and must not be rewritten here.
- A2: keep unit titles, explanations, and most labels in English. This is a hard
  rule: do not copy the French source unit title, and do not write a full French
  subtitle. Add only short natural French examples (no more than four words)
  to roughly 40% of the visible copy, not every line.
- B1: make French the main visible language, with concise English glosses where
  they remove ambiguity.
- B2: use natural French for almost all visible copy; use English only as a
  compact gloss when it genuinely helps.

Keep titles concise enough for a mobile course card. Make all ten titles
different within this unit. For roleplay_scene, return the same id and provide
only revised display fields: title, subtitle, location, learner_role,
tutor_role, and goal. Do not return opening_line or target_phrases.

Input rows:
${jsonEncode(source)}
''';
  final uri = Uri.parse(
    'https://generativelanguage.googleapis.com/v1beta/models/$_geminiModel:generateContent?key=$apiKey',
  );
  final response = await http.post(
    uri,
    headers: const {'content-type': 'application/json'},
    body: jsonEncode({
      'contents': [
        {
          'parts': [
            {'text': prompt},
          ],
        },
      ],
      'generationConfig': {
        'temperature': 0.35,
        'responseMimeType': 'application/json',
      },
    }),
  );
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw StateError('Gemini ${response.statusCode}: ${response.body}');
  }
  final body = jsonDecode(response.body) as Map<String, dynamic>;
  final parts =
      (((body['candidates'] as List).first as Map)['content'] as Map)['parts']
          as List;
  final raw = (parts.first as Map)['text'] as String;
  final decoded = jsonDecode(_stripCodeFence(raw));
  if (decoded is Map) return Map<String, dynamic>.from(decoded);
  throw StateError('Gemini returned no relocalized unit object.');
}

String _requiredCopy(Map<String, dynamic> row, String field) {
  final value = row[field];
  if (value is String && value.trim().isNotEmpty) return value.trim();
  throw StateError('Relocalized session is missing $field.');
}

Future<Map<String, dynamic>> _generateUnitWithRetry({
  required String apiKey,
  required String level,
  required int unit,
  List<String> avoidTitles = const [],
}) async {
  Object? lastError;
  for (var attempt = 1; attempt <= 3; attempt++) {
    try {
      final generated = await _generateUnit(
        apiKey: apiKey,
        level: level,
        unit: unit,
        avoidTitles: avoidTitles,
      );
      final sessions = generated['sessions'];
      if (sessions is! List || sessions.length != 10) {
        throw StateError(
          '$level unit $unit returned ${sessions is List ? sessions.length : 0} sessions, expected 10.',
        );
      }
      return generated;
    } catch (error) {
      lastError = error;
      stderr.writeln('  attempt $attempt failed: $error');
      if (attempt < 3) await Future<void>.delayed(const Duration(seconds: 1));
    }
  }
  throw StateError(
    'Unable to generate $level unit $unit after 3 attempts: $lastError',
  );
}

Future<Map<String, dynamic>> _generateUnit({
  required String apiKey,
  required String level,
  required int unit,
  List<String> avoidTitles = const [],
}) async {
  final avoidLine = avoidTitles.isEmpty
      ? ''
      : '\nDo not reuse any of these titles already used in $level: ${avoidTitles.join(' | ')}\n';
  final prompt =
      '''
You are authoring one unit for a serious French speaking course.
Level: $level
Unit number: $unit

Return ONLY valid compact JSON with this shape:
{"unit_title":"...","sessions":[{"title":"...","subtitle":"...","kind":"video|review|speaking|roleplay|story","estimated_minutes":7,"target_phrases":["..."],"roleplay_scene":null}]}

Write exactly 10 sessions for this unit. The ten sessions must have different
titles and different learning jobs in this order: notice, build, listen, use,
story, choose, roleplay, review, elaborate, roleplay. Do not reuse generic
titles such as "Say hi and goodbye" across units.

For roleplay sessions, roleplay_scene must be an object with exactly these
fields: id, level, title, subtitle, location, learner_role, tutor_role, goal,
opening_line, target_phrases. For other sessions it must be null.

Use realistic French contexts. Keep $level language appropriate. Do not add
scores, mastery claims, UI instructions, or invented grammar labels.
$avoidLine
''';
  final uri = Uri.parse(
    'https://generativelanguage.googleapis.com/v1beta/models/$_geminiModel:generateContent?key=$apiKey',
  );
  final response = await http.post(
    uri,
    headers: const {'content-type': 'application/json'},
    body: jsonEncode({
      'contents': [
        {
          'parts': [
            {'text': prompt},
          ],
        },
      ],
      'generationConfig': {
        'temperature': 0.7,
        'responseMimeType': 'application/json',
      },
    }),
  );
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw StateError('Gemini ${response.statusCode}: ${response.body}');
  }
  final body = jsonDecode(response.body) as Map<String, dynamic>;
  final text =
      (((body['candidates'] as List).first as Map)['content'] as Map)['parts']
          as List;
  final raw = (text.first as Map)['text'] as String;
  final decoded = jsonDecode(_stripCodeFence(raw));
  if (decoded is List) {
    // Some Gemini responses follow the requested sessions array but omit the
    // wrapper object. Keep that response usable while still validating every
    // row below.
    return {'unit_title': 'Unit $unit', 'sessions': decoded};
  }
  if (decoded is Map) return Map<String, dynamic>.from(decoded);
  throw StateError('Gemini returned neither an object nor a sessions array.');
}

List<Map<String, dynamic>> _normaliseUnit(
  Map<String, dynamic> raw, {
  required String level,
  required int unit,
}) {
  final sessions = raw['sessions'] as List? ?? const [];
  if (sessions.length != 10) {
    throw StateError(
      '$level unit $unit returned ${sessions.length} sessions, expected 10.',
    );
  }
  final unitTitle = raw['unit_title'] as String? ?? 'Unit $unit';
  return sessions
      .asMap()
      .entries
      .map((entry) {
        final index = entry.key;
        final value = Map<String, dynamic>.from(entry.value as Map);
        final key =
            '${level.toLowerCase()}_u${unit.toString().padLeft(2, '0')}_s${(index + 1).toString().padLeft(2, '0')}';
        value
          ..['content_key'] = key
          ..['level'] = level
          ..['unit_number'] = unit
          ..['unit_title'] = unitTitle
          ..['session_index'] = (unit - 1) * 10 + index
          ..['published'] = false
          ..['content_version'] = 1;
        return value;
      })
      .toList(growable: false);
}

Future<void> _repairDuplicateTitles(
  List<Map<String, dynamic>> rows, {
  required String apiKey,
  required File checkpoint,
}) async {
  for (final level in _levels.keys) {
    final seen = <String>{};
    final unitCount = _levels[level]!;
    for (var unit = 1; unit <= unitCount; unit++) {
      final prefix =
          '${level.toLowerCase()}_u${unit.toString().padLeft(2, '0')}_';
      var unitRows = rows
          .where(
            (row) =>
                (row['content_key'] as String?)?.startsWith(prefix) == true,
          )
          .toList(growable: false);
      final titles = unitRows
          .map((row) => (row['title'] as String).trim().toLowerCase())
          .toList();
      final needsRepair =
          unitRows.length != 10 ||
          titles.length != titles.toSet().length ||
          titles.any(seen.contains);
      if (needsRepair) {
        stdout.writeln('Repairing duplicate titles in $level unit $unit...');
        List<Map<String, dynamic>>? repaired;
        for (var attempt = 1; attempt <= 3 && repaired == null; attempt++) {
          final generated = await _generateUnitWithRetry(
            apiKey: apiKey,
            level: level,
            unit: unit,
            avoidTitles: [...seen, ...titles],
          );
          final candidate = _normaliseUnit(generated, level: level, unit: unit);
          final candidateTitles = candidate
              .map((row) => (row['title'] as String).trim().toLowerCase())
              .toList();
          if (candidateTitles.length == candidateTitles.toSet().length &&
              !candidateTitles.any(seen.contains)) {
            repaired = candidate;
          } else if (attempt == 3) {
            // Keep the generated learning content, but make the published
            // labels deterministic and unique rather than allowing two path
            // rows to collapse into the same title in the UI.
            repaired = _makeTitlesUnique(candidate, seen);
          }
        }
        final repairedRows = repaired!;
        rows.removeWhere(
          (row) => (row['content_key'] as String?)?.startsWith(prefix) == true,
        );
        rows.addAll(repairedRows);
        unitRows = repairedRows;
        await checkpoint.writeAsString(
          const JsonEncoder.withIndent('  ').convert({'sessions': rows}),
        );
      }
      seen.addAll(
        unitRows.map((row) => (row['title'] as String).trim().toLowerCase()),
      );
    }
  }
}

List<Map<String, dynamic>> _makeTitlesUnique(
  List<Map<String, dynamic>> rows,
  Set<String> alreadyUsed,
) {
  final used = {...alreadyUsed};
  return rows
      .map((row) {
        final original = (row['title'] as String).trim();
        var title = original;
        if (used.contains(title.toLowerCase())) {
          title = '$original · ${row['unit_title']}';
        }
        if (used.contains(title.toLowerCase())) {
          title =
              '$title · session ${(row['session_index'] as num).toInt() + 1}';
        }
        used.add(title.toLowerCase());
        return {...row, 'title': title};
      })
      .toList(growable: false);
}

void _validate(List<Map<String, dynamic>> rows) {
  final expectedCount = _levels.values.fold<int>(
    0,
    (sum, count) => sum + count * 10,
  );
  if (rows.length != expectedCount) {
    throw StateError('Expected $expectedCount sessions, found ${rows.length}.');
  }
  final keys = <String>{};
  final titles = <String>{};
  for (final entry in _levels.entries) {
    final count = rows.where((row) => row['level'] == entry.key).length;
    if (count != entry.value * 10) {
      throw StateError(
        'Expected ${entry.value * 10} ${entry.key} sessions, found $count.',
      );
    }
  }
  for (final row in rows) {
    final key = row['content_key'] as String?;
    final level = row['level'] as String?;
    final title = row['title'] as String?;
    if (key == null || level == null || title == null || title.trim().isEmpty) {
      throw StateError('A generated session is missing required fields.');
    }
    if (!keys.add(key)) throw StateError('Duplicate content_key: $key');
    final titleKey = '${level.toLowerCase()}::${title.trim().toLowerCase()}';
    if (!titles.add(titleKey)) {
      throw StateError('Duplicate title inside level: $title');
    }
    if (row['kind'] == 'roleplay' && row['roleplay_scene'] is! Map) {
      throw StateError('Roleplay $key has no roleplay_scene.');
    }
  }
}

void _deduplicateTitles(List<Map<String, dynamic>> rows) {
  for (final level in _levels.keys) {
    final levelRows = rows
        .where((row) => row['level'] == level)
        .toList(growable: false);
    final repaired = _makeTitlesUnique(levelRows, <String>{});
    rows.removeWhere((row) => row['level'] == level);
    rows.addAll(repaired);
  }
}

void _addSkillMetadata(List<Map<String, dynamic>> rows) {
  for (final row in rows) {
    if (row['primary_skill'] != null) continue;
    final unit = (row['unit_number'] as num? ?? 1).toInt();
    final sessionIndex = (row['session_index'] as num? ?? 0).toInt();
    final slot = sessionIndex % 10;
    final kind = (row['kind'] as String? ?? '').toLowerCase();
    final primary = kind == 'roleplay'
        ? 'roleplay'
        : unit == 1 && slot == 0
        ? 'alphabet'
        : unit == 1 && slot == 1
        ? 'connectors'
        : switch (slot) {
            0 => 'vocabulary',
            1 => 'reading',
            2 => 'listening',
            3 => 'grammar',
            4 => 'writing',
            5 => 'speaking',
            6 => 'roleplay',
            7 => 'review',
            8 => 'writing',
            _ => 'roleplay',
          };
    row['primary_skill'] = primary;
    row['supporting_skills'] = [
      if (primary != 'vocabulary') 'vocabulary',
      if (primary != 'speaking') 'speaking',
      if (unit == 1 && primary != 'liaison') 'liaison',
    ].take(2).toList(growable: false);
  }
}

Future<void> _publish(List<Map<String, dynamic>> rows) async {
  final baseUrl = Platform.environment['SUPABASE_URL'];
  final serviceKey = Platform.environment['SUPABASE_SERVICE_ROLE_KEY'];
  if (baseUrl == null ||
      serviceKey == null ||
      baseUrl.isEmpty ||
      serviceKey.isEmpty) {
    throw StateError(
      'SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required for publishing.',
    );
  }
  final uri = Uri.parse(
    '$baseUrl/rest/v1/course_sessions?on_conflict=content_key',
  );
  final headers = {
    'content-type': 'application/json',
    'apikey': serviceKey,
    'authorization': 'Bearer $serviceKey',
    'prefer': 'resolution=merge-duplicates,return=minimal',
  };

  // Keep each request small enough for the Data API while preserving an
  // idempotent upsert. A failed batch stops the publish; it never reports a
  // partial catalog as complete.
  const batchSize = 100;
  for (var start = 0; start < rows.length; start += batchSize) {
    final end = (start + batchSize < rows.length)
        ? start + batchSize
        : rows.length;
    final batch = rows
        .sublist(start, end)
        .map((row) => {...row, 'published': true})
        .toList(growable: false);
    final response = await http.post(
      uri,
      headers: headers,
      body: jsonEncode(batch),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Supabase ${response.statusCode} while publishing rows '
        '${start + 1}-$end: ${response.body}',
      );
    }
  }
}

String _stripCodeFence(String value) {
  final trimmed = value.trim();
  if (!trimmed.startsWith('```')) return trimmed;
  return trimmed
      .replaceFirst(RegExp(r'^```(?:json)?\s*'), '')
      .replaceFirst(RegExp(r'\s*```$'), '')
      .trim();
}
