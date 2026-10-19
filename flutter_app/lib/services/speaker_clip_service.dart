import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/api_keys.dart';

/// The speaker buttons: one short French line in the tutor's chosen voice.
///
/// Order, one attempt each, no retries:
///   1. this phone (instant, works offline),
///   2. the shared clip store (a plain file download, about half a second),
///   3. the `speak-line` function, which makes the clip once for everybody.
///
/// A clip made for one learner is saved for all of them, so each line is paid
/// for once per voice and only if somebody actually taps it. A failed attempt
/// is never repeated here: the next tap simply tries again.
class SpeakerClipService {
  SpeakerClipService({
    http.Client? client,
    Future<Directory> Function()? directory,
    String? baseUrl,
    String? anonKey,
    String? Function()? accessToken,
    this.storeTimeout = const Duration(seconds: 5),
    this.makeTimeout = const Duration(seconds: 12),
  }) : _http = client ?? http.Client(),
       _directory = directory ?? _defaultDirectory,
       _baseUrl = baseUrl ?? ApiKeys.supabaseUrl,
       _anonKey = anonKey ?? ApiKeys.supabaseAnonKey,
       _accessToken = accessToken ?? _sessionToken;

  static final shared = SpeakerClipService();

  static const version = 'tts2';
  static const bucket = 'speak-lines';
  static const maxChars = 200;
  static const _debugGeminiKey = String.fromEnvironment('E2E_GEMINI_API_KEY');

  final http.Client _http;
  final Future<Directory> Function() _directory;
  final String _baseUrl;
  final String _anonKey;
  final String? Function() _accessToken;
  final Duration storeTimeout;
  final Duration makeTimeout;

  final _inFlight = <String, Future<List<int>?>>{};
  final _prefetchTried = <String>{};
  final _prefetchQueue = <(String, String)>[];
  var _prefetchWorkers = 0;
  Directory? _dir;

  static Future<Directory> _defaultDirectory() async {
    final base = await getApplicationSupportDirectory();
    return Directory('${base.path}/speaker_clips');
  }

  static String? _sessionToken() {
    try {
      return Supabase.instance.client.auth.currentSession?.accessToken;
    } catch (_) {
      return null;
    }
  }

  /// Marie and Julien speak France French; Camille and Mathieu speak Quebec
  /// French, as in their live calls.
  static String languageFor(String voice) =>
      (voice == 'Leda' || voice == 'Orus') ? 'fr-CA' : 'fr-FR';

  static String normalize(String text) =>
      text.trim().replaceAll(RegExp(r'\s+'), ' ');

  static String hashOf(String normalized) =>
      sha256.convert(utf8.encode(normalized)).toString();

  /// The object path in the shared clip store (matches the function).
  static String storagePath(String voice, String normalized) =>
      '$version/$voice/${hashOf(normalized)}.pcm';

  static bool validPcm(List<int>? bytes) =>
      bytes != null && bytes.length >= 400 && bytes.length.isEven;

  Future<File> _file(String voice, String normalized) async {
    final dir = _dir ??= await _directory();
    if (!await dir.exists()) await dir.create(recursive: true);
    return File('${dir.path}/${version}_${voice}_${hashOf(normalized)}.pcm');
  }

  /// A saved clip on this phone, or null. Never touches the network.
  Future<List<int>?> saved(String text, String voice) async {
    final line = normalize(text);
    if (line.isEmpty) return null;
    try {
      final file = await _file(voice, line);
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      return validPcm(bytes) ? bytes : null;
    } catch (_) {
      return null;
    }
  }

  /// The clip for [text] in [voice], or null if it could not be had. One
  /// attempt at each step; concurrent calls for the same line share one.
  Future<List<int>?> clip(String text, String voice) async {
    final line = normalize(text);
    if (line.isEmpty || line.length > maxChars) return null;
    final local = await saved(line, voice);
    if (local != null) return local;
    final id = '$voice|$line';
    final running = _inFlight[id];
    if (running != null) return running;
    final future = _fetch(line, voice);
    _inFlight[id] = future;
    try {
      return await future;
    } finally {
      if (identical(_inFlight[id], future)) _inFlight.remove(id);
    }
  }

  Future<List<int>?> _fetch(String line, String voice) async {
    final shared = await _fromStore(line, voice);
    if (shared != null) return _keep(line, voice, shared);
    final made = await _make(line, voice);
    return made == null ? null : _keep(line, voice, made);
  }

