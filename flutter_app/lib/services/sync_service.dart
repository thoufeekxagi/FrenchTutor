import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqlite3/common.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/database/pilot_infrastructure_store.dart';
import '../models/content_models.dart';
import '../models/daily_session.dart';
import '../models/profile.dart';
import '../models/srs_state.dart';
import '../orchestration/models/competency_state.dart';
import '../orchestration/models/error_event.dart';
import '../orchestration/models/evidence_event.dart';
import '../orchestration/models/learning_plan.dart';
import '../orchestration/models/task_result.dart';

/// The single gateway between local SQLite and Supabase.
///
/// Supabase is the source of truth for every signed-in learner — vocab
/// state, session progress, and the orchestration/competency model that
/// carries a learner's "personality" (mastery, mistakes, phrasing history)
/// across devices and reinstalls. Local SQLite stays as a read cache and
/// write buffer so the app is instant and still works with no signal.
///
/// Every push method here is best-effort and never throws to its caller: a
/// network failure queues the mutation in `sync_outbox`
/// (PilotInfrastructureStore) for [drainOutbox] to retry later, and the
/// local write the caller already made is the one the UI reflects
/// immediately either way.
class SyncService {
  SyncService(this._db);

  final CommonDatabase _db;

  SupabaseClient get _client => Supabase.instance.client;
  String? get _userId => _client.auth.currentUser?.id;
  bool get isSignedIn => _userId != null;

  PilotInfrastructureStore get _outbox => PilotInfrastructureStore(_db);

