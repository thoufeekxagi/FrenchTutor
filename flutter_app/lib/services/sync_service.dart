import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqlite3/common.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/database/generated_grammar_story_store.dart';
import '../data/database/generated_story_store.dart';
import '../data/database/generated_writing_task_store.dart';
import '../data/database/generated_vocabulary_set_store.dart';
import '../data/database/speaking_lesson_store.dart';
import '../data/database/adaptive_course_store.dart';
import '../data/database/pilot_infrastructure_store.dart';
import '../models/content_models.dart';
import '../models/daily_session.dart';
import '../models/note.dart';
// Aliased — supabase_flutter's own `Session` (an auth session) would
// otherwise collide with this app's practice-session model of the same name.
import '../models/session.dart' as app_session;
import '../models/profile.dart';
import '../models/srs_state.dart';
import '../models/speak_curriculum.dart';
import '../models/speaking_course.dart';
import '../data/database/speaking_lesson_codec.dart';
import 'image_storage_optimizer.dart';
import '../orchestration/models/competency_state.dart';
import '../orchestration/models/error_event.dart';
import '../orchestration/models/evidence_event.dart';
import '../orchestration/models/learning_plan.dart';
import '../orchestration/models/task_result.dart';

class _CoverOptimizationFailure implements Exception {
  const _CoverOptimizationFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

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

  /// Parallel artwork/enrichment callbacks can update one story close
  /// together. Serialize snapshots per story so a slower network response
  /// cannot overwrite a newer local snapshot in Supabase.
  final Map<String, Future<void>> _generatedStorySyncs = {};

  SupabaseClient get _client => Supabase.instance.client;
  String? get _userId => _client.auth.currentUser?.id;
  bool get isSignedIn => _userId != null;

  /// Local starter cards use an asset URL until their private cover has been
  /// uploaded. Never persist that local-only marker as a remote URL.
  String? _remoteCoverUrl(String? value) =>
      value != null && value.startsWith('asset:') ? null : value;

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

