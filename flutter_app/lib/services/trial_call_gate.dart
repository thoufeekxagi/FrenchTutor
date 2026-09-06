import 'package:shared_preferences/shared_preferences.dart';

/// The pre-signup trial call's single source of truth: ONE 3-minute live call
/// with the chosen tutor per install, ever — experienced before any account
/// exists (Readle's "sample story before signup" pattern, adapted to voice).
///
/// Enforcement layers, in order of authority:
///   1. `markStarted()` is written BEFORE the call dials, so force-quitting
///      mid-call can never mint a second full trial.
///   2. The call screen's app-owned timer hard-ends the call at [maxSeconds]
///      (the model is told about the limit but never trusted with it).
///   3. This flag lives in SharedPreferences — device-local by design for the
///      pilot. Server-side attestation (DeviceCheck / Play Integrity behind an
///      edge function that mints ephemeral tokens) is the post-pilot hardening
///      step; the call-site contract here won't change when it lands.
class TrialCallGate {
  TrialCallGate._();

  static const maxSeconds = 180;

  /// Ask the tutor to start wrapping up with this much time left, so the hard
  /// cutoff lands on a goodbye instead of mid-sentence.
  static const wrapUpLeadSeconds = 30;

  static const _usedAtKey = 'trial_call_used_at';
  static const _connectedKey = 'trial_call_connected';
  static const _secondsKey = 'trial_call_seconds';
  static const _utterancesKey = 'trial_call_utterances';
  static const _pendingAttemptGrace = Duration(minutes: 5);

  /// The onboarding trial intentionally runs before account creation. Its
  /// separate Edge Function mints a short-lived, single-use Live token.
  static Future<bool> isAvailable() async {
    final prefs = await SharedPreferences.getInstance();
    final usedAt = prefs.getString(_usedAtKey);
    if (usedAt == null) return true;
    // A force-quit can happen after the gate is burned but before the socket
    // connects. Keep that attempt reserved briefly, then make it retryable if
    // it never reported a connection. A connected call stays consumed even if
    // the process dies before its recap is written.
    final connected = prefs.getBool(_connectedKey) ?? false;
    if (!connected) {
      final started = DateTime.tryParse(usedAt);
      if (started != null &&
          DateTime.now().toUtc().difference(started.toUtc()) >
              _pendingAttemptGrace) {
        await releaseIfNeverConnected(connected: false);
        return true;
      }
    }
    return false;
  }

  /// Burn the trial. Called immediately before dialing.
  static Future<void> markStarted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_usedAtKey, DateTime.now().toIso8601String());
    await prefs.setBool(_connectedKey, false);
  }

  /// Marks the point at which the learner actually received a live tutor.
  /// This lets the next app launch distinguish an interrupted dial from a
  /// consumed call without trusting an in-memory flag.
  static Future<void> markConnected() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_connectedKey, true);
  }

  /// What actually happened, for the recap screen and pilot telemetry.
  static Future<void> recordResult({
    required int durationSeconds,
    required int learnerUtteranceCount,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_secondsKey, durationSeconds);
    await prefs.setInt(_utterancesKey, learnerUtteranceCount);
  }

  /// A token request or a cancelled dial can fail before Gemini ever connects.
  /// In that case the learner has not consumed the experience and should be
  /// allowed to retry, especially after a temporary network failure. Once a
  /// call connected, callers must not invoke this method.
  static Future<void> releaseIfNeverConnected({required bool connected}) async {
    final prefs = await SharedPreferences.getInstance();
    // The persisted marker is authoritative when a route closes without
    // returning its result (for example, an interrupted navigation).
    if (connected || (prefs.getBool(_connectedKey) ?? false)) return;
    await prefs.remove(_usedAtKey);
    await prefs.remove(_connectedKey);
    await prefs.remove(_secondsKey);
    await prefs.remove(_utterancesKey);
  }
}
