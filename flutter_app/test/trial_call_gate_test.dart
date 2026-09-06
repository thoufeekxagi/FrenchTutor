import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:french_tutor/services/trial_call_gate.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  test('a pre-connect failure releases the one-time trial for retry', () async {
    await TrialCallGate.markStarted();
    expect(await TrialCallGate.isAvailable(), isFalse);

    await TrialCallGate.releaseIfNeverConnected(connected: false);

    expect(await TrialCallGate.isAvailable(), isTrue);
  });

  test('a connected trial stays consumed when release is requested', () async {
    await TrialCallGate.markStarted();
    await TrialCallGate.markConnected();

    await TrialCallGate.releaseIfNeverConnected(connected: true);

    expect(await TrialCallGate.isAvailable(), isFalse);
  });

  test('a stale pre-connect attempt can recover after a force-quit', () async {
    SharedPreferences.setMockInitialValues({
      'trial_call_used_at': DateTime.now()
          .toUtc()
          .subtract(const Duration(minutes: 6))
          .toIso8601String(),
      'trial_call_connected': false,
    });

    expect(await TrialCallGate.isAvailable(), isTrue);
  });
}
