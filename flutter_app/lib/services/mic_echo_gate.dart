/// The one rule that stops a tutor from hearing herself.
///
/// While the phone is making sound, the microphone must send nothing to the
/// model. Sound includes the tutor's voice, the short tail after it (audio is
/// buffered and keeps playing after the last chunk is queued), and any clip the
/// app plays itself, such as a lesson's speaker button. This holds for the
/// loudspeaker, the earpiece, AirPods and wired headsets alike, because it does
/// not depend on the route.
///
/// Anything that plays audio while a call can be open must go through here
/// (see AudioStreamingService.blockMicUntil). Never let the model answer its
/// own voice.
class MicEchoGate {
  /// How long the mic stays closed after playback is scheduled to end. The
  /// native player and the speaker keep sounding after the last chunk, so a
  /// short margin lets the tail of her voice back in as "the learner".
  static const tail = Duration(milliseconds: 900);

  DateTime _blockedUntil = DateTime.fromMillisecondsSinceEpoch(0);

  /// Closes the mic until [time] (plus nothing: callers pass the final time).
  void blockUntil(DateTime time) {
    if (time.isAfter(_blockedUntil)) _blockedUntil = time;
  }

  /// A clip of [length] starts now: the mic stays closed for its whole length
  /// and the usual tail.
  void clipStarted(Duration length, {DateTime? now}) {
    blockUntil((now ?? DateTime.now()).add(length + tail));
  }

  void reset() => _blockedUntil = DateTime.fromMillisecondsSinceEpoch(0);

  bool clipBlocks({DateTime? now}) =>
      (now ?? DateTime.now()).isBefore(_blockedUntil);

  /// True when a microphone chunk must be dropped right now.
  bool blocks({
    required bool outputActive,
    required DateTime playbackEnd,
    DateTime? now,
  }) {
    final t = now ?? DateTime.now();
    return outputActive ||
        t.isBefore(playbackEnd.add(tail)) ||
        clipBlocks(now: t);
  }
}
