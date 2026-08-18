import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/tutor_persona.dart';
import 'gemini_live_token_service.dart';

/// Resolves short tutor audio clips through the same Gemini Live model and
/// selected persona used by an actual call. Generated lesson audio never
/// silently switches to a different voice or to the old HTTP TTS endpoint.
class GeminiLiveAudioService {
  GeminiLiveAudioService._();

  static final shared = GeminiLiveAudioService._();

  static const _model = 'models/gemini-3.1-flash-live-preview';
  static const _bucket = 'vocabulary-audio';
  static const _cacheVersion = 'live-audio-v1';

  final Map<String, Future<List<int>?>> _inFlight = {};
  Directory? _cacheDir;

  static String cacheKeyFor({
    required String text,
    required String voiceName,
    bool slow = false,
  }) {
    final normalized = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    return sha256
        .convert(utf8.encode('$_cacheVersion|$voiceName|$slow|$normalized'))
        .toString();
  }

  static String storagePathFor({
    required String userId,
    required String cacheKey,
  }) => '$userId/v1/$cacheKey.pcm';

  /// Gemini 3.1 Live accepts new text turns through realtimeInput. Keeping
  /// this message shape in one place prevents the one-shot pronunciation path
  /// from accidentally using the legacy clientContent turn format.
  static Map<String, dynamic> realtimeTextMessage(String text) => {
    'realtimeInput': {'text': text},
  };

