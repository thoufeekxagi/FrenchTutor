import 'dart:math' as math;
import 'dart:typed_data';

import 'package:french_tutor/services/audio_streaming_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:permission_handler/permission_handler.dart';

Uint8List tone24Khz({
  Duration duration = const Duration(milliseconds: 700),
  int sampleRate = 24000,
}) {
  final samples = duration.inMicroseconds * sampleRate ~/ 1000000;
  final pcm = Uint8List(samples * 2);
  for (var i = 0; i < samples; i++) {
    final envelope = math.min(1.0, math.min(i / 2400, (samples - i) / 2400));
    final sample =
        (math.sin(2 * math.pi * 440 * i / sampleRate) * 4500 * envelope)
            .round();
    pcm[i * 2] = sample & 0xff;
    pcm[i * 2 + 1] = (sample >> 8) & 0xff;
  }
  return pcm;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('iPhone voice processing captures during shared-engine playback', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final permission = await Permission.microphone.request();
      expect(permission.isGranted, isTrue);

      final audio = AudioStreamingService()
        ..preferFullDuplexVoiceProcessing = true
        ..isAwaitingTutorResponse = true;
      final frames = <List<int>>[];
      try {
        await audio.startStreaming(onChunk: frames.add);
        expect(
          audio.fullDuplexActive,
          isTrue,
          reason: 'the phone must enable native voice processing',
        );
        await Future<void>.delayed(const Duration(seconds: 1));
        expect(
          frames,
          isNotEmpty,
          reason: 'the processed mic must stream during a tutor response',
        );
        expect(frames.every((frame) => frame.length == 640), isTrue);

        final beforePlayback = frames.length;
        await audio.playAudioChunk(tone24Khz(), waitForFeed: true);
        await Future<void>.delayed(const Duration(milliseconds: 300));
        expect(
          frames.length,
          greaterThan(beforePlayback),
          reason:
              'capture must stay live while tutor PCM plays and a reply is pending',
        );
        await audio.stopPlayback();

        await audio.stopStreaming();
        final afterMute = frames.length;
        await Future<void>.delayed(const Duration(milliseconds: 120));
        expect(frames.length, lessThanOrEqualTo(afterMute + 1));
      } finally {
        await audio.dispose();
      }
    });
  });
}
