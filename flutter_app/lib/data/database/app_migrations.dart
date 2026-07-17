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

/// Ordered map of version -> migration. Never edit a shipped migration;
/// add a new version instead.
final Map<int, void Function(CommonDatabase)> _migrations = {
  1: _migrationV1,
  2: _migrationV2,
  3: _migrationV3,
  4: _migrationV4,
  5: _migrationV5,
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