  Future<void> syncProfile(Profile p) => _guarded(
    (uid) async {
      await _client
          .from('profiles')
          .update({
            'goal': p.goal,
            'level': p.level,
            'session_length': p.sessionLength,
            'reminder_time': p.reminderTime,
            'preferred_days': p.preferredDays.isEmpty
                ? null
                : p.preferredDays.join(','),
            'interests': p.interests.isEmpty ? null : p.interests.join(','),
            'time_zone': p.timeZone,
            'notification_permission_state': p.notificationPermissionState,
            'onboarding_version': p.onboardingVersion,
            'onboarded_at': p.onboardedAt?.toUtc().toIso8601String(),
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', uid);
    },
    queueTable: 'profiles',
    queueRowId: p.id,
  );

  // ---------------------------------------------------------------------------
  // Adaptive course plans and learner-specific session specifications
  // ---------------------------------------------------------------------------

  Future<void> syncAdaptiveCoursePlan(AdaptiveCoursePlanSnapshot plan) =>
      _guarded(
        (uid) async {
          final now = DateTime.now().toUtc().toIso8601String();
          await _client.from('adaptive_course_plans').upsert({
            'id': plan.id,
            'user_id': uid,
            'goal': plan.goal,
            'level': plan.level,
            'profile_fingerprint': plan.profileFingerprint,
            'version': plan.version,
            'status': plan.status,
            'updated_at': now,
          }, onConflict: 'id');
          if (plan.sessions.isEmpty) return;
          await _client
              .from('adaptive_course_sessions')
              .upsert(
                plan.sessions
                    .map(
                      (session) => {
                        'id': session.id,
                        'user_id': uid,
                        'plan_id': plan.id,
                        'content_key': session.contentKey,
                        'sequence': session.sequence,
                        'level': session.level,
                        'unit': session.unit,
                        'unit_title': session.unitTitle,
                        'title': session.title,
                        'subtitle': session.subtitle,
                        'competency': session.competency,
                        'context': session.context,
                        'primary_skill': session.primarySkill.wireName,
                        'supporting_skills_json': session.supportingSkills
                            .map((skill) => skill.wireName)
                            .toList(),
                        'grammar_focus_json': session.grammarFocus,
                        'success_criteria_json': session.successCriteria,
                        'estimated_minutes': session.estimatedMinutes,
                        'profile_fingerprint': session.profileFingerprint,
                        'status': session.status,
                        'created_at': session.createdAt
                            .toUtc()
                            .toIso8601String(),
                        'updated_at': now,
                        'completed_at': session.completedAt
                            ?.toUtc()
                            .toIso8601String(),
                      },
                    )
                    .toList(),
                onConflict: 'id',
              );
        },
        queueTable: 'adaptive_course_plans',
        queueRowId: plan.id,
      );

  Future<void> syncAdaptiveCourseSession(AdaptiveCourseSessionSpec session) =>
      _guarded(
        (uid) async {
          await _client.from('adaptive_course_sessions').upsert({
            'id': session.id,
            'user_id': uid,
            'plan_id': session.planId,
            'content_key': session.contentKey,
            'sequence': session.sequence,
            'level': session.level,
            'unit': session.unit,
            'unit_title': session.unitTitle,
            'title': session.title,
            'subtitle': session.subtitle,
            'competency': session.competency,
            'context': session.context,
            'primary_skill': session.primarySkill.wireName,
            'supporting_skills_json': session.supportingSkills
                .map((skill) => skill.wireName)
                .toList(),
            'grammar_focus_json': session.grammarFocus,
            'success_criteria_json': session.successCriteria,
            'estimated_minutes': session.estimatedMinutes,
            'profile_fingerprint': session.profileFingerprint,
            'status': session.status,
            'created_at': session.createdAt.toUtc().toIso8601String(),
            'updated_at': DateTime.now().toUtc().toIso8601String(),
            'completed_at': session.completedAt?.toUtc().toIso8601String(),
          }, onConflict: 'id');
        },
        queueTable: 'adaptive_course_sessions',
        queueRowId: session.id,
      );

  // ---------------------------------------------------------------------------
  // Vocab / SRS
  // ---------------------------------------------------------------------------

  Future<void> syncVocabCard(SRSState s) => _guarded(
    (uid) async {
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
    },
    queueTable: 'vocab_cards',
    queueRowId: s.entryId,
  );

  Future<void> logVocabReview({
    required String reviewId,
    required String entryId,
    required String grade,
    required String responseType,
    String? sessionId,
    required DateTime reviewedAt,
  }) => _guarded(
    (uid) async {
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
    },
    queueTable: 'vocab_reviews',
    queueRowId: reviewId,
  );

  // ---------------------------------------------------------------------------
  // Daily Path / AI sessions / credit
  // ---------------------------------------------------------------------------

  Future<void> syncDailySession(DailySession session) => _guarded(
    (uid) async {
      // The table's real uniqueness constraint is (user_id, local_date), not
      // just `id` — a new local DailySession row (a fresh client-generated id,
      // e.g. when the rotation planner regenerates today's plan) for a date
      // that already has a synced row was hitting that constraint as a 23505
      // conflict instead of updating it, since upsert() only dedupes against
      // the column set you give it (the primary key, `id`, by default).
      await _client.from('daily_session_state').upsert({
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
        'writing_task_json': session.writingTaskJson,
        'started_at': session.startedAt?.toUtc().toIso8601String(),
        'completed_at': session.completedAt?.toUtc().toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'user_id,local_date');
    },
    queueTable: 'daily_sessions',
    queueRowId: session.id,
  );

  // ---------------------------------------------------------------------------
  // Generated story library
  // ---------------------------------------------------------------------------

  Future<void> syncGeneratedStory(GeneratedStory story) {
    final previous = _generatedStorySyncs[story.id] ?? Future<void>.value();
    final next = previous.then((_) => _syncGeneratedStoryNow(story));
    _generatedStorySyncs[story.id] = next;
    next.then(
      (_) {
        if (identical(_generatedStorySyncs[story.id], next)) {
          _generatedStorySyncs.remove(story.id);
        }
      },
      onError: (_, _) {
        if (identical(_generatedStorySyncs[story.id], next)) {
          _generatedStorySyncs.remove(story.id);
        }
      },
    );
    return next;
  }

  Future<void> _syncGeneratedStoryNow(GeneratedStory story) => _guarded(
    (uid) async {
      await _client.from('generated_stories').upsert({
        'id': story.id,
        'user_id': uid,
        'title': story.title,
        'passage_json': story.passage.toJson(),
        'quiz_json': story.quiz.map((q) => q.toJson()).toList(),
        'keywords_json': story.keywords.map((k) => k.toJson()).toList(),
        'level_band': story.levelBand,
        'summary': story.summary,
        'topic': story.topic,
        'read_time_minutes': story.readTimeMinutes,
        'cover_url': _remoteCoverUrl(story.coverUrl),
        'music_background_url': _remoteCoverUrl(story.musicBackgroundUrl),
        'audio_path': story.audioPath,
        'audio_mode': story.audioMode,
        'practice_mode': story.practiceMode,
        'created_at': story.createdAt.toUtc().toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
    },
    queueTable: 'generated_stories',
    queueRowId: story.id,
  );

  Future<void> syncStoryFavorite({
    required String storyId,
    required bool favorite,
  }) => _guarded(
    (uid) async {
      if (favorite) {
        final now = DateTime.now().toUtc().toIso8601String();
        await _client.from('story_favorites').upsert({
          'user_id': uid,
          'story_id': storyId,
          'created_at': now,
          'updated_at': now,
        }, onConflict: 'user_id,story_id');
      } else {
        await _client
            .from('story_favorites')
            .delete()
            .eq('user_id', uid)
            .eq('story_id', storyId);
      }
    },
    queueTable: 'story_favorites',
    queueRowId: storyId,
  );

  /// Uploads a generated cover to the learner-scoped private bucket and
  /// returns a long-lived signed URL for the local story card. The object
  /// path is owned by the authenticated learner; it is never public.
  Future<String?> uploadStoryCover({
    required String storyId,
    required Uint8List bytes,
    String? diagnosticRoleplayId,
    int maxBytes = ImageStorageOptimizer.maxBytes,
  }) async {
    try {
      return await _uploadStoryCoverOnce(
        storyId: storyId,
        bytes: bytes,
        maxBytes: maxBytes,
        diagnosticRoleplayId: diagnosticRoleplayId,
        targetAspectRatio: ImageStorageOptimizer.targetAspectRatio,
        maxWidth: ImageStorageOptimizer.maxWidth,
        maxHeight: ImageStorageOptimizer.maxHeight,
      );
    } catch (e, st) {
      debugPrint('Story cover upload failed ($storyId): $e\n$st');
      if (diagnosticRoleplayId != null) {
        unawaited(
          logRoleplayCoverEvent(
            roleplayId: diagnosticRoleplayId,
            phase: 'upload_failed',
            error: e,
            sourceBytes: bytes.length,
          ),
        );
      }
      return null;
    }
  }

  /// Saves the exact rendered listening clip in a private, learner-scoped
  /// bucket. The database stores only this stable path, never base64 audio or
  /// an expiring signed URL.
  Future<String?> uploadListeningAudio({
    required String storyId,
    required String mode,
    required Uint8List bytes,
    String extension = 'mp3',
    String contentType = 'audio/mpeg',
  }) async {
    final uid = _userId;
    if (uid == null || bytes.isEmpty) return null;
    final safeMode = mode.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '-');
    final safeExtension = extension.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    if (safeExtension.isEmpty) {
      throw ArgumentError.value(extension, 'extension', 'must not be empty');
    }
    final path = '$uid/$storyId-$safeMode.$safeExtension';
    await _client.storage
        .from('listening-audio')
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: true),
        );
    return path;
  }

  /// Downloads a previously rendered clip using the current user's JWT, so a
  /// private bucket remains private while the lesson can still be replayed.
  Future<Uint8List?> downloadListeningAudio(String path) async {
    if (_userId == null || path.trim().isEmpty) return null;
    return _client.storage.from('listening-audio').download(path);
  }

  /// Generates and uploads artwork with the single shared retry policy.
  /// Generation/compression may happen twice; upload/network errors do not
  /// trigger an unbounded regeneration loop.
  Future<String?> uploadGeneratedStoryCover({
    required String storyId,
    required Future<Uint8List> Function(int attempt) generate,
    String? diagnosticRoleplayId,
    String storageSuffix = '',
    double targetAspectRatio = ImageStorageOptimizer.targetAspectRatio,
    int maxWidth = ImageStorageOptimizer.maxWidth,
    int maxHeight = ImageStorageOptimizer.maxHeight,
    int maxBytes = ImageStorageOptimizer.maxBytes,
    int? retryMaxBytes,
  }) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      final attemptNumber = attempt + 1;
      unawaited(
        diagnosticRoleplayId == null
            ? Future<void>.value()
            : logRoleplayCoverEvent(
                roleplayId: diagnosticRoleplayId,
                phase: 'attempt_started',
                attempt: attemptNumber,
              ),
      );
      Uint8List bytes;
      try {
        bytes = await generate(attempt);
      } catch (error) {
        debugPrint(
          'Story cover generation attempt $attemptNumber failed ($storyId): $error',
        );
        if (attempt == 1) return null;
        continue;
      }
      try {
        final url = await _uploadStoryCoverOnce(
          storyId: storyId,
          bytes: bytes,
          maxBytes: attempt == 0
              ? maxBytes
              : (retryMaxBytes ?? (maxBytes * 1.6).round()),
          diagnosticRoleplayId: diagnosticRoleplayId,
          storageSuffix: storageSuffix,
          targetAspectRatio: targetAspectRatio,
          maxWidth: maxWidth,
          maxHeight: maxHeight,
        );
        if (url != null && url.isNotEmpty) return url;
        return null;
      } on _CoverOptimizationFailure catch (error) {
        debugPrint(
          'Story cover compression attempt $attemptNumber failed ($storyId): $error',
        );
        if (attempt == 1) return null;
      } catch (error, stackTrace) {
        debugPrint('Story cover upload failed ($storyId): $error\n$stackTrace');
        return null;
      }
    }
    return null;
  }

