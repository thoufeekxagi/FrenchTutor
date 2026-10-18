import 'dart:async';

import 'package:flutter/services.dart';

/// iOS full-duplex PCM audio backed by one AVAudioEngine. The same engine
/// captures the mic with VoiceProcessingIO enabled and plays the tutor through
/// its render path, giving the system echo canceller the actual playback
/// reference it needs. Android continues to use AudioRecord's communication
/// source and platform AEC/NS through flutter_sound.
class NativeVoiceAudio {
  NativeVoiceAudio();

  static const _method = MethodChannel('com.parlesprint/voice_audio');
  static const _events = EventChannel('com.parlesprint/voice_audio_events');

  StreamSubscription<Object?>? _subscription;
  final StreamController<Uint8List> _micFrames =
      StreamController<Uint8List>.broadcast();
  bool _started = false;
  bool _disposed = false;

  Stream<Uint8List> get micFrames => _micFrames.stream;
  bool get isStarted => _started;

  Future<void> start() async {
    if (_disposed) throw StateError('Native voice audio is disposed');
    if (_started) return;
    _subscription ??= _events.receiveBroadcastStream().listen((event) {
      if (event is Uint8List) {
        _micFrames.add(event);
      } else if (event is List<int>) {
        _micFrames.add(Uint8List.fromList(event));
      }
    }, onError: _micFrames.addError);
    try {
      final status = await _method.invokeMapMethod<String, Object?>('start');
      if (status?['voiceProcessingEnabled'] != true) {
        throw StateError('iOS voice processing did not enable');
      }
      _started = true;
    } catch (_) {
      await _subscription?.cancel();
      _subscription = null;
      try {
        await _method.invokeMethod<void>('stop');
      } catch (_) {}
      rethrow;
    }
  }

  Future<void> setMicEnabled(bool enabled) async {
    if (_started) await _method.invokeMethod<void>('setMicEnabled', enabled);
  }

  Future<void> playPcm(Uint8List pcm24KhzMono) async {
    if (!_started || pcm24KhzMono.isEmpty) return;
    await _method.invokeMethod<void>('playPcm', pcm24KhzMono);
  }

  Future<void> stopPlayback() async {
    if (_started) await _method.invokeMethod<void>('stopPlayback');
  }

  Future<void> setOutputVolume(double volume) async {
    if (_started) {
      await _method.invokeMethod<void>(
        'setOutputVolume',
        volume.clamp(0.0, 1.0),
      );
    }
  }

  Future<void> recover() async {
    if (!_started || _disposed) return;
    final status = await _method.invokeMapMethod<String, Object?>('recover');
    if (status?['voiceProcessingEnabled'] != true) {
      throw StateError('iOS voice processing could not recover');
    }
  }

  Future<Map<String, Object?>> debugStatus() async =>
      await _method.invokeMapMethod<String, Object?>('debugStatus') ?? {};

  Future<void> ensureRunning() async {
    if (_disposed) throw StateError('Native voice audio is disposed');
    final status = await _method.invokeMapMethod<String, Object?>('start');
    if (status?['voiceProcessingEnabled'] != true) {
      throw StateError('iOS voice processing is not running');
    }
    _started = true;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _subscription?.cancel();
    _subscription = null;
    try {
      if (_started) await _method.invokeMethod<void>('stop');
    } finally {
      _started = false;
      await _micFrames.close();
    }
  }
}
