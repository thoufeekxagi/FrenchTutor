import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';

/// Ported from AudioStreamingService.swift — bidirectional PCM streaming for the live
/// Gemini call: 16kHz mono PCM16 captured from the mic, 24kHz mono PCM16 played back for
/// Marie's voice. Unlike the iOS original (which does its own AVAudioEngine sample-rate
/// conversion), flutter_sound's recorder/player do the native-format <-> PCM conversion for
/// us at the given `sampleRate`, so there's no manual `AVAudioConverter` equivalent needed
/// here.
class AudioStreamingService {
  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  final FlutterSoundPlayer _player = FlutterSoundPlayer();

  StreamController<Uint8List>? _micStreamController;
  StreamSubscription<Uint8List>? _micSub;

  bool _isStreaming = false;
  bool _isPlayerStarted = false;
  void Function(List<int> chunk)? _audioChunkCallback;

  /// While true, captured mic audio is not forwarded via the chunk callback. Used to
  /// prevent the mic from picking up the tutor's own speaker output and feeding it back to
  /// Gemini as an echo, since we don't use platform echo-cancellation (which would degrade
  /// output audio quality).
  bool isOutputActive = false;

  /// `isOutputActive` is set false the moment the SERVER signals turnComplete — but network
  /// delivery outruns real-time playback, so scheduled audio can still be physically playing
  /// through the speaker for seconds after that. Reopening the mic at turnComplete would let
  /// it pick up the tail of the tutor's own still-playing voice as if it were fresh user
  /// speech. This tracks the real end of the scheduled playback queue as an independent gate.
  DateTime _scheduledPlaybackEndTime = DateTime.fromMillisecondsSinceEpoch(0);
  static const _playbackTailGraceSeconds = 0.35;

  static const _inputSampleRate = 16000;
  static const _outputSampleRate = 24000;

  Future<bool> requestPermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  Future<void> startStreaming({required void Function(List<int> chunk) onChunk}) async {
    if (_isStreaming) return;
    _audioChunkCallback = onChunk;

    if (!_recorder.isStopped) {
      await _recorder.stopRecorder();
    }
    await _recorder.openRecorder();

    _micStreamController = StreamController<Uint8List>();
    _micSub = _micStreamController!.stream.listen(_handleMicChunk);

    await _recorder.startRecorder(
      codec: Codec.pcm16,
      toStream: _micStreamController!.sink,
      sampleRate: _inputSampleRate,
      numChannels: 1,
    );

    await _ensurePlayerStarted();

    _isStreaming = true;
  }

  Future<void> stopStreaming() async {
    if (!_isStreaming) return;
    _isStreaming = false;
    _audioChunkCallback = null;
    _scheduledPlaybackEndTime = DateTime.fromMillisecondsSinceEpoch(0);

    try {
      if (!_recorder.isStopped) await _recorder.stopRecorder();
    } catch (_) {}
    await _micSub?.cancel();
    _micSub = null;
    await _micStreamController?.close();
    _micStreamController = null;
  }

  void _handleMicChunk(Uint8List chunk) {
    final blockedByOutput = isOutputActive;
    final withinTailGrace = DateTime.now().isBefore(
      _scheduledPlaybackEndTime.add(Duration(milliseconds: (_playbackTailGraceSeconds * 1000).round())),
    );
    if (blockedByOutput || withinTailGrace) return;
    _audioChunkCallback?.call(chunk);
  }

  Future<void> _ensurePlayerStarted() async {
    if (_isPlayerStarted) return;
    if (!_player.isStopped) {
      await _player.stopPlayer();
    }
    await _player.openPlayer();
    await _player.startPlayerFromStream(
      codec: Codec.pcm16,
      sampleRate: _outputSampleRate,
      numChannels: 1,
      interleaved: true,
      bufferSize: 4096,
    );
    _isPlayerStarted = true;
  }

  /// Queues a chunk of Marie's voice (24kHz mono PCM16) for playback and extends the
  /// tracked playback end-of-timeline used by the mic gate above.
  Future<void> playAudioChunk(List<int> pcmBytes) async {
    await _ensurePlayerStarted();
    final bytes = Uint8List.fromList(pcmBytes);

    // Chunks arrive over the network faster than real-time playback, so this buffer's audio
    // won't actually finish sounding until whatever's already queued finishes, plus this
    // buffer's own duration. Extend the tracked timeline instead of resetting it.
    final frameCount = bytes.length / 2; // 16-bit mono samples
    final bufferDurationSeconds = frameCount / _outputSampleRate;
    final now = DateTime.now();
    final base = _scheduledPlaybackEndTime.isAfter(now) ? _scheduledPlaybackEndTime : now;
    _scheduledPlaybackEndTime = base.add(Duration(milliseconds: (bufferDurationSeconds * 1000).round()));

    try {
      await _player.feedUint8FromStream(bytes);
    } catch (_) {
      // Dropped chunk — matches the iOS original's "drop and let the system recover" behavior
      // on a transient playback error rather than crashing the call.
    }
  }

  Future<void> stopPlayback() async {
    try {
      if (!_player.isStopped) await _player.stopPlayer();
    } catch (_) {}
    _isPlayerStarted = false;
    // Discards everything queued, so the tracked playback timeline is now stale — without
    // this reset the mic gate would keep blocking uploads until a time that no longer
    // corresponds to any audio actually playing.
    _scheduledPlaybackEndTime = DateTime.fromMillisecondsSinceEpoch(0);
  }

  /// Best-effort speaker/earpiece toggle. flutter_sound doesn't expose direct output-port
  /// override the way AVAudioSession does on iOS, so this only affects platforms/backends
  /// that honor `AudioFocus`/session category defaults — during an active
  /// record+playback session, both platforms already default to the speaker.
  void setSpeakerEnabled(bool enabled) {
    // No-op placeholder: kept as a method so SessionScreen's speaker toggle has a stable
    // call site if a platform-specific output-route API is added later.
  }

  Future<void> dispose() async {
    await stopStreaming();
    await stopPlayback();
    try {
      if (!_recorder.isStopped) await _recorder.stopRecorder();
      await _recorder.closeRecorder();
    } catch (_) {}
    try {
      if (!_player.isStopped) await _player.stopPlayer();
      await _player.closePlayer();
    } catch (_) {}
  }
}
