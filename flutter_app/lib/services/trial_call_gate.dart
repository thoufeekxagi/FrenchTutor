import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_keys.dart';

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
  static const _secondsKey = 'trial_call_seconds';
  static const _utterancesKey = 'trial_call_utterances';

  /// Trial is offered when it has never been started on this install and the
  /// build actually carries a Gemini key (dev builds without one skip quietly).
  static Future<bool> isAvailable() async {
    if (ApiKeys.geminiKey.isEmpty) return false;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_usedAtKey) == null;
  }

  /// Burn the trial. Called immediately before dialing.
  static Future<void> markStarted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_usedAtKey, DateTime.now().toIso8601String());
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
}