  /// Reads private local/Supabase cache first, then generates one clip through
  /// Gemini Live. Supabase persistence is skipped until the learner has an
  /// authenticated owner; the local cache still keeps the current session
  /// usable without making audio public.
  Future<List<int>?> resolve({
    required String text,
    required String contentItemId,
    String? voiceName,
    bool slow = false,
  }) async {
    final normalized = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.isEmpty) return null;
    final persona = _personaForVoice(voiceName);
    if (persona == null) return null;
    final cacheKey = cacheKeyFor(
      text: normalized,
      voiceName: persona.voiceName,
      slow: slow,
    );
    final existing = _inFlight[cacheKey];
    if (existing != null) return existing;
    final future = _resolveUnshared(
      normalized,
      contentItemId: contentItemId,
      persona: persona,
      cacheKey: cacheKey,
      slow: slow,
    );
    _inFlight[cacheKey] = future;
    try {
      return await future;
    } finally {
      if (identical(_inFlight[cacheKey], future)) _inFlight.remove(cacheKey);
    }
  }

  /// Returns an already-generated clip without ever opening a Gemini Live
  /// socket. This is used by secondary pronunciation controls where a tap
  /// should reuse the lesson's PCM deck, not create new audio on demand.
  Future<List<int>?> loadCached({
    required String text,
    String? voiceName,
    bool slow = false,
  }) async {
    final normalized = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.isEmpty) return null;
    final persona = _personaForVoice(voiceName);
    if (persona == null) return null;
    final cacheKey = cacheKeyFor(
      text: normalized,
      voiceName: persona.voiceName,
      slow: slow,
    );

    // If another screen is already warming this exact clip, wait for that
    // existing work rather than starting anything new from the tap.
    final existing = _inFlight[cacheKey];
    if (existing != null) return existing;

    final local = await _readLocal(cacheKey);
    if (_validPcm(local)) return local;

    final userId = _currentUserId;
    if (userId == null) return null;
    try {
      final remote = await Supabase.instance.client.storage
          .from(_bucket)
          .download(storagePathFor(userId: userId, cacheKey: cacheKey))
          .timeout(const Duration(seconds: 8));
      if (!_validPcm(remote)) return null;
      final bytes = remote.toList(growable: false);
      await _writeLocal(cacheKey, bytes);
      return bytes;
    } catch (_) {
      return null;
    }
  }

  /// Warms the first item before returning, then fills the rest with a small
  /// parallel worker pool so a new lesson never waits for its whole deck.
  Future<void> warmDeck({
    required List<({String text, String contentItemId})> items,
    String? voiceName,
  }) async {
    if (items.isEmpty) return;
    await resolve(
      text: items.first.text,
      contentItemId: items.first.contentItemId,
      voiceName: voiceName,
    );
    if (items.length == 1) return;
    var next = 1;
    Future<void> worker() async {
      while (true) {
        if (next >= items.length) return;
        final item = items[next++];
        await resolve(
          text: item.text,
          contentItemId: item.contentItemId,
          voiceName: voiceName,
        );
      }
    }

    final count = items.length - 1 < 3 ? items.length - 1 : 3;
    await Future.wait(List.generate(count, (_) => worker()));
  }

  /// Removes the private audio clips belonging to one generated content item.
  /// The lesson row itself is untouched, so revisiting it simply regenerates
  /// the missing clips with the currently selected tutor voice.
  Future<void> removeCachedAudio({required String contentItemId}) async {
    final userId = _currentUserId;
    if (userId == null || contentItemId.isEmpty) return;
    final client = Supabase.instance.client;
    try {
      final rows = await client
          .from('vocabulary_audio_cache')
          .select('cache_key, storage_path')
          .eq('user_id', userId)
          .eq('content_item_id', contentItemId);
      final cacheKeys = <String>[];
      final storagePaths = <String>[];
      for (final row in rows.whereType<Map>()) {
        final cacheKey = row['cache_key']?.toString();
        final storagePath = row['storage_path']?.toString();
        if (cacheKey != null) cacheKeys.add(cacheKey);
        if (storagePath != null) storagePaths.add(storagePath);
      }
      if (storagePaths.isNotEmpty) {
        await client.storage.from(_bucket).remove(storagePaths);
      }
      await client
          .from('vocabulary_audio_cache')
          .delete()
          .eq('user_id', userId)
          .eq('content_item_id', contentItemId);
      for (final cacheKey in cacheKeys) {
        try {
          await File('${(await _directory).path}/$cacheKey.pcm').delete();
        } catch (_) {}
      }
    } catch (error) {
      debugPrint(
        'GeminiLiveAudioService: private audio removal skipped: $error',
      );
    }
  }

  Future<List<int>?> _resolveUnshared(
    String text, {
    required String contentItemId,
    required TutorPersona persona,
    required String cacheKey,
    required bool slow,
  }) async {
    final local = await _readLocal(cacheKey);
    if (_validPcm(local)) return local;

    final userId = _currentUserId;
    final storagePath = userId == null
        ? null
        : storagePathFor(userId: userId, cacheKey: cacheKey);
    if (storagePath != null) {
      try {
        final remote = await Supabase.instance.client.storage
            .from(_bucket)
            .download(storagePath)
            .timeout(const Duration(seconds: 8));
        if (_validPcm(remote)) {
          final bytes = remote.toList(growable: false);
          await _writeLocal(cacheKey, bytes);
          return bytes;
        }
      } catch (_) {
        // A miss is expected on a learner's first encounter with a phrase.
      }
    }

    final generated = await _generateLive(
      text,
      persona: persona,
      slow: slow,
    ).timeout(const Duration(seconds: 35), onTimeout: () => null);
    if (!_validPcm(generated)) return null;
    await _writeLocal(cacheKey, generated!);

    if (userId != null && storagePath != null) {
      final client = Supabase.instance.client;
      try {
        await client.storage
            .from(_bucket)
            .uploadBinary(
              storagePath,
              Uint8List.fromList(generated),
              fileOptions: const FileOptions(
                contentType: 'audio/pcm',
                upsert: false,
              ),
            );
      } catch (error) {
        debugPrint(
          'GeminiLiveAudioService: private audio upload skipped: $error',
        );
      }
      try {
        await client.from('vocabulary_audio_cache').upsert({
          'user_id': userId,
          'cache_key': cacheKey,
          'content_item_id': contentItemId,
          'spoken_text': text,
          'voice_name': persona.voiceName,
          'storage_path': storagePath,
          'sha256': sha256.convert(generated).toString(),
          'bytes': generated.length,
          'sample_rate_hz': 24000,
          'channels': 1,
          'encoding': 'pcm_s16le',
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }, onConflict: 'user_id,cache_key');
      } catch (error) {
        debugPrint(
          'GeminiLiveAudioService: private audio index skipped: $error',
        );
      }
    }
    return generated;
  }

  TutorPersona? _personaForVoice(String? voiceName) {
    if (voiceName == null || voiceName.isEmpty) return ActiveTutor.current;
    for (final persona in TutorPersona.all) {
      if (persona.voiceName == voiceName) return persona;
    }
    return null;
  }

  String? get _currentUserId {
    try {
      return Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  Future<Directory> get _directory async {
    if (_cacheDir != null) return _cacheDir!;
    final base = await getApplicationSupportDirectory();
    final directory = Directory('${base.path}/gemini_live_audio_cache');
    if (!await directory.exists()) await directory.create(recursive: true);
    return _cacheDir = directory;
  }

  Future<List<int>?> _readLocal(String cacheKey) async {
    try {
      final file = File('${(await _directory).path}/$cacheKey.pcm');
      if (await file.exists()) return file.readAsBytes();
    } catch (_) {}
    return null;
  }

  Future<void> _writeLocal(String cacheKey, List<int> bytes) async {
    try {
      await File(
        '${(await _directory).path}/$cacheKey.pcm',
      ).writeAsBytes(bytes, flush: false);
    } catch (_) {}
  }

  bool _validPcm(List<int>? bytes) =>
      bytes != null && bytes.isNotEmpty && bytes.length.isEven;

  Future<List<int>?> _generateLive(
    String text, {
    required TutorPersona persona,
    required bool slow,
  }) async {
    late final String token;
    try {
      token = await GeminiLiveTokenService.fetch();
    } catch (_) {
      return null;
    }
    final channel = WebSocketChannel.connect(
      Uri.parse(
        'wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1alpha.GenerativeService.BidiGenerateContentConstrained?access_token=${Uri.encodeQueryComponent(token)}',
      ),
    );
    final setupComplete = Completer<void>();
    final turnComplete = Completer<void>();
    final audio = <int>[];
    late final StreamSubscription subscription;

    void fail(Object error, [StackTrace? stackTrace]) {
      if (!setupComplete.isCompleted) {
        setupComplete.completeError(error, stackTrace);
      }
      if (!turnComplete.isCompleted) {
        turnComplete.completeError(error, stackTrace);
      }
    }

    subscription = channel.stream.listen(
      (message) {
        try {
          final json =
              jsonDecode(
                    message is String
                        ? message
                        : utf8.decode(message as List<int>),
                  )
                  as Map<String, dynamic>;
          final error = json['error'];
          if (error is Map) {
            fail(
              StateError(error['message']?.toString() ?? 'Gemini Live error'),
            );
            return;
          }
          if (json.containsKey('setupComplete') && !setupComplete.isCompleted) {
            setupComplete.complete();
          }
          final serverContent = json['serverContent'];
          if (serverContent is! Map) return;
          final modelTurn = serverContent['modelTurn'];
          final parts = modelTurn is Map ? modelTurn['parts'] : null;
          if (parts is List) {
            for (final part in parts) {
              if (part is! Map) continue;
              final inlineData = part['inlineData'];
              final data = inlineData is Map ? inlineData['data'] : null;
              if (data is String) audio.addAll(base64Decode(data));
            }
          }
          if (serverContent['turnComplete'] == true &&
              !turnComplete.isCompleted) {
            turnComplete.complete();
          }
        } catch (error, stackTrace) {
          fail(error, stackTrace);
        }
      },
      onError: fail,
      onDone: () {
        if (!turnComplete.isCompleted) {
          fail(StateError('Gemini Live audio socket closed early'));
        }
      },
    );

    try {
      channel.sink.add(
        jsonEncode({
          'setup': {
            'model': _model,
            'generationConfig': {
              'responseModalities': ['AUDIO'],
              'speechConfig': {
                'voiceConfig': {
                  'prebuiltVoiceConfig': {'voiceName': persona.voiceName},
                },
              },
            },
            'systemInstruction': {
              'parts': [
                {
                  'text':
                      '${persona.promptBlock} You are preparing one short pronunciation clip. Speak only the French text supplied by the learner, with no explanation or extra words. ${slow ? 'Use a measured, extra-clear learning pace.' : 'Use a natural, clear learning pace.'}',
                },
              ],
            },
          },
        }),
      );
      await setupComplete.future.timeout(const Duration(seconds: 10));
      channel.sink.add(jsonEncode(realtimeTextMessage(text)));
      await turnComplete.future.timeout(const Duration(seconds: 30));
      return _validPcm(audio) ? List<int>.unmodifiable(audio) : null;
    } catch (error) {
      debugPrint('GeminiLiveAudioService: Live generation failed: $error');
      return null;
    } finally {
      await subscription.cancel();
      await channel.sink.close();
    }
  }
}
