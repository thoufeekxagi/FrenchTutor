import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/services/mic_echo_gate.dart';

/// The rule: the microphone never hears the phone's own sound.
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

  test(
    'stays closed for the tail after playback ends (buffered speaker audio)',
    () {
      final g = MicEchoGate();
      final end = t0;
      expect(
        g.blocks(
          outputActive: false,
          playbackEnd: end,
          now: t0.add(const Duration(milliseconds: 400)),
        ),
        isTrue,
        reason: 'the old 350 ms margin let the end of her voice back in',
      );
      expect(
        g.blocks(
          outputActive: false,
          playbackEnd: end,
          now: t0.add(const Duration(milliseconds: 850)),
        ),
        isTrue,
      );
    },
  );

  test('opens after the tail, so the learner can answer', () {
    final g = MicEchoGate();
    expect(
      g.blocks(
        outputActive: false,
        playbackEnd: t0,
        now: t0.add(const Duration(milliseconds: 950)),
      ),
      isFalse,
    );
  });

  test('the tail is long enough to cover buffered audio', () {
    expect(
      MicEchoGate.tail,
      greaterThanOrEqualTo(const Duration(milliseconds: 800)),
    );
  });

  test('a lesson clip closes the mic for its whole length and the tail', () {
    final g = MicEchoGate();
    g.clipStarted(const Duration(seconds: 2), now: t0);
    for (final ms in [0, 500, 1900, 2000, 2800]) {
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
        now: t0.add(const Duration(milliseconds: 2950)),
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

  test('reset opens the mic again', () {
    final g = MicEchoGate();
    g.clipStarted(const Duration(seconds: 5), now: t0);
    g.reset();
    expect(g.clipBlocks(now: t0.add(const Duration(seconds: 1))), isFalse);
  });
}
