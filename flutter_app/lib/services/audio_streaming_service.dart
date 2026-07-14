import 'dart:async';
import 'dart:typed_data';

import 'package:audio_session/audio_session.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:logger/logger.dart' show Level;
import 'package:permission_handler/permission_handler.dart';

/// Ported from AudioStreamingService.swift — bidirectional PCM streaming for the live
/// Gemini call: 16kHz mono PCM16 captured from the mic, 24kHz mono PCM16 played back for
/// Marie's voice. Unlike the iOS original (which does its own AVAudioEngine sample-rate
/// conversion), flutter_sound's recorder/player do the native-format <-> PCM conversion for
/// us at the given `sampleRate`, so there's no manual `AVAudioConverter` equivalent needed
/// here.
///
/// flutter_sound's own `setAudioFocus`/speaker-toggle is unreliable on iOS (a known upstream
/// bug), so routing is configured once via the `audio_session` package instead — mirroring
/// the iOS original's `session.setCategory(.playAndRecord, options: [.defaultToSpeaker,
/// .allowBluetooth])`. Without this, iOS defaults a playAndRecord session to the quiet
/// earpiece receiver instead of the main loudspeaker.
class AudioStreamingService {
  // flutter_sound's default log level is extremely chatty (every internal method-channel call
  // and callback), which drowns out real errors in `flutter run` output — pinned to `error` so
  // only genuine problems show up.
  final FlutterSoundRecorder _recorder = FlutterSoundRecorder(logLevel: Level.error);
  final FlutterSoundPlayer _player = FlutterSoundPlayer(logLevel: Level.error);

  StreamController<Uint8List>? _micStreamController;
  StreamSubscription<Uint8List>? _micSub;

  bool _isStreaming = false;
  bool _isPlayerStarted = false;
  bool _isSessionConfigured = false;
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

  /// Configures the shared audio session once, before the recorder/player ever open —
  /// `defaultToSpeaker` is what actually routes output to the main loudspeaker by default
  /// (iOS otherwise picks the earpiece receiver for a `playAndRecord` category); `allowBluetooth`
  /// lets a connected Bluetooth headset/earbuds still take over routing normally.
  Future<void> _configureSessionIfNeeded() async {
    if (_isSessionConfigured) return;
    final session = await AudioSession.instance;
    await session.configure(AudioSessionConfiguration(
      avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
      avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.defaultToSpeaker |
          AVAudioSessionCategoryOptions.allowBluetooth |
          AVAudioSessionCategoryOptions.allowBluetoothA2dp,
      avAudioSessionMode: AVAudioSessionMode.voiceChat,
      androidAudioAttributes: const AndroidAudioAttributes(
        contentType: AndroidAudioContentType.speech,
        usage: AndroidAudioUsage.voiceCommunication,
      ),
      androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
    ));
    await session.setActive(true);
    _isSessionConfigured = true;
  }

  Future<void> startStreaming({required void Function(List<int> chunk) onChunk}) async {
    if (_isStreaming) return;
    _audioChunkCallback = onChunk;
    await _configureSessionIfNeeded();

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
    await _configureSessionIfNeeded();
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

  /// Best-effort speaker/earpiece toggle for the in-call UI button. The session is already
  /// configured to default to the main speaker (see `_configureSessionIfNeeded`), which
  /// covers the common case; neither `flutter_sound` nor `audio_session` expose a reliable
  /// live output-port override on iOS (flutter_sound's own `setAudioFocus` is a known-broken
  /// upstream bug), so toggling back to the earpiece mid-call is not yet wired to a real
  /// platform call. Kept as a method so a platform-channel override can be dropped in later
  /// without touching call sites.
  void setSpeakerEnabled(bool enabled) {}

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
