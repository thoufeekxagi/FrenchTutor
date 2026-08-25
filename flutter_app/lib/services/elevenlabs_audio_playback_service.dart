import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_sound/flutter_sound.dart';
import 'package:logger/logger.dart' show Level;

/// Plays provider-rendered MP3 clips and WAV-wrapped Gemini Live clips. Both
/// services are stopped by the listening screen before switching sources, so
/// the two native player modes never overlap.
class ElevenLabsAudioPlaybackService {
  ElevenLabsAudioPlaybackService._();

  static final shared = ElevenLabsAudioPlaybackService._();

  final FlutterSoundPlayer _player = FlutterSoundPlayer(logLevel: Level.error);
  final StreamController<PlaybackDisposition> _progressController =
      StreamController<PlaybackDisposition>.broadcast();
  StreamSubscription<PlaybackDisposition>? _playerProgressSubscription;
  bool _opened = false;
  bool isPlaying = false;
  bool _isPaused = false;

  Stream<PlaybackDisposition> get progress => _progressController.stream;
  bool get canResume => _isPaused;

  Future<Duration?> play(
    Uint8List bytes, {
    void Function()? onFinished,
    double speed = 1,
    String container = 'mp3',
  }) async {
    if (bytes.isEmpty) throw StateError('ElevenLabs audio is empty');
    await stop();
    if (!_opened) {
      await _player.openPlayer();
      _opened = true;
    }
    await _player.setSubscriptionDuration(const Duration(milliseconds: 200));
    await _playerProgressSubscription?.cancel();
    _playerProgressSubscription = _player.onProgress?.listen(
      _progressController.add,
    );
    isPlaying = true;
    _isPaused = false;
    final duration = await _player.startPlayer(
      fromDataBuffer: bytes,
      codec: container.toLowerCase() == 'wav' ? Codec.pcm16WAV : Codec.mp3,
      whenFinished: () {
        isPlaying = false;
        _isPaused = false;
        onFinished?.call();
      },
    );
    if (speed != 1) await setSpeed(speed);
    return duration;
  }

  Future<void> pause() async {
    if (!_opened || !isPlaying) return;
    try {
      await _player.pausePlayer();
      isPlaying = false;
      _isPaused = true;
    } catch (_) {}
  }

  Future<void> resume() async {
    if (!_opened || !_isPaused) return;
    try {
      await _player.resumePlayer();
      isPlaying = true;
      _isPaused = false;
    } catch (_) {}
  }

  Future<void> setSpeed(double speed) async {
    if (!_opened) return;
    try {
      await _player.setSpeed(speed.clamp(0.5, 2.0).toDouble());
    } catch (_) {}
  }

  Future<void> stop() async {
    isPlaying = false;
    _isPaused = false;
    if (!_opened || _player.isStopped) return;
    try {
      await _player.stopPlayer();
    } catch (_) {
      // A player interruption should never make the lesson route fail.
    }
  }

  Future<void> dispose() async {
    await stop();
    await _playerProgressSubscription?.cancel();
    await _progressController.close();
    if (!_opened) return;
    try {
      await _player.closePlayer();
    } catch (_) {}
    _opened = false;
  }
}
