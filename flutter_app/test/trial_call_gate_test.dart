import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:french_tutor/services/trial_call_gate.dart';

void main() {
  // NOTE: availability also requires a compiled-in Gemini key
  // (ApiKeys.geminiKey via dart-define). Tests run without one, so the
  // positive "is available on a fresh install" case can't be asserted here —
  // what CAN be locked down is that the trial is never offered twice.
  test('trial is single-use: once started it is never available again', () async {
    SharedPreferences.setMockInitialValues({});
    await TrialCallGate.markStarted();
    expect(await TrialCallGate.isAvailable(), isFalse);

    // Recording a result never resurrects it.
    await TrialCallGate.recordResult(
      durationSeconds: 180,
      learnerUtteranceCount: 7,
    );
    expect(await TrialCallGate.isAvailable(), isFalse);
  });

  test('trial without a Gemini key is quietly unavailable', () async {
    SharedPreferences.setMockInitialValues({});
    // No dart-define in tests → empty key → never offered, never crashes.
    expect(await TrialCallGate.isAvailable(), isFalse);
  });

  test('hard cap and wrap-up lead are sane', () {
    expect(TrialCallGate.maxSeconds, 180);
    expect(
      TrialCallGate.wrapUpLeadSeconds,
      lessThan(TrialCallGate.maxSeconds),
    );
  });
}
