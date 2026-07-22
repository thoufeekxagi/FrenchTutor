import 'dart:async';
import 'dart:collection';
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
  final FlutterSoundRecorder _recorder = FlutterSoundRecorder(
    logLevel: Level.error,
  );
  final FlutterSoundPlayer _player = FlutterSoundPlayer(logLevel: Level.error);

  StreamController<Uint8List>? _micStreamController;
  StreamSubscription<Uint8List>? _micSub;

  /// Reacts to phone calls / other apps interrupting the session, and to
  /// Bluetooth devices (AirPods etc.) connecting or disconnecting mid-call.
  /// Without these, iOS silently leaves the session on whatever route it
  /// fell back to (usually the speaker) after an interruption ends or a
  /// Bluetooth device reconnects, instead of reclaiming the preferred route
  /// the way native VoIP/Messages calls do.
  StreamSubscription<AudioInterruptionEvent>? _interruptionSub;
  StreamSubscription<AudioDevicesChangedEvent>? _devicesChangedSub;

  bool _isStreaming = false;
  bool _isPlayerStarted = false;
  bool _isSessionConfigured = false;
  void Function(List<int> chunk)? _audioChunkCallback;

  /// Gemini delivers audio over the WebSocket in irregular network bursts, not a steady
  /// real-time stream. Feeding each chunk to flutter_sound the instant it arrives — as the
  /// original code did — starves the player's small internal buffer between bursts (causing
  /// audible gaps/cutoffs) and, worse, can call `feedUint8FromStream` again before the
  /// previous call has finished awaiting, which is a known source of pops/jitter in
  /// flutter_sound. This queue decouples network arrival timing from playback feeding: chunks
  /// are appended here immediately, and a single drain loop feeds them to the player strictly
  /// one at a time, always awaiting the previous feed before starting the next. Native
  /// AVAudioEngine got this smoothing for free via buffer-ahead scheduling; flutter_sound
  /// needs it built explicitly.
  final Queue<Uint8List> _playbackQueue = Queue<Uint8List>();
  bool _isDrainingPlaybackQueue = false;

  /// A PCM16 sample is 2 bytes; Gemini's WebSocket chunk boundaries don't
  /// respect that, so a chunk can arrive with an odd byte count, splitting a
  /// sample across two chunks. Feeding a misaligned chunk straight to the
  /// player shifts every sample after that point — the exact cause of
  /// intermittent gargled/robotic playback. This carries the stray trailing
  /// byte over to be prepended to the next chunk instead of ever feeding a
  /// misaligned buffer to the player.
  Uint8List? _pendingOddByte;

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
    final session = await AudioSession.instance;
    if (!_isSessionConfigured) {
      await session.configure(
        AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
          avAudioSessionCategoryOptions:
              AVAudioSessionCategoryOptions.defaultToSpeaker |
              AVAudioSessionCategoryOptions.allowBluetooth |
              AVAudioSessionCategoryOptions.allowBluetoothA2dp,
          avAudioSessionMode: AVAudioSessionMode.voiceChat,
          androidAudioAttributes: const AndroidAudioAttributes(
            contentType: AndroidAudioContentType.speech,
            usage: AndroidAudioUsage.voiceCommunication,
          ),
          androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
        ),
      );
      _isSessionConfigured = true;
    }
    // Re-asserted every time (mic (re)start, app resume, unmute, PTT-down), not just on first
    // configure — an interruption (phone call) or the app being backgrounded can leave the
    // shared session on the wrong route by the time we come back, and re-activating is what
    // makes the OS re-resolve routing against our configured options rather than leaving it
    // wherever it fell back to.
    await session.setActive(true);
  }

  /// Re-activating the session (rather than just observing) is what actually makes iOS/
  /// Android re-evaluate which output device should carry audio — a route change on its own
  /// does not force this, which is why a reconnecting Bluetooth device could otherwise sit
  /// there "available" while the call stayed stuck on the speaker.
  Future<void> _reclaimPreferredRoute() async {
    if (!_isStreaming) return;
    try {
      final session = await AudioSession.instance;
      await session.setActive(true);
    } catch (_) {}
  }

  void _listenForRouteChanges(AudioSession session) {
    _interruptionSub?.cancel();
    _devicesChangedSub?.cancel();
    _interruptionSub = session.interruptionEventStream.listen((event) {
      if (event.begin) {
        // Anything that takes audio focus away from us — a real incoming call,
        // another app's sound, even the OS's own screenshot-shutter sound —
        // fires this. Previously nothing happened here, so whatever briefly
        // played through that conflict (including our own already-buffered
        // audio getting forcibly ducked by iOS) sounded like an abrupt
        // stutter/cut. Muting our own output cleanly the instant this starts
        // means the interruption is silent on our end instead of glitchy.
        try {
          _player.setVolume(0);
        } catch (_) {}
      } else {
        // iOS restores *a* route on its own by an interruption's end, but not always the
        // one we want (it can land back on the speaker even with AirPods connected), so
        // reclaiming here nudges it to re-resolve against our configured options.
        _reclaimPreferredRoute();
        _recoverFromInterruptionIfNeeded();
      }
    });
    _devicesChangedSub = session.devicesChangedEventStream.listen((event) {
      // A Bluetooth device connecting mid-call (e.g. AirPods reconnecting after a phone-call
      // interruption) doesn't retroactively move already-flowing audio over on its own.
      if (event.devicesAdded.isNotEmpty) _reclaimPreferredRoute();
    });
  }

  /// A real interruption (an actual incoming phone/VoIP call, not just a
  /// brief system sound) can leave flutter_sound's recorder silently
  /// stopped underneath us on iOS — a route-reclaim alone doesn't restart
  /// it, so the mic would stay dead for the rest of the call with no error
  /// surfaced anywhere. Detect that and cleanly restart capture; always
  /// restore volume regardless, since the mute above must never get stuck.
  Future<void> _recoverFromInterruptionIfNeeded() async {
    try {
      if (_isStreaming && _recorder.isStopped) {
        await _recorder.openRecorder();
        await _recorder.startRecorder(
          codec: Codec.pcm16,
          toStream: _micStreamController!.sink,
          sampleRate: _inputSampleRate,
          numChannels: 1,
        );
      }
    } catch (_) {
      // Best-effort — if this fails the call continues audio-out-only rather
      // than crashing; the user can still end/restart the call normally.
    } finally {
      try {
        await _player.setVolume(1.0);
      } catch (_) {}
    }
  }

  Future<void> startStreaming({
    required void Function(List<int> chunk) onChunk,
  }) async {
    if (_isStreaming) return;
    _audioChunkCallback = onChunk;
    await _configureSessionIfNeeded();
    _listenForRouteChanges(await AudioSession.instance);

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

  /// Barge-in (mic open while Marie speaks) was tried and REJECTED after device testing:
  /// Gemini Live's server-side VAD treats ANY sound during her generation — background
  /// noise, friends talking, a cough — as the student interrupting, killing her audio
  /// mid-word and making her stutter and restart. Unmanageably ugly. So the mic stays
  /// gated while she talks: she always finishes her sentence, and the student replies in
  /// the natural gap. Voice navigation stays fast anyway — the student's transcript
  /// flushes to the intent judge on its own debounce (see GeminiLiveService), never
  /// waiting on Marie — and the on-screen Back/Next buttons work mid-speech for anyone
  /// who truly can't wait.
  static const allowBargeIn = false;

  void _handleMicChunk(Uint8List chunk) {
    if (!allowBargeIn) {
      final blockedByOutput = isOutputActive;
      final withinTailGrace = DateTime.now().isBefore(
        _scheduledPlaybackEndTime.add(
          Duration(milliseconds: (_playbackTailGraceSeconds * 1000).round()),
        ),
      );
      if (blockedByOutput || withinTailGrace) return;
    }
    _audioChunkCallback?.call(chunk);
  }

  /// Latched so concurrent callers (audio chunks arrive in bursts, each calling
  /// `playAudioChunk` unawaited) share ONE open/start sequence instead of racing
  /// `openPlayer` — the race leaves the player wedged and everything after plays silence.
  Future<void>? _playerStartLatch;

  Future<void> _ensurePlayerStarted() {
    if (_isPlayerStarted) return Future.value();
    return _playerStartLatch ??= _startPlayer().whenComplete(
      () => _playerStartLatch = null,
    );
  }

  Future<void> _startPlayer() async {
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
      // 4096 (~85ms at 24kHz mono PCM16) was too tight — any network burst gap wider than
      // that underran the player and produced an audible cutoff. 16384 (~340ms) gives the
      // serialized playback queue above enough headroom to smooth over Gemini's bursty
      // WebSocket delivery without the extra latency becoming perceptible in conversation.
      bufferSize: 16384,
    );
    _isPlayerStarted = true;
  }

  /// Queues a chunk of Marie's voice (24kHz mono PCM16) for playback and extends the
  /// tracked playback end-of-timeline used by the mic gate above. The chunk is appended to
  /// `_playbackQueue` and fed to the player by the serialized drain loop below — never fed
  /// directly here — so bursty network delivery can't starve or race the player.
  Future<void> playAudioChunk(List<int> pcmBytes) async {
    var bytes = Uint8List.fromList(pcmBytes);
    if (_pendingOddByte != null) {
      bytes = Uint8List.fromList([..._pendingOddByte!, ...bytes]);
      _pendingOddByte = null;
    }
    if (bytes.length.isOdd) {
      _pendingOddByte = Uint8List.fromList([bytes.last]);
      bytes = Uint8List.sublistView(bytes, 0, bytes.length - 1);
    }

    // Arm/extend the mic echo-gate's tail-grace window SYNCHRONOUSLY, before
    // the await below — `_ensurePlayerStarted()` does real platform-channel
    // I/O and can take real time on the very first chunk of a call, and the
    // gate in `_handleMicChunk` must already reflect "audio will be playing
    // until at least now + this buffer's duration" for that entire window.
    // Arming this AFTER awaiting player startup left a gap where a fast
    // turnComplete could flip `isOutputActive` false while this value was
    // still at its stale/epoch default, opening the mic gate before the
    // tutor's own reply had even started sounding — the tutor's voice would
    // then get captured and sent back as if the user had said it.
    //
    // Chunks arrive over the network faster than real-time playback, so this buffer's audio
    // won't actually finish sounding until whatever's already queued finishes, plus this
    // buffer's own duration. Extend the tracked timeline instead of resetting it.
    final frameCount = bytes.length / 2; // 16-bit mono samples
    final bufferDurationSeconds = frameCount / _outputSampleRate;
    final now = DateTime.now();
    final base = _scheduledPlaybackEndTime.isAfter(now)
        ? _scheduledPlaybackEndTime
        : now;
    _scheduledPlaybackEndTime = base.add(
      Duration(milliseconds: (bufferDurationSeconds * 1000).round()),
    );

    // This is genuinely new, wanted audio — cancel any mute a previous
    // stopPlayback() left pending. Without this, switching straight from one
    // clip to another (e.g. tapping a different voice-preview persona) fed
    // the new bytes in while still muted from cutting the old one, and the
    // new clip stayed silent until the old mute timer eventually expired.
    _muteGeneration++;
    unawaited(_player.setVolume(1.0).catchError((_) {}));

    await _ensurePlayerStarted();
    _playbackQueue.add(bytes);
    _drainPlaybackQueue();
  }

  /// Feeds queued chunks to the player strictly one at a time, always awaiting the previous
  /// `feedUint8FromStream` call before starting the next. Safe to call repeatedly — re-entrant
  /// calls while a drain is already running just return immediately, since the running loop
  /// will pick up anything newly queued.
  Future<void> _drainPlaybackQueue() async {
    if (_isDrainingPlaybackQueue) return;
    _isDrainingPlaybackQueue = true;
    try {
      while (_playbackQueue.isNotEmpty) {
        final bytes = _playbackQueue.removeFirst();
        try {
          await _player.feedUint8FromStream(bytes);
        } catch (_) {
          // Dropped chunk — matches the iOS original's "drop and let the system recover"
          // behavior on a transient playback error rather than crashing the call.
        }
      }
    } finally {
      _isDrainingPlaybackQueue = false;
    }
  }

  int _muteGeneration = 0;

  Future<void> stopPlayback() async {
    // Discard anything not yet fed to the player — otherwise queued chunks from before the
    // interruption keep draining and playing after the model was told to stop (barge-in /
    // card-change cut). The player itself is deliberately LEFT RUNNING: tearing it down here
    // (stopPlayer + restart on the next chunk) is what froze Marie's voice for the rest of
    // the call — the restart raced the very next burst of incoming chunks, openPlayer was
    // re-entered while already open, and every subsequent feed failed silently.
    _playbackQueue.clear();
    // A carried-over stray byte belonged to the utterance being cut — letting
    // it prepend to whatever plays next would misalign that unrelated audio.
    _pendingOddByte = null;

    // How long whatever's already been fed to the player still has left to
    // sound, BEFORE it gets reset below. Live-call chunks are short (the
    // ~340ms internal buffer is what the 450ms floor covers), but a one-shot
    // clip (TTS narration, a voice-preview sample) is fed to the player as
    // ONE multi-second buffer in a single call — muting for only a fixed
    // 450ms let its un-played remainder become audible again seconds before
    // it had actually finished, which sounded like the old clip resuming
    // and the new one starting on top of it. Mute for at least as long as
    // there's real audio left to cover, not a flat guess.
    final now = DateTime.now();
    final remainingMs = _scheduledPlaybackEndTime.isAfter(now)
        ? _scheduledPlaybackEndTime.difference(now).inMilliseconds
        : 0;
    final muteMs = remainingMs > 450 ? remainingMs + 50 : 450;

    // Gentle cut: muting the player silences the tail cleanly (a volume change, not a
    // buffer tear), then volume is restored once the tail has drained silently. The
    // generation counter makes a rapid second cut extend the mute instead of the first
    // cut's restore unmuting it early.
    final generation = ++_muteGeneration;
    try {
      await _player.setVolume(0);
    } catch (_) {}
    Future.delayed(Duration(milliseconds: muteMs), () async {
      if (generation != _muteGeneration) return;
      try {
        await _player.setVolume(1.0);
      } catch (_) {}
    });
    // The tracked timeline is now stale — without this reset the mic gate would keep
    // blocking uploads until a time that no longer corresponds to any audio actually playing.
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
    await _interruptionSub?.cancel();
    _interruptionSub = null;
    await _devicesChangedSub?.cancel();
    _devicesChangedSub = null;
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
    _isPlayerStarted = false;
  }
}
