import 'package:sqlite3/common.dart';

/// Versioned, forward-only migrations. Each entry runs at most once, inside a
/// transaction, and is recorded in `schema_migrations`.
///
/// Schema rules (see PILOT_PLAN.md Phase 0.1 — these make the eventual
/// Supabase/Postgres migration a mechanical copy, not a rewrite):
///  - client-generated UUID v4 TEXT primary keys, never AUTOINCREMENT
///  - nullable `user_id` on every table (becomes NOT NULL + RLS on Supabase)
///  - `created_at`/`updated_at` as ISO-8601 UTC TEXT, written by the app
///  - soft deletes via `deleted_at`
///  - history is append-only (vocab_reviews, ai_sessions, credit_usage);
///    current state (vocab_cards) is a cache derived from it
///  - TEXT/INTEGER/REAL only; JSON payloads in `*_json` TEXT columns
void runAppMigrations(CommonDatabase db) {
  db.execute('PRAGMA journal_mode=WAL');
  db.execute('''
    CREATE TABLE IF NOT EXISTS schema_migrations (
      version INTEGER PRIMARY KEY,
      applied_at TEXT NOT NULL
    )
  ''');

  final applied = db
      .select('SELECT version FROM schema_migrations')
      .map((r) => r['version'] as int)
      .toSet();

  _migrations.forEach((version, migration) {
    if (applied.contains(version)) return;
    db.execute('BEGIN');
    try {
      migration(db);
      db.execute(
        'INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)',
        [version, DateTime.now().toUtc().toIso8601String()],
      );
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  });
}

bool _tableExists(CommonDatabase db, String name) {
  return db.select(
    "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?",
    [name],
  ).isNotEmpty;
}

/// `notes` predates this versioned system (StorageService creates it inline
/// via its own `CREATE TABLE IF NOT EXISTS`), so provider-resolution order
/// decides whether that inline statement or this migration runs first —
/// every `ALTER TABLE ADD COLUMN` below has to tolerate the column already
/// existing rather than assume a fixed ordering.
bool _columnExists(CommonDatabase db, String table, String column) {
  return db
      .select('PRAGMA table_info($table)')
      .any((row) => row['name'] == column);
}

/// Ordered map of version -> migration. Never edit a shipped migration;
/// add a new version instead.
final Map<int, void Function(CommonDatabase)> _migrations = {
  1: _migrationV1,
  2: _migrationV2,
  3: _migrationV3,
  4: _migrationV4,
  5: _migrationV5,
  6: _migrationV6,
  7: _migrationV7,
  8: _migrationV8,
  9: _migrationV9,
  10: _migrationV10,
  11: _migrationV11,
  12: _migrationV12,
  13: _migrationV13,
  14: _migrationV14,
  15: _migrationV15,
  16: _migrationV16,
  17: _migrationV17,
  18: _migrationV18,
  19: _migrationV19,
  20: _migrationV20,
  21: _migrationV21,
  22: _migrationV22,
  23: _migrationV23,
  24: _migrationV24,
  25: _migrationV25,
  26: _migrationV26,
  27: _migrationV27,
  28: _migrationV28,
};

void _migrationV1(CommonDatabase db) {
  const statements = [
    // --- Learner profile (single local row until auth exists) ---
    '''
    CREATE TABLE IF NOT EXISTS profiles (
      id TEXT PRIMARY KEY,
      user_id TEXT,
      goal TEXT NOT NULL DEFAULT 'tef_canada',
      level TEXT NOT NULL DEFAULT 'zero',
      session_length TEXT NOT NULL DEFAULT 'standard',
      reminder_time TEXT,
      onboarded_at TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      deleted_at TEXT
    )
    ''',

    // --- SRS current state (cache; source of truth is vocab_reviews) ---
    '''
    CREATE TABLE IF NOT EXISTS vocab_cards (
      id TEXT PRIMARY KEY,
      user_id TEXT,
      entry_id TEXT NOT NULL UNIQUE,
      ease REAL NOT NULL DEFAULT 2.5,
      interval_days REAL NOT NULL DEFAULT 0,
      reps INTEGER NOT NULL DEFAULT 0,
      due_at TEXT,
      introduced_on TEXT,
      last_reviewed_at TEXT,
      last_grade TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      deleted_at TEXT
    )
    ''',
    'CREATE INDEX IF NOT EXISTS idx_vocab_cards_due ON vocab_cards (due_at)',

    // --- Append-only review log ---
    '''
    CREATE TABLE IF NOT EXISTS vocab_reviews (
      id TEXT PRIMARY KEY,
      user_id TEXT,
      entry_id TEXT NOT NULL,
      grade TEXT NOT NULL,
      response_type TEXT NOT NULL DEFAULT 'auto',
      session_id TEXT,
      reviewed_at TEXT NOT NULL,
      created_at TEXT NOT NULL
    )
    ''',
    'CREATE INDEX IF NOT EXISTS idx_vocab_reviews_entry ON vocab_reviews (entry_id)',
    'CREATE INDEX IF NOT EXISTS idx_vocab_reviews_at ON vocab_reviews (reviewed_at)',

    // --- Persisted, resumable Daily Path (one row per local date) ---
    '''
    CREATE TABLE IF NOT EXISTS daily_sessions (
      id TEXT PRIMARY KEY,
      user_id TEXT,
      local_date TEXT NOT NULL UNIQUE,
      planned_length TEXT NOT NULL DEFAULT 'standard',
      current_stage TEXT,
      current_item_index INTEGER NOT NULL DEFAULT 0,
      stages_json TEXT NOT NULL DEFAULT '{}',
      vocab_entry_ids_json TEXT,
      grammar_lesson_id TEXT,
      reading_passage_json TEXT,
      started_at TEXT,
      completed_at TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      deleted_at TEXT
    )
    ''',

    // --- Voice/AI sessions with real timestamps ---
    '''
    CREATE TABLE IF NOT EXISTS ai_sessions (
      id TEXT PRIMARY KEY,
      user_id TEXT,
      daily_session_id TEXT,
      stage TEXT,
      topic TEXT,
      connected_at TEXT,
      ended_at TEXT,
      learner_utterance_count INTEGER NOT NULL DEFAULT 0,
      ended_reason TEXT,
      transcript_json TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      deleted_at TEXT
    )
    ''',
    'CREATE INDEX IF NOT EXISTS idx_ai_sessions_daily ON ai_sessions (daily_session_id)',

    // --- Credit ledger (advisory locally; server-authoritative at launch) ---
    '''
    CREATE TABLE IF NOT EXISTS credit_usage (
      id TEXT PRIMARY KEY,
      user_id TEXT,
      local_date TEXT NOT NULL,
      seconds_used INTEGER NOT NULL,
      ai_session_id TEXT,
      created_at TEXT NOT NULL
    )
    ''',
    'CREATE INDEX IF NOT EXISTS idx_credit_usage_date ON credit_usage (local_date)',
  ];
  for (final sql in statements) {
    db.execute(sql);
  }

  // One-time import of legacy SRS state, only if the old table exists.
  // introduced_on is unknowable for legacy rows; approximate with the last
  // review anchor we have (due_at date) so budgets start sane, not inflated.
  if (_tableExists(db, 'vocab_srs')) {
    db.execute('''
      INSERT OR IGNORE INTO vocab_cards
        (id, entry_id, ease, interval_days, reps, due_at, introduced_on,
         last_grade, created_at, updated_at)
      SELECT
        lower(hex(randomblob(4))) || '-' || lower(hex(randomblob(2))) || '-4' ||
          substr(lower(hex(randomblob(2))), 2) || '-a' ||
          substr(lower(hex(randomblob(2))), 2) || '-' || lower(hex(randomblob(6))),
        entry_id, ease, interval_days, reps, due_at,
        CASE WHEN due_at IS NOT NULL THEN date(due_at) ELSE NULL END,
        CASE last_grade WHEN 0 THEN 'again' WHEN 1 THEN 'good' WHEN 2 THEN 'easy' END,
        datetime('now'), datetime('now')
      FROM vocab_srs
    ''');
  }
}

void _migrationV2(CommonDatabase db) {
  const statements = [
    '''
    CREATE TABLE IF NOT EXISTS installations (
      id TEXT PRIMARY KEY,
      user_id TEXT,
      platform TEXT NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      deleted_at TEXT
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS entitlements (
      id TEXT PRIMARY KEY,
      user_id TEXT,
      product_id TEXT NOT NULL,
      status TEXT NOT NULL,
      source TEXT NOT NULL,
      expires_at TEXT,
      verified_at TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      deleted_at TEXT
    )
    ''',
    'CREATE INDEX IF NOT EXISTS idx_entitlements_status ON entitlements (status)',
    '''
    CREATE TABLE IF NOT EXISTS sync_outbox (
      id TEXT PRIMARY KEY,
      user_id TEXT,
      table_name TEXT NOT NULL,
      row_id TEXT NOT NULL,
      operation TEXT NOT NULL,
      attempt_count INTEGER NOT NULL DEFAULT 0,
      last_error_code TEXT,
      processed_at TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
    ''',
    'CREATE INDEX IF NOT EXISTS idx_sync_outbox_pending ON sync_outbox (processed_at, created_at)',
    '''
    CREATE TABLE IF NOT EXISTS operational_events (
      id TEXT PRIMARY KEY,
      user_id TEXT,
      installation_id TEXT NOT NULL,
      name TEXT NOT NULL,
      properties_json TEXT NOT NULL DEFAULT '{}',
      occurred_at TEXT NOT NULL,
      uploaded_at TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
    ''',
    'CREATE INDEX IF NOT EXISTS idx_operational_events_pending ON operational_events (uploaded_at, occurred_at)',
  ];
  for (final sql in statements) {
    db.execute(sql);
  }
}

void _migrationV3(CommonDatabase db) {
  const statements = [
    '''
    CREATE TABLE IF NOT EXISTS competency_frameworks (
      id TEXT PRIMARY KEY,
      framework_version TEXT NOT NULL,
      curriculum_version TEXT NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      deleted_at TEXT
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS competencies (
      id TEXT PRIMARY KEY,
      kind TEXT NOT NULL,
      title TEXT NOT NULL,
      description TEXT NOT NULL,
      difficulty_band TEXT NOT NULL,
      prerequisite_ids_json TEXT NOT NULL DEFAULT '[]',
      target_level_label TEXT,
      exam_relevance_json TEXT NOT NULL DEFAULT '{}',
      curriculum_version TEXT NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      deleted_at TEXT
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS content_competencies (
      id TEXT PRIMARY KEY,
      content_item_id TEXT NOT NULL,
      competency_id TEXT NOT NULL,
      role TEXT NOT NULL,
      modality TEXT NOT NULL,
      weight REAL NOT NULL,
      curriculum_version TEXT NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      deleted_at TEXT
    )
    ''',
    'CREATE INDEX IF NOT EXISTS idx_content_competencies_content ON content_competencies (content_item_id)',
    'CREATE INDEX IF NOT EXISTS idx_content_competencies_competency ON content_competencies (competency_id)',
  ];
  for (final sql in statements) {
    db.execute(sql);
  }
}

void _migrationV4(CommonDatabase db) {
  const statements = [
    '''
    CREATE TABLE IF NOT EXISTS evidence_events (
      id TEXT PRIMARY KEY,
      user_id TEXT,
      plan_id TEXT,
      plan_task_id TEXT,
      session_id TEXT,
      content_item_id TEXT NOT NULL,
      competency_id TEXT NOT NULL,
      modality TEXT NOT NULL,
      support_level TEXT NOT NULL,
      correctness REAL CHECK (correctness IS NULL OR correctness BETWEEN 0 AND 1),
      score REAL CHECK (score IS NULL OR score BETWEEN 0 AND 1),
      response_time_ms INTEGER CHECK (response_time_ms IS NULL OR response_time_ms >= 0),
      attempt_number INTEGER NOT NULL DEFAULT 1 CHECK (attempt_number >= 1),
      evaluator TEXT NOT NULL,
      evaluator_confidence REAL NOT NULL CHECK (evaluator_confidence BETWEEN 0 AND 1),
      response_json TEXT,
      error_codes_json TEXT NOT NULL DEFAULT '[]',
      occurred_at TEXT NOT NULL,
      created_at TEXT NOT NULL
    )
    ''',
    'CREATE INDEX IF NOT EXISTS idx_evidence_user_competency_modality_at ON evidence_events (user_id, competency_id, modality, occurred_at)',
    'CREATE INDEX IF NOT EXISTS idx_evidence_plan_task ON evidence_events (plan_id, plan_task_id)',
    'CREATE INDEX IF NOT EXISTS idx_evidence_session ON evidence_events (session_id)',
    'CREATE INDEX IF NOT EXISTS idx_evidence_occurred_at ON evidence_events (occurred_at)',
    '''
    CREATE TABLE IF NOT EXISTS error_events (
      id TEXT PRIMARY KEY,
      user_id TEXT,
      competency_id TEXT NOT NULL,
      source_evidence_id TEXT NOT NULL,
      error_code TEXT NOT NULL,
      observed_form TEXT,
      expected_form TEXT,
      explanation TEXT,
      severity REAL NOT NULL CHECK (severity BETWEEN 0 AND 1),
      evaluator TEXT NOT NULL,
      evaluator_confidence REAL NOT NULL CHECK (evaluator_confidence BETWEEN 0 AND 1),
      resolved_by_evidence_id TEXT,
      occurred_at TEXT NOT NULL,
      created_at TEXT NOT NULL
    )
    ''',
    'CREATE INDEX IF NOT EXISTS idx_errors_source_evidence ON error_events (source_evidence_id)',
    'CREATE INDEX IF NOT EXISTS idx_errors_user_competency_at ON error_events (user_id, competency_id, occurred_at)',
    'CREATE INDEX IF NOT EXISTS idx_errors_resolution ON error_events (resolved_by_evidence_id)',
    '''
    CREATE TRIGGER IF NOT EXISTS evidence_events_no_update
    BEFORE UPDATE ON evidence_events BEGIN
      SELECT RAISE(ABORT, 'evidence_events is append-only');
    END
    ''',
    '''
    CREATE TRIGGER IF NOT EXISTS evidence_events_no_delete
    BEFORE DELETE ON evidence_events BEGIN
      SELECT RAISE(ABORT, 'evidence_events is append-only');
    END
    ''',
    '''
    CREATE TRIGGER IF NOT EXISTS error_events_no_update
    BEFORE UPDATE ON error_events BEGIN
      SELECT RAISE(ABORT, 'error_events is append-only');
    END
    ''',
    '''
    CREATE TRIGGER IF NOT EXISTS error_events_no_delete
    BEFORE DELETE ON error_events BEGIN
      SELECT RAISE(ABORT, 'error_events is append-only');
    END
    ''',
  ];
  for (final sql in statements) {
    db.execute(sql);
  }
}

void _migrationV5(CommonDatabase db) {
  const statements = [
    // --- Derived competency-by-modality belief cache. Rebuildable from
    // evidence_events at any time; never a source of truth on its own. ---
    '''
    CREATE TABLE IF NOT EXISTS learner_competency_states (
      id TEXT PRIMARY KEY,
      user_id TEXT,
      competency_id TEXT NOT NULL,
      modality TEXT NOT NULL,
      mastery_estimate REAL NOT NULL CHECK (mastery_estimate BETWEEN 0 AND 1),
      confidence REAL NOT NULL CHECK (confidence BETWEEN 0 AND 1),
      retention_strength REAL NOT NULL CHECK (retention_strength BETWEEN 0 AND 1),
      evidence_count INTEGER NOT NULL DEFAULT 0,
      transfer_status TEXT NOT NULL,
      last_observed_at TEXT,
      last_success_at TEXT,
      next_review_at TEXT,
      learner_model_type TEXT NOT NULL,
      model_version TEXT NOT NULL,
      model_state_json TEXT NOT NULL DEFAULT '{}',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      deleted_at TEXT,
      UNIQUE(user_id, competency_id, modality)
    )
    ''',
    'CREATE INDEX IF NOT EXISTS idx_learner_states_review ON learner_competency_states (next_review_at)',
    'CREATE INDEX IF NOT EXISTS idx_learner_states_competency ON learner_competency_states (competency_id, modality)',

    // --- Immutable plan snapshots. A plan is generated once; starting a
    // task locks it. Replanning creates a new row, never a rewrite. ---
    '''
    CREATE TABLE IF NOT EXISTS learning_plans (
      id TEXT PRIMARY KEY,
      user_id TEXT,
      local_date TEXT NOT NULL,
      available_minutes INTEGER NOT NULL,
      environment_json TEXT NOT NULL,
      primary_priority TEXT NOT NULL,
      explanation TEXT NOT NULL,
      planner_version TEXT NOT NULL,
      input_snapshot_json TEXT NOT NULL,
      status TEXT NOT NULL,
      replaces_plan_id TEXT,
      replan_reason TEXT,
      started_at TEXT,
      completed_at TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      deleted_at TEXT
    )
    ''',
    'CREATE INDEX IF NOT EXISTS idx_learning_plans_date ON learning_plans (local_date)',
    'CREATE INDEX IF NOT EXISTS idx_learning_plans_status ON learning_plans (status)',
    '''
    CREATE TABLE IF NOT EXISTS plan_tasks (
      id TEXT PRIMARY KEY,
      user_id TEXT,
      plan_id TEXT NOT NULL,
      sequence INTEGER NOT NULL,
      content_item_id TEXT NOT NULL,
      requirement TEXT NOT NULL,
      estimated_minutes INTEGER NOT NULL,
      reason_code TEXT NOT NULL,
      reason_detail_json TEXT NOT NULL,
      target_competency_ids_json TEXT NOT NULL,
      status TEXT NOT NULL,
      started_at TEXT,
      completed_at TEXT,
      result_summary_json TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      deleted_at TEXT
    )
    ''',
    'CREATE INDEX IF NOT EXISTS idx_plan_tasks_plan ON plan_tasks (plan_id, sequence)',
    'CREATE INDEX IF NOT EXISTS idx_plan_tasks_status ON plan_tasks (status)',

    // --- Versioned, dated assessment summaries. Never overwritten. ---
    '''
    CREATE TABLE IF NOT EXISTS assessment_snapshots (
      id TEXT PRIMARY KEY,
      user_id TEXT,
      assessment_type TEXT NOT NULL,
      summary_json TEXT NOT NULL,
      source_evidence_ids_json TEXT NOT NULL DEFAULT '[]',
      model_version TEXT NOT NULL,
      created_at TEXT NOT NULL
    )
    ''',
    'CREATE INDEX IF NOT EXISTS idx_assessment_snapshots_type ON assessment_snapshots (assessment_type, created_at)',
    '''
    CREATE TRIGGER IF NOT EXISTS assessment_snapshots_no_update
    BEFORE UPDATE ON assessment_snapshots BEGIN
      SELECT RAISE(ABORT, 'assessment_snapshots is append-only');
    END
    ''',
    '''
    CREATE TRIGGER IF NOT EXISTS assessment_snapshots_no_delete
    BEFORE DELETE ON assessment_snapshots BEGIN
      SELECT RAISE(ABORT, 'assessment_snapshots is append-only');
    END
    ''',
  ];
  for (final sql in statements) {
    db.execute(sql);
  }
}

/// v1 declared `local_date TEXT NOT NULL UNIQUE` on `daily_sessions`, which
/// blocks `resetDailySession()`'s soft-delete-then-recreate flow: the old
/// (deleted) row still holds the date, so inserting today's fresh row hits
/// the UNIQUE constraint and throws. SQLite can't drop a column constraint
/// in place, so this recreates the table with the constraint replaced by a
/// partial unique index that only applies to live rows.
void _migrationV6(CommonDatabase db) {
  const statements = [
    'ALTER TABLE daily_sessions RENAME TO daily_sessions_pre_v6',
    '''
    CREATE TABLE daily_sessions (
      id TEXT PRIMARY KEY,
      user_id TEXT,
      local_date TEXT NOT NULL,
      planned_length TEXT NOT NULL DEFAULT 'standard',
      current_stage TEXT,
      current_item_index INTEGER NOT NULL DEFAULT 0,
      stages_json TEXT NOT NULL DEFAULT '{}',
      vocab_entry_ids_json TEXT,
      grammar_lesson_id TEXT,
      reading_passage_json TEXT,
      started_at TEXT,
      completed_at TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      deleted_at TEXT
    )
    ''',
    '''
    INSERT INTO daily_sessions
      (id, user_id, local_date, planned_length, current_stage,
       current_item_index, stages_json, vocab_entry_ids_json,
       grammar_lesson_id, reading_passage_json, started_at, completed_at,
       created_at, updated_at, deleted_at)
    SELECT
      id, user_id, local_date, planned_length, current_stage,
      current_item_index, stages_json, vocab_entry_ids_json,
      grammar_lesson_id, reading_passage_json, started_at, completed_at,
      created_at, updated_at, deleted_at
    FROM daily_sessions_pre_v6
    ''',
    'DROP TABLE daily_sessions_pre_v6',
    '''
    CREATE UNIQUE INDEX IF NOT EXISTS idx_daily_sessions_active_date
    ON daily_sessions (local_date) WHERE deleted_at IS NULL
    ''',
  ];
  for (final sql in statements) {
    db.execute(sql);
  }
}

/// Future-proofing only (no redemption logic built yet — see
/// APP_STORE_AI_COMPLIANCE.md / auth work): a nullable slot for a promo/
/// referral code entered at sign-up, so adding that feature later is purely
/// additive — never a migration that has to reconcile existing rows.
void _migrationV7(CommonDatabase db) {
  db.execute('ALTER TABLE profiles ADD COLUMN referred_by_code TEXT');
}

void _migrationV8(CommonDatabase db) {
  db.execute(
    "ALTER TABLE plan_tasks ADD COLUMN modality TEXT NOT NULL DEFAULT 'reading_recognition'",
  );
}

/// Index of persisted Gemini TTS audio (lesson narration, vocab/flashcard
/// sounds, roleplay lines): points at a file under the app's persistent
/// support directory, not the OS-evictable temp dir, so a phrase is
/// synthesized once and reused across app relaunches instead of burning a
/// fresh Gemini round-trip every time it's replayed.
void _migrationV9(CommonDatabase db) {
  db.execute('''
    CREATE TABLE IF NOT EXISTS tts_audio_cache (
      cache_key TEXT PRIMARY KEY,
      content_item_id TEXT,
      voice_name TEXT NOT NULL,
      slow INTEGER NOT NULL,
      text TEXT NOT NULL,
      file_name TEXT NOT NULL,
      created_at TEXT NOT NULL
    )
  ''');
  db.execute(
    'CREATE INDEX IF NOT EXISTS idx_tts_audio_cache_content_item '
    'ON tts_audio_cache (content_item_id)',
  );
}

/// Generated mission roleplay scenes are mission-level, not learner-level —
/// the prompt going in (mission title/scenario/level/promptContext + a
/// speaking topic) is identical for every learner who gets that mission, so
/// one generated scene is reusable by everyone instead of re-prompting
/// Gemini per learner per day. A small rotating pool per mission (see
/// `GeneratedSceneCacheStore`) keeps repeat visits to the same mission
/// feeling fresh without an unbounded, ever-growing table.
void _migrationV10(CommonDatabase db) {
  db.execute('''
    CREATE TABLE IF NOT EXISTS generated_scene_cache (
      id TEXT PRIMARY KEY,
      mission_id TEXT NOT NULL,
      scene_json TEXT NOT NULL,
      times_used INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      last_used_at TEXT
    )
  ''');
  db.execute(
    'CREATE INDEX IF NOT EXISTS idx_generated_scene_cache_mission '
    'ON generated_scene_cache (mission_id)',
  );
}

/// Comma-joined topic picks from onboarding's interests step — feeds
/// personalized story topics (see `LessonAgentService.buildPersonalStory`)
/// instead of the generic rotating topic pool. Nullable/empty is a normal
/// state (skipped, or a pre-existing profile from before this question
/// existed), not an error.
void _migrationV11(CommonDatabase db) {
  db.execute('ALTER TABLE profiles ADD COLUMN interests TEXT');
}

/// A learner's personal library of AI-generated stories (replaces the old
/// browsable list of hardcoded `listening.json` exercises in the Listening
/// lab — see `GeneratedStory`/`GeneratedStoryStore`). Unlike
/// `generated_scene_cache`, this data is learner-owned, so it follows the
/// full sync-table convention (uuid pk, nullable user_id, soft delete) and
/// gets pulled back down on sign-in via SyncService.
void _migrationV12(CommonDatabase db) {
  db.execute('''
    CREATE TABLE IF NOT EXISTS generated_stories (
      id TEXT PRIMARY KEY,
      user_id TEXT,
      title TEXT NOT NULL,
      passage_json TEXT NOT NULL,
      quiz_json TEXT NOT NULL DEFAULT '[]',
      keywords_json TEXT NOT NULL DEFAULT '[]',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      deleted_at TEXT
    )
  ''');
  db.execute(
    'CREATE INDEX IF NOT EXISTS idx_generated_stories_created '
    'ON generated_stories (created_at)',
  );
}

/// A learner's personal library of AI-generated roleplay scenes — the
/// Roleplay lab's analog of `generated_stories` (see `_migrationV12`), same
/// full sync-table convention since this is per-user data too.
void _migrationV13(CommonDatabase db) {
  db.execute('''
    CREATE TABLE IF NOT EXISTS generated_roleplays (
      id TEXT PRIMARY KEY,
      user_id TEXT,
      title TEXT NOT NULL,
      passage_json TEXT NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      deleted_at TEXT
    )
  ''');
  db.execute(
    'CREATE INDEX IF NOT EXISTS idx_generated_roleplays_created '
    'ON generated_roleplays (created_at)',
  );
}

/// Freezes the Daily Path's writing prompt for the day, same treatment as
/// `reading_passage_json` (see `_migrationV6`) — without this the writing
/// stage had no persisted content at all and silently reused a hardcoded
/// fallback prompt every single time instead of generating one.
void _migrationV14(CommonDatabase db) {
  db.execute('ALTER TABLE daily_sessions ADD COLUMN writing_task_json TEXT');
}

/// `notes` (the floating notetaker's storage) was created ad hoc by
/// StorageService's own `CREATE TABLE IF NOT EXISTS`, outside this versioned
/// system, with an autoincrement int PK and no `user_id` — unsyncable as-is.
/// Rather than replace the local PK (every existing row and caller keys off
/// the int `id`), this adds a client-generated `uuid` as the sync identity
/// (nullable — legacy rows get one lazily the next time they're saved) plus
/// `source` (a note the learner typed vs. a short AI recap of a live
/// session's new vocabulary) and `session_id` (which live session it came
/// from, when applicable). Guards every column add — see [_columnExists] —
/// because StorageService may have already created this table (old or new
/// shape) before this migration gets a chance to run.
void _migrationV15(CommonDatabase db) {
  if (!_tableExists(db, 'notes')) {
    db.execute('''
      CREATE TABLE notes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT,
        user_id TEXT,
        tag TEXT,
        text TEXT NOT NULL,
        source TEXT NOT NULL DEFAULT 'user',
        session_id TEXT,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        updated_at TEXT NOT NULL DEFAULT (datetime('now')),
        times_shown INTEGER NOT NULL DEFAULT 0,
        deleted_at TEXT
      )
    ''');
    db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_notes_uuid ON notes (uuid) WHERE uuid IS NOT NULL',
    );
    return;
  }
  if (!_columnExists(db, 'notes', 'uuid')) {
    db.execute('ALTER TABLE notes ADD COLUMN uuid TEXT');
  }
  if (!_columnExists(db, 'notes', 'user_id')) {
    db.execute('ALTER TABLE notes ADD COLUMN user_id TEXT');
  }
  if (!_columnExists(db, 'notes', 'source')) {
    db.execute(
      "ALTER TABLE notes ADD COLUMN source TEXT NOT NULL DEFAULT 'user'",
    );
  }
  if (!_columnExists(db, 'notes', 'session_id')) {
    db.execute('ALTER TABLE notes ADD COLUMN session_id TEXT');
  }
  if (!_columnExists(db, 'notes', 'deleted_at')) {
    db.execute('ALTER TABLE notes ADD COLUMN deleted_at TEXT');
  }
  db.execute(
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_notes_uuid ON notes (uuid) WHERE uuid IS NOT NULL',
  );
}