  Future<List<int>> _keep(String line, String voice, List<int> bytes) async {
    try {
      await (await _file(voice, line)).writeAsBytes(bytes, flush: true);
    } catch (_) {
      // The learner still hears it; the next tap just asks again.
    }
    return bytes;
  }

  Future<List<int>?> _fromStore(String line, String voice) async {
    try {
      final response = await _http
          .get(
            Uri.parse(
              '$_baseUrl/storage/v1/object/public/$bucket/'
              '${storagePath(voice, line)}',
            ),
          )
          .timeout(storeTimeout);
      return response.statusCode == 200 && validPcm(response.bodyBytes)
          ? response.bodyBytes
          : null;
    } catch (_) {
      return null;
    }
  }

  Future<List<int>?> _make(String line, String voice) async {
    try {
      if (kDebugMode && _debugGeminiKey.isNotEmpty) {
        return await _makeDirect(line, voice);
      }
      final token = _accessToken();
      if (token == null || token.isEmpty) return null;
      final response = await _http
          .post(
            Uri.parse('$_baseUrl/functions/v1/speak-line'),
            headers: {
              'apikey': _anonKey,
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'text': line, 'voice': voice}),
          )
          .timeout(makeTimeout);
      return response.statusCode == 200 && validPcm(response.bodyBytes)
          ? response.bodyBytes
          : null;
    } catch (_) {
      return null;
    }
  }

  /// Debug builds only (device tests without an account): the same model and
  /// settings as the function, called directly with the test key.
  Future<List<int>?> _makeDirect(String line, String voice) async {
    final response = await _http
        .post(
          Uri.parse(
            'https://generativelanguage.googleapis.com/v1beta/models/'
            'gemini-3.8-flash-lite-tts:generateContent',
          ),
          headers: {
            'x-goog-api-key': _debugGeminiKey,
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'contents': [
              {
                'parts': [
                  {'text': line},
                ],
              },
            ],
            'generationConfig': {
              'responseModalities': ['AUDIO'],
              'speechConfig': {
                'languageCode': languageFor(voice),
                'voiceConfig': {
                  'prebuiltVoiceConfig': {'voiceName': voice},
                },
              },
            },
          }),
        )
        .timeout(makeTimeout);
    if (response.statusCode != 200) return null;
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final b64 =
        (((data['candidates'] as List?)?.first as Map?)?['content']
                as Map?)?['parts']?[0]?['inlineData']?['data']
            as String?;
    return b64 == null ? null : wavToPcm(base64Decode(b64));
  }

  /// Gemini returns a WAV; keep only the 16-bit samples.
  @visibleForTesting
  static List<int>? wavToPcm(List<int> bytes) {
    if (bytes.length < 44) return null;
    if (String.fromCharCodes(bytes.sublist(0, 4)) != 'RIFF') {
      return bytes.length.isEven ? bytes : null;
    }
    final data = ByteData.sublistView(Uint8List.fromList(bytes));
    var offset = 12;
    while (offset + 8 <= bytes.length) {
      final id = String.fromCharCodes(bytes.sublist(offset, offset + 4));
      final size = data.getUint32(offset + 4, Endian.little);
      if (id == 'data') {
        var end = (offset + 8 + size).clamp(0, bytes.length);
        if ((end - offset - 8).isOdd) end -= 1;
        final pcm = bytes.sublist(offset + 8, end);
        return pcm.isEmpty ? null : pcm;
      }
      offset += 8 + size + (size % 2);
    }
    return null;
  }

  /// Quietly gets these lines ready, once each per app run. A line that fails
  /// is not retried here; the tap that needs it will try again. Two at a time,
  /// so a lesson never floods the provider.
  void prefetch(List<String> lines, String voice) {
    for (final raw in lines) {
      final line = normalize(raw);
      if (line.isEmpty || line.length > maxChars) continue;
      if (!_prefetchTried.add('$voice|$line')) continue;
      _prefetchQueue.add((line, voice));
    }
    while (_prefetchWorkers < 2 && _prefetchQueue.isNotEmpty) {
      _prefetchWorkers++;
      unawaited(_prefetchWorker());
    }
  }

  Future<void> _prefetchWorker() async {
    try {
      while (_prefetchQueue.isNotEmpty) {
        final (line, voice) = _prefetchQueue.removeAt(0);
        await clip(line, voice);
      }
    } finally {
      _prefetchWorkers--;
    }
  }

  /// Lines still waiting or being fetched in the background.
  @visibleForTesting
  bool get prefetchBusy => _prefetchWorkers > 0 || _prefetchQueue.isNotEmpty;
}
