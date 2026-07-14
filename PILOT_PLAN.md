# ParleSprint — Paid Pilot Readiness Plan

Goal: one trustworthy daily loop that a paying beginner can rely on — learn a little,
use it, speak it with Marie, resume exactly where they stopped — on iOS first, with
Android and Flutter Web able to follow without rework.

This plan is ordered. Each phase has acceptance criteria. Do not start a later phase
while an earlier phase's P0 items are open. Auth/IAP is deliberately LAST (Phase 5) —
but the data layer is built Supabase-shaped from Phase 1 so migration is a copy, not a rewrite.

---

## Phase 0 — Foundations (data + design wiring) — do this first

Everything else builds on these two layers. Doing them first prevents rework.

### 0.1 New local database schema (Supabase-migration ready)

Rules that make local SQLite → Supabase/Postgres a mechanical copy later:

- **Client-generated UUID (v4) primary keys** — never AUTOINCREMENT ints. Rows keep
  their identity when uploaded; no ID remapping.
- **`user_id TEXT` column on every table**, nullable for now (single local user).
  On migration it becomes `NOT NULL REFERENCES auth.users` with RLS policies.
- **`created_at` / `updated_at` TEXT (ISO-8601 UTC)** on every table, set by the app.
- **`deleted_at` for soft deletes** — sync never needs tombstone reconstruction.
- **Append-only event tables** for anything that is history (reviews, sessions,
  credit usage). Facts are immutable; derived state is computed or cached.
- **A `schema_migrations` table** with versioned, forward-only migrations in Dart
  (`lib/data/database/migrations/`). Same migration files become the Supabase SQL
  migrations later (SQLite and Postgres dialect differences isolated per file).
- Types discipline: TEXT/INTEGER/REAL only, ISO strings for dates, 0/1 for bools,
  JSON as TEXT in `*_json` columns — all map 1:1 to Postgres (timestamptz, boolean, jsonb).

#### Tables