/// A learner's personal library of AI-generated grammar practice — the
/// Grammar lab's analog of `generated_stories` (see `_migrationV12`). Every
/// story generated by "Practice a tense" is saved here so it has real
/// history, same as the Story/Listening library, instead of vanishing the
/// moment the learner leaves the reader screen.
void _migrationV16(CommonDatabase db) {
  db.execute('''
    CREATE TABLE IF NOT EXISTS generated_grammar_stories (
      id TEXT PRIMARY KEY,
      user_id TEXT,
      title TEXT NOT NULL,
      grammar_point TEXT NOT NULL,
      level_band TEXT NOT NULL,
      passage_json TEXT NOT NULL,
      quiz_json TEXT NOT NULL DEFAULT '[]',
      keywords_json TEXT NOT NULL DEFAULT '[]',
      explanation_json TEXT NOT NULL DEFAULT '{}',
      score REAL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      deleted_at TEXT
    )
  ''');
  db.execute(
    'CREATE INDEX IF NOT EXISTS idx_generated_grammar_stories_created '
    'ON generated_grammar_stories (created_at)',
  );
}

/// `sessions`/`messages` predate this versioned system (StorageService
/// creates them inline via its own `CREATE TABLE IF NOT EXISTS`, same
/// situation `notes` was in before `_migrationV15`) — this adds the columns
/// needed to sync them to Supabase. Before this migration, NEITHER table had
/// any sync coverage at all: `sessions` is exactly what streak/momentum/
/// "this week's practice" reads (`DailyGoalService`), so a reinstall lost
/// all of it silently — this is the fix for that. `messages` is every
/// practice session's transcript (used for history review and the
/// auto-generated notes), also previously unsynced.
void _migrationV17(CommonDatabase db) {
  // Unlike `notes` (which StorageService always creates before any query),
  // `sessions`/`messages` may not exist yet at all when this runs — provider
  // resolution order doesn't guarantee StorageService's own inline
  // `CREATE TABLE IF NOT EXISTS` has run first. Create the full shape here
  // too, so this migration is correct standalone; StorageService's own
  // create is then just a no-op against the same shape.
  if (!_tableExists(db, 'sessions')) {
    db.execute('''
      CREATE TABLE sessions (
        id TEXT PRIMARY KEY,
        user_id TEXT,
        started_at TEXT NOT NULL,
        ended_at TEXT,
        summary TEXT,
        topic TEXT,
        vocabulary TEXT DEFAULT '[]',
        stage TEXT,
        updated_at TEXT NOT NULL DEFAULT (datetime('now')),
        deleted_at TEXT
      )
    ''');
  } else {
    if (!_columnExists(db, 'sessions', 'user_id')) {
      db.execute('ALTER TABLE sessions ADD COLUMN user_id TEXT');
    }
    if (!_columnExists(db, 'sessions', 'updated_at')) {
      // SQLite rejects a non-constant default (`datetime('now')`) on
      // `ALTER TABLE ADD COLUMN` — that's only allowed in `CREATE TABLE`.
      // Add it nullable with no default, then backfill existing rows with
      // one fixed timestamp (every future write always sets a real value).
      db.execute('ALTER TABLE sessions ADD COLUMN updated_at TEXT');
      db.execute(
        "UPDATE sessions SET updated_at = ? WHERE updated_at IS NULL",
        [DateTime.now().toUtc().toIso8601String()],
      );
    }
    if (!_columnExists(db, 'sessions', 'deleted_at')) {
      db.execute('ALTER TABLE sessions ADD COLUMN deleted_at TEXT');
    }
  }

  if (!_tableExists(db, 'messages')) {
    db.execute('''
      CREATE TABLE messages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT,
        user_id TEXT,
        session_id TEXT NOT NULL,
        role TEXT NOT NULL,
        content TEXT NOT NULL,
        created_at TEXT NOT NULL DEFAULT (datetime('now'))
      )
    ''');
  } else {
    if (!_columnExists(db, 'messages', 'uuid')) {
      db.execute('ALTER TABLE messages ADD COLUMN uuid TEXT');
    }
    if (!_columnExists(db, 'messages', 'user_id')) {
      db.execute('ALTER TABLE messages ADD COLUMN user_id TEXT');
    }
  }
  db.execute(
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_messages_uuid ON messages (uuid) WHERE uuid IS NOT NULL',
  );
}