  Future<String?> _uploadStoryCoverOnce({
    required String storyId,
    required Uint8List bytes,
    required int maxBytes,
    String? diagnosticRoleplayId,
    String storageSuffix = '',
    required double targetAspectRatio,
    required int maxWidth,
    required int maxHeight,
  }) async {
    final uid = _userId;
    if (uid == null) return null;
    if (bytes.isEmpty) {
      if (diagnosticRoleplayId != null) {
        unawaited(
          logRoleplayCoverEvent(
            roleplayId: diagnosticRoleplayId,
            phase: 'upload_skipped',
            error: StateError('image bytes were empty'),
            sourceBytes: 0,
          ),
        );
      }
      throw _CoverOptimizationFailure('generated image bytes were empty');
    }
    late final Uint8List optimized;
    try {
      optimized = ImageStorageOptimizer.optimizeArtwork(
        bytes,
        maxBytes: maxBytes,
        targetAspectRatio: targetAspectRatio,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
      );
    } on FormatException catch (error) {
      throw _CoverOptimizationFailure(error.message);
    }
    final path = '$uid/$storyId$storageSuffix.jpg';
    final bucket = _client.storage.from('story-covers');
    final contentType =
        optimized.length >= 8 &&
            optimized[0] == 0x89 &&
            optimized[1] == 0x50 &&
            optimized[2] == 0x4e &&
            optimized[3] == 0x47
        ? 'image/png'
        : 'image/jpeg';
    await bucket.uploadBinary(
      path,
      optimized,
      fileOptions: FileOptions(contentType: contentType, upsert: true),
    );
    final signedUrl = await bucket.createSignedUrl(path, 60 * 60 * 24 * 365);
    if (diagnosticRoleplayId != null) {
      unawaited(
        logRoleplayCoverEvent(
          roleplayId: diagnosticRoleplayId,
          phase: 'upload_succeeded',
          sourceBytes: bytes.length,
          optimizedBytes: optimized.length,
        ),
      );
    }
    return signedUrl;
  }