```sql
-- Versioning
CREATE TABLE schema_migrations (version INTEGER PRIMARY KEY, applied_at TEXT NOT NULL);

-- Learner profile (one row locally; becomes per-user on Supabase)
CREATE TABLE profiles (
  id TEXT PRIMARY KEY,                -- uuid
  user_id TEXT,                       -- null until auth exists
  goal TEXT NOT NULL DEFAULT 'tef_canada',   -- tef_canada | everyday | unsure
  level TEXT NOT NULL DEFAULT 'zero',        -- zero | basics | conversational | unsure
  session_length TEXT NOT NULL DEFAULT 'standard', -- quick | standard | deep
  reminder_time TEXT,                 -- 'HH:mm' or null
  onboarded_at TEXT,
  created_at TEXT NOT NULL, updated_at TEXT NOT NULL
);

-- SRS card state (current state; derived from reviews but cached for speed)
CREATE TABLE vocab_cards (
  id TEXT PRIMARY KEY,                -- uuid
  user_id TEXT,
  entry_id TEXT NOT NULL UNIQUE,      -- content id (stable across devices)
  ease REAL NOT NULL DEFAULT 2.5,
  interval_days REAL NOT NULL DEFAULT 0,
  reps INTEGER NOT NULL DEFAULT 0,
  due_at TEXT,
  introduced_on TEXT,                 -- date first graded — fixes new-card budget bug
  last_reviewed_at TEXT,
  created_at TEXT NOT NULL, updated_at TEXT NOT NULL
);

-- Append-only review log (source of truth for pacing, progress, debugging)
CREATE TABLE vocab_reviews (
  id TEXT PRIMARY KEY,                -- uuid
  user_id TEXT,
  entry_id TEXT NOT NULL,
  grade TEXT NOT NULL,                -- again | hard | good | easy
  response_type TEXT NOT NULL,        -- unaided | hinted | self_reported | auto
  session_id TEXT,                    -- FK daily_sessions.id
  reviewed_at TEXT NOT NULL,
  created_at TEXT NOT NULL
);

-- The Daily Path — persisted, resumable (fixes P0.1)
CREATE TABLE daily_sessions (
  id TEXT PRIMARY KEY,                -- uuid
  user_id TEXT,
  local_date TEXT NOT NULL,           -- 'YYYY-MM-DD' in device tz, UNIQUE per user
  planned_length TEXT NOT NULL,       -- quick | standard | deep
  current_stage TEXT,                 -- vocab | grammar | listening | writing | speaking
  current_item_index INTEGER NOT NULL DEFAULT 0,
  stages_json TEXT NOT NULL,          -- per-stage: status(pending|active|paused|completed|skipped), result summary
  vocab_entry_ids_json TEXT,          -- today's fixed word list (never regenerated mid-day)
  grammar_lesson_id TEXT,
  reading_passage_json TEXT,          -- fixed passage content for the day
  started_at TEXT, completed_at TEXT,
  created_at TEXT NOT NULL, updated_at TEXT NOT NULL
);

-- Voice/AI sessions (fixes zero-duration bug; feeds credit metering later)
CREATE TABLE ai_sessions (
  id TEXT PRIMARY KEY,
  user_id TEXT,
  daily_session_id TEXT,
  stage TEXT,                         -- speaking | vocab | grammar | listening | null(free talk)
  topic TEXT,
  connected_at TEXT,                  -- real connection time
  ended_at TEXT,                      -- real end time
  learner_utterance_count INTEGER NOT NULL DEFAULT 0,
  ended_reason TEXT,                  -- completed | cancelled | disconnected | error | credit_exhausted
  transcript_json TEXT,
  created_at TEXT NOT NULL, updated_at TEXT NOT NULL
);

-- Credit ledger (local now for UX; server-authoritative copy at launch)
CREATE TABLE credit_usage (
  id TEXT PRIMARY KEY,
  user_id TEXT,
  local_date TEXT NOT NULL,
  seconds_used INTEGER NOT NULL,
  ai_session_id TEXT,
  created_at TEXT NOT NULL
);

-- Keep: lesson_progress, writing_submissions, mistake_tags, session_diary —
-- rebuilt with the same uuid/user_id/timestamps pattern.
-- daily_activity is REPLACED by derivation from vocab_reviews/ai_sessions/daily_sessions
-- (fixes fabricated-minutes bug: time comes from real timestamps, accumulated not replaced).
```

Migration path to Supabase later: same tables in Postgres, `user_id` becomes NOT NULL,
RLS `user_id = auth.uid()` on every table, one-time upload of local rows stamped with
the new user_id, then a thin sync layer (push on write + pull on login; last-write-wins
by `updated_at` is sufficient for single-learner data).

### 0.2 Platform-adaptive design wiring (iOS / Android / Web)

Current state: `theme.dart` is one hardcoded class; 175+ Material-only usages; zero
adaptation. Build this three-layer wiring so **screens never mention a platform**:

```
Layer 1  DesignTokens        pure constants: color, type scale, spacing, radius,
         (tokens.dart)       durations/curves — the Passeport identity. Platform-free.
Layer 2  AppTheme            maps tokens → ThemeData/CupertinoThemeData; owns
         (app_theme.dart)    PageTransitionsTheme (Cupertino on iOS, Zoom on Android,
                             fade on web), scroll physics, splash/ripple config
                             (NoSplash on iOS/web), density & breakpoints for web.
Layer 3  Adaptive widgets    PSButton, PSSwitch, PSDialog, PSActionSheet, PSNavPage,
         (widgets/adaptive/) PSListTile, PSIcon (SF Symbols style on iOS, Material
                             Symbols on Android/web) — one call site, per-platform render.
```

- All navigation goes through one `AppRouter.push()` helper → `CupertinoPageRoute` on
  iOS (edge-swipe back preserved), platform default elsewhere. No raw
  `MaterialPageRoute` in screens (lint-enforced: add a `custom_lint`/grep CI check).
- Web: breakpoints in tokens (`compact <600 / medium <1024 / expanded`), Daily Path
  card constrained to `maxWidth: 560` centered; nav becomes NavigationRail at medium+.
- Haptics behind `PSHaptics` (no-op on web).
- The two Claude skills (design-system, ui-patterns) stay the source of truth; this
  wiring is their code counterpart. Future design changes = edit tokens + skills, not screens.

