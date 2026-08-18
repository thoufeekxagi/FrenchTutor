import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:french_tutor/services/trial_call_gate.dart';

void main() {
  // The onboarding trial is pre-signup; the separate Edge Function mints its
  // short-lived token. These tests verify the local single-use gate.
  test(
    'trial is single-use: once started it is never available again',
    () async {
      SharedPreferences.setMockInitialValues({});
      await TrialCallGate.markStarted();
      expect(await TrialCallGate.isAvailable(), isFalse);

      // Recording a result never resurrects it.
      await TrialCallGate.recordResult(
        durationSeconds: 180,
        learnerUtteranceCount: 7,
      );
      expect(await TrialCallGate.isAvailable(), isFalse);
    },
  );

  test('hard cap and wrap-up lead are sane', () {
    expect(TrialCallGate.maxSeconds, 180);
    expect(TrialCallGate.wrapUpLeadSeconds, lessThan(TrialCallGate.maxSeconds));
  });
}
