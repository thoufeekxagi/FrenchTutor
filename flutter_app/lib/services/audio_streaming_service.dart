/// The platform seam for live-call audio.
///
/// Bidirectional PCM streaming for the Gemini Live call: 16kHz mono PCM16
/// captured from the mic, 24kHz mono PCM16 played back for the tutor's voice.
/// That wire format is identical on every platform — only the capture/playback
/// plumbing underneath differs, which is exactly why this is an interface and
/// not a `kIsWeb` branch inside the call logic.
///
/// Implementations:
///  - `audio_streaming_service_native.dart` — flutter_sound + audio_session
///    (iOS/Android). The original, device-tested implementation; unchanged.
///  - `audio_streaming_service_web.dart` — Web Audio API via package:web.
///  - `audio_streaming_service_stub.dart` — throws; platforms with neither.
///
/// Callers construct `AudioStreamingService()` and never learn which one they
/// got. Everything above this line (the Gemini Live protocol in
/// `gemini_live_service.dart`, the call lifecycle in
/// `inline_call_controller.dart`, every call UI) is shared across all
/// platforms. See docs/web_migration/05_phase5_voice_and_realtime.md.
library;

import 'audio_streaming_service_stub.dart'
    if (dart.library.io) 'audio_streaming_service_native.dart'
    if (dart.library.js_interop) 'audio_streaming_service_web.dart';

abstract class AudioStreamingService {
  /// Returns the implementation for the current platform, chosen by the
  /// conditional import above.
  factory AudioStreamingService() => createAudioStreamingService();

  /// While true, captured mic audio is not forwarded via the chunk callback.
  /// Prevents the mic picking up the tutor's own speaker output and feeding it
  /// back to Gemini as an echo, since platform echo-cancellation is
  /// deliberately not used (it degrades output audio quality).
  ///
  /// Set by the call controller around the tutor's turn; implementations may
  /// additionally hold the mic closed for a short tail after this goes false,
  /// because network delivery outruns real-time playback.
  bool get isOutputActive;
  set isOutputActive(bool value);

  /// Requests microphone permission. Returns whether it was granted.
  Future<bool> requestPermission();

  /// Opens the mic and begins delivering 16kHz mono PCM16 chunks to [onChunk].
  /// Idempotent: a second call while already streaming is a no-op.
  Future<void> startStreaming({
    required void Function(List<int> chunk) onChunk,
  });

  /// Closes the mic. Idempotent.
  Future<void> stopStreaming();

  /// Enqueues a 24kHz mono PCM16 chunk for playback. Chunks arrive from the
  /// network in irregular bursts, so implementations must queue and feed them
  /// sequentially rather than playing each on arrival.
  Future<void> playAudioChunk(List<int> pcmBytes);

  /// Drops anything queued or playing (barge-in / call end).
  Future<void> stopPlayback();

  /// Routes output to the loudspeaker rather than the earpiece where the
  /// platform makes that distinction. No-op where it does not (web).
  void setSpeakerEnabled(bool enabled);

  /// Releases all audio resources. The instance must not be reused after this.
  Future<void> dispose();
}
