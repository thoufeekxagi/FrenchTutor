import 'dart:typed_data';

import 'package:flutter_sound/flutter_sound.dart';
import 'package:logger/logger.dart' show Level;

/// Plays provider-rendered MP3 clips independently from the existing PCM
/// Gemini Live stream. Both services are stopped by the listening screen before
/// switching sources, so the two native player modes never overlap.
class ElevenLabsAudioPlaybackService {
  ElevenLabsAudioPlaybackService._();

  static final shared = ElevenLabsAudioPlaybackService._();

  final FlutterSoundPlayer _player = FlutterSoundPlayer(logLevel: Level.error);
  bool _opened = false;
  bool isPlaying = false;

  Future<void> play(Uint8List bytes, {void Function()? onFinished}) async {
    if (bytes.isEmpty) throw StateError('ElevenLabs audio is empty');
    await stop();
    if (!_opened) {
      await _player.openPlayer();
      _opened = true;
    }
    isPlaying = true;
    await _player.startPlayer(
      fromDataBuffer: bytes,
      codec: Codec.mp3,
      whenFinished: () {
        isPlaying = false;
        onFinished?.call();
      },
    );
  }

  Future<void> stop() async {
    isPlaying = false;
    if (!_opened || _player.isStopped) return;
    try {
      await _player.stopPlayer();
    } catch (_) {
      // A player interruption should never make the lesson route fail.
    }
  }

  Future<void> dispose() async {
    await stop();
    if (!_opened) return;
    try {
      await _player.closePlayer();
    } catch (_) {}
    _opened = false;
  }
}
