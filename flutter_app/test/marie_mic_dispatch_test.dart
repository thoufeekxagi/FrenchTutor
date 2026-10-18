import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/services/audio_streaming_service.dart';

// 20 ms of mono PCM16 at 16 kHz, matching the live mic input format.
Uint8List pcmFrame(int sample) {
  final bytes = Uint8List(640);
  final unsigned = sample & 0xffff;
  for (var i = 0; i < bytes.length; i += 2) {
    bytes[i] = unsigned & 0xff;
    bytes[i + 1] = unsigned >> 8;
  }
  return bytes;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('lesson speech gate drops quiet room frames and a short click', () {
    final audio = AudioStreamingService()..speechGateEnabled = true;
    final sent = <List<int>>[];
    for (var i = 0; i < 50; i++) {
      audio.handleMicChunkForTest(pcmFrame(100), sent.add);
    }
    audio.handleMicChunkForTest(pcmFrame(6000), sent.add);
    for (var i = 0; i < 20; i++) {
      audio.handleMicChunkForTest(pcmFrame(100), sent.add);
    }
    expect(sent, isEmpty);
  });

  test('lesson speech gate preserves the start of sustained speech', () {
    final audio = AudioStreamingService()..speechGateEnabled = true;
    final sent = <List<int>>[];
    for (var i = 0; i < 12; i++) {
      audio.handleMicChunkForTest(pcmFrame(6000), sent.add);
    }
    expect(sent, isNotEmpty);
    expect(sent.first, pcmFrame(6000));
    expect(sent.length, greaterThanOrEqualTo(10));
  });

  test('tutor output blocks mic even when local speech gate is enabled', () {
    final audio = AudioStreamingService()
      ..speechGateEnabled = true
      ..allowBargeIn = true
      ..isOutputActive = true;
    final sent = <List<int>>[];
    for (var i = 0; i < 50; i++) {
      audio.handleMicChunkForTest(pcmFrame(6000), sent.add);
    }
    expect(sent, isEmpty);
  });

  test('full-duplex tutor accepts learner interruption during its reply', () {
    final audio = AudioStreamingService()
      ..speechGateEnabled = true
      ..isAwaitingTutorResponse = true
      ..isOutputActive = true;
    final sent = <List<int>>[];
    var speechStarts = 0;
    audio.onSpeechStarted = () => speechStarts++;
    for (var i = 0; i < 12; i++) {
      audio.handleMicChunkForTest(
        pcmFrame(6000),
        sent.add,
        fullDuplexActive: true,
      );
    }
    expect(speechStarts, 1);
    expect(sent, isNotEmpty);
    expect(sent.first, pcmFrame(6000));
  });

  test('replayed French voice is held during playback and heard afterward', () {
    final speech = File(
      'test/fixtures/marie/learner_fr_16k.pcm',
    ).readAsBytesSync();
    final audio = AudioStreamingService()..speechGateEnabled = true;
    final sent = <List<int>>[];
    audio.isOutputActive = true;
    for (var offset = 0; offset < speech.length; offset += 640) {
      final end = (offset + 640).clamp(0, speech.length);
      audio.handleMicChunkForTest(
        Uint8List.sublistView(speech, offset, end),
        sent.add,
      );
    }
    expect(sent, isEmpty, reason: 'no app playback reaches Gemini');

    audio.isOutputActive = false;
    for (var offset = 0; offset < speech.length; offset += 640) {
      final end = (offset + 640).clamp(0, speech.length);
      audio.handleMicChunkForTest(
        Uint8List.sublistView(speech, offset, end),
        sent.add,
      );
    }
    expect(sent, isNotEmpty, reason: 'the learner can speak after playback');
  });
}