/// Stable course identity for the new published Speak curriculum. Existing
/// sessions remain valid with a null key; new roadmap/roleplay sessions write
/// one so completion can follow content across devices and catalog versions.
void _migrationV18(CommonDatabase db) {
  if (!_tableExists(db, 'sessions')) return;
  if (!_columnExists(db, 'sessions', 'content_key')) {
    db.execute('ALTER TABLE sessions ADD COLUMN content_key TEXT');
  }
  db.execute(
    'CREATE INDEX IF NOT EXISTS idx_sessions_content_key ON sessions (content_key)',
  );
}

/// Adds the presentation metadata for the Readle-inspired short-book
/// library. The passage remains the source of truth for the lesson itself;
/// these columns only let the home screen render a stable book card and reuse
/// the one generated cover without another model call.
void _migrationV19(CommonDatabase db) {
  if (!_tableExists(db, 'generated_stories')) return;
  if (!_columnExists(db, 'generated_stories', 'level_band')) {
    db.execute(
      "ALTER TABLE generated_stories ADD COLUMN level_band TEXT NOT NULL DEFAULT 'A2'",
    );
  }
  if (!_columnExists(db, 'generated_stories', 'summary')) {
    db.execute(
      "ALTER TABLE generated_stories ADD COLUMN summary TEXT NOT NULL DEFAULT ''",
    );
  }
  if (!_columnExists(db, 'generated_stories', 'topic')) {
    db.execute(
      "ALTER TABLE generated_stories ADD COLUMN topic TEXT NOT NULL DEFAULT ''",
    );
  }
  if (!_columnExists(db, 'generated_stories', 'read_time_minutes')) {
    db.execute(
      "ALTER TABLE generated_stories ADD COLUMN read_time_minutes INTEGER NOT NULL DEFAULT 5",
    );
  }
  if (!_columnExists(db, 'generated_stories', 'cover_url')) {
    db.execute('ALTER TABLE generated_stories ADD COLUMN cover_url TEXT');
  }
}

