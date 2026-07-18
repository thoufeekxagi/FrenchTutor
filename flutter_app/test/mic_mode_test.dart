import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:french_tutor/services/mic_mode.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late int starts;
  late int stops;
  late List<List<int>> sent;
  late MicController mic;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    starts = 0;
    stops = 0;
    sent = [];
    mic = MicController(
      startStream: () async => starts += 1,
      stopStream: () async => stops += 1,
      sendAudio: sent.add,
    );
  });

  group('auto mode', () {
    test('onConnected opens the mic', () async {
      await mic.onConnected();
      expect(starts, 1);
    });

    test('muted onConnected keeps the mic closed', () async {
      await mic.setMuted(true);
      await mic.onConnected();
      expect(starts, 0);
    });

    test('mute toggles the stream', () async {
      await mic.onConnected();
      await mic.setMuted(true);
      expect(stops, 1);
      await mic.setMuted(false);
      expect(starts, 2);
    });

    test('background stops, resume restarts (unless muted)', () async {
      await mic.onConnected();
      await mic.onAppPaused();
      expect(stops, 1);
      await mic.onAppResumed();
      expect(starts, 2);
      await mic.setMuted(true);
      await mic.onAppPaused();
      await mic.onAppResumed();
      expect(starts, 2, reason: 'muted resume must not reopen the mic');
    });
  });

  group('push-to-talk mode', () {
    test('onConnected keeps the mic closed', () async {
      mic.adoptSavedMode(MicMode.pushToTalk);
      await mic.onConnected();
      expect(starts, 0);
    });

    test('switching to PTT mid-call closes the open mic', () async {
      await mic.onConnected();
      expect(starts, 1);
      await mic.setMode(MicMode.pushToTalk);
      expect(stops, 1);
    });

    test('switching back to auto reopens the mic', () async {
      await mic.onConnected();
      await mic.setMode(MicMode.pushToTalk);
      await mic.setMode(MicMode.auto);
      expect(starts, 2);
    });

    test('hold streams, release stops and closes the turn with silence', () async {
      mic.adoptSavedMode(MicMode.pushToTalk);
      await mic.onConnected();
      await mic.pttDown();
      expect(starts, 1);
      expect(mic.isHeld, isTrue);
      await mic.pttUp();
      expect(stops, 1);
      expect(mic.isHeld, isFalse);
      expect(sent.length, MicController.silenceTailChunks);
      expect(sent.first.length, MicController.silenceChunkBytes);
      expect(sent.first.every((b) => b == 0), isTrue);
      // > 2.5s of audio so the server VAD reliably sees end-of-speech.
      final seconds =
          sent.length * MicController.silenceChunkBytes / 2 / 16000;
      expect(seconds, greaterThan(2.5));
    });

    test('release without hold is a no-op', () async {
      mic.adoptSavedMode(MicMode.pushToTalk);
      await mic.onConnected();
      await mic.pttUp();
      expect(stops, 0);
      expect(sent, isEmpty);
    });

    test('double press does not double-start', () async {
      mic.adoptSavedMode(MicMode.pushToTalk);
      await mic.onConnected();
      await mic.pttDown();
      await mic.pttDown();
      expect(starts, 1);
    });

    test('hold before connection is ignored', () async {
      mic.adoptSavedMode(MicMode.pushToTalk);
      await mic.pttDown();
      expect(starts, 0);
      expect(mic.isHeld, isFalse);
    });

    test('backgrounding mid-hold releases and stops', () async {
      mic.adoptSavedMode(MicMode.pushToTalk);
      await mic.onConnected();
      await mic.pttDown();
      await mic.onAppPaused();
      expect(mic.isHeld, isFalse);
      expect(stops, 1);
      // Resume in PTT: mic stays closed until the next hold.
      await mic.onAppResumed();
      expect(starts, 1);
    });
  });

  group('persistence', () {
    test('mode round-trips through prefs', () async {
      await MicModePrefs.save(MicMode.pushToTalk);
      expect(await MicModePrefs.load(), MicMode.pushToTalk);
      await MicModePrefs.save(MicMode.auto);
      expect(await MicModePrefs.load(), MicMode.auto);
    });

    test('setMode persists the choice', () async {
      await mic.setMode(MicMode.pushToTalk);
      expect(await MicModePrefs.load(), MicMode.pushToTalk);
    });
  });
}
