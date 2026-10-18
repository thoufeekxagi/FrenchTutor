import 'dart:convert';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../v3_prefs.dart';
import 'v3_daily_challenge.dart';
import '../lesson/v3_lesson.dart';

/// Loads the signed-in learner's published challenge, with a bundled fallback
/// so the Course screen still opens offline and before the feed is configured.
class V3DailyChallengeRepository {
  const V3DailyChallengeRepository._();

  static final Map<String, int> _savedSteps = {};

  static const assetPath =
      'assets/content/tcf/daily_challenges/a1_clinic_message.json';

  static String dateKey([DateTime? value]) {
    final local = (value ?? DateTime.now()).toLocal();
    return '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }

  static Future<V3DailyChallenge?> load(String level) async {
    const e2eShell = bool.fromEnvironment('E2E_SHELL');
    // E2E uses only the bundled preview so it cannot create real challenge
    // attempts or answer events in the configured Supabase project.
    if (!e2eShell) {
      try {
        final client = Supabase.instance.client;
        if (client.auth.currentSession != null) {
          final response = await client.functions.invoke(
            'daily-challenge',
            body: {
              'action': 'today',
              'level': level.toLowerCase(),
              'local_date': dateKey(),
            },
          );
          final data = (response.data as Map).cast<String, dynamic>();
          final challenge = data['challenge'];
          if (challenge is Map) {
            final raw = (challenge).cast<String, dynamic>();
            raw['attempt'] = data['attempt'];
            return V3DailyChallenge.fromJson(raw, remote: true);
          }
        }
      } catch (_) {
        // The feed is optional during rollout. Use the debug preview below
        // while offline or before a challenge has been published.
      }
    }

    // The bundled clinic package is a development preview until it receives
    // human TCF review. Production only serves approved remote rows.
    if (!kDebugMode || level.toLowerCase() != 'a1') return null;
    final raw = jsonDecode(await rootBundle.loadString(assetPath));
    final challenge = V3DailyChallenge.fromJson(
      (raw as Map).cast<String, dynamic>(),
      remote: false,
    );
    return start(challenge);
  }

  static Future<V3DailyChallenge> start(V3DailyChallenge challenge) async {
    if (challenge.remote) {
      final attemptId = challenge.attemptId;
      if (attemptId != null) {
        await Supabase.instance.client.functions.invoke(
          'daily-challenge',
          body: {'action': 'start', 'attempt_id': attemptId},
        );
      }
      return challenge;
    }
    final prefs = await SharedPreferences.getInstance();
    final key = _progressKey(challenge);
    final currentStep = prefs.getInt('$key.step') ?? 0;
    final completed = prefs.getBool('$key.completed') ?? false;
    return challenge.withProgress(
      currentStep: currentStep,
      completed: completed,
    );
  }

  static Future<V3AnswerFeedback?> checkAnswer(
    V3DailyChallenge challenge,
    String stepId,
    int selectedIndex,
  ) async {
    if (!challenge.remote) return null;
    final attemptId = challenge.attemptId;
    if (attemptId == null) throw StateError('Challenge attempt is missing.');
    final response = await Supabase.instance.client.functions.invoke(
      'daily-challenge',
      body: {
        'action': 'answer',
        'attempt_id': attemptId,
        'step_id': stepId,
        'selected_index': selectedIndex,
      },
    );
    final data = (response.data as Map).cast<String, dynamic>();
    return V3AnswerFeedback(
      correct: data['correct'] == true,
      explanation: data['explanation'] as String? ?? '',
      correctAnswer: data['correct_answer'] as String?,
    );
  }

  static Future<void> saveStep(V3DailyChallenge challenge, int step) async {
    final progressKey = _progressKey(challenge);
    final previouslySaved = _savedSteps[progressKey] ?? 0;
    final highestSaved = previouslySaved > challenge.currentStep
        ? previouslySaved
        : challenge.currentStep;
    // The player can move backwards and revisit a completed step. Keep the
    // backend cursor monotonic so revisiting does not submit duplicate progress.
    if (step <= highestSaved) return;

    if (challenge.remote) {
      final attemptId = challenge.attemptId;
      if (attemptId != null) {
        await Supabase.instance.client.functions.invoke(
          'daily-challenge',
          body: {
            'action': 'progress',
            'attempt_id': attemptId,
            'current_step': step,
          },
        );
        _savedSteps[progressKey] = step;
      }
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('$progressKey.step', step);
    _savedSteps[progressKey] = step;
  }

  static Future<void> complete(V3DailyChallenge challenge) async {
    if (challenge.remote) {
      final attemptId = challenge.attemptId;
      if (attemptId != null) {
        await Supabase.instance.client.functions.invoke(
          'daily-challenge',
          body: {'action': 'complete', 'attempt_id': attemptId},
        );
      }
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final key = _progressKey(challenge);
    await prefs.setBool('$key.completed', true);
    await prefs.setInt('$key.step', challenge.lesson.steps.length - 1);
  }

  static String _progressKey(V3DailyChallenge challenge) =>
      v3Key('daily_${dateKey()}_${challenge.id}');
}