/// Separates the independent reading and listening shelves without duplicating
/// passage, quiz, keyword, or cover storage. Existing rows are treated as
/// reading so they remain visible to learners after the migration.
void _migrationV20(CommonDatabase db) {
  if (!_tableExists(db, 'generated_stories')) return;
  if (!_columnExists(db, 'generated_stories', 'practice_mode')) {
    db.execute(
      "ALTER TABLE generated_stories ADD COLUMN practice_mode TEXT NOT NULL DEFAULT 'reading'",
    );
  }
  db.execute(
    "CREATE INDEX IF NOT EXISTS idx_generated_stories_mode_created ON generated_stories (practice_mode, created_at)",
  );
}

/// Adds the generated grammar-story cover URL used by the compact grammar
/// story shelf. The artwork is optional: the grammar lesson remains entirely
/// text-first when cover generation or storage is unavailable.
void _migrationV21(CommonDatabase db) {
  if (!_tableExists(db, 'generated_grammar_stories')) return;
  if (!_columnExists(db, 'generated_grammar_stories', 'cover_url')) {
    db.execute(
      'ALTER TABLE generated_grammar_stories ADD COLUMN cover_url TEXT',
    );
  }
}

/// Stores AI-generated writing prompts so the Writing lab has the same
/// reopenable library contract as Reading, Listening, and Grammar.
void _migrationV22(CommonDatabase db) {
  db.execute('''
    CREATE TABLE IF NOT EXISTS generated_writing_tasks (
      id TEXT PRIMARY KEY,
      task_json TEXT NOT NULL,
      level_band TEXT NOT NULL DEFAULT 'A2',
      cover_url TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      deleted_at TEXT
    )
  ''');
  db.execute(
    'CREATE INDEX IF NOT EXISTS idx_generated_writing_tasks_created '
    'ON generated_writing_tasks (created_at)',
  );
}