**Acceptance (Phase 0):** app boots on iOS/Android/web with new store; old data
auto-migrated (one-time importer from legacy tables); all existing screens still work
through the compat layer; `flutter analyze` clean.

---

## Phase 1 — Daily Path correctness (P0.1–P0.5)

The product IS this loop. Fix in this order:

1. **PathwayCoordinator** (new: `lib/flow/pathway_coordinator.dart`) — the ONLY owner
   of stage navigation and completion. Each stage screen is opened with
   `final result = await router.push<StageResult>(...)` and returns a **typed result
   exactly once**. No parent callbacks invoked from child screens, no `Navigator.pop`
   of other routes, no navigation from inside completion callbacks. (P0.5)
2. **Persist every transition** to `daily_sessions` (P0.1): stage start, item index
   advance, pause, complete. Relaunch → Home shows "Continue today's session —
   Vocabulary 3 of 5" and reopens the exact card. Content for the day is fixed at
   first assembly (word list, passage) and never regenerated.
3. **Completion semantics** (P0.2, P0.3): `dispose()` never reports results. States:
   completed / paused / abandoned. Objective thresholds:
   - vocab: ≥ configured cards attempted; grammar: ≥ N drills answered
   - listening: passage finished + ≥1 check
   - speaking: connection succeeded AND ≥1 learner utterance AND ≥30s
   `SessionScreen` returns `{completed, durationSeconds, utteranceCount, endedReason}`.
   Disconnect → save paused + offer Reconnect / Continue without voice / Finish later.
4. **One Continue button** (P0.4): Home card = "Today's French — 12 minutes" +
   dominant **Continue**. Stage list collapses to an outline; only current stage has
   the primary action; future stages labelled "Later" (visibly not tappable);
   completed stages reviewable; explicit "Skip for today" where sensible.
5. **Real timestamps**: `ai_sessions.connected_at/ended_at` from actual events;
   Progress derives speaking minutes from them (fixes zero-duration history).

**Acceptance:** force-quit mid-card → relaunch resumes same card. Airplane mode in any
stage → paused, not completed. Cancelling speaking immediately → not completed.
All five stages completable start-to-finish through the coordinator on all 3 platforms.

---

## Phase 2 — Vocab pacing + SRS honesty (P0.6–P0.9)

1. **Humane defaults** (P0.6): day-one beginner 3 new words; normal 3–5 new;
   reviews 3–8; guided-path hard cap ~10 items total. Session-length setting drives
   budget (quick/standard/deep), not a raw card-count setting. Labs stay uncapped.
2. **One queue policy** (P0.7): delete the `newCap=25` fork; `dailyMixedQueue` and
   `buildQueue` share `QueuePolicy{reviewBudget, newBudget}` derived from profile.
3. **`introduced_on` + `vocab_reviews`** (P0.8): budget counts
   `WHERE introduced_on = today`; all pacing/progress derives from the review log.
4. **No silent "good"** (P0.9): grades only from evidence — unaided correct → good;
   hinted → hard; wrong/skip → again; ambiguous → 3 big self-grade buttons
   (Again / Almost / Got it). Adaptive passes: new word full 4-step, familiar 1 recall
   (expand only if wrong), mature fast recall.
5. **Again-loop**: failed cards re-enter the same session's queue until passed
   (re-query `due_at <= now` at queue end).

**Acceptance:** unit tests for intervals, budgets, introduced-on counting, again-loop;
a simulated "fails everything" learner sees ≤ humane totals, never a flood.

---

## Phase 3 — Onboarding + product surface

1. **3-step onboarding** (skippable, <60s): goal → level+session length (one screen)
   → first success (3 words, hear them, mic permission asked only right before first
   repetition, 30–60s Marie exchange, honest recap). Writes `profiles`; level gates
   Marie's English/French ratio; goal replaces hardcoded "CLB 7 · TEF Canada".
2. **4 tabs**: Today / Practice / Progress / Settings. Mocks tab hidden for pilot;
   History+Notes fold under Today/Progress.
