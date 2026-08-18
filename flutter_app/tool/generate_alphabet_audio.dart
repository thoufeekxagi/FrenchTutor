// One-off authoring tool for the static French alphabet audio catalog.
//
// Generates 31 clips (26 letters + 5 accents) for each of the four tutor
// voices and writes raw 24kHz mono PCM16 assets under
// assets/audio/alphabet/<persona>/.
//
// Usage:
//   OPENROUTER_API_KEY=... dart run tool/generate_alphabet_audio.dart
//   OPENROUTER_API_KEY=... dart run tool/generate_alphabet_audio.dart --force
//
// The input is deliberately French and explicitly asks for only the French
// name. OpenRouter's dedicated speech endpoint is used for fixed, exact
// recitation that can be packaged and replayed offline.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

const _model = 'google/gemini-3.1-flash-tts-preview';
const _requestSpacing = Duration(seconds: 12);

class _RateLimitError implements Exception {
  const _RateLimitError(this.message);
  final String message;

  @override
  String toString() => message;
}

const _voices = {
  'marie': ('Aoede', 'France'),
  'julien': ('Puck', 'France'),
  'camille': ('Leda', 'Québec'),
  'mathieu': ('Orus', 'Québec'),
};

const _items = {
  'alphabet_letter_A': ('A', 'a'),
  'alphabet_letter_B': ('B', 'bé'),
  'alphabet_letter_C': ('C', 'cé'),
  'alphabet_letter_D': ('D', 'dé'),
  'alphabet_letter_E': ('E', 'e'),
  'alphabet_letter_F': ('F', 'effe'),
  'alphabet_letter_G': ('G', 'gé'),
  'alphabet_letter_H': ('H', 'ache'),
  'alphabet_letter_I': ('I', 'i'),
  'alphabet_letter_J': ('J', 'ji'),
  'alphabet_letter_K': ('K', 'ka'),
  'alphabet_letter_L': ('L', 'elle'),
  'alphabet_letter_M': ('M', 'emme'),
  'alphabet_letter_N': ('N', 'enne'),
  'alphabet_letter_O': ('O', 'o'),
  'alphabet_letter_P': ('P', 'pé'),
  'alphabet_letter_Q': ('Q', 'ku'),
  'alphabet_letter_R': ('R', 'ère'),
  'alphabet_letter_S': ('S', 'esse'),
  'alphabet_letter_T': ('T', 'té'),
  'alphabet_letter_U': ('U', 'u'),
  'alphabet_letter_V': ('V', 'vé'),
  'alphabet_letter_W': ('W', 'double vé'),
  'alphabet_letter_X': ('X', 'ixe'),
  'alphabet_letter_Y': ('Y', 'i grec'),
  'alphabet_letter_Z': ('Z', 'zède'),
  'alphabet_accent_e_acute': ('É', 'accent aigu'),
  'alphabet_accent_e_grave': ('È', 'accent grave'),
  'alphabet_accent_e_circumflex': ('Ê', 'accent circonflexe'),
  'alphabet_accent_c_cedilla': ('Ç', 'cédille'),
  'alphabet_accent_e_diaeresis': ('Ë', 'tréma'),
};

