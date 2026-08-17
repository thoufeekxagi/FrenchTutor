import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import '../lib/services/tutor_lip_sync_controller.dart';

void main() {
  test('silence keeps the tutor mouth closed', () {
    final controller = TutorLipSyncController();
    addTearDown(controller.dispose);

    controller.pushPcm16(List<int>.filled(4800, 0));

    expect(controller.frame.viseme, TutorViseme.closed);
    expect(controller.frame.mouthOpen, lessThan(0.06));
  });

  test('voiced PCM produces an audio-driven mouth frame', () {
    final controller = TutorLipSyncController();
    addTearDown(controller.dispose);

    final bytes = <int>[];
    for (var sample = 0; sample < 2400; sample++) {
      final value =
          (math.sin(sample * 2 * math.pi * 220 / 24000) * 0.18 * 32767).round();
      final unsigned = value < 0 ? value + 0x10000 : value;
      bytes
        ..add(unsigned & 0xff)
        ..add((unsigned >> 8) & 0xff);
    }

    controller.pushPcm16(bytes);

    expect(controller.frame.energy, greaterThan(0.1));
    expect(controller.frame.mouthOpen, greaterThan(0.06));
    expect(controller.frame.viseme, isNot(TutorViseme.closed));
  });
}