3. **Settings cleanup**: goal, session length, voice speed, reminder, privacy,
   purchase status + restore (stub), help/feedback, version. All provider/model/key UI
   behind a developer flag (`kDebugMode` or hidden toggle).
4. **De-gamify**: streak flames → "N sessions this month" + weekly "This week you can
   now: …" evidence card (from vocab_reviews + ai_sessions). Calm single daily
   reminder at chosen time; permission asked after 2 completed sessions, never at launch.
5. **Branding**: ParleSprint everywhere (app name, headers, About).

**Acceptance:** 5 fresh users pass the corridor test — understand who it's for, pick
level/time, learn 3 words, speak once with Marie, see honest recap, resume next day —
with zero verbal instructions.

---

## Phase 4 — Native feel + platform polish (uses Phase 0 wiring)

Migrate screens through the adaptive layer in this order: onboarding → Home/Daily Path
→ live call → vocab/grammar/listening/writing stages → Progress → Settings.
Per design.md skills: Cupertino routes + edge-swipe everywhere on iOS, adaptive
dialogs/sheets/switches/pickers, no ink ripples on iOS, bouncing scroll physics,
44pt targets, Dynamic Type test pass, portrait-only on iPhone for pilot.
Android: Material 3 defaults from the same tokens. Web: responsive breakpoints,
keyboard focus states, no haptic calls.

**Acceptance:** side-by-side with a native iOS app, no ripple/route/dialog tells;
`flutter build` succeeds for ios/apk/web from one codebase.

---

## Phase 5 — Pre-launch infrastructure (just before pilot invites)

Deliberately last; the app runs local-first until here.

1. **Supabase project**: same schema, RLS everywhere; Sign in with Apple (+ Google on
   Android/web). One-time migrator uploads local rows with new user_id; then thin
   sync (push-on-write, pull-on-login, last-write-wins by updated_at).
2. **Edge function AI proxy**: holds Gemini/OpenRouter keys (removed from binary);
   verifies entitlement; checks credit ledger before opening a Live session; meters
   server-side while streaming; writes `credit_usage`. Client shows calm credit UX:
   minutes in Settings + call sheet, quiet 10-min and 5-min notices, Marie finishes
   her sentence at zero, non-AI study always available.
3. **Founding Learner Pass**: non-consumable IAP via RevenueCat (`purchases_flutter`),
   restore purchase, server-verified entitlement, graceful "verification unavailable"
   state. Copy: one-time $10, first 25–50 learners, up to 60 AI min/day subject to
   reasonable use and provider availability, core updates included — not bare "forever".
4. **Observability**: Sentry (crash + session-connect failures), pilot dashboard
   (daily session starts, connect success rate, resume success, credit usage).
5. **Compliance**: privacy policy, terms, AI-processing disclosure, data deletion,
   support contact in Settings.

**Acceptance:** key extraction from IPA yields nothing usable; device-clock changes
don't alter credits; purchase → delete app → reinstall → restore works; a second
device sees the same progress after sign-in.

---

## Phase 6 — Test suite + pilot acceptance gate

Automated (replaces the `1+1==2` placeholder):
- SRS: intervals, budgets, introduced-on, again-loop, empty queue
- Daily Path: persist/resume every stage, cancel ≠ complete, disconnect ≠ complete,
  speaking threshold, full-path navigation integration test
- Failure paths: missing token, permission denied, AI timeout/retry, credit boundary
- Data: migrations up from every historical version; legacy import
- Purchases (Phase 5): restore, invalid/expired entitlement

Manual chaos pass before invites: airplane mode per stage, provider timeout, mic
denied / interrupted by phone call, background 10 min, force-quit mid-card, credits
exhausted mid-conversation, verification down, XL Dynamic Type, small iPhone (SE), web
narrow window.

**Go/no-go:** all 12 corridor-test journeys calm and recoverable for 5 fresh users →
invite the paid founding cohort. Personally talk to each learner after day 1, 3, 7.

---

## Explicitly deferred (do not build for pilot)

Full mock exams · social/leaderboards/badges/confetti · model-choice UI for users ·
big content expansion · advanced analytics · Android/web *feature* parity beyond
"builds and runs correctly" if it slows iOS pilot reliability.