  Future<void> _guarded(
    Future<void> Function(String userId) body, {
    String? queueTable,
    String? queueRowId,
  }) async {
    final uid = _userId;
    if (uid == null) return; // Not signed in yet — local-only, nothing to push.
    try {
      await body(uid);
    } catch (e, st) {
      debugPrint('SyncService push failed ($queueTable/$queueRowId): $e\n$st');
      if (queueTable != null && queueRowId != null) {
        try {
          _outbox.queueMutation(
            tableName: queueTable,
            rowId: queueRowId,
            operation: 'upsert',
          );
        } catch (_) {
          // Outbox insert itself failing means the local DB is in trouble —
          // nothing more this layer can safely do.
        }
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Profile
  // ---------------------------------------------------------------------------

  Future<void> syncProfile(Profile p) => _guarded((uid) async {
    await _client.from('profiles').update({
      'goal': p.goal,
      'level': p.level,
      'session_length': p.sessionLength,
      'reminder_time': p.reminderTime,
      'onboarded_at': p.onboardedAt?.toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', uid);
  }, queueTable: 'profiles', queueRowId: p.id);

  // ---------------------------------------------------------------------------
  // Vocab / SRS
  // ---------------------------------------------------------------------------

  Future<void> syncVocabCard(SRSState s) => _guarded((uid) async {
    await _client.from('vocab_card_state').upsert({
      'user_id': uid,
      'entry_id': s.entryId,
      'ease': s.ease,
      'interval_days': s.intervalDays,
      'reps': s.reps,
      'due_at': s.dueAt?.toUtc().toIso8601String(),
      'introduced_on': s.introducedOn,
      'last_reviewed_at': s.lastReviewedAt?.toUtc().toIso8601String(),
      'last_grade': s.lastGrade?.name,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'user_id,entry_id');
  }, queueTable: 'vocab_cards', queueRowId: s.entryId);

  Future<void> logVocabReview({
    required String reviewId,
    required String entryId,
    required String grade,
    required String responseType,
    String? sessionId,
    required DateTime reviewedAt,
  }) => _guarded((uid) async {
    await _client.from('learner_events').insert({
      'user_id': uid,
      'event_type': 'vocab_review',
      'payload': {
        'id': reviewId,
        'entry_id': entryId,
        'grade': grade,
        'response_type': responseType,
        'session_id': sessionId,
      },
      'occurred_at': reviewedAt.toUtc().toIso8601String(),
    });
  }, queueTable: 'vocab_reviews', queueRowId: reviewId);

  // ---------------------------------------------------------------------------
  // Daily Path / AI sessions / credit
  // ---------------------------------------------------------------------------

  Future<void> syncDailySession(DailySession session) => _guarded((uid) async {
    // The table's real uniqueness constraint is (user_id, local_date), not
    // just `id` — a new local DailySession row (a fresh client-generated id,
    // e.g. when the rotation planner regenerates today's plan) for a date
    // that already has a synced row was hitting that constraint as a 23505
    // conflict instead of updating it, since upsert() only dedupes against
    // the column set you give it (the primary key, `id`, by default).
    await _client
        .from('daily_session_state')
        .upsert({
          'id': session.id,
          'user_id': uid,
          'local_date': session.localDate,
          'planned_length': session.plannedLength,
          'current_stage': session.currentStage?.name,
          'current_item_index': session.currentItemIndex,
          'stages_json': session.stagesToJson(),
          'vocab_entry_ids_json': session.vocabEntryIds,
          'grammar_lesson_id': session.grammarLessonId,
          'reading_passage_json': session.readingPassageJson,
          'started_at': session.startedAt?.toUtc().toIso8601String(),
          'completed_at': session.completedAt?.toUtc().toIso8601String(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }, onConflict: 'user_id,local_date');
  }, queueTable: 'daily_sessions', queueRowId: session.id);

  // ---------------------------------------------------------------------------
  // Generated story library
  // ---------------------------------------------------------------------------

  Future<void> syncGeneratedStory(GeneratedStory story) => _guarded((uid) async {
    await _client.from('generated_stories').upsert({
      'id': story.id,
      'user_id': uid,
      'title': story.title,
      'passage_json': story.passage.toJson(),
      'quiz_json': story.quiz.map((q) => q.toJson()).toList(),
      'keywords_json': story.keywords.map((k) => k.toJson()).toList(),
      'created_at': story.createdAt.toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }, queueTable: 'generated_stories', queueRowId: story.id);

  // ---------------------------------------------------------------------------
  // Generated roleplay library
  // ---------------------------------------------------------------------------

  Future<void> syncGeneratedRoleplay(GeneratedRoleplay roleplay) =>
      _guarded((uid) async {
        await _client.from('generated_roleplays').upsert({
          'id': roleplay.id,
          'user_id': uid,
          'title': roleplay.title,
          'passage_json': roleplay.passage.toJson(),
          'created_at': roleplay.createdAt.toUtc().toIso8601String(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        });
      }, queueTable: 'generated_roleplays', queueRowId: roleplay.id);

  Future<void> syncAiSessionStart({
    required String id,
    String? dailySessionId,
    String? stage,
    String? topic,
    required DateTime connectedAt,
  }) => _guarded((uid) async {
    await _client.from('ai_session_state').upsert({
      'id': id,
      'user_id': uid,
      'daily_session_id': dailySessionId,
      'stage': stage,
      'topic': topic,
      'connected_at': connectedAt.toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }, queueTable: 'ai_sessions', queueRowId: id);

  Future<void> syncAiSessionEnd({
    required String id,
    required DateTime endedAt,
    required String endedReason,
    required int learnerUtteranceCount,
    String? transcriptJson,
  }) => _guarded((uid) async {
    await _client
        .from('ai_session_state')
        .update({
          'ended_at': endedAt.toUtc().toIso8601String(),
          'ended_reason': endedReason,
          'learner_utterance_count': learnerUtteranceCount,
          if (transcriptJson != null) 'transcript_json': transcriptJson,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', id);
  }, queueTable: 'ai_sessions', queueRowId: id);

  Future<void> addCreditUsage({
    required String localDate,
    required int secondsUsed,
  }) => _guarded((uid) async {
    final existing = await _client
        .from('credit_usage_state')
        .select('seconds_used')
        .eq('user_id', uid)
        .eq('local_date', localDate)
        .maybeSingle();
    final total = (existing?['seconds_used'] as int? ?? 0) + secondsUsed;
    await _client.from('credit_usage_state').upsert({
      'user_id': uid,
      'local_date': localDate,
      'seconds_used': total,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'user_id,local_date');
  }, queueTable: 'credit_usage', queueRowId: '$localDate:$secondsUsed');

  // ---------------------------------------------------------------------------
  // Lesson progress / habits / writing / mistakes / diary — the smaller
  // secondary-loop data, all funneled through learner_events where they're
  // pure logs, or a small state table where they're mutable.
  // ---------------------------------------------------------------------------

  Future<void> syncLessonStatus(
    String lessonId,
    String status, {
    double? score,
  }) => _guarded((uid) async {
    await _client.from('lesson_progress_state').upsert({
      'user_id': uid,
      'lesson_id': lessonId,
      'status': status,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'user_id,lesson_id');
  }, queueTable: 'lesson_progress', queueRowId: lessonId);

  Future<void> logHabit({
    required String habitId,
    required bool done,
    required int minutes,
    required String date,
  }) => _guarded((uid) async {
    await _client.from('learner_events').insert({
      'user_id': uid,
      'event_type': 'habit_marked',
      'payload': {'habit_id': habitId, 'done': done, 'minutes': minutes},
      'occurred_at': DateTime.now().toUtc().toIso8601String(),
    });
  }, queueTable: 'operational_events', queueRowId: '$date:$habitId');

  Future<void> logWritingSubmission({
    required String taskId,
    required String text,
    required String feedback,
  }) => _guarded((uid) async {
    await _client.from('learner_events').insert({
      'user_id': uid,
      'event_type': 'writing_submission',
      'payload': {'task_id': taskId, 'text': text, 'feedback': feedback},
      'occurred_at': DateTime.now().toUtc().toIso8601String(),
    });
  }, queueTable: 'operational_events', queueRowId: '$taskId:${DateTime.now().microsecondsSinceEpoch}');

  Future<void> logMistake({
    required String tag,
    required String description,
  }) => _guarded((uid) async {
    final existing = await _client
        .from('mistake_tag_state')
        .select('occurrences')
        .eq('user_id', uid)
        .eq('tag', tag)
        .maybeSingle();
    await _client.from('mistake_tag_state').upsert({
      'user_id': uid,
      'tag': tag,
      'occurrences': (existing?['occurrences'] as int? ?? 0) + 1,
      'resolved': false,
      'last_seen_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'user_id,tag');
  }, queueTable: 'mistake_tags', queueRowId: tag);

  Future<void> resolveMistakeTag(String tag) => _guarded((uid) async {
    await _client
        .from('mistake_tag_state')
        .update({'resolved': true})
        .eq('user_id', uid)
        .eq('tag', tag);
  }, queueTable: 'mistake_tags', queueRowId: tag);

  Future<void> logDiaryEntry({
    required String stage,
    required String summary,
  }) => _guarded((uid) async {
    await _client.from('learner_events').insert({
      'user_id': uid,
      'event_type': 'diary_entry',
      'payload': {'stage': stage, 'summary': summary},
      'occurred_at': DateTime.now().toUtc().toIso8601String(),
    });
  }, queueTable: 'operational_events', queueRowId: '$stage:${DateTime.now().microsecondsSinceEpoch}');

  // ---------------------------------------------------------------------------
  // Orchestration state — the learner model ("personality"), evidence/error
  // ledger, and mission plans. This is the state the user specifically asked
  // to make resync correctly.
  // ---------------------------------------------------------------------------

  Future<void> logEvidence(EvidenceEvent event) => _guarded((uid) async {
    await _client.from('learner_events').insert({
      'user_id': uid,
      'event_type': 'evidence_event',
      'payload': {
        'id': event.id,
        'plan_id': event.planId,
        'plan_task_id': event.planTaskId,
        'session_id': event.sessionId,
        'content_item_id': event.contentItemId,
        'competency_id': event.competencyId,
        'modality': event.modality.wireName,
        'support_level': event.supportLevel.wireName,
        'correctness': event.correctness,
        'score': event.score,
        'response_time_ms': event.responseTimeMs,
        'attempt_number': event.attemptNumber,
        'evaluator': event.evaluator.wireName,
        'evaluator_confidence': event.evaluatorConfidence,
        'response': event.response,
        'error_codes': event.errorCodes,
      },
      'occurred_at': event.occurredAt.toUtc().toIso8601String(),
    });
  }, queueTable: 'evidence_events', queueRowId: event.id);

  Future<void> logError(ErrorEvent event) => _guarded((uid) async {
    await _client.from('learner_events').insert({
      'user_id': uid,
      'event_type': 'error_event',
      'payload': {
        'id': event.id,
        'competency_id': event.competencyId,
        'source_evidence_id': event.sourceEvidenceId,
        'error_code': event.errorCode,
        'observed_form': event.observedForm,
        'expected_form': event.expectedForm,
        'explanation': event.explanation,
        'severity': event.severity,
        'evaluator': event.evaluator.wireName,
        'evaluator_confidence': event.evaluatorConfidence,
        'resolved_by_evidence_id': event.resolvedByEvidenceId,
      },
      'occurred_at': event.occurredAt.toUtc().toIso8601String(),
    });
  }, queueTable: 'error_events', queueRowId: event.id);

  Future<void> logTaskResult(TaskResult result) async {
    for (final e in result.competencyEvidence) {
      await logEvidence(e);
    }
    for (final e in result.errors) {
      await logError(e);
    }
  }

  /// Replaces the whole learner_competency_state cache for this user —
  /// mirrors CompetencyStateStore.replaceAll's "rebuilt from evidence, never
  /// hand-edited" contract.
  Future<void> syncCompetencyStates(List<CompetencyState> states) =>
      _guarded((uid) async {
        await _client
            .from('learner_competency_state')
            .delete()
            .eq('user_id', uid);
        if (states.isEmpty) return;
        await _client
            .from('learner_competency_state')
            .insert(
              states
                  .map(
                    (s) => {
                      'user_id': uid,
                      'competency_id': s.competencyId,
                      'modality': s.modality.wireName,
                      'mastery_estimate': s.masteryEstimate,
                      'confidence': s.confidence,
                      'retention_strength': s.retentionStrength,
                      'evidence_count': s.evidenceCount,
                      'transfer_status': s.transferStatus.wireName,
                      'last_observed_at': s.lastObservedAt
                          ?.toUtc()
                          .toIso8601String(),
                      'last_success_at': s.lastSuccessAt
                          ?.toUtc()
                          .toIso8601String(),
                      'next_review_at': s.nextReviewAt
                          ?.toUtc()
                          .toIso8601String(),
                      'learner_model_type': s.learnerModelType,
                      'model_version': s.modelVersion,
                      'model_state_json': s.modelState,
                      'updated_at': DateTime.now().toUtc().toIso8601String(),
                    },
                  )
                  .toList(),
            );
      }, queueTable: 'learner_competency_states', queueRowId: _userId ?? 'unknown');

  Future<void> syncPlan(PlanSnapshot plan) => _guarded((uid) async {
    await _client.from('learning_plan_state').upsert({
      'id': plan.id,
      'user_id': uid,
      'local_date': plan.localDate,
      'available_minutes': plan.availableMinutes,
      'environment_json': plan.environment,
      'primary_priority': plan.primaryPriority,
      'explanation': plan.explanation,
      'planner_version': plan.plannerVersion,
      'input_snapshot_json': plan.inputSnapshot,
      'status': plan.status.name,
      'replaces_plan_id': plan.replacesPlanId,
      'replan_reason': plan.replanReason,
      'started_at': plan.startedAt?.toUtc().toIso8601String(),
      'completed_at': plan.completedAt?.toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    if (plan.tasks.isNotEmpty) {
      await _client
          .from('plan_task_state')
          .upsert(
            plan.tasks
                .map(
                  (t) => {
                    'id': t.id,
                    'user_id': uid,
                    'plan_id': t.planId,
                    'sequence': t.sequence,
                    'content_item_id': t.contentItemId,
                    'requirement': t.requirement.name,
                    'modality': t.modality.wireName,
                    'estimated_minutes': t.estimatedMinutes,
                    'reason_code': t.reasonCode.wireName,
                    'reason_detail_json': t.reasonDetail,
                    'target_competency_ids_json': t.targetCompetencyIds,
                    'status': t.status.name,
                    'started_at': t.startedAt?.toUtc().toIso8601String(),
                    'completed_at': t.completedAt?.toUtc().toIso8601String(),
                    'result_summary_json': t.resultSummary,
                    'updated_at': DateTime.now().toUtc().toIso8601String(),
                  },
                )
                .toList(),
          );
    }
  }, queueTable: 'learning_plans', queueRowId: plan.id);

  Future<void> markPlanReplaced(String planId) =>
      updatePlanStatus(planId: planId, status: 'replaced');

  Future<void> updatePlanStatus({
    required String planId,
    required String status,
    DateTime? completedAt,
  }) => _guarded((uid) async {
    await _client
        .from('learning_plan_state')
        .update({
          'status': status,
          if (completedAt != null)
            'completed_at': completedAt.toUtc().toIso8601String(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', planId);
  }, queueTable: 'learning_plans', queueRowId: planId);

  Future<void> syncPlanTask({
    required String taskId,
    required String status,
    DateTime? startedAt,
    DateTime? completedAt,
    Map<String, Object?>? resultSummary,
  }) => _guarded((uid) async {
    await _client
        .from('plan_task_state')
        .update({
          'status': status,
          if (startedAt != null)
            'started_at': startedAt.toUtc().toIso8601String(),
          if (completedAt != null)
            'completed_at': completedAt.toUtc().toIso8601String(),
          if (resultSummary != null) 'result_summary_json': resultSummary,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', taskId);
  }, queueTable: 'plan_tasks', queueRowId: taskId);

  // ---------------------------------------------------------------------------
  // Outbox drain — call on app resume / connectivity restored. Re-attempts
  // each queued mutation by re-reading the CURRENT local row (so a retry
  // always pushes the latest state, not a stale snapshot) and marks it
  // processed only once the push actually succeeds.
  // ---------------------------------------------------------------------------

  Future<void> drainOutbox({int limit = 50}) async {
    if (!isSignedIn) return;
    final pending = _outbox.pendingMutations(limit: limit);
    for (final mutation in pending) {
      final ok = await _retryOne(mutation.tableName, mutation.rowId);
      if (ok) {
        _db.execute(
          'UPDATE sync_outbox SET processed_at = ? WHERE id = ?',
          [DateTime.now().toUtc().toIso8601String(), mutation.id],
        );
      } else {
        _db.execute(
          'UPDATE sync_outbox SET attempt_count = attempt_count + 1, updated_at = ? WHERE id = ?',
          [DateTime.now().toUtc().toIso8601String(), mutation.id],
        );
      }
    }
  }

  Future<bool> _retryOne(String tableName, String rowId) async {
    try {
      switch (tableName) {
        case 'vocab_cards':
          final rows = _db.select(
            'SELECT * FROM vocab_cards WHERE entry_id = ? AND deleted_at IS NULL',
            [rowId],
          );
          if (rows.isEmpty) return true; // Row gone locally — nothing to push.
          final r = rows.first;
          await syncVocabCard(
            SRSState(
              entryId: r['entry_id'] as String,
              ease: (r['ease'] as num).toDouble(),
              intervalDays: (r['interval_days'] as num).toDouble(),
              reps: r['reps'] as int,
              dueAt: r['due_at'] != null
                  ? DateTime.tryParse(r['due_at'] as String)
                  : null,
              introducedOn: r['introduced_on'] as String?,
              lastReviewedAt: r['last_reviewed_at'] != null
                  ? DateTime.tryParse(r['last_reviewed_at'] as String)
                  : null,
              lastGrade: SRSGrade.values
                  .asNameMap()[r['last_grade'] as String?],
            ),
          );
          return true;
        case 'daily_sessions':
          final rows = _db.select(
            'SELECT * FROM daily_sessions WHERE id = ? AND deleted_at IS NULL',
            [rowId],
          );
          if (rows.isEmpty) return true;
          await syncDailySession(_dailySessionFromRow(rows.first));
          return true;
        default:
          // Not yet retryable generically — leave queued rather than drop it.
          return false;
      }
    } catch (_) {
      return false;
    }
  }

  DailySession _dailySessionFromRow(Row row) {
    DateTime? parseDate(Object? raw) =>
        raw is String && raw.isNotEmpty ? DateTime.tryParse(raw) : null;
    return DailySession(
      id: row['id'] as String,
      localDate: row['local_date'] as String,
      plannedLength: row['planned_length'] as String,
      currentStage: PathwayStage.values
          .asNameMap()[row['current_stage'] as String?],
      currentItemIndex: row['current_item_index'] as int,
      stages: DailySession.stagesFromJson(row['stages_json'] as String),
      startedAt: parseDate(row['started_at']),
      completedAt: parseDate(row['completed_at']),
    );
  }

  // ---------------------------------------------------------------------------
  // Restore on sign-in — pulls remote state into local SQLite. Uses the
  // local row's own uuid as the join key (client-generated ids match on both
  // sides by design, see PILOT_PLAN.md), so this is a plain "insert what's
  // missing, refresh what's older" pass, never a destructive replace.
  // ---------------------------------------------------------------------------

  Future<void> hydrateAfterSignIn() async {
    final uid = _userId;
    if (uid == null) return;
    await Future.wait([
      _hydrateVocabCards(uid),
      _hydrateDailySessions(uid),
      _hydrateAiSessions(uid),
      _hydrateCreditUsage(uid),
      _hydrateCompetencyStates(uid),
      _hydrateLearningPlans(uid),
      _hydrateLessonProgress(uid),
      _hydrateMistakeTags(uid),
      _hydrateEvents(uid),
      _hydrateEntitlements(uid),
      _hydrateGeneratedStories(uid),
      _hydrateGeneratedRoleplays(uid),
    ]);
  }

  // Pulls the subscription flags the revenuecat-webhook edge function (and
  // redeem_subscription_invite_code RPC) write onto `profiles` into the local
  // `entitlements` table, so PilotAccessService's synchronous, offline-first
  // snapshot() reflects real subscription state instead of only ever seeing
  // the founding_access/localPreview default. subscription_active is treated
  // as advisory, not authoritative: an invite-code grant has no server job
  // that flips the flag back off once subscription_expires_at passes (unlike
  // RevenueCat cancellations, which the webhook handles), so expiry is always
  // re-checked against wall-clock time here too.
  Future<void> _hydrateEntitlements(String uid) async {
    final row = await _client
        .from('profiles')
        .select('subscription_active, subscription_product_id, subscription_expires_at')
        .eq('id', uid)
        .maybeSingle();
    if (row == null) return;

    final expiresAtRaw = row['subscription_expires_at'] as String?;
    final expiresAt = expiresAtRaw != null ? DateTime.tryParse(expiresAtRaw) : null;
    final notExpired = expiresAt == null || expiresAt.isAfter(DateTime.now().toUtc());
    final isActive = (row['subscription_active'] as bool? ?? false) && notExpired;
    final status = isActive ? 'active' : 'inactive';
    final productId = (row['subscription_product_id'] as String?) ?? 'none';

    final existing = _db.select(
      'SELECT status, product_id, expires_at FROM entitlements '
      "WHERE source = 'supabase_subscription' "
      'ORDER BY verified_at DESC, updated_at DESC LIMIT 1',
    );
    if (existing.isNotEmpty) {
      final e = existing.first;
      if (e['status'] == status &&
          e['product_id'] == productId &&
          e['expires_at'] == expiresAtRaw) {
        return; // Unchanged since last hydration — skip the redundant insert.
      }
    }

    final now = DateTime.now().toUtc().toIso8601String();
    _db.execute(
      '''INSERT INTO entitlements
         (id, user_id, product_id, status, source, expires_at, verified_at, created_at, updated_at)
         VALUES (?, ?, ?, ?, 'supabase_subscription', ?, ?, ?, ?)''',
      ['${uid}_subscription_$now', uid, productId, status, expiresAtRaw, now, now, now],
    );
  }

  Future<void> _hydrateVocabCards(String uid) async {
    final rows = await _client
        .from('vocab_card_state')
        .select()
        .eq('user_id', uid);
    for (final r in rows) {
      _db.execute(
        '''
        INSERT INTO vocab_cards
          (id, entry_id, ease, interval_days, reps, due_at, introduced_on,
           last_reviewed_at, last_grade, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(entry_id) DO UPDATE SET
          ease = excluded.ease, interval_days = excluded.interval_days,
          reps = excluded.reps, due_at = excluded.due_at,
          introduced_on = COALESCE(vocab_cards.introduced_on, excluded.introduced_on),
          last_reviewed_at = excluded.last_reviewed_at, last_grade = excluded.last_grade,
          updated_at = excluded.updated_at
        WHERE excluded.updated_at > vocab_cards.updated_at
        ''',
        [
          '${r['user_id']}:${r['entry_id']}',
          r['entry_id'],
          r['ease'],
          r['interval_days'],
          r['reps'],
          r['due_at'],
          r['introduced_on'],
          r['last_reviewed_at'],
          r['last_grade'],
          r['updated_at'],
          r['updated_at'],
        ],
      );
    }
  }

  Future<void> _hydrateDailySessions(String uid) async {
    final rows = await _client
        .from('daily_session_state')
        .select()
        .eq('user_id', uid);
    for (final r in rows) {
      _db.execute(
        '''
        INSERT INTO daily_sessions
          (id, local_date, planned_length, current_stage, current_item_index,
           stages_json, vocab_entry_ids_json, grammar_lesson_id, reading_passage_json,
           started_at, completed_at, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
          current_stage = excluded.current_stage,
          current_item_index = excluded.current_item_index,
          stages_json = excluded.stages_json,
          started_at = excluded.started_at,
          completed_at = excluded.completed_at,
          updated_at = excluded.updated_at
        WHERE excluded.updated_at > daily_sessions.updated_at
        ''',
        [
          r['id'],
          r['local_date'],
          r['planned_length'] ?? 'standard',
          r['current_stage'],
          r['current_item_index'] ?? 0,
          r['stages_json'] != null ? _jsonOf(r['stages_json']) : '{}',
          r['vocab_entry_ids_json'] != null
              ? _jsonOf(r['vocab_entry_ids_json'])
              : null,
          r['grammar_lesson_id'],
          r['reading_passage_json'] != null
              ? _jsonOf(r['reading_passage_json'])
              : null,
          r['started_at'],
          r['completed_at'],
          r['updated_at'],
          r['updated_at'],
        ],
      );
    }
  }

  Future<void> _hydrateGeneratedStories(String uid) async {
    final rows = await _client
        .from('generated_stories')
        .select()
        .eq('user_id', uid);
    for (final r in rows) {
      _db.execute(
        '''
        INSERT INTO generated_stories
          (id, title, passage_json, quiz_json, keywords_json, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
          title = excluded.title,
          passage_json = excluded.passage_json,
          quiz_json = excluded.quiz_json,
          keywords_json = excluded.keywords_json,
          updated_at = excluded.updated_at
        WHERE excluded.updated_at > generated_stories.updated_at
        ''',
        [
          r['id'],
          r['title'],
          _jsonOf(r['passage_json']),
          _jsonOf(r['quiz_json']),
          _jsonOf(r['keywords_json']),
          r['created_at'],
          r['updated_at'],
        ],
      );
    }
  }

  Future<void> _hydrateGeneratedRoleplays(String uid) async {
    final rows = await _client
        .from('generated_roleplays')
        .select()
        .eq('user_id', uid);
    for (final r in rows) {
      _db.execute(
        '''
        INSERT INTO generated_roleplays
          (id, title, passage_json, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
          title = excluded.title,
          passage_json = excluded.passage_json,
          updated_at = excluded.updated_at
        WHERE excluded.updated_at > generated_roleplays.updated_at
        ''',
        [
          r['id'],
          r['title'],
          _jsonOf(r['passage_json']),
          r['created_at'],
          r['updated_at'],
        ],
      );
    }
  }

  Future<void> _hydrateAiSessions(String uid) async {
    final rows = await _client
        .from('ai_session_state')
        .select()
        .eq('user_id', uid);
    for (final r in rows) {
      _db.execute(
        '''
        INSERT INTO ai_sessions
          (id, daily_session_id, stage, topic, connected_at, ended_at,
           learner_utterance_count, ended_reason, transcript_json, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
          ended_at = excluded.ended_at, ended_reason = excluded.ended_reason,
          learner_utterance_count = excluded.learner_utterance_count,
          transcript_json = COALESCE(excluded.transcript_json, ai_sessions.transcript_json),
          updated_at = excluded.updated_at
        WHERE excluded.updated_at > ai_sessions.updated_at
        ''',
        [
          r['id'],
          r['daily_session_id'],
          r['stage'],
          r['topic'],
          r['connected_at'],
          r['ended_at'],
          r['learner_utterance_count'] ?? 0,
          r['ended_reason'],
          r['transcript_json'] != null ? _jsonOf(r['transcript_json']) : null,
          r['updated_at'],
          r['updated_at'],
        ],
      );
    }
  }

  Future<void> _hydrateCreditUsage(String uid) async {
    final rows = await _client
        .from('credit_usage_state')
        .select()
        .eq('user_id', uid);
    for (final r in rows) {
      final existing = _db.select(
        "SELECT COALESCE(SUM(seconds_used), 0) AS s FROM credit_usage WHERE local_date = ? AND ai_session_id IS NULL",
        [r['local_date']],
      );
      final localSynthetic = existing.first['s'] as int;
      final remote = r['seconds_used'] as int? ?? 0;
      if (remote > localSynthetic) {
        _db.execute(
          '''INSERT INTO credit_usage (id, local_date, seconds_used, ai_session_id, created_at)
             VALUES (?, ?, ?, NULL, ?)''',
          [
            '${uid}_${r['local_date']}_restore',
            r['local_date'],
            remote - localSynthetic,
            DateTime.now().toUtc().toIso8601String(),
          ],
        );
      }
    }
  }

  Future<void> _hydrateCompetencyStates(String uid) async {
    final rows = await _client
        .from('learner_competency_state')
        .select()
        .eq('user_id', uid);
    for (final r in rows) {
      final exists = _db.select(
        'SELECT updated_at FROM learner_competency_states WHERE user_id IS ? AND competency_id = ? AND modality = ?',
        [uid, r['competency_id'], r['modality']],
      );
      if (exists.isNotEmpty) {
        final localUpdated = exists.first['updated_at'] as String?;
        if (localUpdated != null &&
            (r['updated_at'] as String).compareTo(localUpdated) <= 0) {
          continue;
        }
        _db.execute(
          'DELETE FROM learner_competency_states WHERE user_id IS ? AND competency_id = ? AND modality = ?',
          [uid, r['competency_id'], r['modality']],
        );
      }
      _db.execute(
        '''INSERT INTO learner_competency_states
           (id, user_id, competency_id, modality, mastery_estimate, confidence,
            retention_strength, evidence_count, transfer_status, last_observed_at,
            last_success_at, next_review_at, learner_model_type, model_version,
            model_state_json, created_at, updated_at)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
        [
          '${uid}_${r['competency_id']}_${r['modality']}',
          uid,
          r['competency_id'],
          r['modality'],
          r['mastery_estimate'],
          r['confidence'],
          r['retention_strength'],
          r['evidence_count'] ?? 0,
          r['transfer_status'],
          r['last_observed_at'],
          r['last_success_at'],
          r['next_review_at'],
          r['learner_model_type'],
          r['model_version'],
          r['model_state_json'] != null ? _jsonOf(r['model_state_json']) : '{}',
          r['updated_at'],
          r['updated_at'],
        ],
      );
    }
  }

  Future<void> _hydrateLearningPlans(String uid) async {
    final plans = await _client
        .from('learning_plan_state')
        .select()
        .eq('user_id', uid);
    for (final p in plans) {
      _db.execute(
        '''
        INSERT INTO learning_plans
          (id, local_date, available_minutes, environment_json, primary_priority,
           explanation, planner_version, input_snapshot_json, status,
           replaces_plan_id, replan_reason, started_at, completed_at, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
          status = excluded.status, started_at = excluded.started_at,
          completed_at = excluded.completed_at, updated_at = excluded.updated_at
        WHERE excluded.updated_at > learning_plans.updated_at
        ''',
        [
          p['id'],
          p['local_date'],
          p['available_minutes'] ?? 0,
          _jsonOf(p['environment_json'] ?? {}),
          p['primary_priority'] ?? '',
          p['explanation'] ?? '',
          p['planner_version'] ?? '',
          _jsonOf(p['input_snapshot_json'] ?? {}),
          p['status'] ?? 'generated',
          p['replaces_plan_id'],
          p['replan_reason'],
          p['started_at'],
          p['completed_at'],
          p['updated_at'],
          p['updated_at'],
        ],
      );

      final tasks = await _client
          .from('plan_task_state')
          .select()
          .eq('plan_id', p['id'] as String);
      for (final t in tasks) {
        _db.execute(
          '''
          INSERT INTO plan_tasks
            (id, plan_id, sequence, content_item_id, modality, requirement,
             estimated_minutes, reason_code, reason_detail_json,
             target_competency_ids_json, status, started_at, completed_at,
             result_summary_json, created_at, updated_at)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          ON CONFLICT(id) DO UPDATE SET
            status = excluded.status, started_at = excluded.started_at,
            completed_at = excluded.completed_at,
            result_summary_json = excluded.result_summary_json,
            updated_at = excluded.updated_at
          WHERE excluded.updated_at > plan_tasks.updated_at
          ''',
          [
            t['id'],
            t['plan_id'],
            t['sequence'],
            t['content_item_id'],
            t['modality'],
            t['requirement'],
            t['estimated_minutes'] ?? 0,
            t['reason_code'],
            _jsonOf(t['reason_detail_json'] ?? {}),
            _jsonOf(t['target_competency_ids_json'] ?? []),
            t['status'] ?? 'pending',
            t['started_at'],
            t['completed_at'],
            t['result_summary_json'] != null
                ? _jsonOf(t['result_summary_json'])
                : null,
            t['updated_at'],
            t['updated_at'],
          ],
        );
      }
    }
  }

  Future<void> _hydrateLessonProgress(String uid) async {
    final rows = await _client
        .from('lesson_progress_state')
        .select()
        .eq('user_id', uid);
    for (final r in rows) {
      _db.execute(
        'INSERT OR REPLACE INTO lesson_progress (lesson_id, status, score) VALUES (?, ?, ?)',
        [r['lesson_id'], r['status'], null],
      );
    }
  }

  Future<void> _hydrateMistakeTags(String uid) async {
    final rows = await _client
        .from('mistake_tag_state')
        .select()
        .eq('user_id', uid);
    for (final r in rows) {
      _db.execute(
        '''INSERT INTO mistake_tags (tag, description, count, resolved)
           VALUES (?, '', ?, ?)
           ON CONFLICT(tag) DO UPDATE SET
             count = MAX(mistake_tags.count, excluded.count),
             resolved = MAX(mistake_tags.resolved, excluded.resolved)''',
        [r['tag'], r['occurrences'] ?? 1, (r['resolved'] == true) ? 1 : 0],
      );
    }
  }

  /// Append-only streams (vocab reviews, evidence/error events, writing
  /// submissions, diary entries) replayed from `learner_events`, keyed on the
  /// id each event carried in its payload so replays are idempotent.
  Future<void> _hydrateEvents(String uid) async {
    final rows = await _client
        .from('learner_events')
        .select()
        .eq('user_id', uid)
        .order('occurred_at');
    for (final r in rows) {
      final type = r['event_type'] as String;
      final payload = Map<String, Object?>.from(r['payload'] as Map);
      final occurredAt = r['occurred_at'] as String;
      switch (type) {
        case 'vocab_review':
          _db.execute(
            '''INSERT OR IGNORE INTO vocab_reviews
               (id, entry_id, grade, response_type, session_id, reviewed_at, created_at)
               VALUES (?, ?, ?, ?, ?, ?, ?)''',
            [
              payload['id'],
              payload['entry_id'],
              payload['grade'],
              payload['response_type'],
              payload['session_id'],
              occurredAt,
              occurredAt,
            ],
          );
        case 'writing_submission':
          final already = _db.select(
            'SELECT 1 FROM writing_submissions WHERE task_id = ? AND text = ? AND submitted_at = ?',
            [payload['task_id'], payload['text'], occurredAt],
          );
          if (already.isEmpty) {
            _db.execute(
              'INSERT INTO writing_submissions (task_id, text, feedback, submitted_at) VALUES (?, ?, ?, ?)',
              [
                payload['task_id'],
                payload['text'],
                payload['feedback'] ?? '',
                occurredAt,
              ],
            );
          }
        case 'diary_entry':
          final already = _db.select(
            'SELECT 1 FROM session_diary WHERE date = ? AND stage = ? AND summary = ?',
            [occurredAt.split('T').first, payload['stage'], payload['summary']],
          );
          if (already.isEmpty) {
            _db.execute(
              'INSERT INTO session_diary (date, stage, summary) VALUES (?, ?, ?)',
              [occurredAt.split('T').first, payload['stage'], payload['summary']],
            );
          }
        case 'evidence_event':
        case 'error_event':
          // Ground truth for the competency model, already reflected in the
          // materialized learner_competency_state pulled above — not
          // replayed into the local evidence_events/error_events ledger
          // to avoid re-deriving triggers/constraints tied to plan/session
          // ids that may not exist locally yet on a fresh device.
          break;
      }
    }
  }

  String _jsonOf(Object? value) {
    if (value is String) return value;
    if (value == null) return '{}';
    return jsonEncode(value);
  }
}
