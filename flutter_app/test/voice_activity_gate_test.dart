import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/services/voice_activity_gate.dart';

Uint8List pcmFrame(int sample) {
  final bytes = Uint8List(640); // 20ms at 16kHz mono PCM16.
  final value = sample & 0xffff;
  for (var i = 0; i < bytes.length; i += 2) {
    bytes[i] = value & 0xff;
    bytes[i + 1] = value >> 8;
  }
  return bytes;
}

void main() {
  test('drops silence instead of sending it to the billable Live stream', () {
    final gate = VoiceActivityGate();
    for (var i = 0; i < 150; i++) {
      expect(gate.add(pcmFrame(100)).frames, isEmpty);
    }
    expect(gate.isSpeechActive, isFalse);
  });

  test('a brief click cannot open a speech turn', () {
    final gate = VoiceActivityGate();
    final click = gate.add(pcmFrame(12000));
    expect(click.speechStarted, isFalse);
    for (var i = 0; i < 15; i++) {
      expect(gate.add(pcmFrame(100)).frames, isEmpty);
    }
    expect(gate.isSpeechActive, isFalse);
  });

  test('opens after sustained speech and preserves the first syllable', () {
    final gate = VoiceActivityGate();
    final captured = <Uint8List>[];
    VoiceActivityUpdate? opened;
    for (var i = 0; i < 12; i++) {
      final update = gate.add(pcmFrame(6000));
      if (update.speechStarted) opened = update;
      captured.addAll(update.frames);
    }

    expect(opened, isNotNull);
    expect(captured.length, 12);
    expect(captured.first, pcmFrame(6000));
    expect(gate.isSpeechActive, isTrue);
  });

  test(
    'forwards the endpoint and closes after the configured natural pause',
    () {
      final gate = VoiceActivityGate();
      for (var i = 0; i < 12; i++) {
        gate.add(pcmFrame(6000));
      }

      VoiceActivityUpdate? closed;
      var forwardedFinalSilenceFrames = 0;
      for (var i = 0; i < 35; i++) {
        final update = gate.add(pcmFrame(100));
        forwardedFinalSilenceFrames += update.frames.length;
        if (update.speechEnded) closed = update;
      }

      expect(forwardedFinalSilenceFrames, 35);
      expect(closed, isNotNull);
      expect(closed!.frames, hasLength(1));
      expect(gate.isSpeechActive, isFalse);
    },
  );

  test('a pause shorter than the endpoint stays within one learner turn', () {
    final gate = VoiceActivityGate();
    for (var i = 0; i < 12; i++) {
      gate.add(pcmFrame(6000));
    }
    for (var i = 0; i < 20; i++) {
      expect(gate.add(pcmFrame(100)).speechEnded, isFalse);
    }
    expect(gate.isSpeechActive, isTrue);
    final resumed = gate.add(pcmFrame(6000));
    expect(resumed.speechEnded, isFalse);
    expect(resumed.frames, hasLength(1));
  });
}
