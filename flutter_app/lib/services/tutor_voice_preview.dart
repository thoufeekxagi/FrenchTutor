import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/tutor_persona.dart';
import 'audio_streaming_service.dart';
import 'lesson_agent_service.dart';

/// Plays each tutor's [TutorPersona.sampleLine] in their own voice, for the
/// pickers in onboarding and Settings (P2.2). Each sample is synthesized once
/// (Gemini TTS with that persona's voice) and cached for the screen's
/// lifetime; starting a preview cuts any other preview. Failures (offline, no
/// key) are quiet — a preview is a nice-to-have, never a blocker.
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
