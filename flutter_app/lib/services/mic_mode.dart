import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

/// How the microphone is gated during a live session (PILOT_EXECUTION_PLAN.md P1.3).
///
/// [auto] — hands-free: the mic streams continuously and server-side voice activity
/// detection segments utterances. Great at home; on a bus the background noise gets
/// transcribed as garbage "speech".
///
/// [pushToTalk] — the mic streams ONLY while the hold-to-talk button is physically
/// held. Noise can never become an utterance because nothing is ever sent; the
/// student decides exactly when they are speaking.
enum MicMode { auto, pushToTalk }

/// Persisted once, app-wide — the choice survives across sessions and stages.
class MicModePrefs {
  MicModePrefs._();

  static const _key = 'mic_mode';

  static Future<MicMode> load() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key) == 'push_to_talk'
        ? MicMode.pushToTalk
        : MicMode.auto;
  }

  static Future<void> save(MicMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      mode == MicMode.pushToTalk ? 'push_to_talk' : 'auto',
    );
  }
}

/// Owns every decision about when the mic streams for one live call, so all four
/// live screens behave identically. Pure logic — the audio service and socket are
/// injected as callbacks, which also makes this fully unit-testable.
class MicController {
  MicController({
    required this.startStream,
    required this.stopStream,
    required this.sendAudio,
  });

  final Future<void> Function() startStream;
  final Future<void> Function() stopStream;
  final void Function(List<int> pcmBytes) sendAudio;

  MicMode _mode = MicMode.auto;
  MicMode get mode => _mode;

  bool _muted = false;
  bool get muted => _muted;

  bool _connected = false;
  bool _held = false;

  /// True while the hold-to-talk button is physically pressed.
  bool get isHeld => _held;

  /// Server VAD closes an utterance on ~2.5s of silence. In push-to-talk we cut the
  /// stream at release, so the server would otherwise wait forever for end-of-speech —
  /// this tail of silent PCM (16kHz mono 16-bit) closes the turn deterministically.
  /// 10 × 300ms = 3.0s of silence, comfortably past the 2.5s VAD threshold.
  static const silenceTailChunks = 10;
  static const silenceChunkBytes = 9600; // 300ms at 16kHz mono PCM16

  /// Call once the live socket reports connected and mic permission is granted.
  Future<void> onConnected() async {
    _connected = true;
    if (_mode == MicMode.auto && !_muted) await startStream();
  }

  /// Switch modes mid-call. Auto → PTT stops the open mic immediately;
  /// PTT → Auto opens it (unless muted).
  Future<void> setMode(MicMode mode) async {
    if (mode == _mode) return;
    _mode = mode;
    _held = false;
    unawaited(MicModePrefs.save(mode));
    if (!_connected) return;
    if (mode == MicMode.auto) {
      if (!_muted) await startStream();
    } else {
      await stopStream();
    }
  }

  /// Auto-mode mute toggle. Meaningless in push-to-talk (the mic is already gated).
  Future<void> setMuted(bool muted) async {
    _muted = muted;
    if (!_connected || _mode != MicMode.auto) return;
    if (muted) {
      await stopStream();
    } else {
      await startStream();
    }
  }

  /// Hold-to-talk pressed.
  Future<void> pttDown() async {
    if (_mode != MicMode.pushToTalk || !_connected || _held) return;
    _held = true;
    await startStream();
  }

  /// Hold-to-talk released: stop capturing, then close the utterance for the
  /// server's VAD with a silent tail.
  Future<void> pttUp() async {
    if (_mode != MicMode.pushToTalk || !_held) return;
    _held = false;
    await stopStream();
    final silence = List<int>.filled(silenceChunkBytes, 0);
    for (var i = 0; i < silenceTailChunks; i++) {
      sendAudio(silence);
    }
  }

  /// App backgrounded: the mic never streams from a pocket, in either mode.
  Future<void> onAppPaused() async {
    _held = false;
    await stopStream();
  }

  /// App foregrounded: auto mode reopens the mic (unless muted); push-to-talk
  /// stays closed until the next hold.
  Future<void> onAppResumed() async {
    if (!_connected) return;
    if (_mode == MicMode.auto && !_muted) await startStream();
  }

  /// Adopt the persisted preference before the call connects.
  void adoptSavedMode(MicMode saved) {
    if (_connected) return;
    _mode = saved;
  }
}