Future<void> main(List<String> args) async {
  final apiKey = Platform.environment['OPENROUTER_API_KEY'];
  if (apiKey == null || apiKey.isEmpty) {
    stderr.writeln(
      'Missing OPENROUTER_API_KEY. Run with OPENROUTER_API_KEY in the environment.',
    );
    exitCode = 1;
    return;
  }

  final force = args.contains('--force');
  final personaFilter = _argValue(args, '--persona');
  final itemFilter = _argValue(args, '--items')
      ?.split(',')
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toSet();
  final voices = _voices.entries.where(
    (entry) => personaFilter == null || entry.key == personaFilter,
  );
  if (personaFilter != null && !_voices.containsKey(personaFilter)) {
    stderr.writeln('Unknown persona: $personaFilter');
    exitCode = 1;
    return;
  }
  final itemsToGenerate = _items.entries.where(
    (entry) => itemFilter == null || itemFilter.contains(entry.key),
  );
  if (itemFilter != null &&
      itemFilter.any((item) => !_items.containsKey(item))) {
    stderr.writeln('Unknown alphabet item in --items.');
    exitCode = 1;
    return;
  }
  final root = Directory('assets/audio/alphabet');
  await root.create(recursive: true);
  final isPartial = personaFilter != null || itemFilter != null;
  final catalogByKey = <String, Map<String, Object>>{};
  final existingManifest = File('${root.path}/catalog.json');
  if (isPartial && existingManifest.existsSync()) {
    final existing = jsonDecode(await existingManifest.readAsString()) as Map;
    for (final item in (existing['items'] as List).cast<Map>()) {
      final normalized = item.map(
        (key, value) => MapEntry(key.toString(), value),
      );
      catalogByKey[normalized['asset_key'] as String] =
          Map<String, Object>.from(normalized);
    }
  }

  for (final entry in voices) {
    final personaId = entry.key;
    final (voiceName, accent) = entry.value;
    final personaDir = Directory('${root.path}/$personaId');
    await personaDir.create(recursive: true);

    for (final item in itemsToGenerate) {
      final id = item.key;
      final (letter, spokenName) = item.value;
      final file = File('${personaDir.path}/$id.pcm');
      List<int> bytes;
      if (file.existsSync() && !force) {
        bytes = await file.readAsBytes();
      } else {
        stdout.writeln('$personaId/$id ($letter, $accent French)');
        bytes = await _generate(
          apiKey,
          audioId: id,
          voiceName: voiceName,
          letter: letter,
          spokenName: spokenName,
        );
        await file.writeAsBytes(bytes, flush: true);
        // Keep the authoring batch strictly sequential and well below the
        // project quota. The per-request delay also applies on the next call.
        await Future<void>.delayed(_requestSpacing);
      }
      if (bytes.isEmpty || bytes.length.isOdd) {
        throw StateError('Invalid PCM returned for $personaId/$id');
      }
      catalogByKey['$personaId/$id'] = {
        'asset_key': '$personaId/$id',
        'persona_id': personaId,
        'voice_name': voiceName,
        'accent': accent,
        'content_item_id': id,
        'letter': letter,
        'spoken_text': spokenName,
        'asset_path': 'assets/audio/alphabet/$personaId/$id.pcm',
        'sha256': sha256.convert(bytes).toString(),
        'bytes': bytes.length,
        'sample_rate_hz': 24000,
        'channels': 1,
        'encoding': 'pcm_s16le',
      };
    }
  }

  final manifest = File('${root.path}/catalog.json');
  final catalog = catalogByKey.values.toList()
    ..sort(
      (a, b) => (a['asset_key'] as String).compareTo(b['asset_key'] as String),
    );
  await manifest.writeAsString(
    const JsonEncoder.withIndent('  ').convert({
      'version': 1,
      'language': 'fr-FR',
      'model': _model,
      'items': catalog,
    }),
  );
  stdout.writeln(
    'Wrote ${catalog.length} French alphabet clips and ${manifest.path}.',
  );
}

String? _argValue(List<String> args, String name) {
  final prefix = '$name=';
  for (final arg in args) {
    if (arg.startsWith(prefix)) return arg.substring(prefix.length);
  }
  return null;
}

