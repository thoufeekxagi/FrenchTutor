import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:french_tutor/services/auth_service.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://test.supabase.co',
      publishableKey: 'sb_publishable_test_key',
    );
  });

  group('AuthService.isGoogleConfigured', () {
    test('is false with empty dart-define client IDs (the test default)', () {
      // ApiKeys.googleIosClientId / googleWebClientId are compiled from
      // dart-defines, both empty in a plain `flutter test` run — this pins
      // the graceful-degradation contract: no crash, just "not configured".
      expect(AuthService.shared.isGoogleConfigured, isFalse);
    });
  });

  group('AuthService.signInWithGoogle unconfigured path', () {
    test('returns a friendly failure instead of attempting native sign-in', () async {
      final result = await AuthService.shared.signInWithGoogle();
      expect(result.outcome, AuthOutcome.failure);
      expect(result.message, contains('set up yet'));
    });
  });

  group('AuthService session/state surface', () {
    test('currentSession is null with no prior sign-in', () {
      expect(AuthService.shared.currentSession, isNull);
    });

    test('onAuthStateChange is a broadcast stream safe to listen to twice', () {
      final sub1 = AuthService.shared.onAuthStateChange.listen((_) {});
      final sub2 = AuthService.shared.onAuthStateChange.listen((_) {});
      sub1.cancel();
      sub2.cancel();
    });
  });

  group('AuthResult', () {
    test('constant instances carry no message', () {
      expect(AuthResult.success.message, isNull);
      expect(AuthResult.cancelled.message, isNull);
      expect(AuthResult.needsEmailConfirmation.message, isNull);
    });

    test('failure carries the given message', () {
      final result = AuthResult.failure('nope');
      expect(result.outcome, AuthOutcome.failure);
      expect(result.message, 'nope');
    });
  });

  group('email/password validation surfaces Supabase errors, never throws', () {
    test('signInWithEmail with garbage credentials fails gracefully', () async {
      // Real network call to the fake test project — Supabase's SDK itself
      // will reject the malformed URL/host at the HTTP layer; the important
      // contract is that AuthService catches it and returns AuthOutcome.failure
      // rather than letting an exception escape to the caller.
      final result = await AuthService.shared.signInWithEmail(
        email: 'not-a-real-account@example.com',
        password: 'wrong-password',
      );
      expect(result.outcome, AuthOutcome.failure);
      expect(result.message, isNotNull);
    });
  });
}
