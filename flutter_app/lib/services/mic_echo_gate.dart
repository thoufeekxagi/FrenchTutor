/// Local mute window for app-owned lesson clips on the conservative audio
/// route. The V3 tutor uses platform AEC for the tutor's own output so learners
/// can interrupt; this gate remains for short app clips where the exact end is
/// known. Full-duplex paths add only a small device/output tail.
class MicEchoGate {
  /// App clips already carry their measured playback duration. This margin
  /// covers the output route's short acoustic tail without adding a long pause.
  static const tail = Duration(milliseconds: 150);

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
