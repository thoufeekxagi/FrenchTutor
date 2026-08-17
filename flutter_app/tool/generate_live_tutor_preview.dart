// Regenerates a bundled tutor preview from the same Gemini Live setup used by
// the app's real conversations. This avoids a preview sounding different from
// the voice heard in a live session when a cached clip was authored elsewhere.
//
// Run from flutter_app with:
//   dart run tool/generate_live_tutor_preview.dart
//
// The script reads GEMINI_API_KEY from secrets.local.properties and never prints
// the key. It intentionally generates Mathieu only; add another persona only
// when that persona's Live voice configuration changes.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:web_socket_channel/web_socket_channel.dart';

const _model = 'models/gemini-3.1-flash-live-preview';
const _voiceName = 'Orus';
const _sample =
    "Bonjour, bonjour ! Je m'appelle Mathieu, de la ville de Québec. "
    "Hi, I'm Mathieu. We'll go steady and calm, on jase en français un "
    "peu chaque jour, a little chat in French every day. Ça te va ?";

Future<void> main() async {
  final apiKey = _readSecret('GEMINI_API_KEY');
  if (apiKey.isEmpty) {
    stderr.writeln('GEMINI_API_KEY is missing from secrets.local.properties.');
    exitCode = 1;
    return;
  }

  final uri = Uri.parse(
    'wss://generativelanguage.googleapis.com/ws/'
    'google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent'
    '?key=$apiKey',
  );
  final channel = WebSocketChannel.connect(uri);
  final audio = <int>[];
  final done = Completer<void>();
  var setupComplete = false;

  late final StreamSubscription<Object?> subscription;
  subscription = channel.stream.listen(
    (message) {
      final text = message is String
          ? message
          : utf8.decode(message as List<int>);
      final json = jsonDecode(text);
      if (json is! Map) return;
      if (json['error'] is Map) {
        final error = (json['error'] as Map)['message'];
        if (!done.isCompleted) {
          done.completeError(StateError('$error'));
        }
        return;
      }
      if (json.containsKey('setupComplete')) {
        if (setupComplete) return;
        setupComplete = true;
        channel.sink.add(
          jsonEncode({
            'clientContent': {
              'turns': [
                {
                  'role': 'user',
                  'parts': [
                    {
                      'text':
                          'Say this exactly as Mathieu, with a calm masculine '
                          'Québécois tutor voice. Do not add any words: $_sample',
                    },
                  ],
                },
              ],
              'turnComplete': true,
            },
          }),
        );
        return;
      }

      _collectAudio(json, audio);
      final serverContent = json['serverContent'];
      if (serverContent is Map && serverContent['turnComplete'] == true) {
        if (!done.isCompleted) done.complete();
      }
    },
    onError: (Object error, StackTrace stack) {
      if (!done.isCompleted) done.completeError(error, stack);
    },
    onDone: () {
      if (!done.isCompleted) {
        done.completeError(
          StateError('Gemini Live closed before audio completed.'),
        );
      }
    },
  );

  channel.sink.add(
    jsonEncode({
      'setup': {
        'model': _model,
        'generationConfig': {
          'responseModalities': ['AUDIO'],
          'speechConfig': {
            'voiceConfig': {
              'prebuiltVoiceConfig': {'voiceName': _voiceName},
            },
          },
        },
        'systemInstruction': {
          'parts': [
            {
              'text':
                  'You are Mathieu, a calm, steady French tutor from Québec '
                  'City. Speak only French or English. Use a clearly masculine '
                  'Québécois tutor voice and do not add commentary.',
            },
          ],
        },
        'outputAudioTranscription': <String, dynamic>{},
      },
    }),
  );

  try {
    await done.future.timeout(const Duration(seconds: 45));
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (audio.isEmpty || audio.length.isOdd) {
      throw StateError('Gemini Live returned no valid PCM audio.');
    }
    final output = File('assets/audio/tutor_previews/mathieu.pcm');
    await output.writeAsBytes(audio, flush: true);
    stdout.writeln('Wrote ${audio.length} bytes to ${output.path}.');
  } finally {
    await subscription.cancel();
    await channel.sink.close();
  }
}

void _collectAudio(Object? value, List<int> output) {
  if (value is Map) {
    final inline = value['inlineData'];
    if (inline is Map && inline['data'] is String) {
      final mimeType = inline['mimeType'] as String? ?? '';
      if (mimeType.startsWith('audio/pcm')) {
        output.addAll(base64Decode(inline['data'] as String));
      }
    }
    for (final child in value.values) {
      _collectAudio(child, output);
    }
  } else if (value is List) {
    for (final child in value) {
      _collectAudio(child, output);
    }
  }
}

String _readSecret(String name) {
  final file = File('secrets.local.properties');
  if (!file.existsSync()) {
    return '';
  }
  for (final line in file.readAsLinesSync()) {
    if (line.startsWith('$name=')) {
      return line.substring(name.length + 1).trim();
    }
  }
  return '';
}
