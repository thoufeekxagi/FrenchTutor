import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:french_tutor/services/trial_call_gate.dart';

void main() {
  // NOTE: availability requires an authenticated Supabase session because
  // Gemini Live now uses a short-lived server-minted token. These unit tests
  // run without an initialized Supabase client, so they verify the local gate.
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

  test(
    'trial without an authenticated session is quietly unavailable',
    () async {
      SharedPreferences.setMockInitialValues({});
      // No Supabase session in tests → never offered, never crashes.
      expect(await TrialCallGate.isAvailable(), isFalse);
    },
  );

  test('hard cap and wrap-up lead are sane', () {
    expect(TrialCallGate.maxSeconds, 180);
    expect(TrialCallGate.wrapUpLeadSeconds, lessThan(TrialCallGate.maxSeconds));
  });
}