Future<List<int>> _generate(
  String apiKey, {
  required String audioId,
  required String voiceName,
  required String letter,
  required String spokenName,
}) async {
  const maxAttempts = 4;
  // Keep a real French transcript in the request. For accent cards the
  // transcript is the marked character itself, not the label or an example
  // word. The selected Gemini TTS model receives it through OpenRouter and
  // returns raw PCM bytes.
  final transcript = _ttsTranscript(audioId, spokenName);
  // For accents, send only the marked grapheme. Adding prose such as
  // “accent aigu” or an instruction around a one-character input can make the
  // TTS provider return an empty stream, and would also risk speaking the
  // label instead of the sound. The card's teaching copy remains separate.
  final prompt = _isDirectSound(audioId)
      ? transcript
      : '[clear, careful, isolated French pronunciation] $transcript.';
  final uri = Uri.parse('https://openrouter.ai/api/v1/audio/speech');
  var attempt = 0;

  while (attempt < maxAttempts) {
    attempt++;
    // Deliberately one request at a time with a conservative gap. This is an
    // authoring job, not a latency-sensitive product path.
    await Future<void>.delayed(_requestSpacing);
    try {
      final response = await http
          .post(
            uri,
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
              'HTTP-Referer': 'https://parlesprint.com',
              'X-Title': 'ParleSprint alphabet authoring',
            },
            body: jsonEncode({
              'model': _model,
              'input': prompt,
              'voice': voiceName,
              'response_format': 'pcm',
            }),
          )
          .timeout(const Duration(seconds: 60));
      if (response.statusCode < 200 || response.statusCode > 299) {
        if (response.statusCode == 429 || response.statusCode == 402) {
          throw _RateLimitError(
            'OpenRouter speech request stopped for $voiceName/$letter '
            '(HTTP ${response.statusCode}). Completed assets will be '
            'skipped. Provider response: ${response.body}',
          );
        }
        if (attempt == maxAttempts) {
          throw StateError(
            'OpenRouter speech failed with HTTP ${response.statusCode}: '
            '${response.body}',
          );
        }
        await Future<void>.delayed(Duration(seconds: attempt));
        continue;
      }

      final bytes = response.bodyBytes;
      if (bytes.isEmpty || bytes.length.isOdd) {
        throw StateError(
          'OpenRouter returned invalid PCM for $voiceName/$letter',
        );
      }
      return bytes;
    } on _RateLimitError {
      rethrow;
    } catch (error) {
      if (attempt == maxAttempts) rethrow;
      await Future<void>.delayed(Duration(seconds: attempt));
    }
  }
  throw StateError('Unreachable');
}

String _ttsTranscript(String audioId, String spokenName) => switch (audioId) {
  'alphabet_letter_F' => 'effe',
  'alphabet_letter_J' => 'ji',
  'alphabet_letter_A' => 'ami',
  // “euh” is the French schwa sound; “le” adds an article and is not the
  // letter itself.
  'alphabet_letter_E' => 'euh',
  'alphabet_letter_I' => 'i',
  // Keep O as the isolated letter sound. “eau” is a useful spelling example,
  // but it is a word and must not be read when the learner taps the letter.
  'alphabet_letter_O' => 'o',
  // A repeated isolated vowel keeps the provider from dropping a one-letter
  // request while avoiding a carrier/example word such as “tu”.
  'alphabet_letter_U' => 'u u',
  // These must stay as isolated graphemes. The card labels and examples are
  // still shown in the UI, but tapping the speaker must teach the sound and
  // must never read “accent aigu”, “père”, “forêt”, or another example word.
  'alphabet_accent_e_acute' => 'é',
  'alphabet_accent_e_grave' => 'è',
  // Ê and Ë do not introduce a separate vowel sound in these beginner
  // cards; they use the open-e sound. Ç has no vowel of its own, so a single
  // short “ça” carrier is the smallest reliable sample of its /s/ sound.
  'alphabet_accent_e_circumflex' => 'è',
  'alphabet_accent_c_cedilla' => 'ça',
  'alphabet_accent_e_diaeresis' => 'è',
  _ => spokenName,
};

bool _isAccent(String audioId) => audioId.startsWith('alphabet_accent_');

bool _isDirectSound(String audioId) =>
    _isAccent(audioId) ||
    switch (audioId) {
      'alphabet_letter_E' ||
      'alphabet_letter_H' ||
      'alphabet_letter_I' ||
      'alphabet_letter_O' ||
      'alphabet_letter_U' => true,
      _ => false,
    };
