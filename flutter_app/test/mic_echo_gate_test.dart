import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/services/mic_echo_gate.dart';

/// App-owned clips have a measured mute window plus a short output tail.
void main() {
  final t0 = DateTime(2026, 1, 1, 12);
  final longAgo = DateTime.fromMillisecondsSinceEpoch(0);

  test('closed while the tutor audio is being produced', () {
    final g = MicEchoGate();
    expect(g.blocks(outputActive: true, playbackEnd: longAgo, now: t0), isTrue);
  });

  test('closed while queued tutor audio is still due to play', () {
    final g = MicEchoGate();
    final end = t0.add(const Duration(seconds: 4));
    expect(
      g.blocks(
        outputActive: false,
        playbackEnd: end,
        now: t0.add(const Duration(seconds: 2)),
      ),
      isTrue,
    );
  });

  test('uses a short tail after playback ends', () {
    final g = MicEchoGate();
    final end = t0;
    expect(
      g.blocks(
        outputActive: false,
        playbackEnd: end,
        now: t0.add(const Duration(milliseconds: 100)),
      ),
      isTrue,
    );
    expect(
      g.blocks(
        outputActive: false,
        playbackEnd: end,
        now: t0.add(const Duration(milliseconds: 150)),
      ),
      isFalse,
    );
  });

  test('opens after the tail, so the learner can answer', () {
    final g = MicEchoGate();
    expect(
      g.blocks(
        outputActive: false,
        playbackEnd: t0,
        now: t0.add(const Duration(milliseconds: 200)),
      ),
      isFalse,
    );
  });

  test('the tail is short because clips already carry measured duration', () {
    expect(MicEchoGate.tail, const Duration(milliseconds: 150));
  });

  test('a lesson clip closes the mic for its whole length and the tail', () {
    final g = MicEchoGate();
    g.clipStarted(const Duration(seconds: 2), now: t0);
    for (final ms in [0, 500, 1900, 2000, 2149]) {
      expect(
        g.blocks(
          outputActive: false,
          playbackEnd: longAgo,
          now: t0.add(Duration(milliseconds: ms)),
        ),
        isTrue,
        reason: 'clip still audible at $ms ms',
      );
    }
    expect(
      g.blocks(
        outputActive: false,
        playbackEnd: longAgo,
        now: t0.add(const Duration(milliseconds: 2150)),
      ),
      isFalse,
    );
  });

  test('a second clip extends, never shortens, the closed window', () {
    final g = MicEchoGate();
    g.clipStarted(const Duration(seconds: 5), now: t0);
    g.clipStarted(
      const Duration(seconds: 1),
      now: t0.add(const Duration(seconds: 1)),
    );
    expect(
      g.blocks(
        outputActive: false,
        playbackEnd: longAgo,
        now: t0.add(const Duration(seconds: 5)),
      ),
      isTrue,
    );
  });

  test('playback always blocks even when a speech detector hears a voice', () {
    final g = MicEchoGate();
    final playbackEnd = t0.add(const Duration(seconds: 3));
    for (final route in ['speaker', 'earpiece', 'wired', 'AirPods']) {
      expect(
        g.blocks(outputActive: true, playbackEnd: playbackEnd, now: t0),
        isTrue,
        reason: '$route must not forward sound made by the app',
      );
      expect(
        g.blocks(
          outputActive: false,
          playbackEnd: playbackEnd,
          now: playbackEnd.add(const Duration(milliseconds: 149)),
        ),
        isTrue,
        reason: '$route must retain the playback tail',
      );
      expect(
        g.blocks(
          outputActive: false,
          playbackEnd: playbackEnd,
          now: playbackEnd.add(const Duration(milliseconds: 150)),
        ),
        isFalse,
        reason: '$route can accept the learner after the tail',
      );
    }
  });

  test('reset opens the mic again', () {
    final g = MicEchoGate();
    g.clipStarted(const Duration(seconds: 5), now: t0);
    g.reset();
    expect(g.clipBlocks(now: t0.add(const Duration(seconds: 1))), isFalse);
  });
}