/// Adds optional learner-scoped artwork to saved roleplay scenes. The scene
/// itself remains usable if cover generation or private storage is unavailable.
void _migrationV23(CommonDatabase db) {
  if (!_tableExists(db, 'generated_roleplays')) return;
  if (!_columnExists(db, 'generated_roleplays', 'cover_url')) {
    db.execute('ALTER TABLE generated_roleplays ADD COLUMN cover_url TEXT');
  }
}

/// Stores learner-owned starter and generated vocabulary libraries. The
/// entries stay as JSON so the local schema remains compatible with the
/// Supabase jsonb payload and can evolve without a destructive migration.
void _migrationV24(CommonDatabase db) {
  db.execute('''
    CREATE TABLE IF NOT EXISTS generated_vocabulary_sets (
      id TEXT PRIMARY KEY,
      user_id TEXT,
      title TEXT NOT NULL,
      summary TEXT NOT NULL DEFAULT '',
      topic TEXT NOT NULL DEFAULT '',
      level_band TEXT NOT NULL DEFAULT 'A1',
      entries_json TEXT NOT NULL DEFAULT '[]',
      cover_url TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      deleted_at TEXT
    )
  ''');
  db.execute(
    'CREATE INDEX IF NOT EXISTS idx_generated_vocabulary_sets_created '
    'ON generated_vocabulary_sets (created_at)',
  );
}