  /// Best-effort, private diagnostics for the roleplay cover pipeline.
  ///
  /// These events intentionally use the existing RLS-protected
  /// `learner_events` append-only stream. They never enter the sync outbox:
  /// a diagnostic must not create a user-data mutation or delay the lesson.
  /// The payload is bounded and contains no prompt, image bytes, URL, or
  /// credential material.
  Future<void> logRoleplayCoverEvent({
    required String roleplayId,
    required String phase,
    int? attempt,
    Object? error,
    int? sourceBytes,
    int? optimizedBytes,
  }) async {
    final uid = _userId;
    if (uid == null) return;
    final payload = <String, Object?>{
      'roleplay_id': roleplayId,
      'phase': phase,
      if (attempt != null) 'attempt': attempt,
      if (error != null) ...{
        'error_type': error.runtimeType.toString(),
        'error_message': _boundedDiagnostic(error),
      },
      if (sourceBytes != null) 'source_bytes': sourceBytes,
      if (optimizedBytes != null) 'optimized_bytes': optimizedBytes,
    };
    try {
      await _client.from('learner_events').insert({
        'user_id': uid,
        'event_type': 'roleplay_cover',
        'payload': payload,
        'occurred_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (logError, stackTrace) {
      // Diagnostics must never affect content generation or the learner's
      // route. Keep a local breadcrumb for development builds instead.
      debugPrint('Roleplay cover diagnostic failed: $logError\n$stackTrace');
    }
  }

  String _boundedDiagnostic(Object error) {
    final redacted = error.toString().replaceAll(
      RegExp(
        r'(authorization|api[-_ ]?key|access[-_ ]?token|refresh[-_ ]?token)\s*[:=]\s*[^\s,;]+',
        caseSensitive: false,
      ),
      '<redacted>',
    );
    if (redacted.length <= 500) return redacted;
    return '${redacted.substring(0, 500)}…';
  }

  // ---------------------------------------------------------------------------
  // Generated grammar-practice library
  // ---------------------------------------------------------------------------

  Future<void> syncGeneratedGrammarStory(GeneratedGrammarStory story) =>
      _guarded(
        (uid) async {
          await _client.from('generated_grammar_stories').upsert({
            'id': story.id,
            'user_id': uid,
            'title': story.title,
            'grammar_point': story.grammarPoint,
            'level_band': story.levelBand,
            'passage_json': story.passage.toJson(),
            'quiz_json': story.quiz.map((q) => q.toJson()).toList(),
            'keywords_json': story.keywords.map((k) => k.toJson()).toList(),
            'explanation_json': story.explanation.toJson(),
            'score': story.score,
            'cover_url': _remoteCoverUrl(story.coverUrl),
            'created_at': story.createdAt.toUtc().toIso8601String(),
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          });
        },
        queueTable: 'generated_grammar_stories',
        queueRowId: story.id,
      );

  Future<void> syncGeneratedWritingTask(GeneratedWritingTask generated) =>
      _guarded(
        (uid) async {
          await _client.from('generated_writing_tasks').upsert({
            'id': generated.id,
            'user_id': uid,
            'task_json': generated.task.toJson(),
            'level_band': generated.task.levelBand,
            'cover_url': _remoteCoverUrl(generated.coverUrl),
            'created_at': generated.createdAt.toUtc().toIso8601String(),
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          });
        },
        queueTable: 'generated_writing_tasks',
        queueRowId: generated.id,
      );

  // ---------------------------------------------------------------------------
  // Generated roleplay library
  // ---------------------------------------------------------------------------

  Future<void> syncGeneratedRoleplay(GeneratedRoleplay roleplay) => _guarded(
    (uid) async {
      await _client.from('generated_roleplays').upsert({
        'id': roleplay.id,
        'user_id': uid,
        'title': roleplay.title,
        'passage_json': roleplay.passage.toJson(),
        'level_band': roleplay.levelBand,
        'cover_url': _remoteCoverUrl(roleplay.coverUrl),
        'created_at': roleplay.createdAt.toUtc().toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
    },
    queueTable: 'generated_roleplays',
    queueRowId: roleplay.id,
  );

  /// Publishes one already-validated Speaking lesson to the shared catalog.
  /// The app never sends an unvalidated generator payload to this method.
  Future<void> syncSpeakingLesson(SpeakingCourseLesson lesson) => _guarded(
    (uid) async {
      final now = DateTime.now().toUtc().toIso8601String();
      await _client.from('speaking_lessons').upsert({
        'id': lesson.id,
        'source': 'generated',
        'mode': lesson.mode.name,
        'level_band': lesson.level,
        'title': lesson.title,
        'fingerprint': speakingLessonFingerprint(lesson),
        'lesson_json': speakingCourseLessonToJson(lesson),
        'created_by': uid,
        'is_validated': true,
        'created_at': now,
        'updated_at': now,
      }, onConflict: 'id');
    },
    queueTable: 'speaking_lessons',
    queueRowId: lesson.id,
  );

  /// Publishes the bundled catalog once per authenticated account. The rows
  /// are shared and read-only to learners after insertion; the local bundled
  /// catalog remains the immediate offline copy while this runs.
  Future<void> publishDefaultSpeakingCatalog() => _guarded((uid) async {
    final defaults = _defaultSpeakingLessons();
    if (defaults.isEmpty) return;
    final ids = defaults.map((lesson) => lesson.id).toList(growable: false);
    final existing = await _client
        .from('speaking_lessons')
        .select('id')
        .inFilter('id', ids);
    final existingIds = existing.map((row) => row['id'] as String).toSet();
    final missing = defaults.where(
      (lesson) => !existingIds.contains(lesson.id),
    );
    final now = DateTime.now().toUtc().toIso8601String();
    final rows = missing
        .map(
          (lesson) => {
            'id': lesson.id,
            'source': 'default',
            'mode': lesson.mode.name,
            'level_band': lesson.level,
            'title': lesson.title,
            'fingerprint': speakingLessonFingerprint(lesson),
            'lesson_json': speakingCourseLessonToJson(lesson),
            'created_by': uid,
            'is_validated': true,
            'created_at': now,
            'updated_at': now,
          },
        )
        .toList(growable: false);
    for (var start = 0; start < rows.length; start += 40) {
      final end = (start + 40).clamp(0, rows.length);
      await _client.from('speaking_lessons').insert(rows.sublist(start, end));
    }
  });

  Future<void> syncGeneratedVocabularySet(GeneratedVocabularySet set) =>
      _guarded(
        (uid) async {
          await _client.from('generated_vocabulary_sets').upsert({
            'id': set.id,
            'user_id': uid,
            'title': set.title,
            'summary': set.summary,
            'topic': set.topic,
            'level_band': set.levelBand,
            'entries_json': set.entries.map((entry) => entry.toJson()).toList(),
            'cover_url': _remoteCoverUrl(set.coverUrl),
            'created_at': set.createdAt.toUtc().toIso8601String(),
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          });
        },
        queueTable: 'generated_vocabulary_sets',
        queueRowId: set.id,
      );

  // ---------------------------------------------------------------------------
  // Practice sessions + their transcripts — every completed practice/lesson,
  // the exact data DailyGoalService reads for streak/momentum/"this week's
  // practice". Previously had ZERO sync coverage (never pushed, never
  // hydrated) — the cause of progress silently "starting from zero" after a
  // reinstall.
  // ---------------------------------------------------------------------------

  Future<void> syncSession(
    app_session.Session session, {
    required String updatedAt,
  }) => _guarded(
    (uid) async {
      await _client.from('sessions_state').upsert({
        'id': session.id,
        'user_id': uid,
        'started_at': session.startedAt,
        'ended_at': session.endedAt,
        'summary': session.summary,
        'topic': session.topic,
        'content_key': session.contentKey,
        'vocabulary_json': session.vocabulary,
        'stage': session.stage,
        'updated_at': updatedAt,
      });
    },
    queueTable: 'sessions_state',
    queueRowId: session.id,
  );

  Future<void> syncMessage({
    required String uuid,
    required String sessionId,
    required String role,
    required String content,
  }) => _guarded(
    (uid) async {
      await _client.from('chat_messages_state').upsert({
        'id': uuid,
        'user_id': uid,
        'session_id': sessionId,
        'role': role,
        'content': content,
      });
    },
    queueTable: 'chat_messages_state',
    queueRowId: uuid,
  );

  // ---------------------------------------------------------------------------
  // Floating notetaker — both self-typed notes and AI-generated session recaps
  // ---------------------------------------------------------------------------

  Future<void> syncNote(Note note) => _guarded(
    (uid) async {
      if (note.uuid == null) return; // legacy row, not yet assigned an id
      await _client.from('notes_state').upsert({
        'id': note.uuid,
        'user_id': uid,
        'tag': note.tag,
        'text': note.text,
        'source': note.source,
        'session_id': note.sessionId,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
    },
    queueTable: 'notes_state',
    queueRowId: note.uuid ?? note.id.toString(),
  );

  Future<void> deleteNote(String uuid) => _guarded(
    (uid) async {
      await _client
          .from('notes_state')
          .update({'deleted_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', uuid)
          .eq('user_id', uid);
    },
    queueTable: 'notes_state',
    queueRowId: uuid,
  );

  Future<void> syncAiSessionStart({
    required String id,
    String? dailySessionId,
    String? stage,
    String? topic,
    required DateTime connectedAt,
  }) => _guarded(
    (uid) async {
      await _client.from('ai_session_state').upsert({
        'id': id,
        'user_id': uid,
        'daily_session_id': dailySessionId,
        'stage': stage,
        'topic': topic,
        'connected_at': connectedAt.toUtc().toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
    },
    queueTable: 'ai_sessions',
    queueRowId: id,
  );

  Future<void> syncAiSessionEnd({
    required String id,
    required DateTime endedAt,
    required String endedReason,
    required int learnerUtteranceCount,
    String? transcriptJson,
  }) => _guarded(
    (uid) async {
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
    },
    queueTable: 'ai_sessions',
    queueRowId: id,
  );

  Future<void> addCreditUsage({
    required String localDate,
    required int secondsUsed,
  }) => _guarded(
    (uid) async {
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
    },
    queueTable: 'credit_usage',
    queueRowId: '$localDate:$secondsUsed',
  );

  // ---------------------------------------------------------------------------
  // Lesson progress / habits / writing / mistakes / diary — the smaller
  // secondary-loop data, all funneled through learner_events where they're
  // pure logs, or a small state table where they're mutable.
  // ---------------------------------------------------------------------------

  Future<void> syncLessonStatus(
    String lessonId,
    String status, {
    double? score,
  }) => _guarded(
    (uid) async {
      await _client.from('lesson_progress_state').upsert({
        'user_id': uid,
        'lesson_id': lessonId,
        'status': status,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'user_id,lesson_id');
    },
    queueTable: 'lesson_progress',
    queueRowId: lessonId,
  );

  Future<void> logHabit({
    required String habitId,
    required bool done,
    required int minutes,
    required String date,
  }) => _guarded(
    (uid) async {
      await _client.from('learner_events').insert({
        'user_id': uid,
        'event_type': 'habit_marked',
        'payload': {'habit_id': habitId, 'done': done, 'minutes': minutes},
        'occurred_at': DateTime.now().toUtc().toIso8601String(),
      });
    },
    queueTable: 'operational_events',
    queueRowId: '$date:$habitId',
  );

  Future<void> logWritingSubmission({
    required String taskId,
    required String text,
    required String feedback,
  }) => _guarded(
    (uid) async {
      await _client.from('learner_events').insert({
        'user_id': uid,
        'event_type': 'writing_submission',
        'payload': {'task_id': taskId, 'text': text, 'feedback': feedback},
        'occurred_at': DateTime.now().toUtc().toIso8601String(),
      });
    },
    queueTable: 'operational_events',
    queueRowId: '$taskId:${DateTime.now().microsecondsSinceEpoch}',
  );

  Future<void> logMistake({required String tag, required String description}) =>
      _guarded(
        (uid) async {
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
        },
        queueTable: 'mistake_tags',
        queueRowId: tag,
      );

  Future<void> resolveMistakeTag(String tag) => _guarded(
    (uid) async {
      await _client
          .from('mistake_tag_state')
          .update({'resolved': true})
          .eq('user_id', uid)
          .eq('tag', tag);
    },
    queueTable: 'mistake_tags',
    queueRowId: tag,
  );

  Future<void> logDiaryEntry({
    required String stage,
    required String summary,
  }) => _guarded(
    (uid) async {
      await _client.from('learner_events').insert({
        'user_id': uid,
        'event_type': 'diary_entry',
        'payload': {'stage': stage, 'summary': summary},
        'occurred_at': DateTime.now().toUtc().toIso8601String(),
      });
    },
    queueTable: 'operational_events',
    queueRowId: '$stage:${DateTime.now().microsecondsSinceEpoch}',
  );

  // ---------------------------------------------------------------------------
  // Orchestration state — the learner model ("personality"), evidence/error
  // ledger, and mission plans. This is the state the user specifically asked
  // to make resync correctly.
  // ---------------------------------------------------------------------------

  Future<void> logEvidence(EvidenceEvent event) => _guarded(
    (uid) async {
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
    },
    queueTable: 'evidence_events',
    queueRowId: event.id,
  );

  Future<void> logError(ErrorEvent event) => _guarded(
    (uid) async {
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
    },
    queueTable: 'error_events',
    queueRowId: event.id,
  );

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
  Future<void> syncCompetencyStates(List<CompetencyState> states) => _guarded(
    (uid) async {
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
                    'next_review_at': s.nextReviewAt?.toUtc().toIso8601String(),
                    'learner_model_type': s.learnerModelType,
                    'model_version': s.modelVersion,
                    'model_state_json': s.modelState,
                    'updated_at': DateTime.now().toUtc().toIso8601String(),
                  },
                )
                .toList(),
          );
    },
    queueTable: 'learner_competency_states',
    queueRowId: _userId ?? 'unknown',
  );

  Future<void> syncPlan(PlanSnapshot plan) => _guarded(
    (uid) async {
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
    },
    queueTable: 'learning_plans',
    queueRowId: plan.id,
  );

  Future<void> markPlanReplaced(String planId) =>
      updatePlanStatus(planId: planId, status: 'replaced');

  Future<void> updatePlanStatus({
    required String planId,
    required String status,
    DateTime? completedAt,
  }) => _guarded(
    (uid) async {
      await _client
          .from('learning_plan_state')
          .update({
            'status': status,
            if (completedAt != null)
              'completed_at': completedAt.toUtc().toIso8601String(),
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', planId);
    },
    queueTable: 'learning_plans',
    queueRowId: planId,
  );

  Future<void> syncPlanTask({
    required String taskId,
    required String status,
    DateTime? startedAt,
    DateTime? completedAt,
    Map<String, Object?>? resultSummary,
  }) => _guarded(
    (uid) async {
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
    },
    queueTable: 'plan_tasks',
    queueRowId: taskId,
  );

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
        _db.execute('UPDATE sync_outbox SET processed_at = ? WHERE id = ?', [
          DateTime.now().toUtc().toIso8601String(),
          mutation.id,
        ]);
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
        case 'generated_stories':
          final story = GeneratedStoryStore(
            _db,
          ).list().where((item) => item.id == rowId).firstOrNull;
          if (story == null) return true;
          await syncGeneratedStory(story);
          return true;
        case 'story_favorites':
          final uid = _userId;
          if (uid == null) return true;
          final rows = _db.select(
            'SELECT story_id, created_at, updated_at FROM story_favorites '
            'WHERE user_id = ? AND story_id = ?',
            [uid, rowId],
          );
          if (rows.isEmpty) {
            await _client
                .from('story_favorites')
                .delete()
                .eq('user_id', uid)
                .eq('story_id', rowId);
          } else {
            await syncStoryFavorite(storyId: rowId, favorite: true);
          }
          return true;
        case 'generated_grammar_stories':
          final story = GeneratedGrammarStoryStore(
            _db,
          ).list().where((item) => item.id == rowId).firstOrNull;
          if (story == null) return true;
          await syncGeneratedGrammarStory(story);
          return true;
        case 'generated_writing_tasks':
          final task = GeneratedWritingTaskStore(
            _db,
          ).list().where((item) => item.id == rowId).firstOrNull;
          if (task == null) return true;
          await syncGeneratedWritingTask(task);
          return true;
        case 'generated_vocabulary_sets':
          final set = GeneratedVocabularySetStore(
            _db,
          ).list().where((item) => item.id == rowId).firstOrNull;
          if (set == null) return true;
          await syncGeneratedVocabularySet(set);
          return true;
        case 'speaking_lessons':
          final lesson = SpeakingLessonStore(
            _db,
          ).list().where((item) => item.id == rowId).firstOrNull;
          if (lesson == null) return true;
          await syncSpeakingLesson(lesson);
          return true;
        case 'adaptive_course_plans':
          final plan = AdaptiveCourseStore(_db).planById(rowId);
          if (plan == null) return true;
          await syncAdaptiveCoursePlan(plan);
          return true;
        case 'adaptive_course_sessions':
          final session = AdaptiveCourseStore(_db).sessionById(rowId);
          if (session == null) return true;
          await syncAdaptiveCourseSession(session);
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
    // Each leg is wrapped so one failing pull (bad row, RLS hiccup, decode
    // error) can never silently swallow the others — previously a single
    // exception anywhere in this list, or the whole thing simply taking
    // longer than the caller's 8s timeout, left NO trace anywhere (app.dart's
    // `.catchError((_) {})` on the outer call is unconditional and silent).
    // `debugPrint` here at least makes a real failure visible in device logs
    // instead of just reading as "progress didn't come back".
    final legs = <String, Future<void> Function()>{
      'profile': () => _hydrateProfile(uid),
      'adaptiveCourses': () => _hydrateAdaptiveCourses(uid),
      'vocabCards': () => _hydrateVocabCards(uid),
      'dailySessions': () => _hydrateDailySessions(uid),
      'sessions': () => _hydrateSessions(uid),
      'messages': () => _hydrateMessages(uid),
      'aiSessions': () => _hydrateAiSessions(uid),
      'creditUsage': () => _hydrateCreditUsage(uid),
      'competencyStates': () => _hydrateCompetencyStates(uid),
      'learningPlans': () => _hydrateLearningPlans(uid),
      'lessonProgress': () => _hydrateLessonProgress(uid),
      'mistakeTags': () => _hydrateMistakeTags(uid),
      'events': () => _hydrateEvents(uid),
      'generatedStories': () => _hydrateGeneratedStories(uid),
      'storyFavorites': () => _hydrateStoryFavorites(uid),
      'generatedGrammarStories': () => _hydrateGeneratedGrammarStories(uid),
      'generatedWritingTasks': () => _hydrateGeneratedWritingTasks(uid),
      'generatedRoleplays': () => _hydrateGeneratedRoleplays(uid),
      'generatedVocabularySets': () => _hydrateGeneratedVocabularySets(uid),
      'speakingLessons': () => _hydrateSpeakingLessons(),
      'notes': () => _hydrateNotes(uid),
    };
    await Future.wait(
      legs.entries.map(
        (e) => e.value().catchError((err) {
          debugPrint('hydrateAfterSignIn: ${e.key} failed: $err');
        }),
      ),
    );
    // This is intentionally outside the critical hydration path. The bundled
    // catalog is already available locally, so publishing it cannot delay the
    // first screen after sign-in.
    unawaited(publishDefaultSpeakingCatalog());
  }

  /// Pulls the public, validated Speaking catalog into SQLite. It is safe to
  /// call on every app start: IDs and fingerprints make the operation
  /// idempotent, and malformed rows are skipped by the store.
  Future<void> hydrateSpeakingLessons() => _hydrateSpeakingLessons();

  /// Reload generated content into the local store for the current user.
  /// Screens can call this when they become visible without re-running the
  /// entire sign-in hydration sequence.
  Future<void> hydrateGeneratedStories() async {
    final uid = _userId;
    if (uid == null) return;
    await _hydrateGeneratedStories(uid);
  }

  Future<void> hydrateGeneratedGrammarStories() async {
    final uid = _userId;
    if (uid == null) return;
    await _hydrateGeneratedGrammarStories(uid);
  }

  Future<void> hydrateGeneratedWritingTasks() async {
    final uid = _userId;
    if (uid == null) return;
    await _hydrateGeneratedWritingTasks(uid);
  }

  Future<void> hydrateGeneratedRoleplays() async {
    final uid = _userId;
    if (uid == null) return;
    await _hydrateGeneratedRoleplays(uid);
  }

  Future<void> hydrateGeneratedVocabularySets() async {
    final uid = _userId;
    if (uid == null) return;
    await _hydrateGeneratedVocabularySets(uid);
  }

  /// The general profile fields (goal/level/session_length/reminder_time/
  /// study-plan preferences/onboarded_at) — previously push-only, never pulled back on sign-in, so
  /// a reinstalled device kept whatever onboarding defaults it was given
  /// locally instead of the real remote profile.
  Future<void> _hydrateProfile(String uid) async {
    final rows = await _client.from('profiles').select().eq('id', uid).limit(1);
    if (rows.isEmpty) return;
    final r = rows.first;
    _db.execute(
      '''
      UPDATE profiles SET
        goal = ?, level = ?, session_length = ?, reminder_time = ?,
        preferred_days = ?, interests = ?, time_zone = ?, notification_permission_state = ?,
        onboarding_version = ?, onboarded_at = ?, updated_at = ?
      WHERE user_id = ? AND updated_at < ?
      ''',
      [
        r['goal'],
        r['level'],
        r['session_length'],
        r['reminder_time'],
        r['preferred_days'],
        r['interests'],
        r['time_zone'],
        r['notification_permission_state'] ?? 'not_requested',
        r['onboarding_version'] ?? 'v1',
        r['onboarded_at'],
        r['updated_at'],
        uid,
        r['updated_at'],
      ],
    );
  }

  Future<void> _hydrateAdaptiveCourses(String uid) async {
    final store = AdaptiveCourseStore(_db);
    final plans = await _client
        .from('adaptive_course_plans')
        .select()
        .eq('user_id', uid);
    final remotePlanIds = <String>{};
    for (final row in plans) {
      final mapped = Map<String, dynamic>.from(row);
      remotePlanIds.add(mapped['id'] as String);
      store.upsertPlanFromRemote(mapped);
    }
    store.archivePlansNotIn(uid, remotePlanIds);

    final sessions = await _client
        .from('adaptive_course_sessions')
        .select()
        .eq('user_id', uid);
    for (final row in sessions) {
      store.upsertSessionFromRemote(Map<String, dynamic>.from(row));
    }
  }

  Future<void> hydrateAdaptiveCourses() async {
    final uid = _userId;
    if (uid == null) return;
    await _hydrateAdaptiveCourses(uid);
  }

  /// Every completed practice session — the exact data `DailyGoalService`
  /// reads for streak/momentum/"this week's practice". See `syncSession`'s
  /// doc comment for why this mattered.
  Future<void> _hydrateSessions(String uid) async {
    final rows = await _client
        .from('sessions_state')
        .select()
        .eq('user_id', uid);
    for (final r in rows) {
      _db.execute(
        '''
        INSERT INTO sessions
          (id, started_at, ended_at, summary, topic, content_key, vocabulary, stage, updated_at, deleted_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
          ended_at = excluded.ended_at,
          summary = excluded.summary,
          topic = excluded.topic,
          content_key = excluded.content_key,
          vocabulary = excluded.vocabulary,
          stage = excluded.stage,
          updated_at = excluded.updated_at,
          deleted_at = excluded.deleted_at
        WHERE excluded.updated_at > sessions.updated_at
        ''',
        [
          r['id'],
          r['started_at'],
          r['ended_at'],
          r['summary'],
          r['topic'],
          r['content_key'],
          _jsonOf(r['vocabulary_json']),
          r['stage'],
          r['updated_at'],
          r['deleted_at'],
        ],
      );
    }
  }

  /// Every practice session's transcript turns — used for history review and
  /// the auto-generated review notes.
  Future<void> _hydrateMessages(String uid) async {
    final rows = await _client
        .from('chat_messages_state')
        .select()
        .eq('user_id', uid);
    for (final r in rows) {
      _db.execute(
        '''
        INSERT INTO messages (uuid, session_id, role, content, created_at)
        VALUES (?, ?, ?, ?, ?)
        ON CONFLICT(uuid) DO NOTHING
        ''',
        [r['id'], r['session_id'], r['role'], r['content'], r['created_at']],
      );
    }
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
           writing_task_json, started_at, completed_at, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
          current_stage = excluded.current_stage,
          current_item_index = excluded.current_item_index,
          stages_json = excluded.stages_json,
          reading_passage_json = excluded.reading_passage_json,
          writing_task_json = excluded.writing_task_json,
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
          r['writing_task_json'] != null
              ? _jsonOf(r['writing_task_json'])
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
          (id, title, passage_json, quiz_json, keywords_json, level_band,
           summary, topic, read_time_minutes, cover_url, music_background_url,
           audio_path, audio_mode, practice_mode, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
          title = excluded.title,
          passage_json = excluded.passage_json,
          quiz_json = excluded.quiz_json,
          keywords_json = excluded.keywords_json,
          level_band = excluded.level_band,
          summary = excluded.summary,
          topic = excluded.topic,
          read_time_minutes = excluded.read_time_minutes,
          cover_url = excluded.cover_url,
          music_background_url = excluded.music_background_url,
          audio_path = excluded.audio_path,
          audio_mode = excluded.audio_mode,
          practice_mode = excluded.practice_mode,
          updated_at = excluded.updated_at
        WHERE excluded.updated_at > generated_stories.updated_at
        ''',
        [
          r['id'],
          r['title'],
          _jsonOf(r['passage_json']),
          _jsonOf(r['quiz_json']),
          _jsonOf(r['keywords_json']),
          r['level_band'] ?? 'A2',
          r['summary'] ?? '',
          r['topic'] ?? '',
          r['read_time_minutes'] ?? 5,
          r['cover_url'],
          r['music_background_url'],
          r['audio_path'],
          r['audio_mode'],
          r['practice_mode'] ?? 'reading',
          r['created_at'],
          r['updated_at'],
        ],
      );
    }
  }

  Future<void> _hydrateStoryFavorites(String uid) async {
    final rows = await _client
        .from('story_favorites')
        .select('user_id, story_id, created_at, updated_at')
        .eq('user_id', uid);
    for (final row in rows) {
      _db.execute(
        '''INSERT INTO story_favorites (user_id, story_id, created_at, updated_at)
           VALUES (?, ?, ?, ?)
           ON CONFLICT(user_id, story_id) DO UPDATE SET
             created_at = excluded.created_at,
             updated_at = excluded.updated_at
           WHERE excluded.updated_at > story_favorites.updated_at''',
        [row['user_id'], row['story_id'], row['created_at'], row['updated_at']],
      );
    }
  }

  Future<void> _hydrateGeneratedGrammarStories(String uid) async {
    final rows = await _client
        .from('generated_grammar_stories')
        .select()
        .eq('user_id', uid);
    for (final r in rows) {
      _db.execute(
        '''
        INSERT INTO generated_grammar_stories
          (id, title, grammar_point, level_band, passage_json, quiz_json, keywords_json, explanation_json, score, cover_url, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
          title = excluded.title,
          grammar_point = excluded.grammar_point,
          level_band = excluded.level_band,
          passage_json = excluded.passage_json,
          quiz_json = excluded.quiz_json,
          keywords_json = excluded.keywords_json,
          explanation_json = excluded.explanation_json,
          score = excluded.score,
          cover_url = excluded.cover_url,
          updated_at = excluded.updated_at
        WHERE excluded.updated_at > generated_grammar_stories.updated_at
        ''',
        [
          r['id'],
          r['title'],
          r['grammar_point'],
          r['level_band'],
          _jsonOf(r['passage_json']),
          _jsonOf(r['quiz_json']),
          _jsonOf(r['keywords_json']),
          _jsonOf(r['explanation_json']),
          r['score'],
          r['cover_url'],
          r['created_at'],
          r['updated_at'],
        ],
      );
    }
  }

  Future<void> _hydrateGeneratedWritingTasks(String uid) async {
    final rows = await _client
        .from('generated_writing_tasks')
        .select()
        .eq('user_id', uid);
    for (final r in rows) {
      _db.execute(
        '''
        INSERT INTO generated_writing_tasks
          (id, task_json, level_band, cover_url, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
          task_json = excluded.task_json,
          level_band = excluded.level_band,
          cover_url = excluded.cover_url,
          updated_at = excluded.updated_at
        WHERE excluded.updated_at > generated_writing_tasks.updated_at
        ''',
        [
          r['id'],
          _jsonOf(r['task_json']),
          r['level_band'] ?? 'A2',
          r['cover_url'],
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
          (id, title, passage_json, level_band, cover_url, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
          title = excluded.title,
          passage_json = excluded.passage_json,
          level_band = excluded.level_band,
          cover_url = excluded.cover_url,
          updated_at = excluded.updated_at
        WHERE excluded.updated_at > generated_roleplays.updated_at
        ''',
        [
          r['id'],
          r['title'],
          _jsonOf(r['passage_json']),
          r['level_band'] ?? 'A1',
          r['cover_url'],
          r['created_at'],
          r['updated_at'],
        ],
      );
    }
  }

  Future<void> _hydrateSpeakingLessons() async {
    final rows = await _client.from('speaking_lessons').select();
    final store = SpeakingLessonStore(_db);
    for (final row in rows) {
      try {
        final lessonJson = _jsonOf(row['lesson_json']);
        final decoded = jsonDecode(lessonJson);
        if (decoded is! Map) continue;
        // Decode before writing so a bad shared row is isolated to itself.
        final lesson = speakingCourseLessonFromJson(
          decoded.cast<String, dynamic>(),
        );
        if (lesson.id != row['id'] ||
            lesson.mode.name != row['mode'] ||
            lesson.level != row['level_band']) {
          throw const FormatException('Speaking catalog metadata mismatch.');
        }
        store.upsertFromRemote(
          id: row['id'] as String,
          source: row['source'] as String? ?? 'generated',
          mode: row['mode'] as String,
          levelBand: row['level_band'] as String,
          title: row['title'] as String,
          fingerprint: row['fingerprint'] as String,
          lessonJson: lessonJson,
          createdAt: row['created_at'] as String,
          updatedAt: row['updated_at'] as String,
        );
      } catch (error) {
        debugPrint('Skipping invalid public Speaking lesson: $error');
      }
    }
  }

  List<SpeakingCourseLesson> _defaultSpeakingLessons() {
    final byId = <String, SpeakingCourseLesson>{};
    void add(Iterable<SpeakingCourseLesson> lessons) {
      for (final lesson in lessons) {
        byId[lesson.id] = lesson;
      }
    }

    add(SpeakingCourseCatalog.units.expand((unit) => unit.lessons));
    add(SpeakingCourseCatalog.freeTalkLessons);
    add(SpeakingCourseCatalog.roleplays);
    final byFingerprint = <String, SpeakingCourseLesson>{};
    for (final lesson in byId.values) {
      byFingerprint.putIfAbsent(
        speakingLessonFingerprint(lesson),
        () => lesson,
      );
    }
    return byFingerprint.values.toList(growable: false);
  }

  Future<void> _hydrateGeneratedVocabularySets(String uid) async {
    final rows = await _client
        .from('generated_vocabulary_sets')
        .select()
        .eq('user_id', uid);
    final store = GeneratedVocabularySetStore(_db);
    for (final r in rows) {
      store.upsertFromRemote(
        id: r['id'] as String,
        title: r['title'] as String,
        summary: r['summary'] as String? ?? '',
        topic: r['topic'] as String? ?? '',
        levelBand: r['level_band'] as String? ?? 'A1',
        entriesJson: _jsonOf(r['entries_json']),
        coverUrl: r['cover_url'] as String?,
        createdAt: r['created_at'] as String,
        updatedAt: r['updated_at'] as String,
      );
    }
  }

  /// Conflict target is `uuid` (a unique partial index, see `_migrationV15`),
  /// not the local autoincrement `id` — that id is never shared across
  /// devices, only the client-generated uuid is. Pulls tombstones too
  /// (`deleted_at`), so a delete on one device removes the note everywhere.
  Future<void> _hydrateNotes(String uid) async {
    final rows = await _client.from('notes_state').select().eq('user_id', uid);
    for (final r in rows) {
      _db.execute(
        '''
        INSERT INTO notes (uuid, tag, text, source, session_id, created_at, updated_at, deleted_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(uuid) DO UPDATE SET
          tag = excluded.tag,
          text = excluded.text,
          source = excluded.source,
          session_id = excluded.session_id,
          updated_at = excluded.updated_at,
          deleted_at = excluded.deleted_at
        WHERE excluded.updated_at > notes.updated_at
        ''',
        [
          r['id'],
          r['tag'],
          r['text'],
          r['source'] ?? 'user',
          r['session_id'],
          r['created_at'],
          r['updated_at'],
          r['deleted_at'],
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
              [
                occurredAt.split('T').first,
                payload['stage'],
                payload['summary'],
              ],
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
