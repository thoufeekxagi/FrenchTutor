import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/content_models.dart';

/// A provider-rendered lesson clip returned by the authenticated Supabase
/// ElevenLabs boundary. Alignment is character-level, which is enough to
/// derive segment/word timing later without making the transcript provider-
/// owned.
class ElevenLabsAudioClip {
  const ElevenLabsAudioClip({
    required this.mode,
    required this.bytes,
    this.container = 'mp3',
    this.alignment,
    this.voiceSegments = const [],
    this.validation,
  });

  final String mode;
  final Uint8List bytes;
  final String container;

  /// TTS/dialogue return an alignment map; detailed music can return a list of
  /// word timestamps, so keep the provider's timing shape intact.
  final Object? alignment;
  final List<Map<String, dynamic>> voiceSegments;
  final Map<String, dynamic>? validation;

  bool get hasTiming => alignment != null;
  bool get isValidated => validation?['accepted'] == true;
  bool get isWav => container.toLowerCase() == 'wav';
}

class ElevenLabsProviderException implements Exception {
  const ElevenLabsProviderException(this.message, {this.status});

  final String message;
  final int? status;

  bool get isPaymentRequired => status == 402;

  /// Only provider quota/credit/rate-limit failures are eligible for the
  /// explicit Gemini Live spoken-audio recovery path. Other errors remain
  /// visible so a broken renderer cannot be hidden by a different provider.
  bool get isQuotaExceeded {
    if (status == 402 || status == 429) return true;
    final normalized = message.toLowerCase();
    return normalized.contains('quota') ||
        normalized.contains('credit') ||
        normalized.contains('rate limit') ||
        normalized.contains('resource exhausted') ||
        normalized.contains('too many requests');
  }

  @override
  String toString() => message;
}

/// The only text allowed to reach ElevenLabs for a listening lesson. The
/// configured canonical text model creates the story package; this immutable projection carries the French
/// lines plus their learner-facing meaning into the renderer without letting
/// the provider invent replacement lesson content.
class CanonicalAudioLine {
  const CanonicalAudioLine({
    required this.index,
    required this.french,
    required this.english,
    required this.grammarNote,
    required this.pronunciationTip,
    required this.speakerId,
  });

  final int index;
  final String french;
  final String english;
  final String grammarNote;
  final String pronunciationTip;
  final String speakerId;
}

class CanonicalAudioScript {
  const CanonicalAudioScript({required this.mode, required this.lines});

  factory CanonicalAudioScript.fromStory(
    GeneratedStory story, {
    required String format,
  }) {
    final mode = format == 'surprise' ? 'narration' : format;
    return CanonicalAudioScript(
      mode: mode,
      lines: [
        for (var index = 0; index < story.passage.segments.length; index++)
          if (story.passage.segments[index].fr.trim().isNotEmpty)
            CanonicalAudioLine(
              index: index,
              french: story.passage.segments[index].fr.trim(),
              english: story.passage.segments[index].en.trim(),
              grammarNote: story.passage.segments[index].grammarNote.trim(),
              pronunciationTip: story.passage.segments[index].pronunciationTip
                  .trim(),
              speakerId: index.isEven ? 'host' : 'guest',
            ),
      ],
    );
  }

  final String mode;
  final List<CanonicalAudioLine> lines;

  String get frenchText => lines.map((line) => line.french).join(' ');
  String get narrationText => lines.map((line) => line.french).join('\n\n');
  List<String> get lyricLines => lines.map((line) => line.french).toList();

  List<({String text, String? voiceId})> get podcastTurns => [
    for (final line in lines) (text: line.french, voiceId: null),
  ];
}

/// Calls the Supabase Edge Function that owns the ElevenLabs credential.
///
/// The canonical text model remains responsible for the lesson/story JSON. This service only
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
    required List<String> lyrics,
    String style = 'gentle acoustic French learning pop',
    int musicLengthMs = 30_000,
  }) async {
    final response = await _invoke({
      'mode': 'music',
      'lyrics': lyrics,
      'style': style,
      'musicLengthMs': musicLengthMs,
    });
    final data = response.data;
    if (data is! Map) {
      throw const ElevenLabsProviderException(
        'ElevenLabs music returned an invalid validation response.',
      );
    }
    return _clipFromJson(
      Map<String, dynamic>.from(data),
      fallbackMode: 'music',
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
    final alignment = data['alignment'];
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
        validation: data['validation'] is Map
            ? Map<String, dynamic>.from(data['validation'] as Map)
            : null,
      );
    } on FormatException {
      throw const ElevenLabsProviderException(
        'ElevenLabs returned malformed audio data.',
      );
    }
  }
}