/// Dedicated local history for exam-readiness practice. This is intentionally
/// separate from the course-generated content tables so an exam attempt never
/// appears in Reading or Listening libraries.
void _migrationV25(CommonDatabase db) {
  db.execute('''
    CREATE TABLE IF NOT EXISTS exam_practice_attempts (
      id TEXT PRIMARY KEY,
      user_id TEXT,
      exam_name TEXT NOT NULL,
      level_band TEXT NOT NULL,
      skill TEXT NOT NULL,
      content_json TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'in_progress',
      score INTEGER,
      total INTEGER,
      created_at TEXT NOT NULL,
      completed_at TEXT,
      updated_at TEXT NOT NULL,
      deleted_at TEXT
    )
  ''');
  db.execute(
    'CREATE INDEX IF NOT EXISTS idx_exam_practice_attempts_scope '
    'ON exam_practice_attempts (exam_name, level_band, skill, created_at)',
  );
}

/// Stores the learner's study-plan inputs separately from content defaults.
/// Existing learners keep safe weekday/default values until they revisit the
/// updated onboarding or Settings.
void _migrationV26(CommonDatabase db) {
  if (!_columnExists(db, 'profiles', 'preferred_days')) {
    db.execute(
      "ALTER TABLE profiles ADD COLUMN preferred_days TEXT NOT NULL DEFAULT 'mon,tue,wed,thu,fri'",
    );
  }
  if (!_columnExists(db, 'profiles', 'time_zone')) {
    db.execute('ALTER TABLE profiles ADD COLUMN time_zone TEXT');
  }
  if (!_columnExists(db, 'profiles', 'notification_permission_state')) {
    db.execute(
      "ALTER TABLE profiles ADD COLUMN notification_permission_state TEXT NOT NULL DEFAULT 'not_requested'",
    );
  }
  if (!_columnExists(db, 'profiles', 'onboarding_version')) {
    db.execute(
      "ALTER TABLE profiles ADD COLUMN onboarding_version TEXT NOT NULL DEFAULT 'v1'",
    );
  }
}

