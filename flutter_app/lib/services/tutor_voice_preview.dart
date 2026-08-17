import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../models/tutor_persona.dart';
import 'audio_streaming_service.dart';
import 'gemini_live_audio_service.dart';

/// Plays each tutor's [TutorPersona.sampleLine] in their own voice, for the
/// pickers in onboarding and Settings (P2.2).
///
/// Samples ship BUNDLED in the app (`assets/audio/tutor_previews/<id>.pcm`,
/// raw 24kHz mono PCM16 generated from the same Gemini voice configuration as
/// live tutor sessions) so a preview plays instantly, offline, with zero API
/// calls — critical for onboarding, which runs before anything is warmed up.
/// Gemini Live is only a fallback for a persona whose bundled asset is missing.
/// Starting a preview cuts any other preview; failures are quiet — a preview is
/// a nice-to-have, never a blocker.
class TutorVoicePreviewer extends ChangeNotifier {
  // Lazy: no audio machinery (and none of its timers/platform channels) exists
  // until a preview is actually played — screens that merely SHOW the picker
  // stay audio-free.
  AudioStreamingService? _audioLazy;
  AudioStreamingService get _audio => _audioLazy ??= AudioStreamingService();
  final Map<String, List<int>> _cache = {};
  String? _loadingId;
  String? _playingId;
  DateTime? _playStartedAt;
  int? _playingDurationMs;
  Timer? _playbackDoneTimer;
  Timer? _analysisTimer;
  bool _disposed = false;

  /// Receives the same 24 kHz PCM16 that is sent to the player, in small
  /// timed windows, so a visual tutor can animate from the preview audio too.
  void Function(List<int> pcmBytes)? onPcmChunk;

  /// Called when a sample is stopped or reaches its natural end.
  VoidCallback? onPlaybackEnded;

  // Bumped on every play()/stop() call. A play() in flight across an async
  // gap (bundled-asset load OR live-TTS fallback) checks its own generation
  // against this after each await and abandons itself if a newer call
  // superseded it — otherwise two rapid taps on different personas both
  // race past a load, both finish, and both end up queued back-to-back on
  // the shared player instead of the second cancelling the first.
  int _playGeneration = 0;

  /// Persona id currently being synthesized (spinner state), if any.
  String? get loadingId => _loadingId;

  /// Persona id currently sounding, if any.
  String? get playingId => _playingId;

  /// True while a sample is loading or sounding. A new tutor preview is
  /// allowed to interrupt the current one; this is used by the picker to
  /// make switching voices feel immediate instead of ignoring taps.
  bool get isBusy => _playingId != null || _loadingId != null;

  /// When the currently-playing sample started, and how long it runs for —
  /// together these let the UI draw a progress ring that fills up to exactly
  /// when the sample ends.
  DateTime? get playStartedAt => _playStartedAt;
  int? get playingDurationMs => _playingDurationMs;

  /// Play [persona]'s sample. Any existing preview is cut first, including a
  /// preview that is still being synthesized. The generation token prevents
  /// stale async work from starting audio after a newer tutor was selected.
  Future<void> play(TutorPersona persona) async {
    if (_disposed) return;
    if (isBusy) await stop();
    final generation = ++_playGeneration;
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
      if (_disposed || generation != _playGeneration) return;
    }
    if (bytes == null) {
      // Fallback only if the asset is missing: the selected tutor's Gemini Live voice.
      _loadingId = persona.id;
      notifyListeners();
      try {
        bytes = await GeminiLiveAudioService.shared.resolve(
          text: persona.sampleLine,
          contentItemId: 'tutor-preview:${persona.id}',
          voiceName: persona.voiceName,
        );
        if (bytes != null) _cache[persona.id] = bytes;
      } catch (_) {
        bytes = null;
      } finally {
        if (_loadingId == persona.id) _loadingId = null;
        if (!_disposed) notifyListeners();
      }
      if (bytes == null || _disposed || generation != _playGeneration) return;
    }
    // PCM16 mono at 24kHz — mark done when the buffer has actually sounded.
    final playbackMs = (bytes.length / 2 / 24000 * 1000).round() + 250;
    _playingId = persona.id;
    _playStartedAt = DateTime.now();
    _playingDurationMs = playbackMs;
    notifyListeners();
    _startAnalysis(bytes, generation);
    try {
      await _audio.playAudioChunk(bytes);
    } catch (_) {
      if (!_disposed &&
          generation == _playGeneration &&
          _playingId == persona.id) {
        _playingId = null;
        _playStartedAt = null;
        _playingDurationMs = null;
        notifyListeners();
      }
      return;
    }
    if (_disposed || generation != _playGeneration) return;
    _playbackDoneTimer = Timer(Duration(milliseconds: playbackMs), () {
      if (_disposed ||
          _playingId != persona.id ||
          generation != _playGeneration) {
        return;
      }
      _playingId = null;
      _playStartedAt = null;
      _playingDurationMs = null;
      _analysisTimer?.cancel();
      _analysisTimer = null;
      onPlaybackEnded?.call();
      notifyListeners();
    });
  }

  void _startAnalysis(List<int> bytes, int generation) {
    _analysisTimer?.cancel();
    var offset = 0;
    const windowBytes = 2880; // 60 ms at 24 kHz mono PCM16.

    void pump() {
      if (_disposed || generation != _playGeneration || _playingId == null) {
        return;
      }
      if (offset >= bytes.length) {
        _analysisTimer = null;
        return;
      }
      final end = (offset + windowBytes).clamp(0, bytes.length);
      onPcmChunk?.call(bytes.sublist(offset, end));
      offset = end;
      _analysisTimer = Timer(const Duration(milliseconds: 60), pump);
    }

    pump();
  }

  Future<void> stop() async {
    _playGeneration++;
    _playbackDoneTimer?.cancel();
    _analysisTimer?.cancel();
    _analysisTimer = null;
    // Preview clips are one-shot buffers. The live-call player intentionally
    // keeps its native stream open, but that strategy lets already-fed preview
    // audio continue behind a new tutor. Use a hard reset here so Stop and a
    // tutor switch are real cancellations, not volume fades.
    await _audioLazy?.stopPlayback(hardStop: true);
    if (_playingId != null || _loadingId != null) {
      _playingId = null;
      _loadingId = null;
      _playStartedAt = null;
      _playingDurationMs = null;
      onPlaybackEnded?.call();
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _playbackDoneTimer?.cancel();
    _analysisTimer?.cancel();
    _audioLazy?.dispose();
    super.dispose();
  }
}
