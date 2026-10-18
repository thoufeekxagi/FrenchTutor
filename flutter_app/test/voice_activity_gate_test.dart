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

const _swing = [9000, 2500, 11000, 1200, 8000, 3000, 10000, 600, 9500, 2000];

/// A frame of "speech": its level swings like syllables, unlike a steady hum.
Uint8List speechFrame(int i, [int scale = 1]) =>
    pcmFrame(_swing[i % _swing.length] ~/ scale);

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
    for (var i = 0; i < 30; i++) {
      final update = gate.add(speechFrame(i));
      if (update.speechStarted) opened = update;
      captured.addAll(update.frames);
    }

    expect(opened, isNotNull);
    expect(captured.length, 30);
    expect(captured.first, speechFrame(0));
    expect(gate.isSpeechActive, isTrue);
  });

  test(
    'forwards the endpoint and closes after the configured natural pause',
    () {
      final gate = VoiceActivityGate();
      for (var i = 0; i < 30; i++) {
        gate.add(speechFrame(i));
      }

      VoiceActivityUpdate? closed;
      var forwardedFinalSilenceFrames = 0;
      for (var i = 0; i < 35; i++) {
        final update = gate.add(pcmFrame(100));
        forwardedFinalSilenceFrames += update.frames.length;
        if (update.speechEnded) closed = update;
      }

      expect(forwardedFinalSilenceFrames, inInclusiveRange(34, 35));
      expect(closed, isNotNull);
      expect(closed!.frames, hasLength(1));
      expect(gate.isSpeechActive, isFalse);
    },
  );

  test('a pause shorter than the endpoint stays within one learner turn', () {
    final gate = VoiceActivityGate();
    for (var i = 0; i < 30; i++) {
      gate.add(speechFrame(i));
    }
    for (var i = 0; i < 20; i++) {
      expect(gate.add(pcmFrame(100)).speechEnded, isFalse);
    }
    expect(gate.isSpeechActive, isTrue);
    final resumed = gate.add(speechFrame(30));
    expect(resumed.speechEnded, isFalse);
    expect(resumed.frames, hasLength(1));
  });

  test('steady chatter behind the learner does not hold the turn open', () {
    final gate = VoiceActivityGate();
    for (var i = 0; i < 30; i++) {
      gate.add(speechFrame(i));
    }
    var ended = false;
    for (var i = 0; i < 60 && !ended; i++) {
      ended = gate.add(pcmFrame(1500)).speechEnded;
    }
    expect(ended, isTrue);
  });

  test('a learner who keeps talking at their own level stays open', () {
    final gate = VoiceActivityGate();
    for (var i = 0; i < 30; i++) {
      gate.add(speechFrame(i));
    }
    for (var i = 0; i < 100; i++) {
      expect(gate.add(speechFrame(i + 30)).speechEnded, isFalse);
    }
  });

  test('a loud steady hum is treated as noise and never opens a turn', () {
    final gate = VoiceActivityGate();
    var started = false;
    for (var i = 0; i < 250; i++) {
      final wobble = 8000 + (i.isEven ? 120 : -120);
      started = gate.add(pcmFrame(wobble)).speechStarted || started;
    }
    expect(started, isFalse);
  });
}
