import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../models/tutor_persona.dart';
import 'audio_streaming_service.dart';
import 'lesson_agent_service.dart';

/// Plays each tutor's [TutorPersona.sampleLine] in their own voice, for the
/// pickers in onboarding and Settings (P2.2).
///
/// Samples ship BUNDLED in the app (`assets/audio/tutor_previews/<id>.pcm`,
/// raw 24kHz mono PCM16 pre-generated with each persona's real voice) so a
/// preview plays instantly, offline, with zero API calls — critical for
/// onboarding, which runs before anything is warmed up. Live Gemini TTS is
/// only a fallback for a persona whose bundled asset is missing. Starting a
/// preview cuts any other preview; failures are quiet — a preview is a
/// nice-to-have, never a blocker.
class TutorVoicePreviewer extends ChangeNotifier {
  // Lazy: no audio machinery (and none of its timers/platform channels) exists
  // until a preview is actually played — screens that merely SHOW the picker
  // stay audio-free.
  AudioStreamingService? _audioLazy;
  AudioStreamingService get _audio => _audioLazy ??= AudioStreamingService();
  final Map<String, List<int>> _cache = {};
  String? _loadingId;
  String? _playingId;
  Timer? _playbackDoneTimer;
  bool _disposed = false;

  /// Persona id currently being synthesized (spinner state), if any.
  String? get loadingId => _loadingId;

  /// Persona id currently sounding, if any.
  String? get playingId => _playingId;

  /// Play [persona]'s sample. Tapping the tutor that is already playing stops
  /// it instead (toggle).
  Future<void> play(TutorPersona persona) async {
    if (_disposed || _loadingId != null) return;
    if (_playingId == persona.id) {
      stop();
      return;
    }
    stop();
    var bytes = _cache[persona.id];
    if (bytes == null) {
      // Bundled asset first: instant, offline, free.
      try {
        final data = await rootBundle.load(
          'assets/audio/tutor_previews/${persona.id}.pcm',
        );
        bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
        _cache[persona.id] = bytes;
      } catch (_) {
        bytes = null;
      }
      if (_disposed) return;
    }
    if (bytes == null) {
      // Fallback only if the asset is missing: live TTS.
      _loadingId = persona.id;
      notifyListeners();
      try {
        bytes = await LessonAgentService.shared.synthesizeSpeech(
          persona.sampleLine,
          voiceName: persona.voiceName,
        );
        _cache[persona.id] = bytes;
      } catch (_) {
        bytes = null;
      } finally {
        _loadingId = null;
        if (!_disposed) notifyListeners();
      }
      if (bytes == null || _disposed) return;
    }
    _playingId = persona.id;
    notifyListeners();
    await _audio.playAudioChunk(bytes);
    // PCM16 mono at 24kHz — mark done when the buffer has actually sounded.
    final playbackMs = (bytes.length / 2 / 24000 * 1000).round() + 250;
    _playbackDoneTimer = Timer(Duration(milliseconds: playbackMs), () {
      if (_disposed || _playingId != persona.id) return;
      _playingId = null;
      notifyListeners();
    });
  }

  void stop() {
    _playbackDoneTimer?.cancel();
    _audioLazy?.stopPlayback();
    if (_playingId != null) {
      _playingId = null;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _playbackDoneTimer?.cancel();
    _audioLazy?.dispose();
    super.dispose();
  }
}