/// Adaptive course plans replace the old one-size-fits-all catalog for new
/// learners. A plan contains lightweight, validated session specifications;
/// the existing practice engines generate the full story/quiz/audio/artwork
/// only when a learner opens a session.
void _migrationV27(CommonDatabase db) {
  db.execute('''
    CREATE TABLE IF NOT EXISTS adaptive_course_plans (
      id TEXT PRIMARY KEY,
      user_id TEXT,
      goal TEXT NOT NULL,
      level TEXT NOT NULL,
      profile_fingerprint TEXT NOT NULL,
      version INTEGER NOT NULL DEFAULT 1,
      status TEXT NOT NULL DEFAULT 'active',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      deleted_at TEXT
    )
  ''');
  db.execute(
    'CREATE INDEX IF NOT EXISTS idx_adaptive_course_plans_active '
    "ON adaptive_course_plans (status, version, created_at)",
  );
  db.execute('''
    CREATE TABLE IF NOT EXISTS adaptive_course_sessions (
      id TEXT PRIMARY KEY,
      user_id TEXT,
      plan_id TEXT NOT NULL,
      content_key TEXT NOT NULL,
      sequence INTEGER NOT NULL,
      level TEXT NOT NULL,
      unit INTEGER NOT NULL,
      unit_title TEXT NOT NULL,
      title TEXT NOT NULL,
      subtitle TEXT NOT NULL,
      competency TEXT NOT NULL,
      context TEXT NOT NULL,
      primary_skill TEXT NOT NULL,
      supporting_skills_json TEXT NOT NULL DEFAULT '[]',
      grammar_focus_json TEXT NOT NULL DEFAULT '[]',
      success_criteria_json TEXT NOT NULL DEFAULT '[]',
      estimated_minutes INTEGER NOT NULL DEFAULT 10,
      profile_fingerprint TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'planned',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      completed_at TEXT,
      deleted_at TEXT
    )
  ''');
  db.execute(
    'CREATE INDEX IF NOT EXISTS idx_adaptive_course_sessions_plan '
    'ON adaptive_course_sessions (plan_id, sequence)',
  );
  db.execute(
    'CREATE INDEX IF NOT EXISTS idx_adaptive_course_sessions_content '
    'ON adaptive_course_sessions (content_key, status)',
  );
}

/// One bounded, device-local premium preview per local calendar day. The
/// preview is intentionally shared across premium areas: a learner chooses
/// whether today's useful session is reading, listening, writing, exam prep,
/// or the course. A subscription bypasses this table entirely.
void _migrationV28(CommonDatabase db) {
  db.execute('''
    CREATE TABLE IF NOT EXISTS premium_preview_usage (
      usage_date TEXT PRIMARY KEY,
      area TEXT NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      deleted_at TEXT
    )
  ''');
}
