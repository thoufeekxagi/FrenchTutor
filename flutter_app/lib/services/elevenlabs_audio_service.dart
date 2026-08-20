import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

/// A provider-rendered lesson clip returned by the authenticated Supabase
/// ElevenLabs boundary. Alignment is character-level, which is enough to
/// derive segment/word timing later without making the transcript provider-
/// owned.
class ElevenLabsAudioClip {
  const ElevenLabsAudioClip({
    required this.mode,
    required this.bytes,
    this.alignment,
    this.voiceSegments = const [],
  });

  final String mode;
  final Uint8List bytes;
  final Map<String, dynamic>? alignment;
  final List<Map<String, dynamic>> voiceSegments;

  bool get hasTiming => alignment != null;
}

class ElevenLabsProviderException implements Exception {
  const ElevenLabsProviderException(this.message, {this.status});

  final String message;
  final int? status;

  bool get isPaymentRequired => status == 402;

  @override
  String toString() => message;
}

/// Calls the Supabase Edge Function that owns the ElevenLabs credential.
///
/// Gemini remains responsible for the lesson/story JSON. This service only
/// renders the already-generated French content into narration, dialogue, or
/// music, so the learning transcript remains deterministic and testable.
class ElevenLabsAudioService {
  ElevenLabsAudioService._();

  static final shared = ElevenLabsAudioService._();

  static const _functionName = 'elevenlabs-audio';

  Future<ElevenLabsAudioClip> synthesizeNarration({
    required String text,
    String mode = 'narration',
    String? voiceId,
  }) async {
    final data = await _invokeJson({
      'mode': mode,
      'text': text,
      if (voiceId != null && voiceId.trim().isNotEmpty) 'voiceId': voiceId,
    });
    return _clipFromJson(data, fallbackMode: mode);
  }

  Future<ElevenLabsAudioClip> synthesizePodcast({
    required List<({String text, String? voiceId})> turns,
    String? hostVoiceId,
    String? guestVoiceId,
  }) async {
    final data = await _invokeJson({
      'mode': 'podcast',
      'inputs': [
        for (final turn in turns)
          {
            'text': turn.text,
            if (turn.voiceId != null && turn.voiceId!.trim().isNotEmpty)
              'voiceId': turn.voiceId,
          },
      ],
      if (hostVoiceId != null && hostVoiceId.trim().isNotEmpty)
        'hostVoiceId': hostVoiceId,
      if (guestVoiceId != null && guestVoiceId.trim().isNotEmpty)
        'guestVoiceId': guestVoiceId,
    });
    return _clipFromJson(data, fallbackMode: 'podcast');
  }

  Future<ElevenLabsAudioClip> composeMusic({
    required String prompt,
    int musicLengthMs = 30_000,
    bool forceInstrumental = false,
  }) async {
    final response = await _invoke({
      'mode': 'music',
      'prompt': prompt,
      'musicLengthMs': musicLengthMs,
      'forceInstrumental': forceInstrumental,
    });
    final data = response.data;
    if (data is Uint8List) {
      return ElevenLabsAudioClip(mode: 'music', bytes: data);
    }
    if (data is List<int>) {
      return ElevenLabsAudioClip(
        mode: 'music',
        bytes: Uint8List.fromList(data),
      );
    }
    throw const ElevenLabsProviderException(
      'ElevenLabs music returned no playable audio.',
    );
  }

  Future<Map<String, dynamic>> _invokeJson(Map<String, dynamic> body) async {
    final response = await _invoke(body);
    final data = response.data;
    if (data is! Map) {
      throw const ElevenLabsProviderException(
        'ElevenLabs returned an invalid audio response.',
      );
    }
    return Map<String, dynamic>.from(data);
  }

  Future<FunctionResponse> _invoke(Map<String, dynamic> body) async {
    if (Supabase.instance.client.auth.currentSession == null) {
      throw const ElevenLabsProviderException(
        'Sign in is required to generate listening audio.',
      );
    }
    try {
      return await Supabase.instance.client.functions
          .invoke(_functionName, body: body)
          .timeout(const Duration(seconds: 90));
    } on FunctionException catch (error) {
      final details = error.details;
      final providerMessage = details is Map
          ? details['error']?.toString()
          : null;
      throw ElevenLabsProviderException(
        providerMessage?.isNotEmpty == true
            ? providerMessage!
            : 'ElevenLabs audio generation failed.',
        status: error.status,
      );
    } catch (error) {
      if (error is ElevenLabsProviderException) rethrow;
      throw ElevenLabsProviderException(
        'ElevenLabs audio generation failed: $error',
      );
    }
  }

  ElevenLabsAudioClip _clipFromJson(
    Map<String, dynamic> data, {
    required String fallbackMode,
  }) {
    final encoded = data['audioBase64']?.toString() ?? '';
    if (encoded.isEmpty) {
      throw const ElevenLabsProviderException(
        'ElevenLabs returned an empty audio clip.',
      );
    }
    final rawAlignment = data['alignment'];
    final alignment = rawAlignment is Map
        ? Map<String, dynamic>.from(rawAlignment)
        : null;
    final rawVoiceSegments = data['voiceSegments'];
    final voiceSegments = rawVoiceSegments is List
        ? [
            for (final item in rawVoiceSegments)
              if (item is Map) Map<String, dynamic>.from(item),
          ]
        : const <Map<String, dynamic>>[];
    try {
      return ElevenLabsAudioClip(
        mode: data['mode']?.toString() ?? fallbackMode,
        bytes: Uint8List.fromList(base64Decode(encoded)),
        alignment: alignment,
        voiceSegments: voiceSegments,
      );
    } on FormatException {
      throw const ElevenLabsProviderException(
        'ElevenLabs returned malformed audio data.',
      );
    }
  }
}
