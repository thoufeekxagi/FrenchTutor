// Publishes the generated French alphabet catalog to Supabase Storage and
// its public metadata table. Run only from an authoring environment with a
// service-role key; never put that key in the Flutter app or repository.
//
// Prerequisites: apply the alphabet_audio_catalog Supabase migration first.
// Usage:
//   SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... \
//     dart run tool/publish_alphabet_audio.dart
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

const _bucket = 'alphabet-audio';
const _manifestPath = 'assets/audio/alphabet/catalog.json';

Future<void> main(List<String> args) async {
  final storageOnly = args.contains('--storage-only');
  final personaFilter = _argValue(args, '--persona');
  final itemFilter = _argValue(args, '--items')
      ?.split(',')
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toSet();
  final supabaseUrl = Platform.environment['SUPABASE_URL'];
  final serviceRoleKey = Platform.environment['SUPABASE_SERVICE_ROLE_KEY'];
  if (supabaseUrl == null || supabaseUrl.isEmpty) {
    stderr.writeln('Missing SUPABASE_URL.');
    exitCode = 1;
    return;
  }
  if (serviceRoleKey == null || serviceRoleKey.isEmpty) {
    stderr.writeln('Missing SUPABASE_SERVICE_ROLE_KEY.');
    exitCode = 1;
    return;
  }

  final manifestFile = File(_manifestPath);
  if (!manifestFile.existsSync()) {
    stderr.writeln('Missing $_manifestPath. Generate the catalog first.');
    exitCode = 1;
    return;
  }
  final manifest = jsonDecode(await manifestFile.readAsString()) as Map;
  final items = (manifest['items'] as List)
      .cast<Map>()
      .where(
        (item) =>
            (personaFilter == null || item['persona_id'] == personaFilter) &&
            (itemFilter == null ||
                itemFilter.contains(item['content_item_id'])),
      )
      .toList();
  if (items.isEmpty) {
    throw StateError('No catalog items match the requested filters.');
  }
  final headers = {
    'Authorization': 'Bearer $serviceRoleKey',
    'apikey': serviceRoleKey,
  };
  if (!storageOnly) await _verifyCatalogTable(supabaseUrl, headers);
  await _ensureBucket(supabaseUrl, headers);

  for (final item in items) {
    final assetPath = item['asset_path'] as String;
    final localPath = assetPath;
    final bytes = await File(localPath).readAsBytes();
    final storagePath = '${item['persona_id']}/${item['content_item_id']}.pcm';
    final response = await http.post(
      Uri.parse('$supabaseUrl/storage/v1/object/$_bucket/$storagePath'),
      headers: {
        ...headers,
        'Content-Type': 'application/octet-stream',
        'x-upsert': 'true',
      },
      body: bytes,
    );
    if (response.statusCode < 200 || response.statusCode > 299) {
      throw StateError(
        'Storage upload failed for $storagePath: '
        '${response.statusCode} ${response.body}',
      );
    }
    item['storage_path'] = storagePath;
    stdout.writeln('Uploaded $storagePath');
  }

  if (storageOnly) {
    stdout.writeln(
      'Published ${items.length} audio files to Supabase Storage.',
    );
    return;
  }

  final response = await http.post(
    Uri.parse('$supabaseUrl/rest/v1/alphabet_audio_catalog'),
    headers: {
      ...headers,
      'Content-Type': 'application/json',
      'Prefer': 'resolution=merge-duplicates,return=minimal',
    },
    body: jsonEncode(items),
  );
  if (response.statusCode < 200 || response.statusCode > 299) {
    throw StateError(
      'Catalog upsert failed: ${response.statusCode} ${response.body}',
    );
  }
  stdout.writeln('Published ${items.length} catalog rows to Supabase.');
}

String? _argValue(List<String> args, String name) {
  final prefix = '$name=';
  for (final arg in args) {
    if (arg.startsWith(prefix)) return arg.substring(prefix.length);
  }
  return null;
}

Future<void> _verifyCatalogTable(
  String supabaseUrl,
  Map<String, String> headers,
) async {
  final response = await http.get(
    Uri.parse(
      '$supabaseUrl/rest/v1/alphabet_audio_catalog?select=asset_key&limit=1',
    ),
    headers: headers,
  );
  if (response.statusCode >= 200 && response.statusCode < 300) return;
  throw StateError(
    'alphabet_audio_catalog is not available. Apply the Supabase migration '
    'first: ${response.statusCode} ${response.body}',
  );
}

Future<void> _ensureBucket(
  String supabaseUrl,
  Map<String, String> headers,
) async {
  final response = await http.post(
    Uri.parse('$supabaseUrl/storage/v1/bucket'),
    headers: {...headers, 'Content-Type': 'application/json'},
    body: jsonEncode({'id': _bucket, 'name': _bucket, 'public': true}),
  );
  if (response.statusCode >= 200 && response.statusCode < 300) return;
  // A bucket that already exists is fine; the service-role key can still
  // upload into it. Any other response means the public upload cannot proceed.
  if (response.statusCode == 409 || response.statusCode == 400) return;
  throw StateError(
    'Could not create or verify Supabase bucket $_bucket: '
    '${response.statusCode} ${response.body}',
  );
}
