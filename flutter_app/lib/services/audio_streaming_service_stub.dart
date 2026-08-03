import 'audio_streaming_service.dart';

/// Fallback for a platform with neither `dart.library.io` nor
/// `dart.library.js_interop`. Unreachable in practice for this app's targets;
/// it exists so the conditional import in `audio_streaming_service.dart` has a
/// valid default and fails loudly rather than mysteriously if that ever
/// changes.
AudioStreamingService createAudioStreamingService() => throw UnsupportedError(
  'Live-call audio is unavailable on this platform: no native '
  '(flutter_sound) or web (Web Audio API) implementation applies.',
);
